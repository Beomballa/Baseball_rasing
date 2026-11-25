import SwiftUI

/// 원래 아홉 자리와 해당 표시 경계까지의 교체만 읽는다. 누적 타격 행을 선발 명단으로 쓰지 않는다.
struct MatchLineupComparison: Equatable {
    struct Rating: Equatable {
        let label: String
        let value: Double
    }
    struct Entry: Equatable {
        let playerID: String?
        let name: String
        let position: String?
        let note: String?
        let recorded: Bool
        var honors: [LeagueHonor] = []
        var ratings: [Rating] = []
        var season: MatchOpponentSeasonPlayer? = nil
        var through: String? = nil
        var honorsRecorded = false
        var honorsPending: String? = nil
        var uncollectedGames: Int? = nil
        var replacementRole: String? = nil
        var pitches: [String] = []
        var roleLabel: String? { replacementRole ?? position }
        static let missing = Self(playerID: nil, name: "선수 미기록", position: nil, note: nil, recorded: false)
    }
    struct Team: Equatable {
        let name: String
        let home: Bool
        let entries: [Entry]
        let attacking: Bool
        let order: Int
        let completed: Bool
        var teamID: String?
        var available: Bool { entries.contains { $0.recorded } }
        var role: String { completed ? "경기 종료" : attacking ? "공격 중" : "수비 중" }
        func status(slot: Int) -> String? {
            guard available, !completed else { return nil }
            if slot == order % 9 + 1 { return attacking ? "현재 타자" : "다음 공격 선두" }
            return attacking && slot == (order + 1) % 9 + 1 ? "다음 타자" : nil
        }
    }
    let context: String
    let home: Team
    let away: Team
    var available: Bool { home.available || away.available }

