import XCTest

final class SupportInformationFlowTests: XCTestCase {
    @MainActor func testSupportRoutesBothRolesPreserveCareerState() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["roomProfile"].tap()
                app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { app.buttons["closeRoomDetail"].tap() }
            }
            let before = careerStatus(app)
            openSupport(app)
            capture(app, pitcher ? "support-pitcher-index" : "support-batter-index")
            for topic in ["privacy", "terms", "children", "dataRequests", "refund", "licenses"] {
                let row = app.buttons["supportTopic-" + topic]
                reveal(row, app); row.tap()
                XCTAssertTrue(app.buttons["supportTopicBack"].waitForExistence(timeout: 5))
                let first = app.descendants(matching: .any).matching(identifier: "supportSection-" + topic + "-0").firstMatch
                XCTAssertTrue(first.waitForExistence(timeout: 5))
                if !pitcher { capture(app, "support-" + topic) }
                if topic == "refund" {
                    let help = app.descendants(matching: .any).matching(identifier: "supportRefundRequest").firstMatch
                    reveal(help, app); XCTAssertTrue(help.isHittable)
                    XCTAssertTrue(help.label.contains("Apple"))
                    XCTAssertGreaterThanOrEqual(help.frame.height, 44)
                    capture(app, "support-refund-links")
                }
                if topic == "licenses" {
                    let license = app.staticTexts["supportFontLicense"]
                    XCTAssertTrue(license.exists)
                    XCTAssertTrue(license.label.contains("SIL OPEN FONT LICENSE"))
                }
                app.buttons["supportTopicBack"].tap()
                XCTAssertTrue(app.buttons["supportBack"].waitForExistence(timeout: 5))
            }
            app.buttons["supportBack"].tap()
            XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 5))
            app.buttons["closeSettings"].tap()
            XCTAssertTrue(app.buttons["clubhouse-settings"].waitForExistence(timeout: 5))
            XCTAssertEqual(careerStatus(app), before)
        }
    }

    @MainActor func testLargestTextSupportAndRefundRemainReachable() {
        continueAfterFailure = false
        let app = launch(large: true), before = careerStatus(app)
        openSupport(app)
        capture(app, "support-large-index")
        for topic in ["privacy", "terms", "refund", "children", "dataRequests", "licenses"] {
            let button = app.buttons["supportTopic-" + topic]
            reveal(button, app)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minX, 0)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        let refund = app.buttons["supportTopic-refund"]
        reveal(refund, app); refund.tap()
        XCTAssertTrue(app.buttons["supportTopicBack"].waitForExistence(timeout: 5))
        let action = app.descendants(matching: .any).matching(identifier: "supportRefundRequest").firstMatch
        reveal(action, app); XCTAssertTrue(action.isHittable)
        capture(app, "support-large-refund")
        app.buttons["supportTopicBack"].tap()
        XCTAssertTrue(app.buttons["supportBack"].waitForExistence(timeout: 5))
        app.buttons["supportBack"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 5))
        app.buttons["closeSettings"].tap()
        XCTAssertEqual(careerStatus(app), before)
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        return app
    }
    @MainActor private func careerStatus(_ app: XCUIApplication) -> [String] {
        ["homePlayerName", "calendarDate", "homeFatigue", "calendarAction"].map {
            let element = app.descendants(matching: .any).matching(identifier: $0).firstMatch
            XCTAssertTrue(element.exists, $0)
            return element.label
        }
    }
    @MainActor private func openSupport(_ app: XCUIApplication) {
        let settings = app.buttons["clubhouse-settings"]
        reveal(settings, app); settings.tap()
        let support = app.buttons["openSupportInformation"]
        XCTAssertTrue(support.waitForExistence(timeout: 8))
        reveal(support, app); support.tap()
        XCTAssertTrue(app.staticTexts["supportPendingNotice"].waitForExistence(timeout: 5))
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<28 {
            let rect = element.exists ? element.frame : .zero
            if element.exists && element.isHittable && rect.minY >= 110 && rect.maxY < app.frame.maxY - 15 { return }
            let down = element.exists && rect.minY < 110
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).press(forDuration: 0.04,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: down ? 0.85 : 0.3)))
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "v78-" + name; image.lifetime = .keepAlways; add(image)
    }
}
