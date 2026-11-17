import SpriteKit
import SwiftUI
import UIKit

/// Measured on the shared 1024 × 1536 field art, with actors and bases on their existing projection.
struct StadiumBackdrop {
    let imageName: String
    let pixelSize: CGSize
    let height: CGFloat
    let board: CGRect
    let name: String
    let panel: Int
    let trim: Int
    var compact = false
    var logoAsset: String? = nil

    static func tintedPanel(primary: Int) -> Int {
        let neutral = 0x102321
        return [16, 8, 0].reduce(0) { result, shift in
            let tint = (primary >> shift) & 0xff
            let base = (neutral >> shift) & 0xff
            return result | (((base * 2 + tint) / 3) << shift)
        }
    }
}

// V144 uses the same home team IDs as fixtures and saved results.
struct SchoolStadium: Sendable {
    enum Structure: String, CaseIterable, Sendable {
        case manualWall = "manual-wall"
        case steelGantry = "steel-gantry"
        case stoneTerrace = "stone-terrace"
        case harborCorner = "harbor-corner"
        case forestTimber = "forest-timber"
        case canopyFascia = "canopy-fascia"
        case brickArch = "brick-arch"
        case schoolWall = "school-wall"
        case backstopCrossbeam = "backstop-crossbeam"
        case basaltSide = "basalt-side"

        var imageName: String { "school-stadium-v144-" + rawValue }

        // Coordinates of the usable face, in pixels of the 1024 × 1536 art.
        var board: CGRect {
            switch self {
            case .manualWall: CGRect(x: 411, y: 255, width: 203, height: 58)
            case .steelGantry: CGRect(x: 352, y: 130, width: 319, height: 81)
            case .stoneTerrace: CGRect(x: 398, y: 186, width: 227, height: 67)
            case .harborCorner: CGRect(x: 720, y: 188, width: 229, height: 77)
            case .forestTimber: CGRect(x: 390, y: 194, width: 243, height: 60)
            case .canopyFascia: CGRect(x: 326, y: 172, width: 373, height: 32)
            case .brickArch: CGRect(x: 378, y: 174, width: 268, height: 84)
            case .schoolWall: CGRect(x: 397, y: 168, width: 232, height: 66)
            case .backstopCrossbeam: CGRect(x: 391, y: 191, width: 242, height: 40)
            case .basaltSide: CGRect(x: 666, y: 115, width: 148, height: 124)
            }
        }
    }

    let structure: Structure
    let name: String
    let primary: Int
    var panel: Int { StadiumBackdrop.tintedPanel(primary: primary) }
    var backdrop: StadiumBackdrop {
        StadiumBackdrop(imageName: structure.imageName, pixelSize: CGSize(width: 1024, height: 416),
                        height: 416, board: structure.board, name: name, panel: panel, trim: primary,
                        compact: structure == .canopyFascia || structure == .backstopCrossbeam)
    }

    private static let structureByID: [String: Structure] = {
        // Each list begins with the example school reviewed in V144.
        let groups: [(Structure, [Int])] = [
            (.manualWall, [1, 4, 8, 15, 36]),
            (.steelGantry, [2, 5, 11, 25, 26]),
            (.stoneTerrace, [23, 10, 14, 21, 44]),
            (.harborCorner, [24, 18, 19, 38, 52]),
            (.forestTimber, [29, 12, 28, 30, 47]),
            (.canopyFascia, [31, 6, 17, 32, 35]),
            (.brickArch, [37, 7, 20, 34, 46]),
            (.schoolWall, [42, 13, 22, 33, 51]),
            (.backstopCrossbeam, [43, 3, 9, 27, 45]),
            (.basaltSide, [50, 39, 40, 48, 49])
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { structure, numbers in
            numbers.map { ("hs-ref-" + String(format: "%03d", $0), structure) }
        })
    }()
    @MainActor private static let stadiumsByID: [String: Self] = Dictionary(uniqueKeysWithValues: SchoolCatalog.bundled.compactMap { school in
        guard let structure = structureByID[school.id],
              let primary = GameUniformPalette.color(teamID: school.id) else { return nil }
        return (school.id, Self(structure: structure, name: school.name, primary: primary))
    })

    @MainActor static func resolve(_ homeTeamID: String) -> Self? {
        guard structureByID[homeTeamID] != nil else { return nil }
        return stadiumsByID[homeTeamID]
    }
}

struct ProStadium {
    let club: ClubIdentity
    let primary: Int
    let accent: Int
    let board: CGRect

    var panel: Int { StadiumBackdrop.tintedPanel(primary: primary) }
    var backdrop: StadiumBackdrop {
        let prefix = club.isExpansionClub ? "pro-stadium-v147-" : "pro-stadium-v145-"
        return StadiumBackdrop(imageName: prefix + club.id, pixelSize: CGSize(width: 768, height: 348),
                        height: 464, board: board, name: club.name, panel: panel, trim: accent, logoAsset: club.asset)
    }

