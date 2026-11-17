import SwiftUI
import SwiftData

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
            season = try CareerSeasonStore.load(player: player, state: state, year: GameDate(player.gameDate).year, in: context)
            error = nil
        } catch { season = nil; self.error = error.localizedDescription }
    }
    private var ownTeamID: String {
        (try? state.competition(for: player, year: (try? GameDate(player.gameDate).year) ?? 2026).teamID) ?? player.schoolID
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let league {
                LeagueSeasonMasthead(league: league, date: player.gameDate)
                if let own = league.displayStandings.first(where: { $0.id == ownTeamID }) {
                    LeagueOwnScorecard(row: own, name: CareerTeamDirectory.name(own.id, schools: schools), leagueWide: league.hasGeographicDivisions)
                }
                leaderSummary(league)
                todaySummary(league)
            } else if let error {
                GamePanel(title: "리그 기록 확인 필요", onBoard: true) {
                    Text(error).font(.body).accessibilityIdentifier("homeLeagueError")
                    Button("순위 다시 확인", action: reload).buttonStyle(MatchPixelButtonStyle())
                }
            } else { ProgressView("리그 순위 불러오는 중").tint(GameTheme.gold) }
            NavigationLink { AnnualLeagueScreen(player: player, state: state, schools: schools) } label: {
                HStack(spacing: 10) {
                    LeaguePixelFlag().frame(width: 20, height: 22)
                    Text("전체 순위 · 오늘 대진")
                    Spacer(minLength: 0)
                    Text("›").font(.title2.bold())
                }
            }.buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("openAnnualLeague")
            NavigationLink { LeaguePlayersScreen(player: player, state: state) } label: {
                HStack(spacing: 12) { LeagueTrophyPixel().frame(width: 24, height: 28); Text("팀 선수 명단 · 리그 타이틀"); Spacer(); Text("›") }
            }.buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("openLeaguePlayers")
            if let season {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MY SEASON · 내 시즌 기록").font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    SeasonPersonalRecord(totals: season.totals, role: player.role, compact: true,coverage:season.coverage)
                    NavigationLink { CareerSeasonScreen(player: player, state: state, schools: schools, transition: transition) } label: {
                        Text(season.finalized ? "시즌 결산 · 최종 성적" : "시즌 성적 · 결산 보기")
                    }.buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("openSeasonSummary")
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameTheme.boardPanel, in: ManagementStepFrame())
                    .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 2))
            }
        }.foregroundStyle(GameTheme.boardInk)
            .task(id: "\(player.gameDate):\(state.revision):\(transition.display == nil)") {
                if transition.display == nil { reload() }
            }
    }

    private func leaderSummary(_ league: AnnualLeague) -> some View {
        let leaders = league.displayStandings.filter { $0.rank == 1 }
        return ManagementPanel(league.hasGeographicDivisions ? "리그 전체 선두" : "리그 선두", surface: .paper) {
            if let first = leaders.first {
                let name = CareerTeamDirectory.name(first.id, schools: schools)
                Text(leaders.count > 1 ? "공동 선두 · \(name) 외 \(leaders.count - 1)팀" : name).managementFont(.label).bold()
                Text("승률 \(first.percentage)").managementFont(.helper).monospacedDigit()
            } else {
                Text("집계된 팀 경기 결과가 없습니다.").managementFont(.body)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("leagueLeaderSummary")
    }

    private func todaySummary(_ league: AnnualLeague) -> some View {
        let fixture = league.fixtures.first {
            $0.date.description == player.gameDate && ($0.homeID == ownTeamID || $0.awayID == ownTeamID)
        }
        return ManagementPanel("내 팀 오늘 대진") {
            if let fixture {
                LeagueMatchTicket(fixture: fixture, result: league.results.first { $0.id == fixture.id },
                                  pending: league.pendingIDs.contains(fixture.id), ownTeamID: ownTeamID, schools: schools)
            } else {
                Text("오늘 내 팀 경기 일정이 없습니다.").managementFont(.body)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("leagueTodaySummary")
    }
}

struct LeaguePixelFlag: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 8, size.height / 9)
            context.fill(Path(CGRect(x: unit, y: unit, width: unit, height: unit * 8)), with: .color(GameTheme.boardMuted))
            context.fill(Path(CGRect(x: unit * 2, y: unit, width: unit * 5, height: unit * 3)), with: .color(GameTheme.gold))
            context.fill(Path(CGRect(x: unit * 2, y: unit * 4, width: unit * 3, height: unit)), with: .color(GameTheme.growth))
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
    private func name(_ id: String) -> String { CareerTeamDirectory.name(id, schools: schools) }
    private func reload() {
        do {
            let year = try selectedYear ?? GameDate(player.gameDate).year
            league = try AnnualLeagueStore.load(player: player, state: state, year: year, in: context)
            error = nil
        } catch { league = nil; self.error = error.localizedDescription }
    }
    private var ownTeamID: String {
        (try? state.competition(for: player, year: league?.year ?? (try? GameDate(player.gameDate).year) ?? 2026).teamID) ?? player.schoolID
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let league {
                    yearControls(league)
                    LeagueSeasonMasthead(league: league, date: player.gameDate)
                    if let own = league.displayStandings.first(where: { $0.id == ownTeamID }) {
                        LeagueOwnScorecard(row: own, name: name(own.id), leagueWide: league.hasGeographicDivisions)
                    }
                    LeagueStandingsTables(league: league, ownTeamID: ownTeamID, schools: schools)
                    let today = league.fixtures.filter { $0.date.description == player.gameDate }
                    if !today.isEmpty {
                        matchSection("TODAY", title: "오늘 대진") {
                            ForEach(today) { fixture in
                                LeagueMatchTicket(fixture: fixture, result: league.results.first { $0.id == fixture.id },
                                                  pending: league.pendingIDs.contains(fixture.id), ownTeamID: ownTeamID, schools: schools)
                            }
                        }
                    }
                    if let last = league.results.map({ $0.fixture.date }).max() {
                        matchSection("RECENT", title: ManagementDisplay.date(last.description) + " 결과") {
                            ForEach(league.results.filter { $0.fixture.date == last }) { result in
                                LeagueMatchTicket(fixture: result.fixture, result: result, pending: false, ownTeamID: ownTeamID, schools: schools)
                            }
                        }
                    } else {
                        Text("아직 완료한 리그 경기가 없습니다.").font(.body).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("leagueEmpty")
                    }
                    DisclosureGroup("순위 · 집계 기준") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("승률 = 승 ÷ (승+패) · 무승부 제외")
                            Text("같은 승률은 공동 순위 · 승패가 없으면 순위와 승률은 —")
                            if !league.hasFullSchedule { Text("경력 시작 전이거나 현재 진로에서 출전 대상이 아닌 일정은 집계하지 않습니다.") }
                            Text("실제 완료 점수 우선 · 지난 날짜의 남은 경기만 자동 처리")
                            Text("다른 팀 자동 결과는 내 개인 성적·피로·XP에 반영되지 않습니다.")
                        }.font(.subheadline).foregroundStyle(GameTheme.boardMuted).padding(.top, 10)
                    }.font(.subheadline.bold()).tint(GameTheme.gold).padding(14)
                        .background(GameTheme.boardPanel, in: ManagementStepFrame())
                } else if let error {
                    GamePanel(title: "리그 기록 확인 필요", onBoard: true) {
                        Text(error).font(.body).accessibilityIdentifier("leagueLoadError")
                        Button("다시 확인", action: reload).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryAnnualLeague")
                    }
                } else { ProgressView("리그 불러오는 중").tint(GameTheme.gold) }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("연간 리그 순위").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: "\(selectedYear ?? 0):\(player.gameDate):\(state.revision)") { reload() }
    }
    private func yearControls(_ league: AnnualLeague) -> some View {
        HStack(spacing: 12) {
            Button("‹ 이전 연도") { selectedYear = league.year - 1 }
                .disabled(league.year <= (try? GameDate(state.originDate).year) ?? league.year)
                .accessibilityIdentifier("leaguePreviousYear")
            Button("다음 연도 ›") { selectedYear = league.year + 1 }
                .disabled(league.year >= (try? GameDate(player.gameDate).year) ?? league.year)
                .accessibilityIdentifier("leagueNextYear")
        }.buttonStyle(ManagementButtonStyle(variant: .secondary))
    }
    private func matchSection<Content: View>(_ eyebrow: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(eyebrow).font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }
}

