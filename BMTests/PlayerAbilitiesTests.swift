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
    func testCustomAllocationBudgetBoundsAndRoleValidation() throws {
        for role in PlayerRole.allCases {
            var allocation = PlayerStatAllocation(role: role, base: PlayerArchetype.initial(for: role).values)
            XCTAssertTrue(allocation.isValid); XCTAssertEqual(allocation.budget, role == .batter ? 388 : 459)
            XCTAssertEqual(allocation.points.count, role == .batter ? 7 : 8)
            let kind: TrainingKind = role == .batter ? .contact : .velocity
            XCTAssertFalse(allocation.canAdjust(kind, by: 1)); allocation.adjust(kind, by: -1)
            XCTAssertEqual(allocation.remaining, 1); XCTAssertFalse(allocation.isValid)
            allocation.adjust(.mental, by: 1); XCTAssertTrue(allocation.isValid)
            let before = allocation; allocation.adjust(kind, by: 2); XCTAssertEqual(allocation, before)
            allocation.points[kind] = -1; XCTAssertFalse(allocation.isValid)
            allocation.points[kind] = 101; XCTAssertFalse(allocation.isValid)
            allocation.points[.pitch] = 1; XCTAssertFalse(allocation.isValid)
        }
    }
    func testCustomCreationSavesExactValuesAndInitialSnapshotOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom.store")
        var expected: [UUID: PlayerInitialValues] = [:]
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url)
            let context = container.mainContext
            defer { withExtendedLifetime(container) {} }
            for role in PlayerRole.allCases {
                var value = PlayerDraft(); value.role = role; value.name = "사용자지정"; value.schoolID = "hs-ref-001"
                value.isCustom = true; value.allocation = PlayerStatAllocation(role: role, base: value.selectedArchetype.values)
                value.allocation?.adjust(role == .batter ? .contact : .velocity, by: -1); value.allocation?.adjust(.mental, by: 1)
                let player = try CareerStore.create(value, schools: SchoolCatalog.load(), in: context)
                expected[player.id] = value.initialValues
            }
        }
        let reopened = try CareerStore.makeContainer(url: url)
        let context = reopened.mainContext
        defer { withExtendedLifetime(reopened) {} }
        for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
            let saved = try profile(player, context), value = try XCTUnwrap(expected[player.id])
            XCTAssertEqual(saved.archetypeRaw, "custom"); XCTAssertEqual(saved.label, "사용자 지정")
            XCTAssertEqual(saved.productionPresetVersion, "custom-v1")
            XCTAssertEqual(try JSONDecoder().decode(PlayerInitialValues.self, from: XCTUnwrap(saved.initialValues)), value)
            XCTAssertEqual(saved.mental, value.mental); XCTAssertEqual(saved.velocity, value.velocity)
            XCTAssertEqual([player.speed, player.defense, player.arm], [value.speed, value.defense, value.arm])
        }
    }
    func testIncompleteCustomAllocationRejectsAndSaveFailureRollsBack() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true)
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        var value = PlayerDraft(); value.name = "커스텀"; value.schoolID = "hs-ref-001"; value.isCustom = true
        XCTAssertThrowsError(try CareerStore.create(value, schools: SchoolCatalog.load(), in: context))
        value.allocation = PlayerStatAllocation(role: .batter, base: value.selectedArchetype.values)
        value.allocation?.adjust(.power, by: -1)
        XCTAssertThrowsError(try CareerStore.create(value, schools: SchoolCatalog.load(), in: context))
        value.allocation?.adjust(.power, by: 1)
        XCTAssertThrowsError(try CareerStore.create(value, schools: SchoolCatalog.load(), in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerAbilities>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlayerTraits>()), 0)
        XCTAssertFalse(context.hasChanges)
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

