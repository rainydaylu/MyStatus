import AppKit
import ApplicationServices
import Carbon
import Combine
import StatusDeckKit
import SwiftUI

struct ClipboardWindowPlacement: Equatable {
    var shelf: CGRect = .zero
    var preview: CGRect?
    var window: CGRect { (preview.map { shelf.union($0) } ?? shelf).integral }

    func localFrame(_ screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX - window.minX, y: window.maxY - screenFrame.maxY,
               width: screenFrame.width, height: screenFrame.height)
    }
}

@MainActor private final class ClipboardWindowState: ObservableObject {
    @Published var placement = ClipboardWindowPlacement()
}

/// Keep the shelf and its preview in one native window, like the main menu.
/// Both stay key, share the same glass, and cannot be ordered behind one another.
private struct ClipboardWindowView: View {
    @ObservedObject var state: ClipboardWindowState
    let model: ClipboardModel
    let detail: ClipboardDetailModel
    let canPaste: Bool
    let onClose: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        let placement = state.placement
        let shelf = placement.localFrame(placement.shelf)
        ZStack(alignment: .topLeading) {
            ClipboardBrowserView(model: model, canPaste: canPaste, onClose: onClose)
                .frame(width: shelf.width, height: shelf.height)
                .offset(x: shelf.minX, y: shelf.minY)
            if let frame = placement.preview {
                let preview = placement.localFrame(frame)
                ClipboardDetailView(model: detail, onClose: onCollapse)
                    .frame(width: preview.width, height: preview.height)
                    .offset(x: preview.minX, y: preview.minY)
            }
        }
        .frame(width: placement.window.width, height: placement.window.height, alignment: .topLeading)
        .modifier(MenuPanelPalette())
    }
}

/// The window behind the global shortcut. It takes the keyboard without activating
/// the app, so the app the user was in stays frontmost, ready for ⌘V.
@MainActor
final class ClipboardBrowserController {
    private let model: ClipboardModel
    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var pasteTarget: NSRunningApplication?
    private let windowState = ClipboardWindowState()
    private let detail = ClipboardDetailModel()
    private var displayedItem: ClipboardItem?
    private var previewRequest = UUID()
    private var pointerTimer: Timer?
    private var directTouchTap: DirectTouchTapTarget?
    private var doubleTap: DirectTouchTapTarget?

    init(model: ClipboardModel) {
        self.model = model
        model.onPreviewChanged = { [weak self] in self?.updatePreview() }
    }

