import SwiftUI
import UIKit
import SpriteKit

// Presentation geometry never changes the saved pitch, timing window or RNG.
enum MatchArt {
    static let names = ["batter-view-clean", "stadium-clean", "batter-actions", "pitcher-delivery-v2", "catcher-parts",
                        "grip-fastball", "grip-slider", "grip-changeup", "grips-extra", "inplay-stadium-arcade-v1"]
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
                            .accessibilityIdentifier("boardPitchCount")
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
                .background(Color(hex: 0x0b3552))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x69a4bf), lineWidth: 1))
        }.accessibilityElement(children: .contain).accessibilityIdentifier("matchScoreboard")
    }
    private func lamps(_ label: String, count: Int, total: Int, blink: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) { Text(label).font(.caption2); Text("\(count)").font(.system(.headline, design: .monospaced, weight: .bold)) }
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    let confirming = pulse == label && i == (count == 0 ? total - 1 : min(count, total) - 1)
                    Rectangle().fill(i < count || confirming ? (label == "B" ? Color(hex: 0x82e6b2) : Color(hex: 0xed7c6b)) : Color(hex: 0x082337))
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
        var result=values.map { Metric(id: $0.0, label: $0.1, value: $0.2) }
        if (match.detailedFieldVersion ?? 0) >= 2,let plays=match.fieldPlays {
            let count=plays.filter { $0.secondThrow?.out == true && (match.role == "batter" ? $0.ownBatter : (($0.half % 2 == 1) != match.isHome)) }.count
            result.append(Metric(id:"doublePlays",label:match.role == "batter" ? "병살타" : "병살 유도",value:String(count)))
        }
        if (match.detailedFieldVersion ?? 0) >= 3,match.role == "batter" {
            let count=match.fieldPlays?.filter { $0.ownBatter && $0.sacrificeFly }.count ?? 0
            result.append(Metric(id:"sacrificeFlies",label:"희생플라이",value:String(count)))
        }
        if match.detailedFieldVersion == 5 {
            let plays=match.fieldPlays ?? []
            result.append(Metric(id:"fieldingErrors",label:"내 수비 실책",value:String(plays.filter { $0.misplay?.ownError == true }.count)))
            result.append(Metric(id:"teamErrors",label:"팀 실책",value:String(plays.filter { $0.misplay != nil && (($0.half % 2 == 1) != match.isHome) }.count)))
            if match.role == "batter" {result.append(Metric(id:"reachedOnError",label:"실책 출루",value:String(plays.filter { $0.ownBatter && $0.misplay?.reachedOnError == true }.count)))}
        }
        return result
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

enum FieldReplayPresentation {
    static func stageHeight(width:CGFloat,available:CGFloat,accessibility:Bool=false) -> CGFloat {
        max(320,min(width*1.5+36,available-112)) + (accessibility ? 160:0)
    }
    static func seconds(_ play:MatchDetailedPlay,reduced:Bool,animated:Bool) -> Double {
        reduced || !animated ? 0.25:min(8,max(3,play.duration))
    }
    static func phase(_ play:MatchDetailedPlay,time:Double,finished:Bool) -> String {
        if finished {return play.summary}
        if time < play.pickupAt {return play.fly == nil ? "땅볼 · 야수 타구 추격":"공중 타구 · 낙하지점으로 이동"}
        if let relay=play.relay,time>=play.releaseAt {
            if time < relay.receiveAt {return "외야 송구 · 중계 야수 수신 대기"}
            if time < relay.releaseAt {return "중계 포구 · 재송구 준비"}
        }
        if let second=play.secondThrow,time>=play.controlAt && time<second.releaseAt {return "베이스 포구 · 1루 재송구 준비"}
        if play.fly?.caught == true && play.targetRunner == nil && play.misplay == nil {return "포구 · 플레이 확인 중"}
        if time < play.releaseAt {return "포구 · 송구 자세 전환"}
        if let error=play.misplay,time>=error.at && time<error.recoveredAt {return "공 회수 · 주자 이동 중"}
        return "송구 · 주자와 베이스 경합"
    }
    static func lift(_ play:MatchDetailedPlay,time:Double,height:Double) -> Double {
        if time < play.flight {
            let t=max(0,min(1,time/max(0.001,play.flight)))
            return play.fly == nil ? abs(sin(t * .pi * 4))*3:sin(t * .pi)*height*0.19
        }
        for (a,b) in zip(play.ball,play.ball.dropFirst()) where time>=a.at && time<b.at && a.at>=play.releaseAt && a.point != b.point {
            return sin(.pi*(time-a.at)/max(0.001,b.at-a.at))*height*0.035
        }
        return 0
    }
    static func opponentKit(_ own:Int) -> Int {
        [0x294c77,0xf0ead9,0x9a3e39].max {a,b in
            func distance(_ color:Int) -> Int {
                [0,8,16].reduce(0) {sum,shift in let d=((color>>shift)&255)-((own>>shift)&255);return sum+d*d}
            }
            return distance(a)<distance(b)
        }!
    }

}

