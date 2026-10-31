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
        if url == nil && !inMemory {
            let active = try SaveArchiveStore.activeURL(base: configuration.url)
            if active != configuration.url { return try makeContainer(url: active) }
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

// A consistent SQLite snapshot includes WAL transactions without copying a live WAL/SHM trio.
import SQLite3
import CryptoKit
import Observation

struct CareerSaveArchive: Codable, Sendable {
    let format: Int
    let schema: Int
    let created: Date
    let digest: String
    let database: Data
}
enum SaveProtectionError: LocalizedError {
    case invalid, busy, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "지원하지 않거나 손상된 백업입니다. 기존 저장은 변경하지 않았습니다."
        case .busy: "저장이 진행 중이거나 저장소를 읽지 못했습니다. 잠시 후 다시 시도하세요."
        case .unavailable: "이 화면에서는 실제 저장 내보내기·복원을 사용할 수 없습니다."
        }
    }
}
@MainActor enum SaveArchiveStore {
    nonisolated static let maximumBytes = 64 * 1024 * 1024
    nonisolated static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func defaultURL() -> URL {
        ModelConfiguration("Career", schema: Schema(versionedSchema: CareerSchemaV15.self), cloudKitDatabase: .none).url
    }
    static func pointer(_ base: URL) -> URL { base.appendingPathExtension("active-generation") }
    nonisolated static func generationURL(_ id: UUID, base: URL) -> URL {
        base.deletingLastPathComponent().appendingPathComponent("restored-" + id.uuidString).appendingPathComponent("Career.store")
    }
    static func activeURL(base: URL) throws -> URL {
        let file = pointer(base)
        guard FileManager.default.fileExists(atPath: file.path) else { return base }
        let raw = try String(contentsOf: file, encoding: .utf8)
        guard let id = UUID(uuidString: raw) else { throw SaveProtectionError.invalid }
        let url = generationURL(id, base: base)
        guard FileManager.default.fileExists(atPath: url.path) else { throw SaveProtectionError.invalid }
        return url
    }
    nonisolated static func snapshot(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?, output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(destination.path, &output) == SQLITE_OK else { throw SaveProtectionError.busy }
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else { throw SaveProtectionError.busy }
        let step = sqlite3_backup_step(backup, -1), finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE, finish == SQLITE_OK,
              sqlite3_exec(output, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else { throw SaveProtectionError.busy }
    }
    nonisolated static func checkSQLite(_ url: URL) throws {
        var db: OpaquePointer?, statement: OpaquePointer?
        defer { sqlite3_finalize(statement); sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW, let result = sqlite3_column_text(statement, 0),
              String(cString: result) == "ok" else { throw SaveProtectionError.invalid }
        sqlite3_finalize(statement); statement=nil
        guard sqlite3_prepare_v2(db, "SELECT Z_PK FROM ZPLAYER LIMIT 0", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw SaveProtectionError.invalid }
    }
    static func export(container: ModelContainer) throws -> Data {
        guard !container.mainContext.hasChanges, let source = container.configurations.first?.url else { throw SaveProtectionError.busy }
        return try exportSnapshot(source:source)
    }
    static func exportAsync(container:ModelContainer) async throws -> Data {
        guard !container.mainContext.hasChanges,let source=container.configurations.first?.url else {throw SaveProtectionError.busy}
        return try await Task.detached(priority:.utility) {try exportSnapshot(source:source)}.value
    }
    nonisolated private static func exportSnapshot(source:URL) throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("snapshot.store")
        try snapshot(from: source, to: file); try checkSQLite(file)
        let data = try Data(contentsOf: file)
        guard data.count <= maximumBytes else { throw SaveProtectionError.invalid }
        return try JSONEncoder().encode(CareerSaveArchive(format: 1, schema: 15, created: Date(), digest: hash(data), database: data))
    }
    static func prepare(_ data: Data, base: URL) throws -> PreparedSave {try open(try stage(data,base:base))}
    static func prepareAsync(_ data:Data,base:URL) async throws -> PreparedSave {
        let staged=try await Task.detached(priority:.utility) {try stage(data,base:base)}.value
        return try open(staged)
    }
    static func prepareFileAsync(_ file:URL,base:URL) async throws -> PreparedSave {
        let staged=try await Task.detached(priority:.utility) {
            let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size>0,size<=maximumBytes*2 else {throw SaveProtectionError.invalid}
            return try stage(Data(contentsOf:file),base:base)
        }.value
        return try open(staged)
    }
    nonisolated private static func stage(_ data:Data,base:URL) throws -> StagedSave {
        guard data.count <= maximumBytes * 2 else { throw SaveProtectionError.invalid }
        let archive = try JSONDecoder().decode(CareerSaveArchive.self, from: data)
        guard archive.format == 1, archive.schema == 15, !archive.database.isEmpty,
              archive.database.count <= maximumBytes, hash(archive.database) == archive.digest else { throw SaveProtectionError.invalid }
        let id = UUID(), url = generationURL(id, base: base)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try archive.database.write(to: url, options: .atomic); try checkSQLite(url)
            return StagedSave(id:id,url:url,created:archive.created)
        } catch {try? FileManager.default.removeItem(at:url.deletingLastPathComponent());throw error}
    }
    private static func open(_ staged:StagedSave) throws -> PreparedSave {
        let url=staged.url
        do {
            let schema = Schema(versionedSchema: CareerSchemaV15.self)
            let candidate = try ModelContainer(for: schema, configurations: [ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)])
            let players=try validate(candidate)
            return PreparedSave(id:staged.id,url:url,container:candidate,created:staged.created,players:players)
        } catch {try? FileManager.default.removeItem(at:url.deletingLastPathComponent());throw error}
    }
    static func validate(_ candidate:ModelContainer) throws -> [String] {
            let c = candidate.mainContext
            c.autosaveEnabled=false
            guard !c.hasChanges else {throw SaveProtectionError.busy}
            let players = try c.fetch(FetchDescriptor<CareerPlayer>())
            let calendars = try c.fetch(FetchDescriptor<CareerCalendarState>())
            guard Set(players.map(\.id)).count == players.count,
                  Set(calendars.map(\.playerID)) == Set(players.map(\.id)),calendars.count == players.count else {throw SaveProtectionError.invalid}
            let active=try players.filter {try $0.lifecycle.retirement == nil},slots=try c.fetch(FetchDescriptor<ActiveCareerSlot>())
            guard Set(active.map(\.roleRaw)).count == active.count,slots.count == active.count,
                  Set(slots.map(\.playerID)) == Set(active.map(\.id)),Set(slots.map(\.roleRaw)).count == slots.count,
                  slots.allSatisfy({slot in active.contains {$0.id == slot.playerID && $0.roleRaw == slot.roleRaw}}) else {throw SaveProtectionError.invalid}
            for p in players {
                guard let state = calendars.first(where: { $0.playerID == p.id }) else { throw SaveProtectionError.invalid }
                _ = try p.lifecycle; _ = try state.age(of: p)
                _ = try ContractRegistrationStore.journal(player: p, calendar: state, in: c)
            }
            func owner(_ id: UUID) throws -> (CareerPlayer, CareerCalendarState) {
                guard let player=players.first(where: {$0.id == id}), let state=calendars.first(where: {$0.playerID == id}) else { throw SaveProtectionError.invalid }
                return (player,state)
            }
            for row in try c.fetch(FetchDescriptor<CareerAffiliationRecord>()) { let (p,s)=try owner(row.playerID); _ = try row.snapshot(player:p,calendar:s) }
            for row in try c.fetch(FetchDescriptor<CareerContractEvaluation>()) { let (p,s)=try owner(row.playerID); _ = try row.snapshot(player:p,calendar:s) }
            for row in try c.fetch(FetchDescriptor<CareerContractOffer>()) {
                let (p,s)=try owner(row.playerID)
                guard let evaluation=try c.fetch(FetchDescriptor<CareerContractEvaluation>()).first(where: {$0.key == row.key}) else { throw SaveProtectionError.invalid }
                _ = try row.snapshot(evaluation: evaluation,player:p,calendar:s)
            }
            for row in try c.fetch(FetchDescriptor<CareerCertificationRecord>()) { _ = try owner(row.playerID); _ = try row.snapshot() }
            guard try c.fetchCount(FetchDescriptor<PlayerAbilities>()) == players.count,
                  try c.fetchCount(FetchDescriptor<PlayerTraits>()) == players.count,
                  try c.fetchCount(FetchDescriptor<PlayerPositions>()) == players.filter({$0.role == .batter}).count else { throw SaveProtectionError.invalid }
            let abilityRows=try c.fetch(FetchDescriptor<PlayerAbilities>())
            guard Set(abilityRows.map(\.playerID)) == Set(players.map(\.id)) else {throw SaveProtectionError.invalid}
            for row in abilityRows {
                let (p,_)=try owner(row.playerID)
                for kind in p.role == .pitcher ? [TrainingKind.mental,.velocity,.control,.stuff,.stamina]:[.mental] {_ = try row.value(for:kind)}
            }
            for row in try c.fetch(FetchDescriptor<CareerTrainingRecord>()) { _ = try owner(row.playerID); _ = try row.snapshot() }
            for row in try c.fetch(FetchDescriptor<CareerMatchRecord>()) { _ = try owner(row.playerID); _ = try row.snapshot() }
            for row in try c.fetch(FetchDescriptor<CareerLeagueGameRecord>()) { _ = try row.snapshot() }
            for p in players {
                let (_,state)=try owner(p.id)
                _ = try ScoutingObservationStore.reports(player:p,calendar:state,in:c)
            }
            for row in try c.fetch(FetchDescriptor<PlayerTraits>()) { _ = try row.snapshot() }
            for row in try c.fetch(FetchDescriptor<PlayerPositions>()) { _ = try row.snapshot() }
            guard !c.hasChanges else { throw SaveProtectionError.invalid }
            return players.map {$0.name+" · "+$0.role.label+" · "+$0.gameDate+($0.isRetired ? " · 은퇴 보관":" · 진행 중")}.sorted()
    }
}
private struct StagedSave:Sendable {
    let id:UUID
    let url:URL
    let created:Date
}
@MainActor final class PreparedSave {
    let id: UUID
    let url: URL
    let container: ModelContainer
    let created: Date
    let players: [String]
    init(id: UUID, url: URL, container: ModelContainer, created: Date, players: [String]) {
        self.id=id; self.url=url; self.container=container; self.created=created; self.players=players
    }
}
@MainActor @Observable final class SaveProtection {
    var container: ModelContainer
    var generation = UUID()
    let base: URL
    private(set) var recoveryOnly: Bool
    init(container: ModelContainer, base: URL, recoveryOnly: Bool = false) { self.container=container; self.base=base; self.recoveryOnly=recoveryOnly }
    func restore(_ prepared: PreparedSave, commit: (URL, Data) throws -> Void = { try $1.write(to: $0, options: .atomic) }) throws {
        guard prepared.url == SaveArchiveStore.generationURL(prepared.id, base: base) else { throw SaveProtectionError.invalid }
        if container === prepared.container {return}
        guard !container.mainContext.hasChanges, !prepared.container.mainContext.hasChanges else { throw SaveProtectionError.busy }
        try SaveArchiveStore.checkSQLite(prepared.url)
        _ = try SaveArchiveStore.validate(prepared.container)
        try commit(SaveArchiveStore.pointer(base), Data(prepared.id.uuidString.utf8))
        container=prepared.container;recoveryOnly=false;generation=UUID()
    }
}

/// A preferred pitch is a saved selection, never a change to owned pitches or a live round.
@MainActor enum PitchSelectionStore {
    static func resolve(player: CareerPlayer, available: Set<String>? = nil) throws -> String {
        let owned = player.pitches.sorted { $0.order < $1.order }.map(\.code)
        let choices = owned.filter { available?.contains($0) ?? true }
        if let preferred = try player.lifecycle.preferredPitchCode, choices.contains(preferred) { return preferred }
        return choices.first ?? ""
    }
    static func select(_ code: String, player: CareerPlayer, in context: ModelContext,
                       save: CalendarProgression.Save = { try $0.save() }) throws {
        try CareerLifecycleStore.requireActive(player)
        guard player.role == .pitcher, PitchType(rawValue: code) != nil,
              player.pitches.contains(where: { $0.code == code }) else { throw TrainingError.invalidInput }
        var life = try player.lifecycle
        guard life.preferredPitchCode != code else { return }
        life.preferredPitchCode = code
        try life.validate(playerID: player.id, today: player.gameDate)
        do { player.lifecycleData = try JSONEncoder().encode(life); try save(context) }
        catch { context.rollback(); throw error }
    }
}
