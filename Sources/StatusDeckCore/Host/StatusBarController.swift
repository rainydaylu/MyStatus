import AppKit
import Carbon
import Combine
import StatusDeckKit

/// One menu bar icon per plugin that wants one. With none, a plain icon stays so
/// that there is always a way to reach the panel and turn plugins back on.
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
        var imageCancellable: AnyCancellable?

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
        let wanted = manager.activePlugins.compactMap { plugin -> (String, DeckMenuBarItem)? in
            plugin.menuBarItem.map { (plugin.manifest.id, $0) }
        }

        for id in items.keys where !wanted.contains(where: { $0.0 == id }) {
            if let item = items.removeValue(forKey: id) {
                NSStatusBar.system.removeStatusItem(item.statusItem)
            }
        }
        for (id, model) in wanted where items[id] == nil {
            items[id] = makeItem(id: id, model: model)
        }

        if wanted.isEmpty {
            if fallback == nil { fallback = makeFallback() }
        } else if let existing = fallback {
            NSStatusBar.system.removeStatusItem(existing)
            fallback = nil
        }
    }

    private func makeItem(id: String, model: DeckMenuBarItem) -> ManagedItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "StatusDeck.\(id)"
        // The in-app switch controls visibility for the primary icon.
        if id == TrioIconPlugin.id { statusItem.isVisible = true }
        let managed = ManagedItem(statusItem: statusItem)
        configure(statusItem)
        if let button = statusItem.button {
            button.image = model.image
            let catcher = ScrollCatcher(frame: button.bounds)
            catcher.autoresizingMask = [.width, .height]
            catcher.onScroll = { [weak model] delta in model?.onScroll?(delta) }
            button.addSubview(catcher)
        }
        managed.imageCancellable = model.$image.sink { [weak statusItem] image in
            statusItem?.button?.image = image
        }
        return managed
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
                MainActor.assumeIsolated { center?.handlers[identifier] = nil }
            }
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var nextIdentifier: UInt32 = 1
    private var isInstalled = false
    private static let signature: OSType = 0x53444B48 // "SDKH"

    func register(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? {
        installIfNeeded()
        let identifier = nextIdentifier
        nextIdentifier += 1
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        handlers[identifier] = handler
        return Token(reference: reference, identifier: identifier, center: self)
    }

    private func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
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
                MainActor.assumeIsolated { center.handlers[identifier]?() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
