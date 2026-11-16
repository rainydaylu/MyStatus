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
            Divider()
            HStack {
                Text(DeckL("MyStatus 标志灯光 · 硬件引擎基于 MIT LogoLight", "MyStatus logo light · MIT LogoLight hardware engine"))
                Spacer()
                Link("Ark0N/LogoLight", destination: URL(string: "https://github.com/Ark0N/LogoLight")!)
            }.font(.caption).foregroundStyle(.secondary)
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
            Divider()
            Label(runtime.settings.mode.title + DeckL("设置", " settings"), systemImage: runtime.settings.mode.symbol)
                .font(.headline)
            if runtime.settings.mode != .battery {
                slider(DeckL("亮度", "Brightness"), value: $runtime.settings.brightness, range: 0...1,
                       label: "\(Int((runtime.settings.brightness * 100).rounded()))%")
            }
            modeOptions
            DisclosureGroup(DeckL("快捷键与合盖", "Shortcuts and closed lid")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(DeckL("开启灯光快捷键", "Enable light shortcuts"), isOn: $runtime.settings.shortcuts)
                    Text("⌃⌘B  " + DeckL("开关", "Toggle") + "   ·   ⌃⌘↑ / ↓  " + DeckL("亮度 ±5%", "Brightness ±5%"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle(DeckL("合盖继续灯光", "Keep light on with lid closed"), isOn: $runtime.settings.keepClosed)
                    if runtime.settings.keepClosed {
                        Stepper(DeckLF("最长 %d 分钟", "Up to %d minutes", runtime.settings.closedMinutes), value: $runtime.settings.closedMinutes, in: 1...30)
                        Text(DeckL("需连接电源。限时运行；低电量模式或过热时停止。内置屏幕可能保持亮起。", "Requires external power. Time-limited; stops in Low Power Mode or high temperatures. The built-in screen may remain lit."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            }
            Text(DeckL("关闭插件会停止互动与音频，并恢复接管前的标志开关。开机启动由 MyStatus 的偏好设置统一管理。", "Disabling the plug-in stops input/audio and restores the original logo switch. MyStatus preferences manage login launch."))
                .font(.footnote).foregroundStyle(.secondary)
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
            Text(DeckL("跟随系统播放的音乐，不使用麦克风，不录制或保存音频。", "Follow system playback without using the microphone or recording/saving audio."))
                .font(.footnote).foregroundStyle(.secondary)
            slider(DeckL("灵敏度", "Sensitivity"), value: $runtime.settings.musicGain, range: 0.25...3,
                   label: String(format: "%.2f ×", runtime.settings.musicGain))
            slider(DeckL("平滑时间", "Response smoothing"), value: $runtime.settings.musicResponse, range: 0.05...0.5,
                   label: String(format: "%.2f s", runtime.settings.musicResponse))
            Toggle(DeckL("节拍之间熄灭", "Dark between beats"), isOn: $runtime.settings.darkBetweenBeats)
            HStack {
                Button(DeckL("重试系统音频", "Retry system audio")) { runtime.retryAudio() }
                Link(DeckL("音频隐私设置", "Audio privacy settings"), destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
            }
        case .agents:
            Text(DeckL("自动跟随 MyStatus 的 CodeIsland：工作时呼吸，等待时微亮，需要确认时闪烁。请同时启用 CodeIsland 插件。", "Follow MyStatus CodeIsland: breathe while working, dim while idle, and flash for attention. Enable the CodeIsland plug-in too."))
                .font(.footnote).foregroundStyle(.secondary)
            LabeledContent(DeckL("会话数量", "Sessions"), value: String(runtime.sessions))
        case .trackpad:
            Text(DeckL("手指接触兼容触控板时亮起，移开时熄灭。", "Light while a finger rests on a compatible trackpad."))
                .font(.footnote).foregroundStyle(.secondary)
            Toggle(DeckL("接触时点击闪烁", "Blink on click while touching"), isOn: $runtime.settings.clickFlash)
            Text(runtime.inputStatus).font(.footnote).foregroundStyle(.secondary)
        case .typing:
            Text(DeckL("只监听按键时序，不读取输入文字；安全输入期间暂停响应。", "Observe timing only, never characters. Secure Input pauses the response."))
                .font(.footnote).foregroundStyle(.secondary)
            Text(runtime.inputStatus).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button(DeckL("授权或检查输入监控", "Enable or check Input Monitoring")) { runtime.retryInput() }
                Link(DeckL("输入监控设置", "Input Monitoring settings"), destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        }
    }

    private var floorSlider: some View {
        slider(DeckL("最低亮度", "Minimum brightness"), value: $runtime.settings.dimFloor, range: 0...1,
               label: "\(Int((runtime.settings.dimFloor * 100).rounded()))%")
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(label).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
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
