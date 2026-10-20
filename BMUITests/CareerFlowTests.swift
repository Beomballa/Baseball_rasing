import XCTest

final class CareerFlowTests: XCTestCase {
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if element.exists {
                let frame = element.frame
                if !frame.isEmpty && frame.maxY < app.windows.firstMatch.frame.midY {
                    app.swipeDown(); continue
                }
            }
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
        var previousBreakdown = ""
        for index in 0..<5 {
            if index == 2 && !pitcher {
                app.terminate(); app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
                XCTAssertFalse(app.buttons["advanceDay"].isEnabled)
                reveal(app.staticTexts["traitLocked"], in: app)
                XCTAssertTrue(app.staticTexts["traitLocked"].exists)
                expandHomeDetails("traitDetails", in: app)
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traitToggle-")).firstMatch.isEnabled)
                for _ in 0..<5 { app.swipeDown() }
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
                XCTAssertEqual(app.staticTexts["contactScoreBreakdown"].label, previousBreakdown)
            }
            let startAttempt = app.buttons.containing(NSPredicate(format: "identifier == %@ AND label == %@", "trainingAttempt", "\(index + 1)번째 시도 시작")).firstMatch
            XCTAssertTrue(startAttempt.waitForExistence(timeout: 3)); startAttempt.tap()
            let hit = app.buttons.containing(NSPredicate(format: "identifier == %@ AND label == %@", "trainingAttempt", pitcher ? "던지기!" : "타격!")).firstMatch
            XCTAssertTrue(hit.waitForExistence(timeout: 2)); hit.tap()
            if !pitcher {
                XCTAssertTrue(app.staticTexts["contactScoreBreakdown"].waitForExistence(timeout:3))
                previousBreakdown = app.staticTexts["contactScoreBreakdown"].label
                XCTAssertTrue(previousBreakdown.contains("조준")); XCTAssertTrue(previousBreakdown.contains("타이밍"))
                XCTAssertTrue(app.staticTexts["contactTotalScore"].exists)
                if index < 4 { XCTAssertTrue(app.buttons["trainingAttempt"].isHittable) }
                if index == 0 {
                    let feedback = XCTAttachment(screenshot: app.screenshot()); feedback.name = "Contact score breakdown"; feedback.lifetime = .keepAlways; add(feedback)
                }
            }
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

    @MainActor private func trainAbility(_ app: XCUIApplication, power: Bool) {
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let picker = app.segmentedControls["trainingKindPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3)); picker.buttons[power ? "파워" : "선구안"].tap()
        app.buttons["startTraining"].tap()
        let field = app.otherElements["trainingField"].firstMatch
        let action = app.buttons["trainingAttempt"]
        XCTAssertTrue(action.waitForExistence(timeout: 3)); XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThanOrEqual(field.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(field.frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.windows.firstMatch.frame.maxY)
        if power {
            app.buttons["powerForceUp"].tap(); app.buttons["powerAngleUp"].tap()
        } else {
            action.tap()
            XCTAssertTrue(app.buttons["trainingCallStrike"].waitForExistence(timeout: 3))
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = power ? "Power training" : "Discipline training"; shot.lifetime = .keepAlways; add(shot)
        for index in 0..<5 {
            if power && index == 2 {
                app.terminate(); app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
                XCTAssertFalse(app.segmentedControls["trainingKindPicker"].exists)
            }
            if power { app.buttons["trainingAttempt"].tap() }
            else {
                if index > 0 { app.buttons["trainingAttempt"].tap() }
                app.buttons["trainingCallStrike"].tap()
            }
        }
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let saved = app.staticTexts["trainingGrowth"].label
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = power ? "Power growth saved" : "Discipline growth saved"; result.lifetime = .keepAlways; add(result)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"], in: app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].label.contains(power ? "파워" : "선구안"))
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, saved)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
        XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
        app.buttons["advanceDay"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "오늘 행동 미사용"), object: app.staticTexts["calendarAction"])], timeout: 5), .completed)
    }

    @MainActor private func trainField(_ app: XCUIApplication, kind: String, pitcher: Bool = false) {
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let category = app.segmentedControls["trainingCategoryPicker"]
        XCTAssertTrue(category.waitForExistence(timeout: 3)); category.buttons["주루·수비"].tap()
        app.segmentedControls["trainingKindPicker"].buttons[kind].tap()
        app.buttons["startTraining"].tap()
        let action = app.buttons["trainingAttempt"]
        XCTAssertTrue(action.waitForExistence(timeout: 3)); XCTAssertTrue(action.isHittable)
        let field = app.otherElements["trainingField"].firstMatch
        XCTAssertLessThanOrEqual(field.frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertGreaterThanOrEqual(field.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.windows.firstMatch.frame.maxY)
        if kind == "스피드" {
            action.tap(); app.buttons["sprintLeft"].tap()
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            reveal(app.buttons["openTraining"], in: app)
            XCTAssertTrue(app.buttons["openTraining"].label.contains("0/5")); app.buttons["openTraining"].tap()
        } else if kind == "수비" {
            let board=app.otherElements["trainingField"].firstMatch
            board.coordinate(withNormalizedOffset:CGVector(dx:0.3,dy:0.3)).tap()
        } else {
            app.buttons["throwAngleUp"].tap(); app.buttons["throwForceUp"].tap()
        }
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name=(pitcher ? "Pitcher " : "")+kind+" training";shot.lifetime = .keepAlways;add(shot)
        for round in 0..<5 {
            if kind == "스피드" {
                app.buttons["trainingAttempt"].tap()
                if round==0 { app.buttons["sprintLeft"].tap(); app.buttons["sprintRight"].tap() }
                if round < 4 {
                    XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:app.buttons["trainingAttempt"])],timeout:7),.completed)
                } else { XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:7)) }
            } else {
                if kind == "송구" { app.segmentedControls["throwBasePicker"].buttons[["1루","2루","홈","3루","2루"][round]].tap() }
                app.buttons["trainingAttempt"].tap()
            }
        }
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:5))
        let result=app.staticTexts["trainingGrowth"].label
        let saved=XCTAttachment(screenshot:app.screenshot());saved.name=(pitcher ? "Pitcher " : "")+kind+" growth";saved.lifetime = .keepAlways;add(saved)
        app.navigationBars.buttons.element(boundBy:0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"],in:app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].label.contains(kind))
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"],in:app);app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:3));XCTAssertEqual(app.staticTexts["trainingGrowth"].label,result)
        app.navigationBars.buttons.element(boundBy:0).tap()
        reveal(app.buttons["restToday"],in:app);XCTAssertFalse(app.buttons["restToday"].isEnabled)
        XCTAssertTrue(app.buttons["advanceDay"].isEnabled);app.buttons["advanceDay"].tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","오늘 행동 미사용"),object:app.staticTexts["calendarAction"])],timeout:5),.completed)
    }

    @MainActor private func trainRaw(_ app: XCUIApplication, kind: String, pitcher: Bool, nextDay: Bool = true) {
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.segmentedControls["trainingCategoryPicker"].buttons[pitcher ? "투구·멘탈" : "멘탈"].tap()
        app.segmentedControls["trainingKindPicker"].buttons[kind].tap()
        app.buttons["startTraining"].tap()
        let action = app.buttons[kind == "멘탈" ? "mentalChoice-0" : "trainingAttempt"]
        XCTAssertTrue(action.waitForExistence(timeout: 3)); XCTAssertTrue(action.isHittable)
        let field = app.otherElements["trainingField"].firstMatch, window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(field.frame.minX, window.minX); XCTAssertLessThanOrEqual(field.frame.maxX, window.maxX)
        XCTAssertLessThanOrEqual(action.frame.maxY, window.maxY)
        if kind == "멘탈" { XCTAssertLessThanOrEqual(app.buttons["mentalChoice-2"].frame.maxY, window.maxY) }
        if kind == "구속" || kind == "구위" { app.buttons["rawForceUp"].tap(); app.buttons["rawAngleUp"].tap() }
        if kind == "제구" { field.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)).tap() }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = (pitcher ? "Pitcher " : "Batter ") + kind + " raw training"; shot.lifetime = .keepAlways; add(shot)
        for round in 0..<5 {
            if !pitcher && round == 2 {
                let scenario = app.otherElements["mentalScenario"].label
                app.terminate(); app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
                XCTAssertEqual(app.otherElements["mentalScenario"].label, scenario)
            }
            if kind == "멘탈" { app.buttons["mentalChoice-0"].tap() }
            else {
                app.buttons["trainingAttempt"].tap()
                if kind == "지구력" {
                    app.buttons["sprintLeft"].tap(); app.buttons["sprintRight"].tap()
                    if round < 4 {
                        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["trainingAttempt"])], timeout: 7), .completed)
                    } else { XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 7)) }
                }
            }
        }
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let saved = app.staticTexts["trainingGrowth"].label
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = kind + " raw growth saved"; result.lifetime = .keepAlways; add(result)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"], in: app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].label.contains(kind))
        expandHomeDetails("homeAbilityDetails", in: app)
        let identifier = ["구속":"homeVelocity", "제구":"homeControl", "구위":"homeStuff", "지구력":"homeStamina", "멘탈":"homeMental"][kind]!
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        reveal(row, in: app)
        XCTAssertTrue(row.label.contains(saved.components(separatedBy: "→").last!.trimmingCharacters(in: .whitespaces)))
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 3)); XCTAssertEqual(app.staticTexts["trainingGrowth"].label, saved)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
        if nextDay {
            XCTAssertTrue(app.buttons["advanceDay"].isEnabled); app.buttons["advanceDay"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "오늘 행동 미사용"), object: app.staticTexts["calendarAction"])], timeout: 5), .completed)
        }
    }

    @MainActor private func expandHomeDetails(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        reveal(button, in: app)
        if button.value as? String == "접힘" { button.tap() }
    }

    @MainActor private func checkTraitManagement(_ app: XCUIApplication, pitcher: Bool) {
        expandHomeDetails("traitDetails", in: app)
        let count = app.staticTexts["traitActiveCount"]
        reveal(count, in: app); XCTAssertEqual(count.label, "활성 1 / 3")
        let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traitToggle-"))
        XCTAssertEqual(buttons.count, 1)
        let id = buttons.firstMatch.identifier
        let button = app.buttons[id]
        reveal(button, in: app); XCTAssertTrue(button.isEnabled); button.tap()
        XCTAssertEqual(count.label, "활성 0 / 3")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Pitcher trait management" : "Batter trait management"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        if pitcher {
            reveal(app.buttons["homeRole-pitcher"], in: app)
            app.buttons["homeRole-pitcher"].tap()
        }
        for _ in 0..<5 { app.swipeDown() }
        expandHomeDetails("traitDetails", in: app)
        reveal(count, in: app); XCTAssertEqual(count.label, "활성 0 / 3")
        reveal(app.buttons[id], in: app); app.buttons[id].tap()
        XCTAssertEqual(count.label, "활성 1 / 3")
        for _ in 0..<5 { app.swipeDown() }
        reveal(app.staticTexts["calendarAction"], in: app)
        XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 미사용")
        for _ in 0..<5 { app.swipeDown() }
    }

    @MainActor private func chooseArchetype(_ app: XCUIApplication, pitcher: Bool) {
        let options = pitcher ? ["control", "stuff", "endurance"] : ["contact", "onBase", "slugger"]
        let labels = pitcher ? ["제구형", "구위형", "지구력형"] : ["컨택형", "출루형", "장타형"]
        for (code,label) in zip(options,labels) {
            reveal(app.buttons["archetype-" + code],in:app); app.buttons["archetype-" + code].tap()
            XCTAssertTrue(app.staticTexts["archetypePreviewTitle"].label.contains(label))
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Pitcher archetype preview" : "Batter archetype preview"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func checkAbilities(_ app: XCUIApplication, pitcher: Bool) {
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["homeArchetype"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["homeArchetype"].label,pitcher ? "지구력형" : "장타형")
        expandHomeDetails("homeAbilityDetails", in: app)
        let values = pitcher ? [("homeVelocity","52"),("homeControl","54"),("homeStuff","53"),("homeStamina","65"),("homeBreaking","49.8"),("homeMental","55")] : [("homeMental","55")]
        for (identifier,value) in values {
            let row = app.descendants(matching:.any).matching(identifier:identifier).firstMatch
            reveal(row,in:app); XCTAssertTrue(row.exists); XCTAssertTrue(row.label.contains(value),row.label)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Pitcher ability home" : "Batter ability home"; shot.lifetime = .keepAlways; add(shot)
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
        reveal(app.buttons["schoolPicker"], in: app); app.buttons["schoolPicker"].tap()
        app.buttons["hs-ref-001"].tap()
        let creationShot = XCTAttachment(screenshot: app.screenshot()); creationShot.name = "Player creation"; creationShot.lifetime = .keepAlways; add(creationShot)
        chooseArchetype(app,pitcher:false)
        let start = app.buttons["createPlayer"]
        reveal(start,in:app)
        XCTAssertTrue(start.waitForExistence(timeout: 3)); start.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homeSchool"].label.contains("경기고"))
        XCTAssertEqual(app.staticTexts["calendarDate"].label, "2026-04-01")
        XCTAssertTrue(app.staticTexts["homeAge"].label.contains("16세 / 고1"))
        checkAbilities(app,pitcher:false)
        checkTraitManagement(app,pitcher:false)
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
        trainAbility(app, power: true)
        trainAbility(app, power: false)
        trainField(app,kind:"스피드")
        trainField(app,kind:"수비")
        trainField(app,kind:"송구")
        trainRaw(app, kind:"멘탈", pitcher:false, nextDay:false)
        reveal(app.buttons["createOtherRole"], in: app)
        app.buttons["createOtherRole"].tap()
        let pitcherName = app.textFields["playerName"]
        XCTAssertTrue(pitcherName.waitForExistence(timeout: 5)); pitcherName.tap(); pitcherName.typeText("LeftPitcher")
        if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
        app.buttons["hand-left"].tap()
        reveal(app.buttons["randomSchool"], in: app); app.buttons["randomSchool"].tap()
        chooseArchetype(app,pitcher:true)
        reveal(app.buttons["createPlayer"],in:app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("LeftPitcher"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "좌투")).firstMatch.exists)
        checkAbilities(app,pitcher:true)
        checkTraitManagement(app,pitcher:true)
        let homeShot = XCTAttachment(screenshot: app.screenshot()); homeShot.name = "Pitcher saved home"; homeShot.lifetime = .keepAlways; add(homeShot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["homeRole-pitcher"], in: app)
        XCTAssertTrue(app.buttons["homeRole-pitcher"].exists)
        app.buttons["homeRole-pitcher"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("LeftPitcher"))
        checkAbilities(app,pitcher:true)
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
        app.buttons["advanceDay"].tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","오늘 행동 미사용"),object:app.staticTexts["calendarAction"])],timeout:5),.completed)
        trainField(app,kind:"송구",pitcher:true)
        for kind in ["구속", "제구", "구위", "지구력", "멘탈"] {
            trainRaw(app,kind:kind,pitcher:true,nextDay:kind != "멘탈")
        }
    }
}

