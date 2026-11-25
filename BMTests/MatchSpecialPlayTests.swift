import XCTest
import SwiftData
@testable import BM

final class MatchSpecialPlayTests: XCTestCase {
    private let bags = DetailedFieldRules.bases
    private func runner(_ name: String, speed: Double = 60) -> FieldRunnerProfile {
        .init(speed: speed, responsiblePitcher: "home-starter", id: name)
    }
    private func inputs(firstSpeed: Double = 100, firstRead: Double = 0,
                        secondSpeed: Double = 10, secondRead: Double = 100) -> MatchSpecialContext {
        var match = CareerMatch(random: 1, isHome: false, role: "league", appearance: false,
                                contact: 60, power: 60, discipline: 60, mastery: [:])
        match.outs = 1; match.runnerProfiles = [runner("R1", speed: firstSpeed), runner("R2", speed: secondSpeed), nil]
        let npc = DetailedFieldRules.names.map { MatchNPCPlayer(id: $0, position: $0, speed: 50, defense: 0, arm: 0) }
        return MatchSpecialContext(before: MatchPitchState(match), ball: nil, batter: nil, stats: nil,
            npc: npc, defending: false, ownBatter: false, discipline: ["R1": firstRead,"R2": secondRead],
            pitchDuration: 0.9, runningID: "running:1")
    }

    private func fieldInput(_ kind: MatchSpecialField.Kind, outs: Int = 1, inherited: Bool = false) -> MatchSpecialContext {
        let setup: Int, angleIndex: Int, directionIndex: Int
        switch kind {
        case .interference: (setup,angleIndex,directionIndex) = (5,0,17)
        case .passing: (setup,angleIndex,directionIndex) = (4,0,10)
        case .sharedBase: (setup,angleIndex,directionIndex) = (1,0,2)
        case .obstruction: (setup,angleIndex,directionIndex) = (10,5,1)
        }
        let angles = Array(stride(from: 0.05, through: 0.95, by: 0.1))
        let directions = Array(stride(from: 0.05, through: 0.95, by: 0.05))
        let ball = FieldReviewRules.ball(quality: 0.85, contact: 80, power: 65, bunt: false,
            offsetX: 0, offsetY: 0, timing: 0, speedDraw: 0.15, angleDraw: angles[angleIndex], directionDraw: directions[directionIndex])
        var match = CareerMatch(random: 1, isHome: false, role: "league", appearance: false,
            contact: 60, power: 60, discipline: 60, mastery: [:])
        match.outs = outs
        match.runnerProfiles = setup == 10 ? [nil,nil,nil] : [runner("R1", speed: 100),runner("R2", speed: 15),nil]
        if inherited { match.runnerProfiles?[1]?.responsiblePitcher = "home-relief" }
        var batter = runner("B1", speed: setup == 10 ? 100 : 60)
        if inherited { batter.responsiblePitcher = "home-relief" }
        return MatchSpecialContext(before: MatchPitchState(match), ball: ball,
            batter: batter, stats: nil,
            npc: DetailedFieldRules.names.map { .init(id: $0, position: $0, speed: setup == 10 ? 0 : 50, defense: 40, arm: 20) },
            defending: false, ownBatter: false, discipline: ["R1":setup == 4 ? 60 : setup == 5 ? 80 : 100,"R2":0,"B1":60])
    }

    func testDeadBallHoldsUntilAwardAndLiveOutsKeepResponsibility() throws {
        for kind: MatchSpecialField.Kind in [.interference,.obstruction,.passing,.sharedBase] {
            let context = fieldInput(kind), play = try XCTUnwrap(MatchSpecialRules.field(context))
            let event = try XCTUnwrap(play.special)
            XCTAssertEqual(event.kind, kind)
            try play.validate()
            XCTAssertEqual(event.retirements.count, play.outsAdded)
            for move in play.runners {
                // 야수 선택으로 책임이 승계되는 경우도 실제 처리 함수와 동일하게 검증한다.
                if move.from > 0, !move.out { XCTAssertEqual(move.profile.responsiblePitcher, "home-starter") }
                if event.dead, !move.out {
                    let resume = try XCTUnwrap(event.resumeAt)
                    XCTAssertEqual(FieldNode.sample(move.nodes, at: event.at), FieldNode.sample(move.nodes, at: resume))
                    XCTAssertGreaterThan(move.arrival, resume)
                    XCTAssertEqual(move.nodes.last?.point, bags[move.destination])
                }
            }
            if kind == .obstruction {
                XCTAssertLessThan(event.at, try XCTUnwrap(event.awardedAt))
                XCTAssertLessThan(try XCTUnwrap(event.awardedAt), try XCTUnwrap(event.resumeAt))
                XCTAssertEqual(play.hitBases, 1); XCTAssertEqual(play.afterRunners.map { $0?.id }, [nil,"B1",nil])
            }
            if kind == .sharedBase {
                XCTAssertEqual(event.tags.map(\.out), [true,false])
                XCTAssertEqual(play.runners.filter(\.out).map(\.from), [2])
            }
        }
    }

