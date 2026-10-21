import SwiftUI
import UIKit
import SpriteKit

// Presentation geometry never changes the saved pitch, timing window or RNG.
enum MatchArt {
    static let names = ["batter-view-clean", "stadium-clean", "batter-actions", "pitcher-delivery-v2", "catcher-parts",
                        "grip-fastball", "grip-slider", "grip-changeup", "grips-extra"]
    private static let images: [String: UIImage] = Dictionary(uniqueKeysWithValues: names.compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MatchArt"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return (name, image)
    })
    static func image(_ name: String) -> UIImage? { images[name] }
    static func cell(_ name: String, column: Int, row: Int, columns: Int, rows: Int) -> UIImage? {
        guard let source = image(name)?.cgImage,
              let crop = source.cropping(to: CGRect(x: column * source.width / columns, y: row * source.height / rows,
                                                   width: source.width / columns, height: source.height / rows)) else { return nil }
        return UIImage(cgImage: crop)
    }
}

enum MatchPresentation {
    static func batContact(action: String) -> CGPoint {
        let bunt = action == "bunt"
        let feet = bunt ? 471.0 : 503.0
        return CGPoint(x: -0.005 + 0.62 * (bunt ? 416 : 426) / 512,
                       y: 0.34 + 0.61 * (1 - feet / 512) + 0.61 * (bunt ? 245 : 266) / 512)
    }
    static func fieldSize(available: CGSize, role: PlayerRole, chromeHeight: CGFloat = 310) -> CGSize {
        let ratio: CGFloat = role == .batter ? 1 : 1219 / 1290
        let height = min(max(150, available.height - chromeHeight), max(1, available.width) / ratio)
        return CGSize(width: height * ratio, height: height)
    }
    static func countPulse(_ outcome: String?) -> String? {
        switch outcome {
        case "볼", "볼넷": "B"
        case "루킹 스트라이크", "헛스윙", "삼진": "S"
        default: nil
        }
    }
    static func pitchName(_ result: ManualMatchResult?) -> String {
        guard let result else { return "투구 대기" }
        let names = ["four-seam": "포심", "slider": "슬라이더", "changeup": "체인지업", "fork": "포크"]
        return result.pitchCode.flatMap { names[$0] } ?? "구종 미기록"
    }
}

enum MatchBallPath {
    static func point(from start: CGPoint, to end: CGPoint, size: CGSize, role: PlayerRole,
                      hand: String, code: String, progress: Double) -> CGPoint {
        let t = min(1, max(0, progress))
        let depth = role == .batter ? t / (2.4 - 1.4 * t) : 2.4 * t / (1 + 1.4 * t)
        let bend = depth * depth - depth
        let lateral = (code == "slider" ? 0.07 : code == "changeup" ? -0.04 : 0) * (hand == "left" ? -1.0 : 1)
        let drop = code == "fork" ? 0.13 : code == "changeup" ? 0.08 : 0.025
        return CGPoint(x: start.x + (end.x - start.x) * depth + lateral * size.width * bend,
                       y: start.y + (end.y - start.y) * depth - drop * size.height * bend)
    }
}

struct MatchPixelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var selected = false
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .monospaced, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: primary ? 48 : 44)
            .foregroundStyle(enabled ? Color(hex: 0xf3edcf) : Color(hex: 0x9aacb7))
            .background(selected || primary ? Color(hex: 0x307855) : Color(hex: 0x203e57))
            .overlay(Rectangle().strokeBorder(selected ? GameTheme.gold : Color(hex: 0x7695a6), lineWidth: 2))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.25)).frame(height: 3) }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}

