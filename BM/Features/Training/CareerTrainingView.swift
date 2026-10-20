import SwiftUI
import SwiftData
import SpriteKit

struct CareerTrainingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduced
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @State private var record: CareerTrainingRecord?
    @State private var training: CareerTraining?
    @State private var code = ""
    @State private var kind = TrainingKind.contact
    @State private var force = 70.0
    @State private var angle = 35.0
    @State private var judging = false
    @State private var lastDistance: Double?
    @State private var x = 0.5
    @State private var y = 0.5
    @State private var clock = MatchInputClock()
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 320))
    @State private var errorMessage: String?
    @State private var retryInput: TrainingInput?
    @State private var retryRevision: Int?

    private var isPitcher: Bool { player.role == .pitcher }
    private var selectedKind: TrainingKind { training?.selectedKind ?? (isPitcher ? .pitch : kind) }
    private var title: String { selectedKind.label + " 훈련" }
    private var pitchName: String { player.pitches.first { $0.code == (training?.pitchCode ?? code) }?.name ?? selectedKind.label }
    private func load() {
        do {
            record = try CareerTrainingStore.record(player: player, in: context)
            training = try record?.snapshot()
            if code.isEmpty { code = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
        } catch { errorMessage = error.localizedDescription }
    }
    private func start() {
        do {
            record = try CareerTrainingStore.start(player: player, state: calendar, pitchCode: isPitcher ? code : nil, kind: selectedKind, in: context)
            training = try record?.snapshot()
        } catch { errorMessage = error.localizedDescription }
    }
    private func beginAttempt() {
        guard let training, !training.completed, retryInput == nil else { return }
        if selectedKind == .discipline { judging = true; return }
        scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, role: player.role)
        scene.demonstrate(reduceMotion: reduced, flightDuration: 1.6, x: training.targets[training.scores.count].x,
                          y: training.targets[training.scores.count].y, pitchCode: training.pitchCode ?? "four-seam")
        clock.start(windup: 0.35, duration: 1.6) {
            submit(isPitcher ? TrainingInput(release: 0) : TrainingInput())
        }
    }
    private func submit(_ input: TrainingInput) {
        clock.stop(); scene.cancelDelivery(); judging = false
        guard let record else { return }
        retryInput = input; retryRevision = record.revision
        saveAttempt()
    }
    private func saveAttempt() {
        guard let record, let input = retryInput, let revision = retryRevision else { return }
        do {
            try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context)
            training = try record.snapshot()
            if let force = input.force, let angle = input.angle { lastDistance = TrainingRules.distance(force: force, angle: angle) }
            retryInput = nil; retryRevision = nil; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func cancelUncommitted() { clock.stop(); scene.cancelDelivery(); judging = false }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                HStack {
                    Text(title).bold()
                    Spacer()
                    Text(training.map { "\($0.scores.count) / 5" } ?? "READY").monospacedDigit()
                }.accessibilityIdentifier("trainingProgress")
                if let training, training.completed {
                    result(training)
                } else {
                    if isPitcher {
                        if training == nil {
                            Picker("훈련할 구종", selection: $code) {
                                ForEach(player.pitches.sorted { $0.order < $1.order }) { Text("\($0.name) · \($0.mastery, specifier: "%.1f")").tag($0.code) }
                            }.pickerStyle(.menu).tint(GameTheme.gold).accessibilityIdentifier("trainingPitchPicker")
                        } else { Text(pitchName).foregroundStyle(GameTheme.gold).bold() }
                    }
                    if !isPitcher, training == nil {
                        Picker("훈련 능력치", selection: $kind) {
                            ForEach([TrainingKind.contact, .power, .discipline], id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("trainingKindPicker")
                    }
                    arena(height: MatchPresentation.fieldSize(available: CGSize(width: geometry.size.width - 32, height: geometry.size.height - (selectedKind == .power ? 100 : selectedKind == .discipline ? 50 : 0)), role: player.role).height)
                    if let training {
                        if selectedKind == .power {
                            powerControls(training)
                        } else if selectedKind == .discipline {
                            Text(judging ? "존 안이면 스트라이크 · 밖이면 볼" : "공 보기를 누르고 존 안팎을 판단하세요").font(.caption)
                        } else {
                            MatchTimingGauge(phase: clock.phase, center: isPitcher ? ManualMatchRules.releaseCenter : MatchDelivery.contactPhase,
                                             good: isPitcher ? ManualMatchRules.goodWidth(mastery: training.before) : ManualMatchRules.timingWidth(contact: training.before),
                                             perfect: isPitcher ? ManualMatchRules.perfectWidth(mastery: training.before) : 0.025,
                                             label: isPitcher ? "릴리스 · 노란 구간에 맞춰 던지기" : "컨택 · 목표를 조준하고 타격")
                        }
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { index in
                                Text(index < training.scores.count ? "\(training.scores[index])" : "·")
                                    .font(.caption.monospaced().bold()).frame(maxWidth: .infinity, minHeight: 25)
                                    .background(index < training.scores.count ? GameTheme.green : Color(hex: 0x203e57))
                            }
                        }.accessibilityIdentifier("trainingScores")
                        if selectedKind == .discipline {
                            if judging {
                                HStack {
                                    Button("볼") { submit(TrainingInput(calledStrike: false)) }
                                        .accessibilityIdentifier("trainingCallBall")
                                    Button("스트라이크") { submit(TrainingInput(calledStrike: true)) }
                                        .accessibilityIdentifier("trainingCallStrike")
                                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                            } else {
                                Button("공 보기 · \(training.scores.count + 1)/5") { beginAttempt() }
                                    .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                                    .accessibilityIdentifier("trainingAttempt")
                            }
                        } else if selectedKind == .power {
                            Button("티배팅!") { submit(TrainingInput(force: force, angle: angle)) }
                                .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                                .accessibilityIdentifier("trainingAttempt")
                        } else {
                            Button(clock.running ? (isPitcher ? "던지기!" : "타격!") : "\(training.scores.count + 1)번째 시도 시작") {
                                if clock.running {
                                    submit(isPitcher ? TrainingInput(release: clock.phase) : TrainingInput(x: x, y: y, timing: clock.phase))
                                } else { beginAttempt() }
                            }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                                .accessibilityIdentifier("trainingAttempt")
                        }
                    } else {
                        Text("5회 도전 · 완료 시 피로 +6 / 오늘 행동 사용").font(.caption)
                        Button("훈련 시작") { start() }.buttonStyle(MatchPixelButtonStyle(primary: true))
                            .disabled(errorMessage != nil).accessibilityIdentifier("startTraining")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("trainingError")
                    Button(retryInput == nil ? "기록 다시 확인" : "같은 결과 저장 재시도") {
                        if retryInput == nil { self.errorMessage = nil; load() } else { saveAttempt() }
                    }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryTrainingSave")
                }
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(GameTheme.navy).foregroundStyle(Color(hex: 0xf3edcf))
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(GameTheme.navy, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, role: player.role)
            load()
        }
        .onDisappear { cancelUncommitted() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelUncommitted() } }
    }
    private func arena(height: CGFloat) -> some View {
        ZStack {
            SpriteView(scene: scene).allowsHitTesting(false)
            if selectedKind == .contact, let training, !training.completed {
                let target = training.targets[training.scores.count]
                ZStack {
                    BattingAimZone(x: $x, y: $y, locked: retryInput != nil)
                    GeometryReader { geometry in
                        Rectangle().strokeBorder(Color(hex: 0x82e6b2), lineWidth: 3).frame(width: 18, height: 18)
                            .position(x: geometry.size.width * target.x, y: geometry.size.height * target.y)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }.frame(width: height * 0.55, height: height * 0.55)
            }
            if selectedKind == .discipline, let training, !training.completed {
                GeometryReader { geometry in
                    let target = training.targets[training.scores.count]
                    ZStack {
                        Rectangle().fill(GameTheme.navy.opacity(0.7))
                        Rectangle().strokeBorder(Color(hex: 0xf3edcf), lineWidth: 3)
                            .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6)
                        if judging {
                            Rectangle().fill(GameTheme.gold).frame(width: 12, height: 12)
                                .position(x: geometry.size.width * target.x, y: geometry.size.height * target.y)
                        }
                    }
                }.frame(width: height * 0.7, height: height * 0.7)
                    .accessibilityElement(children: .ignore).accessibilityLabel(judging ? "투구 위치" : "스트라이크 존")
                    .accessibilityValue(judging ? "가로 \(Int(training.targets[training.scores.count].x * 100)), 세로 \(Int(training.targets[training.scores.count].y * 100))" : "공 보기 대기")
            }
            if selectedKind == .power, let training, !training.completed {
                VStack {
                    Text("목표 \(TrainingRules.powerTarget(training.scores.count), specifier: "%.0f")m").bold()
                        .padding(8).background(GameTheme.navy).accessibilityIdentifier("powerTarget")
                    Spacer()
                    if let lastDistance {
                        Text("직전 \(lastDistance, specifier: "%.1f")m · \(training.scores.last ?? 0)점")
                            .font(.caption.bold()).padding(8).background(GameTheme.navy)
                    }
                }.padding(8)
            }
            if isPitcher {
                MatchGrip(code: training?.pitchCode ?? code, hand: player.throwingHandRaw)
                    .frame(width: 74, height: 74).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }.frame(width: height * (isPitcher ? 1219.0 / 1290 : 1), height: height).clipped()
            .overlay(Rectangle().strokeBorder(GameTheme.gold.opacity(0.5), lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("trainingField")
    }
    private func powerControls(_ training: CareerTraining) -> some View {
        HStack(spacing: 16) {
            adjustment("힘", value: $force, range: 0...100, suffix: "%", identifier: "powerForce")
            adjustment("각도", value: $angle, range: 15...55, suffix: "°", identifier: "powerAngle")
        }.disabled(retryInput != nil)
    }
    private func adjustment(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, identifier: String) -> some View {
        VStack(spacing: 6) {
            Text("\(label) \(Int(value.wrappedValue))\(suffix)").font(.caption.bold()).monospacedDigit()
            HStack(spacing: 8) {
                Button("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 5) }
                    .accessibilityLabel(label + " 줄이기").accessibilityIdentifier(identifier + "Down")
                    .disabled(value.wrappedValue <= range.lowerBound)
                Button("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 5) }
                    .accessibilityLabel(label + " 늘리기").accessibilityIdentifier(identifier + "Up")
                    .disabled(value.wrappedValue >= range.upperBound)
            }.buttonStyle(MatchPixelButtonStyle())
        }
    }
    private func result(_ value: CareerTraining) -> some View {
        VStack(spacing: 20) {
            PixelPlayer(appearance: player.appearance).frame(width: 64, height: 88)
            Text("TRAINING CLEAR").font(.title2.monospaced().bold()).foregroundStyle(GameTheme.gold)
            Text("\(pitchName) · 평균 \(value.average, specifier: "%.1f")점")
            Text("\(value.before, specifier: "%.1f") → \(value.after, specifier: "%.1f")")
                .font(.largeTitle.monospaced().bold()).accessibilityIdentifier("trainingGrowth")
            Text("성장 +\(value.gain, specifier: "%.1f") · 피로 \(value.fatigue) → \(min(100, value.fatigue + 6))")
            Text("보상 저장 완료 · 다음 경기에 반영").font(.caption)
                .accessibilityIdentifier("trainingCompleted")
            Text("위의 뒤로 버튼으로 선수 홈에 돌아갈 수 있습니다.").font(.caption)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