    @MainActor func testSpecialPlateCountersAndFieldingAreRecordedOnceWithoutStrikeout() throws {
        for kind: MatchSpecialField.Kind in [.interference,.obstruction,.passing,.sharedBase] {
            let play = try XCTUnwrap(MatchSpecialRules.field(fieldInput(kind)))
            var records = try XCTUnwrap(InplayIntegrationTests().makeMatch().playerRecords)
            records.runners = [records.away.lineup[1], records.away.lineup[2], nil]
            let result = kind == .obstruction ? "안타" : "야수 선택"
            records.recordPlate(home: false, order: 0, battingRelief: false, pitchingRelief: true,
                result: result, play: play, runs: play.runs, outsAdded: play.outsAdded, rbi: play.rbi,
                responsible: [], cleanFieldingPlay: play)
            XCTAssertEqual(records.away.battingTotal.plateAppearances, 1)
            XCTAssertEqual(records.away.battingTotal.strikeouts, 0)
            XCTAssertEqual(records.away.battingTotal.hits, kind == .obstruction ? 1 : 0)
            XCTAssertEqual(records.home.pitching[1].counts.battersFaced, 1)
            XCTAssertEqual(records.home.pitching[1].counts.outs, play.outsAdded)
            XCTAssertEqual(records.home.fielding?.reduce(0) { $0 + $1.putouts }, play.outsAdded)
            XCTAssertEqual(records.home.fielding?.reduce(0) { $0 + $1.errors }, kind == .obstruction ? 1 : 0)
            XCTAssertEqual(records.away.battingTotal.rbi, 0)
        }
    }

    @MainActor func testInheritedRunnerTagsChargeOriginalPitcherAfterSpecialPlay() throws {
        for kind: MatchSpecialField.Kind in [.interference,.obstruction,.passing,.sharedBase] {
            let play = try XCTUnwrap(MatchSpecialRules.field(fieldInput(kind, inherited: true)))
            try play.validate()
            var records = try XCTUnwrap(InplayIntegrationTests().makeMatch().playerRecords)
            records.runners = kind == .obstruction ? [nil,nil,nil] : [records.away.lineup[1],records.away.lineup[2],nil]
            records.recordPlate(home: false, order: 0, battingRelief: false, pitchingRelief: true,
                result: kind == .obstruction ? "안타" : "야수 선택", play: play, runs: 0,
                outsAdded: play.outsAdded, rbi: 0, responsible: [], cleanFieldingPlay: play)
            let tags = play.afterRunners.compactMap { $0?.responsiblePitcher } + ["home-relief"]
            records.recordPlate(home: false, order: 3, battingRelief: false, pitchingRelief: true,
                result: "홈런", play: nil, runs: tags.count, outsAdded: 0, rbi: tags.count, responsible: tags)
            XCTAssertEqual(records.home.pitching[0].counts.runsAllowed, tags.filter { $0 == "home-starter" }.count)
            XCTAssertEqual(records.home.pitching[1].counts.runsAllowed, tags.filter { $0 == "home-relief" }.count)
            XCTAssertEqual(records.away.battingTotal.runs, tags.count)
            if kind == .interference || kind == .passing {
                XCTAssertEqual(play.afterRunners[0]?.responsiblePitcher, "home-starter")
            }
        }
    }

