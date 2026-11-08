import AppKit
import StatusDeckKit
import SwiftUI

/// A borderless panel that can take key status without activating the app, so
/// opening it does not pull focus from whatever the user was doing. The glass draws
/// its own edge and shadow on a clear background.
final class FloatingPanel: NSPanel {
    /// What every panel shows. Set panel by panel rather than through `NSApp.appearance`,
    /// which would also reach the menu bar icons, and those have to match the menu bar.
    static var sharedAppearance: NSAppearance? {
        didSet {
            for panel in all.allObjects { panel.appearance = sharedAppearance }
        }
    }

    private static let all = NSHashTable<FloatingPanel>.weakObjects()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: DeckTheme.panelWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // SwiftUI's continuous hover needs mouse-moved events in this nonactivating panel.
        acceptsMouseMovedEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        appearance = Self.sharedAppearance
        Self.all.add(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PanelAppearance: String, CaseIterable {
    /// Automatic: follows macOS, and changes when macOS does.
    case system
    case light, dark

    var isAutomatic: Bool { self == .system }

    /// Leaving automatic lands on what is showing now, so that nothing jumps.
    static func fixed(isDark: Bool) -> PanelAppearance {
        isDark ? .dark : .light
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func colorScheme(following systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class PanelState: ObservableObject {
    @Published var appearance: PanelAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "panel.appearance") }
    }

    init() {
        appearance = PanelAppearance(rawValue: UserDefaults.standard.string(forKey: "panel.appearance") ?? "") ?? .light
    }
}

/// The native material for an individual menu control, or a detail popover.
struct MenuPanelSurface: View {
    var cornerRadius: CGFloat = DeckTheme.cardRadius
    @Environment(\.deckTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deckGlassStrength) private var translucency
    @Environment(\.deckUsesGlass) private var usesGlass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func washGray(isDark: Bool) -> Double { isDark ? 0.12 : 0.94 }

    static func washOpacity(translucency: Double, isDark: Bool) -> Double {
        let amount = min(1, max(0, translucency))
        let midpoint = isDark ? 0.88 : 0.60
        if amount <= 0.5 {
            let start = isDark ? 0.97 : 0.79
            return start + (midpoint - start) * amount * 2
        }
        let minimum = isDark ? 0.64 : 0.34
        return midpoint + (minimum - midpoint) * (amount - 0.5) * 2
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark
        let wash = Color(white: Self.washGray(isDark: isDark))
        Group {
            if reduceTransparency || translucency <= 0 {
                shape.fill(theme.cardTop)
            } else {
                // Keep a tint underneath labels as more of the backdrop is revealed.
                shape.fill(wash.opacity(Self.washOpacity(translucency: translucency, isDark: isDark)))
                    .background {
                        if usesGlass {
                            if #available(macOS 26.0, *) {
                                NativeMenuGlass(cornerRadius: cornerRadius, isDark: isDark, isClear: translucency >= 0.85)
                            } else {
                                FrostedMenuSurface(cornerRadius: cornerRadius)
                            }
                        }
                    }
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(isDark ? 0.18 : 0.42), lineWidth: 0.6))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@available(macOS 26.0, *)
private struct NativeMenuGlass: NSViewRepresentable {
    let cornerRadius: CGFloat
    let isDark: Bool
    let isClear: Bool

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView(frame: .zero)
        view.contentView = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        view.style = isClear ? .clear : .regular
        view.cornerRadius = cornerRadius
    }
}

private struct FrostedMenuSurface: NSViewRepresentable {
    let cornerRadius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct MenuPanelPalette: ViewModifier {
    @Environment(\.deckTheme) private var theme

    func body(content: Content) -> some View {
        content.environment(\.deckTheme, theme.isDark ? .controlCenter : .controlCenterLight)
    }
}

// MARK: - Geometry

/// Where things go, in plain numbers. The panel and its detail share one window, so
/// that the two never take turns at being key: a window that is not key shows grey
/// glass and grey controls. Inside the window, coordinates have y going down, as in
/// SwiftUI. On screen, y goes up, as in AppKit.
enum PanelGeometry {
    /// Clear space around the cards, for their shadows.
    static let margin: CGFloat = 12
    static let verticalPadding: CGFloat = 6
    static let footerShadowRoom: CGFloat = 42
    static let backdropSideSpread: CGFloat = 104
    static let backdropBottomSpread: CGFloat = 144
    /// Between the panel's cards and the detail's.
    static let gap: CGFloat = 8
    /// The least distance from the edge of the screen.
    private static let screenInset: CGFloat = 4
    static let coordinateSpace = "statusdeck.panel"

    struct Layout: Equatable {
        /// The window, on screen. It has room for both columns and the screen's full
        /// height, and lets clicks through wherever there is no card.
        var window: CGRect
        /// Left edges of the two columns of cards, inside the window.
        var panelX: CGFloat
        var flyoutX: CGFloat
        var leftFlyoutX: CGFloat?
        var rightFlyoutX: CGFloat?

        func flyoutPosition(for row: CGRect) -> CGFloat {
            guard row.width < DeckTheme.panelWidth - 1 else { return flyoutX }
            let isRightColumn = row.midX > panelX + DeckTheme.panelWidth / 2
            return (isRightColumn ? rightFlyoutX : leftFlyoutX) ?? flyoutX
        }

        func backdropFrame(contentHeight: CGFloat) -> CGRect {
            let roomOnRight = window.width - panelX - DeckTheme.panelWidth
            let spread = max(0, min(PanelGeometry.backdropSideSpread, panelX, roomOnRight))
            return CGRect(x: panelX - spread, y: 0, width: DeckTheme.panelWidth + 2 * spread,
                          height: min(window.height, contentHeight + PanelGeometry.backdropBottomSpread))
        }
    }

    /// Under the menu bar icon, with the detail on the side with more of the screen.
    static func layout(anchor: CGRect, visible: CGRect) -> Layout {
        let panelWidth = DeckTheme.panelWidth
        let flyoutWidth = DeckTheme.flyoutWidth
        let panelLeft = max(visible.minX + screenInset, min(anchor.midX - panelWidth / 2, visible.maxX - panelWidth - screenInset))
        let panelRight = panelLeft + panelWidth

        let opensLeft = panelLeft - visible.minX > visible.maxX - panelRight
        var flyoutLeft = opensLeft ? panelLeft - gap - flyoutWidth : panelRight + gap
        // A screen too narrow for both overlaps them rather than losing the detail.
        flyoutLeft = max(visible.minX + screenInset, min(flyoutLeft, visible.maxX - flyoutWidth - screenInset))

        let leftCandidate = panelLeft - gap - flyoutWidth
        let rightCandidate = panelRight + gap
        let left = leftCandidate >= visible.minX + screenInset ? leftCandidate : nil
        let right = rightCandidate + flyoutWidth <= visible.maxX - screenInset ? rightCandidate : nil
        let minX = min(max(visible.minX - margin, panelLeft - backdropSideSpread), (left ?? flyoutLeft) - margin)
        let maxX = max(min(visible.maxX + margin, panelRight + backdropSideSpread), (right ?? flyoutLeft) + flyoutWidth + margin)
        let top = min(anchor.minY, visible.maxY)
        return Layout(
            window: CGRect(x: minX, y: visible.minY, width: maxX - minX, height: top - visible.minY),
            panelX: panelLeft - minX,
            flyoutX: flyoutLeft - minX,
            leftFlyoutX: left.map { $0 - minX },
            rightFlyoutX: right.map { $0 - minX }
        )
    }

    /// The top of the detail's column: its first card lines up with the row it belongs
    /// to, as far as the window allows.
    static func flyoutY(rowTop: CGFloat, height: CGFloat, windowHeight: CGFloat) -> CGFloat {
        max(0, min(rowTop - verticalPadding, windowHeight - height))
    }

    static func localPoint(_ pointer: CGPoint, window: CGRect) -> CGPoint {
        CGPoint(x: pointer.x - window.minX, y: window.maxY - pointer.y)
    }

    static func row(at point: CGPoint, frames: [String: CGRect]) -> String? {
        frames.first { $0.value.contains(point) }?.key
    }
}

/// Decides which row the pointer means. Without this, moving diagonally from a row
/// toward its open window would cross other rows and swap the window away.
struct HoverIntent {
    private(set) var activeID: String?
    private var pendingID: String?
    private var pendingSince: TimeInterval = 0

    /// A first window opens on a short rest; a further one sooner, as the user is
    /// already browsing; and much later while the pointer is on its way to the window.
    static let openDelay: TimeInterval = 0.045
    static let switchDelay: TimeInterval = 0.025
    static let headingDelay: TimeInterval = 0.2

    /// Returns a row to open now, if there is one. A nil `rowID` (the pointer is over
    /// the open window, or between rows) leaves the current window alone.
    mutating func update(rowID: String?, isHeadingToFlyout: Bool, now: TimeInterval) -> String? {
        guard let rowID, rowID != activeID else {
            pendingID = nil
            return nil
        }
        if rowID != pendingID {
            pendingID = rowID
            pendingSince = now
        }
        let delay = activeID == nil ? Self.openDelay : (isHeadingToFlyout ? Self.headingDelay : Self.switchDelay)
        guard now - pendingSince >= delay else { return nil }
        activeID = rowID
        pendingID = nil
        return rowID
    }

    mutating func force(_ id: String?) {
        activeID = id
        pendingID = nil
    }

    /// Whether the move stays inside the triangle from where the pointer was to the
    /// near edge of the window: the usual test for a pointer aiming at a submenu.
    static func isHeading(from start: CGPoint, to end: CGPoint, toward flyout: CGRect) -> Bool {
        guard start != end else { return false }
        let nearX = flyout.midX < start.x ? flyout.maxX : flyout.minX
        let top = CGPoint(x: nearX, y: flyout.maxY)
        let bottom = CGPoint(x: nearX, y: flyout.minY)

        func side(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        let d1 = side(start, top, end)
        let d2 = side(top, bottom, end)
        let d3 = side(bottom, start, end)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }
}

// MARK: - Views

/// The row the pointer rests on, and where everything is. Frames change while
/// scrolling and are only read by the tracker, so they do not redraw anything.
@MainActor
final class PanelHoverModel: ObservableObject {
    struct Active {
        let section: DeckSection
        let rowTop: CGFloat
        let flyoutX: CGFloat
    }

    @Published var active: Active?
    var rowFrames: [String: CGRect] = [:]
    var panelFrame = CGRect.zero
    var flyoutFrame: CGRect?

    func reset() {
        active = nil
        rowFrames = [:]
        panelFrame = .zero
        flyoutFrame = nil
    }
}

private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private extension View {
    func reportsContentHeight() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
        })
    }
}

private struct PanelRoot: View {
    let layout: PanelGeometry.Layout
    let manager: PluginManager
    @ObservedObject var state: PanelState
    @ObservedObject var hover: PanelHoverModel
    let store: SystemStore
    let onOpenSettings: (String?) -> Void
    let onOpenDetail: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var panelHeight: CGFloat = 0

