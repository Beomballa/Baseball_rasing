import SwiftUI
import SpriteKit
import SwiftData

struct MatchView: View {
    let player: CareerPlayer
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDelivery = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 400))
    @State private var cue = "투구 모션과 경기장 연결을 확인해 보세요."
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(player.name) · \(player.role.label)").font(.headline)
                    Text("\(player.schoolName) · \(player.roleDetail)").font(.caption)
                }
                Spacer()
                Text("연습 장면").font(.caption.bold()).padding(8).background(GameTheme.gold).foregroundStyle(GameTheme.navy)
            }
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .aspectRatio(1219.0 / 1290, contentMode: .fit)
                .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 3))
                .accessibilityLabel("투수 뒤에서 보는 도트 연습장")
                .accessibilityIdentifier("spriteKitField")
            Text(cue).font(.subheadline).multilineTextAlignment(.center)
                .accessibilityIdentifier("matchCue")
            Button(showingDelivery ? "포수 수신 확인 중…" : "투구 연습 보기") {
                guard !showingDelivery else { return }
                showingDelivery = true; cue = "손에서 릴리스 → 포수 수신 · 동작 진행 중"
                do {
                    let code = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "four-seam"
                    let velocity = player.role == .pitcher ? try CareerTrainingStore.value(player: player, code: nil, kind: .velocity, in: context) : 62.5
                    let delivery = MatchDelivery.pitch(code: code, velocity: velocity)
                    let started = scene.demonstrate(reduceMotion: reduceMotion, flightDuration: PitchFlightPresentation(delivery: delivery).flightDuration, pitchCode: code,
                        onArrival: { cue = "포수 수신 완료 · \(delivery.speed) km/h · 기록/피로 변화 없음" },
                        completion: { showingDelivery = false })
                    if !started { showingDelivery = false }
                } catch { showingDelivery = false; cue = "시연 속도 조회 실패 · " + error.localizedDescription }
            }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(showingDelivery).accessibilityIdentifier("demoPitch")
            Text("이곳은 동작 시연입니다. 공식 카운트·성적은 홈의 경기에서 확인하세요.")
                .font(.caption).foregroundStyle(GameTheme.boardMuted)
            Spacer(minLength: 0)
        }
        .padding(16).background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        .preferredColorScheme(.dark)
        .navigationTitle("경기장").navigationBarTitleDisplayMode(.inline)
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, appearance: player.appearance, jerseyNumber: player.jerseyNumber) }
        .onDisappear { scene.cancelDelivery(); showingDelivery = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scene.cancelDelivery(); showingDelivery = false }
        }
    }
}


