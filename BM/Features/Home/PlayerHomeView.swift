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
    @State private var recentSnapshots: [String: MatchDisplaySnapshot] = [:]
    private var recentRecords: [CareerMatchRecord] { Array(gameRecords.filter { $0.playerID == player.id && $0.completed }.prefix(5)) }
    private var abilities: PlayerAbilities? { abilityProfiles.first { $0.playerID == player.id } }
    private var todayTraining: CareerTrainingRecord? { trainingRecords.first { $0.playerID == player.id && $0.gameDate == player.gameDate } }
    private var age: Int { (try? calendar?.age(of: player)) ?? player.startAge }

    @ViewBuilder private var rolePicker: some View {
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
    }

    private var affiliationLabel:String {
        do {
            if let calendar,let member=try calendar.registration(for:player) {return member.name+" · 출신 "+player.schoolName}
            let age=(try? calendar?.age(of:player)) ?? player.startAge
            return age <= 18 ? player.schoolName:"무소속 · 출신 "+player.schoolName
        } catch {return "소속 조회 오류 · 출신 "+player.schoolName}
    }
    var body: some View {
        let _=calendar?.revision
        let summary = HomeAbilitySummary(player: player, abilities: abilities)
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("BM  CAREER").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    Spacer()
                    NavigationLink { TrainingPracticeView(sourcePlayers: players, initialRole: player.role) } label: { Text("자유 연습") }
                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openTrainingPractice")
                }
                rolePicker
                profile
                if let calendar {
                    CareerCalendarPanel(player: player, state: calendar, schools: schools, transition: transition).id(player.id)
                    playActions(calendar)
                    NavigationLink {ContractMarketView(player:player,calendar:calendar)} label: {Text("계약 시장 · 잔류 / 외부 비교")}
                        .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("openContractMarket")
                    NavigationLink {CareerObjectivesView(player:player,calendar:calendar)} label: {CareerObjectivesHomeLabel(player:player,calendar:calendar)}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openCareerObjectives")
                    NavigationLink {ObservationReviewView(player:player,calendar:calendar)} label: {Text("28일 관찰 결산 · 다음 행동")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openObservationReview")
                    NavigationLink {GoalSpecialActivitiesView(player:player,calendar:calendar)} label: {Text("목표 구단 · 특별 훈련 / 평가전")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openGoalSpecial")
                    CareerContractStatusPanel(player:player,calendar:calendar).id(player.id)
                    ContractEvaluationHomePanel(player:player,calendar:calendar).id(player.id)
                    CareerPathHomePanel(player: player, calendar: calendar).id(player.id)
                    ScoutingObservationHomePanel(player: player, calendar: calendar)
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
                   let experience = recentSnapshots[recent.key]?.match?.positionExperience {
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
                    NavigationLink("인플레이 · 상황별 검증") { FieldReplayVerification() }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("openFieldVerification")
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
            .onChange(of: recentRecords.map(MatchDisplaySnapshot.Token.init), initial: true) { _, _ in
                var next: [String: MatchDisplaySnapshot] = [:]
                for record in recentRecords {
                    var cached = recentSnapshots[record.key] ?? MatchDisplaySnapshot()
                    _ = try? cached.refresh(record)
                    next[record.key] = cached
                }
                recentSnapshots = next
            }
    }

    private var profile: some View {
        HStack(alignment: .center, spacing: 12) {
            PixelPlayer(appearance: player.appearance).frame(width: 44, height: 60)
                .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine))
            VStack(alignment: .leading, spacing: 4) {
                Text(age <= 18 ? "HIGH SCHOOL" : "CAREER").font(.caption2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text("\(player.name)  #\(player.jerseyNumber)").font(.title3.bold()).accessibilityIdentifier("homePlayerName")
                Text(affiliationLabel).font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("homeSchool")
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
                NavigationLink { CareerGameEntryView(player: player, calendar: calendar, schools: schools) } label: {
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
            let recent = recentRecords
            if recent.isEmpty { Text("완료한 경기가 없습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted) }
            ForEach(Array(recent)) { record in
                if let match = recentSnapshots[record.key]?.match {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.gameDate).font(.caption.monospaced())
                            Spacer(); Text("\(match.teamScore) : \(match.opponentScore)").font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold)
                        }
                        Text(CareerTeamDirectory.name(record.opponentID,schools:schools)).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text(record.appearance ? (player.role == .batter
                            ? "\(match.line.atBats)타수 \(match.line.hits)안타 · \(match.line.homeRuns)홈런"
                            : "\(match.line.pitchingOuts / 3).\(match.line.pitchingOuts % 3)이닝 · \(match.line.pitchingStrikeouts)K") : "비등판 · 팀 경기")
                            .font(.caption)
                    }.padding(.vertical, 5)
                    Rectangle().fill(GameTheme.boardLine.opacity(0.4)).frame(height: 1).accessibilityHidden(true)
                } else if recentSnapshots[record.key] == nil { Text("기록 확인 중").font(.caption) }
                else { Text("\(record.gameDate) 기록을 읽을 수 없습니다. 기존 저장은 유지합니다.").font(.caption).foregroundStyle(GameTheme.gold) }
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
    private var ownTeamID:String {(try? state.competition(for:player,year:(try? GameDate(player.gameDate).year) ?? 2026).teamID) ?? player.schoolID}
    var body: some View {
        GamePanel(title:"연간 리그",onBoard:true) {
            if let row=league?.standings.first(where:{$0.id == ownTeamID}) {
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
    private func name(_ id:String) -> String {CareerTeamDirectory.name(id,schools:schools)}
    private func reload() {
        do {
            let year=try selectedYear ?? GameDate(player.gameDate).year
            league=try AnnualLeagueStore.load(player:player,state:state,year:year,in:context);error=nil
        } catch {league=nil;self.error=error.localizedDescription}
    }
    private var ownTeamID:String {(try? state.competition(for:player,year:league?.year ?? (try? GameDate(player.gameDate).year) ?? 2026).teamID) ?? player.schoolID}
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
                Text("\(row.rank.map {"\($0)위"} ?? "—") · \(name(row.id))\(row.id == ownTeamID ? " · 내 팀":"")").font(.headline)
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
            .background(row.id == ownTeamID ? Color(hex:0x244e48):GameTheme.board)
            .overlay(Rectangle().strokeBorder(row.id == ownTeamID ? GameTheme.gold:GameTheme.boardLine,lineWidth:row.id == ownTeamID ? 2:1))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(name(row.id))\(row.id == ownTeamID ? " 내 팀":"") · 순위 \(row.rank.map(String.init) ?? "미정") · \(row.games)경기 \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)")
            .accessibilityIdentifier(row.id == ownTeamID ? "leagueOwnStanding":"leagueStanding-\(row.id)")
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
    private func name(_ id: String) -> String { CareerTeamDirectory.name(id,schools:schools) }
    private func reload() {
        do {
            let year = try selectedYear ?? CareerSeasonStore.offseason(player: player, state: state, in: context)?.seasonYear ?? GameDate(player.gameDate).year
            summary = try CareerSeasonStore.load(player: player, state: state, year: year, in: context)
            if selectedYear == nil { selectedYear = year }
            error = nil
        } catch { summary = nil; self.error = error.localizedDescription }
    }
    private var ownTeamID:String {(try? state.competition(for:player,year:summary?.league.year ?? (try? GameDate(player.gameDate).year) ?? 2026).teamID) ?? player.schoolID}
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
                        Text("\(player.name) · \(name(ownTeamID)) · \(player.role.label)").font(.caption).accessibilityIdentifier("seasonPlayer")
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
                                Text("\(row.rank.map { "\($0)위" } ?? "—") · \(name(row.id))\(row.id == ownTeamID ? " · 내 팀" : "")").font(.headline)
                                Text("\(row.games)경기 · \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)").font(.caption.monospaced())
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(row.id == ownTeamID ? Color(hex: 0x244e48) : GameTheme.board)
                                .overlay(Rectangle().strokeBorder(row.id == ownTeamID ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
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


struct CareerPathHomePanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var history: CareerPathHistory?
    @State private var failure: String?
    @State private var expanded = false
    var body: some View {
        GamePanel(title: "진로 · 소속 이력", onBoard: true) {
            if let failure {
                Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("careerPathError")
                Button("다시 확인", action:load).buttonStyle(MatchPixelButtonStyle())
            } else if let history {
                Text((try? calendar.registration(for:player))?.label ?? history.current.stage.label).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("careerPathStage")
                Text((try? calendar.registration(for:player)).map {"현재 소속 · "+$0.name+" / 출신 · "+player.schoolName} ?? (history.current.stage == .school ? "현재 소속 · \(history.current.schoolName ?? player.schoolName)" : "현재 소속 · 무소속 / 출신 · \(player.schoolName)"))
                    .font(.caption).accessibilityIdentifier("careerPathAffiliation")
                Text("관심·선발·제의와 실제 등록을 구분합니다. 수락한 소속과 제의 결정은 별도 이력으로 보관합니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                HomeDetailButton(title:"신청 경로 · 소속 이력",expanded:$expanded,identifier:"careerPathDetails")
                if expanded {
                    let age = (try? calendar.age(of:player)) ?? player.startAge
                    ForEach(CareerRoute.routes(age:age)) { route in
                        VStack(alignment:.leading,spacing:6) {
                            Text(route.title).font(.subheadline.bold())
                            Text(route.status).font(.caption.bold()).foregroundStyle(GameTheme.gold)
                            Text(route.detail).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }.padding(.vertical,4).accessibilityElement(children:.combine).accessibilityIdentifier("careerRoute-"+route.id)
                    }
                    Text("표시된 경로는 기본 나이 조건입니다. 등록 중인 소속/보유 권리와 실제 제의 상태를 함께 확인하세요.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    ForEach(Array(history.entries.enumerated()),id:\.offset) { _, entry in
                        Text("\(entry.since) · \(entry.stage.label)\(entry.schoolName.map { " · " + $0 } ?? "")")
                            .font(.caption.monospaced()).accessibilityIdentifier("careerAffiliationHistory")
                    }
                    if let journal=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context) {
                        ForEach(journal.retryReleases,id:\.membershipOfferID) {release in
                            Text(release.date+" · 방출 확정 / 보유권리 해제 · 무소속").font(.caption).accessibilityIdentifier("careerReleaseHistory")
                        }
                        ForEach(journal.collegeTransitions ?? [],id:\.offerID) {item in
                            Text(item.acceptedDate+" · 대학 재학생 프로 계약 수락 / "+item.source.effectiveDate+" 소속 전환 · 대학 학적 원본 보존").font(.caption).accessibilityIdentifier("collegeProHistory")
                        }
                        ForEach(journal.overseasCareer?.transitions ?? [],id:\.offerID) {item in
                            Text(item.acceptedDate+" · 해외 계약 수락 / "+item.destination.since+" · "+item.destination.name+" · "+item.destination.label).font(.caption).accessibilityIdentifier("overseasAffiliationHistory")
                        }
                        ForEach(journal.overseasCareer?.promotions ?? []) {item in
                            Text(item.date+" · "+(item.toLevel == "domestic-first-team" ? "국내1군":"미국 조직 메이저")+" 승격 확정 / "+item.effective+" 발효").font(.caption).accessibilityIdentifier("careerPromotionHistory")
                        }
                        ForEach(journal.memberships,id:\.offerID) {member in
                            Text(member.since+" · "+member.label+" · "+member.name).font(.caption).accessibilityIdentifier("careerRegisteredHistory")
                            Text(member.route == .rookie ? "경제 기간 종료 "+member.economicEnd+" · 보유 권리 자동 해제 없음":"학적 종료 "+(member.enrollmentEnd ?? "—"))
                                .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    if history.source == "legacy-v1" {
                        Text("기존 저장은 최초 등록 시점부터 이력을 보관합니다. 이전 졸업·프로 경력은 추정하지 않습니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }
            }
        }.task(id:calendar.revision) { load() }
    }
    private func load() {
        do {
            _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
            guard let row = try CareerPathStore.record(player:player,calendar:calendar,in:context) else { throw CareerPathError.invalid }
            history = try row.snapshot(player:player,calendar:calendar); failure = nil
        } catch { history = nil; failure = error.localizedDescription }
    }
}


struct ContractEvaluationHomePanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @Environment(\.modelContext) private var context
    @Query private var evaluations: [CareerContractEvaluation]
    @State private var details = false
    @State private var selectedKey: String?
    @State private var failure: String?
    private var own: [CareerContractEvaluation] { evaluations.filter {$0.playerID == player.id}.sorted {$0.key > $1.key} }
    var body: some View {
        GamePanel(title:"계약 평가 · 연간 창",onBoard:true) {
            Text(verbatim:"4월 1~14일 진로 · 7월 1~14일 무소속 · 11월 1~14일 프로")
                .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("contractWindows")
            if let failure {
                Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractEvaluationError")
                Button("다시 확인") {self.failure = nil}.buttonStyle(MatchPixelButtonStyle())
            }
            if let row = own.first(where: {!$0.acknowledged}) ?? own.first(where: {$0.key == selectedKey}) ?? own.first {
                if let value = try? row.snapshot(player:player,calendar:calendar) {
                    Text(value.window.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                    Text("\(value.evaluatedDate) 평가 자료 고정 · \(row.acknowledged ? "확인 완료":"확인 필요")")
                        .font(.caption).accessibilityIdentifier("contractEvaluationStatus")
                    Text(value.routes.joined(separator:" / ")).font(.caption).accessibilityIdentifier("contractEvaluationRoutes")
                    if let renewal=value.renewal {
                        DomesticRenewalSummary(player:player,calendar:calendar,value:renewal,evaluatedDate:value.evaluatedDate)
                    } else if let college=value.college {
                        Text("대학 재학생 · 프로 진출 심사").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("collegeProReview")
                        Text("전환 예정일 · "+college.effectiveDate+" / 성인 성적 보정 P=0").font(.caption)
                        ForEach(college.results.filter {$0.selected || !$0.reasons.isEmpty}.prefix(4)) {row in
                            Text(row.name+" · "+DomesticContractOffer.roleName(row.role)+" · "+(row.selected ? "프로 진출 제의 대상":row.reasons.joined(separator:" / "))).font(.caption)
                        }
                    } else if let retry=value.retry {
                        Text("무소속 국내 육성팀 재입단 · 성인 경쟁 심사").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("retryReviewStatus")
                        if let certificate=retry.certificate {
                            Text("인증 평가전 · \(certificate.date) · \(String(format:"%.1f",certificate.score))점 · \(certificate.passed ? "기준 충족":"기준 미달")")
                                .font(.caption).accessibilityIdentifier("retryCertificate")
                        }
                        ForEach(retry.results.filter {$0.selected || !$0.reasons.isEmpty}.prefix(4)) {row in
                            Text(row.name+" · "+DomesticContractOffer.roleName(row.role)+" · "+(row.selected ? "재입단 제의 대상":row.reasons.joined(separator:" / "))).font(.caption)
                        }
                    } else if let selection=value.selection {
                        DomesticSelectionHomeSummary(value:selection)
                    } else {
                        Text("이 원장에는 선발 자료가 기록되지 않았습니다. 기존 자료를 유지하고 다음 허용 창에서 심사합니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("contractSelectionLegacy")
                    }
                    if value.renewal == nil {DomesticOfferHomePanel(player:player,calendar:calendar,evaluation:row)}
                    if !row.acknowledged {
                        Text("같은 창에서는 성장하거나 재실행해도 다시 평가하지 않습니다. 자료를 확인하면 날짜 진행을 계속할 수 있습니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Button("평가 자료 확인 · 계속") {
                            do {try ContractEvaluationStore.acknowledge(player:player,calendar:calendar,key:row.key,date:player.gameDate,revision:calendar.revision,in:context);failure = nil}
                            catch {failure = error.localizedDescription}
                        }.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("acknowledgeContractEvaluation")
                    }
                    HomeDetailButton(title:"고정 자료 · 평가 이력",expanded:$details,identifier:"contractEvaluationDetails")
                    if details {
                        ForEach(value.observation.grades) { grade in
                            Text("\(grade.label) H \(grade.score.map {String(format:"%.1f",$0)} ?? "—")")
                                .font(.caption.monospaced()).accessibilityIdentifier("contractEvaluationGrade-"+grade.id)
                        }
                        Text(value.renewal != nil ? "재계약 심사와 제의는 이 평가일에 고정됩니다. 상세에서 수락하면 저장된 경제 기간을 적용합니다.":value.selection == nil && value.college == nil && value.retry == nil ? "선발 심사 자료 미기록 · 과거 원장은 다시 평가하지 않습니다.":"성적·모집 자리·예산·후보 순서는 평가일에 고정됩니다. 실제 입단 제의는 보관함에서 확인합니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text("당시 평가에 기록된 후속 항목 · 현재 제의는 보관함 확인").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        ForEach(value.pending,id:\.self) {Text($0).font(.caption).foregroundStyle(GameTheme.boardMuted)}
                        ForEach(own) { record in
                            Button((record.key.components(separatedBy:":").last ?? "") + " · 고정 자료 보기") {selectedKey = record.key}.font(.caption.monospaced()).buttonStyle(MatchPixelButtonStyle())
                        }
                    }
                } else {Text(ContractEvaluationError.invalid.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold)}
            } else {
                Text(((try? calendar.age(of:player)) ?? 16) < 20 ? "20세 전에는 정식 평가 자료를 만들지 않습니다.":"해당 경로의 평가 창에서 자료를 한 번 고정합니다.")
                    .font(.caption).accessibilityIdentifier("contractEvaluationWaiting")
            }
            if let date = try? GameDate(player.gameDate), ContractEvaluationWindow.containing(date)?.month == 11,
               (try? calendar.registration(for:player)) == nil {
                Text("11월은 프로 외부/갱신 창입니다. 현재 고교·진로 준비·무소속 선수는 대상이 아닙니다. 국내 육성팀 재계약과 자격을 충족한 대학 재학생 프로 진출을 평가합니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("contractNovemberIneligible")
            }
        }
    }
}

struct DomesticSelectionHomeSummary: View {
    let value: DomesticSelection
    @State private var details=false
    private func best(_ route:DomesticSelectionRoute) -> DomesticSelectionResult? {
        value.results.filter {$0.route == route}.sorted {
            if $0.selected != $1.selected {return $0.selected}
            if $0.reasons.count != $1.reasons.count {return $0.reasons.count < $1.reasons.count}
            return ($0.f ?? -1000) == ($1.f ?? -1000) ? $0.id < $1.id:($0.f ?? -1000) > ($1.f ?? -1000)
        }.first
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("선발 심사 결과").font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
            Text(value.sample.map {"\($0.kind) · \($0.endDate) 종료 · P \(String(format:"%+.1f",$0.comparison.correction))"} ?? "유효 성적 표본 없음 · 심사 보류")
                .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("contractSelectionSample")
            ForEach(DomesticSelectionRoute.allCases,id:\.rawValue) {route in
                if let row=best(route) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("\(route.label) · \(row.status)").font(.subheadline.bold())
                            .foregroundStyle(row.selected ? GameTheme.gold:GameTheme.boardInk).accessibilityIdentifier("contractSelection-"+route.rawValue)
                        Text(row.name+" · "+(valueRole(row.role))).font(.caption)
                        Text("H \(row.h.map {String(format:"%.1f",$0)} ?? "—") / C \(Int(row.c)) / P \(String(format:"%+.1f",row.p)) / F \(row.f.map {String(format:"%+.1f",$0)} ?? "—")")
                            .font(.caption.monospaced()).accessibilityIdentifier("contractSelectionFit-"+route.rawValue)
                        Text("자리 \(row.availableSeats) · 예산 \(row.availableBudget)/필요\(row.cost)지수 · 경쟁 \(row.competition)명")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        if row.selected {
                            Text("\(route == .rookie ? "해당 창의 지명 협상 대상":"대학 입단 선택 대상") · 실제 제의 조건은 보관함에서 확인하세요.").font(.caption).foregroundStyle(GameTheme.gold)
                        } else {
                            ForEach(Array(row.reasons.prefix(3)),id:\.self) {Text($0).font(.caption).foregroundStyle(GameTheme.boardMuted)}
                        }
                    }.padding(10).overlay(Rectangle().stroke(GameTheme.boardMuted.opacity(0.35),lineWidth:1))
                }
            }
            HomeDetailButton(title:"모집·예산·경쟁 심사표",expanded:$details,identifier:"contractSelectionDetails")
            if details {
                Text("가상6구단 역순3라운드 · 가상6대학 역할별1자리 / 실제 구단 수요·입시 재현 아님")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                Text(value.priorMarket).font(.caption)
                ForEach(value.results) {row in
                    VStack(alignment:.leading,spacing:6) {
                        Text(row.name+" · "+valueRole(row.role)+" · "+row.status).font(.caption.bold())
                        Text("F \(row.f.map {String(format:"%+.1f",$0)} ?? "—") · 자리\(row.availableSeats) · 예산\(row.availableBudget)/필요\(row.cost) · 경쟁\(row.competition)").font(.caption.monospaced())
                        Text(row.reasons.isEmpty ? "모든 입단 조건 충족 · 고정 후보 순서로 선발":row.reasons.joined(separator:" / ")).font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }.padding(.vertical,6)
                }
            }
        }
    }
    private func valueRole(_ id:String) -> String {
        switch id {case "slugger":"장타";case "onBase":"출루";case "field":"수비";default:"선발"}
    }
}

struct CareerContractStatusPanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    var body: some View {
        let _=calendar.revision
        GamePanel(title:"계약 · 소속 · 보유권리",onBoard:true) {
            switch status {
            case .success(let value):
                if let value {
                    Text("현재 소속 · "+value.membership.name).font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractCurrentTeam")
                    Text(value.economicExpired && pendingOverseasRenewal != nil ? "기존 경제 기간 종료 · 갱신 발효 대기":value.economicLabel).font(.subheadline.bold()).accessibilityIdentifier("contractEconomicStatus")
                    Text((value.membership.economicStart ?? value.membership.since)+" ~ "+value.membership.economicEnd+" · \(value.membership.economicIndex)\(value.membership.route == .rookie ? " 연봉지수":" 지원지수")")
                        .font(.caption.monospaced()).accessibilityIdentifier("contractEconomicPeriod")
                    if let pending=pendingRenewal {
                        Text("갱신 예정 · "+pending.terms.effectiveDate+" ~ "+pending.terms.economicEnd+" · 연봉지수 \(pending.terms.economicIndex)")
                            .font(.caption).foregroundStyle(GameTheme.growth).accessibilityIdentifier("contractPendingRenewal")
                    }
                    Text(value.rightsLabel).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractRightsStatus")
                    if value.membership.level == "domestic-development" {
                        Text("갱신 평가 창 · "+(value.nextReview ?? "—")+"부터 14일까지")
                            .font(.caption).accessibilityIdentifier("contractNextRenewal")
                        Text("11월 창 안에서는 최초 적격일의 평가·제의를 한 번 고정합니다. 경제 기간 종료나 제의 만료로 소속/권리가 자동 해제되지 않습니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    } else if value.membership.route == .rookie {
                        Text(value.membership.label+" · 조직 보유권리 유지 / 승격·이적은 별도 심사").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    } else {
                        Text("학적 종료 · "+(value.membership.enrollmentEnd ?? "—")+" · 프로 지원:22~23세/재학2년 이상 · 11월")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                } else {
                    Text("등록 경제 계약 없음 · 프로 구단 보유권리 없음").font(.caption).accessibilityIdentifier("contractNoRegistration")
                    Text("현재 학적/진로 소속은 소속 이력에서 확인하세요.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            case .failure(let error):
                Text(error.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractStatusError")
            }
        }
        CollegeProStatusPanel(player:player,calendar:calendar)
        OverseasEligibilityPanel(player:player,calendar:calendar)
        OverseasRenewalPanel(player:player,calendar:calendar)
        ProCareerProgressPanel(player:player,calendar:calendar)
        FAManagementPanel(player:player,calendar:calendar)
        OverseasReleasePanel(player:player,calendar:calendar)
        DomesticReleasePanel(player:player,calendar:calendar)
    }
    private var pendingOverseasRenewal:OverseasOffer? {
        guard let context=calendar.modelContext,let owner=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),
              let member=try? owner.current(on:GameDate(player.gameDate)),let state=owner.overseasCareer else {return nil}
        return (state.renewalReviews ?? []).last {review in
            guard review.source.offerID == member.offerID,let offer=review.offer,offer.effective > player.gameDate else {return false}
            return (state.renewalDecisions ?? []).contains {$0.offerID == offer.id && $0.kind == .accepted}
        }?.offer
    }
    private var pendingRenewal:DomesticRenewalAcceptance? {
        guard let context=calendar.modelContext,
              let journal=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context) else {return nil}
        return journal.renewals?.last {$0.terms.effectiveDate > player.gameDate}
    }
    private var status: Result<CareerContractStatus?,Error> {
        Result {try calendar.registration(for:player).map {try CareerContractStatus($0,on:GameDate(player.gameDate))}}
    }
}

struct DomesticRenewalSummary: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let value: DomesticRenewalReview
    let evaluatedDate: String
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(value.membership.name+" · 재계약 평가").font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
            Text(value.offer == nil ? "재계약 제의 없음":"실제 재계약 제의 1건 발행")
                .font(.headline).accessibilityIdentifier("renewalReviewStatus")
            Text(DomesticContractOffer.roleName(value.roleID)+" · H \(value.h.map {String(format:"%.1f",$0)} ?? "—") / C \(String(format:"%.1f",value.c)) / P +0.0 / F \(value.f.map {String(format:"%+.1f",$0)} ?? "—")")
                .font(.caption.monospaced()).accessibilityIdentifier("renewalReviewFit")
            Text("육성 표본 \(value.sampleCount)\(player.role == .batter ? "타석":"타자 상대") · 모집 자리 1 · 경쟁 기준 \(Int(value.competitorH)) · 가용 예산 \(value.budget)지수")
                .font(.caption).foregroundStyle(GameTheme.boardMuted)
            ForEach(value.reasons,id:\.self) {Text($0).font(.caption).foregroundStyle(GameTheme.gold)}
            NavigationLink {DomesticRenewalDetail(player:player,calendar:calendar,value:value,evaluatedDate:evaluatedDate)} label: {
                Text(value.offer == nil ? "재계약 심사 근거 보기":"재계약 제의 상세 보기")
            }.buttonStyle(MatchPixelButtonStyle(primary:value.offer != nil)).accessibilityIdentifier("openRenewalOffer")
        }
    }
}
struct DomesticRenewalDetail: View {
    @Environment(\.modelContext) private var context
    @State private var error:String?
    @State private var command:(date:String,revision:Int,accept:Bool)?
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let value: DomesticRenewalReview
    let evaluatedDate: String
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                GamePanel(title:"재계약 제의 · 고정 자료",onBoard:true) {
                    Text(value.membership.name).font(.title2.bold()).foregroundStyle(GameTheme.gold)
                    Text(player.name+" · "+DomesticContractOffer.roleName(value.roleID)+" · 국내 육성/출전 경쟁")
                        .font(.subheadline)
                    Text(evaluatedDate+" 평가 · 같은 창 재평가 없음").font(.caption).accessibilityIdentifier("renewalFrozenDate")
                    if let offer=value.offer {
                        Text("발행 · "+offer.issuedDate+" / 유효 마감 · "+offer.expiresDate).font(.caption.monospaced())
                        Text((try? GameDate(player.gameDate) > GameDate(offer.expiresDate)) == true ? "제의 만료 · 원본 이력 보관":"검토 가능한 재계약 제의")
                            .font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("renewalOfferValidity")
                        Text("예정 경제 기간 · "+offer.effectiveDate+" ~ "+offer.economicEnd).font(.caption.monospaced()).accessibilityIdentifier("renewalOfferPeriod")
                        Text("1개 달력연도 · 연봉지수 \(offer.economicIndex)").font(.headline).accessibilityIdentifier("renewalOfferEconomics")
                        switch acceptance {
                        case .success(let accepted):
                            if let accepted {
                                Text(accepted.terms.effectiveDate > player.gameDate ? "수락 완료 · 갱신 예정":"수락 완료 · 경제 기간 적용")
                                    .font(.headline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("renewalAccepted")
                                Text("수락일 · "+accepted.date+" / 소속과 보유권리 유지").font(.caption)
                            } else if rejected {
                                Text("재계약 거절 완료 · 소속/보유권리 유지").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("renewalRejected")
                            } else if player.gameDate <= offer.expiresDate {
                                Button("재계약 수락") {command=(player.gameDate,calendar.revision,true)}
                                    .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("acceptRenewalOffer")
                                Button("재계약 거절") {command=(player.gameDate,calendar.revision,false)}
                                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("rejectRenewalOffer")
                                Text("수락 후 시작일에 새 경제 조건이 적용됩니다. 날짜·피로·소속·보유권리는 유지됩니다.").font(.caption)
                            }
                        case .failure(let failure):Text(failure.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold)
                        }
                        if let error {Text(error).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("renewalDecisionError")}
                    } else {
                        Text("제의 없음 · 소속과 보유권리는 유지됩니다.").font(.headline).foregroundStyle(GameTheme.gold)
                        ForEach(value.reasons,id:\.self) {Text($0).font(.caption)}
                    }
                }
                GamePanel(title:"심사 근거 · 역할/표본/예산",onBoard:true) {
                    Text("H \(value.h.map {String(format:"%.1f",$0)} ?? "—") · C \(String(format:"%.1f",value.c)) · F \(value.f.map {String(format:"%+.1f",$0)} ?? "—")")
                        .font(.subheadline.monospaced())
                    Text("현재 구단 갱신 자리 1 / 고정 NPC 경쟁 기량 \(Int(value.competitorH)) / 가용 예산 \(value.budget)지수")
                        .font(.caption)
                    if let totals=value.totals {
                        Text(player.role == .batter ? "\(totals.games)경기 · \(totals.line.plateAppearances)타석 · \(totals.line.hits)안타 · \(totals.line.homeRuns)홈런":"\(totals.games)경기 · \(totals.innings)이닝 · \(totals.line.pitchingStrikeouts)탈삼진 · \(totals.line.runsAllowed)실점")
                            .font(.caption).accessibilityIdentifier("renewalActualStats")
                    }
                    Text("성적 출처 · "+sampleLabel).font(.caption).accessibilityIdentifier("renewalSampleSource")
                    Text("성인 리그 비교 기준은 미검증이므로 P=0 중립입니다. 고교 성적/자동 팀 결과를 섞지 않으며 실제 육성 출전 표본이 부족하면 보류합니다.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Text("제의 없음/만료만으로 방출 또는 FA를 확정하지 않습니다. 수락해도 소속·보유권리는 유지되며 방출은 별도 결정입니다.")
                        .font(.caption).foregroundStyle(GameTheme.gold)
                }
            }.padding(14).frame(maxWidth:540,alignment:.leading).frame(maxWidth:.infinity)
        }.background(GameTheme.navy).foregroundStyle(GameTheme.boardInk)
            .confirmationDialog("재계약 결정을 확정할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
                Button(command?.accept == true ? "수락 확정":"거절 확정") {
                    guard let selected=command,let offer=value.offer else {return}
                    command=nil
                    do {
                        if selected.accept {try ContractRegistrationStore.acceptRenewal(player:player,calendar:calendar,offerID:offer.id,date:selected.date,revision:selected.revision,in:context)}
                        else {try ContractRegistrationStore.rejectRenewal(player:player,calendar:calendar,offerID:offer.id,date:selected.date,revision:selected.revision,in:context)}
                        error=nil
                    }
                    catch {self.error=error.localizedDescription}
                }.accessibilityIdentifier("confirmRenewalAcceptance")
                Button("취소",role:.cancel) {command=nil}
            }
            .navigationTitle("재계약 제의 상세").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.navy,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
            .toolbarColorScheme(.dark,for:.navigationBar).tint(GameTheme.gold)
    }
    private var rejected:Bool {
        (try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).renewalRejections?.contains {$0.offerID == value.offer?.id}) == true
    }
    private var acceptance:Result<DomesticRenewalAcceptance?,Error> {
        let _=calendar.revision
        return Result {try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).renewals?.first {$0.terms.id == value.offer?.id}}
    }
    private var sampleLabel: String {
        guard let id=value.sampleID else {return "유효 육성 표본 없음"}
        let position=id.split(separator:"/").dropLast().last.map(String.init)
        let label=player.role == .pitcher ? "투수":position.flatMap {FieldPosition(rawValue:$0)?.label} ?? player.roleDetail
        let mode=ScoutingInputMode.allCases.first {id.hasSuffix("/"+$0.suffix)}?.label ?? "조작 분류 미기록"
        return "국내 육성 공식 경기 · "+label+" · "+mode
    }
}

struct DomesticReleasePanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var command:(key:String,date:String,revision:Int)?
    @State private var error:String?
    var body:some View {
        let _=calendar.revision
        Group {
            switch Result(catching:{
                let journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
                return (journal,try ContractRegistrationStore.releaseCandidate(player:player,calendar:calendar,in:context),try journal.current(on:GameDate(player.gameDate)) == nil)
            }) {
            case .failure(let failure):Text(failure.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold)
            case .success(let state):
                if let candidate=state.1 {
                    GamePanel(title:"보유권리 · 방출 통지",onBoard:true) {
                        Text("경제 기간 종료 + 11월 재계약 미체결 + 갱신 수락 없음").font(.subheadline)
                        Text("11월 15일~다음 해 3월 31일에 별도 방출 확정이 필요합니다. 거절·만료만으로 자동 FA가 되지 않습니다.").font(.caption)
                        if candidate.eligible {
                            Button("방출 통지 확인 · 권리 해제") {command=(candidate.key,player.gameDate,calendar.revision)}
                                .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("confirmClubRelease")
                        } else {Text("아직 방출 확정 조건을 충족하지 않았습니다.").font(.caption).accessibilityIdentifier("releaseNotEligible")}
                    }
                } else if state.2,let released=state.0.activeRetryRelease {
                    GamePanel(title:"무소속 · 국내 육성팀 재도전",onBoard:true) {
                        Text("방출 확정 · "+released.date+" / 보유권리 해제").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("releasedUnsignedStatus")
                        Text("다음 4월·7월 평가 창에 재입단 심사 · 신인 지명과 별도").font(.subheadline)
                        Text("육성 성적40타석/15이닝 또는 인증 평가전으로 심사합니다. 현재 능력·구단 자리/예산·고정 후보 경쟁을 함께 평가합니다.").font(.caption)
                        NavigationLink {CertificationView(player:player,calendar:calendar)} label: {Text("인증 평가전 · 시작/이어하기")}
                            .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("openCertification")
                    }
                }
            }
            if let error {Text(error).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("releaseDecisionError")}
        }.confirmationDialog("구단 방출 통지를 확정할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
            Button("방출 확정 · 무소속 전환",role:.destructive) {
                guard let selected=command else {return};command=nil
                do {try ContractRegistrationStore.release(player:player,calendar:calendar,evaluationKey:selected.key,date:selected.date,revision:selected.revision,in:context);error=nil}
                catch {self.error=error.localizedDescription}
            }.accessibilityIdentifier("commitClubRelease")
            Button("취소",role:.cancel) {command=nil}
        }
    }
}

struct CertificationView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var row:CareerCertificationRecord?
    @State private var snapshot:CareerCertification?
    @State private var failure:String?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                GamePanel(title:"무소속 인증 평가전",onBoard:true) {
                    Text(player.name+" · 동일 환경 자동 평가").font(.title3.bold()).foregroundStyle(GameTheme.gold)
                    Text("시작 시 능력·구종 고정 / 표준 컨디션 / 특성 제외 / 야수 숙련60").font(.caption)
                    Text("타자4경기 · 12타석/출루율25% 이상 / 투수2경기 · 12타자/평가지수45 이상").font(.caption)
                    Text("공식 시즌·XP와 분리 · 완료 시 하루 행동/피로+8 한 번 · 다음4·7월 창당1회").font(.caption)
                    if let value=snapshot {
                        Text("제출 대상 · "+value.window.id+" 평가 창").font(.headline).accessibilityIdentifier("certificationWindow")
                        Text("\(value.games.count) / \(value.role == .batter ? 4:2)경기 완료").font(.subheadline.monospaced()).accessibilityIdentifier("certificationProgress")
                        ForEach(Array(value.games.enumerated()),id:\.offset) {index,game in
                            Text(value.role == .batter ? "\(index+1)경기 · \(game.line.plateAppearances)타석 \(game.line.hits)안타 \(game.line.walks)볼넷":"\(index+1)경기 · \(game.line.pitchingOuts)아웃 \(game.line.pitchingStrikeouts)탈삼진 \(game.line.pitchingWalks)볼넷").font(.caption.monospaced())
                        }
                        if let assessment=value.assessment {
                            Text("평가 완료 · \(assessment.score,specifier:"%.1f")점 · \(assessment.passed ? "기준 충족":"기준 미달")").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("certificationResult")
                            Text("결과는 대상 창에서 자동 제출합니다. 이미 고정된 현재 창은 바꾸지 않습니다.").font(.caption)
                        } else {
                            Button("다음 평가 경기 자동 진행") {advance()}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("advanceCertification")
                        }
                    } else {
                        Button("참가 신청 · 저장된 평가전 확인") {start()}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("startCertification")
                    }
                    if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("certificationError")}
                }
                GamePanel(title:"심사 기준",onBoard:true) {
                    Text("타자 점수 = 출루(안타+볼넷)/타석 ×100").font(.caption)
                    Text("투수 지수 = 50+100×(탈삼진−볼넷−2×피홈런)/상대 타자, 0~100 제한").font(.caption)
                    Text("통과는 표본 자격을 보완합니다. 제의는 현재 역할 기량·구단 자리/예산·후보 경쟁 심사를 별도로 통과해야 합니다.").font(.caption)
                }
            }.padding(14)
        }.background(GameTheme.navy).foregroundStyle(GameTheme.boardInk).navigationTitle("인증 평가전").navigationBarTitleDisplayMode(.inline)
    }
    private func start() {
        do {let row=try CertificationStore.start(player:player,calendar:calendar,in:context);self.row=row;snapshot=try row.snapshot();failure=nil}
        catch {failure=error.localizedDescription}
    }
    private func advance() {
        guard let row else {return}
        do {try CertificationStore.advance(player:player,calendar:calendar,row:row,revision:row.revision,in:context);snapshot=try row.snapshot();failure=nil}
        catch {failure=error.localizedDescription}
    }
}


struct CollegeProStatusPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    var body:some View {
        if let context=calendar.modelContext {
            let _=calendar.revision
            switch Result(catching:{try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)}) {
            case .success(let journal):
                if let item=journal.collegeTransitions?.last,
                   let destination=journal.memberships.first(where:{$0.offerID == item.offerID}) {
                    GamePanel(title:"대학 → 프로 진출",onBoard:true,contentSpacing:12) {
                        Text(item.source.effectiveDate > player.gameDate ? "프로 계약 수락 · 소속 전환 예정":"프로 소속 전환 완료").font(.headline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("collegeProTransitionStatus")
                        Text(destination.name+" · "+item.source.effectiveDate+"부터").font(.subheadline)
                        Text("수락일 "+item.acceptedDate+" · 대학 입단/학적 원본을 보존합니다. 전환일부터 대학 출전은 종료되며 프로 소속/보유권리가 적용됩니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                } else if let member=try? journal.current(on:GameDate(player.gameDate)),member.route == .college {
                    GamePanel(title:"대학 재학생 · 프로 지원",onBoard:true,contentSpacing:12) {
                        let eligible=(try? CollegeProReview.eligible(member:member,age:calendar.age(of:player),on:GameDate(player.gameDate))) == true
                        Text(eligible ? "지원 자격 충족 · 11월 고정 심사":"지원 준비 · 22~23세 / 재학 2년 이상").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("collegeProEligibility")
                        Text("동일 환경 대학 공식 성적40타석/15이닝 · 역할 기량·수비 조건·구단 자리/예산/고정 경쟁을 함께 심사합니다.").font(.caption)
                        Text("11월1~14일 최초 적격일 평가 · 제의 수락 시 다음 해4월1일 전환. 거절/미선발은 대학 소속을 유지합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }
            case .failure(let error):Text(error.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold)
            }
        }
    }
}

struct OverseasEligibilityPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    @State private var refreshed=0
    @State private var details=false
    var body:some View {
        let _=calendar.revision;let _=refreshed
        GamePanel(title:"해외 진출 · 자격과 경력",onBoard:true,contentSpacing:12) {
            switch Result(catching:{try OverseasEligibilityStore.current(player:player,calendar:calendar,in:context)}) {
            case .success(let value):
                Text("현재 자격 · "+value.evidence.date+" / 관찰과 정식 제의는 별도").font(.caption).foregroundStyle(GameTheme.boardMuted)
                ForEach(value.routes) {row in
                    VStack(alignment:.leading,spacing:7) {
                        Text(row.route.label+" · "+row.status.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasEligibility-"+row.id)
                        Text(row.reasons.first ?? "선발 심사를 준비하세요").font(.caption)
                    }.padding(.vertical,4)
                }
                NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("해외 성적 비교 · 성장 전망")}
                    .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("openOverseasReport")
                if let report=try? OverseasReportStore.current(player:player,calendar:calendar,in:context),let market=report.market {
                    let interests=market.clubs.filter {$0.interest != nil}
                    Text(interests.isEmpty ? "최근 해외 보고서 · 관심 없음":"최근 해외 보고서 · 관심 역할 \(interests.count)건 / 정식 제의 별도")
                        .font(.caption).foregroundStyle(GameTheme.growth).accessibilityIdentifier("homeOverseasInterest")
                }
                if (try? OverseasContractStore.needsEvaluation(player:player,calendar:calendar,in:context)) == true {
                    Text("해외 평가 창 도착 · 해외 제의 화면에서 이번 창 심사를 확인한 뒤 날짜를 진행하세요.").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasEvaluationDue")
                }
                NavigationLink {OverseasContractsView(player:player,calendar:calendar)} label: {Text("해외 실제 제의 · 상세/비교")}
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openOverseasContracts")
                HomeDetailButton(title:"경력 근거 · 부족 조건",expanded:$details,identifier:"overseasEligibilityDetails")
                if details {
                    ForEach(value.routes) {row in
                        Text(row.route.label+"\n"+row.reasons.joined(separator:"\n")).font(.caption).lineSpacing(4)
                    }
                    Text("공식 개인 경기 근거 \(value.evidence.matches.count)건 · 대학/육성/프로1군 경력을 구분합니다. MLB 인정 해외 프로시즌은 자료 미확인이며0시즌으로 확정하지 않습니다.").font(.caption).accessibilityIdentifier("overseasServiceEvidence")
                    Text("2026 공식 규정 참고 · 게임 경로 판정. 국적/거주·실제 인정 경력/등록·이적 승인은 확인 자료 없이 통과시키지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Button("현재 자격 자료 기록") {
                        do {try OverseasEligibilityStore.capture(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context);failure=nil;refreshed += 1}
                        catch {failure=error.localizedDescription}
                    }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("captureOverseasEligibility")
                    if let journal=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),let last=journal.overseasEligibility?.last {
                        Text("최근 고정 자료 · "+last.evidence.date+" / \(journal.overseasEligibility?.count ?? 0)건 보존").font(.caption).foregroundStyle(GameTheme.growth).accessibilityIdentifier("overseasEligibilitySaved")
                    }
                }
            case .failure(let error):Text(error.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold)
            }
            if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold)}
        }
    }
}

struct OverseasScoutingReportView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var report:OverseasScoutingReport?
    @State private var failure:String?
    @State private var working=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                GamePanel(title:"해외 스카우트 · 고정 자료",onBoard:true,contentSpacing:12) {
                    Text(player.name+" · "+player.role.label).font(.title3.bold()).foregroundStyle(GameTheme.gold)
                    if let report {
                        Text(report.observation.observedDate+" 기준 · 28일 주기 \(report.period) 자료 고정").font(.caption).accessibilityIdentifier("overseasReportDate")
                        Text("현재 능력과 평가일의 자료는 다를 수 있습니다. 같은 주기에서는 재평가하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    } else {Text("현재 주기의 고정 보고서가 없습니다.").font(.caption)}
                    Button(working ? "자료 준비 중":"이번 주기 보고서 기록/확인") {capture()}
                        .buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(working).accessibilityIdentifier("captureOverseasReport")
                    if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasReportError")}
                }
                if let report {
                    NavigationLink {ObservationReviewView(player:player,calendar:calendar)} label: {Text("이전 보고서 비교 · 다음 행동")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("reportObservationReview")
                    CareerProjectReportEvidence(playerID:player.id,period:report.period)
                    OverseasMarketPanel(report:report)
                    GamePanel(title:"동일 환경 · 성적 비교",onBoard:true,contentSpacing:12) {
                        ForEach(report.comparisons) {row in
                            VStack(alignment:.leading,spacing:7) {
                                Text(row.id.hasPrefix("college/") ? "대학 공식 표본":"국내 육성 공식 표본").font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                                Text("\(row.totals.games)경기 · \(report.observation.role == .batter ? String(row.totals.line.plateAppearances)+"타석":row.totals.innings+"이닝") · "+(row.performance?.inputs?.mode.label ?? "환경 미확인")).font(.caption)
                                Text("P "+String(format:"%+.2f",row.correction)+" · "+row.reason).font(.caption).accessibilityIdentifier("overseasComparison")
                            }
                        }
                        if report.comparisons.isEmpty {Text("현재 수준의 성적 표본 없음 · 과거 다른 수준 성적을 합치지 않습니다.").font(.caption)}
                        Text("NPC 기준은 게임 엔진의 표준 비교 자료이며 실제 선수 평균/실사용자 분포가 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    GamePanel(title:"2년 성장 전망 · 역할 기량",onBoard:true,contentSpacing:12) {
                        ForEach(report.projections) {row in
                            Text(DomesticContractOffer.roleName(row.roleID)).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                            Text("현재 \(number(row.current)) → 기준 \(number(row.baseline))\n보수 \(number(row.conservative)) / 낙관 \(number(row.optimistic))")
                                .font(.subheadline.monospaced()).lineSpacing(6).accessibilityIdentifier("overseasProjection-"+row.roleID)
                        }
                        Text("2개 달력연도 · 연180회 훈련 예산 · 실제 나이/능력 감쇠식. 점수/피로 조건은 보수50/60·기준75/40·낙관100/0입니다. 부상/일정·노화까지 예측한 확정 성장값이 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text("전망 계산과 보고서 기록은 실제 능력·날짜·피로·훈련 보상에 반영되지 않습니다.").font(.caption)
                    }
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("해외 스카우트 보고서").navigationBarTitleDisplayMode(.inline)
            .task {load()}
    }
    private func number(_ value:Double?) -> String {value.map {String(format:"%.1f",$0)} ?? "자료 부족"}
    private func load() {do {report=try OverseasReportStore.current(player:player,calendar:calendar,in:context);failure=nil}catch{failure=error.localizedDescription}}
    private func capture() {
        working=true
        do {try OverseasReportStore.capture(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context);load()}
        catch {failure=error.localizedDescription}
        working=false
    }
}

struct OverseasMarketPanel:View {
    let report:OverseasScoutingReport
    @State private var expanded=false
    private var best:[OverseasClubEvaluation] {
        var picked=[String:OverseasClubEvaluation]()
        for row in report.market?.clubs ?? [] where row.interest != nil {
            let key=row.route.id+"/"+row.name
            if picked[key] == nil || (row.f ?? -1000) > (picked[key]?.f ?? -1000) {picked[key]=row}
        }
        return picked.values.sorted {a,b in a.f == b.f ? a.id<b.id:(a.f ?? -1000)>(b.f ?? -1000)}
    }
    var body:some View {
        GamePanel(title:"해외 모집 · 관심 구단",onBoard:true,contentSpacing:12) {
            if report.market == nil {Text("이전 보고서에는 해외 모집 자료가 없습니다. 다음 주기부터 기록합니다.").font(.caption)}
            else if best.isEmpty {
                Text("현재 해외 관심 구단 없음").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasInterestEmpty")
                Text("관찰 표본·기량·모집 조건을 보완하세요. 관심이나 제의를 채우려고 구단을 재추첨하지 않습니다.").font(.caption)
            } else {
                ForEach(Array((expanded ? best:Array(best.prefix(3))))) {row in
                    VStack(alignment:.leading,spacing:8) {
                        Text(row.name+" · "+row.route.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        Text(DomesticContractOffer.roleName(row.roleID)+" · "+(row.interest?.label ?? "관찰 대기")+" / F "+String(format:"%+.1f",row.f ?? 0)).font(.subheadline).accessibilityIdentifier("overseasClubInterest")
                        Text("H \(number(row.h)) / C \(number(row.criterion)) / P \(number(row.p)) · 자리\(row.seats) / 예산\(row.budget)").font(.caption.monospaced())
                        Text(row.blockers.isEmpty ? "기량상 후보 · 실제 계약 자격/기간·예산·경쟁 심사는 별도":row.blockers.prefix(2).joined(separator:" / ")).font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }.padding(.vertical,6)
                }
                Button(expanded ? "관심 구단 접기":"관심 구단 전체 \(best.count)건") {expanded.toggle()}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("overseasInterestDetails")
            }
            Text("가상 구단의 고정 모집 자료입니다. 관심은 정식 계약 제의나 출전 보장이 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }
    }
    private func number(_ value:Double?) -> String {value.map {String(format:"%.1f",$0)} ?? "—"}
}

struct OverseasContractsView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    @State private var refreshed=0
    @State private var command:(offerID:String,accept:Bool,date:String,revision:Int)?
    var body:some View {
        let _=calendar.revision;let _=refreshed
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                GamePanel(title:"해외 계약 · 실제 제의",onBoard:true,contentSpacing:12) {
                    Text("가상 선수의 게임 내 국제계약 지원·심사입니다. 실제 리그 등록/법적 자격 인증이 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasContractError")}
                    switch Result(catching:{try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)}) {
                    case .failure(let error):Text(error.localizedDescription).font(.caption)
                    case .success(let owner):
                        let value=owner.overseasCareer ?? OverseasCareerJournal()
                        if let registration=value.registrationDate {Text("지원자 등록 · "+registration).font(.caption).accessibilityIdentifier("overseasRegistered")}
                        else {
                            Button("게임 국제계약 지원자 등록") {run {try OverseasContractStore.register(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}
                                .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("registerOverseasApplicant")
                        }
                        if let window=try? ContractEvaluationWindow.containing(GameDate(player.gameDate)) {
                            Text(window.label+" · 같은 창 심사1회").font(.subheadline).foregroundStyle(GameTheme.gold)
                            if value.evaluations.contains(where:{$0.window == window}) == false {
                                Text("먼저 이번28일 보고서를 기록하세요. 등록/표본이 없으면 부족 사유도 이번 창의 결과로 고정합니다.").font(.caption)
                                NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("평가 자료 · 보고서 기록")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openOfferScoutingReport")
                                Button("이번 창 실제 선발 심사") {run {try OverseasContractStore.evaluate(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}
                                    .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("evaluateOverseasOffers")
                            }
                        } else {Text("다음4·7·11월1~14일에 실제 심사를 신청할 수 있습니다.").font(.caption)}
                        ForEach(value.evaluations.reversed()) {evaluation in
                            Text(evaluation.date+" 고정 · "+evaluation.window.label).font(.headline).foregroundStyle(GameTheme.gold)
                            if let mobility=evaluation.mobility {Text(mobility.label+" · "+mobility.source.name+" / "+mobility.source.label).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasMobilityBasis")}
                            if evaluation.offers.isEmpty {
                                Text("제의 없음 · "+evaluation.reasons.joined(separator:" / ")).font(.caption).accessibilityIdentifier("overseasOffersEmpty")
                            }
                            ForEach(evaluation.offers) {offer in
                                GamePanel(title:offer.name,onBoard:true,contentSpacing:12) {
                                    Text(offer.route.label+" · "+DomesticContractOffer.roleName(offer.roleID)).font(.headline).foregroundStyle(GameTheme.gold)
                                    Text("연봉지수\(offer.economicIndex) · \(offer.years)년 / 출전·승격 보장 없음").font(.subheadline)
                                    Text("발효 "+offer.effective+" ~ "+offer.economicEnd+"\n수락 마감 "+offer.expires).font(.caption.monospaced()).lineSpacing(5)
                                    Text(String(format:"H %.1f / C %.1f / P %+.1f / 전망 여유 %+.1f",offer.h,offer.c,offer.p,offer.margin)).font(.caption.monospaced())
                                    if let decision=value.decisions.first(where:{$0.offerID == offer.id}) {
                                        Text(decision.kind == .accepted ? (offer.effective > player.gameDate ? "수락 완료 · 해외 소속 전환 예약":"수락 완료 · 해외 소속 발효"):decision.kind == .rejected ? "거절 완료":"다른 제의 수락으로 종료").font(.subheadline.bold()).foregroundStyle(GameTheme.growth).accessibilityIdentifier("overseasOfferDecision")
                                    } else if offer.expires >= player.gameDate {
                                        Button("수락 · 해외 전환 예약") {command=(offer.id,true,player.gameDate,calendar.revision)}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("acceptOverseasOffer")
                                        Button("제의 거절") {command=(offer.id,false,player.gameDate,calendar.revision)}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("rejectOverseasOffer")
                                    } else {Text("만료 · 같은 창 재발행 없음").font(.caption)}
                                }
                            }
                        }
                        if let transition=value.transitions.last {
                            Text(transition.destination.since+" · "+transition.destination.name+" / "+transition.destination.label).font(.subheadline).accessibilityIdentifier("overseasAffiliationTransition")
                            Text("그 전까지 현재 소속을 유지하고 발효일부터 해외30경기 일정/기록이 연결됩니다. 기존 학적·소속/경기 기록은 보존합니다.").font(.caption)
                        }
                    }
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("해외 제의 · 상세/비교").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("계약 결정을 확정할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
                if let selected=command {Button(selected.accept ? "수락 확정":"거절 확정",role:selected.accept ? nil:.destructive) {
                    run {try OverseasContractStore.decide(player:player,calendar:calendar,offerID:selected.offerID,accept:selected.accept,date:selected.date,revision:selected.revision,in:context)};command=nil
                }.accessibilityIdentifier("confirmOverseasDecision")}
                Button("취소",role:.cancel) {command=nil}
            } message: {Text("수락은 다음 해4월1일 소속 전환을 예약하고 다른 열린 제의를 닫습니다. 날짜·피로·능력은 유지하며,경제 기간 종료가 자동 FA는 아닙니다.")}
    }
    private func run(_ action:() throws -> Void) {do {try action();failure=nil;refreshed += 1}catch{failure=error.localizedDescription}}
}

struct ProCareerProgressPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    @State private var refreshed=0
    var body:some View {
        let _=calendar.revision;let _=refreshed
        GamePanel(title:"1군 경력 · 해외 이적 승인",onBoard:true,contentSpacing:12) {
            if let owner=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),let member=try? owner.current(on:GameDate(player.gameDate)) {
                let state=owner.overseasCareer ?? OverseasCareerJournal()
                Text(member.name+" · "+member.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                if member.level == "domestic-development" {
                    Text("11월 · 역할H65/동일 환경 육성40타석·15이닝 / 다음4월1일 승격 심사").font(.caption)
                    if let promotion=state.promotions?.last(where:{$0.sourceOfferID == member.offerID}) {
                        Text("1군 승격 확정 · "+promotion.effective).font(.subheadline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("domesticPromotionPending")
                    } else {
                        Button("국내1군 승격 심사") {run {try OverseasContractStore.promoteDomestic(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("requestDomesticPromotion")
                    }
                }
                if member.level == "mlb-development" {
                    Text("11월 · 조직 내 메이저 역할 기량/같은 환경100타석·25이닝을 심사하며 새 국제계약을 만들지 않습니다.").font(.caption)
                    if let promotion=state.promotions?.last(where:{$0.sourceOfferID == member.offerID}) {
                        Text("메이저 배치 예정 · "+promotion.effective).font(.subheadline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("americanPromotionPending")
                    } else {
                        Button("미국 조직 메이저 승격 심사") {run {try OverseasContractStore.promoteAmerican(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("requestAmericanPromotion")
                    }
                    Text("승격 발효부터1년 표준 연봉지수100 · 같은 조직/보유권리/원래 입단 이력 유지").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
                Text("현재 주기의 해외 보고서를 먼저 기록하세요. 승격·이적 승인은 실제 출전/계약 발효와 구분합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                Button("완료 연도의 경력 근거 확인") {run {try OverseasContractStore.collectService(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("collectProfessionalService")
                Text("게임 인정1군 경력 · \(state.service?.count ?? 0)년 \(state.service == nil ? "(미확인)":"(공식 개인 경기 근거 확인)")").font(.caption).accessibilityIdentifier("professionalServiceYears")
                Text("한 해1월1일~12월31일 같은1군등록과 실제100타석/25이닝이 모두 있는 연도만 기록합니다. 단축시즌 번호·육성/대학·나이만으로 추가하지 않으며 실제MLB의 경력 인증이 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                if ["domestic-first-team","npb-first-team"].contains(member.level) {
                    Button("11월 구단 해외 이적 승인 요청") {run {try OverseasContractStore.requestConsent(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("requestInternationalConsent")
                    if let consent=state.consents?.last {
                        Text(consent.approved ? "게임 구단 이적 승인 · "+consent.expires+"까지":"이적 승인 보류 · "+consent.reasons.joined(separator:" / ")).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("internationalConsentStatus")
                    }
                    Text("게임 정책:1군100타석/25이닝·역할H75를 검토합니다. 승인만으로 소속/권리가 해제되지 않으며 실제포스팅/FA의 법적 절차를 재현하지 않습니다.").font(.caption)
                }
            } else {Text("소속 등록 후 경력/승격 경로를 확인할 수 있습니다.").font(.caption)}
            if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("proCareerError")}
        }
    }
    private func run(_ action:() throws -> Void) {do {try action();failure=nil;refreshed += 1}catch{failure=error.localizedDescription}}
}


struct OverseasRenewalPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    var body:some View {
        if let owner=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),
           let member=try? owner.current(on:GameDate(player.gameDate)),OverseasRenewalReview.route(member) != nil {
            let pending=(owner.overseasCareer?.renewalReviews ?? []).last {review in
                guard review.source.offerID == member.offerID,let offer=review.offer,offer.effective > player.gameDate else {return false}
                return (owner.overseasCareer?.renewalDecisions ?? []).contains {$0.offerID == offer.id && $0.kind == .accepted}
            }?.offer
            GamePanel(title:"해외 잔류 · 재계약",onBoard:true,contentSpacing:12) {
                Text(member.name+" · "+member.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                Text("등록 소속 · 입단 "+member.since+" / 구단 보유권리 유지").font(.caption)
                Text("경제 계약 · "+(member.economicStart ?? member.since)+" ~ "+member.economicEnd).font(.caption.monospaced())
                Text(member.economicEnd < player.gameDate ? "경제 기간 종료 · 소속/권리는 유지됩니다":"현재 연봉지수 \(member.economicIndex)").font(.subheadline).accessibilityIdentifier("overseasEconomicState")
                if let offer=pending {
                    Text("갱신 예정 · "+offer.effective+" ~ "+offer.economicEnd+" / 지수 \(offer.economicIndex)").font(.caption).foregroundStyle(GameTheme.growth).accessibilityIdentifier("overseasPendingRenewal")
                }
                Text("다음 심사 · "+((try? OverseasRenewalReview.nextReview(member,on:GameDate(player.gameDate),economicEnd:pending?.economicEnd)) ?? "확인 필요")+" ~ 14일 / 계약 마지막 해").font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("overseasNextRenewal")
                NavigationLink {OverseasRenewalView(player:player,calendar:calendar)} label: {Text("재계약 보고서 · 조건 확인")}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("openOverseasRenewal")
            }
        }
    }
}
struct OverseasRenewalView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    @State private var refreshed=0
    @State private var command:(id:String,accept:Bool,date:String,revision:Int)?
    var body:some View {
        let _=calendar.revision;let _=refreshed
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                GamePanel(title:"구단 사무실 · 해외 재계약",onBoard:true,contentSpacing:12) {
                    Text("같은 구단 잔류 심사").font(.title3.bold()).foregroundStyle(GameTheme.gold)
                    Text("현재 역할·동일 환경 성적·구단 자리/경쟁·총액 예산을 고정합니다. 거절·만료로 자동 방출되거나 FA가 되지 않습니다. 미국 육성팀은 같은 창의 메이저 승격과 재계약을 중복 예약할 수 없습니다.").font(.subheadline).lineSpacing(5)
                    NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("28일 평가 자료 · 보고서 기록")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("renewalOpenScoutingReport")
                }
                if let failure {Text(failure).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasRenewalError")}
                switch Result(catching:{try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)}) {
                case .failure(let error):Text(error.localizedDescription)
                case .success(let owner):
                    let state=owner.overseasCareer ?? OverseasCareerJournal()
                    if let member=try? owner.current(on:GameDate(player.gameDate)),OverseasRenewalReview.route(member) != nil {
                        if let window=try? ContractEvaluationWindow.containing(GameDate(player.gameDate)),window.month == 11,
                           (try? OverseasRenewalReview.eligible(member,on:GameDate(player.gameDate))) == true,
                           !(state.renewalReviews ?? []).contains(where:{$0.window == window}) {
                            Button("11월 재계약 심사 · 자료 고정") {run {try OverseasContractStore.evaluateRenewal(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("evaluateOverseasRenewal")
                        } else {Text("계약 마지막 해 11월에 심사합니다. 같은 창은 재평가하지 않습니다.").font(.caption)}
                    }
                    ForEach((state.renewalReviews ?? []).reversed()) {review in
                        GamePanel(title:review.source.name+" · "+review.date,onBoard:true,contentSpacing:12) {
                            Text(DomesticContractOffer.roleName(review.roleID)+" · 표본 \(review.sampleCount)"+(player.role == .batter ? "타석":"아웃")).font(.headline).foregroundStyle(GameTheme.gold)
                            Text("H "+(review.h.map {String(format:"%.1f",$0)} ?? "—")+" / C "+(review.criterion.map {String(format:"%.1f",$0)} ?? "—")+String(format:" / P %+.1f",review.p)+" · 예산 "+(review.budget.map(String.init) ?? "미확인")).font(.caption.monospaced())
                            if let offer=review.offer {
                                Text("잔류 제의 · \(offer.years)년 / 연봉지수 \(offer.economicIndex)").font(.headline)
                                Text(offer.effective+" ~ "+offer.economicEnd+"\n수락 마감 "+offer.expires).font(.caption.monospaced()).lineSpacing(5)
                                if let decision=(state.renewalDecisions ?? []).first(where:{$0.offerID == offer.id}) {
                                    Text(decision.kind == .accepted ? "수락 완료 · "+(offer.effective > player.gameDate ? "갱신 발효 대기":"갱신 발효"):"거절 완료 · 소속/보유권리 유지").font(.subheadline.bold()).foregroundStyle(GameTheme.growth).accessibilityIdentifier("overseasRenewalDecision")
                                } else if state.renewalClosedByTransfer(offer,on:player.gameDate) {
                                    Text("다른 제의 수락 · 종료").font(.subheadline).accessibilityIdentifier("overseasRenewalClosed")
                                } else if offer.expires >= player.gameDate {
                                    Button("재계약 수락") {command=(offer.id,true,player.gameDate,calendar.revision)}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("acceptOverseasRenewal")
                                    Button("재계약 거절") {command=(offer.id,false,player.gameDate,calendar.revision)}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("rejectOverseasRenewal")
                                } else {Text("제의 만료 · 소속/보유권리 유지").font(.caption)}
                            } else {Text("제의 없음 · "+review.reasons.joined(separator:" / ")).font(.subheadline).lineSpacing(5).accessibilityIdentifier("overseasRenewalEmpty")}
                        }
                    }
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("해외 재계약").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
            .toolbarColorScheme(.dark,for:.navigationBar).tint(GameTheme.gold)
            .confirmationDialog("재계약 결정을 확정할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
                if let item=command {
                    Button(item.accept ? "수락 확정":"거절 확정",role:item.accept ? nil:.destructive) {run {try OverseasContractStore.decideRenewal(player:player,calendar:calendar,offerID:item.id,accept:item.accept,date:item.date,revision:item.revision,in:context)};command=nil}.accessibilityIdentifier("confirmOverseasRenewal")
                }
                Button("취소",role:.cancel) {command=nil}
            } message: {Text("수락하면 다음4월1일부터 경제 조건만 갱신합니다. 입단 이력·소속·보유권리·기록은 유지하고 다른 열린 해외 제의를 닫습니다.")}
    }
    private func run(_ action:() throws -> Void) {do {try action();failure=nil;refreshed += 1}catch{failure=error.localizedDescription}}
}

struct OverseasReleasePanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var command:(id:String,date:String,revision:Int)?
    @State private var failure:String?
    var body:some View {
        let _=calendar.revision
        Group {
            switch Result(catching:{
                let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
                let member=try owner.current(on:GameDate(player.gameDate))
                let review=try owner.overseasCareer?.releaseReview(owner:owner,on:GameDate(player.gameDate))
                return (owner,member,review)
            }) {
            case .failure(let error):Text(error.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold)
            case .success(let state):
                if let member=state.1,OverseasRenewalReview.route(member) != nil {
                    GamePanel(title:"해외 구단 · 방출 통지",onBoard:true,contentSpacing:12) {
                        Text(member.name+" · 보유권리 유지").font(.headline).foregroundStyle(GameTheme.gold)
                        Text("계약 만료·재계약 거절만으로는 방출되지 않습니다.").font(.subheadline)
                        Text("11월 재계약 미체결 + 경제 기간 종료 + 갱신/이적/승격 예약 없음. 11월15일~다음4월1일 별도 통지를 확정합니다.").font(.caption).lineSpacing(5)
                        if state.2 != nil {
                            Button("구단 방출 통지 확인 · 권리 해제") {command=(member.offerID,player.gameDate,calendar.revision)}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("confirmOverseasRelease")
                        } else {Text("방출 확정 대기 · 재계약 심사/만료 날짜와 예약 상태를 확인하세요.").font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("overseasReleasePending")}
                    }
                } else if state.1 == nil,let released=state.0.overseasCareer?.releases?.last,state.0.activeRetryRelease?.membershipOfferID == released.source.offerID {
                    GamePanel(title:"해외 방출 · 무소속 재도전",onBoard:true,contentSpacing:12) {
                        Text(released.source.name+" · "+released.date+" 권리 해제").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasReleasedUnsigned")
                        Text("원 입단·경제 계약·경기 이력 보존 / 정식 FA 자격 취득과 구분").font(.caption)
                        Text("국내 육성팀 재입단은 4·7월 심사입니다. 국내 표본이 부족하면 인증 평가전을 먼저 진행하세요. 해외 성적을 국내 육성 성적으로 바꾸지 않습니다.").font(.caption).lineSpacing(5)
                        Text("미국 조직 육성 재지원은 기존 해외 보고서·지원 심사 경로를 사용합니다. 해외 전력 재취업·정식 FA 시장은 후속입니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }
            }
            if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("overseasReleaseError")}
        }.confirmationDialog("해외 구단 방출을 확정할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
            Button("방출 확정 · 보유권리 해제",role:.destructive) {
                guard let item=command else {return};command=nil
                do {try OverseasContractStore.release(player:player,calendar:calendar,membershipID:item.id,date:item.date,revision:item.revision,in:context);failure=nil} catch {failure=error.localizedDescription}
            }.accessibilityIdentifier("commitOverseasRelease")
            Button("취소",role:.cancel) {command=nil}
        } message: {Text("통지 확정일부터 현재 소속과 구단 보유권리를 해제합니다. 원 계약·과거 경기 기록은 보존하며 날짜·피로·능력은 변경하지 않습니다.")}
    }
}


struct FAManagementPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    @State private var command:(date:String,revision:Int)?
    var body:some View {
        let _=calendar.revision
        if let owner=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),
           owner.membershipHistory().contains(where:{OverseasRenewalReview.route($0) != nil}) {
            let state=owner.overseasCareer ?? OverseasCareerJournal()
            GamePanel(title:"FA 사무국 · 해외1군 경력",onBoard:true,contentSpacing:12) {
                Text("단축 시즌 보정 · MLB6 / NPB 해외9").font(.headline).foregroundStyle(GameTheme.gold)
                Text("1군 개막~마지막 경기 등록 + 공식 개인100타석/25이닝. 리그별로 따로 누적하며 대학·육성·국내 경력은 제외합니다.").font(.caption).lineSpacing(5)
                if let service=state.faService {
                    Text("MLB \(Set(service.filter {$0.level == "mlb-first-team"}.map(\.year)).count) / 6시즌 · NPB \(Set(service.filter {$0.level == "npb-first-team"}.map(\.year)).count) / 9시즌").font(.subheadline.monospaced()).accessibilityIdentifier("faServiceProgress")
                    ForEach(Array(service.enumerated()),id:\.offset) {_,row in
                        Text("\(row.year) · "+(row.level == "mlb-first-team" ? "MLB":"NPB")+" · 근거 \(row.matchKeys.count)경기").font(.caption)
                    }
                } else {Text("FA 경력 미확인 · 실제 저장 경기로 확인하세요.").font(.caption)}
                Button("FA 경력 근거 확인") {run {try OverseasContractStore.collectFAService(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("collectFAService")
                if let member=try? owner.current(on:GameDate(player.gameDate)),["npb-first-team","mlb-first-team"].contains(member.level),!(state.faDeclarations ?? []).contains(where:{$0.source.offerID == member.offerID}) {
                    Text("11월1~14일 자격 충족·마지막 계약 해에 별도 선언합니다. 선언만으로 오늘 소속이 바뀌지 않고 다음 개막일부터 권리를 해제합니다.").font(.caption)
                    Button("정식 FA 선언 · 조건 확인") {command=(player.gameDate,calendar.revision)}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("declareFA")
                }
                ForEach(state.faDeclarations ?? []) {fa in
                    Text(fa.source.name+" · FA 선언 "+fa.date+" / "+fa.effective+(fa.effective > player.gameDate ? " 권리 해제 예정":" 권리 해제 발효")).font(.subheadline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("faDeclarationStatus")
                }
                if let mobility=try? state.mobility(owner:owner,on:GameDate(player.gameDate)) {
                    Text(mobility.label+" 전력 재취업 심사 · 기존 해외 제의 화면에서 신청").font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("faMobilityStatus")
                }
                Text("방출은 별도 권리 해제 사유이며 FA 경력을 채우지 않습니다. 전력 제의는 최근 동일 환경 표본·기량/역할·자리·예산 심사를 통과해야 합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("faManagementError")}
            }.confirmationDialog("정식 FA를 선언할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
                Button("FA 선언 확정") {guard let item=command else {return};command=nil;run {try OverseasContractStore.declareFA(player:player,calendar:calendar,date:item.date,revision:item.revision,in:context)}}.accessibilityIdentifier("confirmFADeclaration")
                Button("취소",role:.cancel) {command=nil}
            } message: {Text("자격과 계약 종료를 확인해 다음4월1일 권리 해제를 예약합니다. 방출 원장과 구분하며 원 계약·기록을 보존합니다.")}
        }
    }
    private func run(_ action:() throws -> Void) {do {try action();failure=nil}catch{failure=error.localizedDescription}}
}


struct ContractMarketView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var showHistory=false
    var body:some View {
        let _=calendar.revision
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                switch Result(catching:{(try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),try ContractMarketStore.domestic(player:player,calendar:calendar,in:context))}) {
                case .failure(let error):Text(error.localizedDescription).accessibilityIdentifier("marketError")
                case .success(let loaded):
                    let owner=loaded.0
                    let domestic=loaded.1
                    let state=owner.overseasCareer ?? OverseasCareerJournal()
                    let entries=state.marketEntries(on:player.gameDate)
                    GamePanel(title:"CONTRACT MARKET · 계약 시장",onBoard:true,contentSpacing:12) {
                        Text("기준일 "+player.gameDate).font(.caption.monospaced())
                        Text("검토 가능 \(entries.filter {$0.status == "검토 가능"}.count + domestic.filter {$0.status == "검토 가능"}.count)건 · 잔류 / 외부 조건 비교").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketSummary")
                        Text("연봉지수는 게임 내 비교값입니다. 계약 기간·역할·발효일을 함께 확인하세요. 대학 지원금과 연봉을 같은 금액으로 비교하지 않습니다.").font(.caption).lineSpacing(5)
                        Text("수락 시 다른 열린 제의를 닫고 발효일까지 현재 소속을 유지합니다. 마감·거절·제의 없음은 자동 방출이나 FA가 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    Button(showHistory ? "이전 제의 접기":"이전 제의 이력 보기") {showHistory.toggle()}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketHistory")
                    ForEach(entries.filter {showHistory || ["검토 가능","수락 · 발효 대기"].contains($0.status)}) {entry in
                        GamePanel(title:(entry.retention ? "잔류 · ":"외부 · ")+entry.offer.name,onBoard:true,contentSpacing:12) {
                            Text(entry.status).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketOfferStatus")
                            Text(entry.offer.route.label+" / "+DomesticContractOffer.roleName(entry.offer.roleID)).font(.subheadline)
                            Text("연봉지수 \(entry.offer.economicIndex) × \(entry.offer.years)년 · 총 \(entry.offer.economicIndex * entry.offer.years)지수").font(.subheadline.bold())
                            Text("마감 "+entry.offer.expires+"\n발효 "+entry.offer.effective+" ~ "+entry.offer.economicEnd).font(.caption.monospaced()).lineSpacing(5)
                            Text("출전·승격 보장 없음").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    DomesticMarketCards(player:player,calendar:calendar,entries:domestic,showHistory:showHistory)
                    GamePanel(title:"심사 · 결정 창구",onBoard:true,contentSpacing:12) {
                        NavigationLink {OverseasRenewalView(player:player,calendar:calendar)} label: {Text("잔류 심사 · 수락 / 거절")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketRenewal")
                        NavigationLink {OverseasContractsView(player:player,calendar:calendar)} label: {Text("외부 심사 · 수락 / 거절")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketExternal")
                        NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("28일 보고서 · 부족 조건 확인")}.buttonStyle(MatchPixelButtonStyle())
                        Text("국내 신인·대학·육성 제의는 기존 진로 창구에서 확인합니다.").font(.caption)
                        ContractEvaluationHomePanel(player:player,calendar:calendar)
                    }
                    GamePanel(title:"마감 · 제의 없음 · 재도전",onBoard:true,contentSpacing:12) {
                        if !entries.contains(where:{$0.status == "검토 가능"}) && !domestic.contains(where:{$0.status == "검토 가능"}) {
                            Text("현재 검토할 제의 없음").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketEmpty")
                        }
                        Text("같은 평가 창에서는 재심사하거나 만료 제의를 재발행하지 않습니다. 현재 창의 보고서와 부족 조건을 확인하고 다음 유효 창에 새 자료로 도전하세요.").font(.caption).lineSpacing(5)
                        if let date=try? GameDate(player.gameDate),let membership=try? owner.current(on:date) {
                            Text("다음 소속 경로 심사 창 · "+state.nextMarketWindow(after:date,hasMembership:true).start.description).font(.subheadline).foregroundStyle(GameTheme.gold)
                            Text(membership.name+"의 소속·권리는 별도 발효/해제 전까지 유지됩니다.").font(.caption)
                        } else if let date=try? GameDate(player.gameDate) {
                            Text("다음 무소속 심사 창 · "+state.nextMarketWindow(after:date,hasMembership:false).start.description).font(.subheadline).foregroundStyle(GameTheme.gold)
                        }
                        Text("평가 창: 4·7·11월 1~14일. 국내 재입단은 4·7월, 재학생 프로 지원·프로 갱신/이적은 11월에 자격을 확인합니다. 날짜는 홈에서 진행합니다.").font(.caption).lineSpacing(5)
                        OverseasReleasePanel(player:player,calendar:calendar)
                        DomesticReleasePanel(player:player,calendar:calendar)
                        FAManagementPanel(player:player,calendar:calendar)
                    }
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("계약 시장").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
    }
}


struct DomesticMarketCards:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let entries:[DomesticMarketEntry]
    let showHistory:Bool
    @Environment(\.modelContext) private var context
    var body:some View {
        ForEach(entries.filter {showHistory || $0.visible}) {entry in
            GamePanel(title:entry.name+" · "+entry.label,onBoard:true,contentSpacing:12) {
                Text(entry.status).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("domesticMarketStatus")
                Text(DomesticContractOffer.roleName(entry.roleID)).font(.subheadline)
                Text(entry.economicLabel+" \(entry.economicIndex)").font(.headline).accessibilityIdentifier("domesticMarketEconomic")
                Text(entry.period+"\n수락 마감 "+entry.expires).font(.caption.monospaced()).lineSpacing(5)
                if let renewal=entry.renewal {
                    NavigationLink {DomesticRenewalDetail(player:player,calendar:calendar,value:renewal,evaluatedDate:entry.issued)} label: {Text("잔류 조건 · 결정")}.buttonStyle(MatchPixelButtonStyle())
                } else if let evaluation=try? ContractEvaluationStore.records(player:player,calendar:calendar,in:context).first(where:{$0.key == entry.evaluationKey}) {
                    NavigationLink {DomesticOffersView(player:player,calendar:calendar,evaluation:evaluation,page:.detail(entry.id))} label: {Text("제의 상세 · 결정")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("domesticMarketDetail")
                }
            }
        }
    }
}


struct CareerObjectivesView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var owner:CareerContractJournal?
    @State private var live:ScoutingObservation?
    @State private var eligibility:OverseasEligibilitySnapshot?
    @State private var failure:String?
    @State private var path="국내 프로 관찰"
    @State private var clubID=""
    private var latest:OverseasScoutingReport? {owner?.overseasReports?.max {$0.period < $1.period}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                GamePanel(title:"CAREER FILE · 목표 구단",onBoard:true,contentSpacing:12) {
                    if let latest {
                        Text(latest.observation.observedDate+" 고정 관찰 기준 · 현재 기량은 별도 표시").font(.caption)
                        Picker("목표 경로",selection:$path) {
                            ForEach(["국내 프로 관찰"]+OverseasRoute.allCases.map(\.label),id:\.self) {Text($0).tag($0)}
                        }.tint(GameTheme.gold).accessibilityIdentifier("targetPath")
                        Picker("구단 · 모집 역할",selection:$clubID) {
                            Text("목표 선택").tag("")
                            ForEach(CareerTargetClub.catalog(latest).filter {$0.path == path}) {club in Text(club.name+" · "+DomesticContractOffer.roleName(club.roleID)).tag(club.id)}
                        }.tint(GameTheme.gold).accessibilityIdentifier("targetClub")
                        Button("이 구단을 목표로 저장") {run {try OverseasContractStore.selectTarget(player:player,calendar:calendar,reportID:latest.id,clubID:clubID,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(clubID.isEmpty).accessibilityIdentifier("saveCareerTarget")
                        Text("목표 지정은 지원·계약 예약이 아닙니다. 현재28일 주기의 보고서에서 선택하며 지난 자료는 다음 보고서로 갱신하세요.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    } else {Text("먼저 이번28일 보고서를 기록하면 실제 관찰 기준으로 목표를 선택할 수 있습니다.").font(.subheadline)}
                    NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("28일 관찰 보고서 기록/확인")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("objectivesReport")
                    if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("objectivesError")}
                }
                if let owner,let target=owner.developmentTarget,let report=owner.overseasReports?.first(where:{$0.id == target.reportID}),let club=CareerTargetClub.catalog(report).first(where:{$0.id == target.clubID}),let live {
                    readiness(owner:owner,report:report,club:club,live:live)
                    CareerProjectPanel(player:player,calendar:calendar,owner:owner,refresh:{load()})
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("커리어 목표").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
            .task(id:calendar.revision) {load()}
            .onChange(of:path) {_,_ in clubID=""}
    }
    @ViewBuilder private func readiness(owner:CareerContractJournal,report:OverseasScoutingReport,club:CareerTargetClub,live:ScoutingObservation) -> some View {
        let member=try? owner.current(on:GameDate(player.gameDate))
        let level=member?.level ?? (live.age <= 18 ? "highschool":"unsigned")
        let progress=CareerTargetReadiness.make(club:club,live:live,level:level)
        GamePanel(title:club.name+" · "+DomesticContractOffer.roleName(club.roleID),onBoard:true,contentSpacing:12) {
            Text(club.path+" / "+club.demand).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("careerTargetSummary")
            Text("현재 역할 H "+number(progress.currentH)+" / 고정 관찰 기준 "+number(club.criterion)).font(.subheadline)
            Text("기량 차이 · "+(progress.missingH.map {String(format:"%.1f 보완",$0)} ?? "기준 자료 부족")).font(.subheadline).accessibilityIdentifier("targetAbilityGap")
            ProgressView(value:Double(min(progress.sample,progress.requiredSample)),total:Double(progress.requiredSample)).tint(GameTheme.growth)
            Text("현재 수준의 단일 환경 표본 \(progress.sample) / \(progress.requiredSample)"+(player.role == .batter ? "타석":"아웃")).font(.caption).accessibilityIdentifier("targetSample")
            Text("환경별 최대 표본을 표시하며 서로 다른 리그·조작 환경을 합산하지 않습니다. 실제 지원 경로가 허용하는 수준/표본은 정식 심사에서 다시 확인합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            Text("고정 보고서 F "+number(club.fit)+" · 기준일 "+report.observation.observedDate).font(.caption)
            ForEach(club.blockers,id:\.self) {Text("관찰일 부족 조건 · "+$0).font(.caption)}
            if let route=club.route,let gate=eligibility?.routes.first(where:{$0.route == route}) {
                Text("현재 경로 자격 · "+gate.status.label).font(.subheadline.bold())
                ForEach(gate.reasons,id:\.self) {Text($0).font(.caption)}
            } else {Text("국내 진로 자격·모집 자리·예산·경쟁은 평가 창에서 별도 심사합니다. 관찰 기준을 신인 지명 확정 기준으로 취급하지 않습니다.").font(.caption)}
            if let today=try? GameDate(player.gameDate) {
                if let current=ContractEvaluationWindow.containing(today) {Text("현재 평가 창 · "+current.label+" / 마감 "+current.end.description+" · 경로 자격 별도 확인").font(.caption)}
                let next=(owner.overseasCareer ?? OverseasCareerJournal()).nextMarketWindow(after:today,hasMembership:member != nil)
                Text("다음 경로 심사 창 · "+next.start.description+" / D-\(today.days(to:next.start))").font(.subheadline).foregroundStyle(GameTheme.gold)
            }
            Text("추천 준비 · "+club.training.label+" 훈련 / 해당 수준 공식 경기 표본 확보").font(.subheadline)
            NavigationLink {GoalSpecialActivitiesView(player:player,calendar:calendar)} label: {Text("부족 조건 보완 · 특별 훈련 / 평가전")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("targetSpecialActivities")
            NavigationLink {ContractMarketView(player:player,calendar:calendar)} label: {Text("실제 제의 · 계약 시장")}.buttonStyle(MatchPixelButtonStyle())
        }
    }
    private func number(_ value:Double?) -> String {value.map {String(format:"%.1f",$0)} ?? "자료 부족"}
    private func load() {do {owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context);live=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context);eligibility=try OverseasEligibilityStore.current(player:player,calendar:calendar,in:context);failure=nil}catch{failure=error.localizedDescription}}
    private func run(_ action:() throws -> Void) {do {try action();load()}catch{failure=error.localizedDescription}}
}


struct CareerProjectPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let owner:CareerContractJournal
    let refresh:() -> Void
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    var body:some View {
        GamePanel(title:"PLAYER PROJECT · 28일 관찰 과제",onBoard:true,contentSpacing:12) {
            Text("목표 구단의 모집 역할·부족 조건을 바탕으로 선수가 선택한 과제입니다. 구단이 보낸 요청이 아닙니다. 시작은 하루 행동을 소비하지 않고, 실제 훈련/경기는 기존 행동·피로 규칙을 따릅니다.").font(.caption).lineSpacing(5)
            if let project=owner.developmentProjects?.last {
                projectDetails(project)
            }
            if owner.activeProject(on:player.gameDate) == nil {
                Button("목표 역할 · 28일 프로젝트 시작") {
                    do {try OverseasContractStore.startProject(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context);failure=nil;refresh()}catch{failure=error.localizedDescription}
                }.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("startCareerProject")
                Text("현재 주기의 목표 보고서가 필요하며 주기당1개만 시작합니다. 시작 당일 이미 완료한 기록은 제외합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("projectError")}
            Text("완료해도 계약 확정·적합도 가산·추가 성장 보상은 없습니다. 실제 능력/공식 성적은 기존 선발 심사에 반영됩니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }.fixedSize(horizontal:false,vertical:true).id(owner.developmentProjects?.last?.id ?? "no-project")
    }
    @ViewBuilder private func projectDetails(_ project:CareerDevelopmentProject) -> some View {
        Text(project.training.label+" 집중 / "+project.start+" ~ "+project.end).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("projectSummary")
        if let assignment=project.assignment {
            VStack(alignment:.leading,spacing:10) {
                Text(assignment.focus).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("projectAssignmentFocus")
                Text(assignment.reason).font(.subheadline).accessibilityIdentifier("projectAssignmentReason")
                Text("시작 시 모집 · "+assignment.demand+" / 원 보고서 기준 고정").font(.caption)
                ForEach(Array(assignment.blockers.enumerated()),id:\.offset) {_,reason in Text("별도 심사 조건 · "+reason).font(.caption)}
            }.fixedSize(horizontal:false,vertical:true)
        } else {Text("기존 저장 과제 · 훈련3회/우수2회 조건 유지").font(.caption)}
        switch Result(catching:{try CareerProjectStore.progress(project,player:player,on:player.gameDate,in:context)}) {
        case .failure(let error):Text(error.localizedDescription).font(.caption)
        case .success(let progress):
            let review=owner.developmentReviews?.last(where:{$0.projectID == project.id})
            Text(review?.progress.complete == true ? "보고서 확인 · 프로젝트 완료":player.gameDate > project.end ? "기간 종료 · 달성 기록 보존":progress.complete ? "목표 달성 · 다음 보고서 관찰 대기":"진행 중").font(.subheadline.bold()).accessibilityIdentifier("projectStatus")
            taskRow("관련 능력 훈련",value:progress.trainingKeys.count,total:progress.task?.trainingGoal ?? 3,unit:"회")
            taskRow("평균75점 이상 훈련",value:progress.qualitySessions,total:progress.task?.qualityGoal ?? 2,unit:"회")
            if let task=progress.task,task.goal>0 {taskRow(task.metric.label,value:task.value,total:task.goal,unit:task.metric.unit)}
            if project.requiredSample > 0 {
                taskRow("시작 소속 수준 공식 출전",value:progress.sample,total:project.requiredSample,unit:project.role == .batter ? "타석":"아웃")
            } else {Text("비출전 일정 · 이번 프로젝트는 훈련 집중 관찰입니다. 공식 출전 과제는 부여하지 않습니다.").font(.caption).foregroundStyle(GameTheme.gold)}
            Text("실제 해당 훈련 성장 합계 +"+String(format:"%.1f",progress.growth)+" · 기존 성장 기록").font(.caption)
            NavigationLink {CareerTrainingView(player:player,calendar:calendar)} label: {Text(project.training.label+" 훈련 선택 / 이어하기")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("projectTrainingAction")
            if project.assignment?.metric == .position {
                NavigationLink {PositionTrainingView(player:player,calendar:calendar)} label: {Text("시작 포지션 "+(project.assignment?.position ?? "")+" 숙련 훈련")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("projectPositionAction")
            }
            Text("훈련 종류: "+project.training.label+" / 경기 수준: "+project.level+". 연습 모드·인증 평가전·미완료 경기·다른 수준 경기는 제외합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            ForEach((owner.developmentReviews ?? []).filter {$0.projectID == project.id}) {review in
                Text("관찰 확정 "+review.date+" · 훈련 \(review.progress.trainingKeys.count)/\(review.progress.task?.trainingGoal ?? 3) · 우수 \(review.progress.qualitySessions)/\(review.progress.task?.qualityGoal ?? 2) · 표본 \(review.progress.sample)/\(project.requiredSample)").font(.caption).accessibilityIdentifier("projectFrozenReview")
            }
        }
    }
    private func taskRow(_ label:String,value:Int,total:Int,unit:String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(label+" \(value) / \(total)"+unit).font(.subheadline).accessibilityIdentifier("projectTask")
            ProgressView(value:Double(min(value,total)),total:Double(total)).tint(GameTheme.growth)
        }
    }
}


struct CareerObjectivesHomeLabel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Text("커리어 목표 · 준비 현황").font(.headline)
            switch Result(catching:{try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)}) {
            case .failure:Text("목표 자료 확인 필요").font(.caption)
            case .success(let owner):
                if let target=owner.developmentTarget,let report=owner.overseasReports?.first(where:{$0.id == target.reportID}),let club=CareerTargetClub.catalog(report).first(where:{$0.id == target.clubID}) {
                    Text(club.name+" · "+DomesticContractOffer.roleName(club.roleID)).font(.caption).accessibilityIdentifier("homeCareerTarget")
                    Text(owner.activeProject(on:player.gameDate) == nil ? "관찰 과제 · 결과/새 프로젝트 확인":"28일 프로젝트 진행 중").font(.caption)
                } else {Text("목표 구단·역할을 선택하세요").font(.caption)}
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct CareerProjectReportEvidence:View {
    let playerID:UUID
    let period:Int
    @Environment(\.modelContext) private var context
    @State private var reviews:[CareerProjectReview]=[]
    @State private var assignments:[String:CareerProjectAssignment]=[:]
    @State private var plans:[MatchPlanObservation]=[]
    @State private var special:[GoalSpecialReport]=[]
    @State private var failure:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            if !reviews.isEmpty {
                GamePanel(title:"선수 프로젝트 · 확정 관찰 근거",onBoard:true,contentSpacing:12) {
                    ForEach(reviews) {review in
                        Text(review.date+" 고정 · "+(review.progress.complete ? "과제 완료":"진척 관찰")).font(.headline).foregroundStyle(GameTheme.gold)
                        if let assignment=assignments[review.projectID] {Text(assignment.focus+" · "+assignment.reason).font(.subheadline).accessibilityIdentifier("reportAssignmentFocus")}
                        Text("관련 훈련 \(review.progress.trainingKeys.count)/\(review.progress.task?.trainingGoal ?? 3) · 우수 \(review.progress.qualitySessions)/\(review.progress.task?.qualityGoal ?? 2) · 공식 표본 \(review.progress.sample)/\(review.progress.requiredSample)").font(.caption).accessibilityIdentifier("reportProjectEvidence")
                        if let task=review.progress.task,task.goal>0 {Text(task.metric.label+" \(task.value)/\(task.goal)"+task.metric.unit).font(.caption).accessibilityIdentifier("reportAssignmentProgress")}
                    }
                    Text("같은 주기 최초 보고서의 관찰 결과입니다. 계약 보너스 없이 실제 훈련/공식 출전 근거만 보존합니다.").font(.caption)
                }
            }
            ForEach(plans) {observation in
                GamePanel(title:"경기 전 계획 · 확정 수행 기록",onBoard:true,contentSpacing:12) {
                    ForEach(observation.results) {item in
                        Text(item.date+" · "+item.preparation.choice.label+" / "+item.outcome.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("reportGamePlanEvidence")
                        Text("조작 환경 · "+(item.mode?.label ?? "미확인")).font(.caption)
                        ForEach(Array(item.outcome.checks.enumerated()),id:\.offset) {_,check in Text(check.detail).font(.caption)}
                    }
                    Text("완료한 개인 경기의 수행 기록입니다. 기존 H/P/F나 계약 심사에 별도 가산하지 않으며,같은 경기 근거는 한 번만 보고합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            }
            ForEach(special) {report in
                GamePanel(title:"목표 구단 프로그램 · 확정 근거",onBoard:true,contentSpacing:12) {
                    ForEach(report.evidence) {evidence in
                        Text(evidence.date+" · "+evidence.summary).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("reportGoalSpecialEvidence")
                        Text(String(format:"점수 %.1f · 실제 훈련 성장 +%.1f",evidence.score,evidence.growth)).font(.caption)
                    }
                    Text("특별 훈련은 기존 훈련 기록,자동 평가전은 별도 진단 자료입니다. 공식 표본/인증 자격·H/P/F 보너스를 추가하지 않습니다.").font(.caption)
                }
            }
            if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold)}
        }.task(id:"\(playerID)-\(period)") {
            do {
                let id=playerID
                guard let player=try context.fetch(FetchDescriptor<CareerPlayer>(predicate:#Predicate {$0.id == id})).first,
                      let calendar=try context.fetch(FetchDescriptor<CareerCalendarState>(predicate:#Predicate {$0.playerID == id})).first else {throw ContractRegistrationError.invalid}
                let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
                reviews=owner.developmentReviews?.filter {$0.period == period} ?? []
                assignments=Dictionary(uniqueKeysWithValues:(owner.developmentProjects ?? []).compactMap {project in project.assignment.map {(project.id,$0)}})
                plans=owner.gamePlanReports?.filter {$0.period == period} ?? []
                special=owner.specialReports?.filter {$0.period == period} ?? [];failure=nil
            } catch {failure=error.localizedDescription}
        }
    }
}


struct GoalSpecialActivitiesView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var owner:CareerContractJournal?
    @State private var live:ScoutingObservation?
    @State private var failure:String?
    @State private var showTraining=false
    private var todayTraining:GoalSpecialTraining? {owner?.specialTrainings?.first {$0.date == player.gameDate}}
    private var assessment:GoalSpecialAssessment? {owner?.specialAssessments?.last}
    private var pending:Bool {assessment?.completed == false}
    private var period:Int? {try? ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(player.gameDate)).index}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                if let owner,let target=owner.developmentTarget,let club=owner.specialClub(target),let live {
                    GamePanel(title:"DEVELOPMENT LAB · 목표 구단 보완",onBoard:true,contentSpacing:12) {
                        HStack(spacing:12) {
                            PixelPlayer(appearance:player.appearance).frame(width:40,height:54)
                            VStack(alignment:.leading,spacing:6) {
                                Text(club.name+" · "+DomesticContractOffer.roleName(club.roleID)).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("specialTarget")
                                Text("기준일 "+target.date+" / "+player.gameDate).font(.caption.monospaced())
                            }
                        }
                        Text("현재 피로 \(player.fatigue) · "+(calendar.hasAction(on:player.gameDate) ? "오늘 행동 완료":"오늘 행동 가능")).font(.subheadline).accessibilityIdentifier("specialDailyState")
                        Text("모집·예산·보유권리 조건은 훈련/평가전으로 해제하지 않습니다. 정식 평가 자료는 같은 주기 내에 다시 계산하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    trainingPanel(club:club,live:live)
                    assessmentPanel(owner:owner,club:club)
                    NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("관찰 보고서 · 다음 주기 결과 확인")}.buttonStyle(MatchPixelButtonStyle())
                } else if failure == nil {
                    GamePanel(title:"먼저 커리어 목표를 선택하세요",onBoard:true) {
                        Text("관찰 보고서에서 목표 구단과 모집 역할을 정하면 관련 능력 훈련과 해당 수준 평가전을 준비합니다.").font(.subheadline)
                        NavigationLink {CareerObjectivesView(player:player,calendar:calendar)} label: {Text("목표 구단 선택")}.buttonStyle(MatchPixelButtonStyle())
                    }
                }
                if let failure {Text(failure).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("goalSpecialError")}
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("특별 훈련 · 평가전").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
            .task(id:calendar.revision) {load()}
            .navigationDestination(isPresented:$showTraining) {CareerTrainingView(player:player,calendar:calendar)}
    }
    @ViewBuilder private func trainingPanel(club:CareerTargetClub,live:ScoutingObservation) -> some View {
        GamePanel(title:"SPECIAL DRILL · 부족 능력 보완",onBoard:true,contentSpacing:12) {
            if let recommendation=GoalSpecialRecommendation.make(club:club,abilities:live.abilities) {
                Text(recommendation.reason).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("specialTrainingRecommendation")
                Text(String(format:"현재 %.1f · 기존 5회 미니게임 / 완료 피로 +6",recommendation.current)).font(.caption)
                Text("역할 관련 능력 중 낮은 값을 우선합니다. 원본 능력 각각에 구단의 역할 H 기준을 직접 적용하는 합격선은 아닙니다.").font(.caption)
                Button(todayTraining == nil ? recommendation.kind.label+" 특별 훈련 시작":"특별 훈련 이어하기 / 결과") {
                    run {_ = try GoalSpecialStore.startTraining(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context);showTraining=true}
                }.buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(pending || (calendar.hasAction(on:player.gameDate) && todayTraining == nil)).accessibilityIdentifier("startGoalSpecialTraining")
            } else if todayTraining != nil {
                Button("특별 훈련 결과 확인") {showTraining=true}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("startGoalSpecialTraining")
            } else {Text("관련 능력이 모두 상한입니다. 현재 기량은 평가전에서 확인할 수 있습니다.").font(.subheadline)}
            Text("추가 성장 배율 없음 · 기존 하루 행동/성장 감쇠·피로·5회 이어하기/보상1회 유지").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }
    }
    @ViewBuilder private func assessmentPanel(owner:CareerContractJournal,club:CareerTargetClub) -> some View {
        GamePanel(title:"SCOUT TEST · 목표 수준 자동 평가전",onBoard:true,contentSpacing:12) {
            Text("실제 능력·보유 구종·시작 피로를 고정한 2경기 진단입니다. 경기마다 자동 진행하고 저장합니다.").font(.subheadline)
            Text("완료 시 오늘 행동 소비 · 피로 +8 · 능력/XP·공식 성적·무소속 인증 자격 지급 없음").font(.caption).foregroundStyle(GameTheme.gold)
            if let assessment {
                Text((owner.specialClub(assessment.target)?.name ?? club.name)+" · "+assessment.date).font(.subheadline.bold())
                Text("\(assessment.games.count) / 2경기 · 시작 피로 \(assessment.fatigue)").font(.headline).accessibilityIdentifier("goalAssessmentProgress")
                if !assessment.games.isEmpty {
                    VStack(alignment:.leading,spacing:8) {
                        let totals=assessment.totals,line=totals.line
                        Text(assessment.role == .batter
                             ? "평가 \(totals.games)경기 · \(line.plateAppearances)타석 · 타율 \(totals.average)\n\(line.hits)안타 · \(line.homeRuns)홈런 · \(line.walks)볼넷 · \(line.strikeouts)삼진"
                             : "평가 \(totals.games)경기 · \(totals.innings)이닝 · \(line.runsAllowed)실점\n\(line.pitchingStrikeouts)탈삼진 · \(line.pitchingWalks)볼넷 · 피홈런 \(assessment.games.reduce(0){$0+($1.scoutingPerformance?.homersAllowed ?? 0)})")
                            .font(.subheadline.monospaced()).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("goalAssessmentRecord")
                    }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                    Text(String(format:"%@ 진단 %.1f점",assessment.completed ? "최종":"중간",assessment.score)).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("goalAssessmentScore")
                }
                if !assessment.completed {
                    Button("다음 평가 경기 자동 진행") {run {try GoalSpecialStore.advanceAssessment(player:player,calendar:calendar,id:assessment.id,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("advanceGoalAssessment")
                    Text("진행 중에는 날짜·휴식·다른 훈련/경기 준비를 잠급니다. 재열면 저장한 경기부터 이어집니다.").font(.caption)
                } else {Text("완료 저장 · 다음 관찰 보고서에1회 기록").font(.subheadline).foregroundStyle(GameTheme.growth)}
            }
            if assessment?.period != period {
                Button("이번 주기 평가전 준비") {run {try GoalSpecialStore.startAssessment(player:player,calendar:calendar,date:player.gameDate,revision:calendar.revision,in:context)}}.buttonStyle(MatchPixelButtonStyle()).disabled(calendar.hasAction(on:player.gameDate) || pending).accessibilityIdentifier("startGoalAssessment")
            }
            Text("타자는 출루 기여,투수는 탈삼진·볼넷·피홈런을 진단합니다. 수비 역할의 수비·송구·포지션 조건은 별도 확인하며 이 점수로 통과시키지 않습니다. 주기당1회로 같은 조건 재추첨을 막습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }.fixedSize(horizontal:false,vertical:true).id(assessment.map {"\($0.id)/\($0.games.count)"} ?? "new-assessment")
    }
    private func load() {do {owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context);live=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context);failure=nil}catch{failure=error.localizedDescription}}
    private func run(_ action:() throws -> Void) {do {try action();load()}catch{failure=error.localizedDescription}}
}

struct ObservationReviewView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var review:ObservationPeriodReview?
    @State private var failure:String?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if let review {
                    GamePanel(title:"SCOUT REVIEW · 28일 관찰 결산",onBoard:true,contentSpacing:12) {
                        Text(review.current.observedDate+" 확정 · \(review.current.period+1)차 관찰").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("reviewCurrentDate")
                        if let previous=review.previous {
                            Text(previous.observedDate+" → "+review.current.observedDate).font(.subheadline).accessibilityIdentifier("reviewPreviousDate")
                            Text("위의 실제 관찰일 사이 변화이며,정확히28일 간격이 아닐 수 있습니다.").font(.caption)
                            if review.current.period-previous.period>1 {Text("중간 보고서가 없어 최근 저장 자료와 비교합니다. 연속28일의 변화가 아닙니다.").font(.caption)}
                        } else {Text("첫 관찰 자료 · 이전 보고서가 없어 변화량을 계산하지 않습니다.").font(.subheadline).accessibilityIdentifier("reviewNoPrevious")}
                        if review.stale {Text("지난 주기 자료입니다. 이번 주기 보고서를 먼저 확인하세요.").font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("reviewStale")}
                        Text("저장된 관찰일 기준입니다. 현재 능력·제의 상태는 각 화면에서 다시 확인합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    if review.previous != nil {
                        GamePanel(title:"GROWTH · 관찰일 사이의 변화",onBoard:true,contentSpacing:12) {
                            ForEach(review.abilities+review.pitches) {row in
                                Text(row.label+String(format:"  %.1f → %.1f  (%+.1f)",row.before,row.after,row.difference)).font(.subheadline.monospaced()).accessibilityIdentifier("reviewAbility-"+row.id)
                            }
                            Text("양쪽 보고서에 있는 같은 능력·구종만 비교합니다. 훈련·경기·그 외 변화를 포함하며 특정 활동의 효과로 단정하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                        GamePanel(title:"PERFORMANCE · 동일 환경 기록",onBoard:true,contentSpacing:12) {
                            if review.samples.isEmpty {Text("비교 자료 부족 · 리그·조작 환경·평가 방식·포지션이 같고 양쪽에 표본이 있어야 비교합니다.").font(.subheadline).accessibilityIdentifier("reviewNoSampleComparison")}
                            ForEach(review.samples) {row in
                                VStack(alignment:.leading,spacing:8) {
                                    Text(row.label).font(.caption.monospaced()).foregroundStyle(GameTheme.gold)
                                    Text(String(format:"표본 %.0f → %.0f  (%+.0f)",row.before,row.after,row.difference)+(review.current.role == .batter ? "타석":"아웃")).font(.subheadline).accessibilityIdentifier("reviewSample-"+row.id)
                                    if let rate=review.performance.first(where:{$0.id == row.id}) {Text(rate.label+String(format:" %.3f → %.3f",rate.before,rate.after)).font(.subheadline)}
                                }.fixedSize(horizontal:false,vertical:true)
                            }
                            Text("각 관찰일의 최근365일 기록입니다. 차이는 이번28일 신규 경기 수가 아니며,관찰 기간에서 빠진 과거 경기도 영향을 줍니다. 다른 리그/직접·자동·혼합 성적은 합산하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    GamePanel(title:"TARGET FILE · 목표 구단 부족 조건",onBoard:true,contentSpacing:12) {
                        if let club=review.club {
                            Text(club.name+" · "+DomesticContractOffer.roleName(club.roleID)).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("reviewTarget")
                            Text("관심 · "+review.interestBefore+" → "+review.interestNow).font(.subheadline).accessibilityIdentifier("reviewInterest")
                            Text("역할 기량 "+number(review.readiness?.currentH)+" / 이번 관찰 기준 "+number(club.criterion)).font(.subheadline)
                            if let change=review.roleChange {Text(String(format:"역할 기량 변화 %.1f → %.1f (%+.1f)",change.before,change.after,change.difference)).font(.subheadline).accessibilityIdentifier("reviewRoleChange")}
                            Text("관찰 적합도 "+number(club.fit)+" · 모집 상태 "+club.demand).font(.subheadline)
                            if let old=review.previousClub {Text("이전 관찰 기준 "+number(old.criterion)+" · 모집 "+old.demand).font(.caption)}
                            Text("관심·적합도는 성장뿐 아니라 당시 모집·예산·경쟁·자격의 영향을 받습니다. 관심 없음과 미확인 자료를 구분하며 계약을 보장하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                        ForEach(Array(review.missing.enumerated()),id:\.offset) {_,text in Text(text).font(.subheadline).accessibilityIdentifier("reviewMissing")}
                        if review.missing.isEmpty {Text("표시 가능한 부족 조건 없음 · 정식 심사의 자리·예산·경쟁·권리는 별도 확인합니다.").font(.subheadline)}
                    }.fixedSize(horizontal:false,vertical:true)
                    GamePanel(title:"NEXT STEP · 다음 행동",onBoard:true,contentSpacing:12) {
                        Text("관찰일의 부족 조건에 따른 추천 순서입니다. 날짜·피로·진행 중 활동과 실제 지원 자격은 이동한 화면에서 확인합니다.").font(.caption)
                        ForEach(review.actions) {action in
                            VStack(alignment:.leading,spacing:8) {Text(action.reason).font(.caption);actionLink(action)}.fixedSize(horizontal:false,vertical:true)
                        }
                    }
                    CareerProjectReportEvidence(playerID:player.id,period:review.current.period)
                } else if failure == nil {
                    GamePanel(title:"아직 관찰 결산이 없습니다",onBoard:true) {
                        Text("보고서를 먼저 기록하면 고정된 자료를 비교할 수 있습니다.")
                        actionLink(.report)
                    }
                }
                if let failure {Text(failure).foregroundStyle(GameTheme.gold).accessibilityIdentifier("reviewError")}
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("관찰 결산 · 다음 행동").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
            .task(id:calendar.revision) {do {review=try ObservationReviewStore.load(player:player,calendar:calendar,in:context);failure=nil}catch{failure=error.localizedDescription}}
    }
    private func number(_ value:Double?) -> String {value.map {String(format:"%.1f",$0)} ?? "자료 부족"}
    private func actionLink(_ action:ObservationReviewAction) -> some View {
        NavigationLink {destination(action)} label: {Text(action.label)}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("reviewAction-"+action.rawValue)
    }
    @ViewBuilder private func destination(_ action:ObservationReviewAction) -> some View {
        switch action {
        case .report:OverseasScoutingReportView(player:player,calendar:calendar)
        case .target:CareerObjectivesView(player:player,calendar:calendar)
        case .special:GoalSpecialActivitiesView(player:player,calendar:calendar)
        case .training:CareerTrainingView(player:player,calendar:calendar)
        case .schedule:ObservationScheduleView(player:player,calendar:calendar)
        case .position:PositionTrainingView(player:player,calendar:calendar)
        case .market:ContractMarketView(player:player,calendar:calendar)
        }
    }
}
struct ObservationScheduleView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @State private var schools:[School]=[]
    @State private var fixtures:[SeasonFixture]=[]
    @State private var failure:String?
    var body:some View {
        ScrollView {
            GamePanel(title:"SCHEDULE · 다음 공식 경기",onBoard:true,contentSpacing:12) {
                if let failure {Text(failure)} else {
                    Text("오늘 "+player.gameDate+" · "+player.role.label).font(.headline)
                    ForEach(Array(fixtures.filter {$0.isAppearance(for:player.role)}.prefix(3))) {fixture in
                        Text(fixture.date.description+" · "+CareerTeamDirectory.name(fixture.homeID,schools:schools)+" / "+CareerTeamDirectory.name(fixture.awayID,schools:schools)).font(.subheadline)
                    }
                    if fixtures.contains(where:{$0.date.description == player.gameDate}) {
                        NavigationLink {CareerGameEntryView(player:player,calendar:calendar,schools:schools)} label: {Text("오늘 경기 · 이어하기 / 결과")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("reviewTodayGame")
                    } else {Text("오늘 공식 경기가 없습니다. 투수는 예정 선발일에 개인 표본이 쌓입니다. 홈에서 하루 행동과 다음 일정을 진행하세요.").font(.subheadline)}
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("공식 경기 일정").toolbarColorScheme(.dark,for:.navigationBar)
            .task(id:calendar.revision) {do {schools=try SchoolCatalog.load();fixtures=try calendar.upcoming(for:player);failure=nil}catch{failure=error.localizedDescription}}
    }
}
