import Foundation

struct HomeAbilityValue: Identifiable, Codable {
    let id: String
    let label: String
    let current: Double
    let initial: Double?
    var growth: Double? { initial.map { current - $0 } }
}

struct HomeAbilitySummary: Codable {
    let axes: [HomeAbilityValue]
    let originals: [HomeAbilityValue]
    let pitches: [HomeAbilityValue]
    let hasInitialValues: Bool

    @MainActor init(player: CareerPlayer, abilities: PlayerAbilities?) {
        let initial = abilities?.initialValues.flatMap { try? JSONDecoder().decode(PlayerInitialValues.self, from: $0) }
        hasInitialValues = initial != nil
        var values = [HomeAbilityValue]()
        if player.role == .batter {
            values += [HomeAbilityValue(id: "homeContact", label: "컨택", current: player.contact, initial: initial?.contact),
                       HomeAbilityValue(id: "homePower", label: "파워", current: player.power, initial: initial?.power),
                       HomeAbilityValue(id: "homeDiscipline", label: "선구안", current: player.discipline, initial: initial?.discipline)]
        } else if let abilities {
            for (id, label, current, before) in [("homeVelocity", "구속 능력", abilities.velocity, initial?.velocity),
                                                ("homeControl", "제구", abilities.control, initial?.control),
                                                ("homeStuff", "구위", abilities.stuff, initial?.stuff),
                                                ("homeStamina", "지구력", abilities.stamina, initial?.stamina)] {
                if let current { values.append(HomeAbilityValue(id: id, label: label, current: current, initial: before)) }
            }
        }
        let field = [HomeAbilityValue(id: "homeSpeed", label: "스피드", current: player.speed, initial: initial?.speed),
                     HomeAbilityValue(id: "homeDefense", label: "수비", current: player.defense, initial: initial?.defense),
                     HomeAbilityValue(id: "homeArm", label: "송구", current: player.arm, initial: initial?.arm)]
        let mental = abilities.map { HomeAbilityValue(id: "homeMental", label: "멘탈", current: $0.mental, initial: initial?.mental) }
        originals = values + field + (mental.map { [$0] } ?? [])
        let mastery = Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) })
        pitches = player.pitches.sorted { $0.order < $1.order }.map {
            HomeAbilityValue(id: $0.code, label: $0.name, current: $0.mastery, initial: initial?.pitches[$0.code])
        }
        if player.role == .batter {
            let defense = HomeAbilityValue(id: "homeFieldComposite", label: "수비 종합", current: player.defense * 0.7 + player.arm * 0.3,
                                           initial: initial.map { $0.defense * 0.7 + $0.arm * 0.3 })
            axes = values + [field[0], defense] + (mental.map { [$0] } ?? [])
        } else {
            let breaking = HomeAbilityValue(id: "homeBreaking", label: "변화구", current: PlayerInitialValues.breakingRating(mastery),
                                            initial: initial.map { PlayerInitialValues.breakingRating($0.pitches) })
            axes = values.filter { $0.id != "homeStamina" } + [breaking] + values.filter { $0.id == "homeStamina" } + (mental.map { [$0] } ?? [])
        }
    }
}
