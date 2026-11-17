import Foundation

/// Raw completed-game counts frozen before first pitch. Unknown legacy coverage stays explicit.
struct MatchOpponentSeason: Codable, Equatable {
    let version: Int
    let year: Int
    let competition: String
    let teamID: String
    let through: String
    let uncollectedGames: Int
    let players: [MatchOpponentSeasonPlayer]
    var pitchHistory:[OpponentPitchHistory]? = nil
    var honors: [LeagueHonor]? = nil

    func player(_ id: String) -> MatchOpponentSeasonPlayer? { players.first { $0.id == id } }
    func validate(analysis: MatchOppositionAnalysis, date: GameDate) throws {
        guard version == 1, year == date.year, teamID == analysis.teamID,
              competition == analysis.attack?.competition, try GameDate(through) == date.adding(days: -1),
              uncollectedGames >= 0, Set(players.map(\.id)).count == players.count else { throw MatchError.invalidRecord }
        if let honors {
            guard Set(honors.map(\.id)).count == honors.count,
                  honors.allSatisfy({ $0.version == 1 && $0.teamID == teamID && $0.value.isFinite && $0.value >= 0 }) else { throw MatchError.invalidRecord }
            for honor in honors {
                guard let row = player(honor.playerID) else { throw MatchError.invalidRecord }
                let actual: Double? = switch honor.kind {
                case .average: row.batting.average
                case .homeRuns: Double(row.batting.homeRuns)
                case .strikeouts: Double(row.pitching.strikeouts)
                case .era: row.pitching.era
                case .wins: row.wins.map(Double.init)
                }
                guard actual.map({ abs($0 - honor.value) < 0.000000001 }) == true else { throw MatchError.invalidRecord }
            }
        }
        for history in pitchHistory ?? [] {try history.validate()}
        for player in players {
            guard player.battingGames >= 0, player.pitchingGames >= 0,
                  player.earnedRunGames >= 0, player.unscoredPitchingGames >= 0,
                  player.earnedRunGames + player.unscoredPitchingGames == player.pitchingGames,
                  player.wins.map({(0...player.pitchingGames).contains($0)}) ?? true else { throw MatchError.invalidRecord }
            try player.batting.validate(); try player.pitching.validate()
        }
    }
}
struct MatchOpponentSeasonPlayer: Codable, Equatable {
    let id: String
    let battingGames: Int
    let pitchingGames: Int
    let earnedRunGames: Int
    let unscoredPitchingGames: Int
    let batting: MatchBattingCounts
    let pitching: MatchPitchingCounts
    var wins: Int? = nil
    func value(_ label: String) -> String {
        func rate(_ value: Double?, digits: Int = 3) -> String { value.map { String(format: "%.*f", digits, $0) } ?? "미집계" }
        switch label {
        case "AVG": return rate(batting.average)
        case "OBP": return rate(batting.onBasePercentage)
        case "SLG": return rate(batting.sluggingPercentage)
        case "OPS": return rate(batting.ops)
        case "HR": return batting.plateAppearances > 0 ? String(batting.homeRuns) : "미집계"
        case "W": return wins.map(String.init) ?? "미집계"
        case "ER": return pitchingGames > 0 ? pitching.earnedRuns.map(String.init) ?? "미집계" : "미집계"
        case "ERA": return rate(pitching.era, digits: 2)
        case "WHIP": return rate(pitching.outs > 0 ? Double(pitching.hits + pitching.walks) * 3 / Double(pitching.outs) : nil, digits: 2)
        case "K/9": return rate(pitching.outs > 0 ? Double(pitching.strikeouts) * 27 / Double(pitching.outs) : nil, digits: 1)
        default: return "미집계"
        }
    }
}