enum FieldFacing: Int,CaseIterable,Equatable {
    case north,northEast,east,southEast,south,southWest,west,northWest
    var back:Bool {[.north,.northEast,.northWest].contains(self)}
    var side:Bool {self == .east || self == .west}
    var diagonal:Bool {[.northEast,.southEast,.southWest,.northWest].contains(self)}
    var horizontal:Double {[.northWest,.west,.southWest].contains(self) ? -1:1}
    var vector:CGPoint {
        switch self {
        case .north:CGPoint(x:0,y:-1)
        case .northEast:CGPoint(x:0.707,y:-0.707)
        case .east:CGPoint(x:1,y:0)
        case .southEast:CGPoint(x:0.707,y:0.707)
        case .south:CGPoint(x:0,y:1)
        case .southWest:CGPoint(x:-0.707,y:0.707)
        case .west:CGPoint(x:-1,y:0)
        case .northWest:CGPoint(x:-0.707,y:-0.707)
        }
    }
    static func turn(from:Self,to:Self,fraction:Double) -> Self {
        var delta=to.rawValue-from.rawValue
        if delta>4 {delta-=8};if delta < -4 {delta+=8}
        let step=Int((Double(delta)*max(0,min(1,fraction))).rounded())
        return Self(rawValue:(from.rawValue+step+8)%8) ?? to
    }
    static func direction(dx:Double,dy:Double) -> Self {
        if abs(dx)+abs(dy)<0.000001 {return .south}
        if abs(dx)<abs(dy)*0.414 {return dy>0 ? .north:.south}
        if abs(dy)<abs(dx)*0.414 {return dx>0 ? .east:.west}
        if dx>0 {return dy>0 ? .northEast:.southEast}
        return dy>0 ? .northWest:.southWest
    }
}

enum FieldSpriteStage: Equatable {case ready,run,catchBall,gather,windup,release,followThrough}
struct FieldSpriteMotion {
    var facing:FieldFacing
    var stage:FieldSpriteStage
    var progress:Double = 0
    var gait:Double = 0
    var airCatch=false
    var willThrow=false

    var bodyOffset:CGPoint {
        let lean=stage == .followThrough ? facing.vector.x*sin(progress * .pi)*2:stage == .run ? facing.vector.x*1.2:0
        let bob=stage == .run ? -abs(cos(gait))*1.4:stage == .catchBall && !airCatch ? sin(progress * .pi/2)*3:stage == .gather && !airCatch ? (1-progress)*3:0
        return CGPoint(x:lean,y:bob)
    }
    func throwingHand(left:Bool) -> CGPoint {
        let side=(left ? -1.0:1)*(facing.back ? 1:-1)
        let rest=CGPoint(x:side*6,y:-12)
        let direction=facing.vector,extended=CGPoint(x:direction.x*11,y:-17+direction.y*4)
        func blend(_ a:CGPoint,_ b:CGPoint,_ t:Double) -> CGPoint {CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)}
        switch stage {
        case .run:return CGPoint(x:side*6+sin(gait)*2,y:-12+cos(gait)*3)
        case .gather:return willThrow ? blend(rest,CGPoint(x:0,y:-15),progress):rest
        case .windup:
            let cocked=CGPoint(x:-direction.x*7+side*2,y:-26)
            return progress<0.55 ? blend(CGPoint(x:0,y:-15),cocked,progress/0.55):blend(cocked,extended,(progress-0.55)/0.45)
        case .release:return extended
        case .followThrough:
            let crossed=CGPoint(x:-direction.x*4,y:-8)
            return progress<0.65 ? blend(extended,crossed,progress/0.65):blend(crossed,rest,(progress-0.65)/0.35)
        default:return rest
        }
    }
    func glove(left:Bool) -> CGPoint {
        let side=(left ? 1.0:-1)*(facing.back ? 1:-1)
        let rest=CGPoint(x:side*7,y:-12)
        let caught=CGPoint(x:airCatch ? side*4:side*7,y:airCatch ? -27:-7)
        switch stage {
        case .catchBall:
            let reach=sin(min(1,progress)*Double.pi/2)
            return CGPoint(x:rest.x+(caught.x-rest.x)*reach,y:rest.y+(caught.y-rest.y)*reach)
        case .gather:
            if willThrow {return CGPoint(x:caught.x*(1-progress),y:caught.y+(-15-caught.y)*progress)}
            if progress<0.5 {return CGPoint(x:caught.x*(1-progress*2),y:caught.y+(-15-caught.y)*progress*2)}
            return CGPoint(x:rest.x*(progress-0.5)*2,y:-15+(rest.y+15)*(progress-0.5)*2)
        case .windup,.release:return CGPoint(x:side*3,y:-15)
        case .followThrough:return CGPoint(x:side*3+(rest.x-side*3)*progress,y:-15+(rest.y+15)*progress)
        case .run:return CGPoint(x:side*7-sin(gait)*2,y:-12-cos(gait)*3)
        default:return rest
        }
    }
}

