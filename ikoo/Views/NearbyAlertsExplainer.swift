import SwiftUI
import CoreLocation

/// The staged permission ask for Always-location. Shown before triggering the
/// system prompt so the user understands why — this screen (and the fact the
/// app works without it) is the App Store review safety net.
struct NearbyAlertsExplainer: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var geofence = GeofenceManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.and.waves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Never walk past a saved spot again")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 16) {
                explainerRow(
                    icon: "location.fill",
                    text: "ikoo quietly notices when you're near a place you saved — even when the app is closed."
                )
                explainerRow(
                    icon: "bell.badge.fill",
                    text: "You get one heads-up per spot, at most every few days. No spam."
                )
                explainerRow(
                    icon: "lock.fill",
                    text: "Your location is processed on this device and never uploaded anywhere."
                )
            }
            .padding(.horizontal)
            Spacer()
            Button {
                NotificationService.requestAuthorization()
                if geofence.authorizationStatus == .notDetermined {
                    geofence.requestWhenInUseAuthorization()
                } else {
                    geofence.requestAlwaysAuthorization()
                }
                dismiss()
            } label: {
                Text("Turn on nearby alerts")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not now") { dismiss() }
                .padding(.bottom)
        }
        .padding()
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(text).font(.callout)
        }
    }
}
