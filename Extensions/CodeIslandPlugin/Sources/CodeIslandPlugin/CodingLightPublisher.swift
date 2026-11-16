import CodeIslandCore
import Foundation
import Observation

/// A minimal in-process signal. No prompts, tool arguments or paths leave CodeIsland.
@MainActor final class CodingLightPublisher {
    private struct Summary: Equatable { var state: String; var count: Int }
    private var latest = Summary(state: "idle", count: 0)
    private weak var state: AppState?
    private var observing = true
    private var request: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        track()
        request = NotificationCenter.default.addObserver(forName: .init("com.statusdeck.codingLight.request"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
    }

    private func track() {
        guard observing, let state else { return }
        withObservationTracking {
            let values = state.sessions.values
            let needsAttention = values.contains { $0.status == .waitingApproval || $0.status == .waitingQuestion }
            let isWorking = values.contains { $0.status == .running || $0.status == .processing }
            let next = Summary(state: needsAttention ? "attention" : isWorking ? "working" : "idle", count: values.count)
            if latest != next { latest = next; publish() }
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func publish() {
        NotificationCenter.default.post(name: .init("com.statusdeck.codingLight.changed"), object: nil,
                                        userInfo: ["state": latest.state, "sessions": latest.count])
    }

    func stop() {
        observing = false; state = nil
        if let request { NotificationCenter.default.removeObserver(request) }; request = nil
        latest = Summary(state: "idle", count: 0); publish()
    }
}