struct PitchUsage:Codable,Equatable,Identifiable {
    let code:String
    var count=0
    var speedSum=0.0
    var low=300.0,high=0.0
    var id:String {code}
    var average:Double {count == 0 ? 0:speedSum/Double(count)}
}
struct OpponentPitchHistory:Codable,Equatable {
    let pitcherID:String
    var games=0,recordedGames=0
    var usage:[PitchUsage]=[]
    var zone=Array(repeating:0,count:10)
    var zoneInside=0
    var total:Int {usage.reduce(0,{$0+$1.count})}
    var located:Int {zone.reduce(0,+)}
    mutating func add(_ pitch:ObservedPitch) {
        if !usage.contains(where:{$0.code == pitch.code}) {usage.append(PitchUsage(code:pitch.code))}
        let i=usage.firstIndex(where:{$0.code == pitch.code})!
        usage[i].count+=1;usage[i].speedSum+=pitch.speed;usage[i].low=min(usage[i].low,pitch.speed);usage[i].high=max(usage[i].high,pitch.speed)
        if pitch.inZone == true {zoneInside+=1}
        if let x=pitch.x,let y=pitch.y {
            let cell=ManualMatchRules.isStrike(x:x,y:y) ? min(2,max(0,Int((y-0.2)/0.6*3)))*3+min(2,max(0,Int((x-0.2)/0.6*3))):9
            zone[cell]+=1
        }
        usage.sort {$0.code<$1.code}
    }
    func validate() throws {
        guard !pitcherID.isEmpty,games>=0,(0...games).contains(recordedGames),zone.count == 10,zone.allSatisfy({$0>=0}),located<=total,(0...total).contains(zoneInside),Set(usage.map(\.code)).count == usage.count else {throw MatchError.invalidRecord}
        for u in usage {guard PitchType(rawValue:u.code) != nil,u.count>0,[u.speedSum,u.low,u.high].allSatisfy(\.isFinite),u.low>0,u.high<=300,u.low<=u.average+0.00001,u.average<=u.high+0.00001 else {throw MatchError.invalidRecord}}
    }
}

/// Fictional identities use a separate, versioned hash namespace; simulation RNG is never advanced.
enum NPCIdentity {
    static let koreanLast = ["김","이","박","최","정","강","조","윤","장","임","한","오","서","신","권","황","안","송","류","홍","전","고","문","양","손","배","백","허","유","남"]
    static let koreanFirst = ["도윤","시우","준서","지호","서준","민재","현우","지훈","건우","우진","태윤","승민","유찬","도현","주원","정우","하준","예준","성민","태현","재원","승현","동혁","준혁","성준","정훈","찬우","수현","강민","시현","현준","준영","지환","민규","상우","진우","연우","이준","태민","도하"]
    static let japanLast = ["사토","스즈키","다나카","와타나베","이토","야마모토","나카무라","고바야시","가토","요시다","야마다","사사키","야마구치","마쓰모토","이노우에","기무라","하야시","시미즈","사이토","모리"]
    static let japanFirst = ["하루토","유토","렌","소타","코타","다이키","쇼타","타쿠미","류세이","카이토","히로키","료","켄타","신야","유키","나오키","소라","아키라","준","테츠야"]
    static let americaLast = ["밀러","존슨","데이비스","윌슨","가르시아","로드리게스","마르티네스","앤더슨","토머스","잭슨","화이트","해리스","클라크","루이스","워커","영","킹","라이트","로페즈","힐","그린","애덤스","베이커","넬슨"]
    static let americaFirst = ["루카스","마커스","다니엘","노아","이선","잭","올리버","제이든","레오","메이슨","로건","라이언","카를로스","디에고","미겔","호세","가브리엘","마테오","타일러","코너","에런","브랜던","데빈","콜"]
    static func name(_ id: String) -> String {
        let p = id.split(separator: "/").map(String.init)
        guard p.count >= 5, p[0] == "npc-v1", let slot = DetailedFieldRules.names.firstIndex(of: p[4]) else { return "이름 미기록" }
        let index = p.count > 5 && p[5] == "relief" ? 9 : slot
        let region = p[1].hasPrefix("npb") ? "jp" : p[1].hasPrefix("mlb") ? "us" : "kr"
        let last = region == "jp" ? japanLast : region == "us" ? americaLast : koreanLast
        let first = region == "jp" ? japanFirst : region == "us" ? americaFirst : koreanFirst
        // Year/level changes retain the same team-slot name. P and P/starter denote the same player.
        let value = (Int(MatchNPCFielders.hash("npc-name-v1/" + region + "/" + p[3]) % UInt64(last.count * first.count)) + index * 37) % (last.count * first.count)
        return region == "us" ? first[value % first.count] + " " + last[value / first.count] : last[value / first.count] + first[value % first.count]
    }
}
extension MatchNPCBatter { var displayName: String { name ?? NPCIdentity.name(id) } }
extension MatchNPCPitcher { var displayName: String { name ?? NPCIdentity.name(id) } }
extension MatchNPCPlayer { var displayName: String { NPCIdentity.name(id) } }

