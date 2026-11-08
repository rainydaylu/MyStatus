import AppKit
import ApplicationServices
import Carbon
import StatusDeckKit
import SwiftUI

/// The window behind the global shortcut. It takes the keyboard without activating
/// the app, so the app the user was in stays frontmost, ready for ⌘V.
@MainActor
final class ClipboardBrowserController {
    private let model: ClipboardModel
    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var pasteTarget: NSRunningApplication?

    init(model: ClipboardModel) {
        self.model = model
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle() {
        isOpen ? close() : show()
    }

    func show() {
        if isOpen { return }
        pasteTarget = NSWorkspace.shared.frontmostApplication
        if panel == nil { panel = FloatingPanel() }
        guard let panel else { return }
        model.query = ""
        model.filter = .all
        model.sourceFilter = nil
        model.refreshAccess()
        model.reload()

        let view = DeckThemeRoot {
            ClipboardBrowserView(model: model, canPaste: canPaste, onClose: { [weak self] in self?.close() })
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = NSSize(width: min(355, visible.width - 16), height: min(720, visible.height - 16))
        panel.setFrame(NSRect(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - 8,
                              width: size.width, height: size.height), display: true)
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        let finalFrame = panel.frame
        panel.setFrameOrigin(NSPoint(x: finalFrame.minX + 14, y: finalFrame.minY))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().setFrameOrigin(finalFrame.origin)
        }
        installMonitors()
    }

    func close() {
        guard isOpen else { return }
        panel?.orderOut(nil)
        model.sourceFilter = nil
        removeMonitors()
        // This can run inside a button of that very view, so teardown waits a turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.panel?.contentView = nil
            }
        }
    }

    private func installMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private var canPaste: Bool {
        guard let pasteTarget, pasteTarget.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        return CGPreflightPostEventAccess()
    }

    private func paste(_ item: ClipboardItem) {
        guard canPaste, let target = pasteTarget else { model.copy(item); return }
        model.copy(item) {
            DispatchQueue.main.async {
                guard !target.isTerminated,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                      let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(target.processIdentifier)
                up.postToPid(target.processIdentifier)
            }
        }
    }

    /// nil swallows the key. Everything unhandled goes on to the search field.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        let isCommand = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
            return nil
        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return nil
        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem { paste(item) }
            return nil
        case kVK_Delete where isCommand:
            if let item = model.selectedItem { model.delete(item) }
            return nil
        case kVK_ANSI_P where isCommand:
            if let item = model.selectedItem { model.togglePin(item) }
            return nil
        default:
            return event
        }
    }
}
