import Foundation

/// 야구 효과음은 녹음을 사용하고 UI 확인음만 짧은 PCM으로 합성한다.
enum GameSoundPCM {
    static let sampleRate = 22_050
    /// 같은 입력 없이도 항상 동일한 16비트 모노 WAV를 만든다. 경기 RNG는 사용하지 않는다.
    static func confirmation() -> Data {
        let duration: Double = 0.10
        let count = Int(Double(sampleRate) * duration)
        var samples = Data()
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let p = Double(i) / Double(count)
            let wave = sin(t * 2 * Double.pi * (p < 0.5 ? 660 : 880)) * sin(p * Double.pi) * 0.3
            var value = Int16(max(-32767, min(32767, Int(wave * 16000)))).littleEndian
            withUnsafeBytes(of: &value) { samples.append(contentsOf: $0) }
        }
        // WAV 헤더의 길이와 샘플 값을 리틀엔디언 순서로 기록한다.
        var result = Data("RIFF".utf8)
        func word<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { result.append(contentsOf: $0) }
        }
        word(UInt32(36 + samples.count))
        result.append(Data("WAVEfmt ".utf8))
        word(UInt32(16))
        word(UInt16(1))
        word(UInt16(1))
        word(UInt32(sampleRate))
        word(UInt32(sampleRate * 2))
        word(UInt16(2))
        word(UInt16(16))
        result.append(Data("data".utf8))
        word(UInt32(samples.count))
        result.append(samples)
        return result
    }
}