private struct LeagueSeasonMasthead: View {
    let league: AnnualLeague
    let date: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image("NavGameV1").resizable().interpolation(.none).scaledToFit().frame(width: 42, height: 42).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(league.year)) SEASON").font(.title2.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    Text(league.hasGeographicDivisions ? "동부·서부 15구단 · 팀당 연 30경기" : league.standings.count == 10 ? "10구단 단일리그 · 팀당 연 30경기" : "6팀 조별리그 · 팀당 연 30경기")
                        .font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("leagueSeasonFormat")
                }
            }
            Text(league.isComplete ? "FINAL · 최종 기록 보존" : league.hasFullSchedule ? "LIVE · 연간 리그" : "PARTIAL · 부분 시즌")
                .font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("leagueSeasonState")
            Text("팀 순위는 전체 팀 결과 · 개인 성적은 내 출전 원장만")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("leagueRecordScope")
            Text("완료 \(league.results.count) / 대상 \(league.fixtures.count)경기 · \(ManagementDisplay.date(date)) 기준")
                .font(.subheadline.monospacedDigit()).accessibilityIdentifier("leagueProgress")
            GeometryReader { geometry in
                let progress = league.fixtures.isEmpty ? 0 : min(1, Double(league.results.count) / Double(league.fixtures.count))
                ZStack(alignment: .leading) {
                    Rectangle().fill(GameTheme.board)
                    Rectangle().fill(GameTheme.gold).frame(width: max(0, geometry.size.width) * progress)
                }
            }.frame(height: 8).accessibilityHidden(true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.boardPanel, in: ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 2))
    }
}

private struct LeagueOwnScorecard: View {
    let row: LeagueStanding
    let name: String
    let leagueWide: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(row.rank.map(String.init) ?? "—").font(.system(.largeTitle, design: .monospaced, weight: .black))
                    Text(row.rank == nil ? "집계 전" : leagueWide ? "전체 순위" : "위").font(.caption.bold())
                }.foregroundStyle(GameTheme.gold).frame(minWidth: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MY TEAM").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    Text(name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("\(row.games)경기 · 승률 \(row.percentage)").font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                        .accessibilityLabel("\(row.games)경기 · \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)")
                        .accessibilityIdentifier("homeLeagueRecord")
                }
                Spacer(minLength: 0)
                LeaguePixelFlag().frame(width: 26, height: 30)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                record("승", value: row.wins, color: GameTheme.growth)
                record("무", value: row.draws, color: GameTheme.gold)
                record("패", value: row.losses, color: GameTheme.boardMuted)
            }
            LeagueRecordComposition(row: row)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x244a43), in: ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.gold, lineWidth: 2))
            .accessibilityElement(children: .contain)
    }
    private func record(_ title: String, value: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(value)).font(.title2.monospaced().bold()).foregroundStyle(color)
            Text(title).font(.subheadline.bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LeagueRecordComposition: View {
    let row: LeagueStanding
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width)
                let games = Double(max(1, row.games))
                HStack(spacing: 0) {
                    Rectangle().fill(GameTheme.growth).frame(width: width * Double(row.wins) / games)
                    Rectangle().fill(GameTheme.gold).frame(width: width * Double(row.draws) / games)
                    Rectangle().fill(GameTheme.boardMuted).frame(width: width * Double(row.losses) / games)
                }.frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
            }.frame(height: 10)
            Text(row.games == 0 ? "첫 경기의 기록을 기다립니다" : "승 · 무 · 패 구성")
                .font(.caption).foregroundStyle(GameTheme.boardMuted)
        }.accessibilityHidden(true)
    }
}

