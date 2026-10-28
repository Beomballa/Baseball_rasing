import XCTest
import SwiftData
@testable import BM

@MainActor final class PositionTrainingTests: XCTestCase {
    private func setup(_ context: ModelContext, role: PlayerRole = .batter, date: String = "2026-04-02") throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = "위치훈련"; draft.schoolID = "hs-ref-001"; draft.position = .shortstop; draft.role = role
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        player.gameDate = date; player.fatigue = 24; try context.save()
        return (player, try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }))
    }
    private func input(_ training: CareerTraining) throws -> TrainingInput {
        guard !training.completed else { return TrainingInput() }
        let position = try XCTUnwrap(training.position), t = training.targets[training.scores.count]
        let target = TrainingRules.basePoint(position.targetBase), dx = target.x - t.x, dy = target.y - t.y
        return TrainingInput(x: t.x, y: t.y, force: hypot(dx, dy) / 0.9 * 100,
                             angle: (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360), base: position.targetBase)
    }
    private func attempt(_ p: CareerPlayer, _ s: CareerCalendarState, _ r: CareerTrainingRecord, _ c: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        try CareerTrainingStore.attempt(player: p, state: s, record: r, revision: r.revision, input: input(r.snapshot()), in: c, save: save)
    }
    func testIndependentScoringGrowthCarryCapAndPrecision() throws {
        XCTAssertEqual(try PositionTrainingRules.score(position: .catcher, target: TrainingTarget(x: 0.5, y: 0.5), input: TrainingInput(x: 0.5, y: 0.5, force: 160.0 / 9, angle: 270, base: 2)), 100)
        XCTAssertEqual(try PositionTrainingRules.score(position: .catcher, target: TrainingTarget(x: 0.5, y: 0.5), input: TrainingInput(x: 0.5, y: 0.5, force: 0, angle: 0, base: 1)), 60)
        XCTAssertEqual(PositionTrainingRules.gainedXP(mastery: 60, score: 100, fatigue: 24, age: 16), 50.7)
        XCTAssertEqual(PositionTrainingRules.gainedXP(mastery: 10, score: 100, fatigue: 24, age: 16), 78)
        XCTAssertEqual(PositionTrainingRules.gainedXP(mastery: 85, score: 100, fatigue: 80, age: 40), 0.78)
        XCTAssertEqual(PositionTrainingRules.gainedXP(mastery: 10, score: 0, fatigue: 24, age: 16), 60)
        XCTAssertEqual(PositionTrainingRules.adding(50.7, to: PositionSkill(mastery: 60, xp: 90)), PositionSkill(mastery: 61, xp: 40.7))
        XCTAssertEqual(PositionTrainingRules.adding(78, to: PositionSkill(mastery: 99, xp: 90)), PositionSkill(mastery: 100, xp: 0))
        XCTAssertThrowsError(try PositionTrainingRules.score(position: .catcher, target: TrainingTarget(x: 0.5, y: 0.5), input: TrainingInput(force: .nan, angle: 0, base: 2)))
        var invalid = PositionLoadout(primary: .shortstop); invalid.skills["SS"]?.xp = 100
        XCTAssertThrowsError(try invalid.validate())
    }
    func testAllEightPositionsFiveAttemptsOnlySelectedXPChanges() throws {
        for position in FieldPosition.allCases {
            let container = try CareerStore.makeContainer(inMemory: true), c = container.mainContext
            let (p, s) = try setup(c), profile = try XCTUnwrap(PlayerPositionStore.profile(playerID: p.id, in: c))
            let original = try profile.snapshot(), raw = [p.contact, p.power, p.discipline, p.speed, p.defense, p.arm]
            let traits = try XCTUnwrap(PlayerTraitStore.profile(playerID: p.id, in: c)).payload
            let r = try CareerTrainingStore.start(player: p, state: s, position: position, in: c)
            XCTAssertEqual(r.rulesVersion, "native-position-training-v1")
            for i in 1...5 {
                try attempt(p, s, r, c)
                XCTAssertEqual(try r.snapshot().scores.count, i)
                XCTAssertEqual(p.fatigue, i == 5 ? 30 : 24)
                XCTAssertEqual(s.hasAction(on: p.gameDate), i == 5)
                if i < 5 { XCTAssertEqual(try profile.snapshot(), original) }
            }
            let after = try profile.snapshot()
            XCTAssertEqual(try r.snapshot().scores, [100,100,100,100,100])
            XCTAssertEqual(try after.skill(position).xp, position == .shortstop ? 50.7 : 78)
            for other in FieldPosition.allCases where other != position { XCTAssertEqual(try after.skill(other), try original.skill(other)) }
            XCTAssertEqual([p.contact, p.power, p.discipline, p.speed, p.defense, p.arm], raw)
            XCTAssertEqual(try PlayerTraitStore.profile(playerID: p.id, in: c)?.payload, traits)
            XCTAssertEqual(p.positionRaw, "SS"); XCTAssertEqual(profile.revision, 1)
        }
    }
    func testStartIntermediateFinalFailuresAndStaleLocks() throws {
        enum Failure: Error { case injected }
        let container = try CareerStore.makeContainer(inMemory: true), c = container.mainContext
        let (p,s) = try setup(c), profile = try XCTUnwrap(PlayerPositionStore.profile(playerID: p.id, in: c))
        XCTAssertThrowsError(try CareerTrainingStore.start(player: p, state: s, position: .shortstop, in: c, save: { _ in throw Failure.injected }))
        XCTAssertNil(try CareerTrainingStore.record(player: p, in: c)); XCTAssertEqual(s.revision, 0)
        let r = try CareerTrainingStore.start(player: p, state: s, position: .shortstop, in: c)
        XCTAssertThrowsError(try CareerTrainingStore.start(player: p, state: s, position: .first, in: c))
        XCTAssertThrowsError(try CareerTrainingStore.start(player: p, state: s, trait: .cheetah, position: .first, in: c))
        XCTAssertThrowsError(try CalendarProgression.rest(player: p, state: s, revision: s.revision, in: c))
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, in: c))
        XCTAssertThrowsError(try PlayerTraitStore.requireEditable(player: p, state: s, in: c))
        let first = r.payload
        XCTAssertThrowsError(try attempt(p,s,r,c,save:{ _ in throw Failure.injected })); XCTAssertEqual(r.payload, first)
        for _ in 0..<4 { try attempt(p,s,r,c) }
        let payload = r.payload, original = profile.payload, revision = r.revision, calendarRevision = s.revision
        XCTAssertThrowsError(try attempt(p,s,r,c,save:{ _ in throw Failure.injected }))
        XCTAssertEqual(r.payload, payload); XCTAssertEqual(profile.payload, original); XCTAssertEqual(profile.revision,0)
        XCTAssertEqual(r.revision,revision); XCTAssertEqual(s.revision,calendarRevision); XCTAssertEqual(p.fatigue,24)
        profile.revision += 1; try c.save()
        XCTAssertThrowsError(try attempt(p,s,r,c)); profile.revision -= 1; try c.save()
        try attempt(p,s,r,c)
        let completed = r.payload
        XCTAssertThrowsError(try attempt(p,s,r,c)); XCTAssertEqual(r.payload,completed); XCTAssertEqual(p.fatigue,30)
        XCTAssertThrowsError(try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c))
        var invalid = try r.snapshot(); invalid.positionXP = nil; r.payload = try JSONEncoder().encode(invalid)
        XCTAssertThrowsError(try r.snapshot()); c.rollback()
    }
    func testDiskResumeCarryAndResultRewardOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:directory) }
        let url = directory.appendingPathComponent("positions.store")
        let partial = try autoreleasepool {
            let container = try CareerStore.makeContainer(url:url), c=container.mainContext
            let (p,s)=try setup(c), profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            var value=try profile.snapshot(); value.skills["SS"]?.xp=90; profile.payload=try JSONEncoder().encode(value); try c.save()
            let r=try CareerTrainingStore.start(player:p,state:s,position:.shortstop,in:c)
            for _ in 0..<2 { try attempt(p,s,r,c) }; return r.payload
        }
        let final = try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(CareerTrainingStore.record(player:p,in:c)); XCTAssertEqual(r.payload,partial)
            for _ in 0..<3 { try attempt(p,s,r,c) }
            XCTAssertEqual(try PlayerPositionStore.profile(playerID:p.id,in:c)?.snapshot().skill(.shortstop),PositionSkill(mastery:61,xp:40.7))
            return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(CareerTrainingStore.record(player:p,in:c)); XCTAssertEqual(r.payload,final)
            XCTAssertEqual(try CareerTrainingStore.start(player:p,state:s,in:c).payload,final)
            XCTAssertThrowsError(try attempt(p,s,r,c)); XCTAssertEqual(p.fatigue,30)
            XCTAssertTrue(s.hasAction(on:p.gameDate)); XCTAssertEqual(try r.snapshot().positionAfter,PositionSkill(mastery:61,xp:40.7))
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
            XCTAssertEqual(p.fatigue,26); XCTAssertFalse(s.hasAction(on:p.gameDate))
        }
    }
    func testV6FileMigrationPreservesOldPayloadsAndAddsDefaultsOnce() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("v6.store")
        let originals=try autoreleasepool {
            let schema=Schema(versionedSchema:CareerSchemaV6.self)
            let container=try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
            let c=container.mainContext;c.autosaveEnabled=false
            let (p,s)=try setup(c,date:"2026-04-01")
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let game=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:game,revision:game.revision,input:.automatic,in:c)
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
            let r=try CareerTrainingStore.start(player:p,state:s,kind:.power,in:c)
            try CareerTrainingStore.attempt(player:p,state:s,record:r,revision:r.revision,input:TrainingInput(drill:SkillDrillInput(phase:0.5)),in:c)
            let traits=try XCTUnwrap(PlayerTraitStore.profile(playerID:p.id,in:c))
            return (r.payload,game.payload,traits.payload,[p.contact,p.power,p.speed,p.defense,p.arm],p.fatigue,p.gameDate,s.revision)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c));XCTAssertEqual(profile.source,"legacy-v1")
            XCTAssertEqual(try profile.snapshot().skill(.shortstop),PositionSkill(mastery:60,xp:0))
            XCTAssertEqual(try profile.snapshot().skill(.catcher),PositionSkill(mastery:10,xp:0))
            XCTAssertEqual(try CareerTrainingStore.record(player:p,in:c)?.payload,originals.0)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).first?.payload,originals.1)
            XCTAssertEqual(try PlayerTraitStore.profile(playerID:p.id,in:c)?.payload,originals.2)
            XCTAssertEqual([p.contact,p.power,p.speed,p.defense,p.arm],originals.3);XCTAssertEqual(p.fatigue,originals.4)
            XCTAssertEqual(p.gameDate,originals.5);XCTAssertEqual(s.revision,originals.6)
            let data=profile.payload;try PlayerPositionStore.addMissing(in:c);XCTAssertEqual(profile.payload,data)
            XCTAssertEqual(try c.fetchCount(FetchDescriptor<PlayerPositions>()),1)
        }
    }
    func testNewMatchSnapshotPositionDelayAndOldMatchUnchanged() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,s)=try setup(c,date:"2026-04-01"),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        var v=try profile.snapshot();v.skills["SS"]?.xp=90;profile.payload=try JSONEncoder().encode(v);try c.save()
        let r=try CareerTrainingStore.start(player:p,state:s,position:.shortstop,in:c)
        for _ in 0..<5 {try attempt(p,s,r,c)}
        let game=try CareerMatchStore.start(player:p,state:s,in:c),snapshot=try game.snapshot()
        XCTAssertEqual(snapshot.fieldStats?.version,3);XCTAssertEqual(snapshot.fieldStats?.positionMastery,61)
        let frozen=game.payload
        v=try profile.snapshot();v.skills["SS"]?.mastery=90;profile.payload=try JSONEncoder().encode(v);try c.save()
        XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,frozen)
        let base=MatchFieldPlay(runnerTime:2,ballTime:1.85,ownDefense:true,appliedTraits:[])
        XCTAssertTrue(MatchFieldRules.applyingPosition(base,mastery:10).safe)
        XCTAssertFalse(MatchFieldRules.applyingPosition(base,mastery:90).safe)
        XCTAssertEqual(MatchFieldRules.applyingPosition(base,mastery:60).ballTime,1.95,accuracy:0.00001)
        let running=MatchFieldPlay(runnerTime:2,ballTime:1.85,ownDefense:false,appliedTraits:[])
        XCTAssertEqual(MatchFieldRules.applyingPosition(running,mastery:10),running)
        var old=snapshot;old.fieldStats?.version=2;old.fieldStats?.positionMastery=nil;old.positionExperience=nil
        let data=try JSONEncoder().encode(old);game.payload=data;try c.save()
        XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,data)
    }
    func testPitcherAndMaxMasteryCannotStartPositionTraining() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (pitcher,state)=try setup(c,role:.pitcher)
        XCTAssertNil(try PlayerPositionStore.profile(playerID:pitcher.id,in:c))
        XCTAssertThrowsError(try CareerTrainingStore.start(player:pitcher,state:state,position:.catcher,in:c))
        let (p,s)=try setup(c),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        var v=try profile.snapshot();v.skills["SS"]=PositionSkill(mastery:100,xp:0);profile.payload=try JSONEncoder().encode(v);try c.save()
        XCTAssertThrowsError(try CareerTrainingStore.start(player:p,state:s,position:.shortstop,in:c))
        XCTAssertNil(try CareerTrainingStore.record(player:p,in:c))
    }
    func testActualMatchEngineAppliesPositionOnlyToOwnDefense() throws {
        var observed = false
        for seed in 1...200 {
            var old=CareerMatch(random:UInt64(seed),isHome:true,role:"batter",appearance:true,contact:60,power:0,discipline:60,mastery:[:])
            old.fieldStats=MatchFieldStats(version:2,speed:60,defense:60,arm:60,position:"SS",activeTraits:[])
            var perfect=old;perfect.fieldStats?.version=3;perfect.fieldStats?.positionMastery=100
            old.settle();perfect.settle()
            XCTAssertEqual(old.random,perfect.random);XCTAssertEqual(old.line,perfect.line)
            XCTAssertEqual(old.homeScore,perfect.homeScore);XCTAssertEqual(old.awayScore,perfect.awayScore)
            if let play=perfect.lastFieldPlay,play.ownDefense {
                XCTAssertEqual(play.positionDelay,0);observed=true
                XCTAssertEqual(play.ballTime,try XCTUnwrap(old.lastFieldPlay).ballTime)
                break
            }
        }
        XCTAssertTrue(observed,"a defensive opportunity must run through the actual match engine")
    }
    func testMaxAwardRollbackAndRoundedPerformanceBand() throws {
        enum Failure: Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,s)=try setup(c),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        var v=try profile.snapshot();v.skills["SS"]=PositionSkill(mastery:99,xp:99.9);profile.payload=try JSONEncoder().encode(v);try c.save()
        let r=try CareerTrainingStore.start(player:p,state:s,position:.shortstop,in:c)
        for _ in 0..<4 {try attempt(p,s,r,c)}
        let data=profile.payload
        XCTAssertThrowsError(try attempt(p,s,r,c,save:{_ in throw Failure.injected}))
        XCTAssertEqual(profile.payload,data);XCTAssertFalse(r.completed)
        try attempt(p,s,r,c)
        XCTAssertEqual(try profile.snapshot().skill(.shortstop),PositionSkill(mastery:100,xp:0))
        var band=CareerTraining(playerID:p.id,date:p.gameDate,role:"batter",pitchCode:nil,before:60,fatigue:24,age:16,calendarRevision:0,kind:.defense,position:.shortstop)
        band.positionXP=0;band.scores=[90,90,90,90,89]
        XCTAssertEqual(band.average,89.8);XCTAssertEqual(band.positionGainXP,50.7)
    }
    func testMissingProfileSaveFailureAndDamagedExistingDataNeverReset() throws {
        enum Failure: Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,_)=try setup(c),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        c.delete(profile);try c.save()
        XCTAssertThrowsError(try PlayerPositionStore.addMissing(in:c,save:{_ in throw Failure.injected}))
        XCTAssertNil(try PlayerPositionStore.profile(playerID:p.id,in:c))
        try PlayerPositionStore.addMissing(in:c)
        let restored=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        restored.payload=Data("broken".utf8);try c.save()
        try PlayerPositionStore.addMissing(in:c)
        XCTAssertEqual(restored.payload,Data("broken".utf8));XCTAssertThrowsError(try restored.snapshot())
    }
    private func gameReady(_ c: ModelContext) throws -> (CareerPlayer, CareerCalendarState, CareerMatchRecord, PlayerPositions) {
        let (p,s) = try setup(c, date: "2026-04-01")
        let profile = try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
        var value = try profile.snapshot(); value.skills["SS"]?.xp = 99
        profile.payload = try JSONEncoder().encode(value); try c.save()
        try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
        let r = try CareerMatchStore.start(player:p,state:s,in:c)
        let initial = try r.snapshot()
        // Fix only the test RNG. Require a genuine defensive opportunity in the engine.
        for seed in 1...100 {
            var candidate = initial; candidate.random = UInt64(seed)
            var final = candidate; try final.advance(.automatic)
            if final.positionExperience?.events.isEmpty == false {
                r.payload = try JSONEncoder().encode(candidate); try c.save()
                return (p,s,r,profile)
            }
        }
        throw MatchError.invalidRecord
    }
    func testGameXPFormulaParticipationSuccessBandsCarryAndCap() throws {
        let safe = MatchFieldPlay(runnerTime:3,ballTime:4,ownDefense:true)
        let out = MatchFieldPlay(runnerTime:4,ballTime:3,ownDefense:true)
        var xp = MatchPositionExperience(position:.shortstop,before:PositionSkill(mastery:60,xp:99),profileRevision:0,age:16,fatigue:24)
        xp.events = [MatchPositionEvent(half:0,order:0,play:safe),MatchPositionEvent(half:0,order:1,play:out)]
        XCTAssertEqual(xp.successes,1); XCTAssertEqual(xp.gainedXP,13.65)
        XCTAssertEqual(xp.after,PositionSkill(mastery:61,xp:12.65))
        xp = MatchPositionExperience(position:.shortstop,before:PositionSkill(mastery:99,xp:99.99),profileRevision:0,age:40,fatigue:80,events:xp.events)
        XCTAssertEqual(xp.gainedXP,0.0263); XCTAssertEqual(xp.after,PositionSkill(mastery:100,xp:0))
        xp = MatchPositionExperience(position:.shortstop,before:PositionSkill(mastery:100,xp:0),profileRevision:0,age:16,fatigue:0,events:xp.events)
        XCTAssertEqual(xp.gainedXP,0); XCTAssertEqual(xp.after.mastery,100)
    }
    func testGameXPActualParticipationAllPositionsAndNoInventedLegacyEvents() throws {
        for position in FieldPosition.allCases {
            var found = false
            for seed in 1...40 {
                var game = CareerMatch(random:UInt64(seed),isHome:seed % 2 == 0,role:"batter",appearance:true,contact:60,power:0,discipline:60,mastery:[:])
                game.fieldStats = MatchFieldStats(version:3,speed:60,defense:60,arm:60,position:position.rawValue,activeTraits:[],positionMastery:60)
                game.positionExperience = MatchPositionExperience(position:position,before:PositionSkill(mastery:60,xp:0),profileRevision:0,age:16,fatigue:0)
                var legacy = game; legacy.positionExperience = nil
                try game.advance(.automatic); try legacy.advance(.automatic)
                let ledger = try XCTUnwrap(game.positionExperience); try ledger.validate(match:game)
                XCTAssertEqual(game.random,legacy.random);XCTAssertEqual(game.line,legacy.line)
                XCTAssertEqual(game.teamScore,legacy.teamScore);XCTAssertEqual(game.opponentScore,legacy.opponentScore)
                XCTAssertTrue(ledger.events.allSatisfy { $0.play.ownDefense })
                XCTAssertNil(legacy.positionExperience)
                // Removing the opt-in ledger must not change a single gameplay decision/RNG draw.
                game.positionExperience = nil; XCTAssertEqual(game,legacy)
                if !ledger.events.isEmpty { found=true;break }
            }
            XCTAssertTrue(found,position.rawValue)
        }
    }
    func testGameXPAtomicFailureRetryStaleProfileAndNoDuplicateReward() throws {
        enum Failure: Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,s,r,profile)=try gameReady(c)
        let payload=r.payload,positions=profile.payload,fatigue=p.fatigue,revision=s.revision
        XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c,save:{_ in throw Failure.injected}))
        XCTAssertEqual(r.payload,payload);XCTAssertEqual(profile.payload,positions);XCTAssertEqual(profile.revision,0)
        XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision);XCTAssertFalse(r.completed)
        profile.revision += 1;try c.save()
        XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
        XCTAssertEqual(r.payload,payload);XCTAssertEqual(p.fatigue,fatigue)
        profile.revision -= 1;try c.save()
        try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
        let xp=try XCTUnwrap(r.snapshot().positionExperience),after=profile.payload
        XCTAssertGreaterThan(xp.gainedXP,0);XCTAssertEqual(try profile.snapshot().skill(.shortstop),xp.after)
        XCTAssertEqual(profile.revision,1)
        for position in FieldPosition.allCases where position != .shortstop {
            XCTAssertEqual(try profile.snapshot().skill(position),PositionSkill(mastery:10,xp:0))
        }
        XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
        XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,r.payload)
        XCTAssertEqual(profile.payload,after);XCTAssertEqual(profile.revision,1)
    }
    func testGameXPDiskResumeAndNextGameUsesNewMasteryOnly() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("game-xp.store")
        let partial=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,r,profile)=try gameReady(c)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.watch,control:ManualMatchInput(),in:c)
            XCTAssertFalse(r.completed);XCTAssertEqual(try profile.snapshot().skill(.shortstop).xp,99)
            return r.payload
        }
        let final=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first);XCTAssertEqual(r.payload,partial)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let xp=try XCTUnwrap(r.snapshot().positionExperience)
            XCTAssertGreaterThan(xp.after.mastery,xp.before.mastery)
            XCTAssertEqual(try r.snapshot().fieldStats?.positionMastery,xp.before.mastery)
            return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first);XCTAssertEqual(r.payload,final)
            let profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c)),saved=profile.payload
            let after=try profile.snapshot().skill(.shortstop)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
            p.gameDate="2026-04-07";try c.save()
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let next=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertEqual(try next.snapshot().fieldStats?.positionMastery,after.mastery)
            XCTAssertEqual(try next.snapshot().positionExperience?.before,after)
            XCTAssertEqual(profile.payload,saved);XCTAssertEqual(r.payload,final)
            let base=MatchFieldPlay(runnerTime:4,ballTime:3,ownDefense:true)
            XCTAssertLessThan(MatchFieldRules.applyingPosition(base,mastery:after.mastery).ballTime,MatchFieldRules.applyingPosition(base,mastery:60).ballTime)
        }
    }
    func testGameXPLegacyPendingAndCompletedKeepPayloadAndNoRetroactiveReward() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,s,r,profile)=try gameReady(c)
        var old=try r.snapshot();old.positionExperience=nil
        r.payload=try JSONEncoder().encode(old);try c.save()
        let before=profile.payload
        try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
        XCTAssertNil(try r.snapshot().positionExperience);XCTAssertEqual(profile.payload,before)
        let saved=r.payload
        XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,saved)
        XCTAssertEqual(profile.revision,0)
    }
    func testGameXPDamagedOrDuplicateEventsRejectedWithoutReset() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (_,_,r,_)=try gameReady(c)
        var game=try r.snapshot();try game.advance(.automatic)
        var ledger=try XCTUnwrap(game.positionExperience)
        ledger.events.append(try XCTUnwrap(ledger.events.first));game.positionExperience=ledger
        // Record completion consistency is kept so the ledger validation itself is exercised.
        r.completed=true;r.payload=try JSONEncoder().encode(game);try c.save()
        XCTAssertThrowsError(try r.snapshot());XCTAssertNotNil(try c.fetch(FetchDescriptor<CareerMatchRecord>()).first)
        ledger.events=[];ledger.version=99;game.positionExperience=ledger;r.payload=try JSONEncoder().encode(game);try c.save()
        XCTAssertThrowsError(try r.snapshot())
    }
    func testDetailedV55DiskResumeKeepsOriginalPayloadAndBasicRules() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("legacy-v55.store")
        let original=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,r,_)=try gameReady(c)
            var legacy=try r.snapshot();legacy.pitching=nil;legacy.detailedFieldVersion=nil;legacy.fieldPlays=nil;legacy.runnerProfiles=nil
            r.payload=try JSONEncoder().encode(legacy);try c.save()
            return (r.payload,p.pitches.map(\.mastery),s.revision)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertEqual(r.payload,original.0);XCTAssertEqual(p.pitches.map(\.mastery),original.1);XCTAssertEqual(s.revision,original.2)
            var expected=try r.snapshot();try expected.advance(.automatic)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            XCTAssertEqual(try r.snapshot(),expected);XCTAssertNil(try r.snapshot().fieldPlays)
            let saved=r.payload,profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c)),xp=profile.payload
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,saved)
            XCTAssertEqual(profile.payload,xp)
        }
    }
    func testDetailedDamagedLedgerFailsWithoutSavingOrResettingOtherData() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        let (p,s,r,profile)=try gameReady(c)
        var match=try r.snapshot();match.fieldPlays=nil;r.payload=try JSONEncoder().encode(match);try c.save()
        let raw=r.payload,xp=profile.payload,fatigue=p.fatigue,revision=s.revision
        XCTAssertThrowsError(try CareerMatchStore.start(player:p,state:s,in:c))
        XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
        XCTAssertEqual(r.payload,raw);XCTAssertEqual(profile.payload,xp);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
        match.fieldPlays=[];match.runnerProfiles=[FieldRunnerProfile(speed:.nan),nil,nil]
        XCTAssertThrowsError(try match.validateDetailedField())
    }
    func testDoublePlayPivotDiskResumeAtomicRewardAndResultOnce() throws {
        enum Failure:Error {case injected}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("pivot.store")
        let partial=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,r,profile)=try gameReady(c)
            p.positionRaw="2B"
            var loadout=try profile.snapshot();loadout.skills["2B"]=PositionSkill(mastery:10,xp:99)
            profile.payload=try JSONEncoder().encode(loadout)
            var initial=try r.snapshot()
            initial.fieldStats=MatchFieldStats(version:3,speed:p.speed,defense:p.defense,arm:p.arm,position:"2B",activeTraits:[],positionMastery:10)
            initial.half=initial.isHome ? 0:1;initial.outs=0;initial.bases=[true,false,false]
            initial.fieldPlays=[];initial.runnerProfiles=[FieldRunnerProfile(speed:60),nil,nil]
            initial.positionExperience=MatchPositionExperience(position:.second,before:PositionSkill(mastery:10,xp:99),profileRevision:profile.revision,age:16,fatigue:p.fatigue)
            var found:CareerMatch?
            for seed in 1...300 {
                var candidate=initial;candidate.random=UInt64(seed)
                var next=candidate;try next.advance(.watch,control:ManualMatchInput())
                if next.fieldPlays?.contains(where: { $0.secondThrow?.ownThrower == true }) == true { found=candidate;break }
            }
            r.payload=try JSONEncoder().encode(XCTUnwrap(found));try c.save()
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.watch,control:ManualMatchInput(),in:c)
            XCTAssertFalse(r.completed);XCTAssertEqual(try profile.snapshot().skill(.second),PositionSkill(mastery:10,xp:99))
            return (r.payload,profile.payload)
        }
        let final=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1)
            let fatigue=p.fatigue,revision=s.revision
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c,save:{_ in throw Failure.injected}))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let match=try r.snapshot(),experience=try XCTUnwrap(match.positionExperience),plays=try XCTUnwrap(match.fieldPlays)
            let own=plays.filter(\.ownParticipation)
            XCTAssertEqual(experience.events.count,own.count)
            XCTAssertEqual(experience.successes,own.filter { !$0.xpPlay.safe }.count)
            XCTAssertEqual(Set(experience.events.map { "\($0.half):\($0.order)" }).count,experience.events.count)
            XCTAssertTrue(own.contains { $0.secondThrow?.ownThrower == true })
            XCTAssertEqual(try profile.snapshot().skill(.second),experience.after);XCTAssertEqual(profile.revision,1)
            return (r.payload,profile.payload,p.fatigue)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,final.0);XCTAssertEqual(profile.payload,final.1)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,final.0)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(profile.payload,final.1);XCTAssertEqual(p.fatigue,final.2)
        }
    }
    func testDoublePlayV56DiskKeepsSingleThrowPayloadAndRNGWithoutUpgrade() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("v56.store")
        let original=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (_,_,r,_)=try gameReady(c)
            var old=try r.snapshot();old.pitching=nil;old.detailedFieldVersion=1;old.fieldPlays=[]
            old.bases=[false,false,false];old.runnerProfiles=[nil,nil,nil];old.positionExperience?.events=[]
            r.payload=try JSONEncoder().encode(old);try c.save();return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try CareerMatchStore.start(player:p,state:s,in:c);XCTAssertEqual(r.payload,original)
            var expected=try r.snapshot();try expected.advance(.automatic)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let after=try r.snapshot();XCTAssertEqual(after,expected)
            XCTAssertEqual(after.detailedFieldVersion,1);XCTAssertTrue(after.fieldPlays?.allSatisfy { $0.secondThrow == nil && $0.version == 1 } == true)
            XCTAssertNil(MatchResultSummary(match:after,fatigueBefore:r.fatigueBefore,fatigueAfter:r.fatigueAfter).metrics.first { $0.id == "doublePlays" })
        }
    }
    func testFlyCatchDiskResumeAtomicXPAndResultOnce() throws {
        enum Failure:Error {case injected}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("fly.store")
        let partial=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,r,profile)=try gameReady(c)
            p.positionRaw="CF"
            var loadout=try profile.snapshot();loadout.skills["CF"]=PositionSkill(mastery:10,xp:99)
            profile.payload=try JSONEncoder().encode(loadout)
            var initial=try r.snapshot()
            initial.fieldStats=MatchFieldStats(version:3,speed:p.speed,defense:p.defense,arm:p.arm,position:"CF",activeTraits:[],positionMastery:10)
            initial.half=initial.isHome ? 0:1;initial.outs=0;initial.bases=[false,false,true]
            initial.fieldPlays=[];initial.runnerProfiles=[nil,nil,FieldRunnerProfile(speed:100)]
            initial.positionExperience=MatchPositionExperience(position:.center,before:PositionSkill(mastery:10,xp:99),profileRevision:profile.revision,age:16,fatigue:p.fatigue)
            var found:CareerMatch?
            for seed in 1...300 {
                var candidate=initial;candidate.random=UInt64(seed)
                var next=candidate;try next.advance(.watch,control:ManualMatchInput())
                if next.fieldPlays?.contains(where: { $0.fly?.caught == true && $0.ownDefense }) == true { found=candidate;break }
            }
            r.payload=try JSONEncoder().encode(XCTUnwrap(found));try c.save()
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.watch,control:ManualMatchInput(),in:c)
            XCTAssertFalse(r.completed);XCTAssertEqual(try profile.snapshot().skill(.center),PositionSkill(mastery:10,xp:99))
            return (r.payload,profile.payload)
        }
        let final=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1)
            let fatigue=p.fatigue,revision=s.revision
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c,save:{_ in throw Failure.injected}))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let match=try r.snapshot(),experience=try XCTUnwrap(match.positionExperience),plays=try XCTUnwrap(match.fieldPlays)
            let own=plays.filter(\.ownParticipation)
            XCTAssertEqual(experience.events.count,own.count)
            XCTAssertEqual(experience.successes,own.filter { !$0.xpPlay.safe }.count)
            XCTAssertEqual(Set(experience.events.map { "\($0.half):\($0.order)" }).count,experience.events.count)
            XCTAssertTrue(own.contains { $0.fly?.caught == true && $0.ownDefense })
            XCTAssertEqual(try profile.snapshot().skill(.center),experience.after);XCTAssertEqual(profile.revision,1)
            return (r.payload,profile.payload,p.fatigue)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,final.0);XCTAssertEqual(profile.payload,final.1)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,final.0)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(profile.payload,final.1);XCTAssertEqual(p.fatigue,final.2)
        }
    }
    func testFlyV57DiskKeepsDoublePlayPayloadAndRNGWithoutUpgrade() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("v57.store")
        let original=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (_,_,r,_)=try gameReady(c)
            var old=try r.snapshot();old.pitching=nil;old.detailedFieldVersion=2;old.fieldPlays=[]
            old.bases=[false,false,false];old.runnerProfiles=[nil,nil,nil];old.positionExperience?.events=[]
            r.payload=try JSONEncoder().encode(old);try c.save();return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try CareerMatchStore.start(player:p,state:s,in:c);XCTAssertEqual(r.payload,original)
            var expected=try r.snapshot();try expected.advance(.automatic)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let after=try r.snapshot();XCTAssertEqual(after,expected)
            XCTAssertEqual(after.detailedFieldVersion,2);XCTAssertTrue(after.fieldPlays?.allSatisfy { $0.fly == nil && $0.version == 2 } == true)
            XCTAssertNotNil(MatchResultSummary(match:after,fatigueBefore:r.fatigueBefore,fatigueAfter:r.fatigueAfter).metrics.first { $0.id == "doublePlays" })
        }
    }
    func testRelayCutoffDiskResumeAtomicXPAndResultOnce() throws {
        enum Failure:Error {case injected}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("relay.store")
        let partial=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,r,profile)=try gameReady(c)
            p.positionRaw="2B"
            var loadout=try profile.snapshot();loadout.skills["2B"]=PositionSkill(mastery:10,xp:99)
            profile.payload=try JSONEncoder().encode(loadout)
            var initial=try r.snapshot()
            initial.fieldStats=MatchFieldStats(version:3,speed:p.speed,defense:p.defense,arm:p.arm,position:"2B",activeTraits:[],positionMastery:10)
            initial.half=initial.isHome ? 0:1;initial.outs=0;initial.bases=[false,false,true]
            initial.fieldPlays=[];initial.runnerProfiles=[nil,nil,FieldRunnerProfile(speed:100)]
            initial.positionExperience=MatchPositionExperience(position:.second,before:PositionSkill(mastery:10,xp:99),profileRevision:profile.revision,age:16,fatigue:p.fatigue)
            var found:CareerMatch?
            for seed in 1...2000 {
                var candidate=initial;candidate.random=UInt64(seed)
                var next=candidate;try next.advance(.watch,control:ManualMatchInput())
                if next.fieldPlays?.contains(where: { $0.relay?.ownThrower == true }) == true { found=candidate;break }
            }
            r.payload=try JSONEncoder().encode(XCTUnwrap(found));try c.save()
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.watch,control:ManualMatchInput(),in:c)
            XCTAssertFalse(r.completed);XCTAssertEqual(try profile.snapshot().skill(.second),PositionSkill(mastery:10,xp:99))
            return (r.payload,profile.payload)
        }
        let final=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1)
            let fatigue=p.fatigue,revision=s.revision
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c,save:{_ in throw Failure.injected}))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let match=try r.snapshot(),experience=try XCTUnwrap(match.positionExperience),plays=try XCTUnwrap(match.fieldPlays)
            let own=plays.filter(\.ownParticipation)
            XCTAssertEqual(experience.events.count,own.count)
            XCTAssertEqual(experience.successes,own.filter { !$0.xpPlay.safe }.count)
            XCTAssertEqual(Set(experience.events.map { "\($0.half):\($0.order)" }).count,experience.events.count)
            XCTAssertTrue(own.contains { $0.relay?.ownThrower == true })
            XCTAssertEqual(try profile.snapshot().skill(.second),experience.after);XCTAssertEqual(profile.revision,1)
            return (r.payload,profile.payload,p.fatigue)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,final.0);XCTAssertEqual(profile.payload,final.1)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,final.0)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(profile.payload,final.1);XCTAssertEqual(p.fatigue,final.2)
        }
    }
    func testRelayV58DiskKeepsFlyPayloadAndRNGWithoutUpgrade() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("v58.store")
        let original=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (_,_,r,_)=try gameReady(c)
            var old=try r.snapshot();old.pitching=nil;old.detailedFieldVersion=3;old.fieldPlays=[]
            old.bases=[false,false,false];old.runnerProfiles=[nil,nil,nil];old.positionExperience?.events=[]
            r.payload=try JSONEncoder().encode(old);try c.save();return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try CareerMatchStore.start(player:p,state:s,in:c);XCTAssertEqual(r.payload,original)
            var expected=try r.snapshot();try expected.advance(.automatic)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let after=try r.snapshot();XCTAssertEqual(after,expected)
            XCTAssertEqual(after.detailedFieldVersion,3);XCTAssertTrue(after.fieldPlays?.allSatisfy { $0.relay == nil && $0.version == 3 } == true)
            XCTAssertNotNil(MatchResultSummary(match:after,fatigueBefore:r.fatigueBefore,fatigueAfter:r.fatigueAfter).metrics.first { $0.id == "doublePlays" })
        }
    }
    func testMisplayDiskResumeAtomicXPAndResultOnce() throws {
        enum Failure:Error {case injected}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("misplay.store")
        let partial=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,r,profile)=try gameReady(c)
            p.positionRaw="2B"
            var loadout=try profile.snapshot();loadout.skills["2B"]=PositionSkill(mastery:10,xp:99)
            profile.payload=try JSONEncoder().encode(loadout)
            var initial=try r.snapshot()
            initial.fieldStats=MatchFieldStats(version:3,speed:p.speed,defense:p.defense,arm:p.arm,position:"2B",activeTraits:[],positionMastery:10)
            initial.half=initial.isHome ? 0:1;initial.outs=0;initial.bases=[false,false,true]
            initial.fieldPlays=[];initial.runnerProfiles=[nil,nil,FieldRunnerProfile(speed:100)]
            initial.positionExperience=MatchPositionExperience(position:.second,before:PositionSkill(mastery:10,xp:99),profileRevision:profile.revision,age:16,fatigue:p.fatigue)
            var found:CareerMatch?
            for seed in 1...4000 {
                var candidate=initial;candidate.random=UInt64(seed)
                var next=candidate;try next.advance(.watch,control:ManualMatchInput())
                if next.fieldPlays?.contains(where: { $0.misplay?.ownError == true && $0.ownParticipation }) == true { found=candidate;break }
            }
            r.payload=try JSONEncoder().encode(XCTUnwrap(found));try c.save()
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.watch,control:ManualMatchInput(),in:c)
            XCTAssertFalse(r.completed);XCTAssertEqual(try profile.snapshot().skill(.second),PositionSkill(mastery:10,xp:99))
            return (r.payload,profile.payload)
        }
        let final=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1)
            let fatigue=p.fatigue,revision=s.revision
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c,save:{_ in throw Failure.injected}))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(profile.payload,partial.1);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let match=try r.snapshot(),experience=try XCTUnwrap(match.positionExperience),plays=try XCTUnwrap(match.fieldPlays)
            let own=plays.filter(\.ownParticipation)
            XCTAssertEqual(experience.events.count,own.count)
            XCTAssertEqual(experience.successes,own.filter { !$0.xpPlay.safe }.count)
            XCTAssertEqual(Set(experience.events.map { "\($0.half):\($0.order)" }).count,experience.events.count)
            XCTAssertTrue(own.contains { $0.misplay?.ownError == true && $0.ownParticipation })
            XCTAssertEqual(try profile.snapshot().skill(.second),experience.after);XCTAssertEqual(profile.revision,1)
            return (r.payload,profile.payload,p.fatigue)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first),profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c))
            XCTAssertEqual(r.payload,final.0);XCTAssertEqual(profile.payload,final.1)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,final.0)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(profile.payload,final.1);XCTAssertEqual(p.fatigue,final.2)
        }
    }
    func testMisplayV59DiskKeepsRelayPayloadAndRNGWithoutUpgrade() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("v59.store")
        let original=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (_,_,r,_)=try gameReady(c)
            var old=try r.snapshot();old.pitching=nil;old.detailedFieldVersion=4;old.fieldPlays=[]
            old.bases=[false,false,false];old.runnerProfiles=[nil,nil,nil];old.positionExperience?.events=[]
            r.payload=try JSONEncoder().encode(old);try c.save();return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let r=try CareerMatchStore.start(player:p,state:s,in:c);XCTAssertEqual(r.payload,original)
            var expected=try r.snapshot();try expected.advance(.automatic)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let after=try r.snapshot();XCTAssertEqual(after,expected)
            XCTAssertEqual(after.detailedFieldVersion,4);XCTAssertTrue(after.fieldPlays?.allSatisfy { $0.misplay == nil && $0.version == 4 } == true)
            XCTAssertNotNil(MatchResultSummary(match:after,fatigueBefore:r.fatigueBefore,fatigueAfter:r.fatigueAfter).metrics.first { $0.id == "doublePlays" })
        }
    }
}

