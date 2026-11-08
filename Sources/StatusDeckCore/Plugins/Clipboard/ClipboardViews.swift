import AppKit
import Carbon
import StatusDeckKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardRow: View {
    @ObservedObject var model: ClipboardModel

    var body: some View {
        let count = model.totalCount == 1 ? DeckL("1 条", "1 item") : DeckLF("%ld 条", "%ld items", model.totalCount)
        DeckTitleRow(DeckL("剪贴板"), value: model.isPaused ? DeckL("已暂停", "Paused") + " · " + count : count)
    }
}

/// The search box. A real text field cannot draw in screenshot mode, where a plain
/// label takes its place.
private struct ClipboardSearchField: View {
    @ObservedObject var model: ClipboardModel
    var focus: FocusState<Bool>.Binding?
    @Environment(\.deckTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondary)
            if model.isDryRun {
                Text(DeckL("搜索")).font(.system(size: 12)).foregroundStyle(theme.tertiary)
                Spacer(minLength: 0)
            } else {
                field
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.inset))
    }

    @ViewBuilder
    private var field: some View {
        let text = TextField(DeckL("搜索"), text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(theme.primary)
        if let focus {
            text.focused(focus)
        } else {
            text
        }
    }
}

private struct ClipboardFilterBar: View {
    @ObservedObject var model: ClipboardModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(ClipFilter.allCases, id: \.self) { filter in
                    DeckChip(filter.title, isSelected: model.filter == filter) { model.filter = filter }
                }
            }
        }
    }
}

/// A thumbnail, a color swatch, or a round icon, depending on what was copied.
private struct ClipLeading: View {
    let item: ClipboardItem
    @Environment(\.deckTheme) private var theme

