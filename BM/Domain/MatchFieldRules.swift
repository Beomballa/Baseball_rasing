import Foundation

struct MatchFieldStats: Codable, Equatable {
    var version = 1
    let speed: Double
    let defense: Double
    let arm: Double
    let position: String
}

struct MatchFieldPlay: Codable, Equatable {
    let runnerTime: Double
    let ballTime: Double
    let ownDefense: Bool
    var safe: Bool { runnerTime <= ballTime }
}

// First-base races only. Existing matches without this snapshot keep their original rules.
enum MatchFieldRules {
    static func firstBase(runnerSpeed: Double, fielderSpeed: Double, defense: Double, arm: Double,
                          chase: Double, distance: Double, ownDefense: Bool) -> MatchFieldPlay {
        func stat(_ value: Double) -> Double { max(0, min(100, value)) }
        let runner = 27.43 / (5.5 + stat(runnerSpeed) * 0.035)
        let retrieve = chase / (4 + stat(fielderSpeed) * 0.03) + 1 - stat(defense) * 0.006
        let ball = retrieve + distance / (18 + stat(arm) * 0.18)
        return MatchFieldPlay(runnerTime: runner, ballTime: ball, ownDefense: ownDefense)
    }
}
