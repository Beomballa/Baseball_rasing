import SwiftUI
import SwiftData

struct PositionHomePanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var profiles: [PlayerPositions]
    @State private var selection: FieldPosition?
    private var selected: FieldPosition { selection ?? FieldPosition(rawValue: player.positionRaw) ?? .shortstop }
    var body: some View {
        if player.role == .batter {
            GamePanel(title: "포지션 수첩", onBoard: true, contentSpacing: 14) {
                if let profile = profiles.first(where: { $0.playerID == player.id }), let value = try? profile.snapshot() {
                    let heading = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    heading {
                        Text("DEFENSE MAP").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Text("주 포지션 · " + player.positionRaw).font(.subheadline.bold())
                    }
                    if !typeSize.isAccessibilitySize {
                        PositionNotebookField(selected: selected, primary: player.positionRaw, value: value) { selection = $0 }
                            .frame(height: 248).accessibilityElement(children: .contain).accessibilityIdentifier("homePositionMap")
                    }
                    if let skill = value.skills[selected.rawValue] {
                        PositionNotebookSkill(position: selected, skill: skill, primary: player.positionRaw, identifier: "homeSelectedPosition")
                    }
                    Text("위치를 선택해 숙련 확인").font(.subheadline.bold()).foregroundStyle(GameTheme.boardMuted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                        ForEach(FieldPosition.allCases) { position in
                            if let skill = value.skills[position.rawValue] {
                                Button { selection = position } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(position.label + (player.positionRaw == position.rawValue ? " · 주" : ""))
                                            .font(.subheadline.bold()).foregroundStyle(selected == position ? GameTheme.gold : GameTheme.boardInk)
                                        Text("\(position.rawValue)\(player.positionRaw == position.rawValue ? " · 주" : "")  \(skill.mastery, specifier: "%.1f") / XP \(skill.xp, specifier: "%.1f")")
                                            .font(.caption.monospaced()).foregroundStyle(GameTheme.boardInk)
                                            .accessibilityIdentifier("homePosition-" + position.rawValue)
                                        PositionMeter(value: skill.mastery, color: GameTheme.growth)
                                    }.padding(10).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                                        .background(GameTheme.navy, in: ManagementStepFrame())
                                        .overlay(ManagementStepFrame().strokeBorder(selected == position ? GameTheme.gold : GameTheme.boardLine, lineWidth: 1))
                                }.buttonStyle(.plain).accessibilityIdentifier("homePositionSelect-" + position.rawValue)
                                    .accessibilityAddTraits(selected == position ? .isSelected : [])
                            }
                        }
                    }
                    Text("XP 100마다 숙련 +1 · 출전 위치의 숙련을 경기 시작 시 고정").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                } else {
                    Text("포지션 기록을 읽지 못했습니다. 훈련 화면에서 다시 확인해 주세요.").font(.subheadline).foregroundStyle(GameTheme.gold)
                }
                if let calendar {
                    NavigationLink { PositionTrainingView(player: player, calendar: calendar, initialPosition: selected) } label: { Text("포지션 훈련") }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("openPositionTraining")
                }
            }
        }
    }
}

private struct PositionNotebookField: View {
    let selected: FieldPosition
    let primary: String
    let value: PositionLoadout
    let choose: (FieldPosition) -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PositionPracticeField(position: selected, phase: 0, overview: true).accessibilityHidden(true)
                ForEach(FieldPosition.allCases) { position in
                    Button { choose(position) } label: {
                        VStack(spacing: 2) {
                            Text(position.rawValue + (position.rawValue == primary ? " · 주" : "")).font(.caption.bold())
                            if let skill = value.skills[position.rawValue] {
                                Text(skill.mastery, format: .number.precision(.fractionLength(1))).font(.caption.monospacedDigit())
                            }
                        }.frame(width: 66, height: 46).foregroundStyle(selected == position ? GameTheme.gold : GameTheme.boardInk)
                            .background(GameTheme.boardPanel, in: ManagementStepFrame())
                            .overlay(ManagementStepFrame().strokeBorder(selected == position ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(position.label + (position.rawValue == primary ? ", 주 포지션" : ""))
                        .accessibilityValue(value.skills[position.rawValue].map { "숙련 " + $0.mastery.formatted(.number.precision(.fractionLength(1))) } ?? "미기록")
                        .accessibilityAddTraits(selected == position ? .isSelected : [])
                        .accessibilityIdentifier("homePositionMap-" + position.rawValue)
                        .position(x: geometry.size.width * position.fieldPoint.x, y: geometry.size.height * position.fieldPoint.y)
                }
            }
        }
    }
}