    // V145 display data only. League eligibility, fixture IDs and saved names stay engine-owned.
    private static let venueArt: [String: (board: CGRect, accent: Int)] = [
        "kbo-0": (board: CGRect(x: 368, y: 208, width: 288, height: 75), accent: 0xdba140),
        "kbo-1": (board: CGRect(x: 112, y: 137, width: 252, height: 62), accent: 0xb23741),
        "kbo-2": (board: CGRect(x: 336, y: 151, width: 344, height: 82), accent: 0xdb6f5a),
        "kbo-3": (board: CGRect(x: 328, y: 173, width: 364, height: 91), accent: 0x4b379e),
        "kbo-4": (board: CGRect(x: 384, y: 168, width: 252, height: 104), accent: 0xdbae5d),
        "kbo-5": (board: CGRect(x: 388, y: 193, width: 244, height: 80), accent: 0xdba449),
        "kbo-6": (board: CGRect(x: 672, y: 97, width: 272, height: 73), accent: 0x9e1f45),
        "kbo-7": (board: CGRect(x: 384, y: 206, width: 252, height: 78), accent: 0xd7ae58),
        "kbo-8": (board: CGRect(x: 364, y: 171, width: 296, height: 98), accent: 0x4fbdad),
        "kbo-9": (board: CGRect(x: 384, y: 142, width: 252, height: 83), accent: 0xa22d3e),
        "npb-0": (board: CGRect(x: 365, y: 251, width: 294, height: 72), accent: 0xdba631),
        "npb-1": (board: CGRect(x: 388, y: 218, width: 247, height: 68), accent: 0x41b6ac),
        "npb-2": (board: CGRect(x: 385, y: 192, width: 253, height: 71), accent: 0xdb9d34),
        "npb-3": (board: CGRect(x: 371, y: 241, width: 282, height: 61), accent: 0xdba02a),
        "npb-4": (board: CGRect(x: 382, y: 264, width: 259, height: 63), accent: 0x7d9e4b),
        "npb-5": (board: CGRect(x: 389, y: 190, width: 247, height: 64), accent: 0x9e325b),
        "npb-6": (board: CGRect(x: 390, y: 209, width: 245, height: 64), accent: 0x6d479e),
        "npb-7": (board: CGRect(x: 378, y: 217, width: 268, height: 65), accent: 0xccba40),
        "npb-8": (board: CGRect(x: 381, y: 207, width: 261, height: 63), accent: 0xd7ae58),
        "npb-9": (board: CGRect(x: 373, y: 197, width: 278, height: 70), accent: 0x1c84a7),
        "mlb-0": (board: CGRect(x: 350, y: 208, width: 325, height: 61), accent: 0xdb6b3e),
        "mlb-1": (board: CGRect(x: 104, y: 121, width: 208, height: 53), accent: 0x149aa4),
        "mlb-2": (board: CGRect(x: 374, y: 105, width: 278, height: 86), accent: 0x3da3a9),
        "mlb-3": (board: CGRect(x: 312, y: 199, width: 390, height: 71), accent: 0xd7ae58),
        "mlb-4": (board: CGRect(x: 355, y: 151, width: 320, height: 79), accent: 0x1272a1),
        "mlb-5": (board: CGRect(x: 414, y: 116, width: 197, height: 101), accent: 0xd7ae58),
        "mlb-6": (board: CGRect(x: 360, y: 155, width: 303, height: 71), accent: 0xd7ae58),
        "mlb-7": (board: CGRect(x: 668, y: 193, width: 246, height: 74), accent: 0x109aa2),
        "mlb-8": (board: CGRect(x: 218, y: 118, width: 193, height: 73), accent: 0x9e2230),
        "mlb-9": (board: CGRect(x: 380, y: 216, width: 266, height: 74), accent: 0x4d89bb),
        "npb-10": (board: CGRect(x: 361, y: 201, width: 302, height: 70), accent: 0xc87642),
        "npb-11": (board: CGRect(x: 361, y: 198, width: 302, height: 64), accent: 0xe0b854),
        "npb-12": (board: CGRect(x: 363, y: 210, width: 300, height: 71), accent: 0xe5a354),
        "npb-13": (board: CGRect(x: 372, y: 250, width: 280, height: 55), accent: 0xebd39c),
        "npb-14": (board: CGRect(x: 366, y: 207, width: 292, height: 68), accent: 0x80ae64),
        "mlb-10": (board: CGRect(x: 170, y: 191, width: 282, height: 57), accent: 0xd69449),
        "mlb-11": (board: CGRect(x: 335, y: 197, width: 353, height: 55), accent: 0xd9b060),
        "mlb-12": (board: CGRect(x: 331, y: 207, width: 360, height: 63), accent: 0xa0c16c),
        "mlb-13": (board: CGRect(x: 312, y: 265, width: 400, height: 57), accent: 0xeaaa4d),
        "mlb-14": (board: CGRect(x: 337, y: 216, width: 350, height: 63), accent: 0xe3a76f),
    ]

