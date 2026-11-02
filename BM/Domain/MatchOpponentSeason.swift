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
    static func pendingReason(_ ledger: SeasonPlayerLedger, requiredFixtureIDs: Set<String>) -> String? {
        if ledger.uncollectedGames > 0 { return "개인 성적 미수집 \(ledger.uncollectedGames)경기 · 과거 기록을 추정하지 않아 선두를 보류합니다." }
        let missing = requiredFixtureIDs.subtracting(ledger.fixtureIDs).count
        if missing > 0 { return "지난 일정 중 개인 기록 확인이 필요한 \(missing)경기 · 선두 집계 보류" }
        let teams = ledger.teamGames.values.filter { $0 > 0 }.count
        if teams < 6 { return "리그 기록 \(teams)/6팀 · 모든 팀의 경기 기록을 기다립니다." }
        if leaders(ledger, requiredFixtureIDs: requiredFixtureIDs).isEmpty {
            return "규정 표본 또는 양수 기록을 충족한 선수가 아직 없습니다. 아래 기준을 확인하세요."
        }
        return nil
    }

    // Short-season game rules: rates need 15 PA / 3 IP minimum as well as proportional qualification.
    static func leaders(_ ledger: SeasonPlayerLedger, requiredFixtureIDs: Set<String>? = nil) -> [LeagueHonor] {
        guard ledger.uncollectedGames == 0, ledger.teamGames.count == 6, ledger.teamGames.values.allSatisfy({$0 > 0}) else { return [] }
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