    var body: some View {
        let shown = min(panelHeight, layout.window.height)
        let backdrop = layout.backdropFrame(contentHeight: shown)
        DeckThemeRoot {
            ZStack(alignment: .topLeading) {
                // Draw the feather in the window itself. A ScrollView background clips
                // to the scroll column and loses the left and bottom of the blur.
                if shown > 0 {
                    let sideFeather = layout.panelX - backdrop.minX + 32
                    PanelBackdrop(feather: .init(left: sideFeather,
                                                 right: sideFeather,
                                                 top: 48,
                                                 bottom: backdrop.height - shown + 52))
                        .frame(width: backdrop.width, height: backdrop.height)
                        .offset(x: backdrop.minX, y: backdrop.minY)
                }
                PanelColumn(layout: layout, manager: manager, hover: hover, store: store,
                            onOpenSettings: onOpenSettings, onOpenDetail: onOpenDetail, height: $panelHeight)
                if let active = hover.active {
                    FlyoutColumn(active: active, layout: layout, hover: hover)
                        // Each section starts fresh, and its `onDisappear` stops what only it needed.
                        .id(active.section.id)
                        .transition(.opacity.combined(with: .offset(x: active.flyoutX < layout.panelX ? 5 : -5)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: PanelGeometry.coordinateSpace)
            .modifier(MenuPanelPalette())
        }
        .environment(\.colorScheme, state.appearance.colorScheme(following: colorScheme))
    }
}

/// Individually rounded controls over a soft menu backdrop.
private struct PanelColumn: View {
    let layout: PanelGeometry.Layout
    @ObservedObject var manager: PluginManager
    let hover: PanelHoverModel
    let store: SystemStore
    let onOpenSettings: (String?) -> Void
    let onOpenDetail: (String) -> Void
    @Binding var height: CGFloat

    var body: some View {
        let columnWidth = DeckTheme.panelWidth + PanelGeometry.margin * 2
        let shown = height == 0 ? 0 : min(height + PanelGeometry.footerShadowRoom, layout.window.height)
        ScrollView(.vertical, showsIndicators: false) {
            PanelTileGrid(sections: manager.activePlugins.flatMap(\.sections), store: store, hover: hover,
                          onOpenSettings: { onOpenSettings(PluginSettingsSelection.general) }, onOpenDetail: onOpenDetail)
            .padding(.horizontal, PanelGeometry.margin)
            .padding(.vertical, PanelGeometry.verticalPadding)
            .frame(width: columnWidth)
            .padding(.leading, layout.panelX - PanelGeometry.margin)
            .frame(width: layout.window.width, alignment: .leading)
            .reportsContentHeight()
            .padding(.bottom, PanelGeometry.footerShadowRoom)
        }
        // Keep vertical scrolling clipped, but let the glass render to the sides
        // of the cards without meeting the scroll boundary at the card margin.
        .scrollContentBackground(.hidden)
        .frame(width: layout.window.width, height: shown)
        .onPreferenceChange(RowFramesKey.self) { frames in
            MainActor.assumeIsolated { hover.rowFrames = frames }
        }
        .onPreferenceChange(ContentHeightKey.self) { value in
            MainActor.assumeIsolated {
                height = value
                hover.panelFrame = CGRect(x: layout.panelX, y: 0, width: DeckTheme.panelWidth, height: min(value, layout.window.height))
            }
        }
    }
}

enum PanelTileLayout {
    static let spacing: CGFloat = 15
    static let compactHeight: CGFloat = 65
    static let compactWidth = (DeckTheme.panelWidth - spacing) / 2

    static func isCompact(_ sectionID: String) -> Bool {
        ["wifi", "bluetooth", "inputsource", "battery"].contains(sectionID)
    }

    /// Budget for the tallest form of each built-in card before live data arrives.
    /// Leave room for uptime, Edit Controls, and the outer panel margins.
    static func initialHiddenModules(_ orderedIDs: [String], screenHeight: CGFloat) -> Set<String> {
        let heights: [String: CGFloat] = [
            "display": 90, "sound": 90, "mediakeys": 68, "cpu": 190,
            "memory": 138, "disk": 68, "network": 124, "sensors": 200, "clipboard": 52
        ]
        var remaining = max(0, screenHeight - 130)
        var hasHalfRow = false
        var hidden: Set<String> = []
        for id in orderedIDs where id.hasPrefix("com.statusdeck.") {
            let section = String(id.dropFirst("com.statusdeck.".count))
            let compact = isCompact(section)
            guard let height = compact ? compactHeight : heights[section] else { continue }
            let cost = compact && hasHalfRow ? 0 : height + spacing
            if cost <= remaining {
                remaining -= cost
                hasHalfRow = compact && !hasHalfRow
            } else {
                hidden.insert(id)
            }
        }
        return hidden
    }

    static func rows(_ sections: [DeckSection]) -> [[DeckSection]] {
        var rows: [[DeckSection]] = []
        for section in sections {
            if isCompact(section.id), let last = rows.last, last.count == 1, isCompact(last[0].id) {
                rows[rows.count - 1].append(section)
            } else {
                rows.append([section])
            }
        }
        return rows
    }
}

struct PanelTileGrid: View {
    let sections: [DeckSection]
    let store: SystemStore
    let hover: PanelHoverModel
    let onOpenSettings: () -> Void
    let onOpenDetail: (String) -> Void
    @AppStorage("panel.showUptime") private var showUptime = true
    @Namespace private var selection
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: PanelTileLayout.spacing) {
            if showUptime {
                let section = DeckSection(id: "host.uptime", title: DeckL("电脑开启时间")) {
                    PanelUptimeRow(store: store)
                }
                PanelRow(section: section, hover: hover, selection: selection, onOpenDetail: {})
            }
            ForEach(PanelTileLayout.rows(sections), id: \.first?.id) { row in
                HStack(alignment: .top, spacing: PanelTileLayout.spacing) {
                    ForEach(row) { section in
                        PanelRow(section: section, hover: hover, selection: selection) { onOpenDetail(section.id) }
                    }
                    if row.count == 1, let first = row.first, PanelTileLayout.isCompact(first.id) {
                        Spacer(minLength: 0)
                    }
                }
            }
            if sections.isEmpty {
                Text(DeckL("所有插件都已关闭。点击「编辑控制」开启。", "All plugins are off. Choose Edit Controls to enable them."))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(MenuPanelSurface())
            }
            PanelFooter(onOpenSettings: onOpenSettings)
        }
        .frame(width: DeckTheme.panelWidth)
    }
}

struct PanelTileLabel: View {
    let title: String
    let value: String?
    let symbol: String
    var isActive = true
    @Environment(\.deckTheme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? theme.accent : theme.roundGlyph)
                .frame(width: 36, height: 36)
                .background(isActive ? Color.white : theme.roundFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.primary)
                if let value {
                    Text(value).font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .help(value ?? title)
        }
    }
}

private struct PanelUptimeRow: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        DeckTitleRow(DeckL("电脑开启时间"), value: Format.duration(store.snapshot.uptime))
    }
}

