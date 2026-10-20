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
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    func point(_ target: TrainingTarget) -> CGPoint { CGPoint(x: target.x * size.width, y: target.y * size.height) }
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x2b684b)))
                    var diamond = Path(); diamond.move(to: point(TrainingRules.basePoint(4)))
                    for number in [1, 2, 3, 4] { diamond.addLine(to: point(TrainingRules.basePoint(number))) }
                    context.fill(diamond, with: .color(Color(hex: 0x986743))); context.stroke(diamond, with: .color(GameTheme.paper), lineWidth: 2)
                    for number in 1...4 {
                        let center = point(TrainingRules.basePoint(number))
                        context.fill(Path(CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(number == base && kind == .arm ? GameTheme.gold : GameTheme.paper))
                    }
                    if kind == .arm {
                        let origin = point(TrainingTarget(x: 0.5, y: 0.63)), end = point(TrainingRules.throwEndpoint(angle: angle, force: force))
                        var line = Path(); line.move(to: origin); line.addLine(to: end)
                        context.stroke(line, with: .color(GameTheme.gold), style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
                        context.fill(Path(CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(GameTheme.gold))
                    }
                    if kind == .defense, let target {
                        let center = point(target)
                        context.stroke(Path(CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)), with: .color(GameTheme.gold), lineWidth: 3)
                    }
                }
                if kind == .defense {
                    PixelPlayer(appearance: appearance).frame(width: 24, height: 34)
                        .position(x: geometry.size.width * x, y: geometry.size.height * y).allowsHitTesting(false)
                } else if kind == .speed {
                    VStack {
                        Text("16 STEP / 4 SEC").font(.caption.monospaced().bold())
                        Spacer()
                        PixelPlayer(appearance: appearance).frame(width: 40, height: 55)
                            .offset(x: min(1, Double(steps) / 16) * geometry.size.width * 0.45 - geometry.size.width * 0.22)
                        Spacer()
                        Text("\(steps)걸음").font(.title2.monospaced().bold()).accessibilityIdentifier("sprintSteps")
                    }.padding(12)
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
    let appearance: PlayerAppearance
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if kind == .stamina {
                    FieldTrainingBoard(kind: .speed, target: nil, base: 1, angle: 0, force: 0,
                                       steps: steps, appearance: appearance, x: $x, y: $y, locked: locked)
                } else {
                    Rectangle().fill(Color(hex: 0x2b684b))
                    // Pixel lanes connect the controls to a practice field rather than a settings form.
                    Canvas { context, size in
                        for row in stride(from: 0, to: Int(size.height), by: 24) {
                            context.fill(Path(CGRect(x: 0, y: row, width: Int(size.width), height: 1)), with: .color(GameTheme.paper.opacity(0.12)))
                        }
                    }.allowsHitTesting(false)
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
                            VStack(spacing: 18) {
                                Text(kind == .stuff ? "SPIN LAB" : "POWER THROW").font(.title2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                                PixelPlayer(appearance: appearance).frame(width: 48, height: 66)
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
