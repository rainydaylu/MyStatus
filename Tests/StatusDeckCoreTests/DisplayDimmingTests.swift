import AppKit
import CoreGraphics
import Testing
@testable import StatusDeckCore

@MainActor @Suite(.serialized) struct DisplayDimmingTests {
    @Test func aNewInputMethodCandidateStaysBelowTheDimmingWindow() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 16, height: 16)
        let shade = DisplayShadeWindow(frame: frame)
        shade.alphaValue = 0.01
        let candidate = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        candidate.isReleasedWhenClosed = false
        candidate.alphaValue = 0.01
        // WeType's candidate window is one level above the display shield.
        candidate.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        defer { shade.close(); candidate.close() }
        shade.orderFrontRegardless()
        // Reopening the input method must not escape the dimming overlay.
        candidate.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 50_000_000)
        let windows = try #require(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])
        let shadeIndex = try #require(windows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == shade.windowNumber })
        let candidateIndex = try #require(windows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == candidate.windowNumber })
        #expect(shadeIndex < candidateIndex, "Input candidates must be composited below the dimming overlay")
        #expect(shade.ignoresMouseEvents)
        #expect(!shade.canBecomeKey)
        #expect(!shade.canBecomeMain)
    }
}