@MainActor enum TrainingPractice {
    static func round(player: CareerPlayer, calendar: CareerCalendarState, kind: TrainingKind, code: String = "",
                      position: FieldPosition? = nil, in context: ModelContext) throws -> CareerTraining {
        let before: Double
        if let position {
            guard let profile = try PlayerPositionStore.profile(playerID: player.id, in: context) else { throw TrainingError.invalidRecord }
            before = try profile.snapshot().skill(position).mastery
        } else {
            before = try CareerTrainingStore.value(player: player, code: kind == .pitch ? code : nil, kind: kind, in: context)
        }
        var round = CareerTraining(playerID: UUID(), date: player.gameDate, role: player.roleRaw,
                                   pitchCode: kind == .pitch ? code : nil, before: before, fatigue: 0,
                                   age: try calendar.age(of: player), calendarRevision: 0, kind: kind, position: position)
        if position != nil { round.positionRevision = 0; round.positionXP = 0 }
        else if SkillDrillRules.kinds.contains(kind) { round.drillVersion = 1 }
        return round
    }
    static func copy(_ original: CareerPlayer, from source: ModelContext, into memory: ModelContext) throws -> CareerPlayer {
        guard let abilities = try PlayerAbilityStore.profile(playerID: original.id, in: source),
              let state = try source.fetch(FetchDescriptor<CareerCalendarState>()).first(where: { $0.playerID == original.id }) else {
            throw TrainingError.invalidRecord
        }
        var draft = PlayerDraft()
        draft.name = original.name; draft.jerseyNumber = String(original.jerseyNumber); draft.role = original.role
        draft.position = FieldPosition(rawValue: original.positionRaw) ?? .center
        draft.throwingHand = ThrowingHand(rawValue: original.throwingHandRaw) ?? .right
        draft.appearance = original.appearance
        let copy = CareerPlayer(draft: draft, school: School(id: original.schoolID, region: "", name: original.schoolName))
        copy.positionRaw = original.positionRaw; copy.throwingHandRaw = original.throwingHandRaw
        copy.gameDate = original.gameDate; copy.startAge = original.startAge; copy.fatigue = 0
        copy.contact = original.contact; copy.power = original.power; copy.discipline = original.discipline
        copy.speed = original.speed; copy.defense = original.defense; copy.arm = original.arm
        copy.pitches = original.pitches.map { CareerPitchMastery(code: $0.code, name: $0.name, mastery: $0.mastery, order: $0.order) }
        let profile = try PlayerAbilities(player: copy, archetype: nil)
        profile.archetypeRaw = abilities.archetypeRaw; profile.productionPresetVersion = abilities.productionPresetVersion
        profile.initialValues = abilities.initialValues; profile.mental = abilities.mental
        profile.velocity = abilities.velocity; profile.control = abilities.control; profile.stuff = abilities.stuff; profile.stamina = abilities.stamina
        let calendar = CareerCalendarState(player: copy, schools: try SchoolCatalog.load(), legacySave: state.legacySave)
        calendar.originDate = state.originDate
        memory.insert(copy); memory.insert(profile); memory.insert(calendar)
        if copy.role == .batter {
            guard let positions = try PlayerPositionStore.profile(playerID: original.id, in: source) else { throw TrainingError.invalidRecord }
            memory.insert(try PlayerPositions(playerID: copy.id, loadout: positions.snapshot(), source: "practice-copy"))
        }
        return copy
    }

}

