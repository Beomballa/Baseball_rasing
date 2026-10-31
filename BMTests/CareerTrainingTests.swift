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
    func testV94PreferredPitchSurvivesDayAndDiskReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("pitch-selection.store")
        var id: UUID!, roster: [String] = []
        try autoreleasepool {
            let db = try CareerStore.makeContainer(url: url), c = db.mainContext
            let (p, state) = try setup(c, role: .pitcher, date: "2026-04-02")
            id = p.id; roster = p.pitches.sorted { $0.order < $1.order }.map(\.code)
            let fatigue = p.fatigue, revision = state.revision
            try PitchSelectionStore.select("slider", player: p, in: c)
            XCTAssertEqual(try PitchSelectionStore.resolve(player: p), "slider")
            XCTAssertEqual(p.fatigue, fatigue); XCTAssertEqual(state.revision, revision)
            XCTAssertFalse(state.hasAction(on: p.gameDate))
            try CalendarProgression.rest(player: p, state: state, revision: state.revision, in: c)
            try CalendarProgression.advanceDay(player: p, state: state, revision: state.revision, in: c)
            XCTAssertEqual(p.gameDate, "2026-04-03")
        }
        try autoreleasepool {
            let db = try CareerStore.makeContainer(url: url), c = db.mainContext
            let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first { $0.id == id })
            XCTAssertEqual(try PitchSelectionStore.resolve(player: p), "slider")
            XCTAssertEqual(p.pitches.sorted { $0.order < $1.order }.map(\.code), roster)
            XCTAssertEqual(p.gameDate, "2026-04-03")
        }
    }
    func testV94SelectionFailureAndLegacyFallbackPreserveState() throws {
        let db = try CareerStore.makeContainer(inMemory: true), c = db.mainContext
        let (p, state) = try setup(c, role: .pitcher, date: "2026-04-02")
        let legacy = try JSONEncoder().encode(CareerLifecycleState())
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        XCTAssertNil(raw["preferredPitchCode"])
        p.lifecycleData = legacy; try c.save()
        let first = p.pitches.sorted { $0.order < $1.order }.first!.code
        XCTAssertEqual(try PitchSelectionStore.resolve(player: p), first)
        let fatigue = p.fatigue, revision = state.revision
        XCTAssertThrowsError(try PitchSelectionStore.select("slider", player: p, in: c, save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(p.lifecycleData, legacy); XCTAssertEqual(p.fatigue, fatigue); XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(try PitchSelectionStore.resolve(player: p), first)
        try PitchSelectionStore.select("slider", player: p, in: c)
        XCTAssertEqual(try PitchSelectionStore.resolve(player: p, available: [first]), first)
        XCTAssertThrowsError(try PitchSelectionStore.select("not-a-pitch", player: p, in: c))
        XCTAssertEqual(try PitchSelectionStore.resolve(player: p), "slider")
    }
    func testV94PracticeCopiesPreferenceWithoutWritingCareerSelection() throws {
        let db = try CareerStore.makeContainer(inMemory: true), c = db.mainContext
        var draft = PlayerDraft(); draft.name = "연습선수"; draft.schoolID = "hs-ref-001"; draft.role = .pitcher
        let p = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: c)
        let state = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id })
        try PitchSelectionStore.select("slider", player: p, in: c)
        let life = p.lifecycleData, revision = state.revision, fatigue = p.fatigue, date = p.gameDate
        let practiceDB = try CareerStore.makeContainer(inMemory: true), memory = practiceDB.mainContext
        let copy = try TrainingPractice.copy(p, from: c, into: memory)
        XCTAssertNotEqual(copy.id, p.id)
        XCTAssertEqual(try PitchSelectionStore.resolve(player: copy), "slider")
        try PitchSelectionStore.select("four-seam", player: copy, in: memory)
        XCTAssertEqual(try PitchSelectionStore.resolve(player: copy), "four-seam")
        XCTAssertEqual(p.lifecycleData, life); XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(p.fatigue, fatigue); XCTAssertEqual(p.gameDate, date)
    }
    func testV94PreferredSelectionDoesNotRewriteRunningTrainingOrMatch() throws {
        let db = try CareerStore.makeContainer(inMemory: true), c = db.mainContext
        let (p, state) = try setup(c, role: .pitcher)
        try PitchSelectionStore.select("slider", player: p, in: c)
        let row = try CareerTrainingStore.start(player: p, state: state, pitchCode: try PitchSelectionStore.resolve(player: p), in: c)
        let payload = row.payload, revision = row.revision
        try PitchSelectionStore.select("four-seam", player: p, in: c)
        XCTAssertEqual(row.payload, payload); XCTAssertEqual(row.revision, revision)
        XCTAssertEqual(try row.snapshot().pitchCode, "slider")
        let reopened = try CareerTrainingStore.start(player: p, state: state, pitchCode: "four-seam", in: c)
        XCTAssertEqual(reopened.payload, payload)
        for _ in 0..<5 { try attempt(p, state, row, c) }
        let reward = row.payload, fatigue = p.fatigue
        XCTAssertThrowsError(try attempt(p, state, row, c))
        XCTAssertEqual(row.payload, reward); XCTAssertEqual(p.fatigue, fatigue)
        let game = try CareerMatchStore.start(player: p, state: state, in: c)
        let before = game.payload
        try PitchSelectionStore.select("slider", player: p, in: c)
        XCTAssertEqual(game.payload, before)
        try CareerMatchStore.advance(player: p, state: state, record: game, revision: game.revision,
            input: .pitch, pitchCode: "slider", control: ManualMatchInput(release: 0.68), in: c)
        XCTAssertEqual(try game.snapshot().lastManual?.pitchCode, "slider")
    }

    private func attempt(_ player: CareerPlayer, _ calendar: CareerCalendarState, _ record: CareerTrainingRecord, _ context: ModelContext) throws {
        let training = try record.snapshot()
        guard !training.completed else { throw TrainingError.finished }
        let target = training.targets[training.scores.count]
        let input = player.role == .batter ? TrainingInput(x: target.x, y: target.y, timing: MatchDelivery.contactPhase) : TrainingInput(release: 0.68)
        try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: record.revision, input: input, in: context)
    }
    func testV43NewCareerTrainingMatchResumeAndNextDayBothRoles() throws {
        for role in PlayerRole.allCases {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("release-smoke.store")
            var playerID: UUID!, trainingBytes: Data!, matchBytes: Data!, frozenReports: [Data] = []
            try autoreleasepool {
                let db = try CareerStore.makeContainer(url: url), c = db.mainContext
                var draft = PlayerDraft(); draft.name = "출시검증"; draft.schoolID = "hs-ref-001"; draft.role = role
                let p = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: c)
                playerID = p.id
                let state = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let row = try CareerTrainingStore.start(player: p, state: state, pitchCode: role == .pitcher ? p.pitches.first?.code : nil, in: c)
                for _ in 0..<2 { try attempt(p, state, row, c) }
                trainingBytes = row.payload
                XCTAssertFalse(state.hasAction(on: p.gameDate))
            }
            try autoreleasepool {
                let db = try CareerStore.makeContainer(url: url), c = db.mainContext
                let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first { $0.id == playerID })
                let state = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let row = try CareerTrainingStore.start(player: p, state: state, pitchCode: role == .pitcher ? p.pitches.first?.code : nil, in: c)
                XCTAssertEqual(row.payload, trainingBytes)
                for _ in 0..<3 { try attempt(p, state, row, c) }
                XCTAssertTrue(row.completed); XCTAssertTrue(state.hasAction(on: p.gameDate))
                let fatigue = p.fatigue, result = row.payload
                XCTAssertThrowsError(try attempt(p, state, row, c))
                XCTAssertEqual(row.payload, result); XCTAssertEqual(p.fatigue, fatigue)
                let game = try CareerMatchStore.start(player: p, state: state, in: c)
                try CareerMatchStore.advance(player: p, state: state, record: game, revision: game.revision,
                    input: role == .batter ? .watch : .pitch, pitchCode: p.pitches.first?.code,
                    control: role == .batter ? nil : ManualMatchInput(release: 0.68), in: c)
                matchBytes = game.payload
                frozenReports = try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload)
                XCTAssertThrowsError(try CalendarProgression.advanceDay(player: p, state: state, revision: state.revision, in: c))
            }
            try autoreleasepool {
                let db = try CareerStore.makeContainer(url: url), c = db.mainContext
                let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first { $0.id == playerID })
                let state = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let game = try CareerMatchStore.start(player: p, state: state, in: c)
                XCTAssertEqual(game.payload, matchBytes)
                try CareerMatchStore.advance(player: p, state: state, record: game, revision: game.revision, input: .automatic, in: c)
                XCTAssertTrue(game.completed)
                let result = game.payload, fatigue = p.fatigue
                XCTAssertThrowsError(try CareerMatchStore.advance(player: p, state: state, record: game, revision: game.revision, input: .automatic, in: c))
                XCTAssertEqual(game.payload, result); XCTAssertEqual(p.fatigue, fatigue)
                let reports = try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload)
                XCTAssertTrue(frozenReports.allSatisfy { reports.contains($0) })
                let before = p.gameDate
                try CalendarProgression.advanceDay(player: p, state: state, revision: state.revision, in: c)
                XCTAssertEqual(p.gameDate, try GameDate(before).adding(days: 1).description)
                XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 1)
                XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerMatchRecord>()), 1)
            }
        }
    }

    func testV30LegacyReceiptNilAndNoProjectPracticeRemainCompatible() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,s)=try setup(c, date:"2026-04-02")
        let practice=try TrainingPractice.round(player:p,calendar:s,kind:.contact,code:"",in:c)
        XCTAssertNil(practice.projectFeedback)
        let row=try CareerTrainingStore.start(player:p,state:s,in:c)
        for _ in 0..<5 {try attempt(p,s,row,c)}
        var completed=try row.snapshot();XCTAssertNotNil(completed.projectFeedback);XCTAssertNil(completed.projectFeedback?.project)
        completed.projectFeedback=nil
        let legacy=try JSONEncoder().encode(completed);row.payload=legacy;try c.save()
        XCTAssertNil(try row.snapshot().projectFeedback);XCTAssertEqual(row.payload,legacy)
        var corrupt=completed
        corrupt.projectFeedback=TrainingProjectFeedback(version:1,activityKey:"wrong",project:nil,clubName:nil,before:nil,after:nil)
        row.payload=try JSONEncoder().encode(corrupt);XCTAssertThrowsError(try row.snapshot());c.rollback()
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
            let schools=try SchoolCatalog.load()
            var draft=PlayerDraft();draft.name="훈련선수";draft.schoolID=schools[0].id;draft.role = .pitcher
            let historical=CareerSchemaV1.Player(draft:draft,school:schools[0]);historical.fatigue=34;context.insert(historical)
            let player=CareerPlayer(draft:draft,school:schools[0]);player.id=historical.id
            let calendar=CareerCalendarState(player:player,schools:schools,legacySave:false);context.insert(calendar)
            calendar.actionDate = player.gameDate; calendar.revision = 1
            // Historical Player belongs to V3; the detached projection only supplies UUID-based record inputs.
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
        if training.isSkillDrill {
            switch training.selectedKind {
            case .power: return TrainingInput(drill: SkillDrillInput(phase: 0.5))
            case .velocity: return TrainingInput(drill: SkillDrillInput(beats: [0.65,1.35,2.05]))
            default: return TrainingInput(drill: SkillDrillInput(trace: SkillDrillRules.curve(target)))
            }
        }
        switch training.selectedKind {
        case .power: return TrainingInput(force: TrainingRules.powerTarget(training.scores.count) / 1.35, angle: 45)
        case .discipline: return TrainingInput(calledStrike: ManualMatchRules.isStrike(x: target.x, y: target.y))
        case .contact: return TrainingInput(x: target.x, y: target.y, timing: 0.82)
        case .pitch: return TrainingInput(release: 0.68)
        case .control: return TrainingInput(x: target.x, y: target.y)
        case .velocity, .stuff:
            let goal = RawTrainingRules.goal(kind: training.selectedKind, target: target)
            return TrainingInput(force: goal.force, angle: goal.angle)
        case .mental: return TrainingInput(choice: RawTrainingRules.question(targets: training.targets, round: training.scores.count).answer)
        case .stamina: return TrainingInput(footfalls: (0..<16).map { $0.isMultiple(of: 2) ? .left : .right })
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
            XCTAssertEqual(record.rulesVersion, kind == .power ? "native-skill-drills-v1" : "native-training-v2")
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

    private func seedPitchStudyProgress(_ player: CareerPlayer, code: String, replacing: String? = nil, in context: ModelContext) throws {
        var history = CareerTraining(playerID: player.id, date: "2026-03-31", role: "pitcher", pitchCode: code,
                                     before: 98, fatigue: player.fatigue, age: 16, calendarRevision: 0)
        history.pitchStudy = try PitchStudyStore.preparation(player: player, code: code, replacing: replacing, in: context)
        history.scores = [100,100,100,100,100]
        let record = try CareerTrainingRecord(history); record.completed = true
        context.insert(record); try context.save()
    }

    func testPitchStudyUsesFiveAttemptsDailyActionAndPreservesRegisteredSkillsUntilAcquired() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, state) = try setup(context, role: .pitcher, date: "2026-04-02")
        let original = try PitchStudyStore.roster(player), fatigue = player.fatigue
        XCTAssertThrowsError(try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context, save: { _ in throw Injected.failure }))
        XCTAssertNil(try CareerTrainingStore.record(player: player, in: context)); XCTAssertEqual(state.revision, 0)
        let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context)
        XCTAssertEqual(record.rulesVersion, "native-pitch-study-v1")
        XCTAssertEqual(try record.snapshot().controlMastery, 20)
        XCTAssertEqual(try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context).key, record.key)
        XCTAssertThrowsError(try PitchStudyStore.start(player: player, state: state, code: "curve", in: context))
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: state, pitchCode: "four-seam", in: context))
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context))
        XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context))
        let targets = try record.snapshot().targets, revision = state.revision
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision,
            input: TrainingInput(release: 0.68), in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try record.snapshot().scores, []); XCTAssertEqual(try record.snapshot().targets, targets)
        XCTAssertEqual(state.revision, revision); XCTAssertEqual(try PitchStudyStore.roster(player), original)
        for _ in 0..<4 { try attempt(player, state, record, context) }
        XCTAssertEqual(try PitchStudyStore.roster(player), original)
        XCTAssertEqual(try PitchStudyStore.progress(player: player, code: "cutter", in: context), 0)
        XCTAssertEqual(player.fatigue, fatigue); XCTAssertFalse(state.hasAction(on: player.gameDate))
        try attempt(player, state, record, context)
        let completed = try record.snapshot()
        XCTAssertEqual(completed.scores, [100,100,100,100,100])
        let expectedProgress = TrainingRules.traitGrowth(before: 0, score: 100, fatigue: fatigue, age: completed.age)
        XCTAssertEqual(completed.after, expectedProgress)
        XCTAssertEqual(try PitchStudyStore.progress(player: player, code: "cutter", in: context), expectedProgress)
        XCTAssertEqual(try PitchStudyStore.roster(player), original)
        XCTAssertEqual(player.fatigue, fatigue + 6); XCTAssertTrue(state.hasAction(on: player.gameDate))
        XCTAssertThrowsError(try attempt(player, state, record, context))
        XCTAssertEqual(player.fatigue, fatigue + 6)
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
        let next = try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context)
        XCTAssertEqual(try next.snapshot().before, expectedProgress)
        XCTAssertEqual(try next.snapshot().controlMastery, 20 + expectedProgress * 0.2, accuracy: 0.0001)
    }

    func testPitchStudyAcquisitionRegistersAtHundredAndNextGameUsesLearnedPitch() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, state) = try setup(context, role: .pitcher)
        let original = try PitchStudyStore.roster(player)
        try seedPitchStudyProgress(player, code: "cutter", in: context)
        let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context)
        XCTAssertEqual(try record.snapshot().before, TrainingRules.traitGrowth(before: 98, score: 100, fatigue: player.fatigue, age: 16))
        for _ in 0..<4 { try attempt(player, state, record, context) }
        XCTAssertEqual(try PitchStudyStore.roster(player), original)
        let revision = record.revision
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: revision,
            input: TrainingInput(release: 0.68), in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try PitchStudyStore.roster(player), original)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPitchMastery>()), original.count)
        XCTAssertEqual(record.revision, revision); XCTAssertFalse(record.completed)
        try attempt(player, state, record, context)
        XCTAssertEqual(try record.snapshot().after, 100)
        XCTAssertEqual(player.pitches.count, original.count + 1)
        XCTAssertEqual(player.pitches.first { $0.code == "cutter" }?.mastery, 20)
        for pitch in original { XCTAssertEqual(player.pitches.first { $0.code == pitch.code }?.mastery, pitch.mastery) }
        let game = try CareerMatchStore.start(player: player, state: state, in: context).snapshot()
        XCTAssertEqual(game.mastery["cutter"], 20)
        XCTAssertThrowsError(try attempt(player, state, record, context))
        XCTAssertEqual(player.pitches.filter { $0.code == "cutter" }.count, 1)
    }

    func testPitchStudyReplacementArchivesSkillAndReregistrationRestoresOriginalMastery() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, state) = try setup(context, role: .pitcher, date: "2026-04-02")
        let extra = CareerPitchMastery(code: "curve", name: "커브", mastery: 61.75, order: 4)
        context.insert(extra); player.pitches.append(extra); try context.save()
        let original = try PitchStudyStore.roster(player)
        let old = try XCTUnwrap(player.pitches.first { $0.code == "four-seam" }), oldID = old.persistentModelID
        let oldMastery = old.mastery
        XCTAssertThrowsError(try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context))
        try seedPitchStudyProgress(player, code: "cutter", replacing: "four-seam", in: context)
        let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", replacing: "four-seam", in: context)
        for _ in 0..<4 { try attempt(player, state, record, context) }
        XCTAssertEqual(try PitchStudyStore.roster(player), original)
        try attempt(player, state, record, context)
        XCTAssertEqual(player.pitches.count, 5)
        XCTAssertEqual(player.pitches.first { $0.code == "cutter" }?.persistentModelID, oldID)
        XCTAssertEqual(try PitchStudyStore.archived(player: player, in: context), [try XCTUnwrap(original.first { $0.code == "four-seam" })])
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
        let restore = try PitchStudyStore.start(player: player, state: state, code: "four-seam", replacing: "cutter", in: context)
        XCTAssertEqual(try restore.snapshot().before, 100)
        XCTAssertEqual(try restore.snapshot().controlMastery, oldMastery)
        XCTAssertEqual(try restore.snapshot().pitchStudy?.restoredMastery, oldMastery)
        for _ in 0..<5 { try attempt(player, state, restore, context) }
        XCTAssertEqual(player.pitches.first { $0.code == "four-seam" }?.mastery, oldMastery)
        XCTAssertEqual(player.pitches.first { $0.code == "four-seam" }?.persistentModelID, oldID)
        XCTAssertEqual(try PitchStudyStore.archived(player: player, in: context).map(\.code), ["cutter"])
        XCTAssertEqual(try PitchStudyStore.archived(player: player, in: context).first?.mastery, 20)
        XCTAssertThrowsError(try attempt(player, state, restore, context))
        XCTAssertEqual(player.pitches.count, 5)
    }

    func testPitchStudyDiskResumeFinalSaveFailureAndCompletedReopenPreserveOneRegistration() throws {
        enum Injected: Error { case failure }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pitch-study.store")
        let snapshot = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let (player, state) = try setup(context, role: .pitcher, date: "2026-04-02")
            try seedPitchStudyProgress(player, code: "cutter", replacing: "slider", in: context)
            let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", replacing: "slider", in: context)
            for _ in 0..<2 { try attempt(player, state, record, context) }
            return try record.snapshot()
        }
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
            let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", replacing: "slider", in: context)
            XCTAssertEqual(try record.snapshot(), snapshot)
            let roster = try PitchStudyStore.roster(player)
            for _ in 0..<2 { try attempt(player, state, record, context) }
            let payload = record.payload, revision = record.revision, calendarRevision = state.revision
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: revision,
                input: TrainingInput(release: 0.68), in: context, save: { _ in throw Injected.failure }))
            XCTAssertEqual(record.payload, payload); XCTAssertEqual(record.revision, revision)
            XCTAssertEqual(state.revision, calendarRevision); XCTAssertNil(state.actionDate)
            XCTAssertEqual(try PitchStudyStore.roster(player), roster); XCTAssertEqual(player.fatigue, snapshot.fatigue)
            XCTAssertTrue(try PitchStudyStore.archived(player: player, in: context).isEmpty)
            try attempt(player, state, record, context)
            XCTAssertEqual(try PitchStudyStore.archived(player: player, in: context).map(\.code), ["slider"])
        }
        let container = try CareerStore.makeContainer(url: url), context = container.mainContext
        let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", replacing: "slider", in: context)
        XCTAssertTrue(record.completed); XCTAssertEqual(try record.snapshot().after, 100)
        XCTAssertEqual(player.pitches.count, 4); XCTAssertEqual(player.pitches.first { $0.code == "cutter" }?.mastery, 20)
        XCTAssertEqual(player.fatigue, snapshot.fatigue + TrainingRules.fatigueCost); XCTAssertTrue(state.hasAction(on: player.gameDate))
        XCTAssertThrowsError(try attempt(player, state, record, context))
        XCTAssertEqual(player.fatigue, snapshot.fatigue + TrainingRules.fatigueCost)
        XCTAssertEqual(try PitchStudyStore.archived(player: player, in: context).first?.mastery, 65)
    }

    func testPitchStudyPreservesLegacyRosterAndTrainingAndRejectsStaleRoster() throws {
        for count in [2, 6] {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, state) = try setup(context, role: .pitcher)
            if count == 2 { player.pitches = Array(player.pitches.sorted { $0.order < $1.order }.prefix(2)) }
            else {
                for (offset, code) in ["curve", "two-seam"].enumerated() {
                    let pitch = CareerPitchMastery(code: code, name: code, mastery: 44.1234, order: offset + 4)
                    context.insert(pitch); player.pitches.append(pitch)
                }
            }
            try context.save()
            let roster = try PitchStudyStore.roster(player)
            if count > 5 { XCTAssertThrowsError(try PitchStudyStore.start(player: player, state: state, code: "cutter", in: context)) }
            let record = try PitchStudyStore.start(player: player, state: state, code: "cutter", replacing: count > 5 ? "slider" : nil, in: context)
            XCTAssertEqual(try PitchStudyStore.roster(player), roster)
            player.pitches[0].mastery += 0.1; try context.save()
            XCTAssertThrowsError(try attempt(player, state, record, context))
            XCTAssertEqual(record.revision, 0); XCTAssertEqual(player.pitches.count, count)
        }
        var legacy = CareerTraining(playerID: UUID(), date: "2026-04-01", role: "pitcher", pitchCode: "four-seam", before: 91.1234, fatigue: 24, age: 16, calendarRevision: 1)
        legacy.scores = [27,100]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "pitchStudy")
        let restored = try JSONDecoder().decode(CareerTraining.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.pitchStudy); XCTAssertEqual(restored.before, 91.1234); XCTAssertEqual(restored.scores, [27,100])
        XCTAssertEqual(restored.controlMastery, 91.1234)
    }
}

