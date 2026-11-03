import AVFoundation
import UIKit

/// 화면에서 호출하는 소리·진동 진입점이다. 설정을 확인한 뒤 재생 큐에 요청한다.
@MainActor final class GameSound {
    static let shared = GameSound()
    private let output = GameAudioOutput()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private var observers: [NSObjectProtocol] = []
    /// 비활성·오디오 중단 때 재생을 멈추고, 앱 복귀 시 다시 준비한다.
    private init() {
        for name in [
            UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification,
            AVAudioSession.mediaServicesWereResetNotification, UIAccessibility.voiceOverStatusDidChangeNotification,
        ] {
            let invalidates = name != UIAccessibility.voiceOverStatusDidChangeNotification
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.output.stop(invalidateSession: invalidates) }
                })
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.prepare() }
            })
    }
    /// 경기 시작 전에 소리와 진동을 준비하되 메인 스레드에서 음원을 읽지 않는다.
    func prepare() {
        guard canPlay else { return }
        output.prepare()
        impact.prepare()
    }
    private var canPlay: Bool {
        (UserDefaults.standard.object(forKey: "bm-sound-enabled") as? Bool ?? true) && active
    }
    // 단위 테스트와 비활성 앱에서는 실제 소리·진동을 발생시키지 않는다.
    private var active: Bool {
        UIApplication.shared.applicationState == .active
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
    /// 저장된 음량을 0~1로 제한하며 누락·비정상 값은 기본값 0.9로 읽는다.
    static func volume(_ stored: Double?) -> Float {
        guard let stored, stored.isFinite else { return 0.9 }
        return Float(max(0, min(1, stored)))
    }
    private var volume: Float { Self.volume(UserDefaults.standard.object(forKey: "bm-sound-volume") as? Double) }
    func play(_ cue: GameSoundCue) {
        guard canPlay else { return }
        output.play(cue, volume: volume)
    }
    /// 타격 진동은 소리 설정과 별도로 적용하고, 타격음은 소리 설정을 따른다.
    func contact() {
        if active, UserDefaults.standard.object(forKey: "bm-haptics-enabled") as? Bool ?? true {
            impact.impactOccurred(intensity: 0.9)
            impact.prepare()
        }
        play(.contact)
    }
    func updateVolume() { output.updateVolume(volume) }
    /// 확정 판정 문자열만 콜로 변환한다. 예상 결과로 음성을 만들지 않는다.
    func announce(outcome: String) {
        guard let call = UmpireCall(outcome: outcome) else { return }
        announce(call)
    }
    /// 이전 콜을 정리하고, VoiceOver 사용 중에는 안내 음성이 겹치지 않게 한다.
    func announce(_ call: UmpireCall) {
        output.stopVoice()
        guard canPlay, UserDefaults.standard.object(forKey: "bm-umpire-voice-enabled") as? Bool ?? true,
            !UIAccessibility.isVoiceOverRunning
        else { return }
        output.announce(call, volume: volume)
    }
    func stopVoice() { output.stopVoice() }
    func stop() { output.stop() }
}
