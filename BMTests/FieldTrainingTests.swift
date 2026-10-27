import XCTest
import SwiftData
import SwiftUI
import Darwin
import SpriteKit
@testable import BM

@MainActor final class FieldTrainingTests: XCTestCase {
    func testV30ThrowPhasesKeepTheJudgedEndpointAndWaitThroughReceive() throws {
        XCTAssertEqual(TrainingFieldMotion.flight(0.1),0)
        XCTAssertEqual(TrainingFieldMotion.flight(TrainingFieldMotion.arrival),1)
        XCTAssertFalse(TrainingFieldMotion.readyForFeedback(elapsed:TrainingFieldMotion.duration-0.001))
        XCTAssertTrue(TrainingFieldMotion.readyForFeedback(elapsed:TrainingFieldMotion.duration))
        for index in 0..<5 {
            var training=CareerTraining(playerID:UUID(),date:"2026-04-01",role:"batter",pitchCode:nil,before:60,fatigue:24,age:16,calendarRevision:0,kind:.arm)
            training.scores=Array(repeating:50,count:index)
            let base=TrainingRules.throwBase(index),target=TrainingRules.basePoint(base)
            let angle=(atan2(target.y-0.63,target.x-0.5)*180 / .pi+360).truncatingRemainder(dividingBy:360)
            let force=hypot(target.x-0.5,target.y-0.63)/0.55*100
            let endpoint=TrainingRules.throwEndpoint(angle:angle,force:force)
            XCTAssertEqual(TrainingFieldArt.point(endpoint).x,TrainingFieldArt.point(target).x,accuracy:0.00001)
            XCTAssertEqual(TrainingFieldArt.point(endpoint).y,TrainingFieldArt.point(target).y,accuracy:0.00001)
            try training.attempt(TrainingInput(force:force,angle:angle,base:base));XCTAssertEqual(training.scores.last,100)
            var wrong=training;wrong.scores.removeLast()
            try wrong.attempt(TrainingInput(force:force,angle:angle,base:base == 1 ? 2:1));XCTAssertEqual(wrong.scores.last,0)
        }
    }
    func testV29PreparedPitchFlightWaitsForActualFlightAndReceiveThenCompletesOnce() throws {
        let scene = LocationDrillScene(size: CGSize(width: 320,height: 320))
        scene.configure(kind: .control,appearance: PlayerAppearance(),number: 8,hand: "left")
        scene.prepareDrill(phase: 0.85)
        let point = TrainingTarget(x: 0.5,y: 0.5)
        var callbacks = 0
        scene.play(LocationDrillReplay(kind: .control,target: point,input: point,score: 100),at: 100,
                   preparedRelease: true,flightDuration: 0.9,curve: 22) { callbacks += 1 }
        let ball = try XCTUnwrap(scene.childNode(withName:"locationBall")), release = ball.position
        scene.advance(at:100.8); XCTAssertEqual(callbacks,0); XCTAssertNotEqual(ball.position,release)
        scene.advance(at:100.9); XCTAssertEqual(callbacks,0)
        let destination = LocationDrillReplay.point(point,kind:.control)
        XCTAssertEqual(ball.position.x,destination.x,accuracy:0.0001)
        scene.advance(at:101.201); XCTAssertEqual(callbacks,1)
        scene.advance(at:110); XCTAssertEqual(callbacks,1)
    }
    func testV28LocationProjectionAndFeedbackKeepOriginalDistanceScores() throws {
        for kind in [TrainingKind.control, .defense] {
            for value in [0.0, 0.25, 0.5, 0.75, 1] {
                let input = TrainingTarget(x: value, y: 1 - value)
                let inverse = LocationDrillReplay.input(at: LocationDrillReplay.point(input, kind: kind), kind: kind)
                XCTAssertEqual(inverse.x, input.x, accuracy: 0.000001); XCTAssertEqual(inverse.y, input.y, accuracy: 0.000001)
            }
            var round = CareerTraining(playerID: UUID(), date: "2026-04-01", role: "pitcher", pitchCode: nil, before: 60, fatigue: 0, age: 16, calendarRevision: 0, kind: kind)
            let original = round, target = round.targets[0], input = TrainingInput(x: target.x + 0.1, y: target.y)
            try round.attempt(input)
            let score = try XCTUnwrap(round.scores.last)
            XCTAssertEqual(score, Int((max(0, 1 - 0.1 / (kind == .control ? 0.3 : 0.55)) * 100).rounded()))
            let display = LocationDrillReplay(kind: kind, target: target, input: TrainingTarget(x: input.x, y: input.y), score: score)
            XCTAssertTrue(display.comparison.contains("◇ 목표")); XCTAssertTrue(display.comparison.contains("+"))
            XCTAssertEqual(original.scores, []); XCTAssertEqual(original.targets, round.targets)
        }
    }

