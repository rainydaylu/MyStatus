import AppKit
import SwiftUI

// MARK: - Surfaces

public struct DeckCardBackground: View {
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckUsesGlass) private var drawsLiveMaterial
    @Environment(\.deckGlassStrength) private var translucency
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let isInteractive: Bool

    public init(isInteractive: Bool = false) {
        self.isInteractive = isInteractive
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeckTheme.cardRadius, style: .continuous)
        let strength = reduceTransparency || !drawsLiveMaterial ? 0 : min(1, max(0, translucency))
        // The native material supplies the blur and edge highlights. A tint
        // above it keeps text readable while letting the slider reveal the glass.
        let tintOpacity = DeckGlass.isSupported ? 1 - 0.95 * sqrt(strength) : 1 - 0.68 * strength
        ZStack {
            if strength > 0 {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.interactive(isInteractive), in: shape)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            shape.fill(LinearGradient(colors: [theme.cardTop, theme.cardBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(tintOpacity)
        }
        .overlay(shape.strokeBorder(theme.cardStroke, lineWidth: 0.75))
        .shadow(color: theme.shadow, radius: 7, y: 2)
    }
}

/// A floating card of glass. A detail window is a stack of these.
public struct DeckCard<Content: View>: View {
    @Environment(\.deckUsesSharedSurface) private var usesSharedSurface
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .deckPointerGlow(enabled: !usesSharedSurface)
            .background { if !usesSharedSurface { DeckCardBackground() } }
    }
}

/// A recessed group inside a card, for a notice or a confirmation.
public struct DeckInset<Content: View>: View {
    @Environment(\.deckTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DeckTheme.insetRadius, style: .continuous).fill(theme.inset))
    }
}

// MARK: - Headings

/// The blue heading of a row or card.
public struct DeckTitle: View {
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckUsesSharedSurface) private var isFlyoutHeading
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(DeckL(text))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isFlyoutHeading ? theme.accent : theme.heading)
            .lineLimit(1)
    }
}

/// A heading on the left and its value on the right: how every row begins.
public struct DeckTitleRow: View {
    @Environment(\.deckTheme) private var theme
    private let title: String
    private let value: String?

    public init(_ title: String, value: String? = nil) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 8) {
            DeckTitle(title)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

public struct DeckSectionTitle: View {
    @Environment(\.deckTheme) private var theme
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(DeckL(text))
            .font(.system(size: 11, weight: .medium))
            .tracking(1.8)
            .foregroundStyle(theme.tertiary)
            .lineLimit(1)
    }
}

/// A small heading inside a card.
public struct DeckSubheading: View {
    @Environment(\.deckTheme) private var theme
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(DeckL(text))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.secondary)
    }
}

// MARK: - Buttons

private enum DeckButtonForm {
    case capsule, circle

    var drawnShape: AnyShape {
        switch self {
        case .capsule: AnyShape(Capsule())
        case .circle: AnyShape(Circle())
        }
    }
}

private struct DeckNativeButton: ViewModifier {
    let form: DeckButtonForm
    var tint: Color?
    var fallback: Color = .clear

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .background(form.drawnShape.fill(tint ?? fallback))
    }
}

/// A filled circle with a glyph: blue when active, grey when not.
public struct DeckRoundIcon: View {
    @Environment(\.deckTheme) private var theme
    private let symbol: String
    private let isActive: Bool
    private let size: CGFloat

    public init(_ symbol: String, isActive: Bool = true, size: CGFloat = 28) {
        self.symbol = symbol
        self.isActive = isActive
        self.size = size
    }

    public var body: some View {
        let glyph = Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(isActive ? Color.white : theme.roundGlyph)
            .frame(width: size, height: size)
        if isActive {
            glyph.deckGlass(in: Circle(), tint: theme.accent)
        } else {
            glyph.background(Circle().fill(theme.roundFill))
        }
    }
}

public struct DeckRoundButton: View {
    @Environment(\.deckTheme) private var theme
    private let symbol: String
    private let size: CGFloat
    private let action: () -> Void

    public init(_ symbol: String, size: CGFloat = 30, action: @escaping () -> Void) {
        self.symbol = symbol
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(theme.roundGlyph)
                .frame(width: size - 8, height: size - 8)
                .contentShape(Circle())
        }
        .controlSize(.small)
        .modifier(DeckNativeButton(form: .circle, fallback: theme.roundFill))
    }
}

/// A small icon button with a tooltip.
public struct DeckIconButton: View {
    @Environment(\.deckTheme) private var theme
    private let symbol: String
    private let help: String
    private let isActive: Bool
    private let action: () -> Void

    public init(symbol: String, help: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isActive ? theme.heading : theme.primary)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .controlSize(.small)
        .modifier(DeckNativeButton(form: .circle))
        .help(help)
    }
}

