import AppKit
import QuickLookUI
import StatusDeckKit
import SwiftUI
import WebKit

struct ClipboardDetailView: View {
    @ObservedObject var model: ClipboardDetailModel
    let onClose: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ClipboardCloseButton(label: DeckL("收起详情", "Collapse details"), action: onClose)
                Text(model.document?.format ?? DeckL("预览", "Preview")).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            if let document = model.document {
                content(document).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                metadata(document).padding(14)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(theme.primary)
        .background(MenuPanelSurface(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(4)
    }

    @ViewBuilder private func content(_ document: ClipboardPreviewDocument) -> some View {
        switch document.content {
        case .table(let table):
            ClipboardTableView(table: table)
        case .richText(let text):
            ClipboardRichTextView(text: text)
        case .html(let html):
            ClipboardHTMLView(html: html)
        case .image(let image, _):
            ClipboardImageView(image: image)
        case .color(let color):
            VStack(spacing: 20) {
                Circle().fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .frame(width: 130, height: 130).overlay(Circle().strokeBorder(.white.opacity(0.6)))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                Text(color.hex).font(.system(size: 20, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            }
        case .files(let files):
            ClipboardFileView(files: files)
        case .link(let url, let text):
            VStack(alignment: .leading, spacing: 16) {
                Label(url.host ?? url.scheme ?? DeckL("链接"), systemImage: "link").font(.title3.weight(.medium))
                ScrollView { Text(text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button(DeckL("在浏览器中打开", "Open in browser")) { NSWorkspace.shared.open(url) }
            }.padding(16)
        case .text(let text, let code):
            ClipboardRichTextView(text: NSAttributedString(string: text, attributes: [
                .font: code ? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular) : NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ]), usesSystemBackground: true)
        }
    }

    private func metadata(_ document: ClipboardPreviewDocument) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            switch document.content {
            case .image(_, let info):
                infoRow(DeckL("尺寸", "Dimensions"), "\(info.width) × \(info.height)")
                infoRow(DeckL("色彩空间", "Color space"), info.colorSpace)
                infoRow(DeckL("大小"), Format.bytes(UInt64(info.byteCount)))
            case .table(let table):
                infoRow(DeckL("表格", "Table"), DeckLF("%1$@ 行 × %2$@ 列", "%1$@ rows × %2$@ columns", String(table.rows.count), String(table.columnCount)))
            case .color(let color):
                infoRow("RGB", color.rgb)
                infoRow("HSL", color.hsl)
                infoRow("HSB", color.hsb)
                infoRow("CMYK", color.cmyk)
                if color.alpha < 1 { infoRow(DeckL("不透明度", "Opacity"), String(format: "%.0f%%", color.alpha * 100)) }
            case .files(let files):
                infoRow(DeckL("文件数", "Files"), String(files.count))
                if files.count == 1, let url = files.first,
                   let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]) {
                    if let type = values.contentType?.localizedDescription { infoRow(DeckL("类型", "Type"), type) }
                    if let size = values.fileSize { infoRow(DeckL("大小"), Format.bytes(UInt64(max(0, size)))) }
                }
            default:
                infoRow(DeckL("大小"), Format.bytes(UInt64(document.item.byteCount)))
            }
            if document.isTruncated {
                Text(DeckL("已限制预览范围，复制仍保留完整的原始内容。", "Preview is limited; copying retains the complete original content."))
                    .font(.caption).foregroundStyle(theme.secondary)
            }
            Divider()
            HStack(spacing: 6) {
                Text(DeckL("来源应用", "Source app")).foregroundStyle(theme.secondary)
                if let id = document.item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: DeckAppIcon.image(forPath: url.path)).resizable().frame(width: 16, height: 16)
                }
                Text(document.item.sourceName ?? DeckL("未知"))
            }
            if let url = document.sourceURL {
                HStack(spacing: 6) {
                    Text(DeckL("来源 URL", "Source URL")).foregroundStyle(theme.secondary)
                    Text(url.absoluteString).lineLimit(1).truncationMode(.middle).help(url.absoluteString)
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help(DeckL("复制来源 URL", "Copy source URL"))
                }
            }
            HStack {
                Text(DeckL("创建时间", "Created")).foregroundStyle(theme.secondary)
                Text(document.item.createdAt, format: .dateTime.year().month().day().hour().minute().second()).textSelection(.enabled)
            }
        }
        .font(.system(size: 11.5))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).foregroundStyle(theme.secondary).frame(width: 66, alignment: .leading)
            Text(value).monospacedDigit().textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ClipboardImageView: View {
    let image: NSImage
    @State private var actualSize = false
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Spacer()
                Button(actualSize ? DeckL("适合窗口", "Fit to window") : DeckL("放大查看", "Zoom in")) { actualSize.toggle() }.buttonStyle(.plain)
            }.font(.caption).padding(.horizontal, 8)
            if actualSize {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().frame(width: image.size.width, height: image.size.height)
                }
            } else {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ClipboardTableView: View {
    let table: ClipboardTable
    @Environment(\.deckTheme) private var theme
    private let width: CGFloat = 132
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    cell("", width: 34, height: 28, header: true)
                    ForEach(0..<table.columnCount, id: \.self) { column in
                        cell(Self.columnName(column), width: width, height: 28, header: true)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    let height = rowHeight(table.rows[row])
                    HStack(spacing: 0) {
                        cell(String(row + 1), width: 34, height: height, header: true)
                        ForEach(0..<table.columnCount, id: \.self) { column in
                            cell(table.rows[row].indices.contains(column) ? table.rows[row][column] : "",
                                 width: width, height: height, header: table.headerRows.contains(row))
                        }
                    }
                    .background(row.isMultiple(of: 2) ? theme.inset.opacity(0.5) : Color.clear)
                }
            }.frame(width: 34 + CGFloat(table.columnCount) * width, alignment: .leading)
        }
        .background(theme.cardTop)
        .accessibilityLabel(DeckL("表格预览，可横向和纵向滚动", "Table preview, scroll horizontally and vertically"))
    }
    private func cell(_ value: String, width: CGFloat, height: CGFloat, header: Bool) -> some View {
        Text(value).font(.system(size: 12, weight: header ? .semibold : .regular))
            .lineLimit(5).textSelection(.enabled)
            .padding(.horizontal, 7).frame(width: width, height: height, alignment: .leading)
            .background(header ? theme.inset : Color.clear)
            .overlay(Rectangle().strokeBorder(theme.secondary.opacity(0.15), lineWidth: 0.5))
            .help(value)
            .contextMenu {
                Button(DeckL("复制单元格", "Copy cell")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
                }
            }
    }
    private func rowHeight(_ row: [String]) -> CGFloat {
        let lines = row.map { max($0.components(separatedBy: "\n").count, Int(ceil(Double($0.count) / 17))) }.max() ?? 1
        return CGFloat(min(5, max(1, lines))) * 17 + 12
    }
    static func columnName(_ index: Int) -> String {
        var number = index + 1, result = ""
        while number > 0 { number -= 1; result = String(UnicodeScalar(65 + number % 26)!) + result; number /= 26 }
        return result
    }
}

