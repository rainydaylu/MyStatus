import AppKit
import ServiceManagement
import SwiftUI

/// Register the installed app once; later system or user opt-outs stay respected.
@MainActor
public final class DeckLoginItemController: ObservableObject {
    public static let shared = DeckLoginItemController()
    public static let preferenceKey = "app.launchAtLogin"
    @Published public private(set) var status = SMAppService.mainApp.status
    @Published public private(set) var errorMessage: String?

    public var enabled: Bool { status == .enabled || status == .requiresApproval }

    public func applyDefaultIfNeeded() {
        guard UserDefaults.standard.object(forKey: Self.preferenceKey) == nil else {
            refresh()
            return
        }
        setEnabled(true)
    }

    public func refresh() { status = SMAppService.mainApp.status }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
        do {
            let current = SMAppService.mainApp.status
            if enabled && current != .enabled && current != .requiresApproval {
                try SMAppService.mainApp.register()
            } else if !enabled && (current == .enabled || current == .requiresApproval) {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

public struct DeckLoginItemSetting: View {
    @ObservedObject private var controller = DeckLoginItemController.shared

    public init() {}

    public var body: some View {
        Toggle(DeckL("开机时启动"), isOn: Binding(get: { controller.enabled }, set: controller.setEnabled))
            .onAppear { controller.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                controller.refresh()
            }
        if controller.status == .requiresApproval {
            Button(DeckL("在系统设置中允许自动启动", "Allow automatic startup in System Settings")) {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        if let errorMessage = controller.errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(.red)
        }
    }
}
