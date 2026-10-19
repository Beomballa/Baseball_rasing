import Foundation
import SwiftData

struct CalendarAdvanceSummary: Equatable {
    enum Stop: String {
        case fixture = "경기일 도착 · 실제 경기 연결 대기"
        case anniversary = "나이·학적 변경 전 · 하루 진행으로 확인"
        case limit = "30일 진행 완료"
        case cancelled = "진행 중지 · 마지막 저장일부터 이어집니다"
    }
    let days: Int
    let restDays: Int
    let fatigueBefore: Int
    let fatigueAfter: Int
    let stop: Stop
    var message: String {
        "\(days)일 진행 · 휴식 \(restDays)회 · 피로 \(fatigueBefore) → \(fatigueAfter)\n\(stop.rawValue)"
    }
}

@MainActor enum CalendarProgression {
    private static func validate(_ player: CareerPlayer, _ state: CareerCalendarState, revision: Int) throws {
        guard state.playerID == player.id, state.revision == revision else { throw CalendarError.staleState }
        _ = try GameDate(player.gameDate)
    }

    static func rest(player: CareerPlayer, state: CareerCalendarState, revision: Int, in context: ModelContext) throws {
        try validate(player, state, revision: revision)
        guard !state.hasAction(on: player.gameDate) else { throw CalendarError.actionUsed }
        player.fatigue = max(0, min(100, player.fatigue - 18))
        state.actionDate = player.gameDate
        state.revision += 1
        do { try context.save() } catch { context.rollback(); throw error }
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
                           in context: ModelContext) throws {
        try validate(player, state, revision: revision)
        guard try !hasGameToday(player: player, state: state) else { throw CalendarError.fixturePending }
        if try isAnniversaryTomorrow(player: player, state: state), !confirmAnniversary {
            throw CalendarError.anniversaryConfirmation
        }
        let prepared = state.hasAction(on: player.gameDate)
        guard prepared || automaticRest else { throw CalendarError.preparationRequired }
        if !prepared { player.fatigue = max(0, min(100, player.fatigue - 18)) }
        player.fatigue = max(0, min(100, player.fatigue - 4))
        player.gameDate = try GameDate(player.gameDate).adding(days: 1).description
        state.actionDate = nil
        state.revision += 1
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func advanceOffDays(player: CareerPlayer, state: CareerCalendarState,
                               in context: ModelContext, onDaySaved: (@MainActor (String) async -> Void)? = nil) async throws -> CalendarAdvanceSummary {
        let before = player.fatigue
        var days = 0, rests = 0
        var stop = CalendarAdvanceSummary.Stop.limit
        var expectedRevision = state.revision
        while days < 30 {
            if Task.isCancelled { stop = .cancelled; break }
            try validate(player, state, revision: expectedRevision)
            if try hasGameToday(player: player, state: state) { stop = .fixture; break }
            if try isAnniversaryTomorrow(player: player, state: state) { stop = .anniversary; break }
            let needsRest = !state.hasAction(on: player.gameDate)
            try advanceDay(player: player, state: state, revision: expectedRevision, automaticRest: true, in: context)
            expectedRevision = state.revision
            days += 1
            if needsRest { rests += 1 }
            await onDaySaved?(player.gameDate)
            await Task.yield()
        }
        if stop == .limit {
            if try hasGameToday(player: player, state: state) { stop = .fixture }
            else if try isAnniversaryTomorrow(player: player, state: state) { stop = .anniversary }
        }
        return CalendarAdvanceSummary(days: days, restDays: rests, fatigueBefore: before,
                                      fatigueAfter: player.fatigue, stop: stop)
    }
}
