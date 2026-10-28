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
        // Detached display projection; this record is never inserted into the official match context.
        @MainActor init(assessment:GoalSpecialAssessment,match:CareerMatch,playerID:UUID) throws {
            let number=assessment.games.count+(match.completed ? 0:1)
            key="assessment-display/"+assessment.id+"/"+String(number);self.playerID=playerID
            fixtureID=assessment.id+"/game/"+String(number);gameDate=assessment.date;opponentID=assessment.opponentID
            appearance=true;payload=try JSONEncoder().encode(match);revision=assessment.calendarRevision;completed=match.completed
            fatigueBefore=assessment.fatigue;fatigueAfter=assessment.fatigue;rulesVersion="native-match-v2"
        }
        #if DEBUG
        // Historical QA fixtures are validated against registration/fixtures by the service ledger.
        init(verificationPlayerID:UUID,teamID:String,fixture:SeasonFixture,match:CareerMatch,fatigue:Int) throws {
            guard fixture.includes(teamID),match.completed,match.appearance else {throw MatchError.invalidRecord}
            key=Self.key(verificationPlayerID,fixture.id);playerID=verificationPlayerID;fixtureID=fixture.id
            gameDate=fixture.date.description;opponentID=fixture.opponent(of:teamID);appearance=match.appearance
            payload=try JSONEncoder().encode(match);revision=0;completed=match.completed
            fatigueBefore=fatigue;fatigueAfter=fatigue;rulesVersion="native-match-v2"
        }
        #endif
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
            if let attack=match.npcAttack {
                guard let roster=match.npcFielders,match.controlVersion == 2,match.battedBallVersion == 1,
                      attack.competition == (match.competition ?? "highschool") else {throw MatchError.invalidRecord}
                try roster.validate();try attack.validate(roster:roster)
            }
            if let preparation=match.preparation {
                guard preparation.version == (match.npcAttack == nil ? 1:2),preparation.fixtureID == fixtureID,match.appearance,
                      MatchPlanChoice.choices(match.role).contains(preparation.choice),let roster=match.npcFielders else {throw MatchError.invalidRecord}
                try preparation.season?.validate(analysis: preparation.analysis, date: GameDate(gameDate))
                try roster.validate()
                guard preparation.analysis == MatchOppositionAnalysis.make(roster:roster,isHome:match.isHome,attack:match.npcAttack) else {throw MatchError.invalidRecord}
            }
            try match.npcReadiness?.validate(match:match,date:gameDate)
            try match.clubSelection?.validate(fixtureID:fixtureID,playerID:playerID,date:gameDate,competition:match.competition,appearance:match.appearance,role:match.role)
            if let selection=match.clubSelection {
                guard match.npcFielders?.team(home:match.isHome).teamID == selection.review.teamID,
                      match.fieldStats?.position == selection.review.position else {throw MatchError.invalidRecord}
            }
            try match.projectFeedback?.validate(match:match,key:key,date:gameDate)
            try match.validatePitching()
            try match.inningScores?.validate(match: match)
            try match.pitchLog?.validate(match:match)
            try match.playerRecords?.validate(match:match)
            if let records=match.playerRecords {
                guard records.careerID == playerID,records.fixtureID == fixtureID,
                      records.year == (try GameDate(gameDate)).year,
                      key == Self.key(playerID,fixtureID) else {throw MatchError.invalidRecord}
            }
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
    static func start(player: CareerPlayer, state: CareerCalendarState, planChoice:MatchPlanChoice? = nil, in context: ModelContext,
                      save: CalendarProgression.Save = { try $0.save() }) throws -> CareerMatchRecord {
        let fixture = try today(player: player, state: state)
        if let saved = try record(player: player, fixture: fixture, in: context) { _ = try saved.snapshot(); return saved }
        try CareerTrainingStore.requireNoPending(player: player, in: context)
        guard state.hasAction(on: player.gameDate) else { throw MatchError.preparation }
        let seed = (player.id.uuidString + fixture.id).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let plan=try state.competition(for:player,year:fixture.date.year)
        let selection = try ClubSelectionStore.matchSelection(player:player,calendar:state,fixture:fixture,in:context)
        var match = CareerMatch(random: seed, isHome: fixture.homeID == plan.teamID, role: player.roleRaw,
                                appearance: selection?.appearance ?? fixture.isAppearance(for: player.role), contact: player.contact, power: player.power,
                                discipline: player.discipline, mastery: Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) }))
        match.clubSelection=selection
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
            if match.appearance {
                match.positionExperience = MatchPositionExperience(position: position, before: skill,
                    profileRevision: profile.revision, age: try state.age(of: player), fatigue: player.fatigue)
            }
        }
        match.pitching=MatchPitching(startingFatigue:player.fatigue)
        match.detailedFieldVersion=5;match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.battedBallVersion=1
        match.npcFielders=MatchNPCFielders.make(year:fixture.date.year,competition:match.competition ?? "highschool",homeID:fixture.homeID,awayID:fixture.awayID)
        if let roster=match.npcFielders {match.npcAttack=MatchNPCAttack.makeComplete(roster:roster)}
        if let planChoice {
            guard match.appearance,MatchPlanChoice.choices(match.role).contains(planChoice),let roster=match.npcFielders else {throw MatchError.invalidInput}
            match.preparation=MatchPreparation(version:2,fixtureID:fixture.id,choice:planChoice,analysis:MatchOppositionAnalysis.make(roster:roster,isHome:match.isHome,attack:match.npcAttack))
            if let analysis = match.preparation?.analysis { match.preparation?.season = try opponentSeason(player: player, state: state, analysis: analysis, in: context) }
        }
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
        match.inningScores = MatchInningScores()
        if match.npcAttack != nil {match.playerRecords=MatchPlayerRecords.make(match:match,careerID:player.id,fixtureID:fixture.id,trackEarnedRuns:true)}
        if match.playerRecords != nil {
            match.pitchLog=MatchPitchLog()
            match.npcReadiness=try NPCSelectionStore.readiness(playerID:player.id,attack:match.npcAttack!,date:fixture.date,in:context)
        }
        if match.appearance { match.settle() }
        try match.inningScores?.validate(match: match)
        try match.pitchLog?.validate(match:match)
        try match.playerRecords?.validate(match:match)
        try match.validateDetailedField()
        let saved = try CareerMatchRecord(player: player, fixture: fixture, match: match)
        saved.rulesVersion = "native-match-v2"
        context.insert(saved); state.revision += 1
        do {
            if selection != nil { _ = try ClubSelectionStore.capture(player:player,calendar:state,in:context) }
            try save(context)
        } catch { context.rollback(); throw error }
        return saved
    }
    static func advance(player: CareerPlayer, state: CareerCalendarState, record: CareerMatchRecord,
                        revision: Int, input: MatchInput, pitchCode: String? = nil, control: ManualMatchInput? = nil, in context: ModelContext,
                        save: CalendarProgression.Save = { try $0.save() }) throws {
        try CareerLifecycleStore.requireActive(player)
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
        try match.inningScores?.validate(match: match)
        try match.playerRecords?.validate(match:match)
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
        if match.completed {match.projectFeedback = try completionFeedback(match,player:player,state:state,record:record,fixture:fixture,in:context)}
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

    private static func completionFeedback(_ match:CareerMatch,player:CareerPlayer,state:CareerCalendarState,record:CareerMatchRecord,fixture:SeasonFixture,in context:ModelContext) throws -> MatchProjectFeedback {
        let empty=MatchProjectFeedback(version:1,activityKey:record.key,date:record.gameDate,project:nil,clubName:nil,before:nil,after:nil)
        guard context.container.schema.entities.contains(where:{$0.name == "ContractRegistration"}) else {return empty}
        let owner=try ContractRegistrationStore.journal(player:player,calendar:state,in:context)
        guard let project=owner.activeProject(on:record.gameDate) else {return empty}
        guard let report=owner.overseasReports?.first(where:{$0.id == project.target.reportID}),let club=CareerTargetClub.catalog(report).first(where:{$0.id == project.target.clubID}) else {throw MatchError.invalidRecord}
        let id=player.id
        let rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id})).filter {$0.key != record.key}
        let trainings=try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate:#Predicate {$0.playerID == id}))
        let before=try CareerProjectStore.progress(project,on:record.gameDate,matches:rows,trainings:trainings)
        let virtual=try CareerMatchRecord(player:player,fixture:fixture,match:match);virtual.completed=true;virtual.rulesVersion=record.rulesVersion
        let after=try CareerProjectStore.progress(project,on:record.gameDate,matches:rows+[virtual],trainings:trainings)
        let receipt=MatchProjectFeedback(version:1,activityKey:record.key,date:record.gameDate,project:project,clubName:club.name,before:before,after:after)
        try receipt.validate(match:match,key:record.key,date:record.gameDate)
        return receipt
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
        guard try journal.current(on:date) == nil,let release=journal.activeRetryRelease else {throw ContractRegistrationError.registered}
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
              journal.activeRetryRelease?.membershipOfferID == value.releaseOfferID,try journal.current(on:GameDate(player.gameDate)) == nil,
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


