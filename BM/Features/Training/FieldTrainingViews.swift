import SwiftUI

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
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var motion: Double = 0
    var moving: Bool = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TraitTrainingArena(trait: kind == .arm ? .strongArm : kind == .speed ? .cheetah : .safeHands,
                                   target: kind == .arm ? TrainingRules.basePoint(base) : target ?? TrainingTarget(x: 0.5, y: 0.5),
                                   player: TrainingTarget(x: x, y: y), endpoint: TrainingRules.throwEndpoint(angle: angle, force: force),
                                   motion: motion, steps: steps, moving: moving, success: nil, appearance: appearance)
                if kind == .speed {
                    Text("\(steps) / 16 STEP").font(.caption.monospaced().bold())
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
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if kind == .stamina {
                    FieldTrainingBoard(kind: .speed, target: nil, base: 1, angle: 0, force: 0,
                                       steps: steps, appearance: appearance, x: $x, y: $y, locked: locked, motion: motion, moving: moving)
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
                    context.scaleBy(x: size.width / 320, y: size.height / 220)
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
                    box(ball.x - 2, ball.y - 2, 5, 5, 0xfff5d4)
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
            context.scaleBy(x: size.width / 320, y: size.height / 220)
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
                box(60 + (end.x - 60) * t, 150 + (end.y - 150) * t, 6, 6, 0xfff5d4)
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
            let exact = abs(phase - ManualMatchRules.releaseCenter) <= ManualMatchRules.perfectWidth(mastery: round.before)
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
