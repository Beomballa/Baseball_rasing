import SwiftUI
import SpriteKit


/// A single world-to-view transform keeps pixels square and touch coordinates reversible.
enum TrainingStageLayout {
    static let size = CGSize(width: 320, height: 220)
    static func rect(in size: CGSize) -> CGRect {
        let scale = min(size.width / self.size.width, size.height / self.size.height)
        let fitted = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        return CGRect(x: (size.width-fitted.width)/2, y: (size.height-fitted.height)/2, width: fitted.width, height: fitted.height)
    }
    static func world(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let rect = rect(in: size), scale = max(0.001, rect.width / self.size.width)
        return CGPoint(x: (point.x-rect.minX)/scale, y: (point.y-rect.minY)/scale)
    }
    static func fit(_ context: inout GraphicsContext, size: CGSize) {
        let rect = rect(in: size)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / self.size.width, y: rect.height / self.size.height)
    }
    static func fieldInput(_ point: CGPoint, in size: CGSize) -> TrainingTarget {
        let p = world(point, in: size)
        return TrainingTarget(x: min(1,max(0,(p.x-32)/256)), y: min(1,max(0,(p.y-48)/140)))
    }
}

/// Read-only progress toward the next one-decimal display boundary, not a reward formula.
enum TrainingGrowthDisplay {
    static func next(_ value: Double) -> Double { min(100,(floor(value*10+0.5)+1)/10) }
    static func progress(_ value: Double) -> Double {
        guard value < 99.95 else { return 1 }
        let lower = max(0,(floor(value*10+0.5)-0.5)/10)
        let upper = min(100,(floor(value*10+0.5)+0.5)/10)
        return min(1,max(0,(value-lower)/max(0.0001,upper-lower)))
    }
}