extension AnnualLeague {
    var hasGeographicDivisions: Bool {
        standings.count == 15 && standings.allSatisfy { CareerTeamDirectory.division(for: $0.id) != nil }
    }
    func geographicStandings(_ division: ClubIdentity.Division) -> [LeagueStanding] {
        let ids = Set(standings.filter { CareerTeamDirectory.division(for: $0.id) == division }.map(\.id))
        return displayStandings(for: ids)
    }
}

struct LeagueStandingsTables: View {
    let league: AnnualLeague
    let ownTeamID: String
    let schools: [School]
    var body: some View {
        if league.hasGeographicDivisions {
            LeagueStandingsBoard(rows: league.geographicStandings(.east), ownTeamID: ownTeamID, schools: schools,
                                 title: "동부 순위", identifier: "leagueDivision-east")
            LeagueStandingsBoard(rows: league.geographicStandings(.west), ownTeamID: ownTeamID, schools: schools,
                                 title: "서부 순위", identifier: "leagueDivision-west")
        } else {
            LeagueStandingsBoard(rows: league.displayStandings, ownTeamID: ownTeamID, schools: schools)
        }
    }
}

private struct LeagueStandingsBoard: View {
    let rows: [LeagueStanding]
    let ownTeamID: String
    let schools: [School]
    var title = "순위 전광판"
    var identifier = "leagueStandingsTitle"
    @Environment(\.dynamicTypeSize) private var typeSize
    private var expanded: Bool { typeSize >= .xxxLarge }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("LEAGUE").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(title).font(.headline).accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
                Spacer()
            }.padding(12)
            if !expanded { tableHeader }
            ForEach(rows) { standingRow($0) }
        }.background(GameTheme.boardPanel, in: ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 2))
    }
    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("위").frame(width: 28)
            Text("팀").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["승", "패", "무"], id: \.self) { Text($0).frame(width: 28) }
            Text("승률").frame(width: 46, alignment: .trailing)
        }.font(.caption.bold()).foregroundStyle(GameTheme.boardMuted)
            .padding(.horizontal, 10).padding(.vertical, 8).background(Color(hex: 0x244253)).accessibilityHidden(true)
    }
    private func standingRow(_ row: LeagueStanding) -> some View {
        let own = row.id == ownTeamID
        let name = CareerTeamDirectory.name(row.id, schools: schools)
        return VStack(alignment: .leading, spacing: 8) {
            if expanded {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.rank.map { "\($0)위" } ?? "—").font(.title3.monospaced().bold()).foregroundStyle(own ? GameTheme.gold : GameTheme.boardInk)
                    Text(name + (own ? " · 내 팀" : "")).font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                Text("\(row.games)경기 · \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)").font(.body.monospacedDigit())
                LeagueRecordComposition(row: row)
            } else {
                HStack(spacing: 6) {
                    Text(row.rank.map(String.init) ?? "—").font(.title3.monospaced().bold()).foregroundStyle(own ? GameTheme.gold : GameTheme.boardInk).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.subheadline.bold()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if own { Text("내 팀").font(.caption.bold()).foregroundStyle(GameTheme.gold) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(row.wins)).foregroundStyle(GameTheme.growth).frame(width: 28)
                    Text(String(row.losses)).frame(width: 28)
                    Text(String(row.draws)).frame(width: 28)
                    Text(row.percentage).frame(width: 46, alignment: .trailing)
                }.font(.subheadline.monospacedDigit().bold())
            }
        }.padding(.horizontal, 10).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(own ? Color(hex: 0x244a43) : GameTheme.boardPanel)
            .overlay(alignment: .bottom) { Rectangle().fill(GameTheme.boardLine.opacity(0.4)).frame(height: 1) }
            .overlay(alignment: .leading) { if own { Rectangle().fill(GameTheme.gold).frame(width: 3) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)\(own ? " 내 팀" : "") · 순위 \(row.rank.map(String.init) ?? "미정") · \(row.games)경기 \(row.wins)승 \(row.losses)패 \(row.draws)무 · 승률 \(row.percentage)")
            .accessibilityIdentifier(own ? "leagueOwnStanding" : "leagueStanding-\(row.id)")
    }
}

