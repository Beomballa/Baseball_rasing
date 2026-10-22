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
                    MatchAbilityGrowthHomePanel(player: player, records: gameRecords)
                    AnnualLeagueHomePanel(player:player,state:calendar,schools:schools,transition:transition)
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
                    NavigationLink("스카우트·계약 · 화면 시안") { ScoutingContractPreview() }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("openScoutingPreview")
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

struct AnnualLeagueHomePanel: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    let transition: CareerTransition
    @Environment(\.modelContext) private var context
    @State private var season: CareerSeasonSummary?
    private var league: AnnualLeague? { season?.league }
    @State private var error: String?
    private func reload() {
        do {
            season=try CareerSeasonStore.load(player:player,state:state,year:GameDate(player.gameDate).year,in:context);error=nil
        } catch {season=nil;self.error=error.localizedDescription}
    }
    var body: some View {
        GamePanel(title:"연간 리그",onBoard:true) {
            if let row=league?.standings.first(where:{$0.id == player.schoolID}) {
                Text(row.rank.map {"\($0)위 · 내 팀"} ?? "순위 집계 전 · 내 팀").font(.headline).foregroundStyle(GameTheme.gold)
                Text("\(row.games)경기 · \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)")
                    .font(.subheadline.monospaced()).accessibilityIdentifier("homeLeagueRecord")
            } else if let error {
                Text(error).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("homeLeagueError")
                Button("순위 다시 확인",action:reload).buttonStyle(MatchPixelButtonStyle())
            } else {Text("순위 불러오는 중").font(.caption)}
            if let season {
                Text("SEASON · 내 시즌 성적").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.boardMuted)
                SeasonPersonalRecord(totals: season.totals, role: player.role, compact: true)
                NavigationLink { CareerSeasonScreen(player: player, state: state, schools: schools, transition: transition) } label: {
                    Text(season.finalized ? "시즌 결산 · 최종 성적" : "시즌 성적 · 결산 보기")
                }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openSeasonSummary")
            }
            NavigationLink {AnnualLeagueScreen(player:player,state:state,schools:schools)} label: {
                HStack {LeaguePixelFlag().frame(width:20,height:22);Text("리그 순위 보기")}
            }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openAnnualLeague")
        }.task(id:"\(player.gameDate):\(state.revision):\(transition.display == nil)") {
            if transition.display == nil { reload() }
        }
    }
}

struct LeaguePixelFlag: View {
    var body: some View {
        Canvas { c,s in
            let u=min(s.width/8,s.height/9)
            c.fill(Path(CGRect(x:u,y:u,width:u,height:u*8)),with:.color(GameTheme.boardMuted))
            c.fill(Path(CGRect(x:u*2,y:u,width:u*5,height:u*3)),with:.color(GameTheme.gold))
            c.fill(Path(CGRect(x:u*2,y:u*4,width:u*3,height:u)),with:.color(GameTheme.growth))
        }.accessibilityHidden(true)
    }
}