struct LeagueHonor: Codable, Equatable, Identifiable {
    var version = 1
    enum Kind: String, Codable, CaseIterable { case average, homeRuns, strikeouts, era, wins
        var label: String { switch self { case .average: "타율"; case .homeRuns: "홈런"; case .strikeouts: "탈삼진"; case .era: "ERA"; case .wins: "다승" } }
    }
    let playerID: String
    let teamID: String
    let kind: Kind
    let value: Double
    let tied: Bool
    let final: Bool
    var id: String { kind.rawValue + "/" + teamID + "/" + playerID }
    var label: String { (tied ? "공동 " : "") + kind.label + (final ? " 1위" : " 선두") }
    var number: String { String(format: kind == .average ? "%.3f" : kind == .era ? "%.2f" : "%.0f", value) }
}

enum LeagueHonorRules {
    /// Display-only explanation of the same coverage gate used by leaders().
    static func pendingReason(_ ledger: SeasonPlayerLedger, requiredFixtureIDs: Set<String>, teamCount: Int = 6) -> String? {
        if ledger.uncollectedGames > 0 { return "개인 성적 미수집 \(ledger.uncollectedGames)경기 · 과거 기록을 추정하지 않아 선두를 보류합니다." }
        let missing = requiredFixtureIDs.subtracting(ledger.fixtureIDs).count
        if missing > 0 { return "지난 일정 중 개인 기록 확인이 필요한 \(missing)경기 · 선두 집계 보류" }
        let teams = ledger.teamGames.values.filter { $0 > 0 }.count
        if teams < teamCount { return "리그 기록 \(teams)/\(teamCount)팀 · 모든 팀의 경기 기록을 기다립니다." }
        if leaders(ledger, requiredFixtureIDs: requiredFixtureIDs, teamCount: teamCount).isEmpty {
            return "규정 표본 또는 양수 기록을 충족한 선수가 아직 없습니다. 아래 기준을 확인하세요."
        }
        return nil
    }

    // Short-season game rules: rates need 15 PA / 3 IP minimum as well as proportional qualification.
    static func leaders(_ ledger: SeasonPlayerLedger, requiredFixtureIDs: Set<String>? = nil, teamCount: Int = 6) -> [LeagueHonor] {
        guard ledger.uncollectedGames == 0, ledger.teamGames.count == teamCount, ledger.teamGames.values.allSatisfy({$0 > 0}) else { return [] }
        if let requiredFixtureIDs, !requiredFixtureIDs.isSubset(of: Set(ledger.fixtureIDs)) { return [] }
        let final = ledger.teamGames.values.allSatisfy { $0 == 30 }
        return LeagueHonor.Kind.allCases.flatMap { kind -> [LeagueHonor] in
            let eligible = ledger.players.compactMap { row -> (SeasonPlayerRecord, Double)? in
                let games = ledger.teamGames[row.teamID] ?? 0
                switch kind {
                case .average:
                    guard row.batting.plateAppearances >= max(15, Int(ceil(Double(games) * 3.1))), let value = row.batting.average else { return nil }
                    return (row, value)
                case .wins:
                    guard ledger.unscoredDecisionGames == 0, row.unscoredDecisionGames == 0, row.wins > 0 else { return nil }
                    return (row,Double(row.wins))
                case .homeRuns: return row.batting.homeRuns > 0 ? (row, Double(row.batting.homeRuns)) : nil
                case .strikeouts: return row.pitching.strikeouts > 0 ? (row, Double(row.pitching.strikeouts)) : nil
                case .era:
                    guard row.pitching.outs >= max(9, games * 3), row.unscoredPitchingGames == 0, let value = row.pitching.era else { return nil }
                    return (row, value)
                }
            }
            guard let best = (kind == .era ? eligible.map(\.1).min() : eligible.map(\.1).max()) else { return [] }
            if kind == .average && best <= 0 { return [] }
            let winners = eligible.filter { abs($0.1 - best) < 0.000000001 }.sorted { $0.0.id < $1.0.id }
            return winners.map { LeagueHonor(playerID: $0.0.id, teamID: $0.0.teamID, kind: kind, value: $0.1, tied: winners.count > 1, final: final) }
        }
    }
}