@MainActor enum TrainingEnvironmentArt {
    enum Room: Int { case bullpen, field, running, dugout }
    private static let panels: [UIImage?] = {
        guard let url = Bundle.main.url(forResource: "training-environments-v51", withExtension: "png", subdirectory: "MatchArt"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage else { return Array(repeating: nil,count: 4) }
        return (0..<4).map { index in
            guard let crop = source.cropping(to: CGRect(x: index % 2 * source.width/2, y: index/2 * source.height/2, width: source.width/2, height: source.height/2)) else { return nil }
            return UIImage(cgImage: crop)
        }
    }()
    static func image(_ room: Room) -> UIImage? { panels[room.rawValue] }
    static func texture(_ room: Room) -> SKTexture? {
        guard let image = image(room) else { return nil }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest; return texture
    }
    static var tee: SKTexture? {
        guard let url = Bundle.main.url(forResource: "training-tee-v51", withExtension: "png", subdirectory: "MatchArt"), let image = UIImage(contentsOfFile: url.path) else { return nil }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest; return texture
    }
}

/// Display coordinates use the exact normalized input consumed by CareerTraining.attempt.
struct LocationDrillReplay: Equatable {
    let kind: TrainingKind
    let target: TrainingTarget
    let input: TrainingTarget
    let score: Int
    static let windup = 0.45
    static let flight = 1.0
    static let receive = 0.3
    static let duration = windup + flight + receive
    var comparison: String {
        "◇ 목표 \(Self.coordinate(target)) · + \(kind == .control ? "조준" : "선수") \(Self.coordinate(input))"
    }
    static func coordinate(_ point: TrainingTarget) -> String { "가로 \(Int((point.x * 100).rounded())) 세로 \(Int((point.y * 100).rounded()))" }
    static func area(_ kind: TrainingKind) -> CGRect {
        kind == .control ? CGRect(x: 118, y: 48, width: 64, height: 64) : CGRect(x: 24, y: 90, width: 272, height: 115)
    }
    static func point(_ value: TrainingTarget, kind: TrainingKind) -> CGPoint {
        let rect = area(kind)
        return CGPoint(x: rect.minX + value.x * rect.width, y: rect.minY + value.y * rect.height)
    }
    static func input(at point: CGPoint, kind: TrainingKind) -> TrainingTarget {
        let rect = area(kind)
        return TrainingTarget(x: min(1, max(0, (point.x - rect.minX) / rect.width)), y: min(1, max(0, (point.y - rect.minY) / rect.height)))
    }
    static func finished(elapsed: Double) -> Bool { elapsed >= duration }
}

@MainActor final class LocationDrillScene: SKScene {
    private let actor = SKSpriteNode(), receiver = SKSpriteNode(), mitt = SKSpriteNode()
    private let ball = SKSpriteNode(texture: PixelBaseball.texture)
    private let goal = SKShapeNode(), aim = SKShapeNode()
    private var kind = TrainingKind.control
    private var appearance = PlayerAppearance()
    private var number = 1, hand = "right"
    private var frames: [SKTexture] = [], catchFrames: [SKTexture] = []
    private var actorKey = "", receiverKey = ""
    private var target = TrainingTarget(x: 0.5, y: 0.5), selected = TrainingTarget(x: 0.5, y: 0.5)
    private var playback: (replay: LocationDrillReplay, started: Double, flight: Double, curve: Double, completion: @MainActor () -> Void)?
    private var movement: (from: CGPoint, to: CGPoint, started: Double)?
    private(set) var playing = false
    private(set) var finished = false
    override init(size: CGSize) { super.init(size: size); scaleMode = .aspectFit }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func point(_ value: CGPoint) -> CGPoint { CGPoint(x: value.x, y: 220 - value.y) }
    private func facing(from: CGPoint, to: CGPoint) -> FieldFacing { .direction(dx: to.x - from.x, dy: from.y - to.y) }
    private func contact(_ motion: FieldSpriteMotion, at origin: CGPoint, hand: Bool) -> CGPoint {
        let offset = FieldRasterArt.contact(motion, kind: "fielder", left: self.hand == "left", hand: hand) ?? .zero
        return CGPoint(x: origin.x + offset.x * 1.7, y: origin.y - offset.y * 1.7)
    }
    private func cropped(_ name: String, rect: CGRect) -> SKTexture? {
        guard let image = MatchArt.image(name) else { return nil }
        let texture = SKTexture(rect: rect, in: SKTexture(image: image)); texture.filteringMode = .nearest; return texture
    }
    private func backdrop(_ texture: SKTexture?, rect: CGRect) {
        let node = SKSpriteNode(texture: texture, size: rect.size)
        node.position = point(CGPoint(x: rect.midX, y: rect.midY)); addChild(node)
    }
    func configure(kind: TrainingKind, appearance: PlayerAppearance, number: Int, hand: String) {
        cancel(); removeAllChildren(); self.kind = kind; self.appearance = appearance; self.number = number; self.hand = hand; actorKey = ""; receiverKey = ""; goal.isHidden = false; aim.isHidden = false
        actor.name = "locationActor"; ball.name = "locationBall"; goal.name = "locationGoal"; aim.name = "locationAim"
        backgroundColor = UIColor(Color(hex: 0x163b32))
        if kind == .control {
            backdrop(TrainingEnvironmentArt.texture(.bullpen), rect: CGRect(origin: .zero, size: TrainingStageLayout.size))
            let plate = SKSpriteNode(color: .white, size: CGSize(width: 18, height: 3)); plate.position = point(CGPoint(x: 150, y: 118)); addChild(plate)
            frames = PlayerMotionArt.textures(role: .pitcher, appearance: appearance, number: number, hand: hand)
            catchFrames = (0..<4).compactMap { i in
                cropped("catcher-parts", rect: CGRect(x: Double(i % 2) / 2, y: 1 - Double(i / 2 + 1) / 2, width: 0.5, height: 0.5))
            }
            actor.position = point(CGPoint(x: 248, y: 218)); actor.anchorPoint = CGPoint(x: 0.5, y: 0.05)
            actor.size = CGSize(width: 119, height: 147); actor.xScale = hand == "left" ? -1 : 1
            receiver.xScale = 1; receiver.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            receiver.size = CGSize(width: 51, height: 55); receiver.position = point(CGPoint(x: 150, y: 87))
            receiver.texture = catchFrames.first; receiver.zPosition = 2; addChild(receiver)
            mitt.size = CGSize(width: 20, height: 20); mitt.texture = catchFrames.count == 4 ? catchFrames[2] : nil
            mitt.zPosition = 5; addChild(mitt); actor.texture = frames.first
        } else {
            backdrop(TrainingEnvironmentArt.texture(.field), rect: CGRect(origin: .zero, size: TrainingStageLayout.size))
            let coachMotion = FieldSpriteMotion(facing: .direction(dx: 0, dy: -1), stage: .ready)
            setFieldActor(receiver, motion: coachMotion, number: 0); receiver.position = point(CGPoint(x: 160, y: 216))
            receiver.zPosition = 3; addChild(receiver); actor.xScale = 1
        }
        actor.zPosition = 4; addChild(actor)
        ball.size = CGSize(width: 10, height: 10); ball.zPosition = 8; ball.isHidden = true; addChild(ball)
        let diamond = CGMutablePath(); diamond.move(to: CGPoint(x: 0, y: 7)); diamond.addLine(to: CGPoint(x: 7, y: 0)); diamond.addLine(to: CGPoint(x: 0, y: -7)); diamond.addLine(to: CGPoint(x: -7, y: 0)); diamond.closeSubpath()
        goal.path = diamond; goal.strokeColor = UIColor(Color(hex: 0x91dfba)); goal.fillColor = .clear; goal.lineWidth = 2; goal.zPosition = 6; addChild(goal)
        let cross = CGMutablePath(); cross.move(to: CGPoint(x: -6, y: 0)); cross.addLine(to: CGPoint(x: 6, y: 0)); cross.move(to: CGPoint(x: 0, y: -6)); cross.addLine(to: CGPoint(x: 0, y: 6))
        aim.path = cross; aim.strokeColor = UIColor(Color(hex: 0xf1c965)); aim.lineWidth = 2; aim.zPosition = 7; addChild(aim)
        preview(target: target, input: selected, animated: false)
    }
    private func setFieldActor(_ node: SKSpriteNode, motion: FieldSpriteMotion, number: Int) {
        guard let sample = FieldRasterArt.samples(motion, kind: "fielder", left: hand == "left").first else { return }
        let key = FieldRasterArt.Request(sample: sample, kit: PlayerAppearance.kitColors[appearance.kit], skin: PlayerAppearance.skinColors[appearance.skin], hair: PlayerAppearance.hairColors[appearance.hair], number: number, back: motion.facing.back).key + String(sample.mirrored)
        if node === actor, key == actorKey { return }; if node === receiver, key == receiverKey { return }
        guard let image = FieldRasterArt.image(sample, kit: PlayerAppearance.kitColors[appearance.kit], skin: PlayerAppearance.skinColors[appearance.skin], hair: PlayerAppearance.hairColors[appearance.hair], number: number, back: motion.facing.back) else { return }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest; node.texture = texture
        node.size = CGSize(width: sample.frame.rect[2] * sample.unit * 1.7, height: sample.frame.rect[3] * sample.unit * 1.7)
        node.anchorPoint = CGPoint(x: sample.frame.pivot[0] / sample.frame.rect[2], y: 1 - sample.frame.pivot[1] / sample.frame.rect[3])
        node.xScale = sample.mirrored ? -1 : 1
        if node === actor { actorKey = key }; if node === receiver { receiverKey = key }
    }
    func preview(target: TrainingTarget, input: TrainingTarget, animated: Bool = true) {
        guard !playing else { return }
        self.target = target; selected = input; finished = false
        goal.position = point(LocationDrillReplay.point(target, kind: kind)); aim.position = point(LocationDrillReplay.point(input, kind: kind))
        ball.isHidden = true
        if kind == .control {
            actor.texture = frames.first; receiver.texture = catchFrames.first; mitt.texture = catchFrames.count == 4 ? catchFrames[2] : nil; mitt.position = goal.position
        } else {
            let destination = point(LocationDrillReplay.point(input, kind: kind)), delta = CGPoint(x: destination.x - actor.position.x, y: destination.y - actor.position.y)
            movement = animated && hypot(delta.x, delta.y) > 0.5 ? (actor.position, destination, ProcessInfo.processInfo.systemUptime) : nil
            setFieldActor(actor, motion: FieldSpriteMotion(facing: facing(from: actor.position, to: destination), stage: movement == nil ? .ready : .run), number: number)
            if movement == nil { actor.position = destination }
        }
    }
    func play(_ replay: LocationDrillReplay, at now: Double = ProcessInfo.processInfo.systemUptime, preparedRelease: Bool = false, flightDuration: Double = 1, curve: Double = 0, completion: @escaping @MainActor () -> Void) {
        movement = nil
        preview(target: replay.target, input: replay.input, animated: false)
        playback = (replay, now - (preparedRelease ? LocationDrillReplay.windup : 0), flightDuration, curve, completion); playing = true; finished = false; advance(at: now)
    }
    override func update(_ currentTime: TimeInterval) { advance(at: ProcessInfo.processInfo.systemUptime) }
    func advance(at now: Double) {
        if let movement {
            let progress = min(1, max(0, (now - movement.started) / 0.18))
            let dx = movement.to.x - movement.from.x, dy = movement.to.y - movement.from.y
            actor.position = CGPoint(x: movement.from.x + dx * progress, y: movement.from.y + dy * progress)
            setFieldActor(actor, motion: FieldSpriteMotion(facing: facing(from: movement.from, to: movement.to), stage: progress < 1 ? .run : .ready, progress: progress, gait: progress * .pi * 2), number: number)
            if progress == 1 { self.movement = nil }
        }
        guard let playback else { return }
        let elapsed = max(0, now - playback.started), p = min(1, max(0, (elapsed - LocationDrillReplay.windup) / playback.flight))
        let destination = point(LocationDrillReplay.point(kind == .control ? playback.replay.input : playback.replay.target, kind: kind))
        if kind == .control {
            let frame = elapsed < 0.2 ? 1 : elapsed < LocationDrillReplay.windup ? 2 : p < 0.3 ? 3 : p < 1 ? 4 : 5
            if frames.indices.contains(frame) { actor.texture = frames[frame] }
            let anchors = [(0.42, 0.56), (0.38, 0.52), (0.72, 0.37), (0.78, 0.11)]
            let held = anchors[min(3, frame)]
            let release = CGPoint(x: actor.position.x + (0.78 - 0.5) * actor.size.width * actor.xScale, y: actor.position.y + (1 - 0.11 - 0.05) * actor.size.height)
            ball.position = elapsed < LocationDrillReplay.windup ? CGPoint(x: actor.position.x + (held.0 - 0.5) * actor.size.width * actor.xScale, y: actor.position.y + (1 - held.1 - 0.05) * actor.size.height) : CGPoint(x: release.x + (destination.x - release.x) * p + sin(p * .pi) * playback.curve, y: release.y + (destination.y - release.y) * p)
            mitt.position = CGPoint(x: goal.position.x + (destination.x - goal.position.x) * p, y: goal.position.y + (destination.y - goal.position.y) * p)
            if p == 1, catchFrames.count == 4 { receiver.texture = catchFrames[1]; mitt.texture = catchFrames[3] }
        } else {
            let direction = facing(from: receiver.position, to: destination)
            let origin = contact(FieldSpriteMotion(facing: direction, stage: .release), at: receiver.position, hand: true)
            let catching = FieldSpriteMotion(facing: facing(from: destination, to: receiver.position), stage: .catchBall, progress: 1, chestCatch: false)
            let end = contact(catching, at: destination, hand: false)
            setFieldActor(receiver, motion: FieldSpriteMotion(facing: direction, stage: elapsed < LocationDrillReplay.windup ? .windup : p < 0.2 ? .release : .followThrough, progress: p), number: 0)
            ball.position = CGPoint(x: origin.x + (end.x - origin.x) * p, y: origin.y + (end.y - origin.y) * p + abs(sin(p * .pi * 3)) * 5 * (1-p))
            setFieldActor(actor, motion: FieldSpriteMotion(facing: facing(from: actor.position, to: receiver.position), stage: p < 0.8 ? .ready : .catchBall, progress: p, chestCatch: false), number: number)
        }
        ball.isHidden = elapsed < LocationDrillReplay.windup && kind == .defense
        if elapsed >= LocationDrillReplay.windup + playback.flight + LocationDrillReplay.receive {
            self.playback = nil; playing = false; finished = true; playback.completion()
        }
    }
    func prepareDrill(phase: Double) {
        guard !playing else { return }
        goal.isHidden = true; aim.isHidden = true
        let frame = phase < 0.27 ? 0 : phase < 0.56 ? 1 : 2
        if frames.indices.contains(frame) { actor.texture = frames[frame] }
        let anchors = [(0.42, 0.56), (0.38, 0.52), (0.72, 0.37)], held = anchors[frame]
        ball.isHidden = false
        ball.position = CGPoint(x: actor.position.x + (held.0 - 0.5) * actor.size.width * actor.xScale,
                                y: actor.position.y + (1 - held.1 - 0.05) * actor.size.height)
    }
    func cancel() { playback = nil; movement = nil; playing = false; removeAllActions(); actor.removeAllActions(); ball.isHidden = true }
}

struct LocationPracticeBoard: View {
    let kind: TrainingKind, target: TrainingTarget
    let scene: LocationDrillScene
    let player: CareerPlayer
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var aim: TrainingTarget { TrainingTarget(x: x, y: y) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene, preferredFramesPerSecond: 30).allowsHitTesting(false).accessibilityHidden(true)
            if kind == .defense, !typeSize.isAccessibilitySize {
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard !locked else { return }
                        let input = LocationDrillReplay.input(at: TrainingStageLayout.world(value.location, in: geometry.size), kind: kind)
                        x = input.x; y = input.y
                    })
                }.accessibilityHidden(true)
            }
            if kind == .control, !typeSize.isAccessibilitySize {
                GeometryReader { boardGeometry in
                let edge = min(84, max(44, boardGeometry.size.width * 0.26))
                VStack(spacing: 3) {
                    Text("코스").font(.caption.bold())
                    GeometryReader { geometry in
                        ZStack {
                            Rectangle().fill(GameTheme.navy)
                            Path { p in for i in 1...2 {
                                let f = Double(i) / 3
                                p.move(to: CGPoint(x: geometry.size.width * f, y: 0)); p.addLine(to: CGPoint(x: geometry.size.width * f, y: geometry.size.height))
                                p.move(to: CGPoint(x: 0, y: geometry.size.height * f)); p.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * f))
                            }}.stroke(GameTheme.boardLine, lineWidth: 1)
                            Text("◇").foregroundStyle(GameTheme.growth).position(x: target.x * geometry.size.width, y: target.y * geometry.size.height)
                            Text("+").foregroundStyle(GameTheme.gold).position(x: x * geometry.size.width, y: y * geometry.size.height)
                        }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                            guard !locked else { return }; let point = TrainingStageLayout.fieldInput(event.location, in: geometry.size)
                x = point.x; y = point.y
                        })
                    }.frame(width: edge, height: edge).overlay(Rectangle().strokeBorder(GameTheme.boardLine))
                }.padding(5).background(GameTheme.navy).padding(6).accessibilityHidden(true)
                }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(kind == .control ? "불펜 제구 연습장" : "일반 수비 연습장")
            .accessibilityValue("◇ 목표 \(LocationDrillReplay.coordinate(target)), + \(kind == .control ? "조준" : "선수") \(LocationDrillReplay.coordinate(aim))")
            .accessibilityIdentifier("locationPracticeField")
            .onAppear { scene.configure(kind: kind, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw); scene.preview(target: target, input: aim) }
            .onChange(of: x) { _, _ in if !locked { scene.preview(target: target, input: aim) } }
            .onChange(of: y) { _, _ in if !locked { scene.preview(target: target, input: aim) } }
            .onChange(of: target) { _, _ in if !locked { scene.preview(target: target, input: aim) } }
    }
}

