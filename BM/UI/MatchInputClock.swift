import Foundation
import Observation

@MainActor @Observable final class MatchInputClock {
    private(set) var running = false
    private(set) var phase = 0.0
    private var task: Task<Void, Never>?

    func start(windup: Double, duration: Double, onTimeout: @escaping @MainActor () -> Void) {
        guard !running else { return }
        running = true; phase = 0
        let start = ProcessInfo.processInfo.systemUptime
        task = Task { @MainActor in
            do {
                while !Task.isCancelled {
                    phase = min(1, max(0, (ProcessInfo.processInfo.systemUptime - start - windup) / duration))
                    if phase >= 1 { onTimeout(); return }
                    try await Task.sleep(for: .milliseconds(16))
                }
            } catch { /* Cancelling an uncommitted input does not resolve a pitch. */ }
        }
    }
    func stop() { task?.cancel(); task = nil; running = false }
}
