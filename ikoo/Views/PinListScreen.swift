import SwiftUI
import SwiftData

struct PinListScreen: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<SavedPin> { $0.statusRaw == "active" },
        sort: \SavedPin.createdAt,
        order: .reverse
    ) private var pins: [SavedPin]

    /// Events starting within 7 days, or already ongoing.
    private var happeningSoon: [SavedPin] {
        let now = Date()
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        return pins
            .filter { pin in
                guard pin.kind == .event, let start = pin.eventStart else { return false }
                if let end = pin.effectiveEventEnd, start <= now, now <= end { return true }
                return start > now && start <= horizon
            }
            .sorted { ($0.eventStart ?? .distantFuture) < ($1.eventStart ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !happeningSoon.isEmpty {
                    Section("Happening soon") {
                        ForEach(happeningSoon) { pin in
                            NavigationLink {
                                PinDetailView(pin: pin)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(Theme.event)
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pin.name).font(.headline)
                                        if let start = pin.eventStart {
                                            Text(start, format: .relative(presentation: .named))
                                                .font(.subheadline)
                                                .foregroundStyle(Theme.event)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                ForEach(pins) { pin in
                    NavigationLink {
                        PinDetailView(pin: pin)
                    } label: {
                        row(for: pin)
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
                    .listRowBackground(Theme.surface)
                }
            }
            .ikooScreenBackground()
            .overlay {
                if pins.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "bookmark",
                        description: Text("Add a place from the map tab. Soon you'll be able to share posts from TikTok and RedNote straight into ikoo.")
                    )
                }
            }
            .navigationTitle("Saved")
        }
    }

    @ViewBuilder
    private func row(for pin: SavedPin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pin.kind == .event ? "calendar" : "mappin.circle.fill")
                .foregroundStyle(pin.kind == .event ? Theme.event : Theme.accent)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.name).font(.headline)
                HStack(spacing: 4) {
                    if let city = pin.city {
                        Text(city)
                    }
                    if pin.muted {
                        Image(systemName: "bell.slash.fill")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func delete(_ pin: SavedPin) {
        context.delete(pin)
        try? context.save()
        GeofenceManager.shared.rebalance()
    }

    private func toggleMute(_ pin: SavedPin) {
        pin.muted.toggle()
        if !pin.muted {
            pin.notifyCount = 0
        }
        try? context.save()
        GeofenceManager.shared.rebalance()
    }
}
