import SwiftUI
import SwiftData
import SpriteKit

struct CareerGameView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let schools: [School]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    private struct Attempt {
        let revision: Int
        let input: MatchInput
        let pitchCode: String
    }
    private struct PendingSave {
        let attempt: Attempt
        let control: ManualMatchInput
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = MatchInputClock()
    @State private var attempt: Attempt?
    @State private var retrySave: PendingSave?
    @State private var battingAction = MatchInput.swing
    @State private var aimX = 0.5
    @State private var aimY = 0.5
    @State private var record: CareerMatchRecord?
    @State private var error: String?
    @State private var pitchCode = ""
    @State private var confirmAutomatic = false
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 400))

    private func updateBoard() {
        guard let match = try? record?.snapshot() else { return }
        scene.updateScoreboard("BM | \(match.teamScore):\(match.opponentScore) | B\(match.balls) S\(match.strikes) O\(match.outs)")
    }
    private func load() {
        do {
            record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            updateBoard()
            if pitchCode.isEmpty { pitchCode = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
        } catch { self.error = error.localizedDescription }
    }
    private func begin() {
        guard attempt == nil, retrySave == nil, let record, let match = try? record.snapshot(), !match.completed else { return }
        let input: MatchInput = player.role == .pitcher ? .pitch : battingAction
        attempt = Attempt(revision: record.revision, input: input, pitchCode: pitchCode)
        let delivery = match.delivery(pitchCode: pitchCode)
        if player.role == .batter {
            scene.cancelDelivery()
            _ = scene.demonstrate(reduceMotion: reduced, flightDuration: delivery.duration, x: delivery.x, y: delivery.y)
        }
        clock.start(windup: player.role == .batter ? MatchDelivery.windup : 0,
                    duration: player.role == .batter ? delivery.duration : 1.8) { resolve(timeout: true) }
    }
    private func resolve(timeout: Bool = false) {
        guard let attempt else { return }
        let control = player.role == .pitcher ? ManualMatchInput(release: timeout ? 0 : clock.phase)
            : ManualMatchInput(x: aimX, y: aimY, timing: timeout || attempt.input == .watch ? nil : clock.phase)
        self.attempt = nil; clock.stop()
        commit(PendingSave(attempt: attempt, control: control))
    }
    private func commit(_ pending: PendingSave) {
        guard let record else { return }
        guard !record.completed, record.revision == pending.attempt.revision else { retrySave = nil; return }
        do {
            try CareerMatchStore.advance(player: player, state: calendar, record: record,
                                         revision: pending.attempt.revision, input: pending.attempt.input,
                                         pitchCode: pending.attempt.pitchCode, control: pending.control, in: context)
            retrySave = nil; updateBoard()
            if player.role == .pitcher, let result = try record.snapshot().lastManual {
                scene.cancelDelivery()
                _ = scene.demonstrate(reduceMotion: reduced, flightDuration: 1.35 * 145 / Double(result.speed), x: result.x, y: result.y)
            }
        } catch { retrySave = pending; self.error = error.localizedDescription; scene.cancelDelivery() }
    }
    private func cancelInput() {
        clock.stop(); attempt = nil; scene.cancelDelivery()
    }
    private func advance(_ input: MatchInput) {
        guard attempt == nil, retrySave == nil, let record else { return }
        do {
            try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision,
                                         input: input, pitchCode: pitchCode, in: context)
            updateBoard()
            _ = scene.demonstrate(reduceMotion: reduced)
        } catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private func controls(_ match: CareerMatch) -> some View {
        if let pending = retrySave {
            Text("직전 입력을 저장하지 못했습니다.").font(.caption)
            Button("같은 입력 다시 저장") { commit(pending) }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("retryGameInput")
        } else if record?.appearance == true {
            if player.role == .pitcher {
                Picker("구종", selection: $pitchCode) {
                    ForEach(player.pitches.sorted { $0.order < $1.order }) { Text($0.name).tag($0.code) }
                }.disabled(clock.running).accessibilityIdentifier("gamePitchPicker")
                let mastery = match.mastery[pitchCode] ?? 60
                MatchTimingGauge(phase: clock.phase, center: ManualMatchRules.releaseCenter,
                                 good: ManualMatchRules.goodWidth(mastery: mastery),
                                 perfect: ManualMatchRules.perfectWidth(mastery: mastery), label: "릴리스 · 숙련도 \(mastery.formatted(.number.precision(.fractionLength(1))))")
                    .accessibilityIdentifier("releaseGauge")
                Button(clock.running ? "지금 릴리스" : "투구 준비") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(GameButtonStyle()).accessibilityIdentifier(clock.running ? "gameRelease" : "gamePitch")
            } else {
                HStack {
                    ForEach([MatchInput.watch, .swing, .bunt], id: \.rawValue) { input in
                        Button(input.label) { battingAction = input }.buttonStyle(GameButtonStyle(secondary: battingAction != input))
                            .disabled(clock.running).accessibilityIdentifier("gameInput-\(input.rawValue)")
                    }
                }
                MatchTimingGauge(phase: clock.phase, center: MatchDelivery.contactPhase,
                                 good: ManualMatchRules.timingWidth(contact: match.contact), perfect: 0.025, label: "공 도착 · 노란 구간에 타격")
                    .accessibilityIdentifier("battingTimingGauge")
                Button(clock.running ? (battingAction == .watch ? "공을 지켜보는 중" : "지금 \(battingAction.label)") : "투구 요청") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(GameButtonStyle()).disabled(clock.running && battingAction == .watch)
                    .accessibilityIdentifier(clock.running ? "gameHit" : "requestGamePitch")
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let record, let match = try? record.snapshot() {
                    GamePanel(title: "\(record.gameDate) · \(match.inningLabel)") {
                        Text("\(player.schoolName)  \(match.teamScore) : \(match.opponentScore)  \(schools.first { $0.id == record.opponentID }?.name ?? record.opponentID)")
                            .font(.headline.monospaced()).accessibilityIdentifier("careerGameScore")
                        Text("B \(match.balls)   S \(match.strikes)   O \(match.outs) · 주자 \(match.bases.enumerated().filter { $0.element }.map { String($0.offset + 1) }.joined(separator: ","))")
                            .font(.subheadline.monospaced()).accessibilityIdentifier("careerGameCount")
                    }
                    SpriteView(scene: scene).aspectRatio(0.8, contentMode: .fit).frame(maxHeight: 280)
                        .overlay {
                            if player.role == .batter && !match.completed {
                                GeometryReader { size in
                                    BattingAimZone(x: $aimX, y: $aimY, locked: retrySave != nil)
                                        .frame(width: size.size.height * 0.256, height: size.size.height * 0.2)
                                        .position(x: size.size.width / 2, y: size.size.height * 0.8)
                                }
                            }
                        }
                        .overlay(Rectangle().strokeBorder(GameTheme.navy, lineWidth: 3))
                    Text(match.lastManual.map { "\($0.grade) · \($0.outcome) · \($0.speed) km/h" }
                         ?? (match.completed ? match.message : player.role == .batter ? "조준 후 투구 요청" : "구종 선택 후 투구 준비"))
                        .font(.headline).accessibilityIdentifier("careerGameMessage")
                    if match.completed {
                        GamePanel(title: "경기 결과 저장 완료") {
                            Text(match.teamScore == match.opponentScore ? "무승부" : (match.teamScore > match.opponentScore ? "승리" : "패배"))
                                .font(.title2.bold()).accessibilityIdentifier("careerGameFinished")
                            Text(record.appearance ? (player.role == .batter
                                ? "\(match.line.atBats)타수 \(match.line.hits)안타 · HR \(match.line.homeRuns) · BB \(match.line.walks) · K \(match.line.strikeouts)"
                                : "\(match.line.pitchingOuts / 3).\(match.line.pitchingOuts % 3)이닝 · \(match.line.pitches)구 · K \(match.line.pitchingStrikeouts) · 실점 \(match.line.runsAllowed)") : "비등판 · 개인 기록/피로 변화 없음")
                            Text("피로 \(record.fatigueBefore) → \(record.fatigueAfter)")
                            Text("홈에서 다음 날로 진행할 수 있습니다.").font(.caption)
                        }
                        Button("선수 홈으로") { dismiss() }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("gameReturnHome")
                    } else {
                        controls(match)
                        Button(record.appearance ? "남은 경기 자동 마무리" : "비등판 팀 경기 진행") { confirmAutomatic = true }
                            .buttonStyle(GameButtonStyle(secondary: true)).disabled(clock.running || retrySave != nil).accessibilityIdentifier("gameAutomatic")
                        Text(player.role == .batter ? "공마다 저장 · 무입력은 지켜보기" : "공마다 저장 · 시간 초과는 제구 실패")
                            .font(.caption).foregroundStyle(GameTheme.muted)
                    }
                } else {
                    Text(error ?? "경기 불러오는 중")
                    Button("다시 확인") { load() }.buttonStyle(GameButtonStyle())
                }
            }.padding(16)
        }
        .background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("공식 일정 경기").navigationBarTitleDisplayMode(.inline)
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.kit); load() }
        .onDisappear { cancelInput() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelInput() } }
        .confirmationDialog("남은 경기를 자동으로 진행할까요?", isPresented: $confirmAutomatic, titleVisibility: .visible) {
            Button("진행하고 결과 저장") { advance(.automatic) }
        } message: { Text("현재 카운트·주자에서 이어서 진행합니다. 실제 출전 성적과 피로를 반영하며 취소할 수 없습니다.") }
        .alert("경기를 저장하지 못했습니다", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }
}
