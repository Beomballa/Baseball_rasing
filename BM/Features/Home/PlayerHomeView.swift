import SwiftUI
import SwiftData

struct PlayerHomeView: View {
    let player: CareerPlayer
    let players: [CareerPlayer]
    let calendar: CareerCalendarState?
    let schools: [School]
    let transition: CareerTransition
    let select: @MainActor @Sendable (UUID) -> Void
    let create: () -> Void
    let play: () -> Void
    @Query(sort: \CareerMatchRecord.gameDate, order: .reverse) private var gameRecords: [CareerMatchRecord]
    @Query private var abilityProfiles: [PlayerAbilities]
    private var abilities: PlayerAbilities? { abilityProfiles.first { $0.playerID == player.id } }

    @Query(sort: \CareerTrainingRecord.gameDate, order: .reverse) private var trainingRecords: [CareerTrainingRecord]
    private var todayTraining: CareerTrainingRecord? { trainingRecords.first { $0.playerID == player.id && $0.gameDate == player.gameDate } }

    private var age: Int { (try? calendar?.age(of: player)) ?? player.startAge }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("PLAYER CAREER").font(.caption.monospaced().bold())
                    Spacer(); Text("LOCAL SAVE").font(.caption.monospaced())
                }.foregroundStyle(GameTheme.gold).padding(12).background(GameTheme.navy)
                GamePanel(title: "선수 홈") {
                    HStack(spacing: 16) {
                        PixelPlayer(appearance: player.appearance).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(player.name)  #\(player.jerseyNumber)").font(.title2.bold())
                                .accessibilityIdentifier("homePlayerName")
                            Text(player.schoolName).fontWeight(.semibold).accessibilityIdentifier("homeSchool")
                            Text("\(player.role.label) · \(player.roleDetail) · \(age)세 / \(SeasonSchedule.academicStatus(age: age))")
                                .font(.subheadline).foregroundStyle(GameTheme.muted).accessibilityIdentifier("homeAge")
                            if let abilities {
                                Text(abilities.label).font(.caption.bold()).foregroundStyle(GameTheme.green)
                                    .accessibilityIdentifier("homeArchetype")
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Text(player.gameDate).monospacedDigit()
                        Spacer(); Text("피로 \(player.fatigue) / 100").accessibilityIdentifier("homeFatigue")
                    }.font(.subheadline)
                    if calendar?.legacySave == true {
                        Text("기존 저장 유지 · 저장 날짜를 나이 진행 기준일로 사용")
                            .font(.caption).foregroundStyle(GameTheme.muted)
                    }
                }
                if let calendar {
                    NavigationLink {
                        CareerTrainingView(player: player, calendar: calendar)
                    } label: {
                        Text(todayTraining.map { $0.completed ? "오늘 훈련 결과" : "훈련 이어하기 · \((try? $0.snapshot().scores.count) ?? 0)/5" }
                             ?? (player.role == .batter ? "타격 · 수비 · 멘탈 훈련" : "투구 · 수비 · 멘탈 훈련"))
                    }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("openTraining")
                        .disabled(calendar.hasAction(on: player.gameDate) && todayTraining == nil)
                    if let latest = trainingRecords.first(where: { $0.playerID == player.id && $0.completed }),
                       let result = try? latest.snapshot() {
                        GamePanel(title: "최근 훈련 성장") {
                            let name = result.pitchCode.flatMap { code in player.pitches.first { $0.code == code }?.name } ?? result.selectedKind.label
                            Text("\(latest.gameDate) · \(name)  \(result.before, specifier: "%.1f") → \(result.after, specifier: "%.1f")")
                                .bold().accessibilityIdentifier("homeTrainingGrowth")
                            Text("성장 +\(result.gain, specifier: "%.1f") · 평균 \(result.average, specifier: "%.1f")점 · 다음 경기 반영")
                                .font(.caption)
                        }
                    }
                    CareerCalendarPanel(player: player, state: calendar, schools: schools, transition: transition).id(player.id)
                } else {
                    Text("달력 정보를 불러오지 못했습니다. 앱을 다시 열어 주세요.").font(.caption)
                }
                if let calendar {
                    let status = CalendarScheduleStatus(player: player, state: calendar)
                    if let fixture = status.schedule?.today {
                        let saved = gameRecords.first { $0.playerID == player.id && $0.fixtureID == fixture.id }
                        NavigationLink {
                            CareerGameView(player: player, calendar: calendar, schools: schools)
                        } label: {
                            Text(saved?.completed == true ? "오늘 경기 결과" : (saved == nil ? "오늘 경기 시작" : "오늘 경기 이어하기"))
                        }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("openCareerGame")
                            .disabled(!calendar.hasAction(on: player.gameDate) && saved == nil)
                    }
                }
                GamePanel(title: "최근 경기 결과") {
                    let recent = gameRecords.filter { $0.playerID == player.id && $0.completed }.prefix(5)
                    if recent.isEmpty { Text("완료한 경기가 없습니다.").font(.caption) }
                    ForEach(Array(recent)) { record in
                        if let match = try? record.snapshot() {
                            VStack(alignment: .leading) {
                                Text("\(record.gameDate) · \(match.teamScore) : \(match.opponentScore)").bold()
                                Text(record.appearance ? (player.role == .batter
                                    ? "\(match.line.atBats)타수 \(match.line.hits)안타 · \(match.line.homeRuns)홈런"
                                    : "\(match.line.pitchingOuts / 3).\(match.line.pitchingOuts % 3)이닝 · \(match.line.pitchingStrikeouts)K") : "비등판 · 팀 경기")
                            }.font(.caption)
                        }
                    }
                }.accessibilityIdentifier("homeGameResults")
                GamePanel(title: player.role == .batter ? "주요 능력치" : "보유 구종 · 숙련도") {
                    if player.role == .batter {
                        StatRow(name: "컨택", value: player.contact)
                        StatRow(name: "파워", value: player.power)
                        StatRow(name: "선구안", value: player.discipline)
                        if let abilities { StatRow(name: "멘탈", value: abilities.mental).accessibilityIdentifier("homeMental") }
                    } else {
                        ForEach(player.pitches.sorted { $0.order < $1.order }) { pitch in
                            StatRow(name: pitch.name, value: pitch.mastery)
                        }
                    }
                }
                if player.role == .pitcher, let abilities {
                    GamePanel(title: "투수 능력치 · 0~100점") {
                        if let velocity = abilities.velocity { StatRow(name: "구속 능력", value: velocity).accessibilityIdentifier("homeVelocity") }
                        if let control = abilities.control { StatRow(name: "제구", value: control).accessibilityIdentifier("homeControl") }
                        if let stuff = abilities.stuff { StatRow(name: "구위", value: stuff).accessibilityIdentifier("homeStuff") }
                        if let stamina = abilities.stamina { StatRow(name: "지구력", value: stamina).accessibilityIdentifier("homeStamina") }
                        StatRow(name: "변화구", value: PlayerInitialValues.breakingRating(Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) })))
                            .accessibilityIdentifier("homeBreaking")
                        StatRow(name: "멘탈", value: abilities.mental).accessibilityIdentifier("homeMental")
                        Text("변화구는 포심을 제외한 상위 2종의 숙련도 기준입니다.").font(.caption).foregroundStyle(GameTheme.muted)
                    }
                }
                if abilities == nil {
                    Text("확장 능력치 정보를 불러오지 못했습니다. 앱을 다시 열어 주세요.").font(.caption).foregroundStyle(GameTheme.muted)
                }
                GamePanel(title: "주루 · 수비") {
                    StatRow(name: "스피드", value: player.speed).accessibilityIdentifier("homeSpeed")
                    StatRow(name: "수비", value: player.defense).accessibilityIdentifier("homeDefense")
                    StatRow(name: "송구", value: player.arm).accessibilityIdentifier("homeArm")
                }
                Button("연습장 입장", action: play).buttonStyle(GameButtonStyle())
                    .accessibilityIdentifier("openMatch")
                Text("경기장 연결 단계 · 연습 장면은 기록에 반영되지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.muted)
                if players.count > 1 {
                    Picker("플레이 선수", selection: Binding(get: { player.id }, set: select)) {
                        ForEach(players) { Text("\($0.role.label) · \($0.name)").tag($0.id) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("homeRolePicker")
                }
                if players.count < PlayerRole.allCases.count {
                    Button("다른 역할 선수 만들기", action: create).buttonStyle(GameButtonStyle(secondary: true))
                        .accessibilityIdentifier("createOtherRole")
                }
            }.padding(16)
        }
        .background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("선수 홈").navigationBarTitleDisplayMode(.inline)
    }
}
