import SwiftUI

/// ikoo's signature card. Instead of a stock gray-icon list row, each place
/// carries its category's color and icon, a colored category chip, and soft
/// decorative circles bleeding off the corner — distinct and branded, not a
/// system List row. Reused across Saved, Nearby, and group lists.
struct PlaceCard: View {
    let pin: SavedPin
    /// Optional trailing info (e.g. distance) shown in the meta line.
    var trailing: String?

    private var cat: CategoryStyle { CategoryStyle.of(pin) }
    private var tint: Color { pin.visited ? Color.gray : cat.color }

    var body: some View {
        HStack(spacing: 14) {
            iconTile
            VStack(alignment: .leading, spacing: 6) {
                Text(pin.name)
                    .font(Theme.title(19))
                    .foregroundStyle(pin.visited ? Theme.inkSecondary : Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metaLine
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.6))
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: - Pieces

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: 50, height: 50)
            .overlay(
                Image(systemName: pin.visited ? "checkmark" : cat.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(cat.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.14), in: Capsule())
            if let secondary = secondaryText {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var secondaryText: String? {
        if pin.visited, let when = pin.visitedAt {
            return "Visited \(when.formatted(date: .abbreviated, time: .omitted))"
        }
        if let trailing { return trailing }
        return pin.city
    }

    /// Surface + two soft category-colored circles bleeding off the top-right —
    /// the decorative "graphic" flavor, clipped by the card's rounded rect.
    private var cardBackground: some View {
        ZStack(alignment: .topTrailing) {
            Theme.surface
            Circle()
                .fill(tint.opacity(pin.visited ? 0.05 : 0.11))
                .frame(width: 150, height: 150)
                .offset(x: 55, y: -70)
            Circle()
                .fill(tint.opacity(pin.visited ? 0.04 : 0.08))
                .frame(width: 84, height: 84)
                .offset(x: 12, y: -30)
        }
    }
}
