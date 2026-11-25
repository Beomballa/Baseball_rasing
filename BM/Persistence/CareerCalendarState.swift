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
        private static let baseRules = "career-core-v1"
        private static let overseasRulesPrefix = "career-core-v1+overseas-v147:"
        private static let domesticRulesSeparator = "+domestic-v162:"

        init(player: CareerPlayer, schools: [School], legacySave: Bool, currentLeagueRules: Bool = false) {
            playerID = player.id
            originDate = player.gameDate
            schoolIDs = SeasonSchedule.group(for: player.id, schoolID: player.schoolID, schools: schools)
            actionDate = nil
            revision = 0
            self.legacySave = legacySave
            rulesVersion = Self.baseRules
            if currentLeagueRules, !legacySave, let date = try? GameDate(player.gameDate) {
                rulesVersion = Self.overseasRulesPrefix + String(date.year) + Self.domesticRulesSeparator + String(date.year)
            }
        }

        private var expansionYears: (overseas: Int?, domestic: Int?) {
            get throws {
                if rulesVersion == Self.baseRules { return (nil, nil) }
                let parts = rulesVersion.components(separatedBy: Self.domesticRulesSeparator)
                guard (1...2).contains(parts.count), let overseasPart = parts.first,
                      overseasPart.hasPrefix(Self.overseasRulesPrefix) else { throw CalendarError.invalidGroup }
                func year(_ text: String) throws -> Int {
                    guard let value = Int(text), (1...9998).contains(value), String(value) == text else {
                        throw CalendarError.invalidGroup
                    }
                    return value
                }
                let overseas = try year(String(overseasPart.dropFirst(Self.overseasRulesPrefix.count)))
                let domestic = try parts.count == 2 ? year(parts[1]) : nil
                return (overseas, domestic)
            }
        }

        var overseasExpansionYear: Int? { get throws { try expansionYears.overseas } }
        var domesticExpansionYear: Int? { get throws { try expansionYears.domestic } }

        func isExpandedOverseas(year: Int) throws -> Bool {
            try overseasExpansionYear.map { year >= $0 } ?? false
        }
        func isExpandedDomestic(year: Int) throws -> Bool {
            try domesticExpansionYear.map { year >= $0 } ?? false
        }
        func isExpandedDomesticAtFutureOpening(year: Int) throws -> Bool {
            // The first day advancement adopts the expanded league by the next opening.
            try domesticExpansionYear.map { year >= $0 } ?? (year <= 9998)
        }
        func isExpandedCompetition(level: String, year: Int) throws -> Bool {
            switch level {
            case "domestic-development", "domestic-first-team": try isExpandedDomestic(year: year)
            case "npb-first-team", "mlb-first-team": try isExpandedOverseas(year: year)
            default: false
            }
        }

        /// First successful day advancement fixes the next season's rules without changing any earlier fixtures.
        func adoptOverseasExpansion(after date: GameDate) throws {
            guard try overseasExpansionYear == nil else { return }
            let april = try GameDate(String(format: "%04d-04-01", date.year))
            let firstExpandedYear = date < april ? date.year : date.year + 1
            guard firstExpandedYear <= 9998 else { return }
            rulesVersion = Self.overseasRulesPrefix + String(firstExpandedYear)
        }

        func adoptProfessionalExpansion(after date: GameDate) throws {
            let years = try expansionYears
            guard years.domestic == nil else { return }
            let april = try GameDate(String(format: "%04d-04-01", date.year))
            let firstExpandedYear = date < april ? date.year : date.year + 1
            guard firstExpandedYear <= 9998 else { return }
            rulesVersion = Self.overseasRulesPrefix + String(years.overseas ?? firstExpandedYear)
                + Self.domesticRulesSeparator + String(firstExpandedYear)
        }

        func age(of player: CareerPlayer) throws -> Int {
            try GameDate(originDate).age(startingAt: player.startAge, on: GameDate(player.gameDate))
        }
        @MainActor func registration(for player:CareerPlayer) throws -> CareerMembership? {
            try registration(for:player,on:GameDate(player.gameDate))
        }
        @MainActor func registration(for player:CareerPlayer,on date:GameDate) throws -> CareerMembership? {
            guard let context=modelContext else {return nil}
            return try ContractRegistrationStore.journal(player:player,calendar:self,in:context).current(on:date)
        }
        @MainActor func displayTeamID(for player:CareerPlayer,on date:GameDate) throws -> String? {
            if let member=try registration(for:player,on:date) {return member.teamID}
            let age=try GameDate(originDate).age(startingAt:player.startAge,on:date)
            return age <= 18 ? player.schoolID:nil
        }
        @MainActor func presentationAppearance(for player:CareerPlayer,on date:GameDate,uniformTeamID:String?=nil) throws -> PlayerAppearance {
            let team=try uniformTeamID ?? displayTeamID(for:player,on:date)
            var appearance=player.appearance.wearing(teamID:team)
            // An unaffiliated adult keeps the personal kit, not the saved creation-school uniform.
            if team == nil {appearance.schoolKitID=nil}
            return appearance
        }
        @MainActor func competition(for player:CareerPlayer,year:Int) throws -> CareerCompetitionPlan {
            guard playerID == player.id,schoolIDs.contains(player.schoolID) else {throw CalendarError.invalidGroup}
            if let context=modelContext {
                let journal=try ContractRegistrationStore.journal(player:player,calendar:self,in:context)
                let first=try GameDate(String(format:"%04d-04-01",year)),last=first.adding(days:174)
                let members=try journal.membershipHistory().filter {member in
                    try GameDate(member.since) <= last && (member.enrollmentEnd.map {try GameDate($0) >= first} ?? true) && (member.releasedOn.map {try GameDate($0) > first} ?? true)
                }
                guard members.count <= 1 else {throw ContractRegistrationError.invalid}
                if let original=members.first {
                    let member=try journal.projected(original,on:first)
                    let scheduledKBOTransfer = member.level == KBOFADeclaration.competition
                        && journal.kboTransfers?.acceptedOffers.contains {
                            $0.id == member.offerID && $0.effective <= first.description
                        } == true
                    let expanded = try scheduledKBOTransfer && GameDate(player.gameDate) < first
                        ? isExpandedDomesticAtFutureOpening(year: year)
                        : isExpandedCompetition(level: member.level, year: year)
                    let ids = CareerTeamDirectory.teams(level: member.level, expanded: expanded)
                    guard ids.contains(member.teamID) else { throw CalendarError.invalidGroup }
                    let fixtures = try CareerTeamDirectory.fixtures(level: member.level, year: year, expanded: expanded)
                    return CareerCompetitionPlan(teamID: member.teamID, teamIDs: ids, fixtures: fixtures, membership: member)
                }
            }
            let origin=try GameDate(originDate)
            return CareerCompetitionPlan(teamID:player.schoolID,teamIDs:schoolIDs,
                fixtures:try SeasonSchedule.fixtures(year:year,schoolIDs:schoolIDs).filter {
                    $0.date >= origin && origin.age(startingAt:player.startAge,on:$0.date) <= 18
                },membership:nil)
        }
        @MainActor func teamID(for player:CareerPlayer,on date:GameDate) throws -> String {try competition(for:player,year:date.year).teamID}
        @MainActor func fixtures(for player: CareerPlayer, year: Int) throws -> [SeasonFixture] {
            let plan=try competition(for:player,year:year)
            return try plan.fixtures.filter {fixture in
                guard fixture.includes(plan.teamID) else {return false}
                return try plan.membership?.contains(fixture.date) ?? true
            }.map { $0.forTeam(plan.teamID) }
        }
        @MainActor func upcoming(for player: CareerPlayer) throws -> [SeasonFixture] {
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
    struct ValidatedMatch {
        let key: String
        let completed: Bool
        let appearance: Bool
        let match: CareerMatch
    }
    struct ValidatedSnapshot {
        let league: AnnualLeague
        let matches: [ValidatedMatch]
        let teamID: String
    }
    static func load(player:CareerPlayer,state:CareerCalendarState,year:Int,in context:ModelContext) throws -> AnnualLeague {
        let id=player.id
        let records=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        return try snapshot(player:player,state:state,year:year,records:records)
    }
    static func snapshot(player:CareerPlayer,state:CareerCalendarState,year:Int,records:[CareerMatchRecord]) throws -> AnnualLeague {
        try makeSnapshot(player:player,state:state,year:year,records:records,retainMatches:false).league
    }
    static func validatedSnapshot(player:CareerPlayer,state:CareerCalendarState,year:Int,records:[CareerMatchRecord]) throws -> ValidatedSnapshot {
        try makeSnapshot(player:player,state:state,year:year,records:records,retainMatches:true)
    }
    private static func makeSnapshot(player:CareerPlayer,state:CareerCalendarState,year:Int,records:[CareerMatchRecord],retainMatches:Bool) throws -> ValidatedSnapshot {
        guard state.playerID == player.id,state.schoolIDs.contains(player.schoolID) else {throw LeagueError.invalidRecord}
        let today=try GameDate(player.gameDate),origin=try GameDate(state.originDate)
        let plan=try state.competition(for:player,year:year),fixtures=plan.fixtures
        let byID=Dictionary(uniqueKeysWithValues:fixtures.map {($0.id,$0)})
        var official:[LeagueOfficialResult]=[],pending:Set<String>=[]
        var seen:Set<String>=[],matches:[ValidatedMatch]=[]
        for record in records where record.playerID == player.id {
            guard try GameDate(record.gameDate).year == year else {continue}
            guard let fixture=byID[record.fixtureID],fixture.includes(plan.teamID),fixture.date.description == record.gameDate,
                  record.key == CareerMatchRecord.key(player.id,fixture.id),record.opponentID == fixture.opponent(of:plan.teamID),
                  seen.insert(record.fixtureID).inserted else {throw LeagueError.invalidRecord}
            let match=try record.snapshot()
            guard match.clubSelection?.fixtureNumber.map({ $0 == fixture.forTeam(plan.teamID).number }) ?? true else {
                throw LeagueError.invalidRecord
            }
            guard match.isHome == (fixture.homeID == plan.teamID),match.role == player.roleRaw else {throw LeagueError.invalidRecord}
            guard match.competition == plan.membership?.level else {throw LeagueError.invalidRecord}
            if let member=plan.membership {guard try member.contains(fixture.date) else {throw LeagueError.invalidRecord}}
            if retainMatches {
                matches.append(ValidatedMatch(key:record.key,completed:record.completed,appearance:record.appearance,match:match))
            }
            if record.completed {
                official.append(LeagueOfficialResult(fixtureID:fixture.id,homeScore:match.homeScore,awayScore:match.awayScore))
            } else {pending.insert(fixture.id)}
        }
        let automatic=try state.modelContext.map {try AutomaticLeagueStore.scores(player:player,state:state,year:year,in:$0)} ?? []
        let league=try AnnualLeague.make(playerID:player.id,schoolIDs:plan.teamIDs,origin:origin,startAge:player.startAge,today:today,year:year,official:official,pending:pending,competitionFixtures:fixtures,automatic:automatic)
        // Reuse is confined to this read, after every league validation has succeeded.
        return ValidatedSnapshot(league:league,matches:matches,teamID:plan.teamID)
    }
}

