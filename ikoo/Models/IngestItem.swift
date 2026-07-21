import Foundation

/// Payload the share extension drops into the App Group inbox for the main
/// app to process. This file is compiled into BOTH targets — keep it free of
/// SwiftData/UIKit/MapKit imports.
struct IngestItem: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String?
    var sharedText: String?
    var sourceApp: String
    var sharedAt: Date

    init(url: String?, sharedText: String?, sharedAt: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.sharedText = sharedText
        self.sharedAt = sharedAt
        self.sourceApp = Self.guessSource(url: url, text: sharedText)
    }

    static func guessSource(url: String?, text: String?) -> String {
        let haystack = [url, text].compactMap { $0 }.joined(separator: " ").lowercased()
        if haystack.contains("tiktok.com") { return "tiktok" }
        if haystack.contains("xhslink.com") || haystack.contains("xiaohongshu.com") { return "rednote" }
        return "other"
    }

    /// First URL found in the payload — RedNote often shares a text blob with
    /// an xhslink inside rather than a bare URL.
    var effectiveURL: String? {
        if let url, !url.isEmpty { return url }
        guard let sharedText else { return nil }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(sharedText.startIndex..., in: sharedText)
            if let match = detector.firstMatch(in: sharedText, range: range), let url = match.url {
                return url.absoluteString
            }
        }
        return nil
    }
}