struct AnnualLeagueScreen: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedYear: Int?
    @State private var league: AnnualLeague?
    @State private var error: String?
    private func name(_ id:String) -> String {schools.first {$0.id == id}?.name ?? id}
    private func reload() {
        do {
            let year=try selectedYear ?? GameDate(player.gameDate).year
            league=try AnnualLeagueStore.load(player:player,state:state,year:year,in:context);error=nil
        } catch {league=nil;self.error=error.localizedDescription}
    }
    var body: some View {
        ScrollView {
            VStack(spacing:12) {
                if let league {
                    HStack {
                        Button("이전 연도") {selectedYear=league.year-1}
                            .disabled(league.year <= (try? GameDate(state.originDate).year) ?? league.year)
                            .accessibilityIdentifier("leaguePreviousYear")
                        Spacer();Text("\(String(league.year)) SEASON").font(.headline.monospaced()).foregroundStyle(GameTheme.gold);Spacer()
                        Button("다음 연도") {selectedYear=league.year+1}
                            .disabled(league.year >= (try? GameDate(player.gameDate).year) ?? league.year)
                            .accessibilityIdentifier("leagueNextYear")
                    }.buttonStyle(MatchPixelButtonStyle())
                    Text("가상 6교 조별리그 · 연 30경기").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    GamePanel(title:"LEAGUE · 순위표",onBoard:true) {
                        Text("완료 \(league.results.count) / 대상 \(league.fixtures.count)경기 · \(player.gameDate) 기준")
                            .font(.caption.monospaced()).accessibilityIdentifier("leagueProgress")
                        if !typeSize.isAccessibilitySize {tableHeader}
                        ForEach(league.standings) {row in standingRow(row)}
                        Text("승률 = 승 ÷ (승+패) · 무승부 제외\n같은 승률은 공동 순위 · 승패가 없으면 순위/승률 —")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        if league.fixtures.count < 90 {
                            Text("경력 시작 전 일정과 고교 출전 연령 밖 일정은 집계하지 않습니다.")
                                .font(.caption).foregroundStyle(GameTheme.gold)
                        }
                    }
                    let today=league.fixtures.filter {$0.date.description == player.gameDate}
                    if !today.isEmpty {
                        GamePanel(title:"TODAY · 오늘 대진",onBoard:true) {
                            ForEach(today) {fixture in gameRow(fixture,result:league.results.first {$0.id == fixture.id},pending:league.pendingIDs.contains(fixture.id))}
                        }
                    }
                    if let last=league.results.map({$0.fixture.date}).max() {
                        GamePanel(title:"RECENT · \(last)",onBoard:true) {
                            ForEach(league.results.filter {$0.fixture.date == last}) {result in gameRow(result.fixture,result:result,pending:false)}
                        }
                    } else {Text("아직 완료한 리그 경기가 없습니다.").font(.caption).accessibilityIdentifier("leagueEmpty")}
                    Text("실제 완료 점수 우선 · 지난 날짜의 남은 경기만 자동\n자동 리그 결과는 개인 성적·피로·XP에 반영되지 않습니다.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                } else if let error {
                    GamePanel(title:"리그 기록 확인 필요",onBoard:true) {
                        Text(error).font(.subheadline).accessibilityIdentifier("leagueLoadError")
                        Button("다시 확인",action:reload).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryAnnualLeague")
                    }
                } else {ProgressView("리그 불러오는 중").tint(GameTheme.gold)}
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("연간 리그 순위").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar).toolbarColorScheme(.dark,for:.navigationBar)
            .task(id:"\(selectedYear ?? 0):\(player.gameDate):\(state.revision)"){reload()}
    }
    private var tableHeader: some View {
        HStack(spacing:4) {
            Text("위").frame(width:20);Text("팀").frame(maxWidth:.infinity,alignment:.leading)
            ForEach(["경기","승","패","무"],id:\.self){Text($0).frame(width:25)}
            Text("승률").frame(width:48)
        }.font(.caption2.bold()).foregroundStyle(GameTheme.boardMuted).accessibilityHidden(true)
    }
    private func standingRow(_ row:LeagueStanding) -> some View {
        VStack(alignment:.leading,spacing:6) {
            if typeSize.isAccessibilitySize {
                Text("\(row.rank.map {"\($0)위"} ?? "—") · \(name(row.id))\(row.id == player.schoolID ? " · 내 팀":"")").font(.headline)
                Text("\(row.games)경기 · \(row.wins)승 \(row.losses)패 \(row.draws)무\n승률 \(row.percentage)").font(.body.monospaced())
            } else {
                HStack(spacing:4) {
                    Text(row.rank.map(String.init) ?? "—").frame(width:20)
                    Text(name(row.id)).frame(maxWidth:.infinity,alignment:.leading).lineLimit(1).minimumScaleFactor(0.75)
                    ForEach([row.games,row.wins,row.losses,row.draws].indices,id:\.self){i in Text(String([row.games,row.wins,row.losses,row.draws][i])).frame(width:25)}
                    Text(row.percentage).frame(width:48)
                }.font(.caption.monospaced().bold())
            }
        }.padding(.vertical,10).padding(.horizontal,4).frame(maxWidth:.infinity,alignment:.leading)
            .background(row.id == player.schoolID ? Color(hex:0x244e48):GameTheme.board)
            .overlay(Rectangle().strokeBorder(row.id == player.schoolID ? GameTheme.gold:GameTheme.boardLine,lineWidth:row.id == player.schoolID ? 2:1))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(name(row.id))\(row.id == player.schoolID ? " 내 팀":"") · 순위 \(row.rank.map(String.init) ?? "미정") · \(row.games)경기 \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)")
            .accessibilityIdentifier(row.id == player.schoolID ? "leagueOwnStanding":"leagueStanding-\(row.id)")
    }
    private func gameRow(_ fixture:SeasonFixture,result:LeagueResult?,pending:Bool) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(name(fixture.awayID))  @  \(name(fixture.homeID))").font(.subheadline.bold())
            if let result {
                Text("\(result.awayScore) : \(result.homeScore) · \(result.automatic ? "자동 결과":"실제 경기")")
                    .font(.caption.monospaced()).foregroundStyle(GameTheme.gold)
            } else {Text(pending ? "경기 진행 중":"경기 대기").font(.caption).foregroundStyle(GameTheme.boardMuted)}
        }.padding(.vertical,4).frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityElement(children:.combine).accessibilityIdentifier("leagueFixture-\(fixture.id)")
    }
}

