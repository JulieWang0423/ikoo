import Foundation
import CoreLocation
import SwiftData

enum PinKind: String, Codable {
    case place
    case event
}

enum PinStatus: String, Codable {
    case active
    case archived
    case expired
}

@Model
final class SavedPin {
    var id: UUID = UUID()
    var name: String = ""
    var address: String?
    var city: String?
    var latitude: Double = 0
    var longitude: Double = 0
    var category: String?
    var kindRaw: String = PinKind.place.rawValue
    var sourceURL: String?
    var sourceApp: String?
    var sourceCaption: String?
    /// Thumbnail of the source post (from oEmbed/og:image) — the frame that
    /// made the user save this. Shared across places from the same post.
    var thumbnailURL: String?
    var createdAt: Date = Date()
    var statusRaw: String = PinStatus.active.rawValue

    // Event fields (nil for places)
    var eventStart: Date?
    var eventEnd: Date?
    var eventDateIsApproximate: Bool = false
    var rawDateText: String?

    // Geofence bookkeeping
    /// User-defined grouping ("Seoul trip", "Date spots"). Nil = unfiled.
    var collectionName: String?

    var lastNotifiedAt: Date?
    var lastOpenedAt: Date?
    var notifyCount: Int = 0
    var muted: Bool = false
    /// When the user marked this place as visited. nil = still on the wishlist.
    /// Visited pins drop off the geofence so you stop getting nudged…
    var visitedAt: Date?
    /// …unless the user opts to keep alerts on for a favorite worth revisiting.
    var notifyWhenVisited: Bool = false
    var extractionConfidence: Double = 1.0

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        city: String? = nil,
        category: String? = nil,
        kind: PinKind = .place,
        sourceURL: String? = nil,
        sourceApp: String? = nil,
        sourceCaption: String? = nil,
        eventStart: Date? = nil,
        eventEnd: Date? = nil,
        extractionConfidence: Double = 1.0
    ) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.city = city
        self.category = category
        self.kindRaw = kind.rawValue
        self.sourceURL = sourceURL
        self.sourceApp = sourceApp
        self.sourceCaption = sourceCaption
        self.createdAt = Date()
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.extractionConfidence = extractionConfidence
    }

    var kind: PinKind {
        get { PinKind(rawValue: kindRaw) ?? .place }
        set { kindRaw = newValue.rawValue }
    }

    var status: PinStatus {
        get { PinStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Events without an explicit end are treated as ending 1 day after start.
    var effectiveEventEnd: Date? {
        guard kind == .event else { return nil }
        if let eventEnd { return eventEnd }
        if let eventStart { return eventStart.addingTimeInterval(24 * 3600) }
        return nil
    }

    var isExpiredEvent: Bool {
        guard let end = effectiveEventEnd else { return false }
        return end < Date()
    }

    var visited: Bool { visitedAt != nil }

    /// Where this came from, spelled the way the platform spells itself.
    /// nil when it's a plain link with no recognizable source.
    var sourceDisplayName: String? {
        switch sourceApp {
        case "tiktok": return "TikTok"
        case "rednote": return "RedNote"
        case "screenshot": return "a screenshot"
        case "other", nil: return nil
        case let other?: return other.capitalized
        }
    }

    /// The caption trimmed for display in a notification: hashtag spam off the
    /// end, clipped to a readable length. nil when there's nothing worth saying.
    func captionSnippet(limit: Int = 130) -> String? {
        guard var text = sourceCaption?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        while let tail = text.range(of: #"\s*#[^\s#]+$"#, options: .regularExpression) {
            text.removeSubrange(tail)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count > limit {
            text = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }
}
