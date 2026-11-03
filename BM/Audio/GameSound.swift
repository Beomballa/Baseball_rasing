import AVFoundation
import UIKit

@MainActor final class GameSound {
    static let shared = GameSound()
    private let output = GameAudioOutput()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private var observers: [NSObjectProtocol] = []
    private init() {
        for name in [UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIAccessibility.voiceOverStatusDidChangeNotification] {
            let invalidates = name != UIAccessibility.voiceOverStatusDidChangeNotification
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.output.stop(invalidateSession: invalidates) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepare() }
        })
    }
    func prepare() {
        guard canPlay else { return }
        output.prepare(); impact.prepare()
    }
    private var canPlay: Bool {
        (UserDefaults.standard.object(forKey: "bm-sound-enabled") as? Bool ?? true) && active
    }
    private var active: Bool { UIApplication.shared.applicationState == .active && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil }
    static func volume(_ stored: Double?) -> Float {
        guard let stored, stored.isFinite else { return 0.9 }
        return Float(max(0, min(1, stored)))
    }
    private var volume: Float { Self.volume(UserDefaults.standard.object(forKey: "bm-sound-volume") as? Double) }
    func play(_ cue: GameSoundCue) {
        guard canPlay else { return }
        output.play(cue, volume: volume)
    }
    func contact() {
        if active, UserDefaults.standard.object(forKey: "bm-haptics-enabled") as? Bool ?? true {
            impact.impactOccurred(intensity: 0.9); impact.prepare()
        }
        play(.contact)
    }
    func updateVolume() { output.updateVolume(volume) }
    func announce(outcome: String) {
        guard let call = UmpireCall(outcome: outcome) else { return }
        announce(call)
    }
    func announce(_ call: UmpireCall) {
        output.stopVoice()
        guard canPlay, UserDefaults.standard.object(forKey: "bm-umpire-voice-enabled") as? Bool ?? true,
              !UIAccessibility.isVoiceOverRunning else { return }
        output.announce(call, volume: volume)
    }
    func stopVoice() { output.stopVoice() }
    func stop() { output.stop() }
}