    func testV28LocationPlaybackEndsAtJudgedCoordinatesAndCompletesOnlyOnceAfterReceive() throws {
        for kind in [TrainingKind.control, .defense] {
            let scene = LocationDrillScene(size: CGSize(width: 320, height: 320))
            scene.configure(kind: kind, appearance: PlayerAppearance(), number: 27, hand: "left")
            let target = TrainingTarget(x: 0.3, y: 0.6), input = TrainingTarget(x: 0.7, y: 0.4)
            let replay = LocationDrillReplay(kind: kind, target: target, input: input, score: 0)
            var completions = 0
            scene.play(replay, at: 100) { completions += 1 }
            scene.advance(at: 100 + LocationDrillReplay.windup + LocationDrillReplay.flight)
            XCTAssertEqual(completions, 0); XCTAssertFalse(scene.finished)
            scene.advance(at: 100 + LocationDrillReplay.duration + 0.001)
            XCTAssertEqual(completions, 1); XCTAssertTrue(scene.finished)
            let judged = LocationDrillReplay.point(kind == .control ? input : target, kind: kind)
            let ball = try XCTUnwrap(scene.childNode(withName: "locationBall"))
            if kind == .control {
                XCTAssertEqual(ball.position.x, judged.x, accuracy: 0.0001)
                XCTAssertEqual(ball.position.y, 320 - judged.y, accuracy: 0.0001)
            } else {
                let catchFacing = FieldFacing.direction(dx: 160 - judged.x, dy: 286 - judged.y)
                let offset = try XCTUnwrap(FieldRasterArt.contact(FieldSpriteMotion(facing: catchFacing, stage: .catchBall, progress: 1, chestCatch: true), kind: "fielder", left: true, hand: false))
                XCTAssertEqual(ball.position.x, judged.x + offset.x * 1.7, accuracy: 0.0001)
                XCTAssertEqual(ball.position.y, 320 - judged.y - offset.y * 1.7, accuracy: 0.0001)
            }
            let actor = try XCTUnwrap(scene.childNode(withName: "locationActor"))
            if kind == .defense {
                let chosen = LocationDrillReplay.point(input, kind: kind)
                XCTAssertEqual(actor.position.x, chosen.x, accuracy: 0.0001); XCTAssertEqual(actor.position.y, 320 - chosen.y, accuracy: 0.0001)
            }
            scene.advance(at: 150); XCTAssertEqual(completions, 1)
            scene.play(replay, at: 200) { completions += 1 }; scene.cancel(); scene.advance(at: 250)
            XCTAssertEqual(completions, 1)
        }
    }
    func testSessionMissionUsesSavedScoresAndDoesNotRewardFailuresOrLongestStreakTwice() {
        let mixed = TrainingMissionProgress(kind: .contact, scores: [75, 80, 0, 100, 74])
        XCTAssertEqual(mixed.successes, 3); XCTAssertTrue(mixed.achieved); XCTAssertEqual(mixed.bestStreak, 2)
        XCTAssertFalse(TrainingMissionProgress(kind: .contact, scores: [74,74,74,74,74]).achieved)
        XCTAssertFalse(TrainingMissionProgress(kind: .mental, scores: [100,100,100,0,0]).achieved)
        XCTAssertTrue(TrainingMissionProgress(kind: .discipline, scores: [100,100,0,100,100]).achieved)
        XCTAssertEqual(TrainingMissionProgress(kind: .pitch, scores: [75,75,75]).bestStreak, 3)
    }
    func testSessionCoachMatchesActualPitchPowerPlacementAndWrongBase() throws {
        func round(_ kind: TrainingKind) -> CareerTraining {
            CareerTraining(playerID: UUID(), date: "2026-04-01", role: kind == .pitch ? "pitcher" : "batter",
                pitchCode: kind == .pitch ? "slider" : nil, before: 60, fatigue: 0, age: 16, calendarRevision: 0, kind: kind)
        }
        XCTAssertTrue(TrainingSessionGuide.note(round: round(.pitch), input: TrainingInput(release: 0.2), score: 0).next.contains("늦게"))
        XCTAssertTrue(TrainingSessionGuide.note(round: round(.pitch), input: TrainingInput(release: 0.95), score: 0).next.contains("일찍"))
        XCTAssertTrue(TrainingSessionGuide.note(round: round(.power), input: TrainingInput(force: 100, angle: 45), score: 0).next.contains("줄여"))
        var defense = round(.defense)
        let target = defense.targets[0]
        XCTAssertTrue(TrainingSessionGuide.note(round: defense, input: TrainingInput(x: target.x - 0.1, y: target.y), score: 50).next.contains("오른쪽"))
        XCTAssertTrue(TrainingSessionGuide.note(round: round(.arm), input: TrainingInput(force: 50, angle: 0, base: 2), score: 0).observation.contains("베이스"))
        let original = defense
        _ = TrainingSessionGuide.note(round: defense, input: TrainingInput(x: target.x, y: target.y), score: 100)
        XCTAssertEqual(defense, original)
        try defense.attempt(TrainingInput(x: target.x, y: target.y))
        XCTAssertEqual(defense.scores, [100])
    }
    func testAllSessionCoachKindsUseTheOriginalTargetAndKeepRawScoringUnchanged() throws {
        for kind in TrainingKind.allCases {
            let role = [TrainingKind.pitch,.velocity,.control,.stuff,.stamina].contains(kind) ? "pitcher" : "batter"
            var round = CareerTraining(playerID: UUID(), date: "2026-04-01", role: role, pitchCode: kind == .pitch ? "four-seam" : nil,
                before: 60, fatigue: 0, age: 16, calendarRevision: 0, kind: kind)
            let untouched = round
            let input = TrainingInput(x: 0.5, y: 0.5, timing: kind == .contact ? 0.82 : nil, release: kind == .pitch ? 0.68 : nil)
            let note = TrainingSessionGuide.note(round: round, input: input, score: 50)
            XCTAssertFalse(note.observation.isEmpty); XCTAssertFalse(note.next.isEmpty); XCTAssertEqual(round, untouched)
            round.scores = [100,0,75]
            let encoded = try JSONEncoder().encode(round), restored = try JSONDecoder().decode(CareerTraining.self, from: encoded)
            XCTAssertEqual(TrainingMissionProgress(kind: kind, scores: restored.scores),TrainingMissionProgress(kind: kind, scores: round.scores))
        }
    }
    private func setup(_ context: ModelContext, role: PlayerRole = .batter, date: String = "2026-04-01") throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = "필드훈련"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
        player.gameDate = date; try context.save()
        return (player, try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first))
    }
    private func input(_ training: CareerTraining) -> TrainingInput {
        let target = training.targets[training.scores.count]
        switch training.selectedKind {
        case .speed: return TrainingInput(footfalls: (0..<16).map { $0.isMultiple(of: 2) ? .left : .right })
        case .defense: return TrainingInput(x: target.x, y: target.y)
        default:
            let base = TrainingRules.throwBase(training.scores.count), target = TrainingRules.basePoint(TrainingRules.throwBase(training.scores.count))
            let angle = atan2(target.y - 0.63, target.x - 0.5) * 180 / .pi
            return TrainingInput(force: hypot(target.x - 0.5, target.y - 0.63) / 0.55 * 100, angle: angle < 0 ? angle + 360 : angle, base: base)
        }
    }
    private func advance(_ player: CareerPlayer, _ state: CareerCalendarState, _ record: CareerTrainingRecord, _ context: ModelContext) throws {
        try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision, input: input(record.snapshot()), in: context)
    }
    func testAlternatingStepsIgnoreRepeatedFootAndScoreZeroPartialAndCap() throws {
        XCTAssertEqual(TrainingRules.steps([.left,.left,.right,.right,.left]), 3)
        for (feet, score) in [([],0), ([SprintFoot.left,.right,.left,.right],25), ((0..<32).map { $0.isMultiple(of: 2) ? SprintFoot.left : .right },100)] {
            var training = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "batter", pitchCode: nil, before: 72, fatigue: 24, age: 16, calendarRevision: 1, kind: .speed)
            try training.attempt(TrainingInput(footfalls: feet)); XCTAssertEqual(training.scores, [score])
        }
    }
    func testDefenseAndThrowScorePositionBaseDirectionAndForce() throws {
        for kind in [TrainingKind.defense,.arm] {
            var training = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "pitcher", pitchCode: nil, before: 60, fatigue: 52, age: 16, calendarRevision: 1, kind: kind)
            for _ in 0..<5 { try training.attempt(input(training)) }
            XCTAssertEqual(training.scores, [100,100,100,100,100])
        }
        var arm = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "batter", pitchCode: nil, before: 68, fatigue: 24, age: 16, calendarRevision: 1, kind: .arm)
        try arm.attempt(TrainingInput(force: 0.28 / 0.55 * 100, angle: 0, base: 2))
        XCTAssertEqual(arm.scores, [0])
        for bad in [TrainingInput(force: 101, angle: 0, base: 1), TrainingInput(force: 50, angle: .nan, base: 1), TrainingInput(force: 50, angle: 361, base: 1), TrainingInput(force: 50, angle: 0, base: 0), TrainingInput(timing: 0.82)] {
            XCTAssertThrowsError(try arm.attempt(bad))
        }
        XCTAssertEqual(arm.scores, [0])
    }
    func testBothRolesAllThreeGoalsGrowOnlyChosenStatAndNewMatchSnapshotsThem() throws {
        for role in PlayerRole.allCases { for kind in [TrainingKind.speed,.defense,.arm] {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, state) = try setup(context, role: role)
            let before = [player.speed, player.defense, player.arm], pitches = Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) }), fatigue = player.fatigue
            let record = try CareerTrainingStore.start(player: player, state: state, kind: kind, in: context)
            XCTAssertEqual(record.rulesVersion, "native-training-v3")
            for _ in 0..<5 { try advance(player, state, record, context) }
            let after = try record.snapshot().after
            XCTAssertEqual([player.speed,player.defense,player.arm], [kind == .speed ? after : before[0],kind == .defense ? after : before[1],kind == .arm ? after : before[2]])
            XCTAssertEqual([player.contact,player.power,player.discipline], [65,75,60]); XCTAssertEqual(Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) }), pitches)
            XCTAssertEqual(player.fatigue, min(100,fatigue+6)); XCTAssertTrue(state.hasAction(on: player.gameDate))
            XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context))
            XCTAssertThrowsError(try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:record.revision,input:TrainingInput(),in:context))
            XCTAssertEqual(try CareerTrainingStore.start(player: player,state: state,kind: .contact,in: context).key,record.key)
            let game = try CareerMatchStore.start(player: player,state: state,in: context)
            let snapshot = try game.snapshot()
            XCTAssertEqual(snapshot.fieldStats?.speed, player.speed); XCTAssertEqual(snapshot.fieldStats?.defense,player.defense); XCTAssertEqual(snapshot.fieldStats?.arm,player.arm)
            XCTAssertEqual(snapshot.fieldStats?.position, role == .pitcher ? "P" : player.positionRaw)
        } }
    }
    func testDiskResumeAllFieldKindsPreservesTasksAndPaysOnlyOnce() throws {
        for kind in [TrainingKind.speed,.defense,.arm] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("field.store")
            let payload = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let (player,state) = try setup(context,role:.pitcher,date:"2026-04-02")
                let record = try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context)
                for _ in 0..<2 { try advance(player,state,record,context) }
                XCTAssertThrowsError(try CalendarProgression.rest(player:player,state:state,revision:state.revision,in:context))
                XCTAssertThrowsError(try CalendarProgression.advanceDay(player:player,state:state,revision:state.revision,in:context))
                return record.payload
            }
            try autoreleasepool {
                let container = try CareerStore.makeContainer(url:url),context=container.mainContext
                let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first), state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record = try CareerTrainingStore.start(player:player,state:state,pitchCode:"four-seam",in:context)
                XCTAssertEqual(record.payload,payload); XCTAssertEqual(try record.snapshot().selectedKind,kind)
                for _ in 0..<3 { try advance(player,state,record,context) }
            }
            let container = try CareerStore.makeContainer(url:url),context=container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record = try CareerTrainingStore.start(player:player,state:state,in:context)
            XCTAssertTrue(record.completed); XCTAssertEqual(player.fatigue,58); XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()),1)
            XCTAssertEqual(try record.snapshot().scores,[100,100,100,100,100])
        }
    }
    func testFieldAttemptFailureRollbackAndRetryAtEveryBoundary() throws {
        enum Injected:Error { case failure }
        for kind in [TrainingKind.speed,.defense,.arm] {
            let container = try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            let(player,state) = try setup(context,date:"2026-04-02")
            XCTAssertThrowsError(try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context,save:{_ in throw Injected.failure}))
            XCTAssertNil(try CareerTrainingStore.record(player:player,in:context))
            let record = try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context)
            for count in 0..<5 {
                let payload=record.payload,rev=record.revision,calendarRev=state.revision,old=[player.speed,player.defense,player.arm]
                let input=try input(record.snapshot())
                XCTAssertThrowsError(try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:rev,input:input,in:context,save:{_ in throw Injected.failure}))
                XCTAssertEqual(record.payload,payload); XCTAssertEqual(state.revision,calendarRev); XCTAssertEqual(record.revision,rev)
                XCTAssertEqual([player.speed,player.defense,player.arm],old); XCTAssertEqual(player.fatigue,24); XCTAssertNil(state.actionDate)
                try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:rev,input:input,in:context)
                XCTAssertEqual(try record.snapshot().scores.count,count+1)
                XCTAssertThrowsError(try CareerTrainingStore.attempt(player:player,state:state,record:record,revision:rev,input:input,in:context))
            }
            XCTAssertEqual(player.fatigue,30); XCTAssertTrue(record.completed)
        }
    }
    func testFirstBaseTimesRespondIndependentlyToAllThreeStatsAndTieIsSafe() {
        let baseline=MatchFieldRules.firstBase(runnerSpeed:60,fielderSpeed:60,defense:60,arm:60,chase:12,distance:30,ownDefense:false)
        let speed=MatchFieldRules.firstBase(runnerSpeed:100,fielderSpeed:60,defense:60,arm:60,chase:12,distance:30,ownDefense:false)
        let defense=MatchFieldRules.firstBase(runnerSpeed:60,fielderSpeed:60,defense:100,arm:60,chase:12,distance:30,ownDefense:true)
        let arm=MatchFieldRules.firstBase(runnerSpeed:60,fielderSpeed:60,defense:60,arm:100,chase:12,distance:30,ownDefense:true)
        let chase=MatchFieldRules.firstBase(runnerSpeed:60,fielderSpeed:100,defense:60,arm:60,chase:12,distance:30,ownDefense:true)
        XCTAssertLessThan(speed.runnerTime,baseline.runnerTime); XCTAssertEqual(speed.ballTime,baseline.ballTime)
        for play in [defense,arm,chase] { XCTAssertLessThan(play.ballTime,baseline.ballTime); XCTAssertEqual(play.runnerTime,baseline.runnerTime) }
        XCTAssertTrue(MatchFieldPlay(runnerTime:1,ballTime:1,ownDefense:false).safe)
    }
    private func game(_ seed:Int,role:String="batter",speed:Double=60,defense:Double=60,arm:Double=60) -> CareerMatch {
        var game=CareerMatch(random:UInt64(seed),isHome:true,role:role,appearance:true,contact:65,power:0,discipline:60,mastery:["four-seam":72])
        game.half=role=="batter" ? 1:0; game.controlVersion=2; game.trainingEffectsVersion=1
        game.fieldStats=MatchFieldStats(speed:speed,defense:defense,arm:arm,position:role=="pitcher" ? "P":"CF")
        return game
    }
    func testRunnerGrowthChangesActualFairBallHitsWithSameInputs() throws {
        var lowHits=0,highHits=0
        for seed in 0..<500 {
            for speed in [0.0,100.0] {
                var state=game(seed,speed:speed);let delivery=state.delivery()
                try state.advance(.swing,control:ManualMatchInput(x:delivery.x,y:delivery.y,timing:0.82))
                if speed==0 { lowHits+=state.line.hits } else { highHits+=state.line.hits }
            }
        }
        XCTAssertGreaterThan(highHits,lowHits)
    }
    func testOwnPitcherDefenseAndArmChangeActualOutcomes() throws {
        for kind in [TrainingKind.defense,.arm] {
            var lowHits=0,highHits=0,opportunities=0
            for seed in 0..<1000 {
                for stat in [0.0,100.0] {
                    var state=game(seed,role:"pitcher",defense:kind == .defense ? stat:60,arm:kind == .arm ? stat:60)
                    try state.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
                    if state.lastFieldPlay?.ownDefense==true { opportunities+=1 }
                    if stat==0 { lowHits+=state.line.hitsAllowed } else { highHits+=state.line.hitsAllowed }
                }
            }
            XCTAssertGreaterThan(opportunities,0); XCTAssertLessThan(highHits,lowHits)
        }
    }
    func testFieldSnapshotPreservesReplayAndLegacyGamesDoNotAcquireEffects() throws {
        for role in ["batter","pitcher"] {
            for seed in 0..<12 {
                var automatic=game(seed,role:role),manual=automatic
                try automatic.advance(.automatic)
                while !manual.completed { try manual.advance(role=="batter" ? .swing:.pitch,pitchCode:role=="batter" ? nil:"four-seam") }
                XCTAssertEqual(manual,automatic)
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(automatic)),automatic)
            }
        }
        var old=game(42);old.fieldStats=nil
        let payload=try JSONEncoder().encode(old)
        var restored=try JSONDecoder().decode(CareerMatch.self,from:payload)
        XCTAssertNil(restored.fieldStats);try restored.advance(.automatic);XCTAssertNil(restored.lastFieldPlay)
    }
    private func detailed(_ x:Double = -16,_ y:Double = 37,speed:Double=60,defense:Double=60,arm:Double=60,
                          before:[FieldRunnerProfile?]=[nil,nil,nil],outs:Int=0,traits:[PlayerTrait]=[],flight:Double=1) -> MatchDetailedPlay {
        DetailedFieldRules.resolve(half:0,order:0,landing:FieldPoint(x:x,y:y),flight:flight,runners:before,
            batter:FieldRunnerProfile(speed:speed,traits:traits,own:true),outs:outs,
            stats:MatchFieldStats(version:3,speed:60,defense:defense,arm:arm,position:"SS",activeTraits:traits,positionMastery:60),defending:true,ownBatter:false)
    }
    func testDetailedRaceUsesIndependentTimesSpeedAndSingleDoubleDecisions() throws {
        let slow=detailed(speed:0),fast=detailed(speed:100)
        XCTAssertEqual(slow.fielder,5);XCTAssertEqual(slow.targetBase,1)
        XCTAssertEqual(slow.runnerAt!,0.52+27.43/5.5,accuracy:0.000001)
        let expectedPickup=0.34+0.1+sqrt(40)/5.8+0.2
        XCTAssertEqual(slow.pickupAt,expectedPickup,accuracy:0.000001)
        let expectedControl=expectedPickup+0.39+hypot(16+DetailedFieldRules.diagonal,37-DetailedFieldRules.diagonal)/28.8
        XCTAssertEqual(slow.controlAt,expectedControl,accuracy:0.000001)
        XCTAssertTrue(slow.out);XCTAssertEqual(slow.hitBases,0)
        XCTAssertFalse(fast.out);XCTAssertEqual(fast.hitBases,1)
        let deepSlow=detailed(-45,85,speed:0,flight:3.5),deepFast=detailed(-45,85,speed:100,flight:3.5)
        XCTAssertEqual(deepSlow.hitBases,1);XCTAssertEqual(deepFast.hitBases,2)
        XCTAssertEqual(deepSlow.afterRunners[0]?.speed,0);XCTAssertEqual(deepFast.afterRunners[1]?.speed,100)
        try slow.validate();try fast.validate();try deepFast.validate()
    }
    func testDetailedAbilityAndTraitsApplyToTheActualHandlerOnly() throws {
        let low=detailed(defense:0,arm:0),high=detailed(defense:100,arm:100)
        XCTAssertEqual(low.fielder,5);XCTAssertEqual(high.fielder,5)
        XCTAssertLessThan(high.pickupAt,low.pickupAt);XCTAssertLessThan(high.controlAt,low.controlAt)
        let active=detailed(traits:[.strongArm,.safeHands,.cheetah]),plain=detailed()
        XCTAssertLessThan(active.controlAt,plain.controlAt);XCTAssertTrue(active.ownDefense)
        XCTAssertEqual(Set(active.appliedTraits),Set([.strongArm,.safeHands,.cheetah]))
        let other=detailed(40,70,traits:[.strongArm,.safeHands,.cheetah],flight:2.5)
        XCTAssertFalse(other.ownDefense);XCTAssertTrue(other.appliedTraits.isEmpty)
        let none=detailed(40,70,flight:2.5)
        XCTAssertEqual(other.controlAt,none.controlAt)
    }
    func testDetailedAllOccupanciesNoCollisionAndSingleThrowForceTagThirdOut() throws {
        var targets=Set<Int>(),forceCount=0,tagCount=0,thirdForce=0
        for mask in 0..<8 {
            let before=(0..<3).map { mask & (1 << $0) != 0 ? FieldRunnerProfile(speed:60) : nil }
            for outs in 0...2 {
                for x in stride(from:-40.0,through:40.0,by:20) {
                    for y in [15.0,30,55,85] {
                        let p=detailed(x,y,before:before,outs:outs,flight:y/25)
                        try p.validate();targets.insert(p.targetBase)
                        XCTAssertEqual(p.out,p.runnerAt.map { p.controlAt < $0 } ?? false)
                        let bases=p.runners.filter { !$0.out && (1...3).contains($0.destination) }.map(\.destination)
                        XCTAssertEqual(Set(bases).count,bases.count)
                        XCTAssertEqual(p.runners.count,mask.nonzeroBitCount+1)
                        XCTAssertLessThanOrEqual(p.outsAdded,1)
                        if p.out && p.force && p.targetRunner != 0 { XCTAssertEqual(p.rbi,0) }
                        else { XCTAssertEqual(p.rbi,p.runs) }
                        if p.out && p.force { forceCount += 1 }
                        if p.out && !p.force { tagCount += 1 }
                        if p.out && p.force && outs == 2 {
                            thirdForce += 1;XCTAssertEqual(p.runs,0);XCTAssertTrue(p.afterRunners.allSatisfy { $0 == nil })
                        }
                    }
                }
            }
        }
        XCTAssertTrue(targets.contains(1));XCTAssertTrue(targets.contains(2));XCTAssertTrue(targets.contains(4))
        XCTAssertGreaterThan(forceCount,0);XCTAssertGreaterThan(tagCount,0);XCTAssertGreaterThan(thirdForce,0)
    }
    func testDetailedTimelineInterpolationAndThrowNoTeleport() throws {
        let p=detailed(speed:0)
        XCTAssertEqual(FieldNode.sample(p.ball,at:0),DetailedFieldRules.bases[0])
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.flight),p.landing)
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.releaseAt),p.landing)
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.ballAt),DetailedFieldRules.bases[p.targetBase])
        XCTAssertEqual(FieldNode.sample(p.ball,at:(p.releaseAt+p.ballAt)/2),p.landing.towards(DetailedFieldRules.bases[p.targetBase],fraction:0.5))
        let runner=try XCTUnwrap(p.runners.first { $0.from == 0 })
        XCTAssertTrue(runner.out);XCTAssertLessThan(runner.arrival,p.runnerAt!)
        XCTAssertNotEqual(runner.nodes.last?.point,DetailedFieldRules.bases[1])
        XCTAssertEqual(try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONEncoder().encode(p)),p)
    }
    func testDetailedActualEngineStatsProfilesAndXPUseSavedEventsAndLegacyIsOptIn() throws {
        for role in ["batter","pitcher"] {
            var seen=false
            for seed in 1...20 {
                var state=game(seed,role:role)
                state.detailedFieldVersion=1;state.fieldPlays=[];state.runnerProfiles=[nil,nil,nil]
                if role == "batter" {
                    state.fieldStats?.version=3;state.fieldStats?.positionMastery=60
                    state.positionExperience=MatchPositionExperience(position:.center,before:PositionSkill(mastery:60,xp:0),profileRevision:0,age:16,fatigue:24)
                }
                var manual=state
                try state.advance(.automatic)
                while !manual.completed { try manual.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "batter" ? nil:"four-seam") }
                XCTAssertEqual(manual,state)
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(state)),state)
                let plays=try XCTUnwrap(state.fieldPlays)
                XCTAssertFalse(plays.isEmpty);XCTAssertEqual(Set(plays.map(\.eventID)).count,plays.count)
                for play in plays { try play.validate() }
                if let experience=state.positionExperience {
                    let defense=plays.filter(\.ownDefense)
                    XCTAssertEqual(experience.events.count,defense.count)
                    XCTAssertEqual(experience.successes,defense.filter(\.out).count)
                    try experience.validate(match:state)
                    if !defense.isEmpty {seen=true}
                } else { seen=true }
                XCTAssertEqual(state.runnerProfiles?.map { $0 != nil },state.bases)
                if seen { break }
            }
            XCTAssertTrue(seen)
        }
        var legacy=game(42);try legacy.advance(.automatic)
        XCTAssertNil(legacy.detailedFieldVersion);XCTAssertNil(legacy.fieldPlays);XCTAssertNil(legacy.runnerProfiles)
    }
    private func doublePlay(_ x:Double = -14,_ y:Double = 35,batterSpeed:Double=60,runnerSpeed:Double=60,
                            defense:Double=60,arm:Double=60,position:String="SS",outs:Int=0,
                            before:[FieldRunnerProfile?]?=nil,enabled:Bool=true,ground:Bool=true) -> MatchDetailedPlay {
        DetailedFieldRules.resolve(half:0,order:0,landing:FieldPoint(x:x,y:y),flight:1,
            runners:before ?? [FieldRunnerProfile(speed:runnerSpeed),nil,nil],batter:FieldRunnerProfile(speed:batterSpeed),outs:outs,
            stats:MatchFieldStats(version:3,speed:60,defense:defense,arm:arm,position:position,activeTraits:[],positionMastery:60),
            defending:true,ownBatter:false,doublePlayEnabled:enabled,groundBall:ground)
    }
    func testDoublePlayIndependentTwoArrivalTimesAndPivotFlight() throws {
        let play=doublePlay(),second=try XCTUnwrap(play.secondThrow)
        let pickup=0.44+4/5.8+0.2
        let first=pickup+0.39+hypot(14,DetailedFieldRules.diagonal*2-35)/28.8
        let final=first+0.39+27.43/28.8
        XCTAssertEqual(play.fielder,5);XCTAssertEqual(play.receiver,3);XCTAssertEqual(second.receiver,2)
        XCTAssertEqual(play.controlAt,first,accuracy:0.000001)
        XCTAssertEqual(second.controlAt,final,accuracy:0.000001)
        XCTAssertEqual(play.runnerAt!,0.26+27.43/7.6,accuracy:0.000001)
        XCTAssertEqual(second.runnerAt,0.4+27.43/7.6,accuracy:0.000001)
        XCTAssertTrue(play.out);XCTAssertTrue(second.out);XCTAssertEqual(play.outsAdded,2)
        XCTAssertEqual(play.hitBases,0);XCTAssertEqual(play.rbi,0);XCTAssertTrue(play.afterRunners.allSatisfy { $0 == nil })
        try play.validate()
    }
    func testDoublePlayFastBatterAndPivotDefenseArmChangeSecondOut() throws {
        let fast=doublePlay(batterSpeed:100),slow=doublePlay(batterSpeed:0)
        XCTAssertTrue(fast.out);XCTAssertFalse(try XCTUnwrap(fast.secondThrow).out)
        XCTAssertEqual(fast.outsAdded,1);XCTAssertEqual(fast.afterRunners[0]?.speed,100)
        XCTAssertEqual(fast.summary,"병살 무산 · 2루 아웃 → 1루 세이프")
        XCTAssertTrue(try XCTUnwrap(slow.secondThrow).out);XCTAssertEqual(slow.outsAdded,2)
        for (low,high) in [(doublePlay(arm:0,position:"2B"),doublePlay(arm:100,position:"2B")),
                           (doublePlay(defense:0,position:"2B"),doublePlay(defense:100,position:"2B"))] {
            XCTAssertFalse(low.ownDefense);XCTAssertTrue(low.ownParticipation)
            XCTAssertFalse(try XCTUnwrap(low.secondThrow).out);XCTAssertTrue(try XCTUnwrap(high.secondThrow).out)
            XCTAssertGreaterThan(try XCTUnwrap(low.secondThrow).controlAt,try XCTUnwrap(high.secondThrow).controlAt)
            XCTAssertEqual(low.xpPlay.safe,true);XCTAssertEqual(high.xpPlay.safe,false)
            try low.validate();try high.validate()
        }
    }
    func testDoublePlayEligibilityFirstSafeAndThirdOutCancelsRuns() throws {
        for p in [doublePlay(outs:2),doublePlay(before:[nil,nil,nil]),doublePlay(ground:false),doublePlay(-45,85),doublePlay(-30,35,runnerSpeed:100)] {
            XCTAssertNil(p.secondThrow);XCTAssertLessThanOrEqual(p.outsAdded,1);try p.validate()
        }
        let loaded=[FieldRunnerProfile(speed:60),FieldRunnerProfile(speed:60),FieldRunnerProfile(speed:60)]
        let ended=doublePlay(outs:1,before:loaded)
        XCTAssertEqual(ended.outsAdded,2);XCTAssertEqual(ended.runs,0);XCTAssertEqual(ended.rbi,0)
        XCTAssertTrue(ended.afterRunners.allSatisfy { $0 == nil });try ended.validate()
        let continuing=doublePlay(outs:0,before:loaded)
        XCTAssertEqual(continuing.outsAdded,2);XCTAssertEqual(continuing.runs,1);XCTAssertEqual(continuing.rbi,0)
        try continuing.validate()
    }
    func testDoublePlayBallWaitsAtPivotAndRunnersRetireAtDifferentTimes() throws {
        let p=doublePlay(),second=try XCTUnwrap(p.secondThrow)
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.ballAt),DetailedFieldRules.bases[2])
        XCTAssertEqual(FieldNode.sample(p.ball,at:(p.controlAt+second.releaseAt)/2),DetailedFieldRules.bases[2])
        XCTAssertEqual(FieldNode.sample(p.ball,at:second.ballAt),DetailedFieldRules.bases[1])
        let middle=FieldNode.sample(p.ball,at:(second.releaseAt+second.ballAt)/2)
        XCTAssertEqual(middle.x,DetailedFieldRules.diagonal/2,accuracy:0.000000001)
        XCTAssertEqual(middle.y,DetailedFieldRules.diagonal*1.5,accuracy:0.000000001)
        XCTAssertEqual(p.runners.first { $0.from == 1 }?.retiredAt,p.controlAt)
        XCTAssertEqual(p.runners.first { $0.from == 0 }?.retiredAt,second.controlAt)
        XCTAssertLessThan(p.controlAt,second.releaseAt)
        XCTAssertEqual(p.decisionAt,second.controlAt)
        XCTAssertEqual(try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONEncoder().encode(p)),p)
    }
    func testDoublePlayAllOccupanciesPreserveV1AndNeverAddMoreThanRemainingOuts() throws {
        var success=0,failed=0
        for mask in 0..<8 {
            let before=(0..<3).map { mask & (1 << $0) != 0 ? FieldRunnerProfile(speed:60) : nil }
            for outs in 0...2 { for x in [-20.0,-14,0,14,20] { for speed in [0.0,60,100] {
                let p=doublePlay(x,35,batterSpeed:speed,outs:outs,before:before)
                try p.validate();XCTAssertLessThanOrEqual(outs+p.outsAdded,3)
                let occupied=p.runners.filter { !$0.out && (1...3).contains($0.destination) }.map(\.destination)
                XCTAssertEqual(Set(occupied).count,occupied.count)
                if let second=p.secondThrow { if second.out {success += 1} else {failed += 1} }
                let old=doublePlay(x,35,batterSpeed:speed,outs:outs,before:before,enabled:false)
                XCTAssertEqual(old.version,1);XCTAssertNil(old.secondThrow);XCTAssertNil(old.outsBefore);XCTAssertNil(old.doublePlayGrounder)
                XCTAssertTrue(old.runners.allSatisfy { $0.retiredAt == nil });try old.validate()
            } } }
        }
        XCTAssertGreaterThan(success,0);XCTAssertGreaterThan(failed,0)
    }
    func testDoublePlayActualEngineRecordsBothRolesOutsRBIAndSummaryWithoutDuplicateXP() throws {
        for role in ["batter","pitcher"] {
            var observed=false
            for seed in 1...150 {
                var m=game(seed,role:role);m.detailedFieldVersion=2;m.fieldPlays=[]
                m.bases=[true,false,false];m.runnerProfiles=[FieldRunnerProfile(speed:60),nil,nil];m.outs=1
                if role == "pitcher" { m.line.pitchingOuts=1 }
                try m.advance(role == "pitcher" ? .pitch : .swing,pitchCode:role == "pitcher" ? "four-seam":nil)
                guard let p=m.fieldPlays?.first,p.secondThrow?.out == true else { continue }
                try m.validateDetailedField()
                XCTAssertEqual(p.outsAdded,2);XCTAssertEqual(p.rbi,0)
                let summary=MatchResultSummary(match:m,fatigueBefore:0,fatigueAfter:1)
                XCTAssertEqual(summary.metrics.first { $0.id == "doublePlays" }?.value,"1")
                if role == "pitcher" { XCTAssertEqual(m.line.pitchingOuts,3) }
                else { XCTAssertEqual(m.line.atBats,1);XCTAssertEqual(m.line.hits,0);XCTAssertEqual(m.line.rbi,0) }
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(m)),m)
                observed=true;break
            }
            XCTAssertTrue(observed,role)
        }
    }
    func testDoublePlayInvalidSecondThrowOrRetirementNeverFallsBackToSingleOut() throws {
        var p=doublePlay();p.outsBefore=2;XCTAssertThrowsError(try p.validate())
        p=doublePlay();p.doublePlayGrounder=false;XCTAssertThrowsError(try p.validate())
        p=doublePlay();p.version=1;XCTAssertThrowsError(try p.validate())
        p=doublePlay();p.runners[0].retiredAt = .nan;XCTAssertThrowsError(try p.validate())
    }
    private func fly(_ x:Double=0,_ y:Double=90,flight:Double=5.5,speed:Double=60,defense:Double=60,arm:Double=60,
                     outs:Int=0,before:[FieldRunnerProfile?]?=nil) -> MatchDetailedPlay {
        DetailedFieldRules.resolveFly(half:0,order:0,landing:FieldPoint(x:x,y:y),flight:flight,
            runners:before ?? [nil,nil,FieldRunnerProfile(speed:speed,own:true)],batter:FieldRunnerProfile(speed:60),outs:outs,
            stats:MatchFieldStats(version:3,speed:60,defense:defense,arm:arm,position:"CF",activeTraits:[],positionMastery:100),defending:true,ownBatter:false)
    }
    func testFlyCatchAndTagHomeUseIndependentArrivalTimes() throws {
        let p=fly(speed:100)
        XCTAssertEqual(p.fly?.caught,true);XCTAssertEqual(p.fielder,7);XCTAssertEqual(p.targetBase,4)
        XCTAssertEqual(p.flight,5.5);XCTAssertEqual(p.fly?.reachAt ?? 0,0.34+17/5.8+0.2,accuracy:1e-9)
        XCTAssertEqual(p.controlAt,5.5+0.39+90/28.8+0.21,accuracy:1e-9)
        XCTAssertEqual(p.runnerAt ?? 0,5.5+0.18+27.43/9,accuracy:1e-9)
        XCTAssertFalse(p.force);XCTAssertFalse(p.out);XCTAssertEqual(p.outsAdded,1);XCTAssertEqual(p.runs,1)
        XCTAssertTrue(p.sacrificeFly);XCTAssertEqual(p.rbi,1);XCTAssertTrue(p.ownDefense);XCTAssertFalse(p.xpPlay.safe)
        try p.validate()
    }
    func testFlySpeedArmDefenseDetermineCatchHoldSafeAndTagOut() throws {
        let fast=fly(speed:100),caught=fly(speed:60),hold=fly(speed:0)
        XCTAssertFalse(fast.out);XCTAssertEqual(fast.runs,1)
        XCTAssertTrue(caught.out);XCTAssertEqual(caught.outsAdded,2);XCTAssertEqual(caught.runs,0)
        XCTAssertNil(hold.targetRunner);XCTAssertNotNil(hold.afterRunners[2])
        let weak=fly(speed:100,arm:0),strong=fly(speed:100,arm:100)
        XCTAssertNotNil(weak.targetRunner);XCTAssertTrue(strong.out)
        let low=fly(0,90,flight:3.5,defense:0),high=fly(0,90,flight:3.5,defense:100)
        XCTAssertEqual(low.fly?.caught,false);XCTAssertEqual(high.fly?.caught,true)
        for p in [fast,caught,hold,weak,strong,low,high] { try p.validate() }
    }
    func testFlyWaitsAtBagUntilCatchAndReplaysLoftAndSeparateRetirement() throws {
        let p=fly(speed:60),r=try XCTUnwrap(p.runners.first { $0.from == 3 })
        for t in [0,2.0,5.49,5.5] { XCTAssertEqual(FieldNode.sample(r.nodes,at:t),DetailedFieldRules.bases[3]) }
        XCTAssertEqual(p.runners.first { $0.from == 0 }?.retiredAt,p.flight)
        XCTAssertEqual(r.retiredAt,p.controlAt);XCTAssertLessThan(p.flight,p.controlAt)
        XCTAssertEqual(p.decisionAt,p.controlAt)
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.flight),p.landing)
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.ballAt),DetailedFieldRules.bases[4])
        XCTAssertEqual(try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONEncoder().encode(p)),p)
    }
    func testFlyTwoOutCatchEndsInningAndInfieldDoesNotCreditSacrifice() throws {
        let loaded=[FieldRunnerProfile(speed:100),FieldRunnerProfile(speed:100),FieldRunnerProfile(speed:100)]
        let p=fly(outs:2,before:loaded)
        XCTAssertEqual(p.outsAdded,1);XCTAssertEqual(p.runs,0);XCTAssertNil(p.targetRunner)
        XCTAssertTrue(p.afterRunners.allSatisfy { $0 == nil });try p.validate()
        let pop=fly(0,18,flight:5,before:loaded)
        XCTAssertEqual(pop.fly?.caught,true);XCTAssertEqual(pop.fielder,0)
        XCTAssertFalse(pop.sacrificeFly);XCTAssertEqual(pop.runs,0);try pop.validate()
    }
    func testFlyAllOccupanciesNoForceCollisionOrMoreThanThreeOuts() throws {
        var tags=0,outsCount=0,drops=0
        for mask in 0..<8 { for outs in 0...2 { for y in [30.0,60,90,105] { for speed in [0.0,60,100] {
            let before=(0..<3).map { mask & (1 << $0) == 0 ? nil:FieldRunnerProfile(speed:speed) }
            let p=fly(0,y,flight:3.5,speed:speed,outs:outs,before:before)
            try p.validate();XCTAssertLessThanOrEqual(outs+p.outsAdded,3)
            let occupied=p.runners.filter { !$0.out && (1...3).contains($0.destination) }.map(\.destination)
            XCTAssertEqual(Set(occupied).count,occupied.count)
            if p.fly?.caught == true { XCTAssertFalse(p.force);if p.targetRunner != nil {tags += 1};if p.out {outsCount += 1} }
            else {drops += 1}
        } } } }
        XCTAssertGreaterThan(tags,0);XCTAssertGreaterThan(outsCount,0);XCTAssertGreaterThan(drops,0)
    }
    func testFlyActualEngineSacrificeIsPAWithoutABAndPreservesBothRolesOuts() throws {
        for role in ["batter","pitcher"] {
            var seen=false
            for seed in 1...1000 {
                var m=game(seed,role:role);m.detailedFieldVersion=3;m.fieldPlays=[]
                m.bases=[false,false,true];m.runnerProfiles=[nil,nil,FieldRunnerProfile(speed:100)];m.outs=0
                try m.advance(role == "pitcher" ? .pitch:.swing,pitchCode:role == "pitcher" ? "four-seam":nil)
                guard let p=m.fieldPlays?.first,p.sacrificeFly else {continue}
                try m.validateDetailedField();XCTAssertEqual(p.outsAdded,1)
                if role == "batter" {
                    XCTAssertEqual(m.line.plateAppearances,1);XCTAssertEqual(m.line.atBats,0);XCTAssertEqual(m.line.hits,0);XCTAssertEqual(m.line.rbi,1)
                    XCTAssertEqual(MatchResultSummary(match:m,fatigueBefore:0,fatigueAfter:0).metrics.first { $0.id == "sacrificeFlies" }?.value,"1")
                } else {XCTAssertEqual(m.line.pitchingOuts,1);XCTAssertEqual(m.line.hitsAllowed,0);XCTAssertEqual(m.line.runsAllowed,1)}
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(m)),m)
                seen=true;break
            }
            XCTAssertTrue(seen,role)
        }
    }
    func testFlyMalformedCatchVersionOrPrematureRunnerFailsValidation() throws {
        var p=fly();p.version=2;XCTAssertThrowsError(try p.validate())
        p=fly();p.fly=FieldFlyPlay(caught:true,reachAt:10);XCTAssertThrowsError(try p.validate())
        p=fly();p.outsBefore=2;XCTAssertThrowsError(try p.validate())
        p=fly();let i=try XCTUnwrap(p.runners.firstIndex { $0.from == 3 })
        p.runners[i].nodes[0]=FieldNode(at:0,point:DetailedFieldRules.bases[4]);XCTAssertThrowsError(try p.validate())
    }

    func testTagThirdOutIsTimePlayEarlierHomeRunCountsButLaterDoesNot() throws {
        let before=[nil,FieldRunnerProfile(speed:60),FieldRunnerProfile(speed:100)]
        let early=fly(40,90,flight:6,outs:1,before:before)
        XCTAssertEqual(early.fly?.caught,true);XCTAssertEqual(early.targetBase,3);XCTAssertTrue(early.out)
        XCTAssertEqual(early.outsAdded,2);XCTAssertEqual(early.runs,1);XCTAssertEqual(early.rbi,1)
        XCTAssertTrue(early.afterRunners.allSatisfy { $0 == nil });try early.validate()
        let late=fly(0,90,flight:5.5,outs:1,before:[nil,FieldRunnerProfile(speed:100),FieldRunnerProfile(speed:100)])
        XCTAssertEqual(late.targetBase,3);XCTAssertTrue(late.out);XCTAssertEqual(late.runs,0);try late.validate()
    }

    func testFlyReadyExactlyAtBallArrivalIsCatchAndOnlyOneSuccessfulXPEvent() throws {
        let reach=try XCTUnwrap(fly(before:[nil,nil,nil]).fly).reachAt
        let p=fly(flight:reach,before:[nil,nil,nil])
        XCTAssertEqual(p.fly?.caught,true);XCTAssertEqual(p.outsAdded,1)
        XCTAssertEqual(p.xpPlay.runnerTime,p.xpPlay.ballTime);XCTAssertEqual(p.xpPlay.caughtFly,true)
        XCTAssertFalse(p.xpPlay.safe);try p.validate()
    }

    func testSavedTagUpSafeAndOutRenderReadOnlyWithoutChangingLedger() throws {
        for speed in [60.0,100] {
            let original=try JSONEncoder().encode(fly(speed:speed))
            let play=try JSONDecoder().decode(MatchDetailedPlay.self,from:original)
            let renderer=ImageRenderer(content:DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),animated:false) {}
                .frame(width:390,height:300))
            renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width,390);XCTAssertEqual(image.size.height,300)
            let attachment=XCTAttachment(image:image);attachment.name=speed == 60 ? "Tag up OUT saved board":"Tag up SAFE saved board"
            attachment.lifetime = .keepAlways;add(attachment)
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:original))
        }
    }

    private func relayFly(_ x:Double=0,_ y:Double=100,outs:Int=0,speed:Double=100,defense:Double=60,arm:Double=60,
                          position:String="2B",enabled:Bool=true,before:[FieldRunnerProfile?]?=nil) -> MatchDetailedPlay {
        DetailedFieldRules.resolveFly(half:0,order:0,landing:FieldPoint(x:x,y:y),flight:7,
            runners:before ?? [nil,nil,FieldRunnerProfile(speed:speed)],batter:FieldRunnerProfile(speed:60),outs:outs,
            stats:MatchFieldStats(version:3,speed:60,defense:defense,arm:arm,position:position,activeTraits:[],positionMastery:100),
            defending:true,ownBatter:false,relayEnabled:enabled)
    }
    func testRelayIndependentTwoLegTimesAndDirectComparison() throws {
        let p=relayFly(),r=try XCTUnwrap(p.relay)
        let leg=50/28.8*1.125
        XCTAssertEqual(p.fielder,7);XCTAssertEqual(r.fielder,3);XCTAssertEqual(p.targetBase,4)
        XCTAssertEqual(p.releaseAt,7.39,accuracy:1e-9)
        XCTAssertEqual(r.receiveAt,7.39+leg,accuracy:1e-9)
        XCTAssertEqual(r.releaseAt,7.39+leg+0.39,accuracy:1e-9)
        XCTAssertEqual(p.controlAt,7.39+2*leg+0.39+0.21,accuracy:1e-9)
        XCTAssertEqual(r.directAt,7.39+100/28.8*1.75+0.21,accuracy:1e-9)
        XCTAssertLessThan(p.controlAt,r.directAt);XCTAssertTrue(r.ownThrower);XCTAssertTrue(p.ownParticipation)
        XCTAssertFalse(p.ownDefense);XCTAssertNil(p.secondThrow);try p.validate()
    }
    func testRelayCutoffArmDefenseAndShortDistanceCanChooseDirect() throws {
        let weak=relayFly(defense:0,arm:0),strong=relayFly(defense:100,arm:100)
        XCTAssertNotNil(strong.relay)
        XCTAssertLessThan(strong.controlAt,weak.controlAt)
        let short=relayFly(0,65,before:[FieldRunnerProfile(speed:100),nil,nil])
        XCTAssertNil(short.relay);try short.validate()
        let weakOutfield=relayFly(0,66,arm:0,position:"CF"),strongOutfield=relayFly(0,66,arm:100,position:"CF")
        XCTAssertNotNil(weakOutfield.relay);XCTAssertNil(strongOutfield.relay)
        XCTAssertFalse(weakOutfield.out);XCTAssertTrue(strongOutfield.out)
        try weakOutfield.validate();try strongOutfield.validate()
        let old=relayFly(enabled:false)
        XCTAssertEqual(old.version,3);XCTAssertNil(old.relay);try old.validate()
    }
    func testRelayBallHoldsAtCutoffAndPlayersReachBeforeReceiving() throws {
        let p=relayFly(),r=try XCTUnwrap(p.relay)
        XCTAssertEqual(FieldNode.sample(p.ball,at:r.receiveAt),r.point)
        XCTAssertEqual(FieldNode.sample(p.ball,at:(r.receiveAt+r.releaseAt)/2),r.point)
        XCTAssertEqual(FieldNode.sample(p.ball,at:p.ballAt),DetailedFieldRules.bases[4])
        XCTAssertEqual(FieldNode.sample(p.fielders[r.fielder],at:r.receiveAt),r.point)
        XCTAssertLessThanOrEqual(r.readyAt,r.receiveAt)
        XCTAssertEqual(p,try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONEncoder().encode(p)))
    }
    func testRelayAllOccupanciesGroundFlyAndOutsKeepSingleRaceAndThirdOutRules() throws {
        var relayCount=0,direct=0,outCount=0
        for mask in 0..<8 { for outs in 0...2 { for x in [-45.0,0,45] { for speed in [30.0,60,100] {
            let before=(0..<3).map { mask & (1 << $0) == 0 ? nil:FieldRunnerProfile(speed:speed) }
            for fly in [false,true] {
                let p=fly ? relayFly(x,100,outs:outs,speed:speed,before:before) : DetailedFieldRules.resolve(half:0,order:0,
                    landing:FieldPoint(x:x,y:95),flight:2,runners:before,batter:FieldRunnerProfile(speed:speed),outs:outs,stats:nil,
                    defending:false,ownBatter:true,doublePlayEnabled:true,groundBall:false,relayEnabled:true)
                try p.validate();XCTAssertLessThanOrEqual(outs+p.outsAdded,3)
                if let r=p.relay {relayCount += 1;XCTAssertLessThan(p.controlAt,r.directAt);XCTAssertNil(p.secondThrow)} else {direct += 1}
                if p.out {outCount += 1}
                let occupied=p.runners.filter { !$0.out && (1...3).contains($0.destination) }.map(\.destination)
                XCTAssertEqual(Set(occupied).count,occupied.count)
            }
        } } } }
        XCTAssertGreaterThan(relayCount,0);XCTAssertGreaterThan(direct,0);XCTAssertGreaterThan(outCount,0)
    }
    func testRelayActualEngineBothRolesResumeAndSingleEvents() throws {
        for role in ["batter","pitcher"] {
            var m=game(42,role:role);m.detailedFieldVersion=4;m.fieldPlays=[];m.runnerProfiles=[nil,nil,nil]
            var single=m;try m.advance(.automatic)
            while !single.completed {try single.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "pitcher" ? "four-seam":nil)}
            XCTAssertEqual(single,m);try m.validateDetailedField()
            XCTAssertTrue(m.fieldPlays?.contains { $0.relay != nil } == true)
            XCTAssertEqual(Set(m.fieldPlays?.map(\.eventID) ?? []).count,m.fieldPlays?.count)
            XCTAssertEqual(m,try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(m)))
        }
    }
    func testRelayInvalidVersionTimingOrNodeCannotSilentlyBecomeDirect() throws {
        var p=relayFly();p.version=3;XCTAssertThrowsError(try p.validate())
        p=relayFly();let r=try XCTUnwrap(p.relay)
        p.relay=FieldRelay(fielder:r.fielder,point:r.point,readyAt:r.receiveAt+1,receiveAt:r.receiveAt,releaseAt:r.releaseAt,
            directAt:r.directAt,ownThrower:r.ownThrower,traits:r.traits,positionDelay:r.positionDelay)
        XCTAssertThrowsError(try p.validate())
        p=relayFly();p.relay=FieldRelay(fielder:p.receiver,point:r.point,readyAt:r.readyAt,receiveAt:r.receiveAt,releaseAt:r.releaseAt,
            directAt:r.directAt,ownThrower:false,traits:[],positionDelay:0);XCTAssertThrowsError(try p.validate())
    }
    func testSavedRelayBoardRendersReadOnly() throws {
        let p=relayFly(),data=try JSONEncoder().encode(p)
        let renderer=ImageRenderer(content:DetailedFieldReplayBoard(play:p,appearance:PlayerAppearance(),animated:false) {}
            .frame(width:390,height:350));renderer.scale=2
        let image=try XCTUnwrap(renderer.uiImage),a=XCTAttachment(image:image)
        a.name="Relay saved board";a.lifetime = .keepAlways;add(a)
        XCTAssertEqual(p,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
    }

    private func misplay(_ clean:MatchDetailedPlay,stage:Int,position:String="SS",defense:Double=60,arm:Double=60) -> MatchDetailedPlay {
        var draws=Array(repeating:0.999999,count:7);draws[stage]=0
        return FieldMisplayRules.applying(to:clean,stats:MatchFieldStats(version:3,speed:60,defense:defense,arm:arm,position:position,activeTraits:[],positionMastery:100),defending:true,draws:draws)
    }
    func testMisplayProbabilityUsesDefenseArmAndSafeHandsIndependently() throws {
        XCTAssertEqual(FieldMisplayRules.probability(kind:.fielding,defense:60,arm:0,distance:0,traits:[]),0.0148,accuracy:1e-12)
        XCTAssertEqual(FieldMisplayRules.probability(kind:.throwing,defense:0,arm:60,distance:90,traits:[]),0.0274,accuracy:1e-12)
        XCTAssertLessThan(FieldMisplayRules.probability(kind:.fielding,defense:100,arm:0,distance:0,traits:[]),FieldMisplayRules.probability(kind:.fielding,defense:0,arm:100,distance:0,traits:[]))
        XCTAssertLessThan(FieldMisplayRules.probability(kind:.throwing,defense:0,arm:100,distance:70,traits:[]),FieldMisplayRules.probability(kind:.throwing,defense:100,arm:0,distance:70,traits:[]))
        XCTAssertEqual(FieldMisplayRules.probability(kind:.fielding,defense:60,arm:0,distance:0,traits:[.safeHands]),0.0148*0.7,accuracy:1e-12)
        let clean=doublePlay();var draws=Array(repeating:0.999999,count:7);draws[0]=0.01
        func apply(_ defense:Double) -> MatchDetailedPlay {FieldMisplayRules.applying(to:clean,stats:MatchFieldStats(speed:60,defense:defense,arm:60,position:"SS"),defending:true,draws:draws)}
        XCTAssertNotNil(apply(0).misplay);XCTAssertNil(apply(100).misplay)
    }
    func testDroppedFlyRemovesCatchForcesLoadedRunnersWithoutHitRBIOrSacrifice() throws {
        for outs in [0,2] {
            let clean=fly(outs:outs,before:[FieldRunnerProfile(speed:60),FieldRunnerProfile(speed:60),FieldRunnerProfile(speed:60)])
            let p=misplay(clean,stage:0,position:"CF"),e=try XCTUnwrap(p.misplay)
            XCTAssertEqual(e.kind,.fielding);XCTAssertEqual(p.outsAdded,0);XCTAssertEqual(p.hitBases,0)
            XCTAssertTrue(e.reachedOnError);XCTAssertFalse(p.sacrificeFly);XCTAssertEqual(p.rbi,0)
            XCTAssertTrue(p.afterRunners.allSatisfy {$0 != nil});XCTAssertEqual(p.runs,1)
            XCTAssertTrue(p.xpPlay.safe);XCTAssertEqual(p.xpPlay.failedFielding,true);try p.validate()
        }
    }
    func testBadThrowPreservesOrdinaryHitAndSeparatesExtraBases() throws {
        let clean=DetailedFieldRules.resolve(half:0,order:0,landing:FieldPoint(x:-45,y:90),flight:2,runners:[nil,nil,nil],batter:FieldRunnerProfile(speed:100),outs:0,stats:nil,defending:false,ownBatter:true,doublePlayEnabled:true,groundBall:false,relayEnabled:true)
        let p=misplay(clean,stage:1,position:"LF"),e=try XCTUnwrap(p.misplay)
        XCTAssertEqual(e.kind,.throwing);XCTAssertEqual(p.hitBases,clean.hitBases);XCTAssertGreaterThan(p.hitBases,0)
        XCTAssertFalse(e.reachedOnError);XCTAssertFalse(e.extraBases.isEmpty);XCTAssertEqual(p.rbi,min(clean.rbi,p.runs));try p.validate()
    }
    func testPivotBadThrowKeepsSecondBaseOutAndOnlyOneXPEvent() throws {
        let clean=doublePlay(position:"2B",outs:1),p=misplay(clean,stage:5,position:"2B"),e=try XCTUnwrap(p.misplay)
        XCTAssertEqual(p.outsAdded,1);XCTAssertEqual(p.runners.first {$0.from == 1}?.out,true)
        XCTAssertEqual(p.runners.first {$0.from == 0}?.out,false);XCTAssertNil(p.secondThrow)
        XCTAssertEqual(p.hitBases,0);XCTAssertEqual(p.rbi,0);XCTAssertTrue(e.ownError)
        XCTAssertTrue(p.ownParticipation);XCTAssertTrue(p.xpPlay.safe);try p.validate()
    }
    func testRelayBadThrowKeepsEarlierFlyOutAndDoesNotRewardFailedCutoff() throws {
        let clean=relayFly(before:[FieldRunnerProfile(speed:60),nil,FieldRunnerProfile(speed:100)])
        let p=misplay(clean,stage:3,position:"2B"),e=try XCTUnwrap(p.misplay)
        XCTAssertEqual(p.outsAdded,1);XCTAssertEqual(p.runners.first {$0.from == 0}?.out,true)
        XCTAssertFalse(e.extraBases.isEmpty);XCTAssertTrue(e.ownError);XCTAssertTrue(p.ownParticipation);XCTAssertTrue(p.xpPlay.safe)
        XCTAssertEqual(p.rbi,min(clean.rbi,p.runs));try p.validate()
    }
    func testMisplayGridKeepsOccupancyPriorOutsAndStoredNodeOrder() throws {
        var seen=Set<Int>()
        for mask in 0..<8 {for outs in 0...2 {for x in [-35.0,0,35] {for speed in [20.0,60,100] {
            let before=(0..<3).map { mask & (1 << $0) == 0 ? nil:FieldRunnerProfile(speed:speed) }
            let clean=DetailedFieldRules.resolve(half:0,order:0,landing:FieldPoint(x:x,y:35),flight:1,runners:before,batter:FieldRunnerProfile(speed:speed),outs:outs,stats:nil,defending:false,ownBatter:true,doublePlayEnabled:true,groundBall:true,relayEnabled:true)
            for stage in FieldMisplayRules.opportunities(clean).map(\.stage) {
                let p=misplay(clean,stage:stage);try p.validate()
                if let e=p.misplay {seen.insert(e.stage);XCTAssertLessThan(outs+p.outsAdded,3);XCTAssertTrue(e.extraBases.allSatisfy {$0.value > 0 && $0.value <= ($0.key == 0 ? 2:1)})}
                let occupied=p.runners.filter {!$0.out && (1...3).contains($0.destination)}.map(\.destination)
                XCTAssertEqual(Set(occupied).count,occupied.count)
                XCTAssertEqual(p,try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONEncoder().encode(p)))
            }
        }}}}
        XCTAssertTrue(seen.contains(0));XCTAssertTrue(seen.contains(1));XCTAssertTrue(seen.contains(4))
    }
    func testMisplayActualEngineBothRolesDirectAutomaticAndRecordCounts() throws {
        for role in ["batter","pitcher"] {
            var m=game(42,role:role);m.detailedFieldVersion=5;m.fieldPlays=[];m.runnerProfiles=[nil,nil,nil]
            var single=m;try m.advance(.automatic)
            while !single.completed {try single.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "pitcher" ? "four-seam":nil)}
            XCTAssertEqual(single,m);try m.validateDetailedField()
            let plays=try XCTUnwrap(m.fieldPlays);XCTAssertTrue(plays.contains {$0.misplay != nil})
            let summary=MatchResultSummary(match:m,fatigueBefore:0,fatigueAfter:1)
            XCTAssertEqual(summary.metrics.first {$0.id == "fieldingErrors"}?.value,String(plays.filter {$0.misplay?.ownError == true}.count))
            XCTAssertEqual(m,try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(m)))
        }
    }
    func testMisplayDrawsReplayExactlyAndHarmlessFumbleDoesNotInventError() throws {
        let clean=doublePlay(),a=misplay(clean,stage:1),b=misplay(clean,stage:1)
        XCTAssertEqual(a,b)
        let ended=relayFly(outs:2),p=misplay(ended,stage:1)
        XCTAssertNil(p.misplay);XCTAssertEqual(p,ended)
    }
    func testMisplayMalformedVersionOrOccupancyFailsWithoutDroppingEvent() throws {
        var p=misplay(doublePlay(),stage:1);p.version=4;XCTAssertThrowsError(try p.validate())
        p=misplay(doublePlay(),stage:1);p.runners.append(p.runners[0]);XCTAssertThrowsError(try p.validate())
        p=misplay(doublePlay(),stage:1);p.runners[0].nodes.append(FieldNode(at:.nan,point:FieldPoint(x:0,y:0)));XCTAssertThrowsError(try p.validate())
    }
    func testSavedFieldingAndThrowingErrorBoardsRenderReadOnly() throws {
        for stage in [0,1] {
            let p=misplay(doublePlay(),stage:stage),data=try JSONEncoder().encode(p)
            let renderer=ImageRenderer(content:DetailedFieldReplayBoard(play:p,appearance:PlayerAppearance(),animated:false) {}.frame(width:390,height:320));renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage),a=XCTAttachment(image:image)
            a.name=stage == 0 ? "Fielding error saved board":"Throwing error saved board";a.lifetime = .keepAlways;add(a)
            XCTAssertEqual(p,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
    }

    func testErrorCallMeansBaseballMisplayWithTeamPositionAndScoringExplanation() throws {
        for stage in [0,1] {
            let play=misplay(doublePlay(),stage:stage),saved=try JSONEncoder().encode(play)
            let error=try XCTUnwrap(play.misplay)
            XCTAssertEqual(FieldReplayPresentation.resultTitle(play),stage == 0 ? "포구 실책":"악송구")
            for own in [true,false] {
                let detail=try XCTUnwrap(FieldReplayPresentation.errorDetail(play,ownTeamFielding:own))
                XCTAssertTrue(detail.hasPrefix(own ? "우리 팀":"상대 팀"))
                XCTAssertTrue(detail.contains(error.reachedOnError ? "안타 제외":error.ordinaryHitBases>0 ? "안타 인정":error.extraBases.isEmpty ? "주자 생존":"추가 진루"))
            }
            XCTAssertEqual(FieldSpriteAnimation.throwsIn(play).first?.fielder,error.recoverer)
            XCTAssertEqual(FieldSpriteAnimation.motion(play,index:error.recoverer,time:play.releaseAt).stage,.release)
            let recovery=FieldSpriteAnimation.motion(play,index:error.recoverer,time:error.recoveredAt)
            XCTAssertFalse(recovery.airCatch);XCTAssertFalse(recovery.chestCatch)
            XCTAssertEqual(FieldReplayPresentation.phase(play,time:error.at,finished:false),stage == 0 ? "포구 놓침 · 공 이탈":"빗나간 송구 · 수신 시도")
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:saved))
        }
        XCTAssertNil(FieldReplayPresentation.errorDetail(doublePlay(),ownTeamFielding:true))
        XCTAssertFalse(FieldReplayPresentation.resultTitle(doublePlay()).contains("실책"))
    }

    func testAllReceiveAndThrowPosesAreSingleOpaqueFramesWithMatchingContacts() throws {
        for kind in ["fielder","catcher"] {for facing in FieldFacing.allCases {for left in [false,true] {
            for stage in [FieldSpriteStage.catchBall,.gather,.windup,.release,.followThrough] {for progress in [0.0,0.25,0.49,0.5,0.75,1] {
                let motion=FieldSpriteMotion(facing:facing,stage:stage,progress:progress,willThrow:true)
                let frames=FieldRasterArt.samples(motion,kind:kind,left:left)
                XCTAssertEqual(frames.count,1);XCTAssertEqual(frames.first?.weight,1)
                let sample=try XCTUnwrap(frames.first),f=sample.frame
                let anchor=stage == .release ? f.hand:f.glove
                let actual=try XCTUnwrap(FieldRasterArt.contact(motion,kind:kind,left:left,hand:stage == .release))
                XCTAssertEqual(actual.x,(anchor[0]-f.pivot[0])*sample.unit*(sample.mirrored ? -1:1),accuracy:0.00001)
                XCTAssertEqual(actual.y,(anchor[1]-f.pivot[1])*sample.unit,accuracy:0.00001)
            }}
        }}}
        let ground=FieldRasterArt.samples(.init(facing:.south,stage:.catchBall,progress:1),kind:"fielder",left:false)
        let chest=FieldRasterArt.samples(.init(facing:.south,stage:.catchBall,progress:1,chestCatch:true),kind:"fielder",left:false)
        let air=FieldRasterArt.samples(.init(facing:.south,stage:.catchBall,progress:1,airCatch:true),kind:"fielder",left:false)
        XCTAssertEqual(ground.first?.frame.action,"catch");XCTAssertEqual(chest.first?.frame.action,"gather");XCTAssertEqual(air.first?.frame.action,"airCatch")
    }

    func testCatcherStrideAndOpaqueThrowContactSheetRenders() throws {
        let view=Canvas {context,_ in
            for row in 0..<3 {for col in 0..<8 {
                let motion=FieldSpriteMotion(facing:FieldFacing.allCases[col],stage:row == 0 ? .run:row == 1 ? .windup:.catchBall,progress:0.6,gait:Double(col)*0.8,chestCatch:row == 2)
                FieldRasterArt.draw(in:context,at:CGPoint(x:35+col*65,y:70+row*85),scale:1.7,motion:motion,kind:row == 0 ? "catcher":"fielder",kit:0x316841,skin:0xba7750,hair:0x382416,number:47,left:false,selected:false,out:false)
            }}
        }.frame(width:540,height:280).background(GameTheme.board)
        let image=try XCTUnwrap(ImageRenderer(content:view).uiImage)
        let attachment=XCTAttachment(image:image);attachment.name="Opaque catcher stride chest receive and throw poses";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testMisplayRestartsWaitingCheetahRunnerEarlierWithoutChangingSpeed() throws {
        func play(_ traits:[PlayerTrait]) -> MatchDetailedPlay {
            let clean=relayFly(before:[FieldRunnerProfile(speed:60,traits:traits,own:true),nil,FieldRunnerProfile(speed:100)])
            return misplay(clean,stage:3,position:"2B")
        }
        let plain=play([]),fast=play([.cheetah])
        XCTAssertNotNil(plain.misplay);XCTAssertNotNil(fast.misplay)
        let a=try XCTUnwrap(plain.runners.first {$0.from == 1}),b=try XCTUnwrap(fast.runners.first {$0.from == 1})
        XCTAssertEqual(a.profile.speed,b.profile.speed);XCTAssertEqual(a.destination,b.destination)
        XCTAssertLessThan(b.arrival,a.arrival);try fast.validate()
    }

    func testFieldPresentationWithholdsOutcomeUntilResolvedWithoutMutatingReplay() throws {
        for play in [doublePlay(), fly(), relayFly()] {
            let data=try JSONEncoder().encode(play)
            for time in [0,play.pickupAt,play.releaseAt,play.controlAt,play.duration] {
                let phase=FieldReplayPresentation.phase(play,time:time,finished:false)
                for spoiler in ["아웃","세이프","안타","OUT","SAFE"] {XCTAssertFalse(phase.contains(spoiler))}
                XCTAssertNotEqual(phase,play.summary)
            }
            XCTAssertEqual(FieldReplayPresentation.phase(play,time:play.duration,finished:true),play.summary)
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
    }

    func testFieldPresentationSeparatesGroundAirPosesAndTeamKits() {
        let ground=doublePlay(),air=fly()
        XCTAssertLessThanOrEqual(FieldReplayPresentation.lift(ground,time:ground.flight/2,height:300),3)
        XCTAssertGreaterThan(FieldReplayPresentation.lift(air,time:air.flight/2,height:300),50)
        XCTAssertEqual(FieldSpriteAnimation.motion(ground,index:ground.fielder,time:ground.pickupAt).stage,.catchBall)
        XCTAssertEqual(FieldSpriteAnimation.motion(ground,index:ground.fielder,time:ground.releaseAt).stage,.release)
        XCTAssertEqual(FieldSpriteAnimation.travel([.init(at:0,point:.init(x:0,y:0)),.init(at:1,point:.init(x:10,y:0))],time:0.5).stage,.run)
        XCTAssertEqual(FieldReplayPresentation.seconds(ground,reduced:true,animated:true),max(3,ground.duration))
        XCTAssertGreaterThanOrEqual(FieldReplayPresentation.seconds(air,reduced:false,animated:true),3)
        for color in PlayerAppearance.kitColors {XCTAssertNotEqual(FieldReplayPresentation.opponentKit(color),color)}
    }

    func testLiveFieldClockPreservesBallSpeedAndDoesNotStartAtRetiredRunner() throws {
        for play in [doublePlay(),fly(),relayFly()] {
            let saved=try JSONEncoder().encode(play)
            for reduced in [false,true] {
                XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:0,reduced:reduced,animated:true),0)
                XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:-1,reduced:reduced,animated:true),0)
                XCTAssertEqual(FieldReplayPresentation.seconds(play,reduced:reduced,animated:true),max(3,play.duration))
                for runner in play.runners {
                    XCTAssertFalse(FieldReplayPresentation.retired(runner,finished:false))
                    XCTAssertEqual(FieldReplayPresentation.retired(runner,finished:true),runner.out)
                }
                for moment in [play.flight,play.pickupAt,play.releaseAt,play.ballAt,play.controlAt,play.duration] {
                    XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:moment,reduced:reduced,animated:true),moment)
                }
            }
            let mid=play.flight/2
            XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:mid,reduced:false,animated:true),mid)
            let ball=FieldNode.sample(play.ball,at:mid)
            XCTAssertNotEqual(ball,DetailedFieldRules.bases[0])
            XCTAssertNotEqual(ball,play.landing)
            XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:0,reduced:false,animated:false),play.duration)
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:saved))
        }
    }

    func testStaticFieldBoardDoesNotCompleteOrResolveAnActivePlayback() async throws {
        var callbacks=0
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:600))
        window.rootViewController=UIHostingController(rootView:DetailedFieldReplayBoard(play:doublePlay(),appearance:PlayerAppearance(),animated:false,onResolved:{callbacks+=1}) {callbacks+=1})
        window.makeKeyAndVisible()
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(callbacks,0)
        window.isHidden=true;window.rootViewController=nil
    }

    func testLongFieldPlayIsNotCompressedAndReducedStillsStayInEventOrder() throws {
        let play=DetailedFieldRules.resolve(half:0,order:0,landing:FieldPoint(x:55,y:90),flight:4,
            runners:[nil,nil,nil],batter:FieldRunnerProfile(speed:70),outs:0,stats:nil,defending:false,ownBatter:true)
        try play.validate()
        XCTAssertGreaterThan(play.duration,8)
        for reduced in [false,true] {
            XCTAssertEqual(FieldReplayPresentation.seconds(play,reduced:reduced,animated:true),play.duration)
            let before=FieldReplayPresentation.time(play,elapsed:play.flight-0.01,reduced:reduced,animated:true)
            XCTAssertLessThan(before,play.flight)
            let after=FieldReplayPresentation.time(play,elapsed:play.flight,reduced:reduced,animated:true)
            XCTAssertEqual(after,play.flight)
            XCTAssertFalse(FieldReplayPresentation.phase(play,time:after,finished:false).contains("아웃"))
        }
    }

    func testRunningSpritesAreOpaqueFrameCyclesInsteadOfGhostedDissolves() {
        for kind in ["runner","fielder","catcher"] {for facing in FieldFacing.allCases {for left in [false,true] {
            var actions=Set<String>()
            for gait in [0.0,0.4,1.5,3.3,4.8,6.0] {
                let samples=FieldRasterArt.samples(FieldSpriteMotion(facing:facing,stage:.run,gait:gait),kind:kind,left:left)
                XCTAssertEqual(samples.count,1)
                XCTAssertEqual(samples.first?.weight,1)
                if let action=samples.first?.frame.action {actions.insert(action)}
            }
            XCTAssertEqual(actions,["runA","runB"])
        }}}
    }

    func testFieldPresentationRendersOwnLeftHandedNumberAndDistinctUniformsReadOnly() throws {
        let play=relayFly(),data=try JSONEncoder().encode(play)
        for ownFielding in [true,false] {
            var appearance=PlayerAppearance();appearance.kit=2;appearance.skin=4;appearance.hair=4
            let view=DetailedFieldReplayBoard(play:play,appearance:appearance,animated:false,jerseyNumber:47,
                ownPosition:"2B",throwingHand:"left",ownTeamFielding:ownFielding,scoreText:"H 2 : 1 A") {}
                .frame(width:390,height:500)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            let attachment=XCTAttachment(image:image);attachment.name=ownFielding ? "Own defense pixel stadium":"Opponent defense pixel stadium"
            attachment.lifetime = .keepAlways;add(attachment)
        }
        XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
    }

    func testFieldPresentationResolvesBeforeReceiptCompletionAndCancelsOnDismissal() async throws {
        var events:[String]=[]
        let resolved=expectation(description:"field completed before result receipt")
        let complete=expectation(description:"result receipt ended")
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:500))
        let view=DetailedFieldReplayBoard(play:fly(),appearance:PlayerAppearance(),onResolved:{
            events.append("resolved");resolved.fulfill()
        }) {events.append("complete");complete.fulfill()}
        window.rootViewController=UIHostingController(rootView:view);window.makeKeyAndVisible()
        await fulfillment(of:[resolved],timeout:max(3,fly().duration)+3)
        XCTAssertEqual(events,["resolved"])
        await fulfillment(of:[complete],timeout:3)
        XCTAssertEqual(events,["resolved","complete"])
        var cancelledCallbacks=0
        let cancelView=DetailedFieldReplayBoard(play:fly(),appearance:PlayerAppearance(),onResolved:{cancelledCallbacks+=1}) {cancelledCallbacks+=1}
        window.rootViewController=UIHostingController(rootView:cancelView)
        try await Task.sleep(for:.milliseconds(100))
        window.rootViewController=UIViewController()
        try await Task.sleep(for:.seconds(9))
        XCTAssertEqual(cancelledCallbacks,0)
        window.isHidden=true;window.rootViewController=nil
    }

    func testPixelStadiumNativeResolutionAndImmersiveStageAllocation() throws {
        let image=try XCTUnwrap(InplayStadiumArt.image)
        XCTAssertEqual(image.scale,1)
        XCTAssertEqual(try XCTUnwrap(image.cgImage).width,1024)
        XCTAssertEqual(try XCTUnwrap(image.cgImage).height,1536)
        XCTAssertEqual(FieldReplayPresentation.stageHeight(width:374,available:720),597,accuracy:0.01)
        XCTAssertEqual(FieldReplayPresentation.stageHeight(width:304,available:420),320)
        XCTAssertEqual(FieldReplayPresentation.stageHeight(width:304,available:420,accessibility:true),480)
        let attachment=XCTAttachment(image:image);attachment.name="Pixel stadium native art";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testFieldSpriteEightHeadingsAndStoppedRunnerPreservesLastDirection() {
        let vectors:[(Double,Double,FieldFacing)]=[(0,1,.north),(1,1,.northEast),(1,0,.east),(1,-1,.southEast),(0,-1,.south),(-1,-1,.southWest),(-1,0,.west),(-1,1,.northWest)]
        for (x,y,direction) in vectors {
            let nodes=[FieldNode(at:0,point:.init(x:0,y:0)),FieldNode(at:1,point:.init(x:x*10,y:y*10)),FieldNode(at:2,point:.init(x:x*10,y:y*10))]
            XCTAssertEqual(FieldSpriteAnimation.travel(nodes,time:0.5).facing,direction)
            XCTAssertEqual(FieldSpriteAnimation.travel(nodes,time:1.5).facing,direction)
            XCTAssertEqual(FieldSpriteAnimation.travel(nodes,time:1.5).stage,.ready)
        }
        XCTAssertEqual(FieldFacing.turn(from:.northWest,to:.northEast,fraction:0.5),.north)
        XCTAssertEqual(FieldFacing.turn(from:.northEast,to:.northWest,fraction:0.5),.north)
    }

    func testFieldSpriteTransfersFollowBothThrowsAndRelayWithoutChangingSavedPlay() throws {
        for play in [doublePlay(),relayFly()] {
            let data=try JSONEncoder().encode(play)
            for event in FieldSpriteAnimation.throwsIn(play) {
                XCTAssertEqual(FieldSpriteAnimation.motion(play,index:event.fielder,time:event.caughtAt).stage,.catchBall)
                XCTAssertEqual(FieldSpriteAnimation.motion(play,index:event.fielder,time:event.releaseAt-0.01).stage,.windup)
                XCTAssertEqual(FieldSpriteAnimation.motion(play,index:event.fielder,time:event.releaseAt).stage,.release)
                XCTAssertEqual(FieldSpriteAnimation.motion(play,index:event.fielder,time:event.releaseAt+0.15).stage,.followThrough)
                XCTAssertEqual(FieldSpriteAnimation.motion(play,index:event.receiver,time:event.receivedAt).stage,.catchBall)
            }
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
        let noThrow=fly(outs:2,before:[nil,nil,nil])
        XCTAssertTrue(FieldSpriteAnimation.throwsIn(noThrow).isEmpty)
        XCTAssertEqual(FieldSpriteAnimation.motion(noThrow,index:noThrow.fielder,time:noThrow.pickupAt).stage,.catchBall)
    }

    func testFieldSpriteHandIsContinuousAtReleaseAndReturnsAfterFollowThroughForBothHands() {
        for facing in FieldFacing.allCases {for left in [false,true] {
            let windup=FieldSpriteMotion(facing:facing,stage:.windup,progress:1)
            let release=FieldSpriteMotion(facing:facing,stage:.release)
            let follow=FieldSpriteMotion(facing:facing,stage:.followThrough,progress:0)
            XCTAssertEqual(windup.throwingHand(left:left).x,release.throwingHand(left:left).x,accuracy:0.000001)
            XCTAssertEqual(windup.throwingHand(left:left).y,release.throwingHand(left:left).y,accuracy:0.000001)
            XCTAssertEqual(follow.throwingHand(left:left),release.throwingHand(left:left))
            XCTAssertEqual(FieldSpriteMotion(facing:facing,stage:.followThrough,progress:1).glove(left:left),FieldSpriteMotion(facing:facing,stage:.ready).glove(left:left))
            XCTAssertEqual(FieldSpriteMotion(facing:facing,stage:.gather,progress:1).glove(left:left),FieldSpriteMotion(facing:facing,stage:.ready).glove(left:left))
            XCTAssertEqual(FieldSpriteMotion(facing:facing,stage:.followThrough,progress:1).throwingHand(left:left),FieldSpriteMotion(facing:facing,stage:.ready).throwingHand(left:left))
        }}
        XCTAssertNotEqual(FieldSpriteMotion(facing:.south,stage:.windup,progress:0.5).throwingHand(left:true),FieldSpriteMotion(facing:.south,stage:.windup,progress:0.5).throwingHand(left:false))
    }

    func testDirectionalSpriteContactSheetAndDugoutRender() throws {
        let view=Canvas { context,size in
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(GameTheme.navy))
            for (i,facing) in FieldFacing.allCases.enumerated() {
                FieldActorArt.draw(in:context,at:CGPoint(x:35+i*68,y:85),scale:2,motion:.init(facing:facing,stage:.run,gait:.pi/2),kit:0x80464b,skin:0xefbe91,hair:0x68432e,number:47,left:false,selected:i==0)
                context.draw(Text(String(describing:facing)).font(.system(size:10)).foregroundStyle(.white),at:CGPoint(x:35+i*68,y:105))
            }
            let stages:[FieldSpriteStage]=[.catchBall,.gather,.windup,.release,.followThrough,.ready]
            for (i,stage) in stages.enumerated() {
                FieldActorArt.draw(in:context,at:CGPoint(x:45+i*85,y:195),scale:2,motion:.init(facing:.southEast,stage:stage,progress:stage == .windup ? 0.5:0.8),kit:0x214e72,skin:0xc88d62,hair:0x242b35,number:18,left:i%2 == 0,selected:false)
                context.draw(Text(String(describing:stage)).font(.system(size:11)).foregroundStyle(.white),at:CGPoint(x:45+i*85,y:223))
            }
        }.frame(width:550,height:250)
        let renderer=ImageRenderer(content:view);renderer.scale=2
        let image=try XCTUnwrap(renderer.uiImage),attachment=XCTAttachment(image:image)
        attachment.name="Eight-direction running and catch-transfer-throw sprites";attachment.lifetime = .keepAlways;add(attachment)
        XCTAssertEqual(image.size.width,550)
    }

    func testSavedBallUsesThrowingHandAtReleaseAndGloveAtReceiptForBothHands() throws {
        for play in [doublePlay(),relayFly()] {
            let data=try JSONEncoder().encode(play)
            for event in FieldSpriteAnimation.throwsIn(play) {for left in [false,true] {
                let release=FieldSpriteAnimation.motion(play,index:event.fielder,time:event.releaseAt)
                let hand=release.throwingHand(left:left)
                let actual=FieldSpriteAnimation.ballOffset(play,time:event.releaseAt,leftIndex:left ? event.fielder:nil)
                XCTAssertEqual(actual.x,hand.x+release.bodyOffset.x,accuracy:0.000001)
                XCTAssertEqual(actual.y,hand.y+release.bodyOffset.y,accuracy:0.000001)
                let received=FieldSpriteAnimation.motion(play,index:event.receiver,time:event.receivedAt)
                let glove=received.glove(left:left)
                let caught=FieldSpriteAnimation.ballOffset(play,time:event.receivedAt,leftIndex:left ? event.receiver:nil)
                XCTAssertEqual(caught.x,glove.x+received.bodyOffset.x,accuracy:0.000001)
                XCTAssertEqual(caught.y,glove.y+received.bodyOffset.y,accuracy:0.000001)
            }}
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
    }

    func testHomePlateProjectionExpandsInfieldAndKeepsEveryPositionVisible() throws {
        let size=CGSize(width:390,height:460)
        func point(_ p:FieldPoint) -> CGPoint {InplayFieldProjection.point(p,size:size)}
        let home=point(DetailedFieldRules.bases[0]),second=point(DetailedFieldRules.bases[2])
        XCTAssertGreaterThan(home.y-second.y,InplayFieldProjection.viewport(size).height*0.33)
        let first=point(DetailedFieldRules.bases[1]),third=point(DetailedFieldRules.bases[3])
        XCTAssertGreaterThan(abs(first.x-third.x),size.width*0.42)
        XCTAssertGreaterThan(home.y-point(DetailedFieldRules.positions[0]).y,95)
        for p in DetailedFieldRules.positions+DetailedFieldRules.bases {
            let screen=point(p)
            XCTAssertGreaterThan(screen.x,3);XCTAssertLessThan(screen.x,size.width-3)
            XCTAssertGreaterThan(screen.y,50);XCTAssertLessThan(screen.y,size.height)
            XCTAssertEqual(point(.init(x:-p.x,y:p.y)).x,size.width-screen.x,accuracy:0.000001)
        }
        var previous=point(.init(x:0,y:-6)).y
        for depth in 0...125 {
            let next=point(.init(x:0,y:Double(depth))).y
            XCTAssertLessThan(next,previous);previous=next
        }
        for play in [doublePlay(),fly(),relayFly()] {
            let data=try JSONEncoder().encode(play)
            let view=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),animated:false,scoreText:"H 2 : 1 A") {}
                .frame(width:390,height:500)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            let attachment=XCTAttachment(image:try XCTUnwrap(renderer.uiImage))
            attachment.name="Infield home plate camera \(play.fly == nil ? "ground":"air") \(play.relay != nil ? "relay":"direct")"
            attachment.lifetime = .keepAlways;add(attachment)
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
    }

    func testArcadeBackdropLandmarksAndPerspectiveScaleMatchLiveLayers() throws {
        let size=InplayStadiumArt.size
        let landmarks:[(FieldPoint,CGPoint)]=[
            (DetailedFieldRules.bases[0],CGPoint(x:512,y:1135)),
            (DetailedFieldRules.bases[1],CGPoint(x:997,y:765)),
            (DetailedFieldRules.bases[2],CGPoint(x:512,y:609)),
            (DetailedFieldRules.bases[3],CGPoint(x:27,y:765)),
            (DetailedFieldRules.positions[0],CGPoint(x:512,y:786))]
        for (world,expected) in landmarks {
            let screen=InplayFieldProjection.point(world,size:size)
            let viewport=InplayFieldProjection.viewport(size)
            XCTAssertEqual(screen.x,viewport.minX+expected.x*0.95,accuracy:8)
            XCTAssertEqual(screen.y,viewport.minY+expected.y*0.95,accuracy:8)
        }
        let near=InplayFieldProjection.actorScale(.init(x:0,y:0),size:size)
        let far=InplayFieldProjection.actorScale(.init(x:0,y:80),size:size)
        XCTAssertGreaterThan(near,far)
        XCTAssertEqual(InplayFieldProjection.actorScale(.init(x:0,y:80),size:.init(width:512,height:768)),far/2,accuracy:0.000001)
        XCTAssertEqual(InplayFieldProjection.facing(.north,at:.init(x:32,y:62),size:size),.northWest)
        XCTAssertNotNil(InplayStadiumArt.image)
        let phone=CGSize(width:390,height:585)
        for feet in DetailedFieldRules.bases+DetailedFieldRules.positions {
            let point=InplayFieldProjection.point(feet,size:phone)
            let reach=FieldActorArt.horizontalReach*InplayFieldProjection.actorScale(feet,size:phone)
            XCTAssertGreaterThan(point.x-reach,0)
            XCTAssertLessThan(point.x+reach,phone.width)
        }
    }

    func testProjectedBallStaysAtHandsAndGlovesAcrossBothHandsRelayAndDoublePlay() throws {
        let size=CGSize(width:390,height:585)
        for play in [doublePlay(),relayFly()] {
            let data=try JSONEncoder().encode(play)
            for event in FieldSpriteAnimation.throwsIn(play) {for left in [false,true] {
                for (index,time,release) in [(event.fielder,event.releaseAt,true),(event.receiver,event.receivedAt,false)] {
                    let feet=FieldNode.sample(play.fielders[index],at:time)
                    let origin=InplayFieldProjection.point(feet,size:size),u=InplayFieldProjection.actorScale(feet,size:size)
                    let motion=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:index,time:time),at:feet,size:size)
                    let anchor=FieldRasterArt.contact(motion,kind:index == 1 ? "catcher":"fielder",left:left,hand:release) ?? (release ? motion.throwingHand(left:left):motion.glove(left:left))
                    let actual=FieldBallPresentation.point(play,time:time,size:size,leftIndex:left ? index:nil)
                    XCTAssertEqual(actual.x,origin.x+(anchor.x+motion.bodyOffset.x)*u,accuracy:0.2)
                    XCTAssertEqual(actual.y,origin.y+(anchor.y+motion.bodyOffset.y)*u,accuracy:0.2)
                    let before=FieldBallPresentation.point(play,time:max(0,time-0.00001),size:size,leftIndex:left ? index:nil)
                    XCTAssertLessThan(hypot(actual.x-before.x,actual.y-before.y),0.2)
                }
            }}
            for step in 0...100 {
                let p=FieldBallPresentation.point(play,time:play.duration*Double(step)/100,size:size,leftIndex:play.fielder)
                XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            }
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
    }

    func testRasterKindsDirectionsAndPoseWeightsStayAlignedForBothHands() throws {
        let manifest=try XCTUnwrap(FieldRasterArt.manifest)
        XCTAssertEqual(Set(manifest.kinds.keys),Set(["fielder","runner","catcher"]))
        for kind in ["fielder","runner","catcher"] {for facing in FieldFacing.allCases {for left in [false,true] {
            for stage in [FieldSpriteStage.ready,.run,.catchBall,.gather,.windup,.release,.followThrough] {
                let m=FieldSpriteMotion(facing:facing,stage:stage,progress:0.4,gait:1,airCatch:kind == "fielder",willThrow:true)
                let samples=FieldRasterArt.samples(m,kind:kind,left:left)
                XCTAssertFalse(samples.isEmpty)
                XCTAssertEqual(samples.reduce(0){$0+$1.weight},1,accuracy:0.00001)
                for sample in samples {
                    XCTAssertLessThanOrEqual(sample.frame.rect[2]*sample.unit/2+abs(m.bodyOffset.x),FieldActorArt.horizontalReach+0.01)
                    let image=try XCTUnwrap(FieldRasterArt.image(sample,kit:0x316841,skin:0xba7750,hair:0x382416,number:47,back:facing.back))
                    XCTAssertEqual(image.cgImage?.width,Int(sample.frame.rect[2]))
                }
                let p=try XCTUnwrap(FieldRasterArt.contact(m,kind:kind,left:left,hand:stage == .release))
                XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            }
        }}}
    }
    func testRasterPersonalizationAndGlovelessRunnerAreDistinct() throws {
        let runner=FieldRasterArt.samples(.init(facing:.north,stage:.ready),kind:"runner",left:false)[0]
        XCTAssertTrue(runner.frame.file.hasPrefix("runner-"))
        let catcher=FieldRasterArt.samples(.init(facing:.north,stage:.ready),kind:"catcher",left:false)[0]
        XCTAssertTrue(catcher.frame.file.hasPrefix("catcher-"))
        let normal=try XCTUnwrap(FieldRasterArt.image(runner,kit:0x316841,skin:0xba7750,hair:0x382416,number:47,back:true)?.pngData())
        let changed=try XCTUnwrap(FieldRasterArt.image(runner,kit:0x7e2835,skin:0xf5c799,hair:0x9e773d,number:12,back:true)?.pngData())
        XCTAssertNotEqual(normal,changed)
        for variant in [(0x7e2835,0xba7750,0x382416,47),(0x316841,0xf5c799,0x382416,47),(0x316841,0xba7750,0x9e773d,47),(0x316841,0xba7750,0x382416,12)] {
            let image=try XCTUnwrap(FieldRasterArt.image(runner,kit:variant.0,skin:variant.1,hair:variant.2,number:variant.3,back:true)?.pngData())
            XCTAssertNotEqual(normal,image)
        }
        let view=Canvas {context,_ in
            for (row,kind) in ["fielder","runner","catcher"].enumerated() {
                for (column,facing) in FieldFacing.allCases.enumerated() {
                    FieldRasterArt.draw(in:context,at:CGPoint(x:30+column*64,y:55+row*80),scale:1.6,motion:.init(facing:facing,stage:row == 1 ? .run:.release,progress:0.5,gait:1),kind:kind,
                        kit:row == 1 ? 0x7e2835:0x316841,skin:0xba7750,hair:0x382416,number:47,left:false,selected:false,out:false)
                }
            }
        }.frame(width:540,height:250).background(GameTheme.board)
        let renderer=ImageRenderer(content:view);renderer.scale=2
        let image=try XCTUnwrap(renderer.uiImage)
        let attachment=XCTAttachment(image:image);attachment.name="Raster fielders runners catchers eight directions";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testRasterGatherToWindupAndReleaseAnchorsAreContinuous() throws {
        for kind in ["fielder","catcher"] {for facing in FieldFacing.allCases {for left in [false,true] {
            let gather=try XCTUnwrap(FieldRasterArt.contact(.init(facing:facing,stage:.gather,progress:1,willThrow:true),kind:kind,left:left,hand:false))
            let windup=try XCTUnwrap(FieldRasterArt.contact(.init(facing:facing,stage:.windup,progress:0,willThrow:true),kind:kind,left:left,hand:true))
            XCTAssertEqual(gather.x,windup.x,accuracy:0.00001);XCTAssertEqual(gather.y,windup.y,accuracy:0.00001)
            let ready=try XCTUnwrap(FieldRasterArt.contact(.init(facing:facing,stage:.ready),kind:kind,left:left,hand:false))
            let held=try XCTUnwrap(FieldRasterArt.contact(.init(facing:facing,stage:.gather,progress:1),kind:kind,left:left,hand:false))
            XCTAssertEqual(ready.x,held.x,accuracy:0.00001);XCTAssertEqual(ready.y,held.y,accuracy:0.00001)
        }}}
    }

    private func battedPlay(_ ball:MatchBattedBall,runner:Double=60,stats:MatchFieldStats?=nil) -> MatchDetailedPlay {
        var play=ball.kind.airborne ? DetailedFieldRules.resolveFly(half:0,order:0,landing:ball.landing,flight:ball.flight,
            runners:[nil,nil,nil],batter:FieldRunnerProfile(speed:runner,own:true),outs:0,stats:stats,defending:stats != nil,ownBatter:true,relayEnabled:true)
            : DetailedFieldRules.resolve(half:0,order:0,landing:ball.landing,flight:ball.flight,
            runners:[nil,nil,nil],batter:FieldRunnerProfile(speed:runner,own:true),outs:0,stats:stats,defending:stats != nil,ownBatter:true,
            doublePlayEnabled:true,groundBall:ball.kind == .ground,relayEnabled:true)
        play.version=5;play.ball=ball.nodes+play.ball.filter {$0.at>ball.flight};play.battedBall=ball
        return play
    }
    func testBattedSpeedPowerAccuracyBuntControlAndDistinctTrajectories() throws {
        func shot(_ q:Double=1,_ p:Double=60,_ draw:Double=0.5,_ bunt:Bool=false) -> MatchBattedBall {
            .make(quality:q,contact:60,power:p,bunt:bunt,speedDraw:0.5,angleDraw:draw,directionDraw:0.5)
        }
        XCTAssertGreaterThan(shot(1,100).speed,shot(1,0).speed)
        XCTAssertGreaterThan(shot(1).speed,shot(0.2).speed)
        let ground=shot(1,60,0.1),line=shot(),fly=shot(1,60,0.9),bunt=shot(1,60,0.3,true),pop=shot(0,60,0.99,true)
        XCTAssertEqual([ground.kind,line.kind,fly.kind,bunt.kind,pop.kind],[.ground,.line,.fly,.bunt,.buntPop])
        XCTAssertLessThan(bunt.speed,shot(0.2,60,0.3,true).speed)
        XCTAssertLessThan(bunt.distance,shot(0.2,60,0.3,true).distance)
        XCTAssertLessThan(bunt.distance,ground.distance)
        XCTAssertLessThan(line.height(at:line.flight/2),fly.height(at:fly.flight/2))
        let early=ground.point(at:ground.flight*0.25).distance(to:ground.point(at:ground.flight*0.125))
        let late=ground.point(at:ground.flight*0.875).distance(to:ground.point(at:ground.flight*0.75))
        XCTAssertGreaterThan(early,late)
        for ball in [ground,line,fly,bunt,pop] {
            XCTAssertEqual(ball.nodes.count,25);XCTAssertEqual(ball.nodes.first?.point,DetailedFieldRules.bases[0])
            XCTAssertEqual(ball.nodes.last!.point.distance(to:ball.landing),0,accuracy:0.000001)
            XCTAssertEqual(ball.height(at:0),0);XCTAssertEqual(ball.height(at:ball.flight),0,accuracy:0.000001)
            try battedPlay(ball).validate()
        }
    }
    func testBattedBoundaryInputsStayFiniteAndDirectionUsesContactOffsets() throws {
        for q in [0.0,0.5,1] {for p in [0.0,50,100] {for draw in [0.0,0.5,0.999999] {for bunt in [false,true] {
            let ball=MatchBattedBall.make(quality:q,contact:p,power:p,bunt:bunt,offsetX:0.2,offsetY:-0.2,timing:0.1,speedDraw:draw,angleDraw:draw,directionDraw:draw)
            XCTAssertNoThrow(try battedPlay(ball).validate(),"q=\(q) power=\(p) draw=\(draw) bunt=\(bunt) kind=\(ball.kind) speed=\(ball.speed) flight=\(ball.flight)")
            XCTAssertTrue(ball.kmh.isFinite)
        }}}}
        let left=MatchBattedBall.make(quality:0.8,contact:60,power:60,bunt:false,offsetX:-0.1,timing:-0.08,speedDraw:0.5,angleDraw:0.5,directionDraw:0.5)
        let right=MatchBattedBall.make(quality:0.8,contact:60,power:60,bunt:false,offsetX:0.1,timing:0.08,speedDraw:0.5,angleDraw:0.5,directionDraw:0.5)
        XCTAssertLessThan(left.landing.x,0);XCTAssertGreaterThan(right.landing.x,0)
    }
    func testBattedArrivalChangesSafeOutAndRunnerGrowthStillMatters() throws {
        func ball(_ speed:Double) -> MatchBattedBall {
            MatchBattedBall(kind:.ground,quality:0.8,contact:60,power:60,speed:speed,angle:0,direction:-25,distance:30,flight:30/(speed*0.68))
        }
        let fast=battedPlay(ball(30)),slow=battedPlay(ball(10))
        try fast.validate();try slow.validate()
        XCTAssertLessThan(fast.controlAt,slow.controlAt)
        XCTAssertTrue(fast.out);XCTAssertFalse(slow.out)
        let slowRunner=battedPlay(ball(30),runner:0),fastRunner=battedPlay(ball(30),runner:100)
        XCTAssertLessThan(fastRunner.runnerAt!,slowRunner.runnerAt!)
    }
    func testBattedNewGamesResumeDeterministicallyForBothRolesAndRejectCorruption() throws {
        for role in ["batter","pitcher"] {for seed in 1...12 {
            var original=game(seed,role:role);original.detailedFieldVersion=5;original.battedBallVersion=1
            original.fieldPlays=[];original.runnerProfiles=[nil,nil,nil]
            var direct=original
            try original.advance(.automatic)
            while !direct.completed {
                try direct.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "pitcher" ? "four-seam":nil)
                direct=try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(direct))
                try direct.validateDetailedField()
            }
            XCTAssertEqual(direct,original)
            XCTAssertTrue(original.fieldPlays?.allSatisfy {$0.battedBall != nil} == true)
        }}
        var valid=game(9);valid.detailedFieldVersion=5;valid.battedBallVersion=1;valid.fieldPlays=[];valid.runnerProfiles=[nil,nil,nil]
        try valid.advance(.automatic);try valid.validateDetailedField()
        var corrupt=valid;corrupt.battedBallVersion=2;XCTAssertThrowsError(try corrupt.validateDetailedField())
        corrupt=valid;corrupt.fieldPlays![0].battedBall=nil;XCTAssertThrowsError(try corrupt.validateDetailedField())
        corrupt=valid;corrupt.fieldPlays![0].battedBall?.version=2;XCTAssertThrowsError(try corrupt.validateDetailedField())
        corrupt=valid;corrupt.fieldPlays![0].ball[1]=FieldNode(at:0.01,point:FieldPoint(x:999,y:999));XCTAssertThrowsError(try corrupt.validateDetailedField())
    }
    func testBattedManualAccuracyAndWatchAreUsedBeforeFairBallResolution() throws {
        for action in [MatchInput.swing,.bunt] {
            var state=game(12);state.detailedFieldVersion=5;state.battedBallVersion=1;state.fieldPlays=[];state.runnerProfiles=[nil,nil,nil]
            let delivery=state.delivery()
            var miss=state,watch=state
            try miss.advance(action,control:ManualMatchInput(x:delivery.x,y:delivery.y,timing:0))
            try watch.advance(action,control:ManualMatchInput())
            XCTAssertFalse(miss.fieldPlays!.contains {$0.ownBatter});XCTAssertFalse(watch.fieldPlays!.contains {$0.ownBatter})
            try state.advance(action,control:ManualMatchInput(x:delivery.x,y:delivery.y,timing:MatchDelivery.contactPhase))
            let ball=try XCTUnwrap(state.fieldPlays!.first {$0.ownBatter}?.battedBall)
            XCTAssertEqual(ball.quality,1,accuracy:0.000001)
            XCTAssertEqual(ball.kind == .bunt || ball.kind == .buntPop,action == .bunt)
        }
    }
    func testBattedLegacyAbsenceKeepsOldRuleAndNoMetadataIsBackfilled() throws {
        var old=game(42);old.detailedFieldVersion=5;old.fieldPlays=[];old.runnerProfiles=[nil,nil,nil]
        let data=try JSONEncoder().encode(old)
        XCTAssertNil((try JSONSerialization.jsonObject(with:data) as? [String:Any])?["battedBallVersion"])
        var copy=try JSONDecoder().decode(CareerMatch.self,from:data)
        try old.advance(.automatic);try copy.advance(.automatic)
        XCTAssertEqual(old,copy);XCTAssertNil(copy.battedBallVersion)
        XCTAssertTrue(copy.fieldPlays!.allSatisfy {$0.battedBall == nil})
        try copy.validateDetailedField()
    }

    func testRunnerStartAccelerationPreservesReactionAndAllSavedBaseArrivals() throws {
        let play=detailed(-45,85,speed:100,flight:3.5)
        let runner=try XCTUnwrap(play.runners.first {$0.from == 0})
        let first=try XCTUnwrap(zip(runner.nodes,runner.nodes.dropFirst()).first {$0.0.point != $0.1.point})
        let before=FieldSpriteAnimation.runner(runner,play:play,time:first.0.at-0.01)
        XCTAssertEqual(before.point,first.0.point);XCTAssertEqual(before.motion.stage,.ready)
        let moving=FieldSpriteAnimation.runner(runner,play:play,time:first.0.at+0.08)
        XCTAssertEqual(moving.motion.runnerPose,.accelerate)
        XCTAssertLessThan(first.0.point.distance(to:moving.point),first.0.point.distance(to:FieldNode.sample(runner.nodes,at:first.0.at+0.08)))
        for node in runner.nodes {
            XCTAssertEqual(FieldSpriteAnimation.runner(runner,play:play,time:node.at).point,node.point)
        }
        let saved=try JSONEncoder().encode(play)
        for t in stride(from:0.0,through:play.duration,by:0.03) {_=FieldSpriteAnimation.runner(runner,play:play,time:t)}
        XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:saved))
    }

    func testRunnerBaseTurnOverrunAndSlideHaveSeparatePosesWithoutInventingAdvance() throws {
        let single=detailed(speed:100),batter=try XCTUnwrap(single.runners.first {$0.from == 0})
        XCTAssertEqual(batter.destination,1);XCTAssertFalse(batter.out)
        XCTAssertEqual(FieldSpriteAnimation.runner(batter,play:single,time:batter.arrival).point,DetailedFieldRules.bases[1])
        let overrun=FieldSpriteAnimation.runner(batter,play:single,time:batter.arrival+0.18)
        XCTAssertEqual(overrun.motion.runnerPose,.decelerate)
        XCTAssertGreaterThan(overrun.point.x,DetailedFieldRules.bases[1].x)
        let stop=FieldSpriteAnimation.runner(batter,play:single,time:single.duration)
        XCTAssertEqual(stop.motion.stage,.ready);XCTAssertEqual(stop.motion.runnerPose,.settled)
        XCTAssertEqual(single.afterRunners[0],batter.profile)
        let doubleHit=detailed(-45,85,speed:100,flight:3.5)
        let second=try XCTUnwrap(doubleHit.runners.first {$0.from == 0})
        let firstAt=try XCTUnwrap(second.arrival(at:1))
        XCTAssertEqual(FieldSpriteAnimation.runner(second,play:doubleHit,time:firstAt+0.04).motion.runnerPose,.turn)
        for base in [2,3] {
            var runner=second;runner.destination=base
            runner.nodes=[.init(at:0,point:DetailedFieldRules.bases[base-1]),.init(at:3,point:DetailedFieldRules.bases[base])]
            let slide=FieldSpriteAnimation.runner(runner,play:doubleHit,time:2.9)
            XCTAssertEqual(slide.motion.runnerPose,.slide)
            XCTAssertEqual(FieldSpriteAnimation.runner(runner,play:doubleHit,time:3).point,DetailedFieldRules.bases[base])
            XCTAssertEqual(FieldSpriteAnimation.runner(runner,play:doubleHit,time:3.3).motion.runnerPose,.settled)
        }
        let outPlay=detailed(speed:0),retired=try XCTUnwrap(outPlay.runners.first {$0.from == 0})
        XCTAssertTrue(retired.out)
        let stopped=FieldSpriteAnimation.runner(retired,play:outPlay,time:outPlay.duration)
        XCTAssertEqual(stopped.point,retired.nodes.last?.point)
        XCTAssertNotEqual(stopped.motion.runnerPose,.decelerate)
        XCTAssertNotEqual(stopped.motion.runnerPose,.slide)
    }

    func testRunnerTagUpWaitAndReducedMotionUseSavedDepartureAndBagStills() throws {
        let play=fly(speed:100),runner=try XCTUnwrap(play.runners.first {$0.from == 3})
        for t in [0,play.flight-0.01,play.flight] {
            let wait=FieldSpriteAnimation.runner(runner,play:play,time:t)
            XCTAssertEqual(wait.motion.runnerPose,.tagUp);XCTAssertEqual(wait.point,DetailedFieldRules.bases[3])
        }
        let departure=try XCTUnwrap(zip(runner.nodes,runner.nodes.dropFirst()).first {$0.0.point != $0.1.point}).0.at
        XCTAssertEqual(FieldSpriteAnimation.runner(runner,play:play,time:departure+0.08).motion.runnerPose,.accelerate)
        XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:departure,reduced:true,animated:true),departure)
        let single=detailed(speed:100),batter=try XCTUnwrap(single.runners.first {$0.from == 0})
        let reduced=FieldSpriteAnimation.runner(batter,play:single,time:single.duration,reduced:true)
        XCTAssertEqual(reduced.point,DetailedFieldRules.bases[1])
        XCTAssertEqual(FieldSpriteAnimation.runner(runner,play:play,time:runner.arrival).point,DetailedFieldRules.bases[4])
    }

    func testForceReceiveTagAndDoublePlayPivotKeepSavedBallContactsAndOpaqueFrames() throws {
        let force=doublePlay(),tag=fly(speed:100)
        XCTAssertEqual(FieldSpriteAnimation.motion(force,index:force.receiver,time:force.ballAt).baseReceive,.force)
        let second=try XCTUnwrap(force.secondThrow)
        XCTAssertEqual(FieldSpriteAnimation.motion(force,index:second.receiver,time:second.ballAt).baseReceive,.force)
        XCTAssertEqual(FieldSpriteAnimation.motion(force,index:force.receiver,time:second.releaseAt).stage,.release)
        XCTAssertEqual(FieldSpriteAnimation.motion(tag,index:tag.receiver,time:tag.controlAt).baseReceive,.tag)
        for play in [force,tag] {for left in [false,true] {
            let time=play.controlAt,at=FieldNode.sample(play.fielders[play.receiver],at:time),size=CGSize(width:390,height:585)
            let motion=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:play.receiver,time:time),at:at,size:size)
            let kind=play.receiver == 1 ? "catcher":"fielder"
            let contact=try XCTUnwrap(FieldRasterArt.contact(motion,kind:kind,left:left,hand:false))
            let offset=FieldBallPresentation.handOffset(play,time:time,size:size,leftIndex:left ? play.receiver:nil)
            let scale=InplayFieldProjection.actorScale(at,size:size)
            XCTAssertEqual(offset.x,(contact.x+motion.bodyOffset.x)*scale,accuracy:0.00001)
            XCTAssertEqual(offset.y,(contact.y+motion.bodyOffset.y)*scale,accuracy:0.00001)
            XCTAssertEqual(FieldRasterArt.samples(motion,kind:kind,left:left).count,1)
        }}
    }

    func testRunnerArrivalMotionContactSheetAndReplayRender() throws {
        let poses:[FieldRunnerPose]=[.accelerate,.turn,.decelerate,.slide,.tagUp,.settled]
        let view=Canvas {context,_ in
            for row in 0..<2 {for col in poses.indices {
                let motion=FieldSpriteMotion(facing:row == 0 ? .east:.west,stage:col<4 ? .run:.ready,gait:1,runnerPose:poses[col],arrivalProgress:0.5)
                FieldRasterArt.draw(in:context,at:CGPoint(x:42+col*78,y:80+row*90),scale:2,motion:motion,kind:"runner",kit:0x316841,skin:0xba7750,hair:0x382416,number:47,left:false,selected:false,out:false)
            }}
            for (col,style) in [FieldBaseReceive.force,.tag].enumerated() {
                let motion=FieldSpriteMotion(facing:.west,stage:.catchBall,progress:1,chestCatch:style == .force,baseReceive:style,arrivalProgress:0.5,receivePose:style == .tag ? .tag:.secure)
                FieldRasterArt.draw(in:context,at:CGPoint(x:110+col*200,y:270),scale:2,motion:motion,kind:col == 0 ? "fielder":"catcher",kit:0x8b3440,skin:0xefbe91,hair:0x263b48,number:13,left:false,selected:false,out:false)
            }
        }.frame(width:480,height:300).background(GameTheme.board)
        let image=try XCTUnwrap(ImageRenderer(content:view).uiImage)
        let attachment=XCTAttachment(image:image);attachment.name="Runner start turn overrun slide tag-up and force-tag poses";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testDedicatedArrivalFramesCoverEightDirectionsBothHandsWithoutRunPoseDeformation() throws {
        for kind in ["runner","fielder","catcher"] {for facing in FieldFacing.allCases {for left in [false,true] {
            var actions=Set<String>()
            for step in 0..<3 {
                var motion=FieldSpriteMotion(facing:facing,stage:.catchBall,progress:1)
                if kind == "runner" {motion.runnerPose = .slide;motion.arrivalProgress=[0.1,0.5,0.95][step]}
                else {motion.baseReceive = .tag;motion.receivePose=[.reach,.secure,.tag][step]}
                let samples=FieldRasterArt.samples(motion,kind:kind,left:left)
                XCTAssertEqual(samples.count,1)
                let sample=try XCTUnwrap(samples.first)
                XCTAssertEqual(sample.weight,1);XCTAssertEqual(motion.bodyOffset,.zero)
                XCTAssertEqual(sample.frame.file,"\(kind)-arrival-v1.png")
                XCTAssertLessThanOrEqual(sample.frame.rect[2]*sample.unit,26.0001)
                XCTAssertNotNil(sample.frame.referenceHeight);actions.insert(sample.frame.action)
                let cg=try XCTUnwrap(FieldRasterArt.image(sample,kit:0x316841,skin:0xba7750,hair:0x382416,number:47,back:facing.back)?.cgImage)
                XCTAssertGreaterThan(cg.width,100);XCTAssertGreaterThan(cg.height,100)
                let anchor=try XCTUnwrap(FieldRasterArt.contact(motion,kind:kind,left:left,hand:false))
                XCTAssertEqual(anchor.x,(sample.frame.glove[0]-sample.frame.pivot[0])*sample.unit*(sample.mirrored ? -1:1),accuracy:0.00001)
            }
            XCTAssertEqual(actions,kind == "runner" ? ["slideEnter","slideHold","slideRecover"]:["baseReach","baseSecure","baseTag"])
        }}}
    }

    func testSavedSlideArrivalSelectsRecoveryAfterStopAndReducedMotionHoldsOnePose() throws {
        let play=try FieldVerificationScenario.doubleHit.make()
        let runner=try XCTUnwrap(play.runners.first {$0.from == 0})
        for (offset,action) in [(-0.32,"slideEnter"),(-0.02,"slideHold"),(0.20,"slideRecover")] {
            let sample=FieldSpriteAnimation.runner(runner,play:play,time:runner.arrival+offset)
            XCTAssertEqual(FieldRasterArt.samples(sample.motion,kind:"runner",left:false).first?.frame.action,action)
            let still=FieldSpriteAnimation.runner(runner,play:play,time:runner.arrival+offset,reduced:true)
            XCTAssertEqual(FieldRasterArt.samples(still.motion,kind:"runner",left:false).first?.frame.action,"slideHold")
        }
    }

    func testReceiveCatchTagRecoveryFollowSavedTimesAndDoublePlayThrowWins() throws {
        let tag=fly(speed:100),force=doublePlay()
        for play in [tag,force] {
            let before=FieldSpriteAnimation.motion(play,index:play.receiver,time:play.ballAt-0.001)
            XCTAssertEqual(before.receivePose,.reach)
            let caught=FieldSpriteAnimation.motion(play,index:play.receiver,time:play.ballAt)
            XCTAssertEqual(caught.receivePose,.secure)
        }
        for time in [tag.ballAt-0.001,tag.ballAt] {
            let at=FieldNode.sample(tag.fielders[tag.receiver],at:time)
            let incoming=FieldNode.sample(tag.ball,at:max(0,tag.ballAt-0.12))
            let motion=FieldSpriteAnimation.motion(tag,index:tag.receiver,time:time)
            XCTAssertEqual(motion.facing,FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y),"Receive before turning toward the runner")
        }
        XCTAssertEqual(FieldSpriteAnimation.motion(tag,index:tag.receiver,time:tag.controlAt).receivePose,.tag)
        XCTAssertEqual(FieldSpriteAnimation.motion(tag,index:tag.receiver,time:tag.controlAt+0.2).receivePose,.recover)
        let second=try XCTUnwrap(force.secondThrow)
        let outgoing=FieldSpriteAnimation.motion(force,index:force.receiver,time:second.releaseAt)
        XCTAssertEqual(outgoing.stage,.release);XCTAssertEqual(outgoing.baseReceive,.none)
        XCTAssertEqual(FieldRasterArt.samples(outgoing,kind:"fielder",left:false).first?.frame.action,"release")
    }

    func testDedicatedArrivalSamplingLeavesAllSavedScenariosUnchanged() throws {
        for scenario in FieldVerificationScenario.allCases {
            let play=try scenario.make(),bytes=try JSONEncoder().encode(play)
            let saved=try JSONDecoder().decode(MatchDetailedPlay.self,from:bytes)
            for time in stride(from:0.0,through:play.duration,by:0.03) {
                for index in play.fielders.indices {
                    let motion=FieldSpriteAnimation.motion(play,index:index,time:time)
                    for left in [false,true] {_ = FieldRasterArt.samples(motion,kind:index == 1 ? "catcher":"fielder",left:left)}
                }
                for runner in play.runners {
                    let display=FieldSpriteAnimation.runner(runner,play:play,time:time)
                    _ = FieldRasterArt.samples(display.motion,kind:"runner",left:false)
                }
            }
            XCTAssertEqual(play,saved);try play.validate()
        }
    }

    func testDedicatedSlideReceiveAndTagContactSheetAndActualReplayFrames() throws {
        let view=Canvas {context,_ in
            for (row,kind) in ["runner","fielder","catcher"].enumerated() {
                for column in 0..<8 {for phase in 0..<3 {
                    let facing=FieldFacing.allCases[column]
                    var motion=FieldSpriteMotion(facing:facing,stage:.catchBall,progress:1)
                    if kind == "runner" {motion.runnerPose = .slide;motion.arrivalProgress=[0.1,0.5,0.95][phase]}
                    else {motion.baseReceive = .tag;motion.receivePose=[.reach,.secure,.tag][phase]}
                    FieldRasterArt.draw(in:context,at:CGPoint(x:60+column*72,y:68+(row*3+phase)*64),scale:1.8,motion:motion,kind:kind,kit:row == 0 ? 0x316841:0x8b3440,skin:0xba7750,hair:0x382416,number:47,left:false,selected:false,out:false)
                }}
            }
        }.frame(width:640,height:590).background(GameTheme.board)
        let renderer=ImageRenderer(content:view);renderer.scale=2
        let image=try XCTUnwrap(renderer.uiImage)
        let sheet=XCTAttachment(image:image);sheet.name="Dedicated arrival frames eight directions three phases three roles";sheet.lifetime = .keepAlways;add(sheet)
        for scenario in [FieldVerificationScenario.doubleHit,.doublePlay,.tagUp] {
            let play=try scenario.make()
            let time=scenario == .doubleHit ? try XCTUnwrap(play.runners.first {$0.from == 0}).arrival:play.controlAt
            let board=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:time,showsContactPoints:true,complete:{}).frame(width:390,height:585)
            let r=ImageRenderer(content:board);r.scale=2
            let frame=XCTAttachment(image:try XCTUnwrap(r.uiImage));frame.name="Dedicated arrival native \(scenario.rawValue)";frame.lifetime = .keepAlways;add(frame)
        }
    }

    func testDedicatedMisplaySpritesCoverBothKindsEightDirectionsBothHandsAndFourPoses() throws {
        for kind in ["fielder","catcher"] {for facing in FieldFacing.allCases {for left in [false,true] {
            var actions=Set<String>()
            for pose in [FieldErrorPose.spill,.reach,.scoop,.secured] {
                var motion=FieldSpriteMotion(facing:facing,stage:.catchBall,progress:1);motion.errorPose=pose
                let samples=FieldRasterArt.samples(motion,kind:kind,left:left)
                XCTAssertEqual(samples.count,1)
                let sample=try XCTUnwrap(samples.first);actions.insert(sample.frame.action)
                XCTAssertEqual(sample.frame.file,"\(kind)-misplay-v1.png");XCTAssertEqual(sample.weight,1)
                XCTAssertEqual(motion.bodyOffset,.zero);XCTAssertLessThanOrEqual(sample.frame.rect[2]*sample.unit,26.0001)
                XCTAssertNotNil(FieldRasterArt.image(sample,kit:0x316841,skin:0xba7750,hair:0x382416,number:47,back:facing.back))
                let glove=try XCTUnwrap(FieldRasterArt.contact(motion,kind:kind,left:left,hand:false))
                XCTAssertEqual(glove.x,(sample.frame.glove[0]-sample.frame.pivot[0])*sample.unit*(sample.mirrored ? -1:1),accuracy:0.00001)
            }
            XCTAssertEqual(actions,["spill","missReach","scoop","scoopSecure"])
        }}}
    }

    func testLooseErrorBallIsNotAttachedToFailedFielderOrReceiverBeforeSavedRecovery() throws {
        var stages=Set<Int>()
        for clean in [doublePlay(),relayFly(before:[FieldRunnerProfile(speed:60),nil,FieldRunnerProfile(speed:100)])] {
            for stage in FieldMisplayRules.opportunities(clean).map(\.stage) {
                let play=misplay(clean,stage:stage)
                guard let e=play.misplay else {continue};stages.insert(e.stage)
                let original=play
                for time in stride(from:e.at+0.001,to:e.recoveredAt,by:0.027) {
                    XCTAssertEqual(FieldSpriteAnimation.ballOffset(play,time:time,leftIndex:e.fielder),.zero)
                    for hand in [nil,e.recoverer] {
                        XCTAssertEqual(FieldBallPresentation.handOffset(play,time:time,size:CGSize(width:390,height:585),leftIndex:hand),.zero)
                    }
                }
                for left in [false,true] {
                    let size=CGSize(width:390,height:585),at=FieldNode.sample(play.fielders[e.recoverer],at:e.recoveredAt)
                    let motion=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:e.recoverer,time:e.recoveredAt),at:at,size:size)
                    let anchor=try XCTUnwrap(FieldRasterArt.contact(motion,kind:e.recoverer == 1 ? "catcher":"fielder",left:left,hand:false))
                    let offset=FieldBallPresentation.handOffset(play,time:e.recoveredAt,size:size,leftIndex:left ? e.recoverer:nil)
                    let scale=InplayFieldProjection.actorScale(at,size:size)
                    XCTAssertEqual(offset.x,anchor.x*scale,accuracy:0.00001);XCTAssertEqual(offset.y,anchor.y*scale,accuracy:0.00001)
                }
                XCTAssertEqual(play,original);try play.validate()
            }
        }
        XCTAssertTrue(stages.contains(0));XCTAssertTrue(stages.contains(1));XCTAssertTrue(stages.contains(3));XCTAssertTrue(stages.contains(5))
    }

    func testErrorScoopStartsOnlyAfterArrivalAndSecuresOnlyAtSavedRecoveryThenThrows() throws {
        for stage in [0,1,5] {
            let play=misplay(doublePlay(),stage:stage),e=try XCTUnwrap(play.misplay)
            let scoop=try XCTUnwrap(FieldMisplayAnimation.recoveryStart(play))
            XCTAssertLessThanOrEqual(scoop,e.recoveredAt)
            XCTAssertEqual(FieldNode.sample(play.fielders[e.recoverer],at:scoop),e.loosePoint)
            let before=FieldSpriteAnimation.motion(play,index:e.recoverer,time:scoop-0.001)
            XCTAssertNotEqual(before.errorPose,.scoop);XCTAssertNotEqual(before.errorPose,.secured)
            XCTAssertEqual(FieldSpriteAnimation.motion(play,index:e.recoverer,time:(scoop+e.recoveredAt)/2).errorPose,.scoop)
            XCTAssertEqual(FieldSpriteAnimation.motion(play,index:e.recoverer,time:e.recoveredAt).errorPose,.scoop)
            let windup=play.releaseAt-min(0.20,(play.releaseAt-e.recoveredAt)*0.50)
            if windup>e.recoveredAt+0.09 {XCTAssertEqual(FieldSpriteAnimation.motion(play,index:e.recoverer,time:e.recoveredAt+0.09).errorPose,.secured)}
            let thrown=FieldSpriteAnimation.motion(play,index:e.recoverer,time:play.releaseAt)
            XCTAssertEqual(thrown.stage,.release);XCTAssertEqual(thrown.errorPose,.none)
            XCTAssertEqual(FieldSpriteAnimation.throwsIn(play).first?.fielder,e.recoverer)
        }
    }

    func testFastAndSlowRecoveryTransfersStillShowSecuredPoseBeforeOriginalWindup() throws {
        for arm in [0.0,60,100] {
            let play=misplay(doublePlay(),stage:1,arm:arm),e=try XCTUnwrap(play.misplay)
            let secure=try XCTUnwrap(FieldMisplayAnimation.securedAt(play))
            let windup=play.releaseAt-min(0.20,(play.releaseAt-e.recoveredAt)*0.50)
            XCTAssertGreaterThan(secure,e.recoveredAt);XCTAssertLessThan(secure,windup)
            XCTAssertEqual(FieldSpriteAnimation.motion(play,index:e.recoverer,time:secure+0.0001).errorPose,.secured)
            XCTAssertTrue(FieldMisplayAnimation.moments(play).contains {abs($0-secure-0.001)<0.00001})
        }
    }

    func testWildThrowSourceReleasesFromHandAndNearbyReactionDoesNotClaimPossession() throws {
        for stage in [1,5] {
            let play=misplay(doublePlay(),stage:stage),e=try XCTUnwrap(play.misplay)
            XCTAssertEqual(FieldSpriteAnimation.motion(play,index:e.fielder,time:e.at).stage,.release)
            XCTAssertEqual(FieldSpriteAnimation.motion(play,index:e.fielder,time:e.at-0.01).stage,.windup)
            if let miss=FieldMisplayAnimation.missedReception(play) {
                XCTAssertNotEqual(miss.fielder,e.fielder)
                XCTAssertTrue((e.at...e.scatteredAt).contains(miss.at))
                let motion=FieldSpriteAnimation.motion(play,index:miss.fielder,time:miss.at)
                XCTAssertEqual(motion.errorPose,.reach)
                XCTAssertTrue(FieldMisplayAnimation.ballIsLoose(play,time:miss.at))
            }
            for left in [false,true] {
                let at=FieldNode.sample(play.fielders[e.fielder],at:e.at),size=CGSize(width:390,height:585)
                let m=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:e.fielder,time:e.at),at:at,size:size)
                let anchor=try XCTUnwrap(FieldRasterArt.contact(m,kind:e.fielder == 1 ? "catcher":"fielder",left:left,hand:true))
                let offset=FieldBallPresentation.handOffset(play,time:e.at,size:size,leftIndex:left ? e.fielder:nil)
                let scale=InplayFieldProjection.actorScale(at,size:size)
                XCTAssertEqual(offset.x,(anchor.x+m.bodyOffset.x)*scale,accuracy:0.00001)
                XCTAssertEqual(offset.y,(anchor.y+m.bodyOffset.y)*scale,accuracy:0.00001)
            }
        }
    }

    func testMisplayPresentationMomentsAndBounceUseOriginalTimelineAndReducedMotion() throws {
        for stage in [0,1] {
            let play=misplay(doublePlay(),stage:stage),e=try XCTUnwrap(play.misplay)
            let times=FieldMisplayAnimation.moments(play)
            XCTAssertTrue(times.contains(try XCTUnwrap(FieldMisplayAnimation.recoveryStart(play))))
            for time in times {XCTAssertTrue(time>=0 && time<=play.duration)}
            XCTAssertGreaterThan(try XCTUnwrap(FieldMisplayAnimation.lift(play,time:(e.at+e.scatteredAt)/2,height:585)),0)
            XCTAssertEqual(FieldReplayPresentation.lift(play,time:e.recoveredAt,height:585),0,accuracy:1e-12)
            let t=try XCTUnwrap(FieldMisplayAnimation.recoveryStart(play))
            XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:t,reduced:true,animated:true),t)
        }
        XCTAssertTrue(FieldMisplayAnimation.moments(doublePlay()).isEmpty)
        XCTAssertNil(FieldMisplayAnimation.motion(doublePlay(),index:0,time:0))
    }

    func testDedicatedMisplayContactSheetAndSavedErrorSequenceRenderReadOnly() throws {
        let poses:[FieldErrorPose]=[.spill,.reach,.scoop,.secured]
        let view=Canvas {context,_ in
            for (row,kind) in ["fielder","catcher"].enumerated() {
                for (column,facing) in FieldFacing.allCases.enumerated() {for (phase,pose) in poses.enumerated() {
                    var motion=FieldSpriteMotion(facing:facing,stage:.catchBall,progress:1);motion.errorPose=pose
                    FieldRasterArt.draw(in:context,at:CGPoint(x:60+column*72,y:65+(row*4+phase)*66),scale:1.8,motion:motion,kind:kind,kit:row == 0 ? 0x316841:0x8b3440,skin:0xba7750,hair:0x382416,number:47,left:false,selected:false,out:false)
                }}
            }
        }.frame(width:640,height:540).background(GameTheme.board)
        let r=ImageRenderer(content:view);r.scale=2
        let sheet=XCTAttachment(image:try XCTUnwrap(r.uiImage));sheet.name="Dedicated error miss scoop secured eight directions";sheet.lifetime = .keepAlways;add(sheet)
        for stage in [0,1] {
            let play=misplay(doublePlay(),stage:stage),e=try XCTUnwrap(play.misplay),original=play
            for (i,time) in [e.at+0.04,(e.recoveredAt+(FieldMisplayAnimation.recoveryStart(play) ?? e.recoveredAt))/2,play.releaseAt].enumerated() {
                let board=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:time,showsContactPoints:true,complete:{}).frame(width:390,height:585)
                let renderer=ImageRenderer(content:board);renderer.scale=2
                let shot=XCTAttachment(image:try XCTUnwrap(renderer.uiImage));shot.name="Native error sequence \(stage) phase \(i)";shot.lifetime = .keepAlways;add(shot)
            }
            XCTAssertEqual(play,original)
        }
    }

    func testCatcherRunningUsesTwoDedicatedFullBodyStridesForEightDirectionsBothHands() throws {
        for facing in FieldFacing.allCases {for left in [false,true] {
            var images=[Data](),actions=Set<String>()
            for gait in [-1.0,1] {
                let m=FieldSpriteMotion(facing:facing,stage:.run,gait:gait)
                let sample=try XCTUnwrap(FieldRasterArt.samples(m,kind:"catcher",left:left).first)
                XCTAssertEqual(sample.frame.file,"catcher-run-v1.png");XCTAssertEqual(sample.weight,1)
                XCTAssertLessThanOrEqual(sample.frame.rect[2]*sample.unit,26.0001);actions.insert(sample.frame.action)
                images.append(try XCTUnwrap(FieldRasterArt.image(sample,kit:0x316841,skin:0xba7750,hair:0x382416,number:47,back:false)?.pngData()))
            }
            XCTAssertEqual(actions,["runA","runB"]);XCTAssertNotEqual(images[0],images[1])
        }}
    }

    func testRelaySecureExtractAndPlantSelectDedicatedFramesAtUnchangedSavedTimes() throws {
        let play=relayFly(),relay=try XCTUnwrap(play.relay),original=play
        let times=FieldRelayTransfer.moments(play)
        XCTAssertEqual(times.count,3)
        for (index,time) in times.enumerated() {
            let m=FieldSpriteAnimation.motion(play,index:relay.fielder,time:time)
            XCTAssertTrue(m.relayTransfer);XCTAssertEqual(m.bodyOffset,.zero)
            XCTAssertTrue(time>relay.receiveAt && time<relay.releaseAt)
            for left in [false,true] {
                let s=try XCTUnwrap(FieldRasterArt.samples(m,kind:"fielder",left:left).first)
                XCTAssertEqual(s.frame.action,["transferSecure","transferExtract","transferPlant"][index])
                XCTAssertEqual(s.frame.file,"fielder-transfer-v1.png")
            }
            XCTAssertEqual(m.ballInThrowingHand,index>0)
        }
        let released=FieldSpriteAnimation.motion(play,index:relay.fielder,time:relay.releaseAt)
        XCTAssertFalse(released.relayTransfer);XCTAssertEqual(released.stage,.release)
        XCTAssertEqual(play,original);try play.validate()
    }

    func testRelayBallTransfersFromMittToBareHandUsingSameRasterPoseForBothHands() throws {
        let play=relayFly(),relay=try XCTUnwrap(play.relay),size=CGSize(width:390,height:585)
        for time in FieldRelayTransfer.moments(play) {for left in [false,true] {
            let feet=FieldNode.sample(play.fielders[relay.fielder],at:time)
            let m=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:relay.fielder,time:time),at:feet,size:size)
            let contact=try XCTUnwrap(FieldRasterArt.contact(m,kind:"fielder",left:left,hand:m.ballInThrowingHand))
            let offset=FieldBallPresentation.handOffset(play,time:time,size:size,leftIndex:left ? relay.fielder:nil)
            let scale=InplayFieldProjection.actorScale(feet,size:size)
            XCTAssertEqual(offset.x,(contact.x+m.bodyOffset.x)*scale,accuracy:0.00001)
            XCTAssertEqual(offset.y,(contact.y+m.bodyOffset.y)*scale,accuracy:0.00001)
        }}
    }

    func testDedicatedTransferFramesAreOpaqueAndHandAnchorsMatchAcrossEveryFacing() throws {
        for facing in FieldFacing.allCases {for left in [false,true] {
            for (stage,p) in [(FieldSpriteStage.gather,0.25),(.gather,0.75),(.windup,0.10)] {
                var m=FieldSpriteMotion(facing:facing,stage:stage,progress:p,willThrow:true);m.relayTransfer=true
                let sample=try XCTUnwrap(FieldRasterArt.samples(m,kind:"fielder",left:left).first)
                XCTAssertEqual(sample.weight,1);XCTAssertLessThanOrEqual(sample.frame.rect[2]*sample.unit,26.0001)
                let anchor=m.ballInThrowingHand ? sample.frame.hand:sample.frame.glove
                let contact=try XCTUnwrap(FieldRasterArt.contact(m,kind:"fielder",left:left,hand:m.ballInThrowingHand))
                XCTAssertEqual(contact.x,(anchor[0]-sample.frame.pivot[0])*sample.unit*(sample.mirrored ? -1:1),accuracy:0.00001)
                XCTAssertNotNil(FieldRasterArt.image(sample,kit:0x8b3440,skin:0xba7750,hair:0x382416,number:47,back:facing.back))
            }
        }}
    }

    func testRelayPresentationStillsUseSameTransferMomentsWithoutChangingMisplaysOrDoublePlays() throws {
        let relay=relayFly()
        for time in FieldRelayTransfer.moments(relay) {
            XCTAssertEqual(FieldReplayPresentation.time(relay,elapsed:time,reduced:true,animated:true),time)
            XCTAssertTrue(FieldVerificationScenario.moments(relay).contains(time))
        }
        let error=misplay(relayFly(before:[FieldRunnerProfile(speed:60),nil,FieldRunnerProfile(speed:100)]),stage:3)
        XCTAssertNotNil(error.misplay,"The error fixture must actually cancel an out or allow an extra base")
        for play in [doublePlay(),misplay(doublePlay(),stage:1),error] {
            XCTAssertTrue(FieldRelayTransfer.moments(play).isEmpty)
            let original=play
            for time in stride(from:0.0,through:play.duration,by:0.03) {for index in play.fielders.indices {
                XCTAssertFalse(FieldSpriteAnimation.motion(play,index:index,time:time).relayTransfer)
            }}
            XCTAssertEqual(play,original)
        }
    }

    func testActualSavedCatcherMovementUsesRunningArtAndLeavesAllScenarioNodesUntouched() throws {
        var sawRun=false
        for scenario in FieldVerificationScenario.allCases {
            let play=try scenario.make(),data=try JSONEncoder().encode(play)
            for time in stride(from:0.0,through:play.duration,by:0.05) {
                let motion=FieldSpriteAnimation.motion(play,index:1,time:time)
                if motion.stage == .run {
                    sawRun=true
                    XCTAssertEqual(FieldRasterArt.samples(motion,kind:"catcher",left:false).first?.frame.file,"catcher-run-v1.png")
                }
            }
            XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:data))
        }
        XCTAssertTrue(sawRun,"The running sprite must be wired into a real saved catcher path")
    }

    func testCatcherRunningAndRelayTransferContactSheetAndNativeSequenceRenderReadOnly() throws {
        let view=Canvas {context,_ in
            for column in 0..<8 {
                let facing=FieldFacing.allCases[column]
                for row in 0..<5 {
                    var m=FieldSpriteMotion(facing:facing,stage:row<2 ? .run:row == 4 ? .windup:.gather,progress:row == 2 ? 0.25:row == 3 ? 0.75:0.1,gait:row == 0 ? -1:1,willThrow:row>=2)
                    m.relayTransfer=row>=2
                    FieldRasterArt.draw(in:context,at:CGPoint(x:60+column*72,y:65+row*70),scale:1.8,motion:m,kind:row<2 ? "catcher":"fielder",kit:row<2 ? 0x8b3440:0x316841,skin:0xba7750,hair:0x382416,number:47,left:false,selected:false,out:false)
                }
            }
        }.frame(width:640,height:365).background(GameTheme.board)
        let r=ImageRenderer(content:view);r.scale=2
        let sheet=XCTAttachment(image:try XCTUnwrap(r.uiImage));sheet.name="Catcher running relay transfer eight directions";sheet.lifetime = .keepAlways;add(sheet)
        let play=relayFly(),original=play
        for (i,time) in FieldRelayTransfer.moments(play).enumerated() {
            let board=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:time,showsContactPoints:true,complete:{}).frame(width:390,height:585)
            let renderer=ImageRenderer(content:board);renderer.scale=2
            let shot=XCTAttachment(image:try XCTUnwrap(renderer.uiImage));shot.name="Native relay transfer phase \(i)";shot.lifetime = .keepAlways;add(shot)
        }
        XCTAssertEqual(play,original)
    }

    func testFirstBaseOverrunSpriteStaysInsidePhoneFieldViewport() throws {
        let play=detailed(speed:100),runner=try XCTUnwrap(play.runners.first {$0.from == 0})
        for size in [CGSize(width:320,height:480),CGSize(width:390,height:585)] {
            for time in stride(from:runner.arrival,through:play.duration,by:0.02) {
                let display=FieldSpriteAnimation.runner(runner,play:play,time:time)
                let motion=InplayFieldProjection.motion(display.motion,at:display.point,size:size)
                let point=InplayFieldProjection.point(display.point,size:size),scale=InplayFieldProjection.actorScale(display.point,size:size)
                for left in [false,true] {for sample in FieldRasterArt.samples(motion,kind:"runner",left:left) {
                    let frame=sample.frame
                    let extent=sample.mirrored ? frame.pivot[0]:frame.rect[2]-frame.pivot[0]
                    let right=point.x+extent*sample.unit*scale+motion.bodyOffset.x*scale
                    XCTAssertLessThanOrEqual(right,size.width,"First-base follow-through must not crop either handed runner")
                }}
            }
        }
    }

    func testVerificationScenariosValidateAndExposeRealBaselineOutcomesWithoutRNG() throws {
        for scenario in FieldVerificationScenario.allCases {
            for ability in [30.0,60,85] {
                let play:MatchDetailedPlay
                do {play=try scenario.make(ability:ability)}
                catch {XCTFail("QA fixture \(scenario.rawValue) ability \(ability): \(error)");throw error}
                try play.validate();XCTAssertNotNil(play.battedBall)
                XCTAssertEqual(play,try scenario.make(ability:ability))
                XCTAssertEqual(play,try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONEncoder().encode(play)))
                let events=FieldVerificationScenario.moments(play)
                XCTAssertEqual(events,events.sorted());XCTAssertEqual(Set(events).count,events.count)
                XCTAssertEqual(events.first,0);XCTAssertEqual(events.last,play.duration)
                XCTAssertTrue(events.contains(play.controlAt))
            }
        }
        XCTAssertFalse(try FieldVerificationScenario.single.make().out)
        XCTAssertTrue(try FieldVerificationScenario.groundOut.make().out)
        XCTAssertEqual(try FieldVerificationScenario.doubleHit.make().runners.first {$0.from == 0}?.destination,2)
        XCTAssertNotNil(try FieldVerificationScenario.doublePlay.make().secondThrow)
        XCTAssertEqual(try FieldVerificationScenario.tagUp.make().fly?.caught,true)
        XCTAssertNotNil(try FieldVerificationScenario.relay.make().relay)
        XCTAssertEqual(try FieldVerificationScenario.fieldError.make().misplay?.kind,.fielding)
        XCTAssertEqual(try FieldVerificationScenario.throwError.make().misplay?.kind,.throwing)
        XCTAssertEqual(try FieldVerificationScenario.bunt.make().battedBall?.kind,.bunt)
    }

    func testVerificationClockPauseSpeedSeekAndEndDoNotSkipElapsedTime() {
        let start=Date(timeIntervalSince1970:1000)
        var clock=FieldVerificationClock()
        clock.play(at:start,duration:10)
        XCTAssertEqual(clock.time(at:start.addingTimeInterval(2),duration:10),2)
        clock.speed(0.25,at:start.addingTimeInterval(2),duration:10)
        XCTAssertEqual(clock.time(at:start.addingTimeInterval(6),duration:10),3)
        clock.pause(at:start.addingTimeInterval(6),duration:10)
        XCTAssertEqual(clock.time(at:start.addingTimeInterval(100),duration:10),3)
        clock.seek(9,duration:10);clock.play(at:start,duration:10)
        XCTAssertEqual(clock.time(at:start.addingTimeInterval(20),duration:10),10)
        clock.pause(at:start.addingTimeInterval(20),duration:10);clock.play(at:start.addingTimeInterval(21),duration:10)
        XCTAssertEqual(clock.time(at:start.addingTimeInterval(21),duration:10),0)
        clock.seek(-2,duration:10);XCTAssertEqual(clock.elapsed,0)
    }

    func testControlledVerificationBoardNeverFiresCareerCompletionCallbacks() async throws {
        var callbacks=0
        let play=try FieldVerificationScenario.doublePlay.make(),window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        for time in [0.0,play.pickupAt,play.duration] {
            window.rootViewController=UIHostingController(rootView:DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:time,showsContactPoints:true,onResolved:{callbacks+=1}) {callbacks+=1})
            window.makeKeyAndVisible();try await Task.sleep(for:.milliseconds(150))
            XCTAssertEqual(callbacks,0)
        }
        window.isHidden=true;window.rootViewController=nil
    }

    func testNPCProfilesAreStableByTeamSeasonPositionAndIndependentFromPitchRandom() throws {
        let first=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"hs-ref-001",awayID:"hs-ref-002")
        XCTAssertEqual(first,MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"hs-ref-001",awayID:"hs-ref-002"))
        let swapped=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"hs-ref-002",awayID:"hs-ref-001")
        XCTAssertEqual(first.home,swapped.away);XCTAssertEqual(first.away,swapped.home)
        XCTAssertNotEqual(first.home.players,first.away.players)
        XCTAssertEqual(Set(first.home.players.map(\.id)).count,9)
        for (level,base) in [("highschool",54.0),("college",60.0),("domestic-development",66.0)] {
            let value=MatchNPCFielders.make(year:2026,competition:level,homeID:"team-a",awayID:"team-b")
            try value.validate()
            XCTAssertTrue((base-6...base+6).contains(value.home.strength))
            XCTAssertTrue(value.home.players.flatMap {[$0.speed,$0.defense,$0.arm]}.allSatisfy {(20...95).contains($0)})
        }
        XCTAssertNotEqual(first,MatchNPCFielders.make(year:2027,competition:"highschool",homeID:"hs-ref-001",awayID:"hs-ref-002"))
        var match=game(42);let random=match.random
        match.npcFielders=first;XCTAssertEqual(match.random,random)
        XCTAssertEqual(first,try JSONDecoder().decode(MatchNPCFielders.self,from:JSONEncoder().encode(first)))
    }

    func testNPCSkillsUseSavedValuesAndOnlyActiveOwnFielderOverridesThem() throws {
        let roster=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"a",awayID:"b")
        let stats=MatchFieldStats(speed:91,defense:92,arm:93,position:"SS",activeTraits:[.strongArm],positionMastery:80)
        let own=DetailedFieldRules.skills(stats:stats,defending:true,npc:roster.home.players)
        let opponent=DetailedFieldRules.skills(stats:stats,defending:false,npc:roster.home.players)
        for index in 0..<9 {
            XCTAssertEqual(opponent[index].speed,roster.home.players[index].speed)
            XCTAssertEqual(own[index].defense,index == 5 ? 92:roster.home.players[index].defense)
        }
        XCTAssertEqual(own[5].speed,91);XCTAssertEqual(own[5].arm,93);XCTAssertEqual(own[5].traits,[.strongArm])
        XCTAssertEqual(own[5].positionDelay,0.05,accuracy:0.000001)
        XCTAssertEqual(DetailedFieldRules.skills(stats:nil,defending:false,npc:nil).map(\.speed),Array(repeating:60,count:9))
        var match=game(42);match.npcFielders=roster
        match.half=0;XCTAssertEqual(match.npcDefenders,roster.home.players)
        match.half=1;XCTAssertEqual(match.npcDefenders,roster.away.players)
        match.homeOrder=0;match.awayOrder=0
        XCTAssertEqual(match.npcBatterSpeed,roster.home.players[7].speed)
    }

    func testNPCDefenseArmAndSpeedReachGroundFlyThrowAndErrorRules() throws {
        let base=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"a",awayID:"b").home.players
        let low=base.map {MatchNPCPlayer(id:$0.id,position:$0.position,speed:20,defense:20,arm:20)}
        let high=base.map {MatchNPCPlayer(id:$0.id,position:$0.position,speed:95,defense:95,arm:95)}
        func ground(_ npc:[MatchNPCPlayer]) -> MatchDetailedPlay {
            DetailedFieldRules.resolve(half:0,order:0,landing:.init(x:-14,y:35),flight:1,runners:[nil,nil,nil],batter:.init(speed:60),outs:0,
                stats:nil,defending:false,ownBatter:true,doublePlayEnabled:true,groundBall:true,relayEnabled:true,npc:npc)
        }
        let weak=ground(low),strong=ground(high);try weak.validate();try strong.validate()
        XCTAssertGreaterThan(weak.pickupAt,strong.pickupAt);XCTAssertGreaterThan(weak.controlAt,strong.controlAt)
        func fly(_ npc:[MatchNPCPlayer]) -> MatchDetailedPlay {
            DetailedFieldRules.resolveFly(half:0,order:0,landing:.init(x:0,y:90),flight:4,runners:[nil,nil,FieldRunnerProfile(speed:60)],
                batter:.init(speed:60),outs:0,stats:nil,defending:false,ownBatter:true,relayEnabled:true,npc:npc)
        }
        XCTAssertEqual(fly(low).fly?.caught,false);XCTAssertEqual(fly(high).fly?.caught,true)
        let clean=ground(base)
        var draws=Array(repeating:0.999999,count:7);draws[0]=0.01
        let error=FieldMisplayRules.applying(to:clean,stats:nil,defending:false,draws:draws,npc:low)
        XCTAssertNotNil(error.misplay)
        XCTAssertNil(FieldMisplayRules.applying(to:clean,stats:nil,defending:false,draws:draws,npc:high).misplay)
        try error.validate()
    }

    func testNPCBothRolesFullGamesResumeAndRejectMalformedProfiles() throws {
        for role in ["batter","pitcher"] {for seed in 1...20 {
            var match=game(seed,role:role);match.detailedFieldVersion=5;match.battedBallVersion=1
            match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
            match.npcFielders=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"hs-ref-001",awayID:"hs-ref-002")
            let original=match.npcFielders
            var resumed=match;try match.advance(.automatic)
            while !resumed.completed {
                try resumed.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "pitcher" ? "four-seam":nil)
                resumed=try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(resumed))
                try resumed.validateDetailedField()
            }
            XCTAssertEqual(resumed,match);XCTAssertEqual(match.npcFielders,original)
        }}
        var match=game(9);match.detailedFieldVersion=5;match.battedBallVersion=1;match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.npcFielders=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"a",awayID:"b")
        try match.validateDetailedField()
        var corrupt=match;corrupt.npcFielders?.version=2;XCTAssertThrowsError(try corrupt.validateDetailedField())
        corrupt=match;corrupt.npcFielders?.home.players.removeLast();XCTAssertThrowsError(try corrupt.validateDetailedField())
        corrupt=match;corrupt.npcFielders?.home.players[0].defense = .nan;XCTAssertThrowsError(try corrupt.validateDetailedField())
        corrupt=match;corrupt.battedBallVersion=nil;XCTAssertThrowsError(try corrupt.validateDetailedField())
    }

    func testRelayFloatingPointBoundaryCannotReceiveBeforeReadyInFullSeasonInput() throws {
        var match=CareerMatch(random:16_713_080_429_857_878_884,isHome:false,role:"pitcher",appearance:false,
            contact:65,power:75,discipline:60,mastery:["changeup":42,"fork":35,"four-seam":62,"slider":55])
        match.detailedFieldVersion=5;match.battedBallVersion=1;match.controlVersion=2;match.trainingEffectsVersion=1
        match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.fieldStats=MatchFieldStats(version:2,speed:55,defense:60,arm:65,position:"P",activeTraits:[.safeHands])
        match.abilityStats=MatchAbilityStats(mental:55.2226,velocity:50,control:64.4004,stuff:54.2609,stamina:56.2016,fatigue:0)
        match.pitching=MatchPitching(startingFatigue:0);match.scoutingPerformance = .tracked
        match.npcFielders=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:"hs-ref-040",awayID:"hs-ref-001")
        try match.advance(.automatic);try match.validateDetailedField();try match.validatePitching()
        XCTAssertTrue(match.completed)
        let play=try XCTUnwrap(match.fieldPlays?.first {$0.half == 12 && $0.order == 33})
        let relay=try XCTUnwrap(play.relay)
        XCTAssertGreaterThanOrEqual(relay.receiveAt,relay.readyAt)
        XCTAssertEqual(FieldNode.sample(play.ball,at:relay.receiveAt),relay.point)
        for p in match.fieldPlays ?? [] {try p.validate()}
    }

    func testContactHandoffKeepsStoredPathDirectionFlightAndLegacyData() throws {
        let origin=CGPoint(x:0.51,y:0.65),size=CGSize(width:320,height:340)
        for x in [-30.0,30.0] {
            let play=relayFly(x,100),before=try JSONEncoder().encode(play)
            let start=FieldContactPresentation.sourcePoint(play,time:0,origin:origin,size:size)
            XCTAssertEqual(start.x,origin.x,accuracy:0.0001);XCTAssertEqual(start.y,origin.y,accuracy:0.0001)
            let moved=FieldContactPresentation.sourcePoint(play,time:0.28,origin:origin,size:size)
            XCTAssertEqual(moved.x>origin.x,x>0);XCTAssertLessThan(moved.y,origin.y)
            XCTAssertEqual(FieldContactPresentation.duration(play),0.28,accuracy:0.0001)
            let legacy=try JSONDecoder().decode(MatchDetailedPlay.self,from:before)
            XCTAssertEqual(FieldContactPresentation.sourcePoint(legacy,time:0.28,origin:origin,size:size),moved)
            XCTAssertEqual(play.ball,legacy.ball)
        }
        let slow=relayFly(30,100)
        let fast=DetailedFieldRules.resolveFly(half:0,order:0,landing:FieldPoint(x:30,y:100),flight:3,
            runners:[nil,nil,nil],batter:FieldRunnerProfile(speed:60),outs:0,stats:nil,defending:false,ownBatter:true)
        let a=FieldContactPresentation.sourcePoint(fast,time:0.1,origin:origin,size:size)
        let b=FieldContactPresentation.sourcePoint(slow,time:0.1,origin:origin,size:size)
        XCTAssertGreaterThan(a.x,b.x)
    }
    func testContactHandoffCameraAndReplayShareMonotonicClockAndHonorReducedMotion() {
        let h=FieldContactHandoff(startedAt:100,cutAt:100.28,sourcePoint:CGPoint(x:0.5,y:0.6),sourceFrame:CGRect(x:10,y:100,width:300,height:300))
        let canvas=CGRect(x:10,y:80,width:300,height:450),ball=CGPoint(x:150,y:350)
        let atCut=FieldContactPresentation.cameraOffset(h,fieldPoint:ball,canvas:canvas,now:h.cutAt,reduced:false)
        XCTAssertEqual(canvas.minY+ball.y+atCut.y,h.sourceFrame.minY+h.sourcePoint.y*h.sourceFrame.height,accuracy:0.0001)
        XCTAssertEqual(FieldContactPresentation.cameraOffset(h,fieldPoint:ball,canvas:canvas,now:101,reduced:false),.zero)
        XCTAssertEqual(FieldContactPresentation.cameraOffset(h,fieldPoint:ball,canvas:canvas,now:h.cutAt,reduced:true),.zero)
        XCTAssertEqual(FieldContactPresentation.cameraOffset(nil,fieldPoint:ball,canvas:canvas,now:h.cutAt,reduced:false),.zero)
        XCTAssertEqual(FieldContactPresentation.cameraOffset(h,fieldPoint:ball,canvas:.zero,now:h.cutAt,reduced:false),.zero)
        XCTAssertEqual(h.elapsed(at:99),0);XCTAssertEqual(h.elapsed(at:101),1)
        let play=relayFly()
        XCTAssertGreaterThan(FieldReplayPresentation.time(play,elapsed:h.elapsed(at:h.cutAt),reduced:false,animated:true),0)
        XCTAssertEqual(FieldReplayPresentation.time(play,elapsed:play.duration+1,reduced:false,animated:true),play.duration)
    }
    func testContactHandoffDoesNotAttachToAnotherAtBatOrWatch() {
        let play=relayFly()
        var previous=CareerMatch(random:42,isHome:false,role:"pitcher",appearance:true,contact:60,power:60,discipline:60,mastery:[:])
        previous.half=0;previous.awayOrder=0
        XCTAssertTrue(FieldContactPresentation.matches(play,previous:previous,action:"pitch"))
        XCTAssertTrue(FieldContactPresentation.matches(play,previous:previous,action:"bunt"))
        XCTAssertFalse(FieldContactPresentation.matches(play,previous:previous,action:"watch"))
        previous.awayOrder=1
        XCTAssertFalse(FieldContactPresentation.matches(play,previous:previous,action:"swing"))
        previous.awayOrder=0;previous.half=1
        XCTAssertFalse(FieldContactPresentation.matches(play,previous:previous,action:"swing"))
    }

    func testContactHandoffBoardEndsOnSharedClockAndPreviewRemainsReadOnly() async throws {
        let play=try FieldVerificationScenario.doublePlay.make()
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        var resolved=0,completed=0
        let now=ProcessInfo.processInfo.systemUptime
        let handoff=FieldContactHandoff(startedAt:now-max(3,play.duration)+0.2,cutAt:now,sourcePoint:CGPoint(x:0.5,y:0.6),sourceFrame:CGRect(x:0,y:100,width:390,height:390))
        window.rootViewController=UIHostingController(rootView:DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),handoff:handoff,onResolved:{resolved+=1}) {completed+=1}.frame(width:390,height:650))
        window.makeKeyAndVisible()
        defer {window.isHidden=true;window.rootViewController=nil}
        try await Task.sleep(for:.seconds(0.5))
        XCTAssertEqual(resolved,1,"The outgoing contact segment is not replayed from zero")
        XCTAssertEqual(completed,0,"Result remains visible for the normal receipt interval")
        try await Task.sleep(for:.seconds(2.2));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
        window.rootViewController=UIHostingController(rootView:DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:0.28,handoff:handoff,onResolved:{resolved+=1}) {completed+=1})
        try await Task.sleep(for:.seconds(0.3));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
    }

    func testContactHandoffNativeCameraFramesRenderWithoutChangingPlay() throws {
        let play=relayFly(30,100),encoded=try JSONEncoder().encode(relayFly(30,100))
        for settled in [false,true] {
            let now=ProcessInfo.processInfo.systemUptime
            let handoff=FieldContactHandoff(startedAt:now-0.28,cutAt:now-(settled ? 1:0),sourcePoint:CGPoint(x:0.55,y:0.56),sourceFrame:CGRect(x:0,y:0,width:390,height:650))
            let board=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:0.28,handoff:handoff) {}.frame(width:390,height:650)
            let renderer=ImageRenderer(content:board);renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            let shot=XCTAttachment(image:image);shot.name=settled ? "Contact camera settled":"Contact camera entry";shot.lifetime = .keepAlways;add(shot)
            XCTAssertEqual(image.size.width,390)
        }
        let original=try JSONDecoder().decode(MatchDetailedPlay.self,from:encoded)
        XCTAssertEqual(original.ball,play.ball)
    }

    private func homeRunSample(before:[FieldRunnerProfile?]=[nil,nil,nil],power:Double=72,quality:Double=0.9) -> MatchHomeRun {
        MatchHomeRun(half:0,order:0,seed:42,power:power,quality:quality,directionOffset:0,before:before,
            batter:FieldRunnerProfile(speed:60,own:true),defenderSpeeds:Array(repeating:60,count:9))
    }
    func testHomeRunFrozenInputsDistanceFlightAndFenceProjection() throws {
        let event=homeRunSample(),copy=try JSONDecoder().decode(MatchHomeRun.self,from:JSONEncoder().encode(event))
        XCTAssertEqual(copy,event);XCTAssertEqual(copy.distance,event.distance);XCTAssertGreaterThan(Double(event.distance),event.fence)
        XCTAssertGreaterThan(homeRunSample(power:100,quality:1).distance,homeRunSample(power:0,quality:0).distance)
        let size=CGSize(width:390,height:585)
        let fence=HomeRunPresentation.ballPoint(event,time:event.flight*0.85,size:size)
        XCTAssertLessThan(fence.y/size.height,0.22,"Ball crosses above the painted outfield fence")
        for t in [0.0,event.flight/2,event.flight,event.duration] {
            let p=HomeRunPresentation.ballPoint(event,time:t,size:size)
            XCTAssertTrue(p.x.isFinite && p.y.isFinite);XCTAssertTrue((0...size.width).contains(p.x));XCTAssertTrue((0...size.height).contains(p.y))
        }
        XCTAssertEqual(event.ball(at:0),FieldPoint(x:0,y:0));XCTAssertEqual(event.height(at:0),0)
        XCTAssertEqual(event.defender(6,at:event.flight),event.defender(6,at:event.duration))
        XCTAssertNotEqual(event.defender(6,at:0),event.defender(6,at:event.flight))
    }
    func testHomeRunAllOccupanciesTouchEveryRemainingBaseBeforeCelebration() throws {
        for mask in 0..<8 {
            let before=(0..<3).map {mask & (1 << $0) == 0 ? nil:FieldRunnerProfile(speed:Double(30+$0*30))}
            let event=homeRunSample(before:before)
            try event.validate();XCTAssertEqual(event.runs,1+mask.nonzeroBitCount)
            XCTAssertEqual(event.runners.count,event.runs)
            for runner in event.runners {
                XCTAssertFalse(runner.out);XCTAssertEqual(runner.destination,4)
                XCTAssertEqual(Array(runner.nodes.dropFirst(2).map(\.point)),Array(DetailedFieldRules.bases[(runner.from+1)...4]))
                XCTAssertLessThanOrEqual(runner.arrival,event.duration)
                XCTAssertEqual(FieldNode.sample(runner.nodes,at:event.duration),DetailedFieldRules.bases[4])
            }
            XCTAssertGreaterThan(event.duration,event.flight)
            XCTAssertFalse(HomeRunPresentation.phase(event,time:event.flight,finished:false).contains("홈런"))
            XCTAssertEqual(HomeRunPresentation.phase(event,time:event.duration,finished:true),"홈 도착 · 홈런")
            for t in [0.0,event.flight,event.duration] {XCTAssertLessThanOrEqual(HomeRunPresentation.time(event,elapsed:t,reduced:true),t)}
        }
    }
    func testHomeRunLegacyDecodeAndMalformedMetadataAreRejectedWithoutBackfill() throws {
        let state=game(42),data=try JSONEncoder().encode(state)
        XCTAssertNil(try JSONDecoder().decode(CareerMatch.self,from:data).homeRuns)
        var stateWithRun=state;stateWithRun.half=0;stateWithRun.awayOrder=1;stateWithRun.homeRuns=[homeRunSample()]
        try stateWithRun.validateHomeRuns()
        stateWithRun.homeRuns?.append(homeRunSample());XCTAssertThrowsError(try stateWithRun.validateHomeRuns())
        stateWithRun.homeRuns=[homeRunSample()];stateWithRun.awayOrder=0;XCTAssertThrowsError(try stateWithRun.validateHomeRuns())
        var invalid=homeRunSample();invalid.version=99;XCTAssertThrowsError(try invalid.validate())
        let short=MatchHomeRun(half:0,order:0,seed:0,power:60,quality:1,directionOffset:0,before:[],batter:FieldRunnerProfile(speed:60),defenderSpeeds:[])
        XCTAssertThrowsError(try short.validate())
    }
    func testHomeRunActualBothRolesFullGameResumeAndNoDuplicateEvents() throws {
        var seen=false
        for role in ["batter","pitcher"] {
            for seed in 1...4 {
                var state=CareerMatch(random:UInt64(seed),isHome:true,role:role,appearance:true,contact:90,power:100,discipline:60,mastery:["four-seam":72])
                state.half=role == "batter" ? 1:0;state.controlVersion=2
                var restored=state
                while !state.completed {
                    try state.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "pitcher" ? "four-seam":nil)
                    try restored.advance(role == "batter" ? .swing:.pitch,pitchCode:role == "pitcher" ? "four-seam":nil)
                    XCTAssertEqual(state,restored)
                    try state.validateHomeRuns()
                    restored=try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(restored))
                }
                if let events=state.homeRuns,!events.isEmpty {seen=true;XCTAssertEqual(events.count,Set(events.map(\.eventID)).count)}
                let data=try JSONEncoder().encode(state);XCTAssertThrowsError(try state.advance(.automatic));XCTAssertEqual(try JSONEncoder().encode(state).count,data.count)
            }
        }
        XCTAssertTrue(seen)
    }
    func testHomeRunNativeFramesPreserveBallAndRunnerLayers() throws {
        let event=homeRunSample(before:[FieldRunnerProfile(speed:60),nil,FieldRunnerProfile(speed:60)])
        for (name,time) in [("contact",0.28),("fence",event.flight*0.85),("bases",event.flight+2),("home",event.duration)] {
            let view=HomeRunReplayBoard(event:event,appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:"CF",previewTime:time).frame(width:390,height:680)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            let shot=XCTAttachment(image:try XCTUnwrap(renderer.uiImage));shot.name="Home run native \(name)";shot.lifetime = .keepAlways;add(shot)
        }
    }

    func testHomeRunBoardResolvesOnceAfterLastRunnerAndPreviewNeverRewards() async throws {
        let event=homeRunSample(before:[FieldRunnerProfile(speed:60),nil,nil]),window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        var resolved=0,completed=0
        let now=ProcessInfo.processInfo.systemUptime
        let handoff=FieldContactHandoff(startedAt:now-event.duration+0.8,cutAt:now,sourcePoint:.zero)
        window.rootViewController=UIHostingController(rootView:HomeRunReplayBoard(event:event,appearance:PlayerAppearance(),handoff:handoff,onResolved:{resolved+=1}) {completed+=1})
        window.makeKeyAndVisible();defer {window.isHidden=true;window.rootViewController=nil}
        try await Task.sleep(for:.seconds(0.1));XCTAssertEqual(resolved,0);XCTAssertEqual(completed,0)
        try await Task.sleep(for:.seconds(1));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,0)
        try await Task.sleep(for:.seconds(2.2));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
        for time in [0.0,event.flight,event.duration] {
            window.rootViewController=UIHostingController(rootView:HomeRunReplayBoard(event:event,appearance:PlayerAppearance(),previewTime:time,onResolved:{resolved+=1}) {completed+=1})
            try await Task.sleep(for:.seconds(0.1));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
        }
        window.rootViewController=UIHostingController(rootView:HomeRunReplayBoard(event:event,appearance:PlayerAppearance(),onResolved:{resolved+=1}) {completed+=1})
        try await Task.sleep(for:.seconds(0.1));window.rootViewController=nil
        try await Task.sleep(for:.seconds(0.1));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
    }

}

