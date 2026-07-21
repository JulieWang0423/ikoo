import SwiftUI
import CoreLocation
import UIKit

/// The staged permission ask for Always-location. Shown before triggering the
/// system prompt so the user understands why — this screen (and the fact the
/// app works without it) is the App Store review safety net.
///
/// Background geofencing needs "Always". iOS reaches it in two steps
/// (When-In-Use, then an upgrade prompt) and only allows the upgrade ask once,
/// so this screen also handles the "you already declined — open Settings" case.
struct NearbyAlertsExplainer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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

            if geofence.nearbyAlertsState == .needsSettings {
                Text("Nearby alerts need “Always” location access, which is currently off. Turn it on in Settings › ikoo › Location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            Button(action: primaryAction) {
                Text(primaryLabel).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not now") { dismiss() }
                .padding(.bottom)
        }
        .padding()
    }

    private var primaryLabel: String {
        switch geofence.nearbyAlertsState {
        case .needsSettings: return "Open Settings"
        case .needsUpgrade: return "Allow background location"
        default: return "Turn on nearby alerts"
        }
    }

    private func primaryAction() {
        NotificationService.requestAuthorization()
        switch geofence.nearbyAlertsState {
        case .needsSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        default:
            geofence.requestNearbyAlerts()
        }
        dismiss()
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
