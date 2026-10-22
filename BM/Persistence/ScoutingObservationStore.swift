import Foundation
import SwiftData

enum ScoutingObservationError: LocalizedError {
    case invalid, pendingChanges
    var errorDescription: String? {
        switch self {
        case .invalid: "저장된 관찰 보고서 또는 주기 자료가 올바르지 않습니다. 기존 자료를 보존하고 다시 확인해 주세요."
        case .pendingChanges: "다른 저장 작업이 진행 중입니다. 저장을 마친 뒤 보고서를 다시 확인해 주세요."
        }
    }
}

struct ScoutingPeriod: Equatable {
    let index: Int
    let start: GameDate
    var end: GameDate { start.adding(days: 27) }
    var next: GameDate { start.adding(days: 28) }
    init(origin: GameDate, today: GameDate) throws {
        guard today >= origin else { throw ScoutingObservationError.invalid }
        index = origin.days(to: today) / 28
        start = origin.adding(days: index * 28)
    }
}

struct ScoutingRoleGrade: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let score: Double?
    let detail: String
}

// Frozen inputs and game-setting weights. Club criteria and NPC reference statistics remain unavailable.
enum ScoutingRoleEvaluation {
    static let pitches: [String: (family: String, speed: Double)] = [
        "four-seam": ("fast", 145), "slider": ("glove", 132),
        "changeup": ("slow", 125), "fork": ("vertical", 129)
    ]
    static func grades(role: PlayerRole, abilities: HomeAbilitySummary, positionMastery: Double?) throws -> [ScoutingRoleGrade] {
        let original = abilities.originals
        guard Set(original.map(\.id)).count == original.count,
              Set(abilities.pitches.map(\.id)).count == abilities.pitches.count,
              (original + abilities.pitches).allSatisfy({ $0.current.isFinite && (0...100).contains($0.current) }) else {
            throw ScoutingObservationError.invalid
        }
        let values = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0.current) })
        func value(_ id: String) throws -> Double {
            guard let result = values[id] else { throw ScoutingObservationError.invalid }; return result
        }
        func grade(_ id: String, _ label: String, _ base: Double, _ detail: String) throws -> ScoutingRoleGrade {
            let h = (0.95 * base + 0.05 * (try value("homeMental")))
            return ScoutingRoleGrade(id: id, label: label, score: (h * 10_000).rounded() / 10_000, detail: detail)
        }
        if role == .batter {
            let c = try value("homeContact"), p = try value("homePower"), d = try value("homeDiscipline")
            let field = try c * 0.20 + p * 0.10 + d * 0.15 + value("homeSpeed") * 0.10 + value("homeDefense") * 0.30 + value("homeArm") * 0.15
            let eligible = try (positionMastery ?? -1) >= 70 && value("homeDefense") >= 70
            return try [grade("slugger", "장타 역할", c * 0.25 + p * 0.50 + d * 0.25, "컨택25% · 파워50% · 선구안25%"),
                grade("onBase", "출루 역할", c * 0.50 + p * 0.15 + d * 0.35, "컨택50% · 파워15% · 선구안35%"),
                grade("field", "수비 역할", field, "공격/스피드·원본 수비·송구를 반영합니다. " + (eligible ? "위치 숙련/수비70 조건 충족 · 해외 공격 기준은 별도입니다." : "위치 숙련70·원본 수비70 조건 보완이 필요합니다."))]
        }
        let ordered = abilities.pitches.sorted { $0.current == $1.current ? $0.id < $1.id : $0.current > $1.current }
        guard let main = ordered.first, let mainInfo = pitches[main.id], ordered.allSatisfy({ pitches[$0.id] != nil }) else {
            return [ScoutingRoleGrade(id: "starter", label: "선발 역할", score: nil, detail: "구종의 움직임 계열/기준 구속 자료가 없어 구성 평가를 보류합니다.")]
        }
        let complement = ordered.dropFirst().first {
            let info = pitches[$0.id]!
            return info.family != mainInfo.family || abs(info.speed - mainInfo.speed) >= 12
        }
        let mix = main.current * 0.6 + (complement?.current ?? 0) * 0.4
        let base = try value("homeVelocity") * 0.15 + value("homeControl") * 0.25 + value("homeStuff") * 0.25 + mix * 0.20 + value("homeStamina") * 0.15
        return try [grade("starter", "선발 역할", base, "구속15% · 제구25% · 구위25% · 구성20% · 지구력15%\n주력 \(main.label) · 보완 \(complement?.label ?? "없음(0점)") / 구성60:40")]
    }
}

