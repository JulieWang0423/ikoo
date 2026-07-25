import SwiftUI
import SwiftData

/// The Saved tab is your wishlist, not a dead archive: it opens on the places
/// you still want to try, lets you tick them off as "been here", and keeps a
/// record of where you've been. Visited places drop off the map's nudges.
struct PinListScreen: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<SavedPin> { $0.statusRaw == "active" },
        sort: \SavedPin.createdAt,
        order: .reverse
    ) private var pins: [SavedPin]

    enum Filter: String, CaseIterable {
        case wantToGo = "Want to go"
        case visited = "Visited"
        case all = "All"
    }

    @State private var filter: Filter = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IKOO_DEBUG_SAVED_FILTER"] == "visited" { return .visited }
        #endif
        return .wantToGo
    }()
    @State private var search = ""
    @State private var pushed: SavedPin?

    private var filtered: [SavedPin] {
        pins.filter { pin in
            switch filter {
            case .wantToGo: return !pin.visited
            case .visited: return pin.visited
            case .all: return true
            }
        }
        .filter { search.isEmpty || matches($0, search) }
    }

    /// Upcoming events among the want-to-go set — surfaced first because they
    /// expire. Hidden while searching or viewing visited.
    private var happeningSoon: [SavedPin] {
        guard filter != .visited, search.isEmpty else { return [] }
        let now = Date()
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        return filtered
            .filter { pin in
                guard pin.kind == .event, let start = pin.eventStart else { return false }
                if let end = pin.effectiveEventEnd, start <= now, now <= end { return true }
                return start > now && start <= horizon
            }
            .sorted { ($0.eventStart ?? .distantFuture) < ($1.eventStart ?? .distantFuture) }
    }

    private var mainList: [SavedPin] {
        let soonIDs = Set(happeningSoon.map(\.id))
        return filtered.filter { !soonIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Part of the scrolling content, on the same layer as the rows.
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !happeningSoon.isEmpty {
                    Section("Happening soon") {
                        ForEach(happeningSoon) { pin in
                            pinRow(pin, showEventTiming: true)
                        }
                    }
                }
                Section {
                    ForEach(mainList) { pin in
                        pinRow(pin, showEventTiming: false)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(.compact)
            .ikooScreenBackground()
            .searchable(text: $search, prompt: "Search saved places")
            .overlay {
                if filtered.isEmpty { emptyState }
            }
            .navigationTitle("Saved")
            .navigationDestination(item: $pushed) { pin in
                PinDetailView(pin: pin)
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func pinRow(_ pin: SavedPin, showEventTiming: Bool) -> some View {
        Button {
            pushed = pin
        } label: {
            PlaceCard(pin: pin, trailing: eventTrailing(pin, showEventTiming: showEventTiming))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .leading) {
            Button {
                toggleVisited(pin)
            } label: {
                Label(pin.visited ? "Not yet" : "Been here",
                      systemImage: pin.visited ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(pin.visited ? .gray : Theme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(pin)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                toggleMute(pin)
            } label: {
                Label(pin.muted ? "Unmute" : "Mute",
                      systemImage: pin.muted ? "bell" : "bell.slash")
            }
            .tint(Theme.event)
        }
    }

    private func eventTrailing(_ pin: SavedPin, showEventTiming: Bool) -> String? {
        guard showEventTiming, let start = pin.eventStart else { return nil }
        return start.formatted(.relative(presentation: .named))
    }

    private var emptyState: some View {
        switch filter {
        case .wantToGo:
            ContentUnavailableView(
                "Your wishlist is clear",
                systemImage: "checkmark.circle",
                description: Text("Save places from posts, articles, or the map, and they'll wait here until you go.")
            )
        case .visited:
            ContentUnavailableView(
                "Nowhere checked off yet",
                systemImage: "figure.walk",
                description: Text("Swipe a saved place and tap “Been here” once you've made it there.")
            )
        case .all:
            ContentUnavailableView(
                "Nothing saved yet",
                systemImage: "bookmark",
                description: Text("Share a post or article, or add a place from the map, to start your list.")
            )
        }
    }

    private func matches(_ pin: SavedPin, _ query: String) -> Bool {
        let q = query.lowercased()
        return pin.name.lowercased().contains(q)
            || (pin.city?.lowercased().contains(q) ?? false)
            || (pin.collectionName?.lowercased().contains(q) ?? false)
    }

    private func toggleVisited(_ pin: SavedPin) {
        pin.visitedAt = pin.visited ? nil : Date()
        try? context.save()
        GeofenceManager.shared.rebalance()
    }

    private func delete(_ pin: SavedPin) {
        context.delete(pin)
        try? context.save()
        GeofenceManager.shared.rebalance()
    }

    private func toggleMute(_ pin: SavedPin) {
        pin.muted.toggle()
        if !pin.muted { pin.notifyCount = 0 }
        try? context.save()
        GeofenceManager.shared.rebalance()
    }
}
