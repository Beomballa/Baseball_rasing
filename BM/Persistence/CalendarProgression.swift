import Foundation
import SwiftData

struct CalendarAdvanceSummary: Equatable, Sendable {
    enum Stop: String, Sendable {
        case traitChange = "특성 유지 경고·상실 전 · 하루 진행으로 확인"
        case retirement = "은퇴 완료 · 기록 열람 가능"
        case evaluation = "계약 평가 자료 도착 · 홈에서 확인 후 계속"
        case fixture = "경기일 도착 · 경기 진행/완료 확인"
        case anniversary = "나이·학적 변경 전 · 하루 진행으로 확인"
        case limit = "30일 진행 완료"
        case seasonOpening = "다음 연도 4월 1일 도착"
        case failed = "진행 중단 · 완료한 날짜는 저장되어 있습니다"
        case cancelled = "진행 중지 · 마지막 저장일부터 이어집니다"
    }
    let days: Int
    let restDays: Int
    let fatigueBefore: Int
    let fatigueAfter: Int
    let stop: Stop
    let lastSavedDate: String
    var message: String {
        "\(days)일 진행 · 휴식 \(restDays)회 · 피로 \(fatigueBefore) → \(fatigueAfter)\n\(stop.rawValue)\n마지막 저장일 \(lastSavedDate)"
    }
}

enum DailyRecovery {
    static let rest = 18
    static let sleep = 4
    static func recover(_ fatigue: Int, by amount: Int) -> Int { max(0, min(100, fatigue - amount)) }
}

struct CalendarAdvanceFailure: LocalizedError {
    let summary: CalendarAdvanceSummary
    let reason: String
    var errorDescription: String? { "\(summary.message)\n중단 원인: \(reason)" }
}

@MainActor enum CalendarProgression {
    typealias Save = @MainActor (ModelContext) throws -> Void
    private static func validate(_ player: CareerPlayer, _ state: CareerCalendarState, revision: Int) throws {
        guard state.playerID == player.id, state.revision == revision else { throw CalendarError.staleState }
        _ = try state.fixtures(for: player, year: GameDate(player.gameDate).year)
    }

