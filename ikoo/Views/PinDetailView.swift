import SwiftUI
import SwiftData
import MapKit

struct PinDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pin: SavedPin

    var body: some View {
        List {
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

            Section {
                if let address = pin.address {
                    LabeledContent("Address", value: address)
                }
                if let category = pin.category {
                    LabeledContent("Category", value: prettyCategory(category))
                }
                LabeledContent("Saved", value: pin.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let source = pin.sourceApp {
                    LabeledContent("Source", value: source.capitalized)
                }
                if pin.kind == .event, let start = pin.eventStart {
                    LabeledContent("Starts", value: start.formatted(date: .abbreviated, time: .shortened))
                    if let end = pin.eventEnd {
                        LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            Section {
                collectionPicker
                Button {
                    openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
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
                if let urlString = pin.sourceURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("View original post", systemImage: "play.rectangle")
                    }
                }
            }
        }
        .navigationTitle(pin.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Opening a pin resets the ignored-notification counter so it
            // isn't auto-muted.
            pin.lastOpenedAt = Date()
            pin.notifyCount = 0
            try? context.save()
        }
    }

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

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = pin.name
        item.openInMaps(launchOptions: nil)
    }

    private func prettyCategory(_ raw: String) -> String {
        raw.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}
