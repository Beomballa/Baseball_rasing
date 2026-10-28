import XCTest
import UIKit
@testable import BM

final class ManagementFoundationTests: XCTestCase {
    func testV48TrainingInstructionsRespectRecordedVersionWithoutChangingInputs() {
        for kind in [TrainingKind.power, .velocity, .stuff] {
            XCTAssertEqual(kind.drillDescription, kind.drillDescription(version: 1))
            XCTAssertNotEqual(kind.drillDescription(version: nil), kind.drillDescription(version: 1))
        }
        XCTAssertEqual(TrainingKind.power.drillDescription(version: nil), "힘과 발사각 조절")
        for kind in TrainingKind.allCases where ![.power, .velocity, .stuff].contains(kind) {
            XCTAssertEqual(kind.drillDescription(version: nil), kind.drillDescription(version: 1))
        }
    }
    @MainActor func testAddedPlayerAndTrainingRoomAssetsAreBundled() throws {
        for name in ["LockerV1", "BattingRoomV1", "BullpenRoomV1", "StadiumGateV1", "ScoutRoomV1", "RestRoomV1"] {
            let image = try XCTUnwrap(UIImage(named: name), name)
            XCTAssertGreaterThan(image.size.width, image.size.height)
            XCTAssertLessThan(image.size.width / image.size.height, 2)
        }
    }
    func testProgressKeepsUnknownDistinctFromZeroAndClampsOnlyTheBar() {
        XCTAssertNil(ManagementProgressValue(current: nil, target: 100).ratio)
        XCTAssertEqual(ManagementProgressValue(current: nil, target: 100).display, "미집계")
        XCTAssertEqual(ManagementProgressValue(current: 0, target: 100).ratio, 0)
        XCTAssertNotEqual(ManagementProgressValue(current: 0, target: 100).display, "미집계")
        XCTAssertEqual(ManagementProgressValue(current: 2, target: 5).ratio, 0.4)
        XCTAssertEqual(ManagementProgressValue(current: -2, target: 100).ratio, 0)
        XCTAssertEqual(ManagementProgressValue(current: 120, target: 100).ratio, 1)
        XCTAssertEqual(ManagementProgressValue(current: 120, target: 100).current, 120)
        for invalid in [0.0, -1, .infinity, .nan] {
            XCTAssertNil(ManagementProgressValue(current: 5, target: invalid).ratio)
        }
        XCTAssertNil(ManagementProgressValue(current: .infinity, target: 100).ratio)
        XCTAssertNil(ManagementProgressValue(current: .nan, target: 100).ratio)
    }

    @MainActor func testEveryMenuArtworkAndCleanBackdropLoadFromAppBundle() throws {
        for tab in ManagementTab.allCases {
            let image = try XCTUnwrap(UIImage(named: tab.asset), tab.title)
            XCTAssertEqual(image.size, CGSize(width: 28, height: 28))
            XCTAssertTrue([56, 84].contains(try XCTUnwrap(image.cgImage).width))
        }
        let scene = try XCTUnwrap(UIImage(named: "ClubhouseV1"))
        XCTAssertGreaterThan(scene.size.height, scene.size.width)
    }
    func testSpatialDateAndFatigueDisplayBoundaries() {
        XCTAssertEqual(ManagementDisplay.date("2026-04-01"), "4월 1일 (수)")
        XCTAssertEqual(ManagementDisplay.date("2027-01-01"), "1월 1일 (금)")
        XCTAssertEqual(ManagementDisplay.date("unavailable"), "unavailable")
        XCTAssertEqual(ManagementDisplay.fatigueLabel(40), "양호")
        XCTAssertEqual(ManagementDisplay.fatigueLabel(41), "주의")
        XCTAssertEqual(ManagementDisplay.fatigueLabel(59), "주의")
        XCTAssertEqual(ManagementDisplay.fatigueLabel(60), "높음")
    }
    @MainActor func testApprovedPortraitRoomsAreBundledSeparatelyFromLegacyArt() throws {
        for name in ["ClubhouseRoomV2", "LockerRoomV2", "BattingRoomV2", "BullpenRoomV2", "StadiumRoomV2", "ScoutRoomV2", "RestRoomV2"] {
            let image = try XCTUnwrap(UIImage(named: name), name)
            XCTAssertGreaterThan(image.size.height, image.size.width)
            XCTAssertEqual(image.size.height / image.size.width, 1.75, accuracy: 0.02)
        }
    }
}