struct CareerSeasonAwardRecord: Codable, Equatable, Identifiable {
    var version = 1
    let playerID: UUID
    let year: Int
    let competition: String
    let date: String
    let teamID: String
    let teamIDs: [String]
    let fixtureIDs: [String]
    let honors: [LeagueHonor]
    var bestNine: LeagueBestNine? = nil
    var goldGlove: LeagueGoldGlove? = nil

    var id: String { "\(playerID.uuidString)/\(year)/\(competition)" }
    var leagueLabel: String { Self.leagueLabel(competition) }
    var personalHonors: [LeagueHonor] { honors.filter { $0.playerID == playerID.uuidString && $0.teamID == teamID } }
    var unresolvedKinds: [LeagueHonor.Kind] { LeagueHonor.Kind.allCases.filter { kind in !honors.contains { $0.kind == kind } } }

    static func leagueLabel(_ competition: String) -> String {
        switch competition {
        case "highschool": "고교"
        case "domestic-first-team": "KBO"
        case "npb-first-team": "NPB"
        case "mlb-first-team": "MLB"
        default: "리그"
        }
    }

    static func supports(_ competition: String) -> Bool {
        ["highschool", "domestic-first-team", "npb-first-team", "mlb-first-team"].contains(competition)
    }

    static func make(ledger: SeasonPlayerLedger, teamID: String, teamIDs: [String],
                     fixtures: [SeasonFixture]) throws -> Self? {
        guard supports(ledger.competition), allowedTeamCounts(ledger.competition).contains(teamIDs.count),
              Set(teamIDs).count == teamIDs.count, teamIDs.contains(teamID),
              fixtures.count == teamIDs.count * 15, ledger.uncollectedGames == 0 else { return nil }
        guard let first = fixtures.map(\.date).min(), let last = fixtures.map(\.date).max(),
              first == (try GameDate(String(format: "%04d-04-01", ledger.year))),
              last == first.adding(days: 174) else { return nil }
        let fixtureIDs = Set(fixtures.map(\.id))
        guard fixtureIDs.count == fixtures.count, ledger.fixtureIDs.count == fixtures.count,
              Set(ledger.fixtureIDs) == fixtureIDs else { return nil }
        let scheduledGames = Dictionary(grouping: fixtures.flatMap { [$0.homeID, $0.awayID] }, by: { $0 }).mapValues(\.count)
        guard Set(scheduledGames.keys) == Set(teamIDs), scheduledGames.values.allSatisfy({ $0 == 30 }),
              ledger.teamGames == scheduledGames else { return nil }

        // If a qualifying pitcher's earned runs are unknown, we cannot establish the ERA winner.
        let incompleteERA = ledger.players.contains { row in
            row.pitching.outs >= 90 && (row.unscoredPitchingGames > 0 || row.pitching.earnedRuns == nil)
        }
        let honors = LeagueHonorRules.leaders(ledger, requiredFixtureIDs: fixtureIDs, teamCount: teamIDs.count)
            .filter { !incompleteERA || $0.kind != .era }
        let date = last.adding(days: 1)
        let record = Self(playerID: ledger.careerID, year: ledger.year, competition: ledger.competition,
                          date: date.description, teamID: teamID, teamIDs: teamIDs.sorted(),
                          fixtureIDs: fixtureIDs.sorted(), honors: honors, bestNine: LeagueBestNine.make(ledger),
                          goldGlove: LeagueGoldGlove.make(ledger))
        try record.validate(playerID: ledger.careerID, today: date)
        return record
    }

