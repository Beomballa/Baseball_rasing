import XCTest
import SwiftData
@testable import BM

@MainActor final class CareerTrainingTests: XCTestCase {
    private func setup(_ context: ModelContext, role: PlayerRole = .batter, date: String = "2026-04-01") throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = "훈련선수"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        player.gameDate = date; try context.save()
        return (player, try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }))
    }
    private func attempt(_ player: CareerPlayer, _ calendar: CareerCalendarState, _ record: CareerTrainingRecord, _ context: ModelContext) throws {
        let training = try record.snapshot(); let target = training.targets[training.scores.count]
        let input = player.role == .batter ? TrainingInput(x: target.x, y: target.y, timing: MatchDelivery.contactPhase) : TrainingInput(release: 0.68)
        try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: input, in: context)
    }
    func testGrowthUsesAgeScoreLevelFatigueAndCap() {
        XCTAssertEqual(TrainingRules.growth(before: 65, score: 100, fatigue: 24, age: 16, pitch: false), 65.2028)
        XCTAssertEqual(TrainingRules.growth(before: 72, score: 100, fatigue: 52, age: 16, pitch: true), 72.1498)
        XCTAssertEqual(TrainingRules.growth(before: 99.9999, score: 100, fatigue: 0, age: 16, pitch: false), 100)
        XCTAssertEqual([18,19,20,24,28,31,34,37,41].map(TrainingRules.ageMultiplier), [3,2.2,1.8,1.2,1,0.75,0.5,0.3,0.2])
        XCTAssertLessThan(TrainingRules.growth(before: 65, score: 0, fatigue: 60, age: 40, pitch: false), 65.02)
    }
    func testBothRolesCompleteRewardOnceAndNewMatchUsesGrowth() throws {
        for role in PlayerRole.allCases {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, calendar) = try setup(context, role: role)
            let initialFatigue = player.fatigue, otherValues = [player.power, player.discipline, player.speed, player.defense, player.arm]
            let originalPitches = Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) })
            let record = try CareerTrainingStore.start(player: player, state: calendar, pitchCode: role == .pitcher ? "four-seam" : nil, in: context)
            XCTAssertFalse(calendar.hasAction(on: player.gameDate))
            XCTAssertEqual(try CareerTrainingStore.start(player: player, state: calendar, in: context).key, record.key)
            for _ in 0..<5 { try attempt(player, calendar, record, context) }
            let result = try record.snapshot()
            XCTAssertEqual(result.scores, [100,100,100,100,100]); XCTAssertTrue(record.completed)
            XCTAssertEqual(player.fatigue, initialFatigue + 6); XCTAssertTrue(calendar.hasAction(on: player.gameDate))
            XCTAssertEqual([player.power, player.discipline, player.speed, player.defense, player.arm], otherValues)
            for pitch in player.pitches where pitch.code != "four-seam" { XCTAssertEqual(pitch.mastery, originalPitches[pitch.code]) }
            let payload = record.payload, revision = calendar.revision
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: TrainingInput(), in: context))
            XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: calendar, revision: revision, in: context))
            XCTAssertEqual(try CareerTrainingStore.start(player: player, state: calendar, in: context).payload, payload)
            XCTAssertEqual(player.fatigue, initialFatigue + 6); XCTAssertEqual(calendar.revision, revision)
            let game = try CareerMatchStore.start(player: player, state: calendar, in: context).snapshot()
            if role == .batter {
                XCTAssertEqual(player.contact, result.after); XCTAssertEqual(game.contact, result.after)
                XCTAssertGreaterThan(ManualMatchRules.timingWidth(contact: game.contact), ManualMatchRules.timingWidth(contact: result.before))
            } else {
                XCTAssertEqual(game.mastery["four-seam"], result.after)
                XCTAssertGreaterThan(ManualMatchRules.goodWidth(mastery: result.after), ManualMatchRules.goodWidth(mastery: result.before))
            }
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: calendar, revision: revision, in: context))
        }
    }
    func testPendingLocksRestDayBulkAndMatchUntilTrainingFinishes() async throws {
        for date in ["2026-04-01", "2026-04-02"] {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, calendar) = try setup(context, date: date)
            let record = try CareerTrainingStore.start(player: player, state: calendar, in: context)
            try attempt(player, calendar, record, context)
            XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context))
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: calendar, revision: calendar.revision, in: context))
            XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: calendar, in: context))
            do { _ = try await CalendarProgression.advanceOffDays(player: player, state: calendar, in: context) }
            catch { /* No pending attempt can be skipped by bulk recovery. */ }
            XCTAssertEqual(player.gameDate, date); XCTAssertEqual(player.contact, 65); XCTAssertEqual(player.fatigue, 24)
        }
    }
    func testFailedStartAndFinalRewardRollbackAndRetry() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, calendar) = try setup(context, date: "2026-04-02")
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: calendar, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(calendar.revision, 0); XCTAssertNil(try CareerTrainingStore.record(player: player, in: context))
        let record = try CareerTrainingStore.start(player: player, state: calendar, in: context)
        for _ in 0..<4 { try attempt(player, calendar, record, context) }
        let original = record.payload, revision = calendar.revision, recordRevision = record.revision
        let training = try record.snapshot(), target = training.targets[4]
        let input = TrainingInput(x: target.x, y: target.y, timing: 0.82)
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: recordRevision, input: input, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(record.payload, original); XCTAssertEqual(record.revision, recordRevision); XCTAssertFalse(record.completed)
        XCTAssertEqual(calendar.revision, revision); XCTAssertNil(calendar.actionDate); XCTAssertEqual(player.contact, 65); XCTAssertEqual(player.fatigue, 24)
        try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: recordRevision, input: input, in: context)
        XCTAssertEqual(player.contact, 65.2028); XCTAssertEqual(player.fatigue, 30)
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: recordRevision, input: input, in: context))
        try CalendarProgression.advanceDay(player: player, state: calendar, revision: calendar.revision, in: context)
        XCTAssertEqual(player.gameDate, "2026-04-03"); XCTAssertEqual(player.fatigue, 26)
        XCTAssertFalse(calendar.hasAction(on: player.gameDate))
        XCTAssertNoThrow(try CareerTrainingStore.start(player: player, state: calendar, in: context))
    }
    func testFailedIntermediateSaveKeepsSameTargetAndStaleInputRejected() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, calendar) = try setup(context, role: .pitcher)
        let record = try CareerTrainingStore.start(player: player, state: calendar, pitchCode: "slider", in: context)
        let target = try record.snapshot().targets
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: 0, input: TrainingInput(release: 0.68), in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try record.snapshot().scores.count, 0); XCTAssertEqual(try record.snapshot().targets, target)
        try attempt(player, calendar, record, context)
        for input in [TrainingInput(release: .nan), TrainingInput(release: 1.01), TrainingInput(timing: 0.82)] {
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: input, in: context))
        }
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: 0, input: TrainingInput(release: 0.68), in: context))
        XCTAssertEqual(try record.snapshot().scores, [100])
    }
    func testDiskResumeAndCompletedReopenDoNotPayTwice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("training.store")
        let targets = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let (player, calendar) = try setup(context)
            let record = try CareerTrainingStore.start(player: player, state: calendar, in: context)
            for _ in 0..<2 { try attempt(player, calendar, record, context) }
            return try record.snapshot().targets
        }
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record = try CareerTrainingStore.start(player: player, state: calendar, in: context)
            XCTAssertEqual(try record.snapshot().targets, targets); XCTAssertEqual(try record.snapshot().scores, [100,100])
            XCTAssertEqual(player.contact, 65); XCTAssertFalse(calendar.hasAction(on: player.gameDate))
            for _ in 0..<3 { try attempt(player, calendar, record, context) }
        }
        let container = try CareerStore.makeContainer(url: url), context = container.mainContext
        let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let record = try CareerTrainingStore.start(player: player, state: calendar, in: context)
        XCTAssertTrue(record.completed); XCTAssertEqual(player.contact, 65.2028); XCTAssertEqual(player.fatigue, 30)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 1)
    }
    func testV3MigrationPreservesPlayerCalendarAndMatchPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.store")
        let old: (UUID, Data) = try autoreleasepool {
            let schema = Schema(versionedSchema: CareerSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)])
            let context = container.mainContext; context.autosaveEnabled = false
            let (player, calendar) = try setup(context, role: .pitcher)
            calendar.actionDate = player.gameDate; calendar.revision = 1; player.fatigue = 34
            // V3 has no training entity, so create the pre-training match payload directly.
            let fixture = try XCTUnwrap(calendar.upcoming(for: player).first)
            let match = CareerMatch(random: 42, isHome: true, role: player.roleRaw, appearance: true, contact: player.contact, power: player.power, discipline: player.discipline, mastery: Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) }))
            let record = try CareerMatchRecord(player: player, fixture: fixture, match: match)
            context.insert(record); try context.save()
            return (player.id, record.payload)
        }
        let container = try CareerStore.makeContainer(url: url), context = container.mainContext
        let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        XCTAssertEqual(player.id, old.0); XCTAssertEqual(player.gameDate, "2026-04-01"); XCTAssertEqual(player.fatigue, 34)
        XCTAssertEqual(player.pitches.sorted { $0.order < $1.order }.map(\.mastery), [72,65,48,35])
        XCTAssertTrue(calendar.hasAction(on: player.gameDate))
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first)
        XCTAssertEqual(record.payload, old.1)
        XCTAssertEqual(try CareerMatchStore.start(player: player, state: calendar, in: context).payload, old.1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 0)
    }
    func testRestAlreadyUsedAndUnknownPitchCannotCreateTraining() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, calendar) = try setup(context, role: .pitcher)
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: calendar, pitchCode: "unknown", in: context))
        try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: calendar, pitchCode: "slider", in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 0)
    }
}
