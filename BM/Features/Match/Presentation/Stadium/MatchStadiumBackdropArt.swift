import SpriteKit
import UIKit

/// Changes only the distant stands. The original plate, mound and actor projection stay fixed.
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
        let key = "v166-1:\(role.rawValue):\(stadium.key):\(venue.imageName)" as NSString
        if let art = cache.object(forKey: key) { return art }
        guard let original = MatchArt.image(role == .batter ? "batter-field-v52" : "pitcher-field-v52"),
              let upper = InplayStadiumArt.upperArt(venue)?.image else { return nil }
        if role == .pitcher && umpire == nil { return nil }
        let size = original.size
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext; context.interpolationQuality = .none
            original.draw(in: CGRect(origin: .zero, size: size))
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
