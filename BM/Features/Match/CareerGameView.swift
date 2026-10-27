import SwiftUI
import SwiftData
import SpriteKit

struct CareerGameView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let schools: [School]
    var assessmentID:String? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var battingSwipe: MatchBattingSwipe?
    @State private var battingGestureRevision: Int?
    @State private var showGameDetails = false
    @State private var liveControlsHeight: CGFloat = 110
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
    @State private var displaySnapshot = MatchDisplaySnapshot()
    @AppStorage("bm.fieldPlaybackMode.v1") private var fieldPlaybackRaw = FieldPlaybackMode.system.rawValue
    private var fieldPlaybackMode: FieldPlaybackMode { FieldPlaybackMode(rawValue:fieldPlaybackRaw) ?? .system }
    @State private var error: String?
    @State private var pitchCode = ""
    @State private var confirmAutomatic = false
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 400))

    @State private var visualSnapshot: CareerMatch?
    @State private var presenting = false
    @State private var judgment: ManualMatchResult?
    @State private var arrivedSnapshot: CareerMatch?
    @State private var resultReplayPlay:MatchDetailedPlay?
    @State private var resultReplayID=0
    @State private var animateResultReplay=false
    @State private var fieldResolved = false
    @State private var fieldHandoff:FieldContactHandoff?
    @State private var arenaFrame:CGRect = .zero
    @State private var replay: MatchDetailedPlay?
    @State private var homeRunReplay:MatchHomeRun?
    @State private var homeRunResultPlaying=false
    @State private var pulse: String?
    @State private var pulseAt = Date.distantPast

    #if DEBUG
    private var livePerformanceQA:Bool {ProcessInfo.processInfo.arguments.contains("-live-career-performance")}
    @MainActor private var liveQAWindowActive:Bool {
        UIApplication.shared.applicationState == .active && UIApplication.shared.connectedScenes.contains {$0.activationState == .foregroundActive}
    }
    @MainActor private func runLiveCareerQA() async {
        guard assessmentID == nil,ProcessInfo.processInfo.arguments.contains("-live-career-autoplay"),livePerformanceQA else {return}
        let holdsScreen=ProcessInfo.processInfo.arguments.contains("-qa-endurance-seconds")
        let idleBefore=UIApplication.shared.isIdleTimerDisabled
        if holdsScreen {UIApplication.shared.isIdleTimerDisabled=true}
        defer {if holdsScreen {UIApplication.shared.isIdleTimerDisabled=idleBefore}}
        do {
            try await Task.sleep(for:.seconds(15))
            for _ in 0..<180 where !liveQAWindowActive {try await Task.sleep(for:.milliseconds(250))}
            let active=liveQAWindowActive
            let phase=["active":active,"applicationActive":UIApplication.shared.applicationState == .active,
                       "foregroundScene":UIApplication.shared.connectedScenes.contains {$0.activationState == .foregroundActive}]
            try JSONEncoder().encode(phase).write(to:FileManager.default.temporaryDirectory.appendingPathComponent("actual-career-phase-"+player.role.rawValue+".json"),options:.atomic)
            guard active else {return}
            var replayedEventID:String?
            if ProcessInfo.processInfo.arguments.contains("-qa-replay-saved-play") {
                guard let record,record.completed else {throw NSError(domain:"BM.QA",code:4,userInfo:[NSLocalizedDescriptionKey:"완료된 별도 QA 경기가 필요합니다."])}
                let saved=try record.snapshot()
                let savedPayload=record.payload,savedRevision=record.revision,savedFatigue=player.fatigue,savedDate=player.gameDate
                guard let play=saved.fieldPlays?.first(where:{$0.ownBatter || $0.ownParticipation || player.role == .pitcher}) else {
                    throw NSError(domain:"BM.QA",code:5,userInfo:[NSLocalizedDescriptionKey:"저장된 QA 타구가 없습니다."])
                }
                replayedEventID=play.eventID
                visualSnapshot=saved;presenting=true;fieldResolved=false;replay=play
                while presenting {try await Task.sleep(for:.milliseconds(50))}
                guard record.payload==savedPayload,record.revision==savedRevision,player.fatigue==savedFatigue,player.gameDate==savedDate else {
                    throw NSError(domain:"BM.QA",code:6,userInfo:[NSLocalizedDescriptionKey:"읽기 전용 QA 저장 불일치"])
                }
            } else {
                for _ in 0..<24 {
                    guard !Task.isCancelled,let record,!record.completed,error == nil else {break}
                    let match=try record.snapshot()
                    if player.role == .pitcher && !match.ownPitcherActive {break}
                    let delivery=match.delivery(pitchCode:pitchCode)
                    aimX=delivery.x;aimY=delivery.y;battingAction = .swing
                    begin()
                    let target=player.role == .pitcher ? ManualMatchRules.releaseCenter:MatchDelivery.contactPhase
                    while clock.running && clock.phase<target {try await Task.sleep(for:.milliseconds(10))}
                    if clock.running {resolve()}
                    while presenting {try await Task.sleep(for:.milliseconds(50))}
                    if MatchRenderMetrics.lifecycle.contains(where:{$0.name=="career.inplay.exit"}) {break}
                }
            }
            guard !Task.isCancelled,let record,error == nil else {return}
            if !record.completed {advance(.automatic)}
            try await Task.sleep(for:.seconds(2))
            let snapshot=try record.snapshot(),before=record.payload,beforeFatigue=player.fatigue
            let reopened=try CareerMatchStore.start(player:player,state:calendar,in:context)
            struct Audit:Encodable {let replayedEventID:String?;let sessionStore:String;let active:Bool;let completed:Bool;let inplay:Bool;let sameRecord:Bool;let samePayload:Bool;let sameFatigue:Bool;let recordCount:Int}
            let audit=Audit(replayedEventID:replayedEventID,sessionStore:try LiveCareerQA.storeURL(arguments:ProcessInfo.processInfo.arguments,bundleID:Bundle.main.bundleIdentifier).lastPathComponent,active:liveQAWindowActive,completed:snapshot.completed,inplay:MatchRenderMetrics.lifecycle.contains {$0.name=="career.inplay.exit"},sameRecord:reopened.id==record.id,samePayload:reopened.payload==before,sameFatigue:player.fatigue==beforeFatigue,recordCount:try context.fetch(FetchDescriptor<CareerMatchRecord>()).filter {$0.playerID==player.id}.count)
            let data=try JSONEncoder().encode(audit)
            try data.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("actual-career-audit-"+player.role.rawValue+".json"),options:.atomic)
            MatchRenderMetrics.mark("career.qa.completed")
            MatchRenderMetrics.exportLive(role:player.role.rawValue+"-actual-session-\(Int(ProcessInfo.processInfo.systemUptime*1000))")
            let args=ProcessInfo.processInfo.arguments
            if let index=args.firstIndex(of:"-qa-endurance-seconds") {
                guard args.indices.contains(index+1),let seconds=Int(args[index+1]),(60...3600).contains(seconds) else {
                    throw NSError(domain:"BM.QA",code:7,userInfo:[NSLocalizedDescriptionKey:"유효한 장시간 QA 길이가 필요합니다."])
                }
                try await runEnduranceQA(record:record,seconds:seconds)
            }
        } catch {self.error=error.localizedDescription}
    }
    @MainActor private func runEnduranceQA(record:CareerMatchRecord,seconds:Int) async throws {
        let saved=try record.snapshot(),payload=record.payload,revision=record.revision,fatigue=player.fatigue,date=player.gameDate
        let fields=saved.fieldPlays ?? [],homers=saved.homeRuns ?? []
        guard !fields.isEmpty || !homers.isEmpty else {throw NSError(domain:"BM.QA",code:8)}
        let session=try LiveCareerQA.storeURL(arguments:ProcessInfo.processInfo.arguments,bundleID:Bundle.main.bundleIdentifier).lastPathComponent
        let role=player.role.rawValue,log=try CareerEnduranceLog(role:role,session:session,seconds:seconds)
        let oldIdle=UIApplication.shared.isIdleTimerDisabled,oldBattery=UIDevice.current.isBatteryMonitoringEnabled
        UIApplication.shared.isIdleTimerDisabled=true;UIDevice.current.isBatteryMonitoringEnabled=true
        defer {UIApplication.shared.isIdleTimerDisabled=oldIdle;UIDevice.current.isBatteryMonitoringEnabled=oldBattery;log.close()}
        var clip=0
        while log.elapsed<Double(seconds),!Task.isCancelled {
            try log.sample(inplay:presenting,clip:clip)
            if ProcessInfo.processInfo.thermalState == .critical {log.reason="thermal-critical";break}
            guard liveQAWindowActive else {try await Task.sleep(for:.seconds(1));continue}
            MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true
            let marker="qa.endurance.\(role).\(clip)"
            MatchRenderMetrics.mark(marker+".begin")
            visualSnapshot=saved;fieldResolved=false;presenting=true
            let item=clip%(fields.count+homers.count)
            if item<fields.count {replay=fields[item]} else {homeRunReplay=homers[item-fields.count]}
            while presenting,log.elapsed<Double(seconds),!Task.isCancelled {
                try log.sample(inplay:true,clip:clip)
                try await Task.sleep(for:.milliseconds(100))
            }
            let resolved=MatchRenderMetrics.lifecycle.contains {$0.name=="career.inplay.resolved"}
            if presenting {cancelInput();try await Task.sleep(for:.milliseconds(100))}
            MatchRenderMetrics.mark(marker+".end")
            MatchRenderMetrics.exportLive(role:role+"-endurance-clip-\(clip)-\(Int(ProcessInfo.processInfo.systemUptime*1000))")
            log.clips.append(.init(index:clip,at:ProcessInfo.processInfo.systemUptime,resolved:resolved))
            clip+=1
            try await Task.sleep(for:.milliseconds(250))
        }
        try Task.checkCancellation()
        let unchanged=record.payload==payload && record.revision==revision && player.fatigue==fatigue && player.gameDate==date
        let reopened=try CareerMatchStore.start(player:player,state:calendar,in:context)
        let count=try context.fetch(FetchDescriptor<CareerMatchRecord>()).filter {$0.playerID==player.id}.count
        try log.finish(inplay:false,clip:clip,unchanged:unchanged && reopened.id==record.id && reopened.payload==payload && count==1)
    }
    #endif
    private var preparesFieldMotion:Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-match-render-baseline")
        #else
        true
        #endif
    }
    private var fieldCoversArena:Bool {replay != nil || homeRunReplay != nil}
    private var inputLocked: Bool { clock.running || presenting || retrySave != nil }
    private var opponentSide: OpponentBatterSide { (visualSnapshot ?? displaySnapshot.match)?.opponentBatterSide ?? .right }
    private func configureScene() {
        scene.configure(hand: player.throwingHandRaw, kit: player.kit, role: player.role, appearance: player.appearance,
                        jerseyNumber: player.jerseyNumber, batterSide: opponentSide)
    }
    private func load() {
        do {
            let saved = try assessmentID.map {try GoalSpecialStore.displayRecord(player:player,calendar:calendar,id:$0,in:context)} ?? CareerMatchStore.start(player: player, state: calendar, in: context)
            record = saved
            try displaySnapshot.refresh(saved)
            if pitchCode.isEmpty { pitchCode = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
        } catch { self.error = error.localizedDescription }
    }
    private func begin() {
        #if DEBUG
        if livePerformanceQA {MatchRenderMetrics.mark(player.role == .pitcher ? "career.input.pitch":"career.input."+battingAction.rawValue)}
        #endif
        guard !presenting, attempt == nil, retrySave == nil, let record, let match = try? record.snapshot(), !match.completed, player.role != .pitcher || match.ownPitcherActive else { return }
        let input: MatchInput = player.role == .pitcher ? .pitch : battingAction
        let actualCode=match.deliveryPitchCode(requested:pitchCode)
        attempt = Attempt(revision: record.revision, input: input, pitchCode: actualCode)
        let delivery = match.delivery(pitchCode: actualCode)
        let flight = PitchFlightPresentation(delivery: delivery)
        let timeline = MatchInputTimeline(windup: player.role == .batter ? MatchDelivery.windup : 0,
                                          duration: player.role == .batter ? flight.battingDuration : 1.8)
        if player.role == .batter {
            scene.cancelDelivery()
            _ = scene.demonstrate(reduceMotion: reduced, flightDuration: flight.flightDuration, x: delivery.x, y: delivery.y, pitchCode: actualCode, inputTimeline: timeline)
        }
        if player.role == .pitcher { scene.preparePitch(phase: 0, reduced: reduced) }
        clock.start(timeline: timeline) { resolve(timeout: true) }
    }
    private func resolve(timeout: Bool = false) {
        guard let attempt else { return }
        let control = player.role == .pitcher ? ManualMatchInput(release: timeout ? 0 : clock.phase)
            : ManualMatchInput(x: aimX, y: aimY, timing: timeout || attempt.input == .watch ? nil : clock.currentPhase)
        self.attempt = nil; clock.stop()
        commit(PendingSave(attempt: attempt, control: control))
    }
    private func commit(_ pending: PendingSave) {
        guard let record else { return }
        guard !record.completed, record.revision == pending.attempt.revision else { retrySave = nil; return }
        do {
            #if DEBUG
            if livePerformanceQA {MatchRenderMetrics.mark("career.commitBegin")}
            #endif
            let previous = try record.snapshot()
            try persist(record,revision:pending.attempt.revision,input:pending.attempt.input,pitchCode:pending.attempt.pitchCode,control:pending.control)
            retrySave = nil
            let updated=try displaySnapshot.refresh(record)
            #if DEBUG
            if livePerformanceQA {MatchRenderMetrics.mark("career.commitEnd")}
            #endif
            let added=Array((updated.fieldPlays ?? []).dropFirst(previous.fieldPlays?.count ?? 0))
            let homeRun=Array((updated.homeRuns ?? []).dropFirst(previous.homeRuns?.count ?? 0)).first {
                $0.half == previous.half && $0.order == (previous.half%2 == 1 ? previous.homeOrder:previous.awayOrder) && pending.attempt.input != .watch
            }
            let fieldPlay=homeRun == nil ? added.first { $0.ownBatter || $0.ownParticipation || (player.role == .pitcher && $0.half == previous.half) } : nil
            if let result = updated.lastManual {
                visualSnapshot = previous; presenting = true; judgment = nil; arrivedSnapshot = nil
                let showCall: @MainActor () -> Void = {
                    #if DEBUG
                    if livePerformanceQA {MatchRenderMetrics.mark("career.ballArrival")}
                    #endif
                    if let homeRun {
                        var handoff=scene.fieldHandoff;handoff?.sourceFrame=arenaFrame;fieldHandoff=handoff
                        fieldResolved=false;homeRunReplay=homeRun
                    } else if let fieldPlay {
                        fieldResolved=false
                        var handoff=scene.fieldHandoff;handoff?.sourceFrame=arenaFrame;fieldHandoff=handoff
                        replay=fieldPlay
                    } else {
                        judgment = result; arrivedSnapshot = updated
                        pulse = MatchPresentation.countPulse(result.outcome); pulseAt = Date()
                    }
                }
                let showResult: @MainActor () -> Void = {
                    guard fieldPlay == nil && homeRun == nil else {return}
                    judgment = nil;presenting = false; visualSnapshot = nil; arrivedSnapshot = nil
                }
                let contact=fieldPlay.flatMap {FieldContactPresentation.matches($0,previous:previous,action:result.action) ? $0:nil}
                if player.role == .pitcher {
                    let started = scene.demonstrate(reduceMotion: reduced, flightDuration: PitchFlightPresentation(delivery: previous.delivery(pitchCode: result.pitchCode)).flightDuration,
                                          x: result.x, y: result.y, pitchCode: result.pitchCode ?? "four-seam",
                                          outcome: fieldPlay == nil ? result.outcome : "안타", preparedRelease: true, matchJudgment: true, fieldPlay:contact, homeRun:homeRun, onArrival: showCall, completion: showResult)
                    if !started { showCall(); showResult() }
                } else {
                    // Saved fair contact drives the barrel motion; localized multi-base labels are not contact flags.
                    scene.finishBat(action: result.action, outcome: added.contains(where: \.ownBatter) ? "안타" : result.outcome,
                                    reduced: reduced, matchJudgment: true, fieldPlay:contact, homeRun:homeRun, onArrival: showCall, completion: showResult)
                }
            }
        } catch { retrySave = pending; self.error = error.localizedDescription; scene.cancelDelivery() }
    }
    private func cancelInput() {
        clock.stop(); battingSwipe = nil; battingGestureRevision = nil; attempt = nil; judgment = nil; arrivedSnapshot = nil; presenting = false; visualSnapshot = nil; replay=nil;homeRunReplay=nil;homeRunResultPlaying=false;fieldHandoff=nil;fieldResolved=false;resultReplayPlay=nil;animateResultReplay=false;pulse = nil; scene.cancelDelivery()
    }
    private func persist(_ record:CareerMatchRecord,revision:Int,input:MatchInput,pitchCode:String?,control:ManualMatchInput?) throws {
        if let assessmentID {
            let updated=try GoalSpecialStore.advancePlay(player:player,calendar:calendar,id:assessmentID,revision:revision,input:input,pitchCode:pitchCode,control:control,in:context)
            guard let game=updated.currentGame else {throw MatchError.invalidRecord}
            record.payload=try JSONEncoder().encode(game);record.revision=updated.calendarRevision;record.completed=game.completed
        } else {
            try CareerMatchStore.advance(player:player,state:calendar,record:record,revision:revision,input:input,pitchCode:pitchCode,control:control,in:context)
        }
    }
    private func assessmentResults(_ match:CareerMatch) -> some View {
        GamePanel(title:"ASSESSMENT · 평가 경기 저장",onBoard:true,contentSpacing:12) {
            Text("평가 경기 완료 · "+(match.scoutingPerformance?.inputs?.mode.label ?? "입력 미확인")).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("assessmentGameCompleted")
            Text(player.role == .batter
                 ? "\(match.line.plateAppearances)타석 · \(match.line.hits)안타 · \(match.line.homeRuns)홈런 · \(match.line.walks)볼넷"
                 : "\(match.line.pitchingOuts/3).\(match.line.pitchingOuts%3)이닝 · \(match.line.pitchingStrikeouts)탈삼진 · \(match.line.pitchingWalks)볼넷").font(.subheadline)
            Text("공식 경기/시즌 성적·XP·계약 표본에 합산하지 않습니다. 2경기 완료 시 하루 행동과 피로+8을 한 번 반영합니다.").font(.caption)
            Button("평가전 결과·다음 경기로") {dismiss()}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("assessmentReturn")
        }
    }
    private func advance(_ input: MatchInput) {
        guard !presenting, attempt == nil, retrySave == nil, let record else { return }
        do {
            try persist(record,revision:record.revision,input:input,pitchCode:pitchCode,control:nil)
            _ = try displaySnapshot.refresh(record)
            _ = scene.demonstrate(reduceMotion: reduced)
        } catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private func controls(_ match: CareerMatch) -> some View {
        if let pending = retrySave {
            Text("직전 입력을 저장하지 못했습니다.").font(.caption)
            Button("같은 입력 다시 저장") { commit(pending) }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("retryGameInput")
        } else if let change=match.ownPitcherChange {
            PitcherChangePanel(change:change,appearance:player.appearance)
            Text("남겨 둔 주자의 실점은 경기 종료까지 확정됩니다.").font(.caption)
            Button("남은 경기 자동 진행") {advance(.automatic)}
                .buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(inputLocked).accessibilityIdentifier("finishAfterPitcherChange")
        } else if record?.appearance == true {
            if player.role == .pitcher {
                let mastery = match.mastery[pitchCode] ?? 60
                MatchTimingGauge(phase: clock.phase, center: ManualMatchRules.releaseCenter,
                                 good: match.releaseGoodWidth(mastery: mastery),
                                 perfect: match.releasePerfectWidth(mastery: mastery), label: (replay != nil || homeRunReplay != nil) ? "수비·주루 진행 중" : presenting ? (judgment == nil ? "릴리스 확정 · 공 비행 중" : "포구 완료 · 판정 확인") : clock.running ? "팔 준비 중 · 노란 구간에 릴리스" : "릴리스 · 숙련도 \(mastery.formatted(.number.precision(.fractionLength(1))))")
                    .accessibilityIdentifier("releaseGauge")
                Button((replay != nil || homeRunReplay != nil) ? "수비·주루 진행 중…" : presenting ? (judgment == nil ? "공 비행·포구 중…" : "판정 확인 중…") : clock.running ? "지금 릴리스" : "투구 준비") {
                    if clock.running { resolve() } else { begin() }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(presenting).accessibilityIdentifier(clock.running ? "gameRelease" : "gamePitch")
            } else {
                MatchTimingGauge(phase: clock.phase, center: MatchDelivery.contactPhase,
                                 good: ManualMatchRules.timingWidth(contact: match.contact) * match.executionFactor,
                                 perfect: 0.025, label: presenting ? "공·수비 진행 중" : clock.running ? (battingAction == .watch ? "공을 지켜보는 중" : "화면 탭 · 지금 " + battingAction.label) : "스와이프 조준 · 화면 탭으로 투구 요청", batting: true)
                    .accessibilityIdentifier("battingTimingGauge")

            }
        }
    }
    private func broadcast(_ match: CareerMatch, record: CareerMatchRecord) -> some View {
        let ownID = (try? calendar.teamID(for: player, on: GameDate(record.gameDate))) ?? player.schoolID
        let ownName = assessmentID == nil ? CareerTeamDirectory.name(ownID, schools: schools) : "내 평가팀"
        let opponent = CareerTeamDirectory.name(record.opponentID, schools: schools)
        let home = match.playerRecords.map {CareerTeamDirectory.name($0.home.teamID, schools: schools)} ?? (match.isHome ? ownName : opponent)
        let away = match.playerRecords.map {CareerTeamDirectory.name($0.away.teamID, schools: schools)} ?? (match.isHome ? opponent : ownName)
        return MatchBroadcastBoard(match: match, homeName: home, awayName: away, date: record.gameDate, pulse: pulse, pulseAt: pulseAt)
    }
    private var battingTouchLocked: Bool { retrySave != nil || presenting || record?.completed != false || record?.appearance != true }
    private func tapBattingField() {
        guard !battingTouchLocked else { return }
        if clock.running {
            if battingAction != .watch { resolve() }
        } else { begin() }
    }
    private func battingSurface(_ field: CGSize) -> some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !battingTouchLocked else { battingSwipe = nil; return }
                if battingGestureRevision == nil { battingGestureRevision = record?.revision }
                if battingSwipe == nil { battingSwipe = MatchBattingSwipe(x: aimX, y: aimY) }
                guard var swipe = battingSwipe else { return }
                let aim = swipe.move(value.translation, field: field)
                battingSwipe = swipe; aimX = aim.x; aimY = aim.y
            }.onEnded { value in
                defer { battingSwipe = nil; battingGestureRevision = nil }
                guard !battingTouchLocked, battingGestureRevision == record?.revision, var swipe = battingSwipe else { return }
                let aim = swipe.move(value.translation, field: field)
                aimX = aim.x; aimY = aim.y
                if swipe.isTap { tapBattingField() }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clock.running ? (battingAction == .watch ? "공 지켜보기" : "지금 " + battingAction.label) : "경기장 · 투구 요청")
            .accessibilityValue("타격 포인트 가로 \(Int(aimX * 100)), 세로 \(Int(aimY * 100))")
            .accessibilityHint("쓸어서 조준하고 탭하여 타격. 공 대기 중 탭하면 투구를 요청합니다.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tapBattingField() }
            .accessibilityAction(named: "왼쪽 조준") { if !battingTouchLocked { aimX = max(0, aimX - 0.1) } }
            .accessibilityAction(named: "오른쪽 조준") { if !battingTouchLocked { aimX = min(1, aimX + 0.1) } }
            .accessibilityAction(named: "위 조준") { if !battingTouchLocked { aimY = max(0, aimY - 0.1) } }
            .accessibilityAction(named: "아래 조준") { if !battingTouchLocked { aimY = min(1, aimY + 0.1) } }
            .accessibilityIdentifier("battingTouchSurface")
    }
    private var batterChoices: some View {
        VStack(spacing: 6) {
            ForEach([MatchInput.watch, .swing, .bunt], id: \.rawValue) { input in
                Button { battingAction = input } label: {
                    HStack(spacing: 4) {
                        Rectangle().fill(battingAction == input ? GameTheme.gold : Color.clear).frame(width: 4, height: 18)
                        Text(input.label).font(typeSize.isAccessibilitySize ? .headline : .system(size: 14, weight: .heavy, design: .monospaced))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 7).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .foregroundStyle(battingAction == input ? GameTheme.gold : GameTheme.paper)
                    .background(Color(hex: 0x102a3f).opacity(0.96))
                    .overlay(Rectangle().strokeBorder(battingAction == input ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                    .disabled(inputLocked).accessibilityAddTraits(battingAction == input ? .isSelected : [])
                    .accessibilityIdentifier("gameInput-" + input.rawValue)
            }
        }
    }
    private func pitcherChoices(_ match: CareerMatch) -> some View {
        VStack(spacing: 0) {
            ForEach(player.pitches.sorted { $0.order < $1.order }) { pitch in
                let mastery = match.mastery[pitch.code] ?? 60
                Button { pitchCode = pitch.code } label: {
                    MatchPitchChip(name: pitch.name, mastery: mastery, selected: pitchCode == pitch.code)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(inputLocked).accessibilityLabel(pitch.name + " · 숙련도 " + mastery.formatted(.number.precision(.fractionLength(1))))
                    .accessibilityAddTraits(pitchCode == pitch.code ? .isSelected : [])
                    .accessibilityIdentifier("gamePitchChoice-" + pitch.code)
            }
        }
    }
    private func liveGame(_ match: CareerMatch, record: CareerMatchRecord, available: CGSize) -> some View {
        let field = CGSize(width: available.width, height: available.width * (player.role == .batter ? 1 : 1290 / 1219))
        return Group {
            if typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 10) {
                        broadcast(arrivedSnapshot ?? match, record: record)
                        arena(match, field: CGSize(width: max(1, available.width - 16), height: max(1, available.width - 16) * (player.role == .batter ? 1 : 1290 / 1219)))
                        if record.appearance && match.ownPitcherChange == nil {
                            if player.role == .batter { batterChoices } else { pitcherChoices(match) }
                        }
                        controls(match)
                    }.padding(8)
                }
            } else {
                ZStack {
                    arena(match, field: field)
                        .overlay(alignment: player.role == .batter ? .bottomTrailing : .bottomLeading) {
                            if record.appearance && match.ownPitcherChange == nil {
                                if player.role == .batter { batterChoices.frame(width: 106).padding(.trailing, 10).padding(.bottom, 26) }
                                else { pitcherChoices(match).frame(width: 104).padding(.leading, 10)
                                    .padding(.bottom, max(12, liveControlsHeight - (available.height - field.height) / 2 + 8)) }
                            }
                        }
                        .position(x: available.width / 2, y: available.height * 0.50)
                    VStack(spacing: 0) {
                        broadcast(arrivedSnapshot ?? match, record: record).padding(.horizontal, 8).padding(.top, 4)
                        if assessmentID != nil { Text("평가전 · 공식 기록 제외").font(.caption).foregroundStyle(GameTheme.gold) }
                        Spacer(minLength: 0)
                        VStack(spacing: 5) { controls(match) }.padding(.horizontal, 12).padding(.vertical, 8)
                            .background { GeometryReader { g in Color.clear.preference(key: MatchControlsHeightKey.self, value: g.size.height) } }
                            .background(Color(hex: 0x102a3f))
                    }.allowsHitTesting(true)
                }.clipped().onPreferenceChange(MatchControlsHeightKey.self) { liveControlsHeight = $0 }
            }
        }.background(Color(hex: 0x123c3b)).accessibilityHidden(fieldCoversArena)
    }
    private func inplayStage(_ play:MatchDetailedPlay,match:CareerMatch) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing:16) {
                    let header=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)):AnyLayout(HStackLayout())
                    header {
                        Text(typeSize.isAccessibilitySize ? "인플레이":"IN PLAY · FIELD").font(.system(.title3,design:.monospaced,weight:.black))
                        if !typeSize.isAccessibilitySize {Spacer()}
                        Text(player.name + " #" + String(player.jerseyNumber)).font(.headline)
                    }.foregroundStyle(GameTheme.gold).frame(maxWidth:.infinity,alignment:.leading)
                    if typeSize.isAccessibilitySize {
                        Button("경기장 보기") {proxy.scrollTo("fieldGraphic",anchor:.center)}
                            .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("inplayJumpField")
                    }
                    DetailedFieldReplayBoard(play:play,appearance:player.appearance,jerseyNumber:player.jerseyNumber,
                        ownPosition:player.role == .pitcher ? "P":player.positionRaw,throwingHand:player.throwingHandRaw,
                        ownTeamFielding:(play.half%2 == 0) == match.isHome,
                        scoreText:"H \((arrivedSnapshot ?? match).homeScore) : \((arrivedSnapshot ?? match).awayScore) A",handoff:fieldHandoff,playbackMode:fieldPlaybackMode,preparesMotion:preparesFieldMotion,onResolved:{
                            #if DEBUG
                            if livePerformanceQA {MatchRenderMetrics.mark("career.inplay.resolved")}
                            #endif
                            fieldResolved=true
                            if let updated=displaySnapshot.match {
                                arrivedSnapshot=updated;pulse=MatchPresentation.countPulse(updated.lastManual?.outcome ?? "");pulseAt=Date()
                            }
                        }) {
                            replay=nil;fieldHandoff=nil;presenting=false;visualSnapshot=nil;arrivedSnapshot=nil;fieldResolved=false
                        }
                        .id(play.eventID)
                        .frame(height:FieldReplayPresentation.stageHeight(width:geometry.size.width-16,available:geometry.size.height,accessibility:typeSize.isAccessibilitySize))
                    Text(fieldResolved ? play.summary:"타구를 따라 수비가 진행됩니다")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.boardMuted)
                }.padding(.horizontal,8).padding(.vertical,16)
            }.background(GameTheme.navy.ignoresSafeArea())
                .accessibilityIdentifier("inplayFieldStage")
            }
        }
    }
    private func homeRunStage(_ event:MatchHomeRun,match:CareerMatch) -> some View {
        GeometryReader {geometry in
            ScrollView {
                VStack(spacing:16) {
                    Text("IN PLAY · BASE RUNNING").font(.title3.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    HomeRunReplayBoard(event:event,appearance:player.appearance,jerseyNumber:player.jerseyNumber,
                        ownPosition:player.role == .pitcher ? "P":player.positionRaw,throwingHand:player.throwingHandRaw,
                        ownTeamFielding:(event.half%2 == 0) == match.isHome,
                        scoreText:"H \((arrivedSnapshot ?? match).homeScore) : \((arrivedSnapshot ?? match).awayScore) A",handoff:fieldHandoff,
                        playbackMode:fieldPlaybackMode,preparesMotion:preparesFieldMotion,onResolved:{
                            #if DEBUG
                            if livePerformanceQA {MatchRenderMetrics.mark("career.inplay.resolved")}
                            #endif
                            fieldResolved=true;arrivedSnapshot=displaySnapshot.match}) {
                            homeRunReplay=nil;fieldHandoff=nil;presenting=false;visualSnapshot=nil;arrivedSnapshot=nil;fieldResolved=false
                        }.id(event.eventID)
                        .frame(height:FieldReplayPresentation.stageHeight(width:geometry.size.width-16,available:geometry.size.height,accessibility:typeSize.isAccessibilitySize))
                }.padding(.horizontal,8).padding(.vertical,16)
            }.background(GameTheme.navy.ignoresSafeArea()).accessibilityIdentifier("homeRunStage")
        }
    }
    private func arena(_ match: CareerMatch, field: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack {
                MatchArenaSurface(scene:scene,covered:fieldCoversArena && preparesFieldMotion)

            }
                .frame(width: field.width, height: field.height)
                .background {GeometryReader {geometry in Color.clear.preference(key:MatchArenaFrameKey.self,value:geometry.frame(in:.global))}}
                .onPreferenceChange(MatchArenaFrameKey.self) {arenaFrame=$0}
                .accessibilityLabel(player.role == .batter ? "도트 타자 경기장" : "도트 투수 경기장")
                .accessibilityIdentifier("careerMatchField")
                .overlay {
                    if player.role == .batter, !match.completed, !fieldCoversArena {
                        battingSurface(field)
                    }
                    if player.role == .pitcher, replay == nil && homeRunReplay == nil, !typeSize.isAccessibilitySize {
                        PitchLocationBoard(result: judgment ?? match.lastManual, side: match.opponentBatterSide)
                            .frame(width: field.width * 0.24)
                            .position(x: field.width * (match.opponentBatterSide.mapOnRight ? 0.85 : 0.15), y: field.height * 0.20)
                    }
                    if let judgment, replay == nil && homeRunReplay == nil, !typeSize.isAccessibilitySize {
                        PitchJudgmentToast(title: DeliveryPresentation.call(judgment.outcome),
                                           detail: "\(MatchPresentation.pitchName(judgment)) · \(judgment.speed) km/h")
                            .frame(maxWidth: field.width * 0.85)
                            .position(x: field.width * 0.5, y: field.height * (player.role == .pitcher ? 0.22 : 0.17))
                            .accessibilityIdentifier("pitchJudgmentToast")
                    }
                    if (replay != nil || homeRunReplay != nil) { EmptyView() }
                    else if judgment == nil && player.role == .batter && !match.completed {
                        BattingAimZone(x: $aimX, y: $aimY, locked: retrySave != nil || presenting, showsGrid:false)
                            .frame(width: field.width * 0.16, height: field.height * 0.22)
                            .position(x: field.width * 0.5, y: field.height * 0.68)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    } else if judgment == nil && player.role == .pitcher && !match.completed {
                        let target = match.delivery(pitchCode: pitchCode)
                        BattingAimZone(x: .constant(target.x), y: .constant(target.y), locked: true, showsGrid:false)
                            .frame(width: field.width * 0.22, height: field.height * 0.24)
                            .position(x: field.width * 0.54, y: field.height * 0.43)
                            .allowsHitTesting(false)
                            .accessibilityLabel("자동 투구 목표")
                            .accessibilityIdentifier("pitchingTargetZone")
                    }
                }
                .frame(maxWidth: .infinity).background(Color(hex: 0x102a3f))
        }
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
            if let preparation=match.preparation,let outcome=MatchPlanOutcome.make(match:match) {MatchPlanOutcomePanel(preparation:preparation,outcome:outcome)}
            GamePanel(title: player.role == .batter ? "타자 경기 기록" : "투수 경기 기록", onBoard: true) {
                if let change=match.ownPitcherChange {PitcherChangePanel(change:change,finalRuns:match.line.runsAllowed,appearance:player.appearance)}
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
            if let homeRun=match.homeRuns?.last {
                GamePanel(title:"최근 홈런 · 비거리",onBoard:true) {
                    HomeRunReplayBoard(event:homeRun,appearance:player.appearance,jerseyNumber:player.jerseyNumber,
                        ownPosition:player.role == .pitcher ? "P":player.positionRaw,throwingHand:player.throwingHandRaw,
                        ownTeamFielding:(homeRun.half%2 == 0) == match.isHome,scoreText:"H \(match.homeScore) : \(match.awayScore) A",animated:homeRunResultPlaying) {homeRunResultPlaying=false}
                        .id(resultReplayID).frame(height:650)
                    Button("홈런 다시 보기") {homeRunResultPlaying=true;resultReplayID+=1}
                        .buttonStyle(MatchPixelButtonStyle()).disabled(homeRunResultPlaying).accessibilityIdentifier("replayResultHomeRun")
                }
            }
            if let play=resultReplayPlay ?? match.fieldPlays?.last {
                GamePanel(title:resultReplayPlay == nil ? "마지막 타구 · 수비/주루" : resultReplayPlay?.misplay != nil ? "최근 실책 · 추가 진루" : resultReplayPlay?.relay != nil ? "최근 중계 송구" : resultReplayPlay?.fly != nil ? "최근 뜬공 · 태그업" : "최근 병살 시도",onBoard:true) {
                    Text(animateResultReplay ? "인플레이 · 수비 재생 중":play.summary).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("gameDetailedFieldSummary")
                    DetailedFieldReplayBoard(play:play,appearance:player.appearance,animated:animateResultReplay,
                        jerseyNumber:player.jerseyNumber,ownPosition:player.role == .pitcher ? "P":player.positionRaw,throwingHand:player.throwingHandRaw,
                        ownTeamFielding:(play.half%2 == 0) == match.isHome,scoreText:"H \(match.homeScore) : \(match.awayScore) A") { animateResultReplay=false }
                        .id(resultReplayID).frame(height:600)
                    if !animateResultReplay {FieldReplayDetails(play:play)}
                    Button("수비·주루 재생") { animateResultReplay=true;resultReplayID += 1 }
                        .buttonStyle(MatchPixelButtonStyle()).disabled(animateResultReplay).accessibilityIdentifier("replayResultFieldPlay")
                    if let error=match.fieldPlays?.last(where:{$0.misplay != nil}) {
                        Button("최근 실책 다시 보기") {
                            resultReplayPlay=error;animateResultReplay=true;resultReplayID += 1
                        }.buttonStyle(MatchPixelButtonStyle()).disabled(animateResultReplay).accessibilityIdentifier("replayMisplay")
                    }
                    if let relay=match.fieldPlays?.last(where:{ $0.relay != nil }) {
                        Button("최근 중계 송구 다시 보기") {
                            resultReplayPlay=relay;animateResultReplay=true;resultReplayID += 1
                        }.buttonStyle(MatchPixelButtonStyle()).disabled(animateResultReplay).accessibilityIdentifier("replayRelayPlay")
                    }
                    if let fly=match.fieldPlays?.last(where: { $0.fly?.caught == true && $0.targetRunner != nil && $0.misplay == nil }) ?? match.fieldPlays?.last(where:{ $0.fly?.caught == true && $0.misplay == nil }) ?? match.fieldPlays?.last(where:{ $0.fly != nil && $0.misplay == nil }) {
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
            if let experience = match.abilityExperience {
                MatchAbilityGrowthPanel(experience: experience)
            } else {
                GamePanel(title: "경기 능력 성장", onBoard: true) {
                    Text(match.appearance ? "이전 규칙 경기 · 능력 XP 소급 지급 없음" : "비출전 팀 경기 · 개인 능력 XP 없음")
                        .font(.caption).accessibilityIdentifier("gameAbilityXPExcluded")
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
                    Text(detailed?.misplay != nil && detailed?.ownBatter == true ? "내 타석 · 실책/추가 진루" : detailed?.misplay != nil ? "내 수비 참여 · \(play.safe ? "성공 보너스 없음" : "확정 아웃 성공")" : detailed?.fly?.caught == true && detailed?.relay?.ownThrower != true ? (play.ownDefense ? "내 수비 · 뜬공 포구 아웃" : "내 타석 · 뜬공 아웃") : "\(perspective) · \(base == 4 ? "홈" : "\(base)루") \(play.safe ? "세이프" : "아웃")")
                        .font(.headline).foregroundStyle(GameTheme.gold)
                    Text(play.failedFielding != nil ? String(format:"실책 시점 %.2f초 / 회수 %.2f초",play.runnerTime,play.ballTime) : play.caughtFly == true ? String(format:"포구 준비 %.2f초 / 공 도착 %.2f초",play.ballTime,play.runnerTime) : String(format:"대상 주자 %.2f초 / 공 %.2f초",play.runnerTime,play.ballTime))
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
    var body: some View {
        GeometryReader { geometry in
            if let record, let savedMatch = displaySnapshot.match {
                let match = visualSnapshot ?? savedMatch
                if match.completed {
                    ScrollView {
                        VStack(spacing: 10) {
                            broadcast(arrivedSnapshot ?? match, record: record)
                            if !fieldCoversArena {
                                if assessmentID != nil { assessmentResults(match) } else { results(match, record: record) }
                            }
                        }.padding(8)
                    }.accessibilityHidden(fieldCoversArena)
                } else { liveGame(match, record: record, available: geometry.size) }
            } else {
                VStack {
                    Text(error ?? "경기 불러오는 중")
                    Button("다시 확인") { load() }.buttonStyle(MatchPixelButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if let replay,let saved=displaySnapshot.match {inplayStage(replay,match:visualSnapshot ?? saved)}
            if let homeRunReplay,let saved=displaySnapshot.match {homeRunStage(homeRunReplay,match:visualSnapshot ?? saved)}
        }
        .toolbar((replay != nil || homeRunReplay != nil) ? .hidden:.visible,for:.navigationBar)
        .background(Color(hex: 0x18334b)).foregroundStyle(Color(hex: 0xeee9cd))
        .navigationTitle(player.role.label+(assessmentID == nil ? " 경기":" 평가전")).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: 0x18334b), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("경기 계획·출전 선수") { showGameDetails = true }
                    if let saved = displaySnapshot.match {
                        if let last = saved.fieldPlays?.last {
                            Button("직전 수비·주루 다시 보기") {
                                visualSnapshot = saved; presenting = true; fieldResolved = false; fieldHandoff = nil; replay = last
                            }.accessibilityIdentifier("replayLastFieldPlay")
                        }
                        if let last = saved.homeRuns?.last {
                            Button("최근 홈런 다시 보기") {
                                visualSnapshot = saved; presenting = true; fieldResolved = false; fieldHandoff = nil; homeRunReplay = last
                            }.accessibilityIdentifier("replayLastHomeRun")
                        }
                    }
                    Picker("인플레이 재생",selection:Binding(get:{fieldPlaybackMode.menuValue},set:{fieldPlaybackRaw=$0})) {
                        ForEach(FieldPlaybackMode.allCases,id:\.rawValue) { mode in Text(mode.label).tag(mode.rawValue) }
                    }
                } label: { Text("메뉴").font(.caption.bold()).frame(minWidth:44,minHeight:44) }
                    .disabled(inputLocked).accessibilityIdentifier("gamePlaybackMenu").accessibilityValue(fieldPlaybackMode.label)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let record, !record.completed {
                    Button(record.appearance ? "자동" : "팀 진행") { confirmAutomatic = true }
                        .font(.caption.bold()).frame(minWidth: 44, minHeight: 44)
                        .disabled(inputLocked).accessibilityIdentifier("gameAutomatic")
                }
            }
        }
        .sheet(isPresented: $showGameDetails) {
            NavigationStack {
                ScrollView {
                    if let match = displaySnapshot.match {
                        VStack(spacing: 12) {
                            if let plan = match.preparation {
                                NavigationLink("경기 계획 · " + plan.choice.label) {
                                    MatchOpponentCenter(analysis: plan.analysis, fielders: match.npcFielders?.team(home: !match.isHome),
                                        ownRole: match.role, ownRatings: MatchOpponentCenter.ratings(player: player, stats: match.abilityStats, match: match),
                                        teamName: CareerTeamDirectory.name(plan.analysis.teamID, schools: schools), ownTeamName: CareerTeamDirectory.name((try? calendar.teamID(for: player, on: GameDate(record?.gameDate ?? player.gameDate))) ?? player.schoolID, schools: schools),
                                        date: record?.gameDate ?? player.gameDate, activePitcher: match.opponentPitcher, season: plan.season, locked: true,
                                        progress: MatchPlanOutcome.make(match: match, includingLive: true), choice: .constant(plan.choice))
                                }.accessibilityIdentifier("openLiveGamePlan")
                            }
                            MatchNPCFieldersPanel(match: match, schools: schools)
                        }.padding()
                    }
                }.background(GameTheme.board).foregroundStyle(GameTheme.paper).navigationTitle("경기 정보")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { showGameDetails = false } } }
            }
        }
        .onAppear {
            #if DEBUG
            if livePerformanceQA {MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true;MatchRenderMetrics.mark("career.enter")}
            #endif
            load(); configureScene()
        }
        .onChange(of: record.map(MatchDisplaySnapshot.Token.init)) { _, _ in
            guard let record else { return }
            do { try displaySnapshot.refresh(record) } catch { self.error = error.localizedDescription }
        }
        #if DEBUG
        .task {await runLiveCareerQA()}
        .onChange(of:fieldCoversArena) {_,covered in
            guard ProcessInfo.processInfo.arguments.contains("-match-render-performance") else {return}
            if livePerformanceQA {
                MatchRenderMetrics.mark(covered ? "career.inplay.enter":"career.inplay.exit")
                if !covered {MatchRenderMetrics.exportLive(role:player.role.rawValue+"-actual-inplay-\(Int(ProcessInfo.processInfo.systemUptime*1000))")}
                return
            }
            if covered {MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true}
            else {MatchRenderMetrics.exportLive(role:player.role.rawValue+(preparesFieldMotion ? (ProcessInfo.processInfo.arguments.contains("-field-canvas-comparison") ? "-canvas":"-sprite"):"-baseline"));MatchRenderMetrics.enabled=false}
        }
        #endif
        .onChange(of: opponentSide) { _, _ in configureScene() }
        .task(id: pulseAt) {
            guard pulse != nil else { return }
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            if !Task.isCancelled { pulse = nil }
        }
        .onDisappear {
            #if DEBUG
            if livePerformanceQA {MatchRenderMetrics.mark("career.exit");MatchRenderMetrics.exportLive(role:player.role.rawValue+"-actual-career-\(Int(ProcessInfo.processInfo.systemUptime*1000))");MatchRenderMetrics.enabled=false}
            #endif
            cancelInput()
        }
        .onChange(of: clock.phase) { _, phase in
            if player.role == .pitcher && clock.running { scene.preparePitch(phase: phase, reduced: reduced) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                #if DEBUG
                if livePerformanceQA {MatchRenderMetrics.mark("career.inactive");MatchRenderMetrics.exportLive(role:player.role.rawValue+"-actual-career-interrupted-\(Int(ProcessInfo.processInfo.systemUptime*1000))")}
                #endif
                cancelInput()
            }
        }
        .confirmationDialog("남은 경기를 자동으로 진행할까요?", isPresented: $confirmAutomatic, titleVisibility: .visible) {
            Button("진행하고 결과 저장") { advance(.automatic) }
        } message: { Text(assessmentID == nil ? "현재 카운트·주자에서 이어서 진행합니다. 실제 출전 성적과 피로를 반영하며 취소할 수 없습니다.":"현재 평가 경기의 카운트·주자에서 이어서 진행합니다. 자동 입력을 구분해 평가전 원장에 저장합니다.") }
        .alert("경기를 저장하지 못했습니다", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct MatchControlsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 110 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Relative movement uses one origin for the whole gesture; crossing the threshold remains a swipe.
struct MatchBattingSwipe {
    let x: Double
    let y: Double
    private(set) var maxDistance = 0.0
    var isTap: Bool { maxDistance < 10 }
    mutating func move(_ translation: CGSize, field: CGSize) -> CGPoint {
        maxDistance = max(maxDistance, hypot(translation.width, translation.height))
        guard !isTap else { return CGPoint(x: x, y: y) }
        return CGPoint(x: min(1, max(0, x + translation.width / max(1, field.width * 0.65))),
                       y: min(1, max(0, y + translation.height / max(1, field.height * 0.65))))
    }
}

private struct MatchNPCFieldersPanel:View {
    let match:CareerMatch
    let schools:[School]
    @State private var expanded=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Button(expanded ? "출전 야수 능력치 · 접기":"출전 야수 능력치 · 펼치기") {expanded.toggle()}
                .font(.subheadline.bold()).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                .buttonStyle(.plain).accessibilityIdentifier("gameNPCFielders")
            if expanded {
                if let roster=match.npcFielders {
                    Text("NPC v\(roster.version) · \(roster.year)시즌 · 게임용 가상 기량")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    ForEach([true,false],id:\.self) {home in
                        let team=roster.team(home:home)
                        Text(CareerTeamDirectory.name(team.teamID,schools:schools)+" · 기본 전력 \(Int(team.strength))")
                            .font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        ForEach(team.players,id:\.id) {npc in
                            let own=home == match.isHome && match.appearance && (match.role != "pitcher" || match.ownPitcherActive) && npc.position == match.fieldStats?.position
                            let speed=own ? match.fieldStats?.speed ?? npc.speed:npc.speed
                            let defense=own ? match.fieldStats?.defense ?? npc.defense:npc.defense
                            let arm=own ? match.fieldStats?.arm ?? npc.arm:npc.arm
                            Text("\(npc.position) \(own ? "내 선수":"가상 선수") · 스피드 \(speed,specifier:"%.1f") / 수비 \(defense,specifier:"%.1f") / 송구 \(arm,specifier:"%.1f")")
                                .font(.caption.monospaced()).accessibilityIdentifier("gameNPC-"+(home ? "home-":"away-")+npc.position)
                        }
                    }
                    Text("내 선수는 실제 능력치·특성이 우선합니다. NPC 값은 훈련·재실행으로 다시 뽑지 않습니다.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                } else {
                    Text("기존 경기 · 일반 야수는 스피드/수비/송구 60 기준 유지")
                        .font(.caption).accessibilityIdentifier("gameNPCLegacy")
                }
            }
        }.padding(10).background(GameTheme.boardPanel)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:1))
    }
}

private struct MatchArenaFrameKey:PreferenceKey {
    static let defaultValue:CGRect = .zero
    static func reduce(value:inout CGRect,nextValue:()->CGRect) {value=nextValue()}
}

// View-owned decoded data; store commands still validate the authoritative ledger.
@MainActor struct MatchDisplaySnapshot {
    struct Token: Equatable {
        let key: String
        let playerID: UUID
        let fixtureID: String
        let gameDate: String
        let opponentID: String
        let appearance: Bool
        let payload: Data
        let revision: Int
        let completed: Bool
        let fatigueBefore: Int
        let fatigueAfter: Int
        let rulesVersion: String
        init(_ record: CareerMatchRecord) {
            key=record.key;playerID=record.playerID;fixtureID=record.fixtureID;gameDate=record.gameDate
            opponentID=record.opponentID;appearance=record.appearance;payload=record.payload;revision=record.revision
            completed=record.completed;fatigueBefore=record.fatigueBefore;fatigueAfter=record.fatigueAfter;rulesVersion=record.rulesVersion
        }
    }
    private var token: Token?
    private var result: Result<CareerMatch, Error>?
    var match: CareerMatch? { try? result?.get() }
    #if DEBUG
    private(set) var decodeCount=0
    #endif
    @discardableResult mutating func refresh(_ record: CareerMatchRecord) throws -> CareerMatch {
        let next=Token(record)
        if token != next {
            token=next
            #if DEBUG
            decodeCount+=1
            #endif
            result=Result { try record.snapshot() }
        }
        guard let result else { throw MatchError.invalidRecord }
        return try result.get()
    }
}

enum FieldPlaybackMode: String, CaseIterable {
    case system, continuous, stills
    static var allCases:[Self] {[.system,.stills]}
    var menuValue:String {self == .continuous ? Self.system.rawValue:rawValue}
    var label: String {
        switch self {case .system,.continuous: "기본 재생";case .stills: "단계별 재생"}
    }
    func reducesMovement(system: Bool) -> Bool {
        switch self {case .system,.continuous: false;case .stills: true}
    }
}

/// Match the render lifecycle to the SKView's actual window, including its first attachment.
private struct MatchArenaSurface:UIViewRepresentable {
    let scene:BallparkScene
    let covered:Bool
    func makeUIView(context:Context)->MatchArenaSKView {
        let view=MatchArenaSKView(frame:.zero)
        view.ignoresSiblingOrder=true
        view.presentScene(scene)
        view.setCovered(covered)
        return view
    }
    func updateUIView(_ view:MatchArenaSKView,context:Context) {
        if view.scene !== scene {view.presentScene(scene)}
        view.setCovered(covered)
    }
    static func dismantleUIView(_ view:MatchArenaSKView,coordinator:()) {
        view.isPaused=true
        view.presentScene(nil)
    }
}

final class MatchArenaSKView:SKView {
    private var covered=false
    override init(frame:CGRect) {
        super.init(frame:frame)
        NotificationCenter.default.addObserver(self,selector:#selector(activated(_:)),name:UIScene.didActivateNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(deactivated(_:)),name:UIScene.willDeactivateNotification,object:nil)
    }
    required init?(coder:NSCoder) {fatalError("Storyboard initialization is not used")}
    deinit {NotificationCenter.default.removeObserver(self)}
    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshPause()
    }
    func setCovered(_ value:Bool) {covered=value;refreshPause()}
    private func refreshPause() {
        isPaused=covered || window?.windowScene?.activationState != .foregroundActive
    }
    @objc private func activated(_ notification:Notification) {
        guard let ownScene=window?.windowScene,notification.object as? UIScene === ownScene else {return}
        refreshPause()
    }
    @objc private func deactivated(_ notification:Notification) {
        guard let ownScene=window?.windowScene,notification.object as? UIScene === ownScene else {return}
        isPaused=true
    }
}

#if DEBUG
@MainActor private final class CareerEnduranceLog {
    struct Sample:Codable {
        let at:Double;let elapsed:Double;let bytes:UInt64?;let thermal:Int;let lowPower:Bool;let active:Bool
        let battery:Float;let batteryState:Int;let inplay:Bool;let clip:Int
    }
    struct Clip:Codable {let index:Int;let at:Double;let resolved:Bool}
    struct Report:Codable {
        let sessionStore:String;let role:String;let targetSeconds:Int;let elapsed:Double;let reason:String
        let unchanged:Bool?;let sampleFile:String;let samples:[Sample];let clips:[Clip]
    }
    let began=ProcessInfo.processInfo.systemUptime
    let role:String,session:String,target:Int,sampleURL:URL
    private let stream:FileHandle
    private var samples:[Sample]=[]
    var clips:[Clip]=[],reason="complete"
    var elapsed:Double {ProcessInfo.processInfo.systemUptime-began}
    init(role:String,session:String,seconds:Int) throws {
        self.role=role;self.session=session;target=seconds
        sampleURL=FileManager.default.temporaryDirectory.appendingPathComponent("qa-endurance-\(role)-\(Int(began*1000)).jsonl")
        FileManager.default.createFile(atPath:sampleURL.path,contents:nil)
        stream=try FileHandle(forWritingTo:sampleURL)
    }
    func sample(inplay:Bool,clip:Int,force:Bool=false) throws {
        let now=ProcessInfo.processInfo.systemUptime
        guard force || now-(samples.last?.at ?? 0)>=3 else {return}
        let active=UIApplication.shared.applicationState == .active && UIApplication.shared.connectedScenes.contains {$0.activationState == .foregroundActive}
        let sample=Sample(at:now,elapsed:elapsed,bytes:MatchRenderMetrics.footprint(),thermal:ProcessInfo.processInfo.thermalState.rawValue,
                          lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled,active:active,battery:UIDevice.current.batteryLevel,
                          batteryState:UIDevice.current.batteryState.rawValue,inplay:inplay,clip:clip)
        samples.append(sample)
        var data=try JSONEncoder().encode(sample);data.append(10);try stream.write(contentsOf:data)
        let progress=Report(sessionStore:session,role:role,targetSeconds:target,elapsed:elapsed,reason:"running",unchanged:nil,
                            sampleFile:sampleURL.lastPathComponent,samples:[sample],clips:clips.suffix(1).map {$0})
        try write(progress,name:"progress")
    }
    private func write(_ report:Report,name:String) throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("qa-endurance-\(name)-\(role).json")
        try JSONEncoder().encode(report).write(to:url,options:.atomic)
    }
    func finish(inplay:Bool,clip:Int,unchanged:Bool) throws {
        try sample(inplay:inplay,clip:clip,force:true)
        try write(Report(sessionStore:session,role:role,targetSeconds:target,elapsed:elapsed,reason:reason,unchanged:unchanged,
                         sampleFile:sampleURL.lastPathComponent,samples:samples,clips:clips),name:"final")
    }
    func close() {try? stream.close()}
}
#endif


struct CareerGameEntryView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let schools:[School]
    @Environment(\.modelContext) private var context
    @State private var season: MatchOpponentSeason?
    @State private var analysis:MatchOppositionAnalysis?
    @State private var fielders:MatchNPCTeam?
    @State private var ownRatings:[String:Double]=[:]
    @State private var ownTeamName="내 팀"
    @State private var choice:MatchPlanChoice?
    @State private var date=""
    @State private var revision=0
    @State private var enterGame=false
    @State private var failure:String?
    var body:some View {
        Group {
            if enterGame {CareerGameView(player:player,calendar:calendar,schools:schools)}
            else {
                VStack(spacing:0) {
                    if let analysis {
                        MatchOpponentCenter(analysis:analysis,fielders:fielders,ownRole:player.roleRaw,ownRatings:ownRatings,
                            teamName:CareerTeamDirectory.name(analysis.teamID,schools:schools),ownTeamName:ownTeamName,
                            date:date,season:season,choice:$choice,onStart:start)
                    } else if failure == nil {ProgressView("오늘 상대 자료 확인 중").frame(maxWidth:.infinity,maxHeight:.infinity)}
                    if let failure {
                        VStack(spacing:8) {
                            Text(failure).foregroundStyle(GameTheme.gold).accessibilityIdentifier("gamePlanError")
                            Button("자료 다시 확인") {load()}.buttonStyle(MatchPixelButtonStyle())
                        }.padding(12)
                    }
                }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                    .navigationTitle("상대 분석 · 경기 준비").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
            }
        }.task {load()}
    }
    private func load() {
        do {
            let fixture=try CareerMatchStore.today(player:player,state:calendar)
            if let _=try CareerMatchStore.record(player:player,fixture:fixture,in:context) {enterGame=true;return}
            if !fixture.isAppearance(for:player.role) {enterGame=true;return}
            let value=try CareerMatchStore.opposition(player:player,state:calendar)
            if let attack=value.attack {
                fielders=MatchNPCFielders.make(year:fixture.date.year,competition:attack.competition,homeID:fixture.homeID,awayID:fixture.awayID).team(home:fixture.homeID == value.teamID)
            }
            let profile=try PlayerAbilityStore.profile(playerID:player.id,in:context)
            let stats=profile.map {MatchAbilityStats(mental:$0.mental,velocity:$0.velocity,control:$0.control,stuff:$0.stuff,stamina:$0.stamina,fatigue:player.fatigue)}
            ownRatings=MatchOpponentCenter.ratings(player:player,stats:stats)
            ownTeamName=CareerTeamDirectory.name(try calendar.teamID(for:player,on:fixture.date),schools:schools)
            season = try CareerMatchStore.opponentSeason(player: player, state: calendar, analysis: value, in: context)
            analysis=value;date=player.gameDate;revision=calendar.revision
            choice=value.recommended(role:player.roleRaw);failure=nil
        } catch {analysis=nil;season=nil;failure=error.localizedDescription}
    }
    private func start() {
        guard let choice else {return}
        do {_ = try CareerMatchStore.startPrepared(player:player,state:calendar,choice:choice,date:date,revision:revision,in:context);enterGame=true;failure=nil}
        catch {failure=error.localizedDescription}
    }
}

struct MatchPlanOutcomePanel:View {
    let preparation:MatchPreparation
    let outcome:MatchPlanOutcome
    var body:some View {
        GamePanel(title:"GAME PLAN · 수행 결과",onBoard:true,contentSpacing:12) {
            Text(preparation.choice.label+" · "+outcome.label).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("gamePlanOutcome")
            Text(preparation.choice.criteria).font(.caption)
            ForEach(Array(outcome.checks.enumerated()),id:\.offset) {_,check in
                Text(check.detail+" · "+(check.met ? "충족":"미달")).font(.subheadline)
            }
            Text("다음28일 보고서에 실제 경기 근거로 기록합니다. 추가 XP나 계약 적합도 보너스는 없습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }
    }
}


// A read-only projection of the pregame/saved opponent. Only the existing start action writes a plan.
struct MatchOpponentCenter:View {
    enum Tab:String,CaseIterable {case pitcher,lineup,batter,plan
        var label:String {switch self {case .pitcher:"상대 투수";case .lineup:"9명 타선";case .batter:"타자 상세";case .plan:"경기 준비"}}
    }
    let analysis:MatchOppositionAnalysis
    let fielders:MatchNPCTeam?
    let ownRole:String
    let ownRatings:[String:Double]
    let teamName:String
    let ownTeamName:String
    let date:String
    var activePitcher:MatchNPCPitcher? = nil
    var season: MatchOpponentSeason? = nil
    var locked=false
    var progress:MatchPlanOutcome? = nil
    @Binding var choice:MatchPlanChoice?
    var onStart:(()->Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tab=Tab.pitcher
    @State private var selected=2
    @State private var showSeason=false
    @State private var showStatsInfo=false
    private var team:MatchNPCAttackTeam? {analysis.attack}
    private var pitcher:MatchNPCPitcher? {activePitcher ?? team?.starter}
    private var batter:MatchNPCBatter? {team.flatMap {$0.ordered.indices.contains(selected) ? $0.ordered[selected]:nil}}
    private var ink:Color {GameTheme.boardInk}
    private func n(_ value:Double) -> String {String(format:"%.1f",value)}
    private func pitchName(_ code:String) -> String {switch code {case "four-seam":"포심";case "slider":"슬라이더";case "changeup":"체인지업";case "fork":"포크";default:code}}
    @MainActor static func ratings(player:CareerPlayer,stats:MatchAbilityStats?,match:CareerMatch?=nil) -> [String:Double] {
        var result=["컨택":match?.contact ?? player.contact,"파워":match?.power ?? player.power,"선구안":match?.discipline ?? player.discipline]
        if let stats {result["멘탈"]=stats.mental;result["제구"]=stats.control;result["구위"]=stats.stuff}
        return result
    }
    var body:some View {
        VStack(spacing:0) {
            tabBar
            ScrollViewReader {proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        VStack(alignment:.leading,spacing:5) {
                            Text("BM · MATCH CENTER").font(.caption2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                            Text(tab.label).font(.title2.bold()).accessibilityIdentifier("opponentCenterTitle")
                            Text(teamName+" · "+ManagementDisplay.date(date)+(locked ? " · 저장된 경기 자료":" · 경기 시작 시 고정")).font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("oppositionTeam")
                        }.frame(maxWidth:.infinity,alignment:.leading).id("opponentTop")
                        switch tab {
                        case .pitcher:pitcherPage
                        case .lineup:lineupPage
                        case .batter:batterPage
                        case .plan:planPage
                        }
                    }.padding(12)
                }.onChange(of:tab) {_,_ in proxy.scrollTo("opponentTop",anchor:.top)}
            }
        }.background(GameTheme.board).foregroundStyle(ink)
            .safeAreaInset(edge:.bottom,spacing:0) {
                if !locked {
                    Button(tab == .plan ? "계획 확정 · 경기 시작":"경기 준비 · 계획 선택") {
                        if tab == .plan {onStart?()} else {tab = .plan}
                    }.buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(choice == nil)
                        .accessibilityIdentifier(tab == .plan ? "confirmGamePlan":"reviewOpponentPlan")
                        .padding(.horizontal,12).padding(.vertical,8).background(GameTheme.board)
                }
            }
            .alert("미집계 통계",isPresented:$showStatsInfo) {
                Button("확인",role:.cancel) {}
            } message: {
                Text("경기 전날까지 완료된 실제 경기·자동 경기 원장의 개인 성적입니다. 경기 시작 때 저장해 이어하기에서도 바꾸지 않습니다. 분모 0·과거 미수집·자책점 미채점은 미집계로 남기며 WAR·코스별 기록은 후속입니다.")
            }
    }
    private var tabBar:some View {
        let columns=Array(repeating:GridItem(.flexible(),spacing:4),count:typeSize.isAccessibilitySize ? 2:4)
        return LazyVGrid(columns:columns,spacing:4) {
            ForEach(Tab.allCases,id:\.self) {item in
                Button {tab=item} label: {Text(item.label).font(.caption.bold()).frame(maxWidth:.infinity,minHeight:44)}
                    .foregroundStyle(tab == item ? GameTheme.gold:GameTheme.boardMuted)
                    .background(tab == item ? GameTheme.boardPanel:GameTheme.board,ignoresSafeAreaEdges:[])
                    .overlay(alignment:.bottom) {Rectangle().fill(tab == item ? GameTheme.gold:GameTheme.boardLine.opacity(0.4)).frame(height:tab == item ? 3:1)}
                    .accessibilityIdentifier("opponentTab-"+item.rawValue).accessibilityValue(tab == item ? "선택됨":"선택 안 됨")
            }
        }.padding(.horizontal,8).padding(.bottom,8)
    }
    private func identity(title:String,eyebrow:String,detail:String) -> some View {
        HStack(alignment:.center,spacing:12) {
            VStack(alignment:.leading,spacing:10) {
                Text(eyebrow).font(.caption2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(title).font(.title2.bold()).accessibilityIdentifier("opponentIdentity")
                Text(detail).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                Text(teamName).font(.caption).foregroundStyle(GameTheme.boardMuted)
            }.frame(maxWidth:.infinity,alignment:.leading)
            VStack(spacing:4) {
                if let image=MatchArt.opponentPortrait {Image(uiImage:image).resizable().interpolation(.none).scaledToFit().frame(width:typeSize.isAccessibilitySize ? 64:100,height:typeSize.isAccessibilitySize ? 84:124)}
                Text("NPC 공용 도트").font(.caption2).foregroundStyle(GameTheme.boardMuted)
            }.accessibilityElement(children:.ignore).accessibilityLabel("상대 선수 공용 도트 이미지").accessibilityIdentifier("opponentPortrait")
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color(hex:0x203e52))
    }
    private var batterID: String? { batter.map { $0.position == "P" ? (team?.starter.id ?? $0.id) : $0.id } }
    private func seasonValues(_ id: String?, _ labels: [String]) -> [String] {
        labels.map { season?.player(id ?? "")?.value($0) ?? "미집계" }
    }
    private func statisticStrip(_ labels:[String], id: String?) -> some View {
        let columns=Array(repeating:GridItem(.flexible(),spacing:8),count:typeSize.isAccessibilitySize ? 2:min(4,labels.count))
        return VStack(alignment:.leading,spacing:0) {
            LazyVGrid(columns:columns,spacing:12) {
                ForEach(labels,id:\.self) {label in
                    VStack(alignment:.leading,spacing:6) {
                        Text(label).font(.caption2)
                        Text(seasonValues(id, [label])[0]).font(.subheadline.monospaced().bold()).lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.ignore).accessibilityLabel(label).accessibilityValue(seasonValues(id, [label])[0]).accessibilityIdentifier("opponentStat-"+label)
                }
            }.padding(14).foregroundStyle(Color(hex:0x153345)).background(Color(hex:0xeae4cc))
            HStack {
                Text(season.map { "\($0.through)까지 · 경기 전 고정" } ?? "이전 경기 · 시즌 자료 미기록").font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("opponentSeasonCutoff")
                Spacer()
                Button("통계 안내") {showStatsInfo=true}.font(.caption.bold()).foregroundStyle(GameTheme.gold).frame(minWidth:56,minHeight:44).accessibilityIdentifier("opponentStatsInfo")
            }.padding(.horizontal,12)
            if let row = season?.player(id ?? "") {
                Text(labels.contains("ERA") ? "\(row.pitchingGames)경기 · \(row.pitching.innings)이닝 · 자책 채점 \(row.earnedRunGames) / 미채점 \(row.unscoredPitchingGames)" : "\(row.battingGames)경기 · \(row.batting.plateAppearances)타석 · \(row.batting.atBats)타수")
                    .font(.caption.monospacedDigit()).padding(.horizontal, 12).padding(.bottom, 10).accessibilityIdentifier("opponentSeasonSample")
            }
            if let missing = season?.uncollectedGames, missing > 0 { Text("시즌 미수집 경기 \(missing)개 · 수집된 경기만 집계").font(.caption).foregroundStyle(GameTheme.gold).padding(.horizontal,12) }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("opponentUnrecordedStats")
    }
    @ViewBuilder private var pitcherPage:some View {
        if let pitcher {
            let shares=pitcher.selectionShares
            VStack(spacing:0) {
                identity(title:pitcher.id == team?.starter.id ? "선발 투수":"현재 구원 투수",eyebrow:pitcher.id == team?.starter.id ? "STARTER · PITCHING":"RELIEF · PITCHING",detail:String(format:"포심 %.0f km/h · 제구 %.1f",pitcher.fastball,pitcher.control))
                statisticStrip(["ERA","ER","WHIP","K/9"], id: pitcher.id)
            }.overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:1))
            GamePanel(title:"무엇을 던지는 투수인가",onBoard:true,contentSpacing:14) {
                Text(pitcher.id == team?.starter.id ? "선발 투수":"현재 구원 투수").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("opponentPitcherRole")
                Text(String(format:"포심 %.0f km/h · 제구 %.1f / 100",pitcher.fastball,pitcher.control)).font(.subheadline.bold()).accessibilityIdentifier("opponentPitcherRatings")
                let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:14)):AnyLayout(HStackLayout(spacing:14))
                layout {
                    OpponentPitchDonut(shares:shares).frame(width:110,height:110)
                    VStack(spacing:10) {
                        ForEach(Array(pitcher.pitches.enumerated()),id:\.element) {index,code in
                            HStack(spacing:6) {
                                Rectangle().fill(OpponentPitchDonut.colors[index%4]).frame(width:6,height:6).accessibilityHidden(true)
                                Text(pitchName(code)).font(.caption)
                                Spacer(minLength:4)
                                Text("\(shares[index])%").font(.caption.monospaced().bold())
                                Text(String(format:"%.0f km/h",pitcher.speed(code))).font(.caption2.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                            }.accessibilityElement(children:.combine).accessibilityIdentifier("opponentPitch-"+code)
                        }
                    }
                }.accessibilityElement(children:.contain).accessibilityIdentifier("opponentArsenal")
                Text("구종 선택 기준 비중 · 실제 사용률 아님").font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("opponentPitchShareMeaning")
                if let slow=pitcher.pitches.map({pitcher.speed($0)}).min() {
                    Text(String(format:"구종 간 최대 속도 차이 %.0f km/h",pitcher.fastball-slow)).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                }
                if let relief=team?.relief,pitcher.id != relief.id {
                    Text(String(format:"구원 대비 · 포심 %.0f km/h / 제구 %.1f",relief.fastball,relief.control)).font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            }
            GamePanel(title:"투구 능력",onBoard:true,contentSpacing:14) {
                OpponentAbilityBar(label:"구속 능력",value:pitcher.velocity)
                OpponentAbilityBar(label:"제구",value:pitcher.control)
                Text("0~100 능력 · 구속은 실제 비행 시간, 제구는 코스와 승부에 반영됩니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            unrecordedZone
        } else {legacyMissing}
    }
    @ViewBuilder private var lineupPage:some View {
        if let team {
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:14) {
                    HStack(alignment:.firstTextBaseline) {
                        VStack(alignment:.leading,spacing:4) {
                            Text("BATTING ORDER").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                            Text("상대 9명 타순").font(.title3.bold())
                        }
                        Spacer(minLength:8)
                        Text("능력 점수 / 100").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    let overviewLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:14)):AnyLayout(HStackLayout(alignment:.top,spacing:16))
                    overviewLayout {
                        OpponentLineupMeter(label:"출루 성향",value:team.onBase,color:GameTheme.growth)
                        OpponentLineupMeter(label:"장타 성향",value:team.slugging,color:GameTheme.gold)
                    }.accessibilityElement(children:.combine).accessibilityIdentifier("opponentLineupRatings")
                    Text("능력에서 계산한 성향 점수 · 실제 출루율·장타율과 구분").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }.padding(14).foregroundStyle(ink).background(GameTheme.boardPanel,in:ManagementStepFrame())
                    .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine,lineWidth:2))
                HStack(spacing:8) {
                    Button("능력 보기") {showSeason=false}.buttonStyle(MatchPixelButtonStyle(selected:!showSeason)).accessibilityIdentifier("opponentLineupAbilities")
                    Button("시즌 성적") {showSeason=true}.buttonStyle(MatchPixelButtonStyle(selected:showSeason)).accessibilityIdentifier("opponentLineupSeason")
                }
                HStack(spacing:8) {
                    Text(showSeason ? "경기 전 확정 성적":"타순별 기량 · 파워와 성향").font(.subheadline.bold())
                    Spacer(minLength:4)
                    Text("선택하면 상세 ›").font(.caption).foregroundStyle(GameTheme.gold)
                }.foregroundStyle(ink)
                LazyVStack(spacing:10) {
                    ForEach(Array(team.ordered.enumerated()),id:\.element.id) {index,player in
                        let seasonID=player.position == "P" ? team.starter.id:player.id
                        let seasonRow=season?.player(seasonID)
                        let values=seasonValues(seasonID,["AVG","OPS"])
                        Button {selected=index;tab = .batter} label: {
                            OpponentLineupTile(order:index+1,position:player.position,positionLabel:positionName(player.position),
                                               contact:player.contact,power:player.power,discipline:player.discipline,
                                               onBase:player.onBase,slugging:player.slugging,selected:index == selected,
                                               seasonMode:showSeason,average:values[0],ops:values[1],
                                               sample:seasonRow.map {"\($0.battingGames)경기 · \($0.batting.plateAppearances)타석"} ?? "표본 미집계")
                        }.buttonStyle(OpponentLineupTileStyle(selected:index == selected))
                            .accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(index+1)번 \(player.position) · "+(showSeason ? "타율 \(values[0]) · OPS \(values[1]) · "+(seasonRow.map {"\($0.battingGames)경기 \($0.batting.plateAppearances)타석"} ?? "표본 미집계") : "컨택 \(n(player.contact)) · 파워 \(n(player.power)) · 선구안 \(n(player.discipline)) · 출루 성향 \(n(player.onBase)) · 장타 성향 \(n(player.slugging))"))
                            .accessibilityHint("타자 상세 열기")
                            .accessibilityIdentifier("opponentBatter-\(index+1)")
                    }
                }
                Text(showSeason ? "경기 전날까지 완료된 원장만 표시합니다. 없는 성적은 미집계이며 WAR과 표본 범위는 타자 상세에서 확인합니다.":"초상화는 NPC 공용 도트입니다. 타순·포지션·능력은 경기 시작 자료를 사용합니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
        } else {legacyMissing}
    }
    @ViewBuilder private var batterPage:some View {
        if let batter {
            VStack(spacing:0) {
                identity(title:"\(selected+1)번 타자",eyebrow:"KEY BATTER · "+batter.position,detail:positionName(batter.position))
                statisticStrip(["AVG","OBP","SLG","OPS","HR","WAR"], id: batterID)
            }.overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:1))
            GamePanel(title:"선수의 강점",onBoard:true,contentSpacing:14) {
                if !typeSize.isAccessibilitySize {
                    OpponentRadar(values:batterAxes(batter)).frame(height:240).accessibilityIdentifier("opponentBatterRadar")
                }
                ForEach(Array(batterAxes(batter).enumerated()),id:\.offset) {_,axis in OpponentAbilityBar(label:axis.0,value:axis.1)}
                Text("경기 시작 시 고정하는 실제 NPC 능력입니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            GamePanel(title:"타석 공략 참고",onBoard:true,contentSpacing:12) {
                Text(batter.power >= 70 ? "장타 경계 · 가운데 실투 주의":batter.discipline >= 65 ? "선구안 경계 · 볼넷 억제":"컨택 경계 · 코스 변화 활용").font(.headline).foregroundStyle(GameTheme.gold)
                Text("출루 성향 \(n(batter.onBase)) · 장타 성향 \(n(batter.slugging))").font(.subheadline.monospacedDigit())
            }
            unrecordedZone
        } else {legacyMissing}
    }
    private func batterAxes(_ batter:MatchNPCBatter) -> [(String,Double)] {
        var axes=[("컨택",batter.contact),("파워",batter.power),("선구안",batter.discipline)]
        if let field=fielders?.players.first(where:{$0.id == batter.id}) {axes += [("스피드",field.speed),("수비",field.defense)]}
        return axes
    }
    private func positionName(_ raw:String) -> String {FieldPosition(rawValue:raw)?.label ?? (raw == "P" ? "투수":raw)}
    private func miniatureBar(_ value:Double,_ color:Color) -> some View {
        GeometryReader {g in Rectangle().fill(color).frame(width:g.size.width*min(100,max(0,value))/100)}.frame(height:4).background(GameTheme.boardLine.opacity(0.2))
    }
    private var planPage:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:10) {
                Text(ownTeamName).frame(maxWidth:.infinity)
                Text("VS").font(.title3.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(teamName).frame(maxWidth:.infinity)
            }.font(.headline).padding(16).background(GameTheme.boardPanel)
            if ownRole == "batter",let pitcher {
                identity(title:pitcher.id == team?.starter.id ? "상대 선발":"현재 구원",eyebrow:"PITCHING MATCHUP",detail:String(format:"포심 %.0f km/h · 제구 %.1f",pitcher.fastball,pitcher.control))
            } else if let team,let threat=team.ordered.max(by:{$0.onBase+$0.slugging<$1.onBase+$1.slugging}),let index=team.ordered.firstIndex(of:threat) {
                identity(title:"\(index+1)번 타자 · "+threat.position,eyebrow:"BATTING MATCHUP",detail:"출루 \(n(threat.onBase)) · 장타 \(n(threat.slugging))")
            }
            GamePanel(title:"능력 맞대결",onBoard:true,contentSpacing:14) {
                Text("내 선수 / 상대 · 같은 0~100 능력 비교, 승률 아님").font(.caption).foregroundStyle(GameTheme.boardMuted)
                if ownRole == "batter",let pitcher {
                    comparison("컨택 / 제구",ownRatings["컨택"],pitcher.control)
                    comparison("선구 / 제구",ownRatings["선구안"],pitcher.control)
                } else if let team {
                    comparison("제구 / 선구",ownRatings["제구"],team.batters.map(\.discipline).reduce(0,+)/9)
                    comparison("구위 / 컨택",ownRatings["구위"],team.batters.map(\.contact).reduce(0,+)/9)
                    comparison("멘탈 / 파워",ownRatings["멘탈"],team.batters.map(\.power).reduce(0,+)/9)
                } else {Text("이전 경기 · 상대 공격 능력 미기록").font(.caption)}
            }
            GamePanel(title:locked ? "고정된 경기 계획":"내 경기 계획",onBoard:true,contentSpacing:14) {
                Text("추천 · "+analysis.recommended(role:ownRole).label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                ForEach(MatchPlanChoice.choices(ownRole)) {plan in
                    Button {if !locked {choice=plan}} label: {
                        HStack(spacing:10) {
                            VStack(alignment:.leading,spacing:8) {
                                Text(plan.label).font(.headline)
                                Text(plan.criteria).font(.caption).multilineTextAlignment(.leading)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Rectangle().fill(choice == plan ? GameTheme.gold:GameTheme.boardLine.opacity(0.3)).frame(width:12,height:12)
                        }.padding(12)
                    }.buttonStyle(MatchPixelButtonStyle(selected:choice == plan)).disabled(locked)
                        .accessibilityIdentifier("planChoice-"+plan.rawValue).accessibilityValue(choice == plan ? "선택됨":"선택 안 됨")
                }
                if let choice {
                    Text(analysis.reason(for:choice)).font(.subheadline).accessibilityIdentifier("planReason")
                    Text(choice.executionHint).font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("planExecutionHint")
                }
                if locked,let progress {
                    Text("진행 중 · 최종 평가는 경기 종료 후").font(.caption).foregroundStyle(GameTheme.gold)
                    ForEach(Array(progress.checks.enumerated()),id:\.offset) {_,check in Text(check.detail).font(.subheadline.monospacedDigit())}
                }
                Text(locked ? "경기 시작 때 고정한 계획입니다. 변경할 수 없습니다.":"시작 시 상대 자료와 함께 저장·잠금됩니다. 선택 자체의 능력·계약 가산은 없습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
        }
    }
    private func comparison(_ label:String,_ own:Double?,_ other:Double) -> some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Text(own.map(n) ?? "미기록").foregroundStyle(GameTheme.growth)
                Spacer();Text(label).font(.caption).foregroundStyle(GameTheme.boardMuted);Spacer()
                Text(n(other)).foregroundStyle(GameTheme.gold)
            }.font(.subheadline.monospaced().bold())
            HStack(spacing:12) {miniatureBar(own ?? 0,GameTheme.growth);miniatureBar(other,GameTheme.gold)}.accessibilityHidden(true)
        }.accessibilityElement(children:.combine)
    }
    private var unrecordedZone:some View {
        GamePanel(title:"코스별·최근 성적",onBoard:true,contentSpacing:12) {
            ZStack {
                VStack(spacing:3) {ForEach(0..<3) {_ in HStack(spacing:3) {ForEach(0..<3) {_ in Rectangle().fill(GameTheme.boardLine.opacity(0.12))}}}}.frame(height:90).accessibilityHidden(true)
                Text("미집계").font(.headline).foregroundStyle(GameTheme.boardMuted)
            }.accessibilityIdentifier("opponentZoneUnrecorded")
            Text("실제 코스·개인 시즌 기록이 모인 뒤 표시합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }
    }
    private var legacyMissing:some View {
        GamePanel(title:"기존 경기의 상대 자료",onBoard:true,contentSpacing:14) {
            Text("투구·타격 프로필 미기록").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("legacyOpponentMissing")
            Text("이전 경기 자료와 판정을 유지하며, 없는 능력이나 성적을 생성하지 않습니다.").font(.caption)
            OpponentAbilityBar(label:"주력",value:analysis.speed)
            OpponentAbilityBar(label:"수비",value:analysis.defense)
            OpponentAbilityBar(label:"송구",value:analysis.arm)
        }
    }
}

private struct OpponentLineupTileStyle:ButtonStyle {
    let selected:Bool
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .foregroundStyle(GameTheme.boardInk)
            .background(selected ? Color(hex:0x203f3d):GameTheme.boardPanel,in:ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(selected ? GameTheme.gold:GameTheme.boardLine.opacity(0.7),lineWidth:2))
            .offset(y:configuration.isPressed ? 2:0)
    }
}

private struct OpponentLineupTile:View {
    let order:Int
    let position:String
    let positionLabel:String
    let contact:Double
    let power:Double
    let discipline:Double
    let onBase:Double
    let slugging:Double
    let selected:Bool
    let seasonMode:Bool
    let average:String
    let ops:String
    let sample:String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)):AnyLayout(HStackLayout(alignment:.top,spacing:12))
        layout {
            identity
            VStack(alignment:.leading,spacing:6) {
                HStack(alignment:.firstTextBaseline,spacing:8) {
                    Text(positionLabel).font(.subheadline.bold())
                    Spacer(minLength:0)
                    if selected {Text("선택").font(.caption.bold()).foregroundStyle(GameTheme.gold)}
                    Text("›").font(.headline).foregroundStyle(GameTheme.boardMuted)
                }
                if seasonMode {
                    let statsLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(spacing:16))
                    statsLayout {
                        seasonMetric("AVG · 타율",average)
                        seasonMetric("OPS",ops)
                    }
                    Text(sample).font(.caption.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                } else {
                    let numbersLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:4)):AnyLayout(HStackLayout(spacing:14))
                    numbersLayout {
                        rating("컨택",contact)
                        rating("선구안",discipline)
                    }
                    OpponentLineupMeter(label:"파워",value:power,color:GameTheme.gold)
                    let tendencyLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(alignment:.top,spacing:12))
                    tendencyLayout {
                        OpponentLineupMeter(label:"출루 성향",value:onBase,color:GameTheme.growth,compact:true)
                        OpponentLineupMeter(label:"장타 성향",value:slugging,color:Color(hex:0x8bb8d0),compact:true)
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private var identity:some View {
        let layout=typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing:10)):AnyLayout(VStackLayout(spacing:4))
        return layout {
            Text(String(order)).font(.title2.monospaced().bold()).foregroundStyle(GameTheme.navy)
                .frame(minWidth:44,minHeight:32).background(GameTheme.gold,in:ManagementStepFrame())
            if let image=MatchArt.opponentPortrait {
                Image(uiImage:image).resizable().interpolation(.none).scaledToFit().frame(width:44,height:54).accessibilityHidden(true)
            }
            Text(position).font(.caption.monospaced().bold()).foregroundStyle(GameTheme.boardMuted)
        }
    }
    private func rating(_ label:String,_ value:Double) -> some View {
        HStack(spacing:4) {
            Text(label).foregroundStyle(GameTheme.boardMuted)
            Text(String(format:"%.1f",value)).monospacedDigit().bold()
        }.font(.caption).fixedSize(horizontal:false,vertical:true)
    }
    private func seasonMetric(_ label:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(label).font(.caption).foregroundStyle(GameTheme.boardMuted)
            Text(value).font(.title3.monospaced().bold()).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// Each lit segment is an ability-score interval, never a measured event probability.
private struct OpponentLineupMeter:View {
    let label:String
    let value:Double
    let color:Color
    var compact=false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:3)):AnyLayout(HStackLayout(alignment:.firstTextBaseline,spacing:4))
            layout {
                Text(label).font(.caption).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal:false,vertical:true)
                if !typeSize.isAccessibilitySize {Spacer(minLength:0)}
                Text(String(format:"%.1f",value)).font(compact ? .caption.monospaced().bold():.subheadline.monospaced().bold()).foregroundStyle(color).layoutPriority(1)
            }
            HStack(spacing:2) {
                ForEach(0..<10) {segment in
                    GeometryReader {geometry in
                        let fill=min(1,max(0,min(100,max(0,value))/10-Double(segment)))
                        ZStack(alignment:.leading) {
                            Rectangle().fill(GameTheme.boardLine.opacity(0.22))
                            Rectangle().fill(color).frame(width:geometry.size.width*fill)
                        }
                    }
                }
            }.frame(height:compact ? 6:9).accessibilityHidden(true)
        }.frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityElement(children:.ignore).accessibilityLabel(label+String(format:" %.1f / 100",value))
    }
}

