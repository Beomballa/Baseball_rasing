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
        let values = pitches.filter { $0.key != "four-seam" }.map(\.value).sorted(by: >)
        guard let first = values.first else { return 0 }
        return values.count == 1 ? first : first * 0.6 + values[1] * 0.4
    }
}