enum FieldSpriteAnimation {
    struct ThrowEvent {
        let fielder:Int
        let caughtAt:Double
        let releaseAt:Double
        let receivedAt:Double
        let receiver:Int
    }
    static func throwsIn(_ play:MatchDetailedPlay) -> [ThrowEvent] {
        var events:[ThrowEvent]=[]
        if play.releaseAt>play.pickupAt {
            events.append(.init(fielder:play.fielder,caughtAt:play.pickupAt,releaseAt:play.releaseAt,
                receivedAt:play.relay?.receiveAt ?? play.ballAt,receiver:play.relay?.fielder ?? play.receiver))
        }
        if let relay=play.relay {events.append(.init(fielder:relay.fielder,caughtAt:relay.receiveAt,releaseAt:relay.releaseAt,receivedAt:play.ballAt,receiver:play.receiver))}
        if let second=play.secondThrow {events.append(.init(fielder:play.receiver,caughtAt:play.ballAt,releaseAt:second.releaseAt,receivedAt:second.ballAt,receiver:second.receiver))}
        return events
    }
    static func travel(_ nodes:[FieldNode],time:Double) -> FieldSpriteMotion {
        var last:FieldFacing = .south
        for (a,b) in zip(nodes,nodes.dropFirst()) where a.point != b.point {
            let direction=FieldFacing.direction(dx:b.point.x-a.point.x,dy:b.point.y-a.point.y)
            if time>=a.at && time<b.at {return .init(facing:direction,stage:.run,gait:time*17)}
            if time>=b.at {last=direction}
        }
        return .init(facing:last,stage:.ready)
    }
    static func motion(_ play:MatchDetailedPlay,index:Int,time:Double) -> FieldSpriteMotion {
        let nodes=play.fielders[index],at=FieldNode.sample(nodes,at:time)
        let events=throwsIn(play)
        var motion=travel(nodes,time:time)
        if let event=events.first(where:{$0.fielder == index && time >= $0.caughtAt-0.12 && time<=$0.releaseAt+0.38}) {
            let receiver=FieldNode.sample(play.fielders[event.receiver],at:event.receivedAt)
            motion.willThrow=true
            motion.facing=FieldFacing.direction(dx:receiver.x-at.x,dy:receiver.y-at.y)
            let transfer=max(0.001,event.releaseAt-event.caughtAt)
            let catchEnd=event.caughtAt+min(0.10,transfer*0.25)
            let windup=event.releaseAt-min(0.20,transfer*0.50)
            if time<catchEnd {motion.stage = .catchBall;motion.progress=min(1,max(0,(time-event.caughtAt+0.12)/(catchEnd-event.caughtAt+0.12)))}
            else if time<windup {motion.stage = .gather;motion.progress=(time-catchEnd)/max(0.001,windup-catchEnd)}
            else if time<event.releaseAt {motion.stage = .windup;motion.progress=(time-windup)/max(0.001,event.releaseAt-windup)}
            else if time<event.releaseAt+0.08 {motion.stage = .release;motion.progress=(time-event.releaseAt)/0.08}
            else {motion.stage = .followThrough;motion.progress=min(1,(time-event.releaseAt-0.08)/0.30)}
            let incoming=FieldNode.sample(play.ball,at:max(0,event.caughtAt-0.12))
            let catchFacing=FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y)
            if motion.stage == .catchBall {motion.facing=catchFacing}
            else if motion.stage == .gather {motion.facing=FieldFacing.turn(from:catchFacing,to:motion.facing,fraction:motion.progress)}
            motion.airCatch=index == play.fielder && play.fly?.caught == true
            return motion
        }
        let catches=[(play.fielder,play.pickupAt)]+events.map {($0.receiver,$0.receivedAt)}
        if let caught=catches.last(where:{$0.0 == index && time >= $0.1-0.12 && time < $0.1+0.35}) {
            let incoming=FieldNode.sample(play.ball,at:max(0,caught.1-0.12))
            motion.facing=FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y)
            motion.stage=time<caught.1+0.10 ? .catchBall:.gather
            motion.progress=time<caught.1+0.10 ? min(1,max(0,(time-caught.1+0.12)/0.22)):min(1,(time-caught.1-0.10)/0.25)
            motion.airCatch=index == play.fielder && play.fly?.caught == true
        }
        if motion.stage == .ready {
            if let last=events.last(where:{$0.fielder == index && time>$0.releaseAt}) {
                let target=FieldNode.sample(play.fielders[last.receiver],at:last.receivedAt)
                motion.facing=FieldFacing.direction(dx:target.x-at.x,dy:target.y-at.y)
            } else if let caught=catches.last(where:{$0.0 == index && time>=$0.1}) {
                let incoming=FieldNode.sample(play.ball,at:max(0,caught.1-0.12))
                motion.facing=FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y)
            }
        }
        return motion
    }
    static func ballOffset(_ play:MatchDetailedPlay,time:Double,leftIndex:Int?) -> CGPoint {
        let events=throwsIn(play)
        let catches=[(play.fielder,play.pickupAt)]+events.map {($0.receiver,$0.receivedAt)}
        let ball=FieldNode.sample(play.ball,at:time)
        for index in play.fielders.indices {
            let at=FieldNode.sample(play.fielders[index],at:time)
            guard ball.distance(to:at)<0.9 else {continue}
            let motion=motion(play,index:index,time:time),left=index == leftIndex
            let active=events.contains {$0.fielder == index && time >= $0.caughtAt && time <= $0.releaseAt+0.0001}
            let caught=catches.contains {$0.0 == index && time >= $0.1}
            guard active || caught else {continue}
            var p=motion.glove(left:left)
            if active && [.windup,.release].contains(motion.stage) {p=motion.throwingHand(left:left)}
            else if active && motion.stage == .gather {
                let hand=motion.throwingHand(left:left)
                p=CGPoint(x:p.x+(hand.x-p.x)*motion.progress,y:p.y+(hand.y-p.y)*motion.progress)
            }
            return CGPoint(x:p.x+motion.bodyOffset.x,y:p.y+motion.bodyOffset.y)
        }
        return .zero
    }
}

