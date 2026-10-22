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
    var interests: ScoutingInterests?

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
        guard [1,2,3,4].contains(version), evaluationVersion == "contracts-role-v1", cycle.index == period,
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
        if version < 4 {guard interests == nil else {throw ScoutingObservationError.invalid}}
        else {guard interests == ScoutingInterests.make(self) else {throw ScoutingObservationError.invalid}}
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
        let value = try currentObservation(player:player,calendar:calendar,in:context)
        let row = try CareerScoutingReport(value); context.insert(row); return row
    }
    static func currentObservation(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> ScoutingObservation {
        let cycle = try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(player.gameDate))
        let live = try ScoutingReportSnapshot.load(player: player, calendar: calendar, in: context)
        let position = FieldPosition(rawValue: player.positionRaw)
        let profile = player.role == .batter ? try PlayerPositionStore.profile(playerID: player.id, in: context) : nil
        let mastery = try position.flatMap { try profile?.snapshot().skill($0).mastery }
        var value = ScoutingObservation(playerID: player.id, origin: calendar.originDate, period: cycle.index,
            periodStart: cycle.start.description, observedDate: live.date.description, nextDate: cycle.next.description,
            name: player.name, number: player.jerseyNumber, school: try calendar.registration(for:player)?.name ?? player.schoolName, role: player.role,
            position: player.positionRaw, hand: player.throwingHandRaw, appearance: player.appearance, age: live.age,
            sampleStart: live.start.description, abilities: live.abilities, groups: live.groups, totals: live.totals,
            pending: live.pending, positionMastery: mastery,
            grades: try ScoutingRoleEvaluation.grades(role: player.role, abilities: live.abilities, positionMastery: mastery),
            evaluationPending: ScoutingObservation.pendingReasons(age: live.age, role: player.role, groups: live.groups))
        value.version = 4
        value.contractFit = try ScoutingContractFit.make(value)
        value.interests = ScoutingInterests.make(value)
        value.evaluationPending = ScoutingObservation.pendingReasons(age:live.age,role:player.role,groups:live.groups,modern:true,compared:value.contractFit?.selectedEnvironment != nil)
        try value.validate()
        return value
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

struct ContractEvaluationSnapshot: Codable {
    var version = 1
    let rule: String
    let window: ContractEvaluationWindow
    let evaluatedDate: String
    let calendarRevision: Int
    let affiliation: CareerAffiliationEntry
    let routes: [String]
    let observation: ScoutingObservation
    let pending: [String]
    var selection: DomesticSelection?
    var renewal: DomesticRenewalReview?
    func validate(player:CareerPlayer,calendar:CareerCalendarState) throws {
        let date = try GameDate(evaluatedDate)
        guard [1,2,3].contains(version), rule == "contracts-window-v1", [4,7,11].contains(window.month),
              (1...9998).contains(window.year), window == ContractEvaluationWindow.containing(date),
              observation.playerID == player.id, observation.origin == calendar.originDate,
              observation.role == player.role, observation.observedDate == evaluatedDate,
              observation.age == (try GameDate(calendar.originDate).age(startingAt:player.startAge,on:date)),
              date <= (try GameDate(player.gameDate)), calendarRevision >= 0,
              !routes.isEmpty, routes == (version == 3 ? ["국내 육성팀 재계약"]:window.routes(age:observation.age,affiliation:affiliation.stage)),
              !pending.isEmpty else { throw ContractEvaluationError.invalid }
        try observation.validate()
        if version == 3 {
            guard let renewal,selection == nil else {throw ContractEvaluationError.invalid}
            try renewal.validate(observation:observation,key:player.id.uuidString+":"+window.id,window:window)
        } else if version == 1 {guard selection == nil,renewal == nil else {throw ContractEvaluationError.invalid}}
        else {
            guard let selection,renewal == nil, affiliation.stage == .unsigned else {throw ContractEvaluationError.invalid}
            try selection.validate(observation:observation,window:window)
        }
    }
}
enum CareerSchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10,0,0)
    static var models: [any PersistentModel.Type] { CareerSchemaV9.models + [ContractEvaluation.self] }
    @Model final class ContractEvaluation {
        @Attribute(.unique) var key: String
        var playerID: UUID
        var payload: Data
        var acknowledged: Bool
        init(playerID:UUID,snapshot:ContractEvaluationSnapshot) throws {
            self.playerID = playerID;key = Self.key(playerID,snapshot.window.id)
            payload = try JSONEncoder().encode(snapshot);acknowledged = false
        }
        static func key(_ id:UUID,_ window:String) -> String { id.uuidString+":"+window }
        func snapshot(player:CareerPlayer,calendar:CareerCalendarState) throws -> ContractEvaluationSnapshot {
            guard playerID == player.id else {throw ContractEvaluationError.invalid}
            let value = try JSONDecoder().decode(ContractEvaluationSnapshot.self,from:payload)
            try value.validate(player:player,calendar:calendar)
            guard key == Self.key(playerID,value.window.id) else {throw ContractEvaluationError.invalid}
            return value
        }
    }
}
typealias CareerContractEvaluation = CareerSchemaV10.ContractEvaluation

