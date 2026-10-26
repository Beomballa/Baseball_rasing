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
                if let own = league.standings.first(where: { $0.id == ownTeamID }) {
                    LeagueOwnScorecard(row: own, name: CareerTeamDirectory.name(own.id, schools: schools))
                }
                LeagueStandingsBoard(rows: league.standings, ownTeamID: ownTeamID, schools: schools)
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
            if let season {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MY SEASON · 내 시즌 기록").font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    SeasonPersonalRecord(totals: season.totals, role: player.role, compact: true)
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
                    if let own = league.standings.first(where: { $0.id == ownTeamID }) {
                        LeagueOwnScorecard(row: own, name: name(own.id))
                    }
                    LeagueStandingsBoard(rows: league.standings, ownTeamID: ownTeamID, schools: schools)
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
                            if league.fixtures.count < 90 { Text("경력 시작 전이거나 현재 진로에서 출전 대상이 아닌 일정은 집계하지 않습니다.") }
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
                    Text("6팀 조별리그 · 팀당 연 30경기").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }
            }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(row.rank.map(String.init) ?? "—").font(.system(.largeTitle, design: .monospaced, weight: .black))
                    Text(row.rank == nil ? "집계 전" : "위").font(.caption.bold())
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

private struct LeagueStandingsBoard: View {
    let rows: [LeagueStanding]
    let ownTeamID: String
    let schools: [School]
    @Environment(\.dynamicTypeSize) private var typeSize
    private var expanded: Bool { typeSize >= .xxxLarge }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("LEAGUE").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text("순위 전광판").font(.headline)
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
                Text(result.map { $0.automatic ? "자동 결과" : "실제 경기" } ?? (pending ? "경기 진행 중" : "경기 대기"))
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
