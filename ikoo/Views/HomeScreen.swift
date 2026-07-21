import SwiftUI
import SwiftData

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
                heroSection
                if pins.isEmpty {
                    gettingStartedSection
                } else {
                    statsSection
                    collectionsSection
                    citiesSection
                    recentSection
                }
            }
            .navigationTitle("ikoo")
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
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Never walk past a place you saved.")
                    .font(.title3.weight(.semibold))
                howItWorksRow(number: "1", symbol: "square.and.arrow.up",
                              text: "See a place or event on TikTok or RedNote? Tap Share → ikoo.")
                howItWorksRow(number: "2", symbol: "sparkles",
                              text: "ikoo reads the caption, finds every place mentioned, and pins them on your map.")
                howItWorksRow(number: "3", symbol: "bell.badge",
                              text: "Walk near a saved spot someday — ikoo taps you on the shoulder.")
                if geofence.authorizationStatus != .authorizedAlways {
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
                NavigationLink {
                    PinDetailView(pin: pin)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.name)
                        if let city = pin.city {
                            Text(city).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
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

/// Reusable filtered pin list (a collection, a city, …).
struct PinGroupList: View {
    let title: String
    let pins: [SavedPin]

    var body: some View {
        List {
            ForEach(pins) { pin in
                NavigationLink {
                    PinDetailView(pin: pin)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: pin.kind == .event ? "calendar" : "mappin.circle.fill")
                            .foregroundStyle(pin.kind == .event ? .orange : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pin.name)
                            if let address = pin.address {
                                Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