struct TrainingAdjustment: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    let identifier: String
    var step: Double = 5
    var body: some View {
        VStack(spacing: 6) {
            Text("\(label) \(Int(value))\(suffix)").font(.caption.bold()).monospacedDigit()
            HStack(spacing: 8) {
                Button("−") { value = max(range.lowerBound, value - step) }
                    .accessibilityLabel(label + " 줄이기").accessibilityIdentifier(identifier + "Down").disabled(value <= range.lowerBound)
                TrainingValueRail(label: label, value: $value, range: range, step: step, suffix: suffix)
                    .accessibilityIdentifier(identifier + "Slider")
                Button("+") { value = min(range.upperBound, value + step) }
                    .accessibilityLabel(label + " 늘리기").accessibilityIdentifier(identifier + "Up").disabled(value >= range.upperBound)
            }.buttonStyle(MatchPixelButtonStyle())
        }
    }
}

struct FieldTrainingBoard: View {
    let kind: TrainingKind
    let target: TrainingTarget?
    let base: Int
    let angle: Double
    let force: Double
    let steps: Int
    let appearance: PlayerAppearance
    var number = 1
    var hand = "right"
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var motion: Double = 0
    var moving: Bool = false
    var conditioning = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TraitTrainingArena(trait: kind == .arm ? .strongArm : kind == .speed ? .cheetah : .safeHands,
                                   target: kind == .arm ? TrainingRules.basePoint(base) : target ?? TrainingTarget(x: 0.5, y: 0.5),
                                   player: TrainingTarget(x: x, y: y), endpoint: TrainingRules.throwEndpoint(angle: angle, force: force),
                                   motion: motion, steps: steps, moving: moving, success: nil, appearance: appearance, number: number, hand: hand, conditioning: conditioning)
                if kind == .speed {
                    Text(conditioning ? "왕복 페이스 · \(steps) / 16 STEP" : "1루 가속 · \(steps) / 16 STEP").font(.caption.monospaced().bold())
                        .padding(6).background(GameTheme.navy)
                        .frame(maxHeight: .infinity, alignment: .top).padding(8).accessibilityIdentifier("sprintSteps")
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard kind == .defense, !locked else { return }
                x = min(1, max(0, event.location.x / geometry.size.width)); y = min(1, max(0, event.location.y / geometry.size.height))
            }, including: kind == .defense && !locked ? .all : .none)
        }.clipped().overlay(Rectangle().strokeBorder(GameTheme.gold.opacity(0.5), lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("fieldTrainingBoard")
            .accessibilityAction(named: "왼쪽") { if kind == .defense && !locked { x = max(0, x - 0.05) } }
            .accessibilityAction(named: "오른쪽") { if kind == .defense && !locked { x = min(1, x + 0.05) } }
            .accessibilityAction(named: "위") { if kind == .defense && !locked { y = max(0, y - 0.05) } }
            .accessibilityAction(named: "아래") { if kind == .defense && !locked { y = min(1, y + 0.05) } }
    }
}