@MainActor extension CareerMatchStore {
    static func startPrepared(player:CareerPlayer,state:CareerCalendarState,choice:MatchPlanChoice,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws -> CareerMatchRecord {
        let fixture=try today(player:player,state:state)
        if let saved=try record(player:player,fixture:fixture,in:context) {
            guard try saved.snapshot().preparation?.choice == choice else {throw MatchError.stale}
            return saved
        }
        guard !context.hasChanges,player.gameDate == date,state.revision == revision else {throw MatchError.stale}
        return try start(player:player,state:state,planChoice:choice,in:context,save:save)
    }
    static func opposition(player:CareerPlayer,state:CareerCalendarState) throws -> MatchOppositionAnalysis {
        let fixture=try today(player:player,state:state),competition=try state.competition(for:player,year:fixture.date.year)
        let roster=MatchNPCFielders.make(year:fixture.date.year,competition:competition.membership?.level ?? "highschool",homeID:fixture.homeID,awayID:fixture.awayID)
        return MatchOppositionAnalysis.make(roster:roster,isHome:fixture.homeID == competition.teamID,attack:MatchNPCAttack.makeComplete(roster:roster))
    }
}

struct SeasonPlayerRecord:Equatable {
    let teamID:String
    let id:String
    var battingGames=0,pitchingGames=0,earnedRunGames=0,unscoredPitchingGames=0
    var batting=MatchBattingCounts()
    var pitching=MatchPitchingCounts(earnedRuns:0)
}
struct SeasonPlayerLedger:Equatable {
    let careerID:UUID
    let year:Int
    let competition:String
    let fixtureIDs:[String]
    let uncollectedGames:Int
    let players:[SeasonPlayerRecord]
}
extension CareerMatchStore {
    // Completed match payloads are the ledger. No independent total is incremented on read or result reopening.
    static func seasonPlayerRecords(playerID:UUID,year:Int,competition:String,through:GameDate?=nil,in context:ModelContext) throws -> SeasonPlayerLedger {
        let rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == playerID && $0.completed}))
        return try seasonPlayerRecords(playerID:playerID,year:year,competition:competition,through:through,records:rows,automatic:AutomaticLeagueStore.records(playerID:playerID,year:year,in:context))
    }
    static func seasonPlayerRecords(playerID:UUID,year:Int,competition:String,through:GameDate?=nil,records:[CareerMatchRecord],automatic:[CareerLeagueGameRecord]=[]) throws -> SeasonPlayerLedger {
        guard (1...9999).contains(year),["highschool","college","domestic-development","mlb-development","domestic-first-team","npb-first-team","mlb-first-team"].contains(competition) else {throw MatchError.invalidRecord}
        var seen=[String:Data](),fixtures=[String](),missing=0,totals=[String:SeasonPlayerRecord]()
        func add(_ ledger:MatchPlayerRecords) {
            fixtures.append(ledger.fixtureID)
            for team in [ledger.home,ledger.away] {
                for line in team.batting {
                    let key=team.teamID+"/"+line.id
                    var sum=totals[key] ?? SeasonPlayerRecord(teamID:team.teamID,id:line.id)
                    if line.counts.plateAppearances > 0 {sum.battingGames += 1}
                    sum.batting.add(line.counts);totals[key]=sum
                }
                for line in team.pitching {
                    let key=team.teamID+"/"+line.id
                    var sum=totals[key] ?? SeasonPlayerRecord(teamID:team.teamID,id:line.id)
                    if line.counts.pitches > 0 {
                        sum.pitchingGames += 1
                        if line.counts.earnedRuns == nil {sum.unscoredPitchingGames += 1} else {sum.earnedRunGames += 1}
                    }
                    sum.pitching.add(line.counts);totals[key]=sum
                }
            }
        }
        for row in records where row.playerID == playerID && row.completed {
            let date=try GameDate(row.gameDate)
            guard date.year == year,through.map({date <= $0}) ?? true else {continue}
            let match=try row.snapshot()
            guard (match.competition ?? "highschool") == competition else {continue}
            guard row.key == CareerMatchRecord.key(playerID,row.fixtureID) else {throw MatchError.invalidRecord}
            if let previous=seen[row.key] {guard previous == row.payload else {throw MatchError.invalidRecord};continue}
            seen[row.key]=row.payload
            guard let ledger=match.playerRecords else {missing += 1;continue}
            add(ledger)
        }
        for row in automatic where row.playerID == playerID {
            let date=try GameDate(row.gameDate)
            guard date.year == year,through.map({date <= $0}) ?? true else {continue}
            let match=try row.snapshot()
            guard row.competition == competition,let ledger=match.playerRecords else {continue}
            let key=CareerMatchRecord.key(playerID,row.fixtureID)
            if let previous=seen[key] {guard previous == row.payload else {throw MatchError.invalidRecord};continue}
            seen[key]=row.payload;add(ledger)
        }
        return SeasonPlayerLedger(careerID:playerID,year:year,competition:competition,fixtureIDs:fixtures.sorted(),uncollectedGames:missing,
            players:totals.values.sorted {$0.teamID == $1.teamID ? $0.id < $1.id:$0.teamID < $1.teamID})
    }
}