@MainActor final class MatchRenderingPerformanceTests:XCTestCase {
    private func footprint() throws -> UInt64 {
        var info=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let capacity=Int(count)
        let result=withUnsafeMutablePointer(to:&info) {pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:capacity) {task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)}
        }
        XCTAssertEqual(result,KERN_SUCCESS)
        return info.phys_footprint
    }
    private struct MemorySample:Codable {let seconds:Double;let footprint:UInt64;let cache:FieldCacheMetrics.Snapshot}
    private struct Report:Codable {
        let kind:String
        let optimized:Bool
        let elapsed:Double
        let memory:[MemorySample]
        let frames:[MatchRenderMetrics.Frame]
        let cache:FieldCacheMetrics.Snapshot
        let note:String
    }
    func testLiveReplayTwoCyclesFootprintCadenceAndCache() async throws {
        FieldRasterArt.resetCacheForVerification();MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true
        let fixtures=try MatchReplayFixture.make(pitcher:false),pitcher=try MatchReplayFixture.make(pitcher:true)
        let cycle=fixtures.reduce(0) {$0+$1.duration+1},duration=cycle*2+1
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene)
        let started=ProcessInfo.processInfo.systemUptime
        var memory=[MemorySample(seconds:0,footprint:try footprint(),cache:FieldRasterArt.cacheMetrics.snapshot)]
        window.rootViewController=UIHostingController(rootView:MatchReplayStressView(fixtures:fixtures,pitcherFixtures:pitcher,started:started).frame(width:390,height:680))
        window.makeKeyAndVisible()
        defer {MatchRenderMetrics.enabled=false;window.isHidden=true;window.rootViewController=nil;previous?.makeKey()}
        while ProcessInfo.processInfo.systemUptime-started<duration {
            try await Task.sleep(for:.seconds(3))
            memory.append(MemorySample(seconds:ProcessInfo.processInfo.systemUptime-started,footprint:try footprint(),cache:FieldRasterArt.cacheMetrics.snapshot))
        }
        let report=Report(kind:"two real-time ten-play cycles, batter/right then pitcher/left",optimized:!_isDebugAssertConfiguration(),elapsed:ProcessInfo.processInfo.systemUptime-started,
            memory:memory,frames:MatchRenderMetrics.frames,cache:FieldRasterArt.cacheMetrics.snapshot,
            note:"iOS Simulator diagnostic build, 390x680 hosted view; command recording time/callback cadence excludes GPU presentation. Cache bytes are NSCache-owned personalized pixel costs, footprint is Mach phys_footprint of test host.")
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let attachment=XCTAttachment(data:try encoder.encode(report),uniformTypeIdentifier:"public.json");attachment.name="match-replay-performance.json";attachment.lifetime = .keepAlways;add(attachment)
        XCTAssertGreaterThan(report.frames.count,300);XCTAssertGreaterThan(report.cache.hits,report.cache.misses)
        XCTAssertGreaterThan(report.cache.entries,0);XCTAssertGreaterThan(report.cache.bytes,0)
    }
    func testRepeatedPitcherBatterDeliveryUpdateAndFootprint() async throws {
        MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene),controller=UIViewController()
        let view=SKView(frame:CGRect(x:0,y:0,width:320,height:340));controller.view=view;window.rootViewController=controller;window.makeKeyAndVisible()
        defer {MatchRenderMetrics.enabled=false;view.presentScene(nil);window.isHidden=true;window.rootViewController=nil;previous?.makeKey()}
        let start=ProcessInfo.processInfo.systemUptime
        var memory=[MemorySample(seconds:0,footprint:try footprint(),cache:FieldRasterArt.cacheMetrics.snapshot)]
        for role in PlayerRole.allCases {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:role == .pitcher ? "left":"right",kit:2,role:role)
            view.presentScene(scene)
            for index in 0..<4 {
                let done=expectation(description:role.rawValue+" delivery \(index)")
                XCTAssertTrue(scene.demonstrate(reduceMotion:false,flightDuration:0.65,preparedRelease:true,completion:{done.fulfill()}))
                await fulfillment(of:[done],timeout:4)
                memory.append(MemorySample(seconds:ProcessInfo.processInfo.systemUptime-start,footprint:try footprint(),cache:FieldRasterArt.cacheMetrics.snapshot))
            }
        }
        let report=Report(kind:"four repeated deliveries per role",optimized:!_isDebugAssertConfiguration(),elapsed:ProcessInfo.processInfo.systemUptime-start,memory:memory,frames:MatchRenderMetrics.frames,
            cache:FieldRasterArt.cacheMetrics.snapshot,note:"Simulator diagnostic SpriteKit update callback timing, not GPU render time or device FPS.")
        let attachment=XCTAttachment(data:try JSONEncoder().encode(report),uniformTypeIdentifier:"public.json");attachment.name="match-sprite-performance.json";attachment.lifetime = .keepAlways;add(attachment)
        XCTAssertGreaterThan(report.frames.count,100)
    }
}

