import Foundation

struct PositionSkill: Codable, Equatable {
    var mastery: Double
    var xp: Double
}

struct PositionLoadout: Codable, Equatable {
    var skills: [String: PositionSkill]
    init(primary: FieldPosition) {
        skills = Dictionary(uniqueKeysWithValues: FieldPosition.allCases.map { ($0.rawValue, PositionSkill(mastery: $0 == primary ? 60 : 10, xp: 0)) })
    }
    func validate() throws {
        guard Set(skills.keys) == Set(FieldPosition.allCases.map(\.rawValue)), skills.values.allSatisfy({
            $0.mastery.isFinite && (0...100).contains($0.mastery) && $0.xp.isFinite && (0..<100).contains($0.xp)
                && ($0.mastery < 100 || $0.xp == 0)
        }) else { throw TrainingError.invalidRecord }
    }
    func skill(_ position: FieldPosition) throws -> PositionSkill {
        try validate()
        guard let value = skills[position.rawValue] else { throw TrainingError.invalidRecord }
        return value
    }
}

enum PositionTrainingRules {
    static func endpoint(x: Double, y: Double, angle: Double, force: Double) -> TrainingTarget {
        TrainingTarget(x: x + cos(angle * .pi / 180) * force / 100 * 0.9,
                       y: y + sin(angle * .pi / 180) * force / 100 * 0.9)
    }
    static func origin(_ position: FieldPosition) -> TrainingTarget {
        switch position {
        case .catcher: TrainingTarget(x: 0.5, y: 0.83)
        case .first: TrainingTarget(x: 0.78, y: 0.63)
        case .second: TrainingTarget(x: 0.64, y: 0.45)
        case .third: TrainingTarget(x: 0.22, y: 0.63)
        case .shortstop: TrainingTarget(x: 0.36, y: 0.45)
        case .left: TrainingTarget(x: 0.2, y: 0.25)
        case .center: TrainingTarget(x: 0.5, y: 0.22)
        case .right: TrainingTarget(x: 0.8, y: 0.25)
        }
    }
    static func gainedXP(mastery: Double, score: Double, fatigue: Int, age: Int) -> Double {
        guard mastery < 100 else { return 0 }
        let performance = score >= 90 ? 1.3 : score >= 75 ? 1.2 : score >= 50 ? 1.1 : 1
        let level = mastery < 50 ? 1.0 : mastery < 70 ? 0.65 : mastery < 80 ? 0.4 : mastery < 90 ? 0.2 : mastery < 95 ? 0.08 : 0.025
        let recovery = fatigue <= 40 ? 1.0 : fatigue < 60 ? 0.8 : 0.5
        return TrainingRules.round(20 * performance * level * recovery * TrainingRules.ageMultiplier(age))
    }
    static func adding(_ xp: Double, to skill: PositionSkill) -> PositionSkill {
        let total = TrainingRules.round(skill.xp + xp)
        let levels = floor(total / 100)
        let mastery = min(100, skill.mastery + levels)
        return PositionSkill(mastery: mastery, xp: mastery == 100 ? 0 : TrainingRules.round(total - levels * 100))
    }
    // One attempt has both a location decision and a direction/base/strength decision.
    static func score(position: FieldPosition, target: TrainingTarget, input: TrainingInput) throws -> Int {
        guard input.x.isFinite, input.y.isFinite, (0...1).contains(input.x), (0...1).contains(input.y),
              input.timing == nil, input.release == nil, input.calledStrike == nil, input.footfalls == nil, input.choice == nil,
              let base = input.base, (1...4).contains(base), let force = input.force, force.isFinite, (0...100).contains(force),
              let angle = input.angle, angle.isFinite, (0...360).contains(angle) else { throw TrainingError.invalidInput }
        let positioning = max(0, 1 - hypot(input.x - target.x, input.y - target.y) / 0.3)
        let destination = TrainingRules.basePoint(position.targetBase)
        let endpoint = endpoint(x: input.x, y: input.y, angle: angle, force: force)
        let throwing = base == position.targetBase ? max(0, 1 - hypot(endpoint.x - destination.x, endpoint.y - destination.y) / 0.3) : 0
        return Int((100 * (positioning * 0.6 + throwing * 0.4)).rounded())
    }
}

extension FieldPosition {
    var targetBase: Int {
        switch self { case .catcher, .center: 2; case .right: 3; case .left: 2; default: 1 }
    }
}
