import Foundation
import SwiftData

@MainActor enum CareerStore {
    static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CareerSchemaV5.self)
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
        let abilities = try PlayerAbilities(player: player, archetype: draft.selectedArchetype)
        PlayerAbilityStore.apply(draft.selectedArchetype.values, to: player)
        context.insert(player)
        context.insert(abilities)
        context.insert(CareerCalendarState(player: player, schools: schools, legacySave: false))
        do { try save(context) } catch { context.rollback(); throw error }
        return player
    }
}
