import Foundation
import UserNotifications

enum NotificationService {
    static let nearbyCategory = "NEARBY_PIN"
    static let markVisitedAction = "MARK_VISITED"
    static let directionsAction = "DIRECTIONS"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Actions on the arrival notification itself, so the two things you
    /// actually want while standing on the street — walk there, or tick it off
    /// — need no trip through the app.
    static func registerCategories() {
        let directions = UNNotificationAction(
            identifier: directionsAction,
            title: "Directions",
            options: [.foreground]  // handing off to Maps requires foreground
        )
        let visited = UNNotificationAction(
            identifier: markVisitedAction,
            title: "Been here ✓",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: nearbyCategory,
            actions: [directions, visited],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        #if DEBUG
        UNUserNotificationCenter.current().getNotificationCategories { cats in
            for c in cats {
                let ids = c.actions.map { "\($0.identifier)(\($0.title))" }.joined(separator: ", ")
                ikooLog.info("category \(c.identifier, privacy: .public) actions: \(ids, privacy: .public)")
            }
        }
        #endif
    }

    static func notifyNearby(pins: [SavedPin], distanceMeters: Int?) {
        guard let first = pins.first else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["pinID": first.id.uuidString]
        content.categoryIdentifier = nearbyCategory

        let distanceText = distanceMeters.map { "\($0)m away" } ?? "nearby"

        if pins.count > 1 {
            content.title = "\(pins.count) saved spots near you"
            let names = pins.prefix(2).map(\.name).joined(separator: ", ")
            let more = pins.count - 2
            content.body = more > 0
                ? "\(names), and \(more) more within a few blocks."
                : "\(names) are within a few blocks."
        } else if first.kind == .event, let start = first.eventStart {
            let day = start.formatted(.dateTime.weekday(.wide))
            content.title = start < Date()
                ? "\(first.name) is happening now"
                : "\(first.name) starts \(day)"
            // The caption is the reason you cared; distance is the fallback.
            content.body = first.captionSnippet() ?? "It's \(distanceText)."
        } else {
            content.title = "\(first.name) is \(distanceText)"
            // Lead with why you saved it — the thing that makes someone turn
            // around — not with when you saved it.
            content.body = first.captionSnippet()
                ?? first.address
                ?? first.sourceDisplayName.map { "You saved this from \($0)." }
                ?? "One of your saved places."
        }

        let request = UNNotificationRequest(
            identifier: "nearby-\(first.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                ikooLog.error("notification add failed: \(error.localizedDescription, privacy: .public)")
            } else {
                ikooLog.info("notification posted: \(content.title, privacy: .public)")
            }
        }
    }
}