struct SeasonPersonalRecord: View {
    let totals: PersonalSeasonTotals
    let role: PlayerRole
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var values: [(String, String)] {
        let l = totals.line
        return role == .batter ? [("출전", "\(totals.games)경기"), ("타율", totals.average), ("홈런", "\(l.homeRuns)"), ("타점", "\(l.rbi)")]
            : [("등판", "\(totals.games)경기"), ("이닝", totals.innings), ("실점", "\(l.runsAllowed)"), ("탈삼진", "\(l.pitchingStrikeouts)")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 4))
            layout {
                ForEach(values.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(values[i].0).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text(values[i].1).font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(values.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                .accessibilityIdentifier(compact ? "homeSeasonTotals" : "seasonTotals")
            if !compact {
                let l = totals.line
                Text(role == .batter
                    ? "\(l.plateAppearances)타석 · \(l.atBats)타수 \(l.hits)안타\n\(l.walks)볼넷 · \(l.strikeouts)삼진"
                    : "\(l.pitches)구 · 피안타 \(l.hitsAllowed) · 볼넷 \(l.pitchingWalks)\nWHIP \(totals.whip)")
                    .font(.subheadline.monospaced()).accessibilityIdentifier("seasonRecordDetails")
                if role == .pitcher { Text("실점 기준 기록 · 자책점/ERA·투수 승패는 별도 집계 전입니다.").font(.caption).foregroundStyle(GameTheme.boardMuted) }
                Text(totals.games == 0 ? "완료한 개인 출전 기록이 없습니다." : "종료한 개인 출전만 합산 · 미완료/비등판·자동 팀 경기 제외")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
        }
    }
}

struct CareerSeasonScreen: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    let transition: CareerTransition
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedYear: Int?
    @State private var summary: CareerSeasonSummary?
    @State private var error: String?
    private func name(_ id: String) -> String { schools.first { $0.id == id }?.name ?? id }
    private func reload() {
        do {
            let year = try selectedYear ?? CareerSeasonStore.offseason(player: player, state: state, in: context)?.seasonYear ?? GameDate(player.gameDate).year
            summary = try CareerSeasonStore.load(player: player, state: state, year: year, in: context)
            if selectedYear == nil { selectedYear = year }
            error = nil
        } catch { summary = nil; self.error = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let summary {
                    let league = summary.league
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        Button("◀ 이전 연도") { selectedYear = league.year - 1 }
                            .disabled(league.year <= (try? GameDate(state.originDate).year) ?? league.year).accessibilityIdentifier("seasonPreviousYear")
                        Text("\(String(league.year)) SEASON").font(.headline.monospaced()).foregroundStyle(GameTheme.gold).frame(maxWidth: .infinity)
                        Button("다음 연도 ▶") { selectedYear = league.year + 1 }
                            .disabled(league.year >= (try? GameDate(player.gameDate).year) ?? league.year).accessibilityIdentifier("seasonNextYear")
                    }.buttonStyle(MatchPixelButtonStyle())
                    GamePanel(title: summary.finalized ? "FINAL · 시즌 결산" : "LIVE · 시즌 진행 중", onBoard: true) {
                        if summary.finalized {
                            SeasonPixelTrophy().frame(width: 72, height: 72).frame(maxWidth: .infinity)
                            Text(summary.champions.count > 1 ? "CO-CHAMPIONS · 공동 우승" : "LEAGUE CHAMPIONS")
                                .font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                            Text(summary.champions.map { name($0.id) }.joined(separator: " · "))
                                .font(.title2.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("seasonChampion")
                        }
                        Text(summary.finalized ? "모든 팀 30경기 종료 · 전체 90경기 확정" : "완료 \(league.results.count) / 대상 \(league.fixtures.count)경기")
                            .font(.subheadline.monospaced()).accessibilityIdentifier("seasonProgress")
                        if !summary.finalized {
                            Text(league.fixtures.count == 90 ? "전체 일정이 끝나면 최종 순위와 우승팀을 확정합니다. 마지막 날 다른 팀 경기는 다음 날 처리됩니다." : "경력 시작 전/출전 연령 밖 일정을 제외한 부분 시즌입니다. 30경기 결산으로 확정하지 않습니다.")
                                .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                        Text("\(player.name) · \(player.schoolName) · \(player.role.label)").font(.caption).accessibilityIdentifier("seasonPlayer")
                    }
                    GamePanel(title: "MY RECORD · 내 시즌 성적", onBoard: true) {
                        SeasonPersonalRecord(totals: summary.totals, role: player.role)
                    }
                    if summary.finalized {
                        SeasonOffseasonPanel(player: player, state: state, seasonYear: league.year, transition: transition)
                    }
                    GamePanel(title: summary.finalized ? "FINAL TABLE · 최종 순위" : "TABLE · 현재 순위", onBoard: true) {
                        ForEach(summary.finalStandings) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(row.rank.map { "\($0)위" } ?? "—") · \(name(row.id))\(row.id == player.schoolID ? " · 내 팀" : "")").font(.headline)
                                Text("\(row.games)경기 · \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)").font(.caption.monospaced())
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(row.id == player.schoolID ? Color(hex: 0x244e48) : GameTheme.board)
                                .overlay(Rectangle().strokeBorder(row.id == player.schoolID ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                                .accessibilityElement(children: .combine).accessibilityIdentifier("seasonStanding-\(row.id)")
                        }
                        Text("승률 동률은 공동 순위·공동 우승\n전 경기 무승부일 때는 모든 팀 공동 우승·승률 —")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    Text("완료 원장과 저장된 날짜로 복원 · 조회는 날짜·나이·피로·보상을 변경하지 않습니다. 오프시즌은 하루 단위로 저장하며 다음 해 4월 1일에 새 연간 일정이 시작됩니다.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                } else if let error {
                    GamePanel(title: "시즌 기록 확인 필요", onBoard: true) {
                        Text(error).accessibilityIdentifier("seasonLoadError")
                        Button("다시 확인", action: reload).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retrySeasonSummary")
                    }
                } else { ProgressView("시즌 불러오는 중").tint(GameTheme.gold) }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("시즌 성적 · 결산").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: "\(selectedYear ?? 0):\(player.gameDate):\(state.revision):\(transition.display == nil)") {
                if transition.display == nil { reload() }
            }
    }
}

struct SeasonPixelTrophy: View {
    var body: some View {
        Canvas { c, s in
            let u = min(s.width, s.height) / 16
            for r in [CGRect(x: 4, y: 1, width: 8, height: 7), CGRect(x: 5, y: 8, width: 6, height: 2),
                      CGRect(x: 7, y: 10, width: 2, height: 3), CGRect(x: 4, y: 13, width: 8, height: 2),
                      CGRect(x: 1, y: 2, width: 2, height: 5), CGRect(x: 3, y: 6, width: 2, height: 2),
                      CGRect(x: 13, y: 2, width: 2, height: 5), CGRect(x: 11, y: 6, width: 2, height: 2)] {
                c.fill(Path(CGRect(x: r.minX * u, y: r.minY * u, width: r.width * u, height: r.height * u)), with: .color(GameTheme.gold))
            }
            c.fill(Path(CGRect(x: 5 * u, y: 2 * u, width: 2 * u, height: 4 * u)), with: .color(GameTheme.boardInk))
        }.accessibilityHidden(true)
    }
}

struct SeasonOffseasonPanel: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let seasonYear: Int
    let transition: CareerTransition
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dismiss) private var dismiss
    @State private var plan: OffseasonPlan?
    @State private var loadError: String?
    @State private var progress = ""
    @State private var failure: String?
    @State private var confirmBirthday = false
    private func reload() {
        do {
            let latest = try CareerSeasonStore.offseason(player: player, state: state, in: context)
            plan = latest?.seasonYear == seasonYear ? latest : nil; loadError = nil
        } catch { plan = nil; loadError = error.localizedDescription }
    }
    private func proceed(confirmed: Bool = false) {
        guard let plan else { return }
        do {
            if try CalendarProgression.isAnniversaryTomorrow(player: player, state: state), !confirmed {
                confirmBirthday = true; return
            }
            let revision = state.revision, date = player.gameDate
            transition.perform(date: date, label: "오프시즌 진행", reduced: reduced, cancellable: true) {
                progress = ""
                do {
                    progress = try await CalendarProgression.advanceOffseason(player: player, state: state, seasonYear: plan.seasonYear,
                        revision: revision, expectedDate: date, confirmAnniversary: confirmed, in: context, onDaySaved: { saved in
                            transition.arrive(on: saved, reduced: reduced)
                            try? await Task.sleep(for: .milliseconds(reduced ? 0 : 35))
                        }).message
                } catch let error as CalendarAdvanceFailure {
                    progress = error.summary.message; failure = error.localizedDescription
                    transition.arrive(on: error.summary.lastSavedDate, reduced: reduced)
                } catch { failure = error.localizedDescription }
                reload()
            }
        } catch { failure = error.localizedDescription }
    }
    var body: some View {
        GamePanel(title: "OFFSEASON · 다음 연도 준비", onBoard: true) {
            if let loadError {
                Text(loadError).font(.caption).accessibilityIdentifier("offseasonLoadError")
                Button("다시 확인", action: reload).buttonStyle(MatchPixelButtonStyle())
            } else if let plan {
                Text("\(plan.date) → \(plan.target)").font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("offseasonDates")
                Text("남은 \(plan.remainingDays)일 · \(plan.age)세 → \(plan.targetAge)세 · \(SeasonSchedule.academicStatus(age: plan.targetAge))")
                    .font(.caption).accessibilityIdentifier("offseasonAge")
                Text("하루씩 저장 · 미사용 행동은 휴식 −\(DailyRecovery.rest) · 수면 −\(DailyRecovery.sleep)\n최대 30일 진행 후 계속 · 나이 변경 전 확인")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                if plan.targetAge >= 19 {
                    Text("고교 졸업·진로준비로 전환합니다. 고교 경기나 프로·대학 계약을 자동 생성하지 않습니다.")
                        .font(.caption).foregroundStyle(GameTheme.gold)
                }
                Button("다음 연도까지 · 최대 \(min(30, plan.remainingDays))일 진행") { proceed() }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("advanceOffseason")
            } else {
                Text("이 결산의 다음 연도로 이미 진행했거나 현재 진행할 오프시즌이 아닙니다. 과거 기록은 보존됩니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("offseasonUnavailable")
                Button("선수 홈으로") { dismiss() }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("offseasonReturnHome")
            }
            if !progress.isEmpty { Text(progress).font(.caption).accessibilityIdentifier("offseasonSummary") }
        }
        .task(id: "\(seasonYear):\(player.gameDate):\(state.revision):\(transition.display == nil)") {
            if transition.display == nil { reload() }
        }
        .onDisappear { transition.requestCancel() }
        .confirmationDialog("나이·학적 변경일로 진행할까요?", isPresented: $confirmBirthday, titleVisibility: .visible) {
            Button("확인하고 계속 진행") { proceed(confirmed: true) }
        } message: { Text("시작일 기념일에만 나이가 바뀝니다. 능력치·구종·이전 기록을 유지하며 자동 입단이나 성장 보상을 지급하지 않습니다.") }
        .alert("오프시즌 진행을 완료하지 못했습니다", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("확인") { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