private struct PanelFooter: View {
    let onOpenSettings: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        Button(action: onOpenSettings) {
            Text(DeckL("编辑控制", "Edit Controls"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(MenuPanelSurface(cornerRadius: 16))
        .padding(.vertical, 2)
    }
}

private struct OpenPanelDetailKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var openPanelDetail: (() -> Void)? {
        get { self[OpenPanelDetailKey.self] }
        set { self[OpenPanelDetailKey.self] = newValue }
    }
}

private struct PanelRow: View {
    let section: DeckSection
    @ObservedObject var hover: PanelHoverModel
    let selection: Namespace.ID
    let onOpenDetail: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let compact = PanelTileLayout.isCompact(section.id)
        let radius: CGFloat = compact ? PanelTileLayout.compactHeight / 2 : 24
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if compact && ["wifi", "battery"].contains(section.id) {
                section.row
                    .frame(width: PanelTileLayout.compactWidth, height: PanelTileLayout.compactHeight)
            } else if compact && section.detail != nil {
                Button(action: onOpenDetail) {
                    section.row
                        .padding(.horizontal, 12)
                        .frame(width: PanelTileLayout.compactWidth, height: PanelTileLayout.compactHeight, alignment: .leading)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
            } else {
                section.row
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .environment(\.openPanelDetail, section.detail == nil ? nil : onOpenDetail)
            }
        }
            .frame(maxWidth: compact ? PanelTileLayout.compactWidth : .infinity, alignment: .leading)
            .contentShape(shape)
            .deckPointerGlow(cornerRadius: radius)
            .background {
                ZStack {
                    MenuPanelSurface(cornerRadius: radius)
                    if hover.active?.section.id == section.id {
                        shape
                            .fill(theme.rowHover)
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramesKey.self,
                    value: [section.id: proxy.frame(in: .named(PanelGeometry.coordinateSpace))]
                )
            })
    }
}

