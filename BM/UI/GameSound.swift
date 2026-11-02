import AVFoundation
import UIKit

enum GameSoundCue: CaseIterable { case contact, catchBall, confirm }

enum UmpireCall: String, CaseIterable {
    case strike = "스트라이크"
    case ball = "볼"
    case strikeout = "삼진"
    case walk = "볼넷"

    init?(outcome: String) {
        switch outcome {
        case "루킹 스트라이크", "헛스윙": self = .strike
        case "볼": self = .ball
        case "삼진": self = .strikeout
        case "볼넷": self = .walk
        default: return nil
        }
    }
}

/// Original synthesized effects: no downloaded recording, network, or gameplay RNG.
enum GameSoundPCM {
    static let sampleRate = 22_050
    static func wave(_ cue: GameSoundCue) -> Data {
        let duration: Double = cue == .confirm ? 0.10 : cue == .contact ? 0.28 : 0.24
        let count=Int(Double(sampleRate)*duration)
        var samples=Data(), noise: UInt32=0xBACE104
        for i in 0..<count {
            let t=Double(i)/Double(sampleRate), p=Double(i)/Double(count)
            noise=noise &* 1664525 &+ 1013904223
            let n=Double(noise & 0xffff)/32767.5-1
            let wave: Double
            switch cue {
            case .contact:
                let crack = n * 0.72 * exp(-t * 310)
                let wood = (sin(t * 2 * .pi * 880) * 0.22 + sin(t * 2 * .pi * 1740) * 0.16) * exp(-t * 48)
                let body = sin(t * 2 * .pi * 210) * 0.23 * exp(-t * 30)
                wave = (crack + wood + body) * min(1, t * 8000) * (1 - p)
            case .catchBall:
                let thump = sin(2 * .pi * (180 * t - 140 * t * t)) * 0.62 * exp(-t * 34)
                let leather = n * 0.32 * exp(-t * 78)
                wave = (thump + leather) * min(1, t * 4000) * (1 - p)
            case .confirm: wave=sin(t*2*Double.pi*(p < 0.5 ? 660:880))*sin(p*Double.pi)*0.3
            }
            var value=Int16(max(-32767,min(32767,Int(wave*16000)))).littleEndian
            withUnsafeBytes(of:&value) { samples.append(contentsOf:$0) }
        }
        var result=Data("RIFF".utf8)
        func word<T: FixedWidthInteger>(_ value:T) { var v=value.littleEndian;withUnsafeBytes(of:&v) {result.append(contentsOf:$0)} }
        word(UInt32(36+samples.count));result.append(Data("WAVEfmt ".utf8));word(UInt32(16))
        word(UInt16(1));word(UInt16(1));word(UInt32(sampleRate));word(UInt32(sampleRate*2));word(UInt16(2));word(UInt16(16))
        result.append(Data("data".utf8));word(UInt32(samples.count));result.append(samples)
        return result
    }
}

@MainActor final class GameSound {
    static let shared = GameSound()
    private var players: [GameSoundCue: AVAudioPlayer] = [:]
    private let speech = AVSpeechSynthesizer()
    private var observers: [NSObjectProtocol] = []
    private init() {
        speech.usesApplicationAudioSession = true
        for name in [UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification,
                     UIAccessibility.voiceOverStatusDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
        }
    }
    func prepare() {
        guard players.isEmpty else { return }
        for cue in GameSoundCue.allCases {
            if let player=try? AVAudioPlayer(data:GameSoundPCM.wave(cue)) {player.volume=0.45;player.prepareToPlay();players[cue]=player}
        }
    }
    private var canPlay: Bool {
        (UserDefaults.standard.object(forKey: "bm-sound-enabled") as? Bool ?? true)
            && UIApplication.shared.applicationState == .active
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
    private func configureSession() -> Bool {
        // Voice and effects share the ambient session, including the hardware silent switch.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            return true
        } catch { return false }
    }
    func play(_ cue: GameSoundCue) {
        guard canPlay else { return }
        prepare()
        guard configureSession() else { return }
        players[cue]?.currentTime=0;players[cue]?.play()
    }
    func announce(outcome: String) {
        guard let call = UmpireCall(outcome: outcome) else { return }
        announce(call)
    }
    func announce(_ call: UmpireCall) {
        // Do not queue an old call behind the next pitch or compete with VoiceOver.
        stopVoice()
        guard canPlay, UserDefaults.standard.object(forKey: "bm-umpire-voice-enabled") as? Bool ?? true,
              !UIAccessibility.isVoiceOverRunning,
              let voice = AVSpeechSynthesisVoice(language: "ko-KR"), configureSession() else { return }
        let utterance = AVSpeechUtterance(string: call.rawValue)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 0.9
        utterance.volume = 0.85
        utterance.preUtteranceDelay = 0.18
        speech.speak(utterance)
    }
    func stopVoice() { speech.stopSpeaking(at: .immediate) }
    func stop() {
        stopVoice()
        for player in players.values { player.stop();player.currentTime=0 }
    }
}
