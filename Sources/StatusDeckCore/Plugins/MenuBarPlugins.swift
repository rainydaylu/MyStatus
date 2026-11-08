import AppKit
import Combine
import StatusDeckKit
import SwiftUI

// MARK: - Three-in-one icon

/// Status Trio's idea of one icon carrying three states: battery in the ring,
/// connection in the middle, volume in the dots along the bottom. This is a
/// separate, much smaller drawing than its configurable renderer.
final class TrioIconPlugin: BuiltInPlugin {
    private let item = DeckMenuBarItem()
    private var cancellables: Set<AnyCancellable> = []
    private var lastContent: TrioIconRenderer.Content?

    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.trioicon",
            name: "三合一状态图标",
            summary: "一个菜单栏图标同时显示电池、Wi-Fi 和音量。在图标上滚动可以调音量。",
            symbol: "circle.dashed",
            category: .menuBar,
            sortOrder: 900
        ), services: services)
    }

    override var menuBarItem: DeckMenuBarItem? { item }

    override func didActivate() {
        services.store.sampler.setInterest(owner: manifest.id, always: [.battery])
        services.wifi.poller.set(owner: manifest.id, interval: 15)
        services.audio.poller.set(owner: manifest.id, interval: 2)
        services.displays.refreshIfStale()

        item.onScroll = { [weak self] delta in
            guard let self, let next = self.services.sound.nudge(by: delta) else { return }
            self.host?.showLevel(symbol: next == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: next, title: self.services.audio.currentOutput?.name)
        }

        // Each source publishes before its value changes, so drawing waits a turn.
        let changes: [AnyPublisher<Void, Never>] = [
            services.store.objectWillChange.eraseToAnyPublisher(),
            services.wifi.objectWillChange.eraseToAnyPublisher(),
            services.sound.objectWillChange.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.redraw() }
            }
            .store(in: &cancellables)
        redraw()
    }

    override func willDeactivate() {
        cancellables.removeAll()
        lastContent = nil
        item.onScroll = nil
        services.store.sampler.removeInterest(owner: manifest.id)
        services.wifi.poller.set(owner: manifest.id, interval: nil)
        services.audio.poller.set(owner: manifest.id, interval: nil)
    }

    private func redraw() {
        let battery = services.store.snapshot.battery
        let wifi = services.wifi.state
        let content = TrioIconRenderer.Content(
            batteryPercent: battery.isPresent ? battery.percent : nil,
            isCharging: battery.isCharging,
            isPluggedIn: battery.isExternalPowerConnected,
            isLowPower: battery.isLowPowerMode,
            isWiFiOn: wifi.isPoweredOn,
            wifiBars: wifi.bars,
            volume: services.sound.volume ?? 0,
            isMuted: services.sound.isMuted
        )
        guard content != lastContent else { return }
        lastContent = content
        item.image = TrioIconRenderer.image(for: content)
    }
}

enum TrioIconRenderer {
    struct Content: Equatable {
        var batteryPercent: Int?
        var isCharging = false
        var isPluggedIn = false
        var isLowPower = false
        var isWiFiOn = false
        var wifiBars = 0
        var volume = 0.0
        var isMuted = false
    }

