import SpriteKit
import UIKit

@MainActor enum StadiumTurfArt {
    static func name(stadium: StadiumIdentity, camera: StadiumSceneDress.Camera) -> String? {
        let surface: String
        switch stadium.key {
        case "hs-ref-014": surface = "stone"
        case "hs-ref-024": surface = "harbor"
        default:
            switch stadium.pro?.club.id {
            case "kbo-3": surface = "dome"
            case "mlb-0": surface = "pacific"
            default: return nil
            }
        }
        let angle: String
        switch camera {
        case .batter: angle = "batter"
        case .pitcher: angle = "pitcher"
        case .field: angle = "field"
        }
        return "stadium-turf-v187-\(surface)-\(angle)"
    }

    static func image(stadium: StadiumIdentity, camera: StadiumSceneDress.Camera) -> UIImage? {
        let pixelSize: CGSize
        switch camera {
        case .batter: pixelSize = CGSize(width: 1254, height: 1254)
        case .pitcher: pixelSize = CGSize(width: 1219, height: 1290)
        case .field: pixelSize = InplayStadiumArt.size
        }
        guard let name = name(stadium: stadium, camera: camera),
              let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MatchArt"),
              let image = UIImage(contentsOfFile: url.path), image.size == pixelSize else { return nil }
        return image
    }
}

/// Recolors existing grass in each camera perspective while keeping the painted diamond and markings.
@MainActor enum StadiumExpandedTurf {
    private struct PatternAxis {
        let lateral: Double
        let depth: Double

        func row(lateralScale: Double, depth: Double, width: Int, bandWidth: Int) -> PatternRow {
            let units = Double(1 << 15) / Double(bandWidth)
            let step = lateral * lateralScale
            return PatternRow(
                origin: Int((self.depth * depth - Double(width) * step / 2) * units),
                step: Int((step * units).rounded())
            )
        }
    }

    private struct PatternRow {
        let origin: Int
        let step: Int

        func lightBand(at x: Int) -> Bool {
            // Align each mowing edge to four source pixels to match the surrounding artwork.
            ((origin + step * (x & ~3)) >> 15) & 1 == 0
        }
    }

    static func overlay(for source: UIImage, camera: StadiumSceneDress.Camera,
                        appearance: StadiumVenueAppearance, venue: StadiumBackdrop) -> UIImage? {
        guard let image = source.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width
        let height = image.height
        let stride = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let original = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: stride, space: colorSpace, bitmapInfo: bitmapInfo),
              let overlay = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: stride, space: colorSpace, bitmapInfo: bitmapInfo),
              let sourceData = original.data?.assumingMemoryBound(to: UInt8.self),
              let targetData = overlay.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        original.setBlendMode(.copy)
        original.draw(image, in: bounds)

        let seam: Int
        switch camera {
        case .field: seam = Int(venue.height)
        case .batter: seam = Int(Double(height) * 280 / 1254)
        case .pitcher: seam = Int(Double(height) * 487 / 1290)
        }
        let firstRow = grassStart(before: min(seam, height), pixels: sourceData, width: width)
        let primary: PatternAxis
        var crossing: PatternAxis?
        switch appearance.direction {
        case .horizontal: primary = PatternAxis(lateral: 0, depth: 1)
        case .vertical: primary = PatternAxis(lateral: 1, depth: 0)
        case .diagonal: primary = PatternAxis(lateral: 0.8, depth: 0.36)
        case .crosshatch:
            primary = PatternAxis(lateral: 0.72, depth: 0.46)
            crossing = PatternAxis(lateral: 0.72, depth: -0.46)
        }
        let red = (appearance.baseColor >> 16) & 255
        let green = (appearance.baseColor >> 8) & 255
        let blue = appearance.baseColor & 255
        for y in firstRow..<height {
            let (lateralScale, depth) = projection(camera: camera, y: y, width: width, height: height)
            let band = primary.row(lateralScale: lateralScale, depth: depth, width: width,
                                   bandWidth: appearance.bandWidth)
            let crossedBand = crossing?.row(lateralScale: lateralScale, depth: depth, width: width,
                                            bandWidth: appearance.bandWidth)
            let input = sourceData.advanced(by: y * stride)
            let output = targetData.advanced(by: y * stride)
            for x in 0..<width {
                let offset = x * 4
                let r = Int(input[offset])
                let g = Int(input[offset + 1])
                let b = Int(input[offset + 2])
                let strength = g - max(r, b) - 12
                guard strength > 0, input[offset + 3] == 255 else { continue }
                let alpha = min(255, strength * 16)
                let light = band.lightBand(at: x) != (crossedBand?.lightBand(at: x) ?? false)
                let sourceLight = (74 * g + 15 * r + 11 * b - 12200) * 42 / 10000
                let shade = sourceLight + (light ? appearance.contrast : -appearance.contrast)
                output[offset] = component(red + shade * 87 / 100, alpha: alpha)
                output[offset + 1] = component(green + shade, alpha: alpha)
                output[offset + 2] = component(blue + shade * 73 / 100, alpha: alpha)
                output[offset + 3] = UInt8(alpha)
            }
        }
        guard let result = overlay.makeImage() else { return nil }
        return UIImage(cgImage: result, scale: source.scale, orientation: .up)
    }

    private static func grassStart(before seam: Int, pixels: UnsafePointer<UInt8>, width: Int) -> Int {
        // Some stands end in a track or railing. Look for a sustained, broad stretch of grass near the seam.
        var start = seam
        var run = 0
        for y in (max(0, seam - 100)..<seam).reversed() {
            var greenColumns = 0
            for column in 1...32 {
                let offset = (y * width + column * width / 33) * 4
                let r = Int(pixels[offset])
                let g = Int(pixels[offset + 1])
                let b = Int(pixels[offset + 2])
                if g >= 73, g - max(r, b) >= 21 { greenColumns += 1 }
            }
            if greenColumns >= 25 {
                run += 1
                if run >= 3 { start = y }
            } else {
                if start != seam { break }
                run = 0
            }
        }
        return start
    }

    private static func projection(camera: StadiumSceneDress.Camera, y: Int,
                                   width: Int, height: Int) -> (lateralScale: Double, depth: Double) {
        if camera == .field {
            let progress = max(0, Double(y - 338) / 1090)
            return (1 / (0.49 + 0.53 * progress), 1660 * progress / (0.40 + 0.62 * progress))
        }
        let normalized = Double(y) / Double(height)
        let progress = camera == .batter ? max(0, (normalized - 0.22) / 0.50) : max(0, (normalized - 0.35) / 0.65)
        let lateral = 690 / (Double(width) * (0.48 + 0.56 * progress))
        let depth = 910 * progress / (0.42 + 0.65 * progress)
        // Pitching looks toward home plate, reversing both axes of the diamond.
        return camera == .pitcher ? (-lateral, 990 - depth) : (lateral, depth)
    }

    private static func component(_ value: Int, alpha: Int) -> UInt8 {
        UInt8((max(0, min(255, value)) * alpha + 127) / 255)
    }
}

