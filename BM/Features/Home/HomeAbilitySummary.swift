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

    init(axes: [HomeAbilityValue], originals: [HomeAbilityValue], pitches: [HomeAbilityValue], hasInitialValues: Bool) {
        self.axes=axes;self.originals=originals;self.pitches=pitches;self.hasInitialValues=hasInitialValues
    }

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

/// Stored baseline comparison only; training and match awards remain in their own ledgers.
extension HomeAbilityValue {
    var growthFeedback: String {
        guard let growth, growth.isFinite else { return "시작 기록 없음 · 현재 능력만 표시" }
        if growth == 0 { return "시작 대비 변화 없음" }
        if abs(growth) < 0.05 { return growth > 0 ? "소폭 성장 누적 중 · 0.1 미만" : "소폭 감소 · 0.1 미만" }
        return "시작 대비 " + (growth > 0 ? "+" : "") + growth.formatted(.number.precision(.fractionLength(1)))
    }
}

struct EarlyPlayGuidance: Equatable {
    let title: String
    let detail: String
    static func make(trainingPending: Bool, gamePending: Bool, actionUsed: Bool, gameDue: Bool, gameCompleted: Bool) -> Self {
        if trainingPending { return .init(title: "진행 중인 훈련부터 이어가세요", detail: "훈련 탭에서 저장된 시도부터 계속합니다. 5회 완료 후 성장 결과를 확인하세요.") }
        if gamePending { return .init(title: "진행 중인 경기를 이어가세요", detail: "경기 탭에서 저장된 볼카운트와 주자 상황부터 계속합니다.") }
        if gameDue && !gameCompleted { return .init(title: "오늘 경기를 준비하세요", detail: "경기 탭에서 상대 분석과 계획을 확인하세요. 오늘 경기 처리가 끝나야 다음 날로 진행할 수 있습니다.") }
        if actionUsed { return .init(title: "오늘 행동을 마쳤습니다", detail: "선수 탭에서 성장 변화를 확인하고, 오늘 일정에서 다음 날로 진행하세요. 경기는 별도 일정입니다.") }
        return .init(title: "훈련 또는 휴식 중 하나를 고르세요", detail: "훈련 탭에서 능력을 골라 5회 연습하거나 오늘 일정에서 휴식하세요. 자유 연습은 성장·날짜·피로에 반영되지 않습니다.")
    }
}
