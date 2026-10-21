import XCTest
import SpriteKit
import SwiftData
@testable import BM

@MainActor final class ManualMatchTests: XCTestCase {
    func testPitchPreparationHoldsBallUntilExplicitReleaseForBothHands() {
        for hand in ["left", "right"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 320))
            scene.configure(hand: hand, kit: 0, role: .pitcher)
            for phase in [0.0, 0.3, 0.68, 0.95] {
                scene.preparePitch(phase: phase, reduced: false)
                XCTAssertEqual(scene.pitchStage, .preparing)
                XCTAssertNil(scene.action(forKey: "delivery"))
            }
            XCTAssertTrue(scene.demonstrate(reduceMotion: false, preparedRelease: true))
            XCTAssertEqual(scene.pitchStage, .flight)
            scene.preparePitch(phase: 0.7, reduced: false)
            XCTAssertEqual(scene.pitchStage, .flight)
            scene.cancelDelivery(); XCTAssertEqual(scene.pitchStage, .idle)
            scene.preparePitch(phase: 0.68, reduced: true)
            XCTAssertEqual(scene.pitchStage, .preparing)
            XCTAssertTrue(scene.demonstrate(reduceMotion: true, preparedRelease: true))
            XCTAssertEqual(scene.pitchStage, .flight)
        }
    }

    func testFreePracticeAllKindsAndPositionsLeaveCareerStoreUnchanged() throws {
        let real = try CareerStore.makeContainer(inMemory: true)
        var originals: [CareerPlayer] = []
        for role in PlayerRole.allCases {
            var draft = PlayerDraft(); draft.name = role.label; draft.role = role; draft.schoolID = "hs-ref-001"
            draft.throwingHand = .left; draft.appearance = PlayerAppearance(skin: 3, hair: 4, kit: 5, hairStyle: 2, expression: 1)
            let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: real.mainContext)
            player.contact = 81.2345; player.speed = 77.3456
            if role == .pitcher {
                player.pitches = [CareerSchemaV1.PitchMastery(code: "knuckle", name: "너클", mastery: 88.1234, order: 2),
                                  CareerSchemaV1.PitchMastery(code: "slider", name: "슬라이더", mastery: 32.5678, order: 1),
                                  CareerSchemaV1.PitchMastery(code: "four-seam", name: "포심", mastery: 93.4567, order: 0)]
            }
            let profile = try XCTUnwrap(PlayerAbilityStore.profile(playerID: player.id, in: real.mainContext))
            profile.mental = 78.4321
            if role == .pitcher { profile.velocity = 87.6543; profile.control = 91.2345; profile.stuff = 76.789; profile.stamina = 83.4567 }
            originals.append(player)
        }
        try real.mainContext.save()
        let player = originals[0]
        let calendar = try XCTUnwrap(real.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: real.mainContext)
        let matchRecord = try CareerMatchStore.start(player: player, state: calendar, in: real.mainContext)
        let date = player.gameDate, fatigue = player.fatigue, revision = calendar.revision, original = matchRecord.payload
        let memory = try CareerStore.makeContainer(inMemory: true)
        let copies = try originals.map { try TrainingPractice.copy($0, from: real.mainContext, into: memory.mainContext) }
        for (original, copy) in zip(originals, copies) {
            XCTAssertNotEqual(copy.id, original.id); XCTAssertFalse(copy === original)
            XCTAssertEqual(copy.name, original.name); XCTAssertEqual(copy.appearance, original.appearance)
            XCTAssertEqual(copy.throwingHandRaw, "left"); XCTAssertEqual(copy.contact, 81.2345)
            XCTAssertEqual(copy.speed, 77.3456); XCTAssertEqual(copy.fatigue, 0)
            XCTAssertEqual(copy.pitches.sorted { $0.order < $1.order }.map(\.code), original.pitches.sorted { $0.order < $1.order }.map(\.code))
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: copy.pitches.map { ($0.code, $0.mastery) }), Dictionary(uniqueKeysWithValues: original.pitches.map { ($0.code, $0.mastery) }))
            let a = try XCTUnwrap(PlayerAbilityStore.profile(playerID: original.id, in: real.mainContext))
            let b = try XCTUnwrap(PlayerAbilityStore.profile(playerID: copy.id, in: memory.mainContext))
            XCTAssertFalse(a === b); XCTAssertEqual(a.initialValues, b.initialValues)
            XCTAssertEqual(a.mental, b.mental); XCTAssertEqual(a.velocity, b.velocity); XCTAssertEqual(a.control, b.control)
            XCTAssertEqual(a.stuff, b.stuff); XCTAssertEqual(a.stamina, b.stamina)
        }
        for role in PlayerRole.allCases {
            for kind in TrainingKind.allCases where kind.allows(role.rawValue) {
                for _ in 0..<2 {
                    let copy = try XCTUnwrap(copies.first { $0.role == role })
                    let state = try XCTUnwrap(memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == copy.id })
                    var round = try TrainingPractice.round(player: copy, calendar: state, kind: kind, code: "four-seam", in: memory.mainContext)
                    for _ in 0..<5 {
                        let input: TrainingInput
                        switch kind {
                        case .contact: input = TrainingInput(x: 0.5, y: 0.5, timing: 0.82)
                        case .pitch: input = TrainingInput(release: 0.68)
                        case .power, .velocity, .stuff: input = TrainingInput(force: 70, angle: 35)
                        case .discipline: input = TrainingInput(calledStrike: true)
                        case .mental: input = TrainingInput(choice: 0)
                        case .speed, .stamina: input = TrainingInput(footfalls: [])
                        case .arm: input = TrainingInput(force: 70, angle: 35, base: 1)
                        case .control, .defense: input = TrainingInput(x: 0.5, y: 0.5)
                        }
                        try round.attempt(input)
                    }
                    XCTAssertTrue(round.completed)
                    XCTAssertEqual(round.before, try CareerTrainingStore.value(player: originals.first { $0.role == role }!, code: kind == .pitch ? "four-seam" : nil, kind: kind, in: real.mainContext)); XCTAssertEqual(round.fatigue, 0)
                    XCTAssertThrowsError(try round.attempt(TrainingInput()))
                }
            }
        }
        for position in FieldPosition.allCases {
            let copy = copies[0]
            let state = try XCTUnwrap(memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == copy.id })
            var round = try TrainingPractice.round(player: copy, calendar: state, kind: .defense, position: position, in: memory.mainContext)
            XCTAssertEqual(try CareerTrainingRecord(round).snapshot(), round)
            for _ in 0..<5 { try round.attempt(TrainingInput(x: 0.5, y: 0.5, force: 50, angle: 270, base: 1)) }
            XCTAssertTrue(round.completed)
        }
        XCTAssertEqual(player.gameDate, date); XCTAssertEqual(player.fatigue, fatigue)
        XCTAssertEqual(calendar.revision, revision); XCTAssertEqual(matchRecord.payload, original)
        XCTAssertEqual(try real.mainContext.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 0)
        XCTAssertEqual(try memory.mainContext.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 0)
        XCTAssertEqual(try memory.mainContext.fetchCount(FetchDescriptor<CareerMatchRecord>()), 0)
        XCTAssertEqual(try real.mainContext.fetchCount(FetchDescriptor<CareerPlayer>()), 2)
        let pitcher = copies[1], state = try XCTUnwrap(memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == pitcher.id })
        XCTAssertThrowsError(try TrainingPractice.round(player: pitcher, calendar: state, kind: .pitch, code: "fork", in: memory.mainContext))
        let before = try TrainingPractice.round(player: pitcher, calendar: state, kind: .pitch, code: "four-seam", in: memory.mainContext)
        XCTAssertEqual(before.before, 93.4567)
        originals[1].pitches.first { $0.code == "four-seam" }!.mastery = 1
        XCTAssertEqual(pitcher.pitches.first { $0.code == "four-seam" }?.mastery, 93.4567)
        pitcher.speed = 1; XCTAssertEqual(originals[1].speed, 77.3456)
    }

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
        let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
        let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
        return (player, calendar, record)
    }

    func testResultSummaryProjectsSavedBatterMetricsWithoutMutation() {
        var state = match(); state.completed = true; state.homeScore = 4; state.awayScore = 2
        state.line = MatchLine(plateAppearances: 5, atBats: 4, hits: 2, homeRuns: 1, walks: 1, strikeouts: 1, rbi: 3)
        let original = state
        let summary = MatchResultSummary(match: state, fatigueBefore: 24, fatigueAfter: 28)
        XCTAssertEqual(summary.outcome, "승리"); XCTAssertEqual(summary.fatigueChange, "+4")
        XCTAssertEqual(summary.metrics.map(\.value), ["5", "4", "2", "1", "3", "1", "1"])
        XCTAssertEqual(state, original)
    }
    func testResultSummaryPitchingOutsAreBaseThreeAndNoInventedERA() {
        var state = match(role: .pitcher); state.line.pitchingOuts = 17; state.line.pitches = 92
        state.line.hitsAllowed = 5; state.line.runsAllowed = 3; state.line.pitchingWalks = 2; state.line.pitchingStrikeouts = 6
        let summary = MatchResultSummary(match: state, fatigueBefore: 6, fatigueAfter: 37)
        XCTAssertEqual(summary.metrics.map(\.value), ["5.2", "92", "5", "3", "2", "6"])
        XCTAssertFalse(summary.metrics.contains { $0.id == "era" })
    }
    func testResultSummarySeparatesAbsentLegacyEmptyAndAppliedTraits() {
        var state = match()
        XCTAssertTrue(MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0).traitMessage.contains("경합이 없습니다"))
        state.lastFieldPlay = MatchFieldPlay(runnerTime: 3, ballTime: 4, ownDefense: false)
        XCTAssertTrue(MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0).traitMessage.contains("미기록"))
        state.lastFieldPlay?.appliedTraits = []
        XCTAssertTrue(MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0).traitMessage.contains("특성 없음"))
        state.lastFieldPlay?.appliedTraits = [.cheetah]
        let summary = MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0)
        XCTAssertEqual(summary.appliedTraits, [.cheetah]); XCTAssertEqual(summary.fatigueChange, "변화 없음")
        state = CareerMatch(random: 1, isHome: true, role: "pitcher", appearance: false, contact: 60, power: 60, discipline: 60, mastery: [:])
        let absent = MatchResultSummary(match: state, fatigueBefore: 24, fatigueAfter: 24)
        XCTAssertTrue(absent.metrics.isEmpty); XCTAssertTrue(absent.traitMessage.contains("비등판"))
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