@MainActor enum FieldActorArt {
    // Includes glove, throwing hand and the running lean at every displayed heading.
    static let horizontalReach = 15.0
    static func draw(in context:GraphicsContext,at c:CGPoint,scale u:Double,motion:FieldSpriteMotion,
                     kit:Int,skin:Int,hair:Int,number:Int,left:Bool,selected:Bool,out:Bool=false) {
        let outline=0x102336,pants=0xf1f3e9
        let bob=motion.bodyOffset.y,lean=motion.bodyOffset.x
        func tone(_ color:Int,_ delta:Int) -> Int {
            [0,8,16].reduce(0) {$0 | (max(0,min(255,((color >> $1)&255)+delta)) << $1)}
        }
        let kitDark=tone(kit,-35),kitLight=tone(kit,30),skinDark=tone(skin,-35)
        func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ hex:Int,_ body:Bool=true) {
            let rect=CGRect(x:(c.x+(x+(body ? lean:0))*u).rounded(),y:(c.y+(y+(body ? bob:0))*u).rounded(),width:max(1,(w*u).rounded()),height:max(1,(h*u).rounded()))
            context.fill(Path(rect),with:.color(Color(hex:hex).opacity(out ? 0.38:1)))
        }
        func limb(_ a:CGPoint,_ b:CGPoint,_ color:Int,_ body:Bool=true) {
            let steps=max(1,Int(max(abs(b.x-a.x),abs(b.y-a.y))))
            for i in 0...steps {
                let t=Double(i)/Double(steps),x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t
                box(x-2,y-2,5,5,outline,body)
            }
            for i in 0...steps {
                let t=Double(i)/Double(steps),x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t
                box(x-1,y-1,3,3,color,body);box(x-1,y-1,1,2,tone(color,18),body)
            }
        }
        let side=motion.facing.side,width=side ? 9.0:motion.facing.diagonal ? 11:12
        box(-9,2,18,3,0x246b39,false);box(-7,3,14,2,0x174b32,false)
        let crouch=max(0,bob)
        for (hip,phase) in [(side ? -2.0:-3.5,0.0),(side ? 2.0:3.5,Double.pi)] {
            let stride=motion.stage == .run ? sin(motion.gait+phase):0
            let foot=CGPoint(x:hip+motion.facing.vector.x*stride*4,y:3+(abs(motion.facing.vector.y)>0.4 ? stride*2:-max(0,stride)*3))
            let knee=CGPoint(x:hip+motion.facing.vector.x*stride,y:-3-max(0,stride)*2+crouch*0.6)
            limb(CGPoint(x:hip,y:-8+crouch),knee,pants,false);limb(knee,foot,pants,false)
            box(knee.x+1,knee.y,1,3,0xa2b6b9,false)
            box(foot.x-2,foot.y-2,4,3,kitDark,false)
            let toe=side && motion.facing.horizontal<0 ? -4.0:-2
            box(foot.x+toe,foot.y+1,6,3,outline,false)
            box(foot.x+toe+1,foot.y+1,4,1,pants,false)
            box(foot.x+toe,foot.y+3,6,1,0x6d8791,false)
        }
        box(-width/2-1,-20,width+2,14,outline)
        box(-width/2-2,-19,width+4,5,outline)
        box(-width/2,-19,width,12,kit)
        box(-width/2-1,-18,width+2,3,kit)
        box(-width/2,-18,2,10,kitLight);box(width/2-2,-17,2,10,kitDark)
        box(-2,-19,4,2,pants);box(-1,-17,1,8,kitDark)
        box(-width/2+2,-8,width-4,1,kitLight)
        box(-width/2,-7,width,2,outline);box(-1,-7,2,1,0xd6bf88)
        if !side {
            context.draw(Text("\(number)").font(.system(size:7*u,weight:.black,design:.monospaced)).foregroundStyle(Color(hex:kit == 0xf0ead9 ? outline:0xf6f2d8).opacity(out ? 0.38:1)),at:CGPoint(x:c.x+lean*u,y:c.y+(-12+bob)*u))
        } else {box(-1,-18,1,9,pants)}
        let hand=motion.throwingHand(left:left),glove=motion.glove(left:left)
        let anatomical=(left ? -1.0:1)*(motion.facing.back ? 1:-1)
        func arm(_ shoulder:CGPoint,_ end:CGPoint) {
            let elbow=CGPoint(x:shoulder.x*0.4+end.x*0.6,y:shoulder.y*0.45+end.y*0.55+1)
            limb(shoulder,elbow,kit);limb(elbow,end,skin)
            box(shoulder.x-1,shoulder.y-1,3,1,pants)
            box(end.x-1,end.y,2,1,skinDark)
        }
        arm(CGPoint(x:anatomical*(width/2+1),y:-18),hand)
        arm(CGPoint(x:-anatomical*(width/2+1),y:-18),glove)
        let headShift=motion.facing.diagonal ? motion.facing.horizontal:0
        func head(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ hex:Int) {box(x+headShift,y,w,h,hex)}
        head(-5,-32,10,1,outline);head(-7,-31,14,11,outline)
        head(-6,-21,12,3,outline);head(-4,-18,8,1,outline)
        head(-6,-28,12,8,skin);head(-5,-20,10,2,skinDark)
        head(-8,-25,2,4,skinDark);head(6,-25,2,4,skinDark)
        if motion.facing.back {
            head(-6,-27,12,7,hair);head(-5,-21,10,2,tone(hair,20))
            head(-2,-20,4,2,skin)
            if motion.facing.diagonal {head(motion.facing.horizontal*5,-25,2,4,skin)}
        } else {
            head(-5,-27,10,2,hair);head(-5,-25,10,5,skin)
            head(-4,-24,2,3,tone(skin,20))
            let eye=side || motion.facing.diagonal ? motion.facing.horizontal*3:3
            head(eye-1,-25,3,3,0xf7f3e7);head(eye,-25,2,2,outline)
            if !side && !motion.facing.diagonal {head(-4,-25,3,3,0xf7f3e7);head(-3,-25,2,2,outline)}
            head(side || motion.facing.diagonal ? motion.facing.horizontal*6:-1,-23,2,2,skinDark)
            head(-1,-20,3,1,0x9b634a)
        }
        head(-5,-33,10,1,outline);head(-6,-32,12,4,kit)
        head(-4,-32,7,1,kitLight);head(3,-31,3,3,kitDark)
        head(-7,-28,14,2,outline)
        let brim=motion.facing == .north ? -4:motion.facing == .south ? -8:motion.facing.horizontal>0 ? 4:-11
        head(Double(brim),-28,motion.facing == .south ? 16:7,2,kitDark)
        head(Double(brim)+1,-28,motion.facing == .south ? 13:5,1,kitLight)
        if !motion.facing.back && !side {head(-1,-31,2,2,pants)}
        // The glove and fingers are drawn last, at the same anchors used by the ball layer.
        box(hand.x-1,hand.y-1,3,3,skin);box(hand.x,hand.y-1,1,1,tone(skin,20))
        box(glove.x-4,glove.y-3,8,7,outline)
        box(glove.x-3,glove.y-3,6,6,0x8e562d);box(glove.x-2,glove.y-2,4,4,0xb88145)
        box(glove.x-1,glove.y-1,2,3,0x654026);box(glove.x-3,glove.y-2,1,4,0xd5a56b)
        for finger in 0..<3 {box(glove.x-2+Double(finger)*2,glove.y-3,1,2,0xd5a56b)}
        if selected {box(-2,-38,4,2,0xecc66b);box(-1,-36,2,1,0xecc66b)}
    }
}

