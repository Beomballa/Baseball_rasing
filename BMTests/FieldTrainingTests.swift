import XCTest
import SwiftData
@testable import BM

@MainActor final class FieldTrainingTests: XCTestCase {
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
}
