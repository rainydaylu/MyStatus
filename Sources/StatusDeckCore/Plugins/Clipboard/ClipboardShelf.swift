import AppKit
import StatusDeckKit
import SwiftUI
import UniformTypeIdentifiers

enum ClipboardPointerGeometry {
    static let coordinateSpace = "clipboard.shelf"
    static func itemID(at point: CGPoint, list: CGRect, rows: [Int64: CGRect]) -> Int64? {
        guard list.contains(point) else { return nil }
        return rows.first { $0.value.contains(point) }?.key
    }
}

private struct ClipboardRowsKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]
    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ClipboardListKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // Unmeasured siblings publish the default value too. They must not erase
        // the ScrollView's real viewport, or every pointer hit is rejected.
        if !next.isEmpty { value = next }
    }
}

private extension ClipboardTagColor {
    var tint: Color {
        switch self {
        case .orange: .orange
        case .green: .green
        case .red: .red
        case .blue: .blue
        case .purple: .purple
        }
    }
}

struct ClipboardShelf: View {
    @ObservedObject var model: ClipboardModel
    let canPaste: Bool
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool
    @State private var isDropTarget = false
    @State private var showsTagEditor = false
    @State private var tagName = ""
    @State private var tagColor = ClipboardTagColor.red
    @Environment(\.deckTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ClipboardCloseButton(action: onClose)
                Spacer()
            }.padding(.horizontal, 6).padding(.top, 4)
            search.padding(.horizontal, 12).padding(.top, 1)
            tagBar.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
            ClipboardAccessNotice(model: model).padding(.horizontal, 12)
            historyList
            footer
        }
        .foregroundStyle(theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MenuPanelSurface(cornerRadius: 19))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(isDropTarget ? theme.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .padding(4)
        .coordinateSpace(name: ClipboardPointerGeometry.coordinateSpace)
        .onPreferenceChange(ClipboardRowsKey.self) { model.previewRowFrames = $0 }
        .onPreferenceChange(ClipboardListKey.self) { model.previewListFrame = $0 }
        .onDrop(of: [.fileURL, .url, .image, .text], isTargeted: $isDropTarget, perform: model.importDrop)
        .onAppear { searchFocused = true }
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondary)
            if model.rendersStaticSnapshot {
                Text(DeckL("搜索")).foregroundStyle(theme.secondary)
                Spacer()
            } else {
                TextField(DeckL("搜索"), text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
            }
            if model.isDryRun {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 12)).foregroundStyle(theme.secondary)
            } else {
              Menu {
                Section(DeckL("内容类型", "Content type")) {
                    ForEach(ClipFilter.allCases.filter { $0 != .pinned }, id: \.self) { filter in
                        Button {
                            model.filter = filter
                        } label: {
                            if model.filter == filter { Label(filter.title, systemImage: "checkmark") }
                            else { Text(filter.title) }
                        }
                    }
                }
                Section(DeckL("来源应用", "Source app")) {
                    Button(DeckL("所有来源", "All sources")) { model.sourceFilter = nil }
                    ForEach(model.sources) { source in
                        Button(source.name) { model.sourceFilter = source.id }
                    }
                }
            } label: {
                Image(systemName: model.sourceFilter != nil || ![.all, .pinned].contains(model.filter)
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(DeckL("筛选类型与来源", "Filter by type and source"))
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 11).frame(height: 31)
        .background(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.secondary.opacity(0.22), lineWidth: 0.7))
    }

    private var tagBar: some View {
        HStack(spacing: 6) {
            if model.isDryRun {
                tagItems.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) { tagItems }
            }
            Button {
                tagName = ""
                showsTagEditor = true
            } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .light))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 27, height: 27)
                    .background(theme.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain).help(DeckL("新建标签", "New tag"))
            .popover(isPresented: $showsTagEditor) { tagEditor }
        }
        .frame(height: 32)
    }

    private var tagItems: some View {
        HStack(spacing: 15) {
            tagButton(DeckL("全部"), color: .orange, selected: model.selectedTagID == nil && model.filter != .pinned) {
                model.selectedTagID = nil
                model.filter = .all
            }
            tagButton(DeckL("置顶"), color: .green, selected: model.selectedTagID == nil && model.filter == .pinned) {
                model.selectedTagID = nil
                model.filter = .pinned
            }
            ForEach(model.tags) { tag in
                tagButton(tag.name, color: tag.color.tint, selected: model.selectedTagID == tag.id) {
                    model.filter = .all
                    model.selectedTagID = tag.id
                }
                .contextMenu {
                    Button(DeckL("删除标签", "Delete tag"), role: .destructive) { model.deleteTag(tag) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tagButton(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DeckL("新建标签", "New tag")).font(.headline)
            TextField(DeckL("标签名称", "Tag name"), text: $tagName).onSubmit(createTag)
            HStack(spacing: 12) {
                ForEach(ClipboardTagColor.allCases, id: \.self) { color in
                    Button { tagColor = color } label: {
                        Circle().fill(color.tint).frame(width: 19, height: 19)
                            .overlay {
                                if tagColor == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                            }
                    }
                    .buttonStyle(.plain).accessibilityLabel(color.rawValue)
                }
            }
            HStack {
                Spacer()
                Button(DeckL("取消", "Cancel")) { showsTagEditor = false }
                Button(DeckL("创建", "Create"), action: createTag)
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 245)
    }

    private func createTag() {
        guard !tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.addTag(name: tagName, color: tagColor)
        showsTagEditor = false
    }

    @ViewBuilder private var historyList: some View {
      if model.rendersStaticSnapshot {
        VStack(spacing: 3) {
            ForEach(model.items) { item in
                ClipboardShelfRow(item: item, selected: item.id == model.selectedID)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      } else {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if model.items.isEmpty {
                        Text(DeckL("没有找到匹配的内容。")).font(.callout)
                            .foregroundStyle(theme.secondary).padding(.vertical, 28)
                    }
                    ForEach(model.items) { item in
                        Button {
                            searchFocused = false
                            model.selectPreview(item)
                        } label: {
                            ClipboardShelfRow(item: item, selected: item.id == model.selectedID)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: ClipboardRowsKey.self,
                                    value: [item.id: proxy.frame(in: .named(ClipboardPointerGeometry.coordinateSpace))])
                            })
                            .onContinuousHover { phase in
                                if case .active = phase { model.hoverPreview(item) }
                            }
                            .onDrag { model.dragProvider(for: item) }
                            .contextMenu {
                                Button(DeckL("复制")) { model.copy(item) }
                                Button(DeckL("仅复制文本", "Copy plain text")) { model.copyPlainText(item) }
                                    .disabled(item.text == nil)
                                Button(item.isPinned ? DeckL("取消置顶") : DeckL("置顶")) { model.togglePin(item) }
                                if !model.tags.isEmpty {
                                    Menu(DeckL("标签", "Tags")) {
                                        ForEach(model.tags) { tag in
                                            Button { model.toggleTag(tag, for: item) } label: {
                                                if item.tagIDs.contains(tag.id) { Label(tag.name, systemImage: "checkmark") }
                                                else { Text(tag.name) }
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button(DeckL("删除"), role: .destructive) { model.delete(item) }
                            }
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 5)
            }
            .onChange(of: model.keyboardSelectionCounter) { _ in
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ClipboardListKey.self,
                    value: proxy.frame(in: .named(ClipboardPointerGeometry.coordinateSpace)))
            })
        }
      }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(DeckL("↑↓ 选择", "↑↓ Select"))
            Text(canPaste ? DeckL("↩ 粘贴", "↩ Paste") : DeckL("↩ 复制", "↩ Copy"))
            Text(DeckL("双击复制", "Double-click to copy"))
            Spacer(minLength: 0)
            Text(DeckL("Esc 关闭", "Esc Close"))
        }
        .font(.system(size: 10.5)).foregroundStyle(theme.secondary)
        .padding(.horizontal, 14).padding(.vertical, 6)
    }
}

private struct ClipboardShelfRow: View {
    let item: ClipboardItem
    let selected: Bool
    @State private var hovered = false
    @Environment(\.deckTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            leading.frame(width: 38, height: 42)
            VStack(alignment: .leading, spacing: 15) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(6).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)) }
                    Text(typeName)
                    if !item.tagIDs.isEmpty { Image(systemName: "tag.fill").font(.system(size: 9)) }
                    Spacer(minLength: 3)
                    Text(item.createdAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                        .monospacedDigit().lineLimit(1)
                }
                .font(.system(size: 11)).foregroundStyle(theme.secondary)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 75, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(selected ? 0.13 : hovered ? 0.06 : 0)
                      : Color.black.opacity(selected ? 0.12 : hovered ? 0.045 : 0))
        }
        .onHover { hovered = $0 }
        .help(item.sourceName ?? typeName)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: String {
        if item.kind == .file || item.kind == .image { return item.displayPreview }
        return String((item.text ?? item.displayPreview).trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }

    private var typeName: String {
        switch item.kind {
        case .text: item.hasRichText ? DeckL("多信息文本 (RTF)", "Rich text (RTF)") : DeckL("文本")
        case .code: DeckL("代码")
        case .link: DeckL("链接")
        case .color: DeckL("颜色")
        case .image: DeckL("图片")
        case .file: DeckL("文件")
        case .richText: DeckL("富文本", "Rich text")
        case .table: DeckL("表格", "Table")
        }
    }

    @ViewBuilder private var leading: some View {
        if item.kind == .image, let data = item.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else if item.kind == .color, let value = ClipboardClassifier.color(from: item.text ?? "") {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha))
                .frame(width: 34, height: 34)
        } else if item.kind == .table {
            Image(systemName: "tablecells").font(.system(size: 25)).foregroundStyle(theme.accent)
        } else if let bundleID = item.sourceBundleID,
           let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            Image(nsImage: DeckAppIcon.image(forPath: path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 34, height: 34)
        } else if let data = item.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: item.kind.symbol).font(.system(size: 23, weight: .light))
                .foregroundStyle(theme.secondary)
        }
    }
}
