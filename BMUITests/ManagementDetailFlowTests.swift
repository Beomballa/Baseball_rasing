import XCTest

/// Production screens with in-memory QA players; no installed player store is opened.
final class ManagementDetailFlowTests: XCTestCase {
    @MainActor func testPlayerLeagueAndFrozenScoutBoardsBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app)
            let role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
            XCTAssertTrue(app.otherElements["notebookIdentity"].exists || app.descendants(matching: .any).matching(identifier: "notebookIdentity").firstMatch.exists)
            capture(app, role + "-notebook-identity")
            let chart = app.descendants(matching: .any).matching(identifier: "homeAbilityRadar").firstMatch
            reveal(chart, app); XCTAssertTrue(chart.isHittable)
            capture(app, role + "-notebook-abilities")
            close(app); XCTAssertEqual(status(app), before)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-standings"].tap()
            XCTAssertTrue(app.staticTexts["homeLeagueRecord"].waitForExistence(timeout: 8))
            capture(app, role + "-league-overview")
            reveal(app.buttons["openAnnualLeague"], app); app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueProgress"].waitForExistence(timeout: 6))
            capture(app, role + "-league-scoreboard")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
            app.buttons["managementTab-career"].tap(); app.buttons["facility-observation"].tap()
            XCTAssertTrue(app.staticTexts["scoutSavedPeriod"].waitForExistence(timeout: 8))
            let savedPeriod = app.staticTexts["scoutSavedPeriod"].label
            capture(app, role + "-scout-desk")
            reveal(app.buttons["openSavedScoutingReport"], app); app.buttons["openSavedScoutingReport"].tap()
            XCTAssertTrue(app.staticTexts["scoutFrozenDate"].waitForExistence(timeout: 5))
            let frozenDate = app.staticTexts["scoutFrozenDate"].label
            capture(app, role + "-scout-frozen-identity")
            let gradeID = pitcher ? "starter" : "slugger"
            let grade = app.descendants(matching: .any).matching(identifier: "scoutGrade-" + gradeID).firstMatch
            reveal(grade, app); XCTAssertTrue(grade.exists)
            capture(app, role + "-scout-role-evaluation")
            let samples = app.staticTexts["scoutFrozenSample"]
            reveal(samples, app); XCTAssertTrue(samples.exists)
            capture(app, role + "-scout-sample")
            let clubs = app.buttons["scoutClubDetails"]
            reveal(clubs, app); XCTAssertTrue(clubs.exists); clubs.tap()
            let club = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scoutClub-")).firstMatch
            reveal(club, app); XCTAssertTrue(club.exists)
            capture(app, role + "-scout-club-comparison")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.staticTexts["scoutSavedPeriod"], app); XCTAssertEqual(app.staticTexts["scoutSavedPeriod"].label, savedPeriod)
            reveal(app.buttons["openSavedScoutingReport"], app); app.buttons["openSavedScoutingReport"].tap()
            XCTAssertEqual(app.staticTexts["scoutFrozenDate"].label, frozenDate)
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testLineupPowerTendenciesAndRealSeasonBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app)
            openOpponent(app)
            app.buttons["opponentTab-lineup"].tap()
            let first = app.buttons["opponentBatter-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.label.contains("파워")); XCTAssertTrue(first.label.contains("출루 성향")); XCTAssertTrue(first.label.contains("장타 성향"))
            capture(app, pitcher ? "pitcher-lineup-power" : "batter-lineup-power")
            app.buttons["opponentLineupSeason"].tap()
            XCTAssertTrue(first.label.contains("타율")); XCTAssertTrue(first.label.contains("OPS"))
            capture(app, pitcher ? "pitcher-lineup-season" : "batter-lineup-season")
            app.buttons["opponentLineupAbilities"].tap()
            let ninth = app.buttons["opponentBatter-9"]; reveal(ninth, app); ninth.tap()
            XCTAssertTrue(app.staticTexts["opponentIdentity"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["opponentIdentity"].label.contains("9번"))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "opponentStat-WAR").firstMatch.value as? String, "미집계")
            capture(app, pitcher ? "pitcher-ninth-detail" : "batter-ninth-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testLargeTextKeepsDetailValuesAndLineupLabels() {
        let app = launch(large: true)
        app.buttons["managementLargeMenu"].tap(); app.buttons["선수"].tap()
        reveal(app.buttons["facility-abilities"], app); app.buttons["facility-abilities"].tap()
        let weak = app.descendants(matching: .any).matching(identifier: "notebookWeakness").firstMatch
        reveal(weak, app); XCTAssertTrue(weak.isHittable)
        capture(app, "large-notebook-values"); close(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap()
        reveal(app.buttons["facility-analysis"], app); app.buttons["facility-analysis"].tap()
        reveal(app.buttons["hubOpponentAnalysis"], app); app.buttons["hubOpponentAnalysis"].tap()
        XCTAssertTrue(app.buttons["opponentTab-lineup"].waitForExistence(timeout: 5)); app.buttons["opponentTab-lineup"].tap()
        reveal(app.buttons["opponentBatter-1"], app)
        XCTAssertTrue(app.buttons["opponentBatter-1"].label.contains("출루 성향"))
        XCTAssertTrue(app.buttons["opponentBatter-1"].label.contains("장타 성향"))
        capture(app, "large-lineup-labels")
    }

    @MainActor func testCurrentScoutingFileLargeTextBothRoles() {
        let app = launch(large: true)
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap()
                reveal(app.buttons["roomProfile"], app); app.buttons["roomProfile"].tap()
                app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { close(app) }
            }
            let before = status(app)
            app.buttons["managementLargeMenu"].tap(); app.buttons["커리어"].tap()
            reveal(app.buttons["facility-observation"], app); app.buttons["facility-observation"].tap()
            let current = app.buttons["openScoutingReport"]
            reveal(current, app); current.tap()
            XCTAssertTrue(app.staticTexts["scoutActualPlayer"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["scoutActualPlayer"].label.contains(pitcher ? "CareerPitch" : "CareerBat"))
            capture(app, pitcher ? "large-pitcher-current-scout" : "large-batter-current-scout")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-stats-verification"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func openOpponent(_ app: XCUIApplication) {
        app.buttons["managementTab-game"].tap(); app.buttons["facility-analysis"].tap()
        reveal(app.buttons["hubOpponentAnalysis"], app); app.buttons["hubOpponentAnalysis"].tap()
        XCTAssertTrue(app.buttons["opponentTab-lineup"].waitForExistence(timeout: 6))
    }
    @MainActor private func pickPitcher(_ app: XCUIApplication) {
        app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
        if app.buttons["closeRoomDetail"].exists { close(app) }
        app.buttons["managementTab-home"].tap()
    }
    @MainActor private func close(_ app: XCUIApplication) {
        app.buttons["closeRoomDetail"].tap(); XCTAssertTrue(app.buttons["roomProfile"].waitForExistence(timeout: 5))
    }
    @MainActor private func status(_ app: XCUIApplication) -> [String] {
        ["calendarDate", "homeFatigue", "calendarAction"].map { app.descendants(matching: .any).matching(identifier: $0).firstMatch.label }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.isHittable { return }
            let detail = app.scrollViews["roomDetailScroll"]
            let scroll = detail.exists && detail.isHittable ? detail : app.scrollViews.firstMatch
            if element.exists && element.frame.minY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let close = app.buttons["closeRoomDetail"]
        if close.exists && close.isHittable {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in close.frame.minY < 140 }, object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
        }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
