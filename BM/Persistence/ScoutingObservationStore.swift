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
    static let pitches: [String: (family: String, speed: Double)] = Dictionary(uniqueKeysWithValues:
        PitchType.allCases.map { ($0.rawValue, (family: $0.family, speed: 145 + $0.speedOffset)) })
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
        guard [1,2,3,4,5].contains(version), evaluationVersion == "contracts-role-v1", cycle.index == period,
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
        let row = try CareerScoutingReport(value); context.insert(row)
        try CareerProjectStore.observe(player:player,calendar:calendar,observation:value,reportID:row.key,in:context)
        return row
    }
    static func currentObservation(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> ScoutingObservation {
        let cycle = try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(player.gameDate))
        let live = try ScoutingReportSnapshot.load(player: player, calendar: calendar, in: context)
        let position = FieldPosition(rawValue: player.positionRaw)
        let profile = player.role == .batter ? try PlayerPositionStore.profile(playerID: player.id, in: context) : nil
        let mastery = try position.flatMap { try profile?.snapshot().skill($0).mastery }
        var value = ScoutingObservation(playerID: player.id, origin: calendar.originDate, period: cycle.index,
            periodStart: cycle.start.description, observedDate: live.date.description, nextDate: cycle.next.description,
            name: player.name, number: player.jerseyNumber, school: try calendar.registration(for:player)?.name ?? (ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).retryReleases.isEmpty == false ? "무소속":player.schoolName), role: player.role,
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
    var retry:DomesticRetryReview?
    var college:CollegeProReview?
    func validate(player:CareerPlayer,calendar:CareerCalendarState) throws {
        let date = try GameDate(evaluatedDate)
        guard [1,2,3,4,5,6].contains(version), rule == "contracts-window-v1", [4,7,11].contains(window.month),
              (1...9998).contains(window.year), window == ContractEvaluationWindow.containing(date),
              observation.playerID == player.id, observation.origin == calendar.originDate,
              observation.role == player.role, observation.observedDate == evaluatedDate,
              observation.age == (try GameDate(calendar.originDate).age(startingAt:player.startAge,on:date)),
              date <= (try GameDate(player.gameDate)), calendarRevision >= 0,
              !routes.isEmpty, routes == (version == 6 ? ["대학 재학생 프로 진출"]:version == 3 ? ["국내 육성팀 재계약"]:[4,5].contains(version) ? ["무소속 국내 육성팀 재입단"]:window.routes(age:observation.age,affiliation:affiliation.stage)),
              !pending.isEmpty else { throw ContractEvaluationError.invalid }
        try observation.validate()
        guard version == 6 || college == nil else {throw ContractEvaluationError.invalid}
        if version == 6 {
            guard let college,selection == nil,renewal == nil,retry == nil,
                  college == (try CollegeProReview.make(observation:observation,member:college.membership,window:window)) else {throw ContractEvaluationError.invalid}
        } else if [4,5].contains(version) {
            guard let retry,selection == nil,renewal == nil,
                  retry == (try DomesticRetryReview.make(observation:observation,release:retry.release,window:window,certificate:version == 5 ? retry.certificate:nil,certificationEnabled:version == 5)) else {throw ContractEvaluationError.invalid}
        } else if version == 3 {
            guard let renewal,retry == nil,selection == nil else {throw ContractEvaluationError.invalid}
            try renewal.validate(observation:observation,key:player.id.uuidString+":"+window.id,window:window)
        } else if version == 1 {guard selection == nil,renewal == nil,retry == nil else {throw ContractEvaluationError.invalid}}
        else {
            guard let selection,renewal == nil,retry == nil, affiliation.stage == .unsigned else {throw ContractEvaluationError.invalid}
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
                  journal.version == 1,try journal.current(on:GameDate(value.evaluatedDate),excludingRenewal:review.offer?.id) == review.membership,journal.decisions.contains(where:{$0.offerID == review.membership.offerID && $0.kind == .accepted}) else {throw ContractEvaluationError.invalid}
            let source=try context.fetch(FetchDescriptor<CareerContractOffer>(predicate:#Predicate {$0.playerID == id})).flatMap {try JSONDecoder().decode(DomesticOfferPacket.self,from:$0.payload).offers}
            guard let original=source.first(where:{$0.id == review.membership.offerID}),original.roleID == review.roleID,
                  journal.memberships.contains(try CareerMembership.make(offer:original,on:GameDate(review.membership.since),origin:GameDate(calendar.originDate),startAge:player.startAge)) else {throw ContractEvaluationError.invalid}
        }
        for value in snapshots where value.version == 6 {
            guard let college=value.college,let row=try ContractRegistrationStore.row(player:player,in:context),
                  let journal=try? JSONDecoder().decode(CareerContractJournal.self,from:row.payload),
                  journal.playerID == player.id,journal.version == 1,
                  try journal.current(on:GameDate(value.evaluatedDate)) == college.membership else {throw ContractEvaluationError.invalid}
        }
        for value in snapshots where [4,5].contains(value.version) {
            guard let retry=value.retry,let row=try ContractRegistrationStore.row(player:player,in:context),
                  let journal=try? JSONDecoder().decode(CareerContractJournal.self,from:row.payload),
                  journal.retryReleases.contains(retry.release),
                  try journal.current(on:GameDate(value.evaluatedDate),excludingMembership:value.retry?.results.first(where:{$0.selected}).map {value.observation.playerID.uuidString+":"+value.window.id+"/"+$0.id}) == nil else {throw ContractEvaluationError.invalid}
            if let certificate=retry.certificate {
                guard value.version == 5,let stored=try CertificationStore.assessment(player:player,releaseID:retry.release.membershipOfferID,window:value.window,in:context),stored == certificate else {throw ContractEvaluationError.invalid}
            }
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
        if try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).overseasCareer?.hasPending(on:player.gameDate) == true {return false}
        if let member=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).current(on:GameDate(player.gameDate)) {
            if member.route == .college {
                let journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
                guard window.month == 11,!(journal.collegeTransitions ?? []).contains(where:{$0.source.membershipOfferID == member.offerID}),
                      try CollegeProReview.eligible(member:member,age:calendar.age(of:player),on:GameDate(player.gameDate)) else {return false}
                guard let history=try CareerPathStore.record(player:player,calendar:calendar,in:context)?.snapshot(player:player,calendar:calendar) else {throw ContractEvaluationError.invalid}
                let observation=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
                let review=try CollegeProReview.make(observation:observation,member:member,window:window)
                let value=ContractEvaluationSnapshot(version:6,rule:"contracts-window-v1",window:window,evaluatedDate:player.gameDate,calendarRevision:calendar.revision,affiliation:history.current,routes:["대학 재학생 프로 진출"],observation:observation,pending:["성인 Vref 미검증 · P=0 중립","수락 시 다음 해4월1일 전환 · 현재 대학 시즌/학적 원본 보존"],college:review)
                try value.validate(player:player,calendar:calendar)
                context.insert(try CareerContractEvaluation(playerID:player.id,snapshot:value))
                _ = try ContractOfferStore.insertCurrent(player:player,calendar:calendar,in:context);return true
            }
            guard member.level == "domestic-development",window.month == 11 else {return false}
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
                pending:["성인 경기 비교 기준 미검증 · 성적 보정 P=0 중립","권리 해제/방출은 별도 결정이며 경제 만료로 자동 처리하지 않습니다."],renewal:review)
            try value.validate(player:player,calendar:calendar)
            context.insert(try CareerContractEvaluation(playerID:player.id,snapshot:value));return true
        }
        guard let history = try CareerPathStore.record(player:player,calendar:calendar,in:context)?.snapshot(player:player,calendar:calendar) else {throw ContractEvaluationError.invalid}
        let journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        if let release=journal.activeRetryRelease,[4,7].contains(window.month),try calendar.age(of:player) >= 20 {
            // A same-day release is not a pre-existing unsigned sample for today's review.
            guard release.date < player.gameDate else {return false}
            let observation=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
            let certificate=try CertificationStore.assessment(player:player,releaseID:release.membershipOfferID,window:window,in:context)
            let retry=try DomesticRetryReview.make(observation:observation,release:release,window:window,certificate:certificate,certificationEnabled:true)
            let value=ContractEvaluationSnapshot(version:5,rule:"contracts-window-v1",window:window,evaluatedDate:player.gameDate,
                calendarRevision:calendar.revision,affiliation:history.current,routes:["무소속 국내 육성팀 재입단"],observation:observation,
                pending:["성인 Vref 미검증 · P=0 중립","육성 표본 또는 해당 창 인증 평가전 · 같은 창 재평가 없음"],retry:retry)
            try value.validate(player:player,calendar:calendar)
            context.insert(try CareerContractEvaluation(playerID:player.id,snapshot:value))
            _ = try ContractOfferStore.insertCurrent(player:player,calendar:calendar,in:context);return true
        }
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
        guard [2,4,5,6].contains(snapshot.version) else {return false}
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
        try value.validate(player:player,calendar:calendar,offers:offers,reviews:Dictionary(uniqueKeysWithValues:try evaluations.compactMap {row in try row.snapshot(player:player,calendar:calendar).renewal.map {(row.key,$0)}}))
        if let service=value.overseasCareer?.service {
            let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
            let earned=try GameProSeasonEvidence.collect(owner:value,role:player.role,today:GameDate(player.gameDate),rows:rows)
            guard Set(service.map(\.year)).count == service.count,service.allSatisfy({earned.contains($0)}) else {throw ContractRegistrationError.invalid}
        }
        if let service=value.overseasCareer?.faService {
            let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
            let earned=try FASeasonEvidence.collect(owner:value,role:player.role,on:GameDate(player.gameDate),rows:rows)
            guard service.allSatisfy({earned.contains($0)}) else {throw ContractRegistrationError.invalid}
        }
        try value.validateSeasonGoals(today:GameDate(player.gameDate),offers:offers)
        try value.validateDevelopment(today:GameDate(player.gameDate))
        if value.developmentProjects != nil || value.developmentReviews != nil || value.gamePlanReports != nil || value.specialTrainings != nil || value.specialAssessments != nil || value.specialReports != nil || value.seasonGoalReports != nil || value.seasonReviews != nil {
            var sources=Dictionary(uniqueKeysWithValues:(value.overseasReports ?? []).map {($0.id,($0.period,$0.observation.observedDate))})
            var reviewSources=Dictionary(uniqueKeysWithValues:(value.overseasReports ?? []).map {($0.id,($0.observation,$0.comparisons))})
            for row in try ScoutingObservationStore.reports(player:player,calendar:calendar,in:context) {
                let observation=try row.snapshot();sources[row.key]=(observation.period,observation.observedDate)
                reviewSources[row.key]=(observation,observation.contractFit?.comparisons ?? [])
            }
            try value.validateProjects(origin:calendar.originDate,today:GameDate(player.gameDate),reports:sources)
            try value.validateGamePlanReports(origin:calendar.originDate,today:GameDate(player.gameDate),reports:sources)
            try value.validateSeasonObservations(origin:calendar.originDate,today:GameDate(player.gameDate),reports:sources)
            try value.validateSeasonReviews(today:GameDate(player.gameDate),sources:reviewSources)
            try value.validateSpecial(origin:calendar.originDate,today:GameDate(player.gameDate),reports:sources)
            try GoalSpecialStore.validateTrainings(owner:value,player:player,in:context)
        }
        return value
    }
    static func releaseCandidate(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> (key:String,review:DomesticRenewalReview,eligible:Bool)? {
        let value=try journal(player:player,calendar:calendar,in:context),today=try GameDate(player.gameDate)
        guard let member=try value.current(on:today),member.route == .rookie else {return nil}
        let rows=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
        let reviews=Dictionary(uniqueKeysWithValues:try rows.compactMap {row in try row.snapshot(player:player,calendar:calendar).renewal.map {(row.key,$0)}})
        guard let key=reviews.keys.sorted().last(where:{reviews[$0]?.membership.offerID == member.offerID}),let review=reviews[key] else {return nil}
        return (key,review,try value.releaseEligible(review:review,key:key,on:today,reviews:reviews))
    }
    private static func requireIdle(player:CareerPlayer,context:ModelContext) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {
            guard try row.snapshot().completed else {throw ContractRegistrationError.busy}
        }
    }
    private static func saveDecision(_ value:CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,evaluationKey:String,
                                     in context:ModelContext,save:CalendarProgression.Save) throws {
        do {
            guard let row=try row(player:player,in:context) else {throw ContractRegistrationError.invalid}
            row.payload=try JSONEncoder().encode(value)
            _ = try journal(player:player,calendar:calendar,in:context)
            try ContractEvaluationStore.records(player:player,calendar:calendar,in:context).first {$0.key == evaluationKey}?.acknowledged=true
            calendar.revision += 1;try save(context)
        } catch {context.rollback();throw error}
    }
    static func rejectRenewal(player:CareerPlayer,calendar:CareerCalendarState,offerID:String,date:String,revision:Int,
                              in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        var value=try journal(player:player,calendar:calendar,in:context)
        if (value.renewalRejections ?? []).contains(where:{$0.offerID == offerID}) {return}
        guard !(value.renewals ?? []).contains(where:{$0.terms.id == offerID}) else {throw ContractRegistrationError.closed}
        guard date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try requireIdle(player:player,context:context)
        guard let row=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context).first(where:{try $0.snapshot(player:player,calendar:calendar).renewal?.offer?.id == offerID}),
              let terms=try row.snapshot(player:player,calendar:calendar).renewal?.offer else {throw ContractRegistrationError.invalid}
        guard date >= terms.issuedDate,date <= terms.expiresDate else {throw ContractRegistrationError.expired}
        var rejected=value.renewalRejections ?? [];rejected.append(.init(offerID:offerID,date:date));value.renewalRejections=rejected;value.revision += 1
        try saveDecision(value,player:player,calendar:calendar,evaluationKey:row.key,in:context,save:save)
    }
    static func release(player:CareerPlayer,calendar:CareerCalendarState,evaluationKey:String,date:String,revision:Int,
                        in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        var value=try journal(player:player,calendar:calendar,in:context)
        if (value.releases ?? []).contains(where:{$0.evaluationKey == evaluationKey}) {return}
        guard date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try requireIdle(player:player,context:context)
        guard let candidate=try releaseCandidate(player:player,calendar:calendar,in:context),candidate.key == evaluationKey,candidate.eligible else {throw ContractRegistrationError.registered}
        var released=value.releases ?? [];released.append(.init(membershipOfferID:candidate.review.membership.offerID,date:date,evaluationKey:evaluationKey));value.releases=released;value.revision += 1
        try saveDecision(value,player:player,calendar:calendar,evaluationKey:evaluationKey,in:context,save:save)
    }

    static func acceptRenewal(player:CareerPlayer,calendar:CareerCalendarState,offerID:String,date:String,revision:Int,
                              in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        var value=try journal(player:player,calendar:calendar,in:context)
        if (value.renewals ?? []).contains(where:{$0.terms.id == offerID}) {return}
        guard !(value.renewalRejections ?? []).contains(where:{$0.offerID == offerID}) else {throw ContractRegistrationError.closed}
        guard date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id,records=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        for record in records {guard try record.snapshot().completed else {throw ContractRegistrationError.busy}}
        let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
        guard let evaluation=try evaluations.first(where:{try $0.snapshot(player:player,calendar:calendar).renewal?.offer?.id == offerID}),
              let review=try evaluation.snapshot(player:player,calendar:calendar).renewal,let terms=review.offer else {throw ContractRegistrationError.invalid}
        let today=try GameDate(date)
        guard today >= (try GameDate(terms.issuedDate)) else {throw ContractRegistrationError.stale}
        guard today <= (try GameDate(terms.expiresDate)) else {throw ContractRegistrationError.expired}
        guard try value.current(on:today) == review.membership else {throw ContractRegistrationError.stale}
        var accepted=value.renewals ?? []
        accepted.append(DomesticRenewalAcceptance(membershipOfferID:review.membership.offerID,date:date,terms:terms))
        value.renewals=accepted;value.revision += 1
        do {
            guard let row=try row(player:player,in:context) else {throw ContractRegistrationError.invalid}
            row.payload=try JSONEncoder().encode(value)
            _ = try journal(player:player,calendar:calendar,in:context)
            evaluation.acknowledged=true;calendar.revision += 1
            try save(context)
        } catch {context.rollback();throw error}
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
            guard value.overseasCareer?.hasPending(on:date) != true else {throw ContractRegistrationError.registered}
            if let entry=offer.collegeEntry {
                guard let member=try value.current(on:today),member.offerID == entry.membershipOfferID,
                      try CollegeProReview.eligible(member:member,age:calendar.age(of:player),on:today),
                      !(value.collegeTransitions ?? []).contains(where:{$0.source.membershipOfferID == member.offerID}) else {throw ContractRegistrationError.registered}
                value.collegeTransitions=(value.collegeTransitions ?? [])+[CollegeProTransition(offerID:offer.id,source:entry,acceptedDate:date)]
            } else {guard try value.current(on:today) == nil else {throw ContractRegistrationError.registered}}
            guard offer.reentry == true ? try calendar.age(of:player) >= 20:(20...23).contains(try calendar.age(of:player)) else {throw ContractRegistrationError.invalid}
            value.memberships.append(try CareerMembership.make(offer:offer,on:offer.collegeEntry.map {try GameDate($0.effectiveDate)} ?? today,origin:GameDate(calendar.originDate),startAge:player.startAge))
        }
        value.decisions.append(DomesticOfferDecision(offerID:offerID,kind:kind,date:date))
        if accept {
            for other in offers where other.id != offerID && !value.decisions.contains(where:{$0.offerID == other.id}) {
                if !(try other.isExpired(on:today)) {value.decisions.append(DomesticOfferDecision(offerID:other.id,kind:.closed,date:date))}
            }
        }
        value.revision += 1
        try value.validate(player:player,calendar:calendar,offers:offers,reviews:Dictionary(uniqueKeysWithValues:try evaluations.compactMap {row in try row.snapshot(player:player,calendar:calendar).renewal.map {(row.key,$0)}}))
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