struct RawTrainingBoard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: TrainingKind
    let training: CareerTraining?
    let steps: Int
    var motion: Double = 0
    var moving: Bool = false
    var force: Double = 70
    var angle: Double = 35
    let appearance: PlayerAppearance
    var number = 1
    var hand = "right"
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if kind == .stamina {
                    FieldTrainingBoard(kind: .speed, target: nil, base: 1, angle: 0, force: 0,
                                       steps: steps, appearance: appearance, number: number, hand: hand, x: $x, y: $y, locked: locked, motion: motion, moving: moving, conditioning: true)
                } else {
                    Rectangle().fill(Color(hex: 0x2b684b))
                    RawPracticeBackdrop(kind: kind, force: force, angle: angle, motion: motion, playing: moving)
                        .allowsHitTesting(false)
                    if let training, !training.completed {
                        let target = training.targets[training.scores.count]
                        if kind == .control {
                            ZStack {
                                BattingAimZone(x: $x, y: $y, locked: locked)
                                Rectangle().strokeBorder(Color(hex: 0x82e6b2), lineWidth: 3).frame(width: 20, height: 20)
                                    .position(x: geometry.size.width * 0.8 * target.x, y: geometry.size.height * 0.8 * target.y)
                                    .allowsHitTesting(false)
                            }.frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.8)
                        } else if kind == .mental {
                            VStack(spacing: 18) {
                                PixelPlayer(appearance: appearance).frame(width: 48, height: 66)
                                Text("SITUATION \(training.scores.count + 1)/5").font(.caption.monospaced().bold())
                            }.padding(12)
                        } else {
                            let goal = RawTrainingRules.goal(kind: kind, target: target)
                            if kind == .velocity {
                                PixelPlayer(appearance: appearance).frame(width: 36, height: 50)
                                    .rotationEffect(.degrees(moving ? 10 : 0), anchor: .bottom)
                                    .position(x: geometry.size.width * 0.15, y: geometry.size.height * 0.73)
                            }
                            VStack(spacing: 8) {
                                Text(kind == .stuff ? "SPIN LAB" : "POWER THROW").font(.title2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                                Spacer(minLength: 50)
                                if !dynamicTypeSize.isAccessibilitySize {
                                    Text("목표 \(Int(goal.force))% · \(Int(goal.angle))°").font(.headline.monospaced()).accessibilityIdentifier("rawTrainingTarget")
                                }
                                Text(kind == .stuff ? "목표 회전 방향과 강도를 맞추세요" : "목표 힘과 발사 방향을 맞추세요").font(.caption)
                            }.padding(12)
                        }
                    } else {
                        VStack(spacing: 16) {
                            PixelPlayer(appearance: appearance).frame(width: 48, height: 66)
                            Text(kind.label + " TRAINING").font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                        }
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("rawTrainingBoard")
    }
}

/// Feedback is a projection of a confirmed score, never an additional reward event.
struct TrainingGradeBanner: View {
    let score: Int
    private var grade: String { score >= 99 ? "PERFECT" : score >= 90 ? "GREAT" : score >= 70 ? "GOOD" : "KEEP TRYING" }
    var body: some View {
        HStack(spacing: 10) {
            Text(grade).font(.caption.monospaced().bold())
            Spacer(minLength: 0)
            Text("\(score)점").font(.headline.monospaced().bold())
        }.padding(8).foregroundStyle(score >= 70 ? GameTheme.growth : GameTheme.gold)
            .background(GameTheme.navy).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2))
            .accessibilityElement(children: .combine).accessibilityIdentifier("trainingGrade")
    }
}

/// Side-on tee practice: the preview and playback use the same distance rule as scoring.
struct PowerPracticeBoard: View {
    let force: Double
    let angle: Double
    let round: Int
    let motion: Double
    let playing: Bool
    let appearance: PlayerAppearance
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    TrainingStageLayout.fit(&context, size: size)
                    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Int) {
                        context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)), with: .color(Color(hex: color)))
                    }
                    box(0, 0, 320, 220, 0x142d40); box(0, 82, 320, 138, 0x326b4d)
                    for i in 0..<16 { box(Double(i * 22), 68, 14, 8, 0x496777) }
                    box(0, 80, 320, 3, 0xecc66b); box(0, 184, 320, 36, 0x9b724a)
                    let target = TrainingRules.powerTarget(min(4, round))
                    let goalX = 42 + target * 1.75
                    box(goalX - 8, 179, 16, 5, 0xecc66b)
                    for i in 1...5 {
                        let x = 42 + Double(i * 30) * 1.75
                        box(x, 187, 2, 12, 0xe7dfbe)
                        context.draw(Text("\(i * 30)m").font(.system(size: 8, design: .monospaced)).foregroundColor(.white), at: CGPoint(x: x, y: 210))
                    }
                    box(46, 169, 3, 15, 0x152c3f); box(40, 183, 16, 3, 0xf3edd5)
                    let distance = TrainingRules.distance(force: force, angle: angle)
                    let endX = 46 + min(150, distance) * 1.75
                    let peak = min(130, max(12, sin(angle * .pi / 180) * force * 1.3))
                    func pathPoint(_ t: Double) -> CGPoint { CGPoint(x: 46 + (endX - 46) * t, y: 164 + 20 * t - sin(t * .pi) * peak) }
                    for i in 1...18 {
                        let t = Double(i) / 18
                        let p = pathPoint(t)
                        box(p.x, p.y, 2, 2, playing && t < motion ? 0xfff5d4 : 0x93ad90)
                    }
                    let ball = pathPoint(playing ? motion : 0)
                    box(ball.x - 3, 184, 8, 2, 0x245039)
                    PixelBaseball.draw(in:context,at:ball,diameter:9)
                    if playing && motion < 0.2 {
                        for d in [-1.0, 1] { box(48 + d * 12, 158 + d * 6, 5, 3, 0xecc66b) }
                    }
                }
                PixelPlayer(appearance: appearance).frame(width: 32, height: 44)
                    .rotationEffect(.degrees(playing ? -8 : 0), anchor: .bottom)
                    .position(x: geometry.size.width * 0.09, y: geometry.size.height * 0.73)
                Rectangle().fill(Color(hex: 0xc99759)).frame(width: 5, height: 28)
                    .rotationEffect(.degrees(playing ? 80 : -25), anchor: .bottom)
                    .position(x: geometry.size.width * 0.12, y: geometry.size.height * 0.72)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("티배팅 훈련장")
            .accessibilityValue("예상 비거리 \(TrainingRules.distance(force: force, angle: angle), specifier: "%.1f")미터")
    }
}