extension CareerTrainingTests {
    private func v38Fixture(_ role:PlayerRole = .batter,url:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let db=try CareerStore.makeContainer(url:url,inMemory:url == nil),c=db.mainContext
        var draft=PlayerDraft();draft.name="Growth38";draft.schoolID="hs-ref-001";draft.role=role;draft.position = .shortstop
        let p=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:c),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        var life=try p.lifecycle;life.development=PlayerDevelopment(adopted:p.gameDate,timing:.early);p.lifecycleData=try JSONEncoder().encode(life);p.fatigue=24;try c.save()
        return(db,p,s)
    }
    private func v38Attempt(_ p:CareerPlayer,_ s:CareerCalendarState,_ row:CareerTrainingRecord,_ c:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        let t=try row.snapshot(),target=t.targets[min(t.scores.count,t.targets.count-1)]
        try CareerTrainingStore.attempt(player:p,state:s,record:row,revision:row.revision,input:TrainingInput(x:target.x,y:target.y),in:c,save:save)
    }
    func testV38GrowthPolicyKeepsLegacyAndHighschoolBaseButSlowsHighRatings() throws {
        XCTAssertEqual(DevelopmentRules.growth(before:40,score:75,fatigue:24,age:16,pitch:false,timing:.balanced),TrainingRules.growth(before:40,score:75,fatigue:24,age:16,pitch:false))
        for value in [72.0,82,92,98] {
            XCTAssertLessThan(DevelopmentRules.growth(before:value,score:90,fatigue:24,age:16,pitch:false,timing:.balanced),TrainingRules.growth(before:value,score:90,fatigue:24,age:16,pitch:false))
        }
        XCTAssertGreaterThan(DevelopmentTiming.early.factor(age:17),DevelopmentTiming.late.factor(age:17))
        XCTAssertLessThan(DevelopmentTiming.early.factor(age:22),DevelopmentTiming.late.factor(age:22))
        XCTAssertEqual(TrainingRules.growth(before:65,score:100,fatigue:24,age:16,pitch:false),65.2028)
        var t=CareerTraining(playerID:UUID(),date:"2026-04-01",role:"batter",pitchCode:nil,before:82,fatigue:24,age:16,calendarRevision:1,kind:.defense)
        t.scores=[100,100,100,100,100];let original=t.after
        let old=try JSONEncoder().encode(t);XCTAssertEqual(try JSONDecoder().decode(CareerTraining.self,from:old).after,original)
        t.growthPolicy=TrainingGrowthPolicy(timing:.balanced,windowID:nil,bonusLimit:0)
        XCTAssertLessThan(t.after,original);XCTAssertEqual(try JSONDecoder().decode(CareerTraining.self,from:old).after,original)
    }
    func testV38TimingIsFixedAndLegacyAdoptionPreservesStateAndPendingTraining() throws {
        let (db,p,s)=try v38Fixture(),c=db.mainContext
        let a=PlayerDevelopment.initial(playerID:p.id,date:p.gameDate),b=PlayerDevelopment.initial(playerID:p.id,date:p.gameDate);XCTAssertEqual(a,b)
        var life=try p.lifecycle;life.development=nil;p.lifecycleData=try JSONEncoder().encode(life);try c.save()
        let row=try CareerTrainingStore.start(player:p,state:s,kind:.defense,in:c)
        XCTAssertNil(try row.snapshot().growthPolicy)
        XCTAssertThrowsError(try DevelopmentStore.adopt(player:p,calendar:s,in:c))
        for _ in 0..<5 {try v38Attempt(p,s,row,c)}
        let bytes=row.payload,before=[p.contact,p.defense,Double(p.fatigue)],date=p.gameDate,action=s.actionDate
        XCTAssertThrowsError(try DevelopmentStore.adopt(player:p,calendar:s,in:c,save:{_ in throw CalendarError.staleState}))
        XCTAssertNil(try p.lifecycle.development)
        try DevelopmentStore.adopt(player:p,calendar:s,in:c)
        XCTAssertEqual(try p.lifecycle.development?.timing,.balanced);XCTAssertEqual(row.payload,bytes)
        XCTAssertEqual([p.contact,p.defense,Double(p.fatigue)],before);XCTAssertEqual(p.gameDate,date);XCTAssertEqual(s.actionDate,action)
        let revision=s.revision;try DevelopmentStore.adopt(player:p,calendar:s,in:c,save:{_ in XCTFail("duplicate adoption")});XCTAssertEqual(s.revision,revision)
    }
    func testV38CompletedTrainingProofAndGrowthShareRollbackAndPayOnceBothRoles() throws {
        for role in PlayerRole.allCases {
            let (db,p,s)=try v38Fixture(role),c=db.mainContext,kind:TrainingKind=role == .batter ? .defense:.control
            let row=try CareerTrainingStore.start(player:p,state:s,kind:kind,in:c)
            for _ in 0..<4 {try v38Attempt(p,s,row,c)}
            let bytes=row.payload,life=p.lifecycleData,before=try CareerTrainingStore.value(player:p,code:nil,kind:kind,in:c),fatigue=p.fatigue,revision=s.revision
            XCTAssertThrowsError(try v38Attempt(p,s,row,c,save:{_ in throw TrainingError.stale}))
            XCTAssertEqual(row.payload,bytes);XCTAssertEqual(p.lifecycleData,life);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            XCTAssertEqual(try CareerTrainingStore.value(player:p,code:nil,kind:kind,in:c),before)
            try v38Attempt(p,s,row,c)
            XCTAssertEqual(try p.lifecycle.development?.proofs[kind.rawValue]?.count,1)
            let final=row.payload,finalLife=p.lifecycleData
            XCTAssertThrowsError(try v38Attempt(p,s,row,c));XCTAssertEqual(row.payload,final);XCTAssertEqual(p.lifecycleData,finalLife)
            XCTAssertEqual(try row.snapshot().growthPolicy?.version,2)
        }
    }
    func testV38WindowDiskResumePracticeIsolationAndBudgetDoNotReroll() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("career.store");var id:UUID!,pending:Data!,savedLife:Data!
        try autoreleasepool {
            let (db,p,s)=try v38Fixture(.pitcher,url:url),c=db.mainContext;id=p.id;p.fatigue=24;try c.save()
            for i in 0..<8 {
                p.gameDate=try GameDate("2026-04-01").adding(days:i*2).description;s.actionDate=nil;p.fatigue=24;try c.save()
                let row=try CareerTrainingStore.start(player:p,state:s,kind:.control,in:c)
                for _ in 0..<5 {try v38Attempt(p,s,row,c)}
            }
            let window=try XCTUnwrap(p.lifecycle.development?.windows.last);XCTAssertEqual(window.used,0);XCTAssertEqual(window.sources.count,8)
            p.gameDate="2026-04-17";s.actionDate=nil;p.fatigue=24;try c.save()
            let row=try CareerTrainingStore.start(player:p,state:s,kind:.control,in:c);XCTAssertNotNil(try row.snapshot().growthPolicy?.windowID)
            for _ in 0..<2 {try v38Attempt(p,s,row,c)};pending=row.payload;savedLife=p.lifecycleData
            let fatigue=p.fatigue,revision=s.revision
            var practice=try TrainingPractice.round(player:p,calendar:s,kind:.control,code:"",in:c)
            for _ in 0..<5 {let target=practice.targets[practice.scores.count];try practice.attempt(TrainingInput(x:target.x,y:target.y))}
            XCTAssertNil(practice.growthPolicy);XCTAssertEqual(p.lifecycleData,savedLife);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
        }
        let db=try CareerStore.makeContainer(url:url),c=db.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id==id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID==id}),row=try XCTUnwrap(CareerTrainingStore.record(player:p,in:c))
        XCTAssertEqual(row.payload,pending);XCTAssertEqual(p.lifecycleData,savedLife)
        for _ in 0..<2 {try v38Attempt(p,s,row,c)}
        XCTAssertThrowsError(try v38Attempt(p,s,row,c,save:{_ in throw TrainingError.stale}));XCTAssertEqual(try row.snapshot().scores.count,4)
        try v38Attempt(p,s,row,c)
        let window=try XCTUnwrap(p.lifecycle.development?.windows.last);XCTAssertEqual(window.used,1);XCTAssertGreaterThan(window.spent,0);XCTAssertLessThanOrEqual(window.spent,0.6)
        let bytes=row.payload,life=p.lifecycleData;XCTAssertThrowsError(try v38Attempt(p,s,row,c));XCTAssertEqual(row.payload,bytes);XCTAssertEqual(p.lifecycleData,life)
        XCTAssertEqual(try p.lifecycle.development?.windows.count,1)
    }
    func testV38AgingSeparatesAbilitiesAndDoesNotRewriteLegacyEvents() throws {
        XCTAssertEqual(DevelopmentRules.loss(.speed,age:27),0.35);XCTAssertEqual(DevelopmentRules.loss(.control,age:27),0)
        XCTAssertEqual(DevelopmentRules.loss(.power,age:29),0.2);XCTAssertEqual(DevelopmentRules.loss(.discipline,age:33),0)
        XCTAssertEqual(DevelopmentRules.loss(.control,age:34),0.12);XCTAssertEqual(DevelopmentRules.loss(.mental,age:40),0)
        let (db,p,s)=try v38Fixture(),c=db.mainContext
        p.gameDate="2029-04-01";try CareerPathStore.synchronize(player:p,calendar:s,in:c)
        p.gameDate="2037-03-31";try CareerPathStore.synchronize(player:p,calendar:s,in:c);try c.save();let old=p.lifecycleData,speed=p.speed
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,confirmAnniversary:true,in:c,save:{_ in throw TrainingError.stale}))
        XCTAssertEqual(p.lifecycleData,old);XCTAssertEqual(p.speed,speed)
        try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,confirmAnniversary:true,in:c)
        let event=try XCTUnwrap(p.lifecycle.aging.last);XCTAssertTrue(event.id.contains("aging-v2"));XCTAssertEqual(p.speed,TrainingRules.round(speed-0.35));XCTAssertEqual(event.age,27)
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let frozen=try encoder.encode(event);var life=try p.lifecycle;life.development=nil;life.aging=[];try life.validate(playerID:p.id,today:p.gameDate)
        XCTAssertEqual(try encoder.encode(event),frozen)
    }
    func testV38PositionSwitchPreservesMasteriesCostsOneActionAndLocksPending() throws {
        let (db,p,s)=try v38Fixture(),c=db.mainContext,profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        var value=try profile.snapshot();value.skills[FieldPosition.center.rawValue]=PositionSkill(mastery:40,xp:30);profile.payload=try JSONEncoder().encode(value);try c.save()
        let bytes=profile.payload,stats=[p.contact,p.power,p.speed,p.defense,p.arm],life=p.lifecycleData,position=p.positionRaw,fatigue=p.fatigue
        XCTAssertThrowsError(try DevelopmentStore.changePosition(player:p,calendar:s,to:.center,date:p.gameDate,revision:s.revision,in:c,save:{_ in throw TrainingError.stale}))
        XCTAssertEqual(p.positionRaw,position);XCTAssertEqual(p.lifecycleData,life);XCTAssertEqual(profile.payload,bytes)
        try DevelopmentStore.changePosition(player:p,calendar:s,to:.center,date:p.gameDate,revision:s.revision,in:c)
        XCTAssertEqual(p.positionRaw,"CF");XCTAssertEqual(profile.payload,bytes);XCTAssertEqual([p.contact,p.power,p.speed,p.defense,p.arm],stats);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.actionDate,p.gameDate)
        let adopted=try XCTUnwrap(p.lifecycle.development);XCTAssertEqual(adopted.positions.count,1);XCTAssertTrue(adopted.windows.isEmpty)
        let game=try CareerMatchStore.start(player:p,state:s,in:c)
        XCTAssertEqual(try game.snapshot().fieldStats?.position,"CF");XCTAssertEqual(try game.snapshot().fieldStats?.positionMastery,40)
        try CareerMatchStore.advance(player:p,state:s,record:game,revision:game.revision,input:.automatic,in:c)
        let frozen=game.payload
        p.gameDate="2026-04-02";s.actionDate=nil;try c.save()
        XCTAssertNotNil(try DevelopmentStore.switchReason(player:p,calendar:s,to:FieldPosition(rawValue:position)!,in:c))
        let row=try CareerTrainingStore.start(player:p,state:s,position:.center,in:c);let pending=row.payload
        XCTAssertThrowsError(try DevelopmentStore.changePosition(player:p,calendar:s,to:.first,date:p.gameDate,revision:s.revision,in:c));XCTAssertEqual(row.payload,pending);XCTAssertEqual(game.payload,frozen)
    }
}

