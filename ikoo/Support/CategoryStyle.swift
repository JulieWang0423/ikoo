import SwiftUI

/// Per-category identity — a vivid color, a real icon, and a short label — so
/// a market, a bar, and a museum read differently at a glance instead of all
/// being a generic gray pin. This is where ikoo's color comes from.
struct CategoryStyle {
    let color: Color
    let symbol: String
    let label: String

    // Vivid but grounded — tuned to read on both warm paper and dark charcoal.
    private enum C {
        static let food = Color(hex: 0xE1552B)   // tomato
        static let cafe = Color(hex: 0xC77A2E)   // caramel
        static let bar = Color(hex: 0xA6497F)    // plum
        static let sight = Color(hex: 0x2E8C9E)  // teal
        static let nature = Color(hex: 0x5C9A46) // leaf
        static let shop = Color(hex: 0xC2971E)   // gold
        static let event = Color(hex: 0x6A5ACB)  // indigo
        static let other = Color(hex: 0xD8560E)  // poppy (default)
    }

    static func of(_ pin: SavedPin) -> CategoryStyle {
        if pin.kind == .event {
            return CategoryStyle(color: C.event, symbol: "calendar", label: "Event")
        }
        let c = (pin.category ?? "").lowercased()
        switch true {
        case c.contains("restaurant"), c.contains("food"), c.contains("bakery"), c.contains("dinner"):
            return CategoryStyle(color: C.food, symbol: "fork.knife", label: "Food")
        case c.contains("cafe"), c.contains("coffee"), c.contains("tea"):
            return CategoryStyle(color: C.cafe, symbol: "cup.and.saucer.fill", label: "Café")
        case c.contains("bar"), c.contains("night"), c.contains("pub"), c.contains("brewery"), c.contains("winery"):
            return CategoryStyle(color: C.bar, symbol: "wineglass.fill", label: "Nightlife")
        case c.contains("nature"), c.contains("park"), c.contains("beach"), c.contains("garden"), c.contains("trail"):
            return CategoryStyle(color: C.nature, symbol: "leaf.fill", label: "Nature")
        case c.contains("shop"), c.contains("store"), c.contains("market"), c.contains("mall"):
            return CategoryStyle(color: C.shop, symbol: "bag.fill", label: "Shop")
        case c.contains("sight"), c.contains("museum"), c.contains("landmark"),
             c.contains("attraction"), c.contains("theater"), c.contains("gallery"), c.contains("historic"):
            return CategoryStyle(color: C.sight, symbol: "building.columns.fill", label: "Sight")
        default:
            return CategoryStyle(color: C.other, symbol: "mappin", label: "Place")
        }
    }
}
