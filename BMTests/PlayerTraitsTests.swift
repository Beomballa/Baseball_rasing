import XCTest
import SwiftData
@testable import BM

@MainActor final class PlayerTraitsTests: XCTestCase {
    private func traitSetup(_ context: ModelContext, role: PlayerRole = .batter, progress: [String: Double] = [:]) throws -> (CareerPlayer, CareerCalendarState, PlayerTraits) {
        let (player, state, profile) = try setup(context, role: role)
        player.gameDate = "2026-04-02"; player.speed = 60; player.arm = 60; player.defense = 60; player.fatigue = 24
        profile.payload = try JSONEncoder().encode(TraitLoadout(owned: [], active: [], progress: progress))
        try context.save(); return (player, state, profile)
    }
    private func traitInput(_ training: CareerTraining) -> TrainingInput {
        guard !training.completed else { return TrainingInput() }
        if training.trait == .cheetah { return TrainingInput(footfalls: (0..<16).map { $0.isMultiple(of: 2) ? .left : .right }) }
        if training.trait == .safeHands { let t = training.targets[training.scores.count]; return TrainingInput(x: t.x, y: t.y) }
        let base = training.throwBase(training.scores.count), point = TrainingRules.basePoint(base)
        let dx = point.x - 0.5, dy = point.y - 0.63
        return TrainingInput(force: hypot(dx, dy) / 0.55 * 100, angle: (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360), base: base)
    }
    private func traitAttempt(_ player: CareerPlayer, _ state: CareerCalendarState, _ record: CareerTrainingRecord, _ context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision,
                                       input: traitInput(record.snapshot()), in: context, save: save)
    }
    func testTraitTrainingFiveAttemptsBothRolesAllTraitsOnlyProgressGrows() throws {
        for role in PlayerRole.allCases { for trait in PlayerTrait.allCases {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, state, profile) = try traitSetup(context, role: role)
            let ability = try XCTUnwrap(PlayerAbilityStore.profile(playerID: player.id, in: context))
            let abilities = [ability.mental, ability.velocity, ability.control, ability.stuff, ability.stamina]
            let originals = [player.contact, player.power, player.discipline, player.speed, player.arm, player.defense]
            let pitches = player.pitches.sorted { $0.code < $1.code }.map(\.mastery)
            let record = try CareerTrainingStore.start(player: player, state: state, trait: trait, in: context)
            XCTAssertEqual(record.rulesVersion, "native-trait-training-v1")
            for count in 1...5 {
                try traitAttempt(player, state, record, context)
                XCTAssertEqual(try record.snapshot().scores.count, count)
                XCTAssertEqual(try profile.snapshot().trainingProgress(trait), count == 5 ? 4.68 : 0)
                XCTAssertEqual(player.fatigue, count == 5 ? 30 : 24)
                XCTAssertEqual(state.hasAction(on: player.gameDate), count == 5)
            }
            XCTAssertEqual(try record.snapshot().scores, [100,100,100,100,100])
            XCTAssertEqual([player.contact, player.power, player.discipline, player.speed, player.arm, player.defense], originals)
            XCTAssertEqual(player.pitches.sorted { $0.code < $1.code }.map(\.mastery), pitches)
            XCTAssertEqual([ability.mental, ability.velocity, ability.control, ability.stuff, ability.stamina], abilities)
            XCTAssertEqual(try profile.snapshot().active, [])
        } }
    }
    func testTraitTrainingFailuresStaleInputAndDailyLocksAreAtomic() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, state, profile) = try traitSetup(context)
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context, save: { _ in throw Injected.failure }))
        XCTAssertNil(try CareerTrainingStore.record(player: player, in: context)); XCTAssertEqual(state.revision, 0)
        let record = try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context)
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context))
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context))
        XCTAssertThrowsError(try PlayerTraitStore.requireEditable(player: player, state: state, in: context))
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: state, trait: .cheetah, in: context))
        XCTAssertEqual(try CareerTrainingStore.start(player: player, state: state, kind: .power, in: context).key, record.key)
        let initial = record.payload
        XCTAssertThrowsError(try traitAttempt(player, state, record, context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(record.payload, initial)
        for _ in 0..<4 { try traitAttempt(player, state, record, context) }
        let payload = record.payload, revision = record.revision, calendarRevision = state.revision, traitPayload = profile.payload
        XCTAssertThrowsError(try traitAttempt(player, state, record, context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(record.payload, payload); XCTAssertEqual(record.revision, revision); XCTAssertEqual(state.revision, calendarRevision)
        XCTAssertEqual(profile.payload, traitPayload); XCTAssertEqual(player.fatigue, 24); XCTAssertFalse(record.completed)
        XCTAssertThrowsError(try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: 0, input: traitInput(record.snapshot()), in: context))
        try traitAttempt(player, state, record, context)
        let final = record.payload
        XCTAssertThrowsError(try traitAttempt(player, state, record, context))
        XCTAssertEqual(record.payload, final); XCTAssertEqual(player.fatigue, 30)
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context))
    }
    func testTraitTrainingDiskResumeAcquisitionAndResultReopenOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trait-training.store")
        let payload = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let (player, state, _) = try traitSetup(context, progress: [PlayerTrait.strongArm.rawValue:99.8])
            let record = try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context)
            for _ in 0..<2 { try traitAttempt(player, state, record, context) }
            return record.payload
        }
        let finished = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
            let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let profile = try XCTUnwrap(PlayerTraitStore.profile(playerID: player.id, in: context))
            let record = try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context)
            XCTAssertEqual(record.payload, payload); XCTAssertEqual(try record.snapshot().scores.count, 2)
            for _ in 0..<2 { try traitAttempt(player, state, record, context) }
            enum Injected: Error { case failure }
            let before = record.payload, traitBefore = profile.payload, revisionBefore = profile.revision
            XCTAssertThrowsError(try traitAttempt(player, state, record, context, save: { _ in throw Injected.failure }))
            XCTAssertEqual(record.payload, before); XCTAssertEqual(profile.payload, traitBefore); XCTAssertEqual(profile.revision, revisionBefore)
            XCTAssertEqual(try profile.snapshot().owned, []); XCTAssertEqual(player.fatigue, 24)
            try traitAttempt(player, state, record, context)
            XCTAssertEqual(try profile.snapshot().owned, [.strongArm]); XCTAssertEqual(try profile.snapshot().active, [])
            XCTAssertEqual(try profile.snapshot().trainingProgress(.strongArm), 100)
            XCTAssertThrowsError(try toggle(.strongArm, player, state, profile, context))
            return record.payload
        }
        let container = try CareerStore.makeContainer(url: url), context = container.mainContext
        let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let profile = try XCTUnwrap(PlayerTraitStore.profile(playerID: player.id, in: context))
        let record = try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context)
        XCTAssertEqual(record.payload, finished); XCTAssertEqual(player.fatigue, 30)
        XCTAssertThrowsError(try traitAttempt(player, state, record, context)); XCTAssertEqual(player.fatigue, 30)
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
        try toggle(.strongArm, player, state, profile, context)
        XCTAssertEqual(try profile.snapshot().active, [.strongArm]); XCTAssertEqual(player.fatigue, 26)
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context))
    }
    func testTraitTrainingEligibilityRevisionsAndMalformedPayloads() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player, state, profile) = try traitSetup(context)
        player.arm = 59; try context.save()
        XCTAssertThrowsError(try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context))
        player.arm = 60; try context.save()
        let record = try CareerTrainingStore.start(player: player, state: state, trait: .strongArm, in: context)
        profile.revision += 1; try context.save()
        XCTAssertThrowsError(try traitAttempt(player, state, record, context)); XCTAssertEqual(try record.snapshot().scores, [])
        profile.revision -= 1; try context.save()
        var value = try record.snapshot(); value.traitRevision = nil
        record.payload = try JSONEncoder().encode(value)
        XCTAssertThrowsError(try record.snapshot())
        for loadout in [TraitLoadout(owned: [], active: [], progress: ["unknown":1]), TraitLoadout(owned: [], active: [], progress: ["cheetah":100]), TraitLoadout(owned: [.cheetah], active: [], progress: ["cheetah":80])] {
            XCTAssertThrowsError(try loadout.validate())
        }
    }
    func testOldTraitPayloadAndGrowthPrecisionRemainCompatible() throws {
        let old = Data("{\"owned\":[\"strong-arm\"],\"active\":[]}".utf8)
        let value = try JSONDecoder().decode(TraitLoadout.self, from: old)
        try value.validate(); XCTAssertEqual(value.progress, [:]); XCTAssertEqual(value.trainingProgress(.strongArm), 100)
        XCTAssertEqual(TrainingRules.traitGrowth(before: 0, score: 100, fatigue: 24, age: 16), 4.68)
        XCTAssertEqual(TrainingRules.traitGrowth(before: 60, score: 50, fatigue: 50, age: 30), 60.6864)
        XCTAssertEqual(TrainingRules.traitGrowth(before: 99.5, score: 100, fatigue: 90, age: 40), 99.5819)
        var boundary = CareerTraining(playerID: UUID(), date: "2026-04-02", role: "batter", pitchCode: nil, before: 0, fatigue: 24, age: 16, calendarRevision: 1, kind: .arm)
        boundary.trait = .strongArm; boundary.traitRevision = 0; boundary.scores = [90,90,90,90,89]
        XCTAssertEqual(boundary.average, 89.8); XCTAssertEqual(boundary.after, 4.68)
        boundary.scores = [50,50,50,50,49]; XCTAssertEqual(boundary.after, 3.96)
        let almost = TrainingRules.traitGrowth(before: 99.94, score: 0, fatigue: 100, age: 41)
        XCTAssertEqual(almost, 99.982); XCTAssertLessThan(almost, 100)
        try TraitLoadout(owned: [], active: [], progress: ["cheetah":almost]).validate()
    }
    func testExistingV6PayloadAndNormalPendingTrainingSurviveDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old-v6.store")
        let old = Data("{\"owned\":[\"strong-arm\"],\"active\":[\"strong-arm\"]}".utf8)
        let trainingBytes = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            let (player, state, profile) = try traitSetup(context)
            profile.payload = old; profile.revision = 7; try context.save()
            let record = try CareerTrainingStore.start(player: player, state: state, kind: .contact, in: context)
            for _ in 0..<2 { try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision, input: TrainingInput(timing: 0.82), in: context) }
            return record.payload
        }
        let container = try CareerStore.makeContainer(url: url), context = container.mainContext
        let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let profile = try XCTUnwrap(PlayerTraitStore.profile(playerID: player.id, in: context))
        let record = try XCTUnwrap(CareerTrainingStore.record(player: player, in: context))
        XCTAssertEqual(profile.payload, old); XCTAssertEqual(profile.revision, 7); XCTAssertEqual(record.payload, trainingBytes)
        XCTAssertNil(try record.snapshot().trait); XCTAssertEqual(try record.snapshot().scores.count, 2)
        for _ in 0..<3 { try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision, input: TrainingInput(timing: 0.82), in: context) }
        XCTAssertTrue(record.completed); XCTAssertEqual(profile.payload, old); XCTAssertEqual(profile.revision, 7)
    }
    private func setup(_ context: ModelContext, role: PlayerRole = .batter, legacy: Bool = false) throws -> (CareerPlayer, CareerCalendarState, PlayerTraits) {
        var draft=PlayerDraft();draft.name="특성선수";draft.role=role;draft.schoolID="hs-ref-001"
        let player=try legacy ? LegacyPlayerFixture.create(draft,schools:SchoolCatalog.load(),in:context) : CareerStore.create(draft,schools:SchoolCatalog.load(),in:context)
        if legacy {try PlayerTraitStore.addMissing(in:context)}
        let state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first{$0.playerID==player.id})
        return (player,state,try XCTUnwrap(PlayerTraitStore.profile(playerID:player.id,in:context)))
    }
    private func toggle(_ trait:PlayerTrait, _ player:CareerPlayer, _ state:CareerCalendarState, _ profile:PlayerTraits, _ context:ModelContext,
                        save: CalendarProgression.Save = {try $0.save()}) throws {
        try PlayerTraitStore.toggle(player:player,state:state,profile:profile,trait:trait,date:player.gameDate,revision:profile.revision,calendarRevision:state.revision,in:context,save:save)
    }
    func testInitialGrantUsesOnlyEligibleCandidatesAndOneImmutableSavedTrait() throws {
        for index in 0..<3 {
            let value=try TraitLoadout.initial(speed:60,defense:50,arm:60,choose:{count in XCTAssertEqual(count,3);return index})
            XCTAssertEqual(value.owned,[PlayerTrait.allCases[index]]);XCTAssertEqual(value.active,value.owned)
        }
        XCTAssertEqual(try TraitLoadout.initial(speed:59,defense:49,arm:60).owned,[.strongArm])
        XCTAssertEqual(try TraitLoadout.initial(speed:59,defense:50,arm:59).owned,[.safeHands])
        XCTAssertEqual(try TraitLoadout.initial(speed:0,defense:0,arm:0).owned,[])
        for type in PlayerArchetype.allCases {
            let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            var draft=PlayerDraft();draft.name="초기특성";draft.schoolID="hs-ref-001";draft.role=type.role;draft.archetype=type
            let player=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:context)
            let profile=try XCTUnwrap(PlayerTraitStore.profile(playerID:player.id,in:context)), before=profile.payload
            let value=try profile.snapshot();XCTAssertEqual(value.owned.count,1);XCTAssertEqual(value.active,value.owned)
            XCTAssertTrue(value.owned[0].qualifies(speed:player.speed,defense:player.defense,arm:player.arm))
            try PlayerTraitStore.addMissing(in:context);XCTAssertEqual(profile.payload,before)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerTraits>()),1)
        }
    }
    func testBackfillAndCreationFailuresRollbackWithoutChangingExistingValues() throws {
        enum Failure:Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
        var draft=PlayerDraft();draft.name="이전특성";draft.schoolID="hs-ref-001"
        XCTAssertThrowsError(try CareerStore.create(draft,schools:SchoolCatalog.load(),in:context,save:{_ in throw Failure.injected}))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerTraits>()),0);XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()),0)
        let player=try LegacyPlayerFixture.create(draft,schools:SchoolCatalog.load(),in:context)
        player.speed=72.1234;try context.save()
        let id=player.id,fatigue=player.fatigue,date=player.gameDate
        XCTAssertThrowsError(try PlayerTraitStore.addMissing(in:context,save:{_ in throw Failure.injected}))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerTraits>()),0)
        try PlayerTraitStore.addMissing(in:context)
        let profile=try XCTUnwrap(PlayerTraitStore.profile(playerID:player.id,in:context))
        XCTAssertEqual(try profile.snapshot(),TraitLoadout(owned:PlayerTrait.allCases,active:[]));XCTAssertEqual(profile.source,"legacy-v1")
        XCTAssertEqual(player.id,id);XCTAssertEqual(player.speed,72.1234);XCTAssertEqual(player.fatigue,fatigue);XCTAssertEqual(player.gameDate,date)
        profile.payload=try JSONEncoder().encode(TraitLoadout(owned:PlayerTrait.allCases,active:[.cheetah]));try context.save()
        var writes=0;try PlayerTraitStore.addMissing(in:context,save:{_ in writes += 1})
        XCTAssertEqual(writes,0);XCTAssertEqual(try profile.snapshot().active,[.cheetah])
    }
    func testThreeSlotsTogglePersistenceStaleInputAndSaveFailureAreAtomic() throws {
        enum Failure:Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
        let (player,state,profile)=try setup(context,legacy:true)
        let fatigue=player.fatigue,stats=[player.speed,player.defense,player.arm],calendarRevision=state.revision
        XCTAssertThrowsError(try toggle(.strongArm,player,state,profile,context,save:{_ in throw Failure.injected}))
        XCTAssertEqual(try profile.snapshot().active,[]);XCTAssertEqual(profile.revision,0);XCTAssertEqual(state.revision,calendarRevision)
        for trait in PlayerTrait.allCases {try toggle(trait,player,state,profile,context)}
        XCTAssertEqual(try profile.snapshot().active,PlayerTrait.allCases)
        XCTAssertThrowsError(try PlayerTraitStore.toggle(player:player,state:state,profile:profile,trait:.cheetah,date:"2026-04-02",revision:profile.revision,calendarRevision:state.revision,in:context))
        XCTAssertThrowsError(try PlayerTraitStore.toggle(player:player,state:state,profile:profile,trait:.cheetah,date:player.gameDate,revision:0,calendarRevision:state.revision,in:context))
        XCTAssertThrowsError(try PlayerTraitStore.toggle(player:player,state:state,profile:profile,trait:.cheetah,date:player.gameDate,revision:profile.revision,calendarRevision:0,in:context))
        try toggle(.cheetah,player,state,profile,context);XCTAssertEqual(try profile.snapshot().active,[.strongArm,.safeHands])
        XCTAssertEqual(player.fatigue,fatigue);XCTAssertEqual([player.speed,player.defense,player.arm],stats);XCTAssertNil(state.actionDate)
        XCTAssertThrowsError(try TraitLoadout(owned:[.strongArm],active:[.cheetah]).validate())
        XCTAssertThrowsError(try TraitLoadout(owned:PlayerTrait.allCases,active:[.strongArm,.cheetah,.safeHands,.strongArm]).validate())
        XCTAssertThrowsError(try TraitLoadout(owned:[.strongArm,.strongArm],active:[]).validate())
        profile.payload=Data("invalid".utf8);XCTAssertThrowsError(try profile.snapshot());context.rollback()
        let other=try PlayerTraits(playerID:UUID(),loadout:TraitLoadout(owned:[],active:[]),source:"initial-v1")
        XCTAssertThrowsError(try PlayerTraitStore.toggle(player:player,state:state,profile:other,trait:.cheetah,date:player.gameDate,revision:0,calendarRevision:state.revision,in:context))
    }
    func testPreparationAndPendingTrainingLockLoadoutUntilNextDay() throws {
        for training in [false,true] {
            let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            let (player,state,profile)=try setup(context,legacy:true)
            if training {_=try CareerTrainingStore.start(player:player,state:state,in:context)}
            else {try CalendarProgression.rest(player:player,state:state,revision:state.revision,in:context)}
            XCTAssertThrowsError(try toggle(.cheetah,player,state,profile,context))
            XCTAssertEqual(try profile.snapshot().active,[])
            if !training {
                let record=try CareerMatchStore.start(player:player,state:state,in:context)
                try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.automatic,in:context)
                XCTAssertThrowsError(try toggle(.cheetah,player,state,profile,context))
                try CalendarProgression.advanceDay(player:player,state:state,revision:state.revision,in:context)
                try toggle(.cheetah,player,state,profile,context);XCTAssertEqual(try profile.snapshot().active,[.cheetah])
            }
        }
        let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
        let (player,state,profile)=try setup(context)
        let loadout=try profile.snapshot()
        let unowned=try XCTUnwrap(PlayerTrait.allCases.first{!loadout.owned.contains($0)})
        XCTAssertThrowsError(try toggle(unowned,player,state,profile,context))
    }
    func testStageMultipliersAffectOnlyPersonalActionsAndNotPermanentStats() {
        func play(_ traits:[PlayerTrait],own:Bool)->MatchFieldPlay {
            MatchFieldRules.firstBaseV2(runnerSpeed:60,fielderSpeed:60,defense:60,arm:60,chase:12,distance:30,ownDefense:own,active:traits)
        }
        let runner=play([],own:false),cheetah=play([.cheetah],own:false)
        XCTAssertEqual(runner.runnerTime-cheetah.runnerTime,0.4*0.08,accuracy:0.000001)
        XCTAssertEqual(runner.ballTime,cheetah.ballTime)
        XCTAssertEqual(play([.strongArm,.safeHands],own:false),MatchFieldPlay(runnerTime:runner.runnerTime,ballTime:runner.ballTime,ownDefense:false,appliedTraits:[]))
        let defense=play([],own:true)
        XCTAssertEqual(defense.ballTime-play([.strongArm],own:true).ballTime,30/28.8-30/(28.8*1.05),accuracy:0.000001)
        XCTAssertEqual(defense.ballTime-play([.safeHands],own:true).ballTime,0.2*0.1,accuracy:0.000001)
        XCTAssertEqual(defense.ballTime-play([.cheetah],own:true).ballTime,0.34*0.08,accuracy:0.000001)
        let all=play(PlayerTrait.allCases,own:true)
        XCTAssertEqual(all.runnerTime,defense.runnerTime)
        XCTAssertEqual(defense.ballTime-all.ballTime,(30/28.8-30/(28.8*1.05))+0.02+0.0272,accuracy:0.000001)
        XCTAssertTrue(MatchFieldPlay(runnerTime:1,ballTime:1,ownDefense:false).safe)
    }
    func testActiveTraitsChangeActualFairBallResultsAndDirectAutomaticStayIdentical() throws {
        func game(_ seed:Int,_ active:[PlayerTrait],role:String)->CareerMatch {
            var game=CareerMatch(random:UInt64(seed),isHome:true,role:role,appearance:true,contact:65,power:0,discipline:60,mastery:["four-seam":72])
            game.half=role=="batter" ? 1:0;game.controlVersion=2
            game.fieldStats=MatchFieldStats(version:2,speed:60,defense:60,arm:60,position:role=="pitcher" ? "P":"CF",activeTraits:active)
            return game
        }
        var baseHits=0,fastHits=0,defenseHits=0,strongDefenseHits=0
        for seed in 0..<3000 {
            for active in [[],[PlayerTrait.cheetah]] {
                var state=game(seed,active,role:"batter");let delivery=state.delivery()
                try state.advance(.swing,control:ManualMatchInput(x:delivery.x,y:delivery.y,timing:0.82))
                if active.isEmpty {baseHits+=state.line.hits}else{fastHits+=state.line.hits}
            }
            for active in [[],PlayerTrait.allCases] {
                var state=game(seed,active,role:"pitcher")
                try state.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
                if active.isEmpty {defenseHits+=state.line.hitsAllowed}else{strongDefenseHits+=state.line.hitsAllowed}
            }
        }
        XCTAssertGreaterThan(fastHits,baseHits);XCTAssertLessThan(strongDefenseHits,defenseHits)
        var auto=game(42,PlayerTrait.allCases,role:"pitcher"),direct=auto
        let input=direct.automaticControl(.pitch,pitchCode:"four-seam")
        try auto.advance(.pitch,pitchCode:"four-seam");try direct.advance(.pitch,pitchCode:"four-seam",control:input)
        XCTAssertEqual(auto,direct)
        var old=game(42,[],role:"batter");old.fieldStats?.version=1
        var extra=old;extra.fieldStats?.activeTraits=PlayerTrait.allCases
        let ball=old.delivery(),control=ManualMatchInput(x:ball.x,y:ball.y,timing:0.82)
        try old.advance(.swing,control:control);try extra.advance(.swing,control:control)
        XCTAssertEqual(old.line,extra.line);XCTAssertEqual(old.lastFieldPlay,extra.lastFieldPlay);XCTAssertEqual(old.random,extra.random)
    }
}

