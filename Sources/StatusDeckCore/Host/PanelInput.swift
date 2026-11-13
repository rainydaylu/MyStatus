import AppKit
import SwiftUI

/// A click wins over a stationary pointer. The next real pointer movement wins
/// over that click; redraws and layout changes at the same point do not.
struct PointerSelectionGate {
    private(set) var heldPointer: CGPoint?

    mutating func hold(at pointer: CGPoint) { heldPointer = pointer }
    mutating func reset() { heldPointer = nil }
    mutating func permitsHover(at pointer: CGPoint) -> Bool {
        guard let heldPointer else { return true }
        guard hypot(pointer.x - heldPointer.x, pointer.y - heldPointer.y) > 0.75 else { return false }
        self.heldPointer = nil
        return true
    }
}

/// Direct display touches use the touched location, independently of the mouse.
@MainActor
final class DirectTouchTapTarget: NSObject, NSGestureRecognizerDelegate {
    private weak var view: NSView?
    private let action: (CGPoint) -> Void
    private let directTouchesOnly: Bool

    init(view: NSView, clickCount: Int = 1, directTouchesOnly: Bool = true, action: @escaping (CGPoint) -> Void) {
        self.view = view
        self.action = action
        self.directTouchesOnly = directTouchesOnly
        super.init()
        view.allowedTouchTypes = [.direct, .indirect]
        let tap = NSClickGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.numberOfClicksRequired = clickCount
        // Trackpad clicks arrive as mouse events; recognizers accept direct
        // touches but reject NSTouch.TouchTypeMask.indirect.
        tap.allowedTouchTypes = .direct
        tap.delaysPrimaryMouseButtonEvents = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        event.type == .directTouch || (!directTouchesOnly && [.leftMouseDown, .leftMouseUp].contains(event.type))
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }

    @objc private func tapped(_ recognizer: NSClickGestureRecognizer) {
        guard let view, recognizer.state == .ended else { return }
        let point = recognizer.location(in: view)
        action(view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y))
    }
}
