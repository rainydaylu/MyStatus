import AppKit
import Carbon
import Combine
import StatusDeckKit

/// The main status icon and readouts share one button. Other plugins keep their
/// own items, and a fallback keeps settings reachable when all items are disabled.
@MainActor
final class StatusBarController {
    private let manager: PluginManager
    private let panel: PanelController
    private let openSettings: () -> Void
    private var items: [String: ManagedItem] = [:]
    private var fallback: NSStatusItem?
    private var cancellable: AnyCancellable?

    private final class ManagedItem {
        let statusItem: NSStatusItem
        var models: [DeckMenuBarItem] = []
        var images: [NSImage?] = []
        var imageCancellables: [AnyCancellable] = []

        init(statusItem: NSStatusItem) {
            self.statusItem = statusItem
        }
    }

    init(manager: PluginManager, panel: PanelController, openSettings: @escaping () -> Void) {
        self.manager = manager
        self.panel = panel
        self.openSettings = openSettings
        cancellable = manager.$contentVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            }
    }

    /// Something to hang the panel from when it opens without a click on an icon.
    var primaryButton: NSStatusBarButton? {
        items[TrioIconPlugin.id]?.statusItem.button ?? items.values.first?.statusItem.button ?? fallback?.button
    }

    func sync() {
        let sources = manager.activePlugins.compactMap { plugin -> (String, DeckMenuBarItem)? in
            plugin.menuBarItem.map { (plugin.manifest.id, $0) }
        }
        let wanted = StatusBarGroup.groups(sources)

        for id in items.keys where !wanted.contains(where: { $0.id == id }) {
            if let item = items.removeValue(forKey: id) {
                NSStatusBar.system.removeStatusItem(item.statusItem)
            }
        }
        for group in wanted {
            let managed = items[group.id] ?? makeItem(id: group.id)
            items[group.id] = managed
            bind(group.models, to: managed)
        }

        if wanted.isEmpty {
            if fallback == nil { fallback = makeFallback() }
        } else if let existing = fallback {
            NSStatusBar.system.removeStatusItem(existing)
            fallback = nil
        }
    }

    private func makeItem(id: String) -> ManagedItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "StatusDeck.\(id)"
        // The in-app switch controls visibility for the primary icon.
        if id == TrioIconPlugin.id { statusItem.isVisible = true }
        let managed = ManagedItem(statusItem: statusItem)
        configure(statusItem)
        if let button = statusItem.button {
            let catcher = ScrollCatcher(frame: button.bounds)
            catcher.autoresizingMask = [.width, .height]
            catcher.onScroll = { [weak managed] delta in
                managed?.models.first(where: { $0.onScroll != nil })?.onScroll?(delta)
            }
            button.addSubview(catcher)
        }
        return managed
    }

    private func bind(_ models: [DeckMenuBarItem], to managed: ManagedItem) {
        guard models.map(ObjectIdentifier.init) != managed.models.map(ObjectIdentifier.init) else { return }
        managed.imageCancellables.removeAll()
        managed.models = models
        managed.images = models.map(\.image)
        managed.statusItem.button?.image = StatusBarGroup.image(managed.images)
        for (index, model) in models.enumerated() {
            let sourceID = ObjectIdentifier(model)
            let subscription = model.$image
                .receive(on: DispatchQueue.main)
                .sink { [weak managed] image in
                    MainActor.assumeIsolated {
                        guard let managed, managed.models.indices.contains(index),
                              ObjectIdentifier(managed.models[index]) == sourceID else { return }
                        managed.images[index] = image
                        managed.statusItem.button?.image = StatusBarGroup.image(managed.images)
                    }
                }
            managed.imageCancellables.append(subscription)
        }
    }

    private func makeFallback() -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "StatusDeck.fallback"
        configure(statusItem)
        let image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "MyStatus")
        image?.isTemplate = true
        statusItem.button?.image = image
        return statusItem
    }

    private func configure(_ statusItem: NSStatusItem) {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("MyStatus")
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.close()
            showMenu(from: sender)
        } else {
            panel.toggle(from: sender)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let label = NSMenuItem(title: "MyStatus \(version)", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: DeckL("插件与设置…"), action: #selector(settingsChosen), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: DeckL("退出 MyStatus"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let statusItem = items.values.first { $0.statusItem.button === button }?.statusItem ?? fallback
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func settingsChosen() {
        openSettings()
    }
}

@MainActor
struct StatusBarGroup {
    let id: String
    let models: [DeckMenuBarItem]

    static func groups(_ sources: [(String, DeckMenuBarItem)]) -> [StatusBarGroup] {
        let mainIDs = [TrioIconPlugin.id, StatsPillPlugin.id]
        let main = mainIDs.compactMap { id in sources.first(where: { $0.0 == id })?.1 }
        let independent = sources.filter { !mainIDs.contains($0.0) }
            .map { StatusBarGroup(id: $0.0, models: [$0.1]) }
        guard !main.isEmpty else { return independent }
        return [StatusBarGroup(id: TrioIconPlugin.id, models: main)] + independent
    }

    static func image(_ sources: [NSImage?]) -> NSImage? {
        let images = sources.compactMap { $0 }
        guard let first = images.first else { return nil }
        guard images.count > 1 else { return first }
        let gap: CGFloat = 4
        let size = NSSize(width: images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(images.count - 1),
                          height: images.map(\.size.height).max() ?? 22)
        let combined = NSImage(size: size, flipped: false) { bounds in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let tint: NSColor = isDark ? .white : .black
            var x: CGFloat = 0
            for source in images {
                let frame = NSRect(x: x, y: (bounds.height - source.size.height) / 2,
                                   width: source.size.width, height: source.size.height)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: frame).addClip()
                source.draw(in: frame)
                if source.isTemplate {
                    NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
                    tint.setFill()
                    NSBezierPath(rect: frame).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                x += source.size.width + gap
            }
            return true
        }
        combined.isTemplate = false
        return combined
    }
}

/// Takes scroll events on the status button and leaves every click to the button
/// underneath, which is why `hitTest` depends on the event in flight.
private final class ScrollCatcher: NSView {
    var onScroll: ((Double) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
    }

    override func scrollWheel(with event: NSEvent) {
        // Trackpads report fine-grained deltas, wheels whole notches.
        let step = event.hasPreciseScrollingDeltas ? 0.005 : 0.03
        let delta = Double(event.scrollingDeltaY) * step
        if delta != 0 { onScroll?(delta) }
    }
}

// MARK: - Global shortcuts

/// Carbon's hot keys need no Accessibility permission, unlike an event tap.
@MainActor
final class HotKeyCenter {
    private final class Token: DeckHotKeyToken {
        let reference: EventHotKeyRef
        let identifier: UInt32
        weak var center: HotKeyCenter?

        init(reference: EventHotKeyRef, identifier: UInt32, center: HotKeyCenter) {
            self.reference = reference
            self.identifier = identifier
            self.center = center
        }

        deinit {
            UnregisterEventHotKey(reference)
            let identifier = identifier
            let center = center
            // Dropping a token can happen from anywhere; the table belongs to the main actor.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    center?.handlers[identifier] = nil
                    center?.shortcuts[identifier] = nil
                    center?.lastInvocation[identifier] = nil
                }
            }
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var shortcuts: [UInt32: DeckHotKey] = [:]
    private var lastInvocation: [UInt32: TimeInterval] = [:]
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var nextIdentifier: UInt32 = 1
    private var isInstalled = false
    private static let signature: OSType = 0x53444B48 // "SDKH"

    func register(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? {
        guard installIfNeeded() else { return nil }
        let identifier = nextIdentifier
        nextIdentifier += 1
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        handlers[identifier] = handler
        shortcuts[identifier] = hotKey
        return Token(reference: reference, identifier: identifier, center: self)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        return result
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = Self.carbonModifiers(event.modifierFlags)
        guard let id = shortcuts.first(where: {
            $0.value.keyCode == UInt32(event.keyCode) && $0.value.modifiers == modifiers
        })?.key else { return false }
        if !event.isARepeat { invoke(id) }
        return true
    }

    private func invoke(_ identifier: UInt32) {
        let now = ProcessInfo.processInfo.systemUptime
        // Carbon and AppKit may both deliver the same physical press.
        guard now - (lastInvocation[identifier] ?? -.infinity) > 0.15 else { return }
        lastInvocation[identifier] = now
        handlers[identifier]?()
    }

    private func installIfNeeded() -> Bool {
        guard !isInstalled else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr else { return status }
            guard id.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            let identifier = id.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.invoke(identifier) }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
        isInstalled = status == noErr
        if isInstalled {
            // Carbon remains the permission-free global route. AppKit also
            // covers directly delivered key events and existing authorized
            // keyboard monitoring; neither path requests a new permission.
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.handleKey(event) == true ? nil : event }
            }
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { _ = self?.handleKey(event) }
            }
        }
        return isInstalled
    }
}
