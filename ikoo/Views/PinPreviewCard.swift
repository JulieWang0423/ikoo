import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Compact card shown when a pin is tapped on the map — instead of a big sheet
/// that re-shows a map you're already looking at. Leads with the useful stuff:
/// why you saved it, how far, and one-tap actions. Tap it to open full detail.
struct PinPreviewCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var pin: SavedPin
    var onDetails: () -> Void
    var onClose: () -> Void

    @State private var distanceText: String?

    private var cat: CategoryStyle { CategoryStyle.of(pin) }
    private var accent: Color { pin.visited ? .gray : cat.color }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onDetails) {
                    HStack(alignment: .top, spacing: 12) {
                        leadingVisual
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pin.name)
                                .font(Theme.title(21))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            metaLine
                            if let caption = pin.sourceCaption, !caption.isEmpty {
                                Text(caption)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            } else if let address = pin.address {
                                Text(address)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Theme.inkSecondary.opacity(0.25))

            HStack(spacing: 0) {
                action("Directions", "figure.walk", tint: Theme.accent, action: openInMaps)
                if pin.sourceURL != nil {
                    verticalDivider
                    action("Watch post", "play.fill", tint: Theme.accent, action: openSource)
                }
                verticalDivider
                action(pin.visited ? "Been here" : "Been here?",
                       pin.visited ? "checkmark.circle.fill" : "checkmark.circle",
                       tint: pin.visited ? .gray : Theme.accent,
                       action: toggleVisited)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.inkSecondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .onAppear(perform: updateDistance)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var leadingVisual: some View {
        let size: CGFloat = 60
        if let thumb = pin.thumbnailURL, let url = URL(string: thumb) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: iconTile
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if pin.sourceURL != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(3)
                }
            }
        } else {
            iconTile.frame(width: size, height: size)
        }
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(accent.opacity(0.16))
            .overlay(
                Image(systemName: pin.visited ? "checkmark" : cat.symbol)
                    .font(.title2)
                    .foregroundStyle(accent)
            )
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(cat.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(accent.opacity(0.14), in: Capsule())
            if pin.visited {
                Label("Visited", systemImage: "checkmark.circle.fill").foregroundStyle(.gray)
            } else if let distanceText {
                Label(distanceText, systemImage: "location.fill").foregroundStyle(accent)
            }
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
    }

    private var verticalDivider: some View {
        Rectangle().fill(Theme.inkSecondary.opacity(0.2)).frame(width: 0.5, height: 30)
    }

    private func action(_ title: String, _ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body)
                Text(title).font(.caption2)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func updateDistance() {
        guard let here = CLLocationManager().location else { return }
        distanceText = PinDetailView.formatDistance(here.distance(from: pin.location))
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = pin.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func openSource() {
        guard let s = pin.sourceURL, let url = URL(string: s) else { return }
        UIApplication.shared.open(url)
    }

    private func toggleVisited() {
        pin.visitedAt = pin.visited ? nil : Date()
        try? context.save()
        GeofenceManager.shared.rebalance()
    }

    private func prettyCategory(_ raw: String) -> String {
        raw.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}