@MainActor enum OverseasEligibilityStore {
    static func current(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> OverseasEligibilitySnapshot {
        let journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard let history=try CareerPathStore.record(player:player,calendar:calendar,in:context)?.snapshot(player:player,calendar:calendar) else {throw CareerPathError.invalid}
        let id=player.id,today=try GameDate(player.gameDate)
        let rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        let completed=try rows.filter {try $0.completed && $0.appearance && GameDate($0.gameDate) <= today}
        for year in Set(try completed.map {try GameDate($0.gameDate).year}) {
            _ = try AnnualLeagueStore.snapshot(player:player,state:calendar,year:year,records:rows)
        }
        let evidence=try completed.map {record in OverseasMatchEvidence(key:record.key,date:record.gameDate,level:try record.snapshot().competition ?? "highschool")}.sorted {$0.key<$1.key}
        let current=try journal.current(on:today)
        var value=OverseasCareerEvidence(version:2,playerID:player.id,date:player.gameDate,age:try calendar.age(of:player),calendarRevision:calendar.revision,registrationRevision:journal.revision,historySource:history.source,origin:calendar.originDate,startAge:player.startAge,memberships:try journal.membershipHistory().map {try journal.projected($0,on:today)},current:current,pendingCollegeEntry:journal.collegeTransitions?.contains {$0.source.effectiveDate > player.gameDate} == true,release:journal.retryReleases.last,matches:evidence)
        let state=journal.overseasCareer
        value.approvedRoutes=state?.consents?.contains(where:{$0.approved && $0.sourceOfferID == current?.offerID && $0.date <= player.gameDate && $0.expires >= player.gameDate}) == true ? OverseasRoute.allCases:[]
        value.gameProYears=state?.service.map {Array(Set($0.map(\.year))).sorted()}
        value.pendingForeignEntry=state?.hasPending(on:player.gameDate) == true
        if let proof=try state?.mobility(owner:journal,on:today) {
            let major=proof.source.level == "mlb-first-team" || (value.age>=25 && Set((proof.internationalService ?? []).map(\.year)).count>=6)
            value.approvedRoutes=major ? [.npbFirstTeam,.mlbFirstTeam]:[.npbFirstTeam]
        }
        return try OverseasEligibilitySnapshot.make(value)
    }
    static func capture(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,
                        save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        guard date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {
            guard try row.snapshot().completed else {throw ContractRegistrationError.busy}
        }
        let snapshot=try current(player:player,calendar:calendar,in:context)
        var journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        // Read-only assessment capture does not increment game/calendar/registration revisions.
        if let old=journal.overseasEligibility?.first(where:{$0.id == snapshot.id}) {
            guard old == snapshot else {throw ContractEvaluationError.invalid};return
        }
        journal.overseasEligibility=(journal.overseasEligibility ?? [])+[snapshot]
        try snapshot.validate(playerID:player.id,today:GameDate(player.gameDate))
        do {
            if let row=try ContractRegistrationStore.row(player:player,in:context) {row.payload=try JSONEncoder().encode(journal)}
            else {context.insert(try CareerContractRegistration(journal))}
            try save(context)
        } catch {context.rollback();throw error}
    }
}

@MainActor enum OverseasReportStore {
    static func current(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> OverseasScoutingReport? {
        let period=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(player.gameDate)).index
        return try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).overseasReports?.first {$0.period == period}
    }
    static func capture(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,
                        save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        guard date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {guard try row.snapshot().completed else {throw ContractRegistrationError.busy}}
        let period=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(player.gameDate)).index
        var journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        if journal.overseasReports?.contains(where:{$0.period == period}) == true {return}
        let eligibility=try OverseasEligibilityStore.current(player:player,calendar:calendar,in:context)
        let observation=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
        let report=try OverseasScoutingReport.make(observation:observation,eligibility:eligibility)
        try report.validate(playerID:player.id,today:GameDate(date))
        journal.overseasReports=(journal.overseasReports ?? [])+[report]
        try CareerProjectStore.appendReview(owner:&journal,player:player,observation:observation,reportID:report.id,in:context)
        try MatchPlanReportStore.append(owner:&journal,player:player,calendar:calendar,observation:observation,reportID:report.id,in:context)
        try GoalSpecialStore.appendEvidence(owner:&journal,player:player,calendar:calendar,observation:observation,reportID:report.id,in:context)
        try ClubSeasonReportStore.append(owner:&journal,player:player,calendar:calendar,observation:observation,reportID:report.id,in:context)
        do {
            if let row=try ContractRegistrationStore.row(player:player,in:context) {row.payload=try JSONEncoder().encode(journal)}
            else {context.insert(try CareerContractRegistration(journal))}
            try save(context)
        } catch {context.rollback();throw error}
    }
}

