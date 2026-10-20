import XCTest
import SwiftData
@testable import BM

@MainActor final class PlayerAbilitiesTests: XCTestCase {
    private func draft(_ type: PlayerArchetype) -> PlayerDraft {
        var draft = PlayerDraft(); draft.name = "유형선수"; draft.schoolID = "hs-ref-001"
        draft.role = type.role; draft.archetype = type
        return draft
    }
    private func profile(_ player: CareerPlayer, _ context: ModelContext) throws -> PlayerAbilities {
        try XCTUnwrap(context.fetch(FetchDescriptor<PlayerAbilities>()).first { $0.playerID == player.id })
    }
    private func finish(_ player: CareerPlayer, _ state: CareerCalendarState, _ context: ModelContext) throws {
        let record = try CareerTrainingStore.start(player: player, state: state,
                                                   pitchCode: player.role == .pitcher ? "four-seam" : nil, in: context)
        while !record.completed {
            let training = try record.snapshot(), target = training.targets[training.scores.count]
            try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision,
                                            input: player.role == .pitcher ? TrainingInput(release: 0.68) : TrainingInput(x: target.x, y: target.y, timing: 0.82), in: context)
        }
    }
    private func preserved(_ player: CareerPlayer) -> [String] {
        [player.id.uuidString, player.roleRaw, player.name, String(player.jerseyNumber), player.schoolID, player.schoolName,
         player.positionRaw, player.throwingHandRaw, String(player.skin), String(player.hair), String(player.kit),
         String(player.hairStyle), String(player.expression), String(player.startAge), player.gameDate, String(player.fatigue),
         String(player.contact), String(player.power), String(player.discipline), String(player.speed), String(player.defense),
         String(player.arm), String(player.createdAt.timeIntervalSinceReferenceDate)] + player.pitches.sorted { $0.order < $1.order }.flatMap {
            [$0.code, $0.name, String($0.mastery), String($0.order)]
        }
    }
    func testSixPresetsMatchFrozenBudgetsAndRoleDefaults() throws {
        let batterExpected: [[Double]] = [[62,46,54,62,55,54,55],[50,65,50,50,56,62,55],[56,46,65,60,53,53,55]]
        for (type, expected) in zip(PlayerArchetype.choices(for: .batter), batterExpected) {
            let v = type.values, actual = [v.contact,v.power,v.discipline,v.speed,v.defense,v.arm,v.mental]
            XCTAssertEqual(actual, expected); XCTAssertEqual(actual.reduce(0,+),388)
        }
        let pitcherExpected: [[Double]] = [[62,48,62,52],[50,64,54,56],[52,54,53,65]]
        for (type, expected) in zip(PlayerArchetype.choices(for: .pitcher), pitcherExpected) {
            let v = type.values, actual = try [v.velocity,v.control,v.stuff,v.stamina].map { try XCTUnwrap($0) }
            XCTAssertEqual(actual,expected); XCTAssertEqual(actual.reduce(0,+),224)
            XCTAssertEqual([v.mental,v.speed,v.defense,v.arm],[55,55,60,65])
            XCTAssertEqual(v.pitches,["four-seam":62,"slider":55,"changeup":42,"fork":35])
        }
        var value = PlayerDraft(); XCTAssertEqual(value.selectedArchetype,.contact)
        value.role = .pitcher; XCTAssertEqual(value.selectedArchetype,.control)
        value.name = "검증"; value.schoolID = "hs-ref-001"; value.archetype = .slugger
        XCTAssertThrowsError(try value.validate(schools: SchoolCatalog.load()))
    }
    func testEveryNewTypeSavesExactInitialValuesWithoutReroll() throws {
        for type in PlayerArchetype.allCases {
            let container = try CareerStore.makeContainer(inMemory:true), context = container.mainContext
            let player = try CareerStore.create(draft(type),schools:SchoolCatalog.load(),in:context)
            let saved = try profile(player,context), v = type.values
            XCTAssertEqual(saved.archetypeRaw,type.rawValue); XCTAssertEqual(saved.productionPresetVersion,"production-v1")
            XCTAssertEqual(try JSONDecoder().decode(PlayerInitialValues.self,from:XCTUnwrap(saved.initialValues)),v)
            XCTAssertEqual([player.contact,player.power,player.discipline,player.speed,player.defense,player.arm], [v.contact,v.power,v.discipline,v.speed,v.defense,v.arm])
            XCTAssertEqual(saved.mental,55); XCTAssertEqual(saved.velocity,v.velocity); XCTAssertEqual(saved.control,v.control)
            XCTAssertEqual(saved.stuff,v.stuff); XCTAssertEqual(saved.stamina,v.stamina)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues:player.pitches.map { ($0.code,$0.mastery) }),v.pitches)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerAbilities>()),1)
            XCTAssertThrowsError(try CareerStore.create(draft(type),schools:SchoolCatalog.load(),in:context))
            XCTAssertFalse(context.hasChanges)
        }
    }
    func testCreationFailureRollsBackPlayerAbilitiesAndCalendarTogether() throws {
        enum Injected:Error {case failure}
        let container = try CareerStore.makeContainer(inMemory:true), context = container.mainContext
        XCTAssertThrowsError(try CareerStore.create(draft(.control),schools:SchoolCatalog.load(),in:context,save:{_ in throw Injected.failure}))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()),0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerAbilities>()),0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerCalendarState>()),0)
        XCTAssertFalse(context.hasChanges)
        _ = try CareerStore.create(draft(.control),schools:SchoolCatalog.load(),in:context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerAbilities>()),1)
    }
    func testLegacyBackfillIsAtomicIdempotentAndDoesNotOverwriteEdits() throws {
        enum Injected:Error {case failure}
        let container = try CareerStore.makeContainer(inMemory:true), context = container.mainContext
        let player = try LegacyPlayerFixture.create(draft(.control),schools:SchoolCatalog.load(),in:context)
        player.contact = 69.1234; player.pitches.first?.mastery = 82.4321; try context.save()
        let original = preserved(player)
        XCTAssertThrowsError(try PlayerAbilityStore.addMissing(in:context,save:{_ in throw Injected.failure}))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerAbilities>()),0); XCTAssertEqual(preserved(player),original)
        try PlayerAbilityStore.addMissing(in:context)
        let saved = try profile(player,context)
        XCTAssertEqual(saved.productionPresetVersion,"legacyDemo"); XCTAssertNil(saved.archetypeRaw); XCTAssertNil(saved.initialValues)
        XCTAssertEqual([saved.velocity,saved.control,saved.stuff,saved.stamina],[50,64,54,56]); XCTAssertEqual(saved.mental,55)
        saved.mental = 63.125; saved.control = 70.25; try context.save()
        var saves = 0
        try PlayerAbilityStore.addMissing(in:context,save:{_ in saves += 1})
        XCTAssertEqual(saves,0); XCTAssertEqual(saved.mental,63.125); XCTAssertEqual(saved.control,70.25)
        XCTAssertEqual(preserved(player),original)
    }
    func testV4FileMigrationPreservesAllPlayerFieldsMatchAndPendingTrainingBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let url = directory.appendingPathComponent("v4.store")
        let original = try autoreleasepool {
            let schema = Schema(versionedSchema:CareerSchemaV4.self)
            let container = try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
            let context = container.mainContext; context.autosaveEnabled = false
            var players: [UUID:[String]] = [:], matches: [UUID:Data] = [:], trainings: [UUID:Data] = [:]
            for type in [PlayerArchetype.contact,.control] {
                let player = try LegacyPlayerFixture.create(draft(type),schools:SchoolCatalog.load(),in:context)
                player.contact = 68.1234; player.speed = 73.4321; player.pitches.first?.mastery = 84.25
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
                let fixture = try XCTUnwrap(state.fixtures(for:player,year:2026).first)
                var game = CareerMatch(random:42,isHome:true,role:player.roleRaw,appearance:true,contact:player.contact,power:player.power,discipline:player.discipline,mastery:Dictionary(uniqueKeysWithValues:player.pitches.map { ($0.code,$0.mastery) }))
                try game.advance(.automatic)
                let match = try CareerMatchRecord(player:player,fixture:fixture,match:game)
                match.completed = true; match.revision = 17; context.insert(match)
                player.gameDate = "2026-04-02"; state.revision = 3
                let training = try CareerTrainingStore.start(player:player,state:state,pitchCode:player.role == .pitcher ? "four-seam" : nil,in:context)
                for _ in 0..<2 {
                    let snapshot = try training.snapshot(), target = snapshot.targets[snapshot.scores.count]
                    try CareerTrainingStore.attempt(player:player,state:state,record:training,revision:training.revision,input:player.role == .pitcher ? TrainingInput(release:0.68) : TrainingInput(x:target.x,y:target.y,timing:0.82),in:context)
                }
                try context.save(); players[player.id] = preserved(player); matches[player.id] = match.payload; trainings[player.id] = training.payload
            }
            return (players,matches,trainings)
        }
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url:url), context = container.mainContext
            let players = try context.fetch(FetchDescriptor<CareerPlayer>())
            XCTAssertEqual(players.count,2); XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerAbilities>()),2)
            for player in players {
                XCTAssertEqual(preserved(player),original.0[player.id]); XCTAssertNil(try profile(player,context).initialValues)
                let match = try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first { $0.playerID == player.id })
                XCTAssertEqual(match.payload,original.1[player.id]); XCTAssertTrue(match.completed); XCTAssertEqual(match.revision,17)
                let training = try XCTUnwrap(context.fetch(FetchDescriptor<CareerTrainingRecord>()).first { $0.playerID == player.id })
                XCTAssertEqual(training.payload,original.2[player.id]); XCTAssertEqual(try training.snapshot().scores.count,2)
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
                XCTAssertEqual(state.revision,6); XCTAssertNil(state.actionDate)
                try finish(player,state,context)
                XCTAssertTrue(training.completed); XCTAssertTrue(state.hasAction(on:player.gameDate))
                XCTAssertEqual(match.payload,original.1[player.id])
            }
        }
        let reopened = try CareerStore.makeContainer(url:url)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<PlayerAbilities>()),2)
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<CareerTrainingRecord>()).allSatisfy(\.completed))
    }
    func testV1V2V3FilesMigrateAndOnlyMissingDefaultsAreAdded() throws {
        let schemas: [any VersionedSchema.Type] = [CareerSchemaV1.self,CareerSchemaV2.self,CareerSchemaV3.self]
        for schemaType in schemas {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:directory)}
            let url = directory.appendingPathComponent("old.store")
            let original = try autoreleasepool {
                let schema = Schema(versionedSchema:schemaType)
                let container = try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
                let player = CareerPlayer(draft:draft(.contact),school:try XCTUnwrap(SchoolCatalog.load().first))
                container.mainContext.insert(player); player.power = 81.1234; try container.mainContext.save()
                return preserved(player)
            }
            let migrated = try CareerStore.makeContainer(url:url), context = migrated.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
            XCTAssertEqual(preserved(player),original); XCTAssertEqual(try profile(player,context).mental,55)
            XCTAssertNil(try profile(player,context).velocity); XCTAssertNil(try profile(player,context).initialValues)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerCalendarState>()),1)
        }
    }
    func testNewTypeDiskReopenKeepsInitialSnapshotAfterTrainingAndNextMatch() throws {
        for type in PlayerArchetype.allCases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:directory)}
            let url = directory.appendingPathComponent("type.store")
            let original = try autoreleasepool {
                let container = try CareerStore.makeContainer(url:url), context = container.mainContext
                let player = try CareerStore.create(draft(type),schools:SchoolCatalog.load(),in:context)
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let initial = try XCTUnwrap(profile(player,context).initialValues)
                try finish(player,state,context)
                let game = try CareerMatchStore.start(player:player,state:state,in:context).snapshot()
                XCTAssertEqual(game.contact,player.contact); XCTAssertEqual(game.mastery,Dictionary(uniqueKeysWithValues:player.pitches.map { ($0.code,$0.mastery) }))
                return (player.id,preserved(player),initial)
            }
            let container = try CareerStore.makeContainer(url:url), context = container.mainContext
            let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
            XCTAssertEqual(player.id,original.0); XCTAssertEqual(preserved(player),original.1)
            let saved = try profile(player,context)
            XCTAssertEqual(saved.initialValues,original.2); XCTAssertEqual(saved.label,type.label)
            XCTAssertEqual(try JSONDecoder().decode(PlayerInitialValues.self,from:XCTUnwrap(saved.initialValues)),type.values)
        }
    }
    func testBreakingGraphUsesOnlyTopTwoOffspeedMasteries() {
        XCTAssertEqual(PlayerInitialValues.breakingRating([:]),0)
        XCTAssertEqual(PlayerInitialValues.breakingRating(["four-seam":100]),0)
        XCTAssertEqual(PlayerInitialValues.breakingRating(["four-seam":100,"fork":35]),35)
        XCTAssertEqual(PlayerInitialValues.breakingRating(["four-seam":100,"fork":35,"slider":55,"changeup":42]),49.8,accuracy:0.00001)
    }
}
