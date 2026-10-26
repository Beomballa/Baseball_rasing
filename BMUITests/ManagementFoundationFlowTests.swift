import XCTest

final class ManagementFoundationFlowTests: XCTestCase {
    @MainActor func testBothRolesTabsButtonStatesAnd320PointLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-management-components-preview", "-management-preview-width-320"]
        app.launch()
        XCTAssertTrue(app.staticTexts["managementPreviewNoStore"].waitForExistence(timeout: 10))
        capture(app, "Foundation clubhouse 320pt")
        for tab in ["home", "player", "training", "game", "career"] {
            let button = app.buttons["managementTab-" + tab]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        app.buttons["managementTab-player"].tap()
        for pitcher in [false, true] {
            app.buttons[pitcher ? "투수" : "타자"].tap()
            XCTAssertEqual(app.staticTexts["managementPlayerName"].label, pitcher ? "투수 샘플" : "타자 샘플")
            capture(app, pitcher ? "Foundation pitcher components" : "Foundation batter components")
        }
        let primary = app.buttons["managementPrimaryAction"]
        reveal(primary, app: app); XCTAssertTrue(primary.isEnabled); primary.tap()
        XCTAssertEqual(app.staticTexts["managementTapCount"].label, "이번 화면에서 1회 선택")
        chooseState("잠금", app: app)
        reveal(primary, app: app); XCTAssertFalse(primary.isEnabled)
        XCTAssertTrue(app.staticTexts["오늘 행동 사용 · 진행 중인 훈련은 이어갈 수 있습니다"].exists)
        capture(app, "Foundation locked action")
        chooseState("처리 중", app: app)
        reveal(primary, app: app); XCTAssertFalse(primary.isEnabled)
        chooseState("오류", app: app)
        reveal(primary, app: app); XCTAssertTrue(primary.isEnabled); primary.tap()
        XCTAssertEqual(app.staticTexts["managementTapCount"].label, "이번 화면에서 2회 선택")
        capture(app, "Foundation retry and progress")
        reveal(app.staticTexts["managementLastContent"], app: app)
        XCTAssertTrue(app.staticTexts["managementLastContent"].isHittable)
    }

    @MainActor func testLargeTextUsesMenuAndKeepsLastContentReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-management-components-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let menu = app.buttons["managementLargeMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["managementTab-home"].exists)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        menu.tap(); app.buttons["훈련"].tap()
        XCTAssertTrue(app.staticTexts["managementCurrentTab"].label.contains("훈련"))
        capture(app, "Foundation accessibility text")
        let primary = app.buttons["managementPrimaryAction"]
        reveal(primary, app: app); XCTAssertTrue(primary.isHittable)
        XCTAssertGreaterThanOrEqual(primary.frame.height, 56)
        primary.tap()
        reveal(app.staticTexts["managementLastContent"], app: app)
        XCTAssertTrue(app.staticTexts["managementLastContent"].isHittable)
        capture(app, "Foundation large text last content")
    }

    @MainActor private func chooseState(_ state: String, app: XCUIApplication) {
        let menu = app.buttons["managementStateMenu"]
        reveal(menu, app: app); menu.tap(); app.buttons[state].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if element.exists && element.frame.minY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