@MainActor enum OverseasContractStore {
    private static func requireIdle(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        guard player.gameDate == date,calendar.revision == revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {guard try row.snapshot().completed else {throw ContractRegistrationError.busy}}
    }
    private static func write(_ value:CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext,save:CalendarProgression.Save) throws {
        do {
            if let row=try ContractRegistrationStore.row(player:player,in:context) {row.payload=try JSONEncoder().encode(value)}
            else {context.insert(try CareerContractRegistration(value))}
            _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
            calendar.revision += 1;try save(context)
        } catch {context.rollback();throw error}
    }
    static func register(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        if value.registrationDate != nil {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard try calendar.age(of:player) >= 20 else {throw ContractRegistrationError.invalid}
        value.registrationDate=date;owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func evaluate(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        guard let window=ContractEvaluationWindow.containing(try GameDate(date)) else {throw OverseasProgressError.window}
        if value.evaluations.contains(where:{$0.window == window}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let report=try OverseasReportStore.current(player:player,calendar:calendar,in:context) else {throw OverseasProgressError.report}
        let member=try owner.current(on:GameDate(date)),reserved=value.hasPending(on:date) || value.hasPendingRenewal(on:date) || owner.collegeTransitions?.contains {$0.source.effectiveDate > date} == true
        let evaluation:OverseasOfferEvaluation
        if let proof=try value.mobility(owner:owner,on:GameDate(date)) {
            evaluation=try OverseasOfferEvaluation.makeMobility(report:report,window:window,on:GameDate(date),registrationDate:value.registrationDate,member:member,context:proof,reserved:reserved)
        } else if let member,["domestic-first-team","npb-first-team"].contains(member.level),let consent=value.consents?.last(where:{$0.sourceOfferID == member.offerID && $0.date <= date && $0.expires >= date}) {
            let proof=OverseasProContext(consent:consent,service:value.service ?? [])
            evaluation=try OverseasOfferEvaluation.makeProfessional(report:report,window:window,on:GameDate(date),registrationDate:value.registrationDate,member:member,context:proof,reserved:reserved || owner.renewals?.contains {$0.membershipOfferID == member.offerID && $0.terms.effectiveDate > date} == true)
        } else {evaluation=try OverseasOfferEvaluation.make(report:report,window:window,on:GameDate(date),registrationDate:value.registrationDate,member:member,reserved:reserved)}
        value.evaluations.append(evaluation);owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func decide(player:CareerPlayer,calendar:CareerCalendarState,offerID:String,accept:Bool,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        let kind:DomesticOfferDecisionKind=accept ? .accepted:.rejected
        if let old=value.decisions.first(where:{$0.offerID == offerID}) {guard old.kind == kind else {throw ContractRegistrationError.closed};return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let evaluation=value.evaluations.first(where:{$0.offers.contains {$0.id == offerID}}),let offer=evaluation.offers.first(where:{$0.id == offerID}) else {throw ContractRegistrationError.invalid}
        guard date >= offer.issued,date <= offer.expires else {throw ContractRegistrationError.expired}
        if accept {
            guard owner.renewals?.contains(where:{$0.membershipOfferID == evaluation.sourceMembershipID && $0.terms.effectiveDate > date}) != true,
                  !value.hasPending(on:date),!value.hasPendingRenewal(on:date),owner.collegeTransitions?.contains(where:{$0.source.effectiveDate > date}) != true,
                  try owner.current(on:GameDate(date))?.offerID == evaluation.sourceMembershipID else {throw ContractRegistrationError.registered}
            value.transitions.append(OverseasTransition(offerID:offerID,sourceMembershipID:evaluation.sourceMembershipID,acceptedDate:date,destination:offer.membership()))
            for other in value.evaluations.flatMap(\.offers) where other.id != offerID && !value.decisions.contains(where:{$0.offerID == other.id}) && other.issued <= date && other.expires >= date {
                value.decisions.append(OverseasDecision(offerID:other.id,kind:.closed,date:date))
            }
            let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
            let domestic=try ContractOfferStore.records(player:player,calendar:calendar,in:context).flatMap {row -> [DomesticContractOffer] in
                guard let evaluation=evaluations.first(where:{$0.key == row.key}) else {throw ContractRegistrationError.invalid}
                return try row.snapshot(evaluation:evaluation,player:player,calendar:calendar).offers
            }
            for other in domestic where !owner.decisions.contains(where:{$0.offerID == other.id}) && other.issuedDate <= date && other.expiresDate >= date {
                owner.decisions.append(DomesticOfferDecision(offerID:other.id,kind:.closed,date:date))
            }
        }
        value.decisions.append(OverseasDecision(offerID:offerID,kind:kind,date:date))
        owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}

@MainActor extension OverseasContractStore {
    static func promoteDomestic(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        guard let member=try owner.current(on:GameDate(date)) else {throw ContractRegistrationError.registered}
        if value.promotions?.contains(where:{$0.sourceOfferID == member.offerID}) == true {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard member.level == "domestic-development",let window=ContractEvaluationWindow.containing(try GameDate(date)),window.month == 11,
              !value.hasPending(on:date),let report=try OverseasReportStore.current(player:player,calendar:calendar,in:context),
              report.eligibility.evidence.current?.offerID == member.offerID,report.eligibility.evidence.current?.level == member.level,
              let h=report.observation.grades.compactMap(\.score).max(),h >= 65,
              let source=report.selected else {throw OverseasProgressError.requirements}
        let sample=player.role == .batter ? source.totals.line.plateAppearances:source.totals.line.pitchingOuts
        guard sample >= (player.role == .batter ? 40:45) else {throw OverseasProgressError.requirements}
        let promotion=CareerLevelPromotion(id:member.offerID+":promotion:"+window.id,sourceOfferID:member.offerID,reportID:report.id,date:date,effective:try CollegeProReview.effective(after:GameDate(date)).description,fromLevel:member.level,toLevel:"domestic-first-team",teamID:member.teamID.replacingOccurrences(of:"dev-",with:"pro-"),h:h,sampleCount:sample)
        value.promotions=(value.promotions ?? [])+[promotion];owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func collectService(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        let earned=try GameProSeasonEvidence.collect(owner:owner,role:player.role,today:GameDate(date),rows:rows)
        if value.service == earned {return}
        value.service=earned;owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func requestConsent(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        guard let window=ContractEvaluationWindow.containing(try GameDate(date)),window.month == 11 else {throw OverseasProgressError.window}
        let key=player.id.uuidString+":club-consent-v1:"+window.id
        if value.consents?.contains(where:{$0.id == key}) == true {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let report=try OverseasReportStore.current(player:player,calendar:calendar,in:context),let member=try owner.current(on:GameDate(date)) else {throw ContractEvaluationError.invalid}
        let consent=try ClubTransferConsent.make(report:report,member:member,window:window,on:GameDate(date))
        value.consents=(value.consents ?? [])+[consent];owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}

@MainActor extension OverseasContractStore {
    static func needsEvaluation(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> Bool {
        guard let window=ContractEvaluationWindow.containing(try GameDate(player.gameDate)),try calendar.age(of:player) >= 20 else {return false}
        let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        if let member=try owner.current(on:GameDate(player.gameDate)),try OverseasRenewalReview.eligible(member,on:GameDate(player.gameDate)),window.month == 11,owner.overseasCareer?.hasPendingFA(on:player.gameDate) != true,owner.overseasCareer?.hasPending(on:player.gameDate) != true {
            return !(owner.overseasCareer?.renewalReviews ?? []).contains {$0.window == window}
        }
        guard let value=owner.overseasCareer,value.registrationDate != nil,!value.hasPending(on:player.gameDate),
              !value.evaluations.contains(where:{$0.window == window}),owner.collegeTransitions?.contains(where:{$0.source.effectiveDate > player.gameDate}) != true else {return false}
        let member=try owner.current(on:GameDate(player.gameDate))
        if member == nil || member?.route == .college {return [4,7,11].contains(window.month)}
        return window.month == 11 && (["domestic-first-team","npb-first-team"].contains(member?.level ?? "") || value.hasPendingFA(on:player.gameDate))
    }
}

@MainActor extension OverseasContractStore {
    static func promoteAmerican(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        guard let member=try owner.current(on:GameDate(date)) else {throw ContractRegistrationError.registered}
        if value.promotions?.contains(where:{$0.sourceOfferID == member.offerID}) == true {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard member.level == "mlb-development",let window=ContractEvaluationWindow.containing(try GameDate(date)),window.month == 11,!value.hasPending(on:date),!value.hasPendingRenewal(on:date),
              let report=try OverseasReportStore.current(player:player,calendar:calendar,in:context),report.eligibility.evidence.current?.offerID == member.offerID,report.eligibility.evidence.current?.level == member.level,
              let grade=CareerLevelPromotion.majorRole(report),let h=grade.score,let source=report.selected else {throw OverseasProgressError.requirements}
        let sample=player.role == .batter ? source.totals.line.plateAppearances:source.totals.line.pitchingOuts
        guard sample >= (player.role == .batter ? 100:75) else {throw OverseasProgressError.requirements}
        var promotion=CareerLevelPromotion(id:member.offerID+":us-promotion:"+window.id,sourceOfferID:member.offerID,reportID:report.id,date:date,effective:try CollegeProReview.effective(after:GameDate(date)).description,fromLevel:member.level,toLevel:"mlb-first-team",teamID:member.teamID.replacingOccurrences(of:"us-dev-",with:"us-pro-"),h:h,sampleCount:sample)
        promotion.roleID=grade.id;value.promotions=(value.promotions ?? [])+[promotion];owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}


@MainActor extension OverseasContractStore {
    static func evaluateRenewal(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        guard let window=ContractEvaluationWindow.containing(try GameDate(date)),window.month == 11 else {throw OverseasProgressError.window}
        if (value.renewalReviews ?? []).contains(where:{$0.window == window}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let member=try owner.current(on:GameDate(date)),try OverseasRenewalReview.eligible(member,on:GameDate(date)) else {throw OverseasProgressError.requirements}
        guard let report=try OverseasReportStore.current(player:player,calendar:calendar,in:context) else {throw OverseasProgressError.report}
        guard let initial=value.evaluations.flatMap(\.offers).first(where:{$0.id == member.offerID}) else {throw ContractRegistrationError.invalid}
        let role=value.promotions?.last(where:{$0.sourceOfferID == member.offerID && $0.effective <= date})?.roleID ?? initial.roleID
        let reserved=value.hasPending(on:date) || value.hasPendingRenewal(on:date) || value.hasPendingFA(on:date) || (value.promotions ?? []).contains {$0.sourceOfferID == member.offerID && $0.effective > date}
        let review=try OverseasRenewalReview.make(report:report,member:member,roleID:role,window:window,on:GameDate(date),reserved:reserved)
        value.renewalReviews=(value.renewalReviews ?? [])+[review];owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func decideRenewal(player:CareerPlayer,calendar:CareerCalendarState,offerID:String,accept:Bool,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        let kind:DomesticOfferDecisionKind=accept ? .accepted:.rejected
        if let old=(value.renewalDecisions ?? []).first(where:{$0.offerID == offerID}) {guard old.kind == kind else {throw ContractRegistrationError.closed};return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let review=(value.renewalReviews ?? []).first(where:{$0.offer?.id == offerID}),let offer=review.offer else {throw ContractRegistrationError.invalid}
        guard date >= offer.issued,date <= offer.expires else {throw ContractRegistrationError.expired}
        guard !value.renewalClosedByTransfer(offer,on:date) else {throw ContractRegistrationError.closed}
        guard let member=try owner.current(on:GameDate(date)),member == review.source else {throw ContractRegistrationError.stale}
        if accept {
            guard !value.hasPending(on:date),!value.hasPendingRenewal(on:date),!value.hasPendingFA(on:date),!(value.promotions ?? []).contains(where:{$0.sourceOfferID == member.offerID && $0.effective > date}) else {throw ContractRegistrationError.registered}
            for other in value.evaluations.flatMap(\.offers) where other.issued <= date && other.expires >= date && !value.decisions.contains(where:{$0.offerID == other.id}) {
                value.decisions.append(OverseasDecision(offerID:other.id,kind:.closed,date:date))
            }
        }
        value.renewalDecisions=(value.renewalDecisions ?? [])+[OverseasRenewalDecision(offerID:offerID,kind:kind,date:date)]
        owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}


@MainActor extension OverseasContractStore {
    static func release(player:CareerPlayer,calendar:CareerCalendarState,membershipID:String,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        if (value.releases ?? []).contains(where:{$0.source.offerID == membershipID}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let review=try value.releaseReview(owner:owner,on:GameDate(date)),review.source.offerID == membershipID else {throw OverseasProgressError.requirements}
        value.releases=(value.releases ?? [])+[OverseasRelease(source:review.source,reviewID:review.id,date:date)]
        for offer in value.evaluations.flatMap(\.offers) where offer.issued <= date && offer.expires >= date && !value.decisions.contains(where:{$0.offerID == offer.id}) {
            value.decisions.append(OverseasDecision(offerID:offer.id,kind:.closed,date:date))
        }
        owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}


@MainActor extension OverseasContractStore {
    static func collectFAService(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        let service=try FASeasonEvidence.collect(owner:owner,role:player.role,on:GameDate(date),rows:rows)
        let international=try GameProSeasonEvidence.collect(owner:owner,role:player.role,today:GameDate(date),rows:rows)
        if value.faService == service && value.service == international {return}
        value.faService=service;value.service=international;owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func declareFA(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),value=owner.overseasCareer ?? OverseasCareerJournal()
        guard let member=try owner.current(on:GameDate(date)) else {throw OverseasProgressError.freeAgency}
        if (value.faDeclarations ?? []).contains(where:{$0.source.offerID == member.offerID}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard !value.hasPending(on:date),!value.hasPendingRenewal(on:date),!(value.promotions ?? []).contains(where:{$0.sourceOfferID == member.offerID && $0.effective > date}) else {throw ContractRegistrationError.registered}
        let fa=try FADeclaration.make(member:member,on:GameDate(date),service:value.faService ?? [])
        value.faDeclarations=(value.faDeclarations ?? [])+[fa];owner.overseasCareer=value;owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}


@MainActor enum ContractMarketStore {
    static func domestic(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> [DomesticMarketEntry] {
        let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
        var entries:[DomesticMarketEntry]=[]
        for packet in try ContractOfferStore.records(player:player,calendar:calendar,in:context) {
            guard let evaluation=evaluations.first(where:{$0.key == packet.key}) else {throw ContractOfferError.invalid}
            for offer in try packet.snapshot(evaluation:evaluation,player:player,calendar:calendar).offers {
                let decision=owner.decisions.first {$0.offerID == offer.id}
                let member=owner.memberships.first {$0.offerID == offer.id}
                let status=decision.map {$0.kind == .accepted ? ((member?.since ?? "") > player.gameDate ? "수락 · 발효 대기":"수락 · 발효 완료"):$0.kind == .rejected ? "거절":"다른 제의 수락 · 종료"} ?? (player.gameDate > offer.expiresDate ? "마감":"검토 가능")
                entries.append(DomesticMarketEntry(id:offer.id,evaluationKey:packet.key,name:offer.name,roleID:offer.roleID,label:offer.kind,economicLabel:offer.economicLabel,economicIndex:offer.economicIndex,period:member.map {$0.since+" ~ "+($0.enrollmentEnd ?? $0.economicEnd)} ?? offer.period,issued:offer.issuedDate,expires:offer.expiresDate,status:status,renewal:nil))
            }
        }
        for evaluation in evaluations {
            guard let review=try evaluation.snapshot(player:player,calendar:calendar).renewal,let offer=review.offer else {continue}
            let accepted=owner.renewals?.contains {$0.terms.id == offer.id} == true
            let rejected=owner.renewalRejections?.contains {$0.offerID == offer.id} == true
            let transferred=owner.overseasCareer?.transitions.contains {$0.sourceMembershipID == review.membership.offerID && $0.acceptedDate >= offer.issuedDate && $0.acceptedDate <= offer.expiresDate} == true
            let status=accepted ? (player.gameDate < offer.effectiveDate ? "수락 · 발효 대기":"수락 · 발효 완료"):rejected ? "거절":transferred ? "다른 제의 수락 · 종료":player.gameDate > offer.expiresDate ? "마감":"검토 가능"
            entries.append(DomesticMarketEntry(id:offer.id,evaluationKey:evaluation.key,name:review.membership.name,roleID:review.roleID,label:"국내 육성 · 잔류",economicLabel:"연봉지수",economicIndex:offer.economicIndex,period:offer.effectiveDate+" ~ "+offer.economicEnd,issued:offer.issuedDate,expires:offer.expiresDate,status:status,renewal:review))
        }
        return entries.sorted {$0.issued == $1.issued ? $0.id < $1.id:$0.issued > $1.issued}
    }
}


@MainActor extension OverseasContractStore {
    static func selectTarget(player:CareerPlayer,calendar:CareerCalendarState,reportID:String,clubID:String,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        if owner.developmentTarget?.reportID == reportID && owner.developmentTarget?.clubID == clubID {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard owner.activeProject(on:date) == nil else {throw ContractRegistrationError.busy}
        guard let report=owner.overseasReports?.first(where:{$0.id == reportID}),report.period == (try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(date))).index,
              CareerTargetClub.catalog(report).contains(where:{$0.id == clubID}) else {throw ContractRegistrationError.invalid}
        owner.developmentTarget=CareerDevelopmentTarget(reportID:reportID,clubID:clubID,date:date);owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}


@MainActor enum CareerProjectStore {
    static func progress(_ project:CareerDevelopmentProject,on date:String,matches:[CareerMatchRecord],trainings:[CareerTrainingRecord]) throws -> CareerProjectProgress {
        let end=min(date,project.end)
        var matchKeys:[String]=[],trainingKeys:[String]=[],taskKeys:[String]=[],quality=0,sample=0,growth=0.0,taskValue=0
        for row in matches where row.gameDate >= project.start && row.gameDate <= end && row.completed && row.appearance && !project.baselineMatches.contains(row.key) {
            let match=try row.snapshot()
            guard match.completed,match.appearance,match.role == project.role.rawValue,match.competition == project.level else {continue}
            matchKeys.append(row.key);sample += project.role == .batter ? match.line.plateAppearances:match.line.pitchingOuts
            if let assignment=project.assignment {
                let value=assignment.metric.value(in:match);taskValue += value;if value>0 {taskKeys.append(row.key)}
            }
        }
        for row in trainings where row.gameDate >= project.start && row.gameDate <= end && row.completed && !project.baselineTrainings.contains(row.key) {
            let training=try row.snapshot()
            guard training.role == project.role.rawValue,training.trait == nil else {continue}
            if let assignment=project.assignment,assignment.metric == .position,training.position?.rawValue == assignment.position,training.position != nil {
                taskValue += 1;taskKeys.append(row.key)
            }
            guard training.selectedKind == project.training,training.position == nil else {continue}
            trainingKeys.append(row.key);if training.average >= 75 {quality += 1};growth += training.gain
        }
        var progress=CareerProjectProgress(matchKeys:matchKeys.sorted(),trainingKeys:trainingKeys.sorted(),qualitySessions:quality,sample:sample,growth:TrainingRules.round(growth),requiredSample:project.requiredSample)
        if let assignment=project.assignment {progress.task=CareerProjectTaskProgress(metric:assignment.metric,value:taskValue,goal:assignment.metricGoal,keys:taskKeys.sorted(),trainingGoal:assignment.trainingGoal,qualityGoal:assignment.qualityGoal)}
        return progress
    }
    static func progress(_ project:CareerDevelopmentProject,player:CareerPlayer,on date:String,in context:ModelContext) throws -> CareerProjectProgress {
        let id=player.id
        return try progress(project,on:date,matches:context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})),trainings:context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate:#Predicate {$0.playerID == id})))
    }
    static func appendReview(owner:inout CareerContractJournal,player:CareerPlayer,observation:ScoutingObservation,reportID:String,in context:ModelContext) throws {
        for project in owner.developmentProjects ?? [] where project.start <= observation.observedDate && project.period < observation.period {
            guard !(owner.developmentReviews ?? []).contains(where:{$0.projectID == project.id && ($0.period == observation.period || $0.progress.complete || $0.date > project.end)}) else {continue}
            let value=try progress(project,player:player,on:observation.observedDate,in:context)
            owner.developmentReviews=(owner.developmentReviews ?? [])+[CareerProjectReview(projectID:project.id,reportID:reportID,period:observation.period,date:observation.observedDate,progress:value)]
        }
    }
    // The enclosing report/day command owns saving and rollback.
    static func observe(player:CareerPlayer,calendar:CareerCalendarState,observation:ScoutingObservation,reportID:String,in context:ModelContext) throws {
        guard context.container.schema.entities.contains(where:{$0.name == "ContractRegistration"}) else {return}
        let row=try ContractRegistrationStore.row(player:player,in:context)
        var owner=try row.map {try JSONDecoder().decode(CareerContractJournal.self,from:$0.payload)} ?? CareerContractJournal(playerID:player.id)
        let before=owner
        try appendReview(owner:&owner,player:player,observation:observation,reportID:reportID,in:context)
        try MatchPlanReportStore.append(owner:&owner,player:player,calendar:calendar,observation:observation,reportID:reportID,in:context)
        try GoalSpecialStore.appendEvidence(owner:&owner,player:player,calendar:calendar,observation:observation,reportID:reportID,in:context)
        try ClubSeasonReportStore.append(owner:&owner,player:player,calendar:calendar,observation:observation,reportID:reportID,in:context)
        guard owner != before else {return}
        if let row {row.payload=try JSONEncoder().encode(owner)} else {context.insert(try CareerContractRegistration(owner))}
    }
}
@MainActor extension OverseasContractStore {
    static func startProject(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        let period=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(date)).index
        if (owner.developmentProjects ?? []).contains(where:{$0.period == period}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard owner.activeProject(on:date) == nil,let target=owner.developmentTarget,
              let report=owner.overseasReports?.first(where:{$0.id == target.reportID && $0.period == period}),
              let club=CareerTargetClub.catalog(report).first(where:{$0.id == target.clubID}) else {throw ContractRegistrationError.invalid}
        let id=player.id,day=date
        let matches=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id && $0.gameDate == day})).filter(\.completed).map(\.key).sorted()
        let trainings=try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate:#Predicate {$0.playerID == id && $0.gameDate == day})).filter(\.completed).map(\.key).sorted()
        let member=try owner.current(on:GameDate(date))
        let level:String
        if let member {level=member.level} else {level=(try calendar.age(of:player)) <= 18 ? "highschool":"unsigned"}
        guard level != "unsigned" else {throw CareerProjectError.affiliation}
        let end=try GameDate(date).adding(days:27)
        let scheduled=try calendar.fixtures(for:player,year:GameDate(date).year).filter {$0.date.description >= date && $0.date <= end && $0.isAppearance(for:player.role)}.count
        let sampleGoal=player.role == .batter ? min(20,scheduled*4):min(18,scheduled*18)
        let assignment=CareerProjectAssignment.make(club:club,observation:report.observation,level:level,sampleGoal:sampleGoal)
        var project=CareerDevelopmentProject(id:player.id.uuidString+":development-project-v1:"+String(period),target:target,start:date,end:try GameDate(date).adding(days:27).description,period:period,role:player.role,level:level,training:assignment.training,baselineMatches:matches,baselineTrainings:trainings,requiredSample:sampleGoal)
        project.assignment=assignment
        owner.developmentProjects=(owner.developmentProjects ?? [])+[project];owner.revision += 1
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}


enum CareerProjectError:LocalizedError {
    case affiliation
    var errorDescription:String? {"공식 출전 소속이 필요합니다. 무소속은 계약 시장의 인증 평가전·재입단 경로를 먼저 확인하세요."}
}


@MainActor enum MatchPlanReportStore {
    static func append(owner:inout CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,observation:ScoutingObservation,reportID:String,in context:ModelContext) throws {
        guard !(owner.gamePlanReports ?? []).contains(where:{$0.period == observation.period}) else {return}
        let included=Set((owner.gamePlanReports ?? []).flatMap {$0.results.map(\.matchKey)}),id=player.id
        var results:[MatchPlanReportItem]=[]
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id && $0.completed && $0.appearance})) where row.gameDate <= observation.observedDate && !included.contains(row.key) {
            guard try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(row.gameDate)).index < observation.period else {continue}
            let match=try row.snapshot()
            guard match.role == player.roleRaw,let preparation=match.preparation,let outcome=MatchPlanOutcome.make(match:match) else {continue}
            results.append(MatchPlanReportItem(matchKey:row.key,date:row.gameDate,role:match.role,preparation:preparation,outcome:outcome,mode:match.scoutingPerformance?.inputs?.mode))
        }
        guard !results.isEmpty else {return}
        results.sort {$0.date == $1.date ? $0.matchKey < $1.matchKey:$0.date < $1.date}
        owner.gamePlanReports=(owner.gamePlanReports ?? [])+[MatchPlanObservation(reportID:reportID,period:observation.period,date:observation.observedDate,results:results)]
    }
}


@MainActor enum GoalSpecialStore {
    static func requireNoPending(player:CareerPlayer,in context:ModelContext) throws {
        guard let row=try ContractRegistrationStore.row(player:player,in:context) else {return}
        let owner=try JSONDecoder().decode(CareerContractJournal.self,from:row.payload)
        if (owner.specialAssessments ?? []).contains(where:{!$0.completed}) {throw GoalSpecialError.pending}
    }
    private static func requireReady(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext) throws {
        guard !context.hasChanges,date == player.gameDate,revision == calendar.revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        guard !calendar.hasAction(on:date) else {throw TrainingError.actionUsed}
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {guard try row.snapshot().completed else {throw ContractRegistrationError.busy}}
    }
    private static func commit(_ owner:CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext,save:CalendarProgression.Save) throws {
        if let row=try ContractRegistrationStore.row(player:player,in:context) {row.payload=try JSONEncoder().encode(owner)} else {context.insert(try CareerContractRegistration(owner))}
        _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        try save(context)
    }
    static func startTraining(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws -> CareerTrainingRecord {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        if (owner.specialTrainings ?? []).contains(where:{$0.date == date}),date == player.gameDate,let row=try CareerTrainingStore.record(player:player,in:context) {return row}
        try requireReady(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard try CareerTrainingStore.record(player:player,in:context) == nil,let target=owner.developmentTarget,let club=owner.specialClub(target) else {throw GoalSpecialError.target}
        let live=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
        guard let recommendation=GoalSpecialRecommendation.make(club:club,abilities:live.abilities) else {throw TrainingError.limit}
        do {
            let row=try CareerTrainingStore.start(player:player,state:calendar,kind:recommendation.kind,in:context,save:{_ in})
            let assignment=GoalSpecialTraining(id:"goal-training-v1/"+row.key,target:target,date:date,kind:recommendation.kind,recordKey:row.key)
            owner.specialTrainings=(owner.specialTrainings ?? [])+[assignment];owner.revision += 1
            try commit(owner,player:player,calendar:calendar,in:context,save:save);return row
        } catch {context.rollback();throw error}
    }
    static func startAssessment(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,interactive:Bool=false,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        let period=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(date)).index
        if (owner.specialAssessments ?? []).contains(where:{$0.period == period}) {return}
        try requireReady(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let target=owner.developmentTarget,let club=owner.specialClub(target) else {throw GoalSpecialError.target}
        let live=try ScoutingObservationStore.currentObservation(player:player,calendar:calendar,in:context)
        let values=Dictionary(uniqueKeysWithValues:live.abilities.originals.map {($0.id,$0.current)})
        guard let mental=values["homeMental"] else {throw TrainingError.invalidRecord}
        let snapshot=PlayerInitialValues(contact:player.contact,power:player.power,discipline:player.discipline,speed:player.speed,defense:player.defense,arm:player.arm,mental:mental,velocity:values["homeVelocity"],control:values["homeControl"],stuff:values["homeStuff"],stamina:values["homeStamina"],pitches:Dictionary(uniqueKeysWithValues:player.pitches.map {($0.code,$0.mastery)}))
        guard let opponentID=club.assessmentTeamID else {throw GoalSpecialError.target}
        var value=GoalSpecialAssessment(id:player.id.uuidString+":goal-assessment-v1:"+String(period),target:target,date:date,period:period,role:player.role,position:player.role == .pitcher ? "P":player.positionRaw,level:club.assessmentLevel,opponentID:opponentID,values:snapshot,fatigue:player.fatigue,calendarRevision:calendar.revision+1)
        if interactive {value.playVersion=1}
        owner.specialAssessments=(owner.specialAssessments ?? [])+[value];owner.revision += 1
        do {calendar.revision += 1;try commit(owner,player:player,calendar:calendar,in:context,save:save)}catch{context.rollback();throw error}
    }
    static func advanceAssessment(player:CareerPlayer,calendar:CareerCalendarState,id:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges,calendar.revision == revision else {throw ContractRegistrationError.stale}
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard let index=owner.specialAssessments?.firstIndex(where:{$0.id == id}),var value=owner.specialAssessments?[index] else {throw MatchError.invalidRecord}
        guard !value.completed else {throw MatchError.finished}
        guard value.calendarRevision == revision,value.date == player.gameDate,value.fatigue == player.fatigue,!calendar.hasAction(on:player.gameDate) else {throw ContractRegistrationError.stale}
        try value.advance();value.calendarRevision += 1
        owner.specialAssessments?[index]=value;owner.revision += 1
        do {
            if value.completed {calendar.actionDate=player.gameDate;player.fatigue=min(100,player.fatigue+8)}
            calendar.revision += 1;try commit(owner,player:player,calendar:calendar,in:context,save:save)
        } catch {context.rollback();throw error}
    }
    @discardableResult static func preparePlay(player:CareerPlayer,calendar:CareerCalendarState,id:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws -> GoalSpecialAssessment {
        try changePlay(player:player,calendar:calendar,id:id,revision:revision,in:context,save:save) {try $0.preparePlay()}
    }
    @discardableResult static func advancePlay(player:CareerPlayer,calendar:CareerCalendarState,id:String,revision:Int,input:MatchInput,pitchCode:String?=nil,control:ManualMatchInput?=nil,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws -> GoalSpecialAssessment {
        try changePlay(player:player,calendar:calendar,id:id,revision:revision,in:context,save:save) {try $0.play(input,pitchCode:pitchCode,control:control)}
    }
    private static func changePlay(player:CareerPlayer,calendar:CareerCalendarState,id:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save,change:(inout GoalSpecialAssessment) throws -> Void) throws -> GoalSpecialAssessment {
        guard !context.hasChanges,calendar.revision == revision else {throw ContractRegistrationError.stale}
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard let index=owner.specialAssessments?.firstIndex(where:{$0.id == id}),var value=owner.specialAssessments?[index],value.playVersion == 1 else {throw MatchError.invalidRecord}
        guard !value.completed else {throw MatchError.finished}
        guard value.calendarRevision == revision,value.date == player.gameDate,value.fatigue == player.fatigue,!calendar.hasAction(on:player.gameDate) else {throw ContractRegistrationError.stale}
        let previous=value;try change(&value)
        guard previous != value else {return value}
        value.calendarRevision += 1;owner.specialAssessments?[index]=value;owner.revision += 1
        do {
            if value.completed {calendar.actionDate=player.gameDate;player.fatigue=min(100,player.fatigue+8)}
            calendar.revision += 1;try commit(owner,player:player,calendar:calendar,in:context,save:save)
        } catch {context.rollback();throw error}
        return value
    }
    static func displayRecord(player:CareerPlayer,calendar:CareerCalendarState,id:String,in context:ModelContext) throws -> CareerMatchRecord {
        let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard let assessment=owner.specialAssessments?.first(where:{$0.id == id}),assessment.playVersion == 1,let match=assessment.currentGame else {throw MatchError.invalidRecord}
        return try CareerMatchRecord(assessment:assessment,match:match,playerID:player.id)
    }
    static func validateTrainings(owner:CareerContractJournal,player:CareerPlayer,in context:ModelContext) throws {
        guard owner.specialTrainings?.isEmpty == false else {return}
        let id=player.id,rows=try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate:#Predicate {$0.playerID == id}))
        for assignment in owner.specialTrainings ?? [] {
            guard let row=rows.first(where:{$0.key == assignment.recordKey}) else {throw TrainingError.invalidRecord}
            let training=try row.snapshot()
            guard training.role == player.roleRaw,training.selectedKind == assignment.kind,training.trait == nil,training.position == nil else {throw TrainingError.invalidRecord}
        }
    }
    static func appendEvidence(owner:inout CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,observation:ScoutingObservation,reportID:String,in context:ModelContext) throws {
        guard !(owner.specialReports ?? []).contains(where:{$0.period == observation.period}) else {return}
        let included=Set((owner.specialReports ?? []).flatMap {$0.evidence.map(\.id)}),id=player.id
        let rows=try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate:#Predicate {$0.playerID == id && $0.completed}))
        var evidence:[GoalSpecialEvidence]=[]
        for assignment in owner.specialTrainings ?? [] where !included.contains(assignment.id) {
            guard assignment.date <= observation.observedDate,try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(assignment.date)).index < observation.period,
                  let row=rows.first(where:{$0.key == assignment.recordKey}) else {continue}
            let training=try row.snapshot()
            evidence.append(GoalSpecialEvidence(id:assignment.id,kind:.training,target:assignment.target,date:assignment.date,score:training.average,growth:training.gain,summary:assignment.kind.label+" 특별 훈련 · 5회 완료"))
        }
        for assessment in owner.specialAssessments ?? [] where assessment.completed && !included.contains(assessment.id) {
            guard assessment.period < observation.period,assessment.date <= observation.observedDate else {continue}
            evidence.append(GoalSpecialEvidence(id:assessment.id,kind:.assessment,target:assessment.target,date:assessment.date,score:assessment.score,growth:0,summary:(assessment.playVersion == nil ? "자동 평가전2경기":"선택형 평가전2경기 · "+assessment.inputSummary)+" · "+(assessment.role == .batter ? "\(assessment.totals.line.plateAppearances)타석":"\(assessment.totals.innings)이닝")+(assessment.playVersion == 1 ? " · "+assessment.roleDiagnosis.joined(separator:" / "):"")))
        }
        guard !evidence.isEmpty else {return}
        evidence.sort {$0.id < $1.id};owner.specialReports=(owner.specialReports ?? [])+[GoalSpecialReport(reportID:reportID,period:observation.period,date:observation.observedDate,evidence:evidence)]
    }
}
enum GoalSpecialError:LocalizedError {
    case pending,target
    var errorDescription:String? {switch self {case .pending:"진행 중인 목표 구단 평가전을 먼저 마쳐 주세요. 특별 훈련·평가전 화면에서 이어갈 수 있습니다.";case .target:"먼저 관찰 보고서에서 목표 구단과 역할을 선택해 주세요."}}
}

@MainActor enum ObservationReviewStore {
    static func load(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> ObservationPeriodReview? {
        let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        let reports=try ScoutingObservationStore.reports(player:player,calendar:calendar,in:context).map {try $0.snapshot()}
        let period=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(player.gameDate)).index
        return ObservationPeriodReview.make(observations:reports,owner:owner,period:period)
    }
}

@MainActor enum ClubSeasonStore {
    static func role(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> CareerClubRole? {
        let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard let member=try owner.current(on:GameDate(player.gameDate)) else {return nil}
        let evaluations=try ContractEvaluationStore.records(player:player,calendar:calendar,in:context)
        let offers=try ContractOfferStore.records(player:player,calendar:calendar,in:context).flatMap {row in
            guard let evaluation=evaluations.first(where:{$0.key == row.key}) else {throw ContractRegistrationError.invalid}
            return try row.snapshot(evaluation:evaluation,player:player,calendar:calendar).offers
        }
        return CareerClubRole.make(member:member,owner:owner,offers:offers,on:player.gameDate)
    }
}

@MainActor extension ClubSeasonStore {
    static func progress(_ goal:ClubSeasonGoal,player:CareerPlayer,on date:String?=nil,in context:ModelContext) throws -> ClubSeasonProgress {
        if let result=goal.result,date.map {cutoff in goal.settledOn.map {$0 <= cutoff} ?? false} ?? true {return result}
        let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        let source=try rows.filter {row in row.completed && goal.fixtureIDs.contains(row.fixtureID) && row.gameDate >= goal.started && (date.map {row.gameDate <= $0} ?? true)}.map {row -> (key:String,match:CareerMatch) in
            let match=try row.snapshot()
            guard match.competition == goal.role.level,match.role == goal.playerRole else {throw ContractRegistrationError.invalid}
            return (row.key,match)
        }
        return goal.progress(matches:source)
    }
    static func start(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard let role=try role(player:player,calendar:calendar,in:context),role.roleID != nil else {throw ClubSeasonGoalError.roleUnavailable}
        let year=try GameDate(date).year,key=ClubSeasonGoal.key(role,year:year)
        if (owner.seasonGoals ?? []).contains(where:{$0.id == key}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        let id=player.id,old=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})).map(\.key).sorted()
        let fixtures=try calendar.fixtures(for:player,year:year).filter {$0.date.description >= date && !old.contains(CareerMatchRecord.key(player.id,$0.id))}
        let n=fixtures.filter {$0.isAppearance(for:player.role)}.count
        guard n > 0 else {throw ClubSeasonGoalError.noGames}
        let goal=ClubSeasonGoal(id:key,year:year,started:date,role:role,playerRole:player.roleRaw,fixtureIDs:fixtures.map(\.id),excludedKeys:old,appearances:n,targets:ClubSeasonGoal.targets(role:role,playerRole:player.roleRaw,appearances:n))
        owner.seasonGoals=(owner.seasonGoals ?? [])+[goal]
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    static func settle(_ goalID:String,player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard var goals=owner.seasonGoals,let i=goals.firstIndex(where:{$0.id == goalID}) else {throw ContractRegistrationError.invalid}
        if goals[i].result != nil {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        let summary=try CareerSeasonStore.load(player:player,state:calendar,year:goals[i].year,in:context)
        guard summary.finalized else {throw ClubSeasonGoalError.unfinished}
        goals[i].result=try progress(goals[i],player:player,in:context);goals[i].settledOn=date;owner.seasonGoals=goals
        let review=try makeReview(goal:goals[i],owner:owner,player:player,calendar:calendar,date:date,in:context)
        owner.seasonReviews=(owner.seasonReviews ?? [])+[review]
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
    private static func requireIdle(player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext) throws {
        guard !context.hasChanges else {throw ContractRegistrationError.busy}
        guard player.gameDate == date,calendar.revision == revision else {throw ContractRegistrationError.stale}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {guard try row.snapshot().completed else {throw ContractRegistrationError.busy}}
    }
    private static func write(_ owner:CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext,save:CalendarProgression.Save) throws {
        do {
            var value=owner;value.revision += 1
            if let row=try ContractRegistrationStore.row(player:player,in:context) {row.payload=try JSONEncoder().encode(value)} else {context.insert(try CareerContractRegistration(value))}
            _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
            calendar.revision += 1;try save(context)
        } catch {context.rollback();throw error}
    }
}

@MainActor enum ClubSeasonReportStore {
    // Both report paths call this before their atomic save. Older reports are never backfilled.
    static func append(owner:inout CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,observation:ScoutingObservation,reportID:String,in context:ModelContext) throws {
        guard !(owner.seasonGoals ?? []).isEmpty,!(owner.seasonGoalReports ?? []).contains(where:{$0.period == observation.period}) else {return}
        let general=try ScoutingObservationStore.reports(player:player,calendar:calendar,in:context)
        guard !general.contains(where:{$0.period == observation.period && $0.key != reportID}),
              !(owner.overseasReports ?? []).contains(where:{$0.period == observation.period && $0.id != reportID}) else {return}
        let through=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(observation.observedDate)).start.adding(days:-1).description
        var items:[ClubSeasonObservationItem]=[]
        for goal in owner.seasonGoals ?? [] where goal.started <= through {
            let previous=(owner.seasonGoalReports ?? []).filter {$0.period < observation.period}.sorted {$0.period > $1.period}.compactMap {r in r.items.first {$0.goalID == goal.id}.map {(reportID:r.reportID,item:$0)}}.first
            if previous?.item.final == true {continue}
            let final=goal.result != nil && (goal.settledOn.map {$0 <= through} ?? false)
            if goal.year < (try GameDate(through)).year,previous != nil,!final {continue}
            let progress=try ClubSeasonStore.progress(goal,player:player,on:through,in:context)
            items.append(.make(goal:goal,progress:progress,previous:previous,final:final))
        }
        owner.seasonGoalReports=(owner.seasonGoalReports ?? [])+[ClubSeasonObservation(reportID:reportID,period:observation.period,date:observation.observedDate,through:through,items:items)]
    }
}

@MainActor extension ClubSeasonStore {
    static func makeReview(goal:ClubSeasonGoal,owner:CareerContractJournal,player:CareerPlayer,calendar:CareerCalendarState,date:String,in context:ModelContext) throws -> ClubSeasonReview {
        var candidates:[ClubSeasonReviewBasis]=[]
        for report in owner.overseasReports ?? [] {
            if let basis=try ClubSeasonReviewBasis.make(goal:goal,owner:owner,reportID:report.id,observation:report.observation,comparisons:report.comparisons,on:date) {candidates.append(basis)}
        }
        for row in try ScoutingObservationStore.reports(player:player,calendar:calendar,in:context) {
            let observation=try row.snapshot()
            if let basis=try ClubSeasonReviewBasis.make(goal:goal,owner:owner,reportID:row.key,observation:observation,comparisons:observation.contractFit?.comparisons ?? [],on:date) {candidates.append(basis)}
        }
        // Pick the latest available evidence once. Later reports never replace an archived review.
        let basis=candidates.sorted {a,b in
            if a.date != b.date {return a.date > b.date}
            let foreignA=a.reportID.contains(":overseas-report-"),foreignB=b.reportID.contains(":overseas-report-")
            if foreignA != foreignB {return foreignA}
            return a.reportID < b.reportID
        }.first
        return try ClubSeasonReview.make(goal:goal,on:date,basis:basis)
    }
    static func review(_ goalID:String,player:CareerPlayer,calendar:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        var owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        if (owner.seasonReviews ?? []).contains(where:{$0.goalID == goalID}) {return}
        try requireIdle(player:player,calendar:calendar,date:date,revision:revision,in:context)
        guard let goal=owner.seasonGoals?.first(where:{$0.id == goalID}),goal.result != nil else {throw ClubSeasonGoalError.unfinished}
        let review=try makeReview(goal:goal,owner:owner,player:player,calendar:calendar,date:date,in:context)
        owner.seasonReviews=(owner.seasonReviews ?? [])+[review]
        try write(owner,player:player,calendar:calendar,in:context,save:save)
    }
}
