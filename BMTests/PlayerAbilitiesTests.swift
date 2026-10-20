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
}
