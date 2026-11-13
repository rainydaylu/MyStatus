import AppKit
import Foundation
import Testing
@testable import StatusDeckCore

private func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("statusdeck-clip-\(UUID().uuidString)")
}

private func text(_ string: String) -> [[(type: String, data: Data)]] {
    [[(PasteboardType.plainText, Data(string.utf8))]]
}

private func payload(_ string: String) -> ClipboardPayload {
    ClipboardPayload.make(items: text(string), maxBytes: 1 << 20)!
}

@Suite struct ClassifierTests {
    @Test func linksMustBeASingleURL() {
        #expect(ClipboardClassifier.isLink("https://example.com/a?b=1"))
        #expect(ClipboardClassifier.isLink("  https://example.com  "))
        #expect(!ClipboardClassifier.isLink("see https://example.com"))
        #expect(!ClipboardClassifier.isLink("example.com"))
        #expect(!ClipboardClassifier.isLink("file:///etc/hosts"))
    }

    @Test func colorsParseCommonForms() throws {
        let full = try #require(ClipboardClassifier.color(from: "#2B7DF6"))
        #expect(abs(full.red - 43.0 / 255) < 0.001)
        let short = try #require(ClipboardClassifier.color(from: "#fff"))
        #expect(short.red == 1 && short.blue == 1)
        let alpha = try #require(ClipboardClassifier.color(from: "#00000080"))
        #expect(abs(alpha.alpha - 128.0 / 255) < 0.001)
        let rgb = try #require(ClipboardClassifier.color(from: "rgb(255, 0, 0)"))
        #expect(rgb.red == 1 && rgb.green == 0)
    }

    @Test func colorRejectsLookalikes() {
        #expect(ClipboardClassifier.color(from: "#12") == nil)
        #expect(ClipboardClassifier.color(from: "#zzzzzz") == nil)
        #expect(ClipboardClassifier.color(from: "rgb(300, 0, 0)") == nil)
        #expect(ClipboardClassifier.color(from: "hello") == nil)
    }

    @Test func codeNeedsSeveralLinesAndSignals() {
        #expect(ClipboardClassifier.looksLikeCode("func a() {\n    return 1;\n}"))
        #expect(!ClipboardClassifier.looksLikeCode("一行普通的话"))
        #expect(!ClipboardClassifier.looksLikeCode("第一行\n第二行\n第三行"))
    }

    @Test func previewCollapsesWhitespaceAndTruncates() {
        #expect(ClipboardClassifier.preview(of: " a\n\n b\tc ") == "a b c")
        #expect(ClipboardClassifier.preview(of: String(repeating: "x", count: 1000)).count == 241)
    }
}

@Suite struct PayloadTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAEBgIApD5fRAAAAABJRU5ErkJggg==")!

    @Test func filesWinOverTheirTextForm() throws {
        let made = try #require(ClipboardPayload.make(items: [[
            (PasteboardType.fileURL, Data("file:///tmp/a.txt".utf8)),
            (PasteboardType.plainText, Data("a.txt".utf8)),
            ("com.apple.icns", Data(repeating: 1, count: 100))
        ]], maxBytes: 1 << 20))
        #expect(made.kind == .file)
        #expect(made.preview == "a.txt")
        #expect(made.representations.map(\.type) == [PasteboardType.fileURL], "icons do not need keeping")
    }

    @Test func textWinsOverAnAccompanyingImage() throws {
        let made = try #require(ClipboardPayload.make(items: [[
            (PasteboardType.plainText, Data("单元格".utf8)),
            (PasteboardType.png, png)
        ]], maxBytes: 1 << 20))
        #expect(made.kind == .text)
        #expect(made.representations.count == 2, "the image stays, so that pasting restores it")
    }

    @Test func imageOnlyGetsAThumbnailAndItsSize() throws {
        let made = try #require(ClipboardPayload.make(items: [[(PasteboardType.png, png)]], maxBytes: 1 << 20))
        #expect(made.kind == .image)
        #expect(made.preview == "图片 1 × 1")
        #expect(made.thumbnail != nil)
    }

    @Test func emptyOrUnknownIsNothing() {
        #expect(ClipboardPayload.make(items: text("   \n"), maxBytes: 100) == nil)
        #expect(ClipboardPayload.make(items: [[("com.example.private", Data([1]))]], maxBytes: 100) == nil)
        #expect(ClipboardPayload.make(items: [], maxBytes: 100) == nil)
    }

    @Test func tooLargeEssentialFlavorSkipsTheCopy() {
        #expect(ClipboardPayload.make(items: text(String(repeating: "x", count: 200)), maxBytes: 100) == nil)
    }

    @Test func tooLargeSecondaryFlavorIsDroppedAlone() throws {
        let made = try #require(ClipboardPayload.make(items: [[
            (PasteboardType.plainText, Data("hi".utf8)),
            (PasteboardType.html, Data(repeating: 1, count: 500))
        ]], maxBytes: 100))
        #expect(made.representations.map(\.type) == [PasteboardType.plainText])
    }

    @Test func styledCopiesOfTheSameTextShareAnIdentity() throws {
        let plain = payload("相同内容")
        let styled = try #require(ClipboardPayload.make(items: [[
            (PasteboardType.plainText, Data("相同内容".utf8)),
            (PasteboardType.html, Data("<b>相同内容</b>".utf8))
        ]], maxBytes: 1 << 20))
        #expect(plain.hash == styled.hash)
        #expect(plain.hash != payload("不同内容").hash)
    }
}