    @MainActor private static let venuesByHomeID: [String: Self] = {
        var venues = Dictionary(uniqueKeysWithValues: ClubIdentity.all.compactMap { club -> (String, Self)? in
            guard let art = venueArt[club.id], let primary = GameUniformPalette.color(teamID: club.id) else { return nil }
            return (club.id, Self(club: club, primary: primary, accent: art.accent, board: art.board))
        })
        let seasonTeams = CareerTeamDirectory.expandedDomesticFirstIDs + CareerTeamDirectory.japaneseExpandedFirstIDs + CareerTeamDirectory.americanExpandedFirstIDs
        for id in seasonTeams {
            guard let club = ClubIdentity.resolve(name: CareerTeamDirectory.name(id)) else { continue }
            venues[id] = venues[club.id]
        }
        return venues
    }()

    @MainActor static func resolve(_ homeTeamID: String) -> Self? { venuesByHomeID[homeTeamID] }
}

struct StadiumVenueAppearance: Equatable {
    enum Direction: String {
        case horizontal, vertical, diagonal, crosshatch
    }

    enum Family: String {
        case park, terrace, coastal, canopy, brick, woodland, sunlit

        var palette: (color: Int, direction: Direction, bandWidth: Int, contrast: Int, trim: Int) {
            switch self {
            case .park: (0x4d8747, .horizontal, 92, 18, 0x778066)
            case .terrace: (0x4b774c, .diagonal, 92, 14, 0x879087)
            case .coastal: (0x418e67, .horizontal, 122, 16, 0x568381)
            case .canopy: (0x2c775a, .vertical, 77, 18, 0x7a8494)
            case .brick: (0x65923e, .diagonal, 112, 18, 0x9a6e56)
            case .woodland: (0x3c8053, .crosshatch, 95, 12, 0x726f52)
            case .sunlit: (0x789044, .diagonal, 153, 17, 0x9b8661)
            }
        }

        init(school structure: SchoolStadium.Structure) {
            switch structure {
            case .manualWall, .schoolWall: self = .park
            case .steelGantry, .canopyFascia, .backstopCrossbeam: self = .canopy
            case .stoneTerrace, .basaltSide: self = .terrace
            case .harborCorner: self = .coastal
            case .forestTimber: self = .woodland
            case .brickArch: self = .brick
            }
        }

        // The roof, setting and materials are those of the bundled V145/V147 backdrops.
        private static let proFamilies: [String: Family] = {
            let groups: [(Family, [String])] = [
                (.park, ["npb-0", "npb-11", "mlb-3", "mlb-5"]),
                (.terrace, ["kbo-7", "npb-6", "npb-10", "mlb-1", "mlb-9"]),
                (.coastal, ["kbo-0", "kbo-2", "npb-1", "npb-7", "npb-9", "npb-13", "mlb-4", "mlb-7"]),
                (.canopy, ["kbo-1", "kbo-6", "kbo-8", "npb-3", "npb-4", "mlb-6"]),
                (.brick, ["kbo-4", "kbo-9", "npb-2", "npb-12", "mlb-8", "mlb-10"]),
                (.woodland, ["npb-8", "mlb-2", "mlb-11", "mlb-12"]),
                (.sunlit, ["kbo-5", "npb-5", "npb-14", "mlb-13", "mlb-14"])
            ]
            return Dictionary(uniqueKeysWithValues: groups.flatMap { family, ids in ids.map { ($0, family) } })
        }()

        init?(clubID: String) {
            guard let family = Self.proFamilies[clubID] else { return nil }
            self = family
        }
    }

    let id: String
    let family: Family
    let standTint: Int
    private let turfVariation: Int

    init(id: String, family: Family, standTint: Int) {
        self.id = id
        self.family = family
        self.standTint = standTint
        let number = id.split(separator: "-").last.flatMap { Int($0) } ?? 0
        let offset = id.hasPrefix("npb-") ? 12 : id.hasPrefix("mlb-") ? 5 : 0
        turfVariation = (number * 7 + offset) % 13 - 6
    }

    var baseColor: Int {
        let color = family.palette.color
        // Vary the color and band spacing between venues that share a backdrop and team palette.
        func channel(_ shift: Int) -> Int { Int(UInt8(clamping: ((color >> shift) & 255) + turfVariation)) << shift }
        return channel(16) | channel(8) | channel(0)
    }
    var direction: Direction { family.palette.direction }
    var bandWidth: Int { family.palette.bandWidth + turfVariation * 3 }
    var contrast: Int { family.palette.contrast }
    var standTrim: Int { family.palette.trim }
}

