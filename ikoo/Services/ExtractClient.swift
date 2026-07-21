import Foundation

struct ExtractionCandidate: Codable, Identifiable, Equatable {
    var name: String
    var kind: String            // "place" | "event"
    var category: String?
    var cityHint: String?
    var addressHint: String?
    var eventStart: String?     // ISO date "2026-07-25"
    var eventEnd: String?
    var rawDateText: String?
    var confidence: Double
    var evidence: String?

    var id: String { name + (cityHint ?? "") }

    enum CodingKeys: String, CodingKey {
        case name, kind, category, confidence, evidence
        case cityHint = "city_hint"
        case addressHint = "address_hint"
        case eventStart = "event_start"
        case eventEnd = "event_end"
        case rawDateText = "raw_date_text"
    }

    var eventStartDate: Date? { Self.parseISODate(eventStart) }
    var eventEndDate: Date? { Self.parseISODate(eventEnd) }

    static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

struct ExtractResponse: Codable {
    var source: String
    var fetchStatus: String
    var rawTitle: String?
    var rawDescription: String?
    var thumbnailURL: String?
    var candidates: [ExtractionCandidate]

    enum CodingKeys: String, CodingKey {
        case source, candidates
        case fetchStatus = "fetch_status"
        case rawTitle = "raw_title"
        case rawDescription = "raw_description"
        case thumbnailURL = "thumbnail_url"
    }
}

/// Client for the ikoo backend. If the backend is unreachable or unset, all
/// calls resolve to nil and the app falls back to manual search — a dead
/// backend must never break the core loop.
enum ExtractClient {
    /// Configure via Info.plist. Empty string disables extraction entirely.
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "IkooExtractBaseURL") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var appToken: String {
        (Bundle.main.object(forInfoDictionaryKey: "IkooExtractToken") as? String) ?? "dev-token"
    }

    static func extract(item: IngestItem) async -> ExtractResponse? {
        guard let baseURL else { return nil }
        guard item.effectiveURL != nil || item.sharedText != nil else { return nil }

        var request = URLRequest(url: baseURL.appendingPathComponent("extract"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        var body: [String: Any] = [
            "shared_at": ISO8601DateFormatter().string(from: item.sharedAt),
        ]
        if let url = item.effectiveURL { body["url"] = url }
        if let text = item.sharedText { body["caption"] = text }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ExtractResponse.self, from: data)
        } catch {
            return nil
        }
    }
}