/// Composites the venue and turf into the fixed pitching and batting backgrounds.
@MainActor enum MatchStadiumBackdropArt {
    final class Artwork {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
        lazy var texture: SKTexture = {
            let texture = SKTexture(image: image); texture.filteringMode = .nearest; return texture
        }()
    }
    private static let cache: NSCache<NSString, Artwork> = {
        let cache = NSCache<NSString, Artwork>(); cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 6
        return cache
    }()
    private static let umpire: UIImage? = {
        guard let url = Bundle.main.url(forResource: "umpire-isolated-v166", withExtension: "png", subdirectory: "MatchArt"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let w = source.width, h = source.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            c.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard drawn else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 32 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY,
              let crop = source.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
        return UIImage(cgImage: crop)
    }()

    static func art(stadium: StadiumIdentity, role: PlayerRole) -> Artwork? {
        guard let venue = stadium.backdrop else { return nil }
        let key = "\(role.rawValue):\(stadium.key):\(venue.imageName)" as NSString
        if let art = cache.object(forKey: key) { return art }
        guard let original = MatchArt.image(role == .batter ? "batter-field-v52" : "pitcher-field-v52"),
              let upper = InplayStadiumArt.upperArt(venue, stadium: stadium)?.image else { return nil }
        if role == .pitcher && umpire == nil { return nil }
        let camera: StadiumSceneDress.Camera = role == .pitcher ? .pitcher : .batter
        let bundledTurf = StadiumTurfArt.image(stadium: stadium, camera: camera)
        let appearance = bundledTurf == nil ? stadium.expandedAppearance : nil
        let size = original.size
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext; context.interpolationQuality = .none
            original.draw(in: bounds)
            if role == .pitcher, let source = original.cgImage {
                // Copy the same horizontal background rows; never touch the plate lines at y >= 675.
                let patch = CGRect(x: 485, y: 290, width: 255, height: 360)
                if let sample = source.cropping(to: CGRect(x: 810, y: 290, width: 255, height: 360)) {
                    UIImage(cgImage: sample).draw(in: patch)
                }
            }
            let cutoff = size.height * (role == .pitcher ? 487.0 / 1290.0 : 280.0 / 1254.0)
            let viewport = CGRect(x: 0, y: 0, width: size.width, height: cutoff)
            context.saveGState(); context.clip(to: viewport)
            let scale = max(viewport.width / upper.size.width, viewport.height / upper.size.height)
            let projected = CGSize(width: upper.size.width * scale, height: upper.size.height * scale)
            upper.draw(in: CGRect(x: (viewport.width - projected.width) / 2,
                                  y: (viewport.height - projected.height) / 2,
                                  width: projected.width, height: projected.height))
            context.restoreGState()
            if let bundledTurf {
                bundledTurf.draw(in: bounds)
            } else if let appearance, let composite = context.makeImage() {
                StadiumExpandedTurf.overlay(for: UIImage(cgImage: composite), camera: camera,
                                            appearance: appearance, venue: venue)?.draw(in: bounds)
            }
            if role == .pitcher, let umpire {
                let box = CGRect(x: 490, y: 295, width: 240, height: 350)
                let scale = min(box.width / umpire.size.width, box.height / umpire.size.height)
                let target = CGSize(width: umpire.size.width * scale, height: umpire.size.height * scale)
                umpire.draw(in: CGRect(x: box.midX - target.width / 2, y: box.maxY - target.height,
                                      width: target.width, height: target.height))
            }
        }
        let result = Artwork(image)
        cache.setObject(result, forKey: key, cost: Int(size.width * size.height) * 8)
        return result
    }
}
