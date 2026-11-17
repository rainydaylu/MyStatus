import AppKit
import StatusDeckKit
import SwiftUI

struct LogoSettingsView: View {
    @ObservedObject var runtime: LogoRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(runtime.supported ? DeckL("兼容的发光 Apple 标志", "Compatible illuminated Apple logo") : DeckL("当前 Mac 不支持标志灯光控制", "Logo light control is unavailable on this Mac"),
                  systemImage: runtime.supported ? "checkmark.circle" : "info.circle")
                .foregroundStyle(runtime.supported ? Color.green : .secondary)
            if !runtime.supported {
                Text(DeckL("需要配备独立发光 Apple 标志的 MacBook；不会申请此功能的音频或输入权限。", "Requires a MacBook with an independently illuminated Apple logo. Audio/input permissions are not requested on unsupported hardware."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if runtime.connecting { ProgressView(DeckL("正在连接灯光…", "Connecting light…")) }
            if let error = runtime.error {
                Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                HStack {
                    if runtime.needsRecovery { Button(DeckL("恢复原配置", "Restore original settings")) { runtime.recover() } }
                    else { Button(DeckL("重新连接", "Reconnect")) { runtime.connect() } }
                }.disabled(runtime.connecting)
            }
            controls.disabled(!runtime.active)
            HStack {
                Text(DeckL("关闭插件后恢复原有灯光设置", "Disabling the plug-in restores the original light settings"))
                Spacer(minLength: 12)
                Link("LogoLight · MIT", destination: URL(string: "https://github.com/Ark0N/LogoLight")!)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(DeckL("灯光模式", "Light mode"))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("logolight.mode-heading")
                Spacer()
                Toggle(DeckL("灯光", "Light"), isOn: $runtime.settings.enabled)
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityIdentifier("logolight.power")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                ForEach(LogoMode.allCases) { mode in
                    LogoModeCard(mode: mode, selected: runtime.settings.mode == mode) {
                        runtime.settings.mode = mode
                    }
                }
            }
            settingsCard {
                Label(runtime.settings.mode.title + DeckL("设置", " settings"), systemImage: runtime.settings.mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 3)
                if runtime.settings.mode != .battery && runtime.settings.mode != .morse {
                    slider(DeckL("亮度", "Brightness"), value: $runtime.settings.brightness, range: 0...1,
                           label: "\(Int((runtime.settings.brightness * 100).rounded()))%")
                }
                modeOptions
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 12)], alignment: .leading, spacing: 12) {
                shortcutCard
                closedLidCard
            }
        }
    }

    private var shortcutCard: some View {
        settingsCard {
            cardToggle(DeckL("快捷键", "Shortcuts"), symbol: "command", isOn: $runtime.settings.shortcuts)
            Divider().padding(.vertical, 3)
            HStack {
                Text(DeckL("灯光开关", "Toggle light"))
                Spacer()
                keycap("⌃⌘B")
            }
            HStack {
                Text(DeckL("亮度 ±5%", "Brightness ±5%"))
                Spacer()
                keycap("⌃⌘↑ / ↓")
            }
        }
    }

    private var closedLidCard: some View {
        settingsCard {
            cardToggle(DeckL("合盖续亮", "Closed-lid light"), symbol: "laptopcomputer", isOn: $runtime.settings.keepClosed)
            Divider().padding(.vertical, 3)
            HStack {
                Text(DeckL("持续时间", "Duration"))
                Spacer()
                Picker(DeckL("持续时间", "Duration"), selection: $runtime.settings.closedMinutes) {
                    ForEach(Array(Set([5, 10, 15, 30, runtime.settings.closedMinutes])).sorted(), id: \.self) { minutes in
                        Text(DeckLF("%d 分钟", "%d minutes", minutes)).tag(minutes)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                .disabled(!runtime.settings.keepClosed)
                .accessibilityIdentifier("logolight.closed-duration")
            }
            Text(DeckL("需接通电源；锁屏或切换用户即熄灭。", "Requires power; stops on lock or user switching."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var modeOptions: some View {
        switch runtime.settings.mode {
        case .steady: Text(DeckL("保持所选亮度。", "Hold the selected brightness.")).font(.footnote).foregroundStyle(.secondary)
        case .breathing:
            slider(DeckL("呼吸周期", "Breathe cycle"), value: $runtime.settings.cycleSeconds, range: 3...10,
                   label: String(format: "%.1f s", runtime.settings.cycleSeconds))
            floorSlider
        case .battery:
            Text(DeckL("拔电后亮度跟随剩余电量；正在充电时脉冲，充满或暂停充电时常亮。此模式不受手动亮度影响。", "Follow battery charge when unplugged, pulse while charging, and stay solid at full/paused charge. Manual brightness is ignored."))
                .font(.footnote).foregroundStyle(.secondary)
            slider(DeckL("充电脉冲周期", "Charging pulse cycle"), value: $runtime.settings.cycleSeconds, range: 3...10,
                   label: String(format: "%.1f s", runtime.settings.cycleSeconds))
            floorSlider
        case .music:
            slider(DeckL("灵敏度", "Sensitivity"), value: $runtime.settings.musicGain, range: 0.25...3,
                   label: String(format: "%.2f ×", runtime.settings.musicGain))
            slider(DeckL("平滑时间", "Response smoothing"), value: $runtime.settings.musicResponse, range: 0.05...0.5,
                   label: String(format: "%.2f s", runtime.settings.musicResponse))
            Divider().padding(.vertical, 3)
            settingToggle(DeckL("节拍之间熄灭", "Dark between beats"), isOn: $runtime.settings.darkBetweenBeats)
            HStack(spacing: 12) {
                Text(DeckL("跟随系统音频，不使用麦克风", "System audio only, no microphone"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { runtime.retryAudio() } label: {
                    Image(systemName: "arrow.clockwise")
                }.help(DeckL("重试系统音频", "Retry system audio"))
                    .accessibilityLabel(DeckL("重试系统音频", "Retry system audio"))
                Link(destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) {
                    Image(systemName: "lock.shield")
                }.help(DeckL("音频隐私设置", "Audio privacy settings"))
                    .accessibilityLabel(DeckL("音频隐私设置", "Audio privacy settings"))
            }.buttonStyle(.borderless).controlSize(.small)

        case .agents:
            Text(DeckL("自动跟随 MyStatus 的 CodeIsland：工作时呼吸，等待时微亮，需要确认时闪烁。请同时启用 CodeIsland 插件。", "Follow MyStatus CodeIsland: breathe while working, dim while idle, and flash for attention. Enable the CodeIsland plug-in too."))
                .font(.footnote).foregroundStyle(.secondary)
            LabeledContent(DeckL("会话数量", "Sessions"), value: String(runtime.sessions))
        case .trackpad:
            Text(DeckL("手指接触兼容触控板时亮起，移开时熄灭。", "Light while a finger rests on a compatible trackpad."))
                .font(.footnote).foregroundStyle(.secondary)
            settingToggle(DeckL("接触时点击闪烁", "Blink on click while touching"), isOn: $runtime.settings.clickFlash)
            Text(runtime.inputStatus).font(.footnote).foregroundStyle(.secondary)
        case .typing:
            Text(DeckL("只监听按键时序，不读取输入文字；安全输入期间暂停响应。", "Observe timing only, never characters. Secure Input pauses the response."))
                .font(.footnote).foregroundStyle(.secondary)
            Text(runtime.inputStatus).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button(DeckL("授权或检查输入监控", "Enable or check Input Monitoring")) { runtime.retryInput() }
                Link(DeckL("输入监控设置", "Input Monitoring settings"), destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        case .morse:
            TextField(DeckL("输入一行文字，例如 SOS", "Enter one line, such as SOS"), text: $runtime.settings.morseText)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(.system(size: 13))
                .accessibilityLabel(DeckL("摩斯电码文字", "Morse message"))
                .accessibilityIdentifier("logolight.morse-text")
            Text(DeckL("自动循环播放。支持字母、数字和常用标点；中文转为拼音。关闭灯光或锁屏时停止。", "Loops automatically. Letters, digits and common punctuation are supported; Chinese is transliterated to pinyin. Stops when the light is off or the Mac is locked."))
                .font(.footnote).foregroundStyle(.secondary)
            let notation = LogoMorse.notation(runtime.settings.morseText)
            if notation.isEmpty {
                Text(DeckL("请输入可编码的文字；当前灯光保持熄灭。", "Enter an encodable message. The light remains off for now."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(notation).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(DeckL("点划预览：", "Morse preview: ") + notation)
                Text(DeckL("短闪为点，长闪为划；每轮之间留出停顿。", "Short flashes are dots, long flashes are dashes; a pause separates repeats."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            let skipped = LogoMorse.unsupported(runtime.settings.morseText)
            if !skipped.isEmpty {
                Text(DeckL("以下字符无法编码，将跳过：", "These characters cannot be encoded and will be skipped: ") + skipped)
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var floorSlider: some View {
        slider(DeckL("最低亮度", "Minimum brightness"), value: $runtime.settings.dimFloor, range: 0...1,
               label: "\(Int((runtime.settings.dimFloor * 100).rounded()))%")
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range).labelsHidden()
                .controlSize(.small).frame(maxWidth: .infinity)
                .accessibilityLabel(title)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 62, height: 24)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        }.frame(minHeight: 30)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.6)
            }
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
        }.frame(minHeight: 26)
    }

    private func cardToggle(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 10)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
        }.frame(minHeight: 24)
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

}

private struct LogoModeCard: View {
    let mode: LogoMode
    let selected: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .frame(width: 19)
                    Text(mode.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(2)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                    }
                }
                Text(mode.caption).font(.system(size: 11))
                    .foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
            .padding(11)
            .background(selected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(hovered ? 0.065 : 0.025),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.10), lineWidth: selected ? 1.5 : 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(mode.title)
        .accessibilityValue(selected ? DeckL("已选择", "Selected") : DeckL("未选择", "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("logolight.mode.\(mode.rawValue)")
    }
}
