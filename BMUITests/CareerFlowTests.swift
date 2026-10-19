import XCTest

final class CareerFlowTests: XCTestCase {
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
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("NativeBatter"))
        app.swipeUp()
        app.buttons["openMatch"].tap()
        XCTAssertTrue(app.buttons["demoPitch"].waitForExistence(timeout: 5))
        app.buttons["demoPitch"].tap()
        XCTAssertTrue(app.staticTexts["matchCue"].label.contains("포수 수신"))
        let matchShot = XCTAttachment(screenshot: app.screenshot()); matchShot.name = "SpriteKit practice"; matchShot.lifetime = .keepAlways; add(matchShot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.swipeUp()
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
        app.swipeUp()
        XCTAssertTrue(app.segmentedControls["homeRolePicker"].exists)
        app.segmentedControls["homeRolePicker"].buttons["투수 · LeftPitcher"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("LeftPitcher"))
    }
}
