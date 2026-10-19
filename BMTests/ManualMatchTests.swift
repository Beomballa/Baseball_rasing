import XCTest
import SwiftData
@testable import BM

@MainActor final class ManualMatchTests: XCTestCase {
    private func match(role: PlayerRole = .batter, seed: UInt64 = 42, mastery: Double = 72) -> CareerMatch {
        var match = CareerMatch(random: seed, isHome: role == .batter, role: role.rawValue,
                                appearance: true, contact: 65, power: 75, discipline: 60,
                                mastery: role == .pitcher ? ["four-seam": mastery] : [:])
        match.half = role == .batter ? 1 : 0
        match.controlVersion = 2
        return match
    }
    private func fixture(in context: ModelContext, role: PlayerRole = .batter) throws -> (CareerPlayer, CareerCalendarState, CareerMatchRecord) {
        var draft = PlayerDraft(); draft.name = "직접조작"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
        let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
        return (player, calendar, record)
    }

    func testDeliveryPreviewDoesNotConsumeRNGAndSpeedChangesFlightTime() throws {
        let state = match(role: .pitcher)
        XCTAssertEqual(state.delivery(pitchCode: "four-seam"), state.delivery(pitchCode: "four-seam"))
        XCTAssertEqual(state.random, 42)
        XCTAssertLessThan(state.delivery(pitchCode: "four-seam").duration, state.delivery(pitchCode: "changeup").duration)
        let decoded = try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.delivery(), state.delivery())
    }

    func testAimAndTimingMissesCannotBecomeHitsAndPerfectInputRaisesQuality() throws {
        let original = match(); let delivery = original.delivery()
        var centered = original
        try centered.advance(.swing, control: ManualMatchInput(x: delivery.x, y: delivery.y, timing: MatchDelivery.contactPhase))
        XCTAssertEqual(centered.lastManual?.quality, 1); XCTAssertEqual(centered.lastManual?.grade, "정타")
        for seed in 0..<100 {
            var state = match(seed: UInt64(seed)); let target = state.delivery()
            try state.advance(.swing, control: ManualMatchInput(x: target.x, y: target.y, timing: 0.82))
            XCTAssertEqual(state.lastManual?.grade, "정타")
            XCTAssertTrue(["안타", "홈런", "범타"].contains(state.lastManual?.outcome ?? ""))
        }
        for control in [ManualMatchInput(x: delivery.x, y: delivery.y, timing: 0),
                        ManualMatchInput(x: delivery.x < 0.5 ? 1 : 0, y: delivery.y, timing: MatchDelivery.contactPhase)] {
            var missed = original
            try missed.advance(.swing, control: control)
            XCTAssertEqual(missed.lastManual?.quality, 0); XCTAssertEqual(missed.lastManual?.grade, "헛스윙")
            XCTAssertEqual(missed.line.hits, 0); XCTAssertEqual(missed.line.homeRuns, 0)
            XCTAssertEqual(missed.fatigueCost, 1)
        }
    }

    func testNoInputIsIdenticalToWatchingAndUsesActualZoneWithoutFatigue() throws {
        var sawBall = false, sawStrike = false
        for seed in 0..<100 {
            var noInput = match(seed: UInt64(seed)), watched = noInput
            let delivery = noInput.delivery()
            try noInput.advance(.swing, control: ManualMatchInput())
            try watched.advance(.watch, control: ManualMatchInput())
            XCTAssertEqual(noInput, watched); XCTAssertEqual(noInput.fatigueCost, 0)
            XCTAssertEqual(noInput.lastManual?.action, "watch")
            if ManualMatchRules.isStrike(x: delivery.x, y: delivery.y) {
                XCTAssertEqual(noInput.strikes, 1); sawStrike = true
            } else { XCTAssertEqual(noInput.balls, 1); sawBall = true }
        }
        XCTAssertTrue(sawBall && sawStrike)
    }

    func testReleaseMasteryExpandsWindowsAndReducesActualCourseError() throws {
        var low = match(role: .pitcher, mastery: 10), high = match(role: .pitcher, mastery: 90)
        let plan = low.delivery(pitchCode: "four-seam")
        let input = ManualMatchInput(release: 0.80)
        try low.advance(.pitch, pitchCode: "four-seam", control: input)
        try high.advance(.pitch, pitchCode: "four-seam", control: input)
        let lowResult = try XCTUnwrap(low.lastManual), highResult = try XCTUnwrap(high.lastManual)
        XCTAssertEqual(lowResult.grade, "MISS"); XCTAssertEqual(highResult.grade, "GOOD")
        XCTAssertGreaterThan(highResult.quality, lowResult.quality)
        XCTAssertLessThan(abs(highResult.x - plan.x), abs(lowResult.x - plan.x))
        XCTAssertGreaterThan(ManualMatchRules.goodWidth(mastery: 90), ManualMatchRules.goodWidth(mastery: 10))
        var perfect = match(role: .pitcher)
        try perfect.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: 0.68))
        XCTAssertEqual(perfect.lastManual?.grade, "PERFECT"); XCTAssertEqual(perfect.lastManual?.quality, 1)
        XCTAssertEqual(perfect.line.pitches, 1); XCTAssertEqual(perfect.fatigueCost, 0.38, accuracy: 0.0001)
    }

    func testInvalidManualValuesAndRolesLeaveStateUnchanged() throws {
        let original = match()
        for value in [Double.nan, .infinity, -0.1, 1.1] {
            var copy = original
            XCTAssertThrowsError(try copy.advance(.swing, control: ManualMatchInput(x: value, timing: 0.82)))
            XCTAssertEqual(copy, original)
        }
        var pitcher = match(role: .pitcher)
        let before = pitcher
        XCTAssertThrowsError(try pitcher.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(timing: 0.82)))
        XCTAssertEqual(pitcher, before)
        XCTAssertThrowsError(try pitcher.advance(.pitch, pitchCode: "unknown", control: ManualMatchInput(release: 0.68)))
        XCTAssertEqual(pitcher, before)
    }

    func testManualWalkStrikeoutAndBuntConnectToExistingPlateAndBaseProgression() throws {
        for strike in [true, false] {
            let seed = try XCTUnwrap((0..<100).first { value in
                let ball = match(seed: UInt64(value)).delivery()
                return ManualMatchRules.isStrike(x: ball.x, y: ball.y) == strike
            })
            var state = match(seed: UInt64(seed)); state.strikes = strike ? 2 : 0; state.balls = strike ? 0 : 3
            try state.advance(.watch, control: ManualMatchInput())
            XCTAssertEqual(state.line.plateAppearances, 1)
            XCTAssertEqual(state.line.strikeouts, strike ? 1 : 0)
            XCTAssertEqual(state.line.walks, strike ? 0 : 1)
        }
        for seed in 0..<100 {
            var state = match(seed: UInt64(seed)); let ball = state.delivery()
            try state.advance(.bunt, control: ManualMatchInput(x: ball.x, y: ball.y, timing: 0.82))
            XCTAssertEqual(state.line.homeRuns, 0)
        }
    }

    func testV2DirectGeneratedInputsAndAutomaticFinishHaveIdenticalResults() throws {
        var batterStrikeouts = 0
        for role in PlayerRole.allCases {
            for seed in 0..<50 {
                var direct = match(role: role, seed: UInt64(seed))
                direct.settle()
                var automatic = direct
                try automatic.advance(.automatic)
                var count = 0
                while !direct.completed && count < 1000 {
                    let input: MatchInput = role == .batter ? .swing : .pitch
                    let code: String? = role == .pitcher ? "four-seam" : nil
                    let control = direct.automaticControl(input, pitchCode: code)
                    try direct.advance(input, pitchCode: code, control: control)
                    count += 1
                }
                XCTAssertTrue(direct.completed); XCTAssertEqual(direct, automatic)
                if role == .batter { batterStrikeouts += direct.line.strikeouts }
            }
        }
        XCTAssertGreaterThan(batterStrikeouts, 0)
    }

    func testManualSaveFailureRetryAndStaleInputCannotApplyTwice() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, calendar, record) = try fixture(in: context)
        let before = try record.snapshot(); let ball = before.delivery()
        let control = ManualMatchInput(x: ball.x, y: ball.y, timing: 0.82)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: 0,
                                                        input: .swing, control: control, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try record.snapshot(), before); XCTAssertEqual(record.revision, 0)
        XCTAssertEqual(player.fatigue, 6)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: 0, input: .swing, control: control, in: context)
        let once = record.payload
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: 0, input: .swing, control: control, in: context))
        XCTAssertEqual(record.payload, once)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context)
        let fatigue = player.fatigue
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context))
        XCTAssertEqual(player.fatigue, fatigue)
    }

    func testLegacyV1DiskPayloadResumesUpgradesOnlyOnManualSaveAndKeepsCompletedBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        var oldCompleted = Data()
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url); let context = container.mainContext
            for role in PlayerRole.allCases {
                let (_, _, record) = try fixture(in: context, role: role)
                var legacy = try record.snapshot(); legacy.controlVersion = nil; legacy.lastManual = nil
                if role == .pitcher { try legacy.advance(.automatic) }
                var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
                dictionary.removeValue(forKey: "controlVersion"); dictionary.removeValue(forKey: "lastManual")
                record.payload = try JSONSerialization.data(withJSONObject: dictionary, options: .sortedKeys)
                record.completed = legacy.completed; record.rulesVersion = "native-match-v1"
                if role == .pitcher { oldCompleted = record.payload }
            }
            try context.save()
        }
        let reopened = try CareerStore.makeContainer(url: url); let context = reopened.mainContext
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        for player in players {
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
            let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            XCTAssertEqual(player.gameDate, "2026-04-01")
            if player.role == .pitcher {
                XCTAssertEqual(record.payload, oldCompleted); XCTAssertEqual(record.rulesVersion, "native-match-v1")
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .pitch, pitchCode: "four-seam", control: ManualMatchInput(release: 0.68), in: context))
                XCTAssertEqual(record.payload, oldCompleted)
            } else {
                XCTAssertNil(try record.snapshot().controlVersion)
                enum Injected: Error { case failure }
                let oldPayload = record.payload
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision,
                                                                input: .swing, control: ManualMatchInput(), in: context, save: { _ in throw Injected.failure }))
                XCTAssertEqual(record.payload, oldPayload)
                XCTAssertEqual(record.rulesVersion, "native-match-v1")
                try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .swing, control: ManualMatchInput(), in: context)
                XCTAssertEqual(record.rulesVersion, "native-match-v2"); XCTAssertEqual(try record.snapshot().controlVersion, 2)
                XCTAssertEqual(try record.snapshot().lastManual?.action, "watch")
            }
        }
        let second = try CareerStore.makeContainer(url: url)
        let records = try second.mainContext.fetch(FetchDescriptor<CareerMatchRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.contains { $0.completed && $0.payload == oldCompleted })
        XCTAssertTrue(records.contains { $0.rulesVersion == "native-match-v2" })
    }

    func testClockTimeoutOnceAndCancellationDoesNotResolveInput() async throws {
        let clock = MatchInputClock(); var count = 0
        clock.start(windup: 0, duration: 0.02) { count += 1; clock.stop() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(count, 1); XCTAssertFalse(clock.running)
        clock.start(windup: 0, duration: 1) { count += 1 }
        clock.stop()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count, 1); XCTAssertFalse(clock.running)
    }
}