// Calibrated to the clean backdrop's home, first/third, second and mound landmarks.
// Shared by actors, bases and the ball; it never changes simulation geometry.
enum InplayFieldProjection {
    static func viewport(_ size:CGSize) -> CGRect {
        CGRect(x:size.width*0.025,y:size.height*0.025,width:size.width*0.95,height:size.height*0.95)
    }
    static func point(_ p:FieldPoint,size:CGSize) -> CGPoint {
        let depth=max(-6,p.y),denominator=28+depth,frame=viewport(size)
        return CGPoint(x:frame.minX+frame.width*(0.5+1.16*p.x/denominator),
                       y:frame.minY+frame.height*(0.739-0.59*depth/denominator))
    }
    static func actorScale(_ p:FieldPoint,size:CGSize) -> Double {
        viewport(size).width/310*(1.12-0.36*min(1,max(0,p.y)/80))
    }
    static func facing(_ facing:FieldFacing,at p:FieldPoint,size:CGSize) -> FieldFacing {
        let a=point(p,size:size)
        let b=point(.init(x:p.x+facing.vector.x,y:p.y-facing.vector.y),size:size)
        return .direction(dx:b.x-a.x,dy:a.y-b.y)
    }
    static func motion(_ motion:FieldSpriteMotion,at p:FieldPoint,size:CGSize) -> FieldSpriteMotion {
        var display=motion;display.facing=facing(motion.facing,at:p,size:size);return display
    }
}

enum FieldBallPresentation {
    static func handOffset(_ play:MatchDetailedPlay,time:Double,size:CGSize,leftIndex:Int?) -> CGPoint {
        let position=FieldNode.sample(play.ball,at:time)
        let motionIndex=play.fielders.indices.first {FieldNode.sample(play.fielders[$0],at:time).distance(to:position)<0.9}
        let scale=InplayFieldProjection.actorScale(position,size:size)
        var offset=FieldSpriteAnimation.ballOffset(play,time:time,leftIndex:leftIndex)
        if let index=motionIndex {
            let display=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:index,time:time),at:position,size:size)
            // Preserve the gather interpolation while using the projected screen-facing pose.
            let original=FieldSpriteAnimation.motion(play,index:index,time:time)
            let left=index == leftIndex
            func anchor(_ motion:FieldSpriteMotion) -> CGPoint {
                var p=motion.glove(left:left)
                if [.windup,.release].contains(motion.stage) {p=motion.throwingHand(left:left)}
                else if motion.stage == .gather && motion.willThrow {
                    let hand=motion.throwingHand(left:left)
                    p=CGPoint(x:p.x+(hand.x-p.x)*motion.progress,y:p.y+(hand.y-p.y)*motion.progress)
                }
                return CGPoint(x:p.x+motion.bodyOffset.x,y:p.y+motion.bodyOffset.y)
            }
            if offset != .zero {
                let a=anchor(original),b=anchor(display)
                offset=CGPoint(x:offset.x+b.x-a.x,y:offset.y+b.y-a.y)
            }
        }
        return CGPoint(x:offset.x*scale,y:offset.y*scale)
    }
    static func point(_ play:MatchDetailedPlay,time:Double,size:CGSize,leftIndex:Int?) -> CGPoint {
        let raw=InplayFieldProjection.point(FieldNode.sample(play.ball,at:time),size:size)
        var offset=handOffset(play,time:time,size:size,leftIndex:leftIndex)
        if let segment=zip(play.ball,play.ball.dropFirst()).first(where:{time >= $0.0.at && time < $0.1.at && $0.0.point != $0.1.point}) {
            let a=handOffset(play,time:segment.0.at,size:size,leftIndex:leftIndex)
            let b=handOffset(play,time:segment.1.at,size:size,leftIndex:leftIndex)
            let f=(time-segment.0.at)/max(0.001,segment.1.at-segment.0.at)
            offset=CGPoint(x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f)
        }
        return CGPoint(x:raw.x+offset.x,y:raw.y+offset.y-FieldReplayPresentation.lift(play,time:time,height:size.height))
    }
}

// The bundled art contains no players, ball or score; live layers own every moving object.
@MainActor enum InplayStadiumArt {
    static let size=CGSize(width:1024,height:1536)
    static let image=MatchArt.image("inplay-stadium-arcade-v1")
}