extension PlayerTraitsTests {
    func testV5FileMigrationPreservesBothRolesAbilitiesPitchesAndPendingPayloads() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("v5.store")
        let original=try autoreleasepool {
            let schema=Schema(versionedSchema:CareerSchemaV5.self)
            let container=try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
            let context=container.mainContext;context.autosaveEnabled=false
            var saved:[UUID:[Data]]=[:]
            for role in PlayerRole.allCases {
                var draft=PlayerDraft();draft.name="이전검증";draft.role=role;draft.schoolID="hs-ref-001"
                let player=try LegacyPlayerFixture.create(draft,schools:SchoolCatalog.load(),in:context)
                try PlayerAbilityStore.addMissing(in:context)
                let state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first{$0.playerID==player.id})
                player.speed=72.1234;player.arm=68.4321;player.contact=66.8888;player.pitches.first?.mastery=78.1234
                let abilities=try XCTUnwrap(PlayerAbilityStore.profile(playerID:player.id,in:context));abilities.mental=63.4567;abilities.stuff=role == .pitcher ? 65.4321:nil
                let fixture=try XCTUnwrap(state.fixtures(for:player,year:2026).first)
                var game=CareerMatch(random:42,isHome:true,role:player.roleRaw,appearance:true,contact:player.contact,power:player.power,discipline:player.discipline,mastery:Dictionary(uniqueKeysWithValues:player.pitches.map{($0.code,$0.mastery)}))
                game.fieldStats=MatchFieldStats(speed:player.speed,defense:player.defense,arm:player.arm,position:role == .pitcher ? "P":"CF");game.controlVersion=2
                let record=try CareerMatchRecord(player:player,fixture:fixture,match:game);context.insert(record)
                player.gameDate="2026-04-02";try context.save()
                let training=try CareerTrainingStore.start(player:player,state:state,pitchCode:role == .pitcher ? "four-seam":nil,in:context)
                for _ in 0..<2 {try CareerTrainingStore.attempt(player:player,state:state,record:training,revision:training.revision,input:role == .pitcher ? TrainingInput(release:0.68):TrainingInput(timing:0.82),in:context)}
                let scalars=[player.id.uuidString,player.name,player.schoolID,player.gameDate,String(player.fatigue),String(player.contact),String(player.speed),String(player.arm),String(abilities.mental),String(abilities.stuff ?? 0),String(state.revision)] + player.pitches.sorted{$0.order<$1.order}.map{String($0.mastery)}
                saved[player.id]=[try JSONEncoder().encode(scalars),record.payload,training.payload]
            }
            return saved
        }
        let container=try CareerStore.makeContainer(url:url),context=container.mainContext
        for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
            let state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first{$0.playerID==player.id})
            let abilities=try XCTUnwrap(PlayerAbilityStore.profile(playerID:player.id,in:context))
            let profile=try XCTUnwrap(PlayerTraitStore.profile(playerID:player.id,in:context))
            XCTAssertEqual(try profile.snapshot(),TraitLoadout(owned:PlayerTrait.allCases,active:[]))
            let scalars=[player.id.uuidString,player.name,player.schoolID,player.gameDate,String(player.fatigue),String(player.contact),String(player.speed),String(player.arm),String(abilities.mental),String(abilities.stuff ?? 0),String(state.revision)] + player.pitches.sorted{$0.order<$1.order}.map{String($0.mastery)}
            let previous=try XCTUnwrap(original[player.id])
            XCTAssertEqual(try JSONEncoder().encode(scalars),previous[0])
            let game=try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first{$0.playerID==player.id})
            let training=try XCTUnwrap(CareerTrainingStore.record(player:player,in:context))
            XCTAssertEqual(game.payload,previous[1]);XCTAssertEqual(training.payload,previous[2]);XCTAssertEqual(try training.snapshot().scores.count,2)
            XCTAssertEqual(try game.snapshot().fieldStats?.version,1)
            XCTAssertThrowsError(try toggle(.cheetah,player,state,profile,context))
            for _ in 0..<3 {try CareerTrainingStore.attempt(player:player,state:state,record:training,revision:training.revision,input:player.role == .pitcher ? TrainingInput(release:0.68):TrainingInput(timing:0.82),in:context)}
            XCTAssertTrue(training.completed)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerTraits>()),2)
    }
    func testNewMatchFreezesLoadoutAcrossDiskResumeAndFinalResultOnce() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("traits.store")
        let pending=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let (player,state,profile)=try setup(context,role:.pitcher,legacy:true)
            for trait in PlayerTrait.allCases {try toggle(trait,player,state,profile,context)}
            try CalendarProgression.rest(player:player,state:state,revision:state.revision,in:context)
            let record=try CareerMatchStore.start(player:player,state:state,in:context)
            XCTAssertEqual(try record.snapshot().fieldStats?.activeTraits,PlayerTrait.allCases)
            XCTAssertEqual(try record.snapshot().fieldStats?.version,2)
            try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68),in:context)
            return record.payload
        }
        let result=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let profile=try XCTUnwrap(PlayerTraitStore.profile(playerID:player.id,in:context))
            XCTAssertEqual(try profile.snapshot().active,PlayerTrait.allCases)
            let record=try CareerMatchStore.start(player:player,state:state,in:context)
            XCTAssertEqual(record.payload,pending)
            XCTAssertThrowsError(try toggle(.cheetah,player,state,profile,context))
            try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.automatic,in:context)
            let payload=record.payload,fatigue=player.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.automatic,in:context))
            XCTAssertEqual(record.payload,payload);XCTAssertEqual(player.fatigue,fatigue)
            try CalendarProgression.advanceDay(player:player,state:state,revision:state.revision,in:context)
            try toggle(.cheetah,player,state,profile,context)
            XCTAssertEqual(try record.snapshot().fieldStats?.activeTraits,PlayerTrait.allCases)
            return payload
        }
        let container=try CareerStore.makeContainer(url:url),context=container.mainContext
        let record=try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first)
        XCTAssertEqual(record.payload,result)
        let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        XCTAssertEqual(try PlayerTraitStore.profile(playerID:player.id,in:context)?.snapshot().active,[.strongArm,.safeHands])
    }
}
