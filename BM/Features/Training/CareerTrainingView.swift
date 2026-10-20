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
    @State private var x = 0.5
    @State private var y = 0.5
    @State private var clock = MatchInputClock()
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 320))
    @State private var errorMessage: String?
    @State private var retryInput: TrainingInput?
    @State private var retryRevision: Int?

    private var isPitcher: Bool { player.role == .pitcher }
    private var title: String { isPitcher ? "구종 훈련" : "컨택 훈련" }
    private var pitchName: String { player.pitches.first { $0.code == (training?.pitchCode ?? code) }?.name ?? "컨택" }
    private func load() {
        do {
            record = try CareerTrainingStore.record(player: player, in: context)
            training = try record?.snapshot()
            if code.isEmpty { code = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
        } catch { errorMessage = error.localizedDescription }
    }
    private func start() {
        do {
            record = try CareerTrainingStore.start(player: player, state: calendar, pitchCode: isPitcher ? code : nil, in: context)
            training = try record?.snapshot()
        } catch { errorMessage = error.localizedDescription }
    }
    private func beginAttempt() {
        guard let training, !training.completed, retryInput == nil else { return }
        scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, role: player.role)
        scene.demonstrate(reduceMotion: reduced, flightDuration: 1.6, x: training.targets[training.scores.count].x,
                          y: training.targets[training.scores.count].y, pitchCode: training.pitchCode ?? "four-seam")
        clock.start(windup: 0.35, duration: 1.6) {
            submit(isPitcher ? TrainingInput(release: 0) : TrainingInput())
        }
    }
    private func submit(_ input: TrainingInput) {
        clock.stop(); scene.cancelDelivery()
        guard let record else { return }
        retryInput = input; retryRevision = record.revision
        saveAttempt()
    }
    private func saveAttempt() {
        guard let record, let input = retryInput, let revision = retryRevision else { return }
        do {
            try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context)
            training = try record.snapshot(); retryInput = nil; retryRevision = nil; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func cancelUncommitted() { clock.stop(); scene.cancelDelivery() }

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
                    arena(height: MatchPresentation.fieldSize(available: CGSize(width: geometry.size.width - 32, height: geometry.size.height), role: player.role).height)
                    if let training {
                        MatchTimingGauge(phase: clock.phase, center: isPitcher ? ManualMatchRules.releaseCenter : MatchDelivery.contactPhase,
                                         good: isPitcher ? ManualMatchRules.goodWidth(mastery: training.before) : ManualMatchRules.timingWidth(contact: training.before),
                                         perfect: isPitcher ? ManualMatchRules.perfectWidth(mastery: training.before) : 0.025,
                                         label: isPitcher ? "릴리스 · 노란 구간에 맞춰 던지기" : "컨택 · 목표를 조준하고 타격")
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { index in
                                Text(index < training.scores.count ? "\(training.scores[index])" : "·")
                                    .font(.caption.monospaced().bold()).frame(maxWidth: .infinity, minHeight: 25)
                                    .background(index < training.scores.count ? GameTheme.green : Color(hex: 0x203e57))
                            }
                        }.accessibilityIdentifier("trainingScores")
                        Button(clock.running ? (isPitcher ? "던지기!" : "타격!") : "\(training.scores.count + 1)번째 시도 시작") {
                            if clock.running {
                                submit(isPitcher ? TrainingInput(release: clock.phase) : TrainingInput(x: x, y: y, timing: clock.phase))
                            } else { beginAttempt() }
                        }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                            .accessibilityIdentifier("trainingAttempt")
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
            if !isPitcher, let training, !training.completed {
                let target = training.targets[training.scores.count]
                ZStack {
                    BattingAimZone(x: $x, y: $y, locked: retryInput != nil)
                    GeometryReader { geometry in
                        Rectangle().strokeBorder(Color(hex: 0x82e6b2), lineWidth: 3).frame(width: 18, height: 18)
                            .position(x: geometry.size.width * target.x, y: geometry.size.height * target.y)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }.frame(width: height * 0.55, height: height * 0.55)
            }
            if isPitcher {
                MatchGrip(code: training?.pitchCode ?? code, hand: player.throwingHandRaw)
                    .frame(width: 74, height: 74).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }.frame(width: height * (isPitcher ? 1219.0 / 1290 : 1), height: height).clipped()
            .overlay(Rectangle().strokeBorder(GameTheme.gold.opacity(0.5), lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("trainingField")
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
