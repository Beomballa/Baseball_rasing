import XCTest
import SwiftData
import SwiftUI
@testable import BM

@MainActor final class FieldTrainingTests: XCTestCase {
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
            XCTAssertEqual(FieldReplayPresentation.phase(play,time:error.at,finished:false),"벗어난 공 회수 · 주자 이동 중")
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
            XCTAssertEqual(actions,kind == "catcher" ? ["gather"]:["runA","runB"])
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

}