@MainActor final class MatchRenderingIntegrationTests:XCTestCase {
    func testFrontRasterSharesUnpaintedNumberAndMirrorVariantsButPreservesBackDigits() throws {
        FieldRasterArt.resetCacheForVerification()
        let motion=FieldSpriteMotion(facing:.south,stage:.ready)
        let sample=try XCTUnwrap(FieldRasterArt.samples(motion,kind:"fielder",left:false).first)
        let mirrored=FieldRasterArt.Sample(frame:sample.frame,weight:sample.weight,unit:sample.unit,mirrored:!sample.mirrored)
        let first=try XCTUnwrap(FieldRasterArt.image(sample,kit:0x123456,skin:0xefbe91,hair:0x263b48,number:1,back:false))
        for number in 0..<30 {
            let other=try XCTUnwrap(FieldRasterArt.image(number%2 == 0 ? sample:mirrored,kit:0x123456,skin:0xefbe91,hair:0x263b48,number:number,back:false))
            XCTAssertTrue(first === other)
        }
        var stats=FieldRasterArt.cacheMetrics.snapshot
        XCTAssertEqual(stats.misses,1);XCTAssertEqual(stats.hits,30);XCTAssertEqual(stats.entries,1)
        XCTAssertEqual(stats.bytes,first.cgImage!.bytesPerRow*first.cgImage!.height)
        let back=try XCTUnwrap(FieldRasterArt.samples(.init(facing:.north,stage:.ready),kind:"fielder",left:false).first)
        let one=try XCTUnwrap(FieldRasterArt.image(back,kit:0x123456,skin:0xefbe91,hair:0x263b48,number:1,back:true))
        let other=try XCTUnwrap(FieldRasterArt.image(back,kit:0x123456,skin:0xefbe91,hair:0x263b48,number:99,back:true))
        XCTAssertFalse(one === other);XCTAssertNotEqual(one.pngData(),other.pngData())
        stats=FieldRasterArt.cacheMetrics.snapshot;XCTAssertEqual(stats.entries,3)
        FieldRasterArt.resetCacheForVerification();XCTAssertEqual(FieldRasterArt.cacheMetrics.snapshot.bytes,0)
    }
    func testAllPlayBoundaryFramesAreFiniteOpaqueAndPreserveSavedRules() throws {
        for pitcher in [false,true] {
            let fixtures=try MatchReplayFixture.make(pitcher:pitcher)
            XCTAssertEqual(fixtures.count,10)
            for fixture in fixtures {
                if let play=fixture.field {
                    try play.validate();let original=play
                    for left in [false,true] {for reduced in [false,true] {for size in [CGSize(width:320,height:480),CGSize(width:390,height:585)] {
                        let times=FieldVerificationScenario.moments(play).flatMap {[$0-0.001,$0,$0+0.001]}.map {max(0,min(play.duration,$0))}
                        for raw in times {
                            let time=FieldReplayPresentation.time(play,elapsed:raw,reduced:reduced,animated:true)
                            let ball=FieldBallPresentation.point(play,time:time,size:size,leftIndex:pitcher && left ? 0:nil)
                            XCTAssertTrue(ball.x.isFinite && ball.y.isFinite)
                            for index in play.fielders.indices {
                                let at=FieldNode.sample(play.fielders[index],at:time)
                                let motion=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:index,time:time),at:at,size:size)
                                let frames=FieldRasterArt.samples(motion,kind:index == 1 ? "catcher":"fielder",left:pitcher && left && index == 0)
                                XCTAssertEqual(frames.count,1);XCTAssertEqual(frames.first?.weight,1)
                            }
                            for runner in play.runners {
                                let display=FieldSpriteAnimation.runner(runner,play:play,time:time,reduced:reduced)
                                XCTAssertTrue(display.point.x.isFinite && display.point.y.isFinite)
                                XCTAssertFalse(FieldReplayPresentation.retired(runner,finished:false))
                            }
                            if raw<play.duration {
                                let phase=FieldReplayPresentation.phase(play,time:time,finished:false)
                                XCTAssertFalse(phase.contains("세이프"));XCTAssertFalse(phase.contains("아웃"))
                            }
                        }
                    }}}
                    XCTAssertEqual(play,original)
                } else if let event=fixture.homeRun {
                    try event.validate();let original=event
                    for raw in [0.0,event.flight/2,event.flight,event.duration-0.001,event.duration] {
                        for reduced in [false,true] {
                            let time=HomeRunPresentation.time(event,elapsed:raw,reduced:reduced)
                            for size in [CGSize(width:320,height:480),CGSize(width:390,height:585)] {
                                let p=HomeRunPresentation.ballPoint(event,time:time,size:size)
                                XCTAssertTrue((0...size.width).contains(p.x));XCTAssertTrue((0...size.height).contains(p.y))
                            }
                        }
                    }
                    XCTAssertEqual(event,original)
                }
            }
        }
    }
    func testMonotonicReplayClockMatchesContactClockAndNeverUsesWallDate() {
        let start=100.0,now=102.0
        XCTAssertEqual(FieldReplayPresentation.elapsed(start:start,handoff:nil,now:now),2)
        XCTAssertEqual(FieldReplayPresentation.elapsed(start:start,handoff:nil,now:99),0)
        XCTAssertEqual(FieldReplayPresentation.elapsed(start:nil,handoff:nil,now:now),0)
        let handoff=FieldContactHandoff(startedAt:101,cutAt:101.28,sourcePoint:.zero)
        XCTAssertEqual(FieldReplayPresentation.elapsed(start:start,handoff:handoff,now:now),1)
    }
    func testIntegratedNativeStillsBothRolesAndReducedMotionRemainReadOnly() throws {
        for pitcher in [false,true] {
            for fixture in try MatchReplayFixture.make(pitcher:pitcher) {
                let view=MatchReplaySample(sample:fixture,pitcher:pitcher,left:pitcher,time:fixture.duration*0.55,reduced:false).frame(width:320,height:600)
                let renderer=ImageRenderer(content:view);renderer.scale=1
                let shot=XCTAttachment(image:try XCTUnwrap(renderer.uiImage));shot.name="Integrated native \(pitcher ? "pitcher":"batter") \(fixture.name)";shot.lifetime = .keepAlways;add(shot)
                let reduced=MatchReplaySample(sample:fixture,pitcher:pitcher,left:!pitcher,time:fixture.duration,reduced:true).frame(width:390,height:680)
                XCTAssertNotNil(ImageRenderer(content:reduced).uiImage)
            }
        }
    }
}

