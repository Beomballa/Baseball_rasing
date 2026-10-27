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
        @MainActor func registration(for player:CareerPlayer) throws -> CareerMembership? {
            guard let context=modelContext else {return nil}
            return try ContractRegistrationStore.journal(player:player,calendar:self,in:context).current(on:GameDate(player.gameDate))
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
                    let ids=CareerTeamDirectory.teams(level:member.level)
                    return CareerCompetitionPlan(teamID:member.teamID,teamIDs:ids,fixtures:try SeasonSchedule.fixtures(year:year,schoolIDs:ids),membership:member)
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
            }
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
    static func load(player:CareerPlayer,state:CareerCalendarState,year:Int,in context:ModelContext) throws -> AnnualLeague {
        let id=player.id
        let records=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id}))
        return try snapshot(player:player,state:state,year:year,records:records)
    }
    static func snapshot(player:CareerPlayer,state:CareerCalendarState,year:Int,records:[CareerMatchRecord]) throws -> AnnualLeague {
        guard state.playerID == player.id,state.schoolIDs.contains(player.schoolID),state.rulesVersion == "career-core-v1" else {throw LeagueError.invalidRecord}
        let today=try GameDate(player.gameDate),origin=try GameDate(state.originDate)
        let plan=try state.competition(for:player,year:year),fixtures=plan.fixtures
        let byID=Dictionary(uniqueKeysWithValues:fixtures.map {($0.id,$0)})
        var official:[LeagueOfficialResult]=[],pending:Set<String>=[]
        var seen:Set<String>=[]
        for record in records where record.playerID == player.id {
            guard try GameDate(record.gameDate).year == year else {continue}
            guard let fixture=byID[record.fixtureID],fixture.includes(plan.teamID),fixture.date.description == record.gameDate,
                  record.key == CareerMatchRecord.key(player.id,fixture.id),record.opponentID == fixture.opponent(of:plan.teamID),
                  seen.insert(record.fixtureID).inserted else {throw LeagueError.invalidRecord}
            let match=try record.snapshot()
            guard match.isHome == (fixture.homeID == plan.teamID),match.role == player.roleRaw else {throw LeagueError.invalidRecord}
            guard match.competition == plan.membership?.level else {throw LeagueError.invalidRecord}
            if let member=plan.membership {guard try member.contains(fixture.date) else {throw LeagueError.invalidRecord}}
            if record.completed {
                official.append(LeagueOfficialResult(fixtureID:fixture.id,homeScore:match.homeScore,awayScore:match.awayScore))
            } else {pending.insert(fixture.id)}
        }
        let automatic=try state.modelContext.map {try AutomaticLeagueStore.scores(player:player,state:state,year:year,in:$0)} ?? []
        return try AnnualLeague.make(playerID:player.id,schoolIDs:plan.teamIDs,origin:origin,startAge:player.startAge,today:today,year:year,official:official,pending:pending,competitionFixtures:fixtures,automatic:automatic)
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
            try attack.validate(roster:roster);try match.validatePitching();try match.validateDetailedField();try records.validate(match:match);try match.pitchLog?.validate(match:match)
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
    static func simulate(playerID:UUID,fixture:SeasonFixture,competition:String) throws -> CareerMatch {
        let seed=("native-league-player-records-v1/"+playerID.uuidString+"/"+competition+"/"+fixture.id).utf8.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
        var match=CareerMatch(random:seed,isHome:true,role:"league",appearance:false,contact:60,power:60,discipline:60,mastery:[:])
        match.competition=competition == "highschool" ? nil:competition
        match.controlVersion=2;match.detailedFieldVersion=5;match.battedBallVersion=1
        match.npcFielders=MatchNPCFielders.make(year:fixture.date.year,competition:competition,homeID:fixture.homeID,awayID:fixture.awayID)
        match.npcAttack=MatchNPCAttack.makeComplete(roster:match.npcFielders!)
        match.pitching=MatchPitching();match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.playerRecords=MatchPlayerRecords.make(match:match,careerID:playerID,fixtureID:fixture.id,trackEarnedRuns:true)
        match.pitchLog=MatchPitchLog()
        try match.advance(.automatic)
        try match.validatePitching();try match.validateDetailedField();try match.playerRecords?.validate(match:match);try match.pitchLog?.validate(match:match)
        // Automatic games retain their result/rosters/counters, not unused replay geometry.
        match.fieldPlays=[];match.homeRuns=nil
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
            let match=try simulate(playerID:player.id,fixture:fixture,competition:level)
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