    static func image(for content: Content) -> NSImage {
        let image = NSImage(size: NSSize(width: 26, height: 22), flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let primary: NSColor = isDark ? .white : .black
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 9.5

            drawRing(content, center: center, radius: radius, primary: primary)
            drawTop(content, center: center, radius: radius, primary: primary)
            drawConnection(content, center: center, primary: primary)
            drawVolume(content, center: center, radius: radius, primary: primary)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func ringColor(_ content: Content, primary: NSColor) -> NSColor {
        guard let percent = content.batteryPercent else { return primary }
        if content.isLowPower { return .systemYellow }
        if content.isCharging || content.isPluggedIn { return .systemGreen }
        return percent <= 20 ? .systemRed : primary
    }

    /// The ring runs clockwise from the bottom-left gap, over the top, to the
    /// bottom-right gap, leaving room for the percentage and the dots.
    private static func drawRing(_ content: Content, center: NSPoint, radius: CGFloat, primary: NSColor) {
        let start: CGFloat = 215
        let end: CGFloat = -35
        let sweep = start - end

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        track.lineWidth = 1.8
        track.lineCapStyle = .round
        primary.withAlphaComponent(0.28).setStroke()
        track.stroke()

        let fraction = CGFloat(content.batteryPercent ?? 100) / 100
        guard fraction > 0 else { return }
        let fill = NSBezierPath()
        fill.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep * fraction, clockwise: true)
        fill.lineWidth = 1.8
        fill.lineCapStyle = .round
        ringColor(content, primary: primary).setStroke()
        fill.stroke()
    }

    /// The figure, or a bolt/plug while on power, sits in a gap cut from the ring.
    private static func drawTop(_ content: Content, center: NSPoint, radius: CGFloat, primary: NSColor) {
        guard content.batteryPercent != nil else { return }
        let gapCenter = NSPoint(x: center.x, y: center.y + radius - 1)
        let clear = NSRect(x: gapCenter.x - 6.5, y: gapCenter.y - 3.5, width: 13, height: 9)
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(rect: clear).fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        if content.isCharging || content.isPluggedIn {
            // The portrait plug only exists from macOS 14; a bolt fits the gap on older systems.
            let name = content.isCharging || NSImage(systemSymbolName: "powerplug.portrait.fill", accessibilityDescription: nil) == nil
                ? "bolt.fill" : "powerplug.portrait.fill"
            drawSymbol(name, center: NSPoint(x: gapCenter.x, y: gapCenter.y + 0.5), pointSize: 6.5, color: primary)
        } else if let percent = content.batteryPercent {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .bold),
                .foregroundColor: primary
            ]
            let text = "\(percent)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: gapCenter.x - size.width / 2, y: gapCenter.y - size.height / 2 + 0.5), withAttributes: attributes)
        }
    }

    private static func drawConnection(_ content: Content, center: NSPoint, primary: NSColor) {
        let glyphCenter = NSPoint(x: center.x, y: center.y - 0.5)
        let name = content.isWiFiOn ? "wifi" : "wifi.slash"
        let color = content.wifiBars == 0 && content.isWiFiOn ? primary.withAlphaComponent(0.4) : primary
        drawSymbol(name, center: glyphCenter, pointSize: 9, color: color, variableValue: content.isWiFiOn ? Double(max(1, content.wifiBars)) / 3 : nil)
    }

    private static func drawVolume(_ content: Content, center: NSPoint, radius: CGFloat, primary: NSColor) {
        let lit = content.isMuted ? 0 : Int((content.volume * 5).rounded(.up))
        // Five dots along the lower arc of the ring's circle.
        for index in 0..<5 {
            let angle = (235 + CGFloat(index) * 17.5) * .pi / 180
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            let dot = NSBezierPath(ovalIn: NSRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
            (index < lit ? primary : primary.withAlphaComponent(0.28)).setFill()
            dot.fill()
        }
    }

    private static func drawSymbol(_ name: String, center: NSPoint, pointSize: CGFloat, color: NSColor, variableValue: Double? = nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let base = variableValue.flatMap { NSImage(systemSymbolName: name, variableValue: $0, accessibilityDescription: nil) }
            ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        guard let symbol = base?.withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
    }
}

// MARK: - Stats pill