    var isOpen: Bool { panel?.isVisible ?? false }
    var isPreviewVisible: Bool { isOpen && windowState.placement.preview != nil }
    var shelfFrame: CGRect { windowState.placement.shelf }
    var previewFrame: CGRect? { windowState.placement.preview }

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
        model.selectedTagID = nil
        model.isPreviewExpanded = false
        model.resetPreviewInteraction()
        model.previewRowFrames = [:]
        model.previewListFrame = .zero
        model.refreshAccess()
        model.reload()

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = NSSize(width: min(400, visible.width - 16), height: visible.height - 16)
        let shelf = NSRect(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - 8,
                           width: size.width, height: size.height)
        windowState.placement = ClipboardWindowPlacement(shelf: shelf)
        panel.setFrame(shelf, display: true)
        let view = DeckThemeRoot {
            ClipboardWindowView(state: windowState, model: model, detail: detail, canPaste: canPaste,
                                onClose: { [weak self] in self?.close() },
                                onCollapse: { [weak self] in self?.collapsePreview() })
        }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: shelf.size)
        hosting.allowedTouchTypes = [.direct, .indirect]
        directTouchTap = DirectTouchTapTarget(view: hosting) { [weak self] point in
            guard let self, let item = self.item(atWindowPoint: point) else { return }
            self.model.selectPreview(item)
        }
        doubleTap = DirectTouchTapTarget(view: hosting, clickCount: 2, directTouchesOnly: false) { [weak self] point in
            guard let self, let item = self.item(atWindowPoint: point) else { return }
            self.copyAndClose(item)
        }
        panel.contentView = hosting
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        startPointerTracking()
        updatePreview()
    }

    func close() {
        guard isOpen else { return }
        collapsePreview()
        pointerTimer?.invalidate()
        pointerTimer = nil
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

    private func item(at point: CGPoint) -> ClipboardItem? {
        guard let id = ClipboardPointerGeometry.itemID(at: point, list: model.previewListFrame, rows: model.previewRowFrames) else { return nil }
        return model.items.first { $0.id == id }
    }

    private func item(atWindowPoint point: CGPoint) -> ClipboardItem? {
        guard let panel else { return nil }
        let screen = CGPoint(x: panel.frame.minX + point.x, y: panel.frame.maxY - point.y)
        return item(atScreenPoint: screen)
    }

    private func item(atScreenPoint pointer: CGPoint) -> ClipboardItem? {
        guard shelfFrame.contains(pointer) else { return nil }
        return item(at: CGPoint(x: pointer.x - shelfFrame.minX, y: shelfFrame.maxY - pointer.y))
    }

    private func startPointerTracking() {
        pointerTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.trackPointer(at: NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    func trackPointer(at pointer: CGPoint) {
        guard isOpen else { return }
        if let item = item(atScreenPoint: pointer) { model.hoverPreview(item, pointer: pointer, isDragging: false) }
    }

    private func collapsePreview() {
        model.holdPreviewSelection()
        model.isPreviewExpanded = false
        setPreviewFrame(nil)
        detail.document = nil
        displayedItem = nil
        previewRequest = UUID()
    }

    private func setPreviewFrame(_ preview: CGRect?) {
        var placement = windowState.placement
        guard placement.preview != preview else { return }
        placement.preview = preview
        windowState.placement = placement
        panel?.setFrame(placement.window, display: true)
        panel?.contentView?.frame = CGRect(origin: .zero, size: placement.window.size)
        panel?.contentView?.layoutSubtreeIfNeeded()
    }

    private func updatePreview() {
        guard isOpen, model.isPreviewExpanded, let item = model.selectedItem, let panel else {
            if isOpen { setPreviewFrame(nil) }
            return
        }
        guard let visible = (panel.screen ?? NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main)?.visibleFrame else { return }
        setPreviewFrame(ClipboardPreviewLayout.frame(beside: shelfFrame, visible: visible))
        guard displayedItem != item else { return }
        displayedItem = item
        detail.document = nil
        detail.isLoading = true
        let request = UUID()
        previewRequest = request
        model.loadPreview(for: item) { [weak self] document in
            guard let self, self.previewRequest == request, self.isOpen, self.model.isPreviewExpanded else { return }
            self.detail.document = document
            self.detail.isLoading = false
        }
    }

    private func installMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pointer = NSEvent.mouseLocation
                if self.shelfFrame.contains(pointer) || self.previewFrame?.contains(pointer) == true { return }
                self.close()
            }
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

    private func copyAndClose(_ item: ClipboardItem) {
        model.copy(item) { [weak self] in self?.close() }
    }

    private var isShelfResponder: Bool {
        guard let panel, let preview = previewFrame, let responder = panel.firstResponder as? NSView else { return true }
        let center = responder.convert(CGPoint(x: responder.bounds.midX, y: responder.bounds.midY), to: nil)
        return !preview.contains(panel.convertPoint(toScreen: center))
    }

    /// nil swallows the key. Everything unhandled goes on to the search field.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isOpen else { return event }
        guard event.window === panel, let panel else { return event }
        if event.type == .leftMouseDown {
            let point = panel.convertPoint(toScreen: event.locationInWindow)
            if !shelfFrame.contains(point), previewFrame?.contains(point) != true {
                close()
                return nil
            }
            return event
        }
        if event.type == .leftMouseUp {
            // A native double-click leaves the row's immediate single-click preview
            // and drag handling intact. Only the second release performs a copy.
            if event.clickCount == 2 {
                if let item = item(atScreenPoint: panel.convertPoint(toScreen: event.locationInWindow)) { copyAndClose(item) }
            }
            return event
        }
        guard event.type == .keyDown else { return event }
        let isCommand = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
            return nil
        case kVK_Space where isShelfResponder && (model.query.isEmpty || !(panel.firstResponder is NSTextView)):
            model.isPreviewExpanded.toggle()
            return nil
        case kVK_RightArrow where event.modifierFlags.contains(.command):
            model.isPreviewExpanded = true
            return nil
        case kVK_DownArrow where isShelfResponder:
            model.holdPreviewSelection()
            model.moveSelection(by: 1)
            return nil
        case kVK_UpArrow where isShelfResponder:
            model.holdPreviewSelection()
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