@Suite struct StoreTests {
    @Test func copyingAgainMovesToTheTopWithoutDuplicating() throws {
        let store = try ClipboardStore(directory: folder())
        let start = Date(timeIntervalSince1970: 1000)
        let first = try #require(store.insert(payload("one"), sourceBundleID: nil, sourceName: nil, now: start))
        store.insert(payload("two"), sourceBundleID: nil, sourceName: nil, now: start.addingTimeInterval(1))
        let again = try #require(store.insert(payload("one"), sourceBundleID: nil, sourceName: "A", now: start.addingTimeInterval(2)))
        #expect(first.isNew)
        #expect(!again.isNew)
        #expect(first.id == again.id)
        #expect(store.count() == 2)
        #expect(store.fetch().map(\.preview) == ["one", "two"])
        #expect(store.fetch().first?.sourceName == "A")
    }

    @Test func searchTreatsWildcardsLiterally() throws {
        let store = try ClipboardStore(directory: folder())
        store.insert(payload("100% 完成"), sourceBundleID: nil, sourceName: nil)
        store.insert(payload("100 完成"), sourceBundleID: nil, sourceName: nil)
        #expect(store.fetch(query: "100%").map(\.preview) == ["100% 完成"])
        #expect(store.fetch(query: "完成").count == 2)
        #expect(store.fetch(query: "不存在").isEmpty)
    }

    @Test func searchCoversTheFullTextNotJustThePreview() throws {
        let store = try ClipboardStore(directory: folder())
        store.insert(payload(String(repeating: "a ", count: 300) + "needle"), sourceBundleID: nil, sourceName: nil)
        #expect(store.fetch(query: "needle").count == 1)
    }

    @Test func filtersSelectByKindAndPinnedComeFirst() throws {
        let store = try ClipboardStore(directory: folder())
        let start = Date(timeIntervalSince1970: 1000)
        let link = try #require(store.insert(payload("https://example.com"), sourceBundleID: nil, sourceName: nil, now: start))
        store.insert(payload("普通文本"), sourceBundleID: nil, sourceName: nil, now: start.addingTimeInterval(1))
        #expect(store.fetch(filter: .link).map(\.kind) == [.link])
        #expect(store.fetch(filter: .text).map(\.kind) == [.text])
        store.setPinned(link.id, true)
        #expect(store.fetch().first?.id == link.id)
        #expect(store.fetch(filter: .pinned).count == 1)
    }

    @Test func sourceTypeAndSearchCanBeCombined() throws {
        let store = try ClipboardStore(directory: folder())
        store.insert(payload("https://example.com/one"), sourceBundleID: "example.editor", sourceName: "Editor")
        store.insert(payload("https://example.com/two"), sourceBundleID: "example.browser", sourceName: "Browser")
        store.insert(payload("example note"), sourceBundleID: "example.editor", sourceName: "Editor")
        #expect(store.sources().map(\.name) == ["Browser", "Editor"])
        #expect(store.fetch(query: "example", filter: .link, source: "example.editor").map(\.preview) == ["https://example.com/one"])
        #expect(store.fetch(query: "two", filter: .link, source: "example.editor").isEmpty)
    }

