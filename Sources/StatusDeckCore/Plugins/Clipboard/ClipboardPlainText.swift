import Foundation

enum ClipboardPlainText {
    static func from(_ representations: [ClipRepresentation]) -> String? {
        let groups = Dictionary(grouping: representations, by: \.itemIndex)
        let strings = groups.keys.sorted().compactMap { index -> String? in
            let formats = groups[index] ?? []
            for type in ClipboardText.types {
                if let data = formats.first(where: { $0.type == type })?.data,
                   let text = ClipboardText.decode(data), !text.isEmpty { return text }
            }
            for representation in formats where [PasteboardType.rtf, "com.apple.flat-rtfd"].contains(representation.type) {
                if let text = ClipboardText.attributed(representation)?.string, !text.isEmpty { return text }
            }
            if let data = formats.first(where: { $0.type == PasteboardType.html })?.data,
               let html = ClipboardText.decode(data) { return ClipboardText.htmlText(html) }
            if let data = formats.first(where: { $0.type == PasteboardType.fileURL })?.data,
               let value = String(data: data, encoding: .utf8), let url = URL(string: value), url.isFileURL { return url.path }
            return nil
        }
        return strings.isEmpty ? nil : strings.joined(separator: "\n")
    }
}
