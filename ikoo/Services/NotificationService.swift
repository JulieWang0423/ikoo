import Foundation
import UserNotifications

enum NotificationService {
    static let nearbyCategory = "NEARBY_PIN"
    static let markVisitedAction = "MARK_VISITED"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// A "Been here ✓" action right on the arrival notification, so the loop
    /// (save → nudge → visit → check off) closes without opening the app.
    static func registerCategories() {
        let visited = UNNotificationAction(
            identifier: markVisitedAction,
            title: "Been here ✓",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: nearbyCategory,
            actions: [visited],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
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
            var body = "It's \(distanceText)"
            if let end = first.eventEnd {
                body += " — happening \(start.formatted(date: .abbreviated, time: .omitted))–\(end.formatted(date: .abbreviated, time: .omitted))."
            } else {
                body += " — \(start.formatted(date: .abbreviated, time: .shortened))."
            }
            content.body = body
        } else {
            content.title = "\(first.name) is \(distanceText)"
            let saved = first.createdAt.formatted(date: .abbreviated, time: .omitted)
            if let source = first.sourceApp, source != "other" {
                content.body = "You saved this from \(source.capitalized) on \(saved). Tap to see it on the map."
            } else {
                content.body = "You saved this on \(saved). Tap to see it on the map."
            }
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
