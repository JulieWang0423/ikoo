import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct PinDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pin: SavedPin

    @State private var distanceText: String?

    var body: some View {
        List {
            mapSection
            momentSection
            whySavedSection
            detailsSection
            managementSection
        }
        .navigationTitle(pin.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Opening a pin resets the ignored-notification counter so it
            // isn't auto-muted, and records the visit for auto-mute logic.
            pin.lastOpenedAt = Date()
            pin.notifyCount = 0
            try? context.save()
            updateDistance()
        }
    }

    // MARK: - Sections

    private var mapSection: some View {
        Section {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: pin.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker(pin.name, coordinate: pin.coordinate)
            }
            .frame(height: 180)
            .listRowInsets(EdgeInsets())
            .allowsHitTesting(false)
        }
    }

    /// The "standing on the street" moment: how far, and the two things you
    /// most want right then — directions, and the post that made you save it.
    private var momentSection: some View {
        Section {
            if let distanceText {
                Label(distanceText, systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            if pin.kind == .event, let start = pin.eventStart {
                Label(eventTiming(start: start, end: pin.eventEnd), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button(action: openInMaps) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if let url = sourceURL {
                    Link(destination: url) {
                        Label("Watch post", systemImage: "play.rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var whySavedSection: some View {
        if let caption = pin.sourceCaption, !caption.isEmpty {
            Section("Why you saved this") {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let source = pin.sourceApp, source != "other" {
                    Text("From \(source.capitalized)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section {
            if let address = pin.address {
                LabeledContent("Address", value: address)
            }
            if let category = pin.category {
                LabeledContent("Category", value: prettyCategory(category))
            }
            LabeledContent("Saved", value: pin.createdAt.formatted(date: .abbreviated, time: .omitted))
            if pin.sourceCaption == nil, let source = pin.sourceApp, source != "other" {
                LabeledContent("Source", value: source.capitalized)
            }
            if pin.kind == .event, let start = pin.eventStart {
                LabeledContent("Starts", value: start.formatted(date: .abbreviated, time: .shortened))
                if let end = pin.eventEnd {
                    LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private var managementSection: some View {
        Section {
            collectionPicker
            Toggle(isOn: Binding(
                get: { !pin.muted },
                set: { enabled in
                    pin.muted = !enabled
                    if enabled { pin.notifyCount = 0 }
                    try? context.save()
                    GeofenceManager.shared.rebalance()
                }
            )) {
                Label("Nearby alerts", systemImage: "bell")
            }
        }
    }

    // MARK: - Collection picker

    /// Existing collections come from pins plus names pre-registered on the
    /// home screen (UserDefaults "knownCollections").
    private var knownCollections: [String] {
        let fromDefaults = UserDefaults.standard.stringArray(forKey: "knownCollections") ?? []
        let fromPins = (try? context.fetch(FetchDescriptor<SavedPin>()))?.compactMap(\.collectionName) ?? []
        return Array(Set(fromDefaults + fromPins)).sorted()
    }

    private var collectionPicker: some View {
        Menu {
            Button("None") { setCollection(nil) }
            ForEach(knownCollections, id: \.self) { name in
                Button {
                    setCollection(name)
                } label: {
                    if pin.collectionName == name {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            LabeledContent {
                Text(pin.collectionName ?? "None")
            } label: {
                Label("Collection", systemImage: "folder")
            }
        }
    }

    private func setCollection(_ name: String?) {
        pin.collectionName = name
        try? context.save()
    }

    // MARK: - Helpers

    private var sourceURL: URL? {
        guard let urlString = pin.sourceURL else { return nil }
        return URL(string: urlString)
    }

    private func updateDistance() {
        guard let here = CLLocationManager().location else { return }
        let meters = here.distance(from: pin.location)
        distanceText = Self.formatDistance(meters)
    }

    static func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int(meters))m away" }
        return String(format: "%.1f km away", meters / 1000)
    }

    private func eventTiming(start: Date, end: Date?) -> String {
        let now = Date()
        if start <= now, let end, now <= end { return "Happening now" }
        if start > now {
            return "Starts \(start.formatted(.relative(presentation: .named)))"
        }
        return start.formatted(date: .abbreviated, time: .shortened)
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = pin.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func prettyCategory(_ raw: String) -> String {
        raw.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}