private struct LeagueMatchTicket: View {
    let fixture: SeasonFixture
    let result: LeagueResult?
    let pending: Bool
    let ownTeamID: String
    let schools: [School]
    @Environment(\.dynamicTypeSize) private var typeSize
    private var ownMatch: Bool { fixture.homeID == ownTeamID || fixture.awayID == ownTeamID }
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ManagementDisplay.date(fixture.date.description)).font(.caption.monospacedDigit())
                Spacer(minLength: 0)
                Text(result.map {LeagueRecordSource.label(automatic:$0.automatic,ownTeam:ownMatch)} ?? (pending ? "경기 진행 중":"경기 대기"))
                    .font(.caption.bold()).foregroundStyle(result != nil ? GameTheme.gold : GameTheme.boardMuted)
            }
            if typeSize.isAccessibilitySize {
                teamName(fixture.awayID, side: "원정")
                score
                teamName(fixture.homeID, side: "홈")
            } else {
                HStack(spacing: 10) {
                    teamName(fixture.awayID, side: "원정")
                    score
                    teamName(fixture.homeID, side: "홈")
                }
            }
        }.padding(14).frame(maxWidth: .infinity)
            .foregroundStyle(GameTheme.boardInk).background(GameTheme.boardPanel, in: ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(ownMatch ? GameTheme.gold : GameTheme.boardLine, lineWidth: ownMatch ? 2 : 1))
            .accessibilityElement(children: .combine).accessibilityIdentifier("leagueFixture-\(fixture.id)")
    }
    private func teamName(_ id: String, side: String) -> some View {
        VStack(spacing: 5) {
            Text(side).font(.caption).foregroundStyle(GameTheme.boardMuted)
            Text(CareerTeamDirectory.name(id, schools: schools)).font(.subheadline.bold()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }
    private var score: some View {
        HStack(spacing: 7) {
            if let result {
                Text(String(result.awayScore)).foregroundStyle(GameTheme.gold)
                Text(":").foregroundStyle(GameTheme.boardMuted)
                Text(String(result.homeScore)).foregroundStyle(GameTheme.gold)
            } else { Text("VS").foregroundStyle(GameTheme.boardMuted) }
        }.font(.title2.monospaced().bold()).fixedSize(horizontal: true, vertical: false)
    }
}

struct LeagueHonorBadge: View {
    let honor: LeagueHonor
    var body: some View {
        HStack(spacing: 6) {
            LeagueTrophyPixel().frame(width: 16, height: 18)
            Text(honor.label + " · " + honor.number).font(.caption.bold()).fixedSize(horizontal: false, vertical: true)
        }.padding(8).foregroundStyle(GameTheme.gold).background(GameTheme.navy)
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.gold, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}
struct LeagueTrophyPixel: View {
    var body: some View {
        Canvas { context, size in
            let pixels = [".######.","###..###","#.#..#.#",".######.","..####..","...##...","...##...","..####..",".######."]
            let unit = min(size.width / 8, size.height / 9)
            for (y, line) in pixels.enumerated() { for (x, cell) in line.enumerated() where cell == "#" {
                context.fill(Path(CGRect(x: Double(x) * unit, y: Double(y) * unit, width: unit, height: unit)), with: .color(GameTheme.gold))
            } }
        }.accessibilityHidden(true)
    }
}

struct SeasonAwardPanel: View {
    let board: CareerSeasonAwardBoard
    let player: CareerPlayer
    let schools: [School]
    let identifier: String

    private var status: String {
        switch board.status {
        case .inProgress: "시즌 진행 중"
        case .pending: "확정 보류"
        case .historical: "과거 원장 확인"
        case .finalized: "최종 확정"
        }
    }

    var body: some View {
        ManagementPanel("개인 타이틀") {
            HStack(alignment: .top, spacing: ManagementTheme.Space.inline) {
                LeagueTrophyPixel().frame(width: 26, height: 29)
                VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                    Text(status).managementFont(.label)
                        .foregroundStyle(GameTheme.gold)
                        .accessibilityIdentifier(identifier + "Status")
                    Text(CareerSeasonAwardRecord.leagueLabel(board.competition) + " · \(String(board.year)) 시즌")
                        .managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                        .accessibilityIdentifier(identifier + "League")
                    if board.coverageAvailable {
                        Text("개인 성적 확인 \(board.recordedGames) / \(board.expectedGames)경기")
                            .managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(identifier + "Coverage")
                    }
                }
            }
            if let reason = board.reason {
                Text(reason).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + "Pending")
            }
            SeasonAwardLeaders(honors: board.honors, unresolvedKinds: board.record?.unresolvedKinds ?? [],
                               player: player, schools: schools, identifier: identifier)
        }
    }
}

struct SeasonAwardLeaders: View {
    let honors: [LeagueHonor]
    let unresolvedKinds: [LeagueHonor.Kind]
    let player: CareerPlayer
    let schools: [School]
    let identifier: String

    private func result(_ honor: LeagueHonor) -> String {
        if honor.final { return honor.tied ? "공동 1위" : "1위" }
        return honor.tied ? "공동 선두" : "선두"
    }

    var body: some View {
        ForEach(LeagueHonor.Kind.allCases, id: \.rawValue) { kind in
            let winners = honors.filter { $0.kind == kind }
            if let first = winners.first {
                section(kind, result: result(first) + " · " + first.number) {
                    ForEach(winners) { winner in
                        let own = winner.playerID == player.id.uuidString
                        let name = own ? player.name : NPCIdentity.name(winner.playerID)
                        let team = CareerTeamDirectory.name(winner.teamID, schools: schools)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: ManagementTheme.Space.inline) {
                                winnerLabels(name: name, team: team, own: own)
                            }
                            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                                winnerLabels(name: name, team: team, own: own)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(identifier + "Winner-" + winner.id)
                    }
                }
            } else if unresolvedKinds.contains(kind) {
                section(kind, result: "확정 타이틀 없음") { EmptyView() }
            }
        }
    }

    @ViewBuilder
    private func winnerLabels(name: String, team: String, own: Bool) -> some View {
        Text(own ? name + " · 내 선수" : name)
            .managementFont(.label).foregroundStyle(own ? GameTheme.gold : GameTheme.boardInk)
        Text(team).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
    }

    private func section<Content: View>(_ kind: LeagueHonor.Kind, result: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ManagementTheme.Space.inline) { heading(kind, result: result) }
                VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) { heading(kind, result: result) }
            }
            content()
        }
        .padding(ManagementTheme.Space.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.board, in: ManagementStepFrame())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier + "Kind-" + kind.rawValue)
    }

    @ViewBuilder
    private func heading(_ kind: LeagueHonor.Kind, result: String) -> some View {
        Text(kind.label).managementFont(.label).accessibilityAddTraits(.isHeader)
        Text(result).managementFont(.label).foregroundStyle(GameTheme.gold).monospacedDigit()
            .accessibilityIdentifier(identifier + "KindResult-" + kind.rawValue)
    }
}

