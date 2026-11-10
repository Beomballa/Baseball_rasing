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
    static let version = "v166-layered-1"
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

    static func image(_ a: PlayerAppearance, role: PlayerRole = .batter, number: Int = 10, cap: Bool = false) -> UIImage? {
        guard a.isValid else { return nil }
        let key = key(a, role: role, number: number, cap: cap) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let heads = UIImage(named: "ManagementHeadsV166")?.cgImage,
              let features = UIImage(named: "ManagementFeaturesV166")?.cgImage,
              let head = cell(heads, column: a.hairStyle % 4, row: a.hairStyle / 4, columns: 4, rows: 2),
              let base = tinted(head, appearance: a) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext; context.interpolationQuality = .none
            base.draw(in: CGRect(origin: .zero, size: size))
            @MainActor func feature(_ row: Int, _ column: Int, _ rect: CGRect) {
                guard let raw = cell(features, column: column, row: row, columns: 6, rows: 3),
                      let glyph = opaqueCrop(raw) else { return }
                let image = tintedFeature(glyph, appearance: a, eyebrow: row == 1)
                image?.draw(in: CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                    width: rect.width * size.width, height: rect.height * size.height))
            }
            feature(0, a.eyeIndex, CGRect(x: 0.421, y: 0.385, width: 0.263, height: 0.074))
            feature(1, a.browIndex, CGRect(x: 0.417, y: 0.347, width: 0.270, height: 0.036))
            feature(2, a.expression, CGRect(x: 0.528, y: 0.535, width: 0.155, height: a.expression == 3 ? 0.062 : 0.038))
            drawUniformDetails(a, number: number, in: context)
            if cap { drawCap(a, in: context) }
        }
        cache.setObject(image, forKey: key)
        return image
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

    private static func tinted(_ source: CGImage, appearance a: PlayerAppearance) -> UIImage? {
        let width = 256, height = 256
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            c.interpolationQuality = .none; c.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard valid else { return nil }
        let uniform = a.uniformStyle
        for index in 0..<(width * height) {
            let offset = index * 4, alpha = Int(bytes[offset + 3]); if alpha < 24 { continue }
            let r = Int(bytes[offset]) * 255 / alpha, g = Int(bytes[offset + 1]) * 255 / alpha, b = Int(bytes[offset + 2]) * 255 / alpha
            let x = Double(index % width) / Double(width), y = Double(index / width) / Double(height)
            var color: Int?, shade = 1.0
            if r > 70 && r > g * 12 / 10 && g > b * 11 / 10 {
                color = PlayerAppearance.skinColors[a.skin]; shade = Double(r) / 239
            } else if y < 0.63 && max(r, max(g, b)) < 155 && max(r, max(g, b)) - min(r, min(g, b)) < 75 {
                color = PlayerAppearance.hairColors[a.hair]; shade = Double(max(r, max(g, b))) / 65
            } else if y > 0.60 && g > 30 && g > r * 11 / 10 && g > b * 11 / 10 {
                color = uniform?.shirt(x: x, y: (y - 0.65) / 0.35) ?? a.uniformColor; shade = Double(g) / 115
            } else if y > 0.66 && r > 150 && g > 140 && b > 90 && abs(r - g) < 45 && g - b > 8 {
                color = uniform?.trim ?? 0xe8b45f; shade = Double(r + g + b) / 680
            }
            guard let color else { continue }
            for channel in 0..<3 {
                let component = Double((color >> (16 - channel * 8)) & 255) * min(1.45, max(0.25, shade))
                bytes[offset + channel] = UInt8(min(255, max(0, component)) * Double(alpha) / 255)
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info), let image = c.makeImage() else { return nil }
            return UIImage(cgImage: image)
        }
    }

    private static func tintedFeature(_ source: CGImage, appearance a: PlayerAppearance, eyebrow: Bool) -> UIImage? {
        let width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            c.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard valid else { return nil }
        for index in 0..<(width * height) {
            let offset = index * 4, alpha = Int(bytes[offset + 3]); if alpha < 24 { continue }
            let r = Int(bytes[offset]) * 255 / alpha, g = Int(bytes[offset + 1]) * 255 / alpha, b = Int(bytes[offset + 2]) * 255 / alpha
            let skin = r > 70 && r > g * 12 / 10 && g > b * 11 / 10
            guard skin || eyebrow else { continue }
            let color = skin ? PlayerAppearance.skinColors[a.skin] : PlayerAppearance.hairColors[a.hair]
            let shade = skin ? Double(r) / 239 : Double(max(r, max(g, b))) / 65
            for channel in 0..<3 {
                let component = Double((color >> (16 - channel * 8)) & 255) * min(1.45, max(0.25, shade))
                bytes[offset + channel] = UInt8(min(255, max(0, component)) * Double(alpha) / 255)
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info), let image = c.makeImage() else { return nil }
            return UIImage(cgImage: image)
        }
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

    private static func drawCap(_ a: PlayerAppearance, in context: CGContext) {
        let cap = a.uniformStyle?.cap ?? a.uniformColor
        let brim = a.uniformStyle?.brim ?? 0x183944
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: 80))
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
    }
}
