import Foundation

/// A timer several owners can share. It runs at the fastest rate anyone asked for
/// and stops when nobody wants it, so a disabled plugin leaves no polling behind.
@MainActor
final class IntervalPoller {
    private let action: () -> Void
    private var intervals: [String: TimeInterval] = [:]
    private var timer: Timer?
    private var currentInterval: TimeInterval?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// `nil` withdraws this owner's request.
    func set(owner: String, interval: TimeInterval?) {
        let hadNoOwners = intervals.isEmpty
        intervals[owner] = interval
        let wanted = intervals.values.min()
        if wanted != currentInterval {
            timer?.invalidate()
            timer = nil
            currentInterval = wanted
            if let wanted {
                let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.action() }
                }
                timer.tolerance = wanted * 0.2
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        }
        if hadNoOwners, wanted != nil { action() }
    }

    var isRunning: Bool { timer != nil }
}