public struct DeckTextButton: View {
    @Environment(\.deckTheme) private var theme
    private let title: String
    private let role: Role
    private let action: () -> Void

    public enum Role { case normal, destructive, prominent }

    public init(_ title: String, role: Role = .normal, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: role == .prominent ? .semibold : .medium))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
        }
        .controlSize(.small)
        .modifier(DeckNativeButton(
            form: .capsule,
            tint: role == .prominent ? theme.accent : nil,
            fallback: theme.inset
        ))
    }

    private var foreground: Color {
        switch role {
        case .normal: theme.heading
        case .destructive: theme.negative
        case .prominent: .white
        }
    }
}

/// Filled when selected: for short mutually exclusive choices.
public struct DeckChip: View {
    @Environment(\.deckTheme) private var theme
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.white : theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
        }
        .controlSize(.small)
        .modifier(DeckNativeButton(form: .capsule, tint: isSelected ? theme.accent : nil, fallback: theme.inset))
    }
}

// MARK: - Sliders and switches

/// Keeps AppKit's slider drawing and accepts the first click in a floating panel.
private struct DeckNativeSlider: NSViewRepresentable {
    let value: Double
    let color: NSColor
    let onChange: (Double) -> Void

    final class FirstClickSlider: NSSlider {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    final class Coordinator: NSObject {
        var onChange: (Double) -> Void

        init(onChange: @escaping (Double) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSSlider) {
            onChange(sender.doubleValue)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> FirstClickSlider {
        let slider = FirstClickSlider(frame: .zero)
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = value
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.isContinuous = true
        slider.trackFillColor = color
        return slider
    }

    func updateNSView(_ slider: FirstClickSlider, context: Context) {
        context.coordinator.onChange = onChange
        slider.trackFillColor = color
        // During a drag the slider leads. A reading coming back from a monitor must
        // not pull the thumb away from the pointer.
        if NSEvent.pressedMouseButtons == 0, abs(slider.doubleValue - value) > 0.0005 {
            slider.doubleValue = value
        }
    }
}

/// The compact horizontal rail used for main-panel brightness and sound.
public struct DeckRailSlider: View {
    private let value: Double
    private let isDimmed: Bool
    private let onChange: (Double) -> Void

    public init(value: Double, isDimmed: Bool = false, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.isDimmed = isDimmed
        self.onChange = onChange
    }

    public var body: some View {
        DeckSlider(value: value, isDimmed: isDimmed, onChange: onChange)
            .frame(height: 24)
    }
}

public struct DeckSlider: View {
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckUsesGlass) private var usesGlass
    private let value: Double
    private let isDimmed: Bool
    private let onChange: (Double) -> Void

    public init(value: Double, isDimmed: Bool = false, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.isDimmed = isDimmed
        self.onChange = onChange
    }

    public var body: some View {
        let clamped = min(1, max(0, value))
        if usesGlass {
            DeckNativeSlider(value: clamped, color: NSColor(isDimmed ? theme.tertiary : theme.accent), onChange: onChange)
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.track).frame(height: 5)
                    Capsule()
                        .fill(isDimmed ? theme.tertiary : theme.accent)
                        .frame(width: max(5, proxy.size.width * CGFloat(clamped)), height: 5)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 22, height: 14)
                        .offset(x: (proxy.size.width - 22) * CGFloat(clamped))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
        }
    }
}

/// A round button, a slider and its percentage.
public struct DeckLevelRow: View {
    @Environment(\.deckTheme) private var theme
    private let symbol: String
    private let value: Double
    private let isDimmed: Bool
    private let onSymbolTap: (() -> Void)?
    private let onChange: (Double) -> Void

    public init(
        symbol: String,
        value: Double,
        isDimmed: Bool = false,
        onSymbolTap: (() -> Void)? = nil,
        onChange: @escaping (Double) -> Void
    ) {
        self.symbol = symbol
        self.value = value
        self.isDimmed = isDimmed
        self.onSymbolTap = onSymbolTap
        self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let onSymbolTap {
                DeckRoundButton(symbol, size: 30, action: onSymbolTap)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 30, height: 30)
            }
            DeckSlider(value: value, isDimmed: isDimmed, onChange: onChange)
            Text(Format.percent(value))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// The same with a smaller glyph, inside a detail window.
public struct DeckSubSlider: View {
    @Environment(\.deckTheme) private var theme
    private let symbol: String?
    private let value: Double
    private let isDimmed: Bool
    private let onChange: (Double) -> Void

    public init(symbol: String? = nil, value: Double, isDimmed: Bool = false, onChange: @escaping (Double) -> Void) {
        self.symbol = symbol
        self.value = value
        self.isDimmed = isDimmed
        self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 16)
            }
            DeckSlider(value: value, isDimmed: isDimmed, onChange: onChange)
            Text(Format.percent(value))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

public struct DeckSwitch: View {
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckUsesGlass) private var usesGlass
    private let isOn: Bool
    private let isEnabled: Bool
    private let action: () -> Void

