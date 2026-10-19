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

        init(player: CareerPlayer, fixture: SeasonFixture, match: CareerMatch) throws {
            key = Self.key(player.id, fixture.id); playerID = player.id
            fixtureID = fixture.id; gameDate = player.gameDate; opponentID = fixture.opponent(of: player.schoolID)
            appearance = match.appearance; payload = try JSONEncoder().encode(match)
            revision = 0; completed = false; fatigueBefore = player.fatigue; fatigueAfter = player.fatigue
            rulesVersion = "native-match-v1"
        }
        static func key(_ playerID: UUID, _ fixtureID: String) -> String { "\(playerID.uuidString):\(fixtureID)" }
        func snapshot() throws -> CareerMatch {
            guard ["native-match-v1", "native-match-v2"].contains(rulesVersion), let match = try? JSONDecoder().decode(CareerMatch.self, from: payload),
                  match.completed == completed, match.appearance == appearance else { throw MatchError.invalidRecord }
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
        guard state.hasAction(on: player.gameDate) else { throw MatchError.preparation }
        let seed = (player.id.uuidString + fixture.id).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        var match = CareerMatch(random: seed, isHome: fixture.homeID == player.schoolID, role: player.roleRaw,
                                appearance: fixture.isAppearance(for: player.role), contact: player.contact, power: player.power,
                                discipline: player.discipline, mastery: Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) }))
        // Non-appearance team games are only simulated after explicit confirmation, not on screen entry.
        match.controlVersion = 2
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
        record.payload = try JSONEncoder().encode(match)
        if match.controlVersion == 2 { record.rulesVersion = "native-match-v2" }
        record.revision += 1
        if match.completed {
            record.completed = true
            player.fatigue = min(100, max(0, player.fatigue + match.appliedFatigueCost))
            record.fatigueAfter = player.fatigue
        }
        state.revision += 1
        // Result, personal fatigue and completion gate share exactly one explicit save.
        do { try save(context) } catch { context.rollback(); throw error }
    }
}
