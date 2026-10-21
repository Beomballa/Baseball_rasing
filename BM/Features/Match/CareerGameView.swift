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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chromeHeights: [String: CGFloat] = [:]
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
    @State private var resultReplayPlay:MatchDetailedPlay?
    @State private var resultReplayID=0
    @State private var animateResultReplay=false
    @State private var replay: MatchDetailedPlay?
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
        if player.role == .pitcher { scene.preparePitch(phase: 0, reduced: reduced) }
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
            let updated=try record.snapshot()
            let added=Array((updated.fieldPlays ?? []).dropFirst(previous.fieldPlays?.count ?? 0))
            let fieldPlay=added.first { $0.ownBatter || $0.ownParticipation || (player.role == .pitcher && $0.half == previous.half) }
            if let result = updated.lastManual {
                visualSnapshot = previous; presenting = true
                let showResult: @MainActor () -> Void = {
                    if let fieldPlay {
                        replay=fieldPlay
                    } else { presenting = false; visualSnapshot = nil }
                    pulse = MatchPresentation.countPulse(result.outcome); pulseAt = Date()
                }
                if player.role == .pitcher {
                    let started = scene.demonstrate(reduceMotion: reduced, flightDuration: previous.delivery(pitchCode: result.pitchCode).duration,
                                          x: result.x, y: result.y, pitchCode: result.pitchCode ?? "four-seam",
                                          outcome: result.outcome, preparedRelease: true, completion: showResult)
                    if !started { showResult() }
                } else {
                    // Saved fair contact drives the barrel motion; localized multi-base labels are not contact flags.
                    scene.finishBat(action: result.action, outcome: added.contains(where: \.ownBatter) ? "안타" : result.outcome,
                                    reduced: reduced, completion: showResult)
                }
            }
        } catch { retrySave = pending; self.error = error.localizedDescription; scene.cancelDelivery() }
    }
    private func cancelInput() {
        clock.stop(); attempt = nil; presenting = false; visualSnapshot = nil; replay=nil;resultReplayPlay=nil;animateResultReplay=false;pulse = nil; scene.cancelDelivery()
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
            Button("같은 입력 다시 저장") { commit(pending) }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("retryGameInput")
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
                        .background(GameTheme.boardPanel)
                        .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                        .disabled(inputLocked).accessibilityIdentifier("gamePitchPicker")
                    Text(player.throwingHandRaw == "left" ? "좌투" : "우투").font(.caption.bold())
                    .accessibilityLabel("투구 손 " + (player.throwingHandRaw == "left" ? "왼손" : "오른손"))
                }
                let mastery = match.mastery[pitchCode] ?? 60
                MatchTimingGauge(phase: clock.phase, center: ManualMatchRules.releaseCenter,
                                 good: match.releaseGoodWidth(mastery: mastery),
                                 perfect: match.releasePerfectWidth(mastery: mastery), label: presenting ? "릴리스 확정 · 공 비행 중" : clock.running ? "팔 준비 중 · 노란 구간에 릴리스" : "릴리스 · 숙련도 \(mastery.formatted(.number.precision(.fractionLength(1))))")
                    .accessibilityIdentifier("releaseGauge")
                Button(clock.running ? "지금 릴리스" : "투구 준비") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(presenting).accessibilityIdentifier(clock.running ? "gameRelease" : "gamePitch")
            } else {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    ForEach([MatchInput.watch, .swing, .bunt], id: \.rawValue) { input in
                        Button(input.label) { battingAction = input }.buttonStyle(MatchPixelButtonStyle(selected: battingAction == input))
                            .disabled(clock.running || presenting).accessibilityIdentifier("gameInput-\(input.rawValue)")
                    }
                }
                MatchTimingGauge(phase: clock.phase, center: MatchDelivery.contactPhase,
                                 good: ManualMatchRules.timingWidth(contact: match.contact) * match.executionFactor, perfect: 0.025, label: "공 도착 · 노란 구간에 타격")
                    .accessibilityIdentifier("battingTimingGauge")
                Button(clock.running ? (battingAction == .watch ? "공을 지켜보는 중" : "지금 \(battingAction.label)") : "투구 요청") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(presenting || (clock.running && battingAction == .watch))
                    .accessibilityIdentifier(clock.running ? "gameHit" : "requestGamePitch")
            }
        }
    }
    private func scoreHeader(_ match: CareerMatch, record: CareerMatchRecord) -> some View {
        VStack(spacing: 4) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Text(player.schoolName).lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.65)
                Text("\(match.teamScore) : \(match.opponentScore)").font(.system(.title3, design: .monospaced, weight: .bold)).foregroundStyle(GameTheme.gold)
                Text(schools.first { $0.id == record.opponentID }?.name ?? record.opponentID).lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.65)
            }.font(.system(.subheadline, design: .monospaced, weight: .bold)).frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                .accessibilityIdentifier("careerGameScore")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(record.gameDate)
                    Text(match.inningLabel)
                }
                VStack(spacing: 3) { Text(record.gameDate); Text(match.inningLabel) }
            }.font(.caption2.monospaced())
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle().fill(match.bases[i] ? GameTheme.gold : Color(hex: 0x436178))
                        .frame(width: 6, height: 6).rotationEffect(.degrees(45)).accessibilityHidden(true)
                }
                Text(match.bases.contains(true) ? "주자 \(match.bases.enumerated().filter { $0.element }.map { String($0.offset + 1) }.joined(separator: ","))루" : "주자 없음")
            }.font(.caption2.monospaced())
        }.padding(6).frame(maxWidth: .infinity)
            .background(Color(hex: 0x102a3f)).overlay(Rectangle().strokeBorder(Color(hex: 0x7695a6), lineWidth: 1))
    }
    private func arena(_ match: CareerMatch, field: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                if let replay {
                    DetailedFieldReplayBoard(play:replay,appearance:player.appearance) {
                        self.replay=nil;presenting=false;visualSnapshot=nil
                    }.transition(.opacity)
                }
            }
                .frame(width: field.width, height: field.height)
                .accessibilityLabel(player.role == .batter ? "도트 타자 경기장" : "도트 투수 경기장")
                .accessibilityIdentifier("careerMatchField")
                .overlay {
                    if replay != nil { EmptyView() }
                    else if player.role == .batter && !match.completed {
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
        }.overlay(Rectangle().strokeBorder(Color(hex: 0x7695a6), lineWidth: 1))
    }
    private func results(_ match: CareerMatch, record: CareerMatchRecord) -> some View {
        let summary = MatchResultSummary(match: match, fatigueBefore: record.fatigueBefore, fatigueAfter: record.fatigueAfter)
        return VStack(spacing: 10) {
            GamePanel(title: "FINAL · 팀 경기 결과", onBoard: true) {
                HStack(spacing: 12) {
                    PixelPlayer(appearance: player.appearance).frame(width: 36, height: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.outcome).font(.system(.title, design: .monospaced, weight: .heavy))
                            .foregroundStyle(GameTheme.gold).accessibilityIdentifier("careerGameFinished")
                        Text("\(player.name) #\(player.jerseyNumber)").font(.subheadline.bold())
                    }
                }
                Text("결과 저장 완료").font(.caption.bold()).foregroundStyle(GameTheme.growth)
                    .accessibilityIdentifier("gameResultSaved")
            }
            GamePanel(title: player.role == .batter ? "타자 경기 기록" : "투수 경기 기록", onBoard: true) {
                if !record.appearance {
                    Text("비등판 · 팀 경기 결과").font(.headline).accessibilityIdentifier("gameResultNoAppearance")
                    Text("개인 기록과 피로 변화가 없습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 6) {
                        ForEach(summary.metrics) { metric in
                            HStack(alignment: .firstTextBaseline) {
                                Text(metric.label).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                                Spacer(minLength: 8)
                                Text(metric.value).font(.system(.title3, design: .monospaced, weight: .bold))
                            }.padding(8).background(GameTheme.board)
                                .accessibilityElement(children: .combine).accessibilityIdentifier("gameResult-" + metric.id)
                        }
                    }
                }
            }
            if let play=resultReplayPlay ?? match.fieldPlays?.last {
                GamePanel(title:resultReplayPlay == nil ? "마지막 타구 · 수비/주루" : resultReplayPlay?.fly != nil ? "최근 뜬공 · 태그업" : "최근 병살 시도",onBoard:true) {
                    Text(play.summary).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("gameDetailedFieldSummary")
                    DetailedFieldReplayBoard(play:play,appearance:player.appearance,animated:animateResultReplay) { animateResultReplay=false }
                        .id(resultReplayID).frame(height:240)
                    Button("수비·주루 재생") { animateResultReplay=true;resultReplayID += 1 }
                        .buttonStyle(MatchPixelButtonStyle()).disabled(animateResultReplay).accessibilityIdentifier("replayResultFieldPlay")
                    if let fly=match.fieldPlays?.last(where: { $0.fly?.caught == true && $0.targetRunner != nil }) ?? match.fieldPlays?.last(where:{ $0.fly?.caught == true }) ?? match.fieldPlays?.last(where:{ $0.fly != nil }) {
                        Button("최근 뜬공·태그업 다시 보기") {
                            resultReplayPlay=fly;animateResultReplay=true;resultReplayID += 1
                        }.buttonStyle(MatchPixelButtonStyle()).disabled(animateResultReplay).accessibilityIdentifier("replayFlyPlay")
                    }
                    if let doublePlay=match.fieldPlays?.last(where: { $0.secondThrow != nil }) {
                        Button("최근 병살 시도 다시 보기") {
                            resultReplayPlay=doublePlay;animateResultReplay=true;resultReplayID += 1
                        }.buttonStyle(MatchPixelButtonStyle()).disabled(animateResultReplay).accessibilityIdentifier("replayDoublePlay")
                    }
                }
            }
            if let experience = match.positionExperience {
                GamePanel(title: "실전 포지션 성장 · " + experience.position.label, onBoard: true) {
                    Text("수비 참여 \(experience.events.count)회 · 아웃 성공 \(experience.successes)회")
                        .font(.subheadline).accessibilityIdentifier("gamePositionParticipation")
                    Text("XP +\(experience.gainedXP, specifier: "%.1f") · 숙련 \(experience.before.mastery, specifier: "%.1f") → \(experience.after.mastery, specifier: "%.1f")")
                        .font(.headline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("gamePositionGrowth")
                    Text("잔여 XP \(experience.after.xp, specifier: "%.1f") / 100 · 다음 새 경기 반영")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            }
            GamePanel(title: "피로 변화", onBoard: true) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Text("\(record.fatigueBefore) → \(record.fatigueAfter)")
                        .font(.system(.title2, design: .monospaced, weight: .bold)).accessibilityIdentifier("gameResultFatigue")
                    Text(summary.fatigueChange).font(.headline).foregroundStyle(GameTheme.gold)
                }
                Text("경기 전 → 경기 후 · 100 기준").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            GamePanel(title: "적용 특성 · 마지막 개인 경합", onBoard: true) {
                Text(summary.traitMessage).font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("gameResultTraitStatus")
                if record.appearance, let play = match.lastFieldPlay {
                    let detailed=match.fieldPlays?.last { $0.ownParticipation || $0.ownBatter }
                    let base=(detailed?.secondThrow?.ownThrower == true || detailed?.ownBatter == true && detailed?.secondThrow != nil) ? 1 : detailed?.targetBase ?? 1
                    let perspective=detailed?.ownBatter == true && detailed?.targetRunner != 0 ? "내 타석" : "내 \(play.ownDefense ? "수비" : "주루")"
                    Text(detailed?.fly?.caught == true ? (play.ownDefense ? "내 수비 · 뜬공 포구 아웃" : "내 타석 · 뜬공 아웃") : "\(perspective) · \(base == 4 ? "홈" : "\(base)루") \(play.safe ? "세이프" : "아웃")")
                        .font(.headline).foregroundStyle(GameTheme.gold)
                    Text(play.caughtFly == true ? String(format:"포구 준비 %.2f초 / 공 도착 %.2f초",play.ballTime,play.runnerTime) : String(format:"대상 주자 %.2f초 / 공 %.2f초",play.runnerTime,play.ballTime))
                        .font(.caption.monospaced()).accessibilityIdentifier("gameFieldResult")
                    if let delay = play.positionDelay {
                        Text("위치 적응 준비 \(delay, specifier: "%.3f")초").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    ForEach(summary.appliedTraits) { trait in
                        HStack(alignment: .top, spacing: 8) {
                            TraitPixelIcon(trait: trait).frame(width: 28, height: 28).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(trait.label).font(.headline).foregroundStyle(GameTheme.gold)
                                Text(trait.effect).font(.caption)
                            }
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("gameResultTrait-" + trait.rawValue)
                    }
                }
            }
            Button("선수 홈으로") { dismiss() }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("gameReturnHome")
            Text("홈에서 다음 날로 진행할 수 있습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }.accessibilityElement(children: .contain)
    }
    private func measure(_ key: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: MatchChromeHeightKey.self, value: [key: proxy.size.height])
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        if let record, let savedMatch = try? record.snapshot() {
                            let match = visualSnapshot ?? savedMatch
                            VStack(spacing: 6) {
                                scoreHeader(match, record: record)
                                if typeSize.isAccessibilitySize && !match.completed {
                                    Button("경기 조작부로 이동") { proxy.scrollTo("gameControls", anchor: .bottom) }
                                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("gameJumpControls")
                                }
                            }.background { measure("header") }
                            if match.completed {
                                results(match, record: record)
                            } else {
                                arena(match, field: MatchPresentation.fieldSize(
                                    available: CGSize(width: max(1, geometry.size.width - 16), height: geometry.size.height),
                                    role: player.role, chromeHeight: chromeHeights.values.reduce(0, +) + 28))
                                VStack(spacing: 6) {
                                    MatchScoreStrip(match: match, pitchCount: player.role == .pitcher ? match.line.pitches : nil, pulse: pulse, pulseAt: pulseAt)
                                    Text(match.lastManual.map { "\($0.grade) · \($0.outcome)" }
                                         ?? (match.completed ? match.message : player.role == .batter ? "조준 → 투구 요청 → 타격" : "그립 선택 → 투구 준비 → 릴리스"))
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 20)
                                        .accessibilityIdentifier("careerGameMessage")
                                    if let last=savedMatch.fieldPlays?.last {
                                        Button("직전 수비·주루 다시 보기") {
                                            visualSnapshot=savedMatch;presenting=true;replay=last
                                        }.buttonStyle(MatchPixelButtonStyle()).disabled(inputLocked).accessibilityIdentifier("replayLastFieldPlay")
                                    }
                                    VStack(spacing: 6) { controls(match) }
                                }.id("gameControls").background { measure("controls") }
                            }
                        } else {
                            Text(error ?? "경기 불러오는 중")
                            Button("다시 확인") { load() }.buttonStyle(MatchPixelButtonStyle())
                        }
                    }.padding(8).frame(maxWidth: .infinity)
                }.onPreferenceChange(MatchChromeHeightKey.self) { chromeHeights = $0 }
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
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.kit, role: player.role, appearance: player.appearance, jerseyNumber: player.jerseyNumber); load() }
        .task(id: pulseAt) {
            guard pulse != nil else { return }
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            if !Task.isCancelled { pulse = nil }
        }
        .onDisappear { cancelInput() }
        .onChange(of: clock.phase) { _, phase in
            if player.role == .pitcher && clock.running { scene.preparePitch(phase: phase, reduced: reduced) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelInput() } }
        .confirmationDialog("남은 경기를 자동으로 진행할까요?", isPresented: $confirmAutomatic, titleVisibility: .visible) {
            Button("진행하고 결과 저장") { advance(.automatic) }
        } message: { Text("현재 카운트·주자에서 이어서 진행합니다. 실제 출전 성적과 피로를 반영하며 취소할 수 없습니다.") }
        .alert("경기를 저장하지 못했습니다", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct MatchChromeHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