@MainActor enum CareerSeasonStore {
    struct DisplaySnapshot {
        let summary: CareerSeasonSummary
        let teamID: String
    }
    static func load(player: CareerPlayer, state: CareerCalendarState, year: Int, in context: ModelContext) throws -> CareerSeasonSummary {
        try loadDisplaySnapshot(player: player, state: state, year: year, in: context).summary
    }
    static func loadDisplaySnapshot(player: CareerPlayer, state: CareerCalendarState, year: Int, in context: ModelContext) throws -> DisplaySnapshot {
        let id = player.id
        let records = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id }))
        return try displaySnapshot(player: player, state: state, year: year, records: records)
    }
    static func snapshot(player: CareerPlayer, state: CareerCalendarState, year: Int, records: [CareerMatchRecord]) throws -> CareerSeasonSummary {
        try displaySnapshot(player: player, state: state, year: year, records: records).summary
    }
    private static func displaySnapshot(player: CareerPlayer, state: CareerCalendarState, year: Int, records: [CareerMatchRecord]) throws -> DisplaySnapshot {
        let validated = try AnnualLeagueStore.validatedSnapshot(player: player, state: state, year: year, records: records)
        var totals = PersonalSeasonTotals(), coverage=PersonalSeasonCoverage()
        for entry in validated.matches where entry.completed && entry.appearance {
            try totals.add(entry.match.line);coverage.include(entry.match,playerID:player.id)
        }
        // Carry the identity from this validated plan instead of querying it for each display row.
        return DisplaySnapshot(summary: CareerSeasonSummary(league: validated.league, totals: totals, coverage:coverage),teamID:validated.teamID)
    }
}