    @Test func purgeSparesPinnedEntries() throws {
        let store = try ClipboardStore(directory: folder())
        let old = Date(timeIntervalSince1970: 1000)
        let pinned = try #require(store.insert(payload("keep"), sourceBundleID: nil, sourceName: nil, now: old))
        store.setPinned(pinned.id, true)
        store.insert(payload("old"), sourceBundleID: nil, sourceName: nil, now: old)
        store.insert(payload("new"), sourceBundleID: nil, sourceName: nil, now: old.addingTimeInterval(10_000))
        store.purge(maximumItems: 100, maximumAge: 5000, now: old.addingTimeInterval(10_000))
        #expect(Set(store.fetch().map(\.preview)) == ["keep", "new"])
    }

    @Test func purgeEnforcesTheItemLimit() throws {
        let store = try ClipboardStore(directory: folder())
        let start = Date(timeIntervalSince1970: 1000)
        for index in 0..<5 {
            store.insert(payload("n\(index)"), sourceBundleID: nil, sourceName: nil, now: start.addingTimeInterval(Double(index)))
        }
        store.purge(maximumItems: 2, maximumAge: nil, now: start)
        #expect(store.fetch().map(\.preview) == ["n4", "n3"])
    }

    @Test func largeFlavorsLiveInFilesAndAreRemovedWithTheirEntry() throws {
        let directory = folder()
        let store = try ClipboardStore(directory: directory)
        let big = Data(repeating: 7, count: 400 * 1024)
        let made = try #require(ClipboardPayload.make(items: [[
            (PasteboardType.plainText, Data("x".utf8)),
            (PasteboardType.html, big)
        ]], maxBytes: 1 << 22))
        let row = try #require(store.insert(made, sourceBundleID: nil, sourceName: nil))
        let blobs = directory.appendingPathComponent("blobs")
        #expect(try FileManager.default.contentsOfDirectory(atPath: blobs.path).count == 1)
        #expect(store.representations(of: row.id).first { $0.type == PasteboardType.html }?.data == big)
        store.delete(row.id)
        #expect(try FileManager.default.contentsOfDirectory(atPath: blobs.path).isEmpty)
        #expect(store.count() == 0)
    }

    @Test func clearingCanKeepPinnedEntries() throws {
        let store = try ClipboardStore(directory: folder())
        let pinned = try #require(store.insert(payload("keep"), sourceBundleID: nil, sourceName: nil))
        store.setPinned(pinned.id, true)
        store.insert(payload("gone"), sourceBundleID: nil, sourceName: nil)
        store.deleteAll(keepingPinned: true)
        #expect(store.fetch().map(\.preview) == ["keep"])
        store.deleteAll(keepingPinned: false)
        #expect(store.count() == 0)
    }

    @Test func historyIsPrivateToTheUser() throws {
        let directory = folder()
        _ = try ClipboardStore(directory: directory)
        let folderMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("history.sqlite").path)[.posixPermissions] as? Int
        #expect(folderMode == 0o700)
        #expect(fileMode == 0o600)
    }

    @Test func historySurvivesReopening() throws {
        let directory = folder()
        do {
            let store = try ClipboardStore(directory: directory)
            store.insert(payload("persisted"), sourceBundleID: "a.b", sourceName: "App")
        }
        let reopened = try ClipboardStore(directory: directory)
        #expect(reopened.fetch().first?.preview == "persisted")
    }
}

/// Uses an in-memory pasteboard: no pasteboardd permission is needed.
@Suite struct CaptureTests {
    @Test func copyPlainTextStripsFormatsButDoesNotChangeTheStoredOriginal() throws {
        let (pasteboard, store, capture) = try setup()
        let source = NSPasteboardItem()
        source.setString("Hello\tWorld\n1\t2", forType: .string)
        source.setData(Data("{\\rtf1 Hello World}".utf8), forType: NSPasteboard.PasteboardType(PasteboardType.rtf))
        pasteboard.clearContents()
        pasteboard.writeObjects([source])
        capture.pollNow()
        let row = try #require(store.fetch().first)
        let original = store.representations(of: row.id)
        #expect(capture.restorePlainText(row.id))
        let restored = try #require(pasteboard.pasteboardItems?.first)
        #expect(restored.types == [.string])
        #expect(restored.string(forType: .string) == "Hello\tWorld\n1\t2")
        #expect(store.representations(of: row.id) == original)
        capture.pollNow()
        #expect(store.count() == 1)
    }
    private func setup(source: (bundleID: String?, name: String?) = ("com.test.app", "Test")) throws -> (MemoryCapturePasteboard, ClipboardStore, ClipboardCapture) {
        let pasteboard = MemoryCapturePasteboard()
        pasteboard.clearContents()
        let store = try ClipboardStore(directory: folder())
        let capture = ClipboardCapture(pasteboardBackend: pasteboard, store: store, source: { source })
        return (pasteboard, store, capture)
    }