    public init(isOn: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        if usesGlass {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(!isEnabled)
        } else {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.accent : theme.track)
                Circle().fill(Color.white).frame(width: 14, height: 14).padding(2)
            }
            .frame(width: 32, height: 18)
            .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

// MARK: - Rows

/// A round icon and a name; the selected row gets a soft blue band behind it.
public struct DeckDeviceRow<Trailing: View>: View {
    @Environment(\.deckTheme) private var theme
    @State private var isHovered = false

    private let symbol: String
    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let action: () -> Void
    private let trailing: Trailing

    public init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DeckRoundIcon(symbol, isActive: isSelected, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(theme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                trailing
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        if isSelected {
            shape.fill(theme.selectedLeading)
        } else if isHovered {
            shape.fill(theme.rowHover)
        }
    }
}

public extension DeckDeviceRow where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, isSelected: isSelected, action: action) { EmptyView() }
    }
}

/// Label on the left, value on the right.
public struct DeckInfoRow: View {
    @Environment(\.deckTheme) private var theme
    private let label: String
    private let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(theme.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(theme.primary).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 13))
    }
}

/// A label, a value and a thin bar beneath them.
public struct DeckMeterRow: View {
    private let label: String
    private let value: Double
    private let text: String?
    private let color: Color?

    public init(_ label: String, value: Double, text: String? = nil, color: Color? = nil) {
        self.label = label
        self.value = value
        self.text = text
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 4) {
            DeckInfoRow(label, text ?? Format.percent(value))
            DeckBar(value: value, color: color)
        }
    }
}

public struct DeckBar: View {
    @Environment(\.deckTheme) private var theme
    private let value: Double
    private let color: Color?
    private let height: CGFloat

    public init(value: Double, color: Color? = nil, height: CGFloat = 5) {
        self.value = value
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(color ?? theme.accent)
                    .frame(width: max(value > 0 ? height : 0, proxy.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: height)
    }
}

/// One bar split into proportional colored parts.
public struct DeckSegmentedBar: View {
    @Environment(\.deckTheme) private var theme
    private let segments: [(value: Double, color: Color)]

    public init(segments: [(value: Double, color: Color)]) {
        self.segments = segments
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, proxy.size.width * CGFloat(segment.value)))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.track)
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }
}

/// A colored dot naming a series, with its value at the far end.
public struct DeckLegendDot: View {
    @Environment(\.deckTheme) private var theme
    private let label: String
    private let value: String
    private let color: Color

    public init(_ label: String, _ value: String, color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).foregroundStyle(theme.secondary)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(theme.primary).monospacedDigit()
        }
        .font(.system(size: 13))
        .lineLimit(1)
    }
}

/// A large figure with a colored dot and a label under it.
public struct DeckStat: View {
    @Environment(\.deckTheme) private var theme
    private let value: String
    private let label: String
    private let color: Color

    public init(_ value: String, label: String, color: Color) {
        self.value = value
        self.label = label
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 21))
                .monospacedDigit()
                .foregroundStyle(theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rings

/// A ring filled clockwise from the top, by one color or several in a row, with
/// anything at its centre.
public struct DeckRing<Center: View>: View {
    @Environment(\.deckTheme) private var theme
    private let segments: [(value: Double, color: Color)]
    private let lineWidth: CGFloat
    private let center: Center

    public init(segments: [(value: Double, color: Color)], lineWidth: CGFloat = 8, @ViewBuilder center: () -> Center) {
        self.segments = segments
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(theme.track, lineWidth: lineWidth)
            ForEach(Array(Self.arcs(segments).enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.from, to: arc.to)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth))
                    .rotationEffect(.degrees(-90))
            }
            center
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }

    private static func arcs(_ segments: [(value: Double, color: Color)]) -> [(from: CGFloat, to: CGFloat, color: Color)] {
        var start = 0.0
        return segments.map { segment in
            let end = min(1, start + max(0, segment.value))
            defer { start = end }
            return (CGFloat(start), CGFloat(end), segment.color)
        }
    }
}

public extension DeckRing {
    init(value: Double, color: Color, lineWidth: CGFloat = 8, @ViewBuilder center: () -> Center) {
        self.init(segments: [(value, color)], lineWidth: lineWidth, center: center)
    }
}

public extension DeckRing where Center == EmptyView {
    init(value: Double, color: Color, lineWidth: CGFloat = 4) {
        self.init(segments: [(value, color)], lineWidth: lineWidth) { EmptyView() }
    }
}

/// A large percentage with a caption, for the middle of a big ring.
public struct DeckRingPercent: View {
    @Environment(\.deckTheme) private var theme
    private let value: Double
    private let caption: String

