import IOKit.pwr_mgt
import StatusDeckKit
import SwiftUI

/// A complete third-party plugin: one row in the panel, with a window of detail.
/// Everything it uses comes from StatusDeckKit, the only module a plugin can see.
@MainActor
final class KeepAwakePlugin: DeckPlugin {
    let manifest = PluginManifest(
        id: "com.example.keepawake",
        name: "防止休眠",
        summary: "示例插件：开启后阻止 Mac 进入睡眠。",
        symbol: "cup.and.saucer.fill",
        category: .tools,
        enabledByDefault: false,
        sortOrder: 400
    )

    private let model = KeepAwakeModel()

    func activate(host: any DeckHost) {
        // Nothing to start until the user flips the switch.
    }

    /// A disabled plugin must leave nothing behind, here the power assertion.
    func deactivate() {
        model.setActive(false)
    }

    var sections: [DeckSection] {
        [DeckSection(id: "keepawake", title: "防止休眠") {
            KeepAwakeRow(model: model)
        } detail: {
            KeepAwakeDetail(model: model)
        }]
    }
}

@MainActor
final class KeepAwakeModel: ObservableObject {
    @Published private(set) var isActive = false
    private var assertion: IOPMAssertionID = 0

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        if active {
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "StatusDeck 防止休眠插件" as CFString,
                &assertion
            )
            isActive = status == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            isActive = false
        }
    }
}

private struct KeepAwakeRow: View {
    @ObservedObject var model: KeepAwakeModel
    var body: some View { DeckTitleRow("防止休眠", value: model.isActive ? "已开启" : "已关闭") }
}

private struct KeepAwakeDetail: View {
    @ObservedObject var model: KeepAwakeModel
    @Environment(\.deckTheme) private var theme

    var body: some View {
        DeckCard {
            HStack(spacing: 9) {
                DeckRoundIcon("cup.and.saucer.fill", isActive: model.isActive, size: 26)
                Text("阻止显示器和系统睡眠")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.primary)
                Spacer()
                DeckSwitch(isOn: model.isActive) { model.setActive(!model.isActive) }
            }
        }
    }
}

/// The one symbol the host looks for.
@_cdecl("statusdeck_plugin_create")
public func statusdeckPluginCreate() -> UnsafeMutableRawPointer {
    DeckPluginExport.retained { KeepAwakePlugin() }
}
