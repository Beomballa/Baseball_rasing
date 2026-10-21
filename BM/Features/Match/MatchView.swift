import SwiftUI
import SpriteKit
import SwiftData

struct MatchView: View {
    let player: CareerPlayer
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
                Text("연습 장면").font(.caption.bold()).padding(8).background(GameTheme.gold)
            }
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .aspectRatio(0.8, contentMode: .fit)
                .overlay(Rectangle().strokeBorder(GameTheme.navy, lineWidth: 3))
                .accessibilityLabel("위에서 보는 도트 야구장")
                .accessibilityIdentifier("spriteKitField")
            Text(cue).font(.subheadline).multilineTextAlignment(.center)
                .accessibilityIdentifier("matchCue")
            Button("투구 연습 보기") {
                if scene.demonstrate(reduceMotion: reduceMotion) { cue = "손에서 릴리스 → 포수 수신 · 기록/피로 변화 없음" }
            }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("demoPitch")
            Text("카운트·성적·성장 판정은 다음 이식 단계입니다.")
                .font(.caption).foregroundStyle(GameTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(16).background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("경기장").navigationBarTitleDisplayMode(.inline)
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit) }
        .onDisappear { scene.removeAllActions() }
    }
}


@MainActor enum TrainingPractice {
    static func round(role: PlayerRole, kind: TrainingKind, code: String = "", position: FieldPosition? = nil) -> CareerTraining {
        var round = CareerTraining(playerID: UUID(), date: "2026-04-01", role: role.rawValue,
                                   pitchCode: kind == .pitch ? code : nil, before: 60, fatigue: 0,
                                   age: 16, calendarRevision: 0, kind: kind, position: position)
        if position != nil { round.positionRevision = 0; round.positionXP = 0 }
        return round
    }
    static func samples(in context: ModelContext) throws -> [CareerPlayer] {
        let schools = try SchoolCatalog.load()
        return try PlayerRole.allCases.map { role in
            var draft = PlayerDraft()
            draft.name = role == .batter ? "연습 타자" : "연습 투수"
            draft.role = role; draft.schoolID = schools[0].id
            let player = try CareerStore.create(draft, schools: schools, in: context)
            player.fatigue = 0
            for pitch in player.pitches { pitch.mastery = 60 }
            return player
        }
    }
}

struct TrainingPracticeView: View {
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
                            Text("샘플 선수 · 판정 기준 능력 60 · 피로 0")
                            Text("성장·기록·날짜·피로 변화 없음 · 하루 제한 없음")
                                .font(.caption).accessibilityIdentifier("practiceIsolation")
                        }
                        Picker("연습 역할", selection: $role) {
                            ForEach(PlayerRole.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("practiceRole")
                        if let player = players.first(where: { $0.role == role }), let calendar = calendars.first(where: { $0.playerID == player.id }) {
                            NavigationLink {
                                CareerTrainingView(player: player, calendar: calendar, practice: true).modelContainer(container)
                            } label: { Text(role == .batter ? "타격·주루·수비 훈련" : "구종·투구·주루·수비 훈련") }
                                .buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("practiceGeneralTraining")
                            GamePanel(title: "특성 전용 훈련", onBoard: true) {
                                ForEach(PlayerTrait.allCases) { trait in
                                    NavigationLink { TraitDrillExperience(trait: trait).modelContainer(container) } label: { Text(trait.label) }
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
            let samples = try TrainingPractice.samples(in: memory.mainContext)
            let states = try memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>())
            players = samples; calendars = states; container = memory; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct PositionPracticeDestination: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let position: FieldPosition
    @State private var record: CareerTrainingRecord?
    @State private var error: String?
    var body: some View {
        Group {
            if let record { PositionDrillLiveView(player: player, calendar: calendar, record: record, practice: true) }
            else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard record == nil else { return }
            do { record = try CareerTrainingRecord(TrainingPractice.round(role: .batter, kind: .defense, position: position)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