    @MainActor func testSpecialReferenceEnvironmentKeepsPreviouslyFrozenReportSeparate() throws {
        for role in PlayerRole.allCases {
            let position = role == .batter ? "SS" : "P", values = PlayerArchetype.initial(for: role).values
            let old = ScoutingReferenceSimulation.fixture(role: role, position: position, values: values, seed: 91, home: true,
                tracked: true, battedBallVersion: 1, npcFieldersVersion: 1, npcAttackVersion: 2,
                pitchEventsVersion: 1, runningVersion: 1, fieldReviewVersion: 1)
            let current = ScoutingReferenceSimulation.fixture(role: role, position: position, values: values, seed: 91, home: true,
                tracked: true, battedBallVersion: 1, npcFieldersVersion: 1, npcAttackVersion: 2,
                pitchEventsVersion: 1, runningVersion: 1, fieldReviewVersion: 1, specialRulesVersion: 1)
            let environment = try XCTUnwrap(current.scoutingEnvironment)
            XCTAssertNil(old.specialRulesVersion); XCTAssertEqual(current.specialRulesVersion, 1)
            XCTAssertNotEqual(old.scoutingEnvironment, environment); XCTAssertTrue(environment.contains("-special1-"))
            let frozen = try XCTUnwrap(ScoutingReferenceSimulation.make(environment: old.scoutingEnvironment!, role: role, position: position))
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let bytes = try encoder.encode(frozen)
            let reference = try XCTUnwrap(ScoutingReferenceSimulation.make(environment: environment, role: role, position: position))
            try reference.validate(); XCTAssertEqual(reference.environment, environment)
            XCTAssertEqual(try encoder.encode(frozen), bytes)
        }
    }

    func testThirdOutStopsAwardsAndRejectsForgedCompletedCounts() throws {
        for kind: MatchSpecialField.Kind in [.interference,.passing,.sharedBase] {
            let context = fieldInput(kind, outs: 2)
            var play = try XCTUnwrap(MatchSpecialRules.field(context))
            let event = try XCTUnwrap(play.special)
            XCTAssertEqual(event.kind, kind); XCTAssertEqual(play.outsAdded, 1)
            XCTAssertEqual(play.afterRunners.map { $0?.id }, [nil,nil,nil]); XCTAssertEqual(play.runs, 0)
            XCTAssertEqual(event.settledAt, try XCTUnwrap(event.retirements.last?.at))
            var after = CareerMatch(random: 1, isHome: false, role: "league", appearance: false,
                contact: 60, power: 60, discipline: 60, mastery: [:])
            after.half = 1; after.awayOrder = 1; after.runnerProfiles = [nil,nil,nil]
            play.review?.after = MatchPitchState(after); try play.validate()
            after.strikes = 1; play.review?.after = MatchPitchState(after)
            XCTAssertThrowsError(try play.validate())
            after.strikes = 0; after.completed = true; play.review?.after = MatchPitchState(after)
            XCTAssertThrowsError(try play.validate())
        }
    }

    func testAnalyticalContactAndStrictPassingDoNotDependOnFrames() throws {
        let still = [FieldNode(at: 0, point: .init(x: 0, y: 0)), .init(at: 5, point: .init(x: 0, y: 0))]
        let crossing = [FieldNode(at: 0, point: .init(x: -5, y: 0)), .init(at: 5, point: .init(x: 5, y: 0))]
        XCTAssertEqual(MatchSpecialRules.contact(still, crossing, start: 0, end: 5)!, 2.15, accuracy: 0.000001)
        let ahead = DetailedRunner(from: 2, destination: 3, profile: runner("R2"), nodes: [.init(at: 0, point: bags[2]), .init(at: 6, point: bags[3])])
        let behind = DetailedRunner(from: 1, destination: 3, profile: runner("R1"), nodes: [.init(at: 0, point: bags[1]), .init(at: 2, point: bags[2]), .init(at: 4, point: bags[3])])
        let at = try XCTUnwrap(MatchSpecialRules.overtaking(behind, ahead))
        XCTAssertGreaterThan(at, 2.9); XCTAssertLessThan(at, 3.1)
        XCTAssertNil(MatchSpecialRules.overtaking(ahead, behind))
    }

