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
                        ForEach(journal.releases ?? [],id:\.membershipOfferID) {release in
                            Text(release.date+" · 방출 확정 / 보유권리 해제 · 무소속").font(.caption).accessibilityIdentifier("careerReleaseHistory")
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
                        Text(value.renewal != nil ? "재계약 심사와 제의는 이 평가일에 고정됩니다. 상세에서 수락하면 저장된 경제 기간을 적용합니다.":value.selection == nil ? "선발 심사 자료 미기록 · 과거 원장은 다시 평가하지 않습니다.":"성적·모집 자리·예산·후보 순서는 평가일에 고정됩니다. 실제 입단 제의는 보관함에서 확인합니다.")
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
               (try? calendar.registration(for:player))?.route != .rookie {
                Text("11월은 프로 외부/갱신 창입니다. 현재 고교·진로 준비·무소속·대학 선수는 대상이 아닙니다. 국내 육성팀 소속 선수만 재계약 평가를 진행합니다.")
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
                    Text(value.economicLabel).font(.subheadline.bold()).accessibilityIdentifier("contractEconomicStatus")
                    Text((value.membership.economicStart ?? value.membership.since)+" ~ "+value.membership.economicEnd+" · \(value.membership.economicIndex)\(value.membership.route == .rookie ? " 연봉지수":" 지원지수")")
                        .font(.caption.monospaced()).accessibilityIdentifier("contractEconomicPeriod")
                    if let pending=pendingRenewal {
                        Text("갱신 예정 · "+pending.terms.effectiveDate+" ~ "+pending.terms.economicEnd+" · 연봉지수 \(pending.terms.economicIndex)")
                            .font(.caption).foregroundStyle(GameTheme.growth).accessibilityIdentifier("contractPendingRenewal")
                    }
                    Text(value.rightsLabel).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractRightsStatus")
                    if value.membership.route == .rookie {
                        Text("갱신 평가 창 · "+(value.nextReview ?? "—")+"부터 14일까지")
                            .font(.caption).accessibilityIdentifier("contractNextRenewal")
                        Text("11월 창 안에서는 최초 적격일의 평가·제의를 한 번 고정합니다. 경제 기간 종료나 제의 만료로 소속/권리가 자동 해제되지 않습니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    } else {
                        Text("학적 종료 · "+(value.membership.enrollmentEnd ?? "—")+" / 재학 중 프로 진출 심사는 후속")
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
        DomesticReleasePanel(player:player,calendar:calendar)
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
                } else if state.2,let released=state.0.releases?.last {
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
