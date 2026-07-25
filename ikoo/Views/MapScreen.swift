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
    @State private var previewPin: SavedPin?
    @State private var detailPin: SavedPin?
    @State private var showAddSheet = false
    @State private var showPasteLink = false
    @State private var showAlertsExplainer = false
    @State private var showingAll = false

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selection) {
                UserAnnotation()
                ForEach(pins) { pin in
                    Marker(pin.name, systemImage: CategoryStyle.of(pin).symbol, coordinate: pin.coordinate)
                        .tint(pin.visited ? .gray : CategoryStyle.of(pin).color)
                        .tag(pin.id)
                }
            }
            .mapControls {
                MapCompass()
            }
            .overlay(alignment: .bottomLeading) {
                if previewPin == nil {
                    Button {
                        withAnimation {
                            if showingAll || pins.isEmpty {
                                position = .userLocation(fallback: .automatic)
                            } else {
                                position = .region(PinGroupList.region(for: Array(pins)))
                            }
                            showingAll.toggle()
                        }
                    } label: {
                        Image(systemName: showingAll ? "location.fill" : "arrow.up.left.and.arrow.down.right")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22, height: 22)
                            .padding(11)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    }
                    .accessibilityLabel(showingAll ? "Center on me" : "Show all my places")
                    .padding(.leading, 12)
                    // Clear Apple's map attribution at the bottom-left.
                    .padding(.bottom, 44)
                }
            }
            .overlay(alignment: .bottom) {
                if let previewPin {
                    PinPreviewCard(
                        pin: previewPin,
                        onDetails: {
                            let p = previewPin
                            self.previewPin = nil
                            detailPin = p
                        },
                        onClose: { withAnimation { self.previewPin = nil } }
                    )
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: previewPin?.id)
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
                    Menu {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Search for a place", systemImage: "magnifyingglass")
                        }
                        Button {
                            showPasteLink = true
                        } label: {
                            Label("Paste a link", systemImage: "link")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                if let id = newValue, let pin = pins.first(where: { $0.id == id }) {
                    withAnimation { previewPin = pin }
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
                .tint(Theme.accent)
            }
            .onAppear {
                #if DEBUG
                // Automated-test hook: simulate a notification tap opening the
                // named pin's detail (the "moment that matters").
                if let target = ProcessInfo.processInfo.environment["IKOO_DEBUG_OPEN_PIN"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation { previewPin = pins.first { $0.name.contains(target) } }
                    }
                }
                if let target = ProcessInfo.processInfo.environment["IKOO_DEBUG_OPEN_DETAIL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        detailPin = pins.first { $0.name.contains(target) }
                    }
                }
                if ProcessInfo.processInfo.environment["IKOO_DEBUG_ADD"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showAddSheet = true
                    }
                }
                if ProcessInfo.processInfo.environment["IKOO_DEBUG_FIT_ALL"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if !pins.isEmpty {
                            position = .region(PinGroupList.region(for: Array(pins)))
                            showingAll = true
                        }
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAddSheet) {
                AddPinView()
            }
            .sheet(isPresented: $showPasteLink) {
                PasteLinkView()
            }
            .sheet(isPresented: $showAlertsExplainer) {
                NearbyAlertsExplainer()
                    .presentationDetents([.large])
            }
        }
    }
}