/// The floating cards beside the panel. Scrolls only when a screen cannot fit them.
private struct FlyoutColumn: View {
    let active: PanelHoverModel.Active
    let layout: PanelGeometry.Layout
    let hover: PanelHoverModel
    @State private var height: CGFloat = 0

    var body: some View {
        let columnWidth = DeckTheme.flyoutWidth + PanelGeometry.margin * 2
        let shown = min(height, layout.window.height)
        ScrollView(.vertical, showsIndicators: false) {
            active.section.detail
                .padding(.horizontal, PanelGeometry.margin)
                .padding(.vertical, PanelGeometry.verticalPadding)
                .frame(width: columnWidth)
                .reportsContentHeight()
        }
        .frame(width: columnWidth, height: shown)
        .environment(\.deckUsesSharedSurface, true)
        .deckPointerGlow(insets: EdgeInsets(top: PanelGeometry.verticalPadding, leading: PanelGeometry.margin,
                                          bottom: PanelGeometry.verticalPadding, trailing: PanelGeometry.margin))
        .background {
            MenuPanelSurface()
                .padding(.horizontal, PanelGeometry.margin)
                .padding(.vertical, PanelGeometry.verticalPadding)
        }
        .padding(.leading, active.flyoutX - PanelGeometry.margin)
        .padding(.top, PanelGeometry.flyoutY(rowTop: active.rowTop, height: shown, windowHeight: layout.window.height))
        // Nothing until it knows its size, so that it never appears in the wrong place.
        .opacity(height == 0 ? 0 : 1)
        .onPreferenceChange(ContentHeightKey.self) { value in
            MainActor.assumeIsolated {
                height = value
                let shown = min(value, layout.window.height)
                let top = PanelGeometry.flyoutY(rowTop: active.rowTop, height: shown, windowHeight: layout.window.height)
                hover.flyoutFrame = CGRect(
                    x: active.flyoutX,
                    y: top + PanelGeometry.verticalPadding,
                    width: DeckTheme.flyoutWidth,
                    height: max(0, shown - PanelGeometry.verticalPadding * 2)
                )
            }
        }
    }
}

