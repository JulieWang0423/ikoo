import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct PinDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pin: SavedPin

    @State private var distanceText: String?
    @State private var lookAroundScene: MKLookAroundScene?

    var body: some View {
        List {
            heroSection
            momentSection
            whySavedSection
            detailsSection
            managementSection
        }
        .ikooScreenBackground()
        .navigationTitle(pin.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Opening a pin resets the ignored-notification counter so it
            // isn't auto-muted, and records the visit for auto-mute logic.
            pin.lastOpenedAt = Date()
            pin.notifyCount = 0
            try? context.save()
            updateDistance()
            Task { await loadLookAround() }
        }
    }

    // MARK: - Sections

    /// Prefer an immersive Look Around street view of the place; fall back to
    /// the map. Look Around exists for many urban spots but not all.
    private var heroSection: some View {
        Section {
            Group {
                if let lookAroundScene {
                    LookAroundPreview(initialScene: lookAroundScene)
                } else {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: pin.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Marker(pin.name, coordinate: pin.coordinate)
                            .tint(pin.kind == .event ? Theme.event : Theme.accent)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 200)
            .listRowInsets(EdgeInsets())
        }
        .listRowBackground(Theme.surface)
    }

    /// The "standing on the street" moment: how far, and the two things you
    /// most want right then — directions, and the post that made you save it.
    private var momentSection: some View {
        Section {
            if let distanceText {
                Label(distanceText, systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            if pin.kind == .event, let start = pin.eventStart {
                Label(eventTiming(start: start, end: pin.eventEnd), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.event)
            }
            HStack(spacing: 12) {
                Button(action: openInMaps) {
                    Label("Directions", systemImage: "figure.walk")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                if let url = sourceURL {
                    Link(destination: url) {
                        Label("Watch post", systemImage: "play.fill")
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }
            // Plain monochrome glyphs — the Maps-style diamond symbol renders a
            // fixed blue and ignores tint, so it's deliberately avoided here.
            .symbolRenderingMode(.monochrome)
            .padding(.vertical, 2)
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private var whySavedSection: some View {
        let hasCaption = !(pin.sourceCaption ?? "").isEmpty
        let hasThumb = !(pin.thumbnailURL ?? "").isEmpty
        if hasCaption || hasThumb {
            Section("Why you saved this") {
                if let thumb = pin.thumbnailURL, let url = URL(string: thumb) {
                    thumbnailLink(url: url)
                }
                if let caption = pin.sourceCaption, !caption.isEmpty {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let source = pin.sourceApp, source != "other" {
                    Text("From \(source.capitalized)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    /// The frame from the post that made the user save this — tapping it opens
    /// the original. Thumbnail URLs can expire, so failure degrades silently.
    @ViewBuilder
    private func thumbnailLink(url: URL) -> some View {
        let image = AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                Rectangle().fill(.quaternary).overlay { ProgressView() }
            case .failure:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            if pin.sourceURL != nil {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(10)
            }
        }

        if let sourceURL, let link = sourceURL as URL? {
            Link(destination: link) { image }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } else {
            image
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
        .listRowBackground(Theme.surface)
    }

    private var managementSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { pin.visited },
                set: { visited in
                    pin.visitedAt = visited ? Date() : nil
                    try? context.save()
                    GeofenceManager.shared.rebalance()
                }
            )) {
                Label(pin.visited ? "Been here" : "Mark as visited",
                      systemImage: pin.visited ? "checkmark.circle.fill" : "checkmark.circle")
            }
            collectionPicker
            Toggle(isOn: alertsOn) {
                Label("Nearby alerts", systemImage: "bell")
            }
        } footer: {
            if pin.visited {
                Text("You've been here, so ikoo stops nudging you. Keep alerts on if it's a favorite worth revisiting.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// One "Nearby alerts" control that adapts: for a place you haven't been,
    /// it mutes/unmutes; once visited, it decides whether this favorite keeps
    /// alerting despite the visited default of going quiet.
    private var alertsOn: Binding<Bool> {
        Binding(
            get: { pin.visited ? pin.notifyWhenVisited : !pin.muted },
            set: { on in
                if pin.visited {
                    pin.notifyWhenVisited = on
                    if on { pin.muted = false }
                } else {
                    pin.muted = !on
                }
                if on { pin.notifyCount = 0 }
                try? context.save()
                GeofenceManager.shared.rebalance()
            }
        )
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

    private func loadLookAround() async {
        let request = MKLookAroundSceneRequest(coordinate: pin.coordinate)
        let scene = try? await request.scene
        ikooLog.info("lookAround for \(pin.name, privacy: .public): \(scene == nil ? "none" : "found")")
        lookAroundScene = scene
    }

    static func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int(meters))m away" }
        let km = meters / 1000
        if km >= 100 { return "\(Int(km.rounded())) km away" }
        return String(format: "%.1f km away", km)
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
