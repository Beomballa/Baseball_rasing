import SpriteKit

@MainActor final class BallparkScene: SKScene {
    private let ball = SKShapeNode(rectOf: CGSize(width: 5, height: 5))
    private let arm = SKNode()
    private var hand = "right"
    private var kit = 0
    private var ready = false

    override init(size: CGSize) { super.init(size: size); scaleMode = .aspectFit; backgroundColor = UIColor(red: 0.13, green: 0.42, blue: 0.28, alpha: 1) }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not used") }

    func configure(hand: String, kit: Int) {
        self.hand = hand; self.kit = kit
        removeAllActions(); removeAllChildren(); buildField(); ready = true
    }

    private func buildField() {
        for row in 0..<10 {
            let stripe = SKSpriteNode(color: row.isMultiple(of: 2) ? UIColor(red: 0.16, green: 0.47, blue: 0.31, alpha: 1) : backgroundColor,
                                      size: CGSize(width: 320, height: 40))
            stripe.position = CGPoint(x: 160, y: CGFloat(row) * 40 + 20); addChild(stripe)
        }
        let dirt = CGMutablePath(); dirt.move(to: CGPoint(x: 160, y: 52))
        dirt.addLine(to: CGPoint(x: 260, y: 151)); dirt.addLine(to: CGPoint(x: 160, y: 250))
        dirt.addLine(to: CGPoint(x: 60, y: 151)); dirt.closeSubpath()
        let diamond = SKShapeNode(path: dirt); diamond.fillColor = UIColor(red: 0.67, green: 0.48, blue: 0.29, alpha: 1)
        diamond.strokeColor = .white; diamond.lineWidth = 2; addChild(diamond)
        let inner = SKShapeNode(path: dirt); inner.setScale(0.68)
        inner.position = CGPoint(x: 160 * 0.32, y: 151 * 0.32)
        inner.fillColor = backgroundColor; inner.strokeColor = .clear; addChild(inner)
        for p in [CGPoint(x: 160, y: 56), CGPoint(x: 254, y: 151), CGPoint(x: 160, y: 244), CGPoint(x: 66, y: 151)] {
            let base = SKSpriteNode(color: .white, size: CGSize(width: 8, height: 8)); base.position = p; addChild(base)
        }
        let board = SKSpriteNode(color: UIColor(red: 0.08, green: 0.16, blue: 0.25, alpha: 1), size: CGSize(width: 288, height: 36))
        board.position = CGPoint(x: 160, y: 370); addChild(board)
        let label = SKLabelNode(fontNamed: "Menlo-Bold"); label.text = "BM  |  PRACTICE  |  B 0  S 0  O 0"
        label.name = "scoreboard"; label.fontSize = 10; label.position = CGPoint(x: 160, y: 366); addChild(label)
        for point in [CGPoint(x: 70, y: 305), CGPoint(x: 160, y: 325), CGPoint(x: 250, y: 305),
                      CGPoint(x: 230, y: 164), CGPoint(x: 193, y: 225), CGPoint(x: 119, y: 225), CGPoint(x: 90, y: 164)] {
            addChild(pixelFielder(at: point))
        }
        addChild(pixelFielder(at: CGPoint(x: 160, y: 155)))
        addChild(pixelFielder(at: CGPoint(x: 160, y: 39)))
        arm.removeAllChildren(); arm.position = CGPoint(x: hand == "left" ? 152 : 168, y: 160)
        let sleeve = SKSpriteNode(color: .init(red: 0.93, green: 0.75, blue: 0.56, alpha: 1), size: CGSize(width: 4, height: 12))
        sleeve.position = CGPoint(x: 0, y: 5); arm.addChild(sleeve); arm.zPosition = 5; addChild(arm)
        ball.removeAllActions(); ball.fillColor = .white; ball.strokeColor = .clear; ball.zPosition = 6
        ball.position = CGPoint(x: arm.position.x, y: 170); addChild(ball)
    }

    private func pixelFielder(at position: CGPoint) -> SKNode {
        let node = SKNode(); node.position = position; node.zPosition = 3
        let color = PlayerAppearance.kitColors[kit]
        let shirt = UIColor(red: CGFloat((color >> 16) & 255)/255, green: CGFloat((color >> 8) & 255)/255, blue: CGFloat(color & 255)/255, alpha: 1)
        for (x, y, w, h, c) in [(0.0, 0.0, 10.0, 10.0, shirt), (0, 9, 8, 6, UIColor(red: 0.93, green: 0.75, blue: 0.56, alpha: 1)),
                                  (-3, -8, 4, 6, UIColor.white), (3, -8, 4, 6, UIColor.white)] {
            let part = SKSpriteNode(color: c, size: CGSize(width: w, height: h)); part.position = CGPoint(x: x, y: y); node.addChild(part)
        }
        return node
    }

    func updateScoreboard(_ text: String) {
        (childNode(withName: "scoreboard") as? SKLabelNode)?.text = text
    }

    func cancelDelivery() {
        removeAction(forKey: "delivery"); ball.removeAllActions(); arm.removeAllActions()
        arm.zRotation = 0
    }

    @discardableResult func demonstrate(reduceMotion: Bool, flightDuration: Double? = nil, x: Double = 0.5, y: Double = 0.5) -> Bool {
        guard ready, action(forKey: "delivery") == nil else { return false }
        ball.setScale(flightDuration == nil ? 1 : 1.6)
        arm.zRotation = 0; ball.position = CGPoint(x: arm.position.x, y: 170)
        if reduceMotion && flightDuration == nil { ball.position = CGPoint(x: 160, y: 49); return true }
        let direction: CGFloat = hand == "left" ? -1 : 1
        run(.sequence([
            .run { [weak self] in if !reduceMotion { self?.arm.run(.rotate(toAngle: direction * 1.1, duration: 0.3)) } },
            .wait(forDuration: flightDuration == nil ? 0.3 : MatchDelivery.windup),
            .run { [weak self] in
                guard let self else { return }
                if !reduceMotion { self.arm.run(.rotate(toAngle: -direction * 0.7, duration: 0.16)) }
                self.ball.position = CGPoint(x: self.arm.position.x, y: 168)
                let target = flightDuration == nil ? CGPoint(x: 160, y: 49)
                    : CGPoint(x: 160 + (x - 0.5) * 102.4, y: 80 - (y - 0.5) * 80)
                self.ball.run(.move(to: target,
                                     duration: flightDuration.map { $0 * MatchDelivery.contactPhase } ?? 0.52))
            },
            .wait(forDuration: flightDuration ?? 0.7),
            .run { [weak self] in self?.arm.zRotation = 0 }
        ]), withKey: "delivery")
        return true
    }
}