extension CareerSeasonStore {
    static func offseason(player: CareerPlayer, state: CareerCalendarState, in context: ModelContext) throws -> OffseasonPlan? {
        let today = try GameDate(player.gameDate), origin = try GameDate(state.originDate)
        let april = try GameDate(String(format: "%04d-04-01", today.year))
        let year = today < april ? today.year - 1 : today.year
        guard year >= origin.year else { return nil }
        let summary = try load(player: player, state: state, year: year, in: context)
        guard summary.finalized, let lastGame = summary.league.fixtures.map(\.date).max(), today > lastGame,
              year < 9998, today < (try GameDate(String(format: "%04d-04-01", year + 1))) else { return nil }
        return try OffseasonPlan.make(summary: summary, origin: origin, startAge: player.startAge, today: today)
    }
}

struct CareerSeasonAwardBoard {
    enum Status: Equatable { case inProgress, pending, historical, finalized }

    let year: Int
    let competition: String
    let currentTeamID: String
    let status: Status
    let expectedGames: Int
    let recordedGames: Int
    let honors: [LeagueHonor]
    let reason: String?
    let record: CareerSeasonAwardRecord?
    var coverageAvailable = true
    var bestNine: LeagueBestNine? { record?.bestNine }
    var goldGlove: LeagueGoldGlove? { record?.goldGlove }
}

