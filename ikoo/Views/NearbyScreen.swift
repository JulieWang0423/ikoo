import SwiftUI
import SwiftData
import CoreLocation

/// The pull-twin of the arrival notification: what did I save near where I am
/// right now? The reason to open ikoo when you land somewhere — no waiting to
/// physically cross a geofence.
struct NearbyScreen: View {
    @Query(filter: #Predicate<SavedPin> { $0.statusRaw == "active" })
    private var pins: [SavedPin]
    @ObservedObject private var geofence = GeofenceManager.shared

    private struct Bucket: Identifiable {
        let id: String
        let title: String
        let pins: [(pin: SavedPin, meters: CLLocationDistance)]
    }

    private var buckets: [Bucket] {
        guard let here = geofence.currentLocation else { return [] }
        let ranked = pins
            .map { (pin: $0, meters: here.distance(from: $0.location)) }
            .sorted { $0.meters < $1.meters }
        func within(_ lo: CLLocationDistance, _ hi: CLLocationDistance) -> [(SavedPin, CLLocationDistance)] {
            ranked.filter { $0.meters >= lo && $0.meters < hi }.map { ($0.pin, $0.meters) }
        }
        return [
            Bucket(id: "here", title: "Right around you", pins: within(0, 1_000)),
            Bucket(id: "close", title: "A short trip away", pins: within(1_000, 15_000)),
            Bucket(id: "city", title: "Elsewhere in the area", pins: within(15_000, 150_000)),
            Bucket(id: "far", title: "Farther afield", pins: within(150_000, .greatestFiniteMagnitude)),
        ].filter { !$0.pins.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if geofence.authorizationStatus == .notDetermined || geofence.authorizationStatus == .denied {
                    permissionState
                } else if geofence.currentLocation == nil {
                    locatingState
                } else if buckets.isEmpty {
                    emptyState
                } else {
                    nearbyList
                }
            }
            .ikooScreenBackground()
            .navigationTitle("Nearby")
        }
        .onAppear { geofence.requestForegroundLocation() }
    }

    private var nearbyList: some View {
        List {
            ForEach(buckets) { bucket in
                Section(bucket.title) {
                    ForEach(bucket.pins, id: \.pin.id) { entry in
                        NavigationLink {
                            PinDetailView(pin: entry.pin)
                        } label: {
                            row(entry.pin, meters: entry.meters)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
    }

    private func row(_ pin: SavedPin, meters: CLLocationDistance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pin.kind == .event ? "calendar" : "mappin.circle.fill")
                .foregroundStyle(pin.kind == .event ? Theme.event : Theme.accent)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.name).font(.headline)
                if let city = pin.city {
                    Text(city).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(PinDetailView.formatDistance(meters))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pin.kind == .event ? Theme.event : Theme.accent)
                .monospacedDigit()
        }
    }

    private var permissionState: some View {
        ContentUnavailableView {
            Label("See what's near you", systemImage: "location.circle")
        } description: {
            Text("ikoo needs your location to show saved places around you right now.")
        } actions: {
            Button("Allow location") { geofence.requestForegroundLocation() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }

    private var locatingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding your location…").foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing saved near here yet",
            systemImage: "mappin.slash",
            description: Text("Save places from posts or articles, and they'll show up here whenever you're close.")
        )
    }
}
