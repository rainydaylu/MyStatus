import ServiceManagement
import SwiftUI

/// The same login item setting wherever the host exposes it.
public struct DeckLoginItemSetting: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        Toggle(DeckL("开机时启动"), isOn: Binding(get: { enabled }, set: setEnabled))
            .onAppear { enabled = SMAppService.mainApp.status == .enabled }
        if let errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(.red)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        self.enabled = SMAppService.mainApp.status == .enabled
    }
}
