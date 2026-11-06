import SpriteKit
import SwiftUI
import UIKit

private struct UniformTrouserRows {
    private var ranges: [ClosedRange<Int>?]
    private var top: Int
    private var bottom = 0

    init(height: Int) {
        ranges = Array(repeating: nil, count: height)
        top = height
    }

    mutating func insert(x: Int, y: Int) {
        let range = ranges[y] ?? x...x
        ranges[y] = min(range.lowerBound, x)...max(range.upperBound, x)
        top = min(top, y)
        bottom = max(bottom, y)
    }

    func position(x: Int, y: Int) -> (x: Double, y: Double)? {
        guard let range = ranges[y] else { return nil }
        let u = (Double(x - range.lowerBound) + 0.5) / Double(range.count)
        let v = (Double(y - top) + 0.5) / Double(bottom - top + 1)
        return (u, v)
    }
}

/// 원화에 저장된 외형·유니폼·등번호를 합성하고 동작 텍스처를 재사용한다.
@MainActor enum PlayerMotionArt {
    static func sourceName(role: PlayerRole) -> String {
        role == .pitcher ? "pitcher-delivery-v75" : "batter-actions-v75"
    }
    private static let cache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    /// 한 자세 셀에서 색을 바꿀 영역과 등번호를 그릴 위치다.
    struct Pose {
        let shirt: [CGPoint]
        let hair: CGRect
        let skin: [CGRect]
        let number: CGPoint
        var angle: Double = 0
        var erase: CGRect = .zero
        var numberUnit = 5
        var numberClip: CGRect = .zero
        var pants: CGRect = .zero
    }
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
    private static func polygon(_ pairs: [(Double, Double)]) -> [CGPoint] { pairs.map { CGPoint(x: $0.0, y: $0.1) } }

    // Ankle guides follow the exposed sock between the pants hem and the shoe in each authored pose.
    private struct SockGuide {
        let top: CGPoint
        let bottom: CGPoint
        let width: Double

        func position(x: Int, y: Int) -> Double? {
            let dx = bottom.x - top.x, dy = bottom.y - top.y
            let px = Double(x) - top.x, py = Double(y) - top.y
            let lengthSquared = dx * dx + dy * dy
            let progress = (px * dx + py * dy) / lengthSquared
            guard (0...1).contains(progress), abs(px * dy - py * dx) <= width * sqrt(lengthSquared) else { return nil }
            return progress
        }
    }