@MainActor final class MatchMotionPreparationTests:XCTestCase {
    func testPreparationCoversActualPosesAndPreservesReplayData() async throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        for pitcher in [false,true] {
            let fixtures=try MatchReplayFixture.make(pitcher:pitcher)
            let sprites=FieldReplaySprites(appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:pitcher ? "P":"CF",throwingHand:pitcher ? "left":"right",ownTeamFielding:pitcher)
            for fixture in [fixtures[0],fixtures[fixtures.count-2],fixtures.last!] {
                let before=try fixture.field.map {try encoder.encode($0)} ?? fixture.homeRun.map {try encoder.encode($0)}
                let actors:(Double)->[FieldReplaySprites.Actor] = {time in
                    if let play=fixture.field {return sprites.actors(play,time:time,reduced:false,finished:time>=play.duration)}
                    return sprites.actors(fixture.homeRun!,time:time,reduced:false)
                }
                let planned=await sprites.requests(duration:fixture.duration,reduced:false,actorsAt:actors)
                let requests=try XCTUnwrap(planned)
                let generated=await FieldRasterArt.prepare(requests)
                let prepared=try XCTUnwrap(generated)
                XCTAssertEqual(prepared.images.count,requests.count)
                XCTAssertLessThan(prepared.bytes,48*1024*1024,"Per-play pinned pixels must fit the existing cache budget")
                for step in 0...Int(fixture.duration*59) {
                    for actor in actors(min(fixture.duration,(Double(step)+0.37)/59)) {
                        let motion=InplayFieldProjection.motion(actor.motion,at:actor.point,size:CGSize(width:390,height:585))
                        let ownKit=PlayerAppearance.kitColors[2]
                        for sample in FieldRasterArt.samples(motion,kind:actor.kind,left:actor.own && pitcher) {
                            let request=FieldRasterArt.Request(sample:sample,kit:actor.teamOwn ? ownKit:FieldReplayPresentation.opponentKit(ownKit),skin:actor.own ? PlayerAppearance.skinColors[0]:0xefbe91,hair:actor.own ? PlayerAppearance.hairColors[0]:0x263b48,number:actor.number,back:motion.facing.back && actor.kind != "catcher")
                            XCTAssertNotNil(prepared.images[request.key],"Missing \(fixture.name) \(actor.kind) \(step)")
                        }
                    }
                }
                if let request=requests.values.first {
                    let sample=FieldRasterArt.Sample(frame:request.frame,weight:1,unit:1,mirrored:request.mirrored)
                    let original=FieldRasterArt.image(sample,kit:request.kit,skin:request.skin,hair:request.hair,number:request.number,back:request.back)
                    XCTAssertEqual(prepared.images[request.key]?.pngData(),original?.pngData())
                }
                let after=try fixture.field.map {try encoder.encode($0)} ?? fixture.homeRun.map {try encoder.encode($0)}
                XCTAssertEqual(before,after)
            }
        }
    }
    func testPreparedHomeRunKeepsCutAndCompletesOnce() async throws {
        let event=try XCTUnwrap(MatchReplayFixture.make(pitcher:true).last?.homeRun)
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene)
        window.frame=CGRect(x:0,y:0,width:390,height:700)
        let now=ProcessInfo.processInfo.systemUptime
        var resolved=0,completed=0,resolvedAt=0.0
        MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true
        defer {MatchRenderMetrics.enabled=false;window.isHidden=true;window.rootViewController=nil;previous?.makeKey()}
        let handoff=FieldContactHandoff(startedAt:now-event.duration+0.9,cutAt:now,sourcePoint:.zero)
        window.rootViewController=UIHostingController(rootView:HomeRunReplayBoard(event:event,appearance:PlayerAppearance(kit:2),jerseyNumber:27,throwingHand:"left",ownTeamFielding:true,handoff:handoff,preparesMotion:true,onResolved:{resolved+=1;resolvedAt=ProcessInfo.processInfo.systemUptime}) {completed+=1})
        window.makeKeyAndVisible()
        try await Task.sleep(for:.seconds(0.1));XCTAssertEqual(resolved,0)
        let deadline=ProcessInfo.processInfo.systemUptime+8
        while completed == 0 && ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(for:.seconds(0.1))}
        XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
        let preparation=try XCTUnwrap(MatchRenderMetrics.preparations.first)
        XCTAssertGreaterThan(resolvedAt-preparation.endedAt,0.6)
        let ready=try XCTUnwrap(MatchRenderMetrics.lifecycle.first {$0.name.hasPrefix("rendererReady.")})
        let clock=try XCTUnwrap(MatchRenderMetrics.lifecycle.first {$0.name == "clockStarted"})
        XCTAssertGreaterThanOrEqual(clock.at,ready.at)
        XCTAssertTrue(MatchRenderMetrics.frames.contains {$0.kind == "homeRunSprite"})
        XCTAssertEqual(MatchRenderMetrics.spriteFallbacks,0);XCTAssertEqual(MatchRenderMetrics.preparedMisses,0)
    }
    func testPreparationCancellationAndHandoffDelayPreserveCut() async throws {
        let fixture=try MatchReplayFixture.make(pitcher:false)[0]
        let sprites=FieldReplaySprites(appearance:PlayerAppearance(),jerseyNumber:1,ownPosition:"CF",throwingHand:"right",ownTeamFielding:false)
        let task=Task {await sprites.requests(duration:fixture.duration,reduced:false,actorsAt:{sprites.actors(fixture.field!,time:$0,reduced:false,finished:false)})}
        task.cancel();let cancelled=await task.value;XCTAssertNil(cancelled)
        let handoff=FieldContactHandoff(startedAt:10,cutAt:10.28,sourcePoint:CGPoint(x:0.3,y:0.4),sourceFrame:CGRect(x:1,y:2,width:3,height:4))
        let shifted=handoff.delayed(by:0.7)
        XCTAssertEqual(shifted.elapsed(at:11.1),handoff.elapsed(at:10.4),accuracy:0.000001)
        XCTAssertEqual(shifted.cutAt-shifted.startedAt,0.28,accuracy:0.000001)
        XCTAssertEqual(shifted.sourcePoint,handoff.sourcePoint);XCTAssertEqual(shifted.sourceFrame,handoff.sourceFrame)
    }
}