struct DetailedFieldReplayBoard: View {
    let play: MatchDetailedPlay
    let appearance: PlayerAppearance
    var animated = true
    var jerseyNumber = 1
    var ownPosition: String? = nil
    var throwingHand = "right"
    var ownTeamFielding: Bool? = nil
    var scoreText = "IN PLAY"
    var onResolved: @MainActor () -> Void = {}
    let complete: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var start = Date()
    @State private var resolved = false
    private var seconds: Double {FieldReplayPresentation.seconds(play,reduced:reduced,animated:animated)}
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduced || !animated)) { timeline in
            let fraction = reduced || !animated ? 1:min(1,max(0,timeline.date.timeIntervalSince(start)/seconds))
            let time=fraction*play.duration,finished = !animated || resolved
            let phase=FieldReplayPresentation.phase(play,time:time,finished:finished)
            let second=play.secondThrow
            let target=time >= (second?.releaseAt ?? .infinity) ? 1:play.targetBase
            VStack(spacing:4) {
                Text(finished ? "플레이 완료":phase).font(.system(.headline,design:.monospaced,weight:.bold)).foregroundStyle(GameTheme.gold)
                    .lineLimit(typeSize.isAccessibilitySize ? nil:2).accessibilityIdentifier("fieldReplayPhase")
                Canvas { context,size in
                    func point(_ p:FieldPoint) -> CGPoint {InplayFieldProjection.point(p,size:size)}
                    if let image=InplayStadiumArt.image {
                        context.draw(Image(uiImage:image).interpolation(.none),in:InplayFieldProjection.viewport(size))
                    } else {
                        context.draw(Text("구장 이미지를 불러오지 못했습니다").foregroundStyle(GameTheme.paper),at:CGPoint(x:size.width/2,y:size.height/4))
                    }
                    let viewport=InplayFieldProjection.viewport(size)
                    let scoreFrame=CGRect(x:viewport.minX+viewport.width*0.39,y:viewport.minY+viewport.height*0.123,width:viewport.width*0.22,height:viewport.height*0.039)
                    context.fill(Path(scoreFrame),with:.color(Color(hex:0x0b2030)))
                    context.stroke(Path(scoreFrame),with:.color(GameTheme.gold),lineWidth:2)
                    context.draw(Text(scoreText).font(.system(size:max(12,size.width*0.028),weight:.black,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:scoreFrame.midX,y:scoreFrame.midY))
                    if time>=play.pickupAt {
                        let b=point(DetailedFieldRules.bases[target]),w=max(7,size.width*0.025)
                        context.stroke(Path(ellipseIn:CGRect(x:b.x-w,y:b.y-w/2,width:w*2,height:w)),with:.color(GameTheme.gold.opacity(0.8)),lineWidth:1)
                    }
                    let ownKit=PlayerAppearance.kitColors[appearance.kit],opponent=FieldReplayPresentation.opponentKit(ownKit)
                    let defenseOwn=ownTeamFielding ?? !play.ownBatter
                    var actors:[(point:FieldPoint,motion:FieldSpriteMotion,own:Bool,teamOwn:Bool,number:Int,out:Bool)]=[]
                    for index in play.fielders.indices {
                        let own=defenseOwn && (ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index==play.fielder))
                        actors.append((FieldNode.sample(play.fielders[index],at:time),FieldSpriteAnimation.motion(play,index:index,time:time),own,defenseOwn,own ? jerseyNumber:index+1,false))
                    }
                    for runner in play.runners {
                        actors.append((FieldNode.sample(runner.nodes,at:time),FieldSpriteAnimation.travel(runner.nodes,time:time),runner.profile.own,!defenseOwn,runner.profile.own ? jerseyNumber:runner.from+10,finished && runner.out))
                    }
                    for actor in actors.sorted(by:{$0.point.y>$1.point.y}) {
                        FieldActorArt.draw(in:context,at:point(actor.point),scale:InplayFieldProjection.actorScale(actor.point,size:size),motion:InplayFieldProjection.motion(actor.motion,at:actor.point,size:size),
                            kit:actor.teamOwn ? ownKit:opponent,skin:actor.own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                            hair:actor.own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:actor.number,
                            left:actor.own && throwingHand == "left",selected:actor.own,out:actor.out)
                    }
                    let ownIndex=defenseOwn ? play.fielders.indices.first {index in ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index == play.fielder)}:nil
                    let leftIndex=throwingHand == "left" ? ownIndex:nil
                    func ballPoint(_ t:Double) -> CGPoint {
                        FieldBallPresentation.point(play,time:t,size:size,leftIndex:leftIndex)
                    }
                    let groundBall=point(FieldNode.sample(play.ball,at:time))
                    context.fill(Path(ellipseIn:CGRect(x:groundBall.x-3,y:groundBall.y-1,width:6,height:2)),with:.color(.black.opacity(0.4)))
                    for i in 1...3 where time<Double(play.ball.last?.at ?? 0) {
                        let p=ballPoint(max(0,time-Double(i)*0.04))
                        context.fill(Path(CGRect(x:p.x,y:p.y,width:2,height:2)),with:.color(GameTheme.paper.opacity(0.4)))
                    }
                    PixelBaseball.draw(in:context,at:ballPoint(time),diameter:max(5,6*InplayFieldProjection.actorScale(FieldNode.sample(play.ball,at:time),size:size)))
                    if finished {
                        let label=play.misplay != nil ? "ERROR":play.secondThrow?.out == true ? "DOUBLE PLAY":play.fly?.caught == true && play.targetRunner == nil ? "CATCH · OUT":play.out ? "OUT":"SAFE"
                        let frame=CGRect(x:size.width*0.18,y:size.height*0.27,width:size.width*0.64,height:32)
                        context.fill(Path(frame),with:.color(GameTheme.board.opacity(0.96)))
                        context.stroke(Path(frame),with:.color(GameTheme.gold),lineWidth:2)
                        context.draw(Text(label).font(.system(size:18,weight:.black,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:frame.midX,y:frame.midY))
                    }
                }.aspectRatio(2.0/3,contentMode:.fit).accessibilityLabel(finished ? "도트 수비 주루 재생 · "+play.summary:"인플레이 · "+(play.fly == nil ? "땅볼":"공중 타구"))
                    .accessibilityIdentifier("fieldReplayCanvas").id("fieldGraphic")
            }.padding(4).background(GameTheme.board)
                .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
        }
        .task(id:play.eventID) {
            start=Date();resolved=false
            do {try await Task.sleep(for:.seconds(seconds))} catch {return}
            guard !Task.isCancelled else {return}
            resolved=true;onResolved()
            if animated {
                do {try await Task.sleep(for:.seconds(DeliveryPresentation.receipt(reduced:reduced,match:true)))} catch {return}
            }
            if !Task.isCancelled {complete()}
        }
    }
}

