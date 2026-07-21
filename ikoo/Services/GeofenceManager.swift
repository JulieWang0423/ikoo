import Foundation
import CoreLocation
import SwiftData
import os

let ikooLog = Logger(subsystem: "com.sihewang.ikoo", category: "geofence")

/// Owns all region monitoring. iOS caps region monitoring at 20 regions per
/// app, so we budget 18 and dynamically re-register the regions nearest to the
/// user, waking up on significant-location-changes (which relaunch the app
/// even if terminated).
final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    static let maxRegions = 18
    static let defaultRadius: CLLocationDistance = 200
    static let minRadius: CLLocationDistance = 100
    static let maxRadius: CLLocationDistance = 400
    static let clusterDistance: CLLocationDistance = 250
    static let placeCooldown: TimeInterval = 72 * 3600
    static let eventCooldown: TimeInterval = 24 * 3600
    /// Auto-mute a pin after this many notifications that the user never opened.
    static let autoMuteThreshold = 3

    private let manager = CLLocationManager()
    private var modelContainer: ModelContainer?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Call once at app launch (including background relaunches — the App
    /// init runs before delegate callbacks are delivered).
    func start(container: ModelContainer) {
        modelContainer = container
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
        primeLocation()
        rebalance()
    }

    /// `manager.location` is nil until some session delivers a fix, and SLC
    /// alone won't produce one promptly — request a one-shot location so the
    /// first rebalance has something to work with.
    private func primeLocation() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Region rebalancing

    struct DesiredRegion {
        var center: CLLocationCoordinate2D
        var radius: CLLocationDistance
        var pinIDs: [UUID]

        /// Region identifier encodes member pin IDs so didEnterRegion can
        /// resolve pins without extra lookup state.
        var identifier: String {
            pinIDs.map(\.uuidString).joined(separator: ",")
        }
    }

    /// Re-register the nearest regions around the user's current location.
    /// Diffs against currently monitored regions instead of churning all 18.
    func rebalance() {
        guard let context = mainContext() else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        guard let current = manager.location else { return }

        let candidates = eligiblePins(in: context)
        let desired = Self.desiredRegions(for: candidates, around: current)
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })

        let monitored = manager.monitoredRegions.compactMap { $0 as? CLCircularRegion }
        let monitoredIDs = Set(monitored.map(\.identifier))

        ikooLog.info("rebalance: \(candidates.count) eligible pins -> \(desired.count) desired regions (\(monitored.count) currently monitored)")
        for region in monitored where desiredByID[region.identifier] == nil {
            manager.stopMonitoring(for: region)
            ikooLog.info("stopped region \(region.identifier, privacy: .public)")
        }
        for desiredRegion in desired where !monitoredIDs.contains(desiredRegion.identifier) {
            let region = CLCircularRegion(
                center: desiredRegion.center,
                radius: desiredRegion.radius,
                identifier: desiredRegion.identifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            ikooLog.info("started region \(desiredRegion.identifier, privacy: .public) r=\(Int(desiredRegion.radius))m")
            // iOS does not fire didEnter for a region you're already inside
            // at registration time; requestState covers that case.
            manager.requestState(for: region)
        }
    }

    /// Pins worth spending a region slot on.
    private func eligiblePins(in context: ModelContext) -> [SavedPin] {
        let activeRaw = PinStatus.active.rawValue
        let descriptor = FetchDescriptor<SavedPin>(
            predicate: #Predicate { $0.statusRaw == activeRaw && $0.muted == false }
        )
        let pins = (try? context.fetch(descriptor)) ?? []
        return pins.filter { !$0.isExpiredEvent && !Self.inCooldown($0) }
    }

    static func inCooldown(_ pin: SavedPin, now: Date = Date()) -> Bool {
        guard let last = pin.lastNotifiedAt else { return false }
        return now.timeIntervalSince(last) < cooldownInterval(for: pin, now: now)
    }

    static func cooldownInterval(for pin: SavedPin, now: Date = Date()) -> TimeInterval {
        // Events starting within 48h nudge harder.
        if pin.kind == .event, let start = pin.eventStart,
           start.timeIntervalSince(now) < 48 * 3600, start.timeIntervalSince(now) > -48 * 3600 {
            return eventCooldown
        }
        return placeCooldown
    }

    /// Nearest-first greedy clustering: pins within `clusterDistance` of an
    /// anchor share one region so a dense street doesn't eat several slots.
    static func desiredRegions(for pins: [SavedPin], around location: CLLocation) -> [DesiredRegion] {
        let sorted = pins.sorted {
            $0.location.distance(from: location) < $1.location.distance(from: location)
        }
        var regions: [DesiredRegion] = []
        var assigned = Set<UUID>()

        for anchor in sorted {
            guard regions.count < maxRegions else { break }
            guard !assigned.contains(anchor.id) else { continue }

            let members = sorted.filter {
                !assigned.contains($0.id) &&
                $0.location.distance(from: anchor.location) <= clusterDistance
            }
            for member in members { assigned.insert(member.id) }

            let count = Double(members.count)
            let center = CLLocationCoordinate2D(
                latitude: members.map(\.latitude).reduce(0, +) / count,
                longitude: members.map(\.longitude).reduce(0, +) / count
            )
            let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let spread = members.map { $0.location.distance(from: centerLocation) }.max() ?? 0
            let radius = min(max(defaultRadius, spread + 100), maxRadius)

            regions.append(DesiredRegion(center: center, radius: radius, pinIDs: members.map(\.id)))
        }
        return regions
    }

    // MARK: - Entry handling

    private func handleEntry(regionIdentifier: String) {
        guard let context = mainContext() else { return }
        let ids = Set(regionIdentifier.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        guard !ids.isEmpty else { return }

        let activeRaw = PinStatus.active.rawValue
        let descriptor = FetchDescriptor<SavedPin>(
            predicate: #Predicate { $0.statusRaw == activeRaw && $0.muted == false }
        )
        let pins = ((try? context.fetch(descriptor)) ?? [])
            .filter { ids.contains($0.id) && !$0.isExpiredEvent && !Self.inCooldown($0) }
        ikooLog.info("region entry: \(ids.count) member(s), \(pins.count) eligible after cooldown/mute filter")
        guard !pins.isEmpty else { return }

        let distance = manager.location.map { loc in
            Int(pins.map { $0.location.distance(from: loc) }.min() ?? 0)
        }
        NotificationService.notifyNearby(pins: pins, distanceMeters: distance)

        let now = Date()
        for pin in pins {
            pin.lastNotifiedAt = now
            pin.notifyCount += 1
            // Stop spending a slot on pins the user keeps ignoring.
            if pin.notifyCount >= Self.autoMuteThreshold, pin.lastOpenedAt == nil {
                pin.muted = true
            }
        }
        try? context.save()
        rebalance()
    }

    /// CLLocationManager is created on the main thread, so its delegate
    /// callbacks arrive on the main run loop — assumeIsolated makes that
    /// contract explicit (and traps loudly if it's ever violated).
    private func mainContext() -> ModelContext? {
        guard let modelContainer else { return nil }
        return MainActor.assumeIsolated { modelContainer.mainContext }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
        primeLocation()
        rebalance()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        rebalance()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleEntry(regionIdentifier: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside {
            handleEntry(regionIdentifier: region.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Non-fatal: slot pressure or transient failures; next rebalance retries.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignore transient location errors (e.g. denied while prompting).
    }
}
