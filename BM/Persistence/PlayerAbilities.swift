import Foundation
import SwiftData

enum CareerSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV4.models + [PlayerAbilities.self] }

    @Model final class PlayerAbilities {
        @Attribute(.unique) var playerID: UUID
        var archetypeRaw: String?
        var productionPresetVersion: String
        var initialValues: Data?
        var mental: Double
        var velocity: Double?
        var control: Double?
        var stuff: Double?
        var stamina: Double?

        init(player: CareerPlayer, archetype: PlayerArchetype?) throws {
            playerID = player.id
            archetypeRaw = archetype?.rawValue
            productionPresetVersion = archetype == nil ? "legacyDemo" : PlayerArchetype.presetVersion
            initialValues = try archetype.map { try JSONEncoder().encode($0.values) }
            // A legacy save gets explicit missing-field defaults, never a reconstructed initial profile.
            let values = (archetype ?? PlayerArchetype.initial(for: player.role)).values
            mental = values.mental
            velocity = player.role == .pitcher ? values.velocity : nil
            control = player.role == .pitcher ? values.control : nil
            stuff = player.role == .pitcher ? values.stuff : nil
            stamina = player.role == .pitcher ? values.stamina : nil
        }
        var label: String { archetypeRaw.flatMap(PlayerArchetype.init(rawValue:))?.label ?? "기존 시연 선수" }
    }
}

typealias PlayerAbilities = CareerSchemaV5.PlayerAbilities

@MainActor enum PlayerAbilityStore {
    static func addMissing(in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        let profiles = try context.fetch(FetchDescriptor<PlayerAbilities>())
        let existing = Set(profiles.map(\.playerID))
        let missing = players.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return }
        do {
            for player in missing { context.insert(try PlayerAbilities(player: player, archetype: nil)) }
            try save(context)
        } catch { context.rollback(); throw error }
    }

    static func apply(_ values: PlayerInitialValues, to player: CareerPlayer) {
        if player.role == .batter {
            player.contact = values.contact; player.power = values.power; player.discipline = values.discipline
        }
        player.speed = values.speed; player.defense = values.defense; player.arm = values.arm
        for pitch in player.pitches { if let mastery = values.pitches[pitch.code] { pitch.mastery = mastery } }
    }
}
