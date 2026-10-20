import XCTest

final class CareerFlowTests: XCTestCase {
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func assertArenaFits(_ app: XCUIApplication, button: String, ratio: CGFloat) {
        let field = app.otherElements["careerMatchField"]
        let board = app.otherElements["matchScoreboard"]
        let control = app.buttons[button]
        XCTAssertTrue(control.isHittable)
        let window = app.windows.firstMatch.frame
        for element in [field, board, control] {
            XCTAssertTrue(element.exists)
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX)
            XCTAssertGreaterThanOrEqual(element.frame.minY, window.minY)
            XCTAssertLessThanOrEqual(element.frame.maxY, window.maxY)
        }
        XCTAssertEqual(field.frame.width / field.frame.height, ratio, accuracy: 0.02)
    }
    @MainActor private func waitForEnabled(_ button: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)], timeout: 5), .completed)
    }

    @MainActor private func train(_ app: XCUIApplication, pitcher: Bool) {
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 5))
        if pitcher {
            app.buttons["trainingPitchPicker"].tap()
            let slider = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "슬라이더")).firstMatch
            XCTAssertTrue(slider.waitForExistence(timeout: 3)); slider.tap()
        }
        app.buttons["startTraining"].tap()
        let field = app.otherElements["trainingField"].firstMatch
        let button = app.buttons["trainingAttempt"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        XCTAssertTrue(button.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(field.exists)
        XCTAssertLessThanOrEqual(field.frame.maxX, window.maxX)
        XCTAssertLessThanOrEqual(button.frame.maxY, window.maxY)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Pitch training" : "Contact training"; shot.lifetime = .keepAlways; add(shot)
        for index in 0..<5 {
            if index == 2 && !pitcher {
                app.terminate(); app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
                XCTAssertFalse(app.buttons["advanceDay"].isEnabled)
                for _ in 0..<5 { app.swipeDown() }
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
            }
            let startAttempt = app.buttons.containing(NSPredicate(format: "identifier == %@ AND label == %@", "trainingAttempt", "\(index + 1)번째 시도 시작")).firstMatch
            XCTAssertTrue(startAttempt.waitForExistence(timeout: 3)); startAttempt.tap()
            let hit = app.buttons.containing(NSPredicate(format: "identifier == %@ AND label == %@", "trainingAttempt", pitcher ? "던지기!" : "타격!")).firstMatch
            XCTAssertTrue(hit.waitForExistence(timeout: 2)); hit.tap()
        }
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let result = app.staticTexts["trainingGrowth"].label
        let resultShot = XCTAttachment(screenshot: app.screenshot()); resultShot.name = pitcher ? "Pitch growth saved" : "Contact growth saved"; resultShot.lifetime = .keepAlways; add(resultShot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"], in: app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].exists)
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, result)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeDown() }
    }

    @MainActor func testCreateBothRolesRelaunchAndEnterSpriteKit() throws {
        let app = XCUIApplication()
        app.launch()
        // This test runs on a dedicated simulator with an empty installation.
        let name = app.textFields["playerName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("NativeBatter")
        if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
        app.buttons["schoolPicker"].tap()
        app.buttons["hs-ref-001"].tap()
        let creationShot = XCTAttachment(screenshot: app.screenshot()); creationShot.name = "Player creation"; creationShot.lifetime = .keepAlways; add(creationShot)
        app.swipeUp(); app.swipeUp()
        let start = app.buttons["createPlayer"]
        XCTAssertTrue(start.waitForExistence(timeout: 3)); start.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homeSchool"].label.contains("경기고"))
        XCTAssertEqual(app.staticTexts["calendarDate"].label, "2026-04-01")
        XCTAssertTrue(app.staticTexts["homeAge"].label.contains("16세 / 고1"))
        reveal(app.buttons["restToday"], in: app)
        train(app, pitcher: false)
        reveal(app.buttons["restToday"], in: app)
        XCTAssertFalse(app.buttons["restToday"].isEnabled)
        XCTAssertFalse(app.buttons["advanceDay"].isEnabled)
        XCTAssertFalse(app.buttons["advanceOffDays"].isEnabled)
        app.buttons["showSeasonSchedule"].tap()
        let lastGame = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "30차전 · 2026-09-22")).firstMatch
        reveal(lastGame, in: app)
        XCTAssertTrue(lastGame.exists)
        let scheduleShot = XCTAttachment(screenshot: app.screenshot()); scheduleShot.name = "Thirty-game schedule"; scheduleShot.lifetime = .keepAlways; add(scheduleShot)
        app.buttons["닫기"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("NativeBatter"))
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 30 / 100")
        XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 완료 · 훈련")
        XCTAssertTrue(app.staticTexts["fixtureGate"].exists)
        let calendarShot = XCTAttachment(screenshot: app.screenshot()); calendarShot.name = "Calendar and persisted rest"; calendarShot.lifetime = .keepAlways; add(calendarShot)
        reveal(app.buttons["openMatch"], in: app)
        app.buttons["openMatch"].tap()
        XCTAssertTrue(app.buttons["demoPitch"].waitForExistence(timeout: 5))
        app.buttons["demoPitch"].tap()
        XCTAssertTrue(app.staticTexts["matchCue"].label.contains("포수 수신"))
        let matchShot = XCTAttachment(screenshot: app.screenshot()); matchShot.name = "SpriteKit practice"; matchShot.lifetime = .keepAlways; add(matchShot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openCareerGame"], in: app)
        app.buttons["openCareerGame"].tap()
        XCTAssertTrue(app.buttons["gameInput-watch"].waitForExistence(timeout: 5))
        assertArenaFits(app, button: "requestGamePitch", ratio: 1)
        let gameShot = XCTAttachment(screenshot: app.screenshot()); gameShot.name = "Native batter game"; gameShot.lifetime = .keepAlways; add(gameShot)
        let aim = app.otherElements["battingAimZone"]
        XCTAssertTrue(aim.exists)
        aim.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.25)).tap()
        XCTAssertNotNil(aim.value as? String)
        XCTAssertNotEqual(aim.value as? String, "가로 50, 세로 50")
        app.buttons["gameInput-swing"].tap()
        app.buttons["requestGamePitch"].tap()
        let take = NSPredicate(format: "label CONTAINS %@", "지켜보기")
        expectation(for: take, evaluatedWith: app.staticTexts["careerGameMessage"])
        waitForExpectations(timeout: 5)
        waitForEnabled(app.buttons["requestGamePitch"])
        app.buttons["requestGamePitch"].tap()
        XCTAssertTrue(app.buttons["gameHit"].waitForExistence(timeout: 2))
        app.buttons["gameHit"].tap()
        XCTAssertTrue(app.buttons["requestGamePitch"].waitForExistence(timeout: 3))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["openCareerGame"], in: app)
        XCTAssertEqual(app.buttons["openCareerGame"].label, "오늘 경기 이어하기")
        app.buttons["openCareerGame"].tap()
        reveal(app.buttons["gameAutomatic"], in: app)
        app.buttons["gameAutomatic"].tap()
        app.buttons["진행하고 결과 저장"].tap()
        XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5))
        reveal(app.buttons["gameReturnHome"], in: app)
        app.buttons["gameReturnHome"].tap()
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["advanceDay"], in: app)
        XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
        app.buttons["advanceDay"].tap()
        let newDate = app.staticTexts["calendarDate"]
        let predicate = NSPredicate(format: "label == %@", "2026-04-02")
        expectation(for: predicate, evaluatedWith: newDate)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 미사용")
        reveal(app.buttons["createOtherRole"], in: app)
        app.buttons["createOtherRole"].tap()
        let pitcherName = app.textFields["playerName"]
        XCTAssertTrue(pitcherName.waitForExistence(timeout: 5)); pitcherName.tap(); pitcherName.typeText("LeftPitcher")
        if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
        app.segmentedControls["throwingHandPicker"].buttons["좌투"].tap()
        app.buttons["randomSchool"].tap()
        app.swipeUp(); app.swipeUp(); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("LeftPitcher"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "좌투")).firstMatch.exists)
        let homeShot = XCTAttachment(screenshot: app.screenshot()); homeShot.name = "Pitcher saved home"; homeShot.lifetime = .keepAlways; add(homeShot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.segmentedControls["homeRolePicker"], in: app)
        XCTAssertTrue(app.segmentedControls["homeRolePicker"].exists)
        app.segmentedControls["homeRolePicker"].buttons["투수 · LeftPitcher"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("LeftPitcher"))
        for _ in 0..<5 { app.swipeDown() }
        train(app, pitcher: true)
        reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
        XCTAssertTrue(app.buttons["gamePitch"].waitForExistence(timeout: 5))
        assertArenaFits(app, button: "gamePitch", ratio: 1219.0 / 1290)
        XCTAssertTrue(app.otherElements["pitchingTargetZone"].exists)
        let pitchShot = XCTAttachment(screenshot: app.screenshot()); pitchShot.name = "Native pitcher game"; pitchShot.lifetime = .keepAlways; add(pitchShot)
        app.buttons["gamePitch"].tap()
        XCTAssertTrue(app.buttons["gameRelease"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["gameAutomatic"].isEnabled)
        app.buttons["gameRelease"].tap()
        XCTAssertTrue(app.buttons["gamePitch"].waitForExistence(timeout: 3))
        waitForEnabled(app.buttons["gameAutomatic"])
        reveal(app.buttons["gameAutomatic"], in: app); app.buttons["gameAutomatic"].tap()
        app.buttons["진행하고 결과 저장"].tap()
        XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5))
        reveal(app.buttons["gameReturnHome"], in: app); app.buttons["gameReturnHome"].tap()
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["advanceDay"], in: app); XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
    }
}