    func validate(playerID: UUID, today: GameDate) throws {
        let prefix = String(format: "%04d-", year)
        let date = try GameDate(self.date)
        let opening = try GameDate(prefix + "04-01")
        let firstFixtureDate = opening.description
        guard version == 1, self.playerID == playerID, Self.supports(competition),
              Self.allowedTeamCounts(competition).contains(teamIDs.count),
              !teamIDs.contains(where: \.isEmpty), teamIDs == Set(teamIDs).sorted(), teamIDs.contains(teamID),
              date == opening.adding(days: 175), date <= today,
              fixtureIDs.count == teamIDs.count * 15, fixtureIDs == Set(fixtureIDs).sorted(),
              fixtureIDs.allSatisfy({ $0.prefix(10) >= firstFixtureDate && $0.prefix(10) < self.date }),
              Set(honors.map(\.id)).count == honors.count else { throw CareerPathError.invalid }
        if competition != "highschool" {
            let leagueTeams = CareerTeamDirectory.teams(level: competition, expanded: teamIDs.count != 6)
            guard teamIDs == leagueTeams.sorted() else { throw CareerPathError.invalid }
        }
        try bestNine?.validate(teamIDs: teamIDs)
        try goldGlove?.validate(competition: competition, teamIDs: teamIDs)
        let byKind = Dictionary(grouping: honors, by: \.kind)
        for (kind, group) in byKind {
            guard let value = group.first?.value, value.isFinite, value >= 0,
                  kind != .average || value <= 1,
                  kind == .average || kind == .era || (value > 0 && value.rounded() == value),
                  group.allSatisfy({ $0.version == 1 && !$0.playerID.isEmpty && $0.final && teamIDs.contains($0.teamID)
                      && abs($0.value - value) < 0.000000001 && $0.tied == (group.count > 1) }) else {
                throw CareerPathError.invalid
            }
        }
    }

    private static func allowedTeamCounts(_ competition: String) -> [Int] {
        switch competition {
        case "highschool": [6]
        case "domestic-first-team": [6, 10]
        case "npb-first-team", "mlb-first-team": [6, 15]
        default: []
        }
    }
}

struct LeagueBestNine: Codable, Equatable {
    var version = 1
    let slots: [Slot]

    enum Position: String, Codable, CaseIterable, Identifiable {
        case pitcher = "P", catcher = "C", first = "1B", second = "2B", third = "3B"
        case shortstop = "SS", left = "LF", center = "CF", right = "RF"

        var id: String { rawValue }
        var label: String { FieldPosition(rawValue: rawValue)?.label ?? PlayerRole.pitcher.label }
    }

    enum HoldReason: String, Codable {
        case missingDefensiveCoverage
        case missingEarnedRunCoverage
        case noEligiblePlayer

        var label: String {
            switch self {
            case .missingDefensiveCoverage: "포지션별 수비 원장을 확인할 수 없어 선정을 보류했습니다."
            case .missingEarnedRunCoverage: "규정 이닝에 도달한 투수의 자책점 기록이 부족해 선정을 보류했습니다."
            case .noEligiblePlayer: "이 포지션의 출전 기준을 충족한 선수가 없습니다."
            }
        }
    }

    struct Slot: Codable, Equatable, Identifiable {
        let position: Position
        let winner: Winner?
        let reason: HoldReason?

        var id: String { position.rawValue }
    }

    struct Winner: Codable, Equatable {
        let teamID: String
        let playerID: String
        let evidence: Evidence
    }

    enum Evidence: Codable, Equatable {
        case pitcher(PitcherEvidence)
        case fielder(FielderEvidence)

        var sampleSummary: String {
            switch self {
            case .pitcher(let sample):
                "등판 \(sample.games)경기 · \(LeagueBestNine.innings(sample.outs)) 투구"
            case .fielder(let sample):
                "수비 \(sample.games)경기 · \(LeagueBestNine.innings(sample.outs)) · \(sample.plateAppearances)타석"
            }
        }

        var rankingSummary: String {
            switch self {
            case .pitcher(let sample):
                "ERA \(String(format: "%.2f", sample.era)) · 탈삼진 \(sample.strikeouts)개"
            case .fielder(let sample):
                "OPS \(String(format: "%.3f", Double(sample.rankedOPS) / 1_000)) · 홈런 \(sample.homeRuns)개"
            }
        }

        var summary: String { sampleSummary + " · " + rankingSummary }
    }

    struct PitcherEvidence: Codable, Equatable {
        let games: Int
        let outs: Int
        let earnedRuns: Int
        let strikeouts: Int

        var era: Double { Double(earnedRuns) * 27 / Double(outs) }
    }

    struct FielderEvidence: Codable, Equatable {
        let games: Int
        let outs: Int
        let plateAppearances: Int
        let ops: Double
        let homeRuns: Int

        var rankedOPS: Int { Int((ops * 1_000).rounded()) }
    }

    static let minimumOutsPerTeamGame = 15
    static let minimumPlateAppearancesPerTeamGame = 2
    static let minimumPitchingOutsPerTeamGame = 3