extension CareerTrainingTests {
    func testV38WindowIsBoundedByEightSetsTwentyEightDaysYearAndExtraBudget() throws {
        let id=UUID(),date="2026-04-15",key=CareerTrainingRecord.key(id,date)
        let sources=try (0..<8).map {i in let d=try GameDate("2026-04-01").adding(days:i*2).description;return DevelopmentProof(key:CareerTrainingRecord.key(id,d),date:d)}
        var d=PlayerDevelopment(adopted:"2026-04-01",timing:.early)
        d.windows=[DevelopmentWindow(id:key+"/growth-window-v2",kind:.control,opened:date,expires:"2026-05-12",sources:sources)]
        for i in 0..<8 {
            let date=try GameDate("2026-04-16").adding(days:i).description
            var t=CareerTraining(playerID:id,date:date,role:"pitcher",pitchCode:nil,before:20,fatigue:24,age:16,calendarRevision:1,kind:.control)
            t.growthPolicy=d.policy(kind:.control,on:date);t.scores=[100,100,100,100,100]
            try d.complete(t,key:CareerTrainingRecord.key(id,date))
        }
        XCTAssertEqual(d.windows.count,1);XCTAssertLessThanOrEqual(d.windows[0].used,8);XCTAssertEqual(d.windows[0].spent,0.6,accuracy:0.0001)
        XCTAssertNil(d.active(on:"2026-04-24"));XCTAssertNil(d.policy(kind:.control,on:"2026-04-24").windowID)
        let window=DevelopmentWindow(id:key+"/growth-window-v2",kind:.control,opened:date,expires:"2026-05-12",sources:sources)
        XCTAssertTrue(window.available(on:"2026-05-12"));XCTAssertFalse(window.available(on:"2026-05-13"))
        var exhausted=window;exhausted.used=8;XCTAssertFalse(exhausted.available(on:"2026-04-16"))
        var expired=d;expired.windows=[window];XCTAssertNil(expired.policy(kind:.power,on:"2026-04-16").windowID)
        expired.windows.append(window);XCTAssertThrowsError(try expired.validate(playerID:id,today:"2026-05-13"))
    }
}