    private static func sockGuides(role: PlayerRole, frame: Int) -> [SockGuide] {
        let guides: [[(Double, Double, Double, Double, Double)]] = role == .pitcher ? [
            [(234, 390, 225, 434, 21), (343, 392, 354, 432, 20)],
            [(209, 327, 225, 350, 13), (287, 396, 289, 433, 20)],
            [(185, 399, 165, 430, 21), (374, 397, 400, 430, 22)],
            [(246, 368, 224, 406, 20), (358, 365, 385, 402, 18)],
            [(223, 361, 222, 405, 17), (365, 311, 395, 296, 17)],
            [(211, 368, 191, 405, 20), (319, 367, 335, 403, 20)],
        ] : [
            [(174, 398, 161, 434, 21), (247, 418, 242, 452, 23)],
            [(182, 420, 174, 457, 21), (265, 372, 265, 402, 21)],
            [(103, 422, 90, 444, 20), (235, 422, 247, 451, 23)],
            [(206, 384, 175, 408, 21), (285, 394, 296, 423, 22)],
            [(146, 380, 126, 413, 25), (237, 371, 238, 400, 20)],
            [(136, 390, 115, 419, 25), (226, 375, 231, 401, 21)],
        ]
        return guides[frame].map { SockGuide(top: CGPoint(x: $0.0, y: $0.1), bottom: CGPoint(x: $0.2, y: $0.3), width: $0.4) }
    }
    /// 유효한 원화 프레임(0~5)의 의상·피부·번호 마스크를 반환한다.
    static func pose(role: PlayerRole, frame: Int) -> Pose {
        if role == .pitcher {
            let hair = [
                rect(235, 177, 102, 44), rect(218, 166, 102, 44), rect(221, 201, 97, 41), rect(222, 174, 103, 42),
                rect(147, 198, 91, 45), rect(216, 185, 102, 43),
            ]
            let skin = [
                [rect(215, 172, 136, 61), rect(199, 266, 38, 44)], [rect(204, 160, 132, 57), rect(181, 253, 46, 37)],
                [rect(202, 191, 139, 57), rect(153, 239, 48, 43), rect(331, 163, 66, 96)],
                [rect(208, 161, 137, 64), rect(204, 251, 46, 50), rect(329, 38, 97, 125)],
                [rect(133, 190, 113, 61), rect(200, 282, 105, 78)],
                [rect(180, 171, 150, 70), rect(173, 258, 75, 51), rect(329, 270, 35, 38)],
            ]
            let centers = [
                CGPoint(x: 303, y: 266), CGPoint(x: 291, y: 251), CGPoint(x: 301, y: 286), CGPoint(x: 299, y: 245),
                CGPoint(x: 264, y: 244), CGPoint(x: 288, y: 252),
            ]
            let erase = [
                rect(264, 237, 76, 57), rect(253, 222, 77, 59), rect(262, 255, 76, 60), rect(264, 216, 76, 58),
                rect(220, 208, 87, 66), rect(252, 223, 76, 58),
            ]
            let shirts = [
                polygon([(260, 229), (327, 229), (339, 252), (339, 300), (246, 301), (251, 258)]),
                polygon([(258, 215), (319, 215), (332, 238), (326, 291), (240, 279), (246, 241)]),
                polygon([(260, 246), (326, 247), (335, 268), (334, 324), (252, 322), (251, 277)]),
                polygon([(259, 212), (324, 212), (343, 238), (337, 278), (253, 287), (253, 246)]),
                polygon([(218, 239), (245, 218), (273, 209), (307, 231), (323, 250), (273, 280), (244, 270)]),
                polygon([(257, 220), (316, 220), (337, 240), (335, 284), (254, 286), (252, 249)]),
            ]
            return Pose(
                shirt: shirts[frame], hair: hair[frame], skin: skin[frame], number: centers[frame],
                angle: frame == 4 ? -0.5 : 0, erase: erase[frame], numberUnit: 6, numberClip: erase[frame],
                pants: [
                    rect(205, 309, 156, 82), rect(174, 286, 155, 108), rect(182, 329, 212, 91),
                    rect(219, 280, 135, 106), rect(269, 250, 135, 83), rect(208, 288, 157, 95),
                ][frame])
        }
        let shirts = [
            polygon([(198, 180), (230, 178), (270, 201), (278, 264), (251, 291), (154, 279), (164, 237), (179, 200)]),
            polygon([(163, 196), (203, 187), (258, 204), (262, 270), (238, 303), (153, 298), (164, 258)]),
            polygon([(143, 203), (195, 209), (238, 231), (244, 280), (200, 316), (112, 303), (122, 246)]),
            polygon([(197, 151), (265, 169), (337, 199), (339, 243), (304, 270), (211, 266), (198, 216)]),
            polygon([(158, 182), (207, 183), (260, 208), (271, 246), (241, 280), (118, 270), (132, 224)]),
            polygon([(151, 187), (205, 186), (260, 209), (269, 248), (239, 281), (116, 275), (129, 227)]),
        ]
        let hair = [
            rect(248, 168, 58, 25), rect(209, 177, 62, 33), rect(178, 180, 78, 36), rect(255, 143, 70, 32),
            rect(215, 177, 72, 35), rect(210, 179, 72, 35),
        ]
        let skin = [
            [rect(258, 160, 68, 47), rect(264, 188, 85, 60)], [rect(210, 174, 79, 44), rect(85, 164, 78, 65)],
            [rect(171, 181, 110, 46), rect(248, 231, 81, 59)], [rect(252, 142, 90, 49), rect(180, 90, 65, 51)],
            [rect(210, 175, 97, 53), rect(231, 225, 114, 52)], [rect(203, 176, 100, 53), rect(230, 223, 111, 55)],
        ]
        // 팔에 가려지지 않은 등 영역에 번호를 놓아 어깨 위로 번지지 않게 한다.
        let centers = [
            CGPoint(x: 188, y: 252), CGPoint(x: 204, y: 280), CGPoint(x: 161, y: 278), CGPoint(x: 277, y: 226),
            CGPoint(x: 146, y: 248), CGPoint(x: 143, y: 250),
        ]
        let clips = [
            rect(168, 233, 42, 39), rect(180, 265, 48, 28), rect(137, 256, 49, 43), rect(236, 200, 79, 54),
            rect(130, 232, 33, 31), rect(127, 234, 33, 31),
        ]
        let units = [4, 4, 4, 6, 3, 3]
        return Pose(
            shirt: shirts[frame], hair: hair[frame], skin: skin[frame], number: centers[frame],
            numberUnit: units[frame], numberClip: clips[frame],
            pants: [
                rect(149, 291, 113, 133), rect(167, 306, 139, 126), rect(119, 315, 143, 112), rect(191, 267, 117, 126),
                rect(127, 280, 149, 130), rect(125, 281, 149, 130),
            ][frame])
    }
    /// 외형·유니폼·번호·투구 손을 키에 포함해 다른 선수의 캐시가 섞이지 않게 한다.
    static func cacheKey(role: PlayerRole, appearance: PlayerAppearance, number: Int, hand: String) -> String {
        ([role.rawValue, hand, appearance.uniformStyle?.id ?? "legacy"]
            + [
                appearance.creationVersion ?? 0, appearance.skin, appearance.hair, appearance.uniformColor,
                appearance.hairStyle, appearance.expression, number,
            ].map(String.init)).joined(separator: ":")
    }
    /// 6개 자세가 모두 준비됐을 때만 임시 보관해 다음 요청에서 재사용한다.
    static func textures(role: PlayerRole, appearance: PlayerAppearance, number: Int, hand: String) -> [SKTexture] {
        let key = cacheKey(role: role, appearance: appearance, number: number, hand: hand) as NSString
        if let cached = cache.object(forKey: key) as? [SKTexture] { return cached }
        let result = (0..<6).compactMap { frame -> SKTexture? in
            guard let image = image(role: role, frame: frame, appearance: appearance, number: number, hand: hand) else {
                return nil
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            return texture
        }
        if result.count == 6 { cache.setObject(result as NSArray, forKey: key, cost: 6 * 512 * 512 * 4) }
        return result
    }
    // 이 시점에서는 헬멧 아래 목덜미만 보여 원화의 전체 머리 윤곽은 유지한다.
    static func napeDepth(style: Int, x: Double) -> Double {
        let x = min(1, max(0, x))
        switch style {
        case 1: return 0.56 + x * 0.28
        case 2: return 0.82 + (Int(x * 8) % 2 == 0 ? 0.12 : 0)
        case 3: return 0.46
        case 4: return 0.98 - abs(x - 0.5) * 0.12
        case 5: return 0.58 + abs(x - 0.5) * 0.62
        case 6: return 0.62 + (Int(x * 6) % 2 == 0 ? 0.18 : 0)
        case 7: return 0.80 + sin(x * .pi * 3) * 0.12
        default: return 0.72
        }
    }
    // 의상 마스크와 등번호 위치는 원화의 512px 자세 셀 기준이다.
    /// 원화 픽셀의 음영·투명도를 유지하며 외형과 복장을 합성한다. 유효하지 않으면 결과 없음(nil)을 반환한다.
    static func image(role: PlayerRole, frame: Int, appearance: PlayerAppearance, number: Int, hand: String) -> UIImage?
    {
        guard (0..<6).contains(frame), appearance.isValid, (0...99).contains(number),
            let original = MatchArt.cell(
                sourceName(role: role), column: frame % 3, row: frame / 3, columns: 3, rows: 2)?.cgImage,
            original.width == 512, original.height == 512
        else { return nil }
        let width = original.width
        let height = original.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: colorSpace, bitmapInfo: format)
            else { return false }
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard decoded else { return nil }
        let pose = pose(role: role, frame: frame)
        let shirt = CGMutablePath()
        if let first = pose.shirt.first {
            shirt.move(to: first)
            for point in pose.shirt.dropFirst() { shirt.addLine(to: point) }
            shirt.closeSubpath()
        }
        let style = appearance.uniformStyle
        let kit = appearance.uniformColor
        let skin = PlayerAppearance.skinColors[appearance.skin]
        let hair = PlayerAppearance.hairColors[appearance.hair]
        func rgb(_ hex: Int, _ shade: Double) -> (Int, Int, Int) {
            (
                min(255, Int(Double((hex >> 16) & 255) * shade)), min(255, Int(Double((hex >> 8) & 255) * shade)),
                min(255, Int(Double(hex & 255) * shade))
            )
        }
        var shirtShade = [Double](repeating: 0.95, count: height)
        if role == .pitcher {
            for y in Int(pose.erase.minY)..<Int(pose.erase.maxY) {
                var sum = 0.0
                var count = 0.0
                for x in Int(pose.erase.minX)..<Int(pose.erase.maxX) {
                    let i = (y * width + x) * 4
                    let a = Int(bytes[i + 3])
                    guard a > 128 else { continue }
                    let r = Double(bytes[i]) * 255 / Double(a)
                    let g = Double(bytes[i + 1]) * 255 / Double(a)
                    let b = Double(bytes[i + 2]) * 255 / Double(a)
                    if b > 36 && b > r * 1.35 && b > g * 1.1 {
                        sum += b / 135
                        count += 1
                    }
                }
                if count > 0 { shirtShade[y] = max(0.25, min(1.6, sum / count)) }
            }
        }
        let mouths = [
            CGPoint(x: 303, y: 193), CGPoint(x: 264, y: 206), CGPoint(x: 262, y: 218), CGPoint(x: 314, y: 180),
            CGPoint(x: 273, y: 205), CGPoint(x: 270, y: 206),
        ]
        let mouth = mouths[frame]
        let bounds = shirt.boundingBox
        let proStyle = style.flatMap { $0.pro == nil ? nil : $0 }
        let mirrored = role == .pitcher && hand == "left"
        let sockGuides = proStyle == nil ? [] : sockGuides(role: role, frame: frame)
        var trouserRows = UniformTrouserRows(height: height)
        if proStyle != nil {
            for y in Int(pose.pants.minY)..<Int(pose.pants.maxY) {
                for x in Int(pose.pants.minX)..<Int(pose.pants.maxX) {
                    let i = (y * width + x) * 4
                    let a = Int(bytes[i + 3])
                    guard a > 128 else { continue }
                    let r = Int(bytes[i]) * 255 / a, g = Int(bytes[i + 1]) * 255 / a, b = Int(bytes[i + 2]) * 255 / a
                    if min(r, g, b) > 105 && max(r, g, b) - min(r, g, b) < 70 {
                        trouserRows.insert(x: x, y: y)
                    }
                }
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let alpha = Int(bytes[index + 3])
                guard alpha > 16 else { continue }
                let r = Int(bytes[index]) * 255 / alpha
                let g = Int(bytes[index + 1]) * 255 / alpha
                let b = Int(bytes[index + 2]) * 255 / alpha
                let point = CGPoint(x: x, y: y)
                let high = max(r, g, b)
                let low = min(r, g, b)
                var color: (Int, Int, Int)?
                let torso = shirt.contains(point)
                let ny = (Double(y) - bounds.minY) / bounds.height
                let jersey = torso ? style?.shirt(x: (Double(x) - bounds.minX) / bounds.width, y: ny,
                                                 back: true, mirrored: mirrored) ?? kit : kit
                let onCap =
                    Double(y) < pose.hair.minY + 8 && Double(x) > pose.hair.minX - 38 && Double(x) < pose.hair.maxX + 24
                if role == .pitcher && pose.erase.contains(point) && torso && high > 24 {
                    color = rgb(jersey, shirtShade[y])
                } else if b > 36 && Double(b) > Double(r) * 1.35 && Double(b) > Double(g) * 1.1 {
                    let cap = Double(y) > pose.hair.minY - 8 ? style?.brim : style?.cap
                    var base = torso ? jersey : onCap ? cap ?? kit : style?.sleeves ?? kit
                    if let proStyle, !torso && !onCap {
                        if let sockY = sockGuides.lazy.compactMap({ $0.position(x: x, y: y) }).first {
                            base = proStyle.sock(base: proStyle.sleeves, y: sockY)
                        } else if Double(y) > pose.pants.minY + 12, pose.pants.contains(point),
                                  let leg = trouserRows.position(x: x, y: y), (0...1).contains(leg.x) {
                            base = proStyle.leg(base: proStyle.pants, x: leg.x, y: leg.y, back: true, mirrored: mirrored)
                        } else if (0...1).contains(ny) && Double(y) < pose.pants.minY {
                            base = proStyle.sleeve(base: base, y: ny)
                        }
                    }
                    color = rgb(base, max(0.25, min(1.6, Double(b) / 135)))
                } else if role == .batter && low > 90 && high - low < 70 && torso {
                    color = rgb(jersey, max(0.35, Double(r + g + b) / 720))
                } else if let style, pose.pants.contains(point), low > 105, high - low < 70 {
                    let leg = trouserRows.position(x: x, y: y)
                    let base = leg.map { style.leg(base: style.pants, x: $0.x, y: $0.y, back: true, mirrored: mirrored) } ?? style.pants
                    color = rgb(base, max(0.35, min(1.1, Double(r + g + b) / 735)))
                } else if pose.hair.contains(point) && high > 22 && high - low < 34 {
                    if appearance.creationVersion == 1 {
                        let hx = (Double(x) - pose.hair.minX) / pose.hair.width
                        let hy = (Double(y) - pose.hair.minY) / pose.hair.height
                        let cropped = hy > napeDepth(style: appearance.hairStyle, x: hx)
                        color = rgb(cropped ? skin : hair, cropped ? 0.68 : max(0.35, min(1.15, Double(high) / 52)))
                    } else {
                        let shaved = appearance.hairStyle == 1 && Double(x) < pose.hair.minX + pose.hair.width * 0.25
                        color = rgb(shaved ? skin : hair, max(0.35, min(1.15, Double(high) / 52)))
                    }
                } else if pose.skin.contains(where: { $0.contains(point) }) && r > 175 && Double(r) > Double(g) * 1.12
                    && Double(g) > Double(b) * 1.12
                {
                    color = rgb(skin, max(0.5, min(1.15, Double(r) / 247)))
                }
                if appearance.creationVersion != 1 && appearance.hairStyle == 2 && pose.hair.contains(point)
                    && Double(y) > pose.hair.maxY - 7 && high > 30 && high - low < 90 && (x / 6) % 2 == 0
                {
                    color = rgb(hair, 0.8)
                }
                if appearance.creationVersion != 1 && role == .batter && appearance.expression > 0 {
                    if abs(Double(x) - mouth.x) <= 3 && abs(Double(y) - mouth.y) <= (appearance.expression == 2 ? 2 : 0)
                        && r > 175 && Double(r) > Double(g) * 1.12 && Double(g) > Double(b) * 1.12
                    {
                        color = rgb(0x85442e, 0.8)
                    }
                }
                if let color {
                    bytes[index] = UInt8(color.0 * alpha / 255)
                    bytes[index + 1] = UInt8(color.1 * alpha / 255)
                    bytes[index + 2] = UInt8(color.2 * alpha / 255)
                }
            }
        }
        if let style, role == .batter {
            let helmet = [
                CGPoint(x: 280, y: 133), CGPoint(x: 256, y: 143), CGPoint(x: 220, y: 151), CGPoint(x: 301, y: 106),
                CGPoint(x: 259, y: 145), CGPoint(x: 254, y: 146),
            ]
            style.drawMark(at: helmet[frame], unit: 1, bytes: &bytes, width: width, height: height)
        }
        // 무늬 위에서도 번호를 읽을 수 있게 대비되는 1픽셀 테두리를 넣는다.
        let ink = style?.ink ?? 0xf4f0db
        let outline = GameUniformStyle.outline(for: ink)
        drawNumber(
            number, at: pose.number, angle: pose.angle, mirrored: role == .pitcher && hand == "left",
            unit: pose.numberUnit, ink: ink, outline: outline, clip: pose.numberClip,
            bytes: &bytes, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: format), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }
    nonisolated static let digits = [
        "111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
        "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
    ]
    /// 등번호를 회전·반전한 뒤 보이는 의상 영역 안에만 그린다.
    nonisolated static func drawNumber(
        _ number: Int, at center: CGPoint, angle: Double, mirrored: Bool, unit: Int, ink: Int = 0xf4f0db,
        outline: Int? = nil, clip: CGRect? = nil, eligible: [Bool]? = nil, bytes: inout [UInt8], width: Int, height: Int
    ) {
        let masks = String(number).compactMap { $0.wholeNumberValue }.map { Array(digits[$0]) }
        let columns = masks.count * 4 - 1
        let textWidth = Double(columns * unit)
        let textHeight = Double(5 * unit)
        let cosine = cos(angle)
        let sine = sin(angle)
        for y in max(0, Int(center.y) - 70)..<min(height, Int(center.y) + 70) {
            for x in max(0, Int(center.x) - 70)..<min(width, Int(center.x) + 70) {
                let dx = Double(x) - center.x
                let dy = Double(y) - center.y
                let localX = (dx * cosine + dy * sine) * (mirrored ? -1 : 1) + textWidth / 2
                let localY = dy * cosine - dx * sine + textHeight / 2
                guard clip?.contains(CGPoint(x: x, y: y)) != false, eligible.map({ $0[y * width + x] }) != false else {
                    continue
                }
                func filled(_ px: Double, _ py: Double) -> Bool {
                    guard px >= 0, px < textWidth, py >= 0, py < textHeight else { return false }
                    let col = Int(px) / unit
                    let row = Int(py) / unit
                    return col % 4 < 3 && masks[col / 4][row * 3 + col % 4] == "1"
                }
                let inside = filled(localX, localY)
                let edge =
                    outline != nil
                    && [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)].contains { filled(localX + $0.0, localY + $0.1) }
                guard inside || edge else { continue }
                let color = inside ? ink : outline ?? ink
                let i = (y * width + x) * 4
                guard bytes[i + 3] > 128 else { continue }
                let a = Int(bytes[i + 3])
                bytes[i] = UInt8(((color >> 16) & 255) * a / 255)
                bytes[i + 1] = UInt8(((color >> 8) & 255) * a / 255)
                bytes[i + 2] = UInt8((color & 255) * a / 255)
            }
        }
    }
}

