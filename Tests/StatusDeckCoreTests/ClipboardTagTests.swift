import Foundation
import SQLite3
import Testing
@testable import StatusDeckCore

@Suite struct ClipboardTagTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mystatus-tags-\(UUID())")
    }

    private func payload(_ value: String) throws -> ClipboardPayload {
        try #require(ClipboardPayload.make(items: [[(PasteboardType.plainText, Data(value.utf8))]], maxBytes: 4096))
    }

    @Test func tagsSurviveRestartAndRemovingATagKeepsTheOriginalHistory() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var tagID: Int64 = 0
        var itemID: Int64 = 0
        do {
            let store = try ClipboardStore(directory: directory)
            itemID = try #require(store.insert(try payload("Project notes"), sourceBundleID: "example.notes", sourceName: "Notes")).id
            tagID = try #require(store.addTag(name: "  Research  ", color: .red))
            #expect(store.addTag(name: "research", color: .green) == tagID)
            store.setTag(tagID, for: itemID, included: true)
            #expect(store.fetch(query: "Project", source: "example.notes", tagID: tagID).first?.id == itemID)
            #expect(store.fetch(query: "missing", tagID: tagID).isEmpty)
        }
        let restored = try ClipboardStore(directory: directory)
        #expect(restored.tags() == [ClipboardTag(id: tagID, name: "Research", color: .red)])
        #expect(restored.fetch().first?.tagIDs == [tagID])
        restored.deleteTag(tagID)
        #expect(restored.tags().isEmpty)
        #expect(restored.fetch().first?.id == itemID)
        #expect(restored.fetch().first?.tagIDs.isEmpty == true)
    }

    @Test func oldHistoryMigratesWithoutChangingContentOrPinnedState() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try ClipboardStore(directory: directory)
            let id = try #require(store.insert(try payload("Keep this original"), sourceBundleID: nil, sourceName: nil)).id
            store.setPinned(id, true)
        }
        var db: OpaquePointer?
        #expect(sqlite3_open(directory.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "DROP TABLE item_tags; DROP TABLE tags;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let migrated = try ClipboardStore(directory: directory)
        let item = try #require(migrated.fetch().first)
        #expect(item.text == "Keep this original")
        #expect(item.isPinned)
        #expect(item.tagIDs.isEmpty)
        #expect(migrated.addTag(name: "Work", color: .blue) != nil)
    }

    @Test func formatMetadataAndMembershipsFollowTheStoredRepresentations() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directory: directory)
        let payload = try #require(ClipboardPayload.make(items: [[
            (PasteboardType.plainText, Data("Formatted note".utf8)),
            (PasteboardType.rtf, Data("{\\rtf1 Formatted note}".utf8))
        ]], maxBytes: 4096))
        let id = try #require(store.insert(payload, sourceBundleID: nil, sourceName: nil)).id
        let tag = try #require(store.addTag(name: "Work", color: .green))
        store.setTag(tag, for: id, included: true)
        #expect(store.fetch().first?.hasRichText == true)
        store.delete(id)
        #expect(store.fetch(tagID: tag).isEmpty)
        #expect(store.tags().count == 1)
        #expect(store.addTag(name: "   ", color: .red) == nil)
    }
}
