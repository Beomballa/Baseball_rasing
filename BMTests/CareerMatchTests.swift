import XCTest
import SwiftData
import SwiftUI
@testable import BM

@MainActor final class CareerMatchTests: XCTestCase {
    private func setup(role: PlayerRole = .batter, date: String = "2026-04-01", in context: ModelContext) throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = role == .batter ? "경기타자" : "경기투수"
        draft.schoolID = "hs-ref-001"; draft.role = role; draft.throwingHand = .left
        let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
        player.gameDate = date
        try context.save()
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        return (player, state)
    }
    private func ready(_ player: CareerPlayer, _ state: CareerCalendarState, in context: ModelContext) throws -> CareerMatchRecord {
        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
        return try CareerMatchStore.start(player: player, state: state, in: context)
    }

    func testBothRolesCompleteOnceAndUnlockOnlyCompletedGameDay() throws {
        for role in PlayerRole.allCases {
            let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
            let (player, state) = try setup(role: role, in: context)
            XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context))
            let saved = try ready(player, state, in: context)
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context))
            XCTAssertEqual(try CareerMatchStore.start(player: player, state: state, in: context).key, saved.key)
            let initial = player.fatigue
            try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context)
            let final = try saved.snapshot()
            XCTAssertTrue(saved.completed); XCTAssertTrue(final.completed)
            XCTAssertEqual(player.fatigue, min(100, initial + final.appliedFatigueCost))
            XCTAssertEqual(saved.fatigueAfter, player.fatigue)
            if role == .batter { XCTAssertGreaterThan(final.line.atBats, 0); XCTAssertEqual(final.line.pitches, 0) }
            else { XCTAssertGreaterThan(final.line.pitches, 0); XCTAssertGreaterThan(final.line.pitchingOuts, 0); XCTAssertEqual(final.line.atBats, 0) }
            let before = (player.fatigue, state.revision, saved.payload)
            for revision in [0, saved.revision] {
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: revision, input: .automatic, in: context))
            }
            XCTAssertEqual(player.fatigue, before.0); XCTAssertEqual(state.revision, before.1); XCTAssertEqual(saved.payload, before.2)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()), 1)
            try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
            XCTAssertEqual(player.gameDate, "2026-04-02"); XCTAssertEqual(player.fatigue, max(0, before.0 - 4))
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: before.1, in: context))
        }
    }

    func testNonStartTeamGameHasNoPersonalCostOrStats() throws {
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, state) = try setup(role: .pitcher, date: "2026-04-07", in: context)
        let saved = try ready(player, state, in: context); let fatigue = player.fatigue
        XCTAssertFalse(saved.appearance)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .pitch, pitchCode: "four-seam", in: context))
        try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context)
        XCTAssertEqual(try saved.snapshot().line, MatchLine()); XCTAssertEqual(player.fatigue, fatigue)
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
        XCTAssertEqual(player.gameDate, "2026-04-08")
    }

    func testInvalidRolePitchRevisionAndFixtureDoNotChangeState() throws {
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, state) = try setup(role: .pitcher, in: context)
        let saved = try ready(player, state, in: context); let payload = saved.payload
        for (input, code, revision) in [(MatchInput.pitch, "unknown", 0), (.swing, "four-seam", 0), (.pitch, "four-seam", 10)] {
            XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: revision, input: input, pitchCode: code, in: context))
        }
        let (other, otherState) = try setup(in: context)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: other, state: otherState, record: saved, revision: 0, input: .automatic, in: context))
        XCTAssertEqual(saved.payload, payload); XCTAssertEqual(saved.revision, 0)
        player.gameDate = "2026-04-02"; try context.save()
        XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context))
    }

    func testFailedStartAndCompletionRollbackThenRetryOnce() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, state) = try setup(in: context)
        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
        let revision = state.revision
        XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()), 0); XCTAssertEqual(state.revision, revision)
        let saved = try CareerMatchStore.start(player: player, state: state, in: context)
        let before = try saved.snapshot(); let fatigue = player.fatigue; let startRevision = state.revision
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try saved.snapshot(), before); XCTAssertEqual(saved.revision, 0); XCTAssertFalse(saved.completed)
        XCTAssertEqual(player.fatigue, fatigue); XCTAssertEqual(state.revision, startRevision)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context))
        var expected = before; try expected.advance(.automatic)
        try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .automatic, in: context)
        XCTAssertEqual(try saved.snapshot(), expected); XCTAssertTrue(saved.completed)
    }

    func testPartialGameDiskReopenResumesSameRNGAndKeepsOtherRole() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("match.store")
        let expected: CareerMatch = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url); let context = container.mainContext
            let (player, state) = try setup(in: context)
            _ = try setup(role: .pitcher, in: context)
            let saved = try ready(player, state, in: context)
            try CareerMatchStore.advance(player: player, state: state, record: saved, revision: 0, input: .watch, in: context)
            let snapshot = try saved.snapshot(); XCTAssertFalse(snapshot.completed)
            return snapshot
        }
        let reopened = try CareerStore.makeContainer(url: url); let context = reopened.mainContext
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        let batter = try XCTUnwrap(players.first { $0.role == .batter })
        let pitcher = try XCTUnwrap(players.first { $0.role == .pitcher })
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == batter.id })
        let saved = try CareerMatchStore.start(player: batter, state: state, in: context)
        XCTAssertEqual(try saved.snapshot(), expected)
        var next = expected; try next.advance(.automatic)
        try CareerMatchStore.advance(player: batter, state: state, record: saved, revision: saved.revision, input: .automatic, in: context)
        XCTAssertEqual(try saved.snapshot(), next)
        XCTAssertEqual(pitcher.fatigue, 52); XCTAssertEqual(pitcher.gameDate, "2026-04-01")
        XCTAssertEqual(pitcher.pitches.sorted { $0.order < $1.order }.map(\.mastery), [72,65,48,35])
        let second = ModelContext(reopened)
        XCTAssertTrue(try XCTUnwrap(second.fetch(FetchDescriptor<CareerMatchRecord>()).first).completed)
    }

    func testPitchCostRoundingUsesFourDigitPrecisionBeforeIntegerStorage() {
        var match = CareerMatch(random: 1, isHome: true, role: "pitcher", appearance: true,
                                contact: 65, power: 75, discipline: 60, mastery: ["four-seam": 72])
        match.fatigueCost = 19.00000000000001
        XCTAssertEqual(match.appliedFatigueCost, 19)
        match.fatigueCost = 19.38
        XCTAssertEqual(match.appliedFatigueCost, 20)
    }

    func testDirectAndAutomaticUseIdenticalEngineAndValidBaseballTotals() throws {
        for seed in 0..<100 {
            for home in [true, false] {
                for role in PlayerRole.allCases {
                    var direct = CareerMatch(random: UInt64(seed), isHome: home, role: role.rawValue,
                                             appearance: true, contact: 65, power: 75, discipline: 60,
                                             mastery: role == .pitcher ? ["four-seam": 72] : [:])
                    direct.settle()
                    var automatic = direct
                    try automatic.advance(.automatic)
                    var inputs = 0
                    while !direct.completed && inputs < 1000 {
                        try direct.advance(role == .batter ? .swing : .pitch, pitchCode: "four-seam")
                        inputs += 1
                    }
                    XCTAssertTrue(direct.completed); XCTAssertEqual(direct, automatic)
                    XCTAssertTrue((17...18).contains(direct.half))
                    if direct.half == 17 { XCTAssertGreaterThan(direct.homeScore, direct.awayScore) }
                    XCTAssertEqual(direct.line.plateAppearances, direct.line.atBats + direct.line.walks)
                    XCTAssertLessThanOrEqual(direct.line.homeRuns, direct.line.hits)
                    XCTAssertLessThanOrEqual(direct.line.hits, direct.line.atBats)
                    if role == .pitcher {
                        XCTAssertTrue([24, 25, 26, 27].contains(direct.line.pitchingOuts))
                        XCTAssertEqual(direct.line.runsAllowed, direct.opponentScore)
                    }
                    XCTAssertThrowsError(try direct.advance(.automatic))
                }
            }
        }
    }

    func testV2DiskMigrationPreservesCalendarActionsAndCreatesNoFakeGames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v2.store")
        let schools = try SchoolCatalog.load()
        let ids: [UUID] = try autoreleasepool {
            let schema = Schema(versionedSchema: CareerSchemaV2.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            var ids: [UUID] = []
            for role in PlayerRole.allCases {
                var draft = PlayerDraft(); draft.name = "기존선수"; draft.schoolID = schools[0].id; draft.role = role
                let player = CareerPlayer(draft: draft, school: schools[0]); player.gameDate = "2027-04-01"; player.speed = 72.125; player.fatigue = 37
                let state = CareerCalendarState(player: player, schools: schools, legacySave: true)
                state.actionDate = player.gameDate; state.revision = 8
                old.mainContext.insert(player); old.mainContext.insert(state); ids.append(player.id)
            }
            try old.mainContext.save(); return ids
        }
        let current = try CareerStore.makeContainer(url: url); let context = current.mainContext
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<CareerPlayer>()).map(\.id)), Set(ids))
        for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
            XCTAssertEqual(player.gameDate, "2027-04-01"); XCTAssertEqual(player.speed, 72.125); XCTAssertEqual(player.fatigue, 37)
        }
        for state in try context.fetch(FetchDescriptor<CareerCalendarState>()) {
            XCTAssertEqual(state.revision, 8); XCTAssertEqual(state.actionDate, "2027-04-01"); XCTAssertTrue(state.legacySave)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()), 0)
    }
    private func reliefMatch(seed:UInt64=1) -> CareerMatch {
        var m=CareerMatch(random:seed,isHome:true,role:"pitcher",appearance:true,contact:60,power:60,discipline:60,mastery:["four-seam":60])
        m.controlVersion=2;m.detailedFieldVersion=5;m.fieldPlays=[];m.runnerProfiles=[nil,nil,nil];m.pitching=MatchPitching()
        m.abilityStats=MatchAbilityStats(mental:60,velocity:60,control:60,stuff:60,stamina:60,fatigue:0)
        return m
    }
    func testPitcherLimitUsesStaminaAndWaitsForPlateEnd() throws {
        XCTAssertEqual(MatchPitching.limit(stamina:0),70);XCTAssertEqual(MatchPitching.limit(stamina:60),94);XCTAssertEqual(MatchPitching.limit(stamina:100),110)
        var found=false
        for seed in 1...100 {
            var m=reliefMatch(seed:UInt64(seed));m.line.pitches=93;m.pitching?.homePitches=93
            try m.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
            guard m.homeOrder+m.awayOrder == 0 else {continue}
            found=true;XCTAssertEqual(m.line.pitches,94);XCTAssertNil(m.ownPitcherChange)
            for _ in 0..<20 where m.ownPitcherChange == nil {try m.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))}
            let c=try XCTUnwrap(m.ownPitcherChange);XCTAssertGreaterThanOrEqual(c.pitches,94);XCTAssertEqual(c.reason,"투구 수 한도")
            XCTAssertFalse(m.completed);XCTAssertEqual(m.balls,0);XCTAssertEqual(m.strikes,0)
            XCTAssertThrowsError(try m.advance(.pitch,pitchCode:"four-seam"));try m.validatePitching();break
        }
        XCTAssertTrue(found)
    }
    func testFatigueChangeFreezesPersonalOutsPitchesAndCostThroughRelief() throws {
        var m=reliefMatch();m.pitching?.startingFatigue=100;m.abilityStats=MatchAbilityStats(mental:60,velocity:60,control:60,stuff:60,stamina:60,fatigue:100)
        for _ in 0..<20 where m.ownPitcherChange == nil {try m.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))}
        XCTAssertEqual(m.ownPitcherChange?.reason,"피로 한도");XCTAssertFalse(m.completed)
        let before=m.line,cost=m.fatigueCost
        let data=try JSONEncoder().encode(m);var resumed=try JSONDecoder().decode(CareerMatch.self,from:data)
        try m.advance(.automatic);try resumed.advance(.automatic)
        XCTAssertEqual(m,resumed);XCTAssertTrue(m.completed);try m.validatePitching();try m.validateDetailedField()
        XCTAssertEqual(m.line.pitches,before.pitches);XCTAssertEqual(m.line.pitchingOuts,before.pitchingOuts);XCTAssertEqual(m.line.hitsAllowed,before.hitsAllowed)
        XCTAssertEqual(m.line.pitchingWalks,before.pitchingWalks);XCTAssertEqual(m.fatigueCost,cost)
    }
    func testInheritedScoringAndForceChoicePreserveOriginalPitcher() throws {
        var scored=false
        for seed in 1...20 {
            var m=reliefMatch(seed:UInt64(seed));m.line.pitches=94;m.pitching?.homePitches=94
            m.bases=[true,true,true];m.runnerProfiles=(0..<3).map {_ in FieldRunnerProfile(speed:60,responsiblePitcher:"home-starter")}
            m.finishPitcherPlate(home:true,previousHalf:0)
            XCTAssertEqual(m.ownPitcherChange?.inheritedBases,[1,2,3]);try m.advance(.automatic);try m.validatePitching()
            XCTAssertEqual(m.line.pitchingOuts,0);XCTAssertEqual(m.line.pitches,94);XCTAssertTrue((0...3).contains(m.line.runsAllowed))
            XCTAssertEqual(m.line.runsAllowed,m.pitching?.runs["home-starter",default:0]);XCTAssertEqual(m.opponentScore,(m.pitching?.runs["home-starter",default:0] ?? 0)+(m.pitching?.runs["home-relief",default:0] ?? 0))
            scored = scored || m.line.runsAllowed > 0
        }
        XCTAssertTrue(scored)
        var found=false
        for depth in [3.0,8,15,25,35] {
            var p=DetailedFieldRules.resolve(half:0,order:0,landing:FieldPoint(x:0,y:depth),flight:0.4,runners:[FieldRunnerProfile(speed:10,responsiblePitcher:"home-starter"),nil,nil],batter:FieldRunnerProfile(speed:100,responsiblePitcher:"home-relief"),outs:0,stats:nil,defending:false,ownBatter:false)
            guard p.runners.contains(where:{$0.from == 1 && $0.out}),p.runners.contains(where:{$0.from == 0 && !$0.out}) else {continue}
            MatchPitching.transferChoiceResponsibility(&p);XCTAssertEqual(p.runners.first(where:{$0.from == 0})?.profile.responsiblePitcher,"home-starter");try p.validate();found=true
        }
        XCTAssertTrue(found)
    }
    func testNewPitchingBothRolesAndAllSeedsValidateWithoutChangingLegacy() throws {
        for role in ["batter","pitcher"] {for seed in 1...24 {
            var m=reliefMatch(seed:UInt64(seed))
            if role == "batter" {m=CareerMatch(random:UInt64(seed),isHome:false,role:role,appearance:true,contact:60,power:60,discipline:60,mastery:[:]);m.controlVersion=2;m.pitching=MatchPitching();m.detailedFieldVersion=5;m.fieldPlays=[];m.runnerProfiles=[nil,nil,nil]}
            try m.advance(.automatic);try m.validatePitching();try m.validateDetailedField()
            XCTAssertEqual(m.pitching?.runs.values.reduce(0,+),m.homeScore+m.awayScore)
            XCTAssertEqual(m,try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(m)))
        }}
        var legacy=reliefMatch();legacy.pitching=nil
        try legacy.advance(.automatic);XCTAssertEqual(legacy.line.runsAllowed,legacy.opponentScore);XCTAssertTrue([24,25,26,27].contains(legacy.line.pitchingOuts))
    }
    func testMalformedPitchingLedgerIsRejectedWithoutReset() throws {
        var m=reliefMatch();try m.validatePitching()
        m.pitching?.runs["other"]=1;XCTAssertThrowsError(try m.validatePitching())
        m=reliefMatch();m.runnerProfiles=[FieldRunnerProfile(speed:60,responsiblePitcher:"unknown"),nil,nil];XCTAssertThrowsError(try m.validatePitching())
        m=reliefMatch();m.pitching?.version=2;XCTAssertThrowsError(try m.validatePitching())
        m=reliefMatch();m.awayScore=1;m.pitching?.runs["away-starter"]=1;XCTAssertThrowsError(try m.validatePitching())
    }

    func testPitcherChangeDiskResumeRollbackAndFinalRewardOnce() throws {
        enum Failure:Error {case injected}
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("pitching.store")
        let partial=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s)=try setup(role:.pitcher,in:c),r=try ready(p,s,in:c)
            var m=try r.snapshot();m.line.pitches=93;m.pitching?.homePitches=m.isHome ? 93:0;m.pitching?.awayPitches=m.isHome ? 0:93
            r.payload=try JSONEncoder().encode(m);try c.save()
            let fatigue=p.fatigue
            for _ in 0..<30 where try r.snapshot().ownPitcherChange == nil {
                try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68),in:c)
            }
            XCTAssertNotNil(try r.snapshot().ownPitcherChange);XCTAssertFalse(r.completed);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c))
            return (r.payload,p.fatigue)
        }
        let final=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first),r=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first)
            XCTAssertEqual(r.payload,partial.0);XCTAssertNotNil(try r.snapshot().ownPitcherChange)
            let revision=s.revision
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c,save:{_ in throw Failure.injected}))
            XCTAssertEqual(r.payload,partial.0);XCTAssertEqual(p.fatigue,partial.1);XCTAssertEqual(s.revision,revision)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            XCTAssertTrue(r.completed);let value=try r.snapshot()
            XCTAssertEqual(p.fatigue,min(100,partial.1+value.appliedFatigueCost))
            return (r.payload,p.fatigue)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first),r=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertEqual(r.payload,final.0);XCTAssertEqual(p.fatigue,final.1)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(r.payload,final.0);XCTAssertEqual(p.fatigue,final.1)
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
        }
    }

    func testPitcherChangeBoardsRenderFromSavedJSONReadOnly() throws {
        var m=reliefMatch();m.line.pitches=94;m.pitching?.homePitches=94
        m.bases=[true,false,true];m.runnerProfiles=[FieldRunnerProfile(speed:60,responsiblePitcher:"home-starter"),nil,FieldRunnerProfile(speed:60,responsiblePitcher:"home-starter")]
        m.finishPitcherPlate(home:true,previousHalf:0)
        let data=try JSONEncoder().encode(m),saved=try JSONDecoder().decode(CareerMatch.self,from:data),change=try XCTUnwrap(saved.ownPitcherChange)
        for final in [false,true] {
            let renderer=ImageRenderer(content:PitcherChangePanel(change:change,finalRuns:final ? 2:nil,appearance:PlayerAppearance()).foregroundStyle(GameTheme.boardInk).frame(width:350).padding(8).background(GameTheme.boardPanel));renderer.scale=2
            let a=XCTAttachment(image:try XCTUnwrap(renderer.uiImage));a.name=final ? "Pitcher responsibility saved result":"Pitcher change saved pending";a.lifetime = .keepAlways;add(a)
        }
        XCTAssertEqual(saved,m);XCTAssertEqual(saved,try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(m)))
    }

    func testV60DiskPayloadWithoutPitchingKeepsOriginalAndOldCompleteGame() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("v60.store")
        let original=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s)=try setup(role:.pitcher,in:c),r=try ready(p,s,in:c)
            func oldJSON(_ object:Any) -> Any {
                if let d=object as? [String:Any] {return d.filter {$0.key != "pitching" && $0.key != "responsiblePitcher"}.mapValues {oldJSON($0)}}
                if let a=object as? [Any] {return a.map {oldJSON($0)}}
                return object
            }
            r.payload=try JSONSerialization.data(withJSONObject:oldJSON(JSONSerialization.jsonObject(with:r.payload)),options:[.sortedKeys]);try c.save();return r.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first),r=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertEqual(r.payload,original);var expected=try r.snapshot();XCTAssertNil(expected.pitching);try expected.advance(.automatic)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let final=try r.snapshot();XCTAssertEqual(final,expected);XCTAssertNil(final.pitching);XCTAssertEqual(final.line.runsAllowed,final.opponentScore)
            XCTAssertTrue([24,25,26,27].contains(final.line.pitchingOuts))
            let data=r.payload;XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,data)
        }
    }

}

