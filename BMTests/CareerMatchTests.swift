import XCTest
import SwiftData
@testable import BM

@MainActor final class CareerMatchTests: XCTestCase {
    private func setup(role: PlayerRole = .batter, date: String = "2026-04-01", in context: ModelContext) throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = role == .batter ? "경기타자" : "경기투수"
        draft.schoolID = "hs-ref-001"; draft.role = role; draft.throwingHand = .left
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        player.gameDate = date
        try context.save()
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        return (player, state)
    }
    private func ready(_ player: CareerPlayer, _ state: CareerCalendarState, in context: ModelContext) throws -> CareerMatchRecord {
        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
        return try CareerMatchStore.start(player: player, state: state, in: context)
    }

    func testBothRolesCompleteOnceAndUnlockOnlyCompletedGameDay() throws {
        for role in PlayerRole.allCases {
            let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
            let (player, state) = try setup(role: role, in: context)
            XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context))
            let saved = try ready(player, state, in: context)
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context))
            XCTAssertEqual(try CareerMatchStore.start(player: player, state: state, in: context).key, saved.key)
            let initial = player.fatigue
            try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context)
            let final = try saved.snapshot()
            XCTAssertTrue(saved.completed); XCTAssertTrue(final.completed)
            XCTAssertEqual(player.fatigue, min(100, initial + final.appliedFatigueCost))
            XCTAssertEqual(saved.fatigueAfter, player.fatigue)
            if role == .batter { XCTAssertGreaterThan(final.line.atBats, 0); XCTAssertEqual(final.line.pitches, 0) }
            else { XCTAssertGreaterThan(final.line.pitches, 0); XCTAssertGreaterThan(final.line.pitchingOuts, 0); XCTAssertEqual(final.line.atBats, 0) }
            let before = (player.fatigue, state.revision, saved.payload)
            for revision in [0, saved.revision] {
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: revision, input: .automatic, in: context))
            }
            XCTAssertEqual(player.fatigue, before.0); XCTAssertEqual(state.revision, before.1); XCTAssertEqual(saved.payload, before.2)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()), 1)
            try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
            XCTAssertEqual(player.gameDate, "2026-04-02"); XCTAssertEqual(player.fatigue, max(0, before.0 - 4))
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: before.1, in: context))
        }
    }

    func testNonStartTeamGameHasNoPersonalCostOrStats() throws {
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, state) = try setup(role: .pitcher, date: "2026-04-07", in: context)
        let saved = try ready(player, state, in: context); let fatigue = player.fatigue
        XCTAssertFalse(saved.appearance)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .pitch, pitchCode: "four-seam", in: context))
        try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context)
        XCTAssertEqual(try saved.snapshot().line, MatchLine()); XCTAssertEqual(player.fatigue, fatigue)
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
        XCTAssertEqual(player.gameDate, "2026-04-08")
    }

    func testInvalidRolePitchRevisionAndFixtureDoNotChangeState() throws {
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, state) = try setup(role: .pitcher, in: context)
        let saved = try ready(player, state, in: context); let payload = saved.payload
        for (input, code, revision) in [(MatchInput.pitch, "unknown", 0), (.swing, "four-seam", 0), (.pitch, "four-seam", 10)] {
            XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: revision, input: input, pitchCode: code, in: context))
        }
        let (other, otherState) = try setup(in: context)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: other, state: otherState, record: saved, revision: 0, input: .automatic, in: context))
        XCTAssertEqual(saved.payload, payload); XCTAssertEqual(saved.revision, 0)
        player.gameDate = "2026-04-02"; try context.save()
        XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context))
    }

    func testFailedStartAndCompletionRollbackThenRetryOnce() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, state) = try setup(in: context)
        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
        let revision = state.revision
        XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()), 0); XCTAssertEqual(state.revision, revision)
        let saved = try CareerMatchStore.start(player: player, state: state, in: context)
        let before = try saved.snapshot(); let fatigue = player.fatigue; let startRevision = state.revision
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try saved.snapshot(), before); XCTAssertEqual(saved.revision, 0); XCTAssertFalse(saved.completed)
        XCTAssertEqual(player.fatigue, fatigue); XCTAssertEqual(state.revision, startRevision)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context))
        var expected = before; try expected.advance(.automatic)
        try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context)
        XCTAssertEqual(try saved.snapshot(), expected); XCTAssertTrue(saved.completed)
    }

    func testPartialGameDiskReopenResumesSameRNGAndKeepsOtherRole() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("match.store")
        let expected: CareerMatch = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url); let context = container.mainContext
            let (player, state) = try setup(in: context)
            _ = try setup(role: .pitcher, in: context)
            let saved = try ready(player, state, in: context)
            try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .watch, in: context)
            let snapshot = try saved.snapshot(); XCTAssertFalse(snapshot.completed)
            return snapshot
        }
        let reopened = try CareerStore.makeContainer(url: url); let context = reopened.mainContext
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        let batter = try XCTUnwrap(players.first { $0.role == .batter })
        let pitcher = try XCTUnwrap(players.first { $0.role == .pitcher })
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == batter.id })
        let saved = try CareerMatchStore.start(player: batter, state: state, in: context)
        XCTAssertEqual(try saved.snapshot(), expected)
        var next = expected; try next.advance(.automatic)
        try CareerMatchStore.advance(player: batter, state: state, record: saved, revision: saved.revision, input: .automatic, in: context)
        XCTAssertEqual(try saved.snapshot(), next)
        XCTAssertEqual(pitcher.fatigue, 52); XCTAssertEqual(pitcher.gameDate, "2026-04-01")
        XCTAssertEqual(pitcher.pitches.sorted { $0.order < $1.order }.map(\.mastery), [72,65,48,35])
        let second = ModelContext(reopened)
        XCTAssertTrue(try XCTUnwrap(second.fetch(FetchDescriptor<CareerMatchRecord>()).first).completed)
    }

    func testPitchCostRoundingUsesFourDigitPrecisionBeforeIntegerStorage() {
        var match = CareerMatch(random: 1, isHome: true, role: "pitcher", appearance: true,
                                contact: 65, power: 75, discipline: 60, mastery: ["four-seam": 72])
        match.fatigueCost = 19.00000000000001
        XCTAssertEqual(match.appliedFatigueCost, 19)
        match.fatigueCost = 19.38
        XCTAssertEqual(match.appliedFatigueCost, 20)
    }

    func testDirectAndAutomaticUseIdenticalEngineAndValidBaseballTotals() throws {
        for seed in 0..<100 {
            for home in [true, false] {
                for role in PlayerRole.allCases {
                    var direct = CareerMatch(random: UInt64(seed), isHome: home, role: role.rawValue,
                                             appearance: true, contact: 65, power: 75, discipline: 60,
                                             mastery: role == .pitcher ? ["four-seam": 72] : [:])
                    direct.settle()
                    var automatic = direct
                    try automatic.advance(.automatic)
                    var inputs = 0
                    while !direct.completed && inputs < 1000 {
                        try direct.advance(role == .batter ? .swing : .pitch, pitchCode: "four-seam")
                        inputs += 1
                    }
                    XCTAssertTrue(direct.completed); XCTAssertEqual(direct, automatic)
                    XCTAssertTrue((17...18).contains(direct.half))
                    if direct.half == 17 { XCTAssertGreaterThan(direct.homeScore, direct.awayScore) }
                    XCTAssertEqual(direct.line.plateAppearances, direct.line.atBats + direct.line.walks)
                    XCTAssertLessThanOrEqual(direct.line.homeRuns, direct.line.hits)
                    XCTAssertLessThanOrEqual(direct.line.hits, direct.line.atBats)
                    if role == .pitcher {
                        XCTAssertTrue([24, 25, 26, 27].contains(direct.line.pitchingOuts))
                        XCTAssertEqual(direct.line.runsAllowed, direct.opponentScore)
                    }
                    XCTAssertThrowsError(try direct.advance(.automatic))
                }
            }
        }
    }

    func testV2DiskMigrationPreservesCalendarActionsAndCreatesNoFakeGames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v2.store")
        let schools = try SchoolCatalog.load()
        let ids: [UUID] = try autoreleasepool {
            let schema = Schema(versionedSchema: CareerSchemaV2.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            var ids: [UUID] = []
            for role in PlayerRole.allCases {
                var draft = PlayerDraft(); draft.name = "기존선수"; draft.schoolID = schools[0].id; draft.role = role
                let player = CareerPlayer(draft: draft, school: schools[0]); player.gameDate = "2027-04-01"; player.speed = 72.125; player.fatigue = 37
                let state = CareerCalendarState(player: player, schools: schools, legacySave: true)
                state.actionDate = player.gameDate; state.revision = 8
                old.mainContext.insert(player); old.mainContext.insert(state); ids.append(player.id)
            }
            try old.mainContext.save(); return ids
        }
        let current = try CareerStore.makeContainer(url: url); let context = current.mainContext
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<CareerPlayer>()).map(\.id)), Set(ids))
        for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
            XCTAssertEqual(player.gameDate, "2027-04-01"); XCTAssertEqual(player.speed, 72.125); XCTAssertEqual(player.fatigue, 37)
        }
        for state in try context.fetch(FetchDescriptor<CareerCalendarState>()) {
            XCTAssertEqual(state.revision, 8); XCTAssertEqual(state.actionDate, "2027-04-01"); XCTAssertTrue(state.legacySave)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()), 0)
    }
}