// MARK: - Panel

@MainActor
final class PanelController {
    private let manager: PluginManager
    private let store: SystemStore
    private let state: PanelState
    private let hover = PanelHoverModel()
    private let panel = FloatingPanel()
    private var currentLayout: PanelGeometry.Layout?
    private let onOpenSettings: (String?) -> Void
    private let onVisibilityChange: (Bool) -> Void
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private weak var anchorButton: NSStatusBarButton?

    private var hoverTimer: Timer?
    private var intent = HoverIntent()
    private var trail: (point: CGPoint, time: TimeInterval)?
    private var sectionToShow: String?

    private(set) var isOpen = false

    init(
        manager: PluginManager,
        store: SystemStore,
        state: PanelState,
        onOpenSettings: @escaping (String?) -> Void,
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.manager = manager
        self.store = store
        self.state = state
        self.onOpenSettings = onOpenSettings
        self.onVisibilityChange = onVisibilityChange
    }

    func toggle(from button: NSStatusBarButton?) {
        if isOpen, anchorButton === button {
            close()
        } else {
            open(from: button)
        }
    }

    func open(from button: NSStatusBarButton?, showing sectionID: String? = nil) {
        anchorButton?.isHighlighted = false
        anchorButton = button
        button?.isHighlighted = true
        sectionToShow = sectionID

        if !isOpen {
            isOpen = true
            onVisibilityChange(true)
        }

        hover.reset()
        intent = HoverIntent()

        let buttonWindow = button?.window
        let screen = buttonWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let anchor = buttonWindow?.frame ?? NSRect(x: visible.maxX - DeckTheme.panelWidth, y: visible.maxY, width: DeckTheme.panelWidth, height: 0)
        let layout = PanelGeometry.layout(anchor: anchor, visible: visible)
        currentLayout = layout

        panel.setFrame(layout.window, display: false)
        let hosting = NSHostingView(rootView: PanelRoot(
            layout: layout,
            manager: manager,
            state: state,
            hover: hover,
            store: store,
            onOpenSettings: onOpenSettings,
            onOpenDetail: { [weak self] id in
                self?.intent.force(id)
                self?.show(id)
            }
        ))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        startTracking()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        anchorButton?.isHighlighted = false
        stopTracking()
        hover.reset()
        panel.orderOut(nil)
        removeMonitors()
        onVisibilityChange(false)
        // Dropping the hosting view stops all SwiftUI work while closed. This can be
        // running inside a button of that very view, so it waits for the event to
        // finish, and leaves alone a panel reopened in the meantime.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.panel.contentView = nil
            }
        }
    }

    // MARK: Pointer

    private func startTracking() {
        hoverTimer?.invalidate()
        trail = nil
        // Common modes, so that a scroll in progress does not freeze it.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func trackPointer() {
        // A drag on a slider or an open menu may cross other rows and must not switch.
        if NSEvent.pressedMouseButtons != 0 || RunLoop.current.currentMode == .eventTracking { return }

        if let id = sectionToShow, hover.rowFrames[id] != nil {
            sectionToShow = nil
            intent.force(id)
            show(id)
            return
        }

        let point = PanelGeometry.localPoint(NSEvent.mouseLocation, window: panel.frame)
        let now = ProcessInfo.processInfo.systemUptime
        let isOverFlyout = hover.flyoutFrame?.contains(point) ?? false
        let isOverPanel = hover.panelFrame.contains(point)

        // The window spans the screen's height. Away from the cards it must not be there.
        panel.ignoresMouseEvents = !isOverFlyout && !isOverPanel

        let rowID = !isOverFlyout && isOverPanel ? PanelGeometry.row(at: point, frames: hover.rowFrames) : nil
        let isHeading = hover.flyoutFrame.map { flyout in
            HoverIntent.isHeading(from: trail?.point ?? point, to: point, toward: flyout)
        } ?? false

        if let next = intent.update(rowID: rowID, isHeadingToFlyout: isHeading, now: now) {
            show(next)
        }

        if trail == nil || now - (trail?.time ?? 0) > 0.1 {
            trail = (point, now)
        }
    }

    private func show(_ id: String) {
        let section = manager.activePlugins.flatMap(\.sections).first { $0.id == id }
        withAnimation(.spring(response: 0.13, dampingFraction: 0.92)) {
            if let section, section.detail != nil, let frame = hover.rowFrames[id], let currentLayout {
                hover.flyoutFrame = nil
                hover.active = PanelHoverModel.Active(section: section, rowTop: frame.minY,
                                                     flyoutX: currentLayout.flyoutPosition(for: frame))
            } else {
                hover.active = nil
                hover.flyoutFrame = nil
            }
        }
    }

    // MARK: Closing

    private func installMonitors() {
        // `--pin-panel` keeps it open while other things are used, for checking the interface.
        guard clickMonitor == nil, !CommandLine.arguments.contains("--pin-panel") else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, event.window === self.panel { // Esc
                MainActor.assumeIsolated { self.close() }
                return nil
            }
            return event
        }
        let closeOn: (NotificationCenter, Notification.Name, AnyObject?) -> Void = { [weak self] center, name, object in
            let token = center.addObserver(forName: name, object: object, queue: .main) { _ in
                MainActor.assumeIsolated { self?.close() }
            }
            self?.observers.append((center, token))
        }
        closeOn(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification, nil)
        // Another app took the keyboard, as with ⌘Tab. Glass without focus would turn grey.
        closeOn(NotificationCenter.default, NSWindow.didResignKeyNotification, panel)
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for observer in observers { observer.center.removeObserver(observer.token) }
        clickMonitor = nil
        keyMonitor = nil
        observers = []
    }
}

