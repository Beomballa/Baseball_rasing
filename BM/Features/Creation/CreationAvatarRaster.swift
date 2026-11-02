import SwiftUI
import UIKit

@MainActor struct SchoolCreationKit: Decodable {
    let id: String
    let wordmark: String
    let primary: String
    let accent: String
    let home: Home
    struct Home: Decodable {
        let pattern: String
        let body: String
        let capCrown: String
        let capBrim: String
    }
    static let all: [SchoolCreationKit] = {
        guard let data = NSDataAsset(name: "CreationSchoolKitsV98")?.data else { return [] }
        return (try? JSONDecoder().decode([SchoolCreationKit].self, from: data)) ?? []
    }()
    static func find(_ id: String?) -> SchoolCreationKit? { all.first { $0.id == id } }
    static func color(_ hex: String) -> Int { Int(hex.dropFirst(), radix: 16) ?? 0x214e72 }
}

// Shared V93 primary palette; full match kit details are resolved by GameUniformStyles.
@MainActor enum GameUniformPalette {
    private struct Entry: Decodable { let id: String; let primary: String }
    private static let colors: [String: Int] = {
        guard let data = NSDataAsset(name: "GameUniformColorsV102")?.data,
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, SchoolCreationKit.color($0.primary)) })
    }()
    static func color(teamID: String?) -> Int? {
        guard let teamID else { return nil }
        let catalogID = ClubIdentity.resolve(name: CareerTeamDirectory.name(teamID))?.id ?? teamID
        return colors[catalogID]
    }
}
extension PlayerAppearance {
    @MainActor var uniformColor: Int {
        GameUniformPalette.color(teamID: uniformTeamID ?? schoolKitID) ?? Self.kitColors[kit]
    }
}

enum CreationAvatarMode: String { case head, portrait, full }

struct CreationAvatarImage: View {
    let appearance: PlayerAppearance
    var role: PlayerRole = .batter
    var number: Int = 10
    var cap = false
    var mode = CreationAvatarMode.head
    @State private var image: UIImage?
    private var key: String { CreationAvatarRaster.key(appearance, role: role, number: number, cap: cap, mode: mode) }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit() }
            else { Color.clear }
        }.accessibilityHidden(true)
            .task(id: key) { image = CreationAvatarRaster.image(appearance, role: role, number: number, cap: cap, mode: mode) }
    }
}