@MainActor enum ContractEvaluationStore {
    static func records(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> [CareerContractEvaluation] {
        guard context.container.schema.entities.contains(where:{$0.name == "ContractEvaluation"}) else {return []}
        guard calendar.playerID == player.id else {throw ContractEvaluationError.invalid}
        let id = player.id
        let rows = try context.fetch(FetchDescriptor<CareerContractEvaluation>(predicate:#Predicate {$0.playerID == id}))
        guard Set(rows.map(\.key)).count == rows.count else {throw ContractEvaluationError.invalid}
        let snapshots=try rows.map {try $0.snapshot(player:player,calendar:calendar)}
        for value in snapshots where value.version == 3 {
            guard let review=value.renewal,let row=try ContractRegistrationStore.row(player:player,in:context),
                  let journal=try? JSONDecoder().decode(CareerContractJournal.self,from:row.payload),journal.playerID == player.id,
                  journal.version == 1,journal.memberships.contains(review.membership),journal.decisions.contains(where:{$0.offerID == review.membership.offerID && $0.kind == .accepted && $0.date == review.membership.since}) else {throw ContractEvaluationError.invalid}
            let source=try context.fetch(FetchDescriptor<CareerContractOffer>(predicate:#Predicate {$0.playerID == id})).flatMap {try JSONDecoder().decode(DomesticOfferPacket.self,from:$0.payload).offers}
            guard let original=source.first(where:{$0.id == review.membership.offerID}),original.roleID == review.roleID,
                  review.membership == (try CareerMembership.make(offer:original,on:GameDate(review.membership.since),origin:GameDate(calendar.originDate),startAge:player.startAge)) else {throw ContractEvaluationError.invalid}
        }
        for value in snapshots where value.window.month == 7 {
            if let selection=value.selection {
                let april=snapshots.first {$0.window.year == value.window.year && $0.window.month == 4}?.selection
                guard selection.carried == DomesticSelection.carried(seed:selection.seed,april:april) else {throw ContractEvaluationError.invalid}
            }
        }
        return rows.sorted {$0.key > $1.key}
    }
    static func unread(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> CareerContractEvaluation? {
        try records(player:player,calendar:calendar,in:context).first {$0.acknowledged == false}
    }
    // Creation/date progression/legacy registration owns the single save and rollback.
    @discardableResult static func captureIfDue(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> Bool {
        guard context.container.schema.entities.contains(where:{$0.name == "ContractEvaluation"}) else {return false}
        let rows = try records(player:player,calendar:calendar,in:context)
        guard let window = ContractEvaluationWindow.containing(try GameDate(player.gameDate)) else {return false}
        guard !rows.contains(where:{$0.key == CareerContractEvaluation.key(player.id,window.id)}) else {return false}
        if let member=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).current(on:GameDate(player.gameDate)) {
            guard member.route == .rookie,window.month == 11 else {return false}
            guard let history=try CareerPathStore.record(player:player,calendar:calendar,in:context)?.snapshot(player:player,calendar:calendar) else {throw ContractEvaluationError.invalid}
            let evaluations=try records(player:player,calendar:calendar,in:context)
            let packets=try ContractOfferStore.records(player:player,calendar:calendar,in:context).map { row in
                guard let evaluation=evaluations.first(where:{$0.key == row.key}) else {throw ContractEvaluationError.invalid}
                return try row.snapshot(evaluation:evaluation,player:player,calendar:calendar)
            }
            guard let original=packets.flatMap(\.offers).first(where:{$0.id == member.offerID}) else {throw ContractEvaluationError.invalid}
            let observation=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
            let key=CareerContractEvaluation.key(player.id,window.id)
            let review=try DomesticRenewalReview.make(observation:observation,member:member,roleID:original.roleID,key:key,window:window)
            let value=ContractEvaluationSnapshot(version:3,rule:"contracts-window-v1",window:window,evaluatedDate:player.gameDate,
                calendarRevision:calendar.revision,affiliation:history.current,routes:["국내 육성팀 재계약"],observation:observation,
                pending:["성인 경기 비교 기준 미검증 · 성적 보정 P=0 중립","재계약 수락/기간 갱신·권리 해제/방출은 후속입니다."],renewal:review)
            try value.validate(player:player,calendar:calendar)
            context.insert(try CareerContractEvaluation(playerID:player.id,snapshot:value));return true
        }
        guard let history = try CareerPathStore.record(player:player,calendar:calendar,in:context)?.snapshot(player:player,calendar:calendar) else {throw ContractEvaluationError.invalid}
        let routes = window.routes(age:try calendar.age(of:player),affiliation:history.current.stage)
        guard !routes.isEmpty else {return false}
        let observation = try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
        var value = ContractEvaluationSnapshot(rule:"contracts-window-v1",window:window,evaluatedDate:player.gameDate,
            calendarRevision:calendar.revision,affiliation:history.current,routes:routes,observation:observation,
            pending:observation.age <= 23 ? ["실제 제의 발행·수락/등록·성인 소속/일정 전환은 후속입니다.","인증 평가전 원장 미연결 · 자료 누락 시 심사 보류"] : ["국내 전력/검증 테스트 선발 심사 대기"])
        if (20...23).contains(observation.age) {
            let seed=player.id.uuidString+"/\(window.year)",seats=DomesticSelection.market(seed:seed)
            let april=try rows.first(where:{$0.key == CareerContractEvaluation.key(player.id,"\(window.year)-04")})?.snapshot(player:player,calendar:calendar).selection
            let carried=window.month == 7 ? DomesticSelection.carried(seed:seed,april:april):[]
            let sample=try graduationSample(player:player,calendar:calendar,observation:observation,in:context)
            let reason="검증된 졸업 표본40PA/15IP 부족 또는 유효기간 경과 · 동일 형식 인증 평가전 자료 필요"
            let candidates=DomesticSelection.candidates(seed:seed,month:window.month)
            let simulated=DomesticSelection.simulate(observation:observation,seats:window.month == 7 ? seats.filter {$0.route == .rookie}:seats,
                candidates:candidates,carried:carried,sample:sample,sampleReason:reason)
            value.version=2
            value.selection=DomesticSelection(rule:"domestic-selection-v1",seed:seed,priorMarket:window.month == 4 ? "연간 신규 시장":april == nil ? "고정 가상4월 NPC 충원 이월":"4월 고정 NPC 충원 이월 · 미수락 내 예약 해제",
                sample:sample,sampleReason:reason,seats:seats,candidates:candidates,carried:carried,picks:simulated.picks,results:simulated.results)
        }
        try value.validate(player:player,calendar:calendar)
        context.insert(try CareerContractEvaluation(playerID:player.id,snapshot:value))
        _ = try ContractOfferStore.insertCurrent(player:player,calendar:calendar,in:context)
        return true
    }
    static func graduationSample(player:CareerPlayer,calendar:CareerCalendarState,observation:ScoutingObservation,in context:ModelContext) throws -> DomesticSelectionSample? {
        guard observation.age == 20 else {return nil}
        let date=try GameDate(observation.observedDate),origin=try GameDate(calendar.originDate),id=player.id
        let records=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        // Last completed high-school season only; never search older better performance or mix years/modes.
        let lastYear=min(date.year,origin.year+18-player.startAge)
        guard lastYear >= origin.year else {return nil}
        let summary=try CareerSeasonStore.snapshot(player:player,state:calendar,year:lastYear,records:records)
        guard summary.finalized,let end=summary.league.fixtures.map(\.date).max(),end <= date,end.days(to:date) <= 730 else {return nil}
        var groups:[String:ScoutingSampleGroup]=[:]
        for row in records where row.completed && row.appearance {
            guard try GameDate(row.gameDate).year == lastYear else {continue}
            let match=try row.snapshot()
            guard let source=match.scoutingEnvironment,let perf=match.scoutingPerformance else {continue}
            var group=groups[source] ?? ScoutingSampleGroup(id:source)
            if group.performance == nil {group.performance=perf.version == 2 ? .tracked:MatchScoutingPerformance()}
            try group.performance?.add(perf);try group.totals.add(match.line);groups[source]=group
        }
        let comparisons=try groups.values.compactMap { group -> ScoutingPerformanceComparison? in
            guard let perf=group.performance,(perf.version == 2 || !perf.manual),
                  player.role == .batter ? group.hasBatterMinimum:group.hasPitcherMinimum,
                  let ref=try ScoutingReferenceSimulation.make(environment:group.id,role:player.role,position:player.role == .batter ? player.positionRaw:"P"),
                  let v=perf.contribution(group.totals.line,role:player.role),let vr=ref.value else {return nil}
            return ScoutingPerformanceComparison(id:group.id,totals:group.totals,performance:perf,reference:ref,value:v,
                correction:ScoutingContractFit.correction(value:v,reference:vr,n:perf.sample(group.totals.line,role:player.role)),verified:true,reason:"졸업한 마지막 고교 공식시즌 · 동일 환경/표준 NPC")
        }
        guard let source=ScoutingContractFit.selected(comparisons,role:player.role) else {return nil}
        return DomesticSelectionSample(kind:"졸업 고교 공식시즌",endDate:end.description,comparison:source)
    }
    static func registerCurrent(in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractEvaluationError.pendingChanges}
        do {
            let calendars = try context.fetch(FetchDescriptor<CareerCalendarState>())
            for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
                guard let calendar = calendars.first(where:{$0.playerID == player.id}) else {throw ContractEvaluationError.invalid}
                _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
                _ = try captureIfDue(player:player,calendar:calendar,in:context)
                _ = try ContractOfferStore.insertCurrent(player:player,calendar:calendar,in:context)
            }
            if context.hasChanges {try save(context)}
        } catch {context.rollback();throw error}
    }
    static func acknowledge(player:CareerPlayer,calendar:CareerCalendarState,key:String,date:String,revision:Int,
                            in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractEvaluationError.pendingChanges}
        guard player.gameDate == date,calendar.revision == revision,
              let row = try records(player:player,calendar:calendar,in:context).first(where:{$0.key == key}) else {throw ContractEvaluationError.invalid}
        guard !row.acknowledged else {return}
        row.acknowledged = true
        do {try save(context)} catch {context.rollback();throw error}
    }
}


// Offer issuance is independent of the immutable evaluation payload and acknowledgement flag.
enum CareerSchemaV11: VersionedSchema {
    static let versionIdentifier = Schema.Version(11,0,0)
    static var models:[any PersistentModel.Type] {CareerSchemaV10.models+[ContractOffer.self]}
    @Model final class ContractOffer {
        @Attribute(.unique) var key:String
        var playerID:UUID
        var payload:Data
        init(playerID:UUID,value:DomesticOfferPacket) throws {
            self.playerID=playerID;key=value.evaluationKey;payload=try JSONEncoder().encode(value)
        }
        func snapshot(evaluation:CareerContractEvaluation,player:CareerPlayer,calendar:CareerCalendarState) throws -> DomesticOfferPacket {
            guard playerID == player.id,key == evaluation.key else {throw ContractOfferError.invalid}
            let value=try JSONDecoder().decode(DomesticOfferPacket.self,from:payload)
            try value.validate(evaluation:evaluation.snapshot(player:player,calendar:calendar),key:key,today:GameDate(player.gameDate))
            return value
        }
    }
}
typealias CareerContractOffer = CareerSchemaV11.ContractOffer

@MainActor enum ContractOfferStore {
    static func records(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> [CareerContractOffer] {
        guard context.container.schema.entities.contains(where:{$0.name == "ContractOffer"}) else {return []}
        let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context),id=player.id
        let rows=try context.fetch(FetchDescriptor<CareerContractOffer>(predicate:#Predicate {$0.playerID == id}))
        guard Set(rows.map(\.key)).count == rows.count else {throw ContractOfferError.invalid}
        for row in rows {
            guard let evaluation=evaluations.first(where:{$0.key == row.key}) else {throw ContractOfferError.invalid}
            _ = try row.snapshot(evaluation:evaluation,player:player,calendar:calendar)
        }
        return rows.sorted {$0.key > $1.key}
    }
    // Parent evaluation/date transaction owns the one save, including old active V10 imports.
    @discardableResult static func insertCurrent(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> Bool {
        guard context.container.schema.entities.contains(where:{$0.name == "ContractOffer"}) else {return false}
        let rows=try records(player:player,calendar:calendar,in:context),date=try GameDate(player.gameDate)
        guard let window=ContractEvaluationWindow.containing(date) else {return false}
        let key=CareerContractEvaluation.key(player.id,window.id)
        guard !rows.contains(where:{$0.key == key}),
              let evaluation=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context).first(where:{$0.key == key}) else {return false}
        let snapshot=try evaluation.snapshot(player:player,calendar:calendar)
        guard snapshot.version == 2 else {return false}
        let value=try DomesticOfferPacket.make(evaluation:snapshot,key:key,on:date)
        try value.validate(evaluation:snapshot,key:key,today:date)
        context.insert(try CareerContractOffer(playerID:player.id,value:value));return true
    }
}


enum CareerSchemaV12:VersionedSchema {
    static let versionIdentifier=Schema.Version(12,0,0)
    static var models:[any PersistentModel.Type] {CareerSchemaV11.models+[ContractRegistration.self]}
    @Model final class ContractRegistration {
        @Attribute(.unique) var playerID:UUID
        var payload:Data
        init(_ value:CareerContractJournal) throws {playerID=value.playerID;payload=try JSONEncoder().encode(value)}
    }
}
typealias CareerContractRegistration=CareerSchemaV12.ContractRegistration

@MainActor enum ContractRegistrationStore {
    static func row(player:CareerPlayer,in context:ModelContext) throws -> CareerContractRegistration? {
        guard context.container.schema.entities.contains(where:{$0.name == "ContractRegistration"}) else {return nil}
        let id=player.id,rows=try context.fetch(FetchDescriptor<CareerContractRegistration>(predicate:#Predicate {$0.playerID == id}))
        guard rows.count <= 1 else {throw ContractRegistrationError.invalid};return rows.first
    }
    static func journal(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> CareerContractJournal {
        guard calendar.playerID == player.id else {throw ContractRegistrationError.invalid}
        guard let row=try row(player:player,in:context) else {return CareerContractJournal(playerID:player.id)}
        guard let value=try? JSONDecoder().decode(CareerContractJournal.self,from:row.payload) else {throw ContractRegistrationError.invalid}
        let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
        let offers=try ContractOfferStore.records(player:player,calendar:calendar,in:context).flatMap {row in
            guard let evaluation=evaluations.first(where:{$0.key == row.key}) else {throw ContractRegistrationError.invalid}
            return try row.snapshot(evaluation:evaluation,player:player,calendar:calendar).offers
        }
        try value.validate(player:player,calendar:calendar,offers:offers);return value
    }
    static func decide(player:CareerPlayer,calendar:CareerCalendarState,offerID:String,accept:Bool,date:String,revision:Int,
                       in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        var value=try journal(player:player,calendar:calendar,in:context)
        let kind:DomesticOfferDecisionKind=accept ? .accepted:.rejected
        if let old=value.decisions.first(where:{$0.offerID == offerID}) {
            guard old.kind == kind else {throw ContractRegistrationError.closed};return
        }
        guard date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id,records=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        for record in records {guard try record.snapshot().completed else {throw ContractRegistrationError.busy}}
        let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
        let packets=try ContractOfferStore.records(player:player,calendar:calendar,in:context).map {row -> DomesticOfferPacket in
            guard let evaluation=evaluations.first(where:{$0.key == row.key}) else {throw ContractRegistrationError.invalid}
            return try row.snapshot(evaluation:evaluation,player:player,calendar:calendar)
        }
        let offers=packets.flatMap(\.offers),today=try GameDate(date)
        guard let offer=offers.first(where:{$0.id == offerID}) else {throw ContractRegistrationError.invalid}
        guard !(try offer.isExpired(on:today)) else {throw ContractRegistrationError.expired}
        if accept {
            guard try value.current(on:today) == nil else {throw ContractRegistrationError.registered}
            guard (20...23).contains(try calendar.age(of:player)) else {throw ContractRegistrationError.invalid}
            value.memberships.append(try CareerMembership.make(offer:offer,on:today,origin:GameDate(calendar.originDate),startAge:player.startAge))
        }
        value.decisions.append(DomesticOfferDecision(offerID:offerID,kind:kind,date:date))
        if accept {
            for other in offers where other.id != offerID && !value.decisions.contains(where:{$0.offerID == other.id}) {
                if !(try other.isExpired(on:today)) {value.decisions.append(DomesticOfferDecision(offerID:other.id,kind:.closed,date:date))}
            }
        }
        value.revision += 1
        try value.validate(player:player,calendar:calendar,offers:offers)
        do {
            if let row=try row(player:player,in:context) {row.payload=try JSONEncoder().encode(value)}
            else {context.insert(try CareerContractRegistration(value))}
            for packet in packets where packet.offers.contains(where:{offer in value.decisions.contains {$0.offerID == offer.id}}) {
                evaluations.first(where:{$0.key == packet.evaluationKey})?.acknowledged=true
            }
            calendar.revision += 1
            try save(context)
        } catch {context.rollback();throw error}
    }
}
