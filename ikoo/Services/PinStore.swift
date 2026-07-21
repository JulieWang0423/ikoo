import Foundation
import CoreLocation
import SwiftData

/// Save-time helpers, chiefly duplicate detection. People re-save the same
/// spot constantly (save it from a post, then again manually months later),
/// and each duplicate wastes a geofence slot and fires its own notification.
enum PinStore {
    /// Same spot if essentially on top of an existing pin, or nearby with a
    /// matching name. Tight distance catches "same POI, slightly different
    /// coordinate from a different map match"; the name check avoids merging
    /// two genuinely different shops in the same building.
    static let sameSpotDistance: CLLocationDistance = 20
    static let sameNameDistance: CLLocationDistance = 120

    static func existingDuplicate(
        name: String,
        latitude: Double,
        longitude: Double,
        in context: ModelContext
    ) -> SavedPin? {
        let activeRaw = PinStatus.active.rawValue
        let descriptor = FetchDescriptor<SavedPin>(
            predicate: #Predicate { $0.statusRaw == activeRaw }
        )
        guard let pins = try? context.fetch(descriptor) else { return nil }
        let target = CLLocation(latitude: latitude, longitude: longitude)
        let normalizedName = normalize(name)
        return pins.first { pin in
            let distance = pin.location.distance(from: target)
            if distance <= sameSpotDistance { return true }
            return distance <= sameNameDistance && namesMatch(normalize(pin.name), normalizedName)
        }
    }

    /// Are two candidates within the same save operation duplicates of each
    /// other? Used to dedupe a single post's extracted list against itself.
    static func sameSpot(
        _ a: (name: String, lat: Double, lng: Double),
        _ b: (name: String, lat: Double, lng: Double)
    ) -> Bool {
        let distance = CLLocation(latitude: a.lat, longitude: a.lng)
            .distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
        if distance <= sameSpotDistance { return true }
        return distance <= sameNameDistance && namesMatch(normalize(a.name), normalize(b.name))
    }

    private static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func namesMatch(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }
}