@MainActor extension CareerMatchTests {
    private func growthSetup(role: PlayerRole = .batter, in context: ModelContext) throws -> (CareerPlayer, CareerCalendarState) {
        var draft = PlayerDraft(); draft.name = "Growth"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        return (player, state)
    }
    private func growthSample(role: String = "batter", annual: Double = 0, age: Int = 16, fatigue: Int = 20) -> CareerMatch {
        var match = CareerMatch(random: 1, isHome: true, role: role, appearance: true, contact: 60, power: 60, discipline: 60, mastery: [:])
        match.abilityStats = MatchAbilityStats(mental: 60, velocity: role == "pitcher" ? 60 : nil,
            control: role == "pitcher" ? 60 : nil, stuff: role == "pitcher" ? 60 : nil, stamina: role == "pitcher" ? 60 : nil, fatigue: fatigue)
        match.abilityExperience = MatchAbilityExperience(year: 2026, age: age, fatigue: fatigue,
            before: Dictionary(uniqueKeysWithValues: MatchAbilityExperience.kinds(role: role).map { ($0.rawValue, 60.0) }), annualBefore: annual)
        match.completed = true
        return match
    }
    private func growthResult(_ match: CareerMatch) throws -> MatchAbilityGrowth {
        try XCTUnwrap(match.abilityExperience).reward(for: match)
    }
    func testMatchGrowthIndependentBatterAndPitcherAllocation() throws {
        var batter = growthSample()
        batter.line.plateAppearances = 4; batter.line.atBats = 3; batter.line.hits = 2
        batter.line.homeRuns = 1; batter.line.walks = 1; batter.line.strikeouts = 1
        let b = try growthResult(batter)
        XCTAssertEqual(b.rawXP, 2.6); XCTAssertEqual(b.quality, 1); XCTAssertEqual(b.participation, 1)
        XCTAssertEqual(b.awards.map(\.rawXP), [0.4588, 0.6118, 0.9176, 0.6118])
        XCTAssertEqual(b.awards.map(\.after), [60.0089, 60.0119, 60.0179, 60.0119])
        var pitcher = growthSample(role: "pitcher")
        pitcher.line.pitchingOuts = 18; pitcher.line.pitchingStrikeouts = 18; pitcher.line.pitches = 72
        let p = try growthResult(pitcher)
        XCTAssertEqual(p.rawXP, 13); XCTAssertEqual(p.quality, 1); XCTAssertEqual(p.participation, 1)
        XCTAssertEqual(p.awards.map(\.rawXP), [3.7143, 5.5714, 1.8571, 1.8572])
        XCTAssertEqual(p.awards.map(\.kind), [.control,.stuff,.stamina,.mental])
        XCTAssertEqual(p.awards.map(\.after), [60.0724,60.1086,60.0362,60.0362])
    }
    func testMatchGrowthParticipationBadGameAgeFatigueAndCaps() throws {
        var b = growthSample(); b.line.plateAppearances = 4; b.line.atBats = 4; b.line.strikeouts = 4
        XCTAssertEqual(try growthResult(b).rawXP, 2)
        XCTAssertEqual(try growthResult(b).awards.first { $0.kind == .power }?.rawXP, 0)
        b.line.plateAppearances = 1; b.line.atBats = 1; b.line.strikeouts = 1
        XCTAssertEqual(try growthResult(b).rawXP, 0.5)
        var p = growthSample(role: "pitcher"); p.line.pitches = 1; p.line.hitsAllowed = 1
        XCTAssertEqual(try growthResult(p).participation, 0.2); XCTAssertEqual(try growthResult(p).rawXP, 2)
        p.line.pitches = 0; XCTAssertEqual(try growthResult(p).rawXP, 0)
        var capped = growthSample(annual: 79.9); capped.line = b.line
        XCTAssertEqual(try growthResult(capped).rawXP, 0.1)
        capped.abilityExperience = MatchAbilityExperience(year: 2026, age: 16, fatigue: 20, before: ["contact":100,"power":100,"discipline":100,"mental":100], annualBefore: 0)
        XCTAssertEqual(try growthResult(capped).rawXP, 0)
        var adult = growthSample(age: 28), tired = growthSample(fatigue: 80)
        adult.line = b.line; tired.line = b.line
        XCTAssertGreaterThan(try growthResult(b).awards[0].gain, try growthResult(adult).awards[0].gain)
        XCTAssertGreaterThan(try growthResult(b).awards[0].gain, try growthResult(tired).awards[0].gain)
        var maxed = growthSample(); maxed.line = b.line
        maxed.abilityExperience = MatchAbilityExperience(year:2026,age:16,fatigue:20,before:["contact":100,"power":60,"discipline":60,"mental":60],annualBefore:0)
        let award = try growthResult(maxed)
        XCTAssertEqual(award.awards[0].rawXP, 0); XCTAssertEqual(TrainingRules.round(award.awards.reduce(0) {$0 + $1.rawXP}), award.rawXP)
    }
    func testMatchGrowthAnnualRoleParityAndAllocationBudget() throws {
        var batter = growthSample(), pitcher = growthSample(role: "pitcher")
        batter.line.plateAppearances = 4; batter.line.atBats = 4; batter.line.hits = 4
        pitcher.line.pitches = 72; pitcher.line.pitchingOuts = 18; pitcher.line.pitchingStrikeouts = 18
        XCTAssertEqual(try growthResult(batter).rawXP * 30, 78)
        XCTAssertEqual(try growthResult(pitcher).rawXP * 6, 78)
        for raw in [0.0, 77.4, 79.9999, 80] {
            var match = growthSample(annual: raw); match.line = batter.line
            let r = try growthResult(match)
            XCTAssertLessThanOrEqual(TrainingRules.round(raw + r.rawXP), 80)
            XCTAssertEqual(TrainingRules.round(r.awards.reduce(0) {$0 + $1.rawXP}), r.rawXP)
        }
    }
    func testMatchGrowthBothRolesAtomicFailureResumeAndNextSnapshot() throws {
        enum Failure: Error { case injected }
        for role in PlayerRole.allCases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("growth.store")
            let partial = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), c = container.mainContext
                let (p,s) = try growthSetup(role: role, in: c), r = try ready(p,s,in:c)
                try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:role == .batter ? .watch : .pitch,pitchCode:role == .pitcher ? "four-seam" : nil,in:c)
                XCTAssertNil(try r.snapshot().abilityExperience?.result)
                return r.payload
            }
            let completed = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), c = container.mainContext
                let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first)
                let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let r = try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first)
                XCTAssertEqual(r.payload, partial)
                let before = try r.snapshot(), revision = r.revision, fatigue = p.fatigue, calendarRevision = s.revision
                let values = try MatchAbilityExperience.kinds(role: p.roleRaw).map { try CareerTrainingStore.value(player:p,code:nil,kind:$0,in:c) }
                let pitches = Dictionary(uniqueKeysWithValues:p.pitches.map { ($0.code,$0.mastery) }), positions = try PlayerPositionStore.profile(playerID:p.id,in:c)?.payload
                XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:revision,input:.automatic,in:c,save:{ _ in throw Failure.injected }))
                XCTAssertEqual(r.payload,partial); XCTAssertEqual(r.revision,revision); XCTAssertEqual(p.fatigue,fatigue); XCTAssertEqual(s.revision,calendarRevision)
                XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2026,in:c),0)
                XCTAssertEqual(try MatchAbilityExperience.kinds(role:p.roleRaw).map { try CareerTrainingStore.value(player:p,code:nil,kind:$0,in:c) },values)
                XCTAssertEqual(try PlayerPositionStore.profile(playerID:p.id,in:c)?.payload,positions)
                var expected = before; try expected.advance(.automatic)
                try CareerMatchStore.advance(player:p,state:s,record:r,revision:revision,input:.automatic,in:c)
                XCTAssertEqual(try r.snapshot(),expected)
                let growth = try XCTUnwrap(expected.abilityExperience?.result)
                for award in growth.awards { XCTAssertEqual(try CareerTrainingStore.value(player:p,code:nil,kind:award.kind,in:c),award.after) }
                XCTAssertEqual(Dictionary(uniqueKeysWithValues:p.pitches.map { ($0.code,$0.mastery) }),pitches)
                XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2026,in:c),growth.rawXP)
                return r.payload
            }
            try autoreleasepool {
                let container = try CareerStore.makeContainer(url:url),c = container.mainContext
                let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first), s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let r = try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first)
                XCTAssertEqual(r.payload,completed)
                let original = try r.snapshot(), fatigue = p.fatigue
                XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,completed)
                XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
                XCTAssertEqual(p.fatigue,fatigue); XCTAssertEqual(r.payload,completed)
                try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
                let next = try XCTUnwrap(s.fixtures(for:p,year:2026).first { $0.date.description > p.gameDate && $0.isAppearance(for:role) })
                p.gameDate = next.date.description; try c.save()
                try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
                let future = try CareerMatchStore.start(player:p,state:s,in:c).snapshot()
                XCTAssertEqual(future.abilityExperience?.before,Dictionary(uniqueKeysWithValues:try XCTUnwrap(original.abilityExperience?.result).awards.map { ($0.kind.rawValue,$0.after) }))
                XCTAssertEqual(future.abilityExperience?.annualBefore,original.abilityExperience?.result?.rawXP)
                XCTAssertEqual(future.mastery,original.mastery)
            }
        }
    }
    func testMatchGrowthOldPendingAndCompletedPayloadsAreNotRetrofitted() throws {
        let container = try CareerStore.makeContainer(inMemory:true),c = container.mainContext
        let (p,s) = try growthSetup(in:c), r = try ready(p,s,in:c)
        var legacy = try r.snapshot(); legacy.abilityExperience = nil
        r.payload = try JSONEncoder().encode(legacy); try c.save()
        let values = [p.contact,p.power,p.discipline], first = r.payload
        XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,first)
        try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
        let completed = r.payload
        XCTAssertNil(try r.snapshot().abilityExperience); XCTAssertEqual([p.contact,p.power,p.discipline],values)
        XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2026,in:c),0)
        XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,completed)
    }
    func testMatchGrowthStaleValuesCorruptRewardAndHistoryAreRejected() throws {
        let container = try CareerStore.makeContainer(inMemory:true),c = container.mainContext
        let (p,s) = try growthSetup(in:c),r = try ready(p,s,in:c)
        let first = r.payload, original = p.contact
        p.contact += 1; try c.save()
        XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
        XCTAssertEqual(r.payload,first); XCTAssertFalse(r.completed)
        p.contact = original; try c.save()
        try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
        var corrupted = try r.snapshot(); corrupted.abilityExperience?.version = 99
        r.payload = try JSONEncoder().encode(corrupted); XCTAssertThrowsError(try r.snapshot()); c.rollback()
        XCTAssertThrowsError(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2026,records:[r,r]))
        XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:UUID(),year:2026,records:[r]),0)
        XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2027,records:[r]),0)
    }
    func testMatchGrowthFullYearAppearanceIsolationAndNewYearBudget() throws {
        for role in PlayerRole.allCases {
            let container = try CareerStore.makeContainer(inMemory:true),c = container.mainContext
            let (p,s) = try growthSetup(role:role,in:c)
            let fixtures = try s.fixtures(for:p,year:2026)
            var appearances = 0, total = 0.0
            for fixture in fixtures {
                p.gameDate = fixture.date.description; try c.save()
                try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
                let r = try CareerMatchStore.start(player:p,state:s,in:c)
                XCTAssertEqual(try r.snapshot().abilityExperience?.annualBefore ?? total,total)
                try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
                if fixture.isAppearance(for:role) {
                    appearances += 1
                    total = TrainingRules.round(total + (try XCTUnwrap(r.snapshot().abilityExperience?.result)).rawXP)
                } else { XCTAssertNil(try r.snapshot().abilityExperience); XCTAssertEqual(try r.snapshot().line,MatchLine()) }
                XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2026,in:c),total)
            }
            XCTAssertEqual(appearances,role == .batter ? 30 : 6); XCTAssertLessThanOrEqual(total,78)
            p.gameDate = "2027-04-01"; try c.save()
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).snapshot().abilityExperience?.annualBefore,0)
            XCTAssertEqual(try CareerMatchStore.annualAbilityXP(playerID:p.id,year:2026,in:c),total)
        }
    }
    func testMatchGrowthLeavesRNGOutcomesAndExistingPitchMasteriesUnchanged() throws {
        for role in ["batter","pitcher"] {
            for seed in 1...40 {
                var match = growthSample(role:role); match.completed = false; match.random = UInt64(seed)
                var legacy = match; legacy.abilityExperience = nil
                try match.advance(.automatic); try legacy.advance(.automatic)
                XCTAssertEqual(match.random,legacy.random); XCTAssertEqual(match.line,legacy.line)
                XCTAssertEqual(match.homeScore,legacy.homeScore); XCTAssertEqual(match.awayScore,legacy.awayScore)
                XCTAssertEqual(match.fatigueCost,legacy.fatigueCost); XCTAssertEqual(match.mastery,legacy.mastery)
                try match.abilityExperience?.validate(match:match)
            }
        }
    }
}