struct TrainingPracticeView: View {
    var sourcePlayers: [CareerPlayer]? = nil
    var initialRole: PlayerRole = .batter
    @Environment(\.modelContext) private var sourceContext
    @State private var profiles: [PlayerAbilities] = []
    @State private var container: ModelContainer?
    @State private var players: [CareerPlayer] = []
    @State private var calendars: [CareerCalendarState] = []
    @State private var role = PlayerRole.batter
    @State private var error: String?
    var body: some View {
        Group {
            if let container {
                ScrollView {
                    VStack(spacing: 12) {
                        GamePanel(title: "FREE PRACTICE", onBoard: true) {
                            Text("자유 연습").font(.title2.bold())
                            Text("내 선수 현재 능력·보유 구종 · 연습 피로 0")
                            Text("성장·기록·날짜·피로 변화 없음 · 하루 제한 없음")
                                .font(.caption).accessibilityIdentifier("practiceIsolation")
                        }
                        if !players.isEmpty { Picker("연습 역할", selection: $role) {
                            ForEach(players) { Text($0.role.label).tag($0.role) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("practiceRole") }
                        if let player = players.first(where: { $0.role == role }), let calendar = calendars.first(where: { $0.playerID == player.id }) {
                            HStack(spacing: 10) {
                                PixelPlayer(appearance: player.appearance).frame(width: 32, height: 44)
                                VStack(alignment: .leading) {
                                    Text("\(player.name) #\(player.jerseyNumber)").bold().accessibilityIdentifier("practicePlayerName")
                                    Text(player.schoolName + " · " + player.roleDetail).font(.caption)
                                }
                            }
                            DisclosureGroup("능력치·보유 구종 확인") {
                                let summary = HomeAbilitySummary(player: player, abilities: profiles.first { $0.playerID == player.id })
                                ForEach(summary.originals + summary.pitches) { value in
                                    HStack { Text(value.label); Spacer(); Text(value.current, format: .number.precision(.fractionLength(1))) }
                                        .font(.caption.monospaced()).accessibilityElement(children: .combine)
                                        .accessibilityIdentifier("practiceValue-" + value.id)
                                }
                            }.tint(GameTheme.gold)
                            NavigationLink {
                                CareerTrainingView(player: player, calendar: calendar, practice: true).modelContainer(container)
                            } label: { Text(role == .batter ? "타격·주루·수비 훈련" : "구종·투구·주루·수비 훈련") }
                                .buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("practiceGeneralTraining")
                            GamePanel(title: "특성 전용 훈련", onBoard: true) {
                                ForEach(PlayerTrait.allCases) { trait in
                                    NavigationLink { TraitDrillExperience(trait: trait, player: player).modelContainer(container) } label: { Text(trait.label) }
                                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("practiceTrait-" + trait.rawValue)
                                }
                            }
                            if role == .batter {
                                GamePanel(title: "포지션 훈련", onBoard: true) {
                                    ForEach(FieldPosition.allCases) { position in
                                        NavigationLink {
                                            PositionPracticeDestination(player: player, calendar: calendar, position: position).modelContainer(container)
                                        } label: { Text(position.label) }.buttonStyle(MatchPixelButtonStyle())
                                            .accessibilityIdentifier("practicePosition-" + position.rawValue)
                                    }
                                }
                            }
                        }
                        if players.isEmpty {
                            Text("생성된 선수가 없습니다. 선수 생성 후 자유 연습을 이용해 주세요.")
                                .accessibilityIdentifier("practiceNoPlayer")
                        }
                    }.padding(12)
                }
            } else if let error {
                VStack { Text(error); Button("연습 다시 열기", action: load) }
            } else { ProgressView("연습장 준비 중") }
        }
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
        .navigationTitle("자유 연습").navigationBarTitleDisplayMode(.inline)
        .task { if container == nil { load() } }
    }
    private func load() {
        do {
            let memory = try CareerStore.makeContainer(inMemory: true)
            let originals = try sourcePlayers ?? sourceContext.fetch(FetchDescriptor<CareerPlayer>())
            let copies = try originals.map { try TrainingPractice.copy($0, from: sourceContext, into: memory.mainContext) }
            let states = try memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>())
            let abilities = try memory.mainContext.fetch(FetchDescriptor<PlayerAbilities>())
            players = copies; calendars = states; profiles = abilities
            role = copies.first(where: { $0.role == initialRole })?.role ?? copies.first?.role ?? initialRole
            container = memory; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct PositionPracticeDestination: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let position: FieldPosition
    @Environment(\.modelContext) private var context
    @State private var record: CareerTrainingRecord?
    @State private var error: String?
    var body: some View {
        Group {
            if let record { PositionDrillLiveView(player: player, calendar: calendar, record: record, practice: true) }
            else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard record == nil else { return }
            do { record = try CareerTrainingRecord(TrainingPractice.round(player: player, calendar: calendar, kind: .defense, position: position, in: context)) }
            catch { self.error = error.localizedDescription }
        }
    }
}

#if DEBUG
// Fixed QA inputs. No career container, random stream, reward or save is opened here.
enum FieldVerificationScenario:String,CaseIterable,Identifiable {
    case single="1루 세이프", groundOut="땅볼 아웃", doubleHit="2루 슬라이딩", doublePlay="병살"
    case tagUp="태그업", relay="중계", fieldError="포구 실책", throwError="악송구", bunt="번트"
    var id:String {rawValue}
    var position:String {
        switch self {case .relay:"2B";case .tagUp:"CF";case .doubleHit:"LF";case .bunt:"P";default:"SS"}
    }
    var forcedError:Bool {self == .fieldError || self == .throwError}
    func make(ability:Double=60,ownBatter:Bool=false) throws -> MatchDetailedPlay {
        let stats=MatchFieldStats(version:3,speed:ability,defense:ability,arm:ability,position:position,activeTraits:[],positionMastery:100)
        let airborne=self == .tagUp || self == .relay
        let landing:FieldPoint=self == .doubleHit ? .init(x:-44,y:83):self == .relay ? .init(x:0,y:95):self == .tagUp ? .init(x:0,y:90):self == .doublePlay ? .init(x:-14,y:35):.init(x:-16,y:37)
        let distance=hypot(landing.x,landing.y),flight=airborne ? (self == .relay ? 7.0:5.5):distance/(35*0.68)
        let shot:MatchBattedBall
        if self == .bunt {
            shot = .make(quality:0.85,contact:60,power:60,bunt:true,speedDraw:0.5,angleDraw:0.2,directionDraw:0.2)
        } else {
            shot=MatchBattedBall(kind:airborne ? .fly:.ground,quality:0.75,contact:60,power:60,
                speed:airborne ? flight*9.81/(2*sin(Double.pi/3)):35,angle:airborne ? 60:0,
                direction:atan2(landing.x,landing.y)*180 / .pi,distance:distance,flight:flight)
        }
        let before:[FieldRunnerProfile?]=self == .doublePlay ? [FieldRunnerProfile(speed:60),nil,nil]:airborne ? [nil,nil,FieldRunnerProfile(speed:100)]:[nil,nil,nil]
        let runner=FieldRunnerProfile(speed:forcedError ? 30:self == .groundOut || self == .doublePlay ? 60:100,own:ownBatter)
        var play=airborne ? DetailedFieldRules.resolveFly(half:0,order:0,landing:shot.landing,flight:shot.flight,runners:before,
            batter:runner,outs:0,stats:stats,defending:!ownBatter,ownBatter:ownBatter,relayEnabled:true):
            DetailedFieldRules.resolve(half:0,order:0,landing:shot.landing,flight:shot.flight,runners:before,
                batter:runner,outs:0,stats:stats,defending:!ownBatter,ownBatter:ownBatter,doublePlayEnabled:true,groundBall:shot.kind == .ground,relayEnabled:true)
        play.ball=shot.nodes+play.ball.filter {$0.at>shot.flight};play.battedBall=shot;play.version=5
        if forcedError {
            var draws=Array(repeating:0.999999,count:7);draws[self == .fieldError ? 0:1]=0
            play=FieldMisplayRules.applying(to:play,stats:stats,defending:!ownBatter,draws:draws)
            play.battedBall=shot
            guard play.misplay != nil else {throw MatchError.invalidRecord}
        }
        try play.validate();return play
    }
    static func moments(_ play:MatchDetailedPlay) -> [Double] {
        var events:[Double]=[0,play.flight,play.pickupAt,play.releaseAt,play.ballAt,play.controlAt,play.duration]
        if let relay=play.relay {events += [relay.receiveAt,relay.releaseAt]}
        if let second=play.secondThrow {events += [second.releaseAt,second.ballAt,second.controlAt]}
        if let error=play.misplay {events += [error.at,error.scatteredAt,error.recoveredAt]}
        events += FieldMisplayAnimation.moments(play)+FieldRelayTransfer.moments(play)
        events += play.runners.flatMap {$0.nodes.map(\.at)}
        return Array(Set(events)).sorted()
    }
}

struct FieldVerificationClock {
    private(set) var elapsed=0.0
    private(set) var startedAt:Date?
    private(set) var rate=1.0
    func time(at now:Date,duration:Double) -> Double {
        min(duration,max(0,elapsed+(startedAt.map {max(0,now.timeIntervalSince($0))*rate} ?? 0)))
    }
    mutating func play(at now:Date,duration:Double) {
        if elapsed>=duration {elapsed=0}
        startedAt=now
    }
    mutating func pause(at now:Date,duration:Double) {elapsed=time(at:now,duration:duration);startedAt=nil}
    mutating func seek(_ value:Double,duration:Double) {elapsed=max(0,min(duration,value));startedAt=nil}
    mutating func speed(_ value:Double,at now:Date,duration:Double) {
        elapsed=time(at:now,duration:duration)
        if startedAt != nil {startedAt=now}
        rate=[0.25,0.5,1].contains(value) ? value:1
    }
}

struct FieldReplayVerification:View {
    @State private var scenario=FieldVerificationScenario.single
    @State private var ability=60.0
    @State private var sample:MatchDetailedPlay?
    @State private var failure:String?
    @State private var clock=FieldVerificationClock()
    @State private var contacts=false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    private var controlsLayout:AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:8)):AnyLayout(HStackLayout(spacing:8))
    }
    var body:some View {
        TimelineView(.animation(minimumInterval:reduced ? 0.15:1.0/30,paused:clock.startedAt == nil)) { timeline in
            let duration=sample?.duration ?? 0
            let time=clock.time(at:timeline.date,duration:duration)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text("인플레이 재현실").font(.title2.bold()).foregroundStyle(GameTheme.gold)
                    Text("고정 재현 자료 · 실전 팀별 NPC와 별도 / 선수 저장·날짜·피로·XP 변경 없음")
                        .font(.caption).accessibilityIdentifier("fieldVerificationNotice")
                    Picker("상황",selection:$scenario) {
                        ForEach(FieldVerificationScenario.allCases) {Text($0.rawValue).tag($0)}
                    }.pickerStyle(.menu).accessibilityIdentifier("fieldVerificationScenario")
                    GamePanel(title:"야수 기준 · 가상 검증값",onBoard:true) {
                        Text("조정 대상 \(scenario.position) · 스피드/수비/송구 \(Int(ability))")
                            .font(.subheadline).accessibilityIdentifier("fieldVerificationAbilities")
                        Picker("대상 야수 기량",selection:$ability) {
                            Text("낮음 30").tag(30.0);Text("기본 60").tag(60.0);Text("높음 85").tag(85.0)
                        }.pickerStyle(.segmented).accessibilityIdentifier("fieldVerificationPreset")
                        Text("나머지 8명은 각각 60 · 특성 없음 · 기준 장면의 결과는 기량에 따라 달라질 수 있음")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        if scenario.forcedError {
                            Text("실책 발생 강제 · 연출 재현용 / 실전 발생 확률과 별도")
                                .font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldVerificationForcedError")
                        }
                    }
                    if let play=sample {
                        controlsLayout {
                            Button(clock.startedAt == nil ? "재생":"일시정지") {
                                if clock.startedAt == nil {clock.play(at:Date(),duration:play.duration)}
                                else {clock.pause(at:Date(),duration:play.duration)}
                            }.accessibilityIdentifier("fieldVerificationPlay")
                            Button("처음으로") {clock.seek(0,duration:play.duration)}.accessibilityIdentifier("fieldVerificationReset")
                        }.buttonStyle(GameButtonStyle(secondary:true,onBoard:true))
                        controlsLayout {
                            Button("이전 구간") {step(play,time:time,forward:false)}.accessibilityIdentifier("fieldVerificationPrevious")
                            Button("다음 구간") {step(play,time:time,forward:true)}.accessibilityIdentifier("fieldVerificationNext")
                            Menu("\(clock.rate,specifier:"%.2g")×") {
                                ForEach([1.0,0.5,0.25],id:\.self) {rate in
                                    Button("\(rate,specifier:"%.2g")×") {clock.speed(rate,at:Date(),duration:play.duration)}
                                        .accessibilityIdentifier("fieldVerificationSpeed-\(rate)")
                                }
                            }.accessibilityIdentifier("fieldVerificationSpeed")
                        }.buttonStyle(GameButtonStyle(secondary:true,onBoard:true))
                        Slider(value:Binding(get:{time},set:{clock.seek($0,duration:play.duration)}),in:0...max(0.001,play.duration))
                            .tint(GameTheme.gold).accessibilityLabel("재생 시각").accessibilityIdentifier("fieldVerificationScrubber")
                        Text("\(time,specifier:"%.2f") / \(play.duration,specifier:"%.2f")초")
                            .monospacedDigit().accessibilityIdentifier("fieldVerificationTime")
                        DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),animated:false,ownPosition:scenario.position,
                            ownTeamFielding:true,previewTime:time,showsContactPoints:contacts) {}
                        Toggle("손·글러브 접촉점 표시",isOn:$contacts).accessibilityIdentifier("fieldVerificationContacts")
                        DisclosureGroup("시각·능력치 진단") {
                            Text("타구 \(play.battedBall?.kmh ?? 0,specifier:"%.1f") km/h · 포구 \(play.pickupAt,specifier:"%.2f")초 · 송구 수신 \(play.ballAt,specifier:"%.2f")초")
                            Text("주자 도착 \(play.runnerAt ?? 0,specifier:"%.2f")초 · 공 통제 \(play.controlAt,specifier:"%.2f")초")
                            let motion=FieldSpriteAnimation.motion(play,index:play.receiver,time:time)
                            Text("수신 야수 \(DetailedFieldRules.names[play.receiver]) · \(String(describing:motion.stage)) / \(String(describing:motion.baseReceive))")
                            Text("대상 포구 실책 기준 \(FieldMisplayRules.probability(kind:.fielding,defense:ability,arm:ability,distance:0,traits:[])*100,specifier:"%.2f")% · 특성 없음")
                            Text("주자 스피드 \(play.runners.map {String(Int($0.profile.speed))}.joined(separator:" / "))")
                            Text("악송구는 송구/거리로 계산 · 강제 실책은 이 확률 검사가 아님")
                        }.font(.caption).accessibilityIdentifier("fieldVerificationDiagnostics")
                    } else if let failure {
                        Text(failure).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldVerificationError")
                        Button("다시 구성",action:load).buttonStyle(GameButtonStyle(secondary:true,onBoard:true))
                    }
                }.padding(12).foregroundStyle(GameTheme.paper)
            }.background(GameTheme.board)
                .onChange(of:time>=duration && duration>0) {_,ended in if ended {clock.pause(at:timeline.date,duration:duration)}}
        }
        .navigationTitle("인플레이 검증").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(GameTheme.board,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
        .toolbarColorScheme(.dark,for:.navigationBar)
        .onAppear(perform:load)
        .onChange(of:scenario) {_,_ in load()}
        .onChange(of:ability) {_,_ in load()}
        .onChange(of:scenePhase) {_,phase in if phase != .active {clock.pause(at:Date(),duration:sample?.duration ?? 0)}}
        .onDisappear {clock.pause(at:Date(),duration:sample?.duration ?? 0)}
    }
    private func load() {
        clock.seek(0,duration:0)
        do {sample=try scenario.make(ability:ability);failure=nil}
        catch {sample=nil;failure="재현 자료를 구성하지 못했습니다. 실제 선수 저장은 변경하지 않았습니다."}
    }
    private func step(_ play:MatchDetailedPlay,time:Double,forward:Bool) {
        let moments=FieldVerificationScenario.moments(play)
        let next=forward ? moments.first {$0>time+0.001} ?? play.duration:moments.last {$0<time-0.001} ?? 0
        clock.seek(next,duration:play.duration)
    }
}

