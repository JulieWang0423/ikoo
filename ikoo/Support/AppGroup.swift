import Foundation

enum AppGroup {
    static let id = "group.com.sihewang.ikoo"

    /// App Group container, falling back to Application Support so the app
    /// still runs if the entitlement is missing (e.g. fresh checkout without
    /// capabilities configured yet).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Where the share extension drops IngestItem JSON files for the main app.
    static var inboxURL: URL {
        let url = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var storeURL: URL {
        containerURL.appendingPathComponent("ikoo.store")
    }
}