struct SeasonBestNinePanel: View {
    let lineup: LeagueBestNine?
    private let availability: SeasonAwardAvailability
    let league: String
    let player: CareerPlayer
    let schools: [School]
    let identifier: String

    init(board: CareerSeasonAwardBoard, player: CareerPlayer, schools: [School], identifier: String) {
        lineup = board.bestNine
        availability = .init(board: board, missing: "이 시즌의 포지션별 출전 기록을 확인할 수 없습니다.")
        league = SeasonAwardCategory.leagueSeason(year: board.year, competition: board.competition)
        self.player = player
        self.schools = schools
        self.identifier = identifier
    }

    init(record: CareerSeasonAwardRecord, player: CareerPlayer, schools: [School], identifier: String) {
        lineup = record.bestNine
        availability = .init(status: "포지션 기록 미집계", reason: "이 시즌의 포지션별 출전 기록을 확인할 수 없습니다.")
        league = SeasonAwardCategory.leagueSeason(year: record.year, competition: record.competition)
        self.player = player
        self.schools = schools
        self.identifier = identifier
    }

    var body: some View {
        SeasonAwardShowcase(category: .team, league: league, availability: availability,
                            selected: lineup?.slots.count(where: { $0.winner != nil }), total: lineup?.slots.count,
                            identifier: identifier) {
            if let lineup {
                ForEach(lineup.slots) { slot in
                    if let winner = slot.winner {
                        let isPitcher = slot.position == .pitcher
                        let content = SeasonAwardCard.Content(
                            teamID: winner.teamID, playerID: winner.playerID,
                            metrics: metrics(for: winner.evidence), sample: winner.evidence.sampleSummary,
                            qualification: isPitcher ? "30투구이닝 · 자책점 집계" : "주 포지션 150수비이닝 · 60타석",
                            ranking: isPitcher ? LeagueBestNine.pitchingRanking : LeagueBestNine.fieldingRanking
                        )
                        SeasonAwardCard(category: .team, position: slot.position, content: content,
                                        player: player, schools: schools, identifier: identifier)
                    } else if let reason = slot.reason {
                        SeasonAwardHold(position: slot.position, reason: reason.label, identifier: identifier)
                    }
                }
                JournalDisclosure(title: "올해의팀 선정 기준", identifier: identifier + "Rules") {
                    SeasonAwardFact(title: "투수", value: LeagueBestNine.pitchingCriteria)
                    SeasonAwardFact(title: "야수", value: LeagueBestNine.fieldingCriteria)
                    SeasonAwardFact(title: "주 포지션", value: LeagueBestNine.primaryPositionRule)
                    SeasonAwardFact(title: "동률", value: LeagueBestNine.finalTieRule)
                }
            }
        }
    }

    private func metrics(for evidence: LeagueBestNine.Evidence) -> [SeasonAwardCard.Metric] {
        switch evidence {
        case .pitcher(let sample):
            [.init(title: "ERA", value: String(format: "%.2f", sample.era)),
             .init(title: "탈삼진", value: "\(sample.strikeouts)")]
        case .fielder(let sample):
            [.init(title: "OPS", value: String(format: "%.3f", Double(sample.rankedOPS) / 1_000)),
             .init(title: "홈런", value: "\(sample.homeRuns)")]
        }
    }
}

struct SeasonGoldGlovePanel: View {
    let lineup: LeagueGoldGlove?
    private let availability: SeasonAwardAvailability
    let league: String
    let player: CareerPlayer
    let schools: [School]
    let identifier: String

    init(board: CareerSeasonAwardBoard, player: CareerPlayer, schools: [School], identifier: String) {
        lineup = board.goldGlove
        availability = .init(board: board, missing: "이 시즌의 포지션별 수비 기록을 확인할 수 없습니다.")
        league = SeasonAwardCategory.leagueSeason(year: board.year, competition: board.competition)
        self.player = player
        self.schools = schools
        self.identifier = identifier
    }

    init(record: CareerSeasonAwardRecord, player: CareerPlayer, schools: [School], identifier: String) {
        lineup = record.goldGlove
        availability = .init(status: "수비 기록 미집계", reason: "이 시즌의 포지션별 수비 기록을 확인할 수 없습니다.")
        league = SeasonAwardCategory.leagueSeason(year: record.year, competition: record.competition)
        self.player = player
        self.schools = schools
        self.identifier = identifier
    }

