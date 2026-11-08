import SwiftUI

private struct GlowKey: EnvironmentKey { static let defaultValue: Double = 0 }
private struct GlowCenterKey: EnvironmentKey { static let defaultValue: CGPoint? = nil }
private extension EnvironmentValues {
    var deckGlowCenter: CGPoint? {
        get { self[GlowCenterKey.self] }
        set { self[GlowCenterKey.self] = newValue }
    }
}
private struct GlassStrengthKey: EnvironmentKey { static let defaultValue = 0.20 }
public extension EnvironmentValues {
    /// Custom card material strength, independent of decorative lighting.
    var deckGlassStrength: Double {
        get { self[GlassStrengthKey.self] }
        set { self[GlassStrengthKey.self] = min(1, max(0, newValue)) }
    }

    var deckGlow: Double {
        get { self[GlowKey.self] }
        set { self[GlowKey.self] = min(1, max(0, newValue)) }
    }
}

/// The highlight produced by the pointer over a glass surface.
enum DeckGlowAnchor {
    static func nearestEdge(to pointer: CGPoint, size: CGSize, radius: CGFloat) -> CGPoint {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let x = min(width, max(0, pointer.x))
        let y = min(height, max(0, pointer.y))
        let r = min(max(0, radius), width / 2, height / 2)
        let horizontal = min(width - r, max(r, x))
        let vertical = min(height - r, max(r, y))
        let candidates = [CGPoint(x: horizontal, y: 0), CGPoint(x: horizontal, y: height),
                          CGPoint(x: 0, y: vertical), CGPoint(x: width, y: vertical)]
        return candidates.min { hypot($0.x - x, $0.y - y) < hypot($1.x - x, $1.y - y) } ?? .zero
    }
}

public struct DeckLight: View {
    @Environment(\.deckGlow) private var intensity
    @Environment(\.deckGlowCenter) private var center
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat

    public init() { self.init(cornerRadius: DeckTheme.cardRadius) }

    fileprivate init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if let center, intensity > 0 {
            GeometryReader { geometry in
                let size = geometry.size
                if size.width > 0, size.height > 0 {
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    let pointer = UnitPoint(x: center.x / size.width, y: center.y / size.height)
                    let edge = DeckGlowAnchor.nearestEdge(to: center, size: size, radius: cornerRadius)
                    let rimDistance = hypot(center.x - edge.x, center.y - edge.y)
                    let light = colorScheme == .dark ? Color.white : Color(red: 0.18, green: 0.55, blue: 1)
                    ZStack {
                        RadialGradient(stops: [
                            .init(color: light.opacity(0.30 * intensity), location: 0),
                            .init(color: light.opacity(0.12 * intensity), location: 0.48),
                            .init(color: .clear, location: 1)
                        ], center: pointer, startRadius: 0, endRadius: 126)
                        .clipShape(shape)

                        RadialGradient(stops: [
                            .init(color: light.opacity(0.88 * intensity), location: 0),
                            .init(color: light.opacity(0.38 * intensity), location: 0.54),
                            .init(color: .clear, location: 1)
                        ], center: pointer, startRadius: rimDistance, endRadius: rimDistance + 140)
                        .mask {
                            shape.strokeBorder(.white.opacity(0.28), lineWidth: 1.6)
                                .overlay(shape.strokeBorder(.white, lineWidth: 0.65))
                        }
                    }
                }
            }
        }
    }
}

public extension View {
    func deckPointerGlow(cornerRadius: CGFloat = DeckTheme.cardRadius, enabled: Bool = true) -> some View {
        modifier(DeckPointerGlow(cornerRadius: cornerRadius, insets: EdgeInsets(), enabled: enabled))
    }

    func deckPointerGlow(insets: EdgeInsets) -> some View {
        modifier(DeckPointerGlow(cornerRadius: DeckTheme.cardRadius, insets: insets, enabled: true))
    }
}

private struct DeckPointerGlow: ViewModifier {
    let cornerRadius: CGFloat
    let insets: EdgeInsets
    let enabled: Bool
    @Environment(\.deckGlow) private var intensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var location: CGPoint?
    @State private var isHovering = false

    func body(content: Content) -> some View {
        if enabled && intensity > 0 && !reduceTransparency {
            content
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(point):
                        location = CGPoint(x: point.x - insets.leading, y: point.y - insets.top)
                        isHovering = true
                    case .ended:
                        isHovering = false
                    }
                }
                .background {
                    DeckLight(cornerRadius: cornerRadius)
                        .environment(\.deckGlowCenter, location)
                        .padding(insets)
                        .opacity(isHovering ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}