extension CareerMatchStore {
    static func opponentSeason(player: CareerPlayer, state: CareerCalendarState, analysis: MatchOppositionAnalysis, in context: ModelContext) throws -> MatchOpponentSeason {
        let fixture = try today(player: player, state: state)
        guard let attack = analysis.attack else { throw MatchError.invalidRecord }
        let cutoff = fixture.date.adding(days: -1)
        let ledger = try seasonPlayerRecords(playerID: player.id, year: fixture.date.year, competition: attack.competition, through: cutoff, in: context)
        let rows = ledger.players.filter { $0.teamID == analysis.teamID }.map {
            MatchOpponentSeasonPlayer(id: $0.id, battingGames: $0.battingGames, pitchingGames: $0.pitchingGames,
                earnedRunGames: $0.earnedRunGames, unscoredPitchingGames: $0.unscoredPitchingGames, batting: $0.batting, pitching: $0.pitching)
        }
        var snapshot = MatchOpponentSeason(version: 1, year: fixture.date.year, competition: attack.competition, teamID: analysis.teamID,
            through: cutoff.description, uncollectedGames: ledger.uncollectedGames, players: rows)
        snapshot.pitchHistory=try opponentPitchHistory(playerID:player.id,year:fixture.date.year,competition:attack.competition,teamID:analysis.teamID,through:cutoff,in:context)
        try snapshot.validate(analysis: analysis, date: fixture.date)
        return snapshot
    }
}