struct ScoutingObservation: Codable {
    var version = 1
    var evaluationVersion = "contracts-role-v1"
    let playerID: UUID
    let origin: String
    let period: Int
    let periodStart: String
    let observedDate: String
    let nextDate: String
    let name: String
    let number: Int
    let school: String
    let role: PlayerRole
    let position: String
    let hand: String
    let appearance: PlayerAppearance
    let age: Int
    let sampleStart: String
    let abilities: HomeAbilitySummary
    let groups: [ScoutingSampleGroup]
    let totals: PersonalSeasonTotals
    let pending: Int
    let positionMastery: Double?
    let grades: [ScoutingRoleGrade]
    var evaluationPending: [String]
    var contractFit: ScoutingContractFit?

    static func pendingReasons(age: Int, role: PlayerRole, groups: [ScoutingSampleGroup], modern: Bool = false, compared: Bool = false) -> [String] {
        var reasons = ["구단 기준 미연결", "동일 환경 비교 성적 미검증", "육성 전망 미산정", "진로/권리·모집/예산 심사 미연결"]
        if modern {
            reasons = ["육성 전망 미산정", "진로/권리·등록/예산 심사 미연결"]
            if !compared {reasons.append("성적 비교 자료 부족 또는 입력 환경 미검증 · P=0 중립")}
        }
        if age < 20 { reasons.append("20세 미만 · 정식 제의 대상 아님") }
        if !groups.contains(where: { role == .batter ? $0.hasBatterMinimum : $0.hasPitcherMinimum }) {
            reasons.append("동일 경기 환경의 관찰 최소 표본 부족")
        }
        return reasons
    }

    func validate() throws {
        let origin = try GameDate(origin), date = try GameDate(observedDate)
        let cycle = try ScoutingPeriod(origin: origin, today: date)
        guard [1,2,3].contains(version), evaluationVersion == "contracts-role-v1", cycle.index == period,
              cycle.start.description == periodStart, cycle.next.description == nextDate,
              try GameDate(sampleStart) == max(origin, date.adding(days: -364)),
              appearance.isValid, (0...99).contains(number), age >= 0, pending >= 0,
              abilities.axes.count == 6,
              (abilities.axes + abilities.originals + abilities.pitches).allSatisfy({
                  $0.current.isFinite && (0...100).contains($0.current)
                      && ($0.initial.map { $0.isFinite && (0...100).contains($0) } ?? true)
              }),
              positionMastery.map({ $0.isFinite && (0...100).contains($0) }) ?? true,
              groups.count <= 365, Set(groups.map(\.id)).count == groups.count,
              evaluationPending == Self.pendingReasons(age: age, role: role, groups: groups, modern: version >= 2, compared: contractFit?.selectedEnvironment != nil),
              grades == (try ScoutingRoleEvaluation.grades(role: role, abilities: abilities, positionMastery: positionMastery)) else {
            throw ScoutingObservationError.invalid
        }
        var expected = PersonalSeasonTotals()
        for group in groups {
            guard (1...365).contains(group.totals.games) else { throw ScoutingObservationError.invalid }
            var validated = PersonalSeasonTotals(); try validated.add(group.totals.line)
            try expected.add(group.totals.line)
        }
        expected.games = groups.reduce(0) { $0 + $1.totals.games }
        guard expected == totals else { throw ScoutingObservationError.invalid }
        if version == 1 {guard contractFit == nil else {throw ScoutingObservationError.invalid}}
        else {guard let contractFit else {throw ScoutingObservationError.invalid};guard contractFit.version == (version == 2 ? 1:2) else {throw ScoutingObservationError.invalid};try contractFit.validate(observation:self)}
    }
}