extension CareerTrainingTests {
    func testV38PitchBreakthroughStaysWithPreparedPitchNotOtherMasteries() throws {
        let id=UUID(),date="2026-04-15",key=CareerTrainingRecord.key(id,date)
        let sources=try (0..<8).map {i in let d=try GameDate("2026-04-01").adding(days:i*2).description;return DevelopmentProof(key:CareerTrainingRecord.key(id,d),date:d)}
        var d=PlayerDevelopment(adopted:"2026-04-01",timing:.early)
        d.windows=[DevelopmentWindow(id:key+"/growth-window-v2",kind:.pitch,pitchCode:"slider",opened:date,expires:"2026-05-12",sources:sources)]
        try d.validate(playerID:id,today:date)
        XCTAssertNotNil(d.policy(kind:.pitch,code:"slider",on:date).windowID)
        XCTAssertNil(d.policy(kind:.pitch,code:"four-seam",on:date).windowID)
        XCTAssertNil(d.policy(kind:.control,on:date).windowID)
        var wrong=CareerTraining(playerID:id,date:"2026-04-16",role:"pitcher",pitchCode:"four-seam",before:40,fatigue:24,age:16,calendarRevision:1)
        wrong.growthPolicy=d.policy(kind:.pitch,code:"slider",on:date);wrong.scores=[100,100,100,100,100]
        XCTAssertThrowsError(try d.complete(wrong,key:CareerTrainingRecord.key(id,wrong.date)))
        XCTAssertEqual(d.windows[0].used,0)
    }
}
