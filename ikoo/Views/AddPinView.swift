import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Manual pin adding via MKLocalSearch. Tapping a result opens a confirm step
/// (mirroring the post-save review), so a manual save gets the same "here's
/// what you're saving" moment and a success toast — never a silent insert.
struct AddPinView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var selected: MKMapItem?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        selected = item
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unknown place")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let subtitle = item.placemark.title {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if searching {
                    ProgressView()
                } else if results.isEmpty && query.isEmpty {
                    ContentUnavailableView(
                        "Search for a place",
                        systemImage: "magnifyingglass",
                        description: Text("Find a spot to pin — you'll get a heads-up whenever you're nearby.")
                    )
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or address")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .navigationTitle("Add place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $selected) { item in
                AddPinConfirmView(item: item) { savedName in
                    dismiss()
                    AppState.shared.showToast("Saved \(savedName) to your map")
                }
            }
            .task {
                #if DEBUG
                if let q = ProcessInfo.processInfo.environment["IKOO_DEBUG_ADD_QUERY"] {
                    query = q
                    await runSearch()
                    selected = results.first
                }
                #endif
            }
        }
    }

    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        errorMessage = nil
        defer { searching = false }
        do {
            let center = CLLocationManager().location?.coordinate
            results = try await GeocodingService.search(query, near: center)
            if results.isEmpty {
                errorMessage = "No places found for “\(query)”."
            }
        } catch {
            errorMessage = "Search failed — check your connection and try again."
            results = []
        }
    }
}

/// Review-before-save step for a manually chosen place.
struct AddPinConfirmView: View {
    @Environment(\.modelContext) private var context
    let item: MKMapItem
    var onSaved: (String) -> Void

    @State private var collection: String?
    @State private var isEvent = false
    @State private var eventStart: Date = .now
    @State private var hasEventEnd = false
    @State private var eventEnd: Date = .now.addingTimeInterval(3 * 3600)
    @State private var duplicateName: String?

    private var placeName: String { item.name ?? "Saved place" }

    var body: some View {
        Form {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: item.placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Marker(placeName, coordinate: item.placemark.coordinate)
                }
                .frame(height: 160)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }

            Section {
                Text(placeName).font(.headline)
                if let subtitle = item.placemark.title {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section {
                collectionPicker
            }

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
        .navigationTitle("Save to map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .alert("Already saved", isPresented: Binding(
            get: { duplicateName != nil },
            set: { if !$0 { duplicateName = nil } }
        )) {
            Button("OK", role: .cancel) { duplicateName = nil }
        } message: {
            Text("“\(duplicateName ?? "")” is already in your saved places.")
        }
    }

    private var knownCollections: [String] {
        let fromDefaults = UserDefaults.standard.stringArray(forKey: "knownCollections") ?? []
        let fromPins = (try? context.fetch(FetchDescriptor<SavedPin>()))?.compactMap(\.collectionName) ?? []
        return Array(Set(fromDefaults + fromPins)).sorted()
    }

    private var collectionPicker: some View {
        Menu {
            Button("None") { collection = nil }
            ForEach(knownCollections, id: \.self) { name in
                Button {
                    collection = name
                } label: {
                    if collection == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            LabeledContent {
                Text(collection ?? "None")
            } label: {
                Label("Collection", systemImage: "folder")
            }
        }
    }

    private func save() {
        let coordinate = item.placemark.coordinate
        if let existing = PinStore.existingDuplicate(
            name: placeName, latitude: coordinate.latitude,
            longitude: coordinate.longitude, in: context) {
            duplicateName = existing.name
            return
        }
        let pin = SavedPin(
            name: placeName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: item.placemark.title,
            city: item.placemark.locality,
            category: item.pointOfInterestCategory?.rawValue,
            kind: isEvent ? .event : .place
        )
        pin.collectionName = collection
        if isEvent {
            pin.eventStart = eventStart
            pin.eventEnd = hasEventEnd ? eventEnd : nil
        }
        context.insert(pin)
        try? context.save()

        GeofenceManager.shared.rebalance()
        AppState.shared.maybePromptNearbyAlertsAfterSave()
        onSaved(placeName)
    }
}

extension MKMapItem: @retroactive Identifiable {
    public var id: Int { hashValue }
}