@MainActor final class GroundFieldSceneTests:XCTestCase {
    func testOrdinaryGroundLabelIsOnlyADiagnosticFilter() throws {
        for scenario in FieldVerificationScenario.allCases {
            let play=try scenario.make()
            XCTAssertEqual(InplayFieldScene.isOrdinaryGround(play),[FieldVerificationScenario.single,.groundOut].contains(scenario),scenario.rawValue)
        }
        var legacy=try FieldVerificationScenario.groundOut.make();legacy.battedBall=nil
        XCTAssertTrue(InplayFieldScene.isOrdinaryGround(legacy))
        var line=legacy;line.battedBall=MatchBattedBall(kind:.line,quality:0.75,contact:60,power:60,speed:110/3.6,angle:15,direction:0,distance:hypot(legacy.landing.x,legacy.landing.y),flight:legacy.flight)
        XCTAssertFalse(InplayFieldScene.isOrdinaryGround(line))
    }
    func testRetainedActorsBallAndFramesMatchCanvasGeometryAndDoNotMutatePlay() async throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        for pitcher in [false,true] {
            for scenario in FieldVerificationScenario.allCases {
                let play=try scenario.make(ownBatter:!pitcher),before=try encoder.encode(play)
                let sprites=FieldReplaySprites(appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:pitcher ? "P":"CF",throwingHand:pitcher ? "left":"right",ownTeamFielding:pitcher)
                let planned=await sprites.requests(duration:play.duration,reduced:false,actorsAt:{sprites.actors(play,time:$0,reduced:false,finished:false)})
                let requests=try XCTUnwrap(planned),generated=await FieldRasterArt.prepare(requests)
                let prepared=try XCTUnwrap(generated)
                let scene=InplayFieldScene(play:play,sprites:sprites,prepared:prepared,scoreText:"H 0 : 0 A")
                await scene.preload()
                let ids=scene.actorIDs
                let times=[0,0.28,play.pickupAt,play.releaseAt,play.ballAt,play.controlAt,play.duration]+stride(from:0.013,through:play.duration,by:1.0/60).map {$0}
                for reduced in [false,true] {
                scene.setReduced(reduced)
                for time in times {
                    scene.display(time:time,finished:time>=play.duration)
                    let expected=sprites.actors(play,time:time,reduced:reduced,finished:time>=play.duration)
                    XCTAssertEqual(scene.actorIDs,ids)
                    XCTAssertEqual(scene.actorPositions.count,expected.count)
                    for (position,actor) in zip(scene.actorPositions,expected) {
                        let point=InplayFieldProjection.point(actor.point,size:scene.size)
                        XCTAssertEqual(position.x,point.x,accuracy:0.0001);XCTAssertEqual(position.y,scene.size.height-point.y,accuracy:0.0001)
                    }
                    let ball=FieldBallPresentation.point(play,time:time,size:scene.size,leftIndex:pitcher ? 0:nil)
                    XCTAssertEqual(scene.ballPosition.x,ball.x,accuracy:0.0001);XCTAssertEqual(scene.ballPosition.y,scene.size.height-ball.y,accuracy:0.0001)
                    XCTAssertEqual(scene.resultVisible,time>=play.duration)
                }
                }
                scene.setReduced(false)
                XCTAssertGreaterThan(scene.textureChanges,0);XCTAssertEqual(scene.fallbackTextures,0)
                XCTAssertEqual(try encoder.encode(play),before)
                let view=SKView(frame:CGRect(x:0,y:0,width:400,height:600));view.presentScene(scene)
                scene.display(time:play.releaseAt,finished:false)
                let image=try XCTUnwrap(view.texture(from:scene)?.cgImage())
                let shot=XCTAttachment(image:UIImage(cgImage:image));shot.name="SpriteKit \(pitcher ? "pitcher-left":"batter-right") \(scenario.rawValue)";shot.lifetime = .keepAlways;add(shot)
                view.presentScene(nil)
            }
        }
    }
    func testHomeRunBothRolesRetainSavedGeometryAndEffectsDoNotFreezeActors() async throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        for pitcher in [false,true] {
            let event=try XCTUnwrap(MatchReplayFixture.make(pitcher:pitcher).last?.homeRun),before=try encoder.encode(event)
            let sprites=FieldReplaySprites(appearance:PlayerAppearance(kit:2),jerseyNumber:27,ownPosition:pitcher ? "P":"CF",throwingHand:pitcher ? "left":"right",ownTeamFielding:pitcher)
            let planned=await sprites.requests(duration:event.duration,reduced:false,actorsAt:{sprites.actors(event,time:$0,reduced:false)})
            let requests=try XCTUnwrap(planned)
            let generated=await FieldRasterArt.prepare(requests)
            let prepared=try XCTUnwrap(generated)
            let scene=InplayFieldScene(event:event,sprites:sprites,prepared:prepared,scoreText:"H 0 : 0 A")
            await scene.preload()
            let ids=scene.actorIDs
            for effects in [false,true] {
                scene.setEffectsReduced(effects)
                for time in [0.123,0.143,event.flight-0.01,event.flight+0.01,event.duration] {
                    scene.display(time:time,finished:time>=event.duration)
                    XCTAssertEqual(scene.displayedTime,time)
                    XCTAssertEqual(scene.actorIDs,ids)
                    let expected=sprites.actors(event,time:time,reduced:false)
                    for (position,actor) in zip(scene.actorPositions,expected) {
                        let point=InplayFieldProjection.point(actor.point,size:scene.size)
                        XCTAssertEqual(position.x,point.x,accuracy:0.0001);XCTAssertEqual(position.y,scene.size.height-point.y,accuracy:0.0001)
                    }
                    let ball=HomeRunPresentation.ballPoint(event,time:time,size:scene.size)
                    XCTAssertEqual(scene.ballPosition.x,ball.x,accuracy:0.0001);XCTAssertEqual(scene.ballPosition.y,scene.size.height-ball.y,accuracy:0.0001)
                    XCTAssertEqual(scene.ballVisible,time<=event.flight);XCTAssertEqual(scene.resultVisible,time>=event.duration)
                    if effects {XCTAssertFalse(scene.effectsVisible)}
                }
            }
            XCTAssertEqual(scene.fallbackTextures,0);XCTAssertEqual(try encoder.encode(event),before)
        }
    }
    func testEffectsReductionPreservesFieldMotionAndSecondThrowTarget() async throws {
        let play=try FieldVerificationScenario.doublePlay.make(ownBatter:true)
        let sprites=FieldReplaySprites(appearance:PlayerAppearance(),jerseyNumber:1,ownPosition:"CF",throwingHand:"right",ownTeamFielding:false)
        let planned=await sprites.requests(duration:play.duration,reduced:false,actorsAt:{sprites.actors(play,time:$0,reduced:false,finished:false)})
        let requests=try XCTUnwrap(planned)
        let generated=await FieldRasterArt.prepare(requests)
        let prepared=try XCTUnwrap(generated)
        let scene=InplayFieldScene(play:play,sprites:sprites,prepared:prepared,scoreText:"H 0 : 0 A");await scene.preload()
        let second=try XCTUnwrap(play.secondThrow)
        scene.setContactPoints(true);XCTAssertEqual(scene.contactPointCount,9)
        scene.setContactPoints(false);XCTAssertEqual(scene.contactPointCount,0)
        for time in [0.123,0.143,second.releaseAt-0.01,second.releaseAt+0.01] {
            scene.setEffectsReduced(false);scene.display(time:time,finished:false)
            let positions=scene.actorPositions,ball=scene.ballPosition
            scene.setEffectsReduced(true);XCTAssertFalse(scene.effectsVisible)
            scene.display(time:time,finished:false)
            XCTAssertEqual(scene.actorPositions,positions);XCTAssertEqual(scene.ballPosition,ball);XCTAssertFalse(scene.effectsVisible)
            let target=InplayFieldProjection.point(DetailedFieldRules.bases[time>=second.releaseAt ? 1:play.targetBase],size:scene.size)
            XCTAssertEqual(scene.targetPosition.x,target.x,accuracy:0.0001);XCTAssertEqual(scene.targetPosition.y,scene.size.height-target.y,accuracy:0.0001)
        }
    }
    func testGroundCompletionAndCancellationRemainPresentationOnly() async throws {
        let play=try FieldVerificationScenario.groundOut.make(ownBatter:true)
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene)
        window.frame=CGRect(x:0,y:0,width:390,height:700)
        var resolved=0,completed=0
        let now=ProcessInfo.processInfo.systemUptime
        window.rootViewController=UIHostingController(rootView:DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),handoff:FieldContactHandoff(startedAt:now-play.duration+0.9,cutAt:now,sourcePoint:.zero),preparesMotion:true,onResolved:{resolved+=1}) {completed+=1})
        window.makeKeyAndVisible();defer {window.isHidden=true;window.rootViewController=nil;previous?.makeKey()}
        try await Task.sleep(for:.seconds(0.1));XCTAssertEqual(resolved,0);XCTAssertEqual(completed,0)
        let deadline=ProcessInfo.processInfo.systemUptime+8
        while completed == 0 && ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(for:.seconds(0.1))}
        XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
        window.rootViewController=UIHostingController(rootView:DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),preparesMotion:true,onResolved:{resolved+=1}) {completed+=1})
        try await Task.sleep(for:.seconds(0.1));window.rootViewController=nil
        try await Task.sleep(for:.seconds(0.2));XCTAssertEqual(resolved,1);XCTAssertEqual(completed,1)
    }
}