struct HomeRunVerification:View {
    @State private var pitcher=false
    @State private var time=0.0
    @State private var live=false
    @State private var replayID=0
    private var event:MatchHomeRun {
        MatchHomeRun(half:0,order:0,seed:42,power:72,quality:0.9,directionOffset:0,
            before:[FieldRunnerProfile(speed:50),FieldRunnerProfile(speed:65),FieldRunnerProfile(speed:80)],
            batter:FieldRunnerProfile(speed:60,own:!pitcher),defenderSpeeds:Array(repeating:60,count:9),ownDefender:pitcher ? 0:nil)
    }
    var body:some View {
        GeometryReader {geometry in
            ScrollView {
                VStack(spacing:12) {
                    Text("홈런 연출 검증 · 실제 저장 미사용").font(.headline).foregroundStyle(GameTheme.gold)
                    Button(pitcher ? "투수 시점":"타자 시점") {pitcher.toggle();live=false;time=0;replayID+=1}
                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("homeRunVerifyRole")
                    HStack {
                        Button("접촉") {live=false;time=0;replayID+=1}.accessibilityIdentifier("homeRunVerifyContact")
                        Button("펜스 통과") {live=false;time=event.flight*0.85;replayID+=1}.accessibilityIdentifier("homeRunVerifyFence")
                        Button("일주") {live=false;time=event.flight+2;replayID+=1}.accessibilityIdentifier("homeRunVerifyBases")
                        Button("홈 도착") {live=false;time=event.duration;replayID+=1}.accessibilityIdentifier("homeRunVerifyHome")
                    }.buttonStyle(MatchPixelButtonStyle())
                    Button("처음부터 재생") {live=true;time=0;replayID+=1}.buttonStyle(MatchPixelButtonStyle(primary:true))
                        .accessibilityIdentifier("homeRunVerifyPlay")
                    HomeRunReplayBoard(event:event,appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:pitcher ? "P":"CF",throwingHand:"left",ownTeamFielding:pitcher,
                        previewTime:live ? nil:time) {live=false;time=event.duration}
                        .id(replayID).frame(height:max(550,geometry.size.width*1.55+80))
                }.padding(8)
            }.background(GameTheme.navy.ignoresSafeArea())
        }.navigationTitle("홈런 재현실").toolbarColorScheme(.dark,for:.navigationBar)
    }
}