    func testSharedNonforceTagsRightsBeforeOutAndKeepsOriginalRunner() throws {
        let context = inputs(), play = try XCTUnwrap(MatchSpecialRules.sharedPitch(context))
        XCTAssertEqual(play.special?.kind, .sharedBase)
        XCTAssertEqual(play.special?.tags.map(\.out), [false,true])
        XCTAssertEqual(play.outsAdded, 1); XCTAssertEqual(play.afterRunners.map { $0?.id }, [nil,"R2",nil])
        XCTAssertEqual(play.runners.filter(\.out).map(\.from), [1])
        try play.validate(); try play.validateRunningField()
        XCTAssertEqual(try JSONDecoder().decode(MatchDetailedPlay.self, from: JSONEncoder().encode(play)), play)
        var changed = play; changed.afterRunners = [nil,context.before.runners[0],nil]
        XCTAssertThrowsError(try changed.validate())
        XCTAssertNil(MatchSpecialRules.sharedPitch(inputs(firstRead: 100)))
    }

    /// 일반 타구 입력을 탐색해 새 규칙의 실제 연결과 잘못된 중복 점유를 함께 검사한다.
    func testFieldRuleInputMatrixAndPersistedProofs() throws {
        var found: [String: [Double]] = [:]
        var count = 0
        for angle in stride(from: 0.05, through: 0.95, by: 0.1) {
            for speed in [0.15,0.45,0.75,0.95] {
                for direction in stride(from: 0.05, through: 0.95, by: 0.05) {
                    let ball = FieldReviewRules.ball(quality: 0.85, contact: 80, power: 65, bunt: false,
                        offsetX: 0, offsetY: 0, timing: 0, speedDraw: speed, angleDraw: angle, directionDraw: direction)
                    guard !FieldReviewRules.isHomeRun(ball), FieldReviewRules.ruling(ball) == nil else { continue }
                    for setup in 0..<11 {
                        var match = CareerMatch(random: 1, isHome: false, role: "league", appearance: false, contact: 60, power: 60, discipline: 60, mastery: [:])
                        match.outs = 1
                        match.runnerProfiles = setup == 0 ? [runner("R1", speed: 100),nil,nil] : [1,3,4,5].contains(setup) ? [runner("R1", speed: 100),runner("R2", speed: 15),nil] : [nil,nil,nil]
                        let context = MatchSpecialContext(before: MatchPitchState(match), ball: ball, batter: runner("B1", speed: setup >= 6 ? Double(setup-6)*25 : 60),
                            stats: nil, npc: DetailedFieldRules.names.map { .init(id: $0, position: $0, speed: setup == 10 ? 0 : 50, defense: 40, arm: 20) },
                            defending: false, ownBatter: false, discipline: ["R1":setup==3 ? 30 : setup==4 ? 60 : setup==5 ? 80 : 100,"R2":0,"B1":60])
                        if ball.kind.airborne {
                            let first = ball.point(at: ball.firstBounceAt ?? ball.flight)
                            let reached = context.skills.indices.map { context.skills[$0].reaction + DetailedFieldRules.positions[$0].distance(to: first)/context.skills[$0].velocity + context.skills[$0].pickup }.min()!
                            if reached <= (ball.firstBounceAt ?? ball.flight) { continue }
                        }
                        guard let play = MatchSpecialRules.field(context) else { continue }
                        count += 1
                        if let event = play.special {
                            try play.validate()
                            if found[event.kind.rawValue] == nil {
                                found[event.kind.rawValue] = [angle,speed,direction,Double(setup)]
                                print("P11_CASE",event.kind.rawValue,found[event.kind.rawValue]!,play.outsAdded,play.afterRunners.map { $0?.id ?? "-" },play.hitBases,play.runs)
                                let a = XCTAttachment(data: try JSONEncoder().encode(play), uniformTypeIdentifier: "public.json"); a.name = "P11-" + event.kind.rawValue; a.lifetime = .keepAlways; add(a)
                            }
                        } else {
                            let ids = play.afterRunners.compactMap { $0?.id }
                            XCTAssertEqual(ids.count, Set(ids).count)
                        }
                    }
                }
            }
        }
        print("P11_GENERATED", found, "inputCases", count)
        XCTAssertNotNil(found["interference"])
        XCTAssertNotNil(found["passing"])
        XCTAssertNotNil(found["sharedBase"])
        XCTAssertNotNil(found["obstruction"])
    }

