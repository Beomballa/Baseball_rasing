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
