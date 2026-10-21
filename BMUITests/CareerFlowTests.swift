import XCTest

final class CareerFlowTests: XCTestCase {
    @MainActor func testPitchCatchJudgmentLocksNextPitchAndResumesSavedCount() throws {
        let app = XCUIApplication(); app.launch()
        app.buttons["role-pitcher"].tap(); app.buttons["hand-left"].tap(); createDashboardSample(app, name: "CatchPitch", motionStyle: true)
        reveal(app.buttons["restToday"], in: app); app.buttons["restToday"].tap()
        reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
        XCTAssertTrue(app.buttons["gamePitch"].waitForExistence(timeout: 5))
        assertArenaFits(app, button: "gamePitch", ratio: 1219.0 / 1290)
        let initialPitchCount = app.staticTexts["boardPitchCount"].label
        app.buttons["gamePitch"].tap(); app.buttons["gameRelease"].tap()
        XCTAssertFalse(app.buttons["gameAutomatic"].isEnabled)
        let toast = app.descendants(matching: .any).matching(identifier: "pitchJudgmentToast").firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["gamePitch"].isEnabled)
        let field = app.otherElements["careerMatchField"].frame
        XCTAssertLessThan(toast.frame.maxY, field.minY + field.height * 0.35)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Pitch judgment above catcher"; shot.lifetime = .keepAlways; add(shot)
        waitForEnabled(app.buttons["gamePitch"], timeout: 15)
        let savedCount = app.otherElements["careerGameCount"].label
        XCTAssertNotEqual(app.staticTexts["boardPitchCount"].label, initialPitchCount)
        let savedPitchCount = app.staticTexts["boardPitchCount"].label
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
        XCTAssertTrue(app.buttons["gamePitch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["careerGameCount"].label, savedCount)
        XCTAssertEqual(app.staticTexts["boardPitchCount"].label, savedPitchCount)
        XCTAssertFalse(toast.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["openMatch"], in: app); app.buttons["openMatch"].tap()
        let demo = app.buttons["demoPitch"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5)); demo.tap()
        XCTAssertFalse(demo.isEnabled)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "수신 완료"), object: app.staticTexts["matchCue"])], timeout: 4), .completed)
        waitForEnabled(demo)
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.name = "Legacy practice receiving lock and board"; preview.lifetime = .keepAlways; add(preview)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["openTrainingPractice"], in: app); app.buttons["openTrainingPractice"].tap()
        app.buttons["practiceGeneralTraining"].tap(); app.buttons["trainingCategory-2"].tap()
        app.buttons["trainingKind-stamina"].tap(); app.buttons["startTraining"].tap()
        let meter = app.progressIndicators["sprintProgress"]
        let initialProgress = meter.value as? String; XCTAssertNotNil(initialProgress)
        let running = app.buttons["trainingAttempt"]; running.tap()
        app.buttons["sprintLeft"].tap(); app.buttons["sprintRight"].tap()
        waitForEnabled(running, timeout: 8)
        XCTAssertEqual(meter.value as? String, initialProgress, "다음 시도 준비 막대는0으로 복원됩니다")
        let track = XCTAttachment(screenshot: app.screenshot()); track.name = "Stamina next attempt resets visible progress"; track.lifetime = .keepAlways; add(track)
    }

    @MainActor func testAllTrainingKindsCompleteMotionThenFeedbackInOwnPlayerPractice() throws {
        let app = XCUIApplication(); createOwnPracticePlayers(app)
        let roles: [(String, [(String, Int)])] = [
            ("타자", [("contact",0),("power",0),("discipline",0),("speed",1),("defense",1),("arm",1),("mental",2)]),
            ("투수", [("pitch",0),("velocity",2),("control",2),("stuff",2),("stamina",2)])
        ]
        for (role, kinds) in roles {
            app.segmentedControls["practiceRole"].buttons[role].tap()
            app.buttons["practiceGeneralTraining"].tap()
            for (kind, category) in kinds {
                app.buttons["trainingCategory-\(category)"].tap()
                if kind != "pitch" { app.buttons["trainingKind-" + kind].tap() }
                app.buttons["startTraining"].tap()
                let ready = XCTAttachment(screenshot: app.screenshot()); ready.name = "Training audit " + kind; ready.lifetime = .keepAlways; add(ready)
                let action = app.buttons[kind == "mental" ? "mentalChoice-0" : "trainingAttempt"]
                for round in 0..<5 {
                    waitForEnabled(action, timeout: 8); XCTAssertTrue(action.isHittable); action.tap()
                    if ["pitch", "contact"].contains(kind) { action.tap() }
                    if kind == "discipline" { app.buttons["trainingCallBall"].tap() }
                    if ["speed", "stamina"].contains(kind), round == 0 {
                        app.buttons["sprintLeft"].tap(); app.buttons["sprintRight"].tap()
                    }
                    if round == 0 {
                        let next = app.buttons["trainingNext"]
                        XCTAssertTrue(next.waitForExistence(timeout: 8))
                        XCTAssertTrue(app.staticTexts["trainingCoach"].exists)
                        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trainingMission").firstMatch.exists)
                        Thread.sleep(forTimeInterval: 0.6)
                        XCTAssertTrue(next.exists, "코칭을 읽는 동안 자동으로 다음 회차를 시작하지 않습니다")
                        let review = XCTAttachment(screenshot: app.screenshot()); review.name = "Session coaching " + kind; review.lifetime = .keepAlways; add(review)
                        next.tap()
                    }
                    if round > 0 && round < 4 {
                        let next = app.buttons["trainingNext"]
                        XCTAssertTrue(next.waitForExistence(timeout: 8)); next.tap()
                    }
                    if round == 4 { finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["practiceCompleted"].waitForExistence(timeout: 8)) }
                }
                XCTAssertFalse(app.staticTexts["trainingGrowth"].exists)
                XCTAssertFalse(app.staticTexts["trainingFatigue"].exists)
                let result = XCTAttachment(screenshot: app.screenshot()); result.name = "Training five attempts " + kind; result.lifetime = .keepAlways; add(result)
                app.buttons["practiceChangeTraining"].tap()
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["practiceIsolation"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testFreePracticeFromHomeAfterDailyActionDoesNotChangeCareer() throws {
        let app = XCUIApplication(); app.launchArguments = ["-training-practice"]; app.launch()
        XCTAssertTrue(app.staticTexts["practiceNoPlayer"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["practiceGeneralTraining"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        createDashboardSample(app, name: "FreeBatter")
        reveal(app.buttons["restToday"], in: app); app.buttons["restToday"].tap()
        let date = app.staticTexts["calendarDate"].label
        let action = app.staticTexts["calendarAction"].label
        let fatigue = app.staticTexts["homeFatigue"].label
        reveal(app.buttons["openTrainingPractice"], in: app); app.buttons["openTrainingPractice"].tap()
        XCTAssertTrue(app.staticTexts["practicePlayerName"].label.contains("FreeBatter"))
        XCTAssertFalse(app.segmentedControls["practiceRole"].buttons["투수"].exists)
        app.buttons["practiceGeneralTraining"].tap()
        app.buttons["trainingKind-power"].tap(); app.buttons["startTraining"].tap()
        for _ in 0..<5 { waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap() }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["practiceCompleted"].waitForExistence(timeout: 5))
        app.buttons["trainingReturnHome"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.staticTexts["calendarDate"].label, date)
        XCTAssertEqual(app.staticTexts["calendarAction"].label, action)
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["calendarDate"].label, date)
        XCTAssertEqual(app.staticTexts["calendarAction"].label, action)
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
    }

    @MainActor private func createOwnPracticePlayers(_ app: XCUIApplication) {
        app.launch(); createDashboardSample(app, name: "OwnBatter", motionStyle: true)
        reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
        createDashboardSample(app, name: "OwnPitcher", motionStyle: true)
        app.terminate(); app.launchArguments = ["-training-practice"]; app.launch()
    }

    @MainActor func testFreePracticeTraitAndPositionFiveAttemptsWithoutRewards() throws {
        let app = XCUIApplication(); createOwnPracticePlayers(app)
        XCTAssertTrue(app.staticTexts["practiceIsolation"].waitForExistence(timeout: 8))
        app.buttons["practiceTrait-safe-hands"].tap()
        for index in 0..<5 {
            let submit = app.buttons["traitDrillSubmit"]; reveal(submit, in: app); submit.tap()
            if index < 4 { let next = app.buttons["traitDrillNext"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap() }
        }
        XCTAssertTrue(app.buttons["practiceTraitRetry"].waitForExistence(timeout: 5))
        app.buttons["practiceTraitRetry"].tap(); XCTAssertTrue(app.buttons["traitDrillSubmit"].exists)
        app.buttons["acquisitionCloseDrill"].tap()
        let position = app.buttons["practicePosition-CF"]; reveal(position, in: app); position.tap()
        for index in 0..<5 {
            let catchButton = app.buttons["positionCatch"]; reveal(catchButton, in: app); catchButton.tap()
            let send = app.buttons["positionThrow"]; reveal(send, in: app); send.tap()
            if index < 4 { let next = app.buttons["positionNextAttempt"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); reveal(next, in: app); next.tap() }
        }
        XCTAssertTrue(app.buttons["practicePositionRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["positionXPGain"].exists); XCTAssertFalse(app.staticTexts["positionFatigue"].exists)
        app.buttons["practicePositionRetry"].tap(); XCTAssertTrue(app.buttons["positionCatch"].exists)
    }

    @MainActor func testNativePitchReleaseTrainingResumeAndRewardOnce() throws {
        let app = XCUIApplication(); app.launch()
        app.buttons["role-pitcher"].tap(); createDashboardSample(app, name: "ReleasePitch", motionStyle: true)
        let fatigue = try XCTUnwrap(Int(app.staticTexts["homeFatigue"].label.split(separator: " ")[1]))
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.buttons["startTraining"].tap()
        for index in 0..<5 {
            if index == 2 {
                app.terminate(); app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
            }
            let attempt = app.buttons["trainingAttempt"]
            waitForEnabled(attempt); attempt.tap(); attempt.tap()
            if index == 0 {
                let toast = app.descendants(matching: .any).matching(identifier: "trainingCatchToast").firstMatch
                XCTAssertTrue(toast.waitForExistence(timeout: 3)); XCTAssertFalse(attempt.isEnabled)
                let caught = XCTAttachment(screenshot: app.screenshot()); caught.name = "Native pitch training receipt and release coaching"; caught.lifetime = .keepAlways; add(caught)
            }
        }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let growth = app.staticTexts["trainingGrowth"].label
        app.buttons["trainingReturnHome"].tap()
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 \(min(100, fatigue + 6)) / 100")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, growth)
        app.buttons["trainingReturnHome"].tap()
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 \(min(100, fatigue + 6)) / 100")
    }

    @MainActor func testFreePracticeBothRolesReplayRetryAndRelease() throws {
        let app = XCUIApplication(); createOwnPracticePlayers(app)
        XCTAssertTrue(app.staticTexts["practiceIsolation"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["practicePlayerName"].label.contains("OwnBatter"))
        app.buttons["능력치·보유 구종 확인"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "practiceValue-homeContact").firstMatch.label.contains("62.0"))
        app.buttons["능력치·보유 구종 확인"].tap()
        app.buttons["practiceGeneralTraining"].tap()
        app.buttons["startTraining"].tap()
        app.buttons["trainingAttempt"].tap(); app.buttons["trainingAttempt"].tap()
        let swing = XCTAttachment(screenshot: app.screenshot()); swing.name = "Personal practice batter swing saved number"; swing.lifetime = .keepAlways; add(swing)
        app.buttons["practiceChangeTraining"].tap()
        app.buttons["trainingKind-power"].tap(); app.buttons["startTraining"].tap()
        let action = app.buttons["trainingAttempt"]
        for _ in 0..<5 { waitForEnabled(action); action.tap() }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["practiceCompleted"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["trainingGrowth"].exists)
        app.buttons["practiceRetry"].tap(); XCTAssertTrue(action.waitForExistence(timeout: 5))
        app.buttons["practiceChangeTraining"].tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["practiceIsolation"].waitForExistence(timeout: 5))
        app.segmentedControls["practiceRole"].buttons["투수"].tap()
        XCTAssertTrue(app.staticTexts["practicePlayerName"].label.contains("OwnPitcher"))
        app.buttons["practiceGeneralTraining"].tap()
        XCTAssertTrue(app.buttons["trainingPitchPicker"].label.contains("62.0"))
        app.buttons["startTraining"].tap()
        action.tap()
        XCTAssertTrue(app.staticTexts["팔 준비 중 · 노란 구간에 릴리스"].waitForExistence(timeout: 2))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Practice held ball before release"; shot.lifetime = .keepAlways; add(shot)
        action.tap()
        XCTAssertTrue(app.staticTexts["릴리스 확정 · 공 비행 중"].waitForExistence(timeout: 2))
        XCTAssertFalse(action.isEnabled)
        let catchToast = app.descendants(matching: .any).matching(identifier: "trainingCatchToast").firstMatch
        XCTAssertTrue(catchToast.waitForExistence(timeout: 3))
        XCTAssertFalse(action.isEnabled, "포구 후 결과 확인 시간에도 다음 시도는 잠겨야 합니다")
        let caught = XCTAttachment(screenshot: app.screenshot()); caught.name = "Pitch training catch and readable score"; caught.lifetime = .keepAlways; add(caught)
        for _ in 1..<5 { waitForEnabled(action); action.tap(); action.tap() }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["practiceCompleted"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["trainingFatigue"].exists)
        app.buttons["practiceRetry"].tap(); XCTAssertTrue(action.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["practiceIsolation"].waitForExistence(timeout: 8))
    }

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
        // Lazy result grids can remove earlier rows from the accessibility tree while scrolled down.
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeDown()
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
        XCTAssertEqual(board.frame.minX, control.frame.minX, accuracy: 1)
        XCTAssertEqual(board.frame.width, control.frame.width, accuracy: 1)
        XCTAssertEqual(field.frame.width / field.frame.height, ratio, accuracy: 0.02)
    }
    @MainActor private func waitForEnabled(_ button: XCUIElement, timeout:TimeInterval = 5) {
        let next = XCUIApplication().buttons["trainingNext"]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if next.exists { next.tap() }
            if button.exists, let state = try? button.snapshot(), state.isEnabled { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("조작 또는 회차 코칭 확인 후 버튼이 열리지 않았습니다")
    }
    @MainActor private func finishTrainingReviewIfNeeded(_ app: XCUIApplication) {
        if app.staticTexts["trainingCompleted"].exists || app.staticTexts["practiceCompleted"].exists { return }
        let next = app.buttons["trainingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 8)); next.tap()
    }

    @MainActor private func checkLargeTraining(_ app: XCUIApplication, name: String, pitcher: Bool = false, actionID: String = "trainingAttempt") {
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
        if role.exists { reveal(role, in: app); role.tap() }
        XCTAssertTrue(app.staticTexts["homeAge"].label.contains(pitcher ? "투수" : "타자"))
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let action = app.buttons[actionID]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        let jump = app.buttons["trainingJumpControls"]
        XCTAssertTrue(jump.waitForExistence(timeout: 3)); reveal(jump, in: app); jump.tap()
        XCTAssertTrue(action.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(action.frame.minX, window.minX); XCTAssertLessThanOrEqual(action.frame.maxX, window.maxX)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Training large text " + name; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        let restoredRole = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
        if restoredRole.exists { reveal(restoredRole, in: app); restoredRole.tap() }
        XCTAssertTrue(app.staticTexts["homeAge"].label.contains(pitcher ? "투수" : "타자"))
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["0 / 5"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["startTraining"].exists)
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
        checkLargeTraining(app, name: pitcher ? "pitch" : "contact", pitcher: pitcher)
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
                app.navigationBars.buttons.element(boundBy: 0).tap()
                reveal(app.staticTexts["homePlayerName"], in: app)
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
                XCTAssertEqual(app.staticTexts["contactScoreBreakdown"].label, previousBreakdown)
            }
            let startAttempt = app.buttons.containing(NSPredicate(format: "identifier == %@ AND label == %@", "trainingAttempt", "\(index + 1)번째 시도 시작")).firstMatch
            XCTAssertTrue(startAttempt.waitForExistence(timeout: 3)); waitForEnabled(startAttempt); startAttempt.tap()
            let hit = app.buttons.containing(NSPredicate(format: "identifier == %@ AND label == %@", "trainingAttempt", pitcher ? "던지기!" : "타격!")).firstMatch
            XCTAssertTrue(hit.waitForExistence(timeout: 2)); hit.tap()
            if !pitcher {
                XCTAssertTrue(app.staticTexts["contactScoreBreakdown"].waitForExistence(timeout:3))
                previousBreakdown = app.staticTexts["contactScoreBreakdown"].label
                XCTAssertTrue(previousBreakdown.contains("조준")); XCTAssertTrue(previousBreakdown.contains("타이밍"))
                XCTAssertTrue(app.staticTexts["contactTotalScore"].exists)
                if index < 4 { waitForEnabled(app.buttons["trainingAttempt"]); XCTAssertTrue(app.buttons["trainingAttempt"].isHittable) }
                if index == 0 {
                    let feedback = XCTAttachment(screenshot: app.screenshot()); feedback.name = "Contact score breakdown"; feedback.lifetime = .keepAlways; add(feedback)
                }
            }
        }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let result = app.staticTexts["trainingGrowth"].label
        let resultShot = XCTAttachment(screenshot: app.screenshot()); resultShot.name = pitcher ? "Pitch growth saved" : "Contact growth saved"; resultShot.lifetime = .keepAlways; add(resultShot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"], in: app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].exists)
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, result)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homePlayerName"], in: app)
    }

    @MainActor private func trainAbility(_ app: XCUIApplication, power: Bool) {
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let choice = app.buttons[power ? "trainingKind-power" : "trainingKind-discipline"]
        XCTAssertTrue(choice.waitForExistence(timeout: 3)); choice.tap()
        app.buttons["startTraining"].tap()
        if power { checkLargeTraining(app, name: "power") }
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
                XCTAssertFalse(app.buttons["trainingKind-power"].exists)
            }
            if power {
                waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap()
                if index == 0 {
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trainingGrade").firstMatch.waitForExistence(timeout: 3))
                    let replay = XCTAttachment(screenshot: app.screenshot()); replay.name = "Power confirmed playback"; replay.lifetime = .keepAlways; add(replay)
                }
            }
            else {
                if index > 0 { waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap() }
                app.buttons["trainingCallStrike"].tap()
            }
        }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let saved = app.staticTexts["trainingGrowth"].label
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = power ? "Power growth saved" : "Discipline growth saved"; result.lifetime = .keepAlways; add(result)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"], in: app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].label.contains(power ? "파워" : "선구안"))
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, saved)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
        XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
        app.buttons["advanceDay"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "오늘 행동 미사용"), object: app.staticTexts["calendarAction"])], timeout: 5), .completed)
    }

    @MainActor private func trainField(_ app: XCUIApplication, kind: String, pitcher: Bool = false) {
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let category = app.buttons["trainingCategory-1"]
        XCTAssertTrue(category.waitForExistence(timeout: 3)); category.tap()
        app.buttons["trainingKind-" + ["스피드":"speed", "수비":"defense", "송구":"arm"][kind]!].tap()
        app.buttons["startTraining"].tap()
        if kind == "송구" { checkLargeTraining(app, name: "arm", pitcher: pitcher) }
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
                waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap()
                if round==0 { app.buttons["sprintLeft"].tap(); app.buttons["sprintRight"].tap() }
                if round < 4 {
                    waitForEnabled(app.buttons["trainingAttempt"], timeout: 8)
                } else { finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:7)) }
            } else {
                if kind == "송구" { waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["throwBase-" + ["1","2","4","3","2"][round]].tap() }
                waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap()
            }
        }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:5))
        let result=app.staticTexts["trainingGrowth"].label
        let saved=XCTAttachment(screenshot:app.screenshot());saved.name=(pitcher ? "Pitcher " : "")+kind+" growth";saved.lifetime = .keepAlways;add(saved)
        app.navigationBars.buttons.element(boundBy:0).tap()
        reveal(app.staticTexts["homeTrainingGrowth"],in:app)
        XCTAssertTrue(app.staticTexts["homeTrainingGrowth"].label.contains(kind))
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"],in:app);app.buttons["openTraining"].tap()
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:3));XCTAssertEqual(app.staticTexts["trainingGrowth"].label,result)
        app.navigationBars.buttons.element(boundBy:0).tap()
        reveal(app.buttons["restToday"],in:app);XCTAssertFalse(app.buttons["restToday"].isEnabled)
        XCTAssertTrue(app.buttons["advanceDay"].isEnabled);app.buttons["advanceDay"].tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","오늘 행동 미사용"),object:app.staticTexts["calendarAction"])],timeout:5),.completed)
    }

    @MainActor private func trainRaw(_ app: XCUIApplication, kind: String, pitcher: Bool, nextDay: Bool = true) {
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.buttons["trainingCategory-2"].tap()
        app.buttons["trainingKind-" + ["구속":"velocity", "제구":"control", "구위":"stuff", "지구력":"stamina", "멘탈":"mental"][kind]!].tap()
        app.buttons["startTraining"].tap()
        if kind == "멘탈" && !pitcher { checkLargeTraining(app, name: "mental", actionID: "mentalChoice-2") }
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
                waitForEnabled(app.buttons["mentalChoice-0"])
                let scenario = app.staticTexts["mentalScenario"].label
                app.terminate(); app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["openTraining"], in: app)
                XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
                XCTAssertEqual(app.staticTexts["mentalScenario"].label, scenario)
            }
            if kind == "멘탈" { waitForEnabled(app.buttons["mentalChoice-0"]); app.buttons["mentalChoice-0"].tap() }
            else {
                waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap()
                if kind == "지구력" {
                    app.buttons["sprintLeft"].tap(); app.buttons["sprintRight"].tap()
                    if round < 4 {
                        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["trainingAttempt"])], timeout: 7), .completed)
                    } else { finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 7)) }
                }
            }
        }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
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
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 3)); XCTAssertEqual(app.staticTexts["trainingGrowth"].label, saved)
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
        if identifier == "traitDetails" || button.value as? String == "접힘" { button.tap() }
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
        reveal(app.staticTexts["homePlayerName"], in: app)
        expandHomeDetails("traitDetails", in: app)
        reveal(count, in: app); XCTAssertEqual(count.label, "활성 0 / 3")
        reveal(app.buttons[id], in: app); app.buttons[id].tap()
        XCTAssertEqual(count.label, "활성 1 / 3")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.staticTexts["homePlayerName"], in: app)
        reveal(app.staticTexts["calendarAction"], in: app)
        XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 미사용")
        reveal(app.staticTexts["homePlayerName"], in: app)
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
        reveal(app.staticTexts["homePlayerName"], in: app)
        XCTAssertTrue(app.staticTexts["homeArchetype"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["homeArchetype"].label,pitcher ? "지구력형" : "장타형")
        expandHomeDetails("homeAbilityDetails", in: app)
        let values = pitcher ? [("homeVelocity","52"),("homeControl","54"),("homeStuff","53"),("homeStamina","65"),("homeBreaking","49.8"),("homeMental","55")] : [("homeMental","55")]
        for (identifier,value) in values {
            let row = app.descendants(matching:.any).matching(identifier:identifier).firstMatch
            reveal(row,in:app); XCTAssertTrue(row.exists); XCTAssertTrue(row.label.contains(value),row.label)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Pitcher ability home" : "Batter ability home"; shot.lifetime = .keepAlways; add(shot)
        reveal(app.staticTexts["homePlayerName"], in: app)
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
        reveal(app.staticTexts["homePlayerName"], in: app)
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
        reveal(app.staticTexts["homePlayerName"], in: app)
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
        reveal(app.staticTexts["homePlayerName"], in: app)
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
        waitForEnabled(app.buttons["gameAutomatic"], timeout: 15)
        reveal(app.buttons["gameAutomatic"], in: app); app.buttons["gameAutomatic"].tap()
        app.buttons["진행하고 결과 저장"].tap()
        XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5))
        reveal(app.buttons["gameReturnHome"], in: app); app.buttons["gameReturnHome"].tap()
        reveal(app.staticTexts["homePlayerName"], in: app)
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
    @MainActor private func checkResultBoard(_ app: XCUIApplication, pitcher: Bool) {
        XCTAssertTrue(app.staticTexts["gameResultSaved"].exists)
        XCTAssertFalse(app.otherElements["careerMatchField"].exists)
        XCTAssertFalse(app.otherElements["matchScoreboard"].exists)
        let metricIDs = pitcher ? ["innings", "pitches", "hitsAllowed", "runsAllowed", "pitchingWalks", "pitchingStrikeouts"]
            : ["plateAppearances", "atBats", "hits", "homeRuns", "rbi", "walks", "strikeouts"]
        var values: [String] = []
        for id in metricIDs {
            let metric = app.descendants(matching: .any).matching(identifier: "gameResult-" + id).firstMatch
            reveal(metric, in: app); XCTAssertTrue(metric.exists); values.append(metric.label)
        }
        reveal(app.staticTexts["gameResultFatigue"], in: app)
        let fatigue = app.staticTexts["gameResultFatigue"].label
        reveal(app.staticTexts["gameResultTraitStatus"], in: app); let traitStatus = app.staticTexts["gameResultTraitStatus"].label
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = pitcher ? "Result pitcher details" : "Result batter details"; detail.lifetime = .keepAlways; add(detail)
        reveal(app.staticTexts["careerGameFinished"], in: app)
        let normal = XCTAttachment(screenshot: app.screenshot()); normal.name = pitcher ? "Result pitcher board" : "Result batter board"; normal.lifetime = .keepAlways; add(normal)
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
        if role.exists { reveal(role, in: app); role.tap() }
        reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
        XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5))
        for (index, id) in metricIDs.enumerated() {
            let metric = app.descendants(matching: .any).matching(identifier: "gameResult-" + id).firstMatch
            reveal(metric, in: app); XCTAssertEqual(metric.label, values[index])
            XCTAssertGreaterThanOrEqual(metric.frame.minX, app.windows.firstMatch.frame.minX)
            XCTAssertLessThanOrEqual(metric.frame.maxX, app.windows.firstMatch.frame.maxX)
        }
        reveal(app.staticTexts["gameResultFatigue"], in: app); XCTAssertEqual(app.staticTexts["gameResultFatigue"].label, fatigue)
        reveal(app.staticTexts["gameResultTraitStatus"], in: app); XCTAssertEqual(app.staticTexts["gameResultTraitStatus"].label, traitStatus)
        reveal(app.buttons["gameReturnHome"], in: app); XCTAssertTrue(app.buttons["gameReturnHome"].isHittable)
        let large = XCTAttachment(screenshot: app.screenshot()); large.name = pitcher ? "Result pitcher large text" : "Result batter large text"; large.lifetime = .keepAlways; add(large)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        let restoredRole = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
        if restoredRole.exists { reveal(restoredRole, in: app); restoredRole.tap() }
        reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
        XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["gameResultFatigue"], in: app); XCTAssertEqual(app.staticTexts["gameResultFatigue"].label, fatigue)
    }

    @MainActor func testMatchBoardBothRolesResumeAndLargeText() throws {
        let app = XCUIApplication(); app.launch()
        for pitcher in [false, true] {
            if pitcher {
                reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
            }
            let name = app.textFields["playerName"]
            XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText(pitcher ? "BoardPitcher" : "BoardBatter")
            if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
            if pitcher { app.buttons["hand-left"].tap() }
            reveal(app.buttons["randomSchool"], in: app); app.buttons["randomSchool"].tap()
            configureMotionStyle(app)
            reveal(app.buttons["createPlayer"], in: app); app.buttons["createPlayer"].tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", pitcher ? "BoardPitcher" : "BoardBatter"), object: app.staticTexts["homePlayerName"])
            XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
            reveal(app.buttons["restToday"], in: app); app.buttons["restToday"].tap()
            reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
            let primary = pitcher ? "gamePitch" : "requestGamePitch"
            XCTAssertTrue(app.buttons[primary].waitForExistence(timeout: 5))
            assertArenaFits(app, button: primary, ratio: pitcher ? 1219.0 / 1290 : 1)
            let gauge = app.otherElements[pitcher ? "releaseGauge" : "battingTimingGauge"]
            XCTAssertTrue(gauge.exists)
            XCTAssertLessThanOrEqual(gauge.frame.maxY, app.windows.firstMatch.frame.maxY)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Match pitcher board" : "Match batter board"; shot.lifetime = .keepAlways; add(shot)
            if pitcher {
                app.buttons["gamePitchPicker"].tap()
                let slider = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "슬라이더")).firstMatch
                XCTAssertTrue(slider.waitForExistence(timeout: 3)); slider.tap()
            }
            // Cancelling an uncommitted attempt must not consume a pitch or change the persisted count.
            let count = app.otherElements["careerGameCount"].label
            app.buttons[primary].tap(); XCTAssertFalse(app.buttons["gameAutomatic"].isEnabled)
            app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
            if role.exists { reveal(role, in: app); role.tap() }
            reveal(app.buttons["openCareerGame"], in: app); XCTAssertEqual(app.buttons["openCareerGame"].label, "오늘 경기 이어하기"); app.buttons["openCareerGame"].tap()
            XCTAssertTrue(app.buttons["gameJumpControls"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.otherElements["careerGameCount"].label, count)
            app.buttons["gameJumpControls"].tap()
            XCTAssertTrue(app.buttons[primary].isHittable)
            let large = XCTAttachment(screenshot: app.screenshot()); large.name = pitcher ? "Match pitcher large text" : "Match batter large text"; large.lifetime = .keepAlways; add(large)
            app.terminate(); app.launchArguments = []; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            let restoredRole = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
            if restoredRole.exists { reveal(restoredRole, in: app); restoredRole.tap() }
            reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
            XCTAssertTrue(app.buttons[primary].waitForExistence(timeout: 5))
            if pitcher {
                app.buttons["gamePitch"].tap(); app.buttons["gameRelease"].tap()
            } else {
                app.buttons["gameInput-swing"].tap(); app.buttons["requestGamePitch"].tap()
                let watched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "지켜보기"), object: app.staticTexts["careerGameMessage"])
                XCTAssertEqual(XCTWaiter.wait(for: [watched], timeout: 5), .completed)
                app.buttons["gameInput-bunt"].tap()
                waitForEnabled(app.buttons[primary],timeout:10); app.buttons[primary].tap(); app.buttons["gameHit"].tap()
                let bunt = XCTAttachment(screenshot: app.screenshot()); bunt.name = "Personal batter bunt saved number"; bunt.lifetime = .keepAlways; add(bunt)
                waitForEnabled(app.buttons[primary],timeout:10); app.buttons["gameInput-swing"].tap(); app.buttons[primary].tap(); app.buttons["gameHit"].tap()
            }
            waitForEnabled(app.buttons["gameAutomatic"],timeout:15)
            let speed = app.descendants(matching: .any).matching(identifier: "boardPitchSpeed").firstMatch
            XCTAssertTrue(speed.exists); XCTAssertFalse(speed.label.contains("–––"))
            app.buttons["gameAutomatic"].tap(); app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5))
            checkResultBoard(app, pitcher: pitcher)
            if pitcher {
                let reason=app.staticTexts["pitcherChangeReason"]
                reveal(reason,in:app);XCTAssertTrue(reason.exists)
                let responsibility=app.staticTexts["pitcherResponsibilityResult"]
                reveal(responsibility,in:app);XCTAssertTrue(responsibility.exists)
                let change=XCTAttachment(screenshot:app.screenshot());change.name="Pitcher change final responsibility";change.lifetime = .keepAlways;add(change)
            }
            reveal(app.buttons["replayResultFieldPlay"], in:app)
            let fieldSummary=app.staticTexts["gameDetailedFieldSummary"].label
            XCTAssertFalse(fieldSummary.isEmpty)
            app.buttons["replayResultFieldPlay"].tap()
            XCTAssertTrue(app.otherElements["fieldReplayCanvas"].exists)
            let movingField=XCTAttachment(screenshot:app.screenshot());movingField.name=pitcher ? "Detailed pitcher field moving" : "Detailed batter field moving";movingField.lifetime = .keepAlways;add(movingField)
            waitForEnabled(app.buttons["replayResultFieldPlay"],timeout:9)
            XCTAssertEqual(app.staticTexts["gameDetailedFieldSummary"].label,fieldSummary)
            let settledField=XCTAttachment(screenshot:app.screenshot());settledField.name=pitcher ? "Detailed pitcher field settled" : "Detailed batter field settled";settledField.lifetime = .keepAlways;add(settledField)
            let dpMetric=app.descendants(matching:.any).matching(identifier:"gameResult-doublePlays").firstMatch
            reveal(dpMetric,in:app);XCTAssertTrue(dpMetric.exists)
            let dpValue=dpMetric.label
            if app.buttons["replayDoublePlay"].exists {
                reveal(app.buttons["replayDoublePlay"],in:app);app.buttons["replayDoublePlay"].tap()
                XCTAssertTrue(app.staticTexts["fieldReplaySecondTimes"].exists)
                reveal(app.staticTexts["fieldReplayPhase"],in:app)
                let moving=XCTAttachment(screenshot:app.screenshot());moving.name=pitcher ? "Double play pitcher moving" : "Double play batter moving";moving.lifetime = .keepAlways;add(moving)
                waitForEnabled(app.buttons["replayDoublePlay"],timeout:9)
                XCTAssertTrue(app.staticTexts["gameDetailedFieldSummary"].label.contains("2루 아웃 → 1루"))
                let ended=XCTAttachment(screenshot:app.screenshot());ended.name=pitcher ? "Double play pitcher settled" : "Double play batter settled";ended.lifetime = .keepAlways;add(ended)
                reveal(dpMetric,in:app);XCTAssertEqual(dpMetric.label,dpValue)
            }
            let flyButton=app.buttons["replayFlyPlay"]
            reveal(flyButton,in:app);XCTAssertTrue(flyButton.exists)
            flyButton.tap()
            XCTAssertTrue(app.staticTexts["fieldReplayCatchTimes"].exists)
            reveal(app.staticTexts["fieldReplayPhase"],in:app)
            let flyMoving=XCTAttachment(screenshot:app.screenshot());flyMoving.name=pitcher ? "Fly pitcher moving" : "Fly batter moving";flyMoving.lifetime = .keepAlways;add(flyMoving)
            waitForEnabled(flyButton,timeout:9)
            let flySummary=app.staticTexts["gameDetailedFieldSummary"].label
            XCTAssertTrue(flySummary.contains("뜬공") || flySummary.contains("태그업"))
            let flySettled=XCTAttachment(screenshot:app.screenshot());flySettled.name=pitcher ? "Fly pitcher settled" : "Fly batter settled";flySettled.lifetime = .keepAlways;add(flySettled)
            reveal(dpMetric,in:app);XCTAssertEqual(dpMetric.label,dpValue)
            let relayButton=app.buttons["replayRelayPlay"]
            reveal(relayButton,in:app);XCTAssertTrue(relayButton.exists)
            relayButton.tap()
            XCTAssertTrue(app.staticTexts["fieldReplayRelayTimes"].exists)
            XCTAssertTrue(app.staticTexts["fieldReplayRouteComparison"].exists)
            reveal(app.staticTexts["fieldReplayPhase"],in:app)
            let relayMoving=XCTAttachment(screenshot:app.screenshot());relayMoving.name=pitcher ? "Relay pitcher moving":"Relay batter moving";relayMoving.lifetime = .keepAlways;add(relayMoving)
            waitForEnabled(relayButton,timeout:9)
            XCTAssertTrue(app.staticTexts["gameDetailedFieldSummary"].label.contains("중계"))
            let relaySettled=XCTAttachment(screenshot:app.screenshot());relaySettled.name=pitcher ? "Relay pitcher settled":"Relay batter settled";relaySettled.lifetime = .keepAlways;add(relaySettled)
            reveal(dpMetric,in:app);XCTAssertEqual(dpMetric.label,dpValue)
            let errorMetric=app.descendants(matching:.any).matching(identifier:"gameResult-teamErrors").firstMatch
            reveal(errorMetric,in:app);XCTAssertTrue(errorMetric.exists);let errorValue=errorMetric.label
            let errorButton=app.buttons["replayMisplay"]
            reveal(errorButton,in:app);XCTAssertTrue(errorButton.exists);errorButton.tap()
            XCTAssertTrue(app.staticTexts["fieldReplayMisplayTimes"].exists)
            XCTAssertTrue(app.staticTexts["fieldReplayMisplayScoring"].exists)
            reveal(app.staticTexts["fieldReplayPhase"],in:app)
            let errorMoving=XCTAttachment(screenshot:app.screenshot());errorMoving.name=pitcher ? "Misplay pitcher moving":"Misplay batter moving";errorMoving.lifetime = .keepAlways;add(errorMoving)
            waitForEnabled(errorButton,timeout:9)
            let errorSummary=app.staticTexts["gameDetailedFieldSummary"].label
            XCTAssertTrue(errorSummary.contains("실책") || errorSummary.contains("악송구"))
            let errorSettled=XCTAttachment(screenshot:app.screenshot());errorSettled.name=pitcher ? "Misplay pitcher settled":"Misplay batter settled";errorSettled.lifetime = .keepAlways;add(errorSettled)
            reveal(errorMetric,in:app);XCTAssertEqual(errorMetric.label,errorValue)
            var positionGrowth = ""
            if !pitcher {
                reveal(app.staticTexts["gamePositionGrowth"], in: app)
                XCTAssertTrue(app.staticTexts["gamePositionParticipation"].exists)
                positionGrowth = app.staticTexts["gamePositionGrowth"].label
                let xpShot = XCTAttachment(screenshot: app.screenshot()); xpShot.name = "Game position XP result"; xpShot.lifetime = .keepAlways; add(xpShot)
            }
            reveal(app.buttons["gameReturnHome"], in: app); app.buttons["gameReturnHome"].tap()
            if !pitcher {
                reveal(app.staticTexts["homeGamePositionGrowth"], in: app)
                XCTAssertEqual(app.staticTexts["homeGamePositionGrowth"].label, positionGrowth)
                let xpHome = XCTAttachment(screenshot: app.screenshot()); xpHome.name = "Home actual game position XP"; xpHome.lifetime = .keepAlways; add(xpHome)
            }
            reveal(app.staticTexts["homeFatigue"], in: app); let fatigue = app.staticTexts["homeFatigue"].label
            reveal(app.buttons["openCareerGame"], in: app); XCTAssertEqual(app.buttons["openCareerGame"].label, "오늘 경기 결과"); app.buttons["openCareerGame"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons[primary].exists)
            let savedDP=app.descendants(matching:.any).matching(identifier:"gameResult-doublePlays").firstMatch
            reveal(savedDP,in:app);XCTAssertEqual(savedDP.label,dpValue)
            let savedErrors=app.descendants(matching:.any).matching(identifier:"gameResult-teamErrors").firstMatch
            reveal(savedErrors,in:app);XCTAssertEqual(savedErrors.label,errorValue)
            reveal(app.buttons["gameReturnHome"], in: app); app.buttons["gameReturnHome"].tap()
            reveal(app.staticTexts["homeFatigue"], in: app); XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
            reveal(app.buttons["advanceDay"], in: app); XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
            reveal(app.staticTexts["homePlayerName"], in: app)
        }
    }

    @MainActor func testNativeTraitTrainingBothRolesResumeAndRewardOnce() throws {
        let app = XCUIApplication(); app.launch()
        for pitcher in [false, true] {
            if pitcher { reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap() }
            createDashboardSample(app, name: pitcher ? "NativeTraitP" : "NativeTraitB")
            let date = app.staticTexts["calendarDate"].label
            let fatigue = try XCTUnwrap(Int(app.staticTexts["homeFatigue"].label.split(separator: " ")[1]))
            expandHomeDetails("traitDetails", in: app)
            var chosen = ""
            for id in ["strong-arm", "cheetah", "safe-hands"] {
                let button = app.buttons["traitTraining-" + id]
                if button.exists { reveal(button, in: app); if button.isEnabled { chosen = id; button.tap(); break } }
            }
            XCTAssertFalse(chosen.isEmpty)
            XCTAssertTrue(app.buttons["startTraitTraining"].waitForExistence(timeout: 5))
            app.buttons["startTraitTraining"].tap()
            func attempt() {
                if chosen == "cheetah" { app.buttons["traitDrillLeft"].tap(); app.buttons["traitDrillRight"].tap() }
                else { app.buttons["traitDrillSubmit"].tap() }
                XCTAssertTrue(app.staticTexts["traitDrillFeedback"].waitForExistence(timeout: 7))
            }
            XCTAssertTrue(app.staticTexts["traitAttemptCount"].waitForExistence(timeout: 5))
            attempt(); app.buttons["traitDrillNext"].tap(); attempt()
            XCTAssertEqual(app.staticTexts["traitAttemptCount"].label, "2 / 5")
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            if pitcher { app.buttons["homeRole-pitcher"].tap() }
            reveal(app.buttons["openTraining"], in: app); XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.staticTexts["traitAttemptCount"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["traitAttemptCount"].label, "2 / 5")
            for index in 0..<3 { attempt(); if index < 2 { app.buttons["traitDrillNext"].tap() } }
            XCTAssertTrue(app.staticTexts["traitTrainingGrowth"].exists)
            let growth = app.staticTexts["traitTrainingGrowth"].label
            XCTAssertFalse(growth.contains("+0.0"))
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = pitcher ? "Native trait pitcher result" : "Native trait batter result"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            if pitcher { app.buttons["homeRole-pitcher"].tap() }
            XCTAssertEqual(app.staticTexts["calendarDate"].label, date)
            XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 \(min(100, fatigue + 6)) / 100")
            XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 완료 · 훈련")
            reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.staticTexts["traitTrainingGrowth"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["traitTrainingGrowth"].label, growth)
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            if pitcher { app.buttons["homeRole-pitcher"].tap() }
            XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 \(min(100, fatigue + 6)) / 100")
        }
    }

    @MainActor func testTrainingSpinBoardPortraitAndFiveSavedAttempts() throws {
        let app = XCUIApplication(); app.launch()
        app.buttons["role-pitcher"].tap()
        createDashboardSample(app, name: "SpinPitcher")
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.buttons["trainingCategory-2"].tap(); app.buttons["trainingKind-stuff"].tap(); app.buttons["startTraining"].tap()
        let action = app.buttons["trainingAttempt"]
        XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isHittable)
        let field = app.otherElements["trainingField"].firstMatch
        XCTAssertLessThanOrEqual(field.frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.windows.firstMatch.frame.maxY)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Round pixel spin portrait"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<5 { waitForEnabled(action); action.tap() }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["trainingGrowth"].label.contains("→"))
    }

    @MainActor func testTrainingPixelRailDirectInputAndSavedReplay() throws {
        let app = XCUIApplication(); app.launch()
        createDashboardSample(app, name: "RailBatter")
        let fatigue = app.staticTexts["homeFatigue"].label
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.buttons["trainingKind-power"].tap(); app.buttons["startTraining"].tap()
        let rail = app.descendants(matching: .any).matching(identifier: "powerForceSlider").firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 5)); XCTAssertTrue(rail.isHittable)
        let original = rail.value as? String
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: rail.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertNotEqual(rail.value as? String, original)
        let input = Int((rail.value as? String ?? "").filter(\.isNumber)) ?? -1
        XCTAssertTrue((0...100).contains(input)); XCTAssertEqual(input % 5, 0)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Pixel rail power practice"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["trainingAttempt"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trainingGrade").firstMatch.waitForExistence(timeout: 4))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        reveal(app.buttons["openTraining"], in: app); XCTAssertTrue(app.buttons["openTraining"].label.contains("1/5")); app.buttons["openTraining"].tap()
        for _ in 0..<4 { waitForEnabled(app.buttons["trainingAttempt"]); app.buttons["trainingAttempt"].tap() }
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        let result = app.staticTexts["trainingGrowth"].label
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 완료 · 훈련")
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        finishTrainingReviewIfNeeded(app); XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, result)
    }

    @MainActor func testNativePositionTrainingResumeXPAndRewardOnce() throws {
        let app = XCUIApplication(); app.launch()
        createDashboardSample(app, name: "PositionB")
        let date = app.staticTexts["calendarDate"].label
        let fatigue = try XCTUnwrap(Int(app.staticTexts["homeFatigue"].label.split(separator: " ")[1]))
        let entry = app.buttons["openPositionTraining"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.buttons["startPositionTraining"].waitForExistence(timeout: 5))
        for code in ["C", "1B", "2B", "3B", "SS", "LF", "RF", "CF"] { app.buttons["livePosition-" + code].tap() }
        XCTAssertTrue(app.staticTexts["livePositionMastery"].label.contains("60.0"))
        let ready = XCTAttachment(screenshot: app.screenshot()); ready.name = "Native position ready"; ready.lifetime = .keepAlways; add(ready)
        app.buttons["startPositionTraining"].tap()
        func attempt() {
            let catchButton = app.buttons["positionCatch"]; reveal(catchButton, in: app); catchButton.tap()
            let base = app.buttons["positionBase-2"]; reveal(base, in: app); base.tap()
            let throwing = app.buttons["positionThrow"]; reveal(throwing, in: app); throwing.tap()
            XCTAssertTrue(app.staticTexts["positionFeedback"].waitForExistence(timeout: 5))
        }
        attempt(); app.buttons["positionNextAttempt"].tap(); attempt()
        XCTAssertEqual(app.staticTexts["positionAttemptCount"].label, "2 / 5")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["restToday"], in: app); XCTAssertFalse(app.buttons["restToday"].isEnabled)
        XCTAssertFalse(app.buttons["advanceDay"].isEnabled)
        reveal(app.buttons["openTraining"], in: app); XCTAssertTrue(app.buttons["openTraining"].label.contains("2/5")); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.buttons["positionCatch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["positionAttemptCount"].label, "2 / 5")
        for index in 0..<3 { attempt(); if index < 2 { app.buttons["positionNextAttempt"].tap() } }
        let gain = app.staticTexts["positionXPGain"].label, result = app.staticTexts["positionGrowth"].label
        XCTAssertTrue(gain.contains("XP +")); XCTAssertFalse(gain.contains("XP +0.0"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native position result"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["calendarDate"].label, date)
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 \(min(100, fatigue + 6)) / 100")
        XCTAssertEqual(app.staticTexts["calendarAction"].label, "오늘 행동 완료 · 훈련")
        reveal(app.staticTexts["homePositionTrainingGrowth"], in: app)
        XCTAssertTrue(app.staticTexts["homePositionTrainingGrowth"].label.contains("XP +"))
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["positionXPGain"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["positionGrowth"].label, result)
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let growth = app.staticTexts["positionGrowth"]; reveal(growth, in: app); XCTAssertEqual(growth.label, result)
        let close = app.buttons["closePositionTraining"]; reveal(close, in: app); XCTAssertTrue(close.isHittable)
        let large = XCTAttachment(screenshot: app.screenshot()); large.name = "Native position result large"; large.lifetime = .keepAlways; add(large)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, "피로 \(min(100, fatigue + 6)) / 100")
        reveal(app.buttons["openCareerGame"], in: app); app.buttons["openCareerGame"].tap()
        let automatic = app.buttons["gameAutomatic"]; reveal(automatic, in: app); automatic.tap(); app.buttons["진행하고 결과 저장"].tap()
        XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 6))
        reveal(app.buttons["gameReturnHome"], in: app); app.buttons["gameReturnHome"].tap()
        reveal(app.buttons["advanceDay"], in: app); XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
    }

    @MainActor func testPositionTrainingPreviewHomeNavigationKeepsDailyAction() throws {
        let app = XCUIApplication(); app.launch()
        if !app.staticTexts["homePlayerName"].waitForExistence(timeout: 4) { createDashboardSample(app, name: "Position QA") }
        let action = app.staticTexts["calendarAction"]; reveal(action, in: app)
        let before = action.label
        let link = app.buttons["openPositionPreview"]; reveal(link, in: app); link.tap()
        XCTAssertTrue(app.staticTexts["positionPreviewNotice"].waitForExistence(timeout: 3))
        app.buttons["positionSelect-C"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(action, in: app); XCTAssertEqual(action.label, before)
        XCTAssertTrue(app.staticTexts["homePlayerName"].exists)
    }

    @MainActor func testPositionTrainingPreviewSelectionStatesAndScenes() throws {
        let app = XCUIApplication(); app.launchArguments = ["-position-training-preview"]; app.launch()
        XCTAssertTrue(app.staticTexts["positionPreviewNotice"].waitForExistence(timeout: 5))
        let progress = app.staticTexts["positionProgress"]
        let window = app.windows.firstMatch.frame
        for (code, task) in [("C", "블로킹"), ("1B", "베이스 커버"), ("2B", "병살 연결"), ("3B", "강습 타구"),
                             ("SS", "백핸드"), ("LF", "낙하지점"), ("CF", "타구 추적"), ("RF", "3루 송구")] {
            let selection = app.buttons["positionSelect-" + code]
            XCTAssertTrue(selection.isHittable); selection.tap()
            XCTAssertTrue(selection.isSelected)
            XCTAssertTrue(app.staticTexts["positionTask"].label.contains(task))
            XCTAssertEqual(progress.label, "잔여 XP 36.0 / 100.0")
            let action = app.buttons["positionStartPreview"]
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(selection.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(selection.frame.maxX, window.maxX)
            XCTAssertLessThanOrEqual(action.frame.maxY, window.maxY)
        }
        let main = XCTAttachment(screenshot: app.screenshot()); main.name = "Position overview RF"; main.lifetime = .keepAlways; add(main)
        app.buttons["positionStartPreview"].tap()
        XCTAssertTrue(app.otherElements["positionDrillField"].waitForExistence(timeout: 3))
        app.buttons["positionPhase-1"].tap()
        XCTAssertTrue(app.staticTexts["positionDrillFeedback"].label.contains("포구"))
        app.buttons["positionPhase-2"].tap()
        XCTAssertTrue(app.staticTexts["positionDrillFeedback"].label.contains("3루"))
        let scene = XCTAttachment(screenshot: app.screenshot()); scene.name = "Position RF throw scene"; scene.lifetime = .keepAlways; add(scene)
        let close = app.buttons["positionCloseDrill"]; reveal(close, in: app); close.tap()
        XCTAssertEqual(progress.label, "잔여 XP 36.0 / 100.0")
        for (state, enabled) in [("오늘 행동 완료", false), ("이어하기", true), ("최대 숙련", false)] {
            app.buttons["positionSampleState"].tap(); app.buttons[state].tap()
            XCTAssertEqual(app.buttons["positionStartPreview"].isEnabled, enabled)
            if state == "이어하기" {
                XCTAssertFalse(app.buttons["positionSelect-SS"].isEnabled)
                XCTAssertTrue(app.staticTexts["positionState"].label.contains("2 / 5"))
            }
            if state == "최대 숙련" { XCTAssertTrue(app.staticTexts["positionMastery"].label.contains("100.0")) }
        }
        app.buttons["positionSampleState"].tap(); app.buttons["조회 오류"].tap()
        XCTAssertFalse(progress.exists); XCTAssertTrue(app.buttons["positionRetry"].isHittable)
        app.buttons["positionRetry"].tap(); XCTAssertEqual(progress.label, "잔여 XP 36.0 / 100.0")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["positionPreviewNotice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["positionSelect-SS"].isSelected)
        XCTAssertEqual(progress.label, "잔여 XP 36.0 / 100.0")
    }

    @MainActor func testPositionTrainingPreviewLargeTextAccess() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-position-training-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["positionPreviewNotice"].waitForExistence(timeout: 5))
        let position = app.buttons["positionSelect-CF"]; reveal(position, in: app); position.tap()
        let progress = app.staticTexts["positionProgress"]; reveal(progress, in: app)
        XCTAssertEqual(progress.label, "잔여 XP 36.0 / 100.0")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Position large progress"; shot.lifetime = .keepAlways; add(shot)
        let action = app.buttons["positionStartPreview"]; reveal(action, in: app)
        XCTAssertGreaterThanOrEqual(action.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, app.windows.firstMatch.frame.maxX)
        action.tap()
        let phase = app.buttons["positionPhase-2"]; reveal(phase, in: app); phase.tap()
        let feedback = app.staticTexts["positionDrillFeedback"]; reveal(feedback, in: app)
        XCTAssertTrue(feedback.label.contains("중계수"))
        let close = app.buttons["positionCloseDrill"]; reveal(close, in: app)
        let drillShot = XCTAttachment(screenshot: app.screenshot()); drillShot.name = "Position large scene"; drillShot.lifetime = .keepAlways; add(drillShot)
        close.tap()
        reveal(progress, in: app); XCTAssertEqual(progress.label, "잔여 XP 36.0 / 100.0")
    }

    @MainActor func testTraitAcquisitionPreviewStatesAndLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-trait-acquisition-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["acquisitionPreviewNotice"].waitForExistence(timeout: 5))
        for (id, label) in [("strong-arm", "송구 60"), ("cheetah", "스피드 60"), ("safe-hands", "수비 50")] {
            app.buttons["acquisitionTrait-" + id].tap()
            XCTAssertTrue(app.staticTexts["acquisitionCondition"].label.contains(label))
            XCTAssertEqual(app.staticTexts["acquisitionProgress"].label, "36.8 / 100.0")
            let button = app.buttons["acquisitionStartPreview"]
            XCTAssertTrue(button.isHittable)
            XCTAssertLessThanOrEqual(button.frame.maxY, app.windows.firstMatch.frame.maxY)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Acquisition " + id; shot.lifetime = .keepAlways; add(shot)
        }
        app.buttons["acquisitionStartPreview"].tap()
        XCTAssertTrue(app.buttons["acquisitionCloseDrill"].waitForExistence(timeout: 3))
        app.buttons["acquisitionCloseDrill"].tap()
        for (state, progress, enabled) in [("조건 미달", "36.8 / 100.0", false), ("습득 직전", "99.4 / 100.0", true), ("보유", "100.0 / 100.0", false), ("오늘 행동 완료", "36.8 / 100.0", false)] {
            app.buttons["acquisitionSampleState"].tap()
            app.buttons[state].tap()
            XCTAssertEqual(app.staticTexts["acquisitionProgress"].label, progress)
            XCTAssertEqual(app.buttons["acquisitionStartPreview"].isEnabled, enabled)
        }
        let locked = XCTAttachment(screenshot: app.screenshot()); locked.name = "Acquisition locked"; locked.lifetime = .keepAlways; add(locked)
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        reveal(app.staticTexts["acquisitionProgress"], in: app)
        XCTAssertEqual(app.staticTexts["acquisitionProgress"].label, "36.8 / 100.0")
        let progressShot = XCTAttachment(screenshot: app.screenshot()); progressShot.name = "Acquisition large progress"; progressShot.lifetime = .keepAlways; add(progressShot)
        let action = app.buttons["acquisitionStartPreview"]
        reveal(action, in: app)
        XCTAssertGreaterThanOrEqual(action.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, app.windows.firstMatch.frame.maxX)
        let large = XCTAttachment(screenshot: app.screenshot()); large.name = "Acquisition large"; large.lifetime = .keepAlways; add(large)
        action.tap()
        let submit = app.buttons["traitDrillSubmit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); reveal(submit, in: app)
        XCTAssertGreaterThanOrEqual(submit.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(submit.frame.maxX, app.windows.firstMatch.frame.maxX)
        let largeDrill = XCTAttachment(screenshot: app.screenshot()); largeDrill.name = "Detailed drill large"; largeDrill.lifetime = .keepAlways; add(largeDrill)
        submit.tap(); XCTAssertTrue(app.staticTexts["traitDrillFeedback"].waitForExistence(timeout: 5))
    }

    @MainActor func testTraitDrillExperienceInputsAndFiveAttempts() throws {
        let app = XCUIApplication(); app.launchArguments = ["-trait-acquisition-preview"]; app.launch()
        XCTAssertTrue(app.buttons["acquisitionStartPreview"].waitForExistence(timeout: 5))
        for id in ["strong-arm", "cheetah", "safe-hands"] {
            app.buttons["acquisitionTrait-" + id].tap(); app.buttons["acquisitionStartPreview"].tap()
            let arena = app.otherElements["traitDrillArena"]
            XCTAssertTrue(arena.waitForExistence(timeout: 5))
            let initial = XCTAttachment(screenshot: app.screenshot()); initial.name = "Detailed drill " + id; initial.lifetime = .keepAlways; add(initial)
            if id == "cheetah" {
                app.buttons["traitDrillLeft"].tap()
                XCUIDevice.shared.press(.home); app.activate()
                XCTAssertFalse(app.staticTexts["traitDrillFeedback"].exists)
                XCTAssertTrue(app.staticTexts["traitDrillSteps"].label.contains("0걸음"))
                app.buttons["traitDrillLeft"].tap(); app.buttons["traitDrillLeft"].tap()
                XCTAssertTrue(app.staticTexts["traitDrillSteps"].label.contains("1걸음"))
                app.buttons["traitDrillRight"].tap()
            } else if id == "safe-hands" {
                arena.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66)).press(forDuration: 0.1, thenDragTo: arena.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.48)))
                app.buttons["traitDrillSubmit"].tap()
            } else {
                app.buttons["traitDrillSubmit"].tap()
            }
            XCTAssertTrue(app.staticTexts["traitDrillFeedback"].waitForExistence(timeout: 7))
            if id != "cheetah" { XCTAssertTrue(app.staticTexts["traitDrillFeedback"].label.contains("GREAT")) }
            let feedback = XCTAttachment(screenshot: app.screenshot()); feedback.name = "Detailed feedback " + id; feedback.lifetime = .keepAlways; add(feedback)
            if id == "strong-arm" {
                for base in [2, 3, 2, 1] {
                    app.buttons["traitDrillNext"].tap()
                    app.buttons["traitDrillBase-\(base)"].tap()
                    let target = base == 2 ? CGVector(dx: 0.5, dy: 0.34) : base == 3 ? CGVector(dx: 0.22, dy: 0.63) : CGVector(dx: 0.78, dy: 0.63)
                    arena.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.63)).press(forDuration: 0.1, thenDragTo: arena.coordinate(withNormalizedOffset: target))
                    app.buttons["traitDrillSubmit"].tap()
                    XCTAssertTrue(app.staticTexts["traitDrillFeedback"].waitForExistence(timeout: 4))
                    XCTAssertTrue(app.staticTexts["traitDrillFeedback"].label.contains("GREAT"))
                }
                XCTAssertTrue(app.staticTexts["traitDrillResult"].exists)
                XCTAssertTrue(app.staticTexts["traitDrillResult"].label.contains("100점"))
                XCTAssertFalse(app.buttons["traitDrillNext"].exists)
            }
            app.buttons["acquisitionCloseDrill"].tap()
            XCTAssertEqual(app.staticTexts["acquisitionProgress"].label, "36.8 / 100.0")
        }
    }

    @MainActor func testTraitDetailBothRolesPersistenceAndLocks() throws {
        let app = XCUIApplication(); app.launch()
        for pitcher in [false, true] {
            if pitcher { reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap() }
            createDashboardSample(app, name: pitcher ? "TraitPitch" : "TraitBat")
            let date = app.staticTexts["calendarDate"].label, fatigue = app.staticTexts["homeFatigue"].label
            expandHomeDetails("traitDetails", in: app)
            XCTAssertTrue(app.staticTexts["traitPlayerName"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["traitActiveCount"].label, "활성 1 / 3")
            for id in ["strong-arm", "cheetah", "safe-hands"] {
                let condition = app.staticTexts["traitCondition-" + id]
                reveal(condition, in: app); XCTAssertTrue(condition.exists)
                XCTAssertTrue(app.staticTexts["traitEffect-" + id].exists)
            }
            let toggles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traitToggle-"))
            XCTAssertEqual(toggles.count, 1); let id = toggles.firstMatch.identifier
            reveal(app.buttons[id], in: app); app.buttons[id].tap()
            reveal(app.staticTexts["traitActiveCount"], in: app); XCTAssertEqual(app.staticTexts["traitActiveCount"].label, "활성 0 / 3")
            let normal = XCTAttachment(screenshot: app.screenshot()); normal.name = pitcher ? "Trait pitcher board" : "Trait batter board"; normal.lifetime = .keepAlways; add(normal)
            app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
            if role.exists { reveal(role, in: app); role.tap() }
            expandHomeDetails("traitDetails", in: app)
            XCTAssertTrue(app.staticTexts["traitPlayerName"].waitForExistence(timeout: 5))
            reveal(app.staticTexts["traitActiveCount"], in: app); XCTAssertEqual(app.staticTexts["traitActiveCount"].label, "활성 0 / 3")
            reveal(app.buttons[id], in: app); XCTAssertTrue(app.buttons[id].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.minX, app.windows.firstMatch.frame.minX)
            XCTAssertLessThanOrEqual(app.buttons[id].frame.maxX, app.windows.firstMatch.frame.maxX)
            app.buttons[id].tap()
            let large = XCTAttachment(screenshot: app.screenshot()); large.name = pitcher ? "Trait pitcher large text" : "Trait batter large text"; large.lifetime = .keepAlways; add(large)
            app.terminate(); app.launchArguments = []; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            let restored = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
            if restored.exists { reveal(restored, in: app); restored.tap() }
            XCTAssertEqual(app.staticTexts["calendarDate"].label, date); XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
            if pitcher {
                reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
                XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 5)); app.buttons["startTraining"].tap()
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else { reveal(app.buttons["restToday"], in: app); app.buttons["restToday"].tap() }
            expandHomeDetails("traitDetails", in: app)
            XCTAssertTrue(app.staticTexts["traitLocked"].waitForExistence(timeout: 5))
            reveal(app.buttons[id], in: app); XCTAssertFalse(app.buttons[id].isEnabled)
            reveal(app.staticTexts["traitActiveCount"], in: app); XCTAssertEqual(app.staticTexts["traitActiveCount"].label, "활성 1 / 3")
            let locked = XCTAttachment(screenshot: app.screenshot()); locked.name = pitcher ? "Trait training locked" : "Trait rest locked"; locked.lifetime = .keepAlways; add(locked)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.staticTexts["homePlayerName"], in: app)
        }
    }

    @MainActor func testCustomCreationBothRolesAndRegistration() throws {
        let app = XCUIApplication(); app.launch()
        for pitcher in [false, true] {
            if pitcher {
                app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
                XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
                reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
            }
            let name = app.textFields["playerName"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(pitcher ? "CustomPitch" : "CustomBat")
            if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
            reveal(app.buttons["randomSchool"], in: app); app.buttons["randomSchool"].tap()
            reveal(app.buttons["archetype-custom"], in: app); app.buttons["archetype-custom"].tap()
            XCTAssertTrue(app.buttons["archetype-custom"].isSelected)
            let kind = pitcher ? "velocity" : "contact"
            let minus = app.buttons["allocation-" + kind + "-minus"]
            reveal(minus, in: app); minus.tap()
            reveal(app.staticTexts["allocationRemaining"], in: app)
            XCTAssertEqual(app.staticTexts["allocationRemaining"].label, pitcher ? "남은 1 / 459점" : "남은 1 / 388점")
            reveal(app.buttons["createPlayer"], in: app); XCTAssertFalse(app.buttons["createPlayer"].isEnabled)
            let mental = app.buttons["allocation-mental-plus"]; reveal(mental, in: app); mental.tap()
            XCTAssertFalse(mental.isEnabled)
            reveal(app.staticTexts["allocationRemaining"], in: app)
            XCTAssertEqual(app.staticTexts["allocationRemaining"].label, pitcher ? "남은 0 / 459점" : "남은 0 / 388점")
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Custom pitcher allocation large" : "Custom batter allocation"; shot.lifetime = .keepAlways; add(shot)
            reveal(app.buttons["createPlayer"], in: app); XCTAssertTrue(app.buttons["createPlayer"].isEnabled); app.buttons["createPlayer"].tap()
            // Successful persistence is followed by a short presentation-only registration state.
            let registered = app.descendants(matching: .any).matching(identifier: "creationRegistered").firstMatch
            XCTAssertTrue(registered.exists)
            let registration = XCTAttachment(screenshot: app.screenshot()); registration.name = pitcher ? "Pitcher registration" : "Batter registration"; registration.lifetime = .keepAlways; add(registration)
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            reveal(app.staticTexts["homeArchetype"], in: app); XCTAssertEqual(app.staticTexts["homeArchetype"].label, "사용자 지정")
            app.terminate(); app.launchArguments = []; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
            let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
            if role.exists { reveal(role, in: app); role.tap() }
            reveal(app.staticTexts["homeArchetype"], in: app); XCTAssertEqual(app.staticTexts["homeArchetype"].label, "사용자 지정")
            reveal(app.staticTexts["homePlayerName"], in: app)
        }
    }

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

    @MainActor func testTrainingLargeTextNavigation() throws {
        let app = XCUIApplication(); app.launch()
        createDashboardSample(app, name: "ScrollBatter")
        reveal(app.buttons["createOtherRole"], in: app); app.buttons["createOtherRole"].tap()
        createDashboardSample(app, name: "ScrollPitch")
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.buttons["startTraining"].tap()
        checkLargeTraining(app, name: "pitch role restore", pitcher: true)
    }

    @MainActor func testTrainingSessionCoachingLargeTextAndResume() throws {
        let app = XCUIApplication(); app.launch()
        app.buttons["role-pitcher"].tap(); createDashboardSample(app, name: "SessionPitch")
        let day = app.staticTexts["calendarDate"].label
        let fatigue = app.staticTexts["homeFatigue"].label
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        app.buttons["startTraining"].tap()
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        reveal(app.buttons["openTraining"], in: app); app.buttons["openTraining"].tap()
        let jump = app.buttons["trainingJumpControls"]; reveal(jump, in: app); jump.tap()
        let attempt = app.buttons["trainingAttempt"]; reveal(attempt, in: app); attempt.tap(); attempt.tap()
        let next = app.buttons["trainingNext"]; XCTAssertTrue(next.waitForExistence(timeout: 8))
        reveal(next, in: app)
        XCTAssertTrue(next.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(next.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(next.frame.maxX, window.maxX)
        let coach = app.descendants(matching: .any).matching(identifier: "trainingCoach").firstMatch
        reveal(coach, in: app); XCTAssertTrue(coach.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Session coaching accessibility XXXL"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertEqual(app.staticTexts["calendarDate"].label, day)
        XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        reveal(app.buttons["openTraining"], in: app)
        XCTAssertTrue(app.buttons["openTraining"].label.contains("1/5")); app.buttons["openTraining"].tap()
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["trainingNext"].exists)
    }

    @MainActor private func createDashboardSample(_ app: XCUIApplication, name: String, motionStyle: Bool = false) {
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
        reveal(app.buttons["randomSchool"], in: app); app.buttons["randomSchool"].tap()
        if motionStyle { configureMotionStyle(app) }
        reveal(app.buttons["createPlayer"], in: app); app.buttons["createPlayer"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        let created = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", name), object: app.staticTexts["homePlayerName"])
        XCTAssertEqual(XCTWaiter.wait(for: [created], timeout: 5), .completed)
    }
    @MainActor private func configureMotionStyle(_ app: XCUIApplication) {
        // Move down the sheet once; swiping back to the top can dismiss creation.
        // Off-default numbers are covered pixel-by-pixel by the renderer tests.
        for label in ["피부 4", "머리색 3", "유니폼 5"] { reveal(app.buttons[label],in:app);app.buttons[label].tap() }
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
            XCTAssertTrue(app.buttons["traitDetails"].isHittable)
            expandHomeDetails("traitDetails", in: app)
            XCTAssertEqual(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traitCard-")).count, 3)
            app.navigationBars.buttons.element(boundBy: 0).tap()
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

extension CareerFlowTests {
    @MainActor func testAnnualLeagueBothRolesActualResultsDateAdvanceAndReload() throws {
        let app=XCUIApplication();app.launch()
        for pitcher in [false,true] {
            if pitcher {reveal(app.buttons["createOtherRole"],in:app);app.buttons["createOtherRole"].tap()}
            createDashboardSample(app,name:pitcher ? "LeaguePitch":"LeagueBat")
            reveal(app.buttons["openAnnualLeague"],in:app);app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueProgress"].waitForExistence(timeout:5))
            XCTAssertTrue(app.staticTexts["leagueProgress"].label.contains("완료 0 / 대상 90"))
            let own=app.descendants(matching:.any).matching(identifier:"leagueOwnStanding").firstMatch
            XCTAssertTrue(own.label.contains("0경기"));XCTAssertTrue(app.staticTexts["leagueEmpty"].exists)
            app.navigationBars.buttons.element(boundBy:0).tap()
            reveal(app.buttons["restToday"],in:app);app.buttons["restToday"].tap()
            reveal(app.buttons["openCareerGame"],in:app);app.buttons["openCareerGame"].tap()
            XCTAssertTrue(app.buttons["gameAutomatic"].waitForExistence(timeout:5));app.buttons["gameAutomatic"].tap();app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout:8))
            reveal(app.buttons["gameReturnHome"],in:app);app.buttons["gameReturnHome"].tap()
            reveal(app.staticTexts["homeLeagueRecord"],in:app)
            let home=app.staticTexts["homeLeagueRecord"].label;XCTAssertTrue(home.contains("1경기"))
            let seasonHome = app.descendants(matching: .any).matching(identifier: "homeSeasonTotals").firstMatch
            reveal(seasonHome, in: app); XCTAssertTrue(seasonHome.label.contains("1경기"))
            let homeTotals = seasonHome.label
            app.buttons["openSeasonSummary"].tap()
            XCTAssertTrue(app.staticTexts["seasonProgress"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["seasonProgress"].label.contains("완료 1 / 대상 90"))
            XCTAssertFalse(app.staticTexts["seasonChampion"].exists)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch.label, homeTotals)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueProgress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["leagueProgress"].label.contains("완료 1 / 대상 90"))
            let actual=app.descendants(matching:.any).matching(identifier:"leagueOwnStanding").firstMatch.label
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name=pitcher ? "League pitcher actual result":"League batter actual result";shot.lifetime = .keepAlways;add(shot)
            app.navigationBars.buttons.element(boundBy:0).tap()
            app.terminate();app.launch()
            selectLeagueRole(app,pitcher:pitcher)
            XCTAssertEqual(app.staticTexts["calendarDate"].label,"2026-04-01")
            reveal(app.staticTexts["homeLeagueRecord"],in:app);XCTAssertEqual(app.staticTexts["homeLeagueRecord"].label,home)
            reveal(app.buttons["advanceDay"],in:app);app.buttons["advanceDay"].tap()
            let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","2026-04-02"),object:app.staticTexts["calendarDate"])
            XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:5),.completed)
            let fatigue=app.staticTexts["homeFatigue"].label
            reveal(app.buttons["openAnnualLeague"],in:app);app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueProgress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["leagueProgress"].label.contains("완료 3 / 대상 90"))
            let afterOwn=app.descendants(matching:.any).matching(identifier:"leagueOwnStanding").firstMatch.label
            XCTAssertEqual(afterOwn.components(separatedBy:" · ").first,actual.components(separatedBy:" · ").first)
            XCTAssertEqual(Array(afterOwn.components(separatedBy:" · ").suffix(2)),Array(actual.components(separatedBy:" · ").suffix(2)))
            let rows=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","leagueStanding-")).allElementsBoundByIndex
            XCTAssertEqual(rows.count,5)
            for row in rows {XCTAssertGreaterThanOrEqual(row.frame.minX,0);XCTAssertLessThanOrEqual(row.frame.maxX,app.windows.firstMatch.frame.maxX)}
            let after=XCTAttachment(screenshot:app.screenshot());after.name=pitcher ? "League pitcher other teams completed":"League batter other teams completed";after.lifetime = .keepAlways;add(after)
            app.terminate();app.launchArguments=["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
            selectLeagueRole(app,pitcher:pitcher)
            reveal(app.buttons["openAnnualLeague"],in:app);app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueProgress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["leagueProgress"].label.contains("완료 3 / 대상 90"))
            let largeOwn=app.descendants(matching:.any).matching(identifier:"leagueOwnStanding").firstMatch
            reveal(largeOwn,in:app);XCTAssertEqual(largeOwn.label,afterOwn)
            let large=XCTAttachment(screenshot:app.screenshot());large.name=pitcher ? "League pitcher accessibility text":"League batter accessibility text";large.lifetime = .keepAlways;add(large)
            app.terminate();app.launchArguments=[];app.launch()
            selectLeagueRole(app,pitcher:pitcher)
            reveal(app.staticTexts["homeFatigue"],in:app);XCTAssertEqual(app.staticTexts["homeFatigue"].label,fatigue)
        }
    }
}

