import SpriteKit
import SwiftUI

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
    private var batterSide = OpponentBatterSide.left
    private var lastPitcherFrame = -1
    private(set) var stadium = StadiumIdentity.legacy
    private var dress: StadiumSceneDress?
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
    private struct BatterFlight {
        let timeline: MatchInputTimeline
        let start: CGPoint, end: CGPoint
        let code: String
        let reduced: Bool
        let receipt: Double
        let arrival: (@MainActor () -> Void)?
        let completion: (@MainActor () -> Void)?
    }
    private struct BatFinish {
        let at: Double
        let action: String, outcome: String
        let reduced: Bool
        let receipt: Double
        let play: MatchDetailedPlay?
        let homeRun: MatchHomeRun?
        let arrival: (@MainActor () -> Void)?
        let completion: @MainActor () -> Void
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
    private var batterFlight: BatterFlight?
    private var batFinish: BatFinish?
    private var pitchReceipt: (deadline:Double, completion:(@MainActor () -> Void)?)?

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        let measuredAt=MatchRenderMetrics.begin()
        defer {MatchRenderMetrics.end("spriteUpdate",started:measuredAt)}
        #endif
        advanceDelivery(at: ProcessInfo.processInfo.systemUptime)
    }

    func advanceDelivery(at now: Double) {
        if let flight=batterFlight {
            let timeline=flight.timeline
            if now < timeline.releaseAt {
                pitchStage = .preparing; ball.isHidden = true
                let windupPhase=(now-timeline.startedAt)/max(0.001,timeline.windup)
                pitcherPose(windupPhase < 0.28 ? 1 : windupPhase < 0.65 ? 2 : 3)
            } else {
                let t=min(1,max(0,(now-timeline.releaseAt)/(timeline.duration*MatchDelivery.contactPhase)))
                let depth=t/(2.4-1.4*t)
                pitchStage = .flight; ball.isHidden = false
                ball.position=MatchBallPath.point(from:flight.start,to:flight.end,size:size,role:.batter,hand:hand,code:flight.code,progress:t)
                ball.setScale(0.35+depth*0.9)
                pitcherPose(t < 0.16 ? 4 : t < 0.45 ? 5 : 6)
                if now >= timeline.contactAt {
                    batterFlight=nil;pitchStage = .received;ball.position=flight.end;ball.isHidden=true;pitcherPose(7);markArrival()
                    if flight.completion != nil { pitchReceipt=(now+flight.receipt,flight.completion) }
                    flight.arrival?()
                }
            }
        }
        if let flight=pitchFlight {
            let t=min(1,max(0,(now-flight.started)/flight.duration))
            pitcherPose(t < 0.25 ? 3 : t < 0.75 ? 4 : 5)
            ball.position=MatchBallPath.point(from:flight.start,to:flight.end,size:size,role:.pitcher,hand:hand,code:flight.code,progress:t)
            ball.setScale(1.1-(2.4*t/(1+1.4*t))*0.4)
            if t >= 1 {
                pitchFlight=nil;ball.position=flight.end;pitcherPose(5)
                if flight.fieldPlay != nil || flight.homeRun != nil || flight.outcome == "헛스윙" {
                    batterPose(2)
                    batter.run(.sequence([.wait(forDuration:0.12),.run { [weak self] in self?.batterPose(3) }]))
                }
                if let play=flight.fieldPlay {
                    pitchStage = .received
                    startContact(play,origin:CGPoint(x:flight.end.x/size.width,y:1-flight.end.y/size.height),reduced:flight.reduced,arrival:flight.arrival,completion:flight.completion,startedAt:now)
                } else if let homeRun=flight.homeRun {
                    pitchStage = .received
                    startContact(nil,homeRun:homeRun,origin:CGPoint(x:flight.end.x/size.width,y:1-flight.end.y/size.height),reduced:flight.reduced,arrival:flight.arrival,completion:flight.completion,startedAt:now)
                } else {
                    finishPitch(outcome:flight.outcome,reduced:flight.reduced)
                    pitchReceipt=(now+flight.receipt,flight.completion)
                    flight.arrival?()
                }
            }
        }
        if let finish=batFinish, now >= finish.at {
            batFinish=nil;batterFlight=nil
            if finish.action != "watch" { batterPose(finish.action == "bunt" ? 5:2) }
            if finish.play != nil || finish.homeRun != nil {
                startContact(finish.play,homeRun:finish.homeRun,origin:MatchPresentation.batContact(action:finish.action),
                             reduced:finish.reduced,arrival:finish.arrival,completion:finish.completion,startedAt:now)
                if finish.action == "swing" && !finish.reduced {
                    batter.run(.sequence([.wait(forDuration:0.12),.run { [weak self] in self?.batterPose(3) }]))
                }
            } else {
                pitchStage = .received;markArrival()
                if ["안타", "홈런", "범타"].contains(finish.outcome) {
                    ball.removeAllActions();receivedBall.isHidden=true
                    let barrel=MatchPresentation.batContact(action:finish.action)
                    ball.position=point(barrel.x,barrel.y);ball.isHidden=false
                    ball.run(.sequence([.move(to:point(finish.action == "bunt" ? 0.54:0.7,finish.outcome == "홈런" ? 0.06:0.40),duration:finish.reduced ? 0.1:0.26),.hide()]))
                } else { ball.isHidden=true }
                pitchReceipt=(now+finish.receipt,{ [weak self] in
                    guard let self else { return }
                    self.ball.isHidden=true
                    if finish.action == "swing" && !finish.reduced { self.batterPose(3) }
                    finish.completion()
                })
                finish.arrival?()
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
        cancelDelivery(); self.hand = hand; self.role = role; self.batterSide = batterSide; lastPitcherFrame = -1
        size = CGSize(width: 320, height: role == .batter ? 320 : 320 * 1290 / 1219)
        removeAllChildren()
        guard let image = MatchArt.image(role == .batter ? "batter-field-v52" : "pitcher-field-v52") else { ready = false; return }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest
        let field = SKSpriteNode(texture: texture, size: size); field.position = CGPoint(x: size.width / 2, y: size.height / 2)
        field.name = "fixedStadiumBackground"
        // Reverse the rear camera with a left-handed pitcher, keeping the rubber under the planted foot.
        field.xScale = role == .pitcher && hand == "left" ? -1 : 1
        addChild(field)
        let style = appearance ?? PlayerAppearance(kit: kit)
        if role == .batter {addBackgroundFielders(ownKit:PlayerAppearance.kitColors[style.kit])}
        pitcherFrames = role == .pitcher ? PlayerMotionArt.textures(role: role, appearance: style, number: jerseyNumber, hand: hand) : OpponentMotionArt.textures("opponent-pitcher-v52",columns:4,rows:2,ownKit:PlayerAppearance.kitColors[style.kit])
        batterFrames = role == .batter ? PlayerMotionArt.textures(role: role, appearance: style, number: jerseyNumber, hand: hand) : OpponentMotionArt.textures("opponent-batter-v52",columns:3,rows:2,ownKit:PlayerAppearance.kitColors[style.kit])
        catcherFrames = OpponentMotionArt.textures("catcher-parts",columns:2,rows:2,ownKit:PlayerAppearance.kitColors[style.kit],opponent:false)
        mittFrames = Array(catcherFrames.suffix(2))
        guard pitcherFrames.count == (role == .pitcher ? 6 : 8), batterFrames.count == 6, catcherFrames.count == 4 else { ready = false; return }
        pitcher.name = "animatedPitcher";pitcher.zPosition = 4;pitcher.xScale = hand == "left" ? -1 : 1;addChild(pitcher);pitcherPose(0)
        batter.name = "animatedBatter";batter.zPosition = 3;batter.isHidden = false;addChild(batter);batterPose(0)
        if role == .pitcher {
            catcher.texture = catcherFrames[0]; catcher.size = CGSize(width: size.width * 0.22, height: size.height * 0.22)
            catcher.position = point(0.50, 0.41); catcher.zPosition = 2; addChild(catcher)
            mitt.texture = mittFrames[0]; mitt.size = CGSize(width: size.width * 0.09, height: size.height * 0.09)
            mitt.position = point(hand == "left" ? 0.45 : 0.55, 0.475); mitt.zPosition = 6; addChild(mitt)
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
        setStadium(stadium)
    }
    func usePracticeSetting() {
        guard let field = childNode(withName: "fixedStadiumBackground") as? SKSpriteNode else { return }
        let image = role == .batter ? MatchArt.image("batting-practice-v75") : TrainingEnvironmentArt.image(.bullpen)
        if let image {
            let texture = SKTexture(image: image); texture.filteringMode = .nearest
            field.texture = texture
        }
        dress?.removeFromParent(); dress = nil
        for i in 0..<3 { childNode(withName: "backgroundFielder-\(i)")?.removeFromParent() }
        if role == .pitcher { batter.isHidden = true }
    }
    func setStadium(_ value: StadiumIdentity) {
        stadium = value; dress?.removeFromParent()
        guard ready else { return }
        let next = StadiumSceneDress(stadium: value, size: size, camera: role == .pitcher ? .pitcher : .batter)
        next.zPosition = 1; addChild(next); dress = next
    }
    private func addBackgroundFielders(ownKit:Int) {
        let motion=FieldSpriteMotion(facing:.south,stage:.ready)
        guard let sample=FieldRasterArt.samples(motion,kind:"fielder",left:false).first,
              let image=FieldRasterArt.image(sample,kit:FieldReplayPresentation.opponentKit(ownKit),skin:0xefbe91,hair:0x263b48,number:0,back:false) else {return}
        let texture=SKTexture(image:image);texture.filteringMode = .nearest
        for (index,placement) in [(0.105,0.295,0.075),(0.637,0.245,0.045),(0.925,0.295,0.075)].enumerated() {
            let height=size.width*placement.2,frame=sample.frame
            let node=SKSpriteNode(texture:texture);node.name="backgroundFielder-\(index)"
            node.anchorPoint=CGPoint(x:frame.pivot[0]/frame.rect[2],y:1-frame.pivot[1]/frame.rect[3])
            node.size=CGSize(width:height*frame.rect[2]/frame.rect[3],height:height)
            node.position=point(placement.0,placement.1);node.zPosition=2;addChild(node)
        }
    }
    func arrivalPoint(x:Double,y:Double) -> CGPoint {
        role == .batter ? point(0.5+(x-0.5)*0.16,0.68+(y-0.5)*0.22):point((hand == "left" ? 0.46 : 0.54)+(x-0.5)*0.22,0.43+(y-0.5)*0.24)
    }
    private func markArrival() {receivedBall.position=destination;receivedBall.isHidden=false}
    private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: (1 - y) * size.height) }
    private func pitcherPose(_ frame: Int) {
        guard pitcherFrames.indices.contains(frame) else { return }
        guard frame != lastPitcherFrame else { return };lastPitcherFrame = frame
        pitcher.texture = pitcherFrames[frame]
        let pose = PitcherPresentationPose(role: role, frame: frame, hand: hand)
        let source = PitcherPresentationPose(role: role, frame: frame, hand: "right")
        pitcher.size = CGSize(width: size.width * pose.width, height: size.width * pose.width)
        // xScale mirrors around the source pivot; mirroring the anchor again would move the planted foot off the rubber.
        pitcher.anchorPoint = CGPoint(x: source.pivot.x,y: 1-source.pivot.y)
        pitcher.position = point(pose.foot.x,pose.foot.y)
    }
    private func batterPose(_ frame: Int) {
        guard batterFrames.indices.contains(frame) else { return }
        batter.texture = batterFrames[frame]
        if role == .pitcher {
            batter.size = CGSize(width: size.width*0.30,height: size.width*0.30)
            batter.anchorPoint = CGPoint(x: 0.5,y: 0.04)
            batter.xScale = batterSide == .left ? 1 : -1
            batter.position = point(batterSide == .left ? 0.32 : 0.70,0.565)
            return
        }
        batter.xScale = 1;batter.anchorPoint = CGPoint(x:0.5,y:0.5)
        let feet = [496.0, 494, 503, 469, 471, 471]
        batter.size = CGSize(width: size.width * 0.62, height: size.height * 0.61)
        batter.position = point(0.305, 0.34 + 0.61 * (1 - feet[frame] / 512) + 0.305)
    }
    func cancelDelivery() {
        contactFlight=nil;fieldHandoff=nil
        pitchFlight=nil;batterFlight=nil;batFinish=nil;pitchReceipt=nil;contactAt=0
        removeAllActions(); ball.removeAllActions(); pitcher.removeAllActions(); batter.removeAllActions(); mitt.removeAllActions();lastPitcherFrame = -1
        pitchStage = .idle
        ball.isHidden = true; receivedBall.isHidden=true; ball.setScale(1); pitcherPose(0); batterPose(0)
        if catcherFrames.count >= 2 {
            catcher.texture = catcherFrames[0]; mitt.texture = mittFrames[0]
            mitt.position = point(hand == "left" ? 0.45 : 0.55, 0.475)
        }
    }
    private func handPoint(_ frame: Int) -> CGPoint {
        let p = PitcherPresentationPose(role: role,frame: frame,hand: hand)
        return point(p.foot.x + p.width*(p.hand.x-p.pivot.x),p.foot.y + p.width*size.width/size.height*(p.hand.y-p.pivot.y))
    }
    func preparePitch(phase: Double, reduced: Bool) {
        guard ready, role == .pitcher, pitchStage != .flight else { return }
        if pitchStage == .received { cancelDelivery() }
        pitchStage = .preparing
        let frame = phase < 0.22 ? 0 : phase < 0.48 ? 1 : 2
        pitcherPose(frame); ball.position = handPoint(frame); ball.isHidden = false
    }
    @discardableResult func demonstrate(reduceMotion: Bool, flightDuration: Double? = nil, x: Double = 0.5, y: Double = 0.5,
                                       pitchCode: String = "four-seam", outcome: String? = nil, preparedRelease: Bool = false, matchJudgment: Bool = false, fieldPlay:MatchDetailedPlay? = nil, homeRun:MatchHomeRun? = nil, onArrival: (@MainActor () -> Void)? = nil, completion: (@MainActor () -> Void)? = nil, inputTimeline: MatchInputTimeline? = nil) -> Bool {
        guard ready else { return false }
        cancelDelivery()
        destination = arrivalPoint(x:x,y:y)
        let release = handPoint(role == .batter ? 4 : 3)
        if role == .batter {
            let timeline=inputTimeline ?? MatchInputTimeline(windup:MatchDelivery.windup,duration:(flightDuration ?? 1.1)/MatchDelivery.contactPhase)
            contactAt=timeline.contactAt
            pitchStage = .preparing;ball.position=release;ball.isHidden=true
            batterFlight=BatterFlight(timeline:timeline,start:release,end:destination,code:pitchCode,reduced:reduceMotion,
                receipt:DeliveryPresentation.receipt(reduced:reduceMotion,match:matchJudgment),arrival:onArrival,completion:completion)
            return true
        }
        let duration=DeliveryPresentation.flight(flightDuration ?? 1.1,reduced:reduceMotion,role:role)
        contactAt=ProcessInfo.processInfo.systemUptime+MatchDelivery.windup+duration
        ball.position=handPoint(0);ball.isHidden=false
        func launch() {
            self.pitchStage = .flight; self.pitcherPose(3); self.ball.position = release
            if self.role == .pitcher && !["안타", "홈런", "범타"].contains(outcome ?? "") {
                if reduceMotion {self.mitt.position=self.destination}
                else {self.mitt.run(.move(to: self.destination, duration: duration * 0.8))}
            }
            // Movement and receipt share elapsed time; an early first SKAction tick cannot shorten a pitch.
            self.pitchFlight=PitchFlight(start:release,end:self.destination,started:ProcessInfo.processInfo.systemUptime,
                duration:duration,code:pitchCode,reduced:reduceMotion,receipt:DeliveryPresentation.receipt(reduced:reduceMotion,match:matchJudgment),outcome:outcome,fieldPlay:fieldPlay,homeRun:homeRun,arrival:onArrival,completion:completion)
        }
        if preparedRelease && role == .pitcher { launch() }
        else {
            run(.sequence([
                .run { [weak self] in
                    guard let self else { return }
                    self.pitcherPose(1)
                    if self.role == .pitcher { self.ball.position = self.handPoint(1) }
                },
                .wait(forDuration: MatchDelivery.windup * 0.55),
                .run { [weak self] in
                    guard let self else { return }; self.pitcherPose(2)
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
    private func startContact(_ play:MatchDetailedPlay?,homeRun:MatchHomeRun? = nil,origin:CGPoint,reduced:Bool,arrival:(@MainActor () -> Void)?,completion:(@MainActor () -> Void)?,startedAt:Double? = nil) {
        ball.removeAllActions();receivedBall.isHidden=true;ball.isHidden=false
        ball.position=point(origin.x,origin.y)
        contactFlight=ContactFlight(play:play,homeRun:homeRun,startedAt:startedAt ?? ProcessInfo.processInfo.systemUptime,origin:origin,reduced:reduced,arrival:arrival,completion:completion)
    }
    func finishBat(action: String, outcome: String, reduced: Bool, matchJudgment: Bool = false, fieldPlay:MatchDetailedPlay? = nil, homeRun:MatchHomeRun? = nil, onArrival: (@MainActor () -> Void)? = nil, completion: @escaping @MainActor () -> Void) {
        if action != "watch" { batterPose(action == "bunt" ? 4:1) }
        batFinish=BatFinish(at:max(contactAt,ProcessInfo.processInfo.systemUptime),action:action,outcome:outcome,reduced:reduced,
            receipt:DeliveryPresentation.receipt(reduced:reduced,match:matchJudgment),play:fieldPlay,homeRun:homeRun,arrival:onArrival,completion:completion)
    }
}

// Atlas pivots are presentation metadata. The rubber stays fixed for both hands and batter sides.
struct PitcherPresentationPose {
    let width: Double
    private(set) var pivot: CGPoint
    private(set) var hand: CGPoint
    private(set) var foot: CGPoint
    init(role: PlayerRole, frame: Int, hand throwingHand: String) {
        if role == .pitcher {
            let pivots = [CGPoint(x:0.70,y:0.90),CGPoint(x:0.57,y:0.90),CGPoint(x:0.74,y:0.90),CGPoint(x:0.41,y:0.85),CGPoint(x:0.40,y:0.85),CGPoint(x:0.42,y:0.85)]
            let hands = [CGPoint(x:0.42,y:0.56),CGPoint(x:0.38,y:0.52),CGPoint(x:0.72,y:0.37),CGPoint(x:0.78,y:0.11),CGPoint(x:0.50,y:0.65),CGPoint(x:0.40,y:0.55)]
            width = 0.52; pivot = pivots[frame]; hand = hands[frame]
            // The stride foot in frame 2 is x=.29 while the pivot foot is x=.74.
            // Carry that planted location into release instead of stepping backward on the next frame.
            foot = CGPoint(x: frame < 3 ? 0.76 : 0.526, y: frame < 3 ? 0.895 : 0.875)
        } else {
            width = 0.20
            let pivots = [0.5,0.53,0.65,0.65,0.55,0.52,0.50,0.5]
            pivot = CGPoint(x:pivots[frame],y:0.965)
            hand = frame == 4 ? CGPoint(x:0.35,y:0.08):CGPoint(x:0.35,y:0.42)
            foot = CGPoint(x:0.50,y:0.375)
        }
        if throwingHand == "left" {
            if role == .pitcher { self.foot.x = 1 - self.foot.x }
            self.pivot = CGPoint(x:1-pivot.x,y:pivot.y)
            self.hand = CGPoint(x:1-hand.x,y:hand.y)
        }
    }
}

@MainActor final class StadiumSceneDress: SKNode {
    enum Camera { case batter, pitcher, field }
    enum Celebration: String { case homeRun, doublePlay }
    let stadium: StadiumIdentity
    let fieldSize: CGSize
    private let effects = SKNode()
    private var lamps: [SKSpriteNode] = []
    private(set) var celebration: Celebration?
    private(set) var celebrationCount = 0
    var effectNodeCount: Int { effects.children.count }
    init(stadium: StadiumIdentity, size: CGSize, camera: Camera) {
        self.stadium = stadium;fieldSize = size
        super.init();name = "stadiumDress-" + stadium.theme.title
        let y: CGFloat = camera == .pitcher ? 0.25 : camera == .batter ? 0.166 : 0.15
        let positions: [CGFloat] = camera == .field ? [0.13,0.87] : [0.16,0.84]
        for (i,x) in positions.enumerated() {
            let sponsor = stadium.sponsors[i]
            let w = size.width*(camera == .field ? 0.20:0.22),h = max(12,size.width*0.052)
            let panel = SKShapeNode(rectOf:CGSize(width:w,height:h))
            panel.fillColor = UIColor(Color(hex:stadium.theme.panel));panel.strokeColor = UIColor(Color(hex:stadium.theme.trim));panel.lineWidth = 1
            panel.position = CGPoint(x:size.width*x,y:size.height*(1-y));addChild(panel)
            let mark = SKLabelNode(fontNamed:"Menlo-Bold");mark.text = sponsor.mark;mark.fontSize = h*0.60
            mark.fontColor = UIColor(Color(hex:stadium.theme.accent));mark.verticalAlignmentMode = .center;mark.position.x = -w*0.36;panel.addChild(mark)
            let label = SKLabelNode(fontNamed:"AppleSDGothicNeo-Bold");label.text = sponsor.name;label.fontSize = h*0.43
            label.fontColor = UIColor(GameTheme.paper);label.verticalAlignmentMode = .center;label.position.x = w*0.12;panel.addChild(label)
        }
        for i in 0..<12 {
            let light = SKSpriteNode(color:UIColor(Color(hex:stadium.theme.trim)),size:CGSize(width:size.width*0.022,height:2))
            light.position = CGPoint(x:size.width*(0.12+Double(i)*0.069),y:size.height*(1-(camera == .field ? 0.19:0.205)))
            light.alpha = 0.48;lamps.append(light);addChild(light)
        }
        effects.zPosition = 2;addChild(effects)
    }
    required init?(coder:NSCoder) {fatalError("Storyboard initialization is not used")}
    func reduceEffects() {
        effects.removeAllChildren()
        for light in lamps {light.removeAllActions();light.alpha = celebration == nil ? 0.48:0.8}
    }
    func celebrate(_ kind:Celebration,reduced:Bool) {
        guard celebration == nil else {return}
        celebration = kind;celebrationCount += 1
        guard !reduced else {reduceEffects();return}
        let delay = Double(stadium.variation)*0.08
        for (i,light) in lamps.enumerated() {
            let at = Double(stadium.theme == .brick ? i:11-i)*0.04+delay
            light.run(.sequence([.wait(forDuration:at),.fadeAlpha(to:1,duration:0.18),.wait(forDuration:0.35),.fadeAlpha(to:0.65,duration:0.35)]))
        }
        // Fixed, bounded decorative paths. No emitter, physics or random-number consumption.
        let count = kind == .doublePlay ? 12 : stadium.theme == .harbor ? 40 : 24
        for i in 0..<count {
            let node = SKSpriteNode(color:i.isMultiple(of:3) ? UIColor(GameTheme.gold):UIColor(Color(hex:stadium.theme.accent)),size:CGSize(width:3,height:i<8 ? 6:3))
            let side = i.isMultiple(of:2) ? 0.23:0.77
            node.position = CGPoint(x:fieldSize.width*side,y:fieldSize.height*0.82)
            effects.addChild(node)
            let angle = Double(i)*2.3999632297
            let radius = Double(16+(i%7)*7)
            let delta:CGVector
            switch stadium.theme {
            case .harbor:delta = CGVector(dx:cos(angle)*radius,dy:sin(angle)*radius)
            case .brick:delta = CGVector(dx:Double(i%6-3)*6,dy:Double(12+i%8*4))
            case .grove:delta = CGVector(dx:Double(i%6-3)*8,dy:-Double(12+i%7*5))
            case .metro:delta = CGVector(dx:Double(i%4-2)*4,dy:Double(20+i%8*4))
            }
            node.alpha = 0
            node.run(.sequence([.wait(forDuration:delay+Double(i%4)*0.08),.fadeIn(withDuration:0.12),.group([.move(by:delta,duration:0.75),.sequence([.wait(forDuration:0.40),.fadeOut(withDuration:0.35)])]),.removeFromParent()]))
        }
    }
}
