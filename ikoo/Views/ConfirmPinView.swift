import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Every shared item routes through this screen before becoming a pin — LLM
/// extraction only controls how pre-filled it is, so extraction errors are a
/// speed bump, never bad data.
struct ConfirmPinView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: IngestItem
    var onDone: () -> Void

    @State private var extracting = true
    @State private var extraction: ExtractResponse?
    @State private var candidate: ExtractionCandidate?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selectedMapItem: MKMapItem?
    @State private var searching = false
    @State private var isEvent = false
    @State private var eventStart: Date = .now
    @State private var eventEnd: Date = .now.addingTimeInterval(3600 * 3)
    @State private var hasEventEnd = false

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if extracting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Finding the place in this post…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    placeSection
                    eventSection
                }
            }
            .navigationTitle("Save to map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) {
                        finish()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedMapItem == nil)
                }
            }
            .task { await runExtraction() }
        }
        .interactiveDismissDisabled()
    }

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

    @ViewBuilder
    private var placeSection: some View {
        Section("Place") {
            if let candidate {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name).font(.headline)
                    if let evidence = candidate.evidence {
                        Text(evidence).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Search name or address", text: $query)
                .autocorrectionDisabled()
                .onSubmit { Task { await runSearch() } }
            if searching {
                ProgressView()
            }
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
        }
    }

    @ViewBuilder
    private var eventSection: some View {
        Section("Event") {
            Toggle("This is an event", isOn: $isEvent)
            if isEvent {
                DatePicker("Starts", selection: $eventStart)
                Toggle("Has end date", isOn: $hasEventEnd)
                if hasEventEnd {
                    DatePicker("Ends", selection: $eventEnd)
                }
                if let raw = candidate?.rawDateText {
                    LabeledContent("From the post", value: raw)
                }
            }
        }
    }

    private func runExtraction() async {
        extraction = await ExtractClient.extract(item: item)
        let best = extraction?.candidates.max(by: { $0.confidence < $1.confidence })
        candidate = best
        if let best {
            query = [best.name, best.cityHint].compactMap { $0 }.joined(separator: ", ")
            isEvent = best.kind == "event"
            if let start = best.eventStartDate {
                eventStart = start
            }
            if let end = best.eventEndDate {
                eventEnd = end
                hasEventEnd = true
            }
        }
        extracting = false
        if !query.isEmpty {
            await runSearch()
            // High confidence + a single strong hit → preselect for one-tap save.
            if let best, best.confidence >= 0.7, results.count >= 1 {
                selectedMapItem = results.first
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

    private func save() {
        guard let mapItem = selectedMapItem else { return }
        let coordinate = mapItem.placemark.coordinate
        let pin = SavedPin(
            name: mapItem.name ?? query,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: mapItem.placemark.title,
            city: mapItem.placemark.locality ?? candidate?.cityHint,
            category: candidate?.category ?? mapItem.pointOfInterestCategory?.rawValue,
            kind: isEvent ? .event : .place,
            sourceURL: item.effectiveURL,
            sourceApp: item.sourceApp,
            sourceCaption: item.sharedText ?? extraction?.rawDescription,
            eventStart: isEvent ? eventStart : nil,
            eventEnd: isEvent && hasEventEnd ? eventEnd : nil,
            extractionConfidence: candidate?.confidence ?? 1.0
        )
        if isEvent, candidate?.eventStartDate == nil {
            pin.eventDateIsApproximate = true
        }
        pin.rawDateText = candidate?.rawDateText
        context.insert(pin)
        try? context.save()

        if GeofenceManager.shared.authorizationStatus == .notDetermined {
            GeofenceManager.shared.requestWhenInUseAuthorization()
        }
        NotificationService.requestAuthorization()
        GeofenceManager.shared.rebalance()
        finish()
    }

    private func finish() {
        IngestService.complete(item)
        onDone()
        dismiss()
    }
}
