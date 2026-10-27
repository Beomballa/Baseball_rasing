import Foundation

enum PlayerArchetype: String, Codable, CaseIterable, Identifiable {
    case contact, slugger, onBase, stuff, control, endurance
    var id: String { rawValue }
    var role: PlayerRole { [.contact, .slugger, .onBase].contains(self) ? .batter : .pitcher }
    var label: String {
        switch self {
        case .contact: "컨택형"
        case .slugger: "장타형"
        case .onBase: "출루형"
        case .stuff: "구위형"
        case .control: "제구형"
        case .endurance: "지구력형"
        }
    }
    static func choices(for role: PlayerRole) -> [Self] { allCases.filter { $0.role == role } }
    static func initial(for role: PlayerRole) -> Self { role == .batter ? .contact : .control }
    static let presetVersion = "production-v1"
    var values: PlayerInitialValues {
        switch self {
        case .contact: PlayerInitialValues(contact: 62, power: 46, discipline: 54, speed: 62, defense: 55, arm: 54)
        case .slugger: PlayerInitialValues(contact: 50, power: 65, discipline: 50, speed: 50, defense: 56, arm: 62)
        case .onBase: PlayerInitialValues(contact: 56, power: 46, discipline: 65, speed: 60, defense: 53, arm: 53)
        case .stuff: pitcher(velocity: 62, control: 48, stuff: 62, stamina: 52)
        case .control: pitcher(velocity: 50, control: 64, stuff: 54, stamina: 56)
        case .endurance: pitcher(velocity: 52, control: 54, stuff: 53, stamina: 65)
        }
    }
    private func pitcher(velocity: Double, control: Double, stuff: Double, stamina: Double) -> PlayerInitialValues {
        PlayerInitialValues(contact: 65, power: 75, discipline: 60, speed: 55, defense: 60, arm: 65,
                            velocity: velocity, control: control, stuff: stuff, stamina: stamina,
                            pitches: ["four-seam": 62, "slider": 55, "changeup": 42, "fork": 35])
    }
}

struct PlayerInitialValues: Codable, Equatable {
    let contact: Double
    let power: Double
    let discipline: Double
    let speed: Double
    let defense: Double
    let arm: Double
    var mental = 55.0
    var velocity: Double?
    var control: Double?
    var stuff: Double?
    var stamina: Double?
    var pitches: [String: Double] = [:]

    static func breakingRating(_ pitches: [String: Double]) -> Double {
        let values = pitches.filter { PitchType(rawValue: $0.key)?.family != "fast" }.map(\.value).sorted(by: >)
        guard let first = values.first else { return 0 }
        return values.count == 1 ? first : first * 0.6 + values[1] * 0.4
    }
}

struct PlayerStatAllocation: Equatable {
    let role: PlayerRole
    var points: [TrainingKind: Int]
    static func kinds(for role: PlayerRole) -> [TrainingKind] {
        (role == .batter ? [.contact, .power, .discipline] : [.velocity, .control, .stuff, .stamina]) + [.speed, .defense, .arm, .mental]
    }
    var budget: Int { role == .batter ? 388 : 459 }
    var remaining: Int { budget - points.values.reduce(0, +) }
    var isValid: Bool {
        Set(points.keys) == Set(Self.kinds(for: role)) && points.values.allSatisfy { (0...100).contains($0) } && remaining == 0
    }
    init(role: PlayerRole, base: PlayerInitialValues) {
        self.role = role
        let values: [TrainingKind: Double] = [.contact: base.contact, .power: base.power, .discipline: base.discipline,
            .speed: base.speed, .defense: base.defense, .arm: base.arm, .mental: base.mental,
            .velocity: base.velocity ?? 0, .control: base.control ?? 0, .stuff: base.stuff ?? 0, .stamina: base.stamina ?? 0]
        points = Dictionary(uniqueKeysWithValues: Self.kinds(for: role).map { ($0, Int(values[$0] ?? 0)) })
    }
    func canAdjust(_ kind: TrainingKind, by amount: Int) -> Bool {
        guard let current = points[kind], (amount == -1 || amount == 1) else { return false }
        return (0...100).contains(current + amount) && (amount < 0 || remaining > 0)
    }
    mutating func adjust(_ kind: TrainingKind, by amount: Int) {
        guard canAdjust(kind, by: amount) else { return }
        points[kind, default: 0] += amount
    }
    var values: PlayerInitialValues {
        let base = PlayerArchetype.initial(for: role).values
        func value(_ kind: TrainingKind) -> Double { Double(points[kind] ?? 0) }
        var result = PlayerInitialValues(contact: role == .batter ? value(.contact) : base.contact,
            power: role == .batter ? value(.power) : base.power, discipline: role == .batter ? value(.discipline) : base.discipline,
            speed: value(.speed), defense: value(.defense), arm: value(.arm), mental: value(.mental),
            velocity: role == .pitcher ? value(.velocity) : nil, control: role == .pitcher ? value(.control) : nil,
            stuff: role == .pitcher ? value(.stuff) : nil, stamina: role == .pitcher ? value(.stamina) : nil)
        result.pitches = base.pitches
        return result
    }
}