@MainActor final class InplayStartupReadinessTests:XCTestCase {
    func testRequiresTwoSettledIntervalsBeforeMovementCanStart() {
        var gate=InplayStartupReadiness()
        gate.observe(at:10);XCTAssertFalse(gate.isReady)
        gate.observe(at:10+1.0/30);XCTAssertFalse(gate.isReady)
        gate.observe(at:10+2.0/30);XCTAssertTrue(gate.isReady)
        XCTAssertEqual(gate.frameCount,3);XCTAssertEqual(gate.settledIntervals,2)
    }
    func testInitial87MillisecondGapIsPreparationRatherThanMovement() {
        var gate=InplayStartupReadiness()
        for time in [0.0,0.087424,0.120757] {gate.observe(at:time);XCTAssertFalse(gate.isReady)}
        gate.observe(at:0.154090);XCTAssertTrue(gate.isReady)
        XCTAssertEqual(gate.frameCount,4)
    }
    func testSlowFramesHaveABoundedPreparationBudgetAndReadinessIsStable() {
        var gate=InplayStartupReadiness()
        for i in 0..<5 {gate.observe(at:Double(i)*0.1);XCTAssertFalse(gate.isReady)}
        gate.observe(at:0.5);XCTAssertTrue(gate.isReady);XCTAssertEqual(gate.settledIntervals,0)
        gate.observe(at:0.6);XCTAssertEqual(gate.frameCount,6)
    }
    func testCancellingAnUnmountedSceneReleasesStartupWaitWithoutAClockOrResult() async throws {
        let play=try FieldVerificationScenario.single.make(ownBatter:true)
        let sprites=FieldReplaySprites(appearance:PlayerAppearance(),jerseyNumber:1,ownPosition:"CF",throwingHand:"right",ownTeamFielding:false)
        let planned=await sprites.requests(duration:play.duration,reduced:false,actorsAt:{sprites.actors(play,time:$0,reduced:false,finished:false)})
        let requests=try XCTUnwrap(planned),generated=await FieldRasterArt.prepare(requests)
        let images=try XCTUnwrap(generated),scene=InplayFieldScene(play:play,sprites:sprites,prepared:images,scoreText:"H 0 : 0 A")
        await scene.preload();scene.display(time:0.28,finished:false)
        let task=Task {await scene.waitForStartup()};await Task.yield();task.cancel()
        let ready=await task.value;XCTAssertFalse(ready)
        XCTAssertEqual(scene.displayedTime,0.28);XCTAssertFalse(scene.resultVisible)
    }
}

