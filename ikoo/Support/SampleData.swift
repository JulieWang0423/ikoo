#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only showcase pins in major cities that have Apple Look Around
/// coverage, so the rich pin-detail page (immersive street view, distance,
/// directions) can be exercised without sharing real posts. Loaded on demand
/// from the Home tab's debug button.
enum SampleData {
    struct Sample {
        let name: String
        let lat: Double
        let lng: Double
        let city: String
        let category: String
        let source: String
        let caption: String
    }

    static let showcase: [Sample] = [
        Sample(name: "Katz's Delicatessen", lat: 40.72224, lng: -73.98733,
               city: "New York", category: "restaurant", source: "tiktok",
               caption: "the pastrami on rye here is unreal 🥪 cash the ticket, tip the cutter, get the pickles #nyc #foodie"),
        Sample(name: "Washington Square Park", lat: 40.73082, lng: -73.99733,
               city: "New York", category: "sight", source: "tiktok",
               caption: "best people-watching in the city 🎷 grab a coffee and sit by the arch #nyc"),
        Sample(name: "The High Line", lat: 40.74799, lng: -74.00485,
               city: "New York", category: "sight", source: "rednote",
               caption: "高线公园散步绝了🌿 从Chelsea Market一路走到哈德逊河 #newyork #纽约"),
        Sample(name: "Brooklyn Bridge", lat: 40.70614, lng: -73.99686,
               city: "New York", category: "sight", source: "tiktok",
               caption: "walk it at sunrise before the crowds 🌉 start from the Brooklyn side #nyc"),
        Sample(name: "Ferry Building Marketplace", lat: 37.79553, lng: -122.39346,
               city: "San Francisco", category: "shop", source: "rednote",
               caption: "旧金山渡轮大厦市集☕️ 周六农夫市场超好逛，Blue Bottle 咖啡必打卡 #sanfrancisco #旅行"),
        Sample(name: "Shibuya Scramble Crossing", lat: 35.65950, lng: 139.70056,
               city: "Tokyo", category: "sight", source: "tiktok",
               caption: "POV: your first time at the busiest crossing on earth 🚦 go up to the Starbucks for the view #tokyo #japan"),
        Sample(name: "Borough Market", lat: 51.50546, lng: -0.09068,
               city: "London", category: "shop", source: "tiktok",
               caption: "best food market in London hands down 🧀 get the grilled cheese from Kappacasein, thank me later #london"),
        Sample(name: "Trevi Fountain", lat: 41.90092, lng: 12.48331,
               city: "Rome", category: "sight", source: "rednote",
               caption: "许愿池真的美到窒息✨ 一定要早上7点前来，没有人超级好拍 #rome #罗马 #旅行攻略"),
        Sample(name: "Gwangjang Market", lat: 37.57013, lng: 126.99969,
               city: "Seoul", category: "restaurant", source: "rednote",
               caption: "广藏市场吃到扶墙出🍲 绿豆饼、生拌牛肉、麻药紫菜包饭全都要 #seoul #首尔美食"),
        Sample(name: "Griffith Observatory", lat: 34.11856, lng: -118.30037,
               city: "Los Angeles", category: "sight", source: "tiktok",
               caption: "sunset here hits different 🌇 park down the hill and walk up, skip the traffic #losangeles #lalife"),
    ]

    /// Insert any showcase pins not already present (matched by name).
    static func loadShowcase(into context: ModelContext) {
        let existing = Set(((try? context.fetch(FetchDescriptor<SavedPin>())) ?? []).map(\.name))
        for s in showcase where !existing.contains(s.name) {
            let pin = SavedPin(
                name: s.name, latitude: s.lat, longitude: s.lng,
                address: s.city, city: s.city, category: s.category,
                kind: .place, sourceApp: s.source, sourceCaption: s.caption
            )
            // Mark a couple visited so the Visited filter has content to show.
            if ProcessInfo.processInfo.environment["IKOO_SEED_VISITED"] == "1",
               ["Katz's Delicatessen", "Brooklyn Bridge"].contains(s.name) {
                pin.visitedAt = Date().addingTimeInterval(-5 * 24 * 3600)
            }
            context.insert(pin)
        }
        try? context.save()
        GeofenceManager.shared.rebalance()
    }
}
#endif