final class StatsPillPlugin: BuiltInPlugin {
    private let item = DeckMenuBarItem()
    private var cancellable: AnyCancellable?
    private let defaults = PluginDefaults(pluginID: "com.statusdeck.statspill")
    private var lastContent: StatusPillRenderer.Content?

    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.statspill",
            name: "菜单栏读数",
            summary: "在菜单栏持续显示网络速度、CPU 和内存占用。",
            symbol: "gauge.with.dots.needle.33percent",
            category: .menuBar,
            enabledByDefault: false,
            sortOrder: 910
        ), services: services)
    }

    override var menuBarItem: DeckMenuBarItem? { item }

    override var settingsView: AnyView? {
        AnyView(StatsPillSettings(defaults: defaults) { [weak self] in self?.applyOptions() })
    }

    override func didActivate() {
        applyOptions()
        cancellable = services.store.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                MainActor.assumeIsolated { self?.redraw(snapshot) }
            }
    }

    override func willDeactivate() {
        cancellable = nil
        lastContent = nil
        services.store.sampler.removeInterest(owner: manifest.id)
    }

    private var showsNetwork: Bool { defaults.bool("network", default: true) }
    private var showsCPU: Bool { defaults.bool("cpu", default: true) }
    private var showsMemory: Bool { defaults.bool("memory", default: true) }

    private func applyOptions() {
        var metrics: Metric = []
        if showsNetwork { metrics.insert(.network) }
        if showsCPU { metrics.insert(.cpu) }
        if showsMemory { metrics.insert(.memory) }
        services.store.sampler.setInterest(owner: manifest.id, always: metrics)
        redraw(services.store.snapshot)
    }

    private func redraw(_ snapshot: SystemSnapshot) {
        let content = StatusPillRenderer.Content(
            upload: showsNetwork ? Format.speed(snapshot.network.uploadBytesPerSecond) : nil,
            download: showsNetwork ? Format.speed(snapshot.network.downloadBytesPerSecond) : nil,
            cpu: showsCPU ? Format.percent(snapshot.cpu.total) : nil,
            memory: showsMemory ? Format.percent(snapshot.memory.usedFraction) : nil
        )
        guard content != lastContent else { return }
        lastContent = content
        item.image = StatusPillRenderer.image(for: content)
    }
}

private struct StatsPillSettings: View {
    let defaults: PluginDefaults
    let onChange: () -> Void

    var body: some View {
        toggle(DeckL("网络速度"), key: "network")
        toggle("CPU", key: "cpu")
        toggle(DeckL("内存"), key: "memory")
    }

    private func toggle(_ title: String, key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { defaults.bool(key, default: true) },
            set: {
                defaults.set($0, forKey: key)
                onChange()
            }
        ))
    }
}

/// The compact two-line readout: network speed, CPU and memory in one pill.
enum StatusPillRenderer {
    struct Content: Equatable {
        var upload: String?
        var download: String?
        var cpu: String?
        var memory: String?
    }

    static func image(for content: Content) -> NSImage {
        let height: CGFloat = 22
        let speedWidth: CGFloat = content.upload == nil ? 0 : 52
        let cpuWidth: CGFloat = content.cpu == nil ? 0 : 26
        let memoryWidth: CGFloat = content.memory == nil ? 0 : 26
        let columns = [speedWidth, cpuWidth, memoryWidth].filter { $0 > 0 }
        let width = columns.reduce(0, +) + CGFloat(max(0, columns.count - 1)) * 5 + 14

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 1.5), xRadius: 7, yRadius: 7)
            NSColor.black.withAlphaComponent(0.16).setFill()
            pill.fill()

            let small = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
            let digits = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
            let value = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

            var x: CGFloat = 7
            if let upload = content.upload, let download = content.download {
                draw("↑", at: NSPoint(x: x, y: 11), font: digits)
                draw("↓", at: NSPoint(x: x, y: 1.5), font: digits)
                drawRight(upload, right: x + speedWidth, y: 11, font: digits)
                drawRight(download, right: x + speedWidth, y: 1.5, font: digits)
                x += speedWidth + 5
            }
            if let cpu = content.cpu {
                drawCentered("CPU", center: x + cpuWidth / 2, y: 12, font: small)
                drawCentered(cpu, center: x + cpuWidth / 2, y: 1.5, font: value)
                x += cpuWidth + 5
            }
            if let memory = content.memory {
                drawCentered("MEM", center: x + memoryWidth / 2, y: 12, font: small)
                drawCentered(memory, center: x + memoryWidth / 2, y: 1.5, font: value)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.black]
    }

    private static func draw(_ text: String, at point: NSPoint, font: NSFont) {
        (text as NSString).draw(at: point, withAttributes: attributes(font))
    }

    private static func drawRight(_ text: String, right: CGFloat, y: CGFloat, font: NSFont) {
        let size = (text as NSString).size(withAttributes: attributes(font))
        draw(text, at: NSPoint(x: right - size.width, y: y), font: font)
    }

    private static func drawCentered(_ text: String, center: CGFloat, y: CGFloat, font: NSFont) {
        let size = (text as NSString).size(withAttributes: attributes(font))
        draw(text, at: NSPoint(x: center - size.width / 2, y: y), font: font)
    }
}