extension StadiumIdentity {
    @MainActor var school: SchoolStadium? { SchoolStadium.resolve(key) }
    @MainActor var pro: ProStadium? { ProStadium.resolve(key) }
    @MainActor var backdrop: StadiumBackdrop? { school?.backdrop ?? pro?.backdrop }
    @MainActor var panelColor: Int { school?.panel ?? pro?.panel ?? theme.panel }
    @MainActor var trimColor: Int { school?.primary ?? pro?.primary ?? theme.trim }
    @MainActor var accentColor: Int { school?.primary ?? pro?.accent ?? theme.accent }

    @MainActor var expandedAppearance: StadiumVenueAppearance? {
        if let school, key != "hs-ref-014", key != "hs-ref-024" {
            return StadiumVenueAppearance(id: key, family: .init(school: school.structure), standTint: school.primary)
        }
        if let pro, let family = StadiumVenueAppearance.Family(clubID: pro.club.id) {
            return StadiumVenueAppearance(id: pro.club.id, family: family, standTint: pro.primary)
        }
        return nil
    }
}

enum StadiumCrowdArt {
    static func styled(_ source: UIImage, in venue: StadiumBackdrop, appearance: StadiumVenueAppearance) -> UIImage {
        guard let image = source.cgImage, venue.height > 0 else { return source }
        let width = image.width
        let height = image.height
        let rowBytes = width * 4
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return source }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Scoreboard geometry uses the shared 1024-wide field coordinates, even for 768-wide pro art.
        let scaleX = CGFloat(width) / 1024
        let scaleY = CGFloat(height) / venue.height
        let board = venue.board.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .insetBy(dx: -8 * scaleX, dy: -7 * scaleY).integral
        let school = appearance.id.hasPrefix("hs-ref-")
        let terrace = appearance.family == .terrace
        let top = Int(Double(height) * (school ? (terrace ? 0.41 : 0.49) : 0.36))
        let bottom = Int(Double(height) * (school ? 0.88 : 0.92))
        let facade = Int(Double(height) * 0.73)
        let railBottom = Int(Double(height) * (school ? 0.81 : 0.85))
        let seaMargin = appearance.family == .coastal ? width / 9 : 0
        let team = Tint(rgb: appearance.standTint)
        let material = Tint(rgb: appearance.standTrim)
        for y in top..<bottom {
            let boardRow = y >= Int(board.minY) && y < Int(board.maxY)
            let margin = y < facade ? seaMargin : 0
            for x in margin..<(width - margin) {
                if boardRow, x >= Int(board.minX), x < Int(board.maxX) { continue }
                let pixel = pixels + y * rowBytes + x * 4
                if pixel[3] != 255 { continue }
                let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
                let light = Tint.luminance(r, g, b)
                let chroma = max(r, g, b) - min(r, g, b)
                let green = g > r + 14 && g > b + 11
                let railPaint = green && y >= facade - height / 16 && y < railBottom && b >= r && light < 112
                // Keep daylight, bright crowd pixels, living greens and amber features in the original art.
                if light < 28 || light > 165 || (green && !railPaint)
                    || (b > r + 22 && g > 120 && b > 145)
                    || (r > 128 && r > g + 18 && g > b + 22) { continue }

                let coolPaint = b > r + 12 && b > g - 12
                let warmPaint = r > g + 13 && b >= g - 23
                let darkTeal = b > r + 12 && g > r + 12 && light < 105
                let painted = coolPaint || warmPaint || darkTeal || railPaint
                let fasciaPaint = y >= facade && chroma >= 18 && r <= 128
                if painted || fasciaPaint {
                    team.apply(to: pixel, light: light, amount: y >= facade ? 76 : 64)
                } else if chroma <= 28 && light > 53 {
                    material.apply(to: pixel, light: light, amount: y >= facade ? 41 : 27)
                }
            }
        }

        guard let shaded = context.makeImage() else { return source }
        return UIImage(cgImage: shaded, scale: source.scale, orientation: source.imageOrientation)
    }

    private struct Tint {
        let red: Int, green: Int, blue: Int
        let light: Int

        init(rgb: Int) {
            red = (rgb >> 16) & 255
            green = (rgb >> 8) & 255
            blue = rgb & 255
            light = Self.luminance(red, green, blue)
        }

        static func luminance(_ red: Int, _ green: Int, _ blue: Int) -> Int {
            (54 * red + 183 * green + 19 * blue) >> 8
        }

        func apply(to pixel: UnsafeMutablePointer<UInt8>, light originalLight: Int, amount: Int) {
            // Shade according to the authored pixel brightness so seat rows and fencing keep their contrast.
            let targetLight = originalLight + (light - 96) / 7
            func channel(_ original: UInt8, _ tint: Int) -> UInt8 {
                let target = targetLight + (tint - light) * 4 / 5
                return UInt8(clamping: (Int(original) * (100 - amount) + target * amount) / 100)
            }
            pixel[0] = channel(pixel[0], red)
            pixel[1] = channel(pixel[1], green)
            pixel[2] = channel(pixel[2], blue)
        }
    }
}

