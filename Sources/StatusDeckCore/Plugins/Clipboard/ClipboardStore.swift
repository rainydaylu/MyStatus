import Foundation
import SQLite3

/// The clipboard history on disk: one SQLite file, with large flavors as separate
/// files beside it. It only ever lives on this Mac. The folder is private to the
/// user and left out of backups, because a clipboard history is full of things
/// nobody meant to keep. All access goes through one serial queue.
final class ClipboardStore {
    /// Larger flavors go to their own file, which keeps the database quick to read.
    private static let inlineLimit = 256 * 1024
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let queue = DispatchQueue(label: "statusdeck.clipboard.store", qos: .utility)
    private let blobDirectory: URL
    private var database: OpaquePointer?

    init(directory: URL) throws {
        let manager = FileManager.default
        blobDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        try manager.createDirectory(at: blobDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)

        let path = directory.appendingPathComponent("history.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.cannotOpen(path)
        }
        chmod(path, 0o600)
        try execute("PRAGMA journal_mode=WAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hash TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                text TEXT,
                preview TEXT NOT NULL,
                source_bundle TEXT,
                source_name TEXT,
                created_at REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                bytes INTEGER NOT NULL,
                thumbnail BLOB
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS reps(
                item_id INTEGER NOT NULL,
                position INTEGER NOT NULL,
                item_index INTEGER NOT NULL,
                type TEXT NOT NULL,
                data BLOB,
                file TEXT
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS items_order ON items(pinned DESC, created_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS reps_item ON reps(item_id)")
        try execute("CREATE TABLE IF NOT EXISTS tags(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, color TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS item_tags(item_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY(item_id, tag_id))")
        try execute("CREATE INDEX IF NOT EXISTS item_tags_tag ON item_tags(tag_id)")
    }

    deinit {
        sqlite3_close(database)
    }

    enum StoreError: Error {
        case cannotOpen(String)
        case sql(String)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(database)))
        }
    }

    // MARK: - Writing

