import XCTest

/// Isolated in-memory CareerRootView; never opens the installed player's store.
final class ManagementCareerFlowTests: XCTestCase {
    @MainActor func testV49FictionalChampionSchoolAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-management-empty-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 15))
        reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
        let search = app.textFields["schoolSearch"]; search.tap(); search.typeText("별나루체육고")
        app.buttons["검색 완료"].tap()
        let row = app.buttons["hs-ref-023"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("2025 우승"))
        XCTAssertTrue(row.label.contains("별나루체육고"))
        capture(app, "v49-fictional-champion-large")
        row.tap()
        XCTAssertTrue(app.buttons["schoolPicker"].label.contains("별나루체육고"))
    }

    @MainActor func testV49CreationReviewNavigationAndSavedIdentityBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-management-empty-verification"]; app.launch()
            XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 15))
            if pitcher { reveal(app.buttons["role-pitcher"], app); app.buttons["role-pitcher"].tap() }
            let name = pitcher ? "ReviewPitch" : "ReviewBat"
            app.buttons["creationSection-information"].tap()
            let field = app.textFields["playerName"]; field.tap(); field.typeText(name)
            app.buttons["입력 완료"].tap()
            reveal(app.buttons["randomSchool"], app); app.buttons["randomSchool"].tap()
            let school = app.buttons["schoolPicker"].label
            app.buttons["creationSection-abilities"].tap()
            XCTAssertTrue(app.staticTexts["archetypePreviewTitle"].label.contains(pitcher ? "459 / 459" : "388 / 388"))
            capture(app, pitcher ? "v49-pitcher-budget" : "v49-batter-budget")
            app.buttons["creationSection-appearance"].tap()
            XCTAssertTrue(app.staticTexts["creationMotionPreview"].waitForExistence(timeout: 5))
            capture(app, pitcher ? "v49-pitcher-appearance" : "v49-batter-appearance")
            app.buttons["creationSection-review"].tap()
            XCTAssertTrue(app.staticTexts["creationReadiness"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["creationReadiness"].label.contains("확인 완료"))
            XCTAssertTrue(app.staticTexts["creationSlots-" + (pitcher ? "pitcher" : "batter")].label.contains("활성 0/1"))
            if pitcher { XCTAssertTrue(app.staticTexts["creationReviewPitches"].label.contains("4개")) }
            capture(app, pitcher ? "v49-pitcher-review" : "v49-batter-review")
            app.buttons["creationSection-information"].tap()
            XCTAssertEqual(field.value as? String, name)
            reveal(app.buttons["schoolPicker"], app); XCTAssertEqual(app.buttons["schoolPicker"].label, school)
            app.buttons["creationSection-review"].tap()
            reveal(app.buttons["createPlayer"], app); app.buttons["createPlayer"].tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(name))
            capture(app, pitcher ? "v49-created-pitcher-home" : "v49-created-batter-home")
        }
    }

    @MainActor func testV49SchoolSearchEmptyAndFilteredRandomAndValidationRetry() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-empty-verification"]; app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 15))
        reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
        capture(app, "v49-schools-list")
        let search = app.textFields["schoolSearch"]; search.tap(); search.typeText("no-such-school")
        app.buttons["검색 완료"].tap()
        XCTAssertTrue(app.staticTexts["schoolSearchEmpty"].exists)
        XCTAssertFalse(app.buttons["randomFilteredSchool"].isEnabled)
        capture(app, "v49-school-empty")
        app.buttons["검색 지우기"].tap(); search.tap(); search.typeText("달여울체육고")
        app.buttons["검색 완료"].tap()
        XCTAssertTrue(app.buttons["randomFilteredSchool"].isEnabled)
        capture(app, "v49-school-search")
        app.buttons["randomFilteredSchool"].tap()
        app.buttons["creationSection-review"].tap()
        XCTAssertTrue(app.staticTexts["creationReadiness"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["creationReadiness"].label.contains("이름"))
        reveal(app.buttons["createPlayer"], app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["creationError"].waitForExistence(timeout: 5))
        app.buttons["creationSection-information"].tap()
        let name = app.textFields["playerName"]; name.tap(); name.typeText("RetryPlayer"); app.buttons["입력 완료"].tap()
        reveal(app.buttons["schoolPicker"], app); XCTAssertTrue(app.buttons["schoolPicker"].label.contains("달여울체육고"))
        app.buttons["creationSection-review"].tap(); reveal(app.buttons["createPlayer"], app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("RetryPlayer"))
    }

    @MainActor func testV49LargestTextCreationShortcutsAndReviewRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-empty-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 15))
        for target in ["abilities", "appearance", "review", "information"] {
            let shortcut = app.buttons["creationSection-" + target]
            XCTAssertTrue(shortcut.isHittable); XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
            shortcut.tap()
            capture(app, "v49-large-" + target)
        }
    }
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
