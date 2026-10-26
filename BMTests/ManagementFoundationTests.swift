import XCTest
import UIKit
@testable import BM

final class ManagementFoundationTests: XCTestCase {
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
}