extension CareerMatchStore {
    static func opponentPitchHistory(playerID:UUID,year:Int,competition:String,teamID:String,through:GameDate,in context:ModelContext) throws -> [OpponentPitchHistory] {
        let official=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == playerID && $0.completed}))
        let automatic=try AutomaticLeagueStore.records(playerID:playerID,year:year,in:context)
        var seen=Set<String>(),result:[String:OpponentPitchHistory]=[:]
        func add(key:String,date:String,match:CareerMatch) throws {
            let day=try GameDate(date)
            guard day.year == year,day<=through,(match.competition ?? "highschool") == competition else {return}
            guard seen.insert(key).inserted,let ledger=match.playerRecords else {return}
            guard let team=[ledger.home,ledger.away].first(where:{$0.teamID == teamID}) else {return}
            try match.pitchLog?.validate(match:match)
            for pitcher in team.pitching where pitcher.counts.pitches>0 {
                var value=result[pitcher.id] ?? OpponentPitchHistory(pitcherID:pitcher.id)
                value.games+=1
                if let log=match.pitchLog {value.recordedGames+=1;for pitch in log.pitches where pitch.pitcherID == pitcher.id {value.add(pitch)}}
                result[pitcher.id]=value
            }
        }
        for row in official {try add(key:row.fixtureID,date:row.gameDate,match:row.snapshot())}
        for row in automatic {try add(key:row.fixtureID,date:row.gameDate,match:row.snapshot())}
        return result.values.sorted {$0.pitcherID<$1.pitcherID}
    }
}