private struct ClipboardRichTextView: NSViewRepresentable {
    let text: NSAttributedString
    var usesSystemBackground = false
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 12, height: 12)
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        scroll.backgroundColor = usesSystemBackground ? .textBackgroundColor : .white
        view.backgroundColor = scroll.backgroundColor
        if view.textStorage?.isEqual(to: text) != true { view.textStorage?.setAttributedString(text) }
    }
}

private struct ClipboardHTMLView: NSViewRepresentable {
    let html: String
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        let prefix = "<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:;\"><style>body{font:14px -apple-system;margin:16px;overflow-wrap:anywhere}img{max-width:100%;height:auto}</style></head><body>"
        view.loadHTMLString(prefix + html + "</body></html>", baseURL: nil)
    }
}

private struct ClipboardFileView: View {
    let files: [URL]
    @State private var selected = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if files.count > 1 {
                Picker(DeckL("文件"), selection: $selected) {
                    ForEach(files.indices, id: \.self) { index in Text(files[index].lastPathComponent).tag(index) }
                }.padding(.horizontal, 8)
            }
            if let url = files.indices.contains(selected) ? files[selected] : files.first {
                if FileManager.default.fileExists(atPath: url.path) {
                    ClipboardQuickLookView(url: url).id(url)
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Button(DeckL("在访达中显示", "Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }.font(.caption).padding(.horizontal, 8)
                } else {
                    Text(DeckL("原文件已移动或不可访问", "The original file has moved or is unavailable")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(url.path).font(.caption).textSelection(.enabled).padding(.horizontal, 8)
            }
        }
        .onChange(of: files) { _ in selected = 0 }
    }
}

private struct ClipboardQuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}
