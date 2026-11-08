import SwiftUI

/// Colors shared by the main panel, flyouts, and plugins.
public struct DeckTheme: Equatable, Sendable {
    public let isDark: Bool
    public let cardTop: Color
    public let cardBottom: Color
    public let cardStroke: Color
    public let cardGlow: Color
    public let shadow: Color
    public let primary: Color
    public let secondary: Color
    public let tertiary: Color
    public let track: Color
    public let accent: Color
    public let accentSoft: Color
    public let selectedLeading: Color
    public let selectedTrailing: Color
    public let roundFill: Color
    public let roundGlyph: Color
    public let rowHover: Color
    public let inset: Color
    public let warning: Color
    public let positive: Color
    public let negative: Color
    /// The second series of a graph or ring, next to `accent`.
    public let magenta: Color
    /// The third series.
    public let amber: Color
    /// Blue text: stronger than `accent` where the background is dark.
    public let heading: Color

    public static let light = DeckTheme(
        isDark: false,
        cardTop: Color(red: 0.985, green: 0.988, blue: 0.992),
        cardBottom: Color(red: 0.902, green: 0.914, blue: 0.933),
        cardStroke: Color.black.opacity(0.09),
        cardGlow: Color(red: 0.55, green: 0.71, blue: 1.0).opacity(0.16),
        shadow: Color.black.opacity(0.16),
        primary: Color(red: 0.227, green: 0.239, blue: 0.263),
        secondary: Color(red: 0.533, green: 0.557, blue: 0.592),
        tertiary: Color(red: 0.690, green: 0.706, blue: 0.733),
        track: Color(red: 0.827, green: 0.839, blue: 0.859),
        accent: Color(red: 0.169, green: 0.490, blue: 0.965),
        accentSoft: Color(red: 0.502, green: 0.706, blue: 1.0),
        selectedLeading: Color(red: 0.169, green: 0.490, blue: 0.965).opacity(0.17),
        selectedTrailing: Color(red: 0.169, green: 0.490, blue: 0.965).opacity(0.05),
        roundFill: Color(red: 0.847, green: 0.859, blue: 0.878),
        roundGlyph: Color(red: 0.263, green: 0.275, blue: 0.298),
        rowHover: Color.black.opacity(0.045),
        inset: Color.black.opacity(0.035),
        warning: Color(red: 0.827, green: 0.533, blue: 0.0),
        positive: Color(red: 0.180, green: 0.749, blue: 0.341),
        negative: Color(red: 0.898, green: 0.243, blue: 0.243),
        magenta: Color(red: 0.914, green: 0.227, blue: 0.541),
        amber: Color(red: 0.937, green: 0.659, blue: 0.0),
        heading: Color(red: 0.094, green: 0.420, blue: 0.898)
    )

    public static let dark = DeckTheme(
        isDark: true,
        cardTop: Color(red: 0.110, green: 0.149, blue: 0.247),
        cardBottom: Color(red: 0.059, green: 0.086, blue: 0.161),
        cardStroke: Color.white.opacity(0.11),
        cardGlow: Color(red: 0.31, green: 0.49, blue: 0.86).opacity(0.13),
        shadow: Color.black.opacity(0.38),
        primary: Color(red: 0.953, green: 0.957, blue: 0.965),
        secondary: Color(red: 0.580, green: 0.592, blue: 0.624),
        tertiary: Color(red: 0.498, green: 0.510, blue: 0.541),
        track: Color(red: 0.302, green: 0.310, blue: 0.333),
        accent: Color(red: 0.169, green: 0.510, blue: 1.0),
        accentSoft: Color(red: 0.412, green: 0.647, blue: 1.0),
        selectedLeading: Color(red: 0.169, green: 0.510, blue: 1.0).opacity(0.26),
        selectedTrailing: Color(red: 0.169, green: 0.510, blue: 1.0).opacity(0.07),
        roundFill: Color(red: 0.333, green: 0.341, blue: 0.365),
        roundGlyph: Color(red: 0.941, green: 0.945, blue: 0.953),
        rowHover: Color.white.opacity(0.06),
        inset: Color.white.opacity(0.045),
        warning: Color(red: 1.0, green: 0.741, blue: 0.180),
        positive: Color(red: 0.255, green: 0.839, blue: 0.431),
        negative: Color(red: 1.0, green: 0.353, blue: 0.353),
        magenta: Color(red: 0.965, green: 0.306, blue: 0.620),
        amber: Color(red: 1.0, green: 0.769, blue: 0.051),
        heading: Color(red: 0.255, green: 0.608, blue: 1.0)
    )

    public static let glassLight = DeckTheme(
        isDark: false,
        cardTop: Color(red: 0.985, green: 0.988, blue: 0.992),
        cardBottom: Color(red: 0.955, green: 0.961, blue: 0.970),
        cardStroke: Color.black.opacity(0.08),
        cardGlow: .clear,
        shadow: Color.black.opacity(0.12),
        primary: Color.black.opacity(0.86),
        secondary: Color.black.opacity(0.65),
        tertiary: Color.black.opacity(0.44),
        track: Color.black.opacity(0.14),
        accent: light.accent,
        accentSoft: light.accentSoft,
        selectedLeading: light.accent.opacity(0.12),
        selectedTrailing: light.accent.opacity(0.035),
        roundFill: Color.white.opacity(0.42),
        roundGlyph: Color.black.opacity(0.78),
        rowHover: Color.black.opacity(0.06),
        inset: Color.white.opacity(0.26),
        warning: light.warning,
        positive: light.positive,
        negative: light.negative,
        magenta: light.magenta,
        amber: light.amber,
        heading: light.heading
    )