/// Generated layers are cropped by measured atlas cells; selections never write a career record here.
@MainActor enum CreationAvatarRaster {
    private static let cache: NSCache<NSString, UIImage> = { let v = NSCache<NSString, UIImage>(); v.countLimit = 96; return v }()
    private static let hairCells = [0, 3, 7, 1, 2, 4, 5, 6]
    static func key(_ a: PlayerAppearance, role: PlayerRole, number: Int, cap: Bool, mode: CreationAvatarMode) -> String {
        [mode.rawValue, role.rawValue, String(number), String(cap), String(a.skin), String(a.hair),
         String(a.kit), String(a.hairStyle), String(a.expression), String(a.eyeIndex), String(a.browIndex), a.schoolKitID ?? "legacy", a.uniformTeamID ?? "", String(a.uniformAway)].joined(separator: ":")
    }
    static func image(_ a: PlayerAppearance, role: PlayerRole = .batter, number: Int = 10,
                      cap: Bool = false, mode: CreationAvatarMode = .head) -> UIImage? {
        guard a.isValid else { return nil }
        let key = key(a, role: role, number: number, cap: cap, mode: mode) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let head = head(a, cap: cap) else { return nil }
        if mode == .head { cache.setObject(head, forKey: key); return head }
        guard let raw = UIImage(named: role == .pitcher || mode == .portrait ? "CreationPitcherBodyV98" : "CreationBodyV98")?.cgImage,
              let body = recolor(raw, appearance: a, body: true) else { return nil }
        let kit = SchoolCreationKit.find(a.uniformTeamID ?? a.schoolKitID)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let size = mode == .full ? CGSize(width: 256, height: 384) : CGSize(width: 256, height: 280)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let c = renderer.cgContext; c.interpolationQuality = .none
            let bodyRect: CGRect, headRect: CGRect
            if mode == .full {
                bodyRect = CGRect(x: 0, y: role == .pitcher ? 38 : 43, width: 256, height: 341)
                headRect = CGRect(x: 58, y: 0, width: 140, height: 132)
            } else {
                bodyRect = CGRect(x: -102, y: 68, width: 460, height: 614)
                headRect = CGRect(x: 0, y: 0, width: 256, height: 241)
            }
            body.draw(in: bodyRect)
            if let style = a.uniformStyle {
                crest(style, rect: CGRect(x: bodyRect.minX + bodyRect.width * 0.38, y: bodyRect.minY + bodyRect.height * 0.33,
                    width: bodyRect.width * 0.07, height: bodyRect.width * 0.07), in: c)
            }
            let club = ClubIdentity.all.first { $0.id == a.uniformStyle?.id.components(separatedBy: ":").first }
            let title = kit?.wordmark ?? club?.name.components(separatedBy: " ").last ?? ""
            let font = UIFont(name: "NeoDunggeunmo", size: bodyRect.width * 0.042) ?? .boldSystemFont(ofSize: bodyRect.width * 0.042)
            let ink = UIColor(Color(hex: a.uniformStyle?.ink ?? 0x14283f))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let text = title as NSString, measured = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bodyRect.midX - measured.width / 2, y: bodyRect.minY + bodyRect.height * 0.39), withAttributes: attrs)
            (String(number) as NSString).draw(at: CGPoint(x: bodyRect.midX + bodyRect.width * 0.08,
                y: bodyRect.minY + bodyRect.height * 0.43), withAttributes: attrs)
            head.draw(in: headRect)
        }
        cache.setObject(image, forKey: key); return image
    }
    private static func head(_ a: PlayerAppearance, cap: Bool) -> UIImage? {
        guard let atlas = UIImage(named: "CreationHeadsV98")?.cgImage,
              let features = UIImage(named: "CreationFeaturesV98")?.cgImage else { return nil }
        let cell = hairCells[a.hairStyle], col = cell % 4
        let left = Int((Double(col) * Double(atlas.width) / 4).rounded())
        let right = Int((Double(col + 1) * Double(atlas.width) / 4).rounded())
        guard let crop = atlas.cropping(to: CGRect(x: left, y: cell < 4 ? 50 : 467, width: right-left, height: 417)),
              let tinted = recolor(crop, appearance: a, body: false) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 241), format: format).image { renderer in
            renderer.cgContext.interpolationQuality = .none
            tinted.draw(in: CGRect(x: 0, y: 0, width: 256, height: 241))
            func feature(row: Int, col: Int, inner: CGRect, destination: CGRect) {
                let x = (Double(col) * Double(features.width) / 6).rounded()
                let y = (Double(row) * Double(features.height) / 3).rounded()
                guard let image = features.cropping(to: inner.offsetBy(dx: x, dy: y)) else { return }
                UIImage(cgImage: image).draw(in: destination)
            }
            feature(row: 0, col: a.eyeIndex, inner: CGRect(x: 50, y: 130, width: 200, height: 95),
                destination: CGRect(x: 91, y: 112, width: 112, height: 43))
            feature(row: 1, col: a.browIndex, inner: CGRect(x: 40, y: 115, width: 220, height: 90),
                destination: CGRect(x: 87, y: 96, width: 119, height: 34))
            feature(row: 2, col: a.expression, inner: CGRect(x: 78, y: 108, width: 145, height: 95),
                destination: a.expression < 2 ? CGRect(x: 137, y: 170, width: 38, height: 16) : CGRect(x: 131, y: 162, width: 52, height: 32))
            if cap, let raw = UIImage(named: "CreationCapV98")?.cgImage,
               let capImage = recolor(raw, appearance: a, body: false, isCap: true) {
                capImage.draw(in: CGRect(x: 0, y: -38, width: 263, height: 175))
                if let style = a.uniformStyle {
                    crest(style, rect: CGRect(x: 126, y: 8, width: 29, height: 29), in: renderer.cgContext)
                }
            }
        }
    }
    private static func recolor(_ source: CGImage, appearance a: PlayerAppearance, body: Bool, isCap: Bool = false) -> UIImage? {
        let w = body ? 256 : 320, h = max(1, Int(Double(source.height) / Double(source.width) * Double(w)))
        var bytes = [UInt8](repeating: 0, count: w*h*4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let space = CGColorSpaceCreateDeviceRGB()
        let ok = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let c = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: space, bitmapInfo: info) else { return false }
            c.interpolationQuality = .none; c.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard ok else { return nil }
        let kit = SchoolCreationKit.find(a.uniformTeamID ?? a.schoolKitID)
        let style = a.uniformStyle
        let primary = style?.sleeves ?? kit.map { SchoolCreationKit.color($0.primary) } ?? PlayerAppearance.kitColors[a.kit]
        for p in 0..<(w*h) {
            let i = p*4, alpha = Int(bytes[i+3]); if alpha < 24 { continue }
            let r = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
            let x = Double(p % w)/Double(w), y = Double(p / w)/Double(h)
            var tint: Int?, shade = 1.0
            if isCap {
                if b > 48 && b > r*12/10 && max(r,max(g,b)) > 55 { tint = y > 0.58 ? style?.brim ?? primary:style?.cap ?? primary; shade = Double(b)/115 }
            } else if !body {
                if r > 115 && r > g*11/10 && g > b*11/10 { tint = PlayerAppearance.skinColors[a.skin]; shade = Double(r)/239 }
                else if r > 28 && r < 145 && r > g*12/10 && g > b { tint = PlayerAppearance.hairColors[a.hair]; shade = Double(r)/104 }
            } else {
                let skinRegion = (y > 0.20 && y < 0.29 && x > 0.40 && x < 0.65)
                    || (y > 0.43 && y < 0.57 && x < 0.43) || (y > 0.25 && y < 0.44 && x > 0.69)
                if skinRegion && r > 185 && r > g*12/10 && g > b*11/10 { tint = PlayerAppearance.skinColors[a.skin]; shade = Double(r)/245 }
                else if y < 0.48 && b > 55 && b > r*13/10 && b > g*11/10 { tint = primary; shade = Double(b)/110 }
                else if let style, r > 145 && g > 145 && b > 135 && abs(r-g) < 45 && y > 0.26 && y < 0.48 {
                    tint = style.shirt(x:x,y:(y-0.26)/0.22); shade = Double(r)/245
                } else if let style, r > 145 && g > 145 && b > 135 && abs(r-g) < 45 && y >= 0.48 && y < 0.81 {
                    tint = style.pants; shade = Double(r)/245
                }
            }
            if let tint {
                for ch in 0..<3 {
                    let value = Double((tint >> (16-ch*8)) & 255) * min(1.45, max(0.25, shade))
                    bytes[i+ch] = UInt8(min(alpha, max(0, Int(value))))
                }
            }
        }
        let cg = bytes.withUnsafeMutableBytes { ptr in
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: space, bitmapInfo: info)?.makeImage()
        }
        return cg.map { UIImage(cgImage: $0) }
    }
    private static func crest(_ style: GameUniformStyle, rect: CGRect, in c: CGContext) {
        guard style.mark.count == 16*16*4 else { return }
        for y in 0..<16 { for x in 0..<16 {
            let i=(y*16+x)*4
            guard style.mark[i+3]>160 else { continue }
            let color=(Int(style.mark[i])<<16)|(Int(style.mark[i+1])<<8)|Int(style.mark[i+2])
            c.setFillColor(UIColor(Color(hex:color)).cgColor)
            c.fill(CGRect(x:rect.minX+CGFloat(x)*rect.width/16,y:rect.minY+CGFloat(y)*rect.height/16,width:rect.width/16,height:rect.height/16))
        }}
    }
}