private struct PositionNotebookSkill: View {
    let position: FieldPosition
    let skill: PositionSkill
    let primary: String
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(position.label + "  " + position.rawValue + (position.rawValue == primary ? " · 주 포지션" : ""))
                .font(.title3.bold()).foregroundStyle(GameTheme.gold)
            Text("숙련 \(skill.mastery, specifier: "%.1f") / 100.0").font(.title2.monospacedDigit().bold())
                .accessibilityIdentifier(identifier + "Mastery")
            PositionMeter(value: skill.mastery, color: GameTheme.growth)
            Text(skill.mastery == 100 ? "최대 숙련" : "다음 숙련 +1까지 \(100 - skill.xp, specifier: "%.1f") XP").font(.subheadline.bold())
            PositionMeter(value: skill.xp, color: GameTheme.gold)
            Text("잔여 XP \(skill.xp, specifier: "%.1f") / 100.0").font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                .accessibilityIdentifier(identifier + "XP")
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.board, in: ManagementStepFrame()).overlay(ManagementStepFrame().strokeBorder(GameTheme.gold, lineWidth: 2))
    }
}

struct PositionTrainingView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    var initialPosition: FieldPosition? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected = FieldPosition.shortstop
    @State private var loadout: PositionLoadout?
    @State private var record: CareerTrainingRecord?
    @State private var errorMessage: String?
    @State private var lockMessage: String?
    @State private var showDrill = false
    @State private var loaded = false
    private var skill: PositionSkill? { loadout?.skills[selected.rawValue] }
    private var ownsRecord: Bool { (try? record?.snapshot().position) != nil }
    private func load(open: Bool = false) {
        do {
            guard player.role == .batter, let profile = try PlayerPositionStore.profile(playerID: player.id, in: context) else { throw TrainingError.invalidRecord }
            loadout = try profile.snapshot(); record = try CareerTrainingStore.record(player: player, in: context)
            if let position = try record?.snapshot().position { selected = position; if open { showDrill = true } }
            lockMessage = nil
            if !ownsRecord {
                do { try PlayerTraitStore.requireEditable(player: player, state: calendar, in: context) }
                catch { lockMessage = error.localizedDescription }
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func start() {
        do {
            record = try CareerTrainingStore.start(player: player, state: calendar, position: selected, in: context)
            errorMessage = nil; showDrill = true
        } catch { errorMessage = error.localizedDescription }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        DetailGamePortrait(role: player.role, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw)
                            .frame(width: 56, height: 72).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POSITION TRAINING").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                            Text(player.name + " · 주 " + player.positionRaw).font(.headline)
                            Text("피로 \(player.fatigue) / 100").font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("positionTrainingError")
                        Button("기록 다시 확인") { load() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                    }
                    if let loadout, let skill {
                        selector(loadout).frame(height: typeSize.isAccessibilitySize ? nil : max(200, min(230, geometry.size.height - 430)))
                        PositionNotebookSkill(position: selected, skill: skill, primary: player.positionRaw, identifier: "livePosition")
                        Text("조건 · 야수 8위치 / 하루 준비 1회").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        Text(selected.positionDrill.title).font(.subheadline.bold())
                        Text(lockMessage ?? "5회 결과로 선택 위치 XP 증가 · 완료 피로 +6").font(.caption).foregroundStyle(GameTheme.gold)
                        Button(ownsRecord ? record?.completed == true ? "오늘 포지션 훈련 결과" : "포지션 훈련 이어하기" : "포지션 훈련 시작 · 5회") {
                            if ownsRecord { showDrill = true } else { start() }
                        }.buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("startPositionTraining")
                            .disabled(errorMessage != nil || (!ownsRecord && (lockMessage != nil || record != nil || skill.mastery >= 100)))
                    }
                }.padding(12)
            }
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("포지션 훈련").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .onAppear { if !loaded { loaded = true; selected = initialPosition ?? FieldPosition(rawValue: player.positionRaw) ?? .shortstop; load(open: true) } }
            .fullScreenCover(isPresented: $showDrill, onDismiss: { load() }) {
                if let record { NavigationStack { PositionDrillLiveView(player: player, calendar: calendar, record: record) } }
            }
    }
    @ViewBuilder private func selector(_ value: PositionLoadout) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 6) { ForEach(FieldPosition.allCases) { position in button(position, value) } }
        } else {
            GeometryReader { geometry in
                ZStack {
                    PositionPracticeField(position: selected, phase: 0, overview: true).accessibilityHidden(true)
                    ForEach(FieldPosition.allCases) { position in
                        button(position, value).frame(width: 64, height: 44)
                            .position(x: geometry.size.width * position.fieldPoint.x, y: geometry.size.height * position.fieldPoint.y)
                    }
                }
            }
        }
    }
    private func button(_ position: FieldPosition, _ value: PositionLoadout) -> some View {
        Button { selected = position } label: {
            VStack(spacing: 1) {
                Text(typeSize.isAccessibilitySize ? position.label : position.rawValue + (position.rawValue == player.positionRaw ? " ★" : "")).font(.caption.bold())
                if let skill = value.skills[position.rawValue] { Text("\(skill.mastery, specifier: "%.1f")").font(.caption.monospaced()) }
            }.frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(selected == position ? GameTheme.gold : GameTheme.boardInk)
                .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(selected == position ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
        }.buttonStyle(.plain).disabled(record != nil).accessibilityIdentifier("livePosition-" + position.rawValue)
            .accessibilityAddTraits(selected == position ? .isSelected : [])
    }
}

