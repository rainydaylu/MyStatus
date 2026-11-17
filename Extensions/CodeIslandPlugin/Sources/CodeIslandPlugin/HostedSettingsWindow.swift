import AppKit
import CodeIslandCore
import Combine
import SwiftUI

/// Hosts the original upstream settings view in its own window. The main app
/// continues to own its Dock policy, login item and extension update mechanism.
@MainActor
final class HostedCodeIslandSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = HostedCodeIslandSettingsWindow()
    private var window: NSWindow?
    private weak var appState: AppState?
    var openUpdates: (() -> Void)?

    func bind(appState: AppState) {
        guard let window, self.appState !== appState else { return }
        self.appState = appState
        window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
    }

    func show(appState: AppState?, openUpdates: @escaping () -> Void) {
        self.openUpdates = openUpdates
        if let window {
            if self.appState !== appState {
                self.appState = appState
                window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.appState = appState
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: min(780, frame.width * 0.8), height: min(650, frame.height * 0.85)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "CodeIsland — \(L10n.shared["settings_title"])"
        window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
        window.contentMinSize = NSSize(width: 660, height: 540)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        appState = nil
        openUpdates = nil
    }
}

enum UpdateState: Equatable {
    case idle, checking, upToDate
    case available(version: String)
    case failed(String)
}

/// A hosted extension must never let the standalone Sparkle updater replace
/// MyStatus. Keep the original About page's update action routed to the host.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published private(set) var state: UpdateState = .idle
    let isHomebrewInstall = false
    let readOnlyInstallReason: AppInstallLocation.ReadOnlyReason? = nil

    func checkForUpdates() { HostedCodeIslandSettingsWindow.shared.openUpdates?() }
}