struct RawPracticeBackdrop: View {
    let kind: TrainingKind
    let force: Double
    let angle: Double
    let motion: Double
    let playing: Bool
    var body: some View {
        Canvas { context, size in
            TrainingStageLayout.fit(&context, size: size)
            func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Int) {
                context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)), with: .color(Color(hex: color)))
            }
            box(0, 0, 320, 38, 0x142d40)
            for i in 0..<12 { box(Double(i * 28), 15, 18, 8, 0x446478) }
            box(0, 38, 320, 3, 0xecc66b)
            if kind == .stuff {
                let center = CGPoint(x: 160, y: 110)
                // The field can stretch vertically; ball pixels must remain square on screen.
                let aspect = (size.width / 320) / (size.height / 220)
                func ballPixel(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
                    context.fill(Path(CGRect(x: x, y: center.y + (y - center.y) * aspect, width: width, height: height * aspect)), with: .color(color), style: FillStyle(antialiased: false))
                }
                for row in -13...13 {
                    let half = floor(sqrt(Double(13 * 13 - row * row)))
                    ballPixel(center.x - half * 2, center.y + Double(row) * 2, (half * 2 + 1) * 2, 2, GameTheme.paper)
                }
                for i in 0..<32 {
                    let t = Double(i) / 32 * .pi * 2
                    ballPixel(center.x + cos(t) * 43 - 1, center.y + sin(t) * 43 - 1, 2, 2, GameTheme.boardMuted)
                }
                let rotation = angle * .pi / 180 + (playing ? motion * force / 100 * .pi * 4 : 0)
                for i in 0..<8 {
                    let t = Double(i) / 8 * .pi * 2 + rotation
                    ballPixel(center.x + cos(t) * 18 - 2, center.y + sin(t) * 18 - 2, 4, 4, Color(hex: 0xbf5544))
                }
                ballPixel(center.x + cos(rotation) * 43 - 3, center.y + sin(rotation) * 43 - 3, 6, 6, GameTheme.gold)
                for i in 0..<10 { box(102 + Double(i * 12), 167, 9, 7, Double(i * 10) < force ? 0xecc66b : 0x204839) }
            } else if kind == .velocity {
                box(270, 61, 3, 112, 0xc6ceaf); box(225, 61, 48, 3, 0xc6ceaf)
                for i in 0..<7 { box(225 + Double(i * 8), 64, 1, 105, 0x82a091) }
                for i in 0..<10 { box(225, 64 + Double(i * 11), 45, 1, 0x82a091) }
                box(32, 173, 258, 16, 0x9b724a)
                let radians = angle * .pi / 180
                let end = CGPoint(x: 60 + cos(radians) * force * 1.8, y: 150 - sin(radians) * force)
                for i in 1...12 {
                    let t = Double(i) / 12
                    box(60 + (end.x - 60) * t, 150 + (end.y - 150) * t, 3, 2, 0xecc66b)
                }
                let t = playing ? motion : 0
                PixelBaseball.draw(in:context,at:CGPoint(x:60+(end.x-60)*t,y:150+(end.y-150)*t),diameter:9)
            } else if kind == .mental {
                box(28, 160, 264, 12, 0x9b724a); box(40, 172, 8, 30, 0x634d39); box(270, 172, 8, 30, 0x634d39)
                for i in 0..<7 { box(43 + Double(i * 37), 75, 21, 38, 0x244b44) }
            } else if kind == .control {
                for i in 0..<12 { box(Double(i * 29), 45, 2, 160, 0x638572) }
                for i in 0..<8 { box(0, 45 + Double(i * 23), 320, 1, 0x638572) }
            }
        }.clipped()
    }
}


/// A compact pixel rail complements the named step buttons and avoids a settings-style control.
struct TrainingValueRail: View {
    @Environment(\.isEnabled) private var enabled
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    private func set(_ fraction: Double) {
        guard enabled else { return }
        let raw = range.lowerBound + min(1, max(0, fraction)) * (range.upperBound - range.lowerBound)
        value = min(range.upperBound, max(range.lowerBound, range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step))
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let width = max(1, size.width - 12)
                context.fill(Path(CGRect(x: 6, y: 18, width: width, height: 8)), with: .color(GameTheme.navy))
                for index in 0..<11 {
                    let x = 6 + width * Double(index) / 10
                    context.fill(Path(CGRect(x: x, y: 16, width: 2, height: 12)), with: .color(GameTheme.boardMuted))
                }
                context.fill(Path(CGRect(x: 6, y: 20, width: width * fraction, height: 4)), with: .color(GameTheme.gold))
                context.fill(Path(CGRect(x: width * fraction, y: 12, width: 12, height: 20)), with: .color(GameTheme.gold))
                context.fill(Path(CGRect(x: width * fraction + 4, y: 15, width: 4, height: 14)), with: .color(GameTheme.navy))
            }.contentShape(Rectangle()).allowsHitTesting(enabled)
                .gesture(DragGesture(minimumDistance: 0).onChanged { set(($0.location.x - 6) / max(1, geometry.size.width - 12)) })
        }.frame(minWidth: 48, minHeight: 44, maxHeight: 44)
            .accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue("\(Int(value))\(suffix)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(range.upperBound, value + step)
                case .decrement: value = max(range.lowerBound, value - step)
                @unknown default: break
                }
            }
    }
}

struct TrainingMissionProgress: Equatable {
    let threshold: Int
    let required: Int
    let successes: Int
    let bestStreak: Int
    let attempts: Int
    var achieved: Bool { successes >= required }
    init(kind: TrainingKind, scores: [Int]) {
        let passing = [.discipline, .mental].contains(kind) ? 100 : 75
        threshold = passing
        required = [.discipline, .mental].contains(kind) ? 4 : 3
        attempts = scores.count
        successes = scores.filter { $0 >= passing }.count
        var streak = 0, best = 0
        for score in scores { streak = score >= passing ? streak + 1 : 0; best = max(best, streak) }
        bestStreak = best
    }
}

struct TrainingCoachNote: Equatable {
    let observation: String
    let next: String
}