    var body: some View {
        Group {
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if item.kind == .color, let color = ClipboardClassifier.color(from: item.text ?? "") {
                Circle()
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(theme.cardStroke, lineWidth: 1))
            } else {
                DeckRoundIcon(item.kind.symbol, isActive: false, size: 26)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct ClipRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let lineLimit: Int
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onSelect: (() -> Void)? = nil

    @State private var isHovered = false
    @Environment(\.deckTheme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            ClipLeading(item: item)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayPreview)
                    .font(item.kind == .code ? .system(size: 11, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(theme.primary)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if item.isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(theme.accent)
                    }
                    Text([item.sourceName, Format.relativeTime(item.createdAt)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isHovered {
                HStack(spacing: 0) {
                    DeckIconButton(symbol: item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? DeckL("取消置顶") : DeckL("置顶"), action: onPin)
                    DeckIconButton(symbol: "trash", help: DeckL("删除"), action: onDelete)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect ?? onCopy)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        if isSelected {
            shape.fill(LinearGradient(colors: [theme.selectedLeading, theme.selectedTrailing], startPoint: .leading, endPoint: .trailing))
        } else if isHovered {
            shape.fill(theme.rowHover)
        }
    }
}

// MARK: - In the panel

struct ClipboardPanelSection: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var hotKey: HotKeyModel
    let onOpenBrowser: () -> Void
    @Environment(\.deckTheme) private var theme

    private let visibleRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ClipboardAccessNotice(model: model)
            ClipboardSearchField(model: model)
            ClipboardFilterBar(model: model)
            if model.items.isEmpty {
                Text(model.query.isEmpty ? DeckL("还没有记录。复制点什么试试。") : DeckL("没有找到匹配的内容。"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(model.items.prefix(visibleRows)) { item in
                ClipRow(
                    item: item,
                    isSelected: false,
                    lineLimit: 1,
                    onCopy: { model.copy(item) },
                    onPin: { model.togglePin(item) },
                    onDelete: { model.delete(item) }
                )
            }
            HStack {
                Text(hotKey.failed ? DeckLF("快捷键 %@ 被占用", "Shortcut %@ is already in use", hotKey.hotKey.label) : DeckL("点击复制，再按 ⌘V 粘贴"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(hotKey.failed ? theme.warning : theme.tertiary)
                Spacer()
                DeckTextButton(DeckLF("全部历史 %@", "Full history %@", hotKey.hotKey.label), action: onOpenBrowser)
            }
        }
    }
}

/// Explains the system prompt instead of leaving it to look like a malfunction.
private struct ClipboardAccessNotice: View {
    @ObservedObject var model: ClipboardModel
    @Environment(\.deckTheme) private var theme

    var body: some View {
        switch model.access {
        case .allowed:
            EmptyView()
        case .willAsk:
            notice(DeckL("macOS 读取剪贴板时可能询问是否允许。要自动记录，请在隐私设置的“粘贴”项里把 MyStatus 设为始终允许。"))
        case .denied:
            notice(DeckL("macOS 已禁止 MyStatus 读取剪贴板，所以没有新记录。可以在隐私设置里更改。"))
        }
    }

    private func notice(_ text: String) -> some View {
        DeckInset {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    DeckTextButton(DeckL("打开隐私设置")) { SystemSettings.open(.privacy) }
                }
            }
        }
    }
}

// MARK: - The browser window

/// A compact edge shelf with a keyboard-driven history list and inline preview.
struct ClipboardBrowserView: View {
    @ObservedObject var model: ClipboardModel
    var canPaste = false
    var onClose: () -> Void = {}
    @FocusState private var isSearchFocused: Bool
    @State private var showsPreview = false
    @State private var isDropTarget = false
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(DeckL("剪贴板"), systemImage: "doc.on.clipboard").font(.headline)
                Spacer()
                DeckIconButton(symbol: "xmark", help: DeckL("关闭", "Close"), action: onClose)
            }
            ClipboardAccessNotice(model: model)
            HStack(spacing: 6) {
                ClipboardSearchField(model: model, focus: $isSearchFocused)
                Menu {
                    Button(DeckL("所有来源", "All sources")) { model.sourceFilter = nil }
                    ForEach(model.sources) { source in
                        Button(source.name) { model.sourceFilter = source.id }
                    }
                } label: {
                    Image(systemName: model.sourceFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .fixedSize()
                .help(model.sources.first { $0.id == model.sourceFilter }?.name ?? DeckL("筛选来源应用", "Filter by source app"))
            }
            ClipboardFilterBar(model: model)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if model.items.isEmpty {
                            Text(DeckL("没有找到匹配的内容。")).font(.callout).foregroundStyle(theme.secondary).padding(10)
                        }
                        ForEach(model.items) { item in
                            ClipRow(item: item, isSelected: item.id == model.selectedID, lineLimit: 2,
                                    onCopy: { model.copy(item) }, onPin: { model.togglePin(item) },
                                    onDelete: { model.delete(item) }, onSelect: { model.selectedID = item.id })
                                .padding(.vertical, 3)
                                .onDrag { model.dragProvider(for: item) }
                                .contextMenu { Button(DeckL("复制")) { model.copy(item) } }
                                .id(item.id)
                        }
                    }
                }
                .onChange(of: model.selectedID) { id in if let id { proxy.scrollTo(id) } }
            }
            if showsPreview {
                Divider()
                ClipPreview(item: model.selectedItem).frame(height: 132)
            }
            HStack(spacing: 8) {
                Text(DeckL("↑↓ 选择", "↑↓ Select"))
                Text(canPaste ? DeckL("↩ 粘贴", "↩ Paste") : DeckL("↩ 复制", "↩ Copy"))
                Spacer()
                Button(DeckL("预览", "Preview")) { showsPreview.toggle() }.buttonStyle(.link)
            }
            .font(.caption).foregroundStyle(theme.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeckCardBackground())
        .overlay {
            if isDropTarget { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .padding(4)
        .onDrop(of: [.fileURL, .url, .image, .text], isTargeted: $isDropTarget, perform: model.importDrop)
        .onAppear { isSearchFocused = true }
    }
}

private struct ClipPreview: View {
    let item: ClipboardItem?
    @Environment(\.deckTheme) private var theme

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 8) {
                DeckSectionTitle(title(item.kind))
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                DeckInfoRow(DeckL("来源"), item.sourceName ?? DeckL("未知"))
                DeckInfoRow(DeckL("时间"), Format.relativeTime(item.createdAt))
                DeckInfoRow(DeckL("大小"), Format.bytes(UInt64(item.byteCount)))
            }
        } else {
            Text(DeckL("没有选中的内容"))
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
        }
    }

    private func title(_ kind: ClipKind) -> String {
        switch kind {
        case .text: DeckL("文本")
        case .code: DeckL("代码")
        case .link: DeckL("链接")
        case .color: DeckL("颜色")
        case .image: DeckL("图片")
        case .file: DeckL("文件")
        }
    }

    @ViewBuilder
    private func content(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .image:
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        case .color:
            if let color = ClipboardClassifier.color(from: item.text ?? "") {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
                    Text(item.text ?? "").font(.system(size: 13, design: .monospaced)).foregroundStyle(theme.primary)
                }
            }
        default:
            ScrollView(.vertical) {
                Text(item.text ?? item.displayPreview)
                    .font(item.kind == .code ? .system(size: 11.5, design: .monospaced) : .system(size: 12.5))
                    .foregroundStyle(theme.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Settings

struct ClipboardSettings: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var hotKey: HotKeyModel
    let onHotKeyChange: (DeckHotKey) -> Void

    @State private var isConfirmingClear = false

    var body: some View {
        Toggle(DeckL("暂停记录"), isOn: $model.isPaused)
        HStack {
            Text(DeckL("打开历史的快捷键"))
            Spacer()
            HotKeyRecorder(hotKey: hotKey.hotKey, onChange: onHotKeyChange)
        }
        if hotKey.failed {
            Text(DeckL("这个快捷键被其他应用占用了，请换一个。"))
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        Picker(DeckL("保留时间"), selection: $model.retentionDays) {
            Text(DeckL("7 天")).tag(7)
            Text(DeckL("30 天")).tag(30)
            Text(DeckL("90 天")).tag(90)
            Text(DeckL("一年")).tag(365)
            Text(DeckL("永久")).tag(0)
        }
        Picker(DeckL("最多保留"), selection: $model.maximumItems) {
            Text(DeckL("200 条")).tag(200)
            Text(DeckL("1000 条")).tag(1000)
            Text(DeckL("5000 条")).tag(5000)
        }
        Text(DeckLF("置顶内容不受限制。共 %1$@ 条，约 %2$@。", "Pinned items are exempt. %1$@ items, about %2$@.", String(model.totalCount), Format.bytes(UInt64(model.totalBytes))))
            .font(.footnote)
            .foregroundStyle(.secondary)

        DisclosureGroup(DeckLF("不记录这些应用（%@）", "Excluded apps (%@)", String(model.blockedApps.count))) {
            ForEach(model.blockedApps, id: \.self) { bundleID in
                HStack {
                    Text(displayName(bundleID)).lineLimit(1)
                    Spacer()
                    Button(DeckL("移除")) { model.blockedApps.removeAll { $0 == bundleID } }
                        .buttonStyle(.link)
                }
            }
            Menu(DeckL("从运行中的应用添加…")) {
                ForEach(runningApps, id: \.bundleID) { app in
                    Button(app.name) {
                        if !model.blockedApps.contains(app.bundleID) { model.blockedApps.append(app.bundleID) }
                    }
                }
            }
        }

        HStack {
            Spacer()
            Button(DeckL("清空历史…"), role: .destructive) { isConfirmingClear = true }
        }
        .confirmationDialog(DeckL("清空剪贴板历史？"), isPresented: $isConfirmingClear) {
            Button(DeckL("清空，保留置顶"), role: .destructive) { model.clearHistory(keepingPinned: true) }
            Button(DeckL("全部清空"), role: .destructive) { model.clearHistory(keepingPinned: false) }
        } message: {
            Text(DeckL("删除后不能恢复。"))
        }
    }

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func displayName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Click, then press the shortcut. Esc cancels.
struct HotKeyRecorder: View {
    let hotKey: DeckHotKey
    let onChange: (DeckHotKey) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? DeckL("按下快捷键…") : hotKey.label) {
            isRecording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            if let recorded = Self.hotKey(from: event) {
                stop()
                onChange(recorded)
                return nil
            }
            return event
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// A shortcut needs at least one of ⌃⌥⌘, or it would swallow ordinary typing.
    static func hotKey(from event: NSEvent) -> DeckHotKey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else {
            return nil
        }
        var carbon: Int = 0
        var label = ""
        if flags.contains(.control) { carbon |= controlKey; label += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; label += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; label += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; label += "⌘" }
        return DeckHotKey(keyCode: UInt32(event.keyCode), modifiers: UInt32(carbon), label: label + key)
    }
}