    init(match: CareerMatch, fixtureID: String?, careerName: String, homeName: String, awayName: String, gameDate: String? = nil) {
        context = match.completed ? "최종 타순" : "\(match.inningLabel) · \(match.outs)아웃"
        func reached(half: Int, order: Int) -> Bool {
            half < match.half || (half == match.half && order <= (half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder))
        }
        func team(_ isHome: Bool, name: String) -> Team {
            let records = isHome ? match.playerRecords?.home : match.playerRecords?.away
            let attack = match.npcAttack?.team(home: isHome)
            let fielders = match.npcFielders?.team(home: isHome)
            let indices = match.battingOrder.map { isHome ? $0.home : $0.away }
            let validIndices = indices.map { $0.count == 9 && Set($0) == Set(0..<9) } ?? true
            let fixtureMatches = fixtureID == nil || match.playerRecords == nil || fixtureID == match.playerRecords?.fixtureID
            let teamMatches = (records == nil || attack == nil || records?.teamID == attack?.teamID)
                && (records == nil || fielders == nil || records?.teamID == fielders?.teamID)
                && (attack == nil || fielders == nil || attack?.teamID == fielders?.teamID)
            let changes = (match.runnerManagement?.changes ?? records?.runnerChanges ?? []).filter {
                ($0.half % 2 == 1) == isHome && reached(half: $0.half, order: $0.order)
            }.sorted { $0.half == $1.half ? $0.order < $1.order : $0.half < $1.half }
            let pitchingChange: PitcherChange? = (match.pitching?.change(home: isHome)).flatMap {
                reached(half: $0.half, order: $0.order) ? $0 : nil
            }
            func playerName(_ id: String, fallback: String) -> String {
                if id == match.playerRecords?.careerID.uuidString, isHome == match.isHome { return careerName }
                if let player = attack?.batters.first(where: { $0.id == id }) { return player.displayName }
                if let pitcher = attack?.starter, pitcher.id == id { return pitcher.displayName }
                if let pitcher = attack?.relief, pitcher.id == id { return pitcher.displayName }
                let value = NPCIdentity.name(id)
                return value == "이름 미기록" ? fallback : value
            }
            func ratings(_ id: String?) -> [Rating] {
                guard let id else { return [] }
                var values: [Rating] = []
                func add(_ label: String, _ value: Double?) {
                    if let value { values.append(Rating(label: label, value: value)) }
                }
                if id == match.playerRecords?.careerID.uuidString, isHome == match.isHome {
                    if match.role == "pitcher" {
                        add("구속 능력", match.abilityStats?.velocity); add("제구", match.abilityStats?.control)
                        add("구위", match.abilityStats?.stuff); add("체력", match.abilityStats?.stamina)
                    } else {
                        add("컨택", match.contact); add("파워", match.power); add("선구안", match.discipline)
                    }
                    add("주력", match.fieldStats?.speed); add("수비", match.fieldStats?.defense)
                    add("송구", match.fieldStats?.arm); add("멘탈", match.abilityStats?.mental)
                } else if let reserve = match.runnerManagement?.reserve(home: isHome), reserve.id == id {
                    add("컨택", reserve.contact); add("파워", reserve.power); add("선구안", reserve.discipline)
                    add("주력", reserve.speed); add("수비", reserve.defense); add("송구", reserve.arm)
                } else {
                    if let pitcher = [attack?.starter, attack?.relief].compactMap({ $0 }).first(where: { $0.id == id }) {
                        add("구속 능력", pitcher.velocity); add("제구", pitcher.control)
                        add("구위", pitcher.profile?.stuff); add("체력", pitcher.profile?.stamina)
                        add("멘탈", pitcher.profile?.mental)
                    } else if let batter = attack?.batters.first(where: { $0.id == id }) {
                        add("컨택", batter.contact); add("파워", batter.power); add("선구안", batter.discipline)
                        add("출루 성향", batter.onBase); add("장타 성향", batter.slugging)
                        add("멘탈", batter.profile?.mental)
                    }
                    if let fielder = fielders?.players.first(where: { $0.id == id }) {
                        add("주력", fielder.speed); add("수비", fielder.defense); add("송구", fielder.arm)
                    }
                }
                return values
            }
            let entries: [Entry] = (0..<9).map { index in
                guard fixtureMatches, teamMatches, validIndices else { return .missing }
                let slot = index + 1
                let original: String
                let position: String
                if let records {
                    guard records.lineup.count == 9, Set(records.lineup).count == 9,
                          let row = records.batting.first(where: { $0.id == records.lineup[index] }), row.order == slot else { return .missing }
                    original = row.id; position = row.position
                    if let indices {
                        let expected = DetailedFieldRules.names[indices[index]]
                        guard position == expected else { return .missing }
                        if original == match.playerRecords?.careerID.uuidString, match.role == "batter" {
                            guard isHome == match.isHome, match.appearance, slot == 1,
                                  match.fieldStats?.position == expected else { return .missing }
                        } else if expected == "P" {
                            guard records.pitching.first?.id == original else { return .missing }
                        } else {
                            let source = attack?.batters.first(where: { $0.position == expected })?.id
                                ?? fielders?.players.first(where: { $0.position == expected })?.id
                            if let source, source != original { return .missing }
                        }
                    }
                } else {
                    // 옛 저장의 명시된 타순과 같은 경기 로스터만 사용한다. 기본 타순을 새로 계산하지 않는다.
                    guard let indices else { return .missing }
                    position = DetailedFieldRules.names[indices[index]]
                    if isHome == match.isHome, match.appearance,
                       (match.role == "batter" && slot == 1 || match.role == "pitcher" && position == "P") { return .missing }
                    let source = position == "P" ? attack?.starter.id
                        : attack?.batters.first(where: { $0.position == position })?.id
                    guard let id = source ?? fielders?.players.first(where: { $0.position == position })?.id else { return .missing }
                    original = id
                }
                if let change = changes.last(where: { $0.slot == slot && $0.original == original }) {
                    guard match.runnerManagement?.reserve(home: isHome).id == change.replacement
                        || records?.batting.contains(where: { $0.id == change.replacement && $0.order == slot }) == true else { return .missing }
                    let outgoing = playerName(original, fallback: "")
                    return Entry(playerID: change.replacement, name: playerName(change.replacement, fallback: "대주자"),
                                 position: nil, note: outgoing.isEmpty ? "대주자 투입" : outgoing + " 대신", recorded: true,
                                 replacementRole: "대주자")
                }
                let starter = records?.pitching.first?.id ?? attack?.starter.id
                if position == "P", original == starter, pitchingChange != nil {
                    let relief = records.flatMap { $0.pitching.count > 1 ? $0.pitching[1].id : nil } ?? attack?.relief.id
                    guard let relief else { return .missing }
                    let outgoing = playerName(original, fallback: "")
                    return Entry(playerID: relief, name: playerName(relief, fallback: "구원 투수"), position: "구원 투수",
                        note: outgoing.isEmpty ? "구원 등판" : outgoing + " 대신 등판", recorded: true)
                }
                return Entry(playerID: original, name: playerName(original, fallback: "선수 미기록"),
                             position: FieldPosition(rawValue: position)?.label ?? (position == "P" ? "투수" : nil), note: nil, recorded: true)
            }
            let teamID = records?.teamID ?? attack?.teamID ?? fielders?.teamID
            // 칭호는 이 경기 전날 고정본과 동일 팀·선수 ID가 검증될 때만 붙인다.
            let frozen: MatchOpponentSeason? = {
                if match.lineupSeasons != nil {
                    guard let gameDate, let date = try? GameDate(gameDate), let fixtureID,
                          fixtureMatches, teamMatches,
                          let seasons = try? match.validatedLineupSeasons(on: date, fixtureID: fixtureID) else { return nil }
                    return seasons.first { $0.teamID == teamID }
                }
                return match.preparation.flatMap { preparation -> MatchOpponentSeason? in
                guard let season = preparation.season, let gameDate, let date = try? GameDate(gameDate),
                      fixtureMatches, teamMatches, preparation.fixtureID == fixtureID, (try? season.validate(analysis: preparation.analysis, date: date)) != nil else { return nil }
                return season
                }
            }()
            let decorated = entries.map { entry in
                var value = entry
                value.honors = (frozen?.honors ?? []).filter {
                    entry.recorded && $0.teamID == teamID && $0.playerID == entry.playerID
                }
                value.ratings = entry.recorded ? ratings(entry.playerID) : []
                value.season = entry.recorded ? frozen?.player(entry.playerID ?? "") : nil
                value.through = frozen?.through
                value.honorsRecorded = frozen?.honors != nil
                value.honorsPending = frozen?.honorsPending
                value.uncollectedGames = frozen?.uncollectedGames
                if entry.playerID == match.playerRecords?.careerID.uuidString, match.role == "pitcher", isHome == match.isHome {
                    value.pitches = match.mastery.keys.sorted()
                } else if let pitcher = [attack?.starter, attack?.relief].compactMap({ $0 }).first(where: { $0.id == entry.playerID }) {
                    value.pitches = pitcher.pitches
                }
                return value
            }
            return Team(name: name, home: isHome, entries: decorated, attacking: !match.half.isMultiple(of: 2) == isHome,
                        order: isHome ? match.homeOrder : match.awayOrder, completed: match.completed, teamID: teamMatches ? teamID : nil)
        }
        home = team(true, name: homeName); away = team(false, name: awayName)
    }
}

