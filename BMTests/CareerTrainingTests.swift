import XCTest
import SwiftData
@testable import BM

@MainActor final class CareerTrainingTests: XCTestCase {
    private func setup(_ context: ModelContext, role: PlayerRole = .batter, date: String = "2026-04-01") throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = "훈련선수"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
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
    private func perfectInput(_ training: CareerTraining) -> TrainingInput {
        let target = training.targets[training.scores.count]
        switch training.selectedKind {
        case .power: return TrainingInput(force: TrainingRules.powerTarget(training.scores.count) / 1.35, angle: 45)
        case .discipline: return TrainingInput(calledStrike: ManualMatchRules.isStrike(x: target.x, y: target.y))
        case .contact: return TrainingInput(x: target.x, y: target.y, timing: 0.82)
        case .pitch: return TrainingInput(release: 0.68)
        case .speed: return TrainingInput(footfalls: (0..<16).map { $0.isMultiple(of: 2) ? .left : .right })
        case .defense: return TrainingInput(x: target.x, y: target.y)
        case .arm:
            let base = TrainingRules.throwBase(training.scores.count), target = TrainingRules.basePoint(TrainingRules.throwBase(training.scores.count))
            let angle = atan2(target.y - 0.63, target.x - 0.5) * 180 / .pi
            return TrainingInput(force: hypot(target.x - 0.5, target.y - 0.63) / 0.55 * 100, angle: angle < 0 ? angle + 360 : angle, base: base)
        }
    }
    func testPowerGeometryAndDisciplineClassificationUseDifferentInputs() throws {
        XCTAssertEqual(TrainingRules.distance(force: 100, angle: 45), 135, accuracy: 0.0001)
        XCTAssertLessThan(TrainingRules.distance(force: 100, angle: 15), TrainingRules.distance(force: 100, angle: 45))
        for kind in [TrainingKind.power, .discipline] {
            var training = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "batter", pitchCode: nil, before: 60, fatigue: 24, age: 16, calendarRevision: 1, kind: kind)
            if kind == .discipline { XCTAssertEqual(training.targets.filter { ManualMatchRules.isStrike(x: $0.x, y: $0.y) }.count, 3) }
            for _ in 0..<5 { try training.attempt(perfectInput(training)) }
            XCTAssertEqual(training.scores, [100,100,100,100,100]); XCTAssertEqual(training.after, 60.2028)
        }
        var failed = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "batter", pitchCode: nil, before: 60, fatigue: 24, age: 16, calendarRevision: 1, kind: .discipline)
        let target = failed.targets[0]
        try failed.attempt(TrainingInput(calledStrike: !ManualMatchRules.isStrike(x: target.x, y: target.y)))
        try failed.attempt(TrainingInput()); XCTAssertEqual(failed.scores, [0,0])
        for bad in [TrainingInput(force: .nan, angle: 45), TrainingInput(force: 101, angle: 45), TrainingInput(force: 70, angle: 14), TrainingInput(force: 70), TrainingInput(timing: 0.82)] {
            var power = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "batter", pitchCode: nil, before: 75, fatigue: 24, age: 16, calendarRevision: 1, kind: .power)
            XCTAssertThrowsError(try power.attempt(bad)); XCTAssertTrue(power.scores.isEmpty)
        }
    }
    func testNewKindsGrowOnlyChosenStatAndNewGameCapturesValues() throws {
        for kind in [TrainingKind.power, .discipline] {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, calendar) = try setup(context)
            let record = try CareerTrainingStore.start(player: player, state: calendar, kind: kind, in: context)
            XCTAssertEqual(record.rulesVersion, "native-training-v2")
            for _ in 0..<5 {
                let input = perfectInput(try record.snapshot())
                try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: input, in: context)
            }
            XCTAssertEqual(player.contact, 65); XCTAssertEqual(player.power, kind == .power ? 75.1248 : 75)
            XCTAssertEqual(player.discipline, kind == .discipline ? 60.2028 : 60)
            XCTAssertEqual(player.fatigue, 30); XCTAssertTrue(calendar.hasAction(on: player.gameDate))
            let original = record.payload
            XCTAssertEqual(try CareerTrainingStore.start(player: player, state: calendar, kind: .contact, in: context).payload, original)
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: TrainingInput(), in: context))
            XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context))
            let gameRecord = try CareerMatchStore.start(player: player, state: calendar, in: context)
            let snapshot = try gameRecord.snapshot()
            XCTAssertEqual(snapshot.power, player.power); XCTAssertEqual(snapshot.discipline, player.discipline)
            XCTAssertEqual(snapshot.trainingEffectsVersion, 1)
            XCTAssertEqual(try CareerMatchStore.start(player: player, state: calendar, in: context).payload, gameRecord.payload)
        }
    }
    func testPowerAndDisciplineDiskResumePreserveTargetAndPreventSwitching() throws {
        for kind in [TrainingKind.power, .discipline] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("new-training.store")
            let original = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let (player, calendar) = try setup(context, date: "2026-04-02")
                let record = try CareerTrainingStore.start(player: player, state: calendar, kind: kind, in: context)
                for _ in 0..<2 { try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: perfectInput(record.snapshot()), in: context) }
                XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context))
                XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: calendar, revision: calendar.revision, in: context))
                return record.payload
            }
            try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
                let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record = try CareerTrainingStore.start(player: player, state: calendar, kind: .contact, in: context)
                XCTAssertEqual(record.payload, original); XCTAssertEqual(try record.snapshot().selectedKind, kind)
                XCTAssertEqual(try record.snapshot().scores.count, 2)
                for _ in 0..<3 { try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: perfectInput(record.snapshot()), in: context) }
            }
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record = try CareerTrainingStore.start(player: player, state: calendar, kind: .contact, in: context)
            XCTAssertTrue(record.completed); XCTAssertEqual(player.fatigue, 30)
            XCTAssertEqual(player.power, kind == .power ? 75.1248 : 75)
            XCTAssertEqual(player.discipline, kind == .discipline ? 60.2028 : 60)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 1)
        }
    }
    func testNewKindsFinalSaveRollbackAndSameInputRetryPayOnce() throws {
        enum Injected: Error { case failure }
        for kind in [TrainingKind.power, .discipline] {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, calendar) = try setup(context, date: "2026-04-02")
            let record = try CareerTrainingStore.start(player: player, state: calendar, kind: kind, in: context)
            for _ in 0..<4 { try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: perfectInput(record.snapshot()), in: context) }
            let input = try perfectInput(record.snapshot()), revision = record.revision, payload = record.payload, calendarRevision = calendar.revision
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context, save: { _ in throw Injected.failure }))
            XCTAssertEqual(record.payload, payload); XCTAssertEqual(calendar.revision, calendarRevision)
            XCTAssertEqual(player.power, 75); XCTAssertEqual(player.discipline, 60); XCTAssertEqual(player.fatigue, 24)
            XCTAssertFalse(record.completed); XCTAssertFalse(calendar.hasAction(on: player.gameDate))
            try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context)
            XCTAssertEqual(player.fatigue, 30); XCTAssertTrue(record.completed)
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context))
        }
    }
    func testLegacyTrainingPayloadAndMatchInputsRemainReadableWithoutRewrite() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, calendar) = try setup(context)
        let record = try CareerTrainingStore.start(player: player, state: calendar, in: context)
        let payload = record.payload
        XCTAssertNil(try record.snapshot().kind); XCTAssertEqual(record.rulesVersion, "native-training-v1")
        XCTAssertEqual(try CareerTrainingStore.start(player: player, state: calendar, kind: .power, in: context).payload, payload)
        for _ in 0..<5 { try attempt(player, calendar, record, context) }
        XCTAssertEqual(player.contact, 65.2028); XCTAssertEqual(player.power, 75); XCTAssertEqual(player.discipline, 60)
        var old = CareerMatch(random: 10, isHome: true, role: "batter", appearance: true, contact: 65, power: 75, discipline: 100, mastery: [:])
        old.controlVersion = 2
        let encoded = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(CareerMatch.self, from: encoded).trainingEffectsVersion)
        XCTAssertNotNil(old.automaticControl(.swing, pitchCode: nil).timing)
    }
    func testDisciplineChangesOnlyVersionedAutomaticBallJudgmentWithoutRNGConsumption() throws {
        var seenBalls = 0
        for seed in 0..<100 {
            var low = CareerMatch(random: UInt64(seed), isHome: true, role: "batter", appearance: true, contact: 65, power: 75, discipline: 0, mastery: [:])
            var high = CareerMatch(random: UInt64(seed), isHome: true, role: "batter", appearance: true, contact: 65, power: 75, discipline: 100, mastery: [:])
            low.trainingEffectsVersion = 1; high.trainingEffectsVersion = 1
            let delivery = high.delivery()
            let highInput = high.automaticControl(.swing, pitchCode: nil)
            XCTAssertNotNil(low.automaticControl(.swing, pitchCode: nil).timing)
            XCTAssertEqual(high.random, UInt64(seed))
            if ManualMatchRules.isStrike(x: delivery.x, y: delivery.y) { XCTAssertNotNil(highInput.timing) }
            else { XCTAssertNil(highInput.timing); seenBalls += 1 }
            high.half = 1; high.controlVersion = 2
            var manual = high, automatic = high
            try automatic.advance(.automatic)
            while !manual.completed { try manual.advance(.swing) }
            XCTAssertEqual(manual, automatic)
        }
        XCTAssertGreaterThan(seenBalls, 0)
    }
    func testPowerChangesHomeRunOutcomesWithSamePerfectContacts() throws {
        var highHomeRuns = 0
        for seed in 0..<200 {
            for power in [0.0,100.0] {
                var game = CareerMatch(random: UInt64(seed), isHome: true, role: "batter", appearance: true, contact: 65, power: power, discipline: 60, mastery: [:])
                game.controlVersion = 2; game.half = 1
                let delivery = game.delivery()
                try game.advance(.swing, control: ManualMatchInput(x: delivery.x, y: delivery.y, timing: 0.82))
                if power == 0 { XCTAssertEqual(game.line.homeRuns, 0) }
                else { highHomeRuns += game.line.homeRuns }
            }
        }
        XCTAssertGreaterThan(highHomeRuns, 0)
    }

    func testContactYellowBandHasFullTimingScoreAcrossLevels() {
        let target = TrainingTarget(x: 0.5, y: 0.5)
        for contact in [0.0,35,65,100] {
            for step in 0...100 {
                let timing = MatchDelivery.contactPhase - TrainingRules.contactPerfectWidth + Double(step) / 100 * TrainingRules.contactPerfectWidth * 2
                let result = TrainingRules.contactResult(input: TrainingInput(x: 0.5, y: 0.5, timing: timing), target: target, contact: contact)
                XCTAssertEqual(result.positionScore, 100); XCTAssertEqual(result.timingScore, 100); XCTAssertEqual(result.total, 100)
            }
            for sign in [-1.0,1] {
                let outside = TrainingRules.contactResult(input: TrainingInput(timing: MatchDelivery.contactPhase + sign * 0.04), target: target, contact: contact)
                let edge = TrainingRules.contactResult(input: TrainingInput(timing: MatchDelivery.contactPhase + sign * ManualMatchRules.timingWidth(contact: contact)), target: target, contact: contact)
                XCTAssertLessThan(outside.timingScore,100); XCTAssertGreaterThan(outside.timingScore,0); XCTAssertEqual(edge.timingScore,0)
            }
        }
    }
    func testContactBreakdownExplainsLowCombinedScoreAndNoInput() throws {
        let target = TrainingTarget(x:0.5,y:0.5)
        let miss = TrainingRules.contactResult(input:TrainingInput(x:0.8,y:0.5,timing:0.845),target:target,contact:65)
        XCTAssertEqual(miss.positionScore,0);XCTAssertEqual(miss.timingScore,100);XCTAssertEqual(miss.total,35)
        let near = TrainingRules.contactResult(input:TrainingInput(x:0.50198,y:0.5,timing:0.82),target:target,contact:65)
        XCTAssertEqual(near.positionScore,99);XCTAssertEqual(near.total,99)
        let noInput = TrainingRules.contactResult(input:TrainingInput(),target:target,contact:65)
        XCTAssertFalse(noInput.didSwing);XCTAssertEqual(noInput.total,0)
        var training = CareerTraining(playerID:UUID(),date:"2026-04-02",role:"batter",pitchCode:nil,before:65,fatigue:24,age:16,calendarRevision:1)
        try training.attempt(TrainingInput())
        XCTAssertEqual(training.scores,[0]);XCTAssertEqual(training.lastContact?.total,0)
    }
    func testContactLegacyScoresRemainAndOnlyNextAttemptUsesNewBreakdown() throws {
        var training = CareerTraining(playerID:UUID(),date:"2026-04-02",role:"batter",pitchCode:nil,before:65,fatigue:24,age:16,calendarRevision:1)
        training.scores=[27,35]
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(training)) as? [String:Any]);object.removeValue(forKey:"lastContact")
        let payload=try JSONSerialization.data(withJSONObject:object)
        var restored=try JSONDecoder().decode(CareerTraining.self,from:payload)
        XCTAssertNil(restored.lastContact);XCTAssertEqual(restored.scores,[27,35])
        let target=restored.targets[2]
        try restored.attempt(TrainingInput(x:target.x,y:target.y,timing:0.845))
        XCTAssertEqual(restored.scores,[27,35,100]);XCTAssertEqual(restored.lastContact?.total,100)
        XCTAssertEqual(try JSONDecoder().decode(CareerTraining.self,from:JSONEncoder().encode(restored)),restored)
    }
    func testContactFeedbackDiskResumeAndFailedFinalSavePreserveOneReward() throws {
        enum Injected:Error {case failure}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("contact.store")
        let feedback = try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let (player,state)=try setup(context,date:"2026-04-02")
            let record=try CareerTrainingStore.start(player:player,state:state,in:context)
            for _ in 0..<2 {try attempt(player,state,record,context)}
            return try XCTUnwrap(record.snapshot().lastContact)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record=try CareerTrainingStore.start(player:player,state:state,in:context)
            XCTAssertEqual(try record.snapshot().lastContact,feedback)
            for _ in 0..<2 {try attempt(player,state,record,context)}
            let payload=record.payload,rev=record.revision,training=try record.snapshot(),target=training.targets[4]
            let input=TrainingInput(x:target.x,y:target.y,timing:0.845)
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:rev,input:input,in:context,save:{_ in throw Injected.failure}))
            XCTAssertEqual(record.payload,payload);XCTAssertEqual(player.contact,65);XCTAssertEqual(player.fatigue,24)
            try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:rev,input:input,in:context)
            XCTAssertEqual(try record.snapshot().scores,[100,100,100,100,100]);XCTAssertEqual(player.contact,65.2028)
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:rev,input:input,in:context))
            XCTAssertEqual(player.fatigue,30)
        }
        let container=try CareerStore.makeContainer(url:url),context=container.mainContext
        let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let record=try CareerTrainingStore.start(player:player,state:state,in:context)
        XCTAssertTrue(record.completed);XCTAssertEqual(try record.snapshot().lastContact?.timingScore,100)
        XCTAssertEqual(player.contact,65.2028);XCTAssertEqual(player.fatigue,30)
    }

}