    static func rest(player: CareerPlayer, state: CareerCalendarState, revision: Int, in context: ModelContext, save: Save = { try $0.save() }) throws {
        try validate(player, state, revision: revision)
        try CareerTrainingStore.requireNoPending(player: player, in: context)
        guard !state.hasAction(on: player.gameDate) else { throw CalendarError.actionUsed }
        player.fatigue = DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest)
        state.actionDate = player.gameDate
        state.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
    }

    static func isAnniversaryTomorrow(player: CareerPlayer, state: CareerCalendarState) throws -> Bool {
        let tomorrow = try GameDate(player.gameDate).adding(days: 1)
        return try GameDate(state.originDate).anniversary(in: tomorrow.year) == tomorrow
    }

    static func hasGameToday(player: CareerPlayer, state: CareerCalendarState) throws -> Bool {
        let today = try GameDate(player.gameDate)
        return try state.fixtures(for: player, year: today.year).contains { $0.date == today }
    }

    /// One day is one save, including automatic rest and sleep. A failed save rolls back the whole day.
    static func advanceDay(player: CareerPlayer, state: CareerCalendarState, revision: Int,
                           automaticRest: Bool = false, confirmAnniversary: Bool = false,
                           in context: ModelContext, save: Save = { try $0.save() }) throws {
        try validate(player, state, revision: revision)
        try CareerTrainingStore.requireNoPending(player: player, in: context)
        if try ContractEvaluationStore.unread(player:player,calendar:state,in:context) != nil || OverseasContractStore.needsEvaluation(player:player,calendar:state,in:context) {throw ContractEvaluationError.unread}
        if try hasGameToday(player: player, state: state) {
            let fixture = try CareerMatchStore.today(player: player, state: state)
            guard try CareerMatchStore.isCompleted(player: player, fixture: fixture, in: context) else { throw CalendarError.fixturePending }
        }
        if try isAnniversaryTomorrow(player: player, state: state), !confirmAnniversary {
            throw CalendarError.anniversaryConfirmation
        }
        let prepared = state.hasAction(on: player.gameDate)
        guard prepared || automaticRest else { throw CalendarError.preparationRequired }
        let today = try GameDate(player.gameDate)
        let nextDate = today.adding(days: 1).description
        let observationDue = try ScoutingPeriod(origin: GameDate(state.originDate), today: today).index
            != ScoutingPeriod(origin: GameDate(state.originDate), today: GameDate(nextDate)).index
        do {
            try AutomaticLeagueStore.completeDay(player:player,state:state,date:today,in:context)
            if !prepared { player.fatigue = DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest) }
            player.fatigue = DailyRecovery.recover(player.fatigue, by: DailyRecovery.sleep)
            player.gameDate = nextDate
            state.actionDate = nil
            state.revision += 1
            try CareerLifecycleStore.advance(player:player,state:state,previous:today,in:context)
            if !player.isRetired {
                try CareerPathStore.synchronize(player: player, calendar: state, in: context)
                _ = try ContractEvaluationStore.captureIfDue(player:player,calendar:state,in:context)
                if observationDue { _ = try ScoutingObservationStore.insertIfNeeded(player: player, calendar: state, in: context) }
                _ = try ClubSelectionStore.capture(player:player,calendar:state,in:context)
            }
            try save(context)
        } catch { context.rollback(); throw error }
    }

    static func advanceOffDays(player: CareerPlayer, state: CareerCalendarState,
                               in context: ModelContext, save: Save = { try $0.save() }, onDaySaved: (@MainActor (String) async -> Void)? = nil) async throws -> CalendarAdvanceSummary {
        let before = player.fatigue
        var days = 0, rests = 0
        var stop = CalendarAdvanceSummary.Stop.limit
        var expectedRevision = state.revision
        var lastSavedDate = player.gameDate
        var lastSavedFatigue = player.fatigue
        do {
            while days < 30 {
                if Task.isCancelled { stop = .cancelled; break }
                try validate(player, state, revision: expectedRevision)
                if try ContractEvaluationStore.unread(player:player,calendar:state,in:context) != nil || OverseasContractStore.needsEvaluation(player:player,calendar:state,in:context) {stop = .evaluation;break}
                if player.isRetired {stop = .retirement;break}
                if try CareerLifecycleStore.traitEventTomorrow(player:player,in:context) {stop = .traitChange;break}
                if try hasGameToday(player: player, state: state) { stop = .fixture; break }
                if try isAnniversaryTomorrow(player: player, state: state) { stop = .anniversary; break }
                let needsRest = !state.hasAction(on: player.gameDate)
                try advanceDay(player: player, state: state, revision: expectedRevision, automaticRest: true, in: context, save: save)
                expectedRevision = state.revision
                lastSavedDate = player.gameDate
                lastSavedFatigue = player.fatigue
                days += 1
                if needsRest { rests += 1 }
                await onDaySaved?(player.gameDate)
                await Task.yield()
                if player.isRetired {stop = .retirement;break}
                if try ContractEvaluationStore.unread(player:player,calendar:state,in:context) != nil || OverseasContractStore.needsEvaluation(player:player,calendar:state,in:context) {stop = .evaluation;break}
            }
            if stop == .limit {
                if try hasGameToday(player: player, state: state) { stop = .fixture }
                else if try isAnniversaryTomorrow(player: player, state: state) { stop = .anniversary }
            }
        } catch {
            let saved = CalendarAdvanceSummary(days: days, restDays: rests, fatigueBefore: before,
                                               fatigueAfter: lastSavedFatigue, stop: .failed, lastSavedDate: lastSavedDate)
            throw CalendarAdvanceFailure(summary: saved, reason: error.localizedDescription)
        }
        return CalendarAdvanceSummary(days: days, restDays: rests, fatigueBefore: before,
                                      fatigueAfter: lastSavedFatigue, stop: stop, lastSavedDate: lastSavedDate)
    }
}