    static let fieldingCriteria = "주 포지션 수비 팀 경기당 5이닝 · 공격 팀 경기당 2타석"
    static let pitchingCriteria = "투구 팀 경기당 1이닝 · 자책점 집계 완료"
    static let primaryPositionRule = "수비 이닝이 가장 많은 포지션에서만 평가합니다. 같으면 수비 경기 수, 포지션 표시 순으로 결정합니다."
    static let fieldingRanking = "OPS(소수 셋째 자리), 홈런, 해당 포지션의 수비 이닝 순"
    static let pitchingRanking = "낮은 ERA, 탈삼진, 투구 이닝 순"
    static let finalTieRule = "성적이 모두 같으면 구단 ID, 선수 ID 순으로 한 명을 선정합니다."

    static func make(_ ledger: SeasonPlayerLedger) -> Self {
        let pitching = selectPitcher(in: ledger)
        let positions = Position.allCases.dropFirst()
        guard ledger.unverifiedFieldingGames == 0 else {
            return Self(slots: [pitching] + positions.map {
                Slot(position: $0, winner: nil, reason: .missingDefensiveCoverage)
            })
        }
        var fielders: [Position: [(record: SeasonPlayerRecord, sample: FielderEvidence)]] = [:]
        for player in ledger.players where player.id != pitching.winner?.playerID {
            guard let teamGames = ledger.teamGames[player.teamID], teamGames > 0,
                  let primary = primaryPosition(player.fielding),
                  primary.sample.outs >= teamGames * minimumOutsPerTeamGame,
                  player.batting.plateAppearances >= teamGames * minimumPlateAppearancesPerTeamGame,
                  let ops = player.batting.ops else { continue }
            let sample = FielderEvidence(games: primary.sample.games, outs: primary.sample.outs,
                                         plateAppearances: player.batting.plateAppearances,
                                         ops: ops, homeRuns: player.batting.homeRuns)
            fielders[primary.position, default: []].append((player, sample))
        }
        let fielding = positions.map { position in
            let selected = fielders[position]?.min { left, right in
                if left.sample.rankedOPS != right.sample.rankedOPS { return left.sample.rankedOPS > right.sample.rankedOPS }
                if left.sample.homeRuns != right.sample.homeRuns { return left.sample.homeRuns > right.sample.homeRuns }
                if left.sample.outs != right.sample.outs { return left.sample.outs > right.sample.outs }
                return (left.record.teamID, left.record.id) < (right.record.teamID, right.record.id)
            }
            guard let selected else { return Slot(position: position, winner: nil, reason: .noEligiblePlayer) }
            return Slot(position: position, winner: Winner(teamID: selected.record.teamID, playerID: selected.record.id,
                                                            evidence: .fielder(selected.sample)), reason: nil)
        }
        return Self(slots: [pitching] + fielding)
    }

    private static func selectPitcher(in ledger: SeasonPlayerLedger) -> Slot {
        let eligible = ledger.players.filter { player in
            guard let teamGames = ledger.teamGames[player.teamID], teamGames > 0 else { return false }
            return player.pitchingGames > 0 && player.pitching.outs >= teamGames * minimumPitchingOutsPerTeamGame
        }
        guard !eligible.contains(where: { $0.unscoredPitchingGames > 0 || $0.pitching.earnedRuns == nil }) else {
            return Slot(position: .pitcher, winner: nil, reason: .missingEarnedRunCoverage)
        }
        let candidates = eligible.compactMap { player -> (record: SeasonPlayerRecord, sample: PitcherEvidence)? in
            guard let earnedRuns = player.pitching.earnedRuns else { return nil }
            let sample = PitcherEvidence(games: player.pitchingGames, outs: player.pitching.outs,
                                         earnedRuns: earnedRuns, strikeouts: player.pitching.strikeouts)
            return (player, sample)
        }
        let selected = candidates.min { left, right in
            if left.sample.era != right.sample.era { return left.sample.era < right.sample.era }
            if left.sample.strikeouts != right.sample.strikeouts { return left.sample.strikeouts > right.sample.strikeouts }
            if left.sample.outs != right.sample.outs { return left.sample.outs > right.sample.outs }
            return (left.record.teamID, left.record.id) < (right.record.teamID, right.record.id)
        }
        guard let selected else { return Slot(position: .pitcher, winner: nil, reason: .noEligiblePlayer) }
        return Slot(position: .pitcher, winner: Winner(teamID: selected.record.teamID, playerID: selected.record.id,
                                                       evidence: .pitcher(selected.sample)), reason: nil)
    }

