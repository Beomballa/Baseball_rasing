import Foundation
import SwiftData

struct CalendarAdvanceSummary: Equatable, Sendable {
    enum Stop: String, Sendable {
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
            try CareerPathStore.synchronize(player: player, calendar: state, in: context)
            _ = try ContractEvaluationStore.captureIfDue(player:player,calendar:state,in:context)
            if observationDue { _ = try ScoutingObservationStore.insertIfNeeded(player: player, calendar: state, in: context) }
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