struct MatchScoreStrip: View {
    let match: CareerMatch
    let pitchCount: Int?
    let pulse: String?
    let pulseAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    private let ink = Color(hex: 0xeee9cd)
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: reduced || pulse == nil)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(pulseAt)
            let blink = !reduced && elapsed >= 0 && elapsed < 1.2 && Int(elapsed / 0.2).isMultiple(of: 2)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                HStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text("\(match.half / 2 + 1) \(match.half % 2 == 0 ? "▲" : "▼")").bold()
                        Text(pitchCount.map { "P \($0)" } ?? "BAT").font(.system(.caption2, design: .monospaced))
                    }.frame(minWidth: 32)
                    HStack(spacing: 8) {
                        lamps("B", count: match.balls, total: 3, blink: blink)
                        lamps("S", count: match.strikes, total: 2, blink: blink)
                        lamps("O", count: match.outs, total: 2, blink: blink)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("B \(match.balls) S \(match.strikes) O \(match.outs)")
                        .accessibilityIdentifier("careerGameCount")
                }
                if !typeSize.isAccessibilitySize { Rectangle().fill(ink.opacity(0.25)).frame(width: 1) }
                let details = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                details {
                    VStack(spacing: 2) {
                        Text(MatchPresentation.pitchName(match.lastManual)).font(.caption.bold())
                            .lineLimit(1).minimumScaleFactor(0.8).accessibilityIdentifier("boardPitchName")
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(match.lastManual.map { String($0.speed) } ?? "–––").lineLimit(1).minimumScaleFactor(0.8).font(.system(.title2, design: .monospaced, weight: .bold)).foregroundStyle(GameTheme.gold)
                            Text("km/h").font(.caption2)
                        }
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("boardPitchSpeed")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("날씨 · 예시").font(.caption2)
                        Text("맑음 22°C").font(.caption2.bold())
                        Text("바람 ↑ 2m/s").font(.caption2)
                    }.accessibilityLabel("예시 날씨 맑음 22도, 외야 방향 바람 초속 2미터")
                }
            }.foregroundStyle(ink).padding(8).frame(maxWidth: .infinity, minHeight: 64)
                .background(Color(hex: 0x173c32))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x93a48c), lineWidth: 1))
        }.accessibilityElement(children: .contain).accessibilityIdentifier("matchScoreboard")
    }
    private func lamps(_ label: String, count: Int, total: Int, blink: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) { Text(label).font(.caption2); Text("\(count)").font(.system(.headline, design: .monospaced, weight: .bold)) }
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    let confirming = pulse == label && i == (count == 0 ? total - 1 : min(count, total) - 1)
                    Rectangle().fill(i < count || confirming ? (label == "B" ? Color(hex: 0x82e6b2) : Color(hex: 0xed7c6b)) : Color(hex: 0x0a211c))
                        .frame(width: 6, height: 6).overlay(Rectangle().strokeBorder(ink.opacity(0.5), lineWidth: 0.5))
                        .opacity(confirming && blink ? 0.2 : 1)
                }
            }
        }
    }
}

struct MatchGrip: View {
    let code: String
    let hand: String
    var body: some View {
        let image = code == "fork" ? MatchArt.cell("grips-extra", column: 2, row: 1, columns: 4, rows: 2)
            : MatchArt.image(code == "slider" ? "grip-slider" : code == "changeup" ? "grip-changeup" : "grip-fastball")
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .scaleEffect(x: hand == "left" ? -1 : 1, y: 1)
                .accessibilityLabel(hand == "left" ? "왼손 구종 그립" : "오른손 구종 그립")
        }
    }
}