    static func primaryPosition(_ fielding: [String: SeasonFieldingSample],
                                includingPitcher: Bool = false) -> (position: Position, sample: SeasonFieldingSample)? {
        var result: (position: Position, sample: SeasonFieldingSample)?
        for position in Position.allCases where includingPitcher || position != .pitcher {
            guard let sample = fielding[position.rawValue], sample.outs > 0, sample.games > 0 else { continue }
            if let best = result?.sample, (sample.outs, sample.games) <= (best.outs, best.games) { continue }
            result = (position, sample)
        }
        return result
    }

    func validate(teamIDs: [String]) throws {
        let winners = slots.compactMap(\.winner)
        guard version == 1, slots.map(\.position) == Position.allCases,
              Set(winners.map(\.playerID)).count == winners.count else { throw CareerPathError.invalid }
        for slot in slots {
            if let reason = slot.reason {
                guard slot.winner == nil,
                      reason != .missingDefensiveCoverage || slot.position != .pitcher,
                      reason != .missingEarnedRunCoverage || slot.position == .pitcher else { throw CareerPathError.invalid }
                continue
            }
            guard let winner = slot.winner, !winner.playerID.isEmpty, teamIDs.contains(winner.teamID) else {
                throw CareerPathError.invalid
            }
            switch winner.evidence {
            case .pitcher(let sample):
                guard slot.position == .pitcher, (1...30).contains(sample.games),
                      sample.outs >= 30 * Self.minimumPitchingOutsPerTeamGame, sample.earnedRuns >= 0,
                      (0...sample.outs).contains(sample.strikeouts) else { throw CareerPathError.invalid }
            case .fielder(let sample):
                guard slot.position != .pitcher, (1...30).contains(sample.games),
                      sample.outs >= 30 * Self.minimumOutsPerTeamGame,
                      sample.plateAppearances >= 30 * Self.minimumPlateAppearancesPerTeamGame,
                      sample.ops.isFinite, (0...5).contains(sample.ops),
                      (0...sample.plateAppearances).contains(sample.homeRuns) else { throw CareerPathError.invalid }
            }
        }
    }

    static func innings(_ outs: Int) -> String {
        "\(outs / 3).\(outs % 3)이닝"
    }
}

struct LeagueGoldGlove: Codable, Equatable {
    var version = 1
    let slots: [Slot]
    let unscoredGames: Int

    enum HoldReason: String, Codable {
        case missingFieldingRecords, belowMinimumInnings, belowMinimumChances

        var label: String {
            switch self {
            case .missingFieldingRecords: "실책·자살·보살 기록이 없는 경기가 있어 수상자를 확정할 수 없습니다."
            case .belowMinimumInnings: "해당 포지션의 최소 수비이닝을 채운 선수가 없습니다."
            case .belowMinimumChances: "이닝 기준을 채운 선수 중 최소 수비 기회를 충족한 선수가 없습니다."
            }
        }
    }

    struct Slot: Codable, Equatable, Identifiable {
        let position: LeagueBestNine.Position
        let minimumInnings: Int
        let minimumChances: Int
        let winner: Winner?
        let reason: HoldReason?

        var id: String { position.rawValue }
    }

    struct Winner: Codable, Equatable {
        let teamID: String
        let playerID: String
        let evidence: Evidence
    }

    struct Evidence: Codable, Equatable {
        let games: Int
        let outs: Int
        let putouts: Int
        let assists: Int
        let errors: Int

        var chances: Int { putouts + assists + errors }
        var fieldingPercentage: Double { Double(putouts + assists) / Double(chances) }
        var sampleSummary: String { "수비 \(games)경기 · \(LeagueBestNine.innings(outs)) · \(chances)기회" }
        var rankingSummary: String { "수비율 \(String(format: "%.3f", fieldingPercentage)) · 실책 \(errors)개" }
    }

    static let rankingRule = "수비율이 높은 순으로 선정합니다. 같으면 수비 기회, 수비이닝 순으로 비교합니다."

