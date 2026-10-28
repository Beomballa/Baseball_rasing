import Foundation
import SwiftData

enum CareerSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV3.models + [TrainingRecord.self] }
    @Model final class TrainingRecord {
        @Attribute(.unique) var key: String
        var playerID: UUID
        var gameDate: String
        var payload: Data
        var revision: Int
        var completed: Bool
        var rulesVersion: String
        init(_ training: CareerTraining) throws {
            key = Self.key(training.playerID, training.date); playerID = training.playerID; gameDate = training.date
            payload = try JSONEncoder().encode(training); revision = 0; completed = false; rulesVersion = training.isSkillDrill ? "native-skill-drills-v1" : training.pitchStudy != nil ? "native-pitch-study-v1" : training.position != nil ? "native-position-training-v1" : training.trait != nil ? "native-trait-training-v1" : training.selectedKind.isRaw ? "native-training-v4" : training.selectedKind.isField ? "native-training-v3" : training.kind == nil ? "native-training-v1" : "native-training-v2"
        }
        static func key(_ player: UUID, _ date: String) -> String { "\(player.uuidString):\(date)" }
        func snapshot() throws -> CareerTraining {
            guard ["native-training-v1", "native-training-v2", "native-training-v3", "native-training-v4", "native-trait-training-v1", "native-position-training-v1", "native-pitch-study-v1", "native-skill-drills-v1"].contains(rulesVersion), let value = try? JSONDecoder().decode(CareerTraining.self, from: payload),
                  value.playerID == playerID, value.date == gameDate, key == Self.key(playerID, gameDate),
                  value.completed == completed,
                  (rulesVersion == "native-skill-drills-v1" ? value.isSkillDrill : value.drillVersion == nil),
                  (rulesVersion == "native-position-training-v1" ? value.position != nil && value.role == "batter" && value.selectedKind == .defense && (value.positionRevision ?? -1) >= 0 && value.positionXP.map { $0.isFinite && (0..<100).contains($0) } == true : value.position == nil && value.positionRevision == nil && value.positionXP == nil),
                  (rulesVersion == "native-trait-training-v1" ? value.trait != nil && value.selectedKind == value.trait?.trainingKind && (value.traitRevision ?? -1) >= 0 : value.trait == nil && value.traitRevision == nil),
                  (rulesVersion == "native-pitch-study-v1" ? value.pitchStudy != nil && value.kind == nil : value.pitchStudy == nil),
                  (rulesVersion == "native-skill-drills-v1" ? value.isSkillDrill : rulesVersion == "native-training-v1" || rulesVersion == "native-pitch-study-v1" ? value.kind == nil : rulesVersion == "native-training-v2" ? (value.kind == .power || value.kind == .discipline) : ["native-training-v3", "native-trait-training-v1", "native-position-training-v1"].contains(rulesVersion) ? value.selectedKind.isField : value.selectedKind.isRaw),
                  (value.selectedKind == .pitch ? value.role == "pitcher" && value.pitchCode != nil : value.selectedKind.allows(value.role) && value.pitchCode == nil), value.targets.count == 5, value.scores.count <= 5,
                  value.scores.allSatisfy({ (0...100).contains($0) }), value.before.isFinite, (0...100).contains(value.before),
                  value.targets.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw TrainingError.invalidRecord }
            try value.growthPolicy?.validate(training:value)
            try value.pitchStudy?.validate(training: value)
            try value.projectFeedback?.validate(training: value)
            return value
        }
    }
}
typealias CareerTrainingRecord = CareerSchemaV4.TrainingRecord

