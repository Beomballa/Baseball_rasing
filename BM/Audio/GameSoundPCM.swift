import Foundation

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
