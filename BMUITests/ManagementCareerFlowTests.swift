import XCTest

final class ManagementCareerFlowTests: XCTestCase {
    @MainActor func testHomeTabsSpatialEntriesBothRolesPreserveDateFatigueAndAction() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["managementTab-player"].tap()
                reveal(app.buttons["homeRole-pitcher"], app); app.buttons["homeRole-pitcher"].tap()
                app.buttons["managementTab-home"].tap()
            }
            let before = labels(app)
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(pitcher ? "CareerPitch" : "CareerBat"))
            capture(app, pitcher ? "Home pitcher clubhouse" : "Home batter clubhouse")
            reveal(app.buttons["clubhouse-training"], app); app.buttons["clubhouse-training"].tap()
            XCTAssertTrue(app.buttons["openTraining"].exists)
            XCTAssertEqual(labels(app), before)
            app.buttons["openTraining"].tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["managementTab-home"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            for tab in ["game", "career", "player", "home"] {
                app.buttons["managementTab-" + tab].tap()
                XCTAssertTrue(app.buttons["managementTab-" + tab].isSelected)
                XCTAssertEqual(labels(app), before)
            }
            reveal(app.buttons["clubhouse-rest"], app); app.buttons["clubhouse-rest"].tap()
            XCTAssertTrue(app.buttons["닫기"].waitForExistence(timeout: 5))
            app.buttons["닫기"].tap()
            XCTAssertEqual(labels(app), before)
        }
    }

    @MainActor func testHomeLargeTextMenuAndSpatialListRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let menu = app.buttons["managementLargeMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        reveal(app.buttons["clubhouse-career"], app); XCTAssertTrue(app.buttons["clubhouse-career"].isHittable)
        app.buttons["clubhouse-career"].tap()
        XCTAssertTrue(app.buttons["openContractMarket"].exists)
        capture(app, "Home large text career entry")
        menu.tap(); app.buttons["홈"].tap()
        reveal(app.buttons["clubhouse-training"], app); XCTAssertTrue(app.buttons["clubhouse-training"].isHittable)
        capture(app, "Home large text spatial list")
    }

    @MainActor private func labels(_ app: XCUIApplication) -> [String] {
        ["calendarDate", "homeFatigue", "calendarAction"].map {
            app.descendants(matching: .any).matching(identifier: $0).firstMatch.label
        }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<16 {
            if element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if element.exists && element.frame.minY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = title; shot.lifetime = .keepAlways; add(shot)
    }
}
