import SpriteKit
import SwiftUI
import UIKit

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
    /// 6개 자세가 모두 준비됐을 때만 캐시에 보관한다.
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
    /// 원화 픽셀의 음영·투명도를 유지하며 외형과 복장을 합성한다. 유효하지 않으면 nil을 반환한다.
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
                let nx = (Double(x) - bounds.minX) / bounds.width
                let ny = (Double(y) - bounds.minY) / bounds.height
                let torso = shirt.contains(point)
                let jersey = style?.shirt(x: nx, y: ny) ?? kit
                let onCap =
                    Double(y) < pose.hair.minY + 8 && Double(x) > pose.hair.minX - 38 && Double(x) < pose.hair.maxX + 24
                let fabric =
                    torso
                    ? jersey
                    : onCap ? (Double(y) > pose.hair.minY - 8 ? style?.brim : style?.cap) ?? kit : style?.sleeves ?? kit
                if role == .pitcher && pose.erase.contains(point) && torso && high > 24 {
                    color = rgb(jersey, shirtShade[y])
                } else if b > 36 && Double(b) > Double(r) * 1.35 && Double(b) > Double(g) * 1.1 {
                    color = rgb(fabric, max(0.25, min(1.6, Double(b) / 135)))
                } else if role == .batter && low > 90 && high - low < 70 && shirt.contains(point) {
                    color = rgb(jersey, max(0.35, Double(r + g + b) / 720))
                } else if let style, pose.pants.contains(point), low > 105, high - low < 70 {
                    color = rgb(style.pants, max(0.35, min(1.1, Double(r + g + b) / 735)))
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
