import SwiftUI
import UIKit
import CoreText

/// ikoo's design system. The product's idea — get off your phone, then be
/// surprised when you're near a saved place — drives a deliberately quiet,
/// mostly-neutral palette that spends its one saturated accent (Spring Leaves)
/// only on "something is here" moments: a new pin, a primary action, the
/// arrival notification. Events use a second warm accent (Poppy) so time and
/// place never compete for the same signal.
enum Theme {

    // MARK: - Palette (raw)

    private enum Palette {
        // Warm paper ground — light enough to feel fresh, warm enough to stay
        // cozy. Cards sit clearly above it so the UI reads layered, not muddy.
        static let paperLight = Color(hex: 0xF5F0E6)
        static let cardLight = Color(hex: 0xFFFDF8)
        static let inkLight = Color(hex: 0x2B2723)      // warm near-black
        static let mutedLight = Color(hex: 0x8C8377)    // warm gray

        // Warm charcoal in dark mode — not a flat neutral gray.
        static let paperDark = Color(hex: 0x24211D)
        static let cardDark = Color(hex: 0x322E29)
        static let inkDark = Color(hex: 0xF1EBDD)        // warm cream
        static let mutedDark = Color(hex: 0x9C9286)

        // Primary accent — warm poppy. Reads strongly on both grounds, and a
        // red-orange map pin matches the convention people expect.
        static let poppy = Color(hex: 0xD8560E)
        static let poppyLight = Color(hex: 0xEE7433)
        // Event accent — cool teal-blue. Warm/cool split keeps place vs time
        // instantly distinct.
        static let eventTeal = Color(hex: 0x2F6B7D)
        static let eventTealLight = Color(hex: 0x7FB2C4)
    }

    // MARK: - Semantic tokens (light/dark aware)

    /// App background — warm paper in light, warm charcoal in dark.
    static let background = dynamic(light: Palette.paperLight, dark: Palette.paperDark)
    /// Raised surfaces (cards, list rows) — distinctly lighter than the ground.
    static let surface = dynamic(light: Palette.cardLight, dark: Palette.cardDark)
    /// Primary text.
    static let ink = dynamic(light: Palette.inkLight, dark: Palette.inkDark)
    /// Secondary text, dividers, muted detail.
    static let inkSecondary = dynamic(light: Palette.mutedLight, dark: Palette.mutedDark)

    /// The one "something is here" accent — arrival, place pins, primary CTAs.
    static let accent = dynamic(light: Palette.poppy, dark: Palette.poppyLight)
    /// Time-based accent — events, "happening soon".
    static let event = dynamic(light: Palette.eventTeal, dark: Palette.eventTealLight)

    // MARK: - Type

    enum TitleStyle { case bigShoulders, rounded }
    /// Switch the display face for the whole app in one place.
    static let titleStyle: TitleStyle = .rounded

    // The variable font's default instance is Thin, so this is its real
    // PostScript name; the wght variation below pushes it to a heavy weight.
    static let titleFontName = "BigShouldersDisplay-Thin"

    static func titleUIFont(_ size: CGFloat, weight: CGFloat = 700) -> UIFont {
        switch titleStyle {
        case .rounded:
            // SF Pro Rounded — warm, friendly, native. No bundling.
            let w: UIFont.Weight = weight >= 800 ? .heavy : (weight >= 700 ? .bold : .semibold)
            let base = UIFont.systemFont(ofSize: size, weight: w)
            if let desc = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: size)
            }
            return base
        case .bigShoulders:
            // Variable font; pin a heavy weight off the `wght` axis.
            let axis = 0x77676874 // 'wght' four-char code
            let descriptor = UIFontDescriptor(fontAttributes: [
                .name: titleFontName,
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [axis: weight],
            ])
            let uiFont = UIFont(descriptor: descriptor, size: size)
            if uiFont.familyName.contains("Big Shoulders") { return uiFont }
            return .systemFont(ofSize: size, weight: .bold)
        }
    }

    static func title(_ size: CGFloat, weight: CGFloat = 700) -> Font {
        Font(titleUIFont(size, weight: weight))
    }

    // MARK: - Global bar appearance

    /// Call once at launch: nav titles adopt Big Shoulders, bars adopt the
    /// palette. Centralised so every screen inherits the identity for free.
    static func applyAppearance() {
        let inkColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Palette.inkDark) : UIColor(Palette.inkLight) }
        let bgColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Palette.paperDark) : UIColor(Palette.paperLight) }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bgColor
        nav.shadowColor = .clear
        nav.largeTitleTextAttributes = [
            .font: titleUIFont(34, weight: 800),
            .foregroundColor: inkColor,
        ]
        nav.titleTextAttributes = [
            .font: titleUIFont(19, weight: 700),
            .foregroundColor: inkColor,
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = bgColor
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // System alert buttons take their colour from the window tint, not the
        // SwiftUI .tint environment — scope the accent to alert controllers.
        let accentColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Palette.poppyLight) : UIColor(Palette.poppy) }
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = accentColor
    }

    // MARK: - Helpers

    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// Section/screen heading in the ikoo title face.
    func ikooTitle(_ size: CGFloat = 28, weight: CGFloat = 700) -> some View {
        font(Theme.title(size, weight: weight))
    }

    /// Replace the system grouped background with ikoo's warm sand/charcoal.
    func ikooScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}
