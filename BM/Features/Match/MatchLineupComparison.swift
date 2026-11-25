import SwiftUI

/// 원래 아홉 자리와 해당 표시 경계까지의 교체만 읽는다. 누적 타격 행을 선발 명단으로 쓰지 않는다.
struct MatchLineupComparison: Equatable {
    struct Entry: Equatable {
        let playerID: String?
        let name: String
        let position: String?
        let note: String?
        let recorded: Bool
        var honors: [LeagueHonor] = []
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
                                 position: nil, note: outgoing.isEmpty ? "대주자 투입" : outgoing + " 대신", recorded: true)
                }
                let starter = records?.pitching.first?.id ?? attack?.starter.id
                if position == "P", original == starter, pitchingChange != nil {
                    let relief = records.flatMap { $0.pitching.count > 1 ? $0.pitching[1].id : nil } ?? attack?.relief.id
                    guard let relief else { return .missing }
                    return Entry(playerID: relief, name: playerName(relief, fallback: "구원 투수"), position: "구원 투수", note: nil, recorded: true)
                }
                return Entry(playerID: original, name: playerName(original, fallback: "선수 미기록"),
                             position: FieldPosition(rawValue: position)?.label ?? (position == "P" ? "투수" : nil), note: nil, recorded: true)
            }
            let teamID = records?.teamID ?? attack?.teamID ?? fielders?.teamID
            // 칭호는 이 경기 전날 고정본과 동일 팀·선수 ID가 검증될 때만 붙인다.
            let frozen = match.preparation.flatMap { preparation -> MatchOpponentSeason? in
                guard let season = preparation.season, let gameDate, let date = try? GameDate(gameDate),
                      fixtureMatches, teamMatches, preparation.fixtureID == fixtureID, (try? season.validate(analysis: preparation.analysis, date: date)) != nil else { return nil }
                return season
            }
            let decorated = entries.map { entry in
                var value = entry
                value.honors = (frozen?.honors ?? []).filter {
                    entry.recorded && $0.teamID == teamID && $0.playerID == entry.playerID
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
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.name).font(.body.weight(.semibold))
            if let position = entry.position { Text(position).font(.subheadline).foregroundStyle(GameTheme.boardMuted) }
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
        }.fixedSize(horizontal: false, vertical: true)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(status == "현재 타자" ? GameTheme.board : .clear)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(([team.name, "\(slot)번", entry.name, entry.position, entry.note, status].compactMap { $0 }
                + entry.honors.map { $0.label + " " + $0.number }).joined(separator: ", "))
            .accessibilityIdentifier("gameLineup-\(team.home ? "home" : "away")-\(slot)")
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