    private func copy(_ string: String, to pasteboard: MemoryCapturePasteboard, extraType: String? = nil) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        if let extraType { item.setData(Data(), forType: NSPasteboard.PasteboardType(extraType)) }
        pasteboard.writeObjects([item])
    }

    @Test func recordsANewCopyWithItsSource() throws {
        let (pasteboard, store, capture) = try setup()
        copy("hello", to: pasteboard)
        capture.pollNow()
        let item = try #require(store.fetch().first)
        #expect(item.text == "hello")
        #expect(item.sourceName == "Test")
    }

    @Test func whatWasThereBeforeStartingIsNotRecorded() throws {
        let pasteboard = MemoryCapturePasteboard()
        copy("old", to: pasteboard)
        let store = try ClipboardStore(directory: folder())
        let capture = ClipboardCapture(pasteboardBackend: pasteboard, store: store, source: { (nil, nil) })
        capture.pollNow()
        #expect(store.count() == 0)
    }

    @Test func nothingHappensWithoutAChange() throws {
        let (pasteboard, store, capture) = try setup()
        copy("once", to: pasteboard)
        capture.pollNow()
        capture.pollNow()
        #expect(store.count() == 1)
    }

    @Test func concealedContentIsNeverRecorded() throws {
        for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            let (pasteboard, store, capture) = try setup()
            copy("secret", to: pasteboard, extraType: type)
            capture.pollNow()
            #expect(store.count() == 0, "\(type) must be respected")
        }
    }

    @Test func blockedAppsAreNotRecorded() throws {
        let (pasteboard, store, capture) = try setup(source: ("com.apple.keychainaccess", "钥匙串"))
        var options = ClipboardCapture.Options()
        options.blockedApps = ["com.apple.keychainaccess"]
        capture.setOptions(options)
        copy("password", to: pasteboard)
        capture.pollNow()
        #expect(store.count() == 0)
    }

    @Test func pausingSkipsCopiesEvenAfterResuming() throws {
        let (pasteboard, store, capture) = try setup()
        var options = ClipboardCapture.Options()
        options.isPaused = true
        capture.setOptions(options)
        copy("while paused", to: pasteboard)
        capture.pollNow()
        options.isPaused = false
        capture.setOptions(options)
        capture.pollNow()
        #expect(store.count() == 0, "what was copied during a pause stays unrecorded")
    }

    @Test func restoringPutsBackEveryFlavorWithoutRecordingAgain() throws {
        let (pasteboard, store, capture) = try setup()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setString("<b>rich</b>", forType: .html)
        pasteboard.writeObjects([item])
        capture.pollNow()
        let row = try #require(store.fetch().first)

        copy("something else", to: pasteboard)
        capture.pollNow()
        #expect(store.count() == 2)

        #expect(capture.restore(row.id))
        #expect(pasteboard.string(forType: .string) == "plain")
        #expect(pasteboard.string(forType: .html) == "<b>rich</b>")
        capture.pollNow()
        #expect(store.count() == 2, "restoring must not create an entry")
        #expect(store.fetch().first?.id == row.id, "using an entry brings it to the top")
    }

    @Test func restoringSomethingGoneFailsCleanly() throws {
        let (_, _, capture) = try setup()
        #expect(!capture.restore(999))
    }
}


private final class MemoryCapturePasteboard: CapturePasteboard {
    private(set) var changeCount = 0
    private(set) var pasteboardItems: [NSPasteboardItem]? = []
    var types: [NSPasteboard.PasteboardType]? { Array(Set((pasteboardItems ?? []).flatMap(\.types))) }
    @discardableResult func clearContents() -> Int {
        changeCount += 1; pasteboardItems = []; return changeCount
    }
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        let items = objects.compactMap { $0 as? NSPasteboardItem }
        guard items.count == objects.count else { return false }
        pasteboardItems = items; changeCount += 1; return true
    }
    func string(forType type: NSPasteboard.PasteboardType) -> String? { pasteboardItems?.first?.string(forType: type) }
}