    public init(_ value: Double, caption: String) {
        self.value = value
        self.caption = caption
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((min(1, max(0, value)) * 100).rounded()))")
                    .font(.system(size: 34, weight: .light))
                Text("%")
                    .font(.system(size: 17, weight: .light))
            }
            .monospacedDigit()
            .foregroundStyle(theme.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - Graphs

/// Bars growing from the bottom, newest on the right: `lower` with `upper` on top.
public struct DeckBarGraph: View {
    @Environment(\.deckTheme) private var theme
    private let lower: [Double]
    private let upper: [Double]
    private let capacity: Int

    public init(lower: [Double], upper: [Double] = [], capacity: Int = 60) {
        self.lower = lower
        self.upper = upper
        self.capacity = capacity
    }

    public var body: some View {
        let lowerColor = theme.accent
        let upperColor = theme.magenta
        Canvas { context, size in
            let slot = size.width / CGFloat(capacity)
            let barWidth = max(1, slot - 1.2)
            for (offset, value) in lower.reversed().enumerated() where offset < capacity {
                let x = size.width - CGFloat(offset + 1) * slot
                let lowerHeight = CGFloat(min(1, max(0, value))) * size.height
                let upperIndex = upper.count - 1 - offset
                let upperValue = upper.indices.contains(upperIndex) ? upper[upperIndex] : 0
                let upperHeight = min(size.height - lowerHeight, CGFloat(max(0, upperValue)) * size.height)
                context.fill(Path(CGRect(x: x, y: size.height - lowerHeight, width: barWidth, height: lowerHeight)), with: .color(lowerColor))
                if upperHeight > 0 {
                    context.fill(Path(CGRect(x: x, y: size.height - lowerHeight - upperHeight, width: barWidth, height: upperHeight)), with: .color(upperColor))
                }
            }
        }
    }
}

/// Two directions around a centre line, on a shared scale following the peak in view.
public struct DeckMirrorGraph: View {
    @Environment(\.deckTheme) private var theme
    private let upper: [Double]
    private let lower: [Double]
    private let floor: Double
    private let capacity: Int

    /// `floor` is the smallest full-scale value, so that a trickle stays small.
    public init(upper: [Double], lower: [Double], floor: Double, capacity: Int = 60) {
        self.upper = upper
        self.lower = lower
        self.floor = floor
        self.capacity = capacity
    }

    public var body: some View {
        let upperColor = theme.magenta
        let lowerColor = theme.accent
        let lineColor = theme.track
        Canvas { context, size in
            let middle = size.height / 2
            let peak = max(floor, upper.max() ?? 0, lower.max() ?? 0)
            let slot = size.width / CGFloat(capacity)
            let barWidth = max(1, slot - 1.2)
            context.fill(Path(CGRect(x: 0, y: middle - 0.25, width: size.width, height: 0.5)), with: .color(lineColor))
            for index in 0..<capacity {
                let x = size.width - CGFloat(index + 1) * slot
                let upIndex = upper.count - 1 - index
                let downIndex = lower.count - 1 - index
                let up = upper.indices.contains(upIndex) ? upper[upIndex] : 0
                let down = lower.indices.contains(downIndex) ? lower[downIndex] : 0
                let upHeight = CGFloat(up / peak) * (middle - 1)
                let downHeight = CGFloat(down / peak) * (middle - 1)
                if upHeight > 0.5 {
                    context.fill(Path(CGRect(x: x, y: middle - 1 - upHeight, width: barWidth, height: upHeight)), with: .color(upperColor))
                }
                if downHeight > 0.5 {
                    context.fill(Path(CGRect(x: x, y: middle + 1, width: barWidth, height: downHeight)), with: .color(lowerColor))
                }
            }
        }
    }
}

// MARK: - App icons

/// `NSWorkspace` icons are slow to fetch and never change for a given path.
@MainActor
public enum DeckAppIcon {
    private static var cache: [String: NSImage] = [:]

    public static func image(forPath path: String?) -> NSImage {
        let key = path ?? "/bin/ls"
        if let cached = cache[key] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: key)
        cache[key] = icon
        return icon
    }
}

/// A row of app icons along the bottom of a detail window. Paths that do not exist
/// on this Mac are left out.
public struct DeckAppShortcutRow: View {
    private let paths: [String]
    private let onOpen: (() -> Void)?

    public init(paths: [String], onOpen: (() -> Void)? = nil) {
        self.paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        self.onOpen = onOpen
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                if index > 0 { Spacer(minLength: 4) }
                Button {
                    onOpen?()
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } label: {
                    Image(nsImage: DeckAppIcon.image(forPath: path))
                        .resizable()
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(FileManager.default.displayName(atPath: path))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