private struct PositionMeter: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(GameTheme.navy)
                Rectangle().fill(color).frame(width: geometry.size.width * min(100, max(0, value)) / 100)
                HStack(spacing: 0) { ForEach(0..<20) { _ in Rectangle().strokeBorder(GameTheme.boardPanel, lineWidth: 1) } }
            }
        }.frame(height: 10).accessibilityHidden(true)
    }
}

struct PositionDrillLiveView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let record: CareerTrainingRecord
    var practice = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var training: CareerTraining?
    @State private var phase = 0
    @State private var x = 0.5
    @State private var y = 0.5
    @State private var base = 1
    @State private var angle = 270.0
    @State private var force = 50.0
    @State private var errorMessage: String?
    @State private var pendingInput: TrainingInput?
    @State private var pendingRevision: Int?
    @State private var flightTask: Task<Void, Never>?
    @State private var startedAt = Date()
    private var endpoint: TrainingTarget { PositionTrainingRules.endpoint(x: x, y: y, angle: angle, force: force) }
    private func load(reset: Bool = false) {
        do {
            let saved = try (practice ? training ?? record.snapshot() : record.snapshot()); guard let position = saved.position else { throw TrainingError.invalidRecord }
            training = saved
            if reset { let origin = PositionTrainingRules.origin(position); x = origin.x; y = origin.y; phase = saved.completed ? 3 : 0 }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func saveInput() {
        guard let input = pendingInput, let revision = pendingRevision else { return }
        do {
            if practice {
                guard var round = training else { return }
                try round.attempt(input); training = round
            } else {
                try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context)
                load()
            }
            phase = 3; pendingInput = nil; pendingRevision = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func submit() {
        guard phase == 1, errorMessage == nil else { return }
        pendingInput = TrainingInput(x: x, y: y, force: force, angle: angle, base: base); pendingRevision = record.revision
        phase = 2; startedAt = Date()
        flightTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(TrainingFieldMotion.duration)) } catch { return }
            guard !Task.isCancelled else { return }; saveInput()
        }
    }
    private func cancelUnconfirmed() {
        flightTask?.cancel(); flightTask = nil
        if errorMessage == nil && phase != 3 { pendingInput = nil; pendingRevision = nil; phase = 0 }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("positionDrillError")
                        Button(pendingInput == nil ? "기록 다시 열기" : "같은 입력 저장 재시도") { if pendingInput == nil { load(reset: true) } else { saveInput() } }
                            .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("positionSaveRetry")
                    }
                    if let training, let position = training.position {
                        let index = min(4, max(0, training.scores.count - (phase == 3 ? 1 : 0)))
                        let target = training.targets[index]
                        if practice { Text("자유 연습 · 성장·저장 없음").font(.caption).foregroundStyle(GameTheme.gold) }
                        Text(position.label + " · " + position.positionDrill.title).font(.subheadline.bold())
                        let mission = TrainingMissionProgress(kind: .defense, scores: training.scores)
                        HStack {
                            Text("\(training.scores.count) / 5").font(.headline.monospaced()).accessibilityIdentifier("positionAttemptCount")
                            Spacer(minLength: 4)
                            Text("목표75점3회 · 성공 \(mission.successes)/3").font(.caption2)
                        }.foregroundStyle(GameTheme.gold)
                        HStack(spacing: 6) {
                            ForEach(0..<5) { i in Text(i < training.scores.count ? "\(training.scores[i])" : "·").font(.caption.monospaced()).frame(maxWidth: .infinity, minHeight: 28).background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.boardLine)) }
                        }.accessibilityElement(children: .combine)
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: phase == 1 || phase == 3 || errorMessage != nil)) { time in
                            PositionPracticeField(position: position, phase: phase == 0 ? 0 : phase == 1 ? 1 : 2, overview: false, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw,
                                                  location: TrainingTarget(x: x, y: y), target: target, endpoint: endpoint,
                                                  motion: min(1, max(0, time.date.timeIntervalSince(startedAt) / TrainingFieldMotion.duration)),
                                                  readMotion: reduced ? 0.6 : time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4)
                        }.frame(height: typeSize.isAccessibilitySize ? 230 : max(170, min(220, geometry.size.height - 390)))
                            .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                guard !typeSize.isAccessibilitySize, phase < 2, errorMessage == nil else { return }
                                let height = max(170, min(220, geometry.size.height - 390))
                                let px = min(0.95, max(0.05, value.location.x / max(1, geometry.size.width - 24)))
                                let py = min(0.95, max(0.05, value.location.y / height))
                                if phase == 0 { x = px; y = py }
                                else { angle = (atan2(py - y, px - x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360); force = min(100, hypot(px - x, py - y) / 0.9 * 100) }
                            }, including: typeSize.isAccessibilitySize ? .none : .all)
                            .accessibilityElement(children: .ignore).accessibilityLabel("\(position.label) 훈련장, 금색 목표로 이동 후 송구")
                            .accessibilityIdentifier("livePositionField")
                        if phase == 0 && !training.completed {
                            Text(position == .first ? "커버 위치로 이동 · 위치 60% / 포구 40%" : "금색 목표로 이동 · 위치 60% / 송구 40%")
                                .font(.caption).foregroundStyle(GameTheme.gold)
                            HStack(spacing: 6) {
                                moveButton("←", dx: -0.025, dy: 0, id: "left"); moveButton("↑", dx: 0, dy: -0.025, id: "up")
                                moveButton("↓", dx: 0, dy: 0.025, id: "down"); moveButton("→", dx: 0.025, dy: 0, id: "right")
                            }
                            Button(position == .first ? "커버 위치 확정" : "포구 위치 확정") { phase = 1 }.buttonStyle(GameButtonStyle(onBoard: true)).disabled(errorMessage != nil).accessibilityIdentifier("positionCatch")
                        } else if phase == 1 && !training.completed {
                            Text("목표 \(position.targetBase)루 · \(position == .first ? "포구" : "송구") 방향 \(angle, specifier: "%.0f")° / \(force, specifier: "%.0f")")
                                .font(.caption.monospaced()).foregroundStyle(GameTheme.gold)
                            HStack(spacing: 6) { ForEach(1...4, id: \.self) { b in
                                Button(b == 4 ? "홈" : "\(b)루") { base = b }.buttonStyle(GameButtonStyle(secondary: base != b, onBoard: true))
                                    .accessibilityIdentifier("positionBase-\(b)")
                            } }
                            HStack(spacing: 6) {
                                adjustment("각도 −5", id: "angleMinus") { angle = (angle + 355).truncatingRemainder(dividingBy: 360) }
                                adjustment("각도 +5", id: "anglePlus") { angle = (angle + 5).truncatingRemainder(dividingBy: 360) }
                            }
                            HStack(spacing: 6) {
                                adjustment("힘 −2", id: "forceMinus") { force = max(0, force - 2) }
                                adjustment("힘 +2", id: "forcePlus") { force = min(100, force + 2) }
                            }
                            Button(position == .first ? "포구 확정" : "송구 확정") { submit() }.buttonStyle(GameButtonStyle(onBoard: true)).disabled(errorMessage != nil).accessibilityIdentifier("positionThrow")
                        } else if phase == 2 {
                            Text(practice ? "연습 동작 재생 · 점수 판정 중" : position == .first ? "포구 중 · 확정 입력 저장 대기" : "송구 중 · 확정 입력 저장 대기")
                                .font(.caption).foregroundStyle(GameTheme.gold)
                        } else if phase == 3 {
                            if let score = training.scores.last { TrainingGradeBanner(score: score) }
                            Text(practice ? "연습 점수 · 실제 저장 없음" : training.completed ? "훈련 완료 · 저장됨" : "\(training.scores.last ?? 0)점 · 시도 저장됨").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("positionFeedback")
                            if training.completed {
                                if practice {
                                    Text("평균 \(training.average, specifier: "%.1f")점 · XP·날짜·피로 변화 없음")
                                    Button("다시 연습") { self.training = nil; load(reset: true) }
                                        .buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("practicePositionRetry")
                                } else { GamePanel(title: "포지션 훈련 결과", onBoard: true) {
                                    Text("평균 \(training.average, specifier: "%.1f")점 · XP +\(training.positionGainXP, specifier: "%.1f")").font(.headline).accessibilityIdentifier("positionXPGain")
                                    Text("숙련 \(training.before, specifier: "%.1f") → \(training.after, specifier: "%.1f") / 잔여 XP \(training.positionAfter.xp, specifier: "%.1f")").font(.subheadline).accessibilityIdentifier("positionGrowth")
                                    Text("피로 \(training.fatigue) → \(min(100, training.fatigue + 6)) · 오늘 행동 완료").font(.caption).accessibilityIdentifier("positionFatigue")
                                    Text("선택 위치만 성장 · 해당 위치로 출전하는 새 경기부터 반영").font(.caption).foregroundStyle(GameTheme.boardMuted)
                                    TrainingProjectFeedbackPanel(training: training)
                                    CareerProjectNextActions(player: player, calendar: calendar)
                                }
                                }
                            } else {
                                Button("다음 시도") { load(reset: true) }.buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("positionNextAttempt")
                            }
                        }
                    }
                    Button(practice ? "연습 메뉴로" : "훈련 화면으로") { dismiss() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("closePositionTraining")
                }.padding(12)
            }
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("포지션 훈련").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .onAppear { load(reset: true) }.onDisappear { cancelUnconfirmed() }
            .onChange(of: scenePhase) { _, value in if value != .active { cancelUnconfirmed() } }
    }
    private func moveButton(_ label: String, dx: Double, dy: Double, id: String) -> some View {
        Button(label) { x = min(0.95, max(0.05, x + dx)); y = min(0.95, max(0.05, y + dy)) }
            .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).disabled(errorMessage != nil).accessibilityIdentifier("positionMove-" + id)
    }
    private func adjustment(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).disabled(errorMessage != nil).accessibilityIdentifier("positionAdjust-" + id)
    }
}