extension CareerFlowTests {
    @MainActor private func selectLeagueRole(_ app:XCUIApplication,pitcher:Bool) {
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:5))
        let button=app.buttons[pitcher ? "homeRole-pitcher":"homeRole-batter"]
        if button.exists {reveal(button,in:app);button.tap()}
        let selected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@",pitcher ? "LeaguePitch":"LeagueBat"),object:app.staticTexts["homePlayerName"])
        XCTAssertEqual(XCTWaiter.wait(for:[selected],timeout:5),.completed)
    }
}

extension CareerFlowTests {
    @MainActor func testSeasonFinalBothRolesAndLargeTextIsolatedRealLedger() throws {
        let app = XCUIApplication(); app.launchArguments = ["-season-summary-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            reveal(app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"], in: app)
            app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"].tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(pitcher ? "SeasonPitch" : "SeasonBat"))
            let date = app.staticTexts["calendarDate"].label, fatigue = app.staticTexts["homeFatigue"].label
            reveal(app.buttons["openSeasonSummary"], in: app); app.buttons["openSeasonSummary"].tap()
            XCTAssertTrue(app.staticTexts["seasonChampion"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["seasonChampion"].label.isEmpty)
            XCTAssertTrue(app.staticTexts["seasonProgress"].label.contains("90경기 확정"))
            let stats = app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch
            reveal(stats, in: app); XCTAssertTrue(stats.label.contains(pitcher ? "6경기" : "30경기"))
            XCTAssertFalse(stats.label.contains("ERA"))
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Season final pitcher" : "Season final batter"; shot.lifetime = .keepAlways; add(shot)
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "seasonStanding-")).allElementsBoundByIndex
            XCTAssertEqual(rows.count, 6)
            for row in rows { reveal(row, in: app); XCTAssertTrue(row.label.contains("30경기")); XCTAssertLessThanOrEqual(row.frame.maxX, app.windows.firstMatch.frame.maxX) }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].label, date); XCTAssertEqual(app.staticTexts["homeFatigue"].label, fatigue)
        }
        app.terminate(); app.launchArguments = ["-season-summary-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        for pitcher in [false, true] {
            reveal(app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"], in: app); app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"].tap()
            reveal(app.buttons["openSeasonSummary"], in: app); app.buttons["openSeasonSummary"].tap()
            XCTAssertTrue(app.staticTexts["seasonChampion"].waitForExistence(timeout: 5))
            let stats = app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch
            reveal(stats, in: app); XCTAssertTrue(stats.label.contains(pitcher ? "6경기" : "30경기"))
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Season large pitcher" : "Season large batter"; shot.lifetime = .keepAlways; add(shot)
            XCTAssertLessThanOrEqual(stats.frame.maxX, app.windows.firstMatch.frame.maxX)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}

