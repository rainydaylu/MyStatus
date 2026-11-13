import AppKit
import Carbon
import Foundation
import StatusDeckKit
import Testing
@testable import StatusDeckCore

@MainActor private final class ClipboardWindowTestHost: DeckHost {
    let isPanelVisible = false
    let isDryRun = true
    func storageDirectory(for pluginID: String) -> URL { FileManager.default.temporaryDirectory }
    func showLevel(symbol: String, value: Double, title: String?) {}
    func openPanel(showing sectionID: String?) {}
    func closePanel() {}
    func openSettings(pluginID: String?) {}
    func pluginContentDidChange() {}
    func registerHotKey(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? { nil }
}

@MainActor @Suite(.serialized) struct ClipboardWindowTests {
    private func sampleModel() async throws -> ClipboardModel {
        let model = ClipboardModel()
        model.start(host: ClipboardWindowTestHost(), pluginID: "clipboard.window.tests")
        for _ in 0..<100 {
            if !model.items.isEmpty { return model }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw CocoaError(.fileReadUnknown)
    }

    private func waitForRows(_ model: ClipboardModel, ids: [Int64]) async throws {
        for _ in 0..<100 {
            if model.previewListFrame.height > 0,
               ids.allSatisfy({ model.previewRowFrames[$0]?.height ?? 0 > 0 }) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(model.previewListFrame.height > 0, "The actual list viewport must be measured")
        throw CocoaError(.coderValueNotFound)
    }

    @Test func doubleClickCopiesOnceAndClosesBothWindows() async throws {
        _ = NSApplication.shared
        let model = try await sampleModel()
        defer { model.stop() }
        let item = try #require(model.items.first)
        var copies = 0
        model.onCopied = { copies += 1 }
        let controller = ClipboardBrowserController(model: model)
        controller.show()
        defer { controller.close() }
        let shelf = try #require(NSApp.windows.first { $0.isVisible && $0.frame == controller.shelfFrame })
        try await waitForRows(model, ids: [item.id])
        let row = try #require(model.previewRowFrames[item.id])
        model.selectPreview(item)
        #expect(controller.isPreviewVisible)
        func release(_ clicks: Int, y: CGFloat? = nil) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: .leftMouseUp,
                location: CGPoint(x: controller.shelfFrame.minX - shelf.frame.minX + row.midX,
                                  y: controller.shelfFrame.maxY - shelf.frame.minY - (y ?? row.midY)), modifierFlags: [],
                timestamp: 0, windowNumber: shelf.windowNumber, context: nil,
                eventNumber: clicks, clickCount: clicks, pressure: 0))
        }
        _ = controller.handle(try release(1))
        #expect(copies == 0)
        #expect(controller.isOpen)
        // A double-click in the toolbar must not copy the selected record.
        _ = controller.handle(try release(2, y: 20))
        #expect(copies == 0)
        #expect(controller.isOpen)
        let doubleClick = try release(2)
        _ = controller.handle(doubleClick)
        #expect(copies == 1)
        #expect(!controller.isOpen)
        #expect(!controller.isPreviewVisible)
        _ = controller.handle(doubleClick)
        #expect(copies == 1)
    }

    @Test func escapeClosesTheShelfAndPreviewFromEitherPane() async throws {
        _ = NSApplication.shared
        let model = try await sampleModel()
        defer { model.stop() }
        let item = try #require(model.items.first)
        let controller = ClipboardBrowserController(model: model)
        defer { controller.close() }
        for fromDetail in [false, true] {
            controller.show()
            model.selectPreview(item)
            let window = try #require(NSApp.windows.first { $0.isVisible && $0.frame.contains(controller.shelfFrame) })
            if fromDetail, let preview = controller.previewFrame {
                let responder = NSTextView(frame: CGRect(x: preview.minX - window.frame.minX + 20,
                    y: preview.minY - window.frame.minY + 20, width: 100, height: 100))
                window.contentView?.addSubview(responder)
                window.makeFirstResponder(responder)
            }
            #expect(controller.isPreviewVisible)
            let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false, keyCode: UInt16(kVK_Escape)))
            #expect(controller.handle(escape) == nil)
            #expect(!controller.isOpen)
            #expect(!controller.isPreviewVisible)
        }
    }

    @Test func hoveringRealRenderedRowsShowsPreviewInsideTheSameWindow() async throws {
        _ = NSApplication.shared
        let model = try await sampleModel()
        defer { model.stop() }
        let controller = ClipboardBrowserController(model: model)
        controller.show()
        defer { controller.close() }
        let rows = Array(model.items.prefix(3))
        #expect(rows.count == 3)
        // Read actual SwiftUI geometry instead of supplying invented hit boxes.
        try await waitForRows(model, ids: rows.map(\.id))
        let frame = controller.shelfFrame
        let firstRow = try #require(model.previewRowFrames[rows[0].id])
        let thirdRow = try #require(model.previewRowFrames[rows[2].id])
        #expect(model.previewListFrame.height > 0)
        let pointer = CGPoint(x: frame.minX + firstRow.midX, y: frame.maxY - firstRow.midY)
        controller.trackPointer(at: pointer)
        #expect(model.selectedID == rows[0].id)
        #expect(controller.isOpen)
        #expect(controller.isPreviewVisible)
        let preview = try #require(controller.previewFrame)
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.frame.contains(frame) && $0.frame.contains(preview) })
        #expect(window.childWindows?.isEmpty != false)
        #expect(controller.shelfFrame == frame)
        #expect(!preview.intersects(frame))
        #expect(window.contentView?.bounds.size == window.frame.size)
        model.selectPreview(rows[1], pointer: pointer)
        controller.trackPointer(at: pointer)
        #expect(model.selectedID == rows[1].id)
        #expect(controller.isPreviewVisible)
        controller.trackPointer(at: CGPoint(x: frame.minX + thirdRow.midX, y: frame.maxY - thirdRow.midY))
        #expect(model.selectedID == rows[2].id)
        #expect(controller.isPreviewVisible)
        model.isPreviewExpanded = false
        #expect(!controller.isPreviewVisible)
    }
}
