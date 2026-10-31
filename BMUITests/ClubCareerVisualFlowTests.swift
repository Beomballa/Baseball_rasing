import XCTest

final class ClubCareerVisualFlowTests: XCTestCase {
    @MainActor func testDirectoryTargetPickerAndProjectPreserveBothCareerStates() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
            }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            openGoals(app)
            XCTAssertTrue(app.staticTexts["targetAbilityGap"].waitForExistence(timeout: 8))
            capture(app, role + "-goal")
            let summary = app.staticTexts["careerTargetSummary"].label
            let directory = app.buttons["openClubDirectory"]; reveal(directory, app); directory.tap()
            XCTAssertTrue(app.staticTexts["clubDirectorySummary"].waitForExistence(timeout: 5))
            for league in ["kbo", "npb", "mlb"] {
                reveal(app.buttons["clubLeague-" + league], app); app.buttons["clubLeague-" + league].tap()
                capture(app, role + "-directory-" + league)
                let inactive = any("clubDirectory-" + league + "-9", app)
                reveal(inactive, app)
                XCTAssertTrue(inactive.label.contains("미참여"))
                XCTAssertFalse(app.buttons["saveCareerTarget"].exists)
                capture(app, role + "-directory-" + league + "-inactive")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let change = app.buttons["changeCareerTarget"]; reveal(change, app); change.tap()
            let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "targetChoice-domestic/")).firstMatch
            reveal(choice, app); XCTAssertTrue(choice.isHittable); choice.tap()
            capture(app, role + "-target-picker")
            // Cancel the draft: merely looking at another club must not save a target.
            app.buttons["cancelCareerTargetSelection"].tap()
            let current = app.staticTexts["careerTargetSummary"]; reveal(current, app); XCTAssertEqual(current.label, summary)
            let start = app.buttons["startCareerProject"]; reveal(start, app); start.tap()
            let next = app.buttons["projectTodayAction"]; reveal(next, app); XCTAssertTrue(next.isHittable)
            capture(app, role + "-project-action")
            next.tap(); XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
            app.buttons["managementTab-home"].tap()
            XCTAssertEqual(status(app), before)
        }
    }
    @MainActor func testTargetConfirmationClearsHiddenSelectionAndPreservesCareerStatus() {
        continueAfterFailure = false
        let app = launch()
        let before = status(app)
        openGoals(app)
        let change = app.buttons["changeCareerTarget"]; reveal(change, app); change.tap()
        let foreign = app.buttons["targetRoute-MLB 조직 육성"]; reveal(foreign, app); foreign.tap()
        capture(app, "route-after-change")
        XCTAssertFalse(app.buttons["saveCareerTarget"].isEnabled, app.staticTexts["targetDraftSummary"].label + " / " + foreign.label)
        XCTAssertTrue(app.staticTexts["targetDraftSummary"].label.contains("선택하세요"))
        let domestic = app.buttons["targetRoute-국내 프로 관찰"]; reveal(domestic, app); domestic.tap()
        let choice = app.buttons["targetChoice-domestic/comets/field"]; reveal(choice, app); choice.tap()
        XCTAssertTrue(app.staticTexts["targetDraftSummary"].label.contains("대전 코멧츠"))
        XCTAssertTrue(app.buttons["saveCareerTarget"].isEnabled)
        capture(app, "target-confirmation")
        app.buttons["saveCareerTarget"].tap()
        XCTAssertFalse(app.buttons["saveCareerTarget"].waitForExistence(timeout: 2))
        let target = app.staticTexts["careerTargetSummary"]; reveal(target, app)
        XCTAssertTrue(app.staticTexts["대전 코멧츠"].exists)
        capture(app, "saved-target")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["openCareerObjectives"], app); app.buttons["openCareerObjectives"].tap()
        XCTAssertTrue(app.staticTexts["대전 코멧츠"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
        app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
    }
    @MainActor func testLargeTextGoalsDirectoryAndPickerRemainReadable() {
        continueAfterFailure = false
        let app = launch(large: true)
        app.buttons["managementLargeMenu"].tap(); app.buttons["커리어"].tap()
        let goals = app.buttons["facility-goals"]; reveal(goals, app); goals.tap()
        let open = app.buttons["openCareerObjectives"]; reveal(open, app); open.tap()
        let gap = app.staticTexts["targetAbilityGap"]; reveal(gap, app); XCTAssertTrue(gap.isHittable)
        capture(app, "large-goal")
        let directory = app.buttons["openClubDirectory"]; reveal(directory, app); directory.tap()
        let first = any("clubDirectory-kbo-0", app); reveal(first, app); XCTAssertTrue(first.isHittable)
        capture(app, "large-directory")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let change = app.buttons["changeCareerTarget"]; reveal(change, app); change.tap()
        let route = app.buttons["targetRoute-국내 프로 관찰"]; reveal(route, app)
        XCTAssertGreaterThanOrEqual(route.frame.height, 44)
        capture(app, "large-target-picker")
    }
    @MainActor func testV82RoomObjectsAndResultsKeepCareerStateBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-v38-development-verification", "-v38-result-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
            }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            capture(app, "v82-" + role + "-home")
            app.buttons["managementTab-training"].tap()
            let entry = app.buttons["roomPrimary"]
            reveal(entry, app); XCTAssertTrue(entry.isHittable)
            XCTAssertLessThan(entry.frame.width, 270); XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
            XCTAssertLessThan(entry.frame.height, 90)
            XCTAssertTrue(entry.label.contains("훈련")); XCTAssertTrue(app.frame.insetBy(dx: 0, dy: 72).contains(entry.frame))
            capture(app, "v82-" + role + "-training")
            entry.tap()
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout: 8))
            capture(app, "v82-" + role + "-stored-result")
            app.buttons["closeRoomDetail"].tap()
            app.buttons["managementTab-game"].tap()
            XCTAssertTrue(entry.isHittable); XCTAssertLessThan(entry.frame.width, 300)
            XCTAssertTrue(app.frame.contains(entry.frame), "경기 진입이 화면 밖으로 잘리면 안 됩니다.")
            XCTAssertTrue(app.buttons["facility-calendar"].isHittable)
            capture(app, "v82-" + role + "-game")
            app.buttons["facility-calendar"].tap()
            XCTAssertTrue(app.buttons["closeCalendar"].waitForExistence(timeout: 8)); app.buttons["closeCalendar"].tap()
            reveal(app.buttons["facility-gameRecords"], app); app.buttons["facility-gameRecords"].tap()
            XCTAssertTrue(app.buttons["gameSection-records"].waitForExistence(timeout: 8)); app.buttons["closeRoomDetail"].tap()
            app.buttons["managementTab-career"].tap()
            capture(app, "v82-" + role + "-career")
            app.buttons["facility-goals"].tap()
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8)); app.buttons["closeRoomDetail"].tap()
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
    @MainActor func testV82LargestTextSceneEntriesRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for tab in ["훈련", "경기"] {
            app.buttons["managementLargeMenu"].tap(); app.buttons[tab].tap()
            let action = app.buttons["roomPrimary"]; reveal(action, app); XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            capture(app, "v82-large-" + tab)
            action.tap(); XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8))
            if tab == "훈련" {
                let tool = app.buttons["trainingKind-power"]; reveal(tool, app); XCTAssertTrue(tool.isHittable)
                capture(app, "v82-large-equipment")
            }
            app.buttons["closeRoomDetail"].tap()
        }
    }
    @MainActor func testV82EquipmentSelectionAndPreparationDoNotConsumeAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
            }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-training"].tap()
            app.buttons["facility-training"].tap()
            let kind = app.buttons[pitcher ? "trainingKind-control" : "trainingKind-power"]
            let shelf = app.scrollViews["trainingEquipmentShelf"]
            for _ in 0..<5 { if kind.isHittable { break }; shelf.swipeLeft() }
            XCTAssertTrue(kind.isHittable); kind.tap()
            capture(app, "v82-" + role + "-equipment")
            let start = app.buttons["openTraining"]; reveal(start, app); start.tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            capture(app, "v82-" + role + "-preparation")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["closeRoomDetail"].tap()
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
    @MainActor func testV83StadiumStructuresAndScheduleBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
            }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-game"].tap()
            XCTAssertTrue(app.scrollViews["stadiumSceneScroll"].exists)
            XCTAssertFalse(app.buttons["roomBackHome"].exists)
            XCTAssertFalse(app.staticTexts["stadiumScheduleDate"].label.isEmpty)
            XCTAssertTrue(any("stadiumMatchup", app).label.contains("VS"))
            let ids = ["facility-calendar", "roomPrimary", "facility-analysis", "facility-gameRecords", "facility-standings"]
            for id in ids {
                let control = app.buttons[id]
                XCTAssertTrue(control.isHittable, id)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                XCTAssertTrue(app.frame.contains(control.frame), id)
            }
            capture(app, "v83-" + role + "-stadium")
            app.buttons["facility-calendar"].tap()
            XCTAssertTrue(app.buttons["closeCalendar"].waitForExistence(timeout: 8)); app.buttons["closeCalendar"].tap()
            app.buttons["roomPrimary"].tap()
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8))
            capture(app, "v83-" + role + "-preparation")
            app.buttons["closeRoomDetail"].tap()
            for (id, section) in [("facility-analysis", "analysis"), ("facility-gameRecords", "records"), ("facility-standings", "standings")] {
                app.buttons[id].tap()
                XCTAssertTrue(app.buttons["gameSection-" + section].waitForExistence(timeout: 8))
                app.buttons["closeRoomDetail"].tap()
            }
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
    @MainActor func testV83OffDayScoreboardOpensExistingCalendar() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-v38-development-verification", "-v38-result-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        let before = status(app)
        app.buttons["managementTab-game"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "다음 경기 ·")).firstMatch.exists)
        XCTAssertTrue(app.buttons["roomPrimary"].label.contains("다음 일정"))
        capture(app, "v83-offday-stadium")
        app.buttons["roomPrimary"].tap()
        XCTAssertTrue(app.buttons["closeCalendar"].waitForExistence(timeout: 8))
        app.buttons["closeCalendar"].tap(); app.buttons["managementTab-home"].tap()
        XCTAssertEqual(status(app), before)
    }

    @MainActor func testV94TrainingPitchChoicePersistsToNextDay() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-v38-development-verification", "-v38-growth-mild", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
        if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
        app.buttons["managementTab-game"].tap(); app.buttons["facility-calendar"].tap()
        let entry = app.buttons["calendarGoTraining"]; reveal(entry, app); entry.tap()
        let slider = app.buttons["trainingPitch-slider"]; reveal(slider, app); slider.tap(); XCTAssertTrue(slider.isSelected)
        XCTAssertEqual(app.otherElements["trainingScenePreview"].value as? String, "슬라이더")
        capture(app, "v94-slider-training-selected")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let rest = app.buttons["restToday"]; reveal(rest, app); rest.tap()
        XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8)); app.buttons["confirmRest"].tap()
        XCTAssertTrue(app.buttons["restDone"].waitForExistence(timeout: 15)); app.buttons["restDone"].tap()
        let next = app.buttons["advanceDay"]; reveal(next, app); next.tap()
        let date = app.scrollViews["calendarDetailScroll"].staticTexts["calendarDate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "4월 18일 (토)"), object: date)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        reveal(entry, app); entry.tap(); reveal(slider, app); XCTAssertTrue(slider.isSelected)
        XCTAssertEqual(app.otherElements["trainingScenePreview"].value as? String, "슬라이더")
        capture(app, "v94-slider-next-day")
    }
    @MainActor func testV94GamePitchChoiceChangesAndSurvivesReopen() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
        if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
        app.buttons["clubhouse-rest"].tap(); app.buttons["confirmRest"].tap()
        XCTAssertTrue(app.buttons["restDone"].waitForExistence(timeout: 15)); app.buttons["restDone"].tap()
        app.buttons["managementTab-game"].tap(); app.buttons["roomPrimary"].tap()
        let open = app.buttons["openCareerGame"]; reveal(open, app); open.tap()
        let plan = app.buttons["opponentTab-plan"]; XCTAssertTrue(plan.waitForExistence(timeout: 10)); plan.tap()
        let confirm = app.buttons["confirmGamePlan"]; if !confirm.isHittable { reveal(confirm, app) }; confirm.tap()
        let slider = app.buttons["gamePitchChoice-slider"]; XCTAssertTrue(slider.waitForExistence(timeout: 15)); slider.tap()
        XCTAssertTrue(slider.isSelected); capture(app, "v94-game-slider-selected")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
        app.buttons["roomPrimary"].tap(); reveal(open, app); open.tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 10)); XCTAssertTrue(slider.isSelected)
        capture(app, "v94-game-slider-resumed")
    }

    @MainActor func testV91SharedHeaderAcrossTabsAndRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            if pitcher { app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap(); if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() } }
            let before = status(app)
            for tab in ["home", "player", "training", "game", "career"] {
                app.buttons["managementTab-" + tab].tap()
                XCTAssertEqual(status(app), before)
                let profile = app.buttons["roomProfile"]
                XCTAssertTrue(profile.isHittable)
                XCTAssertGreaterThanOrEqual(profile.frame.height, 44)
                XCTAssertTrue(app.frame.contains(profile.frame))
                XCTAssertTrue(app.staticTexts["homeSchool"].exists)
                XCTAssertTrue(app.staticTexts["homeAge"].exists)
                capture(app, "v91-" + (pitcher ? "pitcher-" : "batter-") + tab)
            }
            app.buttons["roomProfile"].tap()
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8))
            app.buttons["closeRoomDetail"].tap()
            app.buttons["managementTab-home"].tap()
        }
    }
    @MainActor func testV91LargeHeaderProfileAndMenu() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        let profile = app.buttons["roomProfile"]; XCTAssertTrue(profile.isHittable)
        capture(app, "v91-large-header")
        profile.tap(); XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8)); app.buttons["closeRoomDetail"].tap()
        app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap()
        XCTAssertTrue(app.buttons["roomProfile"].exists)
        let calendar = app.buttons["facility-calendar"]; reveal(calendar, app); XCTAssertTrue(calendar.isHittable)
        capture(app, "v91-large-game")
    }

    @MainActor func testV89CalendarTrainingEntryAndResume() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            if pitcher { app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap(); if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() } }
            let before = status(app)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-calendar"].tap()
            app.buttons["calendarDay-2026-04-02"].tap()
            let entry = app.buttons["calendarGoTraining"]; reveal(entry, app); XCTAssertTrue(entry.isEnabled)
            capture(app, pitcher ? "v89-pitcher-calendar-training" : "v89-batter-calendar-training")
            entry.tap(); XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["closeCalendar"].tap()
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-calendar"].tap()
            reveal(entry, app); entry.tap()
            let start = app.buttons["startTraining"]; reveal(start, app); start.tap()
            let progress = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
            capture(app, pitcher ? "v89-pitcher-training" : "v89-batter-training")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(entry, app); XCTAssertTrue(entry.label.contains("훈련 이어하기")); entry.tap()
            XCTAssertTrue(progress.waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["startTraining"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["closeCalendar"].tap()
            app.buttons["managementTab-home"].tap()
        }
    }
    @MainActor func testV89CalendarTrainingLockedAfterRest() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-v38-development-verification", "-v38-growth-mild", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        app.buttons["managementTab-game"].tap(); app.buttons["facility-calendar"].tap()
        let rest = app.buttons["restToday"]; reveal(rest, app); rest.tap()
        XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8)); app.buttons["confirmRest"].tap()
        XCTAssertTrue(app.buttons["restDone"].waitForExistence(timeout: 15)); app.buttons["restDone"].tap()
        let entry = app.buttons["calendarGoTraining"]; reveal(entry, app); XCTAssertFalse(entry.isEnabled)
        capture(app, "v89-rest-used")
    }

    @MainActor func testV88CalendarSelectionDoesNotAdvanceAndShowsRoleDays() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            if pitcher { app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap(); if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() } }
            let before = status(app)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-calendar"].tap()
            let first = app.buttons["calendarDay-2026-04-01"]
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            XCTAssertTrue(first.label.contains(pitcher ? "등판" : "출전"))
            capture(app, pitcher ? "v88-pitcher-calendar" : "v88-batter-calendar")
            app.buttons["calendarDay-2026-04-02"].tap()
            let selected = app.staticTexts["calendarSelectedDate"]
            XCTAssertEqual(selected.label, "4월 2일 (목)")
            let next = app.buttons["advanceDay"]; reveal(next, app); XCTAssertFalse(next.isEnabled)
            capture(app, pitcher ? "v88-pitcher-actions" : "v88-batter-actions")
            app.buttons["closeCalendar"].tap(); app.buttons["managementTab-home"].tap()
            XCTAssertEqual(status(app), before)
        }
    }
    @MainActor func testV88CalendarRestThenNextDay() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-v38-development-verification", "-v38-growth-mild", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        app.buttons["managementTab-game"].tap(); app.buttons["facility-calendar"].tap()
        let rest = app.buttons["restToday"]; reveal(rest, app); rest.tap()
        XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8)); app.buttons["confirmRest"].tap()
        XCTAssertTrue(app.buttons["restDone"].waitForExistence(timeout: 15)); app.buttons["restDone"].tap()
        let next = app.buttons["advanceDay"]; reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap()
        let savedDate = app.scrollViews["calendarDetailScroll"].staticTexts["calendarDate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "4월 18일 (토)"), object: savedDate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        app.buttons["closeCalendar"].tap(); app.buttons["managementTab-home"].tap()
        XCTAssertEqual(any("calendarDate", app).label, "4월 18일 (토)")
    }
    @MainActor func testV88ClubReportFilesAndFrozenReopen() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["managementTab-career"].tap()
        let report = app.buttons["facility-observation"]; reveal(report, app); report.tap()
        let open = app.buttons["openSavedScoutingReport"]; reveal(open, app); open.tap()
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "scoutClubFile-")).firstMatch
        let heading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "모집 선수 ·")).firstMatch
        reveal(heading, app); XCTAssertTrue(file.exists)
        capture(app, "v88-club-file-header")
        let original = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scoutClub-")).firstMatch
        reveal(original, app); XCTAssertTrue(original.exists); let label = original.label
        capture(app, "v88-club-file")
        app.navigationBars.buttons.element(boundBy: 0).tap(); reveal(open, app); open.tap()
        reveal(original, app); XCTAssertEqual(original.label, label)
    }

    @MainActor func testV88LargeCalendarControls() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap()
        let entry = app.buttons["facility-calendar"]; reveal(entry, app); entry.tap()
        let first = app.buttons["calendarDay-2026-04-01"]; reveal(first, app); XCTAssertTrue(first.isHittable)
        capture(app, "v88-large-calendar")
        let next = app.buttons["advanceDay"]; reveal(next, app); XCTAssertTrue(next.exists)
        capture(app, "v88-large-actions")
        XCTAssertTrue(app.buttons["closeCalendar"].isHittable)
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-college-pro-verification", "-career-objectives-verification", "-goal-special-verification"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"] }
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 120)); return app
    }
    @MainActor private func openGoals(_ app: XCUIApplication) {
        app.buttons["managementTab-career"].tap(); app.buttons["facility-goals"].tap()
        let open = app.buttons["openCareerObjectives"]; reveal(open, app); open.tap()
    }
    @MainActor private func status(_ app: XCUIApplication) -> [String] {
        ["homePlayerName", "calendarDate", "homeFatigue", "calendarAction"].map { any($0, app).label }
    }
    @MainActor private func any(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<34 {
            let r = element.exists ? element.frame : .zero
            let footer=app.buttons["saveCareerTarget"]
            let bottom=footer.exists && element.identifier != "saveCareerTarget" ? footer.frame.minY - 50 : app.frame.maxY - 15
            if element.exists && element.isHittable && r.minY >= 110 && r.maxY < bottom { return }
            let down = element.exists && r.minY < 110
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.6)).press(forDuration: 0.04,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: down ? 0.85 : 0.3)))
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "v79-" + name; image.lifetime = .keepAlways; add(image)
    }
}
