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
        static let beigeSand = Color(hex: 0xE1DBC9)
        static let charcoal = Color(hex: 0x3C3C3C)
        static let slate = Color(hex: 0x6B7B84)
        static let slateLight = Color(hex: 0x92A2A6)
        // Primary accent — warm poppy. Reads strongly on both sand and charcoal,
        // and a red-orange map pin matches the convention people expect.
        static let poppy = Color(hex: 0xD8560E)
        static let poppyLight = Color(hex: 0xE8722E)
        // Event accent — cool teal-blue. Warm/cool split keeps place vs time
        // instantly distinct; deep enough to stay readable on sand.
        static let eventTeal = Color(hex: 0x2F6B7D)
        static let eventTealLight = Color(hex: 0x7FB2C4)
        // Slightly warmer/cooler surface tints than the pure base, for cards.
        static let sandDim = Color(hex: 0xD6CFBA)
        static let charcoalLift = Color(hex: 0x484848)
    }

    // MARK: - Semantic tokens (light/dark aware)

    /// App background — warm sand in light, near-charcoal in dark.
    static let background = dynamic(light: Palette.beigeSand, dark: Palette.charcoal)
    /// Raised surfaces (cards, list rows).
    static let surface = dynamic(light: Color(hex: 0xEDE8DA), dark: Palette.charcoalLift)
    /// Primary text.
    static let ink = dynamic(light: Palette.charcoal, dark: Palette.beigeSand)
    /// Secondary text, dividers, muted detail.
    static let inkSecondary = dynamic(light: Palette.slate, dark: Palette.slateLight)

    /// The one "something is here" accent — arrival, place pins, primary CTAs.
    static let accent = dynamic(light: Palette.poppy, dark: Palette.poppyLight)
    /// Time-based accent — events, "happening soon".
    static let event = dynamic(light: Palette.eventTeal, dark: Palette.eventTealLight)

    // MARK: - Type

    // The variable font's default instance is Thin, so this is its real
    // PostScript name; the wght variation below pushes it to a heavy weight.
    static let titleFontName = "BigShouldersDisplay-Thin"

    /// Big Shoulders is a variable font; pin a specific weight off the `wght`
    /// axis so titles render heavy and consistent instead of the light default.
    /// Falls back to a bold system font if the family failed to register.
    static func titleUIFont(_ size: CGFloat, weight: CGFloat = 700) -> UIFont {
        let axis = 0x77676874 // 'wght' four-char code
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: titleFontName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [axis: weight],
        ])
        let uiFont = UIFont(descriptor: descriptor, size: size)
        if uiFont.familyName.contains("Big Shoulders") {
            return uiFont
        }
        return .systemFont(ofSize: size, weight: .bold)
    }

    static func title(_ size: CGFloat, weight: CGFloat = 700) -> Font {
        Font(titleUIFont(size, weight: weight))
    }

    // MARK: - Global bar appearance

    /// Call once at launch: nav titles adopt Big Shoulders, bars adopt the
    /// palette. Centralised so every screen inherits the identity for free.
    static func applyAppearance() {
        let inkColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Palette.beigeSand) : UIColor(Palette.charcoal) }
        let bgColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Palette.charcoal) : UIColor(Palette.beigeSand) }

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