private struct OpponentAbilityBar:View {
    let label:String
    let value:Double
    var color=GameTheme.growth
    var body:some View {
        HStack(spacing:10) {
            Text(label).font(.caption).frame(minWidth:52,alignment:.leading)
            GeometryReader {g in
                ZStack(alignment:.leading) {
                    Rectangle().fill(GameTheme.boardLine.opacity(0.2))
                    Rectangle().fill(color).frame(width:g.size.width*min(100,max(0,value))/100)
                    Rectangle().fill(GameTheme.boardInk.opacity(0.5)).frame(width:1).offset(x:g.size.width*0.6)
                }
            }.frame(height:10).accessibilityHidden(true)
            Text(String(format:"%.1f",value)).font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold).frame(minWidth:40,alignment:.trailing)
        }.accessibilityElement(children:.ignore).accessibilityLabel(label+String(format:" %.1f / 100",value))
    }
}

private struct OpponentPitchDonut:View {
    let shares:[Int]
    static let colors=[GameTheme.gold,GameTheme.growth,Color(hex:0x8bb8d0),GameTheme.boardLine]
    var body:some View {
        ZStack {
            Canvas {context,size in
                let center=CGPoint(x:size.width/2,y:size.height/2),radius=min(size.width,size.height)*0.39
                var angle = -Double.pi/2
                for (index,value) in shares.enumerated() {
                    let end=angle+Double(value)/100*2*Double.pi
                    var path=Path();path.addArc(center:center,radius:radius,startAngle:.radians(angle+0.025),endAngle:.radians(end-0.025),clockwise:false)
                    context.stroke(path,with:.color(Self.colors[index%4]),lineWidth:14);angle=end
                }
            }
            VStack(spacing:3) {Text("50%").font(.title3.monospaced().bold()).foregroundStyle(GameTheme.gold);Text("포심 기준").font(.caption2).foregroundStyle(GameTheme.boardMuted)}
        }.accessibilityElement(children:.ignore).accessibilityLabel("구종 선택 기준 비중 "+shares.map {"\($0)%"}.joined(separator:", "))
    }
}

