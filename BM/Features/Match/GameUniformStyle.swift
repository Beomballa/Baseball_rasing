import UIKit

struct ProUniformDesign: Decodable, Sendable {
    enum Cut: String, Decodable, Sendable {
        case vest, orbit, gale, button, rail, yoke, raglan, band, pinstripe, diagonal, split, collar
    }
    enum Cuff: String, Decodable, Sendable { case plain, single, double }
    enum Pants: String, Decodable, Sendable { case full, tapered, knicker }
    enum LegStripe: String, Decodable, Sendable { case none, single, double, oneSide }
    enum Socks: String, Decodable, Sendable { case solid, single, double, stirrup }

    let label: String
    let cut: Cut
    let cuff: Cuff
    let pantsStyle: Pants
    let legStripe: LegStripe
    let sockStyle: Socks
    let body, sleeves, trim, pants, socks, cap, brim, ink: String
}

/// Render-only kit data. The replay worker receives immutable colors and pixels.
struct GameUniformStyle: Sendable {
    let id: String
    let pattern: String
    let body, sleeves, cap, brim, trim, ink: Int
    let mark: [UInt8]
    var pants: Int = 0xf4f0df
    var socks: Int = 0x162d30
    var pro: ProUniformDesign?
    var gear: Int?

    func shirt(x: Double, y: Double, back: Bool = false, mirrored: Bool = false) -> Int {
        if let pro {
            let side = back != mirrored ? 1 - x : x
            let center = abs(x - 0.5)
            switch pro.cut {
            case .vest:
                if center > 0.35 { return sleeves }
                if center > 0.31 || y < 0.07 || (!back && center < 0.025) { return trim }
            case .orbit:
                if y < 0.10 + center * center * 1.5 { return trim }
            case .gale:
                let seam = 0.10 + (0.7 - side) * 0.60
                if y < seam { return sleeves }
                if y < seam + 0.06 { return trim }
            case .button:
                if y < 0.065 || (!back && center < 0.027) { return trim }
            case .rail:
                if center > 0.36 { return sleeves }
                if (0.26...0.30).contains(center) || (0.33...0.36).contains(center) { return trim }
            case .yoke:
                if y < 0.22 { return sleeves }
                if y < 0.28 { return trim }
            case .raglan:
                let seam = 0.22 + max(0, y) * 0.21
                if center > seam { return sleeves }
                if center > seam - 0.035 { return trim }
            case .band:
                if (0.28...0.44).contains(y) { return sleeves }
                if (0.24...0.48).contains(y) { return trim }
            case .pinstripe:
                if abs((x * 6).rounded() - x * 6) < 0.12 { return sleeves }
                if y < 0.065 { return trim }
            case .diagonal:
                let seam = 0.20 + side * 0.51
                if abs(y - seam) < 0.046 { return trim }
                if y < seam { return sleeves }
            case .split:
                if side < 0.19 { return sleeves }
                if side < 0.245 { return trim }
            case .collar:
                if y < 0.19 - center * 0.34 { return trim }
            }
            return body
        }
        switch pattern {
        case "pinstripe": return abs((x * 7).rounded() - x * 7) < 0.07 ? sleeves : body
        case "chest-band": return (0.27...0.43).contains(y) ? sleeves : (0.24...0.46).contains(y) ? trim : body
        case "shoulder-yoke": return y < 0.19 ? sleeves : y < 0.23 ? trim : body
        case "raglan": return abs(x - 0.5) > 0.32 - max(0, 0.3-y) ? sleeves : body
        case "retro-vest": return abs(x - 0.5) > 0.36 ? sleeves : abs(x - 0.5) > 0.33 ? trim : body
        default: return abs(x - 0.5) < 0.025 || y < 0.055 ? trim : body
        }
    }

    func sleeve(base: Int, y: Double) -> Int {
        guard let pro else { return base }
        let band = sleeves == trim ? body : trim
        switch pro.cuff {
        case .plain: return sleeves
        case .single: return y > 0.78 ? band : sleeves
        case .double: return y > 0.89 || (0.69...0.79).contains(y) ? band : sleeves
        }
    }

    /// x is relative to the outside seams of the trousers, y to the hip-to-hem span.
    func leg(base: Int, x: Double, y: Double, back: Bool = false, mirrored: Bool = false) -> Int {
        guard let pro else { return base }
        let side = back != mirrored ? 1 - x : x
        let edge = min(x, 1 - x)
        switch pro.legStripe {
        case .none: return pants
        case .single: return (0.035...0.105).contains(edge) ? trim : pants
        case .double: return (0.025...0.075).contains(edge) || (0.10...0.14).contains(edge) ? trim : pants
        case .oneSide: return y < 0.92 && (0.03...0.115).contains(side) ? trim : pants
        }
    }

    func sock(base: Int, y: Double) -> Int {
        guard let pro else { return base }
        // The authored lower-leg fabric is shared by all cuts. Move the hem within it.
        let hem: Double
        switch pro.pantsStyle {
        case .full: hem = 0.64
        case .tapered: hem = 0.32
        case .knicker: hem = 0
        }
        if y < hem { return pants }
        let band = (y - hem) / (1 - hem)
        let accent = pro.sockStyle == .stirrup ? 0xf5eacf : trim == socks ? pants : trim
        switch pro.sockStyle {
        case .solid: return socks
        case .single: return (0.17...0.38).contains(band) ? accent : socks
        case .double, .stirrup:
            if (0.13...0.30).contains(band) || (0.39...0.55).contains(band) { return accent }
            if pro.sockStyle == .stirrup && (0.73...0.91).contains(band) { return pants }
            return socks
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
    private struct ProEntry: Decodable {
        let id: String
        let home, away: ProUniformDesign
    }

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
        let designs = NSDataAsset(name: "ProUniformDesignsV148").flatMap {
            try? JSONDecoder().decode([ProEntry].self, from: $0.data)
        } ?? []
        let proByID = Dictionary(designs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
            let design = proByID[e.id].map { away ? $0.away : $0.home }
            return (key,GameUniformStyle(id:key,pattern:h.pattern,body:SchoolCreationKit.color(design?.body ?? h.body),
                sleeves:SchoolCreationKit.color(design?.sleeves ?? h.sleeves),cap:SchoolCreationKit.color(design?.cap ?? h.capCrown),
                brim:SchoolCreationKit.color(design?.brim ?? h.capBrim),trim:SchoolCreationKit.color(design?.trim ?? h.trim),
                ink:SchoolCreationKit.color(design?.ink ?? h.numberColor),mark:pixels,pants:SchoolCreationKit.color(design?.pants ?? h.pants),
                socks:design.map { SchoolCreationKit.color($0.socks) } ?? 0x162d30,pro:design,
                gear:design == nil ? nil : SchoolCreationKit.color(h.sleeves)))
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
