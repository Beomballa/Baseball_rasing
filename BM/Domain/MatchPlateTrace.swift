import Foundation

/// 새 경기의 판정 확정 기록. 재생·스킵·프레임 보간은 이 원장을 수정하지 않는다.
struct MatchPlateTrace: Codable, Equatable, Identifiable {
    struct ScoredRunner: Codable, Equatable {
        let id: String
        let pitcher: String
    }
    let half: Int
    let order: Int
    let batter: String
    let pitcher: String
    let result: String
    let outsBefore: Int
    let beforeHome: Int
    let beforeAway: Int
    let beforeRunners: [String?]
    let scoring: [ScoredRunner]
    let afterHalf: Int
    let afterOuts: Int
    let home: Int
    let away: Int
    let homeOrder: Int
    let awayOrder: Int
    let afterRunners: [String?]
    var id: String { "\(half):\(order)" }
    var battingHome: Bool { half % 2 == 1 }
}

extension MatchPlayerRecords {
    func homeTeam(batting half: Int) -> MatchTeamRecords { half % 2 == 1 ? home : away }

    mutating func appendPlateTrace(half: Int, order: Int, batter: String, result: String, outsBefore: Int,
                                  beforeHome: Int, beforeAway: Int, beforeRunners: [String?],
                                  responsibility: [String?], match: CareerMatch, play: MatchDetailedPlay?) {
        guard plateTrace != nil else { return }
        let battingHome = half % 2 == 1, defendingHome = !battingHome
        let defense = defendingHome ? home : away
        let current = match.pitching?.change(home: defendingHome) == nil ? 0 : 1
        func pitcherID(_ tag: String?) -> String {
            defense.pitching[tag == MatchPitching.reliefID(home: defendingHome) ? 1 : tag == nil ? current : 0].id
        }
        let count = battingHome ? match.homeScore - beforeHome : match.awayScore - beforeAway
        var goals: [MatchPlateTrace.ScoredRunner] = []
        if let play {
            goals = play.runners.filter { !$0.out && $0.destination == 4 }.sorted { $0.arrival < $1.arrival }
                .prefix(count).compactMap { runner in
                    guard let id = runner.from == 0 ? batter : beforeRunners[runner.from - 1] else { return nil }
                    return .init(id: id, pitcher: pitcherID(runner.profile.responsiblePitcher))
                }
        } else if result == "홈런" {
            goals = (0..<3).reversed().compactMap { index in
                beforeRunners[index].map { .init(id: $0, pitcher: pitcherID(responsibility[index])) }
            } + [.init(id: batter, pitcher: defense.pitching[current].id)]
        } else if count == 1, let id = beforeRunners[2] {
            goals = [.init(id: id, pitcher: pitcherID(responsibility[2]))]
        }
        plateTrace?.append(MatchPlateTrace(half: half, order: order, batter: batter,
            pitcher: defense.pitching[current].id, result: result, outsBefore: outsBefore,
            beforeHome: beforeHome, beforeAway: beforeAway, beforeRunners: beforeRunners, scoring: goals,
            afterHalf: match.half, afterOuts: match.outs, home: match.homeScore, away: match.awayScore,
            homeOrder: match.homeOrder, awayOrder: match.awayOrder, afterRunners: runners))
    }

