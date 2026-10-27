import Foundation
import SwiftData

enum CareerSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV5.models + [PlayerTraits.self] }
    @Model final class PlayerTraits {
        @Attribute(.unique) var playerID: UUID
        var payload: Data
        var revision: Int
        var source: String
        init(playerID: UUID, loadout: TraitLoadout, source: String) throws {
            try loadout.validate()
            self.playerID = playerID; payload = try JSONEncoder().encode(loadout); revision = 0; self.source = source
        }
        func snapshot() throws -> TraitLoadout {
            guard let value = try? JSONDecoder().decode(TraitLoadout.self, from: payload) else { throw TraitError.invalidRecord }
            try value.validate(); return value
        }
    }
}
typealias PlayerTraits = CareerSchemaV6.PlayerTraits

@MainActor enum PlayerTraitStore {
    static func profile(playerID: UUID, in context: ModelContext) throws -> PlayerTraits? {
        try context.fetch(FetchDescriptor<PlayerTraits>(predicate: #Predicate { $0.playerID == playerID })).first
    }
    static func addMissing(in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        let existing = Set(try context.fetch(FetchDescriptor<PlayerTraits>()).map(\.playerID))
        let missing = players.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return }
        do {
            for player in missing {
                context.insert(try PlayerTraits(playerID: player.id, loadout: TraitLoadout(owned: PlayerTrait.allCases, active: []), source: "legacy-v1"))
            }
            try save(context)
        } catch { context.rollback(); throw error }
    }
    static func requireEditable(player: CareerPlayer, state: CareerCalendarState, in context: ModelContext) throws {
        try CareerLifecycleStore.requireActive(player)
        guard state.playerID == player.id else { throw TraitError.stale }
        _ = try state.fixtures(for: player, year: GameDate(player.gameDate).year)
        guard !state.hasAction(on: player.gameDate), try !CareerTrainingStore.hasPending(player: player, in: context) else { throw TraitError.locked }
        let id = player.id, date = player.gameDate
        guard try context.fetchCount(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id && $0.gameDate == date })) == 0 else { throw TraitError.locked }
    }
    static func toggle(player: CareerPlayer, state: CareerCalendarState, profile: PlayerTraits, trait: PlayerTrait,
                       date: String, revision: Int, calendarRevision: Int, in context: ModelContext,
                       save: CalendarProgression.Save = { try $0.save() }) throws {
        guard profile.playerID == player.id, profile.revision == revision, state.revision == calendarRevision, player.gameDate == date else { throw TraitError.stale }
        try requireEditable(player: player, state: state, in: context)
        var value = try profile.snapshot()
        guard value.owned.contains(trait) else { throw TraitError.notOwned }
        if value.active.contains(trait) { value.active.removeAll { $0 == trait } }
        else { guard value.active.count < 3 else { throw TraitError.notOwned }; value.active.append(trait) }
        try value.validate()
        let payload = try JSONEncoder().encode(value)
        profile.payload = payload; profile.revision += 1; state.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
    }
}