enum TrainingSessionGuide {
    static func note(round: CareerTraining, input: TrainingInput, score: Int) -> TrainingCoachNote {
        if round.isSkillDrill {
            switch round.selectedKind {
            case .power:
                let phase = input.drill?.phase ?? 1
                return TrainingCoachNote(observation: score >= 99 ? "MAX에서 힘을 실었어요" : phase < 0.5 ? "힘을 일찍 풀었어요" : "MAX를 지나 힘을 풀었어요",
                    next: score >= 99 ? "같은 힘 모으기를 다음 타격에서도 이어가세요" : phase < 0.5 ? "다음에는 중앙까지 조금 더 모으세요" : "다음에는 조금 더 일찍 손을 떼세요")
            case .velocity:
                let taps = input.drill?.beats ?? [], count = taps.compactMap { $0 }.count
                return TrainingCoachNote(observation: "3단계 중 \(count)단계 입력 · 박자 \(score)점",
                    next: score >= 90 ? "준비·회전·릴리스의 리듬을 유지하세요" : "밝아진 노드를 한 번씩, 박자에 맞춰 누르세요")
            default:
                return TrainingCoachNote(observation: "훈련 궤적 일치 점수 \(score)점",
                    next: score >= 90 ? "시작부터 끝까지 같은 곡선을 이어가세요" : "시작과 끝을 연결하고 곡선의 가운데를 따라가세요")
            }
        }
        let kind = round.selectedKind, index = min(4, round.scores.count)
        let target = round.targets[index]
        func result(_ observation: String, _ next: String) -> TrainingCoachNote {
            TrainingCoachNote(observation: observation, next: next)
        }
        func placement(_ noun: String) -> TrainingCoachNote {
            let dx = target.x - input.x, dy = target.y - input.y
            let direction = abs(dx) >= abs(dy) ? (dx > 0 ? "오른쪽" : "왼쪽") : (dy > 0 ? "아래쪽" : "위쪽")
            return result(score >= 75 ? "목표 가까이에 도착했어요" : "목표와 위치가 벌어졌어요",
                          score >= 75 ? "다음 목표에서도 위치를 먼저 확인하세요" : "\(noun)을 \(direction)으로 더 옮겨 보세요")
        }
        switch kind {
        case .contact:
            let contact = TrainingRules.contactResult(input: input, target: target, contact: round.before)
            guard contact.didSwing else { return result("공을 지켜봤어요", "다음에는 조준 후 타격 버튼을 눌러 보세요") }
            if contact.positionScore < contact.timingScore { return placement("조준점") }
            let early = (input.timing ?? 0) < MatchDelivery.contactPhase
            return result("조준 \(contact.positionScore) · 타이밍 \(contact.timingScore)점",
                          contact.timingScore == 100 ? "지금 타이밍을 유지하고 다음 목표를 확인하세요" : early ? "배트를 조금 더 늦게 내보세요" : "배트를 조금 더 일찍 내보세요")
        case .pitch:
            let phase = input.release ?? 0
            let exact = abs(phase - ManualMatchRules.releaseCenter) <= ManualMatchRules.perfectWidth(mastery: round.controlMastery)
            return result(exact ? "노란 구간에서 공을 놓았어요" : phase < ManualMatchRules.releaseCenter ? "릴리스가 빨랐어요" : "릴리스가 늦었어요",
                          exact ? "같은 손 놓는 위치를 다시 재현해 보세요" : phase < ManualMatchRules.releaseCenter ? "다음에는 손을 조금 더 늦게 떼세요" : "다음에는 손을 조금 더 일찍 떼세요")
        case .power:
            let distance = TrainingRules.distance(force: input.force ?? 0, angle: input.angle ?? 0)
            let goal = TrainingRules.powerTarget(index), delta = distance - goal
            return result(String(format: "목표 %.0fm · 실제 %.1fm", goal, distance),
                          score >= 75 ? "좋은 거리예요. 다음 표적에 맞춰 다시 조절하세요" : delta > 0 ? "거리가 길어요. 힘을 조금 줄여 보세요" : "거리가 짧아요. 힘을 늘리거나 각도를45° 쪽으로 조절하세요")
        case .discipline:
            let strike = ManualMatchRules.isStrike(x: target.x, y: target.y)
            return result(strike ? "이번 공은 스트라이크였어요" : "이번 공은 볼이었어요",
                          score == 100 ? "경계를 잘 읽었어요. 다음 공도 끝까지 보세요" : "공이 도착한 위치와 존의 경계를 비교하세요")
        case .control: return placement("조준점")
        case .defense: return placement("선수")
        case .arm:
            let base = round.throwBase(index)
            if input.base != base { return result("송구할 베이스가 달랐어요", "먼저 목표 \(base == 4 ? "홈" : "\(base)루")을 선택하세요") }
            let point = TrainingRules.basePoint(base)
            let dx = point.x - 0.5, dy = point.y - 0.63
            let angle = (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let force = hypot(dx, dy) / 0.55 * 100
            return result(score >= 75 ? "목표 베이스 근처로 송구했어요" : "목표 베이스에서 송구가 벗어났어요",
                          String(format: "목표 방향 %.0f° · 필요한 강도 약%.0f%%", angle, force))
        case .velocity, .stuff:
            let goal = RawTrainingRules.goal(kind: kind, target: target)
            let difference = abs((input.angle ?? 0) - goal.angle).truncatingRemainder(dividingBy: 360)
            let angleError = min(difference, 360 - difference) / (kind == .velocity ? 35 : 90)
            let forceError = abs((input.force ?? 0) - goal.force) / 40
            return result(score >= 75 ? "목표 힘과 방향을 잘 맞췄어요" : "목표 힘 또는 방향에서 벗어났어요",
                          forceError >= angleError ? String(format: "먼저 강도를 %.0f%% 쪽으로 조절하세요", goal.force) : String(format: "먼저 방향을 %.0f° 쪽으로 조절하세요", goal.angle))
        case .speed, .stamina:
            let steps = TrainingRules.steps(input.footfalls ?? [])
            return result("좌우 교대 \(steps) / 16회", steps >= 12 ? "좋은 교대 리듬이에요. 다음에도 균형을 유지하세요" : "같은 발을 반복하기보다 좌우를 번갈아 눌러 보세요")
        case .mental:
            let question = RawTrainingRules.question(targets: round.targets, round: index)
            return result(score == 100 ? "다음 플레이에 집중하는 선택이에요" : "이 상황에서는 루틴을 먼저 정리해요", question.choices[question.answer])
        }
    }
}

struct TrainingMissionBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: TrainingKind
    let scores: [Int]
    var completed = false
    var body: some View {
        let mission = TrainingMissionProgress(kind: kind, scores: scores)
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(completed ? (mission.achieved ? "세트 목표 달성" : "다음 세트에서 다시 도전") : "오늘의 집중 목표")
                    .font(.caption.bold()).foregroundStyle(GameTheme.gold)
                Text("\(mission.threshold)점 이상 \(mission.required)회 · 성공 \(mission.successes)/\(mission.required)")
                    .font(.caption.monospaced()).fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                Text("최고 연속 \(mission.bestStreak)회").font(.caption2.monospaced())
                Text("5회 · 권장30초~1분").font(.caption2).foregroundStyle(GameTheme.boardMuted)
            }
        }.padding(8).background(GameTheme.boardPanel)
            .overlay(Rectangle().strokeBorder(mission.achieved ? GameTheme.gold : GameTheme.boardLine, lineWidth: 1))
            .accessibilityElement(children: .combine).accessibilityIdentifier("trainingMission")
    }
}