@MainActor enum CareerSeasonAwardStore {
    static func board(player: CareerPlayer, state: CareerCalendarState, year: Int, ledger: SeasonPlayerLedger? = nil,
                      in context: ModelContext) throws -> CareerSeasonAwardBoard {
        guard state.playerID == player.id else { throw CareerPathError.invalid }
        if let award = try storedHistory(player: player, state: state, in: context)?.seasonAwards?.first(where: { $0.year == year }) {
            return savedBoard(award, player: player, state: state, in: context)
        }
        return try projection(player: player, state: state, year: year, ledger: ledger, in: context)
    }

    static func journalBoards(player: CareerPlayer, state: CareerCalendarState,
                              in context: ModelContext) throws -> [(date: GameDate, board: CareerSeasonAwardBoard)] {
        guard state.playerID == player.id else { throw CareerPathError.invalid }
        let saved = try storedHistory(player: player, state: state, in: context)?.seasonAwards ?? []
        let savedByYear = Dictionary(grouping: saved, by: \.year)
        let today = try GameDate(player.gameDate)
        let origin = try GameDate(state.originDate)
        let id = player.id
        let matches = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id && $0.completed }))
        var officialPerYear: [Int: Int] = [:]
        for match in matches {
            if let year = Int(match.gameDate.prefix(4)) { officialPerYear[year, default: 0] += 1 }
        }
        let years = Set(savedByYear.keys).union(officialPerYear.keys).sorted(by: >)
        return try years.flatMap { year -> [(date: GameDate, board: CareerSeasonAwardBoard)] in
            guard (origin.year...today.year).contains(year), let lastDay = try? scheduledLastDay(year: year),
                  today > lastDay else { return [] }
            let date = lastDay.adding(days: 1)
            if let awards = savedByYear[year] {
                return awards.map { (date, savedBoard($0, player: player, state: state, in: context)) }
            }
            let plan = try state.competition(for: player, year: year)
            let level = plan.membership?.level ?? "highschool"
            guard CareerSeasonAwardRecord.supports(level), !plan.fixtures.isEmpty else { return [] }
            if officialPerYear[year, default: 0] >= 30 {
                return [(date, try projection(player: player, state: state, year: year, ledger: nil, in: context))]
            }
            return [(date, CareerSeasonAwardBoard(year: year, competition: level, currentTeamID: plan.teamID,
                status: .pending, expectedGames: plan.teamIDs.count * 15, recordedGames: 0, honors: [],
                reason: "팀당 30경기의 개인 상세 원장이 모두 필요합니다.", record: nil, coverageAvailable: false))]
        }
    }

    // CalendarProgression supplies the enclosing save. An unavailable award never blocks a day.
    static func freezeIfDue(player: CareerPlayer, state: CareerCalendarState, closingDate: GameDate, in context: ModelContext) {
        guard context.container.schema.entities.contains(where: { $0.name == "AffiliationRecord" }),
              (try? scheduledLastDay(year: closingDate.year)) == closingDate,
              player.gameDate == closingDate.adding(days: 1).description,
              let row = try? CareerPathStore.record(player: player, calendar: state, in: context),
              var history = try? row.snapshot(player: player, calendar: state),
              history.seasonAwards?.contains(where: { $0.year == closingDate.year }) != true,
              let award = (try? projection(player: player, state: state, year: closingDate.year, ledger: nil, in: context))?.record else { return }
        history.seasonAwards = ((history.seasonAwards ?? []) + [award]).sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        guard let data = try? JSONEncoder().encode(history) else { return }
        row.payload = String(decoding: data, as: UTF8.self)
    }

    private static func storedHistory(player: CareerPlayer, state: CareerCalendarState, in context: ModelContext) throws -> CareerPathHistory? {
        guard context.container.schema.entities.contains(where: { $0.name == "AffiliationRecord" }) else { return nil }
        return try CareerPathStore.record(player: player, calendar: state, in: context)?.snapshot(player: player, calendar: state)
    }

    private static func scheduledLastDay(year: Int) throws -> GameDate {
        try GameDate(String(format: "%04d-04-01", year)).adding(days: 174)
    }

    private static func finalBoard(_ award: CareerSeasonAwardRecord, status: CareerSeasonAwardBoard.Status) -> CareerSeasonAwardBoard {
        CareerSeasonAwardBoard(year: award.year, competition: award.competition, currentTeamID: award.teamID, status: status,
                               expectedGames: award.teamIDs.count * 15, recordedGames: award.fixtureIDs.count,
                               honors: award.honors, reason: nil, record: award)
    }

    private static func savedBoard(_ award: CareerSeasonAwardRecord, player: CareerPlayer, state: CareerCalendarState,
                                   in context: ModelContext) -> CareerSeasonAwardBoard {
        var display = award
        // Older season titles remain frozen. Additional evidence comes from the same completed fixtures.
        if display.bestNine == nil || display.goldGlove == nil,
           let rebuilt = (try? projection(player: player, state: state, year: award.year, ledger: nil, in: context))?.record,
           rebuilt.competition == award.competition, rebuilt.teamID == award.teamID, rebuilt.fixtureIDs == award.fixtureIDs {
            display.bestNine = display.bestNine ?? rebuilt.bestNine
            display.goldGlove = display.goldGlove ?? rebuilt.goldGlove
        }
        return finalBoard(display, status: .finalized)
    }

    private static func projection(player: CareerPlayer, state: CareerCalendarState, year: Int, ledger supplied: SeasonPlayerLedger?,
                                   in context: ModelContext) throws -> CareerSeasonAwardBoard {
        let today = try GameDate(player.gameDate)
        let closingDate = try scheduledLastDay(year: year)
        let plan = try state.competition(for: player, year: year)
        let competition = plan.membership?.level ?? "highschool"
        let closed = today > closingDate
        let expected = plan.teamIDs.count * 15
        func pending(_ reason: String, recorded: Int? = nil) -> CareerSeasonAwardBoard {
            CareerSeasonAwardBoard(year: year, competition: competition, currentTeamID: plan.teamID,
                                   status: closed ? .pending : .inProgress, expectedGames: expected, recordedGames: recorded ?? 0,
                                   honors: [], reason: reason, record: nil, coverageAvailable: recorded != nil)
        }
        guard CareerSeasonAwardRecord.supports(competition) else {
            return pending("고교·KBO·NPB·MLB 정규 시즌의 타이틀을 집계합니다.")
        }
        guard plan.fixtures.count == expected else {
            return pending("부분 시즌입니다. 모든 팀의 30경기 일정이 있어야 타이틀을 확정할 수 있습니다.")
        }
        let ledger: SeasonPlayerLedger
        if closed {
            guard let value = try? CareerMatchStore.seasonPlayerRecords(playerID: player.id, year: year, competition: competition,
                                                                      through: closingDate, verifiedAgainst: plan, in: context) else {
                return pending("일정과 완료 원장이 일치하는지 확인한 뒤 타이틀을 확정할 수 있습니다.")
            }
            ledger = value
        } else if let supplied, supplied.careerID == player.id, supplied.competition == competition, supplied.year == year {
            ledger = supplied
        } else {
            return pending("리그 선수 명단에서 현재 선두와 집계 범위를 확인할 수 있습니다.")
        }
        let recorded = Set(ledger.fixtureIDs).intersection(plan.fixtures.map(\.id)).count
        if closed {
            guard let record = try? CareerSeasonAwardRecord.make(ledger: ledger, teamID: plan.teamID, teamIDs: plan.teamIDs,
                                                                 fixtures: plan.fixtures) else {
                return pending("팀당 30경기의 개인 상세 원장이 모두 필요합니다.", recorded: recorded)
            }
            return finalBoard(record, status: .historical)
        }

        let required = Set(plan.fixtures.filter { $0.date < today }.map(\.id))
        let leaders = LeagueHonorRules.leaders(ledger, requiredFixtureIDs: required, teamCount: plan.teamIDs.count)
        return CareerSeasonAwardBoard(year: year, competition: competition, currentTeamID: plan.teamID, status: .inProgress,
                                      expectedGames: expected, recordedGames: recorded, honors: leaders.filter { !$0.final },
                                      reason: LeagueHonorRules.pendingReason(ledger, requiredFixtureIDs: required, teamCount: plan.teamIDs.count),
                                      record: nil)
    }
}

