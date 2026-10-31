import SwiftUI

/// Shared, authored pixel data keeps native icons and design exports identical.
struct SchoolCrest: View {
    let school: School
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        Canvas { context, size in
            let unit = floor(min(size.width, size.height) / 32 * displayScale) / displayScale
            let origin = CGPoint(x: (size.width - 32*unit)/2, y: (size.height - 32*unit)/2)
            func box(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: Int) {
                context.fill(Path(CGRect(x: origin.x + Double(x)*unit, y: origin.y + Double(y)*unit,
                                         width: Double(width)*unit, height: Double(height)*unit)), with: .color(Color(hex: color)))
            }
            if let emblem = school.emblem, emblem.isValid {
                for (y, row) in emblem.pixels.enumerated() {
                    let pixels = Array(row.utf8)
                    var x = 0
                    while x < pixels.count {
                        let color = pixels[x], start = x
                        while x < pixels.count && pixels[x] == color { x += 1 }
                        if color != 48 { box(start, y, x-start, 1, emblem.palette[Int(color-48)]) }
                    }
                }
            } else {
                // Old three-field/custom school data has no emblem; retain a neutral baseball.
                for (x, y, w, h) in [(10, 4, 12, 24), (6, 8, 20, 16), (4, 12, 24, 8)] { box(x, y, w, h, 0xf2e9ce) }
                for y in stride(from: 8, through: 24, by: 4) { box(9, y, 3, 1, 0x9b4545); box(20, y, 3, 1, 0x9b4545) }
            }
        }.accessibilityLabel(school.name + " 교표 · " + (school.emblem?.symbol ?? "기본 야구공"))
    }
}

struct SchoolReputationLabels: View {
    let school: School
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { labels }
            VStack(alignment: .leading, spacing: 6) { labels }
        }
    }
    @ViewBuilder private var labels: some View {
        Text(school.reputation).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 4)
            .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.boardLine))
        if school.openingWorldChampion {
            Text("2025 우승 · 설정").font(.caption.bold()).foregroundStyle(GameTheme.gold)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.gold))
        }
    }
}

struct PixelPlayer: View {
    let appearance: PlayerAppearance
    var body: some View {
        Canvas { context, size in
            let unit = floor(min(size.width / 16, size.height / 20))
            let origin = CGPoint(x: (size.width - unit * 16) / 2, y: (size.height - unit * 20) / 2)
            func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: Int) {
                context.fill(Path(CGRect(x: origin.x + Double(x) * unit, y: origin.y + Double(y) * unit,
                                         width: Double(w) * unit, height: Double(h) * unit)), with: .color(Color(hex: hex)))
            }
            let skin = PlayerAppearance.skinColors[appearance.skin]
            let hair = PlayerAppearance.hairColors[appearance.hair]
            let kit = PlayerAppearance.kitColors[appearance.kit]
            box(4, 1, 8, 7, 0x14283f); box(5, 2, 6, 6, skin)
            box(4, 1, 8, 2, hair)
            if appearance.hairStyle == 1 { box(4, 3, 2, 2, hair) }
            if appearance.hairStyle == 2 { box(3, 1, 2, 3, hair); box(11, 1, 2, 3, hair) }
            box(6, 4, 1, 1, 0x14283f); box(9, 4, 1, 1, 0x14283f)
            if appearance.expression == 1 { box(6, 3, 2, 1, hair) }
            if appearance.expression == 2 { box(7, 6, 2, 1, 0x85442e) }
            box(4, 8, 8, 7, kit); box(7, 8, 2, 6, 0xf4f0db)
            box(2, 9, 2, 5, skin); box(12, 9, 2, 5, skin)
            box(4, 15, 3, 3, 0xe3e6d9); box(9, 15, 3, 3, 0xe3e6d9)
            box(3, 18, 4, 2, 0x14283f); box(9, 18, 4, 2, 0x14283f)
        }.accessibilityLabel("선택한 도트 선수 외형")
    }
}

/// The shared header portrait reads appearance only and caches its tinted raster.
struct ManagementPlayerPortrait: View {
    let appearance: PlayerAppearance
    @State private var image: UIImage?
    private var key: String { "\(appearance.skin):\(appearance.hair):\(appearance.kit)" }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFill().clipped() }
            else { PixelPlayer(appearance: appearance) }
        }.accessibilityHidden(true)
            .task(id: key) { image = ManagementPortraitRaster.image(appearance) }
    }
}

@MainActor enum ManagementPortraitRaster {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 12; return cache
    }()
    static func image(_ appearance: PlayerAppearance) -> UIImage? {
        guard appearance.isValid else { return nil }
        let key = "\(appearance.skin):\(appearance.hair):\(appearance.kit)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = UIImage(named: "PlayerPortraitV91")?.cgImage else { return nil }
        let width = 128, height = 160
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let space = CGColorSpaceCreateDeviceRGB()
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: format) else { return false }
            context.interpolationQuality = .none
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard decoded else { return nil }
        // Connected background is excluded so a uniform change cannot recolor the panel.
        let base = [Int(bytes[0]), Int(bytes[1]), Int(bytes[2])]
        var background = [Bool](repeating: false, count: width * height), queue = [Int]()
        func enqueue(_ position: Int) {
            guard !background[position] else { return }
            let offset = position * 4
            let difference = (0..<3).reduce(0) { total, channel in
                let delta = Int(bytes[offset + channel]) - base[channel]; return total + delta * delta
            }
            guard difference < 900 else { return }
            background[position] = true; queue.append(position)
        }
        for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
        for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
        var cursor = 0
        while cursor < queue.count {
            let position = queue[cursor]; cursor += 1
            let x = position % width, y = position / width
            if x > 0 { enqueue(position - 1) }; if x + 1 < width { enqueue(position + 1) }
            if y > 0 { enqueue(position - width) }; if y + 1 < height { enqueue(position + width) }
        }
        for position in 0..<(width * height) where !background[position] {
            let i = position * 4, r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
            let y = Double(position / width) / Double(height)
            var tint: Int?, shade = 1.0
            if r > 110 && Double(r) > Double(g) * 1.15 && Double(g) > Double(b) * 1.12 {
                tint = PlayerAppearance.skinColors[appearance.skin]; shade = Double(r) / 245
            } else if y < 0.45 && r > 25 && r < 110 && Double(r) > Double(g) * 1.2 && g > b {
                tint = PlayerAppearance.hairColors[appearance.hair]; shade = Double(r) / 82
            } else if b > 45 && Double(b) > Double(r) * 1.3 && Double(b) > Double(g) * 1.15 {
                tint = PlayerAppearance.kitColors[appearance.kit]; shade = Double(b) / 115
            }
            if let tint {
                for channel in 0..<3 {
                    let value = Double((tint >> (16 - channel * 8)) & 255) * max(0.25, min(1.5, shade))
                    bytes[i + channel] = UInt8(min(255, max(0, Int(value))))
                }
            }
        }
        let rendered = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: format)?.makeImage()
        }
        guard let rendered else { return nil }
        let image = UIImage(cgImage: rendered)
        cache.setObject(image, forKey: key)
        return image
    }
}
