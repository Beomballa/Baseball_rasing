import AVFoundation
import UIKit

enum GameSoundCue: CaseIterable {
    case contact, catchBall, confirm, crowd
    var recording: GameRecording? {
        switch self {case .contact: .contact; case .catchBall: .catchBall; case .crowd: .crowd; case .confirm: nil}
    }
}

enum GameRecording: String, CaseIterable {
    case contact = "BaseballContactV110", catchBall = "BaseballCatchV110", crowd = "BaseballCrowdV110"
    case strike = "UmpireStrikeV110", ball = "UmpireBallV110", out = "UmpireOutV110"
    func data(bundle: Bundle = .main) -> Data? { NSDataAsset(name: rawValue, bundle: bundle)?.data }
}

enum UmpireCall: String, CaseIterable {
    case strike = "스트라이크"
    case ball = "볼"
    case strikeout = "삼진"
    case walk = "볼넷"
    case out = "타구 아웃"

    // The recordings say Strike / Ball / You're out. Detailed outcomes remain Korean captions.
    var recording: GameRecording {
        switch self {case .strike: .strike; case .ball, .walk: .ball; case .strikeout, .out: .out}
    }
    static func resolvedField(outsAdded: Int) -> Self? { outsAdded > 0 ? .out : nil }

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

/// Only the non-baseball UI confirmation remains synthesized.
enum GameSoundPCM {
    static let sampleRate = 22_050
    static func confirmation() -> Data {
        let duration: Double = 0.10
        let count=Int(Double(sampleRate)*duration)
        var samples=Data()
        for i in 0..<count {
            let t=Double(i)/Double(sampleRate), p=Double(i)/Double(count)
            let wave=sin(t*2*Double.pi*(p < 0.5 ? 660:880))*sin(p*Double.pi)*0.3
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
    private var voices: [GameRecording: AVAudioPlayer] = [:]
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private var observers: [NSObjectProtocol] = []
    private init() {
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
            let data = cue == .confirm ? GameSoundPCM.confirmation() : cue.recording?.data()
            if let data, let player=try? AVAudioPlayer(data:data) {player.prepareToPlay();players[cue]=player}
        }
        for recording in [GameRecording.strike, .ball, .out] {
            if let data=recording.data(),let player=try? AVAudioPlayer(data:data) {player.prepareToPlay();voices[recording]=player}
        }
        impact.prepare()
    }
    private var canPlay: Bool {
        (UserDefaults.standard.object(forKey: "bm-sound-enabled") as? Bool ?? true) && active
    }
    private var active: Bool {UIApplication.shared.applicationState == .active && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil}
    static func volume(_ stored: Double?) -> Float {
        guard let stored,stored.isFinite else {return 0.9}
        return Float(max(0,min(1,stored)))
    }
    private var volume: Float {Self.volume(UserDefaults.standard.object(forKey:"bm-sound-volume") as? Double)}
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
        players[cue]?.volume=volume * (cue == .crowd ? 0.65 : 1)
        players[cue]?.currentTime=0;players[cue]?.play()
    }
    func contact() {
        if active,UserDefaults.standard.object(forKey:"bm-haptics-enabled") as? Bool ?? true {
            impact.impactOccurred(intensity:0.9);impact.prepare()
        }
        play(.contact)
    }
    func updateVolume() {
        for (cue,player) in players {player.volume=volume * (cue == .crowd ? 0.65 : 1)}
        for player in voices.values {player.volume=volume}
    }
    func announce(outcome: String) {
        guard let call = UmpireCall(outcome: outcome) else { return }
        announce(call)
    }
    func announce(_ call: UmpireCall) {
        // Do not queue an old call behind the next pitch or compete with VoiceOver.
        stopVoice()
        guard canPlay, UserDefaults.standard.object(forKey: "bm-umpire-voice-enabled") as? Bool ?? true,
              !UIAccessibility.isVoiceOverRunning, configureSession() else { return }
        prepare()
        guard let player=voices[call.recording] else {return}
        player.volume=volume;player.currentTime=0
        player.play(atTime:player.deviceCurrentTime+0.14)
    }
    func stopVoice() { for player in voices.values {player.stop();player.currentTime=0} }
    func stop() {
        stopVoice()
        for player in players.values { player.stop();player.currentTime=0 }
    }
}
