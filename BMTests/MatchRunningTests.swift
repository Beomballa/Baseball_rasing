import XCTest
import SwiftData
import SwiftUI
@testable import BM

@MainActor final class MatchRunningTests: XCTestCase {
    private func fresh(_ role: PlayerRole = .batter, home: Bool? = nil) -> CareerMatch {
        var match = InplayIntegrationTests().makeMatch(role: role, isHome: home)
        match.enablePitchEvents(); match.enableRunning()
        return match
    }
    private func ownRunner() -> CareerMatch {
        var match = fresh()
        for _ in 0..<3 { InplayIntegrationTests().plate("삼진", in: &match) }
        InplayIntegrationTests().plate("볼넷", in: &match)
        return match
    }
    private func readyFromActualGame(_ initial: CareerMatch, early: Bool = false) throws -> CareerMatch {
        for seed in 1...64 {
            var candidate = initial; candidate.random = UInt64(seed) * 1_099_511_628_211
            for _ in 0..<150 {
                if candidate.canPrepareRunning {
                    if !early || candidate.half < 6 { return candidate }
                    try candidate.advanceRunning(); continue
                }
                if candidate.completed { break }
                try candidate.advance(.watch)
            }
        }
        throw NSError(domain: "RunningQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "출루 준비 상태를 찾지 못했습니다."])
    }
    private func validate(_ match: CareerMatch, file: StaticString = #filePath, line: UInt = #line) throws {
        do {
            try match.validateRunning(); try match.playerRecords?.validate(match: match)
            try match.validatePitchEvents(); try match.validatePitching()
            try match.validateDetailedField(); try match.inningScores?.validate(match: match)
        } catch {
            XCTFail("half \(match.half) order \(match.homeOrder)/\(match.awayOrder) events \(match.running?.events.count ?? 0): \(error)", file: file, line: line)
            throw error
        }
    }
    func testPreparationOnlyForKnownOwnRunnerWithEmptySecondAndSettleStops() throws {
        var match = ownRunner()
        XCTAssertTrue(match.canPrepareRunning)
        let before = match
        match.settle(); XCTAssertEqual(match, before)
        var unknown = match; unknown.runnerProfiles?[0]?.id = nil
        XCTAssertFalse(unknown.canPrepareRunning)
        var other = match; other.runnerProfiles?[0]?.own = false
        XCTAssertFalse(other.canPrepareRunning)
        var occupied = match; occupied.runnerProfiles?[1] = match.runnerProfiles?[0]
        XCTAssertFalse(occupied.canPrepareRunning)
        XCTAssertThrowsError(try match.advance(.watch))
        try validate(match)
    }
    func testReservationAndCancelDoNotConsumePitchRNGFatigueOrScouting() throws {
        var match = ownRunner(), before = match
        try match.reserveRunning(true)
        XCTAssertEqual(match.running?.reservation, match.runningReservation)
        let restored = try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(match))
        XCTAssertEqual(restored, match)
        XCTAssertEqual(restored.random, before.random)
        XCTAssertEqual(restored.line, before.line)
        XCTAssertEqual(restored.fatigueCost, before.fatigueCost)
        XCTAssertEqual(restored.scoutingPerformance, before.scoutingPerformance)
        try match.reserveRunning(false); before.running?.reservation = nil
        XCTAssertEqual(match, before)
        try validate(restored)
    }
    func testWaitingAndReservationUseSeparateCommandsFromBatting() throws {
        for reserve in [false,true] {
            var match = ownRunner()
            try match.reserveRunning(reserve)
            let inputs = match.scoutingPerformance, line = match.line
            try match.advanceRunning()
            XCTAssertEqual(match.line, line)
            XCTAssertEqual(match.scoutingPerformance, inputs)
            XCTAssertNil(match.running?.reservation)
            try validate(match)
        }
    }
    func testPickoffHasNoPitchCountNoPlateOrCaughtStealing() throws {
        var match = ownRunner()
        for seed in 1...100 where !match.coachPickoff { match.random = UInt64(seed) }
        XCTAssertTrue(match.coachPickoff)
        let before = match, pitchCount = match.playerRecords!.away.pitchingTotal.pitches
        XCTAssertTrue(match.resolveRunningPickoff())
        let event = try XCTUnwrap(match.running?.events.last)
        XCTAssertEqual(event.play.runningEvent?.kind, .pickoff)
        XCTAssertEqual(match.playerRecords?.away.pitchingTotal.pitches, pitchCount)
        XCTAssertEqual(match.homeOrder, before.homeOrder); XCTAssertEqual(match.awayOrder, before.awayOrder)
        XCTAssertEqual(match.balls, before.balls); XCTAssertEqual(match.strikes, before.strikes)
        XCTAssertEqual(match.playerRecords?.home.batting.first?.counts.caughtStealing, 0)
        XCTAssertEqual(event.play.out, event.play.controlAt < event.play.runnerAt!)
        try validate(match)
    }
    func testStealAndRundownUseArrivalComparisonWithSamePitchState() throws {
        for speed in [0.0,30,60,100] {
            var match = ownRunner()
            let original = match.runnerProfiles?[0]
            match.runnerProfiles?[0] = FieldRunnerProfile(speed: speed, own: true, responsiblePitcher: original?.responsiblePitcher, id: original?.id)
            let before = MatchPitchState(match), random = match.random
            let play = try XCTUnwrap(MatchRunningRules.play(match: match, kind: .steal, id: "running:1", aggressive: true))
            try play.validate()
            XCTAssertEqual(play.out, play.controlAt < play.runnerAt!)
            XCTAssertFalse(play.force)
            XCTAssertEqual(play.rbi, 0)
            XCTAssertEqual(play.runners.first?.profile.id, before.ids[0])
            XCTAssertEqual(match.random, random)
        }
    }
    func testThirdOutIsTimePlayAndOnlyEarlierHomeTouchScores() throws {
        for home in [true,false] {
            var match = ownRunner()
            match.half = home ? 13 : 12; match.outs = 2
            let original = match.runnerProfiles?[0]
            match.runnerProfiles?[0] = FieldRunnerProfile(speed: 30, own: true, responsiblePitcher: original?.responsiblePitcher, id: original?.id)
            let third = FieldRunnerProfile(speed: 100, responsiblePitcher: MatchPitching.starterID(home: !home), id: "third")
            match.runnerProfiles?[2] = third
            let early = try XCTUnwrap(MatchRunningRules.play(match: match, kind: .steal, id: "running:1", aggressive: true))
            XCTAssertEqual(early.runningEvent?.kind, .rundown); XCTAssertTrue(early.out)
            XCTAssertEqual(early.runs, 1); XCTAssertTrue(early.afterRunners.allSatisfy { $0 == nil })
            try early.validate()
            match.runnerProfiles?[2] = FieldRunnerProfile(speed: 0, responsiblePitcher: third.responsiblePitcher, id: third.id)
            let late = try XCTUnwrap(MatchRunningRules.play(match: match, kind: .steal, id: "running:1", aggressive: true))
            XCTAssertEqual(late.runs, 0); XCTAssertEqual(late.outsAdded, 1)
            XCTAssertTrue(late.runners.allSatisfy { $0.nodes.last!.at <= late.controlAt })
            XCTAssertTrue(late.afterRunners.allSatisfy { $0 == nil }); try late.validate()
        }
    }
    func testDeadBallFairContactAndCompletedInningSuppressRunning() throws {
        var match = ownRunner()
        let before = MatchPitchState(match), original = match.running
        match.pitchFoul(before: before, bunt: false, batter: false, pitcher: false, direct: false)
        match.resolveRunningPitch(before: before, eventCount: 0, fieldCount: 0, homeRunCount: 0, attempted: true)
        XCTAssertEqual(match.running?.events, original?.events)
        for outcome in ["볼넷","사구","홈런","삼진"] {
            var next = ownRunner(); let old = MatchPitchState(next)
            if outcome == "삼진" { next.outs = 2 }
            InplayIntegrationTests().plate(outcome, in: &next)
            next.resolveRunningPitch(before: old, eventCount: 0, fieldCount: 0, homeRunCount: 0, attempted: true)
            XCTAssertTrue(next.running!.events.isEmpty, outcome)
        }
    }
    func testNegativeCountersInvalidRevisionAndForeignReservationAreRejected() throws {
        var match = ownRunner()
        match.playerRecords?.home.batting[0].counts.stolenBases = -1
        XCTAssertThrowsError(try match.validateRunning())
        match.playerRecords?.home.batting[0].counts.stolenBases = 0
        match.running?.reservation = .init(runner: "foreign", half: match.half, order: match.homeOrder, pitch: 0)
        XCTAssertThrowsError(try match.validateRunning())
    }
    func testBothRolesAutomaticAndDirectGamesKeepAllLedgersConsistent() throws {
        for role in PlayerRole.allCases { for home in [true,false] { for seed in 1...12 {
            var match = fresh(role, home: home); match.random = UInt64(seed)
            match.pitchLog = MatchPitchLog(); match.scoutingPerformance = .tracked
            match.settle()
            var commands = 0
            while !match.completed && commands < 600 {
                if role == .pitcher && !match.ownPitcherActive {
                    try match.advance(.automatic)
                } else if match.canPrepareRunning {
                    try match.reserveRunning(seed.isMultiple(of: 2)); try match.advanceRunning()
                } else {
                    let input: MatchInput = role == .pitcher ? .pitch : .swing
                    try match.advance(input, pitchCode: "four-seam", control: match.automaticControl(input, pitchCode: "four-seam"))
                }
                try validate(match); commands += 1
            }
            XCTAssertTrue(match.completed)
            let stored = try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(match))
            XCTAssertEqual(stored, match); try validate(stored)
        } } }
    }
    func testLegacyNilRemainsUnchangedAndCannotAdoptOnReopen() throws {
        var a = InplayIntegrationTests().makeMatch(), b = a
        try a.advance(.automatic); try b.advance(.automatic)
        XCTAssertEqual(a, b); XCTAssertNil(a.running)
        let payload = try JSONEncoder().encode(a)
        var reopened = try JSONDecoder().decode(CareerMatch.self, from: payload)
        reopened.enableRunning(); XCTAssertNil(reopened.running)
        XCTAssertThrowsError(try reopened.reserveRunning(true))
    }
    func testDiskReservationRollbackResumeStaleAndCompletionOnce() throws {
        enum Failure: Error { case injected }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("running-" + UUID().uuidString + ".store")
        let playerID: UUID = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            var draft = PlayerDraft(); draft.name = "주루저장검증"; draft.role = .batter; draft.schoolID = "hs-ref-001"
            let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context, currentLeagueRules: false)
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
            let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            let ready = try readyFromActualGame(record.snapshot())
            record.payload = try JSONEncoder().encode(ready); try context.save()
            let payload = record.payload, revision = record.revision, calendarRevision = calendar.revision, fatigue = player.fatigue
            XCTAssertThrowsError(try CareerMatchStore.running(player: player, state: calendar, record: record,
                revision: revision, reserve: true, in: context, save: { _ in throw Failure.injected }))
            XCTAssertEqual(record.payload, payload); XCTAssertEqual(record.revision, revision)
            XCTAssertEqual(calendar.revision, calendarRevision); XCTAssertEqual(player.fatigue, fatigue)
            _ = try CareerMatchStore.running(player: player, state: calendar, record: record, revision: revision, reserve: true, in: context)
            XCTAssertThrowsError(try CareerMatchStore.running(player: player, state: calendar, record: record, revision: revision, reserve: false, in: context))
            XCTAssertNotNil(try record.snapshot().running?.reservation)
            return player.id
        }
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first { $0.id == playerID })
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record = try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first)
            let resumed = try record.snapshot()
            XCTAssertTrue(resumed.canPrepareRunning); XCTAssertEqual(resumed.running?.reservation, resumed.runningReservation)
            let payload = record.payload, revision = record.revision
            XCTAssertThrowsError(try CareerMatchStore.running(player: player, state: calendar, record: record, revision: revision,
                in: context, save: { _ in throw Failure.injected }))
            XCTAssertEqual(record.payload, payload); XCTAssertEqual(record.revision, revision)
            var expected = resumed; try expected.advanceRunning()
            if expected.completed {
                expected.projectFeedback = MatchProjectFeedback(version:1,activityKey:record.key,date:record.gameDate,project:nil,clubName:nil,before:nil,after:nil)
            }
            _ = try CareerMatchStore.running(player: player, state: calendar, record: record, revision: revision, in: context)
            XCTAssertEqual(try record.snapshot(), expected)
            if !record.completed {
                try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context)
            }
            let completedPayload = record.payload, fatigue = player.fatigue, completedRevision = calendar.revision
            let reopened = try CareerMatchStore.start(player: player, state: calendar, in: context)
            XCTAssertEqual(reopened.payload, completedPayload)
            XCTAssertEqual(player.fatigue, fatigue); XCTAssertEqual(calendar.revision, completedRevision)
            XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context))
        }
    }

    func testPrepareP08NormalEntryFixtures() throws {
        var report: [[String: String]] = []
        for (index, role) in [PlayerRole.batter,.batter,.pitcher,.batter].enumerated() {
            let session = String(format: "B008B008-2026-4124-8000-%012d", index + 1)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-career-" + session + ".store")
            for suffix in ["","-wal","-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            var draft = PlayerDraft(); draft.name = "주루연결검증"; draft.role = role; draft.schoolID = "hs-ref-001"
            let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context, currentLeagueRules: false)
            if role == .batter { player.speed = index == 1 ? 15 : 100; try context.save() }
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
            let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            let initial = try record.snapshot()
            var ready = initial
            if role == .batter { ready = try readyFromActualGame(initial,early:true) }
            else {
                var found: CareerMatch?
                for seed in 1...64 where found == nil {
                    var sample = initial; sample.random = UInt64(seed) * 1_099_511_628_211
                    for _ in 0..<150 {
                        if sample.runningEligible && !sample.offense && sample.ownPitcherActive { found = sample; break }
                        if sample.completed || !sample.ownPitcherActive { break }
                        try sample.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.45))
                    }
                }
                ready = try XCTUnwrap(found)
            }
            var selected: CareerMatch?
            for seed in 1...20_000 where selected == nil {
                var before = ready; before.random = UInt64(seed) * 1_099_511_628_211
                var after = before
                if role == .batter {
                    try after.reserveRunning(true); try after.advanceRunning()
                    if let event = after.running?.events.dropFirst(before.running?.events.count ?? 0).first,
                       event.play.runningEvent?.kind == (index == 1 ? .rundown : .steal), event.play.runners.first?.profile.own == true { selected = before }
                } else if before.coachPickoff { selected = before }
            }
            let source = try XCTUnwrap(selected)
            record.payload = try JSONEncoder().encode(source); try context.save(); _ = try record.snapshot()
            report.append(["session":session,"role":role.rawValue,"fixture":record.fixtureID,"state":source.inningLabel])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "P08 native entry fixtures"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testWalkOffStopsBeforeLaterTagAndDoesNotCreditAStealToReturningRunner() throws {
        var match = ownRunner(); match.half = 17; match.outs = 2; match.homeScore = 2; match.awayScore = 2
        let original = match.runnerProfiles?[0]
        match.runnerProfiles?[0] = FieldRunnerProfile(speed:30,own:true,responsiblePitcher:original?.responsiblePitcher,id:original?.id)
        match.runnerProfiles?[2] = FieldRunnerProfile(speed:100,responsiblePitcher:MatchPitching.starterID(home:false),id:"third")
        let play = try XCTUnwrap(MatchRunningRules.play(match:match,kind:.steal,id:"running:1",aggressive:true))
        XCTAssertNotNil(play.runningEvent?.walkOffAt); XCTAssertEqual(play.outsAdded,0); XCTAssertFalse(play.out)
        XCTAssertEqual(play.runs,1); XCTAssertEqual(play.duration,play.decisionAt + 0.4)
        XCTAssertTrue(play.ball.allSatisfy { $0.at <= play.decisionAt })
        XCTAssertTrue(play.runners.allSatisfy { !$0.out && $0.nodes.allSatisfy { $0.at <= play.decisionAt } })
        try play.validate()
    }
    func testRunningPreparationSmallAndLargeTypeUseNativeLayout() throws {
        for width in [320.0,390.0] { for large in [false,true] { for selected in [false,true] {
            let view = MatchRunningPreparationBar(selected:selected,countdown:5,paused:large,locked:false,reserve:{},next:{})
                .padding(8).background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .environment(\.dynamicTypeSize,large ? .accessibility5:.large)
            let host = UIHostingController(rootView:view)
            let fitting = host.sizeThatFits(in:CGSize(width:width,height:800))
            XCTAssertLessThanOrEqual(fitting.width,width + 0.5)
            XCTAssertGreaterThanOrEqual(fitting.height,44)
            XCTAssertLessThan(fitting.height,568)
            host.view.frame=CGRect(x:0,y:0,width:width,height:fitting.height)
            host.view.setNeedsLayout();host.view.layoutIfNeeded()
            let image=UIGraphicsImageRenderer(bounds:host.view.bounds).image { _ in
                host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true)
            }
            let attachment=XCTAttachment(image:image);attachment.name="P08 native preparation \(Int(width)) \(large ? "large":"normal") \(selected ? "reserved":"waiting")";attachment.lifetime = .keepAlways;add(attachment)
        } } }
    }

    func testRunningCoachDecisionDoesNotMovePreviouslyAimedPitch() throws {
        var match = fresh(.pitcher,home:true)
        InplayIntegrationTests().plate("볼넷",in:&match)
        for seed in 1...100 {
            var sample=match;sample.random=UInt64(seed)
            if sample.coachPickoff {continue}
            let delivery=sample.delivery(pitchCode:"four-seam")
            try sample.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:ManualMatchRules.releaseCenter))
            let receipt=try XCTUnwrap(sample.lastManual)
            XCTAssertEqual(receipt.x,delivery.x,accuracy:0.000001)
            XCTAssertEqual(receipt.y,delivery.y,accuracy:0.000001)
            XCTAssertEqual(receipt.speed,delivery.speed)
            try validate(sample)
            return
        }
        XCTFail("견제 대신 투구하는 고정 사례가 필요합니다.")
    }
    func testNewRunningEnvironmentSeparatesReferenceFromOldReports() throws {
        let modern=ScoutingReferenceSimulation.fixture(role:.batter,position:"SS",values:PlayerArchetype.choices(for:.batter)[0].values,
            seed:76,home:true,tracked:true,battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1)
        var legacy=modern;legacy.running=nil
        XCTAssertTrue(modern.scoutingEnvironment?.contains("-running1-") == true)
        XCTAssertFalse(legacy.scoutingEnvironment?.contains("-running1-") == true)
        let reference=ScoutingReferenceSimulation.fixture(role:.batter,position:"SS",values:PlayerArchetype.choices(for:.batter)[0].values,
            seed:77,home:true,tracked:true,battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1)
        XCTAssertNotNil(reference.running)
    }

    func testPitchFlightAndRunningUseSameVelocityScale() throws {
        let match=ownRunner()
        let fast=try XCTUnwrap(MatchRunningRules.play(match:match,kind:.steal,id:"running:1",pitchDuration:MatchDelivery(x:0.5,y:0.5,speed:160).flightDuration,aggressive:true))
        let slow=try XCTUnwrap(MatchRunningRules.play(match:match,kind:.steal,id:"running:1",pitchDuration:MatchDelivery(x:0.5,y:0.5,speed:100).flightDuration,aggressive:true))
        XCTAssertLessThan(fast.pickupAt,slow.pickupAt)
        XCTAssertEqual(fast.runners.first?.nodes.first,slow.runners.first?.nodes.first)
        XCTAssertEqual(PitchFlightPresentation(delivery:MatchDelivery(x:0.5,y:0.5,speed:145)).flightDuration,MatchDelivery(x:0.5,y:0.5,speed:145).flightDuration)
    }

    func testCommittedRunningReplayDoesNotBorrowLaterAutomaticPlay() throws {
        let previous=ownRunner()
        var updated=previous
        let before=MatchPitchState(previous)
        let play=try XCTUnwrap(MatchRunningRules.play(match:previous,kind:.pickoff,id:"running:1"))
        updated.applyRunning(play,before:before,movement:before)
        XCTAssertEqual(MatchRunningEvent.committedAction(previous:previous,updated:updated)?.id,"running:1")
        var earlier=previous;earlier.homeOrder -= 1
        XCTAssertNil(MatchRunningEvent.committedAction(previous:earlier,updated:updated))
        let state=updated
        _ = updated.running?.events.first?.before.displayMatch(updated)
        _ = updated.running?.events.first?.after.displayMatch(updated)
        XCTAssertEqual(updated,state)
    }

    func testImportedRunningIndicesAreRejectedBeforeArrayAccess() throws {
        let original=ownRunner()
        var stored=original
        let before=MatchPitchState(original)
        let valid=try XCTUnwrap(MatchRunningRules.play(match:original,kind:.pickoff,id:"running:1"))
        stored.applyRunning(valid,before:before,movement:before)
        let event=try XCTUnwrap(stored.running?.events.first)
        var broken=valid
        let runner=valid.runners[0]
        broken.runners[0]=DetailedRunner(from:999,destination:runner.destination,profile:runner.profile,nodes:runner.nodes,out:runner.out,retiredAt:runner.retiredAt)
        stored.running?.events[0]=MatchRunningEvent(index:event.index,pitch:event.pitch,before:event.before,movementBefore:event.movementBefore,after:event.after,play:broken)
        XCTAssertThrowsError(try stored.validateRunning())
        XCTAssertNoThrow(try original.playerRecords?.validate(match:original))
    }

    func testRunningDisplayAdvancesAtCatchHomeTouchAndTagWithoutAnotherJudgment() throws {
        var source=ownRunner();source.half=13;source.outs=2;source.balls=1
        let runner=source.runnerProfiles?[0]
        source.runnerProfiles?[0] = FieldRunnerProfile(speed:30,own:true,responsiblePitcher:runner?.responsiblePitcher,id:runner?.id)
        source.runnerProfiles?[2] = FieldRunnerProfile(speed:100,responsiblePitcher:MatchPitching.starterID(home:false),id:"third")
        let before=MatchPitchState(source)
        source.balls=2
        let movement=MatchPitchState(source)
        let play=try XCTUnwrap(MatchRunningRules.play(match:source,kind:.steal,id:"running:1",aggressive:true))
        XCTAssertEqual(play.runs,1)
        source.homeScore += 1;source.half += 1;source.outs=0;source.balls=0;source.strikes=0;source.runnerProfiles=[nil,nil,nil];source.bases=[false,false,false]
        let event=MatchRunningEvent(index:1,pitch:1,before:before,movementBefore:movement,after:MatchPitchState(source),play:play)
        let goal=try XCTUnwrap(play.runners.first { $0.from == 3 }).arrival
        XCTAssertEqual(event.displayMatch(at:play.pickupAt - 0.001,saved:source).balls,1)
        XCTAssertEqual(event.displayMatch(at:play.pickupAt,saved:source).balls,2)
        XCTAssertEqual(event.displayMatch(at:goal - 0.001,saved:source).homeScore,before.home)
        let touched=event.displayMatch(at:goal,saved:source)
        XCTAssertEqual(touched.homeScore,before.home + 1);XCTAssertEqual(touched.outs,2)
        let tagged=event.displayMatch(at:play.controlAt,saved:source)
        XCTAssertEqual(tagged.half,14);XCTAssertEqual(tagged.outs,0);XCTAssertTrue(tagged.bases.allSatisfy { !$0 })
        XCTAssertTrue(event.displayTimes.contains(goal))
    }

}