    public static let glassDark = DeckTheme(
        isDark: true,
        cardTop: Color(red: 0.16, green: 0.17, blue: 0.19),
        cardBottom: Color(red: 0.12, green: 0.13, blue: 0.15),
        cardStroke: Color.white.opacity(0.10),
        cardGlow: .clear,
        shadow: Color.black.opacity(0.30),
        primary: Color.white.opacity(0.96),
        secondary: Color.white.opacity(0.68),
        tertiary: Color.white.opacity(0.5),
        track: Color.white.opacity(0.2),
        accent: dark.accent,
        accentSoft: dark.accentSoft,
        selectedLeading: dark.accent.opacity(0.20),
        selectedTrailing: dark.accent.opacity(0.06),
        roundFill: Color.white.opacity(0.14),
        roundGlyph: Color.white.opacity(0.92),
        rowHover: Color.white.opacity(0.08),
        inset: Color.white.opacity(0.07),
        warning: dark.warning,
        positive: dark.positive,
        negative: dark.negative,
        magenta: dark.magenta,
        amber: dark.amber,
        heading: dark.heading
    )

    /// Neutral, solid label colors for translucent controls in the light panel.
    public static let controlCenterLight = DeckTheme(
        isDark: false,
        cardTop: glassLight.cardTop,
        cardBottom: glassLight.cardBottom,
        cardStroke: glassLight.cardStroke,
        cardGlow: .clear,
        shadow: .clear,
        primary: Color(white: 0.07),
        secondary: Color(white: 0.16),
        tertiary: Color(white: 0.20),
        track: glassLight.track,
        accent: glassLight.accent,
        accentSoft: glassLight.accentSoft,
        selectedLeading: glassLight.selectedLeading,
        selectedTrailing: glassLight.selectedTrailing,
        roundFill: glassLight.roundFill,
        roundGlyph: Color(white: 0.12),
        rowHover: glassLight.rowHover,
        inset: glassLight.inset,
        warning: glassLight.warning,
        positive: glassLight.positive,
        negative: glassLight.negative,
        magenta: glassLight.magenta,
        amber: glassLight.amber,
        heading: Color(white: 0.09)
    )

    /// High-contrast foregrounds for dark menu bar controls.
    public static let controlCenter = DeckTheme(
        isDark: true,
        cardTop: glassDark.cardTop,
        cardBottom: glassDark.cardBottom,
        cardStroke: glassDark.cardStroke,
        cardGlow: .clear,
        shadow: .clear,
        primary: .white,
        secondary: Color(white: 0.92),
        tertiary: Color(white: 0.83),
        track: Color.white.opacity(0.28),
        accent: glassDark.accent,
        accentSoft: glassDark.accentSoft,
        selectedLeading: glassDark.selectedLeading,
        selectedTrailing: glassDark.selectedTrailing,
        roundFill: Color.white.opacity(0.20),
        roundGlyph: .white,
        rowHover: Color.white.opacity(0.13),
        inset: Color.black.opacity(0.12),
        warning: glassDark.warning,
        positive: glassDark.positive,
        negative: glassDark.negative,
        magenta: glassDark.magenta,
        amber: glassDark.amber,
        heading: .white
    )

    public static let cardRadius: CGFloat = 22
    /// The clear space between cards, where the desktop shows through.
    public static let cardSpacing: CGFloat = 7
    public static let insetRadius: CGFloat = 12
    public static let panelWidth: CGFloat = 300
    public static let flyoutWidth: CGFloat = 320
}

private struct DeckThemeKey: EnvironmentKey {
    static let defaultValue = DeckTheme.light
}

private struct DeckUsesGlassKey: EnvironmentKey {
    static let defaultValue = true
}

private struct DeckUsesSharedSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Use the containing popover's material instead of drawing another card.
    var deckUsesSharedSurface: Bool {
        get { self[DeckUsesSharedSurfaceKey.self] }
        set { self[DeckUsesSharedSurfaceKey.self] = newValue }
    }

    var deckTheme: DeckTheme {
        get { self[DeckThemeKey.self] }
        set { self[DeckThemeKey.self] = newValue }
    }

    /// Disable live system controls and background material for image rendering.
    var deckUsesGlass: Bool {
        get { self[DeckUsesGlassKey.self] }
        set { self[DeckUsesGlassKey.self] = newValue }
    }
}

public enum DeckGlass {
    public static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

public extension View {
    /// Applies the native material to shaped controls on supported systems.
    func deckGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: Color = .clear
    ) -> some View {
        modifier(DeckGlassModifier(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }
}

private struct DeckGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.deckUsesGlass) private var usesGlass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let tint: Color?
    let interactive: Bool
    let fallback: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesGlass, !reduceTransparency {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(shape.fill(tint ?? fallback))
        }
    }
}

/// Resolves the theme from the current color scheme for everything inside it.
public struct DeckThemeRoot<Content: View>: View {
    @AppStorage("ui.pointerGlow") private var glow: Double = 0
    @AppStorage("ui.glassStrength") private var glassStrength = 0.20
    @AppStorage("ui.language") private var language = "system"
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let isDark = colorScheme == .dark
        let theme: DeckTheme = isDark ? .glassDark : .glassLight
        content
            .environment(\.deckTheme, theme)
            .environment(\.deckGlow, glow)
            .environment(\.deckGlassStrength, glassStrength)
            .environment(\.locale, (DeckLanguage(rawValue: language) ?? .system).locale)
            .id(DeckLanguage(rawValue: language)?.resolved() ?? .english)
    }
}
