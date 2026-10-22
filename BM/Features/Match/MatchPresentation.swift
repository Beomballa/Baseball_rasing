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
            return play.fly == nil ? abs(sin(t * .pi * 4))*3:sin(t * .pi)*height*0.19 + (play.fly?.caught == true ? t*height*0.035:0)
        }
        for (a,b) in zip(play.ball,play.ball.dropFirst()) where time>=a.at && time<b.at && a.at>=play.releaseAt && a.point != b.point {
            return height*0.035 + sin(.pi*(time-a.at)/max(0.001,b.at-a.at))*height*0.035
        }
        return time>=play.pickupAt ? height*0.035:0
    }
    static func opponentKit(_ own:Int) -> Int {
        [0x294c77,0xf0ead9,0x9a3e39].max {a,b in
            func distance(_ color:Int) -> Int {
                [0,8,16].reduce(0) {sum,shift in let d=((color>>shift)&255)-((own>>shift)&255);return sum+d*d}
            }
            return distance(a)<distance(b)
        }!
    }
    static func pose(_ play:MatchDetailedPlay,index:Int,time:Double,moving:Bool) -> String {
        let throwEvents=[(play.fielder,play.releaseAt),(play.receiver,play.secondThrow?.releaseAt ?? -10),(play.relay?.fielder ?? -1,play.relay?.releaseAt ?? -10)]
        if throwEvents.contains(where:{$0.0 == index && abs(time-$0.1)<0.26}) {return "throw"}
        let catches=[(play.fielder,play.pickupAt),(play.receiver,play.ballAt),(play.relay?.fielder ?? -1,play.relay?.receiveAt ?? -10)]
        if catches.contains(where:{$0.0 == index && abs(time-$0.1)<0.22}) {return "catch"}
        return moving ? "run":"ready"
    }
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
                Text(phase).font(.system(.caption,design:.monospaced,weight:.bold)).foregroundStyle(GameTheme.gold)
                    .lineLimit(2).accessibilityIdentifier("fieldReplayPhase")
                Canvas { context,size in
                    func point(_ p:FieldPoint) -> CGPoint {CGPoint(x:size.width*(0.5+p.x/145),y:size.height*(0.94-p.y/150))}
                    func path(_ points:[FieldPoint],closed:Bool=false) -> Path {
                        Path {p in guard let first=points.first else {return};p.move(to:point(first))
                            for next in points.dropFirst() {p.addLine(to:point(next))};if closed {p.closeSubpath()}}
                    }
                    func rect(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ hex:Int) {
                        context.fill(Path(CGRect(x:x,y:y,width:w,height:h)),with:.color(Color(hex:hex)))
                    }
                    rect(0,0,size.width,size.height,0x17374d)
                    // Pixel stands use the pitching scene's navy seats, warm skin and cream rails.
                    let cell=max(8,size.width/38)
                    for row in 0..<4 {for col in 0..<40 {
                        let x=Double(col)*cell,y=Double(row)*cell*0.55
                        let skin=[0xefbe91,0xc68a63,0xf0d0a3][(col+row)%3]
                        rect(x,y,cell-1,cell*0.5,(col+row)%3 == 0 ? 0x42617c:0x274967)
                        rect(x+cell*0.28,y+1,cell*0.42,cell*0.18,skin)
                        rect(x+cell*0.2,y,cell*0.58,2,(col+row)%4 == 0 ? 0xefe9d6:0x153452)
                        rect(x+cell*0.16,y+cell*0.22,cell*0.68,cell*0.26,(col+row)%5 == 0 ? 0xefe9d6:0x345e84)
                    }}
                    rect(0,size.height*0.14,size.width,3,0xa4b8b4)
                    rect(0,size.height*0.15,size.width,size.height*0.07,0x13394f)
                    rect(size.width*0.31,3,size.width*0.38,size.height*0.115,0x102a3f)
                    context.stroke(Path(CGRect(x:size.width*0.31,y:3,width:size.width*0.38,height:size.height*0.115)),with:.color(GameTheme.gold),lineWidth:2)
                    context.draw(Text(scoreText).font(.system(size:max(8,size.width*0.025),weight:.heavy,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:size.width*0.5,y:size.height*0.045))
                    context.draw(Text(finished ? "PLAY COMPLETE":"IN PLAY").font(.system(size:max(6,size.width*0.018),weight:.bold,design:.monospaced)).foregroundStyle(GameTheme.gold),at:CGPoint(x:size.width*0.5,y:size.height*0.087))
                    let turf=[FieldPoint(x:0,y:0),FieldPoint(x:60,y:60),FieldPoint(x:45,y:99),FieldPoint(x:0,y:108),FieldPoint(x:-45,y:99),FieldPoint(x:-60,y:60)]
                    var grass=context;grass.clip(to:path(turf,closed:true))
                    grass.fill(Path(CGRect(x:0,y:0,width:size.width,height:size.height)),with:.color(Color(hex:0x33734f)))
                    for row in 0..<12 {
                        grass.fill(Path(CGRect(x:0,y:Double(row)*size.height/12,width:size.width,height:size.height/24)),with:.color(Color(hex:0x3b8157)))
                    }
                    context.stroke(path(turf,closed:true),with:.color(Color(hex:0xa67b4c)),lineWidth:10)
                    context.stroke(path(turf,closed:true),with:.color(Color(hex:0x254c61)),lineWidth:4)
                    context.fill(path(DetailedFieldRules.bases,closed:true),with:.color(Color(hex:0xa47a50)))
                    context.stroke(path(DetailedFieldRules.bases,closed:true),with:.color(Color(hex:0xeee7ca)),lineWidth:1)
                    context.stroke(path([FieldPoint(x:-60,y:60),FieldPoint(x:0,y:0),FieldPoint(x:60,y:60)]),with:.color(Color(hex:0xf0e4c6)),lineWidth:1.5)
                    let mound=point(DetailedFieldRules.positions[0])
                    context.fill(Path(ellipseIn:CGRect(x:mound.x-7,y:mound.y-4,width:14,height:8)),with:.color(Color(hex:0xb28758)))
                    for base in 0..<4 {
                        let b=point(DetailedFieldRules.bases[base]),w=max(4,size.width*0.016)
                        context.fill(Path(CGRect(x:b.x-w/2,y:b.y-w/2,width:w,height:w)),with:.color(base==target && time>=play.pickupAt ? GameTheme.gold:GameTheme.paper))
                    }
                    let ownKit=PlayerAppearance.kitColors[appearance.kit],opponent=FieldReplayPresentation.opponentKit(ownKit)
                    let defenseOwn=ownTeamFielding ?? !play.ownBatter
                    func actor(_ at:FieldPoint,own:Bool,teamOwn:Bool,moving:Bool,pose:String,number:Int,out:Bool=false) {
                        let c=point(at),u=max(0.8,size.width/285)
                        let stride=moving ? sin(time*17)*2:0
                        let shirt=teamOwn ? ownKit:opponent
                        let skin=own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91
                        func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ hex:Int) {
                            context.fill(Path(CGRect(x:c.x+x*u,y:c.y+y*u,width:w*u,height:h*u)),with:.color(Color(hex:hex).opacity(out ? 0.4:1)))
                        }
                        box(-5,3,10,2,0x20543c)
                        box(-3,-15,6,5,skin);box(-4,-16,8,3,shirt);box(-4,-13,3,1,own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48)
                        box(3,-14,3,2,shirt);box(-4,-10,8,8,shirt);box(-4,-3,8,1,0xf0ead9)
                        box(-4,-2,3,5+stride,0xe8e9dd);box(1,-2,3,5-stride,0xe8e9dd)
                        box(-4,3+stride,3,2,0x102a3f);box(1,3-stride,3,2,0x102a3f)
                        let armX=pose == "throw" ? 6.0:pose == "catch" ? 5:4
                        let armY=pose == "throw" ? -16.0:pose == "catch" ? -10:-8
                        let left=own && throwingHand == "left"
                        box(left ? 4:-6,pose == "catch" ? -12:-9+stride,2,4,skin);box(left ? -armX-2:armX,armY,2,5,skin)
                        let gloveX=pose == "catch" ? -8.0:-7
                        box(left ? -gloveX-4:gloveX,pose == "catch" ? -12:-6,4,4,0x976037)
                        box(left ? -gloveX-3:gloveX+1,pose == "catch" ? -11:-5,2,2,0xc99b5e)
                        context.draw(Text("\(number)").font(.system(size:5*u,weight:.black,design:.monospaced)).foregroundStyle(Color(hex:shirt == 0xf0ead9 ? 0x18344b:0xf3ecd3)),at:CGPoint(x:c.x,y:c.y-6*u))
                        if own {box(-1,-20,2,2,0xecc66b)}
                    }
                    for index in play.fielders.indices {
                        let nodes=play.fielders[index],p=FieldNode.sample(nodes,at:time)
                        let moving=p.distance(to:FieldNode.sample(nodes,at:time+0.06))>0.001
                        let own=defenseOwn && (ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index==play.fielder))
                        actor(p,own:own,teamOwn:defenseOwn,moving:moving,pose:FieldReplayPresentation.pose(play,index:index,time:time,moving:moving),number:own ? jerseyNumber:index+1)
                    }
                    for runner in play.runners {
                        let p=FieldNode.sample(runner.nodes,at:time),moving=p.distance(to:FieldNode.sample(runner.nodes,at:time+0.06))>0.001
                        actor(p,own:runner.profile.own,teamOwn:!defenseOwn,moving:moving,pose:"run",number:runner.profile.own ? jerseyNumber:runner.from+10,out:finished && runner.out)
                    }
                    let groundBall=point(FieldNode.sample(play.ball,at:time)),loft=FieldReplayPresentation.lift(play,time:time,height:size.height)
                    context.fill(Path(ellipseIn:CGRect(x:groundBall.x-3,y:groundBall.y-1,width:6,height:2)),with:.color(.black.opacity(0.4)))
                    for i in 1...3 where time<Double(play.ball.last?.at ?? 0) {
                        let before=max(0,time-Double(i)*0.04),p=point(FieldNode.sample(play.ball,at:before))
                        context.fill(Path(CGRect(x:p.x,y:p.y-FieldReplayPresentation.lift(play,time:before,height:size.height),width:2,height:2)),with:.color(GameTheme.paper.opacity(0.4)))
                    }
                    PixelBaseball.draw(in:context,at:CGPoint(x:groundBall.x,y:groundBall.y-loft),diameter:max(7,size.width*0.022))
                    if finished {
                        let label=play.misplay != nil ? "ERROR":play.secondThrow?.out == true ? "DOUBLE PLAY":play.fly?.caught == true && play.targetRunner == nil ? "CATCH · OUT":play.out ? "OUT":"SAFE"
                        let frame=CGRect(x:size.width*0.18,y:size.height*0.27,width:size.width*0.64,height:32)
                        context.fill(Path(frame),with:.color(GameTheme.board.opacity(0.96)))
                        context.stroke(Path(frame),with:.color(GameTheme.gold),lineWidth:2)
                        context.draw(Text(label).font(.system(size:18,weight:.black,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:frame.midX,y:frame.midY))
                    }
                }.accessibilityLabel(finished ? "도트 수비 주루 재생 · "+play.summary:"인플레이 · "+(play.fly == nil ? "땅볼":"공중 타구"))
                    .accessibilityIdentifier("fieldReplayCanvas")
                if finished && !animated {
                if let error=play.misplay {
                    Text("실책 \(error.at,specifier:"%.2f")초 → 회수 \(error.recoveredAt,specifier:"%.2f")초 · 추가 \(error.extraBases.values.reduce(0,+))베이스")
                        .font(.caption2.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayMisplayTimes")
                    Text(error.reachedOnError ? "실책 출루 · 안타 제외" : "정상 타격 기록 유지 · 실책 추가 진루 분리")
                        .font(.caption2).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayMisplayScoring")
                }
                if let relay=play.relay {
                    Text("중계 \(DetailedFieldRules.names[relay.fielder]) · 수신 \(relay.receiveAt,specifier:"%.2f")초 / 재송구 \(relay.releaseAt,specifier:"%.2f")초")
                        .font(.caption2.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayRelayTimes")
                    Text("직접 \(relay.directAt,specifier:"%.2f")초 → 중계 \(play.controlAt,specifier:"%.2f")초")
                        .font(.caption2.monospaced()).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayRouteComparison")
                }
                if let fly=play.fly,play.misplay == nil {
                    Text("공 낙하 \(play.flight,specifier:"%.2f")초 / 포구 준비 \(fly.reachAt,specifier:"%.2f")초 · \(fly.caught ? "포구 성공" : "낙하 후 처리")")
                        .font(.caption2.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayCatchTimes")
                }
                if play.misplay == nil && (play.fly?.caught != true || play.targetRunner != nil) {
                Text("\(play.targetBase == 4 ? "홈" : "\(play.targetBase)루") · 공 \(play.controlAt,specifier:"%.2f")초 / 주자 \(play.runnerAt.map { String(format:"%.2f초",$0) } ?? "진루 완료")")
                    .font(.caption2.monospaced()).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayTimes")
                }
                if let second {
                    Text("1루 · 공 \(second.controlAt,specifier:"%.2f")초 / 타자 \(second.runnerAt,specifier:"%.2f")초")
                        .font(.caption2.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplaySecondTimes")
                }
                }
            }.padding(6).background(GameTheme.board)
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
