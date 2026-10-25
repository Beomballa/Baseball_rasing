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
                    let started = scene.demonstrate(reduceMotion: reduced, flightDuration: previous.delivery(pitchCode: result.pitchCode).duration,
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
        clock.stop(); attempt = nil; judgment = nil; arrivedSnapshot = nil; presenting = false; visualSnapshot = nil; replay=nil;homeRunReplay=nil;homeRunResultPlaying=false;fieldHandoff=nil;fieldResolved=false;resultReplayPlay=nil;animateResultReplay=false;pulse = nil; scene.cancelDelivery()
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
                                 perfect: match.releasePerfectWidth(mastery: mastery), label: (replay != nil || homeRunReplay != nil) ? "수비·주루 진행 중" : presenting ? (judgment == nil ? "릴리스 확정 · 공 비행 중" : "포구 완료 · 판정 확인") : clock.running ? "팔 준비 중 · 노란 구간에 릴리스" : "릴리스 · 숙련도 \(mastery.formatted(.number.precision(.fractionLength(1))))")
                    .accessibilityIdentifier("releaseGauge")
                Button((replay != nil || homeRunReplay != nil) ? "수비·주루 진행 중…" : presenting ? (judgment == nil ? "공 비행·포구 중…" : "판정 확인 중…") : clock.running ? "지금 릴리스" : "투구 준비") {
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
                Button(presenting ? ((replay != nil || homeRunReplay != nil) ? "수비·주루 진행 중…" : "타격·판정 확인 중…") : clock.running ? (battingAction == .watch ? "공을 지켜보는 중" : "지금 \(battingAction.label)") : "투구 요청") {
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
                Text(assessmentID == nil ? CareerTeamDirectory.name((try? calendar.teamID(for:player,on:GameDate(record.gameDate))) ?? player.schoolID,schools:schools):"내 평가팀").lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.65)
                Text("\(match.teamScore) : \(match.opponentScore)").font(.system(.title3, design: .monospaced, weight: .bold)).foregroundStyle(GameTheme.gold)
                Text(CareerTeamDirectory.name(record.opponentID,schools:schools)).lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.65)
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
                        if let record, let savedMatch = displaySnapshot.match {
                            let match = visualSnapshot ?? savedMatch
                            VStack(spacing: 6) {
                                scoreHeader(arrivedSnapshot ?? match, record: record)
                                if assessmentID != nil {Text("목표 수준 평가전 · 표준 조건 / 공식 기록 제외").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("interactiveAssessmentLabel")}
                                if let plan=match.preparation {Text("경기 계획 · "+plan.choice.label).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("activeGamePlan")}
                                if typeSize.isAccessibilitySize && !match.completed {
                                    Button("경기 조작부로 이동") { proxy.scrollTo("gameControls", anchor: .bottom) }
                                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("gameJumpControls")
                                }
                            }.background { measure("header") }
                            if match.completed {
                                if !fieldCoversArena {
                                    if assessmentID != nil {assessmentResults(match)} else {results(match, record: record)}
                                }
                            } else {
                                arena(match, field: MatchPresentation.fieldSize(
                                    available: CGSize(width: max(1, geometry.size.width - 16), height: geometry.size.height),
                                    role: player.role, chromeHeight: chromeHeights.values.reduce(0, +) + 28))
                                VStack(spacing: 6) {
                                    if match.pitching != nil {Text("현재 투수 · " + (arrivedSnapshot ?? match).pitchingLabel).font(.caption.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("activePitcherLabel")}
                                    MatchScoreStrip(match: arrivedSnapshot ?? match, pitchCount: player.role == .pitcher ? (arrivedSnapshot ?? match).line.pitches : nil, pulse: pulse, pulseAt: pulseAt)
                                    if player.role == .pitcher, typeSize.isAccessibilitySize, replay == nil && homeRunReplay == nil {
                                        HStack {
                                            if match.opponentBatterSide.mapOnRight { Spacer(minLength: 0) }
                                            PitchLocationBoard(result: judgment ?? (arrivedSnapshot ?? match).lastManual, side: match.opponentBatterSide).frame(width: 140)
                                            if !match.opponentBatterSide.mapOnRight { Spacer(minLength: 0) }
                                        }
                                    }
                                    if let judgment, typeSize.isAccessibilitySize {
                                        PitchJudgmentToast(title: DeliveryPresentation.call(judgment.outcome),
                                                           detail: "\(MatchPresentation.pitchName(judgment)) · \(judgment.speed) km/h")
                                            .accessibilityIdentifier("pitchJudgmentToast")
                                    }
                                    Text((replay != nil || homeRunReplay != nil) && !fieldResolved ? "인플레이 · 수비 진행 중" : (arrivedSnapshot ?? match).lastManual.map { "\($0.grade) · \($0.outcome)" }
                                         ?? (match.completed ? match.message : player.role == .batter ? "조준 → 투구 요청 → 타격" : "그립 선택 → 투구 준비 → 릴리스"))
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 20)
                                        .accessibilityIdentifier("careerGameMessage")
                                    if let last=savedMatch.homeRuns?.last {
                                        Button("최근 홈런 다시 보기") {
                                            visualSnapshot=savedMatch;presenting=true;fieldResolved=false;fieldHandoff=nil;homeRunReplay=last
                                        }.buttonStyle(MatchPixelButtonStyle()).disabled(inputLocked).accessibilityIdentifier("replayLastHomeRun")
                                    }
                                    #if DEBUG
                                    if ProcessInfo.processInfo.arguments.contains("-match-render-performance"),let ground=savedMatch.fieldPlays?.last(where:InplayFieldScene.isOrdinaryGround) {
                                        Button("일반 땅볼 비교 재생") {
                                            visualSnapshot=savedMatch;presenting=true;fieldResolved=false;fieldHandoff=nil;replay=ground
                                        }.buttonStyle(MatchPixelButtonStyle()).disabled(inputLocked).accessibilityIdentifier("replayGroundComparison")
                                    }
                                    #endif
                                    if let last=savedMatch.fieldPlays?.last {
                                        Button("직전 수비·주루 다시 보기") {
                                            visualSnapshot=savedMatch;presenting=true;fieldResolved=false;fieldHandoff=nil;replay=last
                                        }.buttonStyle(MatchPixelButtonStyle()).disabled(inputLocked).accessibilityIdentifier("replayLastFieldPlay")
                                    }
                                    VStack(spacing: 6) { controls(match) }
                                }.id("gameControls").background { measure("controls") }
                            }
                            MatchNPCFieldersPanel(match:match,schools:schools)
                        } else {
                            Text(error ?? "경기 불러오는 중")
                            Button("다시 확인") { load() }.buttonStyle(MatchPixelButtonStyle())
                        }
                    }.padding(8).frame(maxWidth: .infinity)
                }.onPreferenceChange(MatchChromeHeightKey.self) { chromeHeights = $0 }
                    .accessibilityHidden((replay != nil || homeRunReplay != nil))
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
                    Picker("인플레이 재생",selection:Binding(get:{fieldPlaybackMode.menuValue},set:{fieldPlaybackRaw=$0})) {
                        ForEach(FieldPlaybackMode.allCases,id:\.rawValue) { mode in Text(mode.label).tag(mode.rawValue) }
                    }
                } label: { Text("재생").font(.caption.bold()).frame(minWidth:44,minHeight:44) }
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

