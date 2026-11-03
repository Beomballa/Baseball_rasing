import AVFoundation
import UIKit

/// 음원 준비·재생 상태는 아래 작업 대기열에서 한 번에 하나씩 접근한다.
/// 컴파일러 대신 개발자가 동시 접근 안전성을 보장한다. 외부에서 전달하는 대기열도 순차 실행 방식이어야 한다.
final class GameAudioOutput: @unchecked Sendable {
    private let queue: DispatchQueue
    /// 테스트용 대기열도 순차 실행 방식으로 지정하며, 재생 상태는 이 대기열 안에서만 변경한다.
    init(queue: DispatchQueue = DispatchQueue(label: "dev.bm.audio", qos: .userInitiated)) { self.queue = queue }
    private var players: [GameSoundCue: AVAudioPlayer] = [:]
    private var voices: [GameRecording: AVAudioPlayer] = [:]
    private var sessionReady = false
    // 화면 사건보다 0.15초 이상 늦어진 요청은 버려 뒤늦은 타격·포구음을 방지한다.
    private static let maximumRequestAge: TimeInterval = 0.15
    // 포구 효과음 다음에 심판 콜이 들리도록 기존 0.14초 간격을 유지한다.
    private static let umpireDelay: TimeInterval = 0.14
    private static let crowdVolumeRatio: Float = 0.65

    func prepare() { queue.async { self.prepareOnQueue() } }
    /// 세션과 플레이어를 재사용한다. 오디오 오류가 나도 경기 진행은 막지 않는다.
    private func prepareOnQueue() {
        if !sessionReady {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                sessionReady = true
            } catch { return }
        }
        guard players.isEmpty else { return }
        for cue in GameSoundCue.allCases {
            let data = cue == .confirm ? GameSoundPCM.confirmation() : cue.recording?.data()
            if let data, let player = try? AVAudioPlayer(data: data) {
                player.prepareToPlay()
                players[cue] = player
            }
        }
        for recording in [GameRecording.strike, .ball, .out] {
            if let data = recording.data(), let player = try? AVAudioPlayer(data: data) {
                player.prepareToPlay()
                voices[recording] = player
            }
        }
    }
    /// 효과음을 작업 대기열에 예약하며 화면 사건보다 늦어진 요청은 건너뛴다.
    func play(_ cue: GameSoundCue, volume: Float) {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async {
            self.prepareOnQueue()
            // 초기화가 지연되면 화면과 어긋난 소리를 뒤늦게 재생하지 않는다.
            guard self.sessionReady, ProcessInfo.processInfo.systemUptime - requested < Self.maximumRequestAge else {
                return
            }
            let player = self.players[cue]
            player?.volume = Self.effectVolume(volume, for: cue)
            player?.currentTime = 0
            player?.play()
        }
    }
    /// 이전 콜을 중지하고 포구음 뒤에 새 콜을 예약한다.
    func announce(_ call: UmpireCall, volume: Float) {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async {
            self.stopVoiceOnQueue()
            self.prepareOnQueue()
            guard self.sessionReady, ProcessInfo.processInfo.systemUptime - requested < Self.maximumRequestAge,
                let player = self.voices[call.recording]
            else { return }
            player.volume = volume
            player.currentTime = 0
            player.play(atTime: player.deviceCurrentTime + Self.umpireDelay)
        }
    }
    func updateVolume(_ volume: Float) {
        queue.async {
            for (cue, player) in self.players { player.volume = Self.effectVolume(volume, for: cue) }
            for player in self.voices.values { player.volume = volume }
        }
    }
    /// 관중 소리가 타격·심판 콜을 덮지 않도록 기존 음량 비율을 적용한다.
    private static func effectVolume(_ volume: Float, for cue: GameSoundCue) -> Float {
        volume * (cue == .crowd ? crowdVolumeRatio : 1)
    }
    private func stopVoiceOnQueue() {
        for player in voices.values {
            player.stop()
            player.currentTime = 0
        }
    }
    func stopVoice() { queue.async { self.stopVoiceOnQueue() } }
    /// 중단 시 재생을 멈춘다. 세션 무효화가 필요하면 다음 준비에서 플레이어도 다시 만든다.
    func stop(invalidateSession: Bool = false) {
        queue.async {
            self.stopVoiceOnQueue()
            for player in self.players.values {
                player.stop()
                player.currentTime = 0
            }
            if invalidateSession {
                self.sessionReady = false
                self.players.removeAll()
                self.voices.removeAll()
            }
        }
    }
}