    func validatePlateTrace(match: CareerMatch) throws {
        guard let plateTrace else { return }
        guard plateTrace.count <= 100_000, plateTrace.count == match.homeOrder + match.awayOrder,
              Set(plateTrace.map(\.id)).count == plateTrace.count else { throw MatchError.invalidRecord }
        var previous: MatchPlateTrace?
        for event in plateTrace {
            let batters = event.battingHome ? home : away, pitchers = event.battingHome ? away : home
            let runs = event.battingHome ? event.home - event.beforeHome : event.away - event.beforeAway
            guard (0..<18).contains(event.half), event.order >= 0, (0...2).contains(event.outsBefore),
                  (0...2).contains(event.afterOuts), (event.half...min(18, event.half + 1)).contains(event.afterHalf),
                  event.beforeRunners.count == 3, event.afterRunners.count == 3,
                  [event.beforeRunners, event.afterRunners].allSatisfy({ ids in
                      let occupied = ids.compactMap { $0 }
                      return Set(occupied).count == occupied.count && occupied.allSatisfy { id in batters.batting.contains { $0.id == id } }
                  }),
                  (0...4).contains(runs), event.scoring.count == runs,
                  Set(event.scoring.map(\.id)).count == event.scoring.count,
                  event.battingHome ? event.away == event.beforeAway : event.home == event.beforeHome,
                  batters.batting.contains(where: { $0.id == event.batter }),
                  pitchers.pitching.contains(where: { $0.id == event.pitcher }),
                  event.scoring.allSatisfy({ run in batters.batting.contains { $0.id == run.id } && pitchers.pitching.contains { $0.id == run.pitcher } }),
                  (event.battingHome ? event.homeOrder : event.awayOrder) == event.order + 1,
                  [event.home, event.away, event.beforeHome, event.beforeAway].allSatisfy({ $0 >= 0 }) else { throw MatchError.invalidRecord }
            if let previous {
                let boundary = try MatchTraceBoundary(half: previous.afterHalf, outs: previous.afterOuts,
                    home: previous.home, away: previous.away, homeOrder: previous.homeOrder,
                    awayOrder: previous.awayOrder, runners: previous.afterRunners).resolving(in: match)
                guard event.half == boundary.half, event.outsBefore == boundary.outs,
                      event.beforeHome == boundary.home, event.beforeAway == boundary.away,
                      event.order == (event.battingHome ? boundary.homeOrder : boundary.awayOrder),
                      event.beforeRunners == boundary.runners else { throw MatchError.invalidRecord }
            } else {
                guard event.half == 0, event.order == 0, event.outsBefore == 0,
                      event.beforeHome == 0, event.beforeAway == 0,
                      event.beforeRunners.allSatisfy({ $0 == nil }) else { throw MatchError.invalidRecord }
            }
            previous = event
        }
        if let last = plateTrace.last {
            let boundary = try MatchTraceBoundary(half: last.afterHalf, outs: last.afterOuts,
                home: last.home, away: last.away, homeOrder: last.homeOrder,
                awayOrder: last.awayOrder, runners: last.afterRunners).resolving(in: match)
            guard boundary.half == match.half, boundary.outs == match.outs,
                  boundary.home == match.homeScore, boundary.away == match.awayScore,
                  boundary.homeOrder == match.homeOrder, boundary.awayOrder == match.awayOrder,
                  boundary.runners == runners else { throw MatchError.invalidRecord }
        }
        for index in runners.indices {
            if let id = match.runnerProfiles?[index]?.id { guard runners[index] == id else { throw MatchError.invalidRecord } }
        }
        for team in [home, away] {
            for pitcher in team.pitching {
                let plateRuns = plateTrace.flatMap(\.scoring).filter { $0.pitcher == pitcher.id }.count
                let looseRuns = (match.pitchEvents?.events ?? []).filter { $0.kind == .loose }.flatMap { event in
                    (event.play?.runners ?? []).filter { $0.destination == 4 && !$0.out }.map { runner in
                        let home = event.before.half % 2 == 0
                        let defense = home ? self.home : self.away
                        return defense.pitching[runner.profile.responsiblePitcher == MatchPitching.reliefID(home: home) ? 1 : 0].id
                    }
                }.filter { $0 == pitcher.id }.count
                let runningRuns = (match.running?.events ?? []).flatMap { event in
                    event.play.runners.filter { !$0.out && $0.destination == 4 && ((event.play.outsBefore ?? 0) + event.play.outsAdded < 3 || $0.arrival < event.play.controlAt) }.map { runner in
                        let home = event.play.half % 2 == 0
                        let defense = home ? self.home : self.away
                        return defense.pitching[runner.profile.responsiblePitcher == MatchPitching.reliefID(home: home) ? 1 : 0].id
                    }
                }.filter { $0 == pitcher.id }.count
                guard plateRuns + looseRuns + runningRuns == pitcher.counts.runsAllowed else { throw MatchError.invalidRecord }
            }
        }
    }
}
