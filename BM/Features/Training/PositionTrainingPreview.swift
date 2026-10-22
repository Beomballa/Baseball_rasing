import SwiftUI

#if DEBUG
// UI sample only. Opening or operating this view never accesses a career store.
struct PositionTrainingPreview: View {
    private enum Sample: String, CaseIterable, Identifiable {
        case ready = "훈련 가능", locked = "오늘 행동 완료", pending = "이어하기", maxed = "최대 숙련", error = "조회 오류"
        var id: String { rawValue }
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected = FieldPosition.shortstop
    @State private var sample = Sample.ready
    @State private var showExercise = false
    private let primary = FieldPosition.shortstop
    private func mastery(_ position: FieldPosition) -> Double {
        if sample == .maxed && position == selected { return 100 }
        switch position {
        case .shortstop: return 60
        case .second: return 35.4
        case .center: return 18.2
        case .right: return 17.8
        default: return 10
        }
    }
    private var xp: Double { sample == .maxed ? 0 : 36 }
    private var available: Bool { sample == .ready || sample == .pending }
    private var stateMessage: String {
        switch sample {
        case .ready: "조건 충족 · 다른 포지션도 자유롭게 훈련"
        case .locked: "오늘 행동 사용 · 다음 날 훈련 가능"
        case .pending: "확정 2 / 5회 · 같은 포지션으로 이어하기"
        case .maxed: "최대 숙련 · 추가 XP 훈련 없음"
        case .error: "숙련도 조회 실패 · 실제 저장은 변경하지 않음"
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("화면 시안 · 숙련도/XP는 샘플 · 저장 안 함")
                        .font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("positionPreviewNotice")
                    HStack(spacing: 10) {
                        PixelPlayer(appearance: PlayerAppearance()).frame(width: 32, height: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("수비 포지션 훈련").font(.headline)
                            Text("주 포지션 SS · 유격수 / 야수 8위치").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    if sample == .error {
                        GamePanel(title: "숙련도를 불러오지 못했습니다", onBoard: true) {
                            Text(stateMessage).font(.subheadline).accessibilityIdentifier("positionState")
                            Button("샘플 다시 확인") { sample = .ready }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                                .accessibilityIdentifier("positionRetry")
                        }
                    } else {
                        positionSelector.frame(height: typeSize.isAccessibilitySize ? nil : max(200, min(230, geometry.size.height - 440)))
                        GamePanel(title: selected.rawValue + " · " + selected.label, onBoard: true) {
                            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                                Text(selected == primary ? "주 포지션" : "보조 포지션").font(.caption).foregroundStyle(GameTheme.gold)
                                if !typeSize.isAccessibilitySize { Spacer() }
                                Text("숙련 \(mastery(selected), specifier: "%.1f") / 100.0").font(.subheadline.monospaced().bold())
                                    .accessibilityIdentifier("positionMastery")
                            }
                            meter(mastery(selected), color: GameTheme.growth)
                            Text(sample == .maxed ? "숙련 100.0 · MAX" : "다음 숙련 +1까지 \(100 - xp, specifier: "%.1f") XP")
                                .font(.subheadline.bold()).accessibilityIdentifier("positionNextLevel")
                            meter(xp, color: GameTheme.gold)
                            Text("잔여 XP \(xp, specifier: "%.1f") / 100.0").font(.caption.monospaced()).foregroundStyle(GameTheme.gold)
                                .accessibilityIdentifier("positionProgress")
                            Text("조건 · 별도 능력치 제한 없음 / 하루 준비 1회")
                                .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("positionCondition")
                            Text("포지션은 잠금 해제 대신 XP를 쌓아 숙련을 높입니다.")
                                .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("5회").font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(selected.positionDrill.title).font(.subheadline.bold()).accessibilityIdentifier("positionTask")
                                Text(selected.positionDrill.instruction).font(.caption).foregroundStyle(GameTheme.boardMuted)
                            }
                        }
                        Text(stateMessage).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("positionState")
                        Button(sample == .pending ? "훈련 장면 이어보기 · 시안" : sample == .maxed ? "최대 숙련 도달" : sample == .locked ? "오늘 훈련 불가" : "훈련 장면 미리보기") { showExercise = true }
                            .buttonStyle(GameButtonStyle(onBoard: true)).disabled(!available).accessibilityIdentifier("positionStartPreview")
                        Text("시안에서는 XP·피로·오늘 행동·주 포지션이 바뀌지 않습니다.")
                            .font(.caption2).foregroundStyle(GameTheme.boardMuted)
                    }
                }.padding(12)
            }
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("포지션 훈련").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("샘플 상태", selection: $sample) { ForEach(Sample.allCases) { Text($0.rawValue).tag($0) } }
                    } label: { Text("시안 상태").font(.caption.bold()).foregroundStyle(GameTheme.gold) }
                        .accessibilityIdentifier("positionSampleState")
                }
            }
            .fullScreenCover(isPresented: $showExercise) {
                NavigationStack { PositionDrillPreview(position: selected, resumed: sample == .pending) }
            }
    }
    private var positionSelector: some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 6) {
                    ForEach(FieldPosition.allCases) { position in positionButton(position) }
                }
            } else {
                GeometryReader { geometry in
                    ZStack {
                        PositionPracticeField(position: selected, phase: 0, overview: true).accessibilityHidden(true)
                        ForEach(FieldPosition.allCases) { position in
                            positionButton(position).frame(width: 64, height: 44)
                                .position(x: geometry.size.width * position.fieldPoint.x, y: geometry.size.height * position.fieldPoint.y)
                        }
                    }
                }
            }
        }
    }
    private func positionButton(_ position: FieldPosition) -> some View {
        Button { selected = position } label: {
            VStack(spacing: 1) {
                Text(typeSize.isAccessibilitySize ? position.rawValue + " · " + position.label : position.rawValue + (position == primary ? " ★" : ""))
                    .font(.caption.bold())
                Text("\(mastery(position), specifier: "%.1f")").font(.caption.monospaced())
            }.frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected == position ? GameTheme.gold : GameTheme.boardInk)
                .background(GameTheme.boardPanel)
                .overlay(Rectangle().strokeBorder(selected == position ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
        }.buttonStyle(.plain).disabled(sample == .pending)
            .accessibilityLabel("\(position.label), 숙련 \(mastery(position).formatted(.number.precision(.fractionLength(1))))\(position == primary ? ", 주 포지션" : "")")
            .accessibilityAddTraits(selected == position ? .isSelected : [])
            .accessibilityIdentifier("positionSelect-" + position.rawValue)
    }
    private func meter(_ value: Double, color: Color) -> some View {
        GeometryReader { bar in
            ZStack(alignment: .leading) {
                Rectangle().fill(GameTheme.navy)
                Rectangle().fill(color).frame(width: bar.size.width * value / 100)
                HStack(spacing: 0) { ForEach(0..<20) { _ in Rectangle().strokeBorder(GameTheme.boardPanel, lineWidth: 1) } }
            }
        }.frame(height: 10).accessibilityHidden(true)
    }
}