@MainActor enum CareerTrainingStore {
    static func record(player: CareerPlayer, in context: ModelContext) throws -> CareerTrainingRecord? {
        let key = CareerTrainingRecord.key(player.id, player.gameDate)
        return try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate: #Predicate { $0.key == key })).first
    }
    static func hasPending(player: CareerPlayer, in context: ModelContext) throws -> Bool {
        let id = player.id
        return try context.fetchCount(FetchDescriptor<CareerTrainingRecord>(predicate: #Predicate { $0.playerID == id && !$0.completed })) > 0
    }
    static func requireNoPending(player: CareerPlayer, in context: ModelContext) throws {
        try CareerLifecycleStore.requireActive(player)
        guard try !hasPending(player: player, in: context) else { throw TrainingError.pending }
        if try CertificationStore.hasPending(player:player,in:context) {throw CertificationError.pending}
        try GoalSpecialStore.requireNoPending(player:player,in:context)
    }
    static func value(player: CareerPlayer, code: String?, kind: TrainingKind, in context: ModelContext) throws -> Double {
        guard kind.allows(player.roleRaw) else { throw TrainingError.invalidInput }
        if kind.isRaw {
            guard code == nil, let profile = try PlayerAbilityStore.profile(playerID: player.id, in: context) else { throw TrainingError.invalidRecord }
            return try profile.value(for: kind)
        }
        if kind.isField {
            guard code == nil else { throw TrainingError.invalidInput }
            switch kind { case .speed: return player.speed; case .defense: return player.defense; default: return player.arm }
        }
        if player.role == .batter {
            guard code == nil else { throw TrainingError.invalidInput }
            switch kind {
            case .contact: return player.contact
            case .power: return player.power
            case .discipline: return player.discipline
            default: throw TrainingError.invalidInput
            }
        }
        guard kind == .pitch, let pitch = player.pitches.first(where: { $0.code == code }) else { throw TrainingError.invalidInput }
        return pitch.mastery
    }
    private static func traitProfile(_ trait: PlayerTrait, player: CareerPlayer, in context: ModelContext) throws -> (PlayerTraits, TraitLoadout) {
        guard let profile = try PlayerTraitStore.profile(playerID: player.id, in: context) else { throw TraitError.invalidRecord }
        let loadout = try profile.snapshot()
        guard !loadout.owned.contains(trait), trait.qualifies(speed: player.speed, defense: player.defense, arm: player.arm) else { throw TrainingError.invalidInput }
        return (profile, loadout)
    }
    private static func positionProfile(_ position: FieldPosition, player: CareerPlayer, in context: ModelContext) throws -> (PlayerPositions, PositionLoadout, PositionSkill) {
        guard player.role == .batter, let profile = try PlayerPositionStore.profile(playerID: player.id, in: context) else { throw TrainingError.invalidRecord }
        let loadout = try profile.snapshot()
        return (profile, loadout, try loadout.skill(position))
    }
    private static func completionFeedback(_ training: CareerTraining, player: CareerPlayer, state: CareerCalendarState, record: CareerTrainingRecord, in context: ModelContext) throws -> TrainingProjectFeedback {
        let empty = TrainingProjectFeedback(version:1,activityKey:record.key,project:nil,clubName:nil,before:nil,after:nil)
        guard context.container.schema.entities.contains(where: { $0.name == "ContractRegistration" }) else { return empty }
        let owner = try ContractRegistrationStore.journal(player:player,calendar:state,in:context)
        guard let project = owner.activeProject(on:training.date) else { return empty }
        guard let report = owner.overseasReports?.first(where: { $0.id == project.target.reportID }),
              let club = CareerTargetClub.catalog(report).first(where: { $0.id == project.target.clubID }) else { throw TrainingError.invalidRecord }
        let id=player.id
        let matches=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate { $0.playerID == id }))
        let rows=try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate:#Predicate { $0.playerID == id })).filter { $0.key != record.key }
        let before=try CareerProjectStore.progress(project,on:training.date,matches:matches,trainings:rows)
        // A detached row feeds the existing pure aggregator before any persistent reward mutation.
        let virtual=try CareerTrainingRecord(training); virtual.completed=true; virtual.rulesVersion=record.rulesVersion
        let after=try CareerProjectStore.progress(project,on:training.date,matches:matches,trainings:rows+[virtual])
        let receipt=TrainingProjectFeedback(version:1,activityKey:record.key,project:project,clubName:club.name,before:before,after:after)
        try receipt.validate(training:training)
        return receipt
    }
    static func start(player: CareerPlayer, state: CareerCalendarState, pitchCode: String? = nil, kind: TrainingKind? = nil, trait: PlayerTrait? = nil, position: FieldPosition? = nil, studyCode: String? = nil, replacing: String? = nil, in context: ModelContext,
                      save: CalendarProgression.Save = { try $0.save() }) throws -> CareerTrainingRecord {
        guard state.playerID == player.id else { throw TrainingError.stale }
        guard studyCode == nil ? replacing == nil : pitchCode == nil && trait == nil && position == nil && (kind == nil || kind == .pitch) else { throw TrainingError.invalidInput }
        guard position == nil || (trait == nil && pitchCode == nil && (kind == nil || kind == .defense)) else { throw TrainingError.invalidInput }
        if let saved = try record(player: player, in: context) {
            let training = try saved.snapshot()
            if let studyCode {
                guard training.pitchStudy?.code == studyCode, training.pitchStudy?.replacing == replacing else { throw training.completed ? TrainingError.actionUsed : TrainingError.pending }
            } else if training.pitchStudy != nil {
                guard pitchCode == nil && kind == nil && trait == nil && position == nil else { throw TrainingError.pending }
            }
            guard trait == nil || training.trait == trait else { throw TrainingError.pending }
            guard position == nil || training.position == position else { throw TrainingError.pending }
            return saved
        }
        _ = try state.fixtures(for: player, year: GameDate(player.gameDate).year)
        try requireNoPending(player: player, in: context)
        guard !state.hasAction(on: player.gameDate) else { throw TrainingError.actionUsed }
        let id = player.id, date = player.gameDate
        guard try context.fetchCount(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id && $0.gameDate == date })) == 0 else { throw TrainingError.stale }
        let selected = studyCode != nil ? TrainingKind.pitch : position != nil ? .defense : trait?.trainingKind ?? kind ?? (player.role == .pitcher ? .pitch : .contact)
        let study = try studyCode.map { try PitchStudyStore.preparation(player: player, code: $0, replacing: replacing, in: context) }
        let profile = try trait.map { try traitProfile($0, player: player, in: context) }
        let positions = try position.map { try positionProfile($0, player: player, in: context) }
        guard trait == nil || (pitchCode == nil && (kind == nil || kind == selected)) else { throw TrainingError.invalidInput }
        let before: Double
        if let study { before = try PitchStudyStore.progress(player: player, code: study.code, in: context) }
        else if let positions { before = positions.2.mastery }
        else if let trait, let profile { before = profile.1.trainingProgress(trait) }
        else { before = try value(player: player, code: pitchCode, kind: selected, in: context) }
        guard before.isFinite, (0..<100).contains(before) || study?.restoredMastery != nil && before == 100 else { throw TrainingError.limit }
        var training = CareerTraining(playerID: player.id, date: player.gameDate, role: player.roleRaw, pitchCode: studyCode ?? pitchCode,
                                      before: before, fatigue: player.fatigue, age: try state.age(of: player), calendarRevision: state.revision + 1, kind: selected.isRaw || selected.isField || [.power, .discipline].contains(selected) ? selected : nil, position: position)
        training.trait = trait; training.traitRevision = profile?.0.revision
        training.position = position; training.positionRevision = positions?.0.revision; training.positionXP = positions?.2.xp
        training.pitchStudy = study
        if trait == nil && position == nil && study == nil && SkillDrillRules.kinds.contains(selected) { training.drillVersion = 1 }
        try study?.validate(training: training)
        if trait == nil,position == nil,study == nil {training.growthPolicy=try player.lifecycle.development?.policy(kind:selected,code:pitchCode,on:player.gameDate)}
        let saved = try CareerTrainingRecord(training); context.insert(saved); state.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
        return saved
    }
    static func attempt(player: CareerPlayer, state: CareerCalendarState, record: CareerTrainingRecord, revision: Int,
                        input: TrainingInput, in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        try CareerLifecycleStore.requireActive(player)
        guard !record.completed else { throw TrainingError.finished }
        var training = try record.snapshot()
        let profile = try training.trait.map { try traitProfile($0, player: player, in: context) }
        let positions = try training.position.map { try positionProfile($0, player: player, in: context) }
        let before: Double
        if let study = training.pitchStudy {
            guard try PitchStudyStore.roster(player) == study.rosterSnapshot else { throw TrainingError.stale }
            before = try PitchStudyStore.progress(player: player, code: study.code, in: context)
        }
        else if let positions { before = positions.2.mastery }
        else if let trait = training.trait, let profile { before = profile.1.trainingProgress(trait) }
        else { before = try value(player: player, code: training.pitchCode, kind: training.selectedKind, in: context) }
        guard record.playerID == player.id, training.role == player.roleRaw, state.playerID == player.id,
              record.gameDate == player.gameDate, record.revision == revision, training.calendarRevision == state.revision,
              training.fatigue == player.fatigue, training.age == (try state.age(of: player)),
              training.before == before, training.traitRevision == profile?.0.revision,
              training.positionRevision == positions?.0.revision, training.positionXP == positions?.2.xp,
              !state.hasAction(on: player.gameDate) else { throw TrainingError.stale }
        try training.attempt(input)
        training.calendarRevision = state.revision + 1
        if training.completed { training.projectFeedback = try completionFeedback(training, player: player, state: state, record: record, in: context) }
        var developmentPayload:Data?
        if training.completed,training.growthPolicy != nil {
            var life=try player.lifecycle
            guard var development=life.development else {throw TrainingError.invalidRecord}
            try development.complete(training,key:record.key);life.development=development
            developmentPayload=try JSONEncoder().encode(life)
        }
        let payload = try JSONEncoder().encode(training)
        if training.completed {
            if let position = training.position, let (profile, original, _) = positions {
                var loadout = original; loadout.skills[position.rawValue] = training.positionAfter
                try loadout.validate(); profile.payload = try JSONEncoder().encode(loadout); profile.revision += 1
            } else if let trait = training.trait, let (profile, original) = profile {
                var loadout = original
                loadout.progress[trait.rawValue] = training.after
                if training.after == 100 { loadout.owned.append(trait) }
                try loadout.validate()
                profile.payload = try JSONEncoder().encode(loadout); profile.revision += 1
            } else if let study = training.pitchStudy {
                if training.after == 100 { try PitchStudyStore.register(study, player: player, in: context) }
            } else if let code = training.pitchCode { player.pitches.first { $0.code == code }?.mastery = training.after }
            else if training.selectedKind.isRaw {
                guard let profile = try PlayerAbilityStore.profile(playerID: player.id, in: context) else { throw TrainingError.invalidRecord }
                try profile.grow(training.selectedKind, to: training.after)
            } else {
                switch training.selectedKind {
                case .speed: player.speed = training.after
                case .defense: player.defense = training.after
                case .arm: player.arm = training.after
                case .power: player.power = training.after
                case .discipline: player.discipline = training.after
                default: player.contact = training.after
                }
            }
            if let developmentPayload {player.lifecycleData=developmentPayload}
            player.fatigue = min(100, player.fatigue + TrainingRules.fatigueCost)
            state.actionDate = player.gameDate
            record.completed = true
        }
        state.revision += 1
        record.payload = payload; record.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
    }
}

