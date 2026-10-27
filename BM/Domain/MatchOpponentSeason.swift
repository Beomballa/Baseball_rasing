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

    func player(_ id: String) -> MatchOpponentSeasonPlayer? { players.first { $0.id == id } }
    func validate(analysis: MatchOppositionAnalysis, date: GameDate) throws {
        guard version == 1, year == date.year, teamID == analysis.teamID,
              competition == analysis.attack?.competition, try GameDate(through) == date.adding(days: -1),
              uncollectedGames >= 0, Set(players.map(\.id)).count == players.count else { throw MatchError.invalidRecord }
        for history in pitchHistory ?? [] {try history.validate()}
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
