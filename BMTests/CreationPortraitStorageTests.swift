import XCTest
import SwiftData
@testable import BM

@MainActor final class CreationPortraitStorageTests: XCTestCase {
    func testBothRolesReopenWithSamePortraitAndIndependentOptions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Portrait.store"), schools = try SchoolCatalog.load()
        var expected = [UUID: (PlayerAppearance, Data, [String], String)]()
        try autoreleasepool {
            let db = try CareerStore.makeContainer(url: url), context = db.mainContext
            for (index, role) in PlayerRole.allCases.enumerated() {
                var draft = PlayerDraft(); draft.role = role; draft.name = "Portrait\(index)"; draft.schoolID = schools[index].id
                draft.appearance.schoolKitID = draft.schoolID; draft.appearance.eyeShape = 0; draft.appearance.browShape = 0
                draft.appearance.portraitParts = PlayerPortraitParts(face: index + 1, eyes: index + 1, gaze: 2 - index, ears: index + 1)
                draft.appearance.hairStyle = index == 0 ? 7 : 1
                let original = try XCTUnwrap(ManagementPortraitRasterV166.image(draft.appearance)?.pngData())
                let player = try CareerStore.create(draft, schools: schools, in: context)
                XCTAssertEqual(player.appearance, draft.appearance)
                expected[player.id] = (draft.appearance, original, player.pitches.sorted { $0.order < $1.order }.map(\.code), player.gameDate)
            }
        }
        try autoreleasepool {
            let db = try CareerStore.makeContainer(url: url), context = db.mainContext
            for player in try context.fetch(FetchDescriptor<CareerPlayer>()) {
                let saved = try XCTUnwrap(expected[player.id]), lifecycle = player.lifecycleData
                XCTAssertEqual(player.appearance, saved.0)
                XCTAssertEqual(ManagementPortraitRasterV166.image(player.appearance)?.pngData(), saved.1)
                XCTAssertEqual(player.pitches.sorted { $0.order < $1.order }.map(\.code), saved.2)
                XCTAssertEqual(player.gameDate, saved.3)
                let affiliation = ManagementPlayerAffiliation.read(player: player, calendar: nil)
                XCTAssertEqual(ManagementPortraitRasterV166.image(affiliation.appearance)?.pngData(), saved.1)
                XCTAssertEqual(player.lifecycleData, lifecycle)
            }
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testCreationFailureRollsBackAndRetryPreservesLegacyCareer() throws {
        let db = try CareerStore.makeContainer(inMemory: true), context = db.mainContext, schools = try SchoolCatalog.load()
        var old = PlayerDraft(); old.name = "Legacy"; old.schoolID = schools[0].id; old.appearance = PlayerAppearance()
        let legacy = try CareerStore.create(old, schools: schools, in: context), data = legacy.lifecycleData
        let image = ManagementPortraitRasterV166.image(legacy.appearance)?.pngData()
        var draft = PlayerDraft(); draft.role = .pitcher; draft.name = "NewPitch"; draft.schoolID = schools[1].id
        draft.appearance.schoolKitID = draft.schoolID
        draft.appearance.portraitParts = PlayerPortraitParts(face: 3, eyes: 2, gaze: 1, ears: 2)
        let before = draft.appearance
        XCTAssertThrowsError(try CareerStore.create(draft, schools: schools, in: context, save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()), 1)
        XCTAssertEqual(draft.appearance, before)
        let created = try CareerStore.create(draft, schools: schools, in: context)
        XCTAssertEqual(created.appearance.portraitParts, before.portraitParts)
        XCTAssertThrowsError(try CareerStore.create(draft, schools: schools, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()), 2)
        XCTAssertEqual(legacy.lifecycleData, data)
        XCTAssertNil(legacy.appearance.portraitParts)
        XCTAssertEqual(ManagementPortraitRasterV166.image(legacy.appearance)?.pngData(), image)
    }
}
