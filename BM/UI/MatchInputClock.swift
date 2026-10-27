import Foundation
import Observation

/// One monotonic origin drives the input phase and the visible pitch arrival.
struct MatchInputTimeline: Equatable, Sendable {
    let startedAt: Double
    let windup: Double
    let duration: Double
    init(startedAt: Double = ProcessInfo.processInfo.systemUptime, windup: Double, duration: Double) {
        self.startedAt = startedAt; self.windup = windup; self.duration = duration
    }
    var releaseAt: Double { startedAt + windup }
    var contactAt: Double { releaseAt + duration * MatchDelivery.contactPhase }
    func phase(at time: Double) -> Double { min(1, max(0, (time - releaseAt) / duration)) }
}

@MainActor @Observable final class MatchInputClock {
    private(set) var running = false
    private(set) var phase = 0.0
    private var task: Task<Void, Never>?
    private var timeline: MatchInputTimeline?
    var currentPhase: Double { timeline?.phase(at: ProcessInfo.processInfo.systemUptime) ?? phase }

    func start(windup: Double, duration: Double, onTimeout: @escaping @MainActor () -> Void) {
        start(timeline: MatchInputTimeline(windup: windup, duration: duration), onTimeout: onTimeout)
    }
    func start(timeline: MatchInputTimeline, onTimeout: @escaping @MainActor () -> Void) {
        guard !running else { return }
        self.timeline = timeline; running = true; phase = 0
        task = Task { @MainActor in
            do {
                while !Task.isCancelled {
                    phase = currentPhase
                    if phase >= 1 { onTimeout(); return }
                    try await Task.sleep(for: .milliseconds(16))
                }
            } catch { /* Cancelling an uncommitted input does not resolve a pitch. */ }
        }
    }
    func stop() { phase = currentPhase; task?.cancel(); task = nil; running = false; timeline = nil }
}