@MainActor final class MatchPresentationTests: XCTestCase {
    func testContactUsesTheSwingAndBuntAtlasBarrels() {
        let swing = MatchPresentation.batContact(action: "swing")
        let bunt = MatchPresentation.batContact(action: "bunt")
        XCTAssertEqual(swing.x, 0.510859375, accuracy: 0.000001)
        XCTAssertEqual(swing.y, 0.66763671875, accuracy: 0.000001)
        XCTAssertEqual(bunt.x, 0.49875, accuracy: 0.000001)
        XCTAssertEqual(bunt.y, 0.6807421875, accuracy: 0.000001)
    }

    func testVisualFlightKeepsSavedEndpointAndMirrorsOnlyHorizontalBreak() {
        let size = CGSize(width: 320, height: 320), start = CGPoint(x: 160, y: 220), end = CGPoint(x: 160, y: 80)
        for role in PlayerRole.allCases {
            for code in ["four-seam", "slider", "changeup", "fork"] {
                for hand in ["left", "right"] {
                    XCTAssertEqual(MatchBallPath.point(from: start, to: end, size: size, role: role, hand: hand, code: code, progress: 0), start)
                    XCTAssertEqual(MatchBallPath.point(from: start, to: end, size: size, role: role, hand: hand, code: code, progress: 1), end)
                }
            }
            let right = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: "slider", progress: 0.5)
            let left = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "left", code: "slider", progress: 0.5)
            XCTAssertEqual(right.x + left.x, 320, accuracy: 0.0001)
            XCTAssertEqual(right.y, left.y)
            var previous = start
            for step in 1...100 {
                let point = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: "fork", progress: Double(step) / 100)
                XCTAssertLessThan(point.y, previous.y)
                previous = point
            }
        }
    }

    func testFieldFitsCompactAndTallPhonesWithoutStretching() {
        for available in [CGSize(width: 304, height: 480), CGSize(width: 359, height: 560), CGSize(width: 386, height: 730)] {
            for role in PlayerRole.allCases {
                let field = MatchPresentation.fieldSize(available: available, role: role)
                XCTAssertLessThanOrEqual(field.width, available.width)
                XCTAssertLessThanOrEqual(field.height + 310, available.height)
                XCTAssertEqual(field.width / field.height, role == .batter ? 1 : 1219.0 / 1290, accuracy: 0.0001)
            }
        }
    }
    func testMeasuredMatchChromeKeepsFieldRatioAndAvailableSpace() {
        for chrome in [CGFloat(260), 340, 420] {
            for role in PlayerRole.allCases {
                let size = MatchPresentation.fieldSize(available: CGSize(width: 304, height: 600), role: role, chromeHeight: chrome)
                XCTAssertLessThanOrEqual(size.width, 304)
                XCTAssertLessThanOrEqual(size.height + chrome, 600)
                XCTAssertEqual(size.width / size.height, role == .batter ? 1 : 1219.0 / 1290, accuracy: 0.0001)
            }
        }
        let large = MatchPresentation.fieldSize(available: CGSize(width: 304, height: 480), role: .batter, chromeHeight: 600)
        XCTAssertEqual(large.height, 150) // Large text uses scrolling instead of distorting the field.
    }

    func testOnlyNewPitchJudgmentsRequestCountPulse() {
        for value in ["볼", "볼넷"] { XCTAssertEqual(MatchPresentation.countPulse(value), "B") }
        for value in ["루킹 스트라이크", "헛스윙", "삼진"] { XCTAssertEqual(MatchPresentation.countPulse(value), "S") }
        for value in ["안타", "홈런", "범타"] { XCTAssertNil(MatchPresentation.countPulse(value)) }
        XCTAssertNil(MatchPresentation.countPulse(nil))
    }
    func testSavedPitchNameSurvivesSelectionAndLegacyResultDecodes() throws {
        let result = ManualMatchResult(action: "pitch", quality: 1, grade: "GOOD", x: 0.5, y: 0.5, speed: 132, outcome: "볼", pitchCode: "slider")
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(MatchPresentation.pitchName(try JSONDecoder().decode(ManualMatchResult.self, from: data)), "슬라이더")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "pitchCode")
        let restored = try JSONDecoder().decode(ManualMatchResult.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.pitchCode)
        XCTAssertEqual(MatchPresentation.pitchName(restored), "구종 미기록")
        XCTAssertEqual(MatchPresentation.pitchName(nil), "투구 대기")
    }
    func testAllBundledAtlasFramesAndSceneArtLoad() throws {
        for name in MatchArt.names { XCTAssertNotNil(MatchArt.image(name), name) }
        for name in ["pitcher-delivery-v2", "batter-actions"] {
            for i in 0..<6 { XCTAssertNotNil(MatchArt.cell(name, column: i % 3, row: i / 3, columns: 3, rows: 2)) }
        }
        let scene = BallparkScene(size: CGSize(width: 320, height: 400))
        scene.configure(hand: "left", kit: 0, role: .batter)
        XCTAssertEqual(scene.size, CGSize(width: 320, height: 320))
        XCTAssertTrue(scene.demonstrate(reduceMotion: true))
        scene.cancelDelivery()
        scene.configure(hand: "left", kit: 0, role: .pitcher)
        XCTAssertTrue(scene.demonstrate(reduceMotion: false, pitchCode: "slider"))
        scene.cancelDelivery()
    }
}