// V1-V8 entity definitions remain unchanged; career history is an independent record.
enum CareerSchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV8.models + [AffiliationRecord.self] }
    @Model final class AffiliationRecord {
        @Attribute(.unique) var playerID: UUID
        var payload: String
        init(_ history: CareerPathHistory) throws {
            playerID = history.playerID
            payload = String(decoding: try JSONEncoder().encode(history), as: UTF8.self)
        }
        func snapshot(player: CareerPlayer, calendar: CareerCalendarState) throws -> CareerPathHistory {
            guard let data = payload.data(using:.utf8) else { throw CareerPathError.invalid }
            let history = try JSONDecoder().decode(CareerPathHistory.self, from:data)
            try history.validate(playerID:player.id, origin:calendar.originDate, today:GameDate(player.gameDate),startAge:player.startAge)
            guard playerID == player.id else { throw CareerPathError.invalid }
            return history
        }
    }
}
typealias CareerAffiliationRecord = CareerSchemaV9.AffiliationRecord

@MainActor enum CareerPathStore {
    static func record(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext) throws -> CareerAffiliationRecord? {
        let id = player.id
        let rows = try context.fetch(FetchDescriptor<CareerAffiliationRecord>(predicate:#Predicate { $0.playerID == id }))
        guard rows.count <= 1, calendar.playerID == id else { throw CareerPathError.invalid }
        if let row = rows.first { _ = try row.snapshot(player:player,calendar:calendar) }
        return rows.first
    }
    // The caller owns the atomic save, including the calendar and scouting boundary.
    static func synchronize(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext, initial: Bool = false) throws {
        guard context.container.schema.entities.contains(where: { $0.name == "AffiliationRecord" }) else { return }
        let today = try GameDate(player.gameDate), age = try calendar.age(of:player)
        guard age >= 16 else { throw CareerPathError.invalid }
        let stage = CareerAffiliation.stage(age:age)
        func entry(_ stage: CareerAffiliation) -> CareerAffiliationEntry {
            CareerAffiliationEntry(stage:stage,since:player.gameDate,schoolID:stage == .school ? player.schoolID:nil,
                                   schoolName:stage == .school ? player.schoolName:nil)
        }
        if let row = try record(player:player,calendar:calendar,in:context) {
            var history = try row.snapshot(player:player,calendar:calendar)
            if history.current.stage != stage {
                history.entries.append(entry(stage))
                try history.validate(playerID:player.id,origin:calendar.originDate,today:today,startAge:player.startAge)
                row.payload = String(decoding:try JSONEncoder().encode(history),as:UTF8.self)
            }
        } else {
            let history = CareerPathHistory(playerID:player.id,origin:calendar.originDate,source:initial ? "initial-v1":"legacy-v1",entries:[entry(stage)])
            try history.validate(playerID:player.id,origin:calendar.originDate,today:today,startAge:player.startAge)
            context.insert(try CareerAffiliationRecord(history))
        }
    }
    static func addMissing(in context: ModelContext) throws {
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        let calendars = try context.fetch(FetchDescriptor<CareerCalendarState>())
        do {
            for player in players where !player.isRetired {
                guard let calendar = calendars.first(where: { $0.playerID == player.id }) else { throw CareerPathError.invalid }
                try synchronize(player:player,calendar:calendar,in:context)
            }
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); throw error }
    }
}

// Other-team games never enter MatchRecord, personal XP or the scouting evidence ledger.
enum CareerSchemaV14:VersionedSchema {
    static let versionIdentifier=Schema.Version(14,0,0)
    static var models:[any PersistentModel.Type] {CareerSchemaV13.models+[LeagueGameRecord.self]}
    @Model final class LeagueGameRecord {
        @Attribute(.unique) var key:String
        var playerID:UUID
        var fixtureID:String
        var gameDate:String
        var competition:String
        var rulesVersion:String
        var payload:Data
        init(playerID:UUID,fixture:SeasonFixture,competition:String,match:CareerMatch) throws {
            key=Self.key(playerID,fixture.id);self.playerID=playerID;fixtureID=fixture.id;gameDate=fixture.date.description
            self.competition=competition;rulesVersion="native-league-player-records-v1";payload=try JSONEncoder().encode(match)
            _ = try snapshot()
        }
        static func key(_ playerID:UUID,_ fixtureID:String) -> String {"league/"+CareerMatchRecord.key(playerID,fixtureID)}
        func snapshot() throws -> CareerMatch {
            let match=try JSONDecoder().decode(CareerMatch.self,from:payload)
            guard rulesVersion == "native-league-player-records-v1",key == Self.key(playerID,fixtureID),
                  match.completed,match.role == "league",!match.appearance,match.isHome,
                  match.half == 18 || match.half == 17 && match.homeScore > match.awayScore,
                  match.line == MatchLine(),match.fatigueCost == 0,match.abilityExperience == nil,match.positionExperience == nil,
                  match.abilityStats == nil,match.fieldStats == nil,match.preparation == nil,match.scoutingPerformance == nil,
                  match.controlVersion == 2,match.trainingEffectsVersion == nil,
                  let roster=match.npcFielders,let attack=match.npcAttack,let records=match.playerRecords,
                  competition == (match.competition ?? "highschool"),competition == roster.competition,
                  records.careerID == playerID,records.fixtureID == fixtureID,
                  records.year == (try GameDate(gameDate)).year,roster.year == records.year,
                  fixtureID == gameDate+"-"+roster.home.teamID+"-"+roster.away.teamID,
                  match.fieldPlays?.isEmpty == true,match.homeRuns == nil else {throw LeagueError.invalidRecord}
            try match.npcReadiness?.validate(match:match,date:gameDate)
            try attack.validate(roster:roster);try match.validatePitching();try match.validateDetailedField();try records.validate(match:match);try match.pitchLog?.validate(match:match);try match.validateRunning()
            return match
        }
    }
}
typealias CareerLeagueGameRecord=CareerSchemaV14.LeagueGameRecord

@MainActor enum AutomaticLeagueStore {
    static func records(playerID:UUID,year:Int?=nil,in context:ModelContext) throws -> [CareerLeagueGameRecord] {
        guard context.container.schema.entities.contains(where:{$0.name == "LeagueGameRecord"}) else {return []}
        let first=year.map {String(format:"%04d-01-01",$0)} ?? "0001-01-01",last=year.map {String(format:"%04d-12-31",$0)} ?? "9999-12-31"
        let rows=try context.fetch(FetchDescriptor<CareerLeagueGameRecord>(predicate:#Predicate {$0.playerID == playerID && $0.gameDate >= first && $0.gameDate <= last}))
        guard Set(rows.map(\.key)).count == rows.count else {throw LeagueError.invalidRecord}
        return rows
    }
    static func simulate(playerID:UUID,fixture:SeasonFixture,competition:String,readiness:MatchNPCReadiness?=nil) throws -> CareerMatch {
        let seed=("native-league-player-records-v1/"+playerID.uuidString+"/"+competition+"/"+fixture.id).utf8.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
        var match=CareerMatch(random:seed,isHome:true,role:"league",appearance:false,contact:60,power:60,discipline:60,mastery:[:])
        match.competition=competition == "highschool" ? nil:competition
        match.controlVersion=2;match.detailedFieldVersion=5;match.battedBallVersion=1
        match.npcFielders=MatchNPCFielders.make(year:fixture.date.year,competition:competition,homeID:fixture.homeID,awayID:fixture.awayID)
        match.npcAttack=MatchNPCAttack.makeComplete(roster:match.npcFielders!)
        match.pitching=MatchPitching();match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.playerRecords = MatchPlayerRecords.make(match: match, careerID: playerID, fixtureID: fixture.id,
                                                      trackEarnedRuns: true, trackDecisions: true, trackFielding: true)
        match.pitchLog=MatchPitchLog();match.npcReadiness=readiness
        match.enablePitchEvents()
        match.enableRunning()
        match.enableFieldReview()
        try match.advance(.automatic)
        try match.validatePitching();try match.validateDetailedField();try match.playerRecords?.validate(match:match);try match.pitchLog?.validate(match:match)
        // Automatic games retain their result/rosters/counters, not unused replay geometry.
        try match.validatePitchEvents();try match.validateRunning()
        match.fieldPlays=[];match.homeRuns=nil;match.pitchEvents=nil
        return match
    }
    // Stages only today's other-team games; the caller commits these with the date transition in one save.
    static func completeDay(player:CareerPlayer,state:CareerCalendarState,date:GameDate,in context:ModelContext) throws {
        guard context.container.schema.entities.contains(where:{$0.name == "LeagueGameRecord"}) else {return}
        guard player.id == state.playerID,date.description == player.gameDate,date >= (try GameDate(state.originDate)) else {throw CalendarError.staleState}
        let plan=try state.competition(for:player,year:date.year),level=plan.membership?.level ?? "highschool"
        let existing=try records(playerID:player.id,year:date.year,in:context)
        for fixture in plan.fixtures where fixture.date == date && !fixture.includes(plan.teamID) {
            if let row=existing.first(where:{$0.fixtureID == fixture.id}) {
                let saved=try row.snapshot()
                guard row.competition == level,saved.npcFielders?.home.teamID == fixture.homeID,saved.npcFielders?.away.teamID == fixture.awayID else {throw LeagueError.invalidRecord}
                continue
            }
            let roster=MatchNPCFielders.make(year:date.year,competition:level,homeID:fixture.homeID,awayID:fixture.awayID)
            let readiness=try NPCSelectionStore.readiness(playerID:player.id,attack:MatchNPCAttack.makeComplete(roster:roster),date:date,in:context)
            let match=try simulate(playerID:player.id,fixture:fixture,competition:level,readiness:readiness)
            context.insert(try CareerLeagueGameRecord(playerID:player.id,fixture:fixture,competition:level,match:match))
        }
    }
    static func scores(player:CareerPlayer,state:CareerCalendarState,year:Int,in context:ModelContext) throws -> [LeagueOfficialResult] {
        let plan=try state.competition(for:player,year:year),today=try GameDate(player.gameDate),level=plan.membership?.level ?? "highschool"
        let fixtures=Dictionary(uniqueKeysWithValues:plan.fixtures.map {($0.id,$0)})
        return try records(playerID:player.id,year:year,in:context).map {row in
            let match=try row.snapshot()
            guard let fixture=fixtures[row.fixtureID],!fixture.includes(plan.teamID),fixture.date < today,
                  row.competition == level,match.npcFielders?.home.teamID == fixture.homeID,match.npcFielders?.away.teamID == fixture.awayID else {throw LeagueError.invalidRecord}
            return LeagueOfficialResult(fixtureID:row.fixtureID,homeScore:match.homeScore,awayScore:match.awayScore)
        }
    }
}
