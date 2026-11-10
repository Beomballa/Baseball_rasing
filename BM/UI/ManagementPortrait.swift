import SwiftUI
import UIKit

struct ManagementPortrait: View {
    let appearance: PlayerAppearance
    var role: PlayerRole = .batter
    var number: Int = 10
    var cap = false
    @State private var image: UIImage?
    private var key: String { ManagementPortraitRasterV166.key(appearance, role: role, number: number, cap: cap) }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit() }
            else { Color.clear }
        }.accessibilityHidden(true)
            .task(id: key) { image = ManagementPortraitRasterV166.image(appearance, role: role, number: number, cap: cap) }
    }
}

/// Management artwork reads the saved look; match poses and creation storage remain independent.
@MainActor enum ManagementPortraitRasterV166 {
    static let version = "v167-reference-3"
    private static let size = CGSize(width: 256, height: 256)
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.countLimit = 96; return value
    }()

    static func key(_ a: PlayerAppearance, role: PlayerRole = .batter, number: Int = 10, cap: Bool = false) -> String {
        [version, role.rawValue, String(number), String(cap), String(a.skin), String(a.hair), String(a.kit),
         String(a.hairStyle), String(a.eyeIndex), String(a.browIndex), String(a.expression),
         a.schoolKitID ?? "legacy", String(a.creationVersion ?? 0), a.uniformTeamID ?? "", String(a.uniformAway)]
            .joined(separator: ":")
    }

    private struct Reference {
        let index: Int, hairStyle: Int, eye: Int, brow: Int, expression: Int, skin: Int
        let eyes: CGRect, brows: CGRect, mouth: CGRect, nose: CGRect
    }

    // These pixel rectangles are measured in each approved 627px cell, normalized to 256px.
    // The four completed portraits deliberately have different face positions.
    private static let references = [
        Reference(index: 0, hairStyle: 0, eye: 0, brow: 0, expression: 2, skin: 0,
            eyes: CGRect(x: 114, y: 99, width: 62, height: 16), brows: CGRect(x: 114, y: 90, width: 62, height: 10),
            mouth: CGRect(x: 134, y: 132, width: 25, height: 13), nose: CGRect(x: 147, y: 112, width: 12, height: 16)),
        Reference(index: 1, hairStyle: 1, eye: 0, brow: 1, expression: 2, skin: 0,
            eyes: CGRect(x: 101, y: 96, width: 61, height: 14), brows: CGRect(x: 101, y: 86, width: 61, height: 11),
            mouth: CGRect(x: 121, y: 130, width: 27, height: 13), nose: CGRect(x: 135, y: 107, width: 13, height: 18)),
        Reference(index: 2, hairStyle: 3, eye: 2, brow: 1, expression: 0, skin: 2,
            eyes: CGRect(x: 116, y: 73, width: 63, height: 15), brows: CGRect(x: 116, y: 63, width: 64, height: 12),
            mouth: CGRect(x: 134, y: 108, width: 31, height: 16), nose: CGRect(x: 145, y: 88, width: 18, height: 20)),
        Reference(index: 3, hairStyle: 7, eye: 1, brow: 3, expression: 0, skin: 0,
            eyes: CGRect(x: 107, y: 80, width: 62, height: 15), brows: CGRect(x: 106, y: 68, width: 64, height: 14),
            mouth: CGRect(x: 126, y: 114, width: 29, height: 14), nose: CGRect(x: 145, y: 94, width: 15, height: 20))
    ]

    private static func reference(for appearance: PlayerAppearance) -> Reference {
        references[[0, 1, 0, 2, 0, 1, 0, 3][appearance.hairStyle]]
    }

    static func image(_ a: PlayerAppearance, role: PlayerRole = .batter, number: Int = 10, cap: Bool = false) -> UIImage? {
        guard a.isValid else { return nil }
        let key = key(a, role: role, number: number, cap: cap) as NSString
        if let image = cache.object(forKey: key) { return image }
        let reference = reference(for: a)
        guard let sheet = UIImage(named: "ManagementPortraitReferenceV167")?.cgImage,
              let features = UIImage(named: "ManagementFeaturesV166")?.cgImage,
              let source = cell(sheet, column: reference.index % 2, row: reference.index / 2, columns: 2, rows: 2),
              let base = preparedReference(source, appearance: a, reference: reference) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext; context.interpolationQuality = .none
            base.draw(in: CGRect(origin: .zero, size: size))
            if a.hairStyle != reference.hairStyle {
                drawAlternativeHair(a, reference: reference, source: source, in: context)
            }
            let selected = [a.eyeIndex, a.browIndex, a.expression]
            let canonical = [reference.eye, reference.brow, reference.expression]
            let rects = [reference.eyes, reference.brows, reference.mouth]
            for row in 0..<3 where selected[row] != canonical[row] || (a.hairStyle != reference.hairStyle && row < 2) {
                guard let raw = cell(features, column: selected[row], row: row, columns: 6, rows: 3),
                      let glyph = preparedFeature(raw, appearance: a, eyebrow: row == 1) else { continue }
                let rect = aspectFit(glyph.size, in: rects[row])
                context.saveGState()
                let permitted = CGMutablePath(); permitted.addRect(CGRect(origin: .zero, size: size)); permitted.addRect(reference.nose)
                context.addPath(permitted); context.clip(using: .evenOdd)
                glyph.draw(in: rect)
                context.restoreGState()
            }
            drawUniformDetails(a, number: number, in: context)
            if cap { drawCap(a, reference: reference, in: context) }
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func aspectFit(_ source: CGSize, in target: CGRect) -> CGRect {
        let scale = min(target.width / source.width, target.height / source.height)
        let width = source.width * scale, height = source.height * scale
        return CGRect(x: target.midX - width / 2, y: target.midY - height / 2, width: width, height: height)
    }

    private static func cell(_ source: CGImage, column: Int, row: Int, columns: Int, rows: Int) -> CGImage? {
        let left = Int((Double(column) * Double(source.width) / Double(columns)).rounded())
        let right = Int((Double(column + 1) * Double(source.width) / Double(columns)).rounded())
        let top = Int((Double(row) * Double(source.height) / Double(rows)).rounded())
        let bottom = Int((Double(row + 1) * Double(source.height) / Double(rows)).rounded())
        return source.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
    }

    private static func opaqueCrop(_ source: CGImage) -> CGImage? {
        let width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            c.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard valid else { return nil }
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height { for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 48 {
            left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
        } }
        guard right >= left, bottom >= top else { return nil }
        return source.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
    }

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    private static func bytes(_ source: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let valid = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return false }
            context.interpolationQuality = .none
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        return valid ? pixels : nil
    }

    private static func image(_ pixels: inout [UInt8], width: Int, height: Int) -> UIImage? {
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
                let image = context.makeImage() else { return nil }
            return UIImage(cgImage: image)
        }
    }

    private static func rgb(_ pixels: [UInt8], at offset: Int) -> [Int] {
        let alpha = Int(pixels[offset + 3])
        return (0..<3).map { alpha > 0 ? Int(pixels[offset + $0]) * 255 / alpha : 0 }
    }

    private static func skin(_ color: [Int]) -> Bool {
        color[0] > 70 && color[0] > color[1] * 12 / 10 && color[1] > color[2] * 11 / 10
    }

    private static func component(_ color: Int, _ channel: Int) -> Double {
        Double((color >> (16 - channel * 8)) & 255)
    }

    private static func hairPixel(_ color: [Int], y: Int, reference: Reference) -> Bool {
        y < Int(reference.eyes.minY) && color.max()! < 165 && color.max()! - color.min()! < 80 && !skin(color)
    }

    private struct SourcePalette { let skin: [Int], hair: [Int] }
    private static var sourcePalettes = [Int: SourcePalette]()

    private static func palette(_ original: [UInt8], reference: Reference) -> SourcePalette {
        if let palette = sourcePalettes[reference.index] { return palette }
        func midtone(hair: Bool) -> [Int] {
            var counts = [Int: (count: Int, sum: [Int])]()
            for y in 0..<Int(reference.mouth.minY) { for x in 0..<256 {
                let offset = (y * 256 + x) * 4
                guard original[offset + 3] > 160 else { continue }
                let color = rgb(original, at: offset), light = (color[0] + color[1] * 2 + color[2]) / 4
                let allowed = hair ? hairPixel(color, y: y, reference: reference) && light > 30 && light < 130
                    : x >= Int(reference.eyes.minX) && x < Int(reference.eyes.maxX)
                        && y > Int(reference.eyes.maxY) && skin(color) && color[0] > 100
                        && !reference.nose.contains(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                guard allowed else { continue }
                let key = ((color[0] / 8) << 10) | ((color[1] / 8) << 5) | (color[2] / 8)
                var value = counts[key] ?? (0, [0, 0, 0]); value.count += 1
                for channel in 0..<3 { value.sum[channel] += color[channel] }; counts[key] = value
            } }
            guard let value = counts.values.max(by: { $0.count < $1.count }) else { return hair ? [60, 56, 72] : [249, 183, 130] }
            return value.sum.map { $0 / value.count }
        }
        let result = SourcePalette(skin: midtone(hair: false), hair: midtone(hair: true))
        sourcePalettes[reference.index] = result; return result
    }

    private static func mapped(_ color: [Int], from baseline: [Int], to target: Int) -> [Double] {
        // A fixed continuous slope preserves source shading without amplifying near-white PNG noise.
        (0..<3).map { component(target, $0) + Double(color[$0] - baseline[$0]) * 0.75 }
    }

    private static func mappedHair(_ color: [Int], from baseline: [Int], to target: Int) -> [Double] {
        let light = Double(color[0] + color[1] * 2 + color[2]) / 4
        let middle = Double(baseline[0] + baseline[1] * 2 + baseline[2]) / 4
        return (0..<3).map { channel in
            let selected = component(target, channel)
            let shade = light <= middle ? selected * light / max(1, middle)
                : selected + (255 - selected) * (light - middle) / max(1, 255 - middle)
            let sourceColor = Double(color[channel]) - light - (Double(baseline[channel]) - middle)
            return min(255, max(0, shade + sourceColor * 0.15))
        }
    }

    private static func nearbySkin(_ original: [UInt8], x: Int, y: Int, reference: Reference, fallback: [Int]) -> [Int] {
        for dy in [0, -1, 1, -2, 2, -4, 4] {
            let yy = min(255, max(0, y + dy)); var samples = [[Int]]()
            for direction in [-1, 1] { for distance in 1...48 {
                let xx = x + direction * distance
                guard xx >= Int(reference.eyes.minX) - 12, xx <= Int(reference.eyes.maxX) + 3 else { continue }
                let point = CGPoint(x: CGFloat(xx), y: CGFloat(yy)), offset = (yy * 256 + xx) * 4
                guard !reference.nose.contains(point), original[offset + 3] > 160 else { continue }
                let color = rgb(original, at: offset)
                if skin(color) && color[0] > 145 && color[1] > 95 && color[2] > 55 { samples.append(color); break }
            } }
            if !samples.isEmpty { return (0..<3).map { channel in samples.reduce(0) { $0 + $1[channel] } / samples.count } }
        }
        return fallback
    }

    private static func restoreForehead(_ pixels: inout [UInt8], original: [UInt8], reference: Reference, palette: SourcePalette) {
        let top = reference.brows.minY - 32, bottom = reference.eyes.maxY
        let left = reference.eyes.minX - 12, right = reference.eyes.maxX + 3
        let forehead = CGMutablePath()
        forehead.move(to: CGPoint(x: reference.eyes.minX - 6, y: top))
        forehead.addLine(to: CGPoint(x: reference.eyes.maxX - 3, y: top))
        forehead.addLine(to: CGPoint(x: reference.eyes.maxX + 2, y: bottom))
        forehead.addLine(to: CGPoint(x: left, y: bottom)); forehead.closeSubpath()
        // Fixed anchors produce one continuous plane; per-row nearest samples form visible bands.
        let sampleY = Int(reference.brows.minY) - 4
        let leftSkin = nearbySkin(original, x: Int(reference.eyes.minX) + 6, y: sampleY, reference: reference, fallback: palette.skin)
        let rightSkin = nearbySkin(original, x: Int(reference.eyes.maxX) - 6, y: sampleY, reference: reference, fallback: palette.skin)
        for y in max(0, Int(top))..<Int(bottom) {
            let vertical = Double((CGFloat(y) - top) / (bottom - top))
            for x in max(0, Int(left))..<min(256, Int(right)) {
                let point = CGPoint(x: CGFloat(x), y: CGFloat(y)), offset = (y * 256 + x) * 4
                guard forehead.contains(point), !reference.nose.contains(point) else { continue }
                let horizontal = Double((CGFloat(x) - left) / (right - left))
                for channel in 0..<3 {
                    let lower = Double(leftSkin[channel]) * (1 - horizontal) + Double(rightSkin[channel]) * horizontal
                    let sample = Double(palette.skin[channel]) * (1 - vertical) + lower * vertical
                    pixels[offset + channel] = UInt8(min(255, max(0, sample)) * 253 / 255)
                }
                pixels[offset + 3] = 253
            }
        }
    }

    private static func preparedReference(_ source: CGImage, appearance a: PlayerAppearance, reference: Reference) -> UIImage? {
        let width = 256, height = 256
        guard var pixels = bytes(source, width: width, height: height) else { return nil }
        let original = pixels, colors = palette(original, reference: reference)
        let alternativeHair = a.hairStyle != reference.hairStyle
        if alternativeHair { restoreForehead(&pixels, original: original, reference: reference, palette: colors) }
        let changed = [alternativeHair || a.eyeIndex != reference.eye, alternativeHair || a.browIndex != reference.brow, a.expression != reference.expression]
        for (row, rect) in [reference.eyes, reference.brows, reference.mouth].enumerated() where changed[row] {
            if alternativeHair && row < 2 { continue }
            eraseFeature(in: rect, row: row, reference: reference, original: original, pixels: &pixels)
        }
        let uniform = a.uniformStyle
        for index in 0..<(width * height) {
            let offset = index * 4, alpha = Int(pixels[offset + 3]); if alpha < 24 { continue }
            let color = rgb(pixels, at: offset), r = color[0], g = color[1], b = color[2]
            let x = Double(index % width) / Double(width), y = Double(index / width) / Double(height)
            let point = CGPoint(x: CGFloat(index % width), y: CGFloat(index / width))
            let hair = hairPixel(color, y: index / width, reference: reference)
            if a.hairStyle != reference.hairStyle && hair {
                for channel in 0..<4 { pixels[offset + channel] = 0 }; continue
            }
            var result: [Double]?
            if a.skin != reference.skin && y < 0.75 && skin(color) {
                result = mapped(color, from: colors.skin, to: PlayerAppearance.skinColors[a.skin])
            } else if a.hair != 0 && (hair || reference.brows.contains(point)) && !reference.nose.contains(point)
                && !skin(color) && color.max()! < 165 && color.max()! - color.min()! < 80 {
                result = mappedHair(color, from: colors.hair, to: PlayerAppearance.hairColors[a.hair])
            } else if y > 0.55 && g > 30 && g > r * 11 / 10 && g > b * 11 / 10 {
                let selected = uniform?.shirt(x: x, y: (y - 0.65) / 0.35) ?? a.uniformColor
                result = (0..<3).map { component(selected, $0) * min(1.45, max(0.25, Double(g) / 115)) }
            } else if y > 0.65 && r > 150 && g > 140 && b > 90 && abs(r - g) < 45 && g - b > 8 {
                let selected = uniform?.trim ?? 0xe8b45f
                result = (0..<3).map { component(selected, $0) * min(1.45, max(0.25, Double(r + g + b) / 680)) }
            }
            if let result { for channel in 0..<3 {
                pixels[offset + channel] = UInt8(min(255, max(0, result[channel])) * Double(alpha) / 255)
            } }
        }
        return image(&pixels, width: width, height: height)
    }

    private static func eraseFeature(in rect: CGRect, row: Int, reference: Reference, original: [UInt8], pixels: inout [UInt8]) {
        let colors = palette(original, reference: reference)
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y)), offset = (y * 256 + x) * 4
            guard !reference.nose.contains(point), original[offset + 3] > 48 else { continue }
            let color = rgb(original, at: offset)
            // Keep existing skin texture; only the previous dark ink/eye whites need replacing.
            if skin(color) && color[0] > 145 && color[1] > 95 && color[2] > 55 { continue }
            let preferred = row == 1 ? y : row == 2 ? Int(rect.minY) - 4 : Int(reference.eyes.maxY) + 3
            let sample = nearbySkin(original, x: x, y: preferred, reference: reference, fallback: colors.skin)
            let alpha = Int(pixels[offset + 3])
            for channel in 0..<3 { pixels[offset + channel] = UInt8(sample[channel] * alpha / 255) }
        } }
    }

    private static func preparedFeature(_ source: CGImage, appearance a: PlayerAppearance, eyebrow: Bool) -> UIImage? {
        guard let cropped = opaqueCrop(source) else { return nil }
        let width = cropped.width, height = cropped.height
        guard var pixels = bytes(cropped, width: width, height: height) else { return nil }
        if !eyebrow {
            var eligible = [Bool](repeating: false, count: width * height), visited = eligible, queue = [Int]()
            for index in 0..<(width * height) {
                let offset = index * 4, color = rgb(pixels, at: offset)
                eligible[index] = pixels[offset + 3] > 0 && color[0] > 145 && color[1] > 95 && color[2] > 55 && skin(color)
            }
            for y in 0..<height { for x in 0..<width {
                let index = y * width + x
                guard eligible[index] else { continue }
                let edge = x == 0 || y == 0 || x == width - 1 || y == height - 1
                let outside = edge || [index - 1, index + 1, index - width, index + width].contains { pixels[$0 * 4 + 3] < 49 }
                if outside { visited[index] = true; queue.append(index) }
            } }
            var cursor = 0
            while cursor < queue.count {
                let index = queue[cursor], x = index % width, y = index / width; cursor += 1
                for dy in -1...1 { for dx in -1...1 {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, xx < width, yy >= 0, yy < height else { continue }
                    let next = yy * width + xx
                    if eligible[next] && !visited[next] { visited[next] = true; queue.append(next) }
                } }
            }
            for index in 0..<(width * height) where visited[index] {
                for channel in 0..<4 { pixels[index * 4 + channel] = 0 }
            }
        }
        if eyebrow && a.hair != 0 {
            for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 24 {
                let color = rgb(pixels, at: offset), alpha = Double(pixels[offset + 3]) / 255
                for channel in 0..<3 {
                    let values = mappedHair(color, from: [60, 56, 72], to: PlayerAppearance.hairColors[a.hair])
                    pixels[offset + channel] = UInt8(min(255, max(0, values[channel])) * alpha)
                }
            }
        }
        guard let image = image(&pixels, width: width, height: height)?.cgImage, let tight = opaqueCrop(image) else { return nil }
        return UIImage(cgImage: tight)
    }

    private static func drawAlternativeHair(_ a: PlayerAppearance, reference: Reference, source: CGImage, in context: CGContext) {
        guard let atlas = UIImage(named: "ManagementHeadsV166")?.cgImage,
              let head = cell(atlas, column: a.hairStyle % 4, row: a.hairStyle / 4, columns: 4, rows: 2),
              var hair = bytes(head, width: 256, height: 256), let base = bytes(source, width: 256, height: 256) else { return }
        var left = 256, right = -1
        for y in 0..<Int(reference.brows.minY) { for x in 0..<256 {
            let offset = (y * 256 + x) * 4
            if base[offset + 3] > 48 && hairPixel(rgb(base, at: offset), y: y, reference: reference) {
                left = min(left, x); right = max(right, x)
            }
        } }
        guard right >= left else { return }
        let colors = palette(hair, reference: reference)
        for index in 0..<(256 * 256) {
            let offset = index * 4, color = rgb(hair, at: offset), y = Double(index / 256) / 256
            guard y < 0.39 && !skin(color) && color.max()! < 165 && color.max()! - color.min()! < 80 else {
                for channel in 0..<4 { hair[offset + channel] = 0 }; continue
            }
            if a.hair != 0 { for channel in 0..<3 {
                let values = mappedHair(color, from: colors.hair, to: PlayerAppearance.hairColors[a.hair])
                hair[offset + channel] = UInt8(min(255, max(0, values[channel])) * Double(hair[offset + 3]) / 255)
            } }
        }
        guard let image = image(&hair, width: 256, height: 256)?.cgImage, let glyph = opaqueCrop(image) else { return }
        let width = CGFloat(right - left + 1), height = width * CGFloat(glyph.height) / CGFloat(glyph.width)
        let bottom = reference.eyes.minY + 2
        let rect = CGRect(x: CGFloat(left), y: bottom - height, width: width, height: height)
        context.saveGState(); context.clip(to: CGRect(x: 0, y: 0, width: 256, height: bottom))
        UIImage(cgImage: glyph).draw(in: rect); context.restoreGState()
    }

    private static func drawUniformDetails(_ a: PlayerAppearance, number: Int, in context: CGContext) {
        guard let style = a.uniformStyle else { return }
        let unit: CGFloat = 0.7, x: CGFloat = 157, y: CGFloat = 219
        if style.mark.count == 16 * 16 * 4 {
            for row in 0..<16 { for column in 0..<16 {
                let offset = (row * 16 + column) * 4
                guard style.mark[offset + 3] > 160 else { continue }
                let color = (Int(style.mark[offset]) << 16) | (Int(style.mark[offset + 1]) << 8) | Int(style.mark[offset + 2])
                context.setFillColor(UIColor(Color(hex: color)).cgColor)
                context.fill(CGRect(x: x + CGFloat(column) * unit, y: y + CGFloat(row) * unit, width: unit, height: unit))
            } }
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont(name: "NeoDunggeunmo", size: 9) ?? .boldSystemFont(ofSize: 9),
                                                       .foregroundColor: UIColor(Color(hex: style.ink))]
        (String(number) as NSString).draw(at: CGPoint(x: 168, y: 219), withAttributes: attributes)
    }

    private static func drawCap(_ a: PlayerAppearance, reference: Reference, in context: CGContext) {
        let cap = a.uniformStyle?.cap ?? a.uniformColor
        let brim = a.uniformStyle?.brim ?? 0x183944
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: max(0, reference.brows.minY - 6)))
        context.saveGState()
        context.translateBy(x: reference.eyes.midX - 145, y: reference.brows.minY - 86)
        context.setShouldAntialias(false)
        context.setFillColor(UIColor(Color(hex: cap)).cgColor)
        let crown = CGMutablePath()
        crown.move(to: CGPoint(x: 72, y: 77)); crown.addLines(between: [CGPoint(x: 77, y: 48), CGPoint(x: 97, y: 29),
            CGPoint(x: 164, y: 28), CGPoint(x: 191, y: 42), CGPoint(x: 202, y: 78)]); crown.closeSubpath()
        context.addPath(crown); context.fillPath()
        context.setFillColor(UIColor(Color(hex: brim)).cgColor)
        context.fill(CGRect(x: 72, y: 75, width: 144, height: 10))
        context.setStrokeColor(UIColor(Color(hex: 0x172d36)).cgColor); context.setLineWidth(2)
        context.addPath(crown); context.strokePath()
        context.restoreGState()
    }
}
