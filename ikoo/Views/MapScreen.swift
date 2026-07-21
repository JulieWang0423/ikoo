import SwiftUI
import SwiftData
import MapKit

struct MapScreen: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavedPin> { $0.statusRaw == "active" }) private var pins: [SavedPin]
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var geofence = GeofenceManager.shared

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selection: UUID?
    @State private var detailPin: SavedPin?
    @State private var showAddSheet = false
    @State private var showAlertsExplainer = false

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selection) {
                UserAnnotation()
                ForEach(pins) { pin in
                    Marker(pin.name, systemImage: pin.kind == .event ? "calendar" : "mappin", coordinate: pin.coordinate)
                        .tint(pin.kind == .event ? .orange : .red)
                        .tag(pin.id)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle("ikoo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if geofence.authorizationStatus != .authorizedAlways {
                        Button {
                            showAlertsExplainer = true
                        } label: {
                            Label("Enable nearby alerts", systemImage: "bell.badge")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add place", systemImage: "plus")
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                if let id = newValue, let pin = pins.first(where: { $0.id == id }) {
                    detailPin = pin
                    selection = nil
                }
            }
            .onChange(of: appState.selectedPinID) { _, newValue in
                if let id = newValue, let pin = pins.first(where: { $0.id == id }) {
                    detailPin = pin
                    appState.selectedPinID = nil
                }
            }
            .sheet(item: $detailPin) { pin in
                NavigationStack {
                    PinDetailView(pin: pin)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                #if DEBUG
                // Automated-test hook: simulate a notification tap opening the
                // named pin's detail (the "moment that matters").
                if let target = ProcessInfo.processInfo.environment["IKOO_DEBUG_OPEN_PIN"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        detailPin = pins.first { $0.name.contains(target) }
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAddSheet) {
                AddPinView()
            }
            .sheet(isPresented: $showAlertsExplainer) {
                NearbyAlertsExplainer()
                    .presentationDetents([.large])
            }
        }
    }
}
