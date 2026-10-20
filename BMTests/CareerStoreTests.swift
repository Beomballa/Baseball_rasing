import XCTest
import SwiftData
@testable import BM

@MainActor final class CareerStoreTests: XCTestCase {
    private func draft(_ role: PlayerRole = .batter) -> PlayerDraft {
        var value = PlayerDraft()
        value.name = role == .batter ? "김타자" : "이투수"
        value.jerseyNumber = "27"; value.role = role; value.schoolID = "hs-ref-001"
        value.position = .shortstop; value.throwingHand = .left
        value.appearance = PlayerAppearance(skin: 4, hair: 2, kit: 3, hairStyle: 2, expression: 1)
        return value
    }

    func testBundledSchoolsRetainFiftyUniqueIDs() throws {
        let schools = try SchoolCatalog.load()
        XCTAssertEqual(schools.count, 50)
        XCTAssertEqual(schools.first?.id, "hs-ref-001")
        XCTAssertFalse(schools.contains(where: { $0.name == "부천고" || $0.name == "화순고" }))
    }

    func testInvalidDraftsNeverInsert() throws {
        let schools = try SchoolCatalog.load()
        let container = try CareerStore.makeContainer(inMemory: true)
        for invalid in ["", "   ", "1234567890123", "이름\n다음"] {
            var value = draft(); value.name = invalid
            XCTAssertThrowsError(try CareerStore.create(value, schools: schools, in: container.mainContext))
        }
        for invalid in ["-1", "100", "1.0", "A", ""] {
            var value = draft(); value.jerseyNumber = invalid
            XCTAssertThrowsError(try CareerStore.create(value, schools: schools, in: container.mainContext))
        }
        var invalid = draft(); invalid.schoolID = "unknown"
        XCTAssertThrowsError(try CareerStore.create(invalid, schools: schools, in: container.mainContext))
        invalid = draft(); invalid.appearance.skin = 6
        XCTAssertThrowsError(try CareerStore.create(invalid, schools: schools, in: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CareerPlayer>()), 0)
    }

    func testRoleIsolationAndDuplicateRejection() throws {
        let schools = try SchoolCatalog.load()
        let container = try CareerStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let batter = try CareerStore.create(draft(), schools: schools, in: context)
        let pitcher = try CareerStore.create(draft(.pitcher), schools: schools, in: context)
        XCTAssertNotEqual(batter.id, pitcher.id)
        XCTAssertEqual(batter.positionRaw, "SS")
        XCTAssertEqual(pitcher.throwingHandRaw, "left")
        XCTAssertTrue(batter.pitches.isEmpty)
        XCTAssertEqual(pitcher.pitches.count, 4)
        XCTAssertEqual(Set(pitcher.pitches.map(\.code)).count, 4)
        XCTAssertThrowsError(try CareerStore.create(draft(), schools: schools, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()), 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testDiskSaveReopensWithIdentityAppearanceAndMastery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let schools = try SchoolCatalog.load()
        let id: UUID = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url)
            let saved = try CareerStore.create(draft(.pitcher), schools: schools, in: container.mainContext)
            return saved.id
        }
        let reopened = try CareerStore.makeContainer(url: url)
        let players = try reopened.mainContext.fetch(FetchDescriptor<CareerPlayer>())
        let player = try XCTUnwrap(players.first)
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(player.id, id)
        XCTAssertEqual(player.name, "이투수")
        XCTAssertEqual(player.jerseyNumber, 27)
        XCTAssertEqual(player.schoolID, "hs-ref-001")
        XCTAssertEqual(player.schoolName, "경기고")
        XCTAssertEqual(player.appearance, draft(.pitcher).appearance)
        XCTAssertEqual(player.throwingHandRaw, "left")
        XCTAssertEqual(player.startAge, 16)
        XCTAssertEqual(player.gameDate, "2026-04-01")
        XCTAssertEqual(player.fatigue, 52)
        XCTAssertEqual(player.pitches.sorted { $0.order < $1.order }.map(\.mastery), [62,55,42,35])
        XCTAssertFalse(reopened.mainContext.autosaveEnabled)
    }
}

// Preserve explicit demo fixtures for old training/match regression and migration tests.
@MainActor enum LegacyPlayerFixture {
    static func create(_ draft: PlayerDraft, schools: [School], in context: ModelContext) throws -> CareerPlayer {
        let player = CareerPlayer(draft: draft, school: try XCTUnwrap(schools.first { $0.id == draft.schoolID }))
        context.insert(player)
        context.insert(CareerCalendarState(player: player, schools: schools, legacySave: false))
        try context.save()
        if context.container.schema.entities.contains(where: { $0.name == "PlayerPositions" }) {
            try PlayerPositionStore.addMissing(in: context)
        }
        return player
    }
}
