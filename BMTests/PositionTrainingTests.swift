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
            try CareerTrainingStore.attempt(player:p,state:s,record:r,revision:r.revision,input:TrainingInput(force:80,angle:35),in:c)
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
        var old=snapshot;old.fieldStats?.version=2;old.fieldStats?.positionMastery=nil
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
}
