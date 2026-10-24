import Foundation
import SwiftData

enum CareerSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CareerSchemaV1.Player.self, CareerSchemaV1.PitchMastery.self, CareerSchemaV2.CalendarState.self, MatchRecord.self]
    }
    @Model final class MatchRecord {
        @Attribute(.unique) var key: String
        var playerID: UUID
        var fixtureID: String
        var gameDate: String
        var opponentID: String
        var appearance: Bool
        var payload: Data
        var revision: Int
        var completed: Bool
        var fatigueBefore: Int
        var fatigueAfter: Int
        var rulesVersion: String

        @MainActor init(player: CareerPlayer, fixture: SeasonFixture, match: CareerMatch) throws {
            key = Self.key(player.id, fixture.id); playerID = player.id
            fixtureID = fixture.id; gameDate = player.gameDate; opponentID = fixture.opponent(of: try player.modelContext.map {context in
                guard let state=try context.fetch(FetchDescriptor<CareerCalendarState>()).first(where:{$0.playerID == player.id}) else {throw CalendarError.staleState}
                return try state.teamID(for:player,on:fixture.date)
            } ?? player.schoolID)
            appearance = match.appearance; payload = try JSONEncoder().encode(match)
            revision = 0; completed = false; fatigueBefore = player.fatigue; fatigueAfter = player.fatigue
            rulesVersion = "native-match-v1"
        }
        static func key(_ playerID: UUID, _ fixtureID: String) -> String { "\(playerID.uuidString):\(fixtureID)" }
        func snapshot() throws -> CareerMatch {
            guard ["native-match-v1", "native-match-v2"].contains(rulesVersion), let match = try? JSONDecoder().decode(CareerMatch.self, from: payload),
                  match.completed == completed, match.appearance == appearance else { throw MatchError.invalidRecord }
            if let stats = match.fieldStats, [2, 3].contains(stats.version) {
                guard let active = stats.activeTraits, TraitLoadout.valid(active) else { throw MatchError.invalidRecord }
                if stats.version == 3 {
                    guard let mastery = stats.positionMastery, mastery.isFinite, (0...100).contains(mastery), FieldPosition(rawValue: stats.position) != nil else { throw MatchError.invalidRecord }
                }
            }
            guard match.competition == nil || ["college","domestic-development","mlb-development","domestic-first-team","npb-first-team","mlb-first-team"].contains(match.competition!) else {throw MatchError.invalidRecord}
            if let performance = match.scoutingPerformance {
                guard let role = PlayerRole(rawValue:match.role) else {throw MatchError.invalidRecord}
                try performance.validate(line:match.line,role:role)
            }
            try match.validatePitching()
            try match.validateDetailedField()
            if let roster=match.npcFielders {
                guard roster.year == (try GameDate(gameDate)).year,roster.team(home:!match.isHome).teamID == opponentID else {throw MatchError.invalidRecord}
            }
            try match.positionExperience?.validate(match: match)
            try match.abilityExperience?.validate(match: match)
            if let growth = match.abilityExperience {
                guard growth.year == (try GameDate(gameDate)).year else { throw MatchError.invalidRecord }
            }
            return match
        }
    }
}

typealias CareerMatchRecord = CareerSchemaV3.MatchRecord

