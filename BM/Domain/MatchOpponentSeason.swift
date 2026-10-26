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

    func player(_ id: String) -> MatchOpponentSeasonPlayer? { players.first { $0.id == id } }
    func validate(analysis: MatchOppositionAnalysis, date: GameDate) throws {
        guard version == 1, year == date.year, teamID == analysis.teamID,
              competition == analysis.attack?.competition, try GameDate(through) == date.adding(days: -1),
              uncollectedGames >= 0, Set(players.map(\.id)).count == players.count else { throw MatchError.invalidRecord }
        for player in players {
            guard player.battingGames >= 0, player.pitchingGames >= 0,
                  player.earnedRunGames >= 0, player.unscoredPitchingGames >= 0,
                  player.earnedRunGames + player.unscoredPitchingGames == player.pitchingGames else { throw MatchError.invalidRecord }
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
    func value(_ label: String) -> String {
        func rate(_ value: Double?, digits: Int = 3) -> String { value.map { String(format: "%.*f", digits, $0) } ?? "미집계" }
        switch label {
        case "AVG": return rate(batting.average)
        case "OBP": return rate(batting.onBasePercentage)
        case "SLG": return rate(batting.sluggingPercentage)
        case "OPS": return rate(batting.ops)
        case "HR": return batting.plateAppearances > 0 ? String(batting.homeRuns) : "미집계"
        case "ER": return pitchingGames > 0 ? pitching.earnedRuns.map(String.init) ?? "미집계" : "미집계"
        case "ERA": return rate(pitching.era, digits: 2)
        case "WHIP": return rate(pitching.outs > 0 ? Double(pitching.hits + pitching.walks) * 3 / Double(pitching.outs) : nil, digits: 2)
        case "K/9": return rate(pitching.outs > 0 ? Double(pitching.strikeouts) * 27 / Double(pitching.outs) : nil, digits: 1)
        default: return "미집계"
        }
    }
}
