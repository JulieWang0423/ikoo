import SwiftUI
import SwiftData
import UserNotifications

@main
struct IkooApp: App {
    let container: ModelContainer
    private let notificationDelegate = NotificationDelegate()

    init() {
        let schema = Schema([SavedPin.self])
        do {
            // Store lives in the App Group container from day one so the
            // share extension can gain read access later without a migration.
            let config = ModelConfiguration(schema: schema, url: AppGroup.storeURL, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            container = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        #if DEBUG
        seedTestPinIfRequested()
        #endif
        // Must run on every launch, including background relaunches from
        // region crossings / significant-location-changes.
        GeofenceManager.shared.start(container: container)
    }

    #if DEBUG
    /// Automated-test hook: IKOO_SEED_TEST_PIN=1 inserts a known pin so the
    /// geofence loop can be exercised without driving the UI.
    private func seedTestPinIfRequested() {
        guard ProcessInfo.processInfo.environment["IKOO_SEED_TEST_PIN"] == "1" else { return }
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<SavedPin>())) ?? []
        guard existing.isEmpty else { return }
        let pin = SavedPin(
            name: "The Rotunda",
            latitude: 38.0356,
            longitude: -78.5034,
            address: "1826 University Ave, Charlottesville, VA",
            city: "Charlottesville",
            sourceApp: "tiktok"
        )
        context.insert(pin)

        // IKOO_SEED_TEST_EVENTS=1 additionally inserts one expired and one
        // upcoming event to exercise the sweep and "Happening soon" logic.
        if ProcessInfo.processInfo.environment["IKOO_SEED_TEST_EVENTS"] == "1" {
            let pastEvent = SavedPin(
                name: "Fridays After Five (last week)",
                latitude: 38.0293, longitude: -78.4790,
                city: "Charlottesville", kind: .event,
                sourceApp: "rednote",
                eventStart: Date().addingTimeInterval(-8 * 24 * 3600),
                eventEnd: Date().addingTimeInterval(-7 * 24 * 3600)
            )
            let upcomingEvent = SavedPin(
                name: "IX Art Park Night Market",
                latitude: 38.0250, longitude: -78.4839,
                city: "Charlottesville", kind: .event,
                sourceApp: "rednote",
                eventStart: Date().addingTimeInterval(2 * 24 * 3600),
                eventEnd: Date().addingTimeInterval(2 * 24 * 3600 + 4 * 3600)
            )
            context.insert(pastEvent)
            context.insert(upcomingEvent)
        }
        try? context.save()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

/// Cross-cutting UI state (notification deep-links).
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var selectedPinID: UUID?
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let idString = response.notification.request.content.userInfo["pinID"] as? String,
           let id = UUID(uuidString: idString) {
            DispatchQueue.main.async {
                AppState.shared.selectedPinID = id
            }
        }
        completionHandler()
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var pendingIngests: [IngestItem] = []
    @State private var currentIngest: IngestItem?
    @State private var selectedTab = {
        #if DEBUG
        // Automated-test hook: open directly on a given tab.
        if ProcessInfo.processInfo.environment["IKOO_DEBUG_TAB"] == "saved" { return 1 }
        #endif
        return 0
    }()

    var body: some View {
        TabView(selection: $selectedTab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(0)
            PinListScreen()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(1)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                sweepExpiredEvents()
                drainInbox()
            }
        }
        .onAppear {
            sweepExpiredEvents()
            drainInbox()
        }
        .sheet(item: $currentIngest) { item in
            ConfirmPinView(item: item) {
                pendingIngests.removeAll { $0.id == item.id }
                // Present the next shared item, if any.
                DispatchQueue.main.async {
                    currentIngest = pendingIngests.first
                }
            }
        }
    }

    private func drainInbox() {
        pendingIngests = IngestService.pendingItems()
        if currentIngest == nil {
            currentIngest = pendingIngests.first
        }
    }

    /// Soft-archive events whose end date has passed; frees their geofence
    /// slots on the next rebalance. Never hard-deletes.
    private func sweepExpiredEvents() {
        let eventRaw = PinKind.event.rawValue
        let activeRaw = PinStatus.active.rawValue
        let descriptor = FetchDescriptor<SavedPin>(
            predicate: #Predicate { $0.kindRaw == eventRaw && $0.statusRaw == activeRaw }
        )
        let events = (try? context.fetch(descriptor)) ?? []
        var changed = false
        for event in events where event.isExpiredEvent {
            event.status = .expired
            changed = true
        }
        if changed {
            try? context.save()
            GeofenceManager.shared.rebalance()
        }
    }
}
