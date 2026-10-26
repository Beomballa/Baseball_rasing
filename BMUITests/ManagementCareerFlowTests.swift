import XCTest

final class ManagementCareerFlowTests: XCTestCase {
    @MainActor func testActualGameAfterRestCompletesAndNextDayBothRoles() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        for pitcher in [false, true] {
            if pitcher { app.buttons["managementTab-player"].tap(); reveal(app.buttons["homeRole-pitcher"], app); app.buttons["homeRole-pitcher"].tap(); app.buttons["managementTab-home"].tap() }
            reveal(app.buttons["clubhouse-rest"], app); app.buttons["clubhouse-rest"].tap()
            reveal(app.buttons["confirmRest"], app); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
            reveal(app.buttons["homeTodayGame"], app); app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            app.buttons["confirmGamePlan"].tap()
            let automatic = app.buttons["gameAutomatic"]; XCTAssertTrue(automatic.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["managementTab-home"].exists)
            reveal(automatic, app); automatic.tap(); app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 15))
            let returnHome = app.buttons["gameReturnHome"]; reveal(returnHome, app); returnHome.tap()
            app.buttons["managementTab-game"].tap(); app.buttons["gameSection-records"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "homeGameResults").firstMatch.exists)
            capture(app, pitcher ? "Game pitcher recorded result" : "Game batter recorded result")
            app.buttons["managementTab-home"].tap()
            XCTAssertTrue(app.buttons["homeTodayGame"].label.contains("결과"))
            reveal(app.buttons["advanceDay"], app); XCTAssertTrue(app.buttons["advanceDay"].isEnabled); app.buttons["advanceDay"].tap()
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2026-04-02"), object: app.staticTexts["calendarDate"])
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed)
        }
    }
    @MainActor func testCareerMenusAndRestConfirmationBothRolesUseExistingCommands() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        for pitcher in [false, true] {
            if pitcher { app.buttons["managementTab-player"].tap(); reveal(app.buttons["homeRole-pitcher"], app); app.buttons["homeRole-pitcher"].tap() }
            app.buttons["managementTab-career"].tap()
            let before = labels(app)
            XCTAssertTrue(app.buttons["openScoutingReport"].waitForExistence(timeout: 8))
            capture(app, pitcher ? "Career pitcher observation" : "Career batter observation")
            app.buttons["careerSection-goals"].tap(); XCTAssertTrue(app.buttons["openCareerObjectives"].exists)
            capture(app, pitcher ? "Career pitcher goals" : "Career batter goals")
            app.buttons["careerSection-contracts"].tap(); XCTAssertTrue(app.buttons["openContractMarket"].exists)
            capture(app, pitcher ? "Career pitcher contracts" : "Career batter contracts")
            app.buttons["openContractMarket"].tap(); XCTAssertFalse(app.buttons["managementTab-home"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap(); XCTAssertEqual(labels(app), before)
            app.buttons["managementTab-home"].tap(); reveal(app.buttons["clubhouse-rest"], app); app.buttons["clubhouse-rest"].tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].label.contains(pitcher ? "52 → 34" : "24 → 6"))
            capture(app, pitcher ? "Rest pitcher confirmation" : "Rest batter confirmation")
            app.buttons["닫기"].tap(); XCTAssertEqual(labels(app), before)
            app.buttons["clubhouse-rest"].tap(); reveal(app.buttons["confirmRest"], app); app.buttons["confirmRest"].tap()
            XCTAssertTrue(app.staticTexts["restSaved"].exists); capture(app, pitcher ? "Rest pitcher saved" : "Rest batter saved")
            app.buttons["restDone"].tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].label, before[0])
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "homeFatigue").firstMatch.label.contains(pitcher ? "34" : "6"))
            app.buttons["clubhouse-rest"].tap(); XCTAssertFalse(app.buttons["confirmRest"].isEnabled); app.buttons["닫기"].tap()
        }
    }
    @MainActor func testGameMenuAndActualOpponentSeasonBothRolesStayReadOnly() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-stats-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        for pitcher in [false, true] {
            if pitcher { app.buttons["managementTab-player"].tap(); reveal(app.buttons["homeRole-pitcher"], app); app.buttons["homeRole-pitcher"].tap() }
            app.buttons["managementTab-game"].tap()
            let before = labels(app)
            capture(app, pitcher ? "Game pitcher schedule" : "Game batter schedule")
            app.buttons["gameSection-records"].tap(); XCTAssertTrue(app.buttons["gameOpenSeason"].exists)
            app.buttons["gameSection-standings"].tap(); XCTAssertTrue(app.buttons["openAnnualLeague"].exists)
            app.buttons["gameSection-analysis"].tap(); app.buttons["hubOpponentAnalysis"].tap()
            XCTAssertTrue(app.staticTexts["opponentCenterTitle"].waitForExistence(timeout: 8))
            let era = app.descendants(matching: .any).matching(identifier: "opponentStat-ERA").firstMatch
            XCTAssertTrue(era.exists); XCTAssertNotEqual(era.value as? String, "미집계")
            capture(app, pitcher ? "Opponent pitcher season for pitcher" : "Opponent pitcher season for batter")
            app.buttons["opponentTab-batter"].tap()
            XCTAssertNotEqual(app.descendants(matching: .any).matching(identifier: "opponentStat-AVG").firstMatch.value as? String, "미집계")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "opponentStat-OBP").firstMatch.exists); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "opponentStat-SLG").firstMatch.exists)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "opponentStat-WAR").firstMatch.value as? String, "미집계")
            capture(app, pitcher ? "Opponent batting season for pitcher" : "Opponent batting season for batter")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertEqual(labels(app), before)
        }
    }
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
        reveal(app.buttons["careerSection-contracts"], app)
        XCTAssertTrue(app.buttons["careerSection-contracts"].exists)
        app.buttons["careerSection-contracts"].tap()
        reveal(app.buttons["openContractMarket"], app)
        XCTAssertTrue(app.buttons["openContractMarket"].isHittable)
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