@MainActor enum CareerMatchStore {
    static func record(player: CareerPlayer, fixture: SeasonFixture, in context: ModelContext) throws -> CareerMatchRecord? {
        let key = CareerMatchRecord.key(player.id, fixture.id)
        return try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.key == key })).first
    }
    static func isCompleted(player: CareerPlayer, fixture: SeasonFixture, in context: ModelContext) throws -> Bool {
        guard let saved = try record(player: player, fixture: fixture, in: context) else { return false }
        return try saved.snapshot().completed
    }
    static func today(player: CareerPlayer, state: CareerCalendarState) throws -> SeasonFixture {
        let date = try GameDate(player.gameDate)
        guard state.playerID == player.id,
              let fixture = try state.fixtures(for: player, year: date.year).first(where: { $0.date == date }) else { throw MatchError.noFixture }
        return fixture
    }
    static func start(player: CareerPlayer, state: CareerCalendarState, in context: ModelContext,
                      save: CalendarProgression.Save = { try $0.save() }) throws -> CareerMatchRecord {
        let fixture = try today(player: player, state: state)
        if let saved = try record(player: player, fixture: fixture, in: context) { _ = try saved.snapshot(); return saved }
        try CareerTrainingStore.requireNoPending(player: player, in: context)
        guard state.hasAction(on: player.gameDate) else { throw MatchError.preparation }
        let seed = (player.id.uuidString + fixture.id).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let plan=try state.competition(for:player,year:fixture.date.year)
        var match = CareerMatch(random: seed, isHome: fixture.homeID == plan.teamID, role: player.roleRaw,
                                appearance: fixture.isAppearance(for: player.role), contact: player.contact, power: player.power,
                                discipline: player.discipline, mastery: Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) }))
        match.competition=plan.membership?.level
        // Old schema fixtures and saved matches retain their original rules.
        if context.container.schema.entities.contains(where: { $0.name == "PlayerAbilities" }),
           let profile = try PlayerAbilityStore.profile(playerID: player.id, in: context) {
            match.abilityStats = MatchAbilityStats(mental: try profile.value(for: .mental),
                velocity: player.role == .pitcher ? try profile.value(for: .velocity) : nil,
                control: player.role == .pitcher ? try profile.value(for: .control) : nil,
                stuff: player.role == .pitcher ? try profile.value(for: .stuff) : nil,
                stamina: player.role == .pitcher ? try profile.value(for: .stamina) : nil, fatigue: player.fatigue)
        }
        // Non-appearance team games are only simulated after explicit confirmation, not on screen entry.
        match.controlVersion = 2
        match.trainingEffectsVersion = 1
        match.fieldStats = MatchFieldStats(speed: player.speed, defense: player.defense, arm: player.arm,
                                          position: player.role == .pitcher ? "P" : player.positionRaw)
        if context.container.schema.entities.contains(where: { $0.name == "PlayerTraits" }),
           let traits = try PlayerTraitStore.profile(playerID: player.id, in: context) {
            match.fieldStats?.version = 2
            match.fieldStats?.activeTraits = try traits.snapshot().active
        }
        if player.role == .batter, context.container.schema.entities.contains(where: { $0.name == "PlayerPositions" }) {
            guard let position = FieldPosition(rawValue: player.positionRaw),
                  let profile = try PlayerPositionStore.profile(playerID: player.id, in: context) else { throw TrainingError.invalidRecord }
            match.fieldStats?.version = 3
            let active = match.fieldStats?.activeTraits ?? []
            match.fieldStats?.activeTraits = active
            let skill = try profile.snapshot().skill(position)
            match.fieldStats?.positionMastery = skill.mastery
            match.positionExperience = MatchPositionExperience(position: position, before: skill,
                profileRevision: profile.revision, age: try state.age(of: player), fatigue: player.fatigue)
        }
        match.pitching=MatchPitching(startingFatigue:player.fatigue)
        match.detailedFieldVersion=5;match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.battedBallVersion=1
        match.npcFielders=MatchNPCFielders.make(year:fixture.date.year,competition:match.competition ?? "highschool",homeID:fixture.homeID,awayID:fixture.awayID)
        if match.appearance, match.abilityStats != nil {
            let values = try Dictionary(uniqueKeysWithValues: MatchAbilityExperience.kinds(role: player.roleRaw).map {
                ($0.rawValue, try CareerTrainingStore.value(player: player, code: nil, kind: $0, in: context))
            })
            let year = try GameDate(player.gameDate).year
            match.abilityExperience = MatchAbilityExperience(year: year, age: try state.age(of: player),
                fatigue: player.fatigue, before: values, annualBefore: try annualAbilityXP(playerID: player.id, year: year, in: context))
            try match.abilityExperience?.validate(match: match)
        }
        match.scoutingPerformance = .tracked
        if match.appearance { match.settle() }
        try match.validateDetailedField()
        let saved = try CareerMatchRecord(player: player, fixture: fixture, match: match)
        saved.rulesVersion = "native-match-v2"
        context.insert(saved); state.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
        return saved
    }
    static func advance(player: CareerPlayer, state: CareerCalendarState, record: CareerMatchRecord,
                        revision: Int, input: MatchInput, pitchCode: String? = nil, control: ManualMatchInput? = nil, in context: ModelContext,
                        save: CalendarProgression.Save = { try $0.save() }) throws {
        let fixture = try today(player: player, state: state)
        guard record.playerID == player.id, record.key == CareerMatchRecord.key(player.id, fixture.id),
              record.revision == revision, state.hasAction(on: player.gameDate) else { throw MatchError.stale }
        guard !record.completed else { throw MatchError.finished }
        var match = try record.snapshot()
        try match.advance(input, pitchCode: pitchCode, control: control)
        // Validate all reward recipients before mutating any persistent object.
        var positionReward: (PlayerPositions, PositionLoadout)?
        if match.completed, let experience = match.positionExperience {
            guard let profile = try PlayerPositionStore.profile(playerID: player.id, in: context),
                  profile.revision == experience.profileRevision else { throw MatchError.stale }
            var loadout = try profile.snapshot()
            guard try loadout.skill(experience.position) == experience.before else { throw MatchError.stale }
            loadout.skills[experience.position.rawValue] = experience.after
            try loadout.validate()
            if experience.after != experience.before { positionReward = (profile, loadout) }
        }
        try match.validatePitching()
        try match.validateDetailedField()
        try match.positionExperience?.validate(match: match)
        try match.abilityExperience?.validate(match: match)
        var abilityReward: (PlayerAbilities, MatchAbilityGrowth)?
        if match.completed, let experience = match.abilityExperience, let result = experience.result {
            guard player.fatigue == experience.fatigue,
                  try annualAbilityXP(playerID: player.id, year: experience.year, in: context) == experience.annualBefore,
                  let profile = try PlayerAbilityStore.profile(playerID: player.id, in: context) else { throw MatchError.stale }
            for award in result.awards {
                guard try CareerTrainingStore.value(player: player, code: nil, kind: award.kind, in: context) == award.before else { throw MatchError.stale }
            }
            abilityReward = (profile, result)
        }
        let payload = try JSONEncoder().encode(match)
        let positionPayload = try positionReward.map { try JSONEncoder().encode($0.1) }
        record.payload = payload
        if match.controlVersion == 2 { record.rulesVersion = "native-match-v2" }
        record.revision += 1
        if match.completed {
            record.completed = true
            player.fatigue = min(100, max(0, player.fatigue + match.appliedFatigueCost))
            record.fatigueAfter = player.fatigue
            if let (profile, _) = positionReward, let positionPayload {
                profile.payload = positionPayload
                profile.revision += 1
            }
            if let (profile, growth) = abilityReward {
                for award in growth.awards {
                    switch award.kind {
                    case .contact: player.contact = award.after
                    case .power: player.power = award.after
                    case .discipline: player.discipline = award.after
                    default: try profile.grow(award.kind, to: award.after)
                    }
                }
            }
        }
        state.revision += 1
        // Result, ability growth, position XP, fatigue and completion share one explicit save.
        do { try save(context) } catch { context.rollback(); throw error }
    }

    static func annualAbilityXP(playerID: UUID, year: Int, in context: ModelContext) throws -> Double {
        let records = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == playerID }))
        return try annualAbilityXP(playerID: playerID, year: year, records: records)
    }
    static func annualAbilityXP(playerID: UUID, year: Int, records: [CareerMatchRecord]) throws -> Double {
        let selected = try records.filter {
            guard $0.playerID == playerID, $0.completed else { return false }
            return try GameDate($0.gameDate).year == year
        }
        guard Set(selected.map(\.key)).count == selected.count else { throw MatchError.invalidRecord }
        var total = 0.0
        for record in selected.sorted(by: { ($0.gameDate, $0.key) < ($1.gameDate, $1.key) }) {
            let match = try record.snapshot()
            if let experience = match.abilityExperience, let result = experience.result {
                guard record.appearance, record.key == CareerMatchRecord.key(playerID, record.fixtureID),
                      experience.annualBefore == total else { throw MatchError.invalidRecord }
                total = TrainingRules.round(total + result.rawXP)
            }
        }
        guard total <= MatchAbilityExperience.annualCap else { throw MatchError.invalidRecord }
        return total
    }
}

