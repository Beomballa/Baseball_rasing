import SpriteKit
import SwiftUI

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
    init(stadium: StadiumIdentity, size: CGSize, camera: Camera) {
        self.stadium = stadium
        fieldSize = size
        super.init()
        name = "stadiumDress-" + stadium.theme.title
        let y: CGFloat = camera == .pitcher ? 0.25 : camera == .batter ? 0.166 : 0.15
        let positions: [CGFloat] = camera == .field ? [0.13, 0.87] : [0.16, 0.84]
        for (i, x) in positions.enumerated() {
            let sponsor = stadium.sponsors[i]
            let w = size.width * (camera == .field ? 0.20 : 0.22)
            let h = max(12, size.width * 0.052)
            let panel = SKShapeNode(rectOf: CGSize(width: w, height: h))
            panel.fillColor = UIColor(Color(hex: stadium.theme.panel))
            panel.strokeColor = UIColor(Color(hex: stadium.theme.trim))
            panel.lineWidth = 1
            panel.position = CGPoint(x: size.width * x, y: size.height * (1 - y))
            addChild(panel)
            let mark = SKLabelNode(fontNamed: "Menlo-Bold")
            mark.text = sponsor.mark
            mark.fontSize = h * 0.60
            mark.fontColor = UIColor(Color(hex: stadium.theme.accent))
            mark.verticalAlignmentMode = .center
            mark.position.x = -w * 0.36
            panel.addChild(mark)
            let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
            label.text = sponsor.name
            label.fontSize = h * 0.43
            label.fontColor = UIColor(GameTheme.paper)
            label.verticalAlignmentMode = .center
            label.position.x = w * 0.12
            panel.addChild(label)
        }
        for i in 0..<12 {
            let light = SKSpriteNode(
                color: UIColor(Color(hex: stadium.theme.trim)), size: CGSize(width: size.width * 0.022, height: 2))
            light.position = CGPoint(
                x: size.width * (0.12 + Double(i) * 0.069), y: size.height * (1 - (camera == .field ? 0.19 : 0.205)))
            light.alpha = 0.48
            lamps.append(light)
            addChild(light)
        }
        if camera == .field {
            for i in 0..<4 {
                let bank = SKNode()
                bank.position = CGPoint(
                    x: size.width * (i.isMultiple(of: 2) ? 0.08 : 0.92), y: size.height * (i < 2 ? 0.95 : 0.76))
                let frame = SKSpriteNode(
                    color: UIColor(Color(hex: stadium.theme.panel)), size: CGSize(width: 32, height: 17))
                bank.addChild(frame)
                for cell in 0..<8 {
                    let bulb = SKSpriteNode(color: UIColor(GameTheme.paper), size: CGSize(width: 5, height: 5))
                    bulb.position = CGPoint(x: CGFloat(cell % 4) * 7 - 10.5, y: CGFloat(cell / 4) * 7 - 3.5)
                    bank.addChild(bulb)
                }
                bank.alpha = 0.55
                floodlights.append(bank)
                addChild(bank)
            }
            let plate = SKSpriteNode(
                color: UIColor(Color(hex: stadium.theme.panel)), size: CGSize(width: size.width * 0.52, height: 28))
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
            let at = Double(stadium.theme == .brick ? i : 11 - i) * 0.04 + delay
            light.run(
                .sequence([
                    .wait(forDuration: at), .fadeAlpha(to: 1, duration: 0.18), .wait(forDuration: 0.35),
                    .fadeAlpha(to: 0.65, duration: 0.35),
                ]))
        }
        // 장식 개수와 경로를 고정해 경기 RNG를 소비하지 않는다.
        let count = kind == .doublePlay ? 12 : stadium.theme == .harbor ? 40 : 24
        for i in 0..<count {
            let node = SKSpriteNode(
                color: i.isMultiple(of: 3) ? UIColor(GameTheme.gold) : UIColor(Color(hex: stadium.theme.accent)),
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