private struct OpponentRadar:View {
    let values:[(String,Double)]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing:10) {ForEach(Array(values.enumerated()),id:\.offset) {_,v in OpponentAbilityBar(label:v.0,value:v.1)}}
        } else {
            GeometryReader {g in
                let center=CGPoint(x:g.size.width/2,y:g.size.height/2),radius=min(g.size.width,g.size.height)*0.32
                ZStack {
                    Canvas {context,_ in
                        func point(_ i:Int,_ value:Double) -> CGPoint {
                            let a=Double(i)*2*Double.pi/Double(values.count)-Double.pi/2,r=radius*min(100,max(0,value))/100
                            return CGPoint(x:center.x+cos(a)*r,y:center.y+sin(a)*r)
                        }
                        func polygon(_ scores:[Double]) -> Path {
                            Path {p in for (i,v) in scores.enumerated() {let at=point(i,v);if i == 0 {p.move(to:at)} else {p.addLine(to:at)}};p.closeSubpath()}
                        }
                        for level in [25.0,50,75,100] {context.stroke(polygon(Array(repeating:level,count:values.count)),with:.color(GameTheme.boardLine.opacity(0.45)),lineWidth:1)}
                        let path=polygon(values.map(\.1));context.fill(path,with:.color(GameTheme.growth.opacity(0.2)));context.stroke(path,with:.color(GameTheme.growth),lineWidth:2)
                        for (i,v) in values.enumerated() {let at=point(i,v.1);context.fill(Path(CGRect(x:at.x-2,y:at.y-2,width:4,height:4)),with:.color(GameTheme.gold))}
                    }
                    ForEach(Array(values.enumerated()),id:\.offset) {i,v in
                        let a=Double(i)*2*Double.pi/Double(values.count)-Double.pi/2
                        VStack(spacing:3) {Text(v.0).foregroundStyle(GameTheme.boardMuted);Text(String(format:"%.1f",v.1)).bold()}
                            .font(.caption).frame(width:64).position(x:center.x+cos(a)*radius*1.3,y:center.y+sin(a)*radius*1.3)
                    }
                }
            }.accessibilityElement(children:.ignore).accessibilityLabel(values.map {$0.0+String(format:" %.1f",$0.1)}.joined(separator:", "))
        }
    }
}