struct FieldReplayDetails: View {
    let play:MatchDetailedPlay
    @State private var expanded=false
    var body: some View {
        DisclosureGroup("플레이 상세",isExpanded:$expanded) {
            let second=play.secondThrow
                if let error=play.misplay {
                    Text("실책 \(error.at,specifier:"%.2f")초 → 회수 \(error.recoveredAt,specifier:"%.2f")초 · 추가 \(error.extraBases.values.reduce(0,+))베이스")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayMisplayTimes")
                    Text(error.reachedOnError ? "실책 출루 · 안타 제외" : "정상 타격 기록 유지 · 실책 추가 진루 분리")
                        .font(.subheadline).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayMisplayScoring")
                }
                if let relay=play.relay {
                    Text("중계 \(DetailedFieldRules.names[relay.fielder]) · 수신 \(relay.receiveAt,specifier:"%.2f")초 / 재송구 \(relay.releaseAt,specifier:"%.2f")초")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayRelayTimes")
                    Text("직접 \(relay.directAt,specifier:"%.2f")초 → 중계 \(play.controlAt,specifier:"%.2f")초")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayRouteComparison")
                }
                if let fly=play.fly,play.misplay == nil {
                    Text("공 낙하 \(play.flight,specifier:"%.2f")초 / 포구 준비 \(fly.reachAt,specifier:"%.2f")초 · \(fly.caught ? "포구 성공" : "낙하 후 처리")")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayCatchTimes")
                }
                if play.misplay == nil && (play.fly?.caught != true || play.targetRunner != nil) {
                Text("\(play.targetBase == 4 ? "홈" : "\(play.targetBase)루") · 공 \(play.controlAt,specifier:"%.2f")초 / 주자 \(play.runnerAt.map { String(format:"%.2f초",$0) } ?? "진루 완료")")
                    .font(.subheadline.monospaced()).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayTimes")
                }
                if let second {
                    Text("1루 · 공 \(second.controlAt,specifier:"%.2f")초 / 타자 \(second.runnerAt,specifier:"%.2f")초")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplaySecondTimes")
                }
        }.font(.subheadline.monospaced()).tint(GameTheme.gold)
            .accessibilityIdentifier("fieldReplayDetails")
    }
}

struct PitcherChangePanel: View {
    let change: PitcherChange
    var finalRuns: Int?
    let appearance: PlayerAppearance
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var entered=false
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("투수 교체 · 내 등판 종료").font(.headline).foregroundStyle(GameTheme.gold)
            GeometryReader { g in
                ZStack {
                    Rectangle().fill(Color(hex:0x215b44))
                    Path {p in p.move(to:CGPoint(x:16,y:48));p.addLine(to:CGPoint(x:g.size.width-16,y:48))}.stroke(GameTheme.gold,style:StrokeStyle(lineWidth:2,dash:[4,4]))
                    PixelPlayer(appearance:appearance).frame(width:24,height:32).position(x:entered ? 26:g.size.width*0.5,y:38)
                    PixelPlayer(appearance:PlayerAppearance()).frame(width:24,height:32).position(x:entered ? g.size.width*0.5:g.size.width-26,y:38)
                }
            }.frame(height:66).accessibilityLabel("선발 퇴장 후 구원 투수 마운드 입장")
            Text("\(change.half/2+1)회 \(change.half%2 == 0 ? "초":"말") · \(change.outs)아웃 · \(change.reason) · \(change.pitches)구")
                .font(.caption.monospaced()).accessibilityIdentifier("pitcherChangeReason")
            Text("등판 \(change.outsAtExit/3).\(change.outsAtExit%3)이닝 · 강판 시 실점 \(change.runsAtExit)")
                .font(.caption.monospaced())
            if let finalRuns {
                Text("최종 실점 \(finalRuns) · 강판 후 책임 주자 실점 \(max(0,finalRuns-change.runsAtExit))")
                    .font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("pitcherResponsibilityResult")
            }
            Text(change.inheritedBases.isEmpty ? "남긴 주자 없음":"책임 주자 · \(change.inheritedBases.map {"\($0)루"}.joined(separator:" · "))")
                .font(.caption).accessibilityIdentifier("pitcherInheritedBases")
        }.padding(8).frame(maxWidth:.infinity,alignment:.leading).background(GameTheme.boardPanel)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
            .onAppear {withAnimation(reduced ? nil:.easeInOut(duration:0.9)){entered=true}}
    }
}

