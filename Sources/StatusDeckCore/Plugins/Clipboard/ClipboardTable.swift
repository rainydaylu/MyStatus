import AppKit
import Foundation

struct ClipboardTable: Equatable {
    static let rowLimit = 500
    static let columnLimit = 80
    var rows: [[String]]
    var headerRows: Set<Int> = []
    var isTruncated = false
    var columnCount: Int { rows.map(\.count).max() ?? 0 }

    static func parse(text: String, delimiter: Character) -> ClipboardTable? {
        guard text.utf8.count <= 4 * 1024 * 1024 else { return nil }
        let characters = Array(text)
        var rows: [[String]] = [], row: [String] = [], cell = ""
        var quoted = false, index = 0, truncated = false
        func finishCell() {
            if row.count < columnLimit { row.append(String(cell.prefix(10_000))) } else { truncated = true }
            cell = ""
        }
        func finishRow() {
            finishCell()
            if rows.count < rowLimit { rows.append(row) } else { truncated = true }
            row = []
        }
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    cell.append("\""); index += 1
                } else if quoted || cell.isEmpty { quoted.toggle() }
                else { cell.append(character) }
            } else if !quoted && character == delimiter {
                finishCell()
            } else if !quoted && (character == "\n" || character == "\r" || character == "\r\n") {
                finishRow()
                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
                if rows.count == rowLimit && index + 1 < characters.count { truncated = true; break }
            } else { cell.append(character) }
            index += 1
        }
        guard !quoted else { return nil }
        if !cell.isEmpty || !row.isEmpty { finishRow() }
        guard !rows.isEmpty, (rows.map(\.count).max() ?? 0) > 1 else { return nil }
        return ClipboardTable(rows: rows, isTruncated: truncated)
    }

    static func detect(text: String, explicitCSV: Bool = false, explicitTSV: Bool = false) -> ClipboardTable? {
        if text.contains("\t"), let table = parse(text: text, delimiter: "\t"),
           explicitTSV || (table.rows.count > 1 && !ClipboardClassifier.looksLikeCode(text)) { return table }
        if explicitCSV || (text.contains(",") && text.contains("\n") && !ClipboardClassifier.looksLikeCode(text)) {
            if let table = parse(text: text, delimiter: ","),
               explicitCSV || (table.rows.count > 1 && Set(table.rows.map(\.count)).count == 1) { return table }
        }
        return nil
    }

    static func html(_ html: String) -> ClipboardTable? {
        guard html.utf8.count <= 4 * 1024 * 1024,
              let tableRange = html.range(of: "<table\\b[^>]*>[\\s\\S]*?</table\\s*>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tableHTML = String(html[tableRange])
        let regex = try! NSRegularExpression(pattern: "<tr\\b[^>]*>([\\s\\S]*?)</tr\\s*>", options: .caseInsensitive)
        let cells = try! NSRegularExpression(pattern: "<(td|th)\\b([^>]*)>([\\s\\S]*?)</(?:td|th)\\s*>", options: .caseInsensitive)
        let source = tableHTML as NSString
        let matches = regex.matches(in: tableHTML, range: NSRange(location: 0, length: source.length))
        var grid: [Int: [Int: String]] = [:], headers: Set<Int> = [], truncated = matches.count > rowLimit
        for (rowIndex, rowMatch) in matches.prefix(rowLimit).enumerated() {
            let rowHTML = source.substring(with: rowMatch.range(at: 1))
            let rowSource = rowHTML as NSString
            var column = 0
            for match in cells.matches(in: rowHTML, range: NSRange(location: 0, length: rowSource.length)) {
                while grid[rowIndex]?[column] != nil { column += 1 }
                guard column < columnLimit else { truncated = true; break }
                let attributes = rowSource.substring(with: match.range(at: 2))
                let width = span("colspan", in: attributes, limit: columnLimit)
                let height = span("rowspan", in: attributes, limit: rowLimit)
                if rowSource.substring(with: match.range(at: 1)).lowercased() == "th" { headers.insert(rowIndex) }
                for r in rowIndex..<min(rowLimit, rowIndex + height) {
                    for c in column..<min(columnLimit, column + width) { grid[r, default: [:]][c] = "" }
                }
                grid[rowIndex, default: [:]][column] = String(ClipboardText.htmlText(rowSource.substring(with: match.range(at: 3))).prefix(10_000))
                column += width
            }
        }
        guard let lastRow = grid.keys.max(), let lastColumn = grid.values.flatMap(\.keys).max() else { return nil }
        let rows = (0...lastRow).map { r in (0...lastColumn).map { c in grid[r]?[c] ?? "" } }
        return ClipboardTable(rows: rows, headerRows: headers, isTruncated: truncated)
    }

    private static func span(_ key: String, in text: String, limit: Int) -> Int {
        guard let range = text.range(of: "\\b\(key)\\s*=\\s*[\"']?[0-9]+", options: [.regularExpression, .caseInsensitive]) else { return 1 }
        let digits = text[range].filter(\.isNumber)
        return min(limit, max(1, Int(digits) ?? 1))
    }

    static func richText(_ text: NSAttributedString) -> ClipboardTable? {
        var grid: [Int: [Int: String]] = [:]
        var firstTable: NSTextTable?
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first(where: { $0 is NSTextTableBlock }) as? NSTextTableBlock,
                  block.startingRow >= 0, block.startingColumn >= 0,
                  block.startingRow < rowLimit, block.startingColumn < columnLimit else { return }
            if firstTable == nil { firstTable = block.table }
            guard block.table === firstTable else { return }
            let r = block.startingRow, c = block.startingColumn
            let cell = text.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines)
            for row in r..<min(rowLimit, r + max(1, block.rowSpan)) {
                for column in c..<min(columnLimit, c + max(1, block.columnSpan)) {
                    if grid[row]?[column] == nil { grid[row, default: [:]][column] = "" }
                }
            }
            let existing = grid[r]?[c] ?? ""
            grid[r, default: [:]][c] = existing.isEmpty ? cell : existing + "\n" + cell
        }
        guard let lastRow = grid.keys.max(), let lastColumn = grid.values.flatMap(\.keys).max() else { return nil }
        return ClipboardTable(rows: (0...lastRow).map { r in (0...lastColumn).map { c in grid[r]?[c] ?? "" } })
    }
}

enum ClipboardText {
    static let types = [PasteboardType.plainText, "public.utf16-plain-text", "public.utf16-external-plain-text", "NSStringPboardType",
                        "public.tab-separated-values-text", "public.comma-separated-values-text"]
    static let richTypes = [PasteboardType.rtf, "com.apple.flat-rtfd", PasteboardType.html]

    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    static func htmlText(_ html: String) -> String {
        var value = html.replacingOccurrences(of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "<br\\s*/?>|</(?:p|div|tr|li|h[1-6])\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "</(?:td|th)\\s*>", with: "\t", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, replacement) in entities { value = value.replacingOccurrences(of: entity, with: replacement) }
        let regex = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        let original = value as NSString
        for match in regex.matches(in: value, range: NSRange(location: 0, length: original.length)).reversed() {
            let digits = original.substring(with: match.range(at: 1))
            let number = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: value) { value.replaceSubrange(range, with: String(scalar)) }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attributed(_ representation: ClipRepresentation) -> NSAttributedString? {
        let type: NSAttributedString.DocumentType = representation.type == "com.apple.flat-rtfd" ? .rtfd : .rtf
        return try? NSAttributedString(data: representation.data, options: [.documentType: type], documentAttributes: nil)
    }
}
