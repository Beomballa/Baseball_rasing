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
            guard match.competition == nil || ["college","domestic-development"].contains(match.competition!) else {throw MatchError.invalidRecord}
            if let performance = match.scoutingPerformance {
                guard let role = PlayerRole(rawValue:match.role) else {throw MatchError.invalidRecord}
                try performance.validate(line:match.line,role:role)
            }
            try match.validatePitching()
            try match.validateDetailedField()
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
