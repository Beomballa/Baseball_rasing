import Foundation
import SwiftData

enum CareerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CareerSchemaV1.Player.self, CareerSchemaV1.PitchMastery.self, CalendarState.self]
    }

    @Model final class CalendarState {
        @Attribute(.unique) var playerID: UUID
        var originDate: String
        var schoolIDs: [String]
        var actionDate: String?
        var revision: Int
        var legacySave: Bool
        var rulesVersion: String

        init(player: CareerPlayer, schools: [School], legacySave: Bool) {
            playerID = player.id
            originDate = player.gameDate
            schoolIDs = SeasonSchedule.group(for: player.id, schoolID: player.schoolID, schools: schools)
            actionDate = nil
            revision = 0
            self.legacySave = legacySave
            rulesVersion = "career-core-v1"
        }
        func age(of player: CareerPlayer) throws -> Int {
            try GameDate(originDate).age(startingAt: player.startAge, on: GameDate(player.gameDate))
        }
        func fixtures(for player: CareerPlayer, year: Int) throws -> [SeasonFixture] {
            guard playerID == player.id else { throw CalendarError.staleState }
            guard schoolIDs.contains(player.schoolID) else { throw CalendarError.invalidGroup }
            let origin = try GameDate(originDate)
            let fixtures = try SeasonSchedule.fixtures(year: year, schoolIDs: schoolIDs)
            return fixtures.filter {
                $0.includes(player.schoolID) && $0.date >= origin && origin.age(startingAt: player.startAge, on: $0.date) <= 18
            }
        }
        func upcoming(for player: CareerPlayer) throws -> [SeasonFixture] {
            let today = try GameDate(player.gameDate)
            return try (today.year...min(today.year + 1, 9998)).flatMap { try fixtures(for: player, year: $0) }
                .filter { $0.date >= today }
        }
        func hasAction(on date: String) -> Bool { actionDate == date }
    }
}

typealias CareerCalendarState = CareerSchemaV2.CalendarState

@MainActor enum CalendarScheduleStatus {
    struct Schedule {
        let annual: [SeasonFixture]
        let upcoming: [SeasonFixture]
        let today: SeasonFixture?
    }
    case loaded(Schedule)
    case failed(String)

    init(player: CareerPlayer, state: CareerCalendarState) {
        do {
            let today = try GameDate(player.gameDate)
            let annual = try state.fixtures(for: player, year: today.year)
            self = .loaded(Schedule(annual: annual, upcoming: try state.upcoming(for: player),
                                    today: annual.first { $0.date == today }))
        } catch { self = .failed(error.localizedDescription) }
    }
    var schedule: Schedule? {
        if case .loaded(let value) = self { value } else { nil }
    }
    var errorMessage: String? {
        if case .failed(let message) = self { message } else { nil }
    }
}

@MainActor enum AnnualLeagueStore {
    static func load(player:CareerPlayer,state:CareerCalendarState,year:Int,in context:ModelContext) throws -> AnnualLeague {
        let id=player.id
        let records=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        return try snapshot(player:player,state:state,year:year,records:records)
    }
    static func snapshot(player:CareerPlayer,state:CareerCalendarState,year:Int,records:[CareerMatchRecord]) throws -> AnnualLeague {
        guard state.playerID == player.id,state.schoolIDs.contains(player.schoolID),state.rulesVersion == "career-core-v1" else {throw LeagueError.invalidRecord}
        let today=try GameDate(player.gameDate),origin=try GameDate(state.originDate)
        let fixtures=try SeasonSchedule.fixtures(year:year,schoolIDs:state.schoolIDs).filter {
            $0.date >= origin && origin.age(startingAt:player.startAge,on:$0.date) <= 18
        }
        let byID=Dictionary(uniqueKeysWithValues:fixtures.map {($0.id,$0)})
        var official:[LeagueOfficialResult]=[],pending:Set<String>=[]
        var seen:Set<String>=[]
        for record in records where record.playerID == player.id {
            guard try GameDate(record.gameDate).year == year else {continue}
            guard let fixture=byID[record.fixtureID],fixture.includes(player.schoolID),fixture.date.description == record.gameDate,
                  record.key == CareerMatchRecord.key(player.id,fixture.id),record.opponentID == fixture.opponent(of:player.schoolID),
                  seen.insert(record.fixtureID).inserted else {throw LeagueError.invalidRecord}
            let match=try record.snapshot()
            guard match.isHome == (fixture.homeID == player.schoolID),match.role == player.roleRaw else {throw LeagueError.invalidRecord}
            if record.completed {
                official.append(LeagueOfficialResult(fixtureID:fixture.id,homeScore:match.homeScore,awayScore:match.awayScore))
            } else {pending.insert(fixture.id)}
        }
        return try AnnualLeague.make(playerID:player.id,schoolIDs:state.schoolIDs,origin:origin,startAge:player.startAge,today:today,year:year,official:official,pending:pending)
    }
}

@MainActor enum CareerSeasonStore {
    static func load(player: CareerPlayer, state: CareerCalendarState, year: Int, in context: ModelContext) throws -> CareerSeasonSummary {
        let id = player.id
        let records = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id }))
        return try snapshot(player: player, state: state, year: year, records: records)
    }
    static func snapshot(player: CareerPlayer, state: CareerCalendarState, year: Int, records: [CareerMatchRecord]) throws -> CareerSeasonSummary {
        let league = try AnnualLeagueStore.snapshot(player: player, state: state, year: year, records: records)
        var totals = PersonalSeasonTotals()
        for record in records where record.playerID == player.id && record.completed && record.appearance {
            guard try GameDate(record.gameDate).year == year else { continue }
            try totals.add(record.snapshot().line)
        }
        return CareerSeasonSummary(league: league, totals: totals)
    }
}

extension CareerSeasonStore {
    static func offseason(player: CareerPlayer, state: CareerCalendarState, in context: ModelContext) throws -> OffseasonPlan? {
        let today = try GameDate(player.gameDate), origin = try GameDate(state.originDate)
        let april = try GameDate(String(format: "%04d-04-01", today.year))
        let year = today < april ? today.year - 1 : today.year
        guard year >= origin.year else { return nil }
        let summary = try load(player: player, state: state, year: year, in: context)
        guard summary.finalized, year < 9998, today < (try GameDate(String(format: "%04d-04-01", year + 1))) else { return nil }
        return try OffseasonPlan.make(summary: summary, origin: origin, startAge: player.startAge, today: today)
    }
}
