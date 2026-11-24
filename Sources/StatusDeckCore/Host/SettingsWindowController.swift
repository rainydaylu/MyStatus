import AppKit

/// Give settings a Dock entry while keeping normal menu-bar use unobtrusive.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let showsDockIcon: Bool
    private var previousPolicy: NSApplication.ActivationPolicy?

    init(window: NSWindow, showsDockIcon: Bool) {
        self.showsDockIcon = showsDockIcon
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        if showsDockIcon {
            if previousPolicy == nil { previousPolicy = NSApp.activationPolicy() }
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
            }
            NSApp.setActivationPolicy(.regular)
        }
        super.showWindow(sender)
        if window?.isMiniaturized == true { window?.deminiaturize(sender) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        if let previousPolicy {
            NSApp.setActivationPolicy(previousPolicy)
            self.previousPolicy = nil
        }
    }
}