    var body: some View {
        SeasonAwardShowcase(category: .defense, league: league, availability: availability,
                            selected: lineup?.slots.count(where: { $0.winner != nil }), total: lineup?.slots.count,
                            identifier: identifier) {
            if let lineup {
                ForEach(lineup.slots) { slot in
                    let qualification = "최소 \(slot.minimumInnings)수비이닝 · \(slot.minimumChances)수비기회"
                    if let winner = slot.winner {
                        let sample = winner.evidence
                        let metrics: [SeasonAwardCard.Metric] = [
                            .init(title: "수비율", value: String(format: "%.3f", sample.fieldingPercentage)),
                            .init(title: "실책", value: "\(sample.errors)")
                        ]
                        let content = SeasonAwardCard.Content(
                            teamID: winner.teamID, playerID: winner.playerID,
                            metrics: metrics, sample: sample.sampleSummary, qualification: qualification,
                            ranking: LeagueGoldGlove.rankingRule, scorebook: "자살 \(sample.putouts) · 보살 \(sample.assists) · 실책 \(sample.errors)"
                        )
                        SeasonAwardCard(category: .defense, position: slot.position, content: content,
                                        player: player, schools: schools, identifier: identifier)
                    } else if let reason = slot.reason {
                        SeasonAwardHold(position: slot.position, reason: reason.label,
                                        qualification: qualification, identifier: identifier)
                    }
                }
                JournalDisclosure(title: "골든글러브 선정 기준", identifier: identifier + "Rules") {
                    SeasonAwardFact(title: "출전 자격", value: "포지션별 최소 수비이닝과 수비기회를 충족해야 합니다.")
                    SeasonAwardFact(title: "수비율", value: "(자살 + 보살) / (자살 + 보살 + 실책)")
                    SeasonAwardFact(title: "순위 산정", value: LeagueGoldGlove.rankingRule)
                }
            }
        }
    }
}

private enum SeasonAwardCategory {
    case team, defense

    var title: String { self == .team ? "올해의팀" : "골든글러브" }
    var criteria: String { self == .team ? "포지션별 투타 성적" : "포지션별 수비 성적" }
    var accent: Color { self == .team ? GameTheme.gold : GameTheme.growth }

    static func leagueSeason(year: Int, competition: String) -> String {
        "\(String(year)) \(CareerSeasonAwardRecord.leagueLabel(competition)) 시즌"
    }
}

private struct SeasonAwardAvailability {
    let status: String
    let reason: String?

    init(status: String, reason: String?) {
        self.status = status
        self.reason = reason
    }

    init(board: CareerSeasonAwardBoard, missing: String) {
        switch board.status {
        case .inProgress:
            self.init(status: "시즌 진행 중", reason: "최종 시상은 시즌 종료 후 확인할 수 있습니다.")
        case .pending:
            self.init(status: "확정 보류", reason: board.reason)
        case .historical, .finalized:
            self.init(status: "포지션 기록 미집계", reason: board.reason ?? missing)
        }
    }
}

private struct SeasonAwardShowcase<Content: View>: View {
    let category: SeasonAwardCategory
    let league: String
    let availability: SeasonAwardAvailability
    let selected: Int?
    let total: Int?
    let identifier: String
    @ViewBuilder let content: Content

    private var status: String {
        guard let selected, let total else { return availability.status }
        if selected == total { return "\(total)개 포지션 확정" }
        if selected == 0 { return "전체 포지션 보류" }
        return "선정 \(selected) / \(total) 포지션"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            masthead
            if selected == nil, let reason = availability.reason {
                Text(reason).managementFont(.body).foregroundStyle(GameTheme.boardMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + "Reason")
            }
            content
        }
        .padding(ManagementTheme.Space.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(GameTheme.boardInk)
        .background(GameTheme.boardPanel, in: ManagementStepFrame())
        .overlay {
            ManagementStepFrame()
                .strokeBorder(category.accent.opacity(0.5), lineWidth: ManagementTheme.Control.border)
                .allowsHitTesting(false)
        }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: ManagementTheme.Space.compact) {
            Group {
                if category == .team {
                    LeagueTrophyPixel().frame(width: 24, height: 27)
                } else {
                    SeasonFieldingMedal().frame(width: 28, height: 28)
                }
            }
            .frame(width: ManagementTheme.Control.secondaryHeight, height: ManagementTheme.Control.secondaryHeight)
            .background(GameTheme.navy, in: ManagementStepFrame())
            .overlay { ManagementStepFrame().strokeBorder(category.accent, lineWidth: 1) }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                Text(league).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                Text(category.title).managementFont(.metric).foregroundStyle(category.accent)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier + "Title")
                Text(category.criteria).managementFont(.helper).foregroundStyle(GameTheme.boardInk)
                Text(status).managementFont(.label).foregroundStyle(category.accent)
                    .monospacedDigit().accessibilityIdentifier(identifier + "Status")
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ManagementTheme.Space.compact)
        .background(category.accent.opacity(0.09), in: ManagementStepFrame())
    }
}