@MainActor final class RawTrainingTests: XCTestCase {
    private let kinds: [TrainingKind] = [.velocity, .control, .stuff, .stamina, .mental]
    private func setup(_ context: ModelContext, role: PlayerRole = .pitcher) throws -> (CareerPlayer, CareerCalendarState, PlayerAbilities) {
        var draft = PlayerDraft(); draft.name = "원본훈련"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        return (player, try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first),
                try XCTUnwrap(PlayerAbilityStore.profile(playerID: player.id, in: context)))
    }
    private func input(_ training: CareerTraining) -> TrainingInput {
        let target = training.targets[training.scores.count]
        switch training.selectedKind {
        case .control: return TrainingInput(x: target.x, y: target.y)
        case .stamina: return TrainingInput(footfalls: (0..<16).map { $0.isMultiple(of: 2) ? .left : .right })
        case .mental: return TrainingInput(choice: RawTrainingRules.question(targets: training.targets, round: training.scores.count).answer)
        default:
            let goal = RawTrainingRules.goal(kind: training.selectedKind, target: target)
            return TrainingInput(force: goal.force, angle: goal.angle)
        }
    }
    private func attempt(_ player: CareerPlayer, _ state: CareerCalendarState, _ record: CareerTrainingRecord, _ context: ModelContext,
                         save: CalendarProgression.Save = { try $0.save() }) throws {
        try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision,
                                        input: record.completed ? TrainingInput() : input(record.snapshot()), in: context, save: save)
    }
    func testRawScoringHasIndependentPerfectPartialWrongAndInvalidInputs() throws {
        XCTAssertEqual(TrainingKind.stuff.initialDirection, 0)
        XCTAssertEqual(TrainingKind.velocity.initialDirection, 35)
        let fixed = TrainingTarget(x: 0.5, y: 0.5)
        XCTAssertEqual(RawTrainingRules.directionScore(kind: .velocity, target: fixed, force: 75, angle: 35), 100)
        XCTAssertEqual(RawTrainingRules.directionScore(kind: .velocity, target: fixed, force: 55, angle: 35), 50)
        XCTAssertEqual(RawTrainingRules.directionScore(kind: .stuff, target: fixed, force: 50, angle: 180), 100)
        XCTAssertEqual(RawTrainingRules.directionScore(kind: .stuff, target: fixed, force: 50, angle: 0), 0)
        for kind in kinds {
            var training = CareerTraining(playerID: UUID(), date: "2026-04-01", role: "pitcher", pitchCode: nil, before: 60, fatigue: 24, age: 16, calendarRevision: 1, kind: kind)
            XCTAssertThrowsError(try training.attempt(TrainingInput(timing: 0.82)))
            XCTAssertThrowsError(try training.attempt(TrainingInput(force: .nan, angle: 30)))
            for _ in 0..<5 { try training.attempt(input(training)) }
            XCTAssertEqual(training.scores, [100,100,100,100,100]); XCTAssertEqual(training.after, 60.2028)
        }
        var mental = CareerTraining(playerID: UUID(), date: "2026-04-01", role: "batter", pitchCode: nil, before: 55, fatigue: 24, age: 16, calendarRevision: 1, kind: .mental)
        let answer = RawTrainingRules.question(targets: mental.targets, round: 0).answer
        try mental.attempt(TrainingInput(choice: (answer + 1) % 3)); XCTAssertEqual(mental.scores, [0])
        XCTAssertThrowsError(try mental.attempt(TrainingInput(choice: 3)))
        let questions = (0..<5).map { RawTrainingRules.question(targets: mental.targets, round: $0).prompt }
        XCTAssertEqual(Set(questions).count, 5)
    }
    func testAllRawGoalsAndBothRolesMentalGrowOnlyChosenValueAndSnapshotNewMatches() throws {
        for role in PlayerRole.allCases { for kind in role == .batter ? [.mental] : kinds {
            let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
            let (player, state, profile) = try setup(context, role: role)
            let initial = profile.initialValues, fatigue = player.fatigue
            let before = try kinds.map { role == .batter && $0 != .mental ? nil : try profile.value(for: $0) }
            let base = [player.contact,player.power,player.discipline,player.speed,player.defense,player.arm]
            let pitches = Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code, $0.mastery) })
            let record = try CareerTrainingStore.start(player: player, state: state, kind: kind, in: context)
            XCTAssertEqual(record.rulesVersion, "native-training-v4")
            XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context))
            XCTAssertThrowsError(try CareerMatchStore.start(player: player, state: state, in: context))
            for _ in 0..<5 { try attempt(player, state, record, context) }
            let saved = try record.snapshot()
            XCTAssertEqual(saved.scores, [100,100,100,100,100]); XCTAssertGreaterThan(saved.after, saved.before)
            for (index, other) in kinds.enumerated() where before[index] != nil {
                XCTAssertEqual(try profile.value(for: other), other == kind ? saved.after : before[index])
            }
            XCTAssertEqual(base, [player.contact,player.power,player.discipline,player.speed,player.defense,player.arm])
            XCTAssertEqual(profile.initialValues, initial); XCTAssertEqual(Dictionary(uniqueKeysWithValues: player.pitches.map { ($0.code,$0.mastery) }), pitches)
            XCTAssertEqual(player.fatigue, min(100,fatigue+6)); XCTAssertTrue(state.hasAction(on: player.gameDate))
            XCTAssertThrowsError(try attempt(player, state, record, context))
            let result = record.payload
            XCTAssertEqual(try CareerTrainingStore.start(player: player, state: state, kind: .pitch, in: context).payload, result)
            let matchRecord = try CareerMatchStore.start(player: player, state: state, in: context)
            let match = try matchRecord.snapshot(), stats = try XCTUnwrap(match.abilityStats)
            XCTAssertEqual(stats.mental, profile.mental); XCTAssertEqual(stats.velocity, profile.velocity)
            XCTAssertEqual(stats.control, profile.control); XCTAssertEqual(stats.stuff, profile.stuff); XCTAssertEqual(stats.stamina, profile.stamina)
            XCTAssertEqual(stats.fatigue, player.fatigue)
            profile.mental = 99; try context.save()
            XCTAssertEqual(try CareerMatchStore.start(player: player,state: state,in: context).payload, matchRecord.payload)
            XCTAssertEqual(try matchRecord.snapshot().abilityStats, stats)
        } }
    }
    func testRoleRestrictionsAndPitchTrainingDoesNotGrowRawValues() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let (player,state,profile) = try setup(context,role:.batter)
        for kind in kinds where kind != .mental { XCTAssertThrowsError(try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context)) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()),0); XCTAssertEqual(profile.mental,55)
        var draft=PlayerDraft();draft.name="구종단독";draft.schoolID="hs-ref-001";draft.role = .pitcher
        let pitcher=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:context)
        let calendar=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first{$0.playerID==pitcher.id})
        let pitcherProfile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:pitcher.id,in:context)), original=try kinds.map{try pitcherProfile.value(for:$0)}
        let record=try CareerTrainingStore.start(player:pitcher,state:calendar,pitchCode:"slider",in:context)
        for _ in 0..<5 {try CareerTrainingStore.attempt(player:pitcher,state:calendar,record:record,revision:record.revision,input:TrainingInput(release:0.68),in:context)}
        XCTAssertEqual(try kinds.map{try pitcherProfile.value(for:$0)},original)
        XCTAssertGreaterThan(try XCTUnwrap(pitcher.pitches.first{$0.code=="slider"}).mastery,55)
    }
    func testEveryRawTaskResumesFromDiskWithoutRegeneratingOrPayingTwice() throws {
        for kind in kinds {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:directory)}
            let url=directory.appendingPathComponent("raw.store")
            let pending=try autoreleasepool {
                let container=try CareerStore.makeContainer(url:url), context=container.mainContext
                let (player,state,_)=try setup(context)
                let record=try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context)
                for _ in 0..<2 {try attempt(player,state,record,context)}
                return record.payload
            }
            let completed=try autoreleasepool {
                let container=try CareerStore.makeContainer(url:url),context=container.mainContext
                let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record=try CareerTrainingStore.start(player:player,state:state,kind:.pitch,in:context)
                XCTAssertEqual(record.payload,pending);XCTAssertEqual(try record.snapshot().selectedKind,kind)
                for _ in 0..<3 {try attempt(player,state,record,context)}
                return record.payload
            }
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record=try CareerTrainingStore.start(player:player,state:state,kind:.mental,in:context)
            XCTAssertEqual(record.payload,completed); XCTAssertTrue(state.hasAction(on:player.gameDate))
            let value=try XCTUnwrap(PlayerAbilityStore.profile(playerID:player.id,in:context)).value(for:kind)
            XCTAssertEqual(value,try record.snapshot().after)
            XCTAssertThrowsError(try attempt(player,state,record,context));XCTAssertEqual(record.payload,completed)
        }
    }
    func testStartIntermediateAndFinalSaveFailuresRollbackAllFiveRewards() throws {
        enum Failure:Error {case injected}
        for kind in kinds {
            let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            let (player,state,profile)=try setup(context), original=try profile.value(for:kind), initial=profile.initialValues, fatigue=player.fatigue
            XCTAssertThrowsError(try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context,save:{_ in throw Failure.injected}))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerTrainingRecord>()),0);XCTAssertFalse(context.hasChanges)
            let record=try CareerTrainingStore.start(player:player,state:state,kind:kind,in:context)
            let payload=record.payload, revision=record.revision, calendarRevision=state.revision
            XCTAssertThrowsError(try attempt(player,state,record,context,save:{_ in throw Failure.injected}))
            XCTAssertEqual(record.payload,payload);XCTAssertEqual(record.revision,revision);XCTAssertEqual(state.revision,calendarRevision)
            for _ in 0..<4 {try attempt(player,state,record,context)}
            let fourth=record.payload
            XCTAssertThrowsError(try attempt(player,state,record,context,save:{_ in throw Failure.injected}))
            XCTAssertEqual(record.payload,fourth);XCTAssertFalse(record.completed);XCTAssertFalse(state.hasAction(on:player.gameDate))
            XCTAssertEqual(try profile.value(for:kind),original);XCTAssertEqual(player.fatigue,fatigue);XCTAssertEqual(profile.initialValues,initial)
            try attempt(player,state,record,context)
            XCTAssertTrue(record.completed);XCTAssertEqual(try profile.value(for:kind),try record.snapshot().after)
        }
    }
    func testMatchBalanceUsesIndependentStatsAndPressureOnce() throws {
        func stats(mental:Double=55,velocity:Double=50,control:Double=50,stuff:Double=50,stamina:Double=60)->MatchAbilityStats {
            MatchAbilityStats(mental:mental,velocity:velocity,control:control,stuff:stuff,stamina:stamina,fatigue:24)
        }
        XCTAssertEqual(stats(velocity:50).speed(code:"four-seam"),140)
        XCTAssertEqual(stats(velocity:100).speed(code:"slider"),147)
        XCTAssertLessThan(MatchDelivery(x:0.5,y:0.5,speed:160).duration,MatchDelivery(x:0.5,y:0.5,speed:120).duration)
        XCTAssertEqual(stats(stamina:100).pitchCost,0.3,accuracy:0.000001);XCTAssertEqual(stats(stamina:0).pitchCost,0.5)
        XCTAssertEqual(stats(control:0).controlWidth,0.8);XCTAssertEqual(stats(control:100).controlWidth,1.2,accuracy:0.000001)
        XCTAssertEqual(stats(stuff:100).hitChance(quality:0.5),0.20,accuracy:0.000001)
        XCTAssertEqual(stats(stuff:0).hitChance(quality:0.5),0.32,accuracy:0.000001)
        XCTAssertEqual(stats(mental:100).execution(currentFatigue:24,pressure:true),1,accuracy:0.000001)
        XCTAssertEqual(stats(mental:0).execution(currentFatigue:80,pressure:true),0.736,accuracy:0.000001)
        var game=CareerMatch(random:42,isHome:true,role:"pitcher",appearance:true,contact:65,power:75,discipline:60,mastery:["four-seam":60])
        game.controlVersion=2;game.abilityStats=stats(control:100,stamina:100)
        let before=game.random, plan=game.delivery(pitchCode:"four-seam")
        XCTAssertEqual(plan.speed,140);XCTAssertEqual(game.random,before)
        XCTAssertEqual(game.releaseGoodWidth(mastery:60),0.144,accuracy:0.000001)
        let quality=game.releaseQuality(0.75,mastery:60)
        XCTAssertEqual(quality,1-0.07/0.288,accuracy:0.000001)
        let control=game.automaticControl(.pitch,pitchCode:"four-seam")
        var automatic=game, direct=game
        try automatic.advance(.pitch,pitchCode:"four-seam")
        try direct.advance(.pitch,pitchCode:"four-seam",control:control)
        XCTAssertEqual(automatic,direct);XCTAssertEqual(direct.lastManual?.speed,140)
        XCTAssertEqual(direct.fatigueCost,0.3,accuracy:0.000001)
        var legacy=game;legacy.abilityStats=nil
        XCTAssertEqual(legacy.delivery(pitchCode:"four-seam").speed,145)
        XCTAssertEqual(legacy.releaseGoodWidth(mastery:60),0.12,accuracy:0.000001)
        try legacy.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
        XCTAssertEqual(legacy.fatigueCost,0.38,accuracy:0.000001)
        var batter=CareerMatch(random:42,isHome:true,role:"batter",appearance:true,contact:65,power:75,discipline:60,mastery:[:])
        batter.abilityStats=stats(mental:0);batter.half=1
        XCTAssertEqual(batter.executionFactor,1)
        batter.bases[1]=true;XCTAssertEqual(batter.executionFactor,0.92)
        batter.abilityStats=stats(mental:100);XCTAssertEqual(batter.executionFactor,1)
    }
}

extension RawTrainingTests {
    func testEachRawAbilityChangesActualPitchAndPressureEvaluation() throws {
        func game(control:Double=50,stuff:Double=50,stamina:Double=60,mental:Double=55,velocity:Double=50,seed:UInt64=42)->CareerMatch {
            var game=CareerMatch(random:seed,isHome:true,role:"pitcher",appearance:true,contact:65,power:75,discipline:60,mastery:["four-seam":60])
            game.controlVersion=2
            game.abilityStats=MatchAbilityStats(mental:mental,velocity:velocity,control:control,stuff:stuff,stamina:stamina,fatigue:24)
            return game
        }
        var inaccurate=game(control:0), accurate=game(control:100)
        let target=accurate.delivery(pitchCode:"four-seam")
        try inaccurate.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.82))
        try accurate.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.82))
        XCTAssertGreaterThan(try XCTUnwrap(accurate.lastManual).quality,try XCTUnwrap(inaccurate.lastManual).quality)
        XCTAssertLessThan(abs(try XCTUnwrap(accurate.lastManual).x-target.x),abs(try XCTUnwrap(inaccurate.lastManual).x-target.x))
        var weakHits=0, strongHits=0
        for seed in UInt64(0)..<1000 {
            var weak=game(stuff:0,seed:seed), strong=game(stuff:100,seed:seed)
            try weak.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
            try strong.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
            weakHits += weak.line.hitsAllowed;strongHits += strong.line.hitsAllowed
        }
        XCTAssertGreaterThan(weakHits,strongHits)
        var tired=game(stamina:0), enduring=game(stamina:100)
        try tired.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
        try enduring.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.68))
        XCTAssertEqual(tired.fatigueCost,0.5);XCTAssertEqual(enduring.fatigueCost,0.3)
        var unsettled=game(mental:0), focused=game(mental:100)
        unsettled.bases[1]=true;focused.bases[1]=true
        try unsettled.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.75))
        try focused.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.75))
        XCTAssertGreaterThan(try XCTUnwrap(focused.lastManual).quality,try XCTUnwrap(unsettled.lastManual).quality)
        let slow=game(velocity:50).delivery(pitchCode:"four-seam"), faster=game(velocity:50.2).delivery(pitchCode:"four-seam")
        XCTAssertEqual(slow.speed,faster.speed);XCTAssertLessThan(faster.duration,slow.duration)
        XCTAssertEqual(faster.exactSpeed,140.08)
    }
    func testNewAbilityMatchDiskResumeAndFinalResultAreAppliedOnce() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("new-match.store")
        let pending=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let (player,state,_)=try setup(context)
            let training=try CareerTrainingStore.start(player:player,state:state,kind:.mental,in:context)
            for _ in 0..<5 {try attempt(player,state,training,context)}
            let record=try CareerMatchStore.start(player:player,state:state,in:context)
            try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0.75),in:context)
            return try record.snapshot()
        }
        let finished=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let record=try CareerMatchStore.start(player:player,state:state,in:context)
            XCTAssertEqual(try record.snapshot(),pending)
            let profile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:player.id,in:context)); profile.stuff=99;try context.save()
            XCTAssertEqual(try record.snapshot().abilityStats,pending.abilityStats)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.automatic,in:context))
            XCTAssertFalse(record.completed)
            profile.stuff = pending.abilityStats?.stuff; try context.save()
            try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.automatic,in:context)
            XCTAssertTrue(record.completed)
            let fatigue=player.fatigue,payload=record.payload
            XCTAssertThrowsError(try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:.automatic,in:context))
            XCTAssertEqual(player.fatigue,fatigue);XCTAssertEqual(record.payload,payload)
            return (try record.snapshot(),fatigue)
        }
        let container=try CareerStore.makeContainer(url:url),context=container.mainContext
        let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first),state=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()),1)
        XCTAssertEqual(try CareerMatchStore.start(player:player,state:state,in:context).snapshot(),finished.0)
        XCTAssertEqual(player.fatigue,finished.1)
        try CalendarProgression.advanceDay(player:player,state:state,revision:state.revision,in:context)
        XCTAssertEqual(player.gameDate,"2026-04-02")
    }
}