// MARK: - HUD

/// The level shown when a key or scroll changes something with no visible control:
/// a sheet of glass at the top right, where macOS 26 shows its own. Drawn here rather
/// than through Apple's private OSD framework, which MonitorControl uses, so it cannot
/// break with a system update.
@MainActor
final class HUDController {
    private final class Levels: ObservableObject {
        @Published var symbol = "sun.max.fill"
        @Published var value = 0.0
        @Published var title: String?
    }

    private struct HUDView: View {
        @ObservedObject var levels: Levels
        @Environment(\.deckTheme) private var theme

        var body: some View {
            HStack(spacing: 11) {
                Image(systemName: levels.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 6) {
                    if let title = levels.title {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.primary)
                            .lineLimit(1)
                    }
                    DeckBar(value: levels.value, height: 6)
                }
                Text(Format.percent(levels.value))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(width: HUDController.size.width, height: HUDController.size.height)
            .background(DeckCardBackground())
            .padding(PanelGeometry.margin)
        }
    }

    fileprivate static let size = CGSize(width: 290, height: 62)

    private let levels = Levels()
    private lazy var panel: NSPanel = {
        let panel = FloatingPanel()
        panel.ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: DeckThemeRoot { HUDView(levels: levels) })
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }()
    private var hideWork: DispatchWorkItem?

    func show(symbol: String, value: Double, title: String?) {
        levels.symbol = symbol
        levels.value = value
        levels.title = title

        // On the screen in use, which for a key press is the one with the pointer.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let margin = PanelGeometry.margin
        let width = Self.size.width + margin * 2
        let height = Self.size.height + margin * 2
        panel.setFrame(NSRect(x: visible.maxX - width - 2, y: visible.maxY - height - 2, width: width, height: height), display: true)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}
