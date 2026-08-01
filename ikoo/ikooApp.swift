import SwiftUI
import SwiftData
import UserNotifications
import UIKit

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
        AppState.shared.container = container
        NotificationService.registerCategories()
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
    /// Set at launch; lets non-View code (the notification action handler)
    /// reach the store.
    var container: ModelContainer?

    private let promptedKey = "hasPromptedNearbyAlertsAfterSave"

    /// Mark a place visited (from the notification action or elsewhere). It
    /// drops off the wishlist and stops nudging on the next rebalance.
    func markVisited(pinID: UUID) {
        MainActor.assumeIsolated {
            guard let context = container?.mainContext else { return }
            let descriptor = FetchDescriptor<SavedPin>(predicate: #Predicate { $0.id == pinID })
            guard let pin = try? context.fetch(descriptor).first else { return }
            pin.visitedAt = Date()
            try? context.save()
            GeofenceManager.shared.rebalance()
        }
    }

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
                if response.actionIdentifier == "MARK_VISITED" {
                    AppState.shared.markVisited(pinID: id)
                } else {
                    AppState.shared.selectedPinID = id
                }
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
    /// The place a tapped notification is asking us to open.
    @State private var notificationPin: SavedPin?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab = {
        #if DEBUG
        // Automated-test hook: open directly on a given tab.
        switch ProcessInfo.processInfo.environment["IKOO_DEBUG_TAB"] {
        case "nearby": return 1
        case "map": return 2
        case "saved": return 3
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
            NearbyScreen()
                .tabItem { Label("Nearby", systemImage: "location") }
                .tag(1)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(2)
            PinListScreen()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(3)
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
        // Notification deep-link, handled at the root so it works from any tab
        // and on a cold launch. Isolated in a background layer because stacking
        // several .sheet modifiers on one view makes presentation unreliable.
        .background(
            Color.clear.sheet(item: $notificationPin) { pin in
                NavigationStack { PinDetailView(pin: pin) }
                    .tint(Theme.accent)
            }
        )
        // A tapped notification can land before OR after this view appears, so
        // catch both: the value already sitting there, and later changes.
        .onAppear { openPinFromNotification(appState.selectedPinID) }
        .onChange(of: appState.selectedPinID) { _, id in openPinFromNotification(id) }
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
            if ProcessInfo.processInfo.environment["IKOO_DEBUG_OCR"] == "1" {
                Task {
                    guard let url = Bundle.main.url(forResource: "ocr-sample", withExtension: "png"),
                          let data = try? Data(contentsOf: url),
                          let image = UIImage(data: data) else { return }
                    let text = await OCRService.recognizeText(in: image)
                    ikooLog.info("OCR sample text:\n\(text, privacy: .public)")
                    var item = IngestItem(url: nil, sharedText: text)
                    item.sourceApp = "screenshot"
                    await MainActor.run { currentIngest = item }
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

    /// Resolve a deep-linked pin id and present its detail. Consumes the id so
    /// a stale one can't pop a sheet later.
    private func openPinFromNotification(_ id: UUID?) {
        guard let id else { return }
        appState.selectedPinID = nil
        // Don't fight the onboarding cover for the screen.
        guard hasCompletedOnboarding else { return }
        let descriptor = FetchDescriptor<SavedPin>(predicate: #Predicate { $0.id == id })
        guard let pin = try? context.fetch(descriptor).first else {
            ikooLog.error("deep link: no pin for \(id.uuidString, privacy: .public)")
            return
        }
        ikooLog.info("deep link: opening \(pin.name, privacy: .public)")
        notificationPin = pin
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
