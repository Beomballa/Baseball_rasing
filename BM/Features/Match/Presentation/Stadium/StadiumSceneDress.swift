import SpriteKit
import SwiftUI

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
        let seasonTeams = CareerTeamDirectory.domesticFirstIDs + CareerTeamDirectory.japaneseExpandedFirstIDs + CareerTeamDirectory.americanExpandedFirstIDs
        for id in seasonTeams {
            guard let club = ClubIdentity.resolve(name: CareerTeamDirectory.name(id)) else { continue }
            venues[id] = venues[club.id]
        }
        return venues
    }()

    @MainActor static func resolve(_ homeTeamID: String) -> Self? { venuesByHomeID[homeTeamID] }
}

extension StadiumIdentity {
    @MainActor var school: SchoolStadium? { SchoolStadium.resolve(key) }
    @MainActor var pro: ProStadium? { ProStadium.resolve(key) }
    @MainActor var backdrop: StadiumBackdrop? { school?.backdrop ?? pro?.backdrop }
    @MainActor var panelColor: Int { school?.panel ?? pro?.panel ?? theme.panel }
    @MainActor var trimColor: Int { school?.primary ?? pro?.primary ?? theme.trim }
    @MainActor var accentColor: Int { school?.primary ?? pro?.accent ?? theme.accent }
}

/// 구장 장식과 축하 효과만 담당한다. 판정·저장·경기 난수에는 관여하지 않는다.
@MainActor final class StadiumSceneDress: SKNode {
    enum Camera { case batter, pitcher, field }
    enum Celebration: String { case homeRun, doublePlay }
    let stadium: StadiumIdentity
    let fieldSize: CGSize
    private let effects = SKNode()
    private var lamps: [SKSpriteNode] = []
    private var floodlights: [SKNode] = []
    private let homeRunSign = SKNode()
    private(set) var celebration: Celebration?
    private(set) var celebrationCount = 0
    var effectNodeCount: Int { effects.children.count }
    var floodlightCount: Int { floodlights.count }
    var animatedLightCount: Int { (lamps.map { $0 as SKNode } + floodlights).filter { $0.hasActions() }.count }
    init(stadium: StadiumIdentity, size: CGSize, camera: Camera, hasVenueBackdrop: Bool = false) {
        self.stadium = stadium
        fieldSize = size
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
        if camera == .field {
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
                color: panelColor, size: CGSize(width: size.width * 0.52, height: 28))
            let text = SKLabelNode(fontNamed: "Menlo-Bold")
            text.text = "HOME RUN"
            text.fontSize = 18
            text.fontColor = UIColor(GameTheme.gold)
            text.verticalAlignmentMode = .center
            homeRunSign.addChild(plate)
            homeRunSign.addChild(text)
            homeRunSign.position = CGPoint(x: size.width * 0.5, y: size.height * 0.875)
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
    func celebrate(_ kind: Celebration, reduced: Bool) {
        guard celebration == nil else { return }
        celebration = kind
        celebrationCount += 1
        homeRunSign.isHidden = kind != .homeRun
        guard !reduced else {
            reduceEffects()
            return
        }
        let delay = Double(stadium.variation) * 0.08
        // 화면 전체를 번쩍이지 않고 조명 묶음만 천천히 두 번 변화시킨다.
        for (i, bank) in floodlights.enumerated() {
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
            light.isHidden = false
            let at = Double(stadium.theme == .brick ? i : 11 - i) * 0.04 + delay
            light.run(
                .sequence([
                    .wait(forDuration: at), .fadeAlpha(to: 1, duration: 0.18), .wait(forDuration: 0.35),
                    .fadeAlpha(to: 0.65, duration: 0.35),
                ]))
        }
        // 장식 개수와 경로를 고정해 경기 난수를 소비하지 않는다.
        let count = kind == .doublePlay ? 12 : stadium.theme == .harbor ? 40 : 24
        for i in 0..<count {
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
}
