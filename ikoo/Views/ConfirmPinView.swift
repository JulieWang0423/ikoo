import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Every shared item routes through this screen before becoming pins — LLM
/// extraction only controls how pre-filled it is, so extraction errors are a
/// speed bump, never bad data.
///
/// Posts often name several places (travel vlogs, "top 5" lists), so the
/// extraction candidates render as a batch checklist: each one is geocoded,
/// preselected when a map match is found, and saved together.
struct ConfirmPinView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: IngestItem
    var onDone: () -> Void

    struct CandidateRow: Identifiable {
        let id = UUID()
        var candidate: ExtractionCandidate?
        var resolved: MKMapItem?
        var include: Bool
        var alreadySaved = false

        var displayName: String {
            resolved?.name ?? candidate?.name ?? "Unknown place"
        }
        var isEvent: Bool { candidate?.kind == "event" }
    }

    @State private var extracting = true
    @State private var extraction: ExtractResponse?
    @State private var rows: [CandidateRow] = []
    @State private var resolvingRowID: UUID?
    @State private var addingPlace = false

    // Single-place manual fallback (no candidates found).
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selectedMapItem: MKMapItem?
    @State private var searching = false
    @State private var isEvent = false
    @State private var eventStart: Date = .now
    @State private var eventEnd: Date = .now.addingTimeInterval(3600 * 3)
    @State private var hasEventEnd = false

    private var includedCount: Int {
        rows.filter { $0.include && $0.resolved != nil }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if extracting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Finding places in this post…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !rows.isEmpty {
                    batchSection
                    addAnotherSection
                } else {
                    manualPlaceSection
                    manualEventSection
                }
            }
            .navigationTitle("Save to map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { finish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !rows.isEmpty {
                        Button(includedCount > 1 ? "Save \(includedCount) places" : "Save") {
                            saveBatch()
                        }
                        .disabled(includedCount == 0)
                    } else {
                        Button("Save") { saveSingle() }
                            .disabled(selectedMapItem == nil)
                    }
                }
            }
            .task { await runExtraction() }
            .sheet(isPresented: $addingPlace) {
                ResolvePlaceView(initialQuery: "") { mapItem in
                    rows.append(CandidateRow(candidate: nil, resolved: mapItem, include: true))
                }
            }
            .sheet(item: $resolvingRowID) { rowID in
                let row = rows.first { $0.id == rowID }
                ResolvePlaceView(initialQuery: row.map { Self.searchQuery(for: $0) } ?? "") { mapItem in
                    if let index = rows.firstIndex(where: { $0.id == rowID }) {
                        rows[index].resolved = mapItem
                        rows[index].include = true
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section("Shared from \(item.sourceApp == "other" ? "link" : item.sourceApp.capitalized)") {
            if let url = item.effectiveURL {
                Text(url).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            if let text = item.sharedText, item.effectiveURL == nil || text != item.effectiveURL {
                Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }

    private var batchSection: some View {
        Section {
            ForEach($rows) { $row in
                Button {
                    if row.resolved != nil {
                        row.include.toggle()
                    } else {
                        resolvingRowID = row.id
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: rowIcon(row))
                            .font(.title3)
                            .foregroundStyle(rowIconColor(row))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.displayName).foregroundStyle(.primary)
                                if row.isEvent {
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if row.alreadySaved {
                                Text("Already in your saved places")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else if let subtitle = row.resolved?.placemark.title {
                                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            } else {
                                Text("No map match — tap to search")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            if let evidence = row.candidate?.evidence, !row.alreadySaved {
                                Text("“\(evidence)”").font(.footnote).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if row.resolved != nil {
                            Button {
                                resolvingRowID = row.id
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        } header: {
            Text("Places in this post")
        } footer: {
            Text("Tap to include or skip. The magnifier changes a wrong match.")
        }
    }

    private func rowIcon(_ row: CandidateRow) -> String {
        if row.alreadySaved { return "checkmark.seal" }
        if row.resolved == nil { return "questionmark.circle" }
        return row.include ? "checkmark.circle.fill" : "circle"
    }

    private func rowIconColor(_ row: CandidateRow) -> Color {
        if row.alreadySaved { return .secondary }
        if row.resolved == nil { return .orange }
        return row.include ? .green : .secondary
    }

    private var addAnotherSection: some View {
        Section {
            Button {
                addingPlace = true
            } label: {
                Label("Add another place", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var manualPlaceSection: some View {
        Section {
            TextField("Search name or address", text: $query)
                .autocorrectionDisabled()
                .onSubmit { Task { await runManualSearch() } }
            if searching { ProgressView() }
            ForEach(results, id: \.self) { mapItem in
                Button {
                    selectedMapItem = mapItem
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapItem.name ?? "Unknown place").foregroundStyle(.primary)
                            if let subtitle = mapItem.placemark.title {
                                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedMapItem == mapItem {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
        } header: {
            Text("Place")
        } footer: {
            if !extracting && extraction?.candidates.isEmpty != false {
                Text("ikoo couldn't spot place names in this post. It works best with posts whose caption names specific spots — cafés, restaurants, markets, sights. Search above to add them yourself, or share again and paste the caption text along with the link.")
            }
        }
    }

    @ViewBuilder
    private var manualEventSection: some View {
        Section("Event") {
            Toggle("This is an event", isOn: $isEvent)
            if isEvent {
                DatePicker("Starts", selection: $eventStart)
                Toggle("Has end date", isOn: $hasEventEnd)
                if hasEventEnd {
                    DatePicker("Ends", selection: $eventEnd)
                }
            }
        }
    }

    // MARK: - Extraction & geocoding

    private func runExtraction() async {
        extraction = await ExtractClient.extract(item: item)
        let candidates = extraction?.candidates ?? []
        if !candidates.isEmpty {
            rows = await Self.resolveCandidates(candidates)
            markDuplicates()
        }
        extracting = false
    }

    /// Flag rows that already exist (from an earlier save) or that duplicate
    /// an earlier row in this same batch. Flagged rows default to unchecked so
    /// the user sees them but doesn't re-save by reflex.
    private func markDuplicates() {
        var kept: [(name: String, lat: Double, lng: Double)] = []
        for index in rows.indices {
            guard let mapItem = rows[index].resolved else { continue }
            let c = mapItem.placemark.coordinate
            let name = mapItem.name ?? rows[index].candidate.map { Self.romanized($0.name) } ?? ""
            let entry = (name: name, lat: c.latitude, lng: c.longitude)
            let dupInStore = PinStore.existingDuplicate(
                name: name, latitude: c.latitude, longitude: c.longitude, in: context) != nil
            let dupInBatch = kept.contains { PinStore.sameSpot($0, entry) }
            if dupInStore || dupInBatch {
                rows[index].alreadySaved = true
                rows[index].include = false
            } else {
                kept.append(entry)
            }
        }
    }

    /// Geocode every candidate concurrently; preselect the ones that matched.
    static func resolveCandidates(_ candidates: [ExtractionCandidate]) async -> [CandidateRow] {
        let center = CLLocationManager().location?.coordinate
        return await withTaskGroup(of: (Int, MKMapItem?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let query = searchQuery(name: candidate.name, city: candidate.cityHint)
                    let match = try? await GeocodingService.search(query, near: center).first
                    return (index, match)
                }
            }
            var matches = [Int: MKMapItem]()
            for await (index, match) in group {
                if let match { matches[index] = match }
            }
            return candidates.enumerated().map { index, candidate in
                CandidateRow(candidate: candidate,
                             resolved: matches[index],
                             include: matches[index] != nil)
            }
        }
    }

    /// RedNote captions come back bilingual ("广藏市场 (Gwangjang Market)");
    /// Apple Maps matches the romanized part far more reliably.
    static func romanized(_ text: String) -> String {
        if let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")"), open < close {
            let inner = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { return inner }
        }
        return text
    }

    static func searchQuery(name: String, city: String?) -> String {
        [romanized(name), city.map(romanized)].compactMap { $0 }.joined(separator: ", ")
    }

    static func searchQuery(for row: CandidateRow) -> String {
        guard let candidate = row.candidate else { return "" }
        return searchQuery(name: candidate.name, city: candidate.cityHint)
    }

    private func runManualSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searching = true
        defer { searching = false }
        let center = CLLocationManager().location?.coordinate
        results = (try? await GeocodingService.search(trimmed, near: center)) ?? []
    }

    // MARK: - Saving

    private func saveBatch() {
        let count = rows.filter { $0.include && $0.resolved != nil }.count
        for row in rows where row.include {
            guard let mapItem = row.resolved else { continue }
            insertPin(from: mapItem, candidate: row.candidate)
        }
        try? context.save()
        requestPermissionsAndRebalance()
        AppState.shared.showToast(count == 1 ? "Saved 1 place to your map" : "Saved \(count) places to your map")
        finish()
    }

    private func saveSingle() {
        guard let mapItem = selectedMapItem else { return }
        let pin = insertPin(from: mapItem, candidate: nil)
        if isEvent {
            pin.kind = .event
            pin.eventStart = eventStart
            pin.eventEnd = hasEventEnd ? eventEnd : nil
        }
        try? context.save()
        requestPermissionsAndRebalance()
        AppState.shared.showToast("Saved \(mapItem.name ?? "place") to your map")
        finish()
    }

    @discardableResult
    private func insertPin(from mapItem: MKMapItem, candidate: ExtractionCandidate?) -> SavedPin {
        let coordinate = mapItem.placemark.coordinate
        let resolvedName = mapItem.name ?? candidate.map { Self.romanized($0.name) } ?? "Unknown place"
        // Defensive: never create a second pin for the same spot.
        if let existing = PinStore.existingDuplicate(
            name: resolvedName, latitude: coordinate.latitude,
            longitude: coordinate.longitude, in: context) {
            return existing
        }
        let pin = SavedPin(
            name: mapItem.name ?? candidate.map { Self.romanized($0.name) } ?? "Unknown place",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: mapItem.placemark.title,
            city: mapItem.placemark.locality ?? candidate?.cityHint.map { Self.romanized($0) },
            category: candidate?.category ?? mapItem.pointOfInterestCategory?.rawValue,
            kind: candidate?.kind == "event" ? .event : .place,
            sourceURL: item.effectiveURL,
            sourceApp: item.sourceApp,
            sourceCaption: item.sharedText ?? extraction?.rawDescription,
            eventStart: candidate?.eventStartDate,
            eventEnd: candidate?.eventEndDate,
            extractionConfidence: candidate?.confidence ?? 1.0
        )
        if pin.kind == .event, candidate?.eventStartDate == nil {
            pin.eventDateIsApproximate = true
        }
        pin.rawDateText = candidate?.rawDateText
        pin.thumbnailURL = extraction?.thumbnailURL
        context.insert(pin)
        return pin
    }

    private func requestPermissionsAndRebalance() {
        GeofenceManager.shared.rebalance()
        // Ask for background location contextually, once, after the first save
        // — not with a cold system prompt mid-confirm.
        AppState.shared.maybePromptNearbyAlertsAfterSave()
    }

    private func finish() {
        IngestService.complete(item)
        onDone()
        dismiss()
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// Search-and-pick sheet used to fix a wrong match or add an extra place.
struct ResolvePlaceView: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    var onSelect: (MKMapItem) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(results, id: \.self) { mapItem in
                    Button {
                        onSelect(mapItem)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapItem.name ?? "Unknown place").foregroundStyle(.primary)
                            if let subtitle = mapItem.placemark.title {
                                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if searching {
                    ProgressView()
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Search for the place",
                        systemImage: "magnifyingglass",
                        description: Text("Try the place name plus its city.")
                    )
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or address")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .navigationTitle("Find place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if !initialQuery.isEmpty {
                    query = initialQuery
                    await runSearch()
                }
            }
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searching = true
        defer { searching = false }
        let center = CLLocationManager().location?.coordinate
        results = (try? await GeocodingService.search(trimmed, near: center)) ?? []
    }
}