// Read-only projection of the completed ledger; never estimates missing statistics.
struct MatchResultSummary {
    struct Metric: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
    }
    let match: CareerMatch
    let fatigueBefore: Int
    let fatigueAfter: Int
    var outcome: String {
        match.teamScore == match.opponentScore ? "무승부" : (match.teamScore > match.opponentScore ? "승리" : "패배")
    }
    var metrics: [Metric] {
        guard match.appearance else { return [] }
        let l = match.line
        let values: [(String, String, String)] = match.role == "pitcher" ? [
            ("innings", "이닝", "\(l.pitchingOuts / 3).\(l.pitchingOuts % 3)"), ("pitches", "투구 수", "\(l.pitches)"),
            ("hitsAllowed", "피안타", "\(l.hitsAllowed)"), ("runsAllowed", "실점", "\(l.runsAllowed)"),
            ("pitchingWalks", "볼넷", "\(l.pitchingWalks)"), ("pitchingStrikeouts", "탈삼진", "\(l.pitchingStrikeouts)")
        ] : [
            ("plateAppearances", "타석", "\(l.plateAppearances)"), ("atBats", "타수", "\(l.atBats)"),
            ("hits", "안타", "\(l.hits)"), ("homeRuns", "홈런", "\(l.homeRuns)"),
            ("rbi", "타점", "\(l.rbi)"), ("walks", "볼넷", "\(l.walks)"), ("strikeouts", "삼진", "\(l.strikeouts)")
        ]
        return values.map { Metric(id: $0.0, label: $0.1, value: $0.2) }
    }
    var fatigueChange: String {
        let delta = fatigueAfter - fatigueBefore
        return delta == 0 ? "변화 없음" : (delta > 0 ? "+\(delta)" : "\(delta)")
    }
    var appliedTraits: [PlayerTrait] { match.lastFieldPlay?.appliedTraits ?? [] }
    var traitMessage: String {
        guard match.appearance else { return "비등판 · 개인 특성 적용 기록 없음" }
        guard let play = match.lastFieldPlay else { return "저장된 개인 주루·수비 경합이 없습니다." }
        guard play.appliedTraits != nil else { return "이전 기록 · 적용 특성 미기록" }
        return appliedTraits.isEmpty ? "마지막 개인 경합에 적용된 특성 없음" : "마지막 개인 경합에서 적용"
    }
}