private struct SeasonFieldingMedal: View {
    var body: some View {
        Canvas { context, size in
            let rows = [
                "....##....",
                "....#.#...",
                "..#.#.##..",
                ".##.#.###.",
                ".########.",
                ".#####.###",
                "..####.###",
                "..#######.",
                "...#####..",
                "....###..."
            ]
            let unit = min(size.width, size.height) / 10
            for (y, row) in rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "#" {
                    let rect = CGRect(x: Double(x) * unit, y: Double(y) * unit, width: unit, height: unit)
                    context.fill(Path(rect), with: .color(GameTheme.gold))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SeasonAwardCard: View {
    struct Metric {
        let title: String
        let value: String
    }

    struct Content {
        let teamID: String
        let playerID: String
        let metrics: [Metric]
        let sample: String
        let qualification: String
        let ranking: String
        var scorebook: String? = nil
    }

    let category: SeasonAwardCategory
    let position: LeagueBestNine.Position
    let content: Content
    let player: CareerPlayer
    let schools: [School]
    let identifier: String
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var suffix: String { "-" + position.rawValue }
    private var isOwn: Bool { content.playerID == player.id.uuidString }
    private var name: String { isOwn ? player.name : NPCIdentity.name(content.playerID) }
    private var team: String { CareerTeamDirectory.name(content.teamID, schools: schools) }

    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            identity
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
                    metrics
                    detailButton
                }
            } else {
                HStack(alignment: .center, spacing: ManagementTheme.Space.inline) {
                    metrics
                    detailButton
                }
            }
            if expanded { evidence }
        }
        .padding(ManagementTheme.Space.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.navy, in: ManagementStepFrame())
        .overlay {
            ManagementStepFrame().strokeBorder(category.accent.opacity(isOwn ? 1 : 0.48),
                                                lineWidth: isOwn ? ManagementTheme.Control.border : 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var metrics: some View {
        if let primary = content.metrics.first {
            metric(primary, prominence: true).accessibilityIdentifier(identifier + "Metric" + suffix)
        }
        if let secondary = content.metrics.dropFirst().first {
            metric(secondary, prominence: false)
        }
    }

    private var identity: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ManagementTheme.Space.inline))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ManagementTheme.Space.compact))
        return layout {
            SeasonAwardEmblem(teamID: content.teamID, name: team, schools: schools,
                              identifier: identifier + "Emblem" + suffix)
            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                Text(position.label + " 선정")
                    .managementFont(.label).foregroundStyle(category.accent)
                Text(name).managementFont(.sectionTitle).foregroundStyle(GameTheme.boardInk)
                    .accessibilityIdentifier(identifier + "Winner" + suffix)
                Text(team).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                    .accessibilityIdentifier(identifier + "Team" + suffix)
                if isOwn {
                    Text("내 선수").managementFont(.label).foregroundStyle(category.accent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ metric: Metric, prominence: Bool) -> some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
            Text(metric.title).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
            Text(metric.value).managementFont(prominence ? .metric : .sectionTitle)
                .foregroundStyle(prominence ? category.accent : GameTheme.boardInk)
                .monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var detailButton: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: ManagementTheme.Space.micro) {
                Text("근거").managementFont(.label).foregroundStyle(category.accent)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.footnote.bold()).foregroundStyle(category.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ManagementTheme.Space.inline)
            .frame(minWidth: ManagementTheme.Control.hit, minHeight: ManagementTheme.Control.hit)
            .contentShape(Rectangle())
            .background(category.accent.opacity(0.09), in: ManagementStepFrame())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(position.label) \(name), \(team), 선정 근거")
        .accessibilityValue(expanded ? "펼침" : "접힘")
        .accessibilityIdentifier(identifier + "Position" + suffix)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            Text("선정 근거").managementFont(.label).foregroundStyle(category.accent)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier + "Evidence" + suffix)
            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                Text("출전 기록").managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                Text(content.sample).managementFont(.label)
                    .accessibilityIdentifier(identifier + "Sample" + suffix)
                Text(content.qualification).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                    .accessibilityIdentifier(identifier + "Qualification" + suffix)
            }
            if let scorebook = content.scorebook {
                SeasonAwardFact(title: "수비 기록", value: scorebook, identifier: identifier + "Scorebook" + suffix)
            }
            SeasonAwardFact(title: "순위 산정", value: content.ranking, identifier: identifier + "Ranking" + suffix)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(ManagementTheme.Space.inline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.boardPanel, in: ManagementStepFrame())
    }
}

private struct SeasonAwardEmblem: View {
    let teamID: String
    let name: String
    let schools: [School]
    let identifier: String

    var body: some View {
        if let school = schools.first(where: { $0.id == teamID }) ?? SchoolCatalog.bundled.first(where: { $0.id == teamID }) {
            emblem { SchoolCrest(school: school) }
        } else if let club = ClubIdentity.resolve(name: name) ?? ClubIdentity.resolve(id: teamID) {
            emblem { Image(club.asset).interpolation(.none).resizable().scaledToFit() }
        }
    }

    private func emblem<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(ManagementTheme.Space.micro)
            .frame(width: ManagementTheme.Control.secondaryHeight, height: ManagementTheme.Control.secondaryHeight)
            .background(ManagementTheme.Palette.control, in: ManagementStepFrame())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name + " 엠블럼")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier(identifier)
    }
}

private struct SeasonAwardHold: View {
    let position: LeagueBestNine.Position
    let reason: String
    var qualification: String? = nil
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
            Text(position.label + " · 보류").managementFont(.label)
                .accessibilityIdentifier(identifier + "Position-" + position.rawValue)
            Text(reason).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                .accessibilityIdentifier(identifier + "Hold-" + position.rawValue)
            if let qualification {
                Text(qualification).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                    .accessibilityIdentifier(identifier + "Qualification-" + position.rawValue)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(ManagementTheme.Space.inline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.board, in: ManagementStepFrame())
    }
}

