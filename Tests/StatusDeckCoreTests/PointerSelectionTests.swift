import AppKit
import Testing
@testable import StatusDeckCore

@Suite struct PointerSelectionTests {
    @Test func clippedRowsDoNotTreatTheToolbarAsAClipboardEntry() {
        let list = CGRect(x: 0, y: 80, width: 400, height: 400)
        let rows: [Int64: CGRect] = [1: CGRect(x: 0, y: 20, width: 400, height: 80),
                                    2: CGRect(x: 0, y: 100, width: 400, height: 80)]
        #expect(ClipboardPointerGeometry.itemID(at: CGPoint(x: 10, y: 40), list: list, rows: rows) == nil)
        #expect(ClipboardPointerGeometry.itemID(at: CGPoint(x: 10, y: 120), list: list, rows: rows) == 2)
    }
    @MainActor @Test func previewChangeIsDeliveredAfterTheSelectionAndExpansionAreCommitted() {
        let model = ClipboardModel()
        let row = ClipboardItem(id: 42, kind: .text, text: "Preview", preview: "Preview", sourceBundleID: nil,
                                sourceName: nil, createdAt: .now, isPinned: false, byteCount: 7, thumbnail: nil)
        var events: [(Int64?, Bool)] = []
        model.onPreviewChanged = { events.append((model.selectedID, model.isPreviewExpanded)) }
        model.selectPreview(row, pointer: .zero)
        #expect(events.last?.0 == 42)
        #expect(events.last?.1 == true)
        model.isPreviewExpanded = false
        #expect(events.last?.1 == false)
        model.onPreviewChanged = nil
    }
    @Test func aClickOverridesTheStationaryPointerUntilTheMouseActuallyMoves() {
        var gate = PointerSelectionGate()
        let mouse = CGPoint(x: 100, y: 100)
        let allowed1 = gate.permitsHover(at: mouse)
        #expect(allowed1)
        gate.hold(at: mouse)
        let allowed2 = gate.permitsHover(at: mouse)
        #expect(!allowed2)
        let allowed3 = gate.permitsHover(at: CGPoint(x: 100.2, y: 100))
        #expect(!allowed3)
        let allowed4 = gate.permitsHover(at: CGPoint(x: 102, y: 100))
        #expect(allowed4)
        let allowed5 = gate.permitsHover(at: CGPoint(x: 102, y: 100))
        #expect(allowed5)
        gate.hold(at: CGPoint(x: 102, y: 100))
        let allowed6 = gate.permitsHover(at: CGPoint(x: 102, y: 100))
        #expect(!allowed6)
    }

    @MainActor @Test func clipboardHoverClickAndLaterMovementHaveTheRequestedPrecedence() {
        let model = ClipboardModel()
        func item(_ id: Int64) -> ClipboardItem {
            ClipboardItem(id: id, kind: .text, text: "Item \(id)", preview: "Item \(id)", sourceBundleID: nil,
                          sourceName: nil, createdAt: .now, isPinned: false, byteCount: 6, thumbnail: nil)
        }
        let a = item(1), b = item(2), c = item(3)
        let pointer = CGPoint(x: 20, y: 40)
        model.hoverPreview(a, pointer: pointer, isDragging: false)
        #expect(model.selectedID == a.id && model.isPreviewExpanded)
        // A finger clicks B while the mouse still rests on A.
        model.selectPreview(b, pointer: pointer)
        model.hoverPreview(a, pointer: pointer, isDragging: false)
        #expect(model.selectedID == b.id)
        // The next mouse movement takes over again.
        model.hoverPreview(c, pointer: CGPoint(x: 24, y: 44), isDragging: false)
        #expect(model.selectedID == c.id)
        model.hoverPreview(a, pointer: CGPoint(x: 50, y: 60), isDragging: true)
        #expect(model.selectedID == c.id)
    }

    @Test func plainTextExtractionUnderstandsRichOnlyAndMultipleFileCopies() {
        let html = ClipRepresentation(itemIndex: 0, type: PasteboardType.html, data: Data("<p>Hello <b>world</b></p>".utf8))
        #expect(ClipboardPlainText.from([html]) == "Hello world")
        let files = [ClipRepresentation(itemIndex: 0, type: PasteboardType.fileURL, data: Data("file:///tmp/one.txt".utf8)),
                     ClipRepresentation(itemIndex: 1, type: PasteboardType.fileURL, data: Data("file:///tmp/two.txt".utf8))]
        #expect(ClipboardPlainText.from(files) == "/tmp/one.txt\n/tmp/two.txt")
        #expect(ClipboardPlainText.from([ClipRepresentation(itemIndex: 0, type: PasteboardType.png, data: Data())]) == nil)
    }
}