// These intervals affect presentation only; input windows, pitch speed and saved outcomes stay unchanged.
enum DeliveryPresentation {
    static func flight(_ duration: Double, reduced: Bool, role: PlayerRole = .batter) -> Double { reduced && role == .batter ? 0.15 : duration }
    static func receipt(reduced: Bool, match: Bool = false) -> Double { (reduced ? 0.8 : 1.1) + (match ? 1:0) }
    static func trainingMotion(reduced: Bool) -> Double { reduced ? 0.15 : 0.9 }
    static func trainingRead(reduced: Bool) -> Double { reduced ? 0.8 : 1.1 }
    static func call(_ outcome: String) -> String {
        outcome == "루킹 스트라이크" ? "스트라이크" : outcome
    }
}

struct PitchJudgmentToast: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.system(.headline, design: .monospaced, weight: .heavy))
            if let detail { Text(detail).font(.caption2.monospaced().bold()) }
        }.foregroundStyle(GameTheme.paper).padding(.horizontal, 14).padding(.vertical, 8)
            .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2))
            .overlay(alignment: .bottom) {
                Rectangle().fill(GameTheme.gold).frame(width: 8, height: 4).offset(y: 4)
            }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
            .allowsHitTesting(false)
    }
}

struct PitchLocationBoard: View {
    let result: ManualMatchResult?
    let side: OpponentBatterSide
    @Environment(\.dynamicTypeSize) private var typeSize
    static func marker(x: Double, y: Double, size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (0.08 + 0.84 * min(1, max(0, x))),
                y: size.height * (0.08 + 0.84 * min(1, max(0, y))))
    }
    var body: some View {
        VStack(spacing: 3) {
            Text(side.label).foregroundStyle(GameTheme.gold)
            Canvas { context, size in
                let a = Self.marker(x: 0.2, y: 0.2, size: size), b = Self.marker(x: 0.8, y: 0.8, size: size)
                context.stroke(Path(CGRect(x: a.x, y: a.y, width: b.x-a.x, height: b.y-a.y)), with: .color(GameTheme.boardInk), lineWidth: 1)
                for value in [0.4,0.6] {
                    let x = Self.marker(x:value,y:0,size:size).x, y = Self.marker(x:0,y:value,size:size).y
                    var line = Path(); line.move(to:CGPoint(x:x,y:a.y)); line.addLine(to:CGPoint(x:x,y:b.y))
                    line.move(to:CGPoint(x:a.x,y:y)); line.addLine(to:CGPoint(x:b.x,y:y))
                    context.stroke(line,with:.color(GameTheme.boardLine),lineWidth:0.5)
                }
                if let result {
                    let p = Self.marker(x:result.x,y:result.y,size:size)
                    PixelBaseball.draw(in:context,at:p,diameter:8)
                }
            }.aspectRatio(1,contentMode:.fit).accessibilityHidden(true)
            Text(result == nil ? "도착 대기" : "실제 도착 코스")
                .foregroundStyle(GameTheme.boardInk)
        }.font(typeSize.isAccessibilitySize ? .caption2 : .system(size:10,weight:.bold,design:.monospaced))
            .padding(5).background(GameTheme.board.opacity(0.94))
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(side.label) · \(side.mapOnRight ? "오른쪽" : "왼쪽") 코스 보드")
            .accessibilityValue(result.map { "실제 도착 가로 \(Int(($0.x*100).rounded())), 세로 \(Int(($0.y*100).rounded())), \(ManualMatchRules.isStrike(x:$0.x,y:$0.y) ? "존 안" : "존 밖")" } ?? "도착 대기")
            .accessibilityIdentifier("pitchLocationBoard")
            .allowsHitTesting(false)
    }
}

// One code-drawn pixel asset shared by SpriteKit and SwiftUI; transparent corners keep it round.
@MainActor enum PixelBaseball {
    static let rows = ["....oooo....","..oowwwwoo..",".owrwwwwrwo.",".owwrwwrwwwo","owwwwrrwwwwo","owwwwwwwwwwo","owwwwwwwwwwo","owwwwrrwwwwo",".owwrwwrwwwo",".owrwwwwrwo.","..oossssoo..","....oooo...."]
    static let image: UIImage = {
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=false
        return UIGraphicsImageRenderer(size:CGSize(width:12,height:12),format:format).image {renderer in
            let colors:[Character:UIColor] = ["o":UIColor(red:0.26,green:0.34,blue:0.39,alpha:1),"w":UIColor(red:0.98,green:0.98,blue:0.93,alpha:1),"r":UIColor(red:0.78,green:0.24,blue:0.22,alpha:1),"s":UIColor(red:0.72,green:0.78,blue:0.78,alpha:1)]
            for (y,row) in rows.enumerated() {for (x,key) in row.enumerated() {
                guard let color=colors[key] else {continue};renderer.cgContext.setFillColor(color.cgColor)
                renderer.cgContext.fill(CGRect(x:x,y:y,width:1,height:1))
            }}
        }
    }()
    static let texture: SKTexture = {let t=SKTexture(image:image);t.filteringMode = .nearest;return t}()
    static func draw(in context: GraphicsContext, at point: CGPoint, diameter: CGFloat) {
        let transform=context.transform
        let scaleX=hypot(transform.a,transform.b),scaleY=hypot(transform.c,transform.d)
        let height=scaleY > 0 ? diameter*scaleX/scaleY:diameter
        context.draw(Image(uiImage:image).interpolation(.none),in:CGRect(x:point.x-diameter/2,y:point.y-height/2,width:diameter,height:height))
    }
}