/// 구장 장식과 축하 효과만 담당한다. 판정·저장·경기 난수에는 관여하지 않는다.
@MainActor final class StadiumSceneDress: SKNode {
    enum Camera { case batter, pitcher, field }
    enum Celebration: String { case homeRun, doublePlay }

    struct HomeRunLayout {
        struct Burst {
            let index: Int
            let bounds: CGRect
            let radius: CGFloat
            let delay: TimeInterval
            let spokeCount: Int
        }

        static let scoreboardClearance: CGFloat = 8
        let bannerFrame: CGRect
        let bursts: [Burst]
        private let protectedFrames: [CGRect]

        // The scoreboard and this layout use the same top-origin scene coordinates.
        init(size: CGSize, scoreboardFrame: CGRect?) {
            let unit = size.width / 390
            let sky = CGRect(x: 4 * unit, y: 4 * unit, width: size.width - 8 * unit,
                             height: size.height * 0.32 - 4 * unit)
            let board = scoreboardFrame?.insetBy(dx: -Self.scoreboardClearance, dy: -Self.scoreboardClearance)
            let preferredBanner = CGRect(x: size.width * 0.24, y: size.height * 0.125 - 14,
                                         width: size.width * 0.52, height: 28)
            if let board, preferredBanner.intersects(board) {
                let above = board.minY - preferredBanner.height - 1
                let below = board.maxY + 1
                let hasRoomAbove = above >= sky.minY
                let fitsBetterAbove = preferredBanner.minY - above <= below - preferredBanner.minY
                let y = hasRoomAbove && fitsBetterAbove ? above : below
                bannerFrame = preferredBanner.offsetBy(dx: 0, dy: y - preferredBanner.minY)
            } else {
                bannerFrame = preferredBanner
            }
            let obstacles = [board, bannerFrame.insetBy(dx: -3 * unit, dy: -3 * unit)].compactMap { $0 }
            protectedFrames = obstacles
            let slots: [(x: CGFloat, y: CGFloat, radius: CGFloat, delay: TimeInterval, spokeCount: Int)] = [
                (0.20, 0.075, 38, 0.00, 12),
                (0.80, 0.075, 38, 0.12, 12),
                (0.11, 0.130, 20, 0.21, 6),
                (0.89, 0.130, 20, 0.29, 6),
            ]
            bursts = slots.enumerated().compactMap { index, slot in
                let preferred = CGPoint(x: size.width * slot.x, y: size.height * slot.y)
                let halfWidth = size.width * 0.5
                let side = CGRect(x: slot.x < 0.5 ? sky.minX : halfWidth, y: sky.minY,
                                  width: halfWidth - sky.minX, height: sky.height)
                for radiusScale: CGFloat in [1, 0.75] {
                    let radius = slot.radius * unit * radiusScale
                    // The 4 pt sparks include half their width beyond the maximum travel.
                    let extent = max(radius + 2 * unit, 8 * unit)
                    if let origin = Self.burstOrigin(near: preferred, extent: extent, in: side, avoiding: obstacles) {
                        let bounds = CGRect(x: origin.x - extent, y: origin.y - extent, width: 2 * extent, height: 2 * extent)
                        return Burst(index: index, bounds: bounds, radius: radius, delay: slot.delay, spokeCount: slot.spokeCount)
                    }
                }
                return nil
            }
        }

        func leavesClear(_ frame: CGRect) -> Bool {
            !protectedFrames.contains { $0.intersects(frame) }
        }

        private static func burstOrigin(near preferred: CGPoint, extent: CGFloat, in area: CGRect,
                                        avoiding obstacles: [CGRect]) -> CGPoint? {
            guard area.width > extent * 2, area.height > extent * 2 else { return nil }
            let centers = area.insetBy(dx: extent, dy: extent)
            let blocked = obstacles.map { $0.insetBy(dx: -extent, dy: -extent) }
            func bounded(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: min(centers.maxX, max(centers.minX, x)), y: min(centers.maxY, max(centers.minY, y)))
            }
            let closest = bounded(preferred.x, preferred.y)
            if !blocked.contains(where: { $0.contains(closest) }) { return closest }