extension PositionTrainingTests {
    private func v41Values(_ speed:Double,_ defense:Double,_ arm:Double,_ mental:Double) -> HomeAbilitySummary {
        HomeAbilitySummary(axes:[],originals:zip(["homeSpeed","homeDefense","homeArm","homeMental"],[speed,defense,arm,mental]).map {HomeAbilityValue(id:$0.0,label:$0.0,current:$0.1,initial:nil)},pitches:[],hasInitialValues:false)
    }
    func testV41AdviceSeparatesRawFitMasteryAndNoSpecialistClaims() throws {
        let skills=PositionLoadout(primary:.shortstop),abilities=v41Values(95,50,80,55)
        let advice=try PositionAdvice.make(abilities:abilities,loadout:skills,primary:.shortstop)
        XCTAssertEqual(advice.recommendation,.center);XCTAssertEqual(advice.rows.count,8)
        XCTAssertEqual(advice.rows.first {$0.position == .center}?.fit,76)
        XCTAssertEqual(advice.rows.first {$0.position == .center}?.skill.mastery,10)
        var trained=skills;trained.skills["CF"]=PositionSkill(mastery:45,xp:30)
        let next=try PositionAdvice.make(abilities:abilities,loadout:trained,primary:.shortstop)
        XCTAssertEqual(next.rows.map(\.fit),advice.rows.map(\.fit));XCTAssertEqual(next.recommendation,.center)
        XCTAssertNil(advice.rows.first {$0.position == .catcher}?.fit)
        XCTAssertNil(try PositionAdvice.make(abilities:abilities,loadout:skills,primary:.catcher).recommendation)
        XCTAssertNil(try PositionAdvice.make(abilities:v41Values(60,60,60,60),loadout:skills,primary:.shortstop).recommendation)
        for p in FieldPosition.allCases where p != .catcher {XCTAssertEqual(PositionAdvice.weights(p)!.reduce(0,+),1,accuracy:0.0001)}
    }
    func testV41MissingOrCorruptAbilityNeverCreatesAdvice() throws {
        let skills=PositionLoadout(primary:.shortstop)
        XCTAssertThrowsError(try PositionAdvice.make(abilities:v41Values(.nan,50,50,50),loadout:skills,primary:.shortstop))
        XCTAssertThrowsError(try PositionAdvice.make(abilities:v41Values(101,50,50,50),loadout:skills,primary:.shortstop))
        let partial=HomeAbilitySummary(axes:[],originals:[],pitches:[],hasInitialValues:false)
        XCTAssertThrowsError(try PositionAdvice.make(abilities:partial,loadout:skills,primary:.shortstop))
        var bad=skills;bad.skills["CF"]=nil
        XCTAssertThrowsError(try PositionAdvice.make(abilities:v41Values(60,60,60,60),loadout:bad,primary:.shortstop))
    }
    func testV41AdviceReadsWithoutWritingOrChangingPendingTraining() throws {
        let db=try CareerStore.makeContainer(inMemory:true),c=db.mainContext,(p,s)=try setup(c)
        let row=try CareerTrainingStore.start(player:p,state:s,position:.center,in:c);try attempt(p,s,row,c)
        let bytes=row.payload,life=p.lifecycleData,revision=s.revision,profile=try XCTUnwrap(PlayerPositionStore.profile(playerID:p.id,in:c)),positions=profile.payload,stats=[p.speed,p.defense,p.arm,Double(p.fatigue)]
        let abilities=HomeAbilitySummary(player:p,abilities:try PlayerAbilityStore.profile(playerID:p.id,in:c))
        let a=try PositionAdvice.make(abilities:abilities,loadout:profile.snapshot(),primary:.shortstop)
        XCTAssertEqual(try PositionAdvice.make(abilities:abilities,loadout:profile.snapshot(),primary:.shortstop).rows,a.rows)
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(p.lifecycleData,life);XCTAssertEqual(profile.payload,positions);XCTAssertEqual(s.revision,revision);XCTAssertEqual([p.speed,p.defense,p.arm,Double(p.fatigue)],stats);XCTAssertFalse(c.hasChanges)
        XCTAssertThrowsError(try DevelopmentStore.changePosition(player:p,calendar:s,to:.center,date:p.gameDate,revision:s.revision,in:c))
        for _ in 0..<4 {try attempt(p,s,row,c)}
        XCTAssertThrowsError(try attempt(p,s,row,c));XCTAssertTrue(row.completed)
    }
}