enum CareerSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV7.models + [ScoutingReport.self] }
    @Model final class ScoutingReport {
        @Attribute(.unique) var key: String
        var playerID: UUID
        var period: Int
        var observedDate: String
        var payload: Data
        init(_ value: ScoutingObservation) throws {
            key = Self.key(value.playerID, value.period); playerID = value.playerID
            period = value.period; observedDate = value.observedDate
            payload = try JSONEncoder().encode(value)
        }
        static func key(_ id: UUID, _ period: Int) -> String { "\(id.uuidString):observation-v1:\(period)" }
        @MainActor func snapshot() throws -> ScoutingObservation {
            guard let value = try? JSONDecoder().decode(ScoutingObservation.self, from: payload),
                  value.playerID == playerID, value.period == period, value.observedDate == observedDate,
                  key == Self.key(playerID, period) else { throw ScoutingObservationError.invalid }
            try value.validate(); return value
        }
    }
}
typealias CareerScoutingReport = CareerSchemaV8.ScoutingReport

@MainActor enum ScoutingObservationStore {
    static func reports(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext) throws -> [CareerScoutingReport] {
        let id = player.id
        guard calendar.playerID == id, PlayerRole(rawValue: player.roleRaw) != nil else { throw ScoutingObservationError.invalid }
        let rows = try context.fetch(FetchDescriptor<CareerScoutingReport>(predicate: #Predicate { $0.playerID == id }))
        guard Set(rows.map(\.period)).count == rows.count else { throw ScoutingObservationError.invalid }
        for row in rows {
            let value = try row.snapshot()
            guard value.origin == calendar.originDate, value.role == player.role,
                  try GameDate(value.observedDate) <= GameDate(player.gameDate) else { throw ScoutingObservationError.invalid }
        }
        return rows.sorted { $0.period > $1.period }
    }
    // Parent creation/day transition owns the single atomic save and rollback.
    static func insertIfNeeded(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext) throws -> CareerScoutingReport? {
        guard context.container.schema.entities.contains(where: { $0.name == "ScoutingReport" }) else { return nil }
        let cycle = try ScoutingPeriod(origin: GameDate(calendar.originDate), today: GameDate(player.gameDate))
        let rows = try reports(player: player, calendar: calendar, in: context)
        if let row = rows.first(where: { $0.period == cycle.index }) { return row }
        let live = try ScoutingReportSnapshot.load(player: player, calendar: calendar, in: context)
        let position = FieldPosition(rawValue: player.positionRaw)
        let profile = player.role == .batter ? try PlayerPositionStore.profile(playerID: player.id, in: context) : nil
        let mastery = try position.flatMap { try profile?.snapshot().skill($0).mastery }
        var value = ScoutingObservation(playerID: player.id, origin: calendar.originDate, period: cycle.index,
            periodStart: cycle.start.description, observedDate: live.date.description, nextDate: cycle.next.description,
            name: player.name, number: player.jerseyNumber, school: player.schoolName, role: player.role,
            position: player.positionRaw, hand: player.throwingHandRaw, appearance: player.appearance, age: live.age,
            sampleStart: live.start.description, abilities: live.abilities, groups: live.groups, totals: live.totals,
            pending: live.pending, positionMastery: mastery,
            grades: try ScoutingRoleEvaluation.grades(role: player.role, abilities: live.abilities, positionMastery: mastery),
            evaluationPending: ScoutingObservation.pendingReasons(age: live.age, role: player.role, groups: live.groups))
        value.version = 3
        value.contractFit = try ScoutingContractFit.make(value)
        value.evaluationPending = ScoutingObservation.pendingReasons(age:live.age,role:player.role,groups:live.groups,modern:true,compared:value.contractFit?.selectedEnvironment != nil)
        try value.validate()
        let row = try CareerScoutingReport(value); context.insert(row); return row
    }
    static func ensureCurrent(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext,
                              save: CalendarProgression.Save = { try $0.save() }) throws {
        guard !context.hasChanges else { throw ScoutingObservationError.pendingChanges }
        do {
            _ = try insertIfNeeded(player: player, calendar: calendar, in: context)
            if context.hasChanges { try save(context) }
        } catch { context.rollback(); throw error }
    }
}