// Separate assessment journal: never mixed with official league or player match rewards.
enum CareerSchemaV13:VersionedSchema {
    static let versionIdentifier=Schema.Version(13,0,0)
    static var models:[any PersistentModel.Type] {CareerSchemaV12.models+[CertificationRecord.self]}
    @Model final class CertificationRecord {
        @Attribute(.unique) var key:String
        var playerID:UUID
        var payload:Data
        var revision:Int
        var completed:Bool
        init(_ value:CareerCertification) throws {key=value.key;playerID=value.playerID;payload=try JSONEncoder().encode(value);revision=0;completed=false}
        func snapshot() throws -> CareerCertification {
            let value=try JSONDecoder().decode(CareerCertification.self,from:payload)
            guard key == value.key,playerID == value.playerID,completed == value.completed,revision == value.games.count else {throw MatchError.invalidRecord}
            try value.validate();return value
        }
    }
}
typealias CareerCertificationRecord=CareerSchemaV13.CertificationRecord
@MainActor enum CertificationStore {
    static func records(playerID:UUID,in context:ModelContext) throws -> [CareerCertificationRecord] {
        guard context.container.schema.entities.contains(where:{$0.name == "CertificationRecord"}) else {return []}
        let rows=try context.fetch(FetchDescriptor<CareerCertificationRecord>(predicate:#Predicate {$0.playerID == playerID}))
        guard Set(rows.map(\.key)).count == rows.count else {throw MatchError.invalidRecord}
        for row in rows {_ = try row.snapshot()};return rows
    }
    static func hasPending(player:CareerPlayer,in context:ModelContext) throws -> Bool {
        try records(playerID:player.id,in:context).contains {!$0.completed}
    }
    static func target(on date:GameDate) throws -> ContractEvaluationWindow {
        guard let window=(date.year...min(date.year+1,9998)).flatMap({year in [4,7].map {ContractEvaluationWindow(year:year,month:$0)}}).first(where:{$0.start>date}) else {throw ContractEvaluationError.invalid}
        return window
    }
    static func start(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws -> CareerCertificationRecord {
        guard context.container.schema.entities.contains(where:{$0.name == "CertificationRecord"}),!context.hasChanges,calendar.playerID == player.id else {throw ContractRegistrationError.busy}
        let journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),date=try GameDate(player.gameDate)
        guard try journal.current(on:date) == nil,let release=journal.releases?.last else {throw ContractRegistrationError.registered}
        let window=try target(on:date),key=player.id.uuidString+":"+release.membershipOfferID+":"+window.id
        if let row=try records(playerID:player.id,in:context).first(where:{$0.key == key}) {return row}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        guard !calendar.hasAction(on:player.gameDate) else {throw CalendarError.actionUsed}
        let id=player.id
        for row in try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})) {guard try row.snapshot().completed else {throw ContractRegistrationError.busy}}
        var values=PlayerInitialValues(contact:player.contact,power:player.power,discipline:player.discipline,speed:player.speed,defense:player.defense,arm:player.arm)
        guard let profile=try PlayerAbilityStore.profile(playerID:player.id,in:context) else {throw ScoutingReportError.abilities}
        values.mental=try profile.value(for:.mental)
        if player.role == .pitcher {
            values.velocity=try profile.value(for:.velocity);values.control=try profile.value(for:.control)
            values.stuff=try profile.value(for:.stuff);values.stamina=try profile.value(for:.stamina)
            values.pitches=Dictionary(uniqueKeysWithValues:player.pitches.map {($0.code,$0.mastery)})
        }
        let value=CareerCertification(playerID:player.id,releaseOfferID:release.membershipOfferID,window:window,date:player.gameDate,role:player.role,position:player.role == .pitcher ? "P":player.positionRaw,
            values:values,seed:DomesticSelection.hash(key),calendarRevision:calendar.revision+1)
        try value.validate()
        do {let row=try CareerCertificationRecord(value);context.insert(row);calendar.revision += 1;try save(context);return row}
        catch {context.rollback();throw error}
    }
    static func advance(player:CareerPlayer,calendar:CareerCalendarState,row:CareerCertificationRecord,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard !context.hasChanges,row.playerID == player.id,row.revision == revision else {throw MatchError.stale}
        var value=try row.snapshot()
        guard !value.completed else {throw MatchError.finished}
        let journal=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
        guard value.date == player.gameDate,value.calendarRevision == calendar.revision,
              journal.releases?.last?.membershipOfferID == value.releaseOfferID,try journal.current(on:GameDate(player.gameDate)) == nil,
              !calendar.hasAction(on:player.gameDate) else {throw MatchError.stale}
        try value.advance();value.calendarRevision += 1;try value.validate()
        do {
            row.payload=try JSONEncoder().encode(value);row.revision += 1;row.completed=value.completed
            if value.completed {calendar.actionDate=player.gameDate;player.fatigue=min(100,player.fatigue+8)}
            calendar.revision += 1;try save(context)
        } catch {context.rollback();throw error}
    }
    static func assessment(player:CareerPlayer,releaseID:String,window:ContractEvaluationWindow,in context:ModelContext) throws -> CertifiedAssessment? {
        try records(playerID:player.id,in:context).first(where:{$0.key == player.id.uuidString+":"+releaseID+":"+window.id && $0.completed})?.snapshot().assessment
    }
}