    /// Copying something already in the history moves it to the top rather than
    /// adding a duplicate. Returns its row and whether the row is new.
    @discardableResult
    func insert(_ payload: ClipboardPayload, sourceBundleID: String?, sourceName: String?, now: Date = Date()) -> (id: Int64, isNew: Bool)? {
        queue.sync {
            if let existing = rowID(forHash: payload.hash) {
                // A duplicate keeps its identity/tags, but must restore the latest
                // copied formats rather than stale plain text from an earlier copy.
                do {
                  try execute("BEGIN IMMEDIATE")
                  let oldFiles = try removeRepresentations(of: existing)
                  for (position, representation) in payload.representations.enumerated() {
                    guard store(representation, of: existing, at: position) else { throw StoreError.sql("Cannot update clipboard formats") }
                  }
                  guard write(
                    "UPDATE items SET created_at=?, source_bundle=?, source_name=?, kind=?, text=?, preview=?, bytes=?, thumbnail=? WHERE id=?",
                    [.double(now.timeIntervalSince1970), .text(sourceBundleID), .text(sourceName), .text(payload.kind.rawValue),
                     .text(payload.text), .text(payload.preview), .int(Int64(payload.byteCount)), .blob(payload.thumbnail), .int(existing)]
                  ) else { throw StoreError.sql("Cannot update clipboard record") }
                  try execute("COMMIT")
                  for name in oldFiles { try? FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(name)) }
                  return (existing, false)
                } catch {
                  try? execute("ROLLBACK")
                  return nil
                }
            }
            guard let statement = prepare("""
                INSERT INTO items(hash, kind, text, preview, source_bundle, source_name, created_at, bytes, thumbnail)
                VALUES(?,?,?,?,?,?,?,?,?)
                """) else { return nil }
            defer { sqlite3_finalize(statement) }
            bind(statement, [
                .text(payload.hash), .text(payload.kind.rawValue), .text(payload.text), .text(payload.preview),
                .text(sourceBundleID), .text(sourceName), .double(now.timeIntervalSince1970),
                .int(Int64(payload.byteCount)), .blob(payload.thumbnail)
            ])
            guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
            let id = sqlite3_last_insert_rowid(database)
            for (position, representation) in payload.representations.enumerated() {
                store(representation, of: id, at: position)
            }
            return (id, true)
        }
    }

    private func removeRepresentations(of id: Int64) throws -> [String] {
        var files: [String] = []
        if let statement = prepare("SELECT file FROM reps WHERE item_id=? AND file IS NOT NULL") {
            bind(statement, [.int(id)])
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = text(statement, 0) { files.append(name) }
            }
            sqlite3_finalize(statement)
        }
        guard write("DELETE FROM reps WHERE item_id=?", [.int(id)]) else { throw StoreError.sql("Cannot replace clipboard formats") }
        return files
    }

    @discardableResult private func store(_ representation: ClipRepresentation, of id: Int64, at position: Int) -> Bool {
        var inline: Data? = representation.data
        var fileName: String?
        if representation.data.count > Self.inlineLimit {
            let name = UUID().uuidString
            let url = blobDirectory.appendingPathComponent(name)
            if (try? representation.data.write(to: url, options: [.atomic])) != nil {
                chmod(url.path, 0o600)
                inline = nil
                fileName = name
            }
        }
        return write(
            "INSERT INTO reps(item_id, position, item_index, type, data, file) VALUES(?,?,?,?,?,?)",
            [.int(id), .int(Int64(position)), .int(Int64(representation.itemIndex)), .text(representation.type), .blob(inline), .text(fileName)]
        )
    }

    func setPinned(_ id: Int64, _ isPinned: Bool) {
        queue.sync { update("UPDATE items SET pinned=? WHERE id=?", [.int(isPinned ? 1 : 0), .int(id)]) }
    }

    /// Using an entry brings it back to the top.
    func touch(_ id: Int64, now: Date = Date()) {
        queue.sync { update("UPDATE items SET created_at=? WHERE id=?", [.double(now.timeIntervalSince1970), .int(id)]) }
    }

    func delete(_ id: Int64) {
        queue.sync { deleteRows(where: "id=?", [.int(id)]) }
    }

    func deleteAll(keepingPinned: Bool) {
        queue.sync { deleteRows(where: keepingPinned ? "pinned=0" : "1=1", []) }
    }

    /// Applies the retention settings. Pinned entries are exempt from both limits.
    func purge(maximumItems: Int, maximumAge: TimeInterval?, now: Date = Date()) {
        queue.sync {
            if let maximumAge {
                deleteRows(where: "pinned=0 AND created_at<?", [.double(now.timeIntervalSince1970 - maximumAge)])
            }
            deleteRows(
                where: "pinned=0 AND id NOT IN (SELECT id FROM items WHERE pinned=0 ORDER BY created_at DESC LIMIT ?)",
                [.int(Int64(maximumItems))]
            )
        }
    }

    private func deleteRows(where condition: String, _ values: [Value]) {
        // Blob files first: the rows are what says which files there are.
        let selection = "SELECT file FROM reps WHERE file IS NOT NULL AND item_id IN (SELECT id FROM items WHERE \(condition))"
        if let statement = prepare(selection) {
            bind(statement, values)
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 0) {
                    try? FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(String(cString: name)))
                }
            }
            sqlite3_finalize(statement)
        }
        update("DELETE FROM reps WHERE item_id IN (SELECT id FROM items WHERE \(condition))", values)
        update("DELETE FROM item_tags WHERE item_id IN (SELECT id FROM items WHERE \(condition))", values)
        update("DELETE FROM items WHERE \(condition)", values)
    }

    // MARK: - Reading

    func fetch(query: String = "", filter: ClipFilter = .all, source: String? = nil, tagID: Int64? = nil, limit: Int = 200) -> [ClipboardItem] {
        queue.sync {
            var clauses: [String] = []
            var values: [Value] = []
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let escaped = trimmed
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                clauses.append("(preview LIKE ? ESCAPE '\\' OR text LIKE ? ESCAPE '\\' OR source_name LIKE ? ESCAPE '\\')")
                let pattern = "%\(escaped)%"
                values += [.text(pattern), .text(pattern), .text(pattern)]
            }
            if let source {
                clauses.append("source_bundle=?")
                values.append(.text(source))
            }
            if filter == .pinned { clauses.append("pinned=1") }
            if let tagID {
                clauses.append("id IN (SELECT item_id FROM item_tags WHERE tag_id=?)")
                values.append(.int(tagID))
            }
            if filter == .richText {
                clauses.append("(kind='richText' OR EXISTS(SELECT 1 FROM reps WHERE item_id=items.id AND type IN ('public.rtf','public.html','com.apple.flat-rtfd')))")
            } else if filter == .table {
                clauses.append("(kind='table' OR (instr(text,char(9))>0 AND instr(text,char(10))>0))")
            } else if let kinds = filter.kinds {
                clauses.append("kind IN (\(kinds.map { _ in "?" }.joined(separator: ",")))")
                values += kinds.map { .text($0.rawValue) }
            }
            let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = """
                SELECT id, kind, text, preview, source_bundle, source_name, created_at, pinned, bytes, thumbnail,
                       (SELECT group_concat(tag_id) FROM item_tags WHERE item_id=items.id),
                       EXISTS(SELECT 1 FROM reps WHERE item_id=items.id AND type='public.rtf')
                FROM items \(whereClause) ORDER BY pinned DESC, created_at DESC LIMIT ?
                """
            values.append(.int(Int64(limit)))
            guard let statement = prepare(sql) else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(statement, values)

            var items: [ClipboardItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                items.append(ClipboardItem(
                    id: sqlite3_column_int64(statement, 0),
                    kind: ClipKind(rawValue: text(statement, 1) ?? "") ?? .text,
                    text: text(statement, 2),
                    preview: text(statement, 3) ?? "",
                    sourceBundleID: text(statement, 4),
                    sourceName: text(statement, 5),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    isPinned: sqlite3_column_int(statement, 7) != 0,
                    byteCount: Int(sqlite3_column_int64(statement, 8)),
                    thumbnail: blob(statement, 9),
                    tagIDs: (text(statement, 10) ?? "").split(separator: ",").compactMap { Int64($0) },
                    hasRichText: sqlite3_column_int(statement, 11) != 0
                ))
            }
            return items
        }
    }

    func tags() -> [ClipboardTag] {
        queue.sync {
            guard let statement = prepare("SELECT id, name, color FROM tags ORDER BY id") else { return [] }
            defer { sqlite3_finalize(statement) }
            var result: [ClipboardTag] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(ClipboardTag(id: sqlite3_column_int64(statement, 0), name: text(statement, 1) ?? "",
                                           color: ClipboardTagColor(rawValue: text(statement, 2) ?? "") ?? .blue))
            }
            return result
        }
    }

    func addTag(name: String, color: ClipboardTagColor) -> Int64? {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return nil }
        return queue.sync {
            update("INSERT OR IGNORE INTO tags(name,color) VALUES(?,?)", [.text(name), .text(color.rawValue)])
            guard let statement = prepare("SELECT id FROM tags WHERE name=? COLLATE NOCASE") else { return nil }
            defer { sqlite3_finalize(statement) }
            bind(statement, [.text(name)])
            return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil
        }
    }

    func setTag(_ tagID: Int64, for itemID: Int64, included: Bool) {
        queue.sync {
            if included {
                update("INSERT OR IGNORE INTO item_tags(item_id,tag_id) SELECT ?,? WHERE EXISTS(SELECT 1 FROM items WHERE id=?) AND EXISTS(SELECT 1 FROM tags WHERE id=?)",
                       [.int(itemID), .int(tagID), .int(itemID), .int(tagID)])
            } else {
                update("DELETE FROM item_tags WHERE item_id=? AND tag_id=?", [.int(itemID), .int(tagID)])
            }
        }
    }

    func deleteTag(_ id: Int64) {
        queue.sync {
            update("DELETE FROM item_tags WHERE tag_id=?", [.int(id)])
            update("DELETE FROM tags WHERE id=?", [.int(id)])
        }
    }

    func sources() -> [ClipboardSource] {
        queue.sync {
            guard let statement = prepare("SELECT source_bundle, COALESCE(MAX(source_name),source_bundle) FROM items WHERE source_bundle IS NOT NULL GROUP BY source_bundle ORDER BY 2 COLLATE NOCASE") else { return [] }
            defer { sqlite3_finalize(statement) }
            var result: [ClipboardSource] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let id = text(statement, 0), let name = text(statement, 1) {
                    result.append(ClipboardSource(id: id, name: name))
                }
            }
            return result
        }
    }

    func firstItemTypes(of id: Int64) -> [String] {
        queue.sync {
            guard let statement = prepare("SELECT DISTINCT type FROM reps WHERE item_id=? AND item_index=0") else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(statement, [.int(id)])
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let type = text(statement, 0) { result.append(type) }
            }
            return result
        }
    }

    func count() -> Int {
        queue.sync {
            guard let statement = prepare("SELECT COUNT(*) FROM items") else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    func totalBytes() -> Int {
        queue.sync {
            guard let statement = prepare("SELECT COALESCE(SUM(bytes),0) FROM items") else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    /// Every stored flavor, in the order it came, for putting back on the pasteboard.
    func representations(of id: Int64) -> [ClipRepresentation] {
        queue.sync {
            guard let statement = prepare("SELECT item_index, type, data, file FROM reps WHERE item_id=? ORDER BY position") else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(statement, [.int(id)])
            var representations: [ClipRepresentation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let data: Data?
                if let name = text(statement, 3) {
                    data = try? Data(contentsOf: blobDirectory.appendingPathComponent(name))
                } else {
                    data = blob(statement, 2) ?? Data()
                }
                if let data, let type = text(statement, 1) {
                    representations.append(ClipRepresentation(itemIndex: Int(sqlite3_column_int(statement, 0)), type: type, data: data))
                }
            }
            return representations
        }
    }

    // MARK: - SQLite plumbing

    private enum Value {
        case int(Int64)
        case double(Double)
        case text(String?)
        case blob(Data?)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        return sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK ? statement : nil
    }

    private func bind(_ statement: OpaquePointer, _ values: [Value]) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let .int(number):
                sqlite3_bind_int64(statement, index, number)
            case let .double(number):
                sqlite3_bind_double(statement, index, number)
            case let .text(string):
                if let string {
                    sqlite3_bind_text(statement, index, string, -1, Self.transient)
                } else {
                    sqlite3_bind_null(statement, index)
                }
            case let .blob(data):
                if let data {
                    // An empty Data has no base address, and SQLite reads a null pointer as NULL.
                    if data.isEmpty {
                        sqlite3_bind_zeroblob(statement, index, 0)
                    } else {
                        data.withUnsafeBytes { buffer in
                            _ = sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                        }
                    }
                } else {
                    sqlite3_bind_null(statement, index)
                }
            }
        }
    }

    private func update(_ sql: String, _ values: [Value]) {
        _ = write(sql, values)
    }

    private func write(_ sql: String, _ values: [Value]) -> Bool {
        guard let statement = prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(statement, values)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func rowID(forHash hash: String) -> Int64? {
        guard let statement = prepare("SELECT id FROM items WHERE hash=?") else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(statement, [.text(hash)])
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
