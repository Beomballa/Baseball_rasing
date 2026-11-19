import XCTest

final class CreationPortraitFlowTests: XCTestCase {
    @MainActor func testBothRolesSelectPartsCreateAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            let session = UUID().uuidString, name = pitcher ? "FacePitch" : "FaceBat"
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-management-empty-verification", "-v56-disk-session", session]
            app.launch()
            prepare(app, name: name, pitcher: pitcher)
            app.buttons["creationSection-appearance"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "creationMotionPreview").firstMatch.waitForExistence(timeout: 15))
            capture(app, "V202-\(name)-default-bust")
            select("appearanceTab-face", app)
            for id in ["portrait-face-2", "portrait-eyes-1", "portrait-gaze-1", "portrait-ears-2"] {
                select(id, app); XCTAssertTrue(app.buttons[id].isSelected)
            }
            capture(app, "V202-\(name)-part-thumbnails")
            select("appearanceTab-hair", app)
            select(pitcher ? "hairStyle-7" : "hairStyle-1", app)
            select("appearanceTab-face", app)
            for id in ["portrait-face-2", "portrait-eyes-1", "portrait-gaze-1", "portrait-ears-2"] {
                reveal(app.buttons[id], app); XCTAssertTrue(app.buttons[id].isSelected, "다른 부위를 바꿔도 선택을 유지한다")
            }
            let preview = app.descendants(matching: .any).matching(identifier: "creationMotionPreview").firstMatch
            reveal(preview, app)
            let value = preview.value as? String ?? ""
            for label in ["각진형", "둥근 눈", "올라간 눈매", "돌출 귀"] { XCTAssertTrue(value.contains(label), value) }
            capture(app, "V202-\(name)-selected-bust")
            app.buttons["이 모습으로 계속"].tap()
            let create = app.buttons["createPlayer"]; reveal(create, app)
            capture(app, "V202-\(name)-review")
            create.tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(name))
            capture(app, "V202-\(name)-created-home")
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(name))
            capture(app, "V202-\(name)-reopened-home")
        }
    }

    @MainActor func testLargestTextPartsAndNextRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-management-empty-verification",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]
        app.launch(); prepare(app, name: "LargeFace", pitcher: false)
        app.buttons["creationSection-appearance"].tap()
        select("appearanceTab-face", app)
        for id in ["portrait-face-3", "portrait-eyes-2", "portrait-gaze-2", "portrait-ears-1"] {
            select(id, app)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
            XCTAssertTrue(app.buttons[id].isSelected)
        }
        capture(app, "V202-largest-text-parts")
        let next = app.buttons["이 모습으로 계속"]
        XCTAssertTrue(next.isHittable); next.tap()
        XCTAssertTrue(app.staticTexts["creationReadiness"].waitForExistence(timeout: 10))
        capture(app, "V202-largest-text-review")
    }

    @MainActor private func prepare(_ app: XCUIApplication, name: String, pitcher: Bool) {
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 30))
        if pitcher { reveal(app.buttons["role-pitcher"], app); app.buttons["role-pitcher"].tap() }
        let field = app.textFields["playerName"]; reveal(field, app); field.tap(); field.typeText(name)
        app.buttons["입력 완료"].tap()
        reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
        let school = app.buttons["hs-ref-001"]
        XCTAssertTrue(school.waitForExistence(timeout: 10)); reveal(school, app); school.tap()
    }

    @MainActor private func select(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]; reveal(button, app); XCTAssertTrue(button.isHittable, id); button.tap()
    }

    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let editor = app.scrollViews["appearanceEditorScroll"]
        let scroll = editor.exists ? editor : app.scrollViews.firstMatch
        for _ in 0..<18 {
            let top = max(scroll.frame.minY, app.buttons["creationSection-appearance"].frame.maxY) + 8
            let next = app.buttons["이 모습으로 계속"]
            let bottom = next.exists ? min(scroll.frame.maxY, next.frame.minY) - 8 : scroll.frame.maxY - 8
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: (top + bottom) / 2))
            let direction = element.exists && element.frame.midY < top ? 1.0 : -1.0
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * min(180, (bottom - top) / 3))))
        }
        XCTFail("선택 요소를 표시하지 못함: \(element.identifier)")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
