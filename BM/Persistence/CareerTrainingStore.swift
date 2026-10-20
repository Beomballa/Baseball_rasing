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
            payload = try JSONEncoder().encode(training); revision = 0; completed = false; rulesVersion = training.kind == nil ? "native-training-v1" : "native-training-v2"
        }
        static func key(_ player: UUID, _ date: String) -> String { "\(player.uuidString):\(date)" }
        func snapshot() throws -> CareerTraining {
            guard ["native-training-v1", "native-training-v2"].contains(rulesVersion), let value = try? JSONDecoder().decode(CareerTraining.self, from: payload),
                  value.playerID == playerID, value.date == gameDate, key == Self.key(playerID, gameDate),
                  value.completed == completed,
                  (rulesVersion == "native-training-v1" ? value.kind == nil : (value.kind == .power || value.kind == .discipline)),
                  (value.selectedKind == .pitch ? value.role == "pitcher" && value.pitchCode != nil : value.role == "batter" && value.pitchCode == nil), value.targets.count == 5, value.scores.count <= 5,
                  value.scores.allSatisfy({ (0...100).contains($0) }), value.before.isFinite, (0...100).contains(value.before),
                  value.targets.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw TrainingError.invalidRecord }
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
        guard try !hasPending(player: player, in: context) else { throw TrainingError.pending }
    }
    private static func value(player: CareerPlayer, code: String?, kind: TrainingKind) throws -> Double {
        if player.role == .batter {
            guard code == nil else { throw TrainingError.invalidInput }
            switch kind {
            case .contact: return player.contact
            case .power: return player.power
            case .discipline: return player.discipline
            case .pitch: throw TrainingError.invalidInput
            }
        }
        guard kind == .pitch, let pitch = player.pitches.first(where: { $0.code == code }) else { throw TrainingError.invalidInput }
        return pitch.mastery
    }
    static func start(player: CareerPlayer, state: CareerCalendarState, pitchCode: String? = nil, kind: TrainingKind? = nil, in context: ModelContext,
                      save: CalendarProgression.Save = { try $0.save() }) throws -> CareerTrainingRecord {
        guard state.playerID == player.id else { throw TrainingError.stale }
        if let saved = try record(player: player, in: context) { _ = try saved.snapshot(); return saved }
        _ = try state.fixtures(for: player, year: GameDate(player.gameDate).year)
        try requireNoPending(player: player, in: context)
        guard !state.hasAction(on: player.gameDate) else { throw TrainingError.actionUsed }
        let id = player.id, date = player.gameDate
        guard try context.fetchCount(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id && $0.gameDate == date })) == 0 else { throw TrainingError.stale }
        let selected = kind ?? (player.role == .pitcher ? .pitch : .contact)
        let before = try value(player: player, code: pitchCode, kind: selected)
        guard before.isFinite, (0..<100).contains(before) else { throw TrainingError.limit }
        let training = CareerTraining(playerID: player.id, date: player.gameDate, role: player.roleRaw, pitchCode: pitchCode,
                                      before: before, fatigue: player.fatigue, age: try state.age(of: player), calendarRevision: state.revision + 1, kind: [.power, .discipline].contains(selected) ? selected : nil)
        let saved = try CareerTrainingRecord(training); context.insert(saved); state.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
        return saved
    }
    static func attempt(player: CareerPlayer, state: CareerCalendarState, record: CareerTrainingRecord, revision: Int,
                        input: TrainingInput, in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        guard !record.completed else { throw TrainingError.finished }
        var training = try record.snapshot()
        guard record.playerID == player.id, training.role == player.roleRaw, state.playerID == player.id,
              record.gameDate == player.gameDate, record.revision == revision, training.calendarRevision == state.revision,
              training.fatigue == player.fatigue, training.age == (try state.age(of: player)),
              training.before == (try value(player: player, code: training.pitchCode, kind: training.selectedKind)), !state.hasAction(on: player.gameDate) else { throw TrainingError.stale }
        try training.attempt(input)
        training.calendarRevision = state.revision + 1
        let payload = try JSONEncoder().encode(training)
        if training.completed {
            if let code = training.pitchCode { player.pitches.first { $0.code == code }?.mastery = training.after }
            else {
                switch training.selectedKind {
                case .power: player.power = training.after
                case .discipline: player.discipline = training.after
                default: player.contact = training.after
                }
            }
            player.fatigue = min(100, player.fatigue + 6)
            state.actionDate = player.gameDate
            record.completed = true
        }
        state.revision += 1
        record.payload = payload; record.revision += 1
        do { try save(context) } catch { context.rollback(); throw error }
    }
}
