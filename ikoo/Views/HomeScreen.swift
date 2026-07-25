import SwiftUI
import SwiftData
import MapKit

/// Landing tab: a warm, branded overview of your places — stats, collections
/// as a color carousel, cities, and recent saves — rather than a stock
/// grouped list. First-run shows the how-it-works instead.
struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavedPin> { $0.statusRaw == "active" },
           sort: \SavedPin.createdAt, order: .reverse)
    private var pins: [SavedPin]
    @ObservedObject private var geofence = GeofenceManager.shared

    @State private var showNewCollection = false
    @State private var newCollectionName = ""
    @State private var showAlertsExplainer = false
    @State private var showAddSheet = false
    @State private var showPasteLink = false
    @State private var showScreenshot = false
    @State private var debugCity: String?

    // Rotating card colors for collections.
    private let palette: [Color] = [
        Color(hex: 0xD8560E), Color(hex: 0x2E8C9E), Color(hex: 0x6A5ACB),
        Color(hex: 0xC2971E), Color(hex: 0xA6497F), Color(hex: 0x5C9A46),
    ]

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

    private var wantToGoCount: Int { pins.filter { !$0.visited }.count }
    private var upcomingEvents: Int { pins.filter { $0.kind == .event && !$0.isExpiredEvent }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    addBar
                    if pins.isEmpty {
                        gettingStarted
                    } else {
                        statChips
                        if geofence.nearbyAlertsState != .on { alertsBanner }
                        collectionsSection
                        if !cities.isEmpty { citiesSection }
                        recentSection
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Load samples", systemImage: "sparkles") {
                        SampleData.loadShowcase(into: context)
                    }
                }
                #endif
            }
            .navigationDestination(for: SavedPin.self) { pin in
                PinDetailView(pin: pin)
            }
            .alert("New collection", isPresented: $showNewCollection) {
                TextField("e.g. Seoul trip", text: $newCollectionName)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
                Button("Create") { createCollection() }
            } message: {
                Text("Group places for a trip, a city, or a theme. Assign a place from its detail page.")
            }
            .sheet(isPresented: $showAlertsExplainer) {
                NearbyAlertsExplainer().presentationDetents([.large])
            }
            .sheet(isPresented: $showAddSheet) { AddPinView() }
            .sheet(isPresented: $showPasteLink) { PasteLinkView() }
            .sheet(isPresented: $showScreenshot) { ScreenshotImportView() }
            #if DEBUG
            .navigationDestination(item: $debugCity) { city in
                PinGroupList(title: city,
                             pins: pins.filter { ($0.city ?? "Somewhere") == city },
                             startInMap: true)
            }
            .onAppear {
                if let c = ProcessInfo.processInfo.environment["IKOO_DEBUG_OPEN_CITY"] { debugCity = c }
            }
            #endif
        }
        .tint(Theme.accent)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ikoo").font(Theme.title(40)).foregroundStyle(Theme.ink)
            Text(pins.isEmpty
                 ? "Save places now, stumble on them later."
                 : "\(wantToGoCount) \(wantToGoCount == 1 ? "place" : "places") waiting to be found")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Add entry

    private var addBar: some View {
        HStack(spacing: 12) {
            Button { showAddSheet = true } label: {
                addButtonLabel("Add a place", "magnifyingglass", filled: true)
            }
            .buttonStyle(.plain)
            Menu {
                Button { showPasteLink = true } label: { Label("Paste a link", systemImage: "link") }
                Button { showScreenshot = true } label: { Label("From a screenshot", systemImage: "text.viewfinder") }
            } label: {
                addButtonLabel("Import a post", "square.and.arrow.down", filled: false)
            }
        }
        .padding(.horizontal, 20)
    }

    private func addButtonLabel(_ title: String, _ symbol: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.subheadline.weight(.bold))
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(filled ? Color.white : Theme.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(filled ? Theme.accent : Theme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(filled ? Color.clear : Theme.accent.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Stat chips

    private var statChips: some View {
        HStack(spacing: 12) {
            statChip(pins.count, "saved", palette[0], "mappin.fill")
            statChip(wantToGoCount, "to go", palette[2], "bookmark.fill")
            statChip(cities.count, "cities", palette[1], "building.2.fill")
        }
        .padding(.horizontal, 20)
    }

    private func statChip(_ value: Int, _ label: String, _ color: Color, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text("\(value)").font(Theme.title(30)).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            ZStack(alignment: .topTrailing) {
                Theme.surface
                Circle().fill(color.opacity(0.12)).frame(width: 70, height: 70).offset(x: 26, y: -30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Alerts banner

    private var alertsBanner: some View {
        Button { showAlertsExplainer = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on nearby alerts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Get a nudge when you're near a saved place")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Collections")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(collections.enumerated()), id: \.element.name) { index, c in
                        NavigationLink {
                            PinGroupList(title: c.name, pins: c.pins)
                        } label: {
                            collectionCard(name: c.name, count: c.pins.count,
                                           color: palette[index % palette.count])
                        }
                        .buttonStyle(.plain)
                    }
                    newCollectionCard
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func collectionCard(name: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.95))
            Spacer(minLength: 8)
            Text(name)
                .font(Theme.title(19))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(count) \(count == 1 ? "place" : "places")")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(14)
        .frame(width: 158, height: 118, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                color
                Circle().fill(.white.opacity(0.12)).frame(width: 120, height: 120).offset(x: 40, y: 40)
                Circle().fill(.white.opacity(0.08)).frame(width: 70, height: 70).offset(x: 10, y: 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var newCollectionCard: some View {
        Button { showNewCollection = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.title2.weight(.semibold))
                Text("New").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.inkSecondary)
            .frame(width: 110, height: 118)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.inkSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cities

    private var citiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Cities")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cities.prefix(8), id: \.name) { city in
                        NavigationLink {
                            PinGroupList(title: city.name, pins: city.pins)
                        } label: {
                            cityChip(name: city.name, count: city.pins.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func cityChip(name: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .font(.footnote)
                .foregroundStyle(palette[1])
            Text(name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette[1])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.inkSecondary.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recently saved")
            VStack(spacing: 10) {
                ForEach(pins.prefix(4)) { pin in
                    NavigationLink(value: pin) {
                        PlaceCard(pin: pin)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Getting started (empty)

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Never walk past a place you saved.")
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            howItWorks("square.and.arrow.up", "See a place on TikTok or RedNote? Tap Share → ikoo.")
            howItWorks("sparkles", "ikoo reads the caption and pins every place it finds.")
            howItWorks("bell.badge", "Walk near a saved spot someday — ikoo taps you on the shoulder.")
            Button { showAlertsExplainer = true } label: {
                Text("Turn on nearby alerts")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 4)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func howItWorks(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body).foregroundStyle(Theme.accent).frame(width: 24)
            Text(text).font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        newCollectionName = ""
        guard !name.isEmpty else { return }
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