    @MainActor func testBothRolesGeneralEngineKeepsRecordsAndLegacyAcrossSeeds() throws {
        var cases: [String: Int] = [:]
        for role in PlayerRole.allCases {
            for seed in 1...64 {
                var match = InplayIntegrationTests().makeMatch(role: role)
                match.random = UInt64(seed)
                match.enablePitchEvents(); match.enableRunning(); match.enableFieldReview(); match.enableSpecialPlays()
                XCTAssertEqual(match.specialRulesVersion, 1)
                try match.advance(.automatic)
                XCTAssertTrue(match.completed)
                for play in (match.fieldPlays ?? []) + (match.running?.events.map(\.play) ?? []) {
                    if let kind = play.special?.kind { cases[kind.rawValue, default: 0] += 1 }
                }
                for (name, check) in [("records", { try match.playerRecords?.validate(match: match) }),
                                      ("field", { try match.validateDetailedField() }),
                                      ("running", { try match.validateRunning() })] {
                    do { try check() } catch {
                        print("P11_INVALID",role.rawValue,seed,name)
                        for (part, check) in [("homeRuns",{try match.validateHomeRuns()}),("reviews",{try match.validateFieldReviews()}),("specialParent",{try match.validateSpecialPlays()})] {
                            do {try check()} catch { print("P11_PART",part) }
                        }
                        for (index,play) in (match.fieldPlays ?? []).enumerated() {
                            do { try play.validate() } catch {print("P11_BAD_PLAY",index,play.special?.kind.rawValue ?? "ordinary",play.half,play.order)}
                        }
                        let a=XCTAttachment(data: try JSONEncoder().encode(match), uniformTypeIdentifier:"public.json")
                        a.name="P11-invalid-"+name; a.lifetime = .keepAlways; add(a)
                        throw error
                    }
                }
                let data = try JSONEncoder().encode(match)
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self, from: data), match)
            }
            var old = InplayIntegrationTests().makeMatch(role: role)
            old.enablePitchEvents(); old.enableRunning(); old.enableFieldReview()
            let before = try JSONEncoder().encode(old)
            var reopened = try JSONDecoder().decode(CareerMatch.self, from: before)
            try old.advance(.automatic); try reopened.advance(.automatic)
            XCTAssertEqual(old, reopened); XCTAssertNil(old.specialRulesVersion)
            XCTAssertFalse((old.fieldPlays ?? []).contains { $0.special != nil })
            reopened.enableSpecialPlays(); XCTAssertNil(reopened.specialRulesVersion)
        }
        print("P11_GENERAL_CASES", cases)
    }

    @MainActor func testNewGameDiskRollbackRetryAndCompletionRemainAtomic() throws {
        enum Failure: Error { case injected }
        for role in PlayerRole.allCases {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("p11-" + UUID().uuidString + ".store")
            let saved: (UUID, Data) = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                var draft = PlayerDraft(); draft.name = "특수판정검증"; draft.schoolID = "hs-ref-001"; draft.role = role
                print("P11_STORE",role.rawValue,"create")
                let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
                let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                print("P11_STORE",role.rawValue,"rest")
                try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
                print("P11_STORE",role.rawValue,"start")
                let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
                print("P11_STORE",role.rawValue,"snapshot")
                XCTAssertEqual(try record.snapshot().specialRulesVersion, 1)
                let payload = record.payload, revision = record.revision, day = player.gameDate, fatigue = player.fatigue
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
                    input: .automatic, in: context, save: { _ in throw Failure.injected }))
                XCTAssertEqual(record.payload, payload); XCTAssertEqual(record.revision, revision)
                XCTAssertEqual(player.gameDate, day); XCTAssertEqual(player.fatigue, fatigue)
                try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision, input: .automatic, in: context)
                XCTAssertTrue(record.completed)
                let completed = record.payload, finalFatigue = player.fatigue
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record,
                    revision: record.revision, input: .automatic, in: context))
                XCTAssertEqual(record.payload, completed); XCTAssertEqual(player.fatigue, finalFatigue)
                return (player.id, completed)
            }
            try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let record = try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first { $0.playerID == saved.0 })
                XCTAssertEqual(record.payload, saved.1); XCTAssertTrue(try record.snapshot().completed)
            }
        }
    }
}
