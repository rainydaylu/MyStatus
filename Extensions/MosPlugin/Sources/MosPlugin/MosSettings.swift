import AppKit
import StatusDeckKit
import SwiftUI
import UniformTypeIdentifiers

struct MosSettings: View {
    private enum Page: CaseIterable, Identifiable {
        case basic, advanced, applications, updates, about

        var id: Self { self }
        var title: String {
            switch self {
            case .basic: DeckL("基础", "Basic")
            case .advanced: DeckL("高级", "Advanced")
            case .applications: DeckL("例外", "Exceptions")
            case .updates: DeckL("更新", "Updates")
            case .about: DeckL("关于", "About")
            }
        }
    }

    @ObservedObject var engine: MosEngine
    @ObservedObject var preferences: MosPreferences
    let version: String
    let iconChanged: () -> Void
    let openUpdates: () -> Void
    @State private var page = Page.basic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(DeckL("Mos 设置", "Mos settings"), selection: $page) {
                ForEach(Page.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch page {
            case .basic:
                Text(engine.active ? DeckL("正在接收鼠标滚轮", "Receiving mouse wheel events") : DeckL("等待辅助功能权限", "Waiting for Accessibility permission"))
                    .font(.callout).foregroundStyle(engine.active ? .green : .orange)
                MosBasicOptions(options: $preferences.options)
                Divider()
                DeckLoginItemSetting()
                Text(DeckL("登录后启动 mystatus，并载入已启用的 Mos。", "Start mystatus at login and load Mos when it is enabled."))
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle(DeckL("隐藏 Mos 状态栏图标", "Hide Mos menu bar icon"), isOn: $preferences.hidesIcon)
                    .onChange(of: preferences.hidesIcon) { _, _ in iconChanged() }
            case .advanced:
                MosAdvancedOptions(options: $preferences.options)
            case .applications:
                MosApplications(preferences: preferences)
            case .updates:
                Text(DeckL("在 mystatus 的插件更新中检查和安装 Mos 更新。", "Check for and install Mos updates in mystatus Plugin Updates."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(DeckL("打开插件更新", "Open Plugin Updates"), action: openUpdates)
            case .about:
                Text("Mos · \(version)").font(.headline)
                Text(DeckL("基于 Caldis/Mos 的滚动插值，作为 mystatus 插件运行。", "Uses Caldis/Mos scroll interpolation inside mystatus."))
                    .font(.callout).foregroundStyle(.secondary)
                Link(DeckL("Mos 开源项目", "Mos open source project"), destination: URL(string: "https://github.com/Caldis/Mos")!)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct MosBasicOptions: View {
    @Binding var options: MosScrollOptions

    var body: some View {
        Toggle(DeckL("平滑滚动", "Smooth scrolling"), isOn: $options.smooth)
        Toggle(DeckL("翻转方向", "Reverse direction"), isOn: $options.reverse)
        if options.reverse {
            HStack {
                Toggle(DeckL("垂直", "Vertical"), isOn: $options.reverseVertical)
                Toggle(DeckL("水平", "Horizontal"), isOn: $options.reverseHorizontal)
            }
            .toggleStyle(.checkbox)
        }
    }
}

private struct MosAdvancedOptions: View {
    @Binding var options: MosScrollOptions

    var body: some View {
        keyPicker(DeckL("加速键", "Boost key"), selection: $options.boostKey,
                  explanation: DeckL("按住时加快滚动。", "Hold to scroll faster."))
        keyPicker(DeckL("转换键", "Horizontal scroll key"), selection: $options.horizontalKey,
                  explanation: DeckL("按住时把垂直滚动转换为水平滚动。", "Hold to turn vertical scrolling into horizontal scrolling."))
        keyPicker(DeckL("禁用键", "Bypass key"), selection: $options.bypassKey,
                  explanation: DeckL("按住时暂停平滑。", "Hold to pause smoothing."))
        Divider()
        MosNumberSetting(title: DeckL("最短步长", "Minimum step"), value: $options.minimumStep,
                         range: MosScrollOptions.stepRange, step: 1, unit: "px")
        MosNumberSetting(title: DeckL("速度增益", "Speed gain"), value: $options.speed,
                         range: MosScrollOptions.speedRange, step: 0.05, unit: "×")
        MosNumberSetting(title: DeckL("持续时间", "Duration"), value: $options.duration,
                         range: MosScrollOptions.durationRange, step: 0.01, unit: "")
        Button(DeckL("恢复为预设值", "Restore defaults")) { options.resetAdvanced() }
    }

    private func keyPicker(_ title: String, selection: Binding<MosModifier>, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: selection) {
                ForEach(MosModifier.allCases) { Text($0.title).tag($0) }
            }
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct MosNumberSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        let limited = Binding(get: { value }, set: { proposed in
            if proposed.isFinite { value = min(range.upperBound, max(range.lowerBound, proposed)) }
        })
        let sliderValue = Binding(get: { limited.wrappedValue }, set: { proposed in
            limited.wrappedValue = range.lowerBound + ((proposed - range.lowerBound) / step).rounded() * step
        })
        LabeledContent(title) {
            Slider(value: sliderValue, in: range)
                .accessibilityLabel(title)
            TextField(title, value: limited, format: .number.precision(.fractionLength(2)))
                .labelsHidden()
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 17)
            Stepper(title, value: limited, in: range, step: step).labelsHidden()
        }
    }
}

private struct MosApplications: View {
    @ObservedObject var preferences: MosPreferences
    @State private var editing: MosAppRule?

    var body: some View {
        Toggle(DeckL("白名单模式", "Allowlist mode"), isOn: $preferences.allowlist)
        Text(preferences.allowlist
            ? DeckL("只处理列表中的应用。", "Only listed apps use Mos settings.")
            : DeckL("列表中的应用使用独立设置，其余应用使用基础和高级设置。", "Listed apps use their own settings. Other apps use the global settings."))
            .font(.footnote).foregroundStyle(.secondary)
        if preferences.rules.isEmpty {
            Text(DeckL("还没有添加应用。", "No apps added yet.")).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Text(DeckL("平滑", "Smooth")).frame(width: 45)
                Text(DeckL("反转", "Reverse")).frame(width: 45)
                Text(DeckL("应用程序", "Application"))
            }
            .font(.caption).foregroundStyle(.secondary)
            ForEach($preferences.rules) { $rule in
                HStack(spacing: 8) {
                    Toggle(DeckL("平滑", "Smooth"), isOn: $rule.options.smooth).frame(width: 45)
                    Toggle(DeckL("反转", "Reverse"), isOn: $rule.options.reverse).frame(width: 45)
                    Image(nsImage: rule.path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
                        .resizable().frame(width: 22, height: 22)
                    Text(rule.name).lineLimit(1).help(rule.id)
                    Spacer(minLength: 0)
                    Button { editing = rule } label: { Image(systemName: "ellipsis.circle") }
                        .help(DeckL("编辑应用设置", "Edit app settings"))
                    Button(role: .destructive) { preferences.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                        .help(DeckL("移除应用", "Remove app"))
                }
                .labelsHidden().toggleStyle(.checkbox).buttonStyle(.borderless)
            }
        }
        Menu {
            Menu(DeckL("运行中的应用程序", "Running applications")) {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier, let url = app.bundleURL {
                        Button(app.localizedName ?? id) { preferences.addApp(id: id, name: app.localizedName ?? id, url: url) }
                            .disabled(preferences.rules.contains { $0.id == id })
                    }
                }
            }
            Button(DeckL("手动从访达中选择…", "Choose an app in Finder…"), action: chooseApplication)
        } label: {
            Label(DeckL("添加应用", "Add application"), systemImage: "plus")
        }
        .sheet(item: $editing) { app in
            if let index = preferences.rules.firstIndex(where: { $0.id == app.id }) {
                MosApplicationEditor(name: app.name, options: $preferences.rules[index].options)
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleURL != nil && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? FileManager.default.displayName(atPath: url.deletingPathExtension().path)
            preferences.addApp(id: id, name: name, url: url)
        }
    }
}

private struct MosApplicationEditor: View {
    let name: String
    @Binding var options: MosScrollOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MosBasicOptions(options: $options)
                    Divider()
                    MosAdvancedOptions(options: $options)
                }
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button(DeckL("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 510)
    }
}