struct MatchLineupComparisonView: View {
    let comparison: MatchLineupComparison
    var schools: [School] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 116
    private struct Selection: Identifiable {
        let team: MatchLineupComparison.Team
        let slot: Int
        var entry: MatchLineupComparison.Entry { team.entries[slot - 1] }
        var id: String { (team.home ? "home/" : "away/") + String(slot) }
    }
    @State private var selection: Selection?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("타순").font(.headline).foregroundStyle(GameTheme.gold)
            Text(comparison.context).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                .accessibilityIdentifier("gameLineupContext")
            if comparison.available {
                let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                header {
                    teamHeading(comparison.home)
                    teamHeading(comparison.away)
                }.padding(.leading, typeSize.isAccessibilitySize ? 0 : 28)
                ForEach(1...9, id: \.self) { slot in
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(slot)").font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                                .frame(minWidth: 20).accessibilityLabel("\(slot)번 타순")
                            if typeSize.isAccessibilitySize {
                                stackedPair(slot: slot)
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .top, spacing: 8) {
                                        cell(comparison.home, slot: slot).frame(minWidth: columnWidth)
                                        cell(comparison.away, slot: slot).frame(minWidth: columnWidth)
                                    }
                                    stackedPair(slot: slot)
                                }
                            }
                        }
                        Rectangle().fill(GameTheme.boardLine.opacity(0.6)).frame(height: 1).accessibilityHidden(true)
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("gameLineupRow-\(slot)")
                }
            } else {
                Text("이 경기에는 타순 기록이 없습니다.").font(.body)
                    .accessibilityIdentifier("gameLineupMissing")
            }
        }.padding(12).background(GameTheme.boardPanel)
            .foregroundStyle(GameTheme.boardInk)
            .accessibilityElement(children: .contain).accessibilityIdentifier("gameLineupComparison")
            .sheet(item: $selection) { selected in
                MatchLineupPlayerDetail(entry: selected.entry, team: selected.team, slot: selected.slot, schools: schools)
            }
    }
    private func teamHeading(_ team: MatchLineupComparison.Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MatchTeamCrest(teamID: team.teamID, name: team.name, schools: schools)
                .frame(width: 32, height: 32).accessibilityIdentifier("gameLineupCrest-" + (team.home ? "home" : "away"))
            Text((team.home ? "홈 · " : "원정 · ") + team.name).font(.headline)
            Text(team.available ? team.role : "타순 미기록").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
    private func stackedPair(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("홈 · " + comparison.home.name).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            cell(comparison.home, slot: slot)
            Text("원정 · " + comparison.away.name).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            cell(comparison.away, slot: slot)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func cell(_ team: MatchLineupComparison.Team, slot: Int) -> some View {
        let entry = team.entries[slot - 1], status = team.status(slot: slot)
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(entry.name).font(.body.weight(.semibold))
            if let position = entry.roleLabel { Text(position).font(.subheadline).foregroundStyle(GameTheme.boardMuted) }
            if let note = entry.note { Text(note).font(.subheadline).foregroundStyle(GameTheme.boardMuted) }
            if let status {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: status == "현재 타자" ? "diamond.fill" : status == "다음 타자" ? "diamond" : "arrow.turn.up.right")
                        .font(.caption.bold()).frame(width: 14, height: 18).accessibilityHidden(true)
                    Text(status).font(.subheadline.weight(.semibold))
                }.foregroundStyle(GameTheme.gold)
            }
            ForEach(entry.honors) { honor in
                LeagueHonorBadge(honor: honor).accessibilityIdentifier("gameLineupHonor-" + honor.id)
            }
            if entry.recorded { Text("선수 정보 ›").font(.caption).foregroundStyle(GameTheme.gold) }
        }.fixedSize(horizontal: false, vertical: true)
            .padding(8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(status == "현재 타자" ? GameTheme.board : .clear)
        return Button { selection = Selection(team: team, slot: slot) } label: { content }
            .buttonStyle(.plain).disabled(!entry.recorded)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(([team.name, "\(slot)번", entry.name, entry.roleLabel, entry.note, status].compactMap { $0 }
                + entry.honors.map { $0.label + " " + $0.number }).joined(separator: ", "))
            .accessibilityHint(entry.recorded ? "경기 시작 기량과 경기 전 성적 보기" : "선수 정보 미기록")
            .accessibilityIdentifier("gameLineup-\(team.home ? "home" : "away")-\(slot)")
    }
}