@MainActor enum PlayerMotionArt {
    private static let cache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>(); cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    struct Pose {
        let shirt: [CGPoint]
        let hair: CGRect
        let skin: [CGRect]
        let number: CGPoint
        var angle: Double = 0
        var erase: CGRect = .zero
    }
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    private static func polygon(_ pairs: [(Double, Double)]) -> [CGPoint] { pairs.map { CGPoint(x: $0.0, y: $0.1) } }
    static func pose(role: PlayerRole, frame: Int) -> Pose {
        if role == .pitcher {
            let hair = [rect(235,177,102,44),rect(218,166,102,44),rect(221,201,97,41),rect(222,174,103,42),rect(147,198,91,45),rect(216,185,102,43)]
            let skin = [[rect(215,172,136,61),rect(199,266,38,44)], [rect(204,160,132,57),rect(181,253,46,37)],
                        [rect(202,191,139,57),rect(153,239,48,43),rect(331,163,66,96)],
                        [rect(208,161,137,64),rect(204,251,46,50),rect(329,38,97,125)],
                        [rect(133,190,113,61),rect(200,282,105,78)], [rect(180,171,150,70),rect(173,258,75,51),rect(329,270,35,38)]]
            let centers = [CGPoint(x:303,y:266),CGPoint(x:291,y:251),CGPoint(x:301,y:286),CGPoint(x:299,y:245),CGPoint(x:264,y:244),CGPoint(x:288,y:252)]
            let erase = [rect(264,237,76,57),rect(253,222,77,59),rect(262,255,76,60),rect(264,216,76,58),rect(220,208,87,66),rect(252,223,76,58)]
            return Pose(shirt: [], hair: hair[frame], skin: skin[frame], number: centers[frame], angle: frame == 4 ? -0.5 : 0, erase: erase[frame])
        }
        let shirts = [polygon([(198,180),(230,178),(270,201),(278,264),(251,291),(154,279),(164,237),(179,200)]),
                      polygon([(163,196),(203,187),(258,204),(262,270),(238,303),(153,298),(164,258)]),
                      polygon([(143,203),(195,209),(238,231),(244,280),(200,316),(112,303),(122,246)]),
                      polygon([(197,151),(265,169),(337,199),(339,243),(304,270),(211,266),(198,216)]),
                      polygon([(158,182),(207,183),(260,208),(271,246),(241,280),(118,270),(132,224)]),
                      polygon([(151,187),(205,186),(260,209),(269,248),(239,281),(116,275),(129,227)])]
        let hair = [rect(248,168,58,25),rect(209,177,62,33),rect(178,180,78,36),rect(255,143,70,32),rect(215,177,72,35),rect(210,179,72,35)]
        let skin = [[rect(258,160,68,47),rect(264,188,85,60)], [rect(210,174,79,44),rect(85,164,78,65)],
                    [rect(171,181,110,46),rect(248,231,81,59)], [rect(252,142,90,49),rect(180,90,65,51)],
                    [rect(210,175,97,53),rect(231,225,114,52)], [rect(203,176,100,53),rect(230,223,111,55)]]
        let centers = [CGPoint(x:202,y:240),CGPoint(x:232,y:266),CGPoint(x:162,y:262),CGPoint(x:273,y:226),CGPoint(x:165,y:240),CGPoint(x:163,y:242)]
        return Pose(shirt: shirts[frame], hair: hair[frame], skin: skin[frame], number: centers[frame])
    }
    static func textures(role: PlayerRole, appearance: PlayerAppearance, number: Int, hand: String) -> [SKTexture] {
        let key = ([role.rawValue, hand] + [appearance.skin,appearance.hair,appearance.kit,appearance.hairStyle,appearance.expression,number].map(String.init)).joined(separator: ":") as NSString
        if let cached = cache.object(forKey: key) as? [SKTexture] { return cached }
        let result = (0..<6).compactMap { frame -> SKTexture? in
            guard let image = image(role: role, frame: frame, appearance: appearance, number: number, hand: hand) else { return nil }
            let texture = SKTexture(image: image); texture.filteringMode = .nearest; return texture
        }
        if result.count == 6 { cache.setObject(result as NSArray, forKey: key, cost: 6 * 512 * 512 * 4) }
        return result
    }
    // Semantic regions use the original 512px cells. Source sheets, alpha, pose geometry and saved state stay unchanged.
    static func image(role: PlayerRole, frame: Int, appearance: PlayerAppearance, number: Int, hand: String) -> UIImage? {
        guard (0..<6).contains(frame), appearance.isValid, (0...99).contains(number),
              let original = MatchArt.cell(role == .pitcher ? "pitcher-delivery-v2" : "batter-actions", column: frame % 3, row: frame / 3, columns: 3, rows: 2)?.cgImage, original.width == 512, original.height == 512 else { return nil }
        let width = original.width, height = original.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: format) else { return false }
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard decoded else { return nil }
        let pose = pose(role: role, frame: frame)
        let shirt = CGMutablePath(); if let first = pose.shirt.first { shirt.move(to: first); pose.shirt.dropFirst().forEach { shirt.addLine(to: $0) }; shirt.closeSubpath() }
        let kit = PlayerAppearance.kitColors[appearance.kit], skin = PlayerAppearance.skinColors[appearance.skin], hair = PlayerAppearance.hairColors[appearance.hair]
        func rgb(_ hex: Int, _ shade: Double) -> (Int,Int,Int) {
            (min(255,Int(Double((hex >> 16) & 255) * shade)), min(255,Int(Double((hex >> 8) & 255) * shade)), min(255,Int(Double(hex & 255) * shade)))
        }
        var shirtShade = [Double](repeating: 0.95, count: height)
        if role == .pitcher {
            for y in Int(pose.erase.minY)..<Int(pose.erase.maxY) {
                var sum = 0.0, count = 0.0
                for x in Int(pose.erase.minX)..<Int(pose.erase.maxX) {
                    let i = (y * width + x) * 4, a = Int(bytes[i+3]); guard a > 128 else { continue }
                    let r = Double(bytes[i]) * 255 / Double(a), g = Double(bytes[i+1]) * 255 / Double(a), b = Double(bytes[i+2]) * 255 / Double(a)
                    if b > 36 && b > r * 1.35 && b > g * 1.1 { sum += b / 135; count += 1 }
                }
                if count > 0 { shirtShade[y] = max(0.25,min(1.6,sum / count)) }
            }
        }
        let mouths = [CGPoint(x:303,y:193),CGPoint(x:264,y:206),CGPoint(x:262,y:218),CGPoint(x:314,y:180),CGPoint(x:273,y:205),CGPoint(x:270,y:206)]
        let mouth = mouths[frame]
        for y in 0..<height { for x in 0..<width {
            let index = (y * width + x) * 4, alpha = Int(bytes[index + 3])
            guard alpha > 16 else { continue }
            let r = Int(bytes[index]) * 255 / alpha, g = Int(bytes[index + 1]) * 255 / alpha, b = Int(bytes[index + 2]) * 255 / alpha
            let point = CGPoint(x: x, y: y), high = max(r,g,b), low = min(r,g,b)
            var color: (Int,Int,Int)?
            if role == .pitcher && pose.erase.contains(point) && high > 100 && high - low < 105 {
                color = rgb(kit, shirtShade[y])
            } else if b > 36 && Double(b) > Double(r) * 1.35 && Double(b) > Double(g) * 1.1 {
                color = rgb(kit, max(0.25,min(1.6,Double(b) / 135)))
            } else if role == .batter && low > 90 && high - low < 70 && shirt.contains(point) {
                color = rgb(kit, max(0.35,Double(r + g + b) / 720))
            } else if pose.hair.contains(point) && high > 22 && high - low < 34 {
                let shaved = appearance.hairStyle == 1 && Double(x) < pose.hair.minX + pose.hair.width * 0.25
                color = rgb(shaved ? skin : hair, max(0.35,min(1.15,Double(high) / 52)))
            } else if pose.skin.contains(where: { $0.contains(point) }) && r > 175 && Double(r) > Double(g) * 1.12 && Double(g) > Double(b) * 1.12 {
                color = rgb(skin, max(0.5,min(1.15,Double(r) / 247)))
            }
            if appearance.hairStyle == 2 && pose.hair.contains(point) && Double(y) > pose.hair.maxY - 7 && high > 30 && high - low < 90 && (x / 6) % 2 == 0 {
                color = rgb(hair, 0.8)
            }
            if role == .batter && appearance.expression > 0 {
                if abs(Double(x) - mouth.x) <= 3 && abs(Double(y) - mouth.y) <= (appearance.expression == 2 ? 2 : 0) && r > 175 && Double(r) > Double(g) * 1.12 && Double(g) > Double(b) * 1.12 {
                    color = rgb(0x85442e, 0.8)
                }
            }
            if let color {
                bytes[index] = UInt8(color.0 * alpha / 255); bytes[index + 1] = UInt8(color.1 * alpha / 255); bytes[index + 2] = UInt8(color.2 * alpha / 255)
            }
        } }
        drawNumber(number, at: pose.number, angle: pose.angle, mirrored: role == .pitcher && hand == "left", unit: role == .pitcher ? 7 : 5, bytes: &bytes, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: format), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }
    static let digits = ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001", "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]
    private static func drawNumber(_ number: Int, at center: CGPoint, angle: Double, mirrored: Bool, unit: Int, bytes: inout [UInt8], width: Int, height: Int) {
        let masks = String(number).compactMap { $0.wholeNumberValue }.map { Array(digits[$0]) }
        let columns = masks.count * 4 - 1, textWidth = Double(columns * unit), textHeight = Double(5 * unit)
        let cosine = cos(angle), sine = sin(angle)
        for y in max(0,Int(center.y)-70)..<min(height,Int(center.y)+70) {
            for x in max(0,Int(center.x)-70)..<min(width,Int(center.x)+70) {
                let dx = Double(x) - center.x, dy = Double(y) - center.y
                let localX = (dx * cosine + dy * sine) * (mirrored ? -1 : 1) + textWidth / 2
                let localY = dy * cosine - dx * sine + textHeight / 2
                guard localX >= 0, localX < textWidth, localY >= 0, localY < textHeight else { continue }
                let col = Int(localX) / unit, row = Int(localY) / unit
                guard col % 4 < 3, masks[col / 4][row * 3 + col % 4] == "1" else { continue }
                let i = (y * width + x) * 4
                guard bytes[i + 3] > 128 else { continue }
                let a = Int(bytes[i + 3]); bytes[i] = UInt8(244*a/255); bytes[i+1] = UInt8(240*a/255); bytes[i+2] = UInt8(219*a/255)
            }
        }
    }
}