extension CalendarProgression {
    /// Each batch preserves the existing 30-day limit and daily atomic save/recovery.
    static func advanceOffseason(player: CareerPlayer, state: CareerCalendarState, seasonYear: Int,
                                 revision: Int, expectedDate: String, confirmAnniversary: Bool = false,
                                 in context: ModelContext, save: Save = { try $0.save() },
                                 onDaySaved: (@MainActor (String) async -> Void)? = nil) async throws -> CalendarAdvanceSummary {
        let before = player.fatigue
        var days = 0, rests = 0, expectedRevision = revision
        var lastDate = expectedDate, lastFatigue = before
        var stop = CalendarAdvanceSummary.Stop.limit
        do {
            try validate(player, state, revision: revision)
            guard player.gameDate == expectedDate else { throw CalendarError.staleState }
            guard let plan = try CareerSeasonStore.offseason(player: player, state: state, in: context),
                  plan.seasonYear == seasonYear else { throw OffseasonError.unavailable }
            try CareerTrainingStore.requireNoPending(player: player, in: context)
            let id = player.id
            let records = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id }))
            guard !records.contains(where: { !$0.completed }) else { throw CalendarError.fixturePending }
            while days < 30 {
                if Task.isCancelled { stop = .cancelled; break }
                try validate(player, state, revision: expectedRevision)
                guard player.gameDate == lastDate else { throw CalendarError.staleState }
                if try GameDate(player.gameDate) >= plan.target { stop = .seasonOpening; break }
                if try ContractEvaluationStore.unread(player:player,calendar:state,in:context) != nil || OverseasContractStore.needsEvaluation(player:player,calendar:state,in:context) {stop = .evaluation;break}
                if player.isRetired {stop = .retirement;break}
                if try CareerLifecycleStore.traitEventTomorrow(player:player,in:context) {stop = .traitChange;break}
                if try hasGameToday(player: player, state: state) { stop = .fixture; break }
                let birthday = try isAnniversaryTomorrow(player: player, state: state)
                if birthday && !(confirmAnniversary && days == 0) { stop = .anniversary; break }
                let needsRest = !state.hasAction(on: player.gameDate)
                try advanceDay(player: player, state: state, revision: expectedRevision, automaticRest: true,
                    confirmAnniversary: birthday && confirmAnniversary && days == 0, in: context, save: save)
                expectedRevision = state.revision; lastDate = player.gameDate; lastFatigue = player.fatigue
                days += 1
                if needsRest { rests += 1 }
                await onDaySaved?(lastDate)
                await Task.yield()
                if player.isRetired {stop = .retirement;break}
                if try ContractEvaluationStore.unread(player:player,calendar:state,in:context) != nil || OverseasContractStore.needsEvaluation(player:player,calendar:state,in:context) {stop = .evaluation;break}
            }
            if stop == .limit {
                if try GameDate(player.gameDate) == plan.target { stop = .seasonOpening }
                else if try isAnniversaryTomorrow(player: player, state: state) { stop = .anniversary }
            }
        } catch {
            // A preflight failure reports the actual saved date, not a stale caller's date.
            if days == 0 { lastDate = player.gameDate; lastFatigue = player.fatigue }
            throw CalendarAdvanceFailure(summary: CalendarAdvanceSummary(days: days, restDays: rests, fatigueBefore: before,
                fatigueAfter: lastFatigue, stop: .failed, lastSavedDate: lastDate), reason: error.localizedDescription)
        }
        return CalendarAdvanceSummary(days: days, restDays: rests, fatigueBefore: before,
            fatigueAfter: lastFatigue, stop: stop, lastSavedDate: lastDate)
    }
}


