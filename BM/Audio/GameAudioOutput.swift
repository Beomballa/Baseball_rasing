import AVFoundation
import UIKit

/// All AVFoundation work is confined to this queue, never the SpriteKit/main actor.
final class GameAudioOutput: @unchecked Sendable {
    private let queue: DispatchQueue
    init(queue: DispatchQueue = DispatchQueue(label: "dev.bm.audio", qos: .userInitiated)) { self.queue = queue }
    private var players: [GameSoundCue: AVAudioPlayer] = [:]
    private var voices: [GameRecording: AVAudioPlayer] = [:]
    private var sessionReady = false

    func prepare() { queue.async { self.prepareOnQueue() } }
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
                player.prepareToPlay(); players[cue] = player
            }
        }
        for recording in [GameRecording.strike, .ball, .out] {
            if let data = recording.data(), let player = try? AVAudioPlayer(data: data) {
                player.prepareToPlay(); voices[recording] = player
            }
        }
    }
    func play(_ cue: GameSoundCue, volume: Float) {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async {
            self.prepareOnQueue()
            // Slow audio startup must not produce a delayed hit/catch after the visual event.
            guard self.sessionReady, ProcessInfo.processInfo.systemUptime - requested < 0.15 else { return }
            let player = self.players[cue]
            player?.volume = volume * (cue == .crowd ? 0.65 : 1)
            player?.currentTime = 0; player?.play()
        }
    }
    func announce(_ call: UmpireCall, volume: Float) {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async {
            self.stopVoiceOnQueue(); self.prepareOnQueue()
            guard self.sessionReady, ProcessInfo.processInfo.systemUptime - requested < 0.15,
                  let player = self.voices[call.recording] else { return }
            player.volume = volume; player.currentTime = 0
            player.play(atTime: player.deviceCurrentTime + 0.14)
        }
    }
    func updateVolume(_ volume: Float) {
        queue.async {
            for (cue, player) in self.players { player.volume = volume * (cue == .crowd ? 0.65 : 1) }
            for player in self.voices.values { player.volume = volume }
        }
    }
    private func stopVoiceOnQueue() {
        for player in voices.values { player.stop(); player.currentTime = 0 }
    }
    func stopVoice() { queue.async { self.stopVoiceOnQueue() } }
    func stop(invalidateSession: Bool = false) {
        queue.async {
            self.stopVoiceOnQueue()
            for player in self.players.values { player.stop(); player.currentTime = 0 }
            if invalidateSession {
                self.sessionReady = false
                self.players.removeAll(); self.voices.removeAll()
            }
        }
    }
}
