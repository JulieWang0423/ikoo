import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// A place's full detail. Deliberately not a stack of grouped rows: a branded
/// hero, one calm meta line (category + distance), clean actions, then tidy
/// info — with each fact shown exactly once.
struct PinDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pin: SavedPin

    @State private var distanceText: String?
    @State private var lookAroundScene: MKLookAroundScene?

    private var cat: CategoryStyle { CategoryStyle.of(pin) }
    private var caption: String? {
        let c = pin.sourceCaption?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (c?.isEmpty == false) ? c : nil
    }
    private var sourceName: String? {
        guard let s = pin.sourceApp, s != "other" else { return nil }
        return s.capitalized
    }

    private var hasThumb: Bool { !(pin.thumbnailURL ?? "").isEmpty }
    private var hasWhySaved: Bool { caption != nil || hasThumb }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                titleBlock
                actions
                if hasWhySaved { whySaved }
                if lookAroundScene != nil { lookAroundSection }
                detailsCard
                managementCard
            }
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Opening a pin clears the ignored-notification counter so it isn't
            // auto-muted, and records the visit.
            pin.lastOpenedAt = Date()
            pin.notifyCount = 0
            try? context.save()
            updateDistance()
            Task { await loadLookAround() }
        }
    }

    // MARK: - Title (Apple Maps style: big, left-aligned, buttons beneath)

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pin.name)
                .font(Theme.title(30))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            if pin.kind == .event, let start = pin.eventStart {
                Label(eventTiming(start: start, end: pin.eventEnd), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.event)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
    }

    private var subtitle: String {
        var parts = [cat.label]
        if let distanceText { parts.append(distanceText) }
        if pin.visited { parts.append("Visited") }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: openInMaps) { pill("Directions", "figure.walk", filled: true) }
                .buttonStyle(.plain)
            if let url = sourceURL {
                Link(destination: url) { pill("Watch post", "play.fill", filled: false) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Look Around (moved below the fold)

    private var lookAroundSection: some View {
        Group {
            if let lookAroundScene {
                LookAroundPreview(initialScene: lookAroundScene)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
    }

    private func pill(_ title: String, _ symbol: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.subheadline.weight(.bold))
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(filled ? Color.white : Theme.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(filled ? Theme.accent : Theme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(filled ? Color.clear : Theme.accent.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Why saved

    private var whySaved: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Why you saved this")
            if let thumb = pin.thumbnailURL, let url = URL(string: thumb) {
                thumbnailImage(url)
            }
            if let caption {
                Text(caption).font(.callout).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(savedLine).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 20)
    }

    /// The frame from the post that made the user save this — tap to watch.
    @ViewBuilder
    private func thumbnailImage(_ url: URL) -> some View {
        let img = AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
            case .empty: Rectangle().fill(.quaternary).overlay(ProgressView())
            default: Color.clear
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if sourceURL != nil {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(10)
            }
        }
        if let sourceURL {
            Link(destination: sourceURL) { img }
        } else {
            img
        }
    }

    private var savedLine: String {
        let date = pin.createdAt.formatted(date: .abbreviated, time: .omitted)
        if let sourceName { return "Saved from \(sourceName) · \(date)" }
        return "Saved \(date)"
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsCard: some View {
        let showSavedRow = !hasWhySaved  // otherwise it's in the "why saved" line
        let hasEvent = pin.kind == .event && pin.eventStart != nil
        if pin.address != nil || hasEvent || showSavedRow {
            infoCard {
                if let address = pin.address {
                    infoRow("Address", address)
                    if hasEvent || showSavedRow { rowDivider }
                }
                if hasEvent, let start = pin.eventStart {
                    infoRow("Starts", start.formatted(date: .abbreviated, time: .shortened))
                    if let end = pin.eventEnd {
                        rowDivider
                        infoRow("Ends", end.formatted(date: .abbreviated, time: .shortened))
                    }
                    if showSavedRow { rowDivider }
                }
                if showSavedRow {
                    infoRow("Saved", pin.createdAt.formatted(date: .abbreviated, time: .omitted))
                    if let sourceName { rowDivider; infoRow("Source", sourceName) }
                }
            }
        }
    }

    // MARK: - Management

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoCard {
                Toggle(isOn: visitedBinding) {
                    Label(pin.visited ? "Been here" : "Mark as visited",
                          systemImage: pin.visited ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16).padding(.vertical, 8)
                rowDivider
                collectionRow
                rowDivider
                Toggle(isOn: alertsOn) {
                    Label("Nearby alerts", systemImage: "bell").foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            if pin.visited {
                Text("You've been here, so ikoo stops nudging you. Keep alerts on if it's a favorite worth revisiting.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var visitedBinding: Binding<Bool> {
        Binding(
            get: { pin.visited },
            set: { visited in
                pin.visitedAt = visited ? Date() : nil
                try? context.save()
                GeofenceManager.shared.rebalance()
            }
        )
    }

    private var collectionRow: some View {
        Menu {
            Button("None") { setCollection(nil) }
            ForEach(knownCollections, id: \.self) { name in
                Button {
                    setCollection(name)
                } label: {
                    if pin.collectionName == name { Label(name, systemImage: "checkmark") }
                    else { Text(name) }
                }
            }
        } label: {
            HStack {
                Label("Collection", systemImage: "folder").foregroundStyle(Theme.ink)
                Spacer()
                Text(pin.collectionName ?? "None").foregroundStyle(Theme.inkSecondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Theme.inkSecondary)
            }
            .font(.body)
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    /// Adapts: mute/unmute before you've been, keep-or-silence once visited.
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

    // MARK: - Reusable bits

    private func infoCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.inkSecondary.opacity(0.15)).padding(.leading, 16)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkSecondary)
    }

    // MARK: - Data helpers

    private var knownCollections: [String] {
        let fromDefaults = UserDefaults.standard.stringArray(forKey: "knownCollections") ?? []
        let fromPins = (try? context.fetch(FetchDescriptor<SavedPin>()))?.compactMap(\.collectionName) ?? []
        return Array(Set(fromDefaults + fromPins)).sorted()
    }

    private func setCollection(_ name: String?) {
        pin.collectionName = name
        try? context.save()
    }

    private var sourceURL: URL? {
        guard let urlString = pin.sourceURL else { return nil }
        return URL(string: urlString)
    }

    private func updateDistance() {
        guard let here = CLLocationManager().location else { return }
        distanceText = Self.formatDistance(here.distance(from: pin.location))
    }

    private func loadLookAround() async {
        let request = MKLookAroundSceneRequest(coordinate: pin.coordinate)
        lookAroundScene = try? await request.scene
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
        if start > now { return "Starts \(start.formatted(.relative(presentation: .named)))" }
        return start.formatted(date: .abbreviated, time: .shortened)
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = pin.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
