import Foundation

struct MatchFieldStats: Codable, Equatable {
    var version = 1
    let speed: Double
    let defense: Double
    let arm: Double
    let position: String
    var activeTraits: [PlayerTrait]?
}

struct MatchFieldPlay: Codable, Equatable {
    let runnerTime: Double
    let ballTime: Double
    let ownDefense: Bool
    var appliedTraits: [PlayerTrait]?
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


extension MatchFieldRules {
    static func firstBaseV2(runnerSpeed: Double, fielderSpeed: Double, defense: Double, arm: Double,
                            chase: Double, distance: Double, ownDefense: Bool, active: [PlayerTrait]) -> MatchFieldPlay {
        func stat(_ value: Double) -> Double { max(0, min(100, value)) }
        let runnerTraits = ownDefense ? [] : active.filter { $0 == .cheetah }
        let defenseTraits = ownDefense ? active : []
        let start = (0.32 + (100 - stat(runnerSpeed)) * 0.002) * (runnerTraits.contains(.cheetah) ? 0.92 : 1)
        let runner = start + 27.43 / (5.5 + stat(runnerSpeed) * 0.035)
        let reaction = (0.58 - stat(defense) * 0.004) * (defenseTraits.contains(.cheetah) ? 0.92 : 1)
        let pickup = (0.32 - stat(defense) * 0.002) * (defenseTraits.contains(.safeHands) ? 0.90 : 1)
        let transfer = 0.6 - stat(defense) * 0.0035
        let throwTime = distance / ((18 + stat(arm) * 0.18) * (defenseTraits.contains(.strongArm) ? 1.05 : 1))
        let ball = reaction + chase / (4 + stat(fielderSpeed) * 0.03) + pickup + transfer + throwTime
        return MatchFieldPlay(runnerTime: runner, ballTime: ball, ownDefense: ownDefense, appliedTraits: ownDefense ? defenseTraits : runnerTraits)
    }
}