extension CareerFlowTests {
    @MainActor func testCreationBoardSelectionsAndPersistence() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 10))
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Creation batter board"; top.lifetime = .keepAlways; add(top)
        app.buttons["role-pitcher"].tap()
        XCTAssertTrue(app.buttons["hand-right"].isSelected)
        XCTAssertFalse(app.buttons["position-SS"].exists)
        app.buttons["role-batter"].tap()
        XCTAssertTrue(app.buttons["position-CF"].isSelected)
        reveal(app.buttons["schoolPicker"], in: app); app.buttons["schoolPicker"].tap()
        XCTAssertTrue(app.textFields["schoolSearch"].waitForExistence(timeout: 3))
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["schoolPicker"].waitForExistence(timeout: 3))
        reveal(app.buttons["createPlayer"], in: app); app.buttons["createPlayer"].tap()
        reveal(app.staticTexts["creationError"], in: app)
        XCTAssertTrue(app.staticTexts["creationError"].exists)
        reveal(app.textFields["playerName"], in: app)
        app.textFields["playerName"].tap(); app.textFields["playerName"].typeText("BoardBatter")
        XCTAssertFalse(app.staticTexts["creationError"].exists)
        app.buttons["입력 완료"].tap()
        let number = app.textFields["jerseyNumber"]; number.doubleTap(); number.typeText("27"); XCTAssertEqual(number.value as? String, "27")
        app.buttons["입력 완료"].tap()
        reveal(app.buttons["position-SS"], in: app); app.buttons["position-SS"].tap()
        XCTAssertTrue(app.buttons["position-SS"].isSelected)
        reveal(app.buttons["schoolPicker"], in: app); app.buttons["schoolPicker"].tap()
        let search = app.textFields["schoolSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["schoolSearchEmpty"].waitForExistence(timeout: 3))
        app.buttons["검색 지우기"].tap(); app.buttons["검색 완료"].tap()
        let schools = XCTAttachment(screenshot: app.screenshot()); schools.name = "Creation school board"; schools.lifetime = .keepAlways; add(schools)
        XCTAssertTrue(app.buttons["hs-ref-001"].waitForExistence(timeout: 3)); app.buttons["hs-ref-001"].tap()
        reveal(app.buttons["archetype-slugger"], in: app); app.buttons["archetype-slugger"].tap()
        XCTAssertTrue(app.staticTexts["archetypePreviewTitle"].label.contains("장타형"))
        for label in ["피부 4", "머리색 3", "유니폼 5"] {
            reveal(app.buttons[label], in: app); app.buttons[label].tap(); XCTAssertTrue(app.buttons[label].isSelected)
        }
        for id in ["hairStyle-2", "expression-2"] { reveal(app.buttons[id], in: app); app.buttons[id].tap(); XCTAssertTrue(app.buttons[id].isSelected) }
        let appearance = XCTAttachment(screenshot: app.screenshot()); appearance.name = "Creation appearance board"; appearance.lifetime = .keepAlways; add(appearance)
        reveal(app.buttons["createPlayer"], in: app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["homePlayerName"].label, "BoardBatter  #27")
        XCTAssertTrue(app.staticTexts["homeSchool"].label.contains("경기고"))
        XCTAssertTrue(app.staticTexts["homeAge"].label.contains("유격수"))
        XCTAssertTrue(app.staticTexts["homeArchetype"].label.contains("장타형"))
        let day = app.staticTexts["calendarDate"].label, fatigue = app.staticTexts["homeFatigue"].label
        reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["role-batter"].exists)
        app.buttons["닫기"].tap()
        XCTAssertEqual(app.staticTexts["calendarDate"].label, day)
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
        let pitcherName = app.textFields["playerName"]
        XCTAssertTrue(pitcherName.waitForExistence(timeout: 3)); pitcherName.tap(); pitcherName.typeText("BoardPitcher"); app.buttons["입력 완료"].tap()
        reveal(app.buttons["hand-left"], in: app); app.buttons["hand-left"].tap()
        XCTAssertTrue(app.buttons["hand-left"].isSelected)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(app.buttons["hand-left"].frame.minX, window.minX)
        XCTAssertLessThanOrEqual(app.buttons["hand-left"].frame.maxX, window.maxX)
        let large = XCTAttachment(screenshot: app.screenshot()); large.name = "Creation pitcher large text"; large.lifetime = .keepAlways; add(large)
        reveal(app.buttons["randomSchool"], in: app); app.buttons["randomSchool"].tap()
        reveal(app.buttons["archetype-endurance"], in: app); app.buttons["archetype-endurance"].tap()
        XCTAssertTrue(app.buttons["archetype-endurance"].isSelected)
        reveal(app.buttons["createPlayer"], in: app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("BoardPitcher"))
        XCTAssertTrue(app.staticTexts["homeArchetype"].label.contains("지구력형"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "좌투")).firstMatch.exists)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["homeRole-batter"], in: app); app.buttons["homeRole-batter"].tap()
        XCTAssertEqual(app.staticTexts["homePlayerName"].label, "BoardBatter  #27")
        XCTAssertEqual(app.staticTexts["calendarDate"].label, day)
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        XCTAssertFalse(app.buttons["createOtherRole"].exists)
    }

    @MainActor private func createDashboardSample(_ app: XCUIApplication, name: String) {
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
        reveal(app.buttons["randomSchool"], in: app); app.buttons["randomSchool"].tap()
        reveal(app.buttons["createPlayer"], in: app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
    }
    @MainActor func testHomeDashboardBothRolesAndLargeText() throws {
        let app = XCUIApplication(); app.launch()
        if app.textFields["playerName"].waitForExistence(timeout: 2) { createDashboardSample(app, name: "HomeBatter") }
        if !app.buttons["homeRole-pitcher"].exists {
            reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
            createDashboardSample(app, name: "HomePitcher")
        }
        var savedDates = [String: String](), savedFatigue = [String: String]()
        for role in ["batter", "pitcher"] {
            reveal(app.buttons["homeRole-" + role], in: app); app.buttons["homeRole-" + role].tap()
            let window = app.windows.firstMatch.frame
            for id in ["openTraining", "restToday", "advanceDay"] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, id)
                XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX)
                XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX)
                XCTAssertLessThanOrEqual(button.frame.maxY, window.maxY)
            }
            savedDates[role] = app.staticTexts["calendarDate"].label
            savedFatigue[role] = app.staticTexts["homeFatigue"].label
            let first = XCTAttachment(screenshot: app.screenshot()); first.name = "Native home top " + role; first.lifetime = .keepAlways; add(first)
            reveal(app.buttons["homeAbilityDetails"], in: app)
            XCTAssertEqual(app.buttons["homeAbilityDetails"].value as? String, "접힘")
            let graph = XCTAttachment(screenshot: app.screenshot()); graph.name = "Native home graph " + role; graph.lifetime = .keepAlways; add(graph)
            expandHomeDetails("homeAbilityDetails", in: app)
            let value = app.descendants(matching: .any).matching(identifier: role == "batter" ? "homeContact" : "homeVelocity").firstMatch
            reveal(value, in: app); XCTAssertTrue(value.exists)
            reveal(app.buttons["homeAbilityDetails"], in: app); app.buttons["homeAbilityDetails"].tap()
            reveal(app.buttons["traitDetails"], in: app)
            XCTAssertEqual(app.buttons["traitDetails"].value as? String, "접힘")
            expandHomeDetails("traitDetails", in: app)
            XCTAssertEqual(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traitCard-")).count, 3)
            XCTAssertEqual(app.staticTexts["calendarDate"].label, savedDates[role])
            XCTAssertEqual(app.staticTexts["homeFatigue"].label, savedFatigue[role])
        }
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        for role in ["batter", "pitcher"] {
            reveal(app.buttons["homeRole-" + role], in: app); app.buttons["homeRole-" + role].tap()
            let value = app.descendants(matching: .any).matching(identifier: role == "batter" ? "homeContact" : "homeVelocity").firstMatch
            reveal(value, in: app); XCTAssertTrue(value.isHittable)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(value.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(value.frame.maxX, window.maxX)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native home large text " + role; shot.lifetime = .keepAlways; add(shot)
            XCTAssertEqual(app.staticTexts["calendarDate"].label, savedDates[role])
            XCTAssertEqual(app.staticTexts["homeFatigue"].label, savedFatigue[role])
        }
        app.terminate(); app.launchArguments = []; app.launch()
    }
}
