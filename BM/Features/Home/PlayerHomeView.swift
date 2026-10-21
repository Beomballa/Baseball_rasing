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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \CareerMatchRecord.gameDate, order: .reverse) private var gameRecords: [CareerMatchRecord]
    @Query private var abilityProfiles: [PlayerAbilities]
    @Query(sort: \CareerTrainingRecord.gameDate, order: .reverse) private var trainingRecords: [CareerTrainingRecord]
    @State private var showOriginals = false
    private var abilities: PlayerAbilities? { abilityProfiles.first { $0.playerID == player.id } }
    private var todayTraining: CareerTrainingRecord? { trainingRecords.first { $0.playerID == player.id && $0.gameDate == player.gameDate } }
    private var age: Int { (try? calendar?.age(of: player)) ?? player.startAge }

    var body: some View {
        let summary = HomeAbilitySummary(player: player, abilities: abilities)
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("BM  CAREER").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    Spacer()
                    NavigationLink { TrainingPracticeView(sourcePlayers: players, initialRole: player.role) } label: { Text("자유 연습") }
                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openTrainingPractice")
                }
                if players.count > 1 {
                    let roleLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                    roleLayout {
                        ForEach(players) { candidate in
                            Button { select(candidate.id) } label: {
                                VStack(spacing: 2) {
                                    Text(candidate.role.label).font(.subheadline.bold())
                                    Text(candidate.name).font(.caption).lineLimit(1)
                                }.frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(candidate.id == player.id ? GameTheme.gold : GameTheme.boardInk)
                                    .background(GameTheme.boardPanel)
                                    .overlay(Rectangle().strokeBorder(candidate.id == player.id ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityIdentifier("homeRole-" + candidate.roleRaw)
                                .accessibilityAddTraits(candidate.id == player.id ? .isSelected : [])
                        }
                    }
                }
                profile
                if let calendar {
                    CareerCalendarPanel(player: player, state: calendar, schools: schools, transition: transition).id(player.id)
                    playActions(calendar)
                } else {
                    Text("달력 정보를 불러오지 못했습니다. 앱을 다시 열어 주세요.").font(.caption).foregroundStyle(GameTheme.gold)
                }
                GamePanel(title: "주요 능력 · 성장 그래프", onBoard: true) {
                    if summary.axes.count == 6 {
                        HomeRadarChart(values: summary.axes)
                    } else {
                        Text("확장 능력치 정보를 불러오지 못했습니다. 앱을 다시 열어 주세요.").font(.caption)
                    }
                    if !summary.hasInitialValues {
                        Text("시작값을 확인할 수 없어 현재 능력만 표시합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    HomeDetailButton(title: "원본 능력치 상세", expanded: $showOriginals, identifier: "homeAbilityDetails")
                    if showOriginals {
                        ForEach(summary.originals) { HomeGrowthRow(value: $0) }
                        if player.role == .batter {
                            Text("그래프 수비 종합 = 수비 70% + 송구 30% · 별도 성장 능력이 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        } else {
                            if let breaking = summary.axes.first(where: { $0.id == "homeBreaking" }) { HomeGrowthRow(value: breaking) }
                            Text("구속은 능력 점수 · 변화구는 포심 제외 상위 2종 숙련의 60% / 40%입니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                }
                TraitManagementPanel(player: player, calendar: calendar, onBoard: true, compact: true).id(player.id)
                if player.role == .pitcher {
                    GamePanel(title: "보유 구종 · 숙련도", onBoard: true) {
                        ForEach(summary.pitches) { value in
                            HStack(spacing: 10) {
                                MatchGrip(code: value.id, hand: player.throwingHandRaw).frame(width: 34, height: 42).accessibilityHidden(true)
                                HomeGrowthRow(value: value)
                            }
                        }
                        Text("초록은 현재 · 노란 선은 저장된 시작 숙련도").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }
                if let latest = trainingRecords.first(where: { $0.playerID == player.id && $0.completed }), let result = try? latest.snapshot() {
                    GamePanel(title: "최근 훈련 성장", onBoard: true) {
                        let name = result.position?.label ?? result.trait?.label ?? result.pitchCode.flatMap { code in player.pitches.first { $0.code == code }?.name } ?? result.selectedKind.label
                        Text("\(latest.gameDate) · \(name)  \(result.before, specifier: "%.1f") → \(result.after, specifier: "%.1f")")
                            .font(.subheadline.bold()).accessibilityIdentifier("homeTrainingGrowth")
                        if result.position != nil {
                            Text("XP +\(result.positionGainXP, specifier: "%.1f") · 잔여 \(result.positionAfter.xp, specifier: "%.1f") / 100 · 다음 새 경기 반영")
                                .font(.caption).foregroundStyle(GameTheme.growth).accessibilityIdentifier("homePositionTrainingGrowth")
                        } else {
                            Text("\(result.trait == nil ? "성장" : "진척") +\(result.gain, specifier: "%.1f") · 평균 \(result.average, specifier: "%.1f")점 · \(result.trait == nil ? "다음 새 경기 반영" : "습득 후 직접 활성화")")
                                .font(.caption).foregroundStyle(GameTheme.growth)
                        }
                    }
                }
                if let recent = gameRecords.first(where: { $0.playerID == player.id && $0.completed }),
                   let experience = try? recent.snapshot().positionExperience {
                    GamePanel(title: "최근 경기 · 실전 포지션 XP", onBoard: true) {
                        Text("\(experience.position.label) · 수비 \(experience.events.count)회 / 아웃 \(experience.successes)회")
                            .font(.subheadline)
                        Text("XP +\(experience.gainedXP, specifier: "%.1f") · 숙련 \(experience.before.mastery, specifier: "%.1f") → \(experience.after.mastery, specifier: "%.1f")")
                            .font(.headline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("homeGamePositionGrowth")
                    }
                }
                PositionHomePanel(player: player, calendar: calendar)
                recentGames
                GamePanel(title: "커리어 메뉴", onBoard: true) {
                    #if DEBUG
                    NavigationLink("포지션 훈련 · 화면 미리보기") { PositionTrainingPreview() }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("openPositionPreview")
                    #endif
                    Button("연습장 입장", action: play).buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("openMatch")
                    Text("연습 장면은 공식 기록·능력·피로에 반영되지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    if players.count < PlayerRole.allCases.count {
                        Button("다른 역할 선수 만들기", action: create).buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("createOtherRole")
                    }
                }
            }.padding(12)
        }.id(player.id)
            .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("선수 홈").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: player.id) { _, _ in showOriginals = false }
    }

    private var profile: some View {
        HStack(alignment: .center, spacing: 12) {
            PixelPlayer(appearance: player.appearance).frame(width: 44, height: 60)
                .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine))
            VStack(alignment: .leading, spacing: 4) {
                Text(age <= 18 ? "HIGH SCHOOL" : "CAREER").font(.caption2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text("\(player.name)  #\(player.jerseyNumber)").font(.title3.bold()).accessibilityIdentifier("homePlayerName")
                Text(player.schoolName).font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("homeSchool")
                Text("\(player.role.label) · \(player.roleDetail) · \(age)세 / \(SeasonSchedule.academicStatus(age: age))")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("homeAge")
                if let abilities { Text(abilities.label).font(.caption.bold()).foregroundStyle(GameTheme.growth).accessibilityIdentifier("homeArchetype") }
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2))
    }

    @ViewBuilder private func playActions(_ calendar: CareerCalendarState) -> some View {
        let status = CalendarScheduleStatus(player: player, state: calendar)
        let saved = status.schedule?.today.flatMap { fixture in gameRecords.first { $0.playerID == player.id && $0.fixtureID == fixture.id } }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            NavigationLink { CareerTrainingDestination(player: player, calendar: calendar) } label: {
                Text(todayTraining.map { $0.completed ? "오늘 훈련 결과" : "훈련 이어하기 · \((try? $0.snapshot().scores.count) ?? 0)/5" }
                     ?? (player.role == .batter ? "타자 훈련" : "투수 훈련"))
            }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("openTraining")
                .disabled(status.schedule == nil || calendar.hasAction(on: player.gameDate) && todayTraining == nil)
            if status.schedule?.today != nil {
                NavigationLink { CareerGameView(player: player, calendar: calendar, schools: schools) } label: {
                    Text(saved?.completed == true ? "오늘 경기 결과" : (saved == nil ? "오늘 경기 시작" : "오늘 경기 이어하기"))
                }.buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("openCareerGame")
                    .disabled(!calendar.hasAction(on: player.gameDate) && saved == nil)
            }
        }
        if status.schedule?.today != nil && !calendar.hasAction(on: player.gameDate) && saved == nil {
            Text("훈련 또는 휴식으로 준비한 뒤 오늘 경기에 출전합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }
    }

    private var recentGames: some View {
        GamePanel(title: "최근 5경기", onBoard: true) {
            let recent = gameRecords.filter { $0.playerID == player.id && $0.completed }.prefix(5)
            if recent.isEmpty { Text("완료한 경기가 없습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted) }
            ForEach(Array(recent)) { record in
                if let match = try? record.snapshot() {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.gameDate).font(.caption.monospaced())
                            Spacer(); Text("\(match.teamScore) : \(match.opponentScore)").font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold)
                        }
                        Text(schools.first { $0.id == record.opponentID }?.name ?? record.opponentID).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text(record.appearance ? (player.role == .batter
                            ? "\(match.line.atBats)타수 \(match.line.hits)안타 · \(match.line.homeRuns)홈런"
                            : "\(match.line.pitchingOuts / 3).\(match.line.pitchingOuts % 3)이닝 · \(match.line.pitchingStrikeouts)K") : "비등판 · 팀 경기")
                            .font(.caption)
                    }.padding(.vertical, 5)
                    Rectangle().fill(GameTheme.boardLine.opacity(0.4)).frame(height: 1).accessibilityHidden(true)
                } else { Text("\(record.gameDate) 기록을 읽을 수 없습니다. 기존 저장은 유지합니다.").font(.caption).foregroundStyle(GameTheme.gold) }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("homeGameResults")
    }
}
