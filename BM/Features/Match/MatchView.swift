import SwiftUI
import SpriteKit
import SwiftData

struct MatchView: View {
    let player: CareerPlayer
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
                let started = scene.demonstrate(reduceMotion: reduceMotion,
                    onArrival: { cue = "포수 수신 완료 · 기록/피로 변화 없음" },
                    completion: { showingDelivery = false })
                if !started { showingDelivery = false }
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
        copy.pitches = original.pitches.map { CareerSchemaV1.PitchMastery(code: $0.code, name: $0.name, mastery: $0.mastery, order: $0.order) }
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