/// Tee batting is presentation-only; existing MAX hold/release scoring remains unchanged.
@MainActor final class TirePowerScene: SKScene {
    private let player = SKSpriteNode(), tee = SKSpriteNode(), ball = SKSpriteNode(texture: PixelBaseball.texture)
    private let flash = SKSpriteNode(color: .yellow, size: CGSize(width: 12, height: 12))
    private var frames: [SKTexture] = []
    private var playback: (started: Double, score: Int, reduced: Bool, completion: @MainActor () -> Void)?
    static let contactAt = 0.2
    static let duration = 1.1
    private let contact = CGPoint(x: 180, y: 102)
    override init(size: CGSize) { super.init(size: size); scaleMode = .aspectFit }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(player source: CareerPlayer) {
        cancel(); removeAllChildren(); backgroundColor = UIColor(Color(hex: 0x285446))
        let field = SKSpriteNode(texture: TrainingEnvironmentArt.texture(.field), size: TrainingStageLayout.size)
        field.position = CGPoint(x: 160, y: 110); addChild(field)
        tee.texture = TrainingEnvironmentArt.tee; tee.size = CGSize(width: 30, height: 78)
        tee.anchorPoint = CGPoint(x: 0.5,y: 1); tee.position = CGPoint(x: contact.x, y: contact.y-4); tee.zPosition = 2; addChild(tee)
        frames = PlayerMotionArt.textures(role: .batter, appearance: source.appearance, number: source.jerseyNumber, hand: source.throwingHandRaw)
        player.anchorPoint = CGPoint(x: 0.5, y: 0.05); player.size = CGSize(width: 190, height: 190); player.position = CGPoint(x: 105, y: 16)
        player.texture = frames.first; player.zPosition = 3; addChild(player)
        ball.size = CGSize(width: 9, height: 9); ball.position = contact; ball.zPosition = 4; addChild(ball)
        flash.position = contact; flash.isHidden = true; flash.zPosition = 5; addChild(flash)
    }
    func prepare(_ phase: Double) {
        guard playback == nil else { return }
        let index = phase < 0.5 ? 0 : 1
        if frames.indices.contains(index) { player.texture = frames[index] }
        ball.position = contact; ball.isHidden = false
    }
    func strike(score: Int, reduced: Bool, at now: Double = ProcessInfo.processInfo.systemUptime, completion: @escaping @MainActor () -> Void) { playback = (now, score, reduced, completion) }
    override func update(_ currentTime: TimeInterval) { advance(at: ProcessInfo.processInfo.systemUptime) }
    func advance(at now: Double) {
        guard let playback else { return }
        let t = max(0,now-playback.started)
        let index = t < Self.contactAt ? 1 : t < 0.42 ? 2 : 3
        if frames.indices.contains(index) { player.texture = frames[index] }
        let flight = min(1,max(0,(t-Self.contactAt)/(Self.duration-Self.contactAt)))
        // Display trajectory only. No new distance, hit, or success judgment is created.
        ball.position = CGPoint(x: contact.x+flight*135, y: contact.y+flight*46+sin(flight * .pi)*28)
        ball.setScale(1-flight*0.35)
        flash.isHidden = playback.reduced || t < Self.contactAt || t > 0.32
        if t >= Self.duration { self.playback = nil; flash.isHidden = true; playback.completion() }
    }
    func cancel() { playback = nil; flash.isHidden = true }
}

struct SkillTraceBoard: View {
    let target: TrainingTarget?
    @Binding var points: [TrainingTarget]
    let locked: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(GameTheme.board.opacity(0.94))
                if let target {
                    let reference = SkillDrillRules.curve(target)
                    Path { path in
                        path.addLines(reference.map { CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height) })
                    }.stroke(GameTheme.growth, style: StrokeStyle(lineWidth: 5, dash: [8, 5]))
                    ForEach([0,24], id: \.self) { i in
                        Text(i == 0 ? "① 시작" : "② 끝").font(.caption.bold())
                            .position(x: reference[i].x * geometry.size.width, y: reference[i].y * geometry.size.height + (i == 0 ? 18 : -18))
                    }
                    Path { path in path.addLines(points.map { CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height) }) }
                        .stroke(GameTheme.gold, lineWidth: 3)
                } else { Text("세트 시작 후 훈련 궤적 확인").font(.caption) }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard !locked, target != nil else { return }
                if event.translation == .zero { points = [] }
                let point = TrainingTarget(x: min(1,max(0,event.location.x / geometry.size.width)), y: min(1,max(0,event.location.y / geometry.size.height)))
                if let last = points.last, hypot(last.x-point.x,last.y-point.y) < 0.005 { return }
                if points.count >= 255 { points = points.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element) }
                points.append(point)
            }, including: locked ? .none : .all)
        }.accessibilityElement(children: .ignore).accessibilityLabel("구위 궤적 연습판")
            .accessibilityValue("점선이 목표, 실선이 입력, \(points.count)개 지점. 버튼 조작도 사용할 수 있습니다.")
            .accessibilityIdentifier("skillTraceBoard")
    }
}

struct DrillValueControl: View {
    let name: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step = 0.01
    var body: some View {
        VStack(spacing: 4) {
            Text("\(name) \(value, specifier: "%.2f")").font(.caption.monospacedDigit())
        HStack(spacing: 8) {
            Button("−") { value = max(range.lowerBound, value - step) }.accessibilityLabel(name + " 줄이기").frame(minWidth: 44,minHeight: 44)
            Slider(value: $value, in: range, step: step).tint(GameTheme.gold)
                .accessibilityLabel(name + ", 값 " + String(format: "%.2f", value)).accessibilityIdentifier("skillSlider-" + name)
            Button("+") { value = min(range.upperBound, value + step) }.accessibilityLabel(name + " 늘리기").frame(minWidth: 44,minHeight: 44)
        }.buttonStyle(MatchPixelButtonStyle())
        }
    }
}


/// Presentation time only. Neither these phases nor sprite positions are training judgments.
enum TrainingFieldMotion {
    static let duration = 2.1
    static let release = 0.2
    static let arrival = 0.82
    static func flight(_ phase: Double) -> Double { min(1,max(0,(phase-release)/(arrival-release))) }
    static func stage(_ phase: Double) -> FieldSpriteStage { phase < release ? .windup : phase < 0.34 ? .release : .followThrough }
    static func readyForFeedback(elapsed: Double) -> Bool { elapsed >= duration }
}

@MainActor enum TrainingFieldArt {
    nonisolated static func point(_ p: TrainingTarget) -> CGPoint { CGPoint(x: 32+p.x*256,y: 48+p.y*140) }
    static func background(in context: GraphicsContext, room: TrainingEnvironmentArt.Room = .field) {
        context.fill(Path(CGRect(origin: .zero, size: TrainingStageLayout.size)),with:.color(Color(hex:0x326b4d)))
        if let image = TrainingEnvironmentArt.image(room) {
            context.draw(Image(uiImage: image).interpolation(.none), in: CGRect(origin: .zero, size: TrainingStageLayout.size))
        }
    }
    static func actor(in context:GraphicsContext,at p:CGPoint,appearance:PlayerAppearance,number:Int,hand:String,motion:FieldSpriteMotion,runner:Bool=false,coach:Bool=false) {
        FieldRasterArt.draw(in:context,at:p,scale:1.45,motion:motion,kind:runner ? "runner":"fielder",
            kit:coach ? 0x97664a:PlayerAppearance.kitColors[appearance.kit],skin:PlayerAppearance.skinColors[appearance.skin],
            hair:PlayerAppearance.hairColors[appearance.hair],number:number,left:hand == "left",selected:!coach,out:false)
    }
    static func contact(_ motion:FieldSpriteMotion,origin:CGPoint,hand:Bool,left:Bool) -> CGPoint {
        let p=FieldRasterArt.contact(motion,kind:"fielder",left:left,hand:hand) ?? .zero
        return CGPoint(x:origin.x+p.x*1.45,y:origin.y+p.y*1.45)
    }
    static func marker(in context:GraphicsContext,at p:CGPoint,goal:Bool) {
        var path=Path()
        if goal { path.addLines([CGPoint(x:p.x,y:p.y-9),CGPoint(x:p.x+9,y:p.y),CGPoint(x:p.x,y:p.y+9),CGPoint(x:p.x-9,y:p.y)]);path.closeSubpath() }
        else {path.move(to:CGPoint(x:p.x-7,y:p.y));path.addLine(to:CGPoint(x:p.x+7,y:p.y));path.move(to:CGPoint(x:p.x,y:p.y-7));path.addLine(to:CGPoint(x:p.x,y:p.y+7))}
        context.stroke(path,with:.color(goal ? Color(hex:0x91dfba):GameTheme.gold),lineWidth:2)
    }
}

