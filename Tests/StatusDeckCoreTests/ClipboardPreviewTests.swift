import AppKit
import Foundation
import SQLite3
import Testing
@testable import StatusDeckCore

@Suite struct ClipboardPreviewTests {
    @Test func aFailedFormatRefreshRollsBackWithoutLosingTheOldBlob() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preview-rollback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directory: directory)
        let original = try payload([(PasteboardType.plainText, Data("same".utf8)), (PasteboardType.html, Data(repeating: 65, count: 300_000))])
        let id = try #require(store.insert(original, sourceBundleID: nil, sourceName: nil)).id
        var db: OpaquePointer?
        #expect(sqlite3_open(directory.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_formats BEFORE INSERT ON reps BEGIN SELECT RAISE(ABORT,'test failure'); END;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let next = try payload([(PasteboardType.plainText, Data("same".utf8)), (PasteboardType.html, Data("<b>same</b>".utf8))])
        #expect(store.insert(next, sourceBundleID: nil, sourceName: nil) == nil)
        #expect(store.representations(of: id) == original.representations)
        #expect(store.count() == 1)
    }
    private func payload(_ types: [(String, Data)]) throws -> ClipboardPayload {
        try #require(ClipboardPayload.make(items: [types], maxBytes: 4 * 1024 * 1024))
    }
    private func item(text: String, kind: ClipKind = .text) -> ClipboardItem {
        ClipboardItem(id: 1, kind: kind, text: text, preview: text, sourceBundleID: nil, sourceName: nil,
                      createdAt: Date(), isPinned: false, byteCount: text.utf8.count, thumbnail: nil)
    }

    @Test func quotedCSVPreservesCommasNewlinesEscapedQuotesAndEmptyCells() throws {
        let table = try #require(ClipboardTable.parse(text: "Name,Note,Value\r\nAlice,\"one, two\",\r\nBob,\"line 1\nline \"\"2\"\"\",3\r\n", delimiter: ","))
        #expect(table.rows == [["Name", "Note", "Value"], ["Alice", "one, two", ""], ["Bob", "line 1\nline \"2\"", "3"]])
        #expect(table.columnCount == 3)
        #expect(ClipboardTable.parse(text: "\"unclosed,a\nb,c", delimiter: ",") == nil)
    }

    @Test func tsvRecognizesSpreadsheetRangesWithoutCallingIndentedCodeATable() throws {
        let table = try #require(ClipboardTable.detect(text: "City\tCount\nHong Kong\t12\nHangzhou\t8\n"))
        #expect(table.rows[1] == ["Hong Kong", "12"])
        #expect(ClipboardTable.detect(text: "func one() {\n\treturn 1;\n}") == nil)
        #expect(ClipboardTable.detect(text: "ordinary text") == nil)
    }

    @Test func htmlTablesKeepHeadersEntitiesAndMergedCellCoordinates() throws {
        let html = "<TABLE><TR><TH rowspan='2'>City</TH><TH colspan='2'>Exposure</TH></TR><TR><TD>Heat &amp; sun</TD><TD>&#x7EFF;&#22320;</TD></TR><TR><TD>A<br>B</TD><TD>2</TD><TD>3</TD></TR></TABLE>"
        let table = try #require(ClipboardTable.html(html))
        #expect(table.rows == [["City", "Exposure", ""], ["", "Heat & sun", "绿地"], ["A\nB", "2", "3"]])
        #expect(table.headerRows.contains(0))
    }

    @Test func previewLimitsDoNotTurnMissingCellsIntoInventedValues() throws {
        let source = (0..<600).map { "\($0)\tvalue" }.joined(separator: "\n")
        let table = try #require(ClipboardTable.detect(text: source))
        #expect(table.rows.count == 500)
        #expect(table.isTruncated)
        #expect(table.rows.last == ["499", "value"])
        #expect(ClipboardTableView.columnName(0) == "A")
        #expect(ClipboardTableView.columnName(26) == "AA")
    }

    @Test func richOnlyAndHTMLOnlyCopiesAreCapturedAndUTF16IsReadable() throws {
        let rich = NSAttributedString(string: "Formatted note", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        let data = try #require(rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
        let made = try payload([(PasteboardType.rtf, data)])
        #expect(made.kind == .richText && made.text == "Formatted note")
        #expect(made.representations.first?.data == data)
        let html = try payload([(PasteboardType.html, Data("<p>Hello <b>world</b></p>".utf8))])
        #expect(html.kind == .richText && html.text == "Hello world")
        let utf16 = try payload([("public.utf16-plain-text", try #require("你好".data(using: .utf16)))])
        #expect(utf16.text == "你好")
    }

    @Test func tablesAreClassifiedFromHTMLAndFromSingleRowExplicitCSV() throws {
        let html = try payload([(PasteboardType.html, Data("<table><tr><td>A</td><td>B</td></tr></table>".utf8))])
        #expect(html.kind == .table)
        let csv = try payload([(PasteboardType.plainText, Data("A,B".utf8)), ("public.comma-separated-values-text", Data("A,B".utf8))])
        #expect(csv.kind == .table)
    }

    @Test func sameTextRefreshesOriginalFormatsWhileKeepingPinAndTags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preview-formats-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directory: directory)
        let plain = try payload([(PasteboardType.plainText, Data("same".utf8))])
        let first = try #require(store.insert(plain, sourceBundleID: nil, sourceName: nil))
        store.setPinned(first.id, true)
        let tag = try #require(store.addTag(name: "Work", color: .red))
        store.setTag(tag, for: first.id, included: true)
        let html = Data("<b>same</b>".utf8)
        let styled = try payload([(PasteboardType.plainText, Data("same".utf8)), (PasteboardType.html, html)])
        let second = try #require(store.insert(styled, sourceBundleID: nil, sourceName: nil))
        #expect(first.id == second.id && !second.isNew)
        #expect(store.representations(of: first.id).contains { $0.type == PasteboardType.html && $0.data == html })
        let current = try #require(store.fetch().first)
        #expect(current.isPinned && current.tagIDs == [tag])
        #expect(store.fetch(filter: .richText).count == 1)
    }

    @Test func richPreviewPreservesFontsAndTableCells() throws {
        let table = NSTextTable(); table.numberOfColumns = 2
        let text = NSMutableAttributedString()
        for (column, value) in ["First", "Second"].enumerated() {
            let style = NSMutableParagraphStyle()
            style.textBlocks = [NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: column, columnSpan: 1)]
            text.append(NSAttributedString(string: value + "\n", attributes: [.paragraphStyle: style, .font: NSFont.boldSystemFont(ofSize: 17)]))
        }
        let parsed = try #require(ClipboardTable.richText(text))
        #expect(parsed.rows == [["First", "Second"]])
        let data = try #require(text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        let document = ClipboardPreviewDocument.make(item: item(text: "First Second", kind: .richText), representations: [ClipRepresentation(itemIndex: 0, type: PasteboardType.rtf, data: data)])
        if case .table(let grid) = document.content { #expect(grid.rows[0] == ["First", "Second"]) }
        else { Issue.record("RTF table must have a grid preview") }
    }

    @Test func imagePreviewUsesOriginalDimensionsInsteadOfTheSmallThumbnail() throws {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAEBgIApD5fRAAAAABJRU5ErkJggg==")!
        let document = ClipboardPreviewDocument.make(item: item(text: "", kind: .image), representations: [ClipRepresentation(itemIndex: 0, type: PasteboardType.png, data: data)])
        if case .image(_, let info) = document.content { #expect(info.width == 1 && info.height == 1 && info.format == "PNG") }
        else { Issue.record("PNG needs an image preview") }
    }

    @Test func sourceURLMetadataDoesNotTreatAnArbitraryBodyLinkAsTheSource() {
        let source = "Version:1.0\r\nSourceURL:https://example.com/source\r\n<p><a href='https://other.test'>Link</a></p>"
        #expect(ClipboardPreviewDocument.sourceURL(in: [ClipRepresentation(itemIndex: 0, type: PasteboardType.html, data: Data(source.utf8))])?.host == "example.com")
        #expect(ClipboardPreviewDocument.sourceURL(in: [ClipRepresentation(itemIndex: 0, type: PasteboardType.html, data: Data("<a href='https://other.test'>Link</a>".utf8))]) == nil)
    }

    @Test func previewWindowStaysOnScreenOnEitherSideAndOnSmallScreens() {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 920), CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 640, height: 480)] {
            let shelf = CGRect(x: screen.maxX - 408, y: screen.minY + 8, width: 400, height: screen.height - 16)
            let frame = ClipboardPreviewLayout.frame(beside: shelf, visible: screen)
            #expect(screen.contains(frame))
            #expect(frame.width > 200 && frame.height > 200)
        }
    }

    @Test func colorConversionsHandleBlackAndPrimaryGreenWithoutNaN() {
        let black = ClipboardColorInfo(red: 0, green: 0, blue: 0, alpha: 1)
        #expect(black.cmyk == "0%, 0%, 0%, 100%")
        #expect(black.hsl == "0°, 0%, 0%")
        let green = ClipboardColorInfo(red: 0, green: 1, blue: 0, alpha: 1)
        #expect(green.rgb == "0, 255, 0")
        #expect(green.hex == "#00FF00")
        #expect(green.hsl == "120°, 100%, 50%")
        #expect(green.hsb == "120°, 100%, 100%")
    }
}
