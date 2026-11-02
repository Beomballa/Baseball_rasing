import UIKit

/// Render-only kit data. The replay worker receives immutable colors and pixels.
struct GameUniformStyle: Sendable {
    let id: String
    let pattern: String
    let body, sleeves, cap, brim, trim, ink: Int
    let mark: [UInt8]
    var pants: Int = 0xf4f0df

    func shirt(x: Double, y: Double) -> Int {
        switch pattern {
        case "pinstripe": return abs((x * 7).rounded() - x * 7) < 0.07 ? sleeves : body
        case "chest-band": return (0.27...0.43).contains(y) ? sleeves : (0.24...0.46).contains(y) ? trim : body
        case "shoulder-yoke": return y < 0.19 ? sleeves : y < 0.23 ? trim : body
        case "raglan": return abs(x - 0.5) > 0.32 - max(0, 0.3-y) ? sleeves : body
        case "retro-vest": return abs(x - 0.5) > 0.36 ? sleeves : abs(x - 0.5) > 0.33 ? trim : body
        default: return abs(x - 0.5) < 0.025 || y < 0.055 ? trim : body
        }
    }

    static func outline(for ink: Int) -> Int {
        let light = ((ink >> 16)&255)*299 + ((ink >> 8)&255)*587 + (ink&255)*114
        return light > 150_000 ? 0x14283f : 0xf5eed9
    }

    func drawMark(at center: CGPoint, unit: Int, mirrored: Bool = false, eligible: [Bool]? = nil,
                  bytes: inout [UInt8], width: Int, height: Int) {
        guard mark.count == 16*16*4 else { return }
        for row in 0..<16 { for col in 0..<16 {
            let source=(row*16+col)*4
            guard mark[source+3] > 160 else { continue }
            for dy in 0..<unit { for dx in 0..<unit {
                let x=Int(center.x)+(mirrored ? 15-col:col)*unit-8*unit+dx
                let y=Int(center.y)+row*unit-8*unit+dy
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                let target=(y*width+x)*4
                guard bytes[target+3] > 200, eligible.map({ $0[y*width+x] }) != false else { continue }
                for c in 0..<3 { bytes[target+c]=UInt8(Int(mark[source+c])*Int(bytes[target+3])/255) }
            }}
        }}
    }
}

@MainActor enum GameUniformStyles {
    private struct Entry: Decodable {
        let id: String
        let home: Kit
        let away: Kit
        let crest: Crest?
        struct Kit: Decodable { let pattern, body, sleeves, capCrown, capBrim, trim, numberColor, pants: String }
        struct Crest: Decodable { let palette: [Int]; let pixels: [String] }
    }
    private static let all: [String: GameUniformStyle] = {
        guard let data=NSDataAsset(name: "GameUniformStylesV104")?.data,
              let entries=try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.flatMap { e in
            [false,true].map { away in
            let h=away ? e.away:e.home
            var pixels=[UInt8](repeating:0,count:16*16*4)
            if let crest=e.crest {
                let rows=crest.pixels.map(Array.init)
                for y in 0..<16 { for x in 0..<16 {
                    guard rows.count > y*2, rows[y*2].count > x*2,
                          let index=Int(String(rows[y*2][x*2]), radix:36), index > 0, index < crest.palette.count else { continue }
                    let c=crest.palette[index], i=(y*16+x)*4
                    pixels[i]=UInt8((c>>16)&255);pixels[i+1]=UInt8((c>>8)&255);pixels[i+2]=UInt8(c&255);pixels[i+3]=255
                }}
            } else if let image=UIImage(named:"Club-"+e.id)?.cgImage {
                pixels.withUnsafeMutableBytes { buffer in
                    let c=CGContext(data:buffer.baseAddress,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,
                        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
                    c?.interpolationQuality = .none;c?.draw(image,in:CGRect(x:0,y:0,width:16,height:16))
                }
            }
            let key=e.id+(away ? ":away":":home")
            return (key,GameUniformStyle(id:key,pattern:h.pattern,body:SchoolCreationKit.color(h.body),
                sleeves:SchoolCreationKit.color(h.sleeves),cap:SchoolCreationKit.color(h.capCrown),
                brim:SchoolCreationKit.color(h.capBrim),trim:SchoolCreationKit.color(h.trim),
                ink:SchoolCreationKit.color(h.numberColor),mark:pixels,pants:SchoolCreationKit.color(h.pants)))
            }
        })
    }()
    static func find(_ teamID: String?, away: Bool = false) -> GameUniformStyle? {
        guard let teamID else { return nil }
        let id=ClubIdentity.resolve(name:CareerTeamDirectory.name(teamID))?.id ?? teamID
        return all[id+(away ? ":away":":home")]
    }
}

extension PlayerAppearance {
    @MainActor var opponentUniformStyle: GameUniformStyle? { GameUniformStyles.find(opponentUniformTeamID, away: !uniformAway) }
    @MainActor var opponentUniformColor: Int { GameUniformPalette.color(teamID: opponentUniformTeamID) ?? FieldReplayPresentation.opponentKit(uniformColor) }
    @MainActor var uniformStyle: GameUniformStyle? { GameUniformStyles.find(uniformTeamID ?? schoolKitID, away:uniformAway) }
}