struct MentalPracticeBoard: View {
    let appearance:PlayerAppearance
    var number = 1
    var hand = "right"
    let round:Int
    let reviewing:Bool
    var body:some View {
        ZStack(alignment:.topLeading) {
            Canvas { context,size in
                TrainingStageLayout.fit(&context, size: size);TrainingFieldArt.background(in:context, room: .dugout)
                TrainingFieldArt.actor(in:context,at:CGPoint(x:135,y:179),appearance:appearance,number:number,hand:hand,motion:FieldSpriteMotion(facing:.direction(dx:1,dy:0),stage:.ready))
                TrainingFieldArt.actor(in:context,at:CGPoint(x:204,y:153),appearance:appearance,number:0,hand:"right",motion:FieldSpriteMotion(facing:.direction(dx:-1,dy:0),stage:.ready),coach:true)
            }
            VStack(alignment:.leading,spacing:5) {
                Text("멘탈 루틴 · \(min(5,round+1))/5").font(.subheadline.bold())
                Text(reviewing ? "선택한 대응 돌아보기":"상황 읽기 → 대응 선택 → 루틴 확인").font(.caption)
            }.padding(10).background(GameTheme.navy).padding(8)
        }.accessibilityElement(children:.combine).accessibilityIdentifier("mentalPracticeScene")
    }
}


struct TrainingProjectFeedbackPanel: View {
    let training: CareerTraining
    var body: some View {
        ManagementPanel("이번 훈련 · 목표 과제", surface: .paper) {
            if let receipt=training.projectFeedback {
                if let project=receipt.project,let after=receipt.after {
                    Text(receipt.clubName ?? project.target.clubID).font(.headline).accessibilityIdentifier("trainingProjectClub")
                    Text("훈련 +\(receipt.trainingContribution)회 · 우수 +\(receipt.qualityContribution)회 · 지정 활동 +\(receipt.taskContribution)")
                        .font(.subheadline.bold()).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("trainingProjectContribution")
                    progress("관련 훈련",value:after.trainingKeys.count,total:after.task?.trainingGoal ?? 3)
                    progress("평균 75점 이상",value:after.qualitySessions,total:after.task?.qualityGoal ?? 2)
                    if let task=after.task { progress("지정 관찰 활동",value:task.value,total:task.goal) }
                    progress(project.role == .batter ? "공식 타석":"공식 투구 아웃",value:after.sample,total:after.requiredSample)
                    Text(training.date >= project.end ? "기간 마감 · 다음 관찰 보고서에서 확인하세요.":receipt.nextAction)
                        .font(.subheadline).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("trainingProjectNextAction")
                    Text("완료일 기준 저장 · 관찰 보고서와 계약 심사에는 기존 규칙으로 반영")
                        .font(.caption).fixedSize(horizontal:false,vertical:true)
                } else { Text("완료 당시 진행 중인 선수 프로젝트가 없습니다.").font(.subheadline) }
            } else { Text("이전 기록 · 완료 당시의 과제 요약이 저장되지 않았습니다.").font(.subheadline) }
        }.accessibilityIdentifier("trainingProjectFeedback")
    }
    private func progress(_ title:String,value:Int,total:Int) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text("\(title) \(value) / \(total) · 남음 \(max(0,total-value))").font(.caption.monospacedDigit())
            ProgressView(value:Double(min(value,max(1,total))),total:Double(max(1,total))).tint(GameTheme.growth).accessibilityHidden(true)
        }.accessibilityElement(children:.combine)
    }
}


struct CareerProjectNextActions: View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    var body:some View {
        VStack(spacing:8) {
            NavigationLink {CareerObjectivesView(player:player,calendar:calendar)} label: {Text("현재 선수 프로젝트 보기")}
                .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("completionProjectAction")
            NavigationLink {ObservationReviewView(player:player,calendar:calendar)} label: {Text("28일 관찰 결산 보기")}
                .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("completionObservationAction")
            Text("과제 상세에서 다음 행동 선택 · 날짜와 행동은 자동으로 진행되지 않습니다.").font(.caption).fixedSize(horizontal:false,vertical:true)
        }
    }
}

struct MatchProjectFeedbackPanel:View {
    let feedback:MatchProjectFeedback?
    var body:some View {
        GamePanel(title:"이번 경기 · 목표 과제",onBoard:true) {
            if let feedback {
                if let project=feedback.project,let after=feedback.after {
                    Text(feedback.clubName ?? project.target.clubID).font(.headline).foregroundStyle(GameTheme.gold)
                    Text("공식 \(project.role == .batter ? "타석":"투구 아웃") +\(feedback.sampleContribution) · 지정 활동 +\(feedback.taskContribution)")
                        .font(.subheadline.bold()).accessibilityIdentifier("matchProjectContribution")
                    Text("공식 표본 \(after.sample) / \(after.requiredSample) · 남음 \(max(0,after.requiredSample-after.sample))").font(.subheadline.monospacedDigit())
                    let trainingGoal=after.task?.trainingGoal ?? 3,qualityGoal=after.task?.qualityGoal ?? 2
                    if trainingGoal>0 {Text("관련 훈련 \(after.trainingKeys.count) / \(trainingGoal) · 남음 \(max(0,trainingGoal-after.trainingKeys.count))회").font(.subheadline)}
                    if qualityGoal>0 {Text("우수 훈련 \(after.qualitySessions) / \(qualityGoal) · 남음 \(max(0,qualityGoal-after.qualitySessions))회").font(.subheadline)}
                    if let task=after.task,task.goal>0 {Text(task.metric.label+" \(task.value) / \(task.goal)").font(.subheadline)}
                    Text(after.complete ? "과제 기준 충족 · 다음 관찰 보고서에서 확인":"관련 훈련·공식 출전의 남은 조건은 과제 상세에서 확인하세요.").font(.subheadline)
                    Text(feedback.date+" 완료 당시 저장 · 추가 XP·계약 가산 없음").font(.caption)
                } else {Text("완료 당시 진행 중인 선수 프로젝트가 없습니다.").font(.subheadline)}
            } else {Text("이전 경기 · 완료 당시 과제 요약 미저장").font(.subheadline)}
        }.accessibilityElement(children:.contain).accessibilityIdentifier("matchProjectFeedback")
    }
}