extension CareerFlowTests {
    @MainActor private func openOffseasonRole(_ app: XCUIApplication, pitcher: Bool) {
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 40))
        let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]
        reveal(role, in: app); role.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(pitcher ? "SeasonPitch" : "SeasonBat"))
        reveal(app.buttons["openSeasonSummary"], in: app); app.buttons["openSeasonSummary"].tap()
        XCTAssertTrue(app.staticTexts["seasonChampion"].waitForExistence(timeout: 5))
    }
    @MainActor func testOffseasonBothRolesOpeningDiskResumeAndPastFinalUnchanged() throws {
        let app = XCUIApplication(); app.launchArguments = ["-offseason-verification"]; app.launch()
        for pitcher in [false, true] {
            openOffseasonRole(app, pitcher: pitcher)
            let champion = app.staticTexts["seasonChampion"].label
            let stats = app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch.label
            for (index, date) in ["2026-10-23", "2026-11-22", "2026-12-22", "2027-01-21", "2027-02-20", "2027-03-22", "2027-03-31"].enumerated() {
                let next = app.buttons["advanceOffseason"]; reveal(next, in: app); XCTAssertTrue(next.isEnabled); next.tap()
                let dates = app.staticTexts["offseasonDates"]
                let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", date), object: dates)
                XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 10), .completed)
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["careerTransition"])
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
                if index == 3 {
                    app.terminate(); app.launch(); openOffseasonRole(app, pitcher: pitcher)
                    reveal(app.staticTexts["offseasonDates"], in: app)
                    XCTAssertTrue(app.staticTexts["offseasonDates"].label.hasPrefix(date))
                    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Offseason pitcher year resume" : "Offseason batter year resume"; shot.lifetime = .keepAlways; add(shot)
                }
            }
            XCTAssertTrue(app.staticTexts["offseasonAge"].label.contains("16세 → 17세"))
            reveal(app.buttons["advanceOffseason"], in: app); app.buttons["advanceOffseason"].tap()
            XCTAssertTrue(app.buttons["확인하고 계속 진행"].waitForExistence(timeout: 5)); app.buttons["확인하고 계속 진행"].tap()
            XCTAssertTrue(app.staticTexts["offseasonUnavailable"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["advanceOffseason"].exists)
            XCTAssertEqual(app.staticTexts["seasonChampion"].label, champion)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch.label, stats)
            reveal(app.buttons["offseasonReturnHome"], in: app); app.buttons["offseasonReturnHome"].tap()
            XCTAssertTrue(app.staticTexts["calendarDate"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["calendarDate"].label, "2027-04-01")
            XCTAssertTrue(app.staticTexts["homeAge"].label.contains("17세 / 고2")); XCTAssertTrue(app.staticTexts["homeFatigue"].label.contains("피로 0 / 100"))
            XCTAssertTrue(app.staticTexts["calendarAction"].label.contains("미사용")); XCTAssertTrue(app.staticTexts["todaySchedule"].label.hasPrefix("1 / 30차전"))
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Offseason pitcher opening home" : "Offseason batter opening home"; shot.lifetime = .keepAlways; add(shot)
            app.terminate(); app.launch(); openOffseasonRoleAfterOpening(app, pitcher: pitcher)
            let previous = app.buttons["seasonPreviousYear"]; reveal(previous, in: app); previous.tap()
            XCTAssertTrue(app.staticTexts["seasonChampion"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["seasonChampion"].label, champion)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch.label, stats)
            XCTAssertFalse(app.buttons["advanceOffseason"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
    @MainActor private func openOffseasonRoleAfterOpening(_ app: XCUIApplication, pitcher: Bool) {
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 5))
        let role = app.buttons[pitcher ? "homeRole-pitcher" : "homeRole-batter"]; reveal(role, in: app); role.tap()
        XCTAssertEqual(app.staticTexts["calendarDate"].label, "2027-04-01")
        reveal(app.buttons["openSeasonSummary"], in: app); app.buttons["openSeasonSummary"].tap()
        XCTAssertTrue(app.staticTexts["seasonProgress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["seasonProgress"].label.contains("완료 0 / 대상 90"))
    }
}

extension CareerFlowTests {
    @MainActor func testOffseasonLargeTextBothRolesThirtyDayControlsAndSummary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-season-summary-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        for pitcher in [false, true] {
            openOffseasonRole(app, pitcher: pitcher)
            let next = app.buttons["advanceOffseason"]; reveal(next, in: app)
            XCTAssertTrue(next.isHittable); XCTAssertGreaterThanOrEqual(next.frame.height, 44)
            XCTAssertGreaterThanOrEqual(next.frame.minX, 0); XCTAssertLessThanOrEqual(next.frame.maxX, app.windows.firstMatch.frame.maxX)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = pitcher ? "Offseason large pitcher controls" : "Offseason large batter controls"; shot.lifetime = .keepAlways; add(shot)
            next.tap()
            let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "2026-10-23"), object: app.staticTexts["offseasonDates"])
            XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 15), .completed)
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["careerTransition"])
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
            reveal(app.staticTexts["offseasonSummary"], in: app)
            XCTAssertTrue(app.staticTexts["offseasonSummary"].label.contains("30일 진행"))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].label, "2026-10-23")
        }
    }
}
