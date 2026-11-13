import AppKit
import Foundation
import ImageIO
import StatusDeckKit
import UniformTypeIdentifiers

struct ClipboardImageInfo {
    let width: Int
    let height: Int
    let colorSpace: String
    let format: String
    let byteCount: Int
}

struct ClipboardColorInfo {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    var rgb: String { [red, green, blue].map { String(Int(($0 * 255).rounded())) }.joined(separator: ", ") }
    var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    private var hue: Double {
        let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
        guard delta > 0 else { return 0 }
        let value = high == red ? (green - blue) / delta : high == green ? (blue - red) / delta + 2 : (red - green) / delta + 4
        return (value * 60 + 360).truncatingRemainder(dividingBy: 360)
    }
    var hsb: String {
        let high = max(red, green, blue), low = min(red, green, blue)
        return String(format: "%.0f°, %.0f%%, %.0f%%", hue, high > 0 ? (high - low) / high * 100 : 0, high * 100)
    }
    var hsl: String {
        let high = max(red, green, blue), low = min(red, green, blue), light = (high + low) / 2
        let saturation = high == low ? 0 : (high - low) / (1 - abs(2 * light - 1))
        return String(format: "%.0f°, %.0f%%, %.0f%%", hue, saturation * 100, light * 100)
    }
    var cmyk: String {
        let black = 1 - max(red, green, blue)
        let values = black == 1 ? [0, 0, 0, 1] : [(1 - red - black) / (1 - black), (1 - green - black) / (1 - black), (1 - blue - black) / (1 - black), black]
        return values.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: ", ")
    }
}

struct ClipboardPreviewDocument {
    enum Content {
        case text(String, code: Bool)
        case richText(NSAttributedString)
        case html(String)
        case table(ClipboardTable)
        case image(NSImage, ClipboardImageInfo)
        case color(ClipboardColorInfo)
        case files([URL])
        case link(URL, String)
    }
    let item: ClipboardItem
    let content: Content
    let format: String
    let sourceURL: URL?
    var isTruncated = false

    static func make(item: ClipboardItem, representations: [ClipRepresentation]) -> ClipboardPreviewDocument {
        let sourceURL = sourceURL(in: representations)
        func document(_ content: Content, _ format: String, truncated: Bool = false) -> ClipboardPreviewDocument {
            ClipboardPreviewDocument(item: item, content: content, format: format, sourceURL: sourceURL, isTruncated: truncated)
        }
        let first = representations.filter { $0.itemIndex == 0 }
        if item.kind == .file, let text = item.text {
            let files = text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            return document(.files(files), DeckL("文件"))
        }
        if item.kind == .image {
            for type in PasteboardType.images {
                guard let representation = first.first(where: { $0.type == type }),
                      let source = CGImageSourceCreateWithData(representation.data as CFData, nil) else { continue }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let format = (CGImageSourceGetType(source) as String?).flatMap { UTType($0)?.preferredFilenameExtension }?.uppercased() ?? DeckL("图片")
                let info = ClipboardImageInfo(width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
                                              height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
                                              colorSpace: properties[kCGImagePropertyProfileName] as? String ?? properties[kCGImagePropertyColorModel] as? String ?? "--",
                                              format: format, byteCount: representation.data.count)
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true]
                if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    return document(.image(NSImage(cgImage: image, size: .zero), info), format)
                }
            }
            if let data = item.thumbnail, let image = NSImage(data: data) {
                return document(.image(image, ClipboardImageInfo(width: Int(image.size.width), height: Int(image.size.height), colorSpace: "--", format: DeckL("缩略图", "Thumbnail"), byteCount: data.count)), DeckL("图片"))
            }
        }
        if let value = ClipboardClassifier.color(from: item.text ?? ""), item.kind == .color {
            return document(.color(ClipboardColorInfo(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)), DeckL("颜色"))
        }
        if item.kind == .link, let text = item.text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return document(.link(url, text), DeckL("链接"))
        }
        let html = first.first { $0.type == PasteboardType.html }.flatMap { ClipboardText.decode($0.data) }
        if let html, let table = ClipboardTable.html(html) { return document(.table(table), "HTML " + DeckL("表格", "table"), truncated: table.isTruncated) }
        if let text = item.text, let table = ClipboardTable.detect(text: text,
            explicitCSV: first.contains { $0.type == "public.comma-separated-values-text" },
            explicitTSV: first.contains { $0.type == "public.tab-separated-values-text" }) {
            return document(.table(table), DeckL("表格", "Table"), truncated: table.isTruncated)
        }
        for representation in first where [PasteboardType.rtf, "com.apple.flat-rtfd"].contains(representation.type) && representation.data.count <= 8 * 1024 * 1024 {
            if let rich = ClipboardText.attributed(representation) {
                if let table = ClipboardTable.richText(rich) { return document(.table(table), "RTF " + DeckL("表格", "table"), truncated: table.isTruncated) }
                return document(.richText(rich), representation.type == PasteboardType.rtf ? "RTF" : "RTFD")
            }
        }
        if let html, html.utf8.count <= 4 * 1024 * 1024 { return document(.html(html), "HTML") }
        let text = item.text ?? item.displayPreview
        if text.trimmingCharacters(in: .whitespacesAndNewlines).first.map({ $0 == "{" || $0 == "[" }) == true,
           let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) { return document(.text(String(json.prefix(500_000)), code: true), "JSON", truncated: json.count > 500_000) }
        return document(.text(String(text.prefix(500_000)), code: item.kind == .code), item.kind == .code ? DeckL("代码") : DeckL("文本"), truncated: text.count > 500_000)
    }

    static func sourceURL(in representations: [ClipRepresentation]) -> URL? {
        for representation in representations where ["org.chromium.source-url", "public.url", PasteboardType.html].contains(representation.type) {
            guard let text = ClipboardText.decode(representation.data) else { continue }
            let candidate: String
            if representation.type == PasteboardType.html {
                guard let range = text.range(of: "(?m)^SourceURL:[^\\r\\n]+", options: .regularExpression) else { continue }
                candidate = String(text[range].dropFirst("SourceURL:".count))
            } else { candidate = text }
            if let url = URL(string: candidate.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        }
        return nil
    }
}

@MainActor
final class ClipboardDetailModel: ObservableObject {
    @Published var document: ClipboardPreviewDocument?
    @Published var isLoading = false
}

enum ClipboardPreviewLayout {
    static func frame(beside shelf: CGRect, visible: CGRect, preferredHeight: CGFloat = 650) -> CGRect {
        let gap: CGFloat = 8, margin: CGFloat = 8
        let left = shelf.minX - visible.minX - gap - margin
        let right = visible.maxX - shelf.maxX - gap - margin
        let available = max(left, right)
        // Scale both dimensions equally: the resulting area is 70% of the old
        // preview, including when its original size was constrained by a screen.
        let scale: CGFloat = sqrt(0.70)
        let width = min(560, max(280, available), visible.width - margin * 2) * scale
        let height = min(preferredHeight, visible.height - margin * 2) * scale
        let x: CGFloat
        if available >= width { x = left >= right ? shelf.minX - gap - width : shelf.maxX + gap }
        else { x = visible.minX + margin }
        return CGRect(x: min(max(visible.minX + margin, x), visible.maxX - width - margin),
                      y: min(max(visible.minY + margin, shelf.maxY - height), visible.maxY - height - margin), width: width, height: height)
    }
}