/// 경기 스냅샷의 값만 표시한다. 현재 선수나 시즌 원장을 다시 조회하지 않는다.
private struct MatchLineupPlayerDetail: View {
    let entry: MatchLineupComparison.Entry
    let team: MatchLineupComparison.Team
    let slot: Int
    let schools: [School]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.adaptive(minimum: 104), alignment: .leading)]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        MatchTeamCrest(teamID: team.teamID, name: team.name, schools: schools).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text((team.home ? "홈 · " : "원정 · ") + team.name).font(.subheadline)
                            Text(entry.name).font(.title2.bold())
                            Text("\(slot)번 · " + (entry.roleLabel ?? "포지션 미기록")).font(.body)
                            if let note = entry.note { Text(note).font(.subheadline) }
                            if let status = team.status(slot: slot) { Text(status).foregroundStyle(GameTheme.gold) }
                        }
                    }
                    section("칭호") {
                        if entry.honors.isEmpty {
                            Text(entry.honorsPending.map { "칭호 집계 보류 · " + $0 }
                                ?? (entry.honorsRecorded ? "경기 전 확인된 선두 칭호 없음" : "경기 전 칭호 미기록"))
                                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        } else { ForEach(entry.honors) { LeagueHonorBadge(honor: $0) } }
                    }
                    section("경기 시작 기량") {
                        if entry.ratings.isEmpty { Text("기량 미기록") }
                        else {
                            Text("능력치 · 0~100 · 저장된 항목만 표시").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(entry.ratings, id: \.label) { rating in
                                    metric(rating.label, String(format: "%.1f", rating.value))
                                }
                            }
                            if !entry.pitches.isEmpty {
                                Text("보유 구종 · " + entry.pitches.map { PitchType(rawValue: $0)?.label ?? $0 }.joined(separator: " · "))
                                    .font(.subheadline)
                            }
                        }
                    }
                    section("경기 전 성적") {
                        if let through = entry.through {
                            Text(through + "까지 완료된 경기").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                                .accessibilityIdentifier("lineupDetailThrough")
                        }
                        if let row = entry.season {
                            if entry.position?.contains("투수") == true {
                                Text("\(row.pitchingGames)경기 · \(row.pitching.innings)이닝").font(.subheadline)
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                    metric("승리 · W", row.value("W")); metric("ERA", row.value("ERA"))
                                    metric("WHIP", row.value("WHIP")); metric("K/9", row.value("K/9"))
                                }
                            } else {
                                Text("\(row.battingGames)경기 · \(row.batting.plateAppearances)타석").font(.subheadline)
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                    metric("타율 · AVG", row.value("AVG")); metric("OPS", row.value("OPS"))
                                    metric("출루율 · OBP", row.value("OBP")); metric("장타율 · SLG", row.value("SLG"))
                                    metric("홈런 · HR", row.value("HR"))
                                }
                            }
                        } else {
                            Text(entry.through == nil ? "이 경기의 경기 전 성적 미기록" : "경기 전 개인 성적 미집계")
                                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        }
                        if let count = entry.uncollectedGames, count > 0 {
                            Text("개인 성적 미수집 \(count)경기 · 칭호 집계 보류").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                }.padding(16)
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .navigationTitle("선수 정보").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("닫기") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("closeLineupPlayerDetail")
                    }
                }
                .accessibilityIdentifier("gameLineupPlayerDetail")
        }
    }
    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            Text(value).font(.body.monospacedDigit().weight(.semibold))
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(GameTheme.gold)
            content()
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
    }
}

/// 학교·프로 구단이 이미 사용하는 원본 로고를 조회하며, 누락 자료는 중립 야구공으로 표시한다.
struct MatchTeamCrest: View {
    let teamID: String?
    let name: String
    let schools: [School]
    var body: some View {
        if let teamID, let identity = ClubIdentity.resolve(teamID: teamID) {
            Image(identity.asset).resizable().interpolation(.none).scaledToFit().accessibilityLabel(name + " 엠블럼")
        } else {
            SchoolCrest(school: schools.first { $0.id == teamID } ?? School(id: teamID ?? "", region: "", name: name))
        }
    }
}
