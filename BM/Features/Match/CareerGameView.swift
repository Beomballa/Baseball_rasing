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

    @State private var visualSnapshot: CareerMatch?
    @State private var presenting = false
    @State private var pulse: String?
    @State private var pulseAt = Date.distantPast

    private var inputLocked: Bool { clock.running || presenting || retrySave != nil }
    private func load() {
        do {
            record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            if pitchCode.isEmpty { pitchCode = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
        } catch { self.error = error.localizedDescription }
    }
    private func begin() {
        guard !presenting, attempt == nil, retrySave == nil, let record, let match = try? record.snapshot(), !match.completed else { return }
        let input: MatchInput = player.role == .pitcher ? .pitch : battingAction
        attempt = Attempt(revision: record.revision, input: input, pitchCode: pitchCode)
        let delivery = match.delivery(pitchCode: pitchCode)
        if player.role == .batter {
            scene.cancelDelivery()
            _ = scene.demonstrate(reduceMotion: reduced, flightDuration: delivery.duration, x: delivery.x, y: delivery.y, pitchCode: pitchCode)
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
            let previous = try record.snapshot()
            try CareerMatchStore.advance(player: player, state: calendar, record: record,
                                         revision: pending.attempt.revision, input: pending.attempt.input,
                                         pitchCode: pending.attempt.pitchCode, control: pending.control, in: context)
            retrySave = nil
            if let result = try record.snapshot().lastManual {
                visualSnapshot = previous; presenting = true
                let showResult: @MainActor () -> Void = {
                    presenting = false; visualSnapshot = nil
                    pulse = MatchPresentation.countPulse(result.outcome); pulseAt = Date()
                }
                if player.role == .pitcher {
                    let started = scene.demonstrate(reduceMotion: reduced, flightDuration: 1.35 * 145 / Double(result.speed),
                                          x: result.x, y: result.y, pitchCode: result.pitchCode ?? "four-seam",
                                          outcome: result.outcome, completion: showResult)
                    if !started { showResult() }
                } else {
                    scene.finishBat(action: result.action, outcome: result.outcome, reduced: reduced, completion: showResult)
                }
            }
        } catch { retrySave = pending; self.error = error.localizedDescription; scene.cancelDelivery() }
    }
    private func cancelInput() {
        clock.stop(); attempt = nil; presenting = false; visualSnapshot = nil; pulse = nil; scene.cancelDelivery()
    }
    private func advance(_ input: MatchInput) {
        guard !presenting, attempt == nil, retrySave == nil, let record else { return }
        do {
            try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision,
                                         input: input, pitchCode: pitchCode, in: context)
            _ = scene.demonstrate(reduceMotion: reduced)
        } catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private func controls(_ match: CareerMatch) -> some View {
        if let pending = retrySave {
            Text("직전 입력을 저장하지 못했습니다.").font(.caption)
            Button("같은 입력 다시 저장") { commit(pending) }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("retryGameInput")
        } else if record?.appearance == true {
            if player.role == .pitcher {
                HStack(spacing: 8) {
                    MatchGrip(code: pitchCode, hand: player.throwingHandRaw).frame(width: 44, height: 44)
                        .background(Color(hex: 0x102a3f)).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 1))
                        .gesture(DragGesture(minimumDistance: 15).onEnded { value in
                            guard !inputLocked else { return }
                            let pitches = player.pitches.sorted { $0.order < $1.order }
                            guard let index = pitches.firstIndex(where: { $0.code == pitchCode }), !pitches.isEmpty else { return }
                            pitchCode = pitches[(index + (value.translation.height < 0 ? 1 : pitches.count - 1)) % pitches.count].code
                        })
                    Picker("구종", selection: $pitchCode) {
                        ForEach(player.pitches.sorted { $0.order < $1.order }) { Text($0.name).tag($0.code) }
                    }.tint(GameTheme.gold).frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(inputLocked).accessibilityIdentifier("gamePitchPicker")
                    Text(player.throwingHandRaw == "left" ? "좌투" : "우투").font(.caption.bold())
                }
                let mastery = match.mastery[pitchCode] ?? 60
                MatchTimingGauge(phase: clock.phase, center: ManualMatchRules.releaseCenter,
                                 good: ManualMatchRules.goodWidth(mastery: mastery),
                                 perfect: ManualMatchRules.perfectWidth(mastery: mastery), label: "릴리스 · 숙련도 \(mastery.formatted(.number.precision(.fractionLength(1))))")
                    .accessibilityIdentifier("releaseGauge")
                Button(clock.running ? "지금 릴리스" : "투구 준비") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(presenting).accessibilityIdentifier(clock.running ? "gameRelease" : "gamePitch")
            } else {
                HStack {
                    ForEach([MatchInput.watch, .swing, .bunt], id: \.rawValue) { input in
                        Button(input.label) { battingAction = input }.buttonStyle(MatchPixelButtonStyle(selected: battingAction == input))
                            .disabled(clock.running || presenting).accessibilityIdentifier("gameInput-\(input.rawValue)")
                    }
                }
                MatchTimingGauge(phase: clock.phase, center: MatchDelivery.contactPhase,
                                 good: ManualMatchRules.timingWidth(contact: match.contact), perfect: 0.025, label: "공 도착 · 노란 구간에 타격")
                    .accessibilityIdentifier("battingTimingGauge")
                Button(clock.running ? (battingAction == .watch ? "공을 지켜보는 중" : "지금 \(battingAction.label)") : "투구 요청") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(presenting || (clock.running && battingAction == .watch))
                    .accessibilityIdentifier(clock.running ? "gameHit" : "requestGamePitch")
            }
        }
    }
    private func scoreHeader(_ match: CareerMatch, record: CareerMatchRecord) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(player.schoolName).lineLimit(1).minimumScaleFactor(0.65)
                Text("\(match.teamScore) : \(match.opponentScore)").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(GameTheme.gold)
                Text(schools.first { $0.id == record.opponentID }?.name ?? record.opponentID).lineLimit(1).minimumScaleFactor(0.65)
            }.font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                .accessibilityIdentifier("careerGameScore")
            HStack(spacing: 6) {
                Text("\(record.gameDate) · \(match.inningLabel)")
                ForEach(0..<3, id: \.self) { i in
                    Rectangle().fill(match.bases[i] ? GameTheme.gold : Color(hex: 0x436178))
                        .frame(width: 6, height: 6).rotationEffect(.degrees(45)).accessibilityHidden(true)
                }
                Text(match.bases.contains(true) ? "주자 \(match.bases.enumerated().filter { $0.element }.map { String($0.offset + 1) }.joined(separator: ","))루" : "주자 없음")
            }.font(.system(size: 10, design: .monospaced))
        }.frame(height: 44).frame(maxWidth: .infinity)
            .background(Color(hex: 0x102a3f)).overlay(Rectangle().strokeBorder(Color(hex: 0x7695a6), lineWidth: 1))
    }
    private func arena(_ match: CareerMatch, field: CGSize) -> some View {
        VStack(spacing: 0) {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .frame(width: field.width, height: field.height)
                .accessibilityLabel(player.role == .batter ? "도트 타자 경기장" : "도트 투수 경기장")
                .accessibilityIdentifier("careerMatchField")
                .overlay {
                    if player.role == .batter && !match.completed {
                        BattingAimZone(x: $aimX, y: $aimY, locked: retrySave != nil || presenting)
                            .frame(width: field.width * 0.16, height: field.height * 0.22)
                            .position(x: field.width * 0.5, y: field.height * 0.68)
                    } else if player.role == .pitcher && !match.completed {
                        let target = match.delivery(pitchCode: pitchCode)
                        BattingAimZone(x: .constant(target.x), y: .constant(target.y), locked: true)
                            .frame(width: field.width * 0.22, height: field.height * 0.24)
                            .position(x: field.width * 0.54, y: field.height * 0.43)
                            .allowsHitTesting(false)
                            .accessibilityLabel("자동 투구 목표")
                            .accessibilityIdentifier("pitchingTargetZone")
                    }
                }
                .frame(maxWidth: .infinity).background(Color(hex: 0x102a3f))
            MatchScoreStrip(match: match, pitchCount: player.role == .pitcher ? match.line.pitches : nil, pulse: pulse, pulseAt: pulseAt)
        }.overlay(Rectangle().strokeBorder(Color(hex: 0x7695a6), lineWidth: 1))
    }
    private func results(_ match: CareerMatch, record: CareerMatchRecord) -> some View {
        VStack(spacing: 12) {
            GamePanel(title: "경기 결과 저장 완료") {
                Text(match.teamScore == match.opponentScore ? "무승부" : (match.teamScore > match.opponentScore ? "승리" : "패배"))
                    .font(.title2.bold()).accessibilityIdentifier("careerGameFinished")
                Text(record.appearance ? (player.role == .batter
                    ? "\(match.line.atBats)타수 \(match.line.hits)안타 · HR \(match.line.homeRuns) · BB \(match.line.walks) · K \(match.line.strikeouts)"
                    : "\(match.line.pitchingOuts / 3).\(match.line.pitchingOuts % 3)이닝 · \(match.line.pitches)구 · K \(match.line.pitchingStrikeouts) · 실점 \(match.line.runsAllowed)") : "비등판 · 개인 기록/피로 변화 없음")
                Text("피로 \(record.fatigueBefore) → \(record.fatigueAfter)")
                if let play = match.lastFieldPlay {
                    Text("최근 내 \(play.ownDefense ? "수비" : "주루") · 1루 \(play.safe ? "세이프" : "아웃")")
                    Text("주자 \(play.runnerTime, specifier: "%.2f")초 / 송구 \(play.ballTime, specifier: "%.2f")초").font(.caption)
                        .accessibilityIdentifier("gameFieldResult")
                }
                Text("홈에서 다음 날로 진행할 수 있습니다.").font(.caption)
            }.foregroundStyle(GameTheme.navy)
            Button("선수 홈으로") { dismiss() }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("gameReturnHome")
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 6) {
                    if let record, let savedMatch = try? record.snapshot() {
                        let match = visualSnapshot ?? savedMatch
                        scoreHeader(match, record: record)
                        arena(match, field: MatchPresentation.fieldSize(available: CGSize(width: geometry.size.width - 16, height: geometry.size.height), role: player.role))
                        Text(match.lastManual.map { "\($0.grade) · \($0.outcome)" }
                             ?? (match.completed ? match.message : player.role == .batter ? "조준 → 투구 요청 → 타격" : "그립 선택 → 투구 준비 → 릴리스"))
                            .font(.system(.caption, design: .monospaced, weight: .bold)).frame(minHeight: 20)
                            .accessibilityIdentifier("careerGameMessage")
                        if match.completed { results(match, record: record) }
                        else { VStack(spacing: 6) { controls(match) } }
                    } else {
                        Text(error ?? "경기 불러오는 중")
                        Button("다시 확인") { load() }.buttonStyle(MatchPixelButtonStyle())
                    }
                }.padding(8).frame(maxWidth: .infinity)
            }
        }
        .background(Color(hex: 0x18334b)).foregroundStyle(Color(hex: 0xeee9cd))
        .navigationTitle(player.role == .batter ? "타자 경기" : "투수 경기").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: 0x18334b), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let record, !record.completed {
                    Button(record.appearance ? "자동" : "팀 진행") { confirmAutomatic = true }
                        .font(.caption.bold()).frame(minWidth: 44, minHeight: 44)
                        .disabled(inputLocked).accessibilityIdentifier("gameAutomatic")
                }
            }
        }
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.kit, role: player.role); load() }
        .task(id: pulseAt) {
            guard pulse != nil else { return }
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            if !Task.isCancelled { pulse = nil }
        }
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