@MainActor final class MatchArenaLifecycleTests:XCTestCase {
    func testDetachedArenaPausesWithoutDiscardingSceneOrActions() {
        let view=MatchArenaSKView(frame:CGRect(x:0,y:0,width:320,height:340))
        let scene=BallparkScene(size:CGSize(width:320,height:340))
        scene.run(.wait(forDuration:10),withKey:"preserved")
        view.presentScene(scene)
        view.setCovered(false)
        XCTAssertTrue(view.isPaused)
        XCTAssertTrue(view.scene === scene)
        XCTAssertNotNil(scene.action(forKey:"preserved"))
        view.setCovered(true)
        XCTAssertTrue(view.isPaused)
        XCTAssertTrue(view.scene === scene)
    }
}

@MainActor final class LiveCareerQAStoreBoundaryTests:XCTestCase {
    func testRejectsExistingProductBundleEvenWithValidSession() {
        XCTAssertThrowsError(try LiveCareerQA.storeURL(arguments:["-qa-session",UUID().uuidString],bundleID:"dev.bm.career"))
    }
    func testRejectsMissingOrPathLikeSession() {
        for args in [[],["-qa-session"],["-qa-session","../../Career.store"]] {
            XCTAssertThrowsError(try LiveCareerQA.storeURL(arguments:args,bundleID:"dev.bm.career.performanceqa"))
        }
    }
    func testSameSessionResumesSameTemporaryStoreAndNewSessionIsIndependent() throws {
        let id=UUID().uuidString,other=UUID().uuidString
        let first=try LiveCareerQA.storeURL(arguments:["-qa-session",id],bundleID:"dev.bm.career.performanceqa")
        XCTAssertEqual(first,try LiveCareerQA.storeURL(arguments:["-qa-session",id],bundleID:"dev.bm.career.performanceqa"))
        XCTAssertNotEqual(first,try LiveCareerQA.storeURL(arguments:["-qa-session",other],bundleID:"dev.bm.career.performanceqa"))
        XCTAssertEqual(first.deletingLastPathComponent().standardizedFileURL,FileManager.default.temporaryDirectory.standardizedFileURL)
    }
}

@MainActor final class InplayCadenceReadinessTests:XCTestCase {
    func testFirstFrameGateAcceptsStableThirtyAndSixtyWithoutChangingTimeBasis() {
        for rate in [30.0,60.0] {
            var gate=InplayStartupReadiness()
            gate.observe(at:100);XCTAssertFalse(gate.isReady)
            gate.observe(at:100+1/rate);XCTAssertFalse(gate.isReady)
            gate.observe(at:100+2/rate);XCTAssertTrue(gate.isReady)
            XCTAssertEqual(gate.frameCount,3)
        }
    }
}

@MainActor final class EnduranceMetricsTests:XCTestCase {
    func testMemorySamplingContinuesAfterBoundedFrameBufferFills() async throws {
        MatchRenderMetrics.reset();MatchRenderMetrics.enabled=true
        defer {MatchRenderMetrics.enabled=false;MatchRenderMetrics.reset()}
        for _ in 0..<12_000 {MatchRenderMetrics.end("probe",started:ProcessInfo.processInfo.systemUptime)}
        XCTAssertEqual(MatchRenderMetrics.frames.count,12_000)
        let before=MatchRenderMetrics.memory.count
        try await Task.sleep(for:.milliseconds(3100))
        MatchRenderMetrics.end("probe",started:ProcessInfo.processInfo.systemUptime)
        XCTAssertEqual(MatchRenderMetrics.frames.count,12_000)
        XCTAssertGreaterThan(MatchRenderMetrics.memory.count,before)
    }
}
