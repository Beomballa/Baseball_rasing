import Foundation
import SwiftData

@MainActor enum CareerStore {
    static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CareerSchemaV15.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("Career", schema: schema, isStoredInMemoryOnly: inMemory,
                                               groupContainer: .none, cloudKitDatabase: .none)
        }
        if !inMemory {try prepareV15Backup(at:configuration.url)}
        let container = try ModelContainer(for: schema, migrationPlan: CareerMigrationPlan.self,
                                           configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        try CareerSlotStore.synchronize(in:container.mainContext)
        try addMissingCalendars(in: container.mainContext)
        try PlayerAbilityStore.addMissing(in: container.mainContext)
        try PlayerTraitStore.addMissing(in: container.mainContext)
        try PlayerPositionStore.addMissing(in: container.mainContext)
        try CareerPathStore.addMissing(in: container.mainContext)
        try ContractEvaluationStore.registerCurrent(in: container.mainContext)
        if !inMemory {try Data("15".utf8).write(to:configuration.url.appendingPathExtension("v15-ready"),options:.atomic)}
        return container
    }

    private static func prepareV15Backup(at url:URL) throws {
        let files=FileManager.default
        guard files.fileExists(atPath:url.path),!files.fileExists(atPath:url.appendingPathExtension("v15-ready").path) else {return}
        let folder=url.deletingLastPathComponent().appendingPathComponent("before-v15-"+UUID().uuidString)
        try files.createDirectory(at:folder,withIntermediateDirectories:true)
        for suffix in ["","-wal","-shm"] {
            let source=URL(fileURLWithPath:url.path+suffix)
            if files.fileExists(atPath:source.path) {try files.copyItem(at:source,to:folder.appendingPathComponent(source.lastPathComponent))}
        }
    }

    private static func addMissingCalendars(in context: ModelContext) throws {
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        let calendars = try context.fetch(FetchDescriptor<CareerCalendarState>())
        let missing = players.filter { player in !calendars.contains { $0.playerID == player.id } }
        guard !missing.isEmpty else { return }
        let schools = try SchoolCatalog.load()
        do {
            for player in missing {
                _ = try GameDate(player.gameDate)
                context.insert(CareerCalendarState(player: player, schools: schools, legacySave: true))
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func create(_ draft: PlayerDraft, schools: [School], in context: ModelContext,
                       save: CalendarProgression.Save = { try $0.save() }) throws -> CareerPlayer {
        try draft.validate(schools: schools)
        let role = draft.role.rawValue
        let request = FetchDescriptor<CareerPlayer>(predicate: #Predicate { $0.roleRaw == role })
        guard try context.fetch(request).allSatisfy({$0.isRetired}) else { throw CreationError.roleAlreadyExists }
        guard let school = schools.first(where: { $0.id == draft.schoolID }) else { throw CreationError.invalidSchool }
        let player = CareerPlayer(draft: draft, school: school)
        var lifecycle=CareerLifecycleState();lifecycle.adopted=player.gameDate
        lifecycle.development=PlayerDevelopment.initial(playerID:player.id,date:player.gameDate)
        player.lifecycleData=try JSONEncoder().encode(lifecycle)
        let values = draft.initialValues
        if player.role == .pitcher {
            player.pitches = draft.selectedPitchCodes.enumerated().compactMap { order, code in
                guard let pitch = PitchType(rawValue: code), let mastery = values.pitches[code] else { return nil }
                return CareerPitchMastery(code: code, name: pitch.label, mastery: mastery, order: order)
            }
        }
        let abilities = try PlayerAbilities(player: player, archetype: draft.selectedArchetype, customValues: draft.isCustom ? values : nil)
        abilities.initialValues = try JSONEncoder().encode(values)
        PlayerAbilityStore.apply(values, to: player)
        let traits = try PlayerTraits(playerID: player.id,
            loadout: TraitLoadout.initial(speed: player.speed, defense: player.defense, arm: player.arm), source: "initial-v1")
        context.insert(player)
        if context.container.schema.entities.contains(where:{$0.name == "ActiveCareerSlot"}) {context.insert(ActiveCareerSlot(role:player.role,playerID:player.id))}
        context.insert(traits)
        context.insert(abilities)
        if player.role == .batter, context.container.schema.entities.contains(where: { $0.name == "PlayerPositions" }) {
            context.insert(try PlayerPositions(playerID: player.id, loadout: PositionLoadout(primary: draft.position), source: "initial-v1"))
        }
        let state = CareerCalendarState(player: player, schools: schools, legacySave: false)
        context.insert(state)
        do {
            try CareerPathStore.synchronize(player: player, calendar: state, in: context, initial: true)
            _ = try ScoutingObservationStore.insertIfNeeded(player: player, calendar: state, in: context)
            try save(context)
        } catch { context.rollback(); throw error }
        return player
    }
}


@MainActor enum CareerSlotStore {
    static func synchronize(in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard context.container.schema.entities.contains(where:{$0.name == "ActiveCareerSlot"}) else {return}
        let players=try context.fetch(FetchDescriptor<CareerPlayer>()),slots=try context.fetch(FetchDescriptor<ActiveCareerSlot>())
        let active=try players.filter {try $0.lifecycle.retirement == nil}
        guard Set(active.map(\.roleRaw)).count == active.count,slots.allSatisfy({slot in active.contains {$0.id == slot.playerID && $0.roleRaw == slot.roleRaw}}) else {throw CareerLifecycleError.invalid}
        let missing=active.filter {p in !slots.contains {$0.playerID == p.id}}
        guard !missing.isEmpty else {return}
        for player in missing {context.insert(ActiveCareerSlot(role:player.role,playerID:player.id))}
        do {try save(context)} catch {context.rollback();throw error}
    }
}