            // A legal center near the default lies just beyond an obstacle edge or corner.
            let xs = [closest.x] + blocked.flatMap { [$0.minX - 1, $0.maxX + 1] }
            let ys = [closest.y] + blocked.flatMap { [$0.minY - 1, $0.maxY + 1] }
            return xs.flatMap { x in ys.map { bounded(x, $0) } }
                .filter { point in !blocked.contains { $0.contains(point) } }
                .min { a, b in
                    hypot(a.x - preferred.x, a.y - preferred.y) < hypot(b.x - preferred.x, b.y - preferred.y)
                }
        }
    }

    let stadium: StadiumIdentity
    let fieldSize: CGSize
    private let homeRunLayout: HomeRunLayout?
    private let effects = SKNode()
    private var lamps: [SKSpriteNode] = []
    private var floodlights: [SKNode] = []
    private let homeRunSign = SKNode()
    private(set) var celebration: Celebration?
    private(set) var celebrationCount = 0
    var effectNodeCount: Int { effects.children.count }
    var floodlightCount: Int { floodlights.count }
    var animatedLightCount: Int { (lamps.map { $0 as SKNode } + floodlights).filter { $0.hasActions() }.count }
    init(stadium: StadiumIdentity, size: CGSize, camera: Camera, hasVenueBackdrop: Bool = false, scoreboardFrame: CGRect? = nil) {
        self.stadium = stadium
        fieldSize = size
        homeRunLayout = camera == .field ? HomeRunLayout(size: size, scoreboardFrame: scoreboardFrame) : nil
        super.init()
        name = "stadiumDress-" + stadium.theme.title
        let y: CGFloat = camera == .pitcher ? 0.25 : camera == .batter ? 0.166 : 0.15
        let positions: [CGFloat] = hasVenueBackdrop ? [] : camera == .field ? [0.13, 0.87] : [0.16, 0.84]
        let school = stadium.school
        let pro = stadium.pro
        let panelColor = UIColor(Color(hex: stadium.panelColor))
        let trimColor = UIColor(Color(hex: stadium.trimColor))
        let accentColor = UIColor(Color(hex: stadium.accentColor))
        if hasVenueBackdrop, camera != .field, let pro {
            let logo = SKSpriteNode(imageNamed: pro.club.asset)
            logo.name = "match-club-logo-" + pro.club.id; logo.texture?.filteringMode = .nearest
            logo.size = CGSize(width: size.width * 0.045, height: size.width * 0.045)
            logo.position = CGPoint(x: size.width * 0.95, y: size.height * 0.95)
            addChild(logo)
        }
        for (i, x) in positions.enumerated() {
            let sponsor = stadium.sponsors[i]
            let venueName = i == 0 ? school?.name ?? pro?.club.name : nil
            let w = size.width * (camera == .field ? 0.20 : 0.22)
            let h = max(12, size.width * 0.052)
            let panel = SKShapeNode(rectOf: CGSize(width: w, height: h))
            panel.fillColor = panelColor
            panel.strokeColor = trimColor
            panel.lineWidth = 1
            panel.position = CGPoint(x: size.width * x, y: size.height * (1 - y))
            addChild(panel)
            let mark = SKLabelNode(fontNamed: "Menlo-Bold")
            mark.text = sponsor.mark
            mark.fontSize = h * 0.60
            mark.fontColor = accentColor
            mark.verticalAlignmentMode = .center
            mark.position.x = -w * 0.36
            if venueName == nil { panel.addChild(mark) }
            if i == 0, let pro {
                let logo = SKSpriteNode(imageNamed: pro.club.asset)
                logo.name = "match-club-logo-" + pro.club.id
                logo.texture?.filteringMode = .nearest
                logo.size = CGSize(width: h * 0.85, height: h * 0.85)
                logo.position.x = -w * 0.36
                panel.addChild(logo)
            }
            let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
            label.text = venueName ?? sponsor.name
            label.fontSize = venueName.map { min(h * 0.53, w * (pro == nil ? 0.88 : 0.65) / CGFloat($0.count)) } ?? (h * 0.43)
            label.fontColor = UIColor(GameTheme.paper)
            label.verticalAlignmentMode = .center
            label.position.x = venueName == nil || pro != nil ? w * 0.12 : 0
            panel.addChild(label)
        }
        for i in 0..<12 {
            let light = SKSpriteNode(
                color: trimColor, size: CGSize(width: size.width * 0.022, height: 2))
            light.position = CGPoint(
                x: size.width * (0.12 + Double(i) * 0.069), y: size.height * (1 - (camera == .field ? 0.19 : 0.205)))
            light.alpha = 0.48
            light.isHidden = hasVenueBackdrop
            lamps.append(light)
            addChild(light)
        }
        if let homeRunLayout {
            for i in 0..<4 {
                let bank = SKNode()
                bank.position = CGPoint(
                    x: size.width * (i.isMultiple(of: 2) ? 0.08 : 0.92), y: size.height * (i < 2 ? 0.95 : 0.76))
                let frame = SKSpriteNode(
                    color: panelColor, size: CGSize(width: 32, height: 17))
                bank.addChild(frame)
                for cell in 0..<8 {
                    let bulb = SKSpriteNode(color: UIColor(GameTheme.paper), size: CGSize(width: 5, height: 5))
                    bulb.position = CGPoint(x: CGFloat(cell % 4) * 7 - 10.5, y: CGFloat(cell / 4) * 7 - 3.5)
                    bank.addChild(bulb)
                }
                bank.alpha = 0.55
                bank.isHidden = hasVenueBackdrop
                floodlights.append(bank)
                addChild(bank)
            }
            let plate = SKSpriteNode(
                color: panelColor, size: homeRunLayout.bannerFrame.size)
            plate.name = "home-run-banner-plate"
            let text = SKLabelNode(fontNamed: "Menlo-Bold")
            text.name = "home-run-banner-title"
            text.text = "HOME RUN"
            text.fontSize = 18
            text.fontColor = UIColor(GameTheme.gold)
            text.verticalAlignmentMode = .center
            text.zPosition = 1
            homeRunSign.name = "home-run-banner"
            homeRunSign.addChild(plate)
            homeRunSign.addChild(text)
            homeRunSign.position = CGPoint(x: homeRunLayout.bannerFrame.midX, y: size.height - homeRunLayout.bannerFrame.midY)
            homeRunSign.zPosition = 3
            homeRunSign.isHidden = true
            addChild(homeRunSign)
        }
        effects.zPosition = 2
        addChild(effects)
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not used") }
    /// 동작 줄이기에서는 장식 움직임을 없애고 결과 표시는 남긴다.
    func reduceEffects() {
        effects.removeAllChildren()
        for light in lamps {
            light.removeAllActions()
            light.alpha = celebration == nil ? 0.48 : 0.8
        }
        for bank in floodlights {
            bank.removeAllActions()
            bank.alpha = 0.8
        }
    }
    /// 장면당 축하 효과를 한 번만 시작한다. 경기 보상 처리와는 별개다.
    func celebrate(_ kind: Celebration, reduced: Bool, homeRunStyle: MatchHomeRun.CelebrationKind = .standard) {
        guard celebration == nil else { return }
        celebration = kind
        celebrationCount += 1
        homeRunSign.isHidden = kind != .homeRun
        if kind == .homeRun, let title = homeRunStyle.title {
            dressHomeRunSign(title: title, accent: homeRunPalette(homeRunStyle).accent)
        }
        guard !reduced else {
            reduceEffects()
            return
        }
        let delay = Double(stadium.variation) * 0.08
        // 화면 전체를 번쩍이지 않고 조명 묶음만 천천히 두 번 변화시킨다.
        for (i, bank) in floodlights.enumerated() {
            if kind == .homeRun && !clearOfHomeRunArtwork(bank) { continue }
            bank.isHidden = false
            bank.run(
                .sequence([
                    .wait(forDuration: Double(i) * 0.18 + delay),
                    .repeat(
                        .sequence([
                            .fadeAlpha(to: 0.18, duration: 0.28), .fadeAlpha(to: 1, duration: 0.35),
                            .wait(forDuration: 0.6),
                        ]), count: 2), .fadeAlpha(to: 0.8, duration: 0.25),
                ]))
        }
        for (i, light) in lamps.enumerated() {
            if kind == .homeRun && !clearOfHomeRunArtwork(light) { continue }
            light.isHidden = false
            let at = Double(stadium.theme == .brick ? i : 11 - i) * 0.04 + delay
            light.run(
                .sequence([
                    .wait(forDuration: at), .fadeAlpha(to: 1, duration: 0.18), .wait(forDuration: 0.35),
                    .fadeAlpha(to: 0.65, duration: 0.35),
                ]))
        }
        if kind == .homeRun {
            showHomeRunFireworks(style: homeRunStyle)
            return
        }
        for i in 0..<12 {
            let node = SKSpriteNode(
                color: i.isMultiple(of: 3) ? UIColor(GameTheme.gold) : UIColor(Color(hex: stadium.accentColor)),
                size: CGSize(width: 3, height: i < 8 ? 6 : 3))
            let side = i.isMultiple(of: 2) ? 0.23 : 0.77
            node.position = CGPoint(x: fieldSize.width * side, y: fieldSize.height * 0.82)
            effects.addChild(node)
            let angle = Double(i) * 2.3999632297
            let radius = Double(16 + (i % 7) * 7)
            let delta: CGVector
            switch stadium.theme {
            case .harbor: delta = CGVector(dx: cos(angle) * radius, dy: sin(angle) * radius)
            case .brick: delta = CGVector(dx: Double(i % 6 - 3) * 6, dy: Double(12 + i % 8 * 4))
            case .grove: delta = CGVector(dx: Double(i % 6 - 3) * 8, dy: -Double(12 + i % 7 * 5))
            case .metro: delta = CGVector(dx: Double(i % 4 - 2) * 4, dy: Double(20 + i % 8 * 4))
            }
            node.alpha = 0
            node.run(
                .sequence([
                    .wait(forDuration: delay + Double(i % 4) * 0.08), .fadeIn(withDuration: 0.12),
                    .group([
                        .move(by: delta, duration: 0.75),
                        .sequence([.wait(forDuration: 0.40), .fadeOut(withDuration: 0.35)]),
                    ]), .removeFromParent(),
                ]))
        }
    }

    private func clearOfHomeRunArtwork(_ light: SKNode) -> Bool {
        guard let homeRunLayout else { return true }
        let frame = light.calculateAccumulatedFrame()
        let sceneFrame = CGRect(x: frame.minX, y: fieldSize.height - frame.maxY, width: frame.width, height: frame.height)
        return homeRunLayout.leavesClear(sceneFrame)
    }

    private func dressHomeRunSign(title: String, accent: UIColor) {
        guard let homeRunLayout,
              let label = homeRunSign.childNode(withName: "home-run-banner-title") as? SKLabelNode else { return }
        label.text = title
        label.fontColor = accent
        let availableWidth = homeRunLayout.bannerFrame.width - 12
        if availableWidth > 0, label.frame.width > availableWidth {
            label.fontSize *= availableWidth / label.frame.width
        }

        let frame = homeRunLayout.bannerFrame.insetBy(dx: 1, dy: 1)
        let rim = SKShapeNode(rectOf: frame.size)
        rim.name = "home-run-banner-accent"
        rim.strokeColor = accent
        rim.lineWidth = 1
        rim.isAntialiased = false
        rim.zPosition = 0.5
        homeRunSign.addChild(rim)
    }

    private func homeRunPalette(_ style: MatchHomeRun.CelebrationKind)
        -> (accent: UIColor, alternate: UIColor, extraSpokes: Int, secondWaveSlots: Range<Int>) {
        let gold = UIColor(GameTheme.gold)
        switch style {
        case .standard:
            return (gold, UIColor(Color(hex: 0xd4b7f7)), 0, 0..<0)
        case .grandSlam:
            return (gold, UIColor(Color(hex: 0x79efcf)), 4, 0..<2)
        case .goAhead:
            return (UIColor(Color(hex: 0x9fe1ff)), gold, 2, 2..<4)
        case .walkOff:
            return (UIColor(Color(hex: 0xffdc86)), UIColor(Color(hex: 0xffabd2)), 6, 0..<4)
        }
    }

    private func showHomeRunFireworks(style: MatchHomeRun.CelebrationKind) {
        guard let homeRunLayout else { return }
        let palette = homeRunPalette(style)
        for burst in homeRunLayout.bursts {
            let usesAlternate = burst.index == 1 || (style != .standard && burst.index == 3)
            let color = usesAlternate ? palette.alternate : palette.accent
            launchHomeRunBurst(burst, color: color, delay: burst.delay, radius: burst.radius,
                               spokes: burst.spokeCount + palette.extraSpokes)
            if palette.secondWaveSlots.contains(burst.index) {
                let encore = usesAlternate ? palette.accent : palette.alternate
                // Reuse the first burst's clearance envelope for every spoke in the second wave.
                launchHomeRunBurst(burst, color: encore, delay: burst.delay + 0.34,
                                   radius: burst.radius * 0.78, spokes: max(6, burst.spokeCount / 2 + 2), angleOffset: .pi / 10)
            }
        }
    }

    private func launchHomeRunBurst(_ burst: HomeRunLayout.Burst, color: UIColor, delay: TimeInterval,
                                    radius: CGFloat, spokes: Int, angleOffset: CGFloat = 0) {
        let cream = UIColor(GameTheme.paper)
        let unit = fieldSize.width / 390
        let origin = CGPoint(x: burst.bounds.midX, y: fieldSize.height - burst.bounds.midY)
        let corePath = CGMutablePath()
        corePath.addRect(CGRect(x: -5 * unit, y: -unit, width: 10 * unit, height: 2 * unit))
        corePath.addRect(CGRect(x: -unit, y: -5 * unit, width: 2 * unit, height: 10 * unit))
        let core = SKShapeNode(path: corePath)
        core.name = "home-run-firework-core"
        core.fillColor = cream
        core.strokeColor = .clear
        core.isAntialiased = false
        core.position = origin
        core.alpha = 0
        effects.addChild(core)
        core.run(.sequence([
            .wait(forDuration: delay), .fadeIn(withDuration: 0.04),
            .group([.scale(to: 1.6, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))

        for spoke in 0..<spokes {
            let angle = CGFloat(spoke) * (2 * .pi / CGFloat(spokes)) + CGFloat(burst.index) * 0.21 + angleOffset
            let reach = radius * (spoke.isMultiple(of: 2) ? 1 : 0.68)
            let side = (spoke.isMultiple(of: 2) ? 4 : 3) * unit
            let spark = SKSpriteNode(color: spoke.isMultiple(of: 3) ? cream : color,
                                     size: CGSize(width: side, height: side))
            spark.name = "home-run-firework-spark"
            spark.position = origin
            spark.alpha = 0
            effects.addChild(spark)
            let spread = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach, duration: 0.73)
            spread.timingMode = .easeOut
            spark.run(.sequence([
                .wait(forDuration: delay), .fadeIn(withDuration: 0.04),
                .group([spread, .sequence([.wait(forDuration: 0.23), .fadeOut(withDuration: 0.50)])]),
                .removeFromParent(),
            ]))
        }
    }
}