#endif

extension FieldPosition {
    var fieldPoint: CGPoint {
        switch self {
        case .catcher: CGPoint(x: 0.5, y: 0.87)
        case .first: CGPoint(x: 0.81, y: 0.65)
        case .second: CGPoint(x: 0.66, y: 0.43)
        case .third: CGPoint(x: 0.19, y: 0.65)
        case .shortstop: CGPoint(x: 0.34, y: 0.43)
        case .left: CGPoint(x: 0.16, y: 0.15)
        case .center: CGPoint(x: 0.5, y: 0.13)
        case .right: CGPoint(x: 0.84, y: 0.15)
        }
    }
    var positionDrill: (title: String, instruction: String, feedback: String) {
        switch self {
        case .catcher: ("블로킹 → 2루 송구", "낮은 공을 막고 2루 송구 자세를 잡습니다.", "몸 앞에서 공을 막고 2루로 연결")
        case .first: ("베이스 커버 → 포구", "1루를 밟고 송구 방향으로 글러브를 뻗습니다.", "베이스를 유지하며 송구 확보")
        case .second: ("2루 커버 → 병살 연결", "2루 커버 위치를 잡고 1루 연결 동작을 익힙니다.", "포구 후 몸을 돌려 1루로 연결")
        case .third: ("강습 타구 → 1루 송구", "타구 앞을 막고 짧은 준비 동작으로 송구합니다.", "정면 포구 후 1루로 빠르게 연결")
        case .shortstop: ("백핸드 포구 → 1루 송구", "백핸드로 공을 잡고 발을 정렬해 송구합니다.", "포구 위치에서 발을 정렬해 1루 연결")
        case .left: ("낙하지점 → 중계 송구", "플라이 낙하지점을 잡고 유격수에게 연결합니다.", "낙하 지점 포구 후 중계수로 연결")
        case .center: ("타구 추적 → 중계 송구", "타구 방향으로 이동하고 2루 중계로 연결합니다.", "타구 추적 후 2루 중계수로 연결")
        case .right: ("낙하지점 → 3루 송구", "플라이를 잡고 3루 방향으로 송구 자세를 잡습니다.", "낙하 지점 포구 후 3루로 연결")
        }
    }
    var throwPoint: CGPoint {
        switch self {
        case .catcher, .center: CGPoint(x: 0.5, y: 0.38)
        case .right: CGPoint(x: 0.23, y: 0.61)
        case .left: FieldPosition.shortstop.fieldPoint
        case .first: CGPoint(x: 0.77, y: 0.61)
        default: CGPoint(x: 0.77, y: 0.61)
        }
    }
}