private struct SeasonAwardFact: View {
    let title: String
    let value: String
    var identifier: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
            Text(title).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
            Text(value).managementFont(.label)
                .accessibilityIdentifier(identifier)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LeaguePlayersScreen: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    var year: Int? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var teams: [MatchNPCAttackTeam] = []
    @State private var selected = ""
    @State private var ledger: SeasonPlayerLedger?
    @State private var honors: [LeagueHonor] = []
    @State private var honorsPending: String?
    @State private var failure: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let failure {
                    Text(failure); Button("선수 명단 다시 확인", action: load).buttonStyle(MatchPixelButtonStyle())
                } else {
                    Text("리그 선수 · 타이틀").font(ManagementPixelFont.readable(.screenTitle))
                    Text("가상 선수 고정 명단 · 경기 원장 성적만 집계").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    if honors.isEmpty { Text(honorsPending ?? "선두 자료 확인 중").font(.subheadline).accessibilityIdentifier("leagueHonorsPending") }
                    ForEach(honors) { honor in
                        HStack(spacing: 10) {
                            LeagueTrophyPixel().frame(width: 26, height: 30)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(honor.playerID == player.id.uuidString ? player.name : NPCIdentity.name(honor.playerID)).font(.headline)
                                Text(CareerTeamDirectory.name(honor.teamID)).font(.caption).foregroundStyle(GameTheme.boardMuted)
                                LeagueHonorBadge(honor: honor)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
                    }
                    if let ledger, ledger.unscoredDecisionGames > 0 {
                        Text("다승 선두 보류 · 승패 미채점 \(ledger.unscoredDecisionGames)경기").font(.subheadline).accessibilityIdentifier("winsPending")
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { ForEach(teams, id: \.teamID) { team in
                            Button(CareerTeamDirectory.name(team.teamID)) { selected = team.teamID }
                                .buttonStyle(MatchPixelButtonStyle(selected: selected == team.teamID))
                                .accessibilityIdentifier("rosterTeam-" + team.teamID)
                        } }
                    }
                    if let team = teams.first(where: { $0.teamID == selected }) {
                        ForEach(team.ordered) { batter in
                            row(id: batter.position == "P" ? team.starter.id : batter.id, name: batter.displayName, position: batter.position == "P" ? "선발 투수" : batter.position, teamID: team.teamID)
                        }
                        row(id: team.relief.id, name: team.relief.displayName, position: "구원 투수", teamID: team.teamID)
                        if ledger?.players.contains(where: { $0.teamID == team.teamID && $0.id == player.id.uuidString }) == true {
                            row(id: player.id.uuidString, name: player.name, position: "내 선수 · 시즌 원장", teamID: team.teamID)
                        }
                    }
                    DisclosureGroup("선두·최종 타이틀 기준") {
                        Text("게임의 30경기 단축 시즌 기준입니다. 타율은 팀 경기×3.1(올림)과 최소15타석, ERA는 팀 경기×3아웃과 최소9아웃을 모두 충족해야 합니다. 홈런/탈삼진은 양수 기록을 비교하며 동률은 공동 선두입니다. 모든 팀의 기록이 확인되고 누락 경기가 없을 때만 표시합니다. 팀당30경기 완료 뒤에만 최종1위로 표시합니다. 다승은 승패 채점을 시작한 경기만 집계하며, 과거 승패 미채점 경기가 있으면 선두를 보류합니다. 선발은 5이닝을 충족해야 하고, 미충족 시 현재 규칙의 유일한 구원투수에게 승리를 기록합니다.")
                            .font(.subheadline).padding(.top, 8)
                    }.tint(GameTheme.gold)
                }
            }.padding(16)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("리그 선수 명단").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(player.id)-\(player.gameDate)-\(state.revision)-\(year ?? 0)") { load() }
    }
    private func row(id: String, name: String, position: String, teamID: String) -> some View {
        let record = ledger?.players.first { $0.teamID == teamID && $0.id == id }
        return VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize >= .xxxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            layout {
                Text(name).font(ManagementPixelFont.readable(.label)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("npcName-" + id)
                Text(position).font(.caption).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(honors.filter { $0.playerID == id && $0.teamID == teamID }) { LeagueHonorBadge(honor: $0) }
            if id.hasSuffix("/starter") || id.hasSuffix("/relief") || id == player.id.uuidString && player.role == .pitcher {
                Text(record.map { "승패 " + ($0.decisionGames > 0 ? "\($0.wins)승 \($0.losses)패 · 채점 \($0.decisionGames)경기" : "미집계") + ($0.unscoredDecisionGames > 0 ? " / 미채점 \($0.unscoredDecisionGames)경기" : "") } ?? "승패 미집계")
                    .font(.subheadline.monospacedDigit()).accessibilityIdentifier("pitcherDecisions-" + id)
                Text("ERA " + (record?.pitching.era.map { String(format: "%.2f", $0) } ?? "미집계") + " · K " + (record.map { String($0.pitching.strikeouts) } ?? "미집계") + " · IP " + (record?.pitching.innings ?? "미집계"))
                    .font(.subheadline.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("AVG " + (record?.batting.average.map { String(format: "%.3f", $0) } ?? "미집계") + " · HR " + (record.map { String($0.batting.homeRuns) } ?? "미집계"))
                    .font(.subheadline.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
    }
    private func load() {
        do {
            let year = try year ?? GameDate(player.gameDate).year
            let plan = try state.competition(for: player, year: year)
            let level = plan.membership?.level ?? "highschool"
            let ids = Set(plan.fixtures.flatMap { [$0.homeID, $0.awayID] }).sorted()
            teams = ids.compactMap { id in
                guard let other = ids.first(where: { $0 != id }) else { return nil }
                return MatchNPCAttack.makeComplete(roster: MatchNPCFielders.make(year: year, competition: level, homeID: id, awayID: other)).home
            }
            if !ids.contains(selected) { selected = plan.teamID }
            let value = try CareerMatchStore.seasonPlayerRecords(playerID: player.id, year: year, competition: level, through: GameDate(player.gameDate), in: context)
            let today = try GameDate(player.gameDate)
            let required = Set(plan.fixtures.filter { $0.date < today }.map(\.id))
            ledger = value; honors = LeagueHonorRules.leaders(value, requiredFixtureIDs: required, teamCount: ids.count)
            honorsPending = LeagueHonorRules.pendingReason(value, requiredFixtureIDs: required, teamCount: ids.count); failure = nil
        } catch { failure = error.localizedDescription }
    }
}
