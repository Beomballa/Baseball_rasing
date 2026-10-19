import Foundation
import SwiftData

@MainActor enum CareerStore {
    static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CareerSchemaV1.self)
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
        return container
    }

    static func create(_ draft: PlayerDraft, schools: [School], in context: ModelContext) throws -> CareerPlayer {
        try draft.validate(schools: schools)
        let role = draft.role.rawValue
        let request = FetchDescriptor<CareerPlayer>(predicate: #Predicate { $0.roleRaw == role })
        guard try context.fetchCount(request) == 0 else { throw CreationError.roleAlreadyExists }
        guard let school = schools.first(where: { $0.id == draft.schoolID }) else { throw CreationError.invalidSchool }
        let player = CareerPlayer(draft: draft, school: school)
        context.insert(player)
        do { try context.save() } catch { context.rollback(); throw error }
        return player
    }
}
