import XCTest

final class ManagementCareerFlowTests: XCTestCase {
    @MainActor func testPlayerAndTrainingMenusBothRolesKeepChosenKindAndResumeSavedRound() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        for pitcher in [false, true] {
            app.buttons["managementTab-player"].tap()
            if pitcher { reveal(app.buttons["homeRole-pitcher"], app); app.buttons["homeRole-pitcher"].tap() }
            let date = app.staticTexts["calendarDate"].label
            let fatigue = app.descendants(matching: .any).matching(identifier: "homeFatigue").firstMatch.label
            let chart = app.descendants(matching: .any).matching(identifier: "homeAbilityRadar").firstMatch
            XCTAssertTrue(chart.exists)
            if !pitcher { XCTAssertTrue(chart.label.contains("수비")); XCTAssertTrue(chart.label.contains("송구")); XCTAssertFalse(chart.label.contains("수비 종합")) }
            reveal(chart, app)
            capture(app, pitcher ? "Player pitcher abilities" : "Player batter seven abilities")
            reveal(app.buttons["playerSection-traits"], app); app.buttons["playerSection-traits"].tap()
            XCTAssertTrue(app.staticTexts["traitActiveCount"].exists)
            capture(app, pitcher ? "Player pitcher traits" : "Player batter traits")
            app.buttons["playerSection-records"].tap()
            XCTAssertTrue(app.buttons["playerOpenSeason"].exists)
            app.buttons["managementTab-training"].tap()
            let kind = pitcher ? "control" : "power"
            reveal(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            XCTAssertEqual(app.staticTexts["trainingHubMethod"].label, pitcher ? "목표 코스 조준" : "힘과 발사각 조절")
            reveal(app.staticTexts["trainingHubMethod"], app)
            capture(app, pitcher ? "Training pitcher control hub" : "Training batter power hub")
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["trainingKind-" + kind].isSelected)
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            XCTAssertFalse(app.buttons["startTraining"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["openTraining"].label.contains("이어하기"))
            XCTAssertEqual(app.staticTexts["calendarDate"].label, date)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "homeFatigue").firstMatch.label, fatigue)
            app.buttons["openTraining"].tap()
            XCTAssertTrue(app.otherElements["trainingProgress"].exists || app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch.exists)
            XCTAssertFalse(app.buttons["startTraining"].exists)
            capture(app, pitcher ? "Training pitcher saved round" : "Training batter saved round")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
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
