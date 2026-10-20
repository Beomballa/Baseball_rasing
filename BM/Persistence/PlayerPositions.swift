import Foundation
import SwiftData

enum CareerSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV6.models + [PlayerPositions.self] }
    @Model final class PlayerPositions {
        @Attribute(.unique) var playerID: UUID
        var payload: Data
        var revision: Int
        var source: String
        init(playerID: UUID, loadout: PositionLoadout, source: String) throws {
            try loadout.validate()
            self.playerID = playerID; payload = try JSONEncoder().encode(loadout); revision = 0; self.source = source
        }
        func snapshot() throws -> PositionLoadout {
            guard let value = try? JSONDecoder().decode(PositionLoadout.self, from: payload) else { throw TrainingError.invalidRecord }
            try value.validate(); return value
        }
    }
}
typealias PlayerPositions = CareerSchemaV7.PlayerPositions

@MainActor enum PlayerPositionStore {
    static func profile(playerID: UUID, in context: ModelContext) throws -> PlayerPositions? {
        try context.fetch(FetchDescriptor<PlayerPositions>(predicate: #Predicate { $0.playerID == playerID })).first
    }
    static func addMissing(in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        let players = try context.fetch(FetchDescriptor<CareerPlayer>()).filter { $0.role == .batter }
        let existing = Set(try context.fetch(FetchDescriptor<PlayerPositions>()).map(\.playerID))
        let missing = players.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return }
        do {
            for player in missing {
                guard let primary = FieldPosition(rawValue: player.positionRaw) else { throw TrainingError.invalidRecord }
                context.insert(try PlayerPositions(playerID: player.id, loadout: PositionLoadout(primary: primary), source: "legacy-v1"))
            }
            try save(context)
        } catch { context.rollback(); throw error }
    }
}