struct MatchReplayFixture {
    let name:String
    let field:MatchDetailedPlay?
    let homeRun:MatchHomeRun?
    var duration:Double {field?.duration ?? homeRun?.duration ?? 0}
    static func make(pitcher:Bool) throws -> [Self] {
        var result=try FieldVerificationScenario.allCases.map {scenario in
            Self(name:scenario.rawValue,field:try scenario.make(ownBatter:!pitcher),homeRun:nil)
        }
        let home=MatchHomeRun(half:0,order:0,seed:42,power:72,quality:0.9,directionOffset:0,
            before:[FieldRunnerProfile(speed:50),FieldRunnerProfile(speed:65),FieldRunnerProfile(speed:80)],
            batter:FieldRunnerProfile(speed:60,own:!pitcher),defenderSpeeds:Array(repeating:60,count:9),ownDefender:pitcher ? 0:nil)
        result.append(Self(name:"홈런",field:nil,homeRun:home));return result
    }
}
struct MatchReplaySample:View {
    let sample:MatchReplayFixture
    let pitcher:Bool
    let left:Bool
    let time:Double
    var reduced=false
    var body:some View {
        Group {
            if let play=sample.field {
                DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:pitcher ? "P":"CF",throwingHand:left ? "left":"right",ownTeamFielding:pitcher,
                    previewTime:time,reduceMotionOverride:reduced,showsContactPoints:true) {}
            } else if let event=sample.homeRun {
                HomeRunReplayBoard(event:event,appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:pitcher ? "P":"CF",throwingHand:left ? "left":"right",ownTeamFielding:pitcher,
                    previewTime:time,reduceMotionOverride:reduced)
            }
        }
    }
}
struct MatchReplayStressView:View {
    let fixtures:[MatchReplayFixture]
    let pitcherFixtures:[MatchReplayFixture]
    let started:Double
    var cycle:Double {fixtures.reduce(0) {$0+$1.duration+1}}
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30)) {_ in
            let elapsed=max(0,ProcessInfo.processInfo.systemUptime-started),loop=Int(elapsed/cycle)
            let local=elapsed.truncatingRemainder(dividingBy:cycle)
            let fixtures=loop%2 == 1 ? pitcherFixtures:self.fixtures
            let index=fixtures.indices.first {i in local<fixtures.prefix(i+1).reduce(0) {$0+$1.duration+1}} ?? 0
            let before=fixtures.prefix(index).reduce(0) {$0+$1.duration+1}
            MatchReplaySample(sample:fixtures[index],pitcher:loop%2 == 1,left:loop%2 == 1,time:min(fixtures[index].duration,local-before))
                .id("\(loop)/\(index)").padding(8).background(GameTheme.navy)
        }
    }
}
struct MatchReplayVerification:View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private var controls:AnyLayout {typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:8)):AnyLayout(HStackLayout(spacing:8))}
    @State private var pitcher=false
    @State private var left=false
    @State private var reduced=false
    @State private var index=0
    @State private var ending=false
    var body:some View {
        ScrollView {
            VStack(spacing:10) {
                Text("경기 연출 통합 검증 · 실제 저장 미사용").font(.headline).foregroundStyle(GameTheme.gold)
                controls {
                    Button(pitcher ? "투수":"타자") {pitcher.toggle()}.accessibilityIdentifier("integratedRole")
                    Button(left ? "왼손":"오른손") {left.toggle()}.accessibilityIdentifier("integratedHand")
                    Button {reduced.toggle()} label: {
                        VStack(spacing:2) {Text("동작 줄이기");Text(reduced ? "켜짐":"꺼짐").font(.caption).accessibilityHidden(true)}
                    }.accessibilityValue(reduced ? "켜짐":"꺼짐").accessibilityIdentifier("integratedReduced")
                }.buttonStyle(MatchPixelButtonStyle())
                if let fixtures=try? MatchReplayFixture.make(pitcher:pitcher) {
                    controls {
                        Button("이전") {index=(index+fixtures.count-1)%fixtures.count;ending=false}.accessibilityIdentifier("integratedPrevious")
                        Text(fixtures[index].name).accessibilityIdentifier("integratedScenario")
                        Button("다음") {index=(index+1)%fixtures.count;ending=false}.accessibilityIdentifier("integratedNext")
                    }.buttonStyle(MatchPixelButtonStyle())
                    Button(ending ? "중간 장면":"최종 장면") {ending.toggle()}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("integratedEnd")
                    MatchReplaySample(sample:fixtures[index],pitcher:pitcher,left:left,time:ending ? fixtures[index].duration:fixtures[index].duration*0.45,reduced:reduced)
                        .frame(minHeight:560)
                } else {Text("고정 검증 자료 오류")}
            }.padding(8)
        }.background(GameTheme.navy.ignoresSafeArea()).foregroundStyle(GameTheme.paper)
            .navigationTitle("통합 재현실").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
    }
}
// Synthetic read-only render cases: no career store, input, rewards or dates.
struct FieldPerformanceAutoplay:View {
    private struct Case {
        let fixture:MatchReplayFixture
        let pitcher:Bool
        let effectsReduced:Bool
        var name:String {"unified-\(pitcher ? "pitcher":"batter")-\(effectsReduced ? "reduced":"normal")-\(fixture.name)"}
    }
    @State private var index=0
    @State private var cases:[Case]=[]
    @Environment(\.scenePhase) private var phase
    @State private var interrupted=false
    var body:some View {
        VStack(spacing:8) {
            Text("QA 자동 인플레이 · 저장 미사용").font(.headline).foregroundStyle(GameTheme.gold)
            if !cases.isEmpty,index<cases.count {
                let item=cases[index]
                Text("\(index+1)/\(cases.count) · \(item.name)").font(.caption).accessibilityIdentifier("unifiedRenderCase")
                Group {
                    if let play=item.fixture.field {
                        DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:item.pitcher ? "P":"CF",throwingHand:item.pitcher ? "left":"right",ownTeamFielding:item.pitcher,
                            reduceMotionOverride:item.effectsReduced,preparesMotion:true) {advance(item)}
                    } else if let event=item.fixture.homeRun {
                        HomeRunReplayBoard(event:event,appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:item.pitcher ? "P":"CF",throwingHand:item.pitcher ? "left":"right",ownTeamFielding:item.pitcher,
                            reduceMotionOverride:item.effectsReduced,preparesMotion:true,complete:{advance(item)})
                    }
                }.id(index).task(id:index) {MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true;interrupted=false}
            } else {Text(cases.isEmpty ? "준비 중":"전체 장면 측정 완료").accessibilityIdentifier("unifiedRenderComplete")}
        }.padding(8).background(GameTheme.navy.ignoresSafeArea()).foregroundStyle(GameTheme.paper)
        .onChange(of:phase) {_,value in if value != .active {interrupted=true}}
        .task {
            guard cases.isEmpty else {return}
            let args=ProcessInfo.processInfo.arguments
            if args.contains("-field-startup-probe") {
                let pitcher=args.contains("-startup-pitcher"),effects=args.contains("-startup-effects-reduced")
                do {try await Task.sleep(for:.seconds(8))} catch {return}
                if let fixture=try? MatchReplayFixture.make(pitcher:pitcher).first {
                    cases=(0..<3).map {_ in Case(fixture:fixture,pitcher:pitcher,effectsReduced:effects)}
                }
            } else {
                for pitcher in [false,true] {for effects in [false,true] {
                    if let fixtures=try? MatchReplayFixture.make(pitcher:pitcher) {cases+=fixtures.map {Case(fixture:$0,pitcher:pitcher,effectsReduced:effects)}}
                }}
            }
        }
    }
    private func advance(_ item:Case) {
        MatchRenderMetrics.exportLive(role:"\(ProcessInfo.processInfo.arguments.contains("-field-startup-probe") ? "startup":"unified")-\(item.name)-\(interrupted ? "interrupted":"foreground")")
        MatchRenderMetrics.enabled=false;index+=1
    }
}

#endif
