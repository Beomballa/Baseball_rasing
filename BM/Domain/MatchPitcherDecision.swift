import Foundation

/// Optional side ledger for new matches. It observes scores; it never decides a play.
struct MatchPitcherDecision: Codable, Equatable {
    struct Lead: Codable, Equatable {
        let home: Int
        let away: Int
        let battingHome: Bool
        let pitcherOfRecord: String
        let responsible: [String]
    }
    var version = 1
    var scores: [Lead] = []
    var settled = false
    var winner: String?
    var loser: String?

    mutating func observe(home: Int, away: Int, battingHome: Bool, pitcher: String, responsible: [String]) {
        guard !settled, !responsible.isEmpty else { return }
        scores.append(Lead(home:home,away:away,battingHome:battingHome,pitcherOfRecord:pitcher,responsible:responsible))
    }
    func candidates(records: MatchPlayerRecords) -> (String?, String?) {
        var home=0,away=0,win: String?,loss: String?
        for event in scores {
            let oldDifference=home-away
            home=event.home;away=event.away
            if home == away {win=nil;loss=nil;continue}
            if (home > away && oldDifference <= 0) || (away > home && oldDifference >= 0) {
                let decisive=(event.battingHome ? -oldDifference:oldDifference)
                guard event.responsible.indices.contains(decisive) else {return (nil,nil)}
                win=event.pitcherOfRecord;loss=event.responsible[decisive]
            }
        }
        guard home != away, let candidate=win else {return (nil,nil)}
        let staff=home > away ? records.home.pitching:records.away.pitching
        // There is exactly one reliever in this game ruleset; scorer discretion is not simulated.
        if candidate == staff[0].id && staff[0].counts.outs < 15 {
            win=staff[1].counts.pitches > 0 ? staff[1].id:nil
        }
        return (win,loss)
    }
    mutating func finish(records: MatchPlayerRecords) {
        guard !settled else {return}
        (winner,loser)=candidates(records:records);settled=true
    }
    func validate(records: MatchPlayerRecords, match: CareerMatch) throws {
        guard version == 1, scores.count <= 20000, settled == match.completed else {throw MatchError.invalidRecord}
        var home=0,away=0
        for event in scores {
            let offense=event.battingHome ? records.home:records.away
            let defense=event.battingHome ? records.away:records.home
            let runs=event.battingHome ? event.home-home:event.away-away
            guard (1...4).contains(runs),event.responsible.count == runs,
                  (event.battingHome ? event.away == away:event.home == home),
                  offense.pitching.contains(where:{$0.id == event.pitcherOfRecord}),
                  event.responsible.allSatisfy({id in defense.pitching.contains {$0.id == id}}) else {throw MatchError.invalidRecord}
            home=event.home;away=event.away
        }
        guard home == match.homeScore,away == match.awayScore else {throw MatchError.invalidRecord}
        if settled {
            let result=candidates(records:records)
            guard winner == result.0,loser == result.1,
                  home == away || (winner != nil && loser != nil) else {throw MatchError.invalidRecord}
        } else if winner != nil || loser != nil {throw MatchError.invalidRecord}
    }
}