private struct MatchChromeHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
    @State private var analysis:MatchOppositionAnalysis?
    @State private var choice:MatchPlanChoice?
    @State private var date=""
    @State private var revision=0
    @State private var enterGame=false
    @State private var failure:String?
    var body:some View {
        Group {
            if enterGame {CareerGameView(player:player,calendar:calendar,schools:schools)}
            else {
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        if let analysis {
                            GamePanel(title:"OPPOSITION FILE · 상대 분석",onBoard:true,contentSpacing:12) {
                                Text(CareerTeamDirectory.name(analysis.teamID,schools:schools)).font(.title3.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("oppositionTeam")
                                Text(date+" · 시즌 고정 NPC 로스터 기준").font(.caption)
                                HStack {
                                    metric("주력",analysis.speed);metric("수비",analysis.defense);metric("송구",analysis.arm)
                                }
                                ForEach(analysis.tendencies,id:\.self) {Text($0).font(.subheadline)}
                                Text("상대 수비 내 최저 수비 포지션 · "+analysis.weakestPosition).font(.caption)
                                Text("실제 경기의 가상 선수 능력값입니다. 구종·타격 성향은 자료가 없어 추정하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                            }
                            GamePanel(title:"GAME PLAN · 오늘의 계획",onBoard:true,contentSpacing:12) {
                                Text("추천 · "+analysis.recommended(role:player.roleRaw).label).font(.headline).foregroundStyle(GameTheme.gold)
                                ForEach(MatchPlanChoice.choices(player.roleRaw)) {plan in
                                    Button {choice=plan} label: {
                                        VStack(alignment:.leading,spacing:6) {
                                            HStack(spacing:8) {
                                                Rectangle().fill(choice == plan ? GameTheme.gold:GameTheme.boardLine).frame(width:8,height:8)
                                                Text(plan.label).font(.headline)
                                            }
                                            Text(plan.criteria).font(.caption).multilineTextAlignment(.leading)
                                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                                    }.buttonStyle(MatchPixelButtonStyle(selected:choice == plan)).accessibilityIdentifier("planChoice-"+plan.rawValue).accessibilityValue(choice == plan ? "선택됨":"선택 안 됨")
                                }
                                Text("계획은 경기 시작과 함께 저장·잠금됩니다. 조작은 기존 방식으로 진행하며,선택만으로 능력치나 판정 보너스가 붙지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                                Button("계획 확정 · 경기 시작") {start()}.buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(choice == nil).accessibilityIdentifier("confirmGamePlan")
                            }
                        } else if failure == nil {ProgressView("오늘 상대 자료 확인 중")}
                        if let failure {
                            Text(failure).foregroundStyle(GameTheme.gold).accessibilityIdentifier("gamePlanError")
                            Button("자료 다시 확인") {load()}.buttonStyle(MatchPixelButtonStyle())
                        }
                    }.padding(12)
                }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("상대 분석 · 경기 준비").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
            }
        }.task {load()}
    }
    private func metric(_ label:String,_ value:Double) -> some View {
        VStack(alignment:.leading,spacing:6) {Text(label).font(.caption);Text(String(format:"%.1f",value)).font(.headline.monospaced()).foregroundStyle(GameTheme.gold)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func load() {
        do {
            let fixture=try CareerMatchStore.today(player:player,state:calendar)
            if let _=try CareerMatchStore.record(player:player,fixture:fixture,in:context) {enterGame=true;return}
            if !fixture.isAppearance(for:player.role) {enterGame=true;return}
            analysis=try CareerMatchStore.opposition(player:player,state:calendar);date=player.gameDate;revision=calendar.revision
            choice=analysis?.recommended(role:player.roleRaw);failure=nil
        } catch {failure=error.localizedDescription}
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