#if DEBUG
private struct PositionDrillPreview: View {
    let position: FieldPosition
    let resumed: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0
    private let phases = ["준비", "포구", "송구"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("훈련 장면 시안 · 입력 채점/XP 저장 미연결").font(.caption).foregroundStyle(GameTheme.gold)
                GamePanel(title: position.label + " · " + position.positionDrill.title, onBoard: true) {
                    Text(resumed ? "이어하기 상태 예시 · 확정 2 / 5회" : "훈련 구성 · 5회 / 아직 시작하지 않음").font(.caption)
                    HStack(spacing: 6) {
                        ForEach(0..<5) { index in
                            Text(resumed && index < 2 ? "완료" : "\(index + 1)")
                                .font(.caption.monospaced().bold()).frame(maxWidth: .infinity, minHeight: 32)
                                .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine))
                        }
                    }.accessibilityElement(children: .combine)
                }
                PositionPracticeField(position: position, phase: phase, overview: false)
                    .aspectRatio(320.0 / 220, contentMode: .fit).accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(position.label) 훈련장, \(phase == 0 ? "준비" : phase == 1 ? "포구" : "송구") 장면")
                    .accessibilityIdentifier("positionDrillField")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { phaseButtons }
                    VStack(spacing: 6) { phaseButtons }
                }
                Text(phase == 0 ? position.positionDrill.instruction : phase == 1 ? "목표 지점에 도착해 포구 자세 확인" : position.positionDrill.feedback)
                    .font(.subheadline).accessibilityIdentifier("positionDrillFeedback")
                GamePanel(title: "연결 예정", onBoard: true) {
                    Text("5회 결과 → 선택 위치 XP 누적\nXP 100마다 숙련 +1 · 완료 피로 +6")
                        .font(.subheadline)
                    Text("일반 훈련·휴식과 하루 준비 1회 공유").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Text("현재 장면 전환은 XP·능력치·경기 기록을 바꾸지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
                Button("포지션 선택으로") { dismiss() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                    .accessibilityIdentifier("positionCloseDrill")
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("포지션 훈련 장면").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
    @ViewBuilder private var phaseButtons: some View {
        ForEach(0..<3) { index in
            Button(index == 0 ? "준비" : phases[index]) { phase = index }
                .buttonStyle(GameButtonStyle(secondary: phase != index, onBoard: true))
                .accessibilityAddTraits(phase == index ? .isSelected : [])
                .accessibilityIdentifier("positionPhase-\(index)")
        }
    }
}

#endif

struct PositionPracticeField: View {
    let position: FieldPosition
    let phase: Int
    let overview: Bool
    var appearance = PlayerAppearance()
    var location: TrainingTarget? = nil
    var target: TrainingTarget? = nil
    var endpoint: TrainingTarget? = nil
    var motion: Double = 1
    var readMotion: Double = 0.5
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 320, y: size.height / 220)
            func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: Int) {
                context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)), with: .color(Color(hex: hex)))
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ hex: Int, width: Double = 2) {
                var path = Path(); path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .color(Color(hex: hex)), lineWidth: width)
            }
            func point(_ value: CGPoint) -> CGPoint { CGPoint(x: value.x * 320, y: value.y * 220) }
            func player(_ p: CGPoint, selected: Bool, receiving: Bool = false) {
                box(p.x - 8, p.y + 10, 16, 3, 0x26523d)
                box(p.x - 5, p.y - 17, 10, 4, selected ? PlayerAppearance.hairColors[appearance.hair] : 0x14283f)
                box(p.x - 4, p.y - 13, 8, 7, selected ? PlayerAppearance.skinColors[appearance.skin] : 0xe0ae7e)
                box(p.x - 5, p.y - 6, 10, 11, selected ? PlayerAppearance.kitColors[appearance.kit] : 0xd8e2d0)
                box(p.x - 5, p.y + 5, 4, 6, 0xf0eddb); box(p.x + 1, p.y + 5, 4, 6, 0xf0eddb)
                box(p.x - 7, p.y + 11, 6, 2, 0x14283f); box(p.x + 1, p.y + 11, 6, 2, 0x14283f)
                box(p.x + 5, p.y - (receiving ? 12 : 3), 7, 7, 0xb98248)
            }
            box(0, 0, 320, 220, 0x326b4d)
            for row in 0..<11 { box(0, Double(row * 22), 320, 11, row.isMultiple(of: 2) ? 0x377654 : 0x326b4d) }
            box(0, 0, 320, 12, 0x14283f)
            for col in 0..<40 { box(Double(col * 9), 3, 5, 3, col.isMultiple(of: 3) ? 0x9aa697 : 0x4b666b) }
            box(0, 12, 320, 6, 0x184a42); box(0, 12, 320, 2, 0xecc66b)
            let home = CGPoint(x: 160, y: 192), first = CGPoint(x: 246, y: 134), second = CGPoint(x: 160, y: 84), third = CGPoint(x: 74, y: 134)
            var diamond = Path(); diamond.addLines([home, first, second, third]); diamond.closeSubpath()
            context.fill(diamond, with: .color(Color(hex: 0xa07951)))
            context.stroke(diamond, with: .color(Color(hex: 0xe6dfbd)), lineWidth: 2)
            for p in [home, first, second, third] { box(p.x - 4, p.y - 3, 8, 6, 0xf3edd5) }
            line(home, CGPoint(x: 0, y: 84), 0xe6dfbd, width: 1); line(home, CGPoint(x: 320, y: 84), 0xe6dfbd, width: 1)
            box(154, 130, 12, 4, 0xeadfc5)
            for x in [12.0, 294] { box(x, 194, 14, 4, 0x9c7246); box(x + 2, 198, 2, 6, 0x594c3e) }
            if !overview {
                let origin = point(position.fieldPoint)
                let catchPoint = target.map { CGPoint(x: $0.x * 320, y: $0.y * 220) } ?? CGPoint(x: min(278, max(42, origin.x + (position == .first ? -6 : 18))), y: min(184, origin.y + 8))
                let destination = endpoint.map { CGPoint(x: $0.x * 320, y: $0.y * 220) } ?? point(position.throwPoint)
                for field in FieldPosition.allCases where field != position { player(point(field.fieldPoint), selected: false) }
                let p = location.map { CGPoint(x: $0.x * 320, y: $0.y * 220) } ?? (phase == 0 ? origin : catchPoint)
                context.stroke(Path(CGRect(x: catchPoint.x - 13, y: catchPoint.y - 9, width: 26, height: 18)), with: .color(GameTheme.gold), lineWidth: 2)
                if phase == 0 {
                    line(home, catchPoint, 0xecc66b, width: 1)
                    let t = readMotion
                    let ballX = home.x + (catchPoint.x - home.x) * t
                    let groundY = home.y + (catchPoint.y - home.y) * t
                    let rise = position == .left || position == .center || position == .right ? sin(t * .pi) * 38 : abs(sin(t * .pi * 3)) * 7
                    box(ballX - 3, groundY + 2, 8, 2, 0x245039)
                    PixelBaseball.draw(in:context,at:CGPoint(x:ballX,y:groundY-rise-3),diameter:9)
                    for i in 1...4 { let trail = max(0, t - Double(i) * 0.05); box(home.x + (catchPoint.x - home.x) * trail, home.y + (catchPoint.y - home.y) * trail, 2, 2, 0xa3b68c) }
                } else if phase == 1 { PixelBaseball.draw(in:context,at:CGPoint(x:catchPoint.x+8,y:catchPoint.y-9),diameter:9) }
                else {
                    for step in 1..<8 {
                        let t = Double(step) / 8
                        box(catchPoint.x + (destination.x - catchPoint.x) * t, catchPoint.y + (destination.y - catchPoint.y) * t, 3, 2, 0xecc66b)
                    }
                    let flight = position == .first && location != nil ? 1 - motion : motion
                    PixelBaseball.draw(in:context,at:CGPoint(x:p.x+(destination.x-p.x)*flight,y:p.y+(destination.y-p.y)*flight-sin(flight * .pi)*20-6),diameter:9)
                    context.stroke(Path(CGRect(x: destination.x - 13, y: destination.y - 12, width: 26, height: 24)), with: .color(GameTheme.growth), lineWidth: 2)
                }
                player(p, selected: true, receiving: phase > 0)
                if phase == 1 { box(p.x + 7, p.y - 13, 9, 7, 0xb98248) }
                if phase == 2 && motion < 0.25 { box(p.x + 5, p.y - 18, 5, 11, PlayerAppearance.skinColors[appearance.skin]) }
            }
        }.drawingGroup().clipped().overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
    }
}

#if DEBUG
#Preview("포지션 훈련 시안") { NavigationStack { PositionTrainingPreview() } }
#endif
