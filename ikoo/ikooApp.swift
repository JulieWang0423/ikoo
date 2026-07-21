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
        Theme.applyAppearance()
        #if DEBUG
        seedTestPinIfRequested()
        if ProcessInfo.processInfo.environment["IKOO_SEED_SHOWCASE"] == "1" {
            SampleData.loadShowcase(into: container.mainContext)
        }
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
        let env = ProcessInfo.processInfo.environment
        let lat = env["IKOO_SEED_LAT"].flatMap(Double.init) ?? 38.0356
        let lng = env["IKOO_SEED_LNG"].flatMap(Double.init) ?? -78.5034
        let pin = SavedPin(
            name: "The Rotunda",
            latitude: lat,
            longitude: lng,
            address: "1826 University Ave, Charlottesville, VA",
            city: "Charlottesville",
            sourceApp: "tiktok"
        )
        pin.sourceURL = "https://www.tiktok.com/@uva/video/7300000000000000000"
        pin.sourceCaption = "the most beautiful spot on grounds 🏛️ Jefferson designed this himself. go at golden hour, sit on the steps #uva #charlottesville #hiddengem"
        pin.thumbnailURL = ProcessInfo.processInfo.environment["IKOO_SEED_THUMB"]
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

/// Cross-cutting UI state (notification deep-links, permission funnel).
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var selectedPinID: UUID?
    @Published var showNearbyAlertsPrompt = false
    @Published var toast: String?

    private let promptedKey = "hasPromptedNearbyAlertsAfterSave"

    /// Brief success confirmation shown over the whole app after a save.
    func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    /// The contextual moment to ask for background location: right after the
    /// user's first save, once they can see their pin landed. Shown once; the
    /// home banner is the persistent nudge afterward.
    func maybePromptNearbyAlertsAfterSave() {
        guard GeofenceManager.shared.nearbyAlertsState != .on,
              !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedKey)
        // Let the save/confirm sheet finish dismissing before presenting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showNearbyAlertsPrompt = true
        }
    }
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

/// Transient success confirmation (a save landed).
struct ToastView: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.accent, in: Capsule())
            .shadow(radius: 8, y: 2)
            .padding(.horizontal, 24)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @ObservedObject private var appState = AppState.shared
    @State private var pendingIngests: [IngestItem] = []
    @State private var currentIngest: IngestItem?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab = {
        #if DEBUG
        // Automated-test hook: open directly on a given tab.
        switch ProcessInfo.processInfo.environment["IKOO_DEBUG_TAB"] {
        case "map": return 1
        case "saved": return 2
        default: break
        }
        #endif
        return 0
    }()

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeScreen()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
            PinListScreen()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(2)
        }
        .tint(Theme.accent)
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                ToastView(message: toast)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: appState.toast)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
        .sheet(isPresented: $appState.showNearbyAlertsPrompt) {
            NearbyAlertsExplainer()
                .presentationDetents([.large])
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                sweepExpiredEvents()
                drainInbox()
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["IKOO_SKIP_ONBOARDING"] == "1" {
                hasCompletedOnboarding = true
            }
            if ProcessInfo.processInfo.environment["IKOO_DEBUG_SHOW_ALERTS_PROMPT"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    appState.showNearbyAlertsPrompt = true
                }
            }
            #endif
        }
        .onAppear {
            sweepExpiredEvents()
            drainInbox()
        }
        // Not shown while onboarding is up; drainInbox re-runs on foreground.
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
