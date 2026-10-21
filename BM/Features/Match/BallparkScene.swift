import SpriteKit

@MainActor final class BallparkScene: SKScene {
    private let ball = SKShapeNode(rectOf: CGSize(width: 5, height: 5))
    private let pitcher = SKSpriteNode()
    private let batter = SKSpriteNode()
    private let catcher = SKSpriteNode()
    private let mitt = SKSpriteNode()
    private var pitcherFrames: [SKTexture] = []
    private var batterFrames: [SKTexture] = []
    private var catcherFrames: [SKTexture] = []
    private var mittFrames: [SKTexture] = []
    private var hand = "right"
    private var role = PlayerRole.pitcher
    private var ready = false
    enum PitchStage { case idle, preparing, flight, received }
    private(set) var pitchStage = PitchStage.idle
    private var contactAt = 0.0
    private var destination = CGPoint.zero

    override init(size: CGSize) {
        super.init(size: size); scaleMode = .aspectFit; backgroundColor = UIColor(red: 0.09, green: 0.20, blue: 0.29, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not used") }

    private func textures(_ name: String, columns: Int, rows: Int) -> [SKTexture] {
        guard let image = MatchArt.image(name) else { return [] }
        let sheet = SKTexture(image: image)
        return (0..<(columns * rows)).map { i in
            let texture = SKTexture(rect: CGRect(x: Double(i % columns) / Double(columns), y: 1 - Double(i / columns + 1) / Double(rows),
                                                width: 1 / Double(columns), height: 1 / Double(rows)), in: sheet)
            texture.filteringMode = .nearest
            return texture
        }
    }
    func configure(hand: String, kit: Int, role: PlayerRole = .pitcher, appearance: PlayerAppearance? = nil, jerseyNumber: Int = 1) {
        cancelDelivery(); self.hand = hand; self.role = role
        size = CGSize(width: 320, height: role == .batter ? 320 : 320 * 1290 / 1219)
        removeAllChildren()
        guard let image = MatchArt.image(role == .batter ? "batter-view-clean" : "stadium-clean") else { ready = false; return }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest
        let field = SKSpriteNode(texture: texture, size: size); field.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(field)
        let style = appearance ?? PlayerAppearance(kit: kit)
        pitcherFrames = role == .pitcher ? PlayerMotionArt.textures(role: role, appearance: style, number: jerseyNumber, hand: hand) : textures("pitcher-delivery-v2", columns: 3, rows: 2)
        batterFrames = role == .batter ? PlayerMotionArt.textures(role: role, appearance: style, number: jerseyNumber, hand: hand) : textures("batter-actions", columns: 3, rows: 2)
        catcherFrames = textures("catcher-parts", columns: 2, rows: 2)
        mittFrames = Array(catcherFrames.suffix(2))
        guard pitcherFrames.count == 6, batterFrames.count == 6, catcherFrames.count == 4 else { ready = false; return }
        if role == .pitcher {
            pitcher.zPosition = 4; pitcher.xScale = hand == "left" ? -1 : 1; addChild(pitcher); pitcherPose(0)
            catcher.texture = catcherFrames[0]; catcher.size = CGSize(width: size.width * 0.22, height: size.height * 0.22)
            catcher.position = point(0.50, 0.41); catcher.zPosition = 2; addChild(catcher)
            mitt.texture = mittFrames[0]; mitt.size = CGSize(width: size.width * 0.09, height: size.height * 0.09)
            mitt.position = point(0.55, 0.475); mitt.zPosition = 6; addChild(mitt)
        } else {
            batter.zPosition = 4; addChild(batter); batterPose(0)
        }
        ball.fillColor = .init(red: 1, green: 0.97, blue: 0.80, alpha: 1); ball.strokeColor = .clear; ball.zPosition = 8
        ball.isHidden = true; addChild(ball); ready = true
    }
    private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: (1 - y) * size.height) }
    private func pitcherPose(_ frame: Int) {
        guard pitcherFrames.indices.contains(frame) else { return }
        pitcher.texture = pitcherFrames[frame]
        pitcher.size = CGSize(width: size.width * 0.52, height: size.height * 0.65)
        pitcher.position = point(0.79, 0.32 + (frame >= 3 ? 0.65 * 31 / 512 : 0) + 0.325)
    }
    private func batterPose(_ frame: Int) {
        guard batterFrames.indices.contains(frame) else { return }
        batter.texture = batterFrames[frame]
        let feet = [496.0, 494, 503, 469, 471, 471]
        batter.size = CGSize(width: size.width * 0.62, height: size.height * 0.61)
        batter.position = point(0.305, 0.34 + 0.61 * (1 - feet[frame] / 512) + 0.305)
    }
    func cancelDelivery() {
        removeAllActions(); ball.removeAllActions(); pitcher.removeAllActions(); batter.removeAllActions(); mitt.removeAllActions()
        pitchStage = .idle
        ball.isHidden = true; pitcherPose(0); batterPose(0)
        if catcherFrames.count >= 2 { catcher.texture = catcherFrames[0]; mitt.texture = mittFrames[0] }
    }
    private func handPoint(_ frame: Int) -> CGPoint {
        let anchors = [(0.42, 0.56), (0.38, 0.52), (0.72, 0.37), (0.78, 0.11)]
        let anchor = anchors[frame]
        return point(0.53 + (hand == "left" ? 1 - anchor.0 : anchor.0) * 0.52,
                     0.32 + (frame >= 3 ? 0.65 * 31 / 512 : 0) + anchor.1 * 0.65)
    }
    func preparePitch(phase: Double, reduced: Bool) {
        guard ready, role == .pitcher, pitchStage != .flight else { return }
        pitchStage = .preparing
        let frame = reduced ? 0 : phase < 0.22 ? 0 : phase < 0.48 ? 1 : 2
        pitcherPose(frame); ball.position = handPoint(frame); ball.isHidden = false
    }
    private func fly(to end: CGPoint, duration: Double, code: String) -> SKAction {
        let start = ball.position
        return .customAction(withDuration: duration) { [weak self] node, elapsed in
            guard let self else { return }
            let t = min(1, Double(elapsed) / duration), depth = self.role == .batter ? t / (2.4 - 1.4 * t) : 2.4 * t / (1 + 1.4 * t)
            node.position = MatchBallPath.point(from: start, to: end, size: self.size, role: self.role,
                                               hand: self.hand, code: code, progress: t)
            node.setScale(self.role == .batter ? 0.35 + depth * 0.9 : 1.1 - depth * 0.65)
        }
    }
    @discardableResult func demonstrate(reduceMotion: Bool, flightDuration: Double? = nil, x: Double = 0.5, y: Double = 0.5,
                                       pitchCode: String = "four-seam", outcome: String? = nil, preparedRelease: Bool = false, completion: (@MainActor () -> Void)? = nil) -> Bool {
        guard ready else { return false }
        cancelDelivery()
        let flight = (flightDuration ?? 1.1) * MatchDelivery.contactPhase
        contactAt = ProcessInfo.processInfo.systemUptime + MatchDelivery.windup + flight
        destination = role == .batter ? point(0.5 + (x - 0.5) * 0.16, 0.68 + (y - 0.5) * 0.22)
            : point(0.54 + (x - 0.5) * 0.22, 0.43 + (y - 0.5) * 0.24)
        let release = role == .batter ? point(0.458, 0.237) : handPoint(3)
        ball.position = role == .batter ? release : handPoint(0); ball.isHidden = false
        if preparedRelease && role == .pitcher {
            pitchStage = .flight; pitcherPose(3); ball.position = release
            let duration = reduceMotion ? 0.08 : flight
            ball.run(fly(to: destination, duration: duration, code: pitchCode))
            run(.sequence([
                .wait(forDuration: duration * 0.25), .run { [weak self] in if !reduceMotion { self?.pitcherPose(4) } },
                .wait(forDuration: duration * 0.75), .run { [weak self] in
                    self?.pitcherPose(5); self?.finishPitch(outcome: outcome, reduced: reduceMotion)
                },
                .wait(forDuration: reduceMotion ? 0.04 : 0.24), .run { completion?() }
            ]), withKey: "delivery")
            return true
        }
        run(.sequence([
            .run { [weak self] in
                guard let self else { return }
                if !reduceMotion { self.pitcherPose(1) }
                if self.role == .pitcher { self.ball.position = self.handPoint(reduceMotion ? 0 : 1) }
            },
            .wait(forDuration: MatchDelivery.windup * 0.55),
            .run { [weak self] in
                guard let self else { return }; if !reduceMotion { self.pitcherPose(2) }
                if self.role == .pitcher { self.ball.position = self.handPoint(2) }
            },
            .wait(forDuration: MatchDelivery.windup * 0.45),
            .run { [weak self] in
                guard let self else { return }; self.pitchStage = .flight; self.pitcherPose(3); self.ball.position = release
                self.ball.run(self.fly(to: self.destination, duration: flight, code: pitchCode))
            },
            .wait(forDuration: flight * 0.25), .run { [weak self] in if !reduceMotion { self?.pitcherPose(4) } },
            .wait(forDuration: flight * 0.75),
            .run { [weak self] in
                guard let self else { return }; self.pitcherPose(5)
                if self.role == .pitcher { self.finishPitch(outcome: outcome, reduced: reduceMotion) }
            },
            .wait(forDuration: 0.24), .run { completion?() }
        ]), withKey: "delivery")
        return true
    }
    private func finishPitch(outcome: String?, reduced: Bool) {
        pitchStage = .received
        let contact = ["안타", "홈런", "범타"].contains(outcome ?? "")
        if contact {
            ball.run(.sequence([.move(to: point(0.3, 0.15), duration: 0.22), .hide()]))
        } else {
            ball.isHidden = true; mitt.position = destination
            catcher.texture = catcherFrames[1]; mitt.texture = mittFrames[1]
            if !reduced { mitt.run(.sequence([.moveBy(x: 0, y: -2, duration: 0.06), .moveBy(x: 0, y: 2, duration: 0.1)])) }
        }
    }
    func finishBat(action: String, outcome: String, reduced: Bool, completion: @escaping @MainActor () -> Void) {
        let hit = ["안타", "홈런", "범타"].contains(outcome)
        let remaining = max(0, contactAt - ProcessInfo.processInfo.systemUptime)
        if action != "watch" { batterPose(action == "bunt" ? 4 : 1) }
        run(.sequence([
            .wait(forDuration: hit ? remaining : 0),
            .run { [weak self] in
                guard let self else { return }
                if action != "watch" { self.batterPose(action == "bunt" ? 5 : 2) }
                if hit {
                    self.ball.removeAllActions()
                    let barrel = MatchPresentation.batContact(action: action)
                    self.ball.position = self.point(barrel.x, barrel.y)
                    self.ball.isHidden = false
                    self.ball.run(.sequence([.move(to: self.point(action == "bunt" ? 0.54 : 0.7, outcome == "홈런" ? 0.06 : 0.40), duration: reduced ? 0.1 : 0.26), .hide()]))
                }
            },
            .wait(forDuration: max(remaining, 0.26)),
            .run { [weak self] in
                guard let self else { return }; self.removeAction(forKey: "delivery"); self.ball.isHidden = true
                if action == "swing" && !reduced { self.batterPose(3) }; completion()
            }
        ]), withKey: "contact")
    }
}
