import AppKit
import StatusDeckKit
import SwiftUI

/// Draw the actual macOS close button with a larger click/touch target.
struct ClipboardCloseButton: View {
    var label = DeckL("关闭剪贴板", "Close clipboard")
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NativeCloseGlyph().allowsHitTesting(false).frame(width: 14, height: 14)
                .frame(width: 32, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

private struct NativeCloseGlyph: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSWindow.standardWindowButton(.closeButton, for: [.titled]) ?? NSButton()
        button.isEnabled = true
        button.target = nil
        button.action = nil
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) {}
}
