import Foundation
import SwiftData

@MainActor enum CareerStore {
    static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CareerSchemaV11.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("Career", schema: schema, isStoredInMemoryOnly: inMemory,
                                               groupContainer: .none, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: CareerMigrationPlan.self,
                                           configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        try addMissingCalendars(in: container.mainContext)
        try PlayerAbilityStore.addMissing(in: container.mainContext)
        try PlayerTraitStore.addMissing(in: container.mainContext)
        try PlayerPositionStore.addMissing(in: container.mainContext)
        try CareerPathStore.addMissing(in: container.mainContext)
        try ContractEvaluationStore.registerCurrent(in: container.mainContext)
        return container
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
        guard try context.fetchCount(request) == 0 else { throw CreationError.roleAlreadyExists }
        guard let school = schools.first(where: { $0.id == draft.schoolID }) else { throw CreationError.invalidSchool }
        let player = CareerPlayer(draft: draft, school: school)
        let values = draft.initialValues
        let abilities = try PlayerAbilities(player: player, archetype: draft.selectedArchetype, customValues: draft.isCustom ? values : nil)
        PlayerAbilityStore.apply(values, to: player)
        let traits = try PlayerTraits(playerID: player.id,
            loadout: TraitLoadout.initial(speed: player.speed, defense: player.defense, arm: player.arm), source: "initial-v1")
        context.insert(player)
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