@MainActor enum CareerLifecycleStore {
    static func requireActive(_ player:CareerPlayer) throws {
        guard try player.lifecycle.retirement == nil else {throw CareerLifecycleError.retired}
    }
    static func values(player:CareerPlayer,in context:ModelContext) throws -> [String:Double] {
        var values:[String:Double]=["contact":player.contact,"power":player.power,"discipline":player.discipline,"speed":player.speed,"defense":player.defense,"arm":player.arm]
        if let profile=try PlayerAbilityStore.profile(playerID:player.id,in:context) {
            for kind in [TrainingKind.mental,.velocity,.control,.stuff,.stamina] where kind.allows(player.roleRaw) {values[kind.rawValue]=try profile.value(for:kind)}
        }
        for pitch in player.pitches {values["pitch/"+pitch.code]=pitch.mastery}
        return values
    }
    static func apply(_ values:[String:Double],player:CareerPlayer,in context:ModelContext) throws {
        player.contact=values["contact"] ?? player.contact;player.power=values["power"] ?? player.power
        player.discipline=values["discipline"] ?? player.discipline;player.speed=values["speed"] ?? player.speed
        player.defense=values["defense"] ?? player.defense;player.arm=values["arm"] ?? player.arm
        if let profile=try PlayerAbilityStore.profile(playerID:player.id,in:context) {
            for kind in [TrainingKind.mental,.velocity,.control,.stuff,.stamina] {
                if let value=values[kind.rawValue] {try profile.grow(kind,to:value)}
            }
        }
        for pitch in player.pitches {if let value=values["pitch/"+pitch.code] {pitch.mastery=value}}
    }
    static func belowRetention(_ trait:PlayerTrait,player:CareerPlayer) -> Bool {
        switch trait {case .strongArm:player.arm < 58;case .cheetah:player.speed < 58;case .safeHands:player.defense < 48}
    }
    static func traitEventTomorrow(player:CareerPlayer,in context:ModelContext) throws -> Bool {
        let life=try player.lifecycle,tomorrow=try GameDate(player.gameDate).adding(days:1)
        return try life.traitRisk.contains {key,since in
            guard let trait=PlayerTrait(rawValue:key),belowRetention(trait,player:player) else {return false}
            return [14,28].contains(try GameDate(since).days(to:tomorrow)+1)
        }
    }
    // The caller commits this with the date. Replaying a view never calls this command.
    static func advance(player:CareerPlayer,state:CareerCalendarState,previous:GameDate,in context:ModelContext) throws {
        var life=try player.lifecycle
        guard life.retirement == nil else {throw CareerLifecycleError.retired}
        if life.adopted == nil {life.adopted=previous.description;life.enforceAgeLimit=try GameDate(state.originDate).age(startingAt:player.startAge,on:previous)<41}
        let today=try GameDate(player.gameDate),origin=try GameDate(state.originDate),age=try state.age(of:player)
        let modern=life.development.map {player.gameDate>$0.adopted} ?? false
        let id=player.id.uuidString+(modern ? ":aging-v2:":":aging-v1:")+player.gameDate
        if today == origin.anniversary(in:today.year),(modern ? 27...40:31...40).contains(age),!life.aging.contains(where:{$0.id == id || $0.date == player.gameDate}) {
            let before=try values(player:player,in:context)
            let after=before.mapValues {$0}
            var adjusted=after
            for (key,value) in before {
                let isPitch=key.hasPrefix("pitch/")
                if let kind=isPitch ? TrainingKind.pitch:TrainingKind(rawValue:key) {adjusted[key]=modern ? DevelopmentRules.aged(value,kind:kind,age:age,pitch:isPitch):CareerAgingRules.value(value,kind:kind,age:age,pitch:isPitch)}
            }
            try apply(adjusted,player:player,in:context)
            life.aging.append(CareerAgeEvent(id:id,date:player.gameDate,age:age,before:before,after:adjusted))
        }
        if let profile=try PlayerTraitStore.profile(playerID:player.id,in:context) {
            var loadout=try profile.snapshot();var changed=false
            for trait in loadout.owned {
                if belowRetention(trait,player:player) {
                    let since=life.traitRisk[trait.rawValue] ?? player.gameDate;life.traitRisk[trait.rawValue]=since
                    if try GameDate(since).days(to:today)+1 >= 28 {
                        loadout.owned.removeAll {$0 == trait};loadout.active.removeAll {$0 == trait}
                        loadout.progress[trait.rawValue]=0
                        life.losses.append(CareerTraitLoss(id:player.id.uuidString+":trait-loss-v1:"+trait.rawValue+":"+player.gameDate,date:player.gameDate,trait:trait))
                        life.traitRisk.removeValue(forKey:trait.rawValue);changed=true
                    }
                } else {life.traitRisk.removeValue(forKey:trait.rawValue)}
            }
            if changed {try loadout.validate();profile.payload=try JSONEncoder().encode(loadout);profile.revision += 1}
        }
        try life.validate(playerID:player.id,today:player.gameDate)
        player.lifecycleData=try JSONEncoder().encode(life)
        if life.enforceAgeLimit,age>=41 {try finalize(player:player,state:state,reason:"age-limit",in:context)}
    }
    static func retire(player:CareerPlayer,state:CareerCalendarState,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        if player.isRetired {return}
        guard !context.hasChanges,date == player.gameDate,state.playerID == player.id,state.revision == revision else {throw CalendarError.staleState}
        guard try state.age(of:player)>=20 else {throw CareerLifecycleError.tooYoung}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        guard try context.fetchCount(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id && !$0.completed})) == 0 else {throw CareerLifecycleError.pending}
        do {try finalize(player:player,state:state,reason:"voluntary",in:context);state.revision += 1;try save(context)} catch {context.rollback();throw error}
    }
    private static func finalize(player:CareerPlayer,state:CareerCalendarState,reason:String,in context:ModelContext) throws {
        var life=try player.lifecycle
        guard life.retirement == nil else {return}
        var owner=try ContractRegistrationStore.journal(player:player,calendar:state,in:context)
        let schools=try SchoolCatalog.load(),date=try GameDate(player.gameDate),age=try state.age(of:player)
        let member=try owner.current(on:date)
        let affiliation=member.map {CareerTeamDirectory.name($0.teamID,schools:schools)} ?? (age<=18 ? player.schoolName:"무소속")
        let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id && $0.completed}))
        var total=MatchLine();var games=0
        for row in rows {let match=try row.snapshot();guard match.appearance else {continue};games += 1
            total.plateAppearances += match.line.plateAppearances;total.atBats += match.line.atBats;total.hits += match.line.hits;total.homeRuns += match.line.homeRuns
            total.walks += match.line.walks;total.rbi += match.line.rbi;total.pitchingOuts += match.line.pitchingOuts;total.pitches += match.line.pitches
            total.strikeouts += match.line.strikeouts;total.runsAllowed += match.line.runsAllowed
            total.pitchingStrikeouts += match.line.pitchingStrikeouts;total.pitchingWalks += match.line.pitchingWalks;total.hitsAllowed += match.line.hitsAllowed
        }
        let final=try values(player:player,in:context)
        life.retirement=CareerRetirement(date:player.gameDate,age:age,reason:reason,affiliation:affiliation,games:games,line:total,finalValues:final.filter {!$0.key.hasPrefix("pitch/")},finalPitches:Dictionary(uniqueKeysWithValues:player.pitches.map {($0.code,$0.mastery)}))
        try life.validate(playerID:player.id,today:player.gameDate);player.lifecycleData=try JSONEncoder().encode(life)
        owner.retiredOn=player.gameDate;owner.revision += 1
        if let row=try ContractRegistrationStore.row(player:player,in:context) {row.payload=try JSONEncoder().encode(owner)}
        else {context.insert(try CareerContractRegistration(owner))}
        for slot in try context.fetch(FetchDescriptor<ActiveCareerSlot>()) where slot.playerID == player.id {context.delete(slot)}
    }
    static func horizon(player:CareerPlayer,calendar:CareerCalendarState) throws -> String {
        let origin=try GameDate(calendar.originDate)
        return origin.anniversary(in:origin.year+max(0,41-player.startAge)).description
    }
    static func requireContractEnd(_ end:String,player:CareerPlayer,calendar:CareerCalendarState) throws {
        let horizon=try GameDate(horizon(player:player,calendar:calendar))
        guard try GameDate(end)<horizon else {throw CareerLifecycleError.horizon}
    }
}
