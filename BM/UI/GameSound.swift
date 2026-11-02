import AVFoundation
import UIKit

enum GameSoundCue: CaseIterable { case contact, catchBall, confirm }

/// Original synthesized effects: no downloaded recording, network, or gameplay RNG.
enum GameSoundPCM {
    static let sampleRate = 22_050
    static func wave(_ cue: GameSoundCue) -> Data {
        let duration: Double = cue == .confirm ? 0.10 : cue == .contact ? 0.12 : 0.16
        let count=Int(Double(sampleRate)*duration)
        var samples=Data(), noise: UInt32=0xBACE104
        for i in 0..<count {
            let t=Double(i)/Double(sampleRate), p=Double(i)/Double(count)
            noise=noise &* 1664525 &+ 1013904223
            let n=Double(noise & 0xffff)/32767.5-1
            let wave: Double
            switch cue {
            case .contact: wave=(n*0.7+sin(t*2*Double.pi*860)*0.3)*exp(-p*16)
            case .catchBall: wave=(n*0.22+sin(t*2*Double.pi*160)*0.6)*exp(-p*10)
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
    private var observers: [NSObjectProtocol] = []
    private init() {
        for name in [UIApplication.didEnterBackgroundNotification, AVAudioSession.interruptionNotification] {
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
    func play(_ cue: GameSoundCue) {
        guard UserDefaults.standard.object(forKey:"bm-sound-enabled") as? Bool ?? true,
              UIApplication.shared.applicationState == .active,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        prepare()
        // Ambient respects the hardware silent switch and does not stop other audio.
        guard (try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default,options:[.mixWithOthers])) != nil else { return }
        players[cue]?.currentTime=0;players[cue]?.play()
    }
    func stop() { for player in players.values { player.stop();player.currentTime=0 } }
}