    static func criteria(_ position: LeagueBestNine.Position, competition: String) -> (innings: Int, chances: Int) {
        let thresholds: (pitcher: Int, catcher: Int, fielder: Int)
        switch competition {
        case "domestic-first-team": thresholds = (10, 135, 150)
        case "npb-first-team": thresholds = (30, 135, 135)
        case "mlb-first-team": thresholds = (30, 135, 165)
        default: thresholds = (10, 120, 135)
        }
        switch position {
        case .pitcher: return (thresholds.pitcher, 5)
        case .catcher: return (thresholds.catcher, 20)
        case .left, .center, .right: return (thresholds.fielder, 12)
        default: return (thresholds.fielder, 20)
        }
    }

    static func make(_ ledger: SeasonPlayerLedger) -> Self {
        let missingGames = max(ledger.unverifiedFieldingGames, ledger.unscoredDefensiveGames)
        var byPosition: [LeagueBestNine.Position: [Winner]] = [:]
        for player in ledger.players where missingGames == 0 {
            guard let primary = LeagueBestNine.primaryPosition(player.fielding, includingPitcher: true),
                  primary.sample.games == primary.sample.scoredGames else { continue }
            let sample = primary.sample
            let evidence = Evidence(games: sample.games, outs: sample.outs, putouts: sample.putouts,
                                    assists: sample.assists, errors: sample.errors)
            byPosition[primary.position, default: []].append(Winner(teamID: player.teamID, playerID: player.id, evidence: evidence))
        }
        let slots = LeagueBestNine.Position.allCases.map { position in
            let minimum = criteria(position, competition: ledger.competition)
            func held(_ reason: HoldReason) -> Slot {
                Slot(position: position, minimumInnings: minimum.innings, minimumChances: minimum.chances, winner: nil, reason: reason)
            }
            guard missingGames == 0 else { return held(.missingFieldingRecords) }
            let qualifiedInnings = (byPosition[position] ?? []).filter { $0.evidence.outs >= 3 * minimum.innings }
            guard !qualifiedInnings.isEmpty else { return held(.belowMinimumInnings) }
            let winner = qualifiedInnings.filter { $0.evidence.chances >= minimum.chances }.min(by: ranksAhead)
            guard let winner else { return held(.belowMinimumChances) }
            return Slot(position: position, minimumInnings: minimum.innings, minimumChances: minimum.chances, winner: winner, reason: nil)
        }
        return Self(slots: slots, unscoredGames: missingGames)
    }

    private static func ranksAhead(_ left: Winner, _ right: Winner) -> Bool {
        let a = left.evidence, b = right.evidence
        let leftRate = (a.putouts + a.assists) * b.chances
        let rightRate = (b.putouts + b.assists) * a.chances
        if leftRate != rightRate { return leftRate > rightRate }
        if a.chances != b.chances { return a.chances > b.chances }
        if a.outs != b.outs { return a.outs > b.outs }
        return (left.teamID, left.playerID) < (right.teamID, right.playerID)
    }

    func validate(competition: String, teamIDs: [String]) throws {
        let winners = slots.compactMap(\.winner)
        guard version == 1, (0...teamIDs.count * 15).contains(unscoredGames),
              slots.map(\.position) == LeagueBestNine.Position.allCases,
              Set(winners.map(\.playerID)).count == winners.count else { throw CareerPathError.invalid }
        for slot in slots {
            let minimum = Self.criteria(slot.position, competition: competition)
            guard slot.minimumInnings == minimum.innings, slot.minimumChances == minimum.chances else { throw CareerPathError.invalid }
            if let reason = slot.reason {
                guard slot.winner == nil, (reason == .missingFieldingRecords) == (unscoredGames > 0) else { throw CareerPathError.invalid }
                continue
            }
            guard unscoredGames == 0, let winner = slot.winner,
                  !winner.playerID.isEmpty, teamIDs.contains(winner.teamID) else { throw CareerPathError.invalid }
            let sample = winner.evidence
            guard (1...30).contains(sample.games),
                  sample.outs >= 3 * minimum.innings, sample.outs <= 27 * sample.games,
                  (0...sample.outs).contains(sample.putouts),
                  (0...200_000 * sample.games).contains(sample.assists),
                  (0...200_000 * sample.games).contains(sample.errors),
                  sample.chances >= minimum.chances else { throw CareerPathError.invalid }
        }
    }
}