@MainActor enum PitchStudyStore {
    static func roster(_ player: CareerPlayer) throws -> [PitchStoredSkill] {
        var values: [PitchStoredSkill] = []
        for pitch in player.pitches {
            values.append(PitchStoredSkill(code: pitch.code, name: pitch.name, mastery: pitch.mastery, order: pitch.order))
        }
        values.sort { left, right in
            left.order == right.order ? left.code < right.code : left.order < right.order
        }
        let codes: [String] = values.map { $0.code }
        guard Set(codes).count == values.count,
              values.allSatisfy({ !$0.code.isEmpty && !$0.name.isEmpty && $0.mastery.isFinite && (0...100).contains($0.mastery) && $0.order >= 0 }) else { throw TrainingError.invalidRecord }
        return values
    }
    private static func completedStudies(player: CareerPlayer, in context: ModelContext) throws -> [CareerTraining] {
        let id = player.id
        let records = try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate: #Predicate { $0.playerID == id && $0.completed }))
        return try records.filter { $0.gameDate <= player.gameDate && $0.rulesVersion == "native-pitch-study-v1" }
            .sorted { $0.gameDate < $1.gameDate }.map { try $0.snapshot() }
    }
    static func archived(player: CareerPlayer, in context: ModelContext) throws -> [PitchStoredSkill] {
        var values: [String: PitchStoredSkill] = [:]
        for training in try completedStudies(player: player, in: context) where training.after == 100 {
            if let retired = training.pitchStudy?.retired { values[retired.code] = retired }
        }
        let registered = Set(player.pitches.map(\.code))
        return values.values.filter { !registered.contains($0.code) }.sorted { $0.code < $1.code }
    }
    static func progress(player: CareerPlayer, code: String, in context: ModelContext) throws -> Double {
        guard player.role == .pitcher, PitchType(rawValue: code) != nil else { throw TrainingError.invalidInput }
        if try archived(player: player, in: context).contains(where: { $0.code == code }) { return 100 }
        return try completedStudies(player: player, in: context).last(where: { $0.pitchCode == code })?.after ?? 0
    }
    static func preparation(player: CareerPlayer, code: String, replacing: String?, in context: ModelContext) throws -> PitchStudy {
        guard player.role == .pitcher, PitchType(rawValue: code) != nil,
              !player.pitches.contains(where: { $0.code == code }),
              replacing.map({ old in player.pitches.contains { $0.code == old } }) ?? (player.pitches.count < 5) else { throw TrainingError.invalidInput }
        let stored = try archived(player: player, in: context).first { $0.code == code }
        return PitchStudy(code: code, replacing: replacing, rosterSnapshot: try roster(player), restoredMastery: stored?.mastery)
    }
    static func start(player: CareerPlayer, state: CareerCalendarState, code: String, replacing: String? = nil,
                      in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws -> CareerTrainingRecord {
        try CareerTrainingStore.start(player: player, state: state, studyCode: code, replacing: replacing, in: context, save: save)
    }
    static func register(_ study: PitchStudy, player: CareerPlayer, in context: ModelContext) throws {
        guard try roster(player) == study.rosterSnapshot, let type = PitchType(rawValue: study.code),
              !player.pitches.contains(where: { $0.code == study.code }) else { throw TrainingError.stale }
        let mastery = study.restoredMastery ?? 20
        if let replacing = study.replacing {
            guard let pitch = player.pitches.first(where: { $0.code == replacing }) else { throw TrainingError.stale }
            // The completed training retains this slot's previous value in rosterSnapshot.
            pitch.code = type.rawValue; pitch.name = type.label; pitch.mastery = mastery
        } else {
            guard player.pitches.count < 5 else { throw TrainingError.limit }
            let pitch = CareerPitchMastery(code: type.rawValue, name: type.label, mastery: mastery, order: (player.pitches.map(\.order).max() ?? -1) + 1)
            context.insert(pitch); player.pitches.append(pitch)
        }
    }
}