/// 전신 원화와 읽기 전용 재질/접지 정보를 준비한다. 경기 판정이나 원장에는 관여하지 않는다.
@MainActor enum FullBodyPitcherArt {
    struct Frame: Decodable {
        let rect: [Int]
        let hand: [Double]
        let leadFoot: [Double]
        let rearFoot: [Double]
        let offset: [Double]
        let shirt: [Double]
        let cap: [Double]
        let number: [Double]
        let numberAngle: Double
        let handVisible: Bool
        let clipRows: [[Int]]
        let coverageRuns: [[Int]]
    }
    struct Camera: Decodable {
        let file: String
        let frames: [Frame]
    }
    struct Manifest: Decodable {
        let progress: [Double]
        let back: Camera
        let front: Camera
    }
    struct RefinedDelivery: Decodable {
        let cell: Int
        let progress: [Double]
        let camera: Camera
    }
    final class Prepared: NSObject {
        let textures: [SKTexture]
        let camera: Camera
        let refined: RefinedDelivery?
        init(textures: [SKTexture], camera: Camera, refined: RefinedDelivery? = nil) {
            self.textures = textures
            self.camera = camera
            self.refined = refined
        }
    }
    private static let cache: NSCache<NSString, Prepared> = {
        let cache = NSCache<NSString, Prepared>()
        cache.countLimit = 4
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    static let manifest: Manifest? = {
        guard let url = Bundle.main.url(forResource: "pitcher-fullbody-v124", withExtension: "json", subdirectory: "MatchArt"),
              let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Manifest.self, from: bytes),
              value.progress.count == 32, value.back.frames.count == 32, value.front.frames.count == 32,
              zip(value.progress, value.progress.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return value
    }()
    private static let sources: [String: CGImage] = {
        var result: [String: CGImage] = [:]
        for file in ["pitcher-depth-back-v124", "pitcher-fullbody-front-v120"] {
            if let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "MatchArt"),
               let image = UIImage(contentsOfFile: url.path)?.cgImage { result[file] = image }
        }
        return result
    }()
    static func index(progress: Double) -> Int {
        guard let times = manifest?.progress else { return 0 }
        return times.lastIndex(where: { $0 <= max(0, progress) }) ?? 0
    }
    static let refinedDelivery: RefinedDelivery? = {
        guard let url = Bundle.main.url(forResource: "pitcher-delivery-back-v143", withExtension: "json", subdirectory: "MatchArt"),
              let bytes = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(RefinedDelivery.self, from: bytes),
              value.cell > 0, value.progress.count == value.camera.frames.count,
              value.progress.first == 0, value.progress.last == 2, value.progress.contains(1),
              zip(value.progress, value.progress.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return value
    }()
    private static let refinedSource: CGImage? = {
        guard let file = refinedDelivery?.camera.file,
              let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "MatchArt") else { return nil }
        return UIImage(contentsOfFile: url.path)?.cgImage
    }()
    static func refinedPreviewImage(appearance: PlayerAppearance, number: Int) -> UIImage? {
        guard appearance.isValid, (0...99).contains(number), let frame = refinedDelivery?.camera.frames.first,
              let refinedSource else { return nil }
        return refinedImage(frame, source: refinedSource, appearance: appearance, number: number, mirrored: false)
    }
    static func prepareRefined(appearance: PlayerAppearance, number: Int, hand: String) -> Prepared? {
        guard appearance.isValid, (0...99).contains(number), let refinedDelivery, let refinedSource else { return nil }
        let key = (PlayerMotionArt.cacheKey(role: .pitcher, appearance: appearance, number: number, hand: hand) + ":whole-v143") as NSString
        if let value = cache.object(forKey: key) { return value }
        let textures = refinedDelivery.camera.frames.compactMap { frame -> SKTexture? in
            guard let image = refinedImage(frame, source: refinedSource, appearance: appearance, number: number, mirrored: hand == "left") else { return nil }
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            return texture
        }
        guard textures.count == refinedDelivery.camera.frames.count else { return nil }
        let value = Prepared(textures: textures, camera: refinedDelivery.camera, refined: refinedDelivery)
        cache.setObject(value, forKey: key, cost: textures.count * refinedDelivery.cell * refinedDelivery.cell * 4)
        return value
    }
    private static func refinedImage(
        _ frame: Frame, source: CGImage, appearance: PlayerAppearance, number: Int, mirrored: Bool
    ) -> UIImage? {
        guard let image = source.cropping(to: CGRect(x: frame.rect[0], y: frame.rect[1], width: frame.rect[2], height: frame.rect[3])) else { return nil }
        let width = image.width, height = image.height
        let space = CGColorSpaceCreateDeviceRGB()
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: format) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard decoded else { return nil }
        let style = appearance.uniformStyle
        let kit = appearance.uniformColor
        let skin = PlayerAppearance.skinColors[appearance.skin]
        let hair = PlayerAppearance.hairColors[appearance.hair]
        let trim = style?.trim ?? 0xf4f1e0
        let pants = style?.pants ?? 0xf4f1e0
        let shade: [Double] = [0.43, 0.65, 0.85, 1.0]
        let proStyle = style.flatMap { $0.pro == nil ? nil : $0 }
        let cosine = cos(frame.numberAngle), sine = sin(frame.numberAngle)
        func shirtPosition(_ pixel: Int) -> (x: Double, y: Double) {
            let dx = Double(pixel % width) / Double(width) - frame.number[0]
            let dy = Double(pixel / width) / Double(height) - frame.number[1]
            return (0.5 + (dx * cosine + dy * sine) / frame.shirt[2],
                    0.5 + (-dx * sine + dy * cosine) / frame.shirt[3])
        }
        let feet = [frame.leadFoot, frame.rearFoot].map { CGPoint(x: $0[0] * Double(width), y: $0[1] * Double(height)) }
        var sockKinds = [UInt8](repeating: 0, count: proStyle == nil ? 0 : width * height)
        var sockTop = [height, height]
        var sockBottom = [0, 0]
        var sleeveEnds = [0.52, 0.52]
        var trouserRows = UniformTrouserRows(height: height)
        if proStyle != nil {
            // The V143 atlas preserves the ankle outlines and both original sock palettes.
            let sockTone: [Int: Int] = [0x122425: 0, 0x1b3335: 1, 0x264446: 2, 0x375757: 3,
                                        0x112b23: 0, 0x1d4435: 1, 0x32634a: 2, 0x558364: 3]
            for pixel in sockKinds.indices {
                let i = pixel * 4
                guard bytes[i + 3] == 255 else { continue }
                let x = pixel % width, y = pixel / width
                if bytes[i + 1] < 4 && bytes[i + 2] == 250 {
                    if bytes[i] == 3 {
                        trouserRows.insert(x: x, y: y)
                    } else if bytes[i] == 1 || bytes[i] == 5 {
                        let offset = shirtPosition(pixel).x - 0.5
                        let side = offset < 0 ? 0 : 1
                        sleeveEnds[side] = max(sleeveEnds[side], abs(offset))
                    }
                    continue
                }
                let rgb = (Int(bytes[i]) << 16) | (Int(bytes[i + 1]) << 8) | Int(bytes[i + 2])
                guard let tone = sockTone[rgb] else { continue }
                var candidate: (index: Int, distance: Double)?
                for (index, foot) in feet.enumerated() {
                    // The atlas registers each foot at the toe. The cuff sits inward from that point.
                    let dx = Double(x) - (foot.x + 7), dy = foot.y - Double(y)
                    guard (2...29).contains(dy), abs(dx) < 24 else { continue }
                    let distance = dx * dx + dy * dy
                    if distance < (candidate?.distance ?? .infinity) { candidate = (index, distance) }
                }
                guard let foot = candidate?.index else { continue }
                sockKinds[pixel] = UInt8(foot * 4 + tone + 1)
                sockTop[foot] = min(sockTop[foot], y)
                sockBottom[foot] = max(sockBottom[foot], y)
            }
            for foot in feet.indices {
                // Green pixels also outline the trouser seams above the sock in the source palette.
                sockTop[foot] = max(sockTop[foot], sockBottom[foot] - 13)
            }
        }
        func sleevePosition(x: Double) -> Double {
            let offset = x - 0.5
            let end = sleeveEnds[offset < 0 ? 0 : 1]
            return (abs(offset) - 0.38) / (end - 0.38)
        }
        var cloth = [Bool](repeating: false, count: width * height)
        for pixel in cloth.indices {
            let i = pixel * 4
            let tone: Double
            let color: Int
            if let proStyle, sockKinds[pixel] > 0 {
                let sock = Int(sockKinds[pixel]) - 1
                let foot = sock / 4
                let y = pixel / width
                guard y >= sockTop[foot] else { continue }
                let position = (Double(y - sockTop[foot]) + 0.5) / Double(sockBottom[foot] - sockTop[foot] + 1)
                color = proStyle.sock(base: proStyle.sleeves, y: position)
                tone = shade[sock % 4]
            } else {
                // Only authored uniform/appearance materials are replaced. Glove and outline ink stay untouched.
                guard bytes[i + 2] == 250, bytes[i + 3] == 255, bytes[i + 1] < 4 else { continue }
                tone = shade[Int(bytes[i + 1])]
                switch bytes[i] {
                case 1:
                    cloth[pixel] = true
                    if let proStyle {
                        let position = shirtPosition(pixel)
                        if position.x < -0.03 || position.x > 1.03 {
                            color = proStyle.sleeve(base: proStyle.sleeves, y: sleevePosition(x: position.x))
                        } else {
                            color = proStyle.shirt(x: position.x, y: position.y, back: true, mirrored: mirrored)
                        }
                    } else {
                        let u = (Double(pixel % width) / Double(width) - frame.shirt[0]) / frame.shirt[2]
                        let v = (Double(pixel / width) / Double(height) - frame.shirt[1]) / frame.shirt[3]
                        color = style?.shirt(x: min(1, max(0, u)), y: min(1, max(0, v))) ?? kit
                    }
                case 2: color = style?.cap ?? kit
                case 3:
                    if let proStyle, let leg = trouserRows.position(x: pixel % width, y: pixel / width) {
                        color = proStyle.leg(base: pants, x: leg.x, y: leg.y, back: true, mirrored: mirrored)
                    } else {
                        color = pants
                    }
                case 4: color = skin
                case 5:
                    let position = shirtPosition(pixel)
                    if let proStyle, abs(position.x - 0.5) > 0.42, position.y > 0.1 {
                        color = proStyle.sleeve(base: proStyle.sleeves, y: sleevePosition(x: position.x))
                    } else {
                        color = trim
                    }
                case 6: color = hair
                default: continue
                }
            }
            for channel in 0..<3 {
                bytes[i + channel] = UInt8(Double((color >> ((2-channel)*8)) & 255) * tone)
            }
        }
        let center = CGPoint(x: frame.number[0] * Double(width), y: frame.number[1] * Double(height))
        let ink = style?.ink ?? 0xf4f0db
        if let placement = badgeCenter(near: center, angle: frame.numberAngle, columns: String(number).count * 4 - 1,
                                       rows: 5, eligible: cloth, width: width, height: height) {
            PlayerMotionArt.drawNumber(number, at: placement, angle: frame.numberAngle, mirrored: mirrored,
                unit: 1, ink: ink, outline: GameUniformStyle.outline(for: ink), eligible: cloth, bytes: &bytes, width: width, height: height)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let rendered = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: format),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: rendered)
    }
    static func prepare(role: PlayerRole, appearance: PlayerAppearance, number: Int, hand: String) -> Prepared? {
        guard let manifest else { return nil }
        let camera = role == .pitcher ? manifest.back : manifest.front
        let style = role == .pitcher ? appearance.uniformStyle : appearance.opponentUniformStyle
        let kit = role == .pitcher ? appearance.uniformColor : appearance.opponentUniformColor
        let key = (PlayerMotionArt.cacheKey(role: role, appearance: appearance, number: number, hand: hand)
            + ":whole-v124:\(kit):\(style?.id ?? "legacy")") as NSString
        if let value = cache.object(forKey: key) { return value }
        let images = camera.frames.compactMap {
            image(frame: $0, file: camera.file, kit: kit, style: style, appearance: appearance,
                  number: role == .pitcher ? number : nil, mirrored: hand == "left")
        }
        guard images.count == camera.frames.count else { return nil }
        let textures = images.map { image in
            let texture = SKTexture(image: image); texture.filteringMode = .nearest; return texture
        }
        let result = Prepared(textures: textures, camera: camera)
        let cost = images.reduce(0) { $0 + ($1.cgImage.map { $0.width * $0.height * 4 } ?? 0) }
        cache.setObject(result, forKey: key, cost: cost)
        return result
    }
    /// 번호 전체와 테두리가 상의 안에 들어가는 가장 가까운 위치를 선택한다.
    static func badgeCenter(near center:CGPoint,angle:Double,columns:Int,rows:Int,
                            eligible:[Bool],width:Int,height:Int)->CGPoint? {
        var candidates:[CGPoint]=[]
        for y in -12...12 {for x in -12...12 {
            candidates.append(CGPoint(x:center.x.rounded()+Double(x),y:center.y.rounded()+Double(y)))
        }}
        candidates.sort {hypot($0.x-center.x,$0.y-center.y)<hypot($1.x-center.x,$1.y-center.y)}
        return candidates.first {p in
            for y in -1...rows {for x in -1...columns {
                let dx=Double(x)-Double(columns)/2,dy=Double(y)-Double(rows)/2
                let px=Int((p.x+dx*cos(angle)-dy*sin(angle)).rounded())
                let py=Int((p.y+dx*sin(angle)+dy*cos(angle)).rounded())
                if px<0 || py<0 || px>=width || py>=height || !eligible[py*width+px] {return false}
            }}
            return true
        }
    }

    private enum UniformMaterial {
        case torso, sleeve, trousers, sock(Int)
    }

    /// 원화의 재질 색만 바꾸며 전신 윤곽이나 관절을 변형하지 않는다.
    static func image(frame: Frame, file: String, kit: Int, style: GameUniformStyle?,
                              appearance: PlayerAppearance, number: Int?, mirrored: Bool) -> UIImage? {
        guard let source = sources[file], frame.rect.count == 4,
              let original = source.cropping(to: CGRect(x: frame.rect[0], y: frame.rect[1],
                                                       width: frame.rect[2], height: frame.rect[3])) else { return nil }
        let sourceWidth = original.width, sourceHeight = original.height
        var sourceBytes = [UInt8](repeating: 0, count: sourceWidth * sourceHeight * 4)
        let width = 128, height = 128
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var shirtPixels = [Bool](repeating: false, count: width * height)
        let space = CGColorSpaceCreateDeviceRGB()
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let decoded = sourceBytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: sourceWidth, height: sourceHeight, bitsPerComponent: 8,
                                    bytesPerRow: sourceWidth * 4, space: space, bitmapInfo: format) else { return false }
            c.draw(original, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)); return true
        }
        guard decoded else { return nil }
        var coverage = [Bool](repeating:false,count:sourceWidth*sourceHeight)
        for row in frame.coverageRuns where row.count == 3 && row[0]>=0 && row[0]<sourceHeight {
            for x in max(0,row[1])..<min(sourceWidth,row[1]+row[2]) {coverage[row[0]*sourceWidth+x]=true}
        }
        func tone(_ value:Double)->Double {
            value<0.535 ? 0.42:value<0.735 ? 0.65:value<0.91 ? 0.82:value<1.065 ? 1.0:1.13
        }
        let skin = number == nil ? 0xefbe91 : PlayerAppearance.skinColors[appearance.skin]
        let hair = number == nil ? 0x263b48 : PlayerAppearance.hairColors[appearance.hair]
        let proStyle = style.flatMap { $0.pro == nil ? nil : $0 }
        let back = file == "pitcher-depth-back-v124"
        let angleCosine = cos(frame.numberAngle), angleSine = sin(frame.numberAngle)
        func shirtPosition(_ x: Double, _ y: Double) -> CGPoint {
            let dx = x - frame.number[0], dy = y - frame.number[1]
            return CGPoint(x: dx * angleCosine + dy * angleSine, y: -dx * angleSine + dy * angleCosine)
        }
        var torsoBounds = CGRect.null
        var trouserRows = UniformTrouserRows(height: height)
        let feet = [frame.leadFoot, frame.rearFoot].map { CGPoint(x: $0[0], y: $0[1]) }
        var sockTop = [height, height]
        var sockBottom = [0, 0]
        var sleeveEnds = [0.0, 0.0]
        var samples: [(pixel: Int, material: UniformMaterial, tone: Double)] = []
        for y in 0..<height { for x in 0..<width {
            let pixel = y * width + x, i = pixel * 4
            let sx=min(sourceWidth-1,Int((Double(x)+0.5)*Double(sourceWidth)/Double(width)))
            let sy=min(sourceHeight-1,Int((Double(y)+0.5)*Double(sourceHeight)/Double(height)))
            let source=(sy*sourceWidth+sx)*4,alpha=Int(sourceBytes[source+3])
            guard alpha >= 128,coverage[sy*sourceWidth+sx] else {
                bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0; continue
            }
            let r = Double(sourceBytes[source]) / Double(alpha), g = Double(sourceBytes[source + 1]) / Double(alpha), b = Double(sourceBytes[source + 2]) / Double(alpha)
            let high = max(r,g,b), low = min(r,g,b), delta = high-low
            var hue = 0.0
            if delta > 0 {
                if high == r { hue = (g-b)/delta }
                else if high == g { hue = (b-r)/delta+2 }
                else { hue = (r-g)/delta+4 }
                hue = hue/6; if hue < 0 { hue += 1 }
            }
            let saturation = high == 0 ? 0 : delta/high
            let px = Double(x)/Double(width), py = Double(y)/Double(height)
            var color: Int?, shade = 1.0
            var material: UniformMaterial?
            // Low-saturation trouser shadows are cloth too; the leather fallback made them brown.
            if py > frame.shirt[1] + frame.shirt[3] * 0.8 && high > 0.24 && saturation < 0.25 {
                color = style?.pants ?? 0xeff0ed; shade = min(1.1, max(0.4, (r+g+b)/2.7))
                material = .trousers
            } else if high > 0.22 && saturation > 0.25 {
                switch hue {
                case 0.48..<0.56:
                    color = skin; shade = min(1.08,max(0.55,high/0.85))
                case 0.56..<0.72:
                    let point = shirtPosition(px, py)
                    let u=0.5+point.x/frame.shirt[2]
                    let v=0.46+point.y/frame.shirt[3]
                    color = style?.shirt(x:min(1,max(0,u)),y:min(1,max(0,v))) ?? kit
                    shirtPixels[pixel] = true; shade = min(1.35,max(0.30,high/0.78))
                    material = .torso
                case 0.72..<0.82:
                    color = style?.sleeves ?? kit; shade = min(1.25,max(0.32,high/0.75))
                    material = .sleeve
                case 0.82..<0.98:
                    color = 0x203b53; shade = min(1.35,max(0.4,high/0.83))
                case 0.11..<0.22:
                    color = 0x203b53; shade = min(1.35,max(0.4,high/0.90))
                case 0.22..<0.48:
                    color = py > frame.cap[1]+frame.cap[3]*0.75 ? style?.brim ?? kit : style?.cap ?? kit
                    shade = min(1.5,max(0.3,high/0.56))
                case 0..<0.04, 0.98...1:
                    color = style?.cap ?? kit; shade = min(1.3,max(0.3,high/0.83))
                    if proStyle != nil && py > frame.shirt[1] + frame.shirt[3] * 0.65 {
                        let a = hypot(px - feet[0].x, py - feet[0].y), b = hypot(px - feet[1].x, py - feet[1].y)
                        if min(a, b) < 0.21 { material = .sock(a < b ? 0 : 1) }
                    }
                default:
                    if py > frame.shirt[1]+frame.shirt[3]*0.8 && saturation<0.36 && high>0.45 {
                        color=style?.pants ?? 0xeff0ed;shade=min(1.1,max(0.4,high))
                        material = .trousers
                    } else if saturation < 0.65 && high > 0.48 {
                        color = skin; shade = min(1.1,max(0.45,high/0.9))
                    } else if py < frame.shirt[1]+0.03 && high < 0.43 {
                        let hx = (px-frame.cap[0])/max(0.01,frame.cap[2])
                        let hy = (py-frame.cap[1]-frame.cap[3]*0.75)/max(0.01,frame.cap[3]*0.45)
                        let depth = PlayerMotionArt.napeDepth(style:appearance.hairStyle,x:hx)
                        color = number != nil && appearance.creationVersion == 1 && hy > depth ? skin : hair
                        shade = min(1.5,max(0.5,high/0.28))
                    }
                }
            } else if high > 0.5 && saturation < 0.20 {
                color = style?.pants ?? 0xeff0ed; shade = min(1.1,max(0.4,(r+g+b)/2.7))
            }
            if let color {
                shade=tone(shade)
                if proStyle != nil, let material {
                    samples.append((pixel, material, shade))
                    switch material {
                    case .torso:
                        let position = shirtPosition(px, py)
                        torsoBounds = torsoBounds.union(CGRect(origin: position, size: .zero))
                    case .sleeve:
                        let offset = shirtPosition(px, py).x
                        let side = offset < 0 ? 0 : 1
                        sleeveEnds[side] = max(sleeveEnds[side], abs(offset))
                    case .trousers:
                        trouserRows.insert(x: x, y: y)
                    case .sock(let foot):
                        sockTop[foot] = min(sockTop[foot], y)
                        sockBottom[foot] = max(sockBottom[foot], y)
                    }
                }
                for channel in 0..<3 {
                    bytes[i+channel] = UInt8(min(255, max(0, Int(Double((color >> ((2-channel)*8)) & 255)*shade))))
                }
            } else {
                let base=high<0.24 ? 0x142637:0x96612f
                let level=tone(high<0.24 ? 1.0:high/0.65)
                for c in 0..<3 {bytes[i+c]=UInt8(min(255,Double((base>>((2-c)*8))&255)*level))}
            }
            bytes[i+3] = 255
        }}
        if let proStyle {
            for sample in samples {
                let x = sample.pixel % width, y = sample.pixel / width
                let i = sample.pixel * 4
                let color: Int
                switch sample.material {
                case .torso:
                    let point = shirtPosition(Double(x) / Double(width), Double(y) / Double(height))
                    let u = (point.x - torsoBounds.minX) / max(0.01, torsoBounds.width)
                    let v = (point.y - torsoBounds.minY) / max(0.01, torsoBounds.height)
                    color = proStyle.shirt(x: u, y: v, back: back, mirrored: mirrored)
                case .sleeve:
                    let offset = shirtPosition(Double(x) / Double(width), Double(y) / Double(height)).x
                    let sleeveStart = torsoBounds.isNull ? 0 : torsoBounds.width * 0.38
                    let sleeveEnd = sleeveEnds[offset < 0 ? 0 : 1]
                    let progress = (abs(offset) - sleeveStart) / max(0.01, sleeveEnd - sleeveStart)
                    color = proStyle.sleeve(base: proStyle.sleeves, y: progress)
                case .trousers:
                    guard let leg = trouserRows.position(x: x, y: y) else { continue }
                    color = proStyle.leg(base: proStyle.pants, x: leg.x, y: leg.y, back: back, mirrored: mirrored)
                case .sock(let foot):
                    let progress = (Double(y - sockTop[foot]) + 0.5) / Double(sockBottom[foot] - sockTop[foot] + 1)
                    color = proStyle.sock(base: proStyle.sleeves, y: progress)
                }
                for channel in 0..<3 {
                    let component = Double((color >> ((2 - channel) * 8)) & 255)
                    bytes[i + channel] = UInt8(min(255, component * sample.tone))
                }
            }
        }
        if let number {
            let center = CGPoint(x: frame.number[0]*Double(width), y: frame.number[1]*Double(height))
            let ink = style?.ink ?? 0xf4f0db
            let columns=String(number).count*4-1
            if let placement=badgeCenter(near:center,angle:frame.numberAngle,columns:columns,rows:5,eligible:shirtPixels,width:width,height:height) {
                PlayerMotionArt.drawNumber(number, at: placement, angle: frame.numberAngle, mirrored: mirrored,
                    unit:1,ink:ink,outline:GameUniformStyle.outline(for:ink),eligible:shirtPixels,
                    bytes:&bytes,width:width,height:height)
            }
        } else if let style {
            let center = CGPoint(x: (frame.shirt[0]+frame.shirt[2]*0.55)*Double(width),
                                 y: (frame.shirt[1]+frame.shirt[3]*0.30)*Double(height))
            if let placement=badgeCenter(near:center,angle:0,columns:5,rows:5,eligible:shirtPixels,width:width,height:height),style.mark.count==1024 {
                for y in 0..<5 {for x in 0..<5 {
                    let source=(min(15,y*16/5)*16+min(15,x*16/5))*4
                    let px=Int(placement.x)+x-2,py=Int(placement.y)+y-2,target=(py*width+px)*4
                    if style.mark[source+3]>160 {for c in 0..<3 {bytes[target+c]=style.mark[source+c]}}
                }}
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width*4, space: space, bitmapInfo: CGBitmapInfo(rawValue:format),
                                  provider:provider, decode:nil, shouldInterpolate:false, intent:.defaultIntent) else {return nil}
        return UIImage(cgImage:image)
    }
}
