import SwiftUI

/// Per-category identity — a vivid color, a real icon, and a short label — so
/// a market, a bar, and a museum read differently at a glance instead of all
/// being a generic gray pin. This is where ikoo's color comes from.
struct CategoryStyle {
    let color: Color
    let symbol: String
    let label: String

    // Tuned to the beachy palette — warm terracotta/mustard against
    // teal/olive/pine, readable on both the Isabelline and pine grounds.
    private enum C {
        static let food = Color(hex: 0xC15A38)   // terracotta
        static let cafe = Color(hex: 0xB0782E)   // caramel
        static let bar = Color(hex: 0x8F5178)    // dusty plum
        static let sight = Color(hex: 0x2F6E5F)  // deep teal-green
        static let nature = Color(hex: 0x6E8B3C) // olive
        static let shop = Color(hex: 0xC0912A)   // mustard
        static let event = Color(hex: 0xCC8A1E)  // Hunyadi gold
        static let other = Color(hex: 0x3E938B)  // Verdigris (default)
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
