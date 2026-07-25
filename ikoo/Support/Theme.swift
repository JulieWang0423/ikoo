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
        // Beachy retro palette: Isabelline ground, Brunswick-green ink,
        // Verdigris teal primary, Hunyadi gold warm accent. Cool and coastal —
        // deliberately not the warm cream/orange look.
        static let isabelline = Color(hex: 0xF7F0EB)    // off-white ground
        static let cardLight = Color(hex: 0xFFFFFF)
        static let inkLight = Color(hex: 0x1B4436)       // Brunswick green text
        static let mutedLight = Color(hex: 0x5E726B)     // muted green-gray

        // Dark mode leans into deep pine, not neutral charcoal. Cards sit
        // clearly above the ground so surfaces read as layered.
        static let pineDark = Color(hex: 0x142420)
        static let cardDark = Color(hex: 0x274139)
        static let inkDark = Color(hex: 0xF1ECE3)        // warm cream text
        static let mutedDark = Color(hex: 0x9DABA3)

        // Primary accent — Verdigris teal (deepened a touch so white button
        // text stays legible).
        static let verdigris = Color(hex: 0x3E938B)
        static let verdigrisDark = Color(hex: 0x77B9B2)
        // Warm accent — Hunyadi gold, for events / "happening soon".
        static let hunyadi = Color(hex: 0xCC8A1E)
        static let hunyadiDark = Color(hex: 0xE7B255)
    }

    // MARK: - Semantic tokens (light/dark aware)

    /// App background — Isabelline off-white in light, deep pine in dark.
    static let background = dynamic(light: Palette.isabelline, dark: Palette.pineDark)
    /// Raised surfaces (cards, list rows) — distinctly lighter than the ground.
    static let surface = dynamic(light: Palette.cardLight, dark: Palette.cardDark)
    /// Primary text — Brunswick green in light.
    static let ink = dynamic(light: Palette.inkLight, dark: Palette.inkDark)
    /// Secondary text, dividers, muted detail.
    static let inkSecondary = dynamic(light: Palette.mutedLight, dark: Palette.mutedDark)

    /// The one "something is here" accent — arrival, place pins, primary CTAs.
    static let accent = dynamic(light: Palette.verdigris, dark: Palette.verdigrisDark)
    /// Time-based accent — events, "happening soon".
    static let event = dynamic(light: Palette.hunyadi, dark: Palette.hunyadiDark)

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
            ? UIColor(Palette.pineDark) : UIColor(Palette.isabelline) }

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
            ? UIColor(Palette.verdigrisDark) : UIColor(Palette.verdigris) }
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
