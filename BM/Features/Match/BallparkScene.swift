import SpriteKit

@MainActor final class BallparkScene: SKScene {
    private let ball = SKSpriteNode(texture: PixelBaseball.texture)
    private let receivedBall = SKSpriteNode(texture: PixelBaseball.texture)
    private let strikeZone = SKShapeNode()
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
    private struct PitchFlight {
        let start: CGPoint, end: CGPoint
        let started: Double, duration: Double
        let code: String
        let reduced: Bool
        let receipt: Double
        let outcome: String?
        let fieldPlay:MatchDetailedPlay?
        let homeRun:MatchHomeRun?
        let arrival: (@MainActor () -> Void)?
        let completion: (@MainActor () -> Void)?
    }
    private struct ContactFlight {
        let play:MatchDetailedPlay?
        let homeRun:MatchHomeRun?
        let startedAt:Double
        let origin:CGPoint
        let reduced:Bool
        let arrival:(@MainActor () -> Void)?
        let completion:(@MainActor () -> Void)?
    }
    private var contactFlight:ContactFlight?
    private(set) var fieldHandoff:FieldContactHandoff?
    private var pitchFlight: PitchFlight?
    private var pitchReceipt: (deadline:Double, completion:(@MainActor () -> Void)?)?

    override func update(_ currentTime: TimeInterval) {
        let now=ProcessInfo.processInfo.systemUptime
        if let flight=pitchFlight {
            let t=min(1,max(0,(now-flight.started)/flight.duration))
            if flight.reduced {
                ball.position=CGPoint(x:flight.start.x+(flight.end.x-flight.start.x)*t,y:flight.start.y+(flight.end.y-flight.start.y)*t)
                ball.setScale(0.9)
            } else {
                ball.position=MatchBallPath.point(from:flight.start,to:flight.end,size:size,role:.pitcher,hand:hand,code:flight.code,progress:t)
                ball.setScale(1.1-(2.4*t/(1+1.4*t))*0.4)
            }
            if t >= 1 {
                pitchFlight=nil;ball.position=flight.end;pitcherPose(5)
                if let play=flight.fieldPlay {
                    pitchStage = .received
                    startContact(play,origin:CGPoint(x:flight.end.x/size.width,y:1-flight.end.y/size.height),reduced:flight.reduced,arrival:flight.arrival,completion:flight.completion)
                } else if let homeRun=flight.homeRun {
                    pitchStage = .received
                    startContact(nil,homeRun:homeRun,origin:CGPoint(x:flight.end.x/size.width,y:1-flight.end.y/size.height),reduced:flight.reduced,arrival:flight.arrival,completion:flight.completion)
                } else {
                    finishPitch(outcome:flight.outcome,reduced:flight.reduced)
                    pitchReceipt=(now+flight.receipt,flight.completion)
                    flight.arrival?()
                }
            }
        }
        if let contact=contactFlight {
            let elapsed=max(0,now-contact.startedAt)
            let p=contact.homeRun.map {HomeRunPresentation.sourcePoint($0,time:elapsed,origin:contact.origin,size:size)}
                ?? contact.play.map {FieldContactPresentation.sourcePoint($0,time:elapsed,origin:contact.origin,size:size)} ?? contact.origin
            ball.position=point(p.x,p.y)
            ball.setScale(contact.reduced ? 0.8:max(0.5,1-elapsed*0.6))
            if elapsed >= (contact.play.map {FieldContactPresentation.duration($0)} ?? 0.28) {
                contactFlight=nil
                fieldHandoff=FieldContactHandoff(startedAt:contact.startedAt,cutAt:now,sourcePoint:p)
                contact.arrival?();contact.completion?()
            }
        }
        if let receipt=pitchReceipt, now >= receipt.deadline {
            pitchReceipt=nil;receipt.completion?()
        }
    }

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
    func configure(hand: String, kit: Int, role: PlayerRole = .pitcher, appearance: PlayerAppearance? = nil, jerseyNumber: Int = 1, batterSide: OpponentBatterSide = .left) {
        cancelDelivery(); self.hand = hand; self.role = role
        size = CGSize(width: 320, height: role == .batter ? 320 : 320 * 1290 / 1219)
        removeAllChildren()
        guard let image = MatchArt.image(role == .batter ? "batter-view-clean" : "stadium-clean") else { ready = false; return }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest
        let field = SKSpriteNode(texture: texture, size: size); field.position = CGPoint(x: size.width / 2, y: size.height / 2)
        field.xScale = role == .pitcher && batterSide == .right ? -1 : 1
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
        ball.name="baseball";ball.zPosition=8;ball.size=CGSize(width:10,height:10)
        ball.isHidden=true;addChild(ball)
        strikeZone.name="pitchStrikeZone";strikeZone.zPosition=5;strikeZone.strokeColor=UIColor(white:1,alpha:0.8)
        strikeZone.lineWidth=0.65;strikeZone.fillColor = .clear
        let a=arrivalPoint(x:0.2,y:0.2),b=arrivalPoint(x:0.8,y:0.8)
        let path=CGMutablePath();path.addRect(CGRect(x:a.x,y:b.y,width:b.x-a.x,height:a.y-b.y))
        for value in [0.4,0.6] {
            let v=arrivalPoint(x:value,y:value)
            path.move(to:CGPoint(x:v.x,y:a.y));path.addLine(to:CGPoint(x:v.x,y:b.y))
            path.move(to:CGPoint(x:a.x,y:v.y));path.addLine(to:CGPoint(x:b.x,y:v.y))
        }
        strikeZone.path=path;addChild(strikeZone)
        receivedBall.name="receivedBaseball";receivedBall.zPosition=9;receivedBall.size=CGSize(width:10,height:10)
        receivedBall.isHidden=true;addChild(receivedBall);ready=true
    }
    func arrivalPoint(x:Double,y:Double) -> CGPoint {
        role == .batter ? point(0.5+(x-0.5)*0.16,0.68+(y-0.5)*0.22):point(0.54+(x-0.5)*0.22,0.43+(y-0.5)*0.24)
    }
    private func markArrival() {receivedBall.position=destination;receivedBall.isHidden=false}
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
        contactFlight=nil;fieldHandoff=nil
        pitchFlight=nil;pitchReceipt=nil
        removeAllActions(); ball.removeAllActions(); pitcher.removeAllActions(); batter.removeAllActions(); mitt.removeAllActions()
        pitchStage = .idle
        ball.isHidden = true; receivedBall.isHidden=true; ball.setScale(1); pitcherPose(0); batterPose(0)
        if catcherFrames.count >= 2 {
            catcher.texture = catcherFrames[0]; mitt.texture = mittFrames[0]
            mitt.position = point(0.55, 0.475)
        }
    }
    private func handPoint(_ frame: Int) -> CGPoint {
        let anchors = [(0.42, 0.56), (0.38, 0.52), (0.72, 0.37), (0.78, 0.11)]
        let anchor = anchors[frame]
        return point(0.53 + (hand == "left" ? 1 - anchor.0 : anchor.0) * 0.52,
                     0.32 + (frame >= 3 ? 0.65 * 31 / 512 : 0) + anchor.1 * 0.65)
    }
    func preparePitch(phase: Double, reduced: Bool) {
        guard ready, role == .pitcher, pitchStage != .flight else { return }
        if pitchStage == .received { cancelDelivery() }
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
                                       pitchCode: String = "four-seam", outcome: String? = nil, preparedRelease: Bool = false, matchJudgment: Bool = false, fieldPlay:MatchDetailedPlay? = nil, homeRun:MatchHomeRun? = nil, onArrival: (@MainActor () -> Void)? = nil, completion: (@MainActor () -> Void)? = nil) -> Bool {
        guard ready else { return false }
        cancelDelivery()
        // The batting input clock reaches contact at 82%; a pitcher's full trip has no batting phase.
        let flight = (flightDuration ?? 1.1) * (role == .batter ? MatchDelivery.contactPhase:1)
        contactAt = ProcessInfo.processInfo.systemUptime + MatchDelivery.windup + flight
        destination = arrivalPoint(x:x,y:y)
        let release = role == .batter ? point(0.458, 0.237) : handPoint(3)
        ball.position = role == .batter ? release : handPoint(0); ball.isHidden = false
        let duration = DeliveryPresentation.flight(flight, reduced: reduceMotion, role:role)
        func launch() {
            self.pitchStage = .flight; self.pitcherPose(3); self.ball.position = release
            self.pitcher.run(.sequence([.wait(forDuration: duration * 0.25), .run { [weak self] in
                if !reduceMotion { self?.pitcherPose(4) }
            }]))
            if self.role == .pitcher && !["안타", "홈런", "범타"].contains(outcome ?? "") {
                if reduceMotion {self.mitt.position=self.destination}
                else {self.mitt.run(.move(to: self.destination, duration: duration * 0.8))}
            }
            // Movement and receipt share elapsed time; an early first SKAction tick cannot shorten a pitch.
            if self.role == .pitcher {
                self.pitchFlight=PitchFlight(start:release,end:self.destination,started:ProcessInfo.processInfo.systemUptime,
                    duration:duration,code:pitchCode,reduced:reduceMotion,receipt:DeliveryPresentation.receipt(reduced:reduceMotion,match:matchJudgment),outcome:outcome,fieldPlay:fieldPlay,homeRun:homeRun,arrival:onArrival,completion:completion)
                return
            }
            self.ball.run(.sequence([
                self.fly(to: self.destination, duration: duration, code: pitchCode),
                .run { [weak self] in
                    guard let self else { return }
                    self.ball.position = self.destination; self.pitcherPose(5);self.markArrival()
                    if self.role == .pitcher { self.finishPitch(outcome: outcome, reduced: reduceMotion) }
                    onArrival?()
                },
                .wait(forDuration: DeliveryPresentation.receipt(reduced: reduceMotion,match:matchJudgment)), .run { completion?() }
            ]), withKey: "ballDelivery")
        }
        if preparedRelease && role == .pitcher { launch() }
        else {
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
                .wait(forDuration: MatchDelivery.windup * 0.45), .run { launch() }
            ]), withKey: "delivery")
        }
        return true
    }
    private func finishPitch(outcome: String?, reduced: Bool) {
        pitchStage = .received;markArrival()
        let contact = ["안타", "홈런", "범타"].contains(outcome ?? "")
        if contact {
            ball.run(.sequence([.move(to: point(0.3, 0.15), duration: 0.22), .hide()]))
        } else {
            ball.isHidden = true; mitt.position = destination
            catcher.texture = catcherFrames[1]; mitt.texture = mittFrames[1]
            if !reduced { mitt.run(.sequence([.moveBy(x: 0, y: -2, duration: 0.06), .moveBy(x: 0, y: 2, duration: 0.1)])) }
        }
    }
    private func startContact(_ play:MatchDetailedPlay?,homeRun:MatchHomeRun? = nil,origin:CGPoint,reduced:Bool,arrival:(@MainActor () -> Void)?,completion:(@MainActor () -> Void)?) {
        ball.removeAllActions();receivedBall.isHidden=true;ball.isHidden=false
        ball.position=point(origin.x,origin.y)
        contactFlight=ContactFlight(play:play,homeRun:homeRun,startedAt:ProcessInfo.processInfo.systemUptime,origin:origin,reduced:reduced,arrival:arrival,completion:completion)
    }
    func finishBat(action: String, outcome: String, reduced: Bool, matchJudgment: Bool = false, fieldPlay:MatchDetailedPlay? = nil, homeRun:MatchHomeRun? = nil, onArrival: (@MainActor () -> Void)? = nil, completion: @escaping @MainActor () -> Void) {
        let hit = ["안타", "홈런", "범타"].contains(outcome)
        let remaining = max(0, contactAt - ProcessInfo.processInfo.systemUptime)
        if action != "watch" { batterPose(action == "bunt" ? 4 : 1) }
        if fieldPlay != nil || homeRun != nil {
            run(.sequence([.wait(forDuration:remaining),.run { [weak self] in
                guard let self else {return}
                self.batterPose(action == "bunt" ? 5:2)
                self.startContact(fieldPlay,homeRun:homeRun,origin:MatchPresentation.batContact(action:action),reduced:reduced,arrival:onArrival,completion:completion)
                if action == "swing" && !reduced {
                    self.batter.run(.sequence([.wait(forDuration:0.12),.run { [weak self] in self?.batterPose(3) }]))
                }
            }]),withKey:"contact")
            return
        }
        run(.sequence([
            .wait(forDuration: remaining),
            .run { [weak self] in
                guard let self else { return }
                if action != "watch" { self.batterPose(action == "bunt" ? 5 : 2) }; self.markArrival(); onArrival?()
                if hit {
                    self.ball.removeAllActions()
                    let barrel = MatchPresentation.batContact(action: action)
                    self.ball.position = self.point(barrel.x, barrel.y)
                    self.ball.isHidden = false
                    self.ball.run(.sequence([.move(to: self.point(action == "bunt" ? 0.54 : 0.7, outcome == "홈런" ? 0.06 : 0.40), duration: reduced ? 0.1 : 0.26), .hide()]))
                }
            },
            .wait(forDuration: DeliveryPresentation.receipt(reduced: reduced,match:matchJudgment)),
            .run { [weak self] in
                guard let self else { return }; self.removeAction(forKey: "delivery"); self.ball.isHidden = true
                if action == "swing" && !reduced { self.batterPose(3) }; completion()
            }
        ]), withKey: "contact")
    }
}
