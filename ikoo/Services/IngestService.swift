import Foundation

/// Drains the App Group inbox that the share extension writes into.
/// Files are only deleted once the user finishes handling an item (saved or
/// discarded), so a crash mid-confirm never loses a share.
enum IngestService {
    static func pendingItems() -> [IngestItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(
            at: AppGroup.inboxURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(IngestItem.self, from: data)
            }
            .sorted { $0.sharedAt < $1.sharedAt }
    }

    static func complete(_ item: IngestItem) {
        let fileURL = AppGroup.inboxURL.appendingPathComponent("\(item.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }
}