extension PlayerAbilitiesTests {
    func testHomeGraphsSeparateOriginalsAndDerivedAxesWithoutChangingSavedValues() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        for type in [PlayerArchetype.slugger, .endurance] {
            let player = try CareerStore.create(draft(type), schools: SchoolCatalog.load(), in: context)
            let abilities = try profile(player, context), initialPayload = abilities.initialValues
            let before = preserved(player)
            let first = HomeAbilitySummary(player: player, abilities: abilities)
            XCTAssertEqual(first.axes.count, 6)
            XCTAssertTrue(first.hasInitialValues)
            XCTAssertTrue(first.axes.allSatisfy { $0.growth == 0 })
            XCTAssertEqual(first.originals.count, type.role == .batter ? 7 : 8)
            XCTAssertEqual(preserved(player), before)
            if type.role == .batter {
                XCTAssertEqual(try XCTUnwrap(first.axes.first { $0.id == "homeFieldComposite" }).current, 57.8, accuracy: 0.000001)
                player.defense += 1; player.arm += 2
                let changed = HomeAbilitySummary(player: player, abilities: abilities)
                XCTAssertEqual(try XCTUnwrap(changed.axes.first { $0.id == "homeFieldComposite" }?.growth), 1.3, accuracy: 0.000001)
                XCTAssertFalse(changed.originals.contains { $0.id == "homeFieldComposite" })
            } else {
                XCTAssertEqual(try XCTUnwrap(first.axes.first { $0.id == "homeBreaking" }).current, 49.8, accuracy: 0.000001)
                let slider = try XCTUnwrap(player.pitches.first { $0.code == "slider" }); slider.mastery += 0.0123
                let changed = HomeAbilitySummary(player: player, abilities: abilities)
                XCTAssertEqual(try XCTUnwrap(changed.axes.first { $0.id == "homeBreaking" }?.growth), 0.00738, accuracy: 0.000001)
                XCTAssertEqual(try XCTUnwrap(changed.pitches.first { $0.id == "slider" }?.growth), 0.0123, accuracy: 0.000001)
                XCTAssertFalse(changed.originals.contains { $0.id == "homeBreaking" })
                XCTAssertEqual(changed.pitches.map(\.id), ["four-seam", "slider", "changeup", "fork"])
            }
            XCTAssertEqual(abilities.initialValues, initialPayload)
        }
    }
    func testHomeGraphDoesNotInventLegacyOrUnreadableInitialValues() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        let player = try LegacyPlayerFixture.create(draft(.control), schools: SchoolCatalog.load(), in: context)
        try PlayerAbilityStore.addMissing(in: context)
        let abilities = try profile(player, context), before = preserved(player)
        for payload in [nil, Data("invalid".utf8)] as [Data?] {
            abilities.initialValues = payload
            let summary = HomeAbilitySummary(player: player, abilities: abilities)
            XCTAssertFalse(summary.hasInitialValues)
            XCTAssertEqual(summary.axes.count, 6)
            XCTAssertTrue((summary.axes + summary.originals + summary.pitches).allSatisfy { $0.initial == nil && $0.growth == nil })
            XCTAssertEqual(abilities.initialValues, payload)
            XCTAssertEqual(preserved(player), before)
        }
        let missing = HomeAbilitySummary(player: player, abilities: nil)
        XCTAssertNotEqual(missing.axes.count, 6)
        XCTAssertFalse(missing.axes.contains { $0.id == "homeMental" })
    }
    private func scoutRecord(_ player: CareerPlayer, _ fixture: SeasonFixture, line: MatchLine,
                             current: Bool = true, completed: Bool = true) throws -> CareerMatchRecord {
        let date = player.gameDate; player.gameDate = fixture.date.description
        defer { player.gameDate = date }
        var match = CareerMatch(random: 123, isHome: fixture.homeID == player.schoolID, role: player.roleRaw,
                                appearance: fixture.isAppearance(for: player.role), contact: player.contact,
                                power: player.power, discipline: player.discipline, mastery: [:])
        match.line = line; match.completed = completed
        if current { match.controlVersion = 2; match.trainingEffectsVersion = 1 }
        let record = try CareerMatchRecord(player: player, fixture: fixture, match: match)
        record.completed = completed; record.rulesVersion = current ? "native-match-v2" : "native-match-v1"
        return record
    }
    func testScoutingReadsCurrentTrainedAbilitiesBothRolesWithoutWrites() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        for role in PlayerRole.allCases {
            let player = try CareerStore.create(draft(.initial(for: role)), schools: SchoolCatalog.load(), in: context)
            let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
            try finish(player, state, context)
            let before = preserved(player), revision = state.revision, action = state.actionDate
            let report = try ScoutingReportSnapshot.load(player: player, calendar: state, in: context)
            let expected = HomeAbilitySummary(player: player, abilities: try profile(player, context))
            XCTAssertEqual(report.abilities.originals.map(\.current), expected.originals.map(\.current))
            XCTAssertEqual(report.abilities.pitches.map(\.current), expected.pitches.map(\.current))
            XCTAssertEqual(report.age, 16); XCTAssertEqual(report.groups.count, 0)
            XCTAssertEqual(report.totals.games, 0); XCTAssertEqual(preserved(player), before)
            XCTAssertEqual(state.revision, revision); XCTAssertEqual(state.actionDate, action)
            XCTAssertFalse(context.hasChanges)
        }
    }
    func testScoutingRolling365DaysPendingAndSeparateEnvironments() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let player = try CareerStore.create(draft(.contact), schools: SchoolCatalog.load(), in: context)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let fixtures = try state.fixtures(for: player, year: 2026)
        var line = MatchLine(); line.plateAppearances = 5; line.atBats = 4; line.hits = 1; line.walks = 1
        let records = try [scoutRecord(player, fixtures[0], line: line), scoutRecord(player, fixtures[1], line: line),
                           scoutRecord(player, fixtures[2], line: line, current: false)]
        player.gameDate = "2027-04-06"
        let report = try ScoutingReportSnapshot.make(player: player, calendar: state, profile: profile(player, context), records: records)
        XCTAssertEqual(report.start.description, "2026-04-07")
        XCTAssertEqual(report.totals.games, 2); XCTAssertEqual(report.totals.line.plateAppearances, 10)
        XCTAssertEqual(report.groups.count, 2); XCTAssertTrue(report.groups.allSatisfy { !$0.hasBatterMinimum })
        player.gameDate = "2027-04-07"
        let today = try XCTUnwrap(state.fixtures(for: player, year: 2027).first { $0.date.description == player.gameDate })
        let pending = try scoutRecord(player, today, line: MatchLine(), completed: false)
        let next = try ScoutingReportSnapshot.make(player: player, calendar: state, profile: profile(player, context), records: records + [pending])
        XCTAssertEqual(next.start.description, "2026-04-08"); XCTAssertEqual(next.totals.games, 1); XCTAssertEqual(next.pending, 1)
        let other = try CareerStore.create(draft(.stuff), schools: SchoolCatalog.load(), in: context)
        let otherState = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == other.id })
        let unrelated = try scoutRecord(other, XCTUnwrap(otherState.fixtures(for: other, year: 2026).first), line: MatchLine())
        unrelated.payload = Data([0])
        XCTAssertEqual(try ScoutingReportSnapshot.make(player: player, calendar: state, profile: profile(player, context), records: records + [pending, unrelated]).totals.games, 1)
    }
    func testScoutingPitcherUsesIntegerOutsAndDoesNotMixMinimums() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let player = try CareerStore.create(draft(.stuff), schools: SchoolCatalog.load(), in: context)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let fixtures = try state.fixtures(for: player, year: 2026).filter { $0.isAppearance(for: .pitcher) }
        player.gameDate = "2026-09-22"
        var records: [CareerMatchRecord] = []
        for (index, outs) in [24,20,1].enumerated() {
            var line = MatchLine(); line.pitchingOuts = outs; line.pitches = 100
            records.append(try scoutRecord(player, fixtures[index], line: line, current: index != 1))
        }
        let first = try ScoutingReportSnapshot.make(player: player, calendar: state, profile: profile(player, context), records: records)
        XCTAssertEqual(first.totals.innings, "15.0"); XCTAssertEqual(first.groups.count, 2)
        XCTAssertTrue(first.groups.allSatisfy { !$0.hasPitcherMinimum })
        var extra = MatchLine(); extra.pitchingOuts = 20; extra.pitches = 100
        records.append(try scoutRecord(player, fixtures[3], line: extra))
        let next = try ScoutingReportSnapshot.make(player: player, calendar: state, profile: profile(player, context), records: records)
        XCTAssertEqual(next.totals.innings, "21.2"); XCTAssertEqual(next.groups.filter(\.hasPitcherMinimum).count, 1)
        var nonAppearance = MatchLine(); nonAppearance.pitchingOuts = 27
        records.append(try scoutRecord(player, state.fixtures(for: player, year: 2026)[1], line: nonAppearance))
        XCTAssertEqual(try ScoutingReportSnapshot.make(player: player, calendar: state, profile: profile(player, context), records: records).totals.games, 4)
    }
    func testScoutingRejectsCorruptionDuplicatesFutureAndMissingProfile() throws {
        let container = try CareerStore.makeContainer(inMemory: true), context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let player = try CareerStore.create(draft(.contact), schools: SchoolCatalog.load(), in: context)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first), abilities = try profile(player, context)
        let fixtures = try state.fixtures(for: player, year: 2026)
        let saved = try scoutRecord(player, fixtures[0], line: MatchLine())
        XCTAssertThrowsError(try ScoutingReportSnapshot.make(player: player, calendar: state, profile: abilities, records: [saved,saved]))
        let future = try scoutRecord(player, fixtures[1], line: MatchLine())
        XCTAssertThrowsError(try ScoutingReportSnapshot.make(player: player, calendar: state, profile: abilities, records: [future]))
        saved.payload = Data([0]); context.insert(saved); try context.save()
        let payload = saved.payload, revision = saved.revision, before = preserved(player)
        XCTAssertThrowsError(try ScoutingReportSnapshot.load(player: player, calendar: state, in: context))
        XCTAssertEqual(saved.payload,payload); XCTAssertEqual(saved.revision,revision); XCTAssertEqual(preserved(player),before)
        XCTAssertFalse(context.hasChanges)
        abilities.mental = .nan
        XCTAssertThrowsError(try ScoutingReportSnapshot.make(player: player, calendar: state, profile: abilities, records: []))
        context.rollback(); context.delete(abilities); try context.save()
        XCTAssertThrowsError(try ScoutingReportSnapshot.load(player: player, calendar: state, in: context))
        XCTAssertFalse(context.hasChanges)
    }
    func testScoutingDiskReopenPreservesPlayersRecordsAndCalendarBothRoles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scout.store")
        var players: [UUID:[String]] = [:], payloads: [UUID:Data] = [:]
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), context = container.mainContext
            defer { withExtendedLifetime(container) {} }
            for role in PlayerRole.allCases {
                let player = try CareerStore.create(draft(.initial(for: role)), schools: SchoolCatalog.load(), in: context)
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
                try finish(player, state, context)
                let record = try scoutRecord(player, XCTUnwrap(state.fixtures(for: player, year: 2026).first), line: MatchLine())
                context.insert(record); try context.save()
                players[player.id] = preserved(player); payloads[player.id] = record.payload
                XCTAssertEqual(try ScoutingReportSnapshot.load(player: player, calendar: state, in: context).totals.games,1)
                XCTAssertFalse(context.hasChanges)
            }
        }
        let reopened = try CareerStore.makeContainer(url: url), context = reopened.mainContext
        defer { withExtendedLifetime(reopened) {} }
        for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
            let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
            let revision = state.revision, action = state.actionDate
            for _ in 0..<2 { XCTAssertEqual(try ScoutingReportSnapshot.load(player: player, calendar: state, in: context).totals.games,1) }
            XCTAssertEqual(preserved(player),players[player.id]); XCTAssertEqual(state.revision,revision); XCTAssertEqual(state.actionDate,action)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CareerMatchRecord>()).first { $0.playerID == player.id }?.payload,payloads[player.id])
            XCTAssertFalse(context.hasChanges)
        }
    }
    private func scoutingSetup(_ role: PlayerRole = .batter, context: ModelContext) throws -> (CareerPlayer,CareerCalendarState) {
        let player = try CareerStore.create(draft(.initial(for: role)),schools:SchoolCatalog.load(),in:context)
        return (player,try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }))
    }
    func testObservationPeriod28DaysInclusiveOriginLeapAndYearBoundaries() throws {
        let origin = try GameDate("2026-04-01")
        for (date,index,start,next) in [("2026-04-01",0,"2026-04-01","2026-04-29"),("2026-04-28",0,"2026-04-01","2026-04-29"),("2026-04-29",1,"2026-04-29","2026-05-27"),("2026-05-27",2,"2026-05-27","2026-06-24")] {
            let cycle = try ScoutingPeriod(origin:origin,today:GameDate(date))
            XCTAssertEqual(cycle.index,index); XCTAssertEqual(cycle.start.description,start); XCTAssertEqual(cycle.next.description,next)
            XCTAssertEqual(cycle.start.days(to:cycle.end),27)
        }
        XCTAssertEqual(try ScoutingPeriod(origin:GameDate("2028-02-01"),today:GameDate("2028-02-29")).index,1)
        XCTAssertEqual(try ScoutingPeriod(origin:GameDate("2026-12-20"),today:GameDate("2027-01-17")).next.description,"2027-02-14")
        XCTAssertThrowsError(try ScoutingPeriod(origin:origin,today:GameDate("2026-03-31")))
    }
    func testObservationRoleGradesIndependentFormulaAndMissingPitchData() throws {
        let container = try CareerStore.makeContainer(inMemory:true), c = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let (b,_) = try scoutingSetup(context:c), bp = try profile(b,c)
        let initial = try ScoutingRoleEvaluation.grades(role:.batter,abilities:HomeAbilitySummary(player:b,abilities:bp),positionMastery:60)
        XCTAssertEqual(try XCTUnwrap(initial[0].score),52.15,accuracy:0.00001)
        XCTAssertEqual(try XCTUnwrap(initial[1].score),56.71,accuracy:0.00001)
        XCTAssertEqual(try XCTUnwrap(initial[2].score),55.855,accuracy:0.00001)
        b.contact=65;b.power=92;b.discipline=75;bp.mental=65;b.fatigue=100
        XCTAssertEqual(try ScoutingRoleEvaluation.grades(role:.batter,abilities:HomeAbilitySummary(player:b,abilities:bp),positionMastery:60)[0].score,80.2)
        b.fatigue=0
        XCTAssertEqual(try ScoutingRoleEvaluation.grades(role:.batter,abilities:HomeAbilitySummary(player:b,abilities:bp),positionMastery:60)[0].score,80.2)
        let (p,_) = try scoutingSetup(.pitcher,context:c), pp = try profile(p,c)
        let grade = try ScoutingRoleEvaluation.grades(role:.pitcher,abilities:HomeAbilitySummary(player:p,abilities:pp),positionMastery:nil)[0]
        XCTAssertEqual(try XCTUnwrap(grade.score),57.128,accuracy:0.00001)
        XCTAssertTrue(grade.detail.contains("포심"));XCTAssertTrue(grade.detail.contains("슬라이더"))
        p.pitches[0].code="unknown-pitch"
        XCTAssertNil(try ScoutingRoleEvaluation.grades(role:.pitcher,abilities:HomeAbilitySummary(player:p,abilities:pp),positionMastery:nil)[0].score)
    }
    func testObservationCreationAndSamePeriodStayFrozenAfterTrainingMatchAndRefresh() throws {
        let container = try CareerStore.makeContainer(inMemory:true), c = container.mainContext
        defer { withExtendedLifetime(container) {} }
        for role in PlayerRole.allCases {
            let (p,s) = try scoutingSetup(role,context:c)
            let first = try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
            let bytes = first.payload, value = try first.snapshot()
            XCTAssertEqual(value.period,0);XCTAssertEqual(value.nextDate,"2026-04-29");XCTAssertEqual(value.totals.games,0)
            XCTAssertEqual(value.version,4);XCTAssertNotNil(value.contractFit)
            XCTAssertTrue(value.evaluationPending.contains { $0.contains("20세 미만") })
            try finish(p,s,c)
            let match = try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:match,revision:match.revision,input:.automatic,in:c)
            let raw=match.payload, before=preserved(p), revision=s.revision
            for _ in 0..<3 {
                try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("same period saved again")})
            }
            XCTAssertEqual(first.payload,bytes);XCTAssertEqual(try first.snapshot().totals.games,0)
            XCTAssertEqual(try ScoutingReportSnapshot.load(player:p,calendar:s,in:c).totals.games,1)
            XCTAssertEqual(match.payload,raw);XCTAssertEqual(preserved(p),before);XCTAssertEqual(s.revision,revision);XCTAssertFalse(c.hasChanges)
        }
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),2)
    }
    func testObservationDayBoundaryAtomicallyFreezesActualSamplesAndNoDuplicate() throws {
        let container = try CareerStore.makeContainer(inMemory:true), c=container.mainContext
        defer { withExtendedLifetime(container) {} }
        for role in PlayerRole.allCases {
            let (p,s)=try scoutingSetup(role,context:c)
            while p.gameDate < "2026-04-29" {
                if try CalendarProgression.hasGameToday(player:p,state:s) {
                    if !s.hasAction(on:p.gameDate) {try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)}
                    let r=try CareerMatchStore.start(player:p,state:s,in:c)
                    if !r.completed {try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)}
                }
                var calls=0
                try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c,save:{ctx in calls += 1;try ctx.save()})
                XCTAssertEqual(calls,1)
            }
            let rows=try ScoutingObservationStore.reports(player:p,calendar:s,in:c)
            XCTAssertEqual(rows.map(\.period),[1,0]);XCTAssertEqual(rows[0].observedDate,"2026-04-29")
            let live=try ScoutingReportSnapshot.load(player:p,calendar:s,in:c), frozen=try rows[0].snapshot()
            XCTAssertEqual(frozen.totals,live.totals);XCTAssertEqual(frozen.totals.games,role == .batter ? 5:1)
            XCTAssertEqual(frozen.abilities.originals.map(\.current),live.abilities.originals.map(\.current))
            let bytes=rows[0].payload
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c)
            XCTAssertEqual(try ScoutingObservationStore.reports(player:p,calendar:s,in:c).count,2)
            XCTAssertEqual(rows[0].payload,bytes)
        }
    }
    func testObservationBoundarySaveFailureRollsBackDayAndRetryCreatesOnce() throws {
        enum Failure:Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer {withExtendedLifetime(container){}}
        let (p,s)=try scoutingSetup(context:c)
        p.gameDate="2026-04-28";p.fatigue=76;try c.save()
        let before=preserved(p),revision=s.revision
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c,save:{_ in throw Failure.injected}))
        XCTAssertEqual(preserved(p),before);XCTAssertEqual(s.revision,revision)
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),1);XCTAssertFalse(c.hasChanges)
        try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c)
        XCTAssertEqual(p.gameDate,"2026-04-29");XCTAssertEqual(p.fatigue,54)
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),2)
        try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("duplicate save")})
    }
    func testObservationPartialBatchPreservesSuccessfulReportAndFailedDayOnly() async throws {
        enum Failure:Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer {withExtendedLifetime(container){}}
        let (p,s)=try scoutingSetup(context:c)
        p.gameDate="2026-04-26";try c.save();var calls=0
        do {
            _=try await CalendarProgression.advanceOffDays(player:p,state:s,in:c,save:{ctx in calls += 1;if calls == 4 {throw Failure.injected};try ctx.save()})
            XCTFail("expected partial failure")
        } catch let error as CalendarAdvanceFailure {
            XCTAssertEqual(error.summary.days,3);XCTAssertEqual(error.summary.lastSavedDate,"2026-04-29")
        }
        XCTAssertEqual(p.gameDate,"2026-04-29")
        let rows=try ScoutingObservationStore.reports(player:p,calendar:s,in:c)
        XCTAssertEqual(rows.map(\.period),[1,0]);XCTAssertEqual(rows[0].observedDate,"2026-04-29")
        let bytes=rows[0].payload
        _=try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(p.gameDate,"2026-05-01");XCTAssertEqual(rows[0].payload,bytes)
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),2)
    }
    func testObservationCatchUpCreatesOnlyCurrentPeriodAndRejectsDamagedReport() throws {
        enum Failure:Error {case injected}
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer {withExtendedLifetime(container){}}
        let (p,s)=try scoutingSetup(context:c)
        p.gameDate="2027-04-01";try c.save()
        XCTAssertThrowsError(try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in throw Failure.injected}))
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),1);XCTAssertFalse(c.hasChanges)
        try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
        let rows=try ScoutingObservationStore.reports(player:p,calendar:s,in:c)
        XCTAssertEqual(rows.map(\.period),[13,0]);XCTAssertEqual(rows[0].observedDate,"2027-04-01")
        rows[0].payload=Data([0]);try c.save()
        let raw=rows[0].payload,before=preserved(p)
        XCTAssertThrowsError(try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c))
        XCTAssertEqual(rows[0].payload,raw);XCTAssertEqual(preserved(p),before);XCTAssertFalse(c.hasChanges)
    }
    func testObservationV7MigrationPreservesPendingTrainingMatchAndRewardsOnceOnDisk() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("v7-observation.store")
        var players:[UUID:[String]]=[:],trainingData:Data?,matchData:Data?
        try autoreleasepool {
            let schema=Schema(versionedSchema:CareerSchemaV7.self)
            let container=try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
            let c=container.mainContext;c.autosaveEnabled=false
            let (b,bs)=try scoutingSetup(context:c)
            b.gameDate="2026-04-02";try c.save()
            let t=try CareerTrainingStore.start(player:b,state:bs,in:c)
            let target=try t.snapshot().targets[0]
            try CareerTrainingStore.attempt(player:b,state:bs,record:t,revision:t.revision,input:TrainingInput(x:target.x,y:target.y,timing:0.82),in:c)
            let (p,ps)=try scoutingSetup(.pitcher,context:c)
            try CalendarProgression.rest(player:p,state:ps,revision:ps.revision,in:c)
            let m=try CareerMatchStore.start(player:p,state:ps,in:c)
            trainingData=t.payload;matchData=m.payload;players[b.id]=preserved(b);players[p.id]=preserved(p)
        }
        var frozen:[UUID:Data]=[:]
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            defer {withExtendedLifetime(container){}}
            XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),0)
            for p in try c.fetch(FetchDescriptor<CareerPlayer>()) {
                let s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first{$0.playerID==p.id})
                XCTAssertEqual(preserved(p),players[p.id])
                try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
                let row=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
                frozen[p.id]=row.payload;XCTAssertEqual(row.observedDate,p.gameDate)
                if p.role == .batter {
                    let t=try XCTUnwrap(CareerTrainingStore.record(player:p,in:c));XCTAssertEqual(t.payload,trainingData)
                    try finish(p,s,c);let awarded=preserved(p)
                    try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
                    XCTAssertEqual(preserved(p),awarded)
                } else {
                    let m=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first{$0.playerID==p.id})
                    XCTAssertEqual(m.payload,matchData)
                    try CareerMatchStore.advance(player:p,state:s,record:m,revision:m.revision,input:.automatic,in:c)
                    let awarded=preserved(p),payload=m.payload
                    XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:m,revision:m.revision,input:.automatic,in:c))
                    try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
                    XCTAssertEqual(preserved(p),awarded);XCTAssertEqual(m.payload,payload)
                }
                XCTAssertEqual(row.payload,frozen[p.id])
            }
        }
        let reopened=try CareerStore.makeContainer(url:url),c=reopened.mainContext
        defer {withExtendedLifetime(reopened){}}
        for row in try c.fetch(FetchDescriptor<CareerScoutingReport>()) {
            XCTAssertEqual(row.payload,frozen[row.playerID]);XCTAssertEqual(try row.snapshot().totals.games,0)
        }
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerScoutingReport>()),2);XCTAssertFalse(c.hasChanges)
    }
    func testContractContributionUsesExplicitHitsAndBFAndNeverInfersOuts() throws {
        var line=MatchLine();line.plateAppearances=31;line.atBats=25;line.hits=15;line.homeRuns=2;line.walks=5;line.strikeouts=4
        var perf=MatchScoutingPerformance()
        for _ in 0..<10 {perf.record("안타",batter:true,pitcher:false)}
        for _ in 0..<3 {perf.record("2루타",batter:true,pitcher:false)}
        for _ in 0..<2 {perf.record("홈런",batter:true,pitcher:false)}
        perf.record("희생플라이",batter:true,pitcher:false)
        try perf.validate(line:line,role:.batter)
        XCTAssertEqual(try XCTUnwrap(perf.contribution(line,role:.batter)),19.4/31,accuracy:0.0000001)
        var pitching=MatchLine();pitching.pitchingOuts=20;pitching.hitsAllowed=8;pitching.pitchingWalks=3;pitching.pitchingStrikeouts=8
        var p=MatchScoutingPerformance();for i in 0..<25 {p.record(i < 2 ? "홈런":"범타",batter:false,pitcher:true)}
        try p.validate(line:pitching,role:.pitcher)
        XCTAssertEqual(p.sample(pitching,role:.pitcher),25);XCTAssertEqual(p.contribution(pitching,role:.pitcher),0.04)
        var doublePlay=MatchLine();doublePlay.pitchingOuts=2
        var one=MatchScoutingPerformance();one.record("범타",batter:false,pitcher:true)
        try one.validate(line:doublePlay,role:.pitcher);XCTAssertEqual(one.battersFaced,1)
        XCTAssertNil(MatchScoutingPerformance().contribution(MatchLine(),role:.pitcher))
        p.battersFaced = -1;XCTAssertThrowsError(try p.validate(line:pitching,role:.pitcher))
    }
    func testContractCriteriaAndFitBoundariesUseUnroundedValuesAndMissingIsNotVacancy() throws {
        let values=PlayerInitialValues(contact:70,power:70,discipline:70,speed:70,defense:70,arm:70,mental:70)
        func rule(_ demand:RecruitmentDemand,_ competitor:PlayerInitialValues?,empty:Bool=false) -> ClubRoleRecruitment {
            ClubRoleRecruitment(id:"oracle/slugger",name:"검증 구단",roleID:"slugger",demand:demand,leagueMinimum:65,competitor:competitor,confirmedEmpty:empty)
        }
        XCTAssertEqual(try rule(.depth,values).criterion(role:.batter),71)
        XCTAssertEqual(try rule(.vacancy,values).criterion(role:.batter),72)
        XCTAssertEqual(try rule(.vacancy,nil,empty:true).criterion(role:.batter),65)
        XCTAssertNil(try rule(.vacancy,nil).criterion(role:.batter));XCTAssertNil(try rule(.none,values).criterion(role:.batter))
        let invalid=PlayerInitialValues(contact:.nan,power:70,discipline:70,speed:70,defense:70,arm:70)
        XCTAssertThrowsError(try rule(.depth,invalid).criterion(role:.batter))
        XCTAssertEqual(ScoutingContractFit.correction(value:1,reference:0,n:200),4)
        XCTAssertEqual(ScoutingContractFit.correction(value:0,reference:1,n:200),-4)
        XCTAssertEqual(ScoutingContractFit.correction(value:0.6,reference:0.5,n:200),1)
        XCTAssertEqual(ScoutingContractFit.correction(value:2,reference:1,n:0),0)
        for (f,expected) in [(-8.0001,"기량 보완 필요"),(-8,"관찰 구간"),(-3.0001,"관찰 구간"),(-3,"보완·테스트 구간"),(-0.0001,"보완·테스트 구간"),(0,"기량상 계약 후보")] {
            XCTAssertEqual(ScoutingContractFit.stage(f:f),expected)
        }
    }
    func testContractReferenceIsDeterministicAndUsesSameEngineForExplicitAndAutomaticInputs() throws {
        for role in PlayerRole.allCases {
            let position=role == .batter ? "CF":"P",values=PlayerArchetype.initial(for:role).values
            let original=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:8841,home:true)
            var batch=original,step=original,legacy=original
            legacy.scoutingPerformance=nil;try legacy.advance(.automatic)
            try batch.advance(.automatic)
            var limit=0
            while !step.completed && limit < 5000 {
                if role == .pitcher && !step.ownPitcherActive {try step.advance(.automatic);break}
                let input:MatchInput=role == .batter ? .swing:.pitch,code=step.mastery.keys.sorted().first
                try step.advance(input,pitchCode:code,control:step.automaticControl(input,pitchCode:code));limit += 1
            }
            XCTAssertTrue(step.completed);XCTAssertEqual(step.line,batch.line);XCTAssertEqual(step.random,batch.random)
            XCTAssertEqual(legacy.line,batch.line);XCTAssertEqual(legacy.random,batch.random)
            XCTAssertEqual(legacy.fieldPlays,batch.fieldPlays)
            let env=try XCTUnwrap(original.scoutingEnvironment)
            let first=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:env,role:role,position:position))
            let again=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:env,role:role,position:position))
            XCTAssertEqual(first,again);try first.validate()
            XCTAssertEqual(first.totals.games,role == .batter ? 60:18)
            XCTAssertGreaterThan(first.performance.sample(first.totals.line,role:role),0)
            XCTAssertNil(try ScoutingReferenceSimulation.make(environment:env.replacingOccurrences(of:"auto-v1",with:"manual-unverified"),role:role,position:position))
        }
    }
    private func insertFitRecord(_ player:CareerPlayer,_ state:CareerCalendarState,_ fixture:SeasonFixture,_ c:ModelContext,manual:Bool=false,legacy:Bool=false) throws {
        let date=player.gameDate;player.gameDate=fixture.date.description
        defer {player.gameDate=date}
        var match=ScoutingReferenceSimulation.fixture(role:player.role,position:player.role == .batter ? player.positionRaw:"P",
            values:PlayerArchetype.initial(for:player.role).values,seed:UInt64(200+fixture.number),home:fixture.homeID == player.schoolID)
        try match.advance(.automatic)
        if manual {match.scoutingPerformance?.manual=true}
        if legacy {match.scoutingPerformance=nil}
        let row=try CareerMatchRecord(player:player,fixture:fixture,match:match)
        row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
    }
    func testContractReportUsesActualAutoSamplesAndSeparatesManualLegacyAndMissingCriteria() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer {withExtendedLifetime(container){}}
        for role in PlayerRole.allCases {
            let (p,s)=try scoutingSetup(role,context:c)
            let fixtures=try s.fixtures(for:p,year:2026).filter{$0.isAppearance(for:role)}
            try insertFitRecord(p,s,fixtures[0],c)
            try insertFitRecord(p,s,fixtures[1],c,manual:true)
            try insertFitRecord(p,s,fixtures[2],c,legacy:true)
            p.gameDate=fixtures[2].date.adding(days:1).description;try c.save()
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            let report=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first).snapshot()
            // Batter's fixtures lie within period0, so capture current inputs explicitly in the next period.
            if role == .batter {
                p.gameDate="2026-04-29";try c.save();try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            }
            let value=role == .batter ? try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first).snapshot():report
            let fit=try XCTUnwrap(value.contractFit);try fit.validate(observation:value)
            XCTAssertEqual(fit.comparisons.count,3);XCTAssertEqual(fit.comparisons.filter(\.verified).count,1)
            let selected=try XCTUnwrap(fit.selectedEnvironment);XCTAssertTrue(selected.hasSuffix("auto-v1"))
            XCTAssertEqual(fit.comparisons.filter{!$0.verified}.map(\.correction),[0,0])
            XCTAssertTrue(fit.clubs.contains{$0.recruitment.demand == .none && $0.f == nil})
            XCTAssertTrue(fit.clubs.contains{$0.recruitment.confirmedEmpty && $0.c == $0.recruitment.leagueMinimum})
            XCTAssertTrue(fit.clubs.contains{$0.recruitment.demand != .none && $0.recruitment.competitor == nil && !$0.recruitment.confirmedEmpty && $0.c == nil})
            for club in fit.clubs {
                if let h=club.h,let criterion=club.c {XCTAssertEqual(club.f,ScoutingContractFit.round(h-criterion+club.p))}
                XCTAssertTrue(club.blockers.contains{$0.contains("20세 미만")})
            }
            XCTAssertFalse(c.hasChanges)
        }
    }
    func testContractV1ReportAndLegacyGameBytesPreservedUntilNextPeriodOnDisk() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("fit-v8.store");var oldData=Data(),gameData=Data()
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s)=try scoutingSetup(context:c)
            let row=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
            var value=try row.snapshot();value.version=1;value.contractFit=nil;value.interests=nil
            value.evaluationPending=ScoutingObservation.pendingReasons(age:value.age,role:value.role,groups:value.groups)
            row.payload=try JSONEncoder().encode(value);oldData=row.payload
            try insertFitRecord(p,s,XCTUnwrap(s.fixtures(for:p,year:2026).first),c,legacy:true);try c.save()
            gameData=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first).payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("old period rewritten")})
            let old=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
            XCTAssertEqual(old.payload,oldData);XCTAssertNil(try old.snapshot().contractFit)
            p.gameDate="2026-04-28";try c.save()
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c)
            let newest=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first).snapshot()
            XCTAssertEqual(newest.version,4);XCTAssertEqual(newest.contractFit?.comparisons.first?.verified,false)
            XCTAssertEqual(newest.contractFit?.comparisons.first?.correction,0)
            XCTAssertEqual(old.payload,oldData);XCTAssertEqual(try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first).payload,gameData)
        }
    }
    func testContractRejectsTamperedFitAndMetricsWithoutRepairingSavedData() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer {withExtendedLifetime(container){}}
        let (p,s)=try scoutingSetup(context:c)
        let row=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:row.payload) as? [String:Any])
        var fit=try XCTUnwrap(object["contractFit"] as? [String:Any]),clubs=try XCTUnwrap(fit["clubs"] as? [[String:Any]])
        clubs[1]["f"]=999;fit["clubs"]=clubs;object["contractFit"]=fit
        row.payload=try JSONSerialization.data(withJSONObject:object);try c.save()
        let bytes=row.payload,before=preserved(p)
        XCTAssertThrowsError(try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c))
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(preserved(p),before);XCTAssertFalse(c.hasChanges)
    }

    func testInputRoutesHaveIdenticalStandardNPCDistributionsAndRNG() throws {
        for role in PlayerRole.allCases {
            for preset in PlayerArchetype.choices(for:role) {
                for seed in 1...6 {
                    let original=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? "CF":"P",values:preset.values,seed:UInt64(seed),home:seed%2 == 0,tracked:true)
                    var auto=original;try ScoutingReferenceSimulation.run(&auto,mode:.automatic)
                    for mode in [ScoutingInputMode.direct,.mixed] {
                        var other=original;try ScoutingReferenceSimulation.run(&other,mode:mode)
                        try other.scoutingPerformance?.validate(line:other.line,role:role)
                        XCTAssertTrue(other.completed);XCTAssertEqual(other.line,auto.line)
                        XCTAssertEqual(other.random,auto.random);XCTAssertEqual(other.fieldPlays,auto.fieldPlays)
                        XCTAssertEqual(other.pitching,auto.pitching);XCTAssertEqual(other.fatigueCost,auto.fatigueCost)
                        XCTAssertEqual(other.scoutingPerformance?.contribution(other.line,role:role),auto.scoutingPerformance?.contribution(auto.line,role:role))
                        XCTAssertEqual(other.scoutingPerformance?.inputs?.mode,mode)
                    }
                }
            }
        }
    }

    func testDirectAndMixedReferencesAreFrozenVersionedAndMatchAutomaticBaseline() throws {
        for role in PlayerRole.allCases {
            let position=role == .batter ? "CF":"P"
            let base=try XCTUnwrap(ScoutingReferenceSimulation.fixture(role:role,position:position,values:PlayerArchetype.initial(for:role).values,seed:3,home:true,tracked:true).scoutingEnvironment)
            var refs=[ScoutingReference]()
            for mode in ScoutingInputMode.allCases {
                let env=base.replacingOccurrences(of:"auto-v2",with:mode.suffix)
                let ref=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:env,role:role,position:position))
                try ref.validate();XCTAssertEqual(ref.version,2);XCTAssertEqual(ref.inputMode,mode)
                XCTAssertEqual(ref.inputPolicy,"standard-controls-v1");XCTAssertEqual(ref.performance.inputs?.mode,mode)
                XCTAssertEqual(try JSONDecoder().decode(ScoutingReference.self,from:JSONEncoder().encode(ref)),ref)
                refs.append(ref)
            }
            XCTAssertEqual(refs[0].totals,refs[1].totals);XCTAssertEqual(refs[0].totals,refs[2].totals)
            XCTAssertEqual(refs[0].value,refs[1].value);XCTAssertEqual(refs[0].value,refs[2].value)
        }
    }

    func testUserPrecisionChangesPerformanceWithoutChangingNPCReference() throws {
        for role in PlayerRole.allCases {
            var good=PersonalSeasonTotals(),bad=PersonalSeasonTotals()
            var goodPerformance=MatchScoutingPerformance.tracked,badPerformance=MatchScoutingPerformance.tracked
            for seed in 1...20 {
                for accurate in [true,false] {
                    var game=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? "CF":"P",values:PlayerArchetype.initial(for:role).values,seed:UInt64(seed),home:true,tracked:true)
                    while !game.completed {
                        if role == .pitcher && !game.ownPitcherActive {try game.advance(.automatic);break}
                        let code=game.mastery.keys.sorted().first,delivery=game.delivery(pitchCode:code)
                        let control=role == .batter ? ManualMatchInput(x:accurate ? delivery.x:0,y:accurate ? delivery.y:0,timing:accurate ? 0.82:0) : ManualMatchInput(release:accurate ? 0.68:0)
                        try game.advance(role == .batter ? .swing:.pitch,pitchCode:code,control:control)
                    }
                    if accurate {try good.add(game.line);try goodPerformance.add(XCTUnwrap(game.scoutingPerformance))}
                    else {try bad.add(game.line);try badPerformance.add(XCTUnwrap(game.scoutingPerformance))}
                }
            }
            let g=try XCTUnwrap(goodPerformance.contribution(good.line,role:role)),b=try XCTUnwrap(badPerformance.contribution(bad.line,role:role))
            XCTAssertGreaterThan(g,b)
        }
    }

    func testDirectMixedReportsUseActualRecordsAndKeepOldUnclassifiedManualNeutral() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer {withExtendedLifetime(container){}}
        for role in PlayerRole.allCases {
            let (p,s)=try scoutingSetup(role,context:c),fixtures=try s.fixtures(for:p,year:2026).filter{$0.isAppearance(for:role)}
            for (index,mode) in ScoutingInputMode.allCases.enumerated() {
                let fixture=fixtures[index],date=p.gameDate;p.gameDate=fixture.date.description
                var game=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:PlayerArchetype.initial(for:role).values,seed:UInt64(300+index),home:fixture.homeID == p.schoolID,tracked:true)
                try ScoutingReferenceSimulation.run(&game,mode:mode)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:game);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row);p.gameDate=date
            }
            try insertFitRecord(p,s,fixtures[3],c,manual:true)
            p.gameDate=fixtures[3].date.adding(days:28).description;try c.save()
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            let row=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first),bytes=row.payload,value=try row.snapshot()
            let fit=try XCTUnwrap(value.contractFit);XCTAssertEqual(value.version,4);XCTAssertEqual(fit.version,2)
            XCTAssertEqual(fit.comparisons.filter(\.verified).count,3)
            let old=try XCTUnwrap(fit.comparisons.first{$0.id.hasSuffix("manual-unverified")});XCTAssertFalse(old.verified);XCTAssertEqual(old.correction,0)
            for comparison in fit.comparisons where comparison.verified {
                let n=try XCTUnwrap(comparison.performance).sample(comparison.totals.line,role:role)
                let expected=ScoutingContractFit.correction(value:try XCTUnwrap(comparison.value),reference:try XCTUnwrap(comparison.reference?.value),n:n)
                XCTAssertEqual(comparison.correction,expected)
            }
            let selected=try XCTUnwrap(fit.comparisons.first{$0.id == fit.selectedEnvironment})
            for club in fit.clubs {XCTAssertEqual(club.p,selected.correction)}
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("same period saved")})
            XCTAssertEqual(row.payload,bytes);XCTAssertFalse(c.hasChanges)
        }
    }

    func testInputUsageInvalidPayloadAndResumeAreIndependentOfRewards() throws {
        for role in PlayerRole.allCases {
            var game=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? "CF":"P",values:PlayerArchetype.initial(for:role).values,seed:33,home:true,tracked:true)
            let action:MatchInput=role == .batter ? .swing:.pitch,code=game.mastery.keys.sorted().first
            let untouched=game
            XCTAssertThrowsError(try game.advance(action,pitchCode:code,control:ManualMatchInput(x:.nan,release:role == .pitcher ? 0.68:nil)))
            XCTAssertEqual(game,untouched)
            try game.advance(action,pitchCode:code,control:game.automaticControl(action,pitchCode:code))
            var resumed=try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(game))
            try game.advance(.automatic);try resumed.advance(.automatic)
            XCTAssertEqual(game,resumed);XCTAssertEqual(resumed.scoutingPerformance?.inputs?.mode,.mixed)
            var bad=try XCTUnwrap(resumed.scoutingPerformance);bad.inputs?.direct = -1
            XCTAssertThrowsError(try bad.validate(line:resumed.line,role:role))
            let done=resumed;XCTAssertThrowsError(try resumed.advance(.automatic));XCTAssertEqual(resumed,done)
        }
    }

    func testVersionTwoReportAndInFlightV1MetricsRemainUnchangedOnDisk() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("input-fit.store");var bytes=Data(),progress=Data()
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s)=try scoutingSetup(context:c)
            try insertFitRecord(p,s,XCTUnwrap(s.fixtures(for:p,year:2026).first),c,manual:true)
            p.gameDate="2026-04-29";try c.save();try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            let report=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
            var value=try report.snapshot();value.version=2;value.contractFit?.version=1;value.interests=nil
            report.payload=try JSONEncoder().encode(value);bytes=report.payload;try c.save()
            let fixture=try XCTUnwrap(s.fixtures(for:p,year:2026).first{$0.date.description == "2026-05-01"})
            p.gameDate=fixture.date.description
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            var match=ScoutingReferenceSimulation.fixture(role:.batter,position:p.positionRaw,values:PlayerArchetype.initial(for:.batter).values,seed:40,home:fixture.homeID == p.schoolID)
            try match.advance(.swing,control:match.automaticControl(.swing,pitchCode:nil))
            let record=try CareerMatchRecord(player:p,fixture:fixture,match:match);c.insert(record);try c.save();progress=record.payload
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let old=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
            XCTAssertEqual(old.payload,bytes);XCTAssertEqual(try old.snapshot().version,2)
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("frozen report saved")})
            let record=try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first{$0.payload == progress})
            let restored=try CareerMatchStore.start(player:p,state:s,in:c);XCTAssertEqual(record.id,restored.id);XCTAssertEqual(restored.payload,progress)
            XCTAssertEqual(try restored.snapshot().scoutingPerformance?.version,1)
            try CareerMatchStore.advance(player:p,state:s,record:restored,revision:restored.revision,input:.automatic,in:c)
            XCTAssertEqual(try restored.snapshot().scoutingPerformance?.version,1);XCTAssertNil(try restored.snapshot().scoutingPerformance?.inputs)
            let completed=restored.payload,values=preserved(p)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:restored,revision:restored.revision,input:.automatic,in:c))
            XCTAssertEqual(restored.payload,completed);XCTAssertEqual(preserved(p),values)
            p.gameDate="2026-05-27";try c.save();try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            let next=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first).snapshot()
            XCTAssertEqual(next.version,4);XCTAssertEqual(next.contractFit?.version,2)
            XCTAssertTrue(next.contractFit?.comparisons.allSatisfy{!$0.verified && $0.correction == 0} == true)
            XCTAssertEqual(old.payload,bytes)
        }
    }

    func testTrackedInputStoreRollbackDiskResumeAndCompletionOnlyOnceBothRoles() throws {
        for role in PlayerRole.allCases {
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
            let url=folder.appendingPathComponent("tracked.store");var progress=Data()
            try autoreleasepool {
                let container=try CareerStore.makeContainer(url:url),c=container.mainContext
                let (p,s)=try scoutingSetup(role,context:c)
                try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
                let record=try CareerMatchStore.start(player:p,state:s,in:c),original=record.payload,revision=record.revision,values=preserved(p)
                let match=try record.snapshot(),action:MatchInput=role == .batter ? .swing:.pitch,code=match.mastery.keys.sorted().first,control=match.automaticControl(role == .batter ? .swing:.pitch,pitchCode:code)
                XCTAssertEqual(match.scoutingPerformance?.version,2)
                XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:revision,input:action,pitchCode:code,control:control,in:c,save:{_ in throw MatchError.invalidRecord}))
                XCTAssertEqual(record.payload,original);XCTAssertEqual(record.revision,revision);XCTAssertEqual(preserved(p),values)
                try CareerMatchStore.advance(player:p,state:s,record:record,revision:revision,input:action,pitchCode:code,control:control,in:c)
                progress=record.payload;XCTAssertEqual(try record.snapshot().scoutingPerformance?.inputs?.direct,1)
            }
            try autoreleasepool {
                let container=try CareerStore.makeContainer(url:url),c=container.mainContext
                let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record=try CareerMatchStore.start(player:p,state:s,in:c);XCTAssertEqual(record.payload,progress)
                let revision=record.revision
                XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:revision,input:.automatic,in:c,save:{_ in throw MatchError.invalidRecord}))
                XCTAssertEqual(record.payload,progress);XCTAssertFalse(record.completed)
                try CareerMatchStore.advance(player:p,state:s,record:record,revision:revision,input:.automatic,in:c)
                XCTAssertEqual(try record.snapshot().scoutingPerformance?.inputs?.mode,.mixed)
                let result=record.payload,values=preserved(p)
                XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
                XCTAssertEqual(record.payload,result);XCTAssertEqual(preserved(p),values)
            }
        }
    }

    func testUnsupportedEnvironmentKeepsOldAndTrackedEventVersionsSeparate() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext
        defer{withExtendedLifetime(container){}}
        for role in PlayerRole.allCases {
            let (p,s)=try scoutingSetup(role,context:c),fixtures=try s.fixtures(for:p,year:2026).filter{$0.isAppearance(for:role)}
            for index in 0..<2 {
                let fixture=fixtures[index],date=p.gameDate;p.gameDate=fixture.date.description
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:PlayerArchetype.initial(for:role).values,seed:UInt64(901+index),home:fixture.homeID == p.schoolID,tracked:index == 1)
                match.abilityStats=nil;XCTAssertNil(match.scoutingEnvironment)
                try match.advance(.automatic)
                let record=try CareerMatchRecord(player:p,fixture:fixture,match:match);record.completed=true;record.rulesVersion="native-match-v2";c.insert(record);p.gameDate=date
            }
            p.gameDate=fixtures[1].date.adding(days:28).description;try c.save()
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            let value=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first).snapshot()
            XCTAssertEqual(value.groups.count,2)
            XCTAssertEqual(Set(value.groups.compactMap{$0.performance?.version}),Set([1,2]))
            XCTAssertTrue(value.contractFit?.comparisons.allSatisfy{!$0.verified && $0.correction == 0} == true)
            XCTAssertFalse(c.hasChanges)
        }
    }

    private func readyInterest(_ role:PlayerRole,in context:ModelContext) throws -> (CareerPlayer,CareerCalendarState,ScoutingObservation) {
        let (p,s)=try scoutingSetup(role,context:context)
        p.contact=75;p.power=75;p.discipline=75;p.defense=75
        let abilities=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:context))
        try abilities.grow(.mental,to:75)
        if role == .pitcher {
            for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try abilities.grow(kind,to:75)}
            for pitch in p.pitches {pitch.mastery=75}
        }
        let fixtures=try s.fixtures(for:p,year:2026).filter{$0.isAppearance(for:role)}
        let count=role == .batter ? 12:4
        for fixture in fixtures.prefix(count) {try insertFitRecord(p,s,fixture,context)}
        p.gameDate=fixtures[count-1].date.adding(days:28).description;try context.save()
        try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:context)
        return (p,s,try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:context).first).snapshot())
    }
    func testInterestThresholdsAndClubDedupHaveStableBestRoleOrdering() throws {
        for (f,level) in [(-8.0001,nil),(-8,ScoutingInterestLevel.observing),(-3.0001,.observing),(-3,.focused),(-0.0001,.focused),(0,.priority)] {
            XCTAssertEqual(ScoutingInterestLevel.at(f),level)
        }
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext;defer{withExtendedLifetime(container){}}
        let (_,_,value)=try readyInterest(.batter,in:c),interests=try XCTUnwrap(value.interests)
        XCTAssertFalse(interests.entries.isEmpty);XCTAssertEqual(Set(interests.entries.map(\.id)).count,interests.entries.count)
        let fit=try XCTUnwrap(value.contractFit)
        for entry in interests.entries {
            let candidates=fit.clubs.filter{$0.id.hasPrefix(entry.id+"/") && $0.recruitment.roleID != "field" && $0.recruitment.demand != .none && $0.f != nil}
            XCTAssertEqual(entry.fit,candidates.compactMap(\.f).max());XCTAssertEqual(entry.level,.priority)
            XCTAssertEqual(entry.reasons.count,3)
        }
        XCTAssertEqual(interests,ScoutingInterests.make(value));XCTAssertEqual(interests,try JSONDecoder().decode(ScoutingInterests.self,from:JSONEncoder().encode(interests)))
        XCTAssertEqual(interests.entries.map(\.fit),interests.entries.map(\.fit).sorted(by:>))
    }
    func testInterestRequiresVerifiedSelectedMinimumAndRoleConditionsBothRoles() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext;defer{withExtendedLifetime(container){}}
        for role in PlayerRole.allCases {
            let (_,_,value)=try readyInterest(role,in:c),fit=try XCTUnwrap(value.contractFit)
            let source=try XCTUnwrap(fit.comparisons.first{$0.id == fit.selectedEnvironment})
            for enough in [false,true] {
                var copy=value,totals=source.totals
                if role == .batter {totals.line.plateAppearances=enough ? 40:39} else {totals.line.pitchingOuts=enough ? 45:44}
                let row=ScoutingPerformanceComparison(id:source.id,totals:totals,performance:source.performance,reference:source.reference,value:source.value,correction:source.correction,verified:true,reason:source.reason)
                copy.contractFit=ScoutingContractFit(comparisons:[row],selectedEnvironment:source.id,clubs:fit.clubs)
                XCTAssertEqual(ScoutingInterests.make(copy).entries.isEmpty,!enough)
            }
            var missing=value;missing.contractFit=ScoutingContractFit(comparisons:fit.comparisons,selectedEnvironment:nil,clubs:fit.clubs)
            XCTAssertTrue(ScoutingInterests.make(missing).entries.isEmpty)
            XCTAssertFalse(ScoutingInterests.make(missing).pendingReasons.isEmpty)
            XCTAssertFalse(value.interests!.entries.contains{entry in fit.clubs.first{$0.id == entry.id+"/"+entry.roleID}?.recruitment.demand == .none})
            if role == .batter {XCTAssertFalse(value.interests!.entries.contains{$0.roleID == "field"})}
        }
    }
    func testHighSchoolInterestAllowedWithoutCreatingOffersAndLatestCycleCanLoseIt() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext;defer{withExtendedLifetime(container){}}
        for role in PlayerRole.allCases {
            let (p,s,value)=try readyInterest(role,in:c)
            XCTAssertEqual(value.age,16);XCTAssertFalse(try XCTUnwrap(value.interests).entries.isEmpty)
            XCTAssertTrue(value.evaluationPending.contains{$0.contains("20세 미만")})
            let old=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first),bytes=old.payload
            p.contact=10;p.power=10;p.discipline=10;p.defense=10
            let abilities=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c))
            try abilities.grow(.mental,to:10)
            if role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try abilities.grow(kind,to:10)};for pitch in p.pitches {pitch.mastery=10}}
            try c.save();try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("same period interest rewritten")})
            XCTAssertEqual(old.payload,bytes)
            p.gameDate=value.nextDate;try c.save();try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c)
            let next=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first).snapshot()
            XCTAssertTrue(try XCTUnwrap(next.interests).entries.isEmpty);XCTAssertFalse(next.interests!.pendingReasons.isEmpty)
            XCTAssertEqual(old.payload,bytes);XCTAssertFalse(c.hasChanges)
        }
    }
    func testInterestVersionThreeReportPreservedAndNewCycleAtomicFailureOnDisk() throws {
        enum Failure:Error {case injected}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("interest.store");var bytes=Data(),next=""
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let (p,s,value)=try readyInterest(.batter,in:c),row=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
            var old=value;old.version=3;old.interests=nil;row.payload=try JSONEncoder().encode(old);bytes=row.payload;next=value.nextDate
            p.gameDate=try GameDate(next).adding(days:-1).description;try c.save()
            let before=preserved(p)
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c,save:{_ in throw Failure.injected}))
            XCTAssertEqual(preserved(p),before);XCTAssertEqual(row.payload,bytes)
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c)
            XCTAssertEqual(p.gameDate,next)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let rows=try ScoutingObservationStore.reports(player:p,calendar:s,in:c),newest=try XCTUnwrap(rows.first).snapshot()
            XCTAssertEqual(newest.version,4);XCTAssertFalse(try XCTUnwrap(newest.interests).entries.isEmpty)
            let old=try XCTUnwrap(rows.first{ $0.payload == bytes });XCTAssertNil(try old.snapshot().interests)
            try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c,save:{_ in XCTFail("reopen saved interest")})
            XCTAssertEqual(old.payload,bytes);XCTAssertFalse(c.hasChanges)
        }
    }
    func testTamperedInterestRejectedWithoutChangingReportOrPlayer() throws {
        let container=try CareerStore.makeContainer(inMemory:true),c=container.mainContext;defer{withExtendedLifetime(container){}}
        let (p,s,_)=try readyInterest(.pitcher,in:c),row=try XCTUnwrap(ScoutingObservationStore.reports(player:p,calendar:s,in:c).first)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:row.payload) as? [String:Any]),interest=try XCTUnwrap(json["interests"] as? [String:Any])
        var entries=try XCTUnwrap(interest["entries"] as? [[String:Any]]);entries[0]["name"]="다른 구단";interest["entries"]=entries;json["interests"]=interest
        row.payload=try JSONSerialization.data(withJSONObject:json);try c.save();let bytes=row.payload,before=preserved(p)
        XCTAssertThrowsError(try ScoutingObservationStore.ensureCurrent(player:p,calendar:s,in:c))
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(preserved(p),before);XCTAssertFalse(c.hasChanges)
    }
    func testBattedRuleReferencesAreSeparateAndDirectMixedAutomaticRemainComparable() throws {
        for role in PlayerRole.allCases {
            let position=role == .batter ? "CF":"P",values=PlayerArchetype.initial(for:role).values
            let old=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:3,home:true,tracked:true)
            let current=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:3,home:true,tracked:true,battedBallVersion:1)
            let environment=try XCTUnwrap(current.scoutingEnvironment)
            XCTAssertNotEqual(old.scoutingEnvironment,environment);XCTAssertTrue(environment.contains("-batted1-"))
            var references=[ScoutingReference]()
            for mode in ScoutingInputMode.allCases {
                let key=environment.replacingOccurrences(of:"auto-v2",with:mode.suffix)
                let reference=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:key,role:role,position:position))
                try reference.validate();XCTAssertEqual(reference.inputMode,mode)
                XCTAssertEqual(reference,try ScoutingReferenceSimulation.make(environment:key,role:role,position:position))
                references.append(reference)
            }
            XCTAssertEqual(references[0].totals,references[1].totals);XCTAssertEqual(references[0].totals,references[2].totals)
            XCTAssertEqual(references[0].value,references[1].value);XCTAssertEqual(references[0].value,references[2].value)
        }
    }

}
