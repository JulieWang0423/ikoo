import SwiftUI
import SwiftData
import MapKit

/// Landing tab: explains what ikoo does before dropping the user on a map,
/// and organizes saved pins into collections and cities (in the spirit of
/// Apple Maps' library + guides, scaled to MVP).
struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavedPin> { $0.statusRaw == "active" },
           sort: \SavedPin.createdAt, order: .reverse)
    private var pins: [SavedPin]
    @ObservedObject private var geofence = GeofenceManager.shared

    @State private var showNewCollection = false
    @State private var newCollectionName = ""
    @State private var showAlertsExplainer = false
    @State private var debugCity: String?
    @State private var pushedPin: SavedPin?

    private var collections: [(name: String, pins: [SavedPin])] {
        Dictionary(grouping: pins.filter { $0.collectionName != nil }, by: { $0.collectionName! })
            .map { (name: $0.key, pins: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private var cities: [(name: String, pins: [SavedPin])] {
        Dictionary(grouping: pins, by: { $0.city ?? "Somewhere" })
            .map { (name: $0.key, pins: $0.value) }
            .sorted { $0.pins.count > $1.pins.count }
    }

    private var upcomingEvents: Int {
        pins.filter { $0.kind == .event && !$0.isExpiredEvent }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    heroSection
                    if pins.isEmpty {
                        gettingStartedSection
                    } else {
                        statsSection
                        collectionsSection
                        citiesSection
                    }
                }
                .listRowBackground(Theme.surface)
                if !pins.isEmpty {
                    recentSection
                }
            }
            .ikooScreenBackground()
            .navigationTitle("ikoo")
            .navigationDestination(item: $pushedPin) { pin in
                PinDetailView(pin: pin)
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Load samples", systemImage: "sparkles") {
                        SampleData.loadShowcase(into: context)
                    }
                }
            }
            #endif
            .alert("New collection", isPresented: $showNewCollection) {
                TextField("e.g. Seoul trip", text: $newCollectionName)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
                Button("Create") { createCollection() }
            } message: {
                Text("Group pins for a trip, a city, or a theme. Assign pins from their detail page.")
            }
            .sheet(isPresented: $showAlertsExplainer) {
                NearbyAlertsExplainer()
                    .presentationDetents([.large])
            }
            #if DEBUG
            .navigationDestination(item: $debugCity) { city in
                PinGroupList(title: city,
                             pins: pins.filter { ($0.city ?? "Somewhere") == city },
                             startInMap: true)
            }
            .onAppear {
                if let c = ProcessInfo.processInfo.environment["IKOO_DEBUG_OPEN_CITY"] {
                    debugCity = c
                }
            }
            #endif
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Never walk past a place you saved.")
                    .ikooTitle(30)
                    .foregroundStyle(Theme.ink)
                howItWorksRow(number: "1", symbol: "square.and.arrow.up",
                              text: "See a place or event on TikTok or RedNote? Tap Share → ikoo.")
                howItWorksRow(number: "2", symbol: "sparkles",
                              text: "ikoo reads the caption, finds every place mentioned, and pins them on your map.")
                howItWorksRow(number: "3", symbol: "bell.badge",
                              text: "Walk near a saved spot someday — ikoo taps you on the shoulder.")
                switch geofence.nearbyAlertsState {
                case .on:
                    EmptyView()
                case .needsSettings:
                    Button {
                        showAlertsExplainer = true
                    } label: {
                        Label("Nearby alerts are off — fix in Settings", systemImage: "bell.slash")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                default:
                    Button {
                        showAlertsExplainer = true
                    } label: {
                        Label("Turn on nearby alerts", systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func howItWorksRow(number: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var gettingStartedSection: some View {
        Section("Try it now") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing saved yet. Open TikTok or RedNote, find a post that names a place — a café, a market, a night event — and share it to ikoo.")
                Text("Posts whose captions name specific spots work best. You can also add places by hand from the Map tab.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.vertical, 4)
        }
    }

    private var statsSection: some View {
        Section {
            HStack {
                stat(value: pins.count, label: "places")
                Divider()
                stat(value: upcomingEvents, label: "events")
                Divider()
                stat(value: cities.count, label: "cities")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var collectionsSection: some View {
        Section {
            ForEach(collections, id: \.name) { collection in
                NavigationLink {
                    PinGroupList(title: collection.name, pins: collection.pins)
                } label: {
                    Label {
                        HStack {
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.pins.count)").foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder").foregroundStyle(.tint)
                    }
                }
            }
            Button {
                showNewCollection = true
            } label: {
                Label("New collection", systemImage: "folder.badge.plus")
            }
        } header: {
            Text("Collections")
        } footer: {
            if collections.isEmpty {
                Text("Group pins for a trip or a theme — assign a pin from its detail page.")
            }
        }
    }

    private var citiesSection: some View {
        Section("Cities") {
            ForEach(cities.prefix(6), id: \.name) { city in
                NavigationLink {
                    PinGroupList(title: city.name, pins: city.pins)
                } label: {
                    Label {
                        HStack {
                            Text(city.name)
                            Spacer()
                            Text("\(city.pins.count)").foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "building.2").foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Recently saved") {
            ForEach(pins.prefix(3)) { pin in
                Button {
                    pushedPin = pin
                } label: {
                    PlaceCard(pin: pin)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        newCollectionName = ""
        guard !name.isEmpty else { return }
        // A collection exists once a pin carries its name; an empty one has
        // nothing to store yet, so park the newest pin in it as a starter
        // only if the user has pins but no other way to reach the collection.
        // Simpler contract for MVP: creating a collection just pre-registers
        // the name via UserDefaults so it appears in pickers.
        var known = UserDefaults.standard.stringArray(forKey: "knownCollections") ?? []
        if !known.contains(name) {
            known.append(name)
            UserDefaults.standard.set(known, forKey: "knownCollections")
        }
    }
}

/// Reusable view of a filtered set of pins (a collection, a city, …), with a
/// list and an all-pins map so you can see the whole group laid out together.
struct PinGroupList: View {
    let title: String
    let pins: [SavedPin]
    var startInMap = false

    @State private var showMap = false
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: UUID?
    @State private var detailPin: SavedPin?

    var body: some View {
        Group {
            if showMap {
                mapView
            } else {
                listView
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { showMap.toggle() }
                } label: {
                    Label(showMap ? "List" : "Map",
                          systemImage: showMap ? "list.bullet" : "map")
                }
            }
        }
        .sheet(item: $detailPin) { pin in
            NavigationStack { PinDetailView(pin: pin) }
                .presentationDetents([.medium, .large])
                .tint(Theme.accent)
        }
        .onAppear { if startInMap { showMap = true } }
    }

    private var listView: some View {
        List {
            ForEach(pins) { pin in
                Button {
                    detailPin = pin
                } label: {
                    PlaceCard(pin: pin)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .ikooScreenBackground()
    }

    private var mapView: some View {
        Map(position: $position, selection: $selection) {
            ForEach(pins) { pin in
                Marker(pin.name,
                       systemImage: CategoryStyle.of(pin).symbol,
                       coordinate: pin.coordinate)
                    .tint(pin.visited ? .gray : CategoryStyle.of(pin).color)
                    .tag(pin.id)
            }
        }
        .onChange(of: selection) { _, newValue in
            if let id = newValue, let pin = pins.first(where: { $0.id == id }) {
                detailPin = pin
                selection = nil
            }
        }
        .onAppear {
            position = .region(Self.region(for: pins))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// A region framing every pin in the group, with breathing room.
    static func region(for pins: [SavedPin]) -> MKCoordinateRegion {
        let coords = pins.map(\.coordinate)
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.02))
        return MKCoordinateRegion(center: center, span: span)
    }
}
