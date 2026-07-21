import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Manual pin adding via MKLocalSearch. In M2+ this same search flow is
/// reused inside ConfirmPinView, seeded by LLM extraction.
struct AddPinView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        save(item)
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

    private func save(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        let pin = SavedPin(
            name: item.name ?? query,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: item.placemark.title,
            city: item.placemark.locality,
            category: item.pointOfInterestCategory?.rawValue
        )
        context.insert(pin)
        try? context.save()

        GeofenceManager.shared.rebalance()
        // Contextual, once-only ask for background location after a save.
        AppState.shared.maybePromptNearbyAlertsAfterSave()
        dismiss()
    }
}
