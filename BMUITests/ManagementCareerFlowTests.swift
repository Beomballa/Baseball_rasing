import XCTest

/// Isolated in-memory CareerRootView; never opens the installed player's store.
final class ManagementCareerFlowTests: XCTestCase {
    @MainActor func testV48HomeSelectionFailureHasReadOnlyRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-v48-selection-query-failure"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeSelectionError"].waitForExistence(timeout: 15))
        let before = labels(app)
        capture(app, "v48-home-selection-error")
        app.buttons["retryHomeSelection"].tap()
        XCTAssertFalse(app.staticTexts["homeSelectionError"].exists)
        XCTAssertEqual(labels(app), before)
        capture(app, "v48-home-selection-recovered")
    }

    @MainActor func testV48AbilitiesAndTrainingActionPrecedeLongRulesBothRoles() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let before = labels(app)
            app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
            let strength = app.descendants(matching: .any).matching(identifier: "notebookStrength").firstMatch
            XCTAssertTrue(strength.waitForExistence(timeout: 5))
            XCTAssertTrue(app.frame.contains(strength.frame))
            capture(app, pitcher ? "v48-pitcher-abilities-first" : "v48-batter-abilities-first")
            closeDetail(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            let action = app.buttons["openTraining"]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(app.frame.contains(action.frame))
            XCTAssertTrue(action.isHittable)
            XCTAssertFalse(app.staticTexts["5회 완료 후 예상"].exists)
            capture(app, pitcher ? "v48-pitcher-training-summary" : "v48-batter-training-summary")
            let details = app.descendants(matching: .any).matching(identifier: "trainingPreparationDetails").firstMatch
            details.tap()
            capture(app, pitcher ? "v48-pitcher-training-details" : "v48-batter-training-details")
            closeDetail(app)
            app.buttons["managementTab-home"].tap()
            XCTAssertEqual(labels(app), before)
        }
    }
    private let captureSession = UUID().uuidString
    @MainActor func testSpatialRoomsAndDetailsBothRolesAreReadOnly() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let before = labels(app)
            XCTAssertTrue(app.frame.contains(app.staticTexts["homePlayerName"].frame))
            XCTAssertTrue(app.frame.contains(app.staticTexts["calendarDate"].frame))
            for tab in ["home", "player", "training", "game", "career"] {
                XCTAssertTrue(app.frame.contains(app.buttons["managementTab-" + tab].frame))
            }
            capture(app, pitcher ? "pitcher-home" : "batter-home")
            let cases = [("player", "facility-abilities", "homeAbilityRadar"),
                         ("training", "facility-training", "trainingHubMethod"),
                         ("game", "facility-game", "hubCalendar"),
                         ("career", "facility-goals", "openCareerObjectives")]
            for (tab, facility, detail) in cases {
                app.buttons["managementTab-" + tab].tap()
                XCTAssertTrue(app.buttons[facility].isHittable, facility)
                XCTAssertTrue(app.buttons["roomPrimary"].isHittable)
                XCTAssertTrue(app.frame.contains(app.buttons["roomPrimary"].frame))
                capture(app, (pitcher ? "pitcher-" : "batter-") + tab)
                app.buttons[facility].tap()
                let element = app.descendants(matching: .any).matching(identifier: detail).firstMatch
                XCTAssertTrue(element.waitForExistence(timeout: 6), detail)
                capture(app, (pitcher ? "pitcher-" : "batter-") + tab + "-detail")
                closeDetail(app)
                XCTAssertEqual(labels(app), before)
            }
            app.buttons["managementTab-home"].tap()
            app.buttons["clubhouse-rest"].tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 5))
            capture(app, pitcher ? "pitcher-rest" : "batter-rest")
            app.buttons["닫기"].tap()
            XCTAssertEqual(labels(app), before)
        }
    }

    @MainActor func testTrainingSelectionAndPendingResumeBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let before = labels(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            let kind = pitcher ? "control" : "power"
            reveal(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            XCTAssertEqual(app.staticTexts["trainingHubMethod"].label, pitcher ? "목표 코스 조준" : "타이어 · MAX 중앙에서 손 떼기")
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 6))
            XCTAssertTrue(app.buttons["trainingKind-" + kind].isSelected)
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            XCTAssertFalse(app.buttons["startTraining"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["openTraining"], app)
            XCTAssertTrue(app.buttons["openTraining"].label.contains("이어하기"))
            app.buttons["openTraining"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch.exists)
            XCTAssertFalse(app.buttons["startTraining"].exists)
            capture(app, pitcher ? "pitcher-training-resume" : "batter-training-resume")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-home"].tap()
            XCTAssertTrue(app.buttons["homeResumeTraining"].exists)
            XCTAssertEqual(Array(labels(app).prefix(2)), Array(before.prefix(2)))
            app.buttons["clubhouse-rest"].tap()
            XCTAssertFalse(app.buttons["confirmRest"].isEnabled)
            app.buttons["닫기"].tap()
        }
    }

    @MainActor func testRestGameCompletionAndNextDayBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let originalDate = app.staticTexts["calendarDate"].label
            app.buttons["clubhouse-rest"].tap()
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].label.contains(pitcher ? "52 → 34" : "24 → 6"))
            app.buttons["confirmRest"].tap(); XCTAssertTrue(app.staticTexts["restSaved"].exists)
            app.buttons["restDone"].tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].label, originalDate)
            XCTAssertTrue(app.staticTexts["calendarAction"].label.contains("0/1"))
            app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let automatic = app.buttons["gameAutomatic"]; XCTAssertTrue(automatic.waitForExistence(timeout: 10))
            reveal(automatic, app); automatic.tap(); app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 15))
            capture(app, pitcher ? "pitcher-completed" : "batter-completed")
            reveal(app.buttons["gameReturnHome"], app); app.buttons["gameReturnHome"].tap()
            if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
            XCTAssertTrue(app.buttons["homeTodayGame"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["homeTodayGame"].label.contains("결과"))
            app.buttons["managementTab-game"].tap(); app.buttons["facility-gameRecords"].tap()
            XCTAssertTrue(app.buttons["gameOpenSeason"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "homeGameResults").firstMatch.exists)
            closeDetail(app)
            app.buttons["facility-calendar"].tap()
            reveal(app.buttons["advanceDay"], app); XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
            app.buttons["advanceDay"].tap()
            let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "4월 2일 (목)"), object: app.scrollViews["calendarDetailScroll"].staticTexts["calendarDate"])
            XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed)
            app.buttons["닫기"].tap(); app.buttons["managementTab-home"].tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].label, "4월 2일 (목)")
        }
    }

    @MainActor func testLargeTextFacilitiesKeepStatusesAndSheetCloseReachable() {
        let app = launch(large: true)
        let before = labels(app)
        XCTAssertTrue(app.buttons["managementLargeMenu"].isHittable)
        XCTAssertTrue(app.frame.contains(app.buttons["managementLargeMenu"].frame))
        XCTAssertTrue(app.frame.contains(app.staticTexts["homePlayerName"].frame))
        XCTAssertTrue(app.scrollViews["roomFacilityList"].exists)
        reveal(app.buttons["clubhouse-career"], app); app.buttons["clubhouse-career"].tap()
        reveal(app.buttons["facility-contracts"], app); app.buttons["facility-contracts"].tap()
        XCTAssertTrue(app.buttons["careerSection-contracts"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["careerSection-contracts"].isSelected)
        reveal(app.buttons["openContractMarket"], app); XCTAssertTrue(app.buttons["openContractMarket"].isHittable)
        capture(app, "large-contracts")
        closeDetail(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap()
        XCTAssertEqual(labels(app), before)
        reveal(app.buttons["clubhouse-rest"], app); XCTAssertTrue(app.buttons["clubhouse-rest"].isHittable)
        capture(app, "large-home")
    }

    @MainActor func testFacilityDetailTabsUpdateWithoutClosingSheet() {
        let app = launch()
        let before = labels(app)
        let cases = [("player", "facility-abilities", "playerSection-traits", "traitActiveCount"),
                     ("game", "facility-game", "gameSection-records", "gameOpenSeason"),
                     ("career", "facility-goals", "careerSection-contracts", "openContractMarket")]
        for (tab, facility, choice, content) in cases {
            app.buttons["managementTab-" + tab].tap(); app.buttons[facility].tap()
            reveal(app.buttons[choice], app); app.buttons[choice].tap()
            let result = app.descendants(matching: .any).matching(identifier: content).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), content)
            closeDetail(app); XCTAssertEqual(labels(app), before)
        }
    }

    @MainActor func testRootCreationAndPracticeWaitForRoomSheetDismissal() {
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification"]
        app.launch(); XCTAssertTrue(app.buttons["managementTab-player"].waitForExistence(timeout: 15))
        app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
        reveal(app.buttons["createOtherRole"], app); app.buttons["createOtherRole"].tap()
        XCTAssertTrue(app.buttons["createPlayer"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["closeRoomDetail"].exists)
        app.buttons["닫기"].tap()
        app.buttons["managementTab-training"].tap(); app.buttons["facility-practice"].tap()
        app.buttons["openMatch"].tap()
        XCTAssertTrue(app.buttons["demoPitch"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["closeRoomDetail"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["managementTab-home"].waitForExistence(timeout: 6))
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func switchToPitcher(_ app: XCUIApplication) {
        app.buttons["roomProfile"].tap(); XCTAssertTrue(app.buttons["homeRole-pitcher"].waitForExistence(timeout: 5))
        app.buttons["homeRole-pitcher"].tap()
        if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
        app.buttons["managementTab-home"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("CareerPitch"))
    }
    @MainActor private func closeDetail(_ app: XCUIApplication) {
        app.buttons["closeRoomDetail"].tap()
        XCTAssertTrue(app.buttons["roomProfile"].waitForExistence(timeout: 5))
    }
    @MainActor private func labels(_ app: XCUIApplication) -> [String] {
        ["calendarDate", "homeFatigue", "calendarAction"].map { app.descendants(matching: .any).matching(identifier: $0).firstMatch.label }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            let detail = app.scrollViews["roomDetailScroll"]
            let calendar = app.scrollViews["calendarDetailScroll"]
            let scroll = detail.exists ? detail : calendar.exists ? calendar : app.scrollViews.firstMatch
            if element.exists && element.frame.minY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot); shot.name = title; shot.lifetime = .keepAlways; add(shot)
        let folder = URL.documentsDirectory.appending(path: "ManagementSpatialCaptures/" + captureSession)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: folder.appending(path: title + ".png"))
        } catch { XCTFail("QA screenshot could not be retained: " + error.localizedDescription) }
    }
}
