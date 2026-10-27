import XCTest

/// Production screens with in-memory QA players; no installed player store is opened.
final class ManagementDetailFlowTests: XCTestCase {
    @MainActor func testV29CompactDirectFieldsAndActualTraceGesture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in ["power","velocity","stuff"] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if kind != "power" { pickPitcher(app) }
            app.buttons["managementTab-training"].tap(); app.buttons[kind == "power" ? "facility-training" : "facility-physical"].tap()
            revealLocationChoice(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            let field = app.descendants(matching: .any).matching(identifier: "skillPracticeField").firstMatch
            let action = kind == "power" ? app.staticTexts["skillPowerHold"] : app.buttons[kind == "velocity" ? "skillRhythmStart" : "skillTraceConfirm"]
            XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(app.frame.contains(field.frame)); XCTAssertTrue(app.frame.contains(action.frame))
            capture(app, "v29-small-\(kind)-ready")
            if kind == "power" { action.press(forDuration: 1.4) }
            else if kind == "velocity" { action.tap() }
            else {
                let trace = app.descendants(matching: .any).matching(identifier: "skillTraceBoard").firstMatch
                XCTAssertTrue(trace.exists)
                let before = trace.value as? String
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.794)).press(forDuration: 0.05,
                    thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.206)))
                XCTAssertNotEqual(trace.value as? String,before)
                capture(app,"v29-small-stuff-drawn")
                action.tap()
            }
            XCTAssertFalse(app.buttons["trainingNext"].exists)
            XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout: 9)); reveal(app.buttons["trainingNext"],app)
            XCTAssertTrue(app.buttons["trainingNext"].isHittable); capture(app,"v29-small-\(kind)-feedback")
        }
    }

    @MainActor func testV29ThreeSkillDrillsFiveAttemptsResumeAndOneReward() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in ["power","velocity","stuff"] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if kind != "power" { pickPitcher(app) }
            let before = status(app)
            app.buttons["managementTab-training"].tap(); app.buttons[kind == "power" ? "facility-training" : "facility-physical"].tap()
            revealLocationChoice(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            capture(app, "v29-\(kind)-direct-ready")
            for round in 1...5 {
                let progress = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
                XCTAssertTrue(progress.waitForExistence(timeout: 6)); XCTAssertTrue(progress.label.contains("\(round) / 5"))
                configureSkillButtons(kind, app)
                let confirm = app.buttons[kind == "power" ? "skillPowerConfirm" : kind == "velocity" ? "skillRhythmConfirm" : "skillTraceConfirm"]
                revealLocationChoice(confirm, app)
                if round == 1 { capture(app, "v29-\(kind)-button-ready") }
                confirm.tap(); XCTAssertFalse(app.buttons["trainingNext"].exists)
                XCTAssertFalse(app.buttons["skillInputMode"].isEnabled)
                if round == 1 { capture(app, "v29-\(kind)-motion") }
                XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout: 8))
                let grade = app.descendants(matching: .any).matching(identifier: "trainingGrade").firstMatch
                XCTAssertTrue(grade.exists); XCTAssertTrue(grade.label.contains("점"), grade.label)
                if round == 1 { capture(app, "v29-\(kind)-feedback") }
                reveal(app.buttons["trainingNext"], app); app.buttons["trainingNext"].tap()
                if round == 2 {
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                    reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
                    XCTAssertTrue(progress.waitForExistence(timeout: 5)); XCTAssertTrue(progress.label.contains("3 / 5"))
                    capture(app, "v29-\(kind)-resume")
                }
            }
            XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 6)); capture(app, "v29-\(kind)-result")
            let growth = app.staticTexts["trainingGrowth"].label
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout: 6)); XCTAssertEqual(app.staticTexts["trainingGrowth"].label, growth)
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["closeRoomDetail"].tap(); app.buttons["managementTab-home"].tap()
            let after = status(app); XCTAssertEqual(before[0],after[0]); XCTAssertEqual(after[2],"행동 0/1"); XCTAssertNotEqual(before[1],after[1])
        }
    }

    @MainActor func testV29DirectPowerHoldAndRhythmTimeout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in ["power","velocity"] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if kind != "power" { pickPitcher(app) }
            app.buttons["managementTab-training"].tap(); app.buttons[kind == "power" ? "facility-training" : "facility-physical"].tap()
            revealLocationChoice(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            if kind == "power" {
                let hold = app.staticTexts["skillPowerHold"]
                revealLocationChoice(hold, app); hold.press(forDuration: 1.4)
            } else { reveal(app.buttons["skillRhythmStart"], app); app.buttons["skillRhythmStart"].tap() }
            XCTAssertFalse(app.buttons["trainingNext"].exists)
            XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout: 9))
            let grade = app.descendants(matching: .any).matching(identifier: "trainingGrade").firstMatch
            XCTAssertTrue(grade.exists)
            if kind == "velocity" { XCTAssertTrue(grade.label.contains("0점")) }
            capture(app, "v29-\(kind)-direct-feedback")
        }
    }

    @MainActor func testV29LargeReducedPracticeAllThreeDrills() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in ["power","velocity","stuff"] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-management-reduced-motion-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if kind != "power" { pickPitcher(app) }
            let before = status(app)
            app.buttons["managementLargeMenu"].tap(); app.buttons["훈련"].tap()
            reveal(app.buttons["facility-practice"], app); app.buttons["facility-practice"].tap()
            reveal(app.buttons["openTrainingPractice"], app); app.buttons["openTrainingPractice"].tap()
            reveal(app.buttons["practiceGeneralTraining"], app); app.buttons["practiceGeneralTraining"].tap()
            let category = app.buttons[kind == "power" ? "trainingCategory-0" : "trainingCategory-2"]
            revealLocationChoice(category, app); category.tap()
            revealLocationChoice(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            configureSkillButtons(kind, app)
            let confirm = app.buttons[kind == "power" ? "skillPowerConfirm" : kind == "velocity" ? "skillRhythmConfirm" : "skillTraceConfirm"]
            revealLocationChoice(confirm, app); XCTAssertTrue(confirm.isHittable); capture(app, "v29-large-\(kind)-ready")
            confirm.tap(); XCTAssertFalse(app.buttons["trainingNext"].exists)
            XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout: 9)); reveal(app.buttons["trainingNext"], app)
            XCTAssertTrue(app.buttons["trainingNext"].isHittable); capture(app, "v29-large-\(kind)-feedback")
            app.buttons["trainingNext"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["closeRoomDetail"].tap()
            app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap(); XCTAssertEqual(status(app),before)
        }
    }

    @MainActor private func configureSkillButtons(_ kind: String, _ app: XCUIApplication) {
        let mode = app.buttons["skillInputMode"]
        revealLocationChoice(mode, app)
        if mode.label.contains("버튼 조작으로") { mode.tap() }
        if kind == "power" {
            let slider = app.sliders["skillSlider-힘 풀기 위치"]
            revealLocationChoice(slider, app); slider.adjust(toNormalizedSliderPosition: 0.5)
        } else if kind == "velocity" {
            for (i,time) in [0.65,1.35,2.05].enumerated() {
                let slider = app.sliders["skillSlider-\(i+1)박 초"]
                revealLocationChoice(slider, app); slider.adjust(toNormalizedSliderPosition: time / 2.4)
            }
        } else {
            for i in 0..<3 {
                let goal = app.staticTexts["skillAnchorGoal-\(i)"]
                revealLocationChoice(goal, app)
                let percent = Double(goal.label.components(separatedBy: " ").last ?? "") ?? 50
                let slider = app.sliders["skillSlider-\(i+1)번 가로"]
                revealLocationChoice(slider, app); slider.adjust(toNormalizedSliderPosition: percent / 100)
            }
        }
    }

    @MainActor func testV28SmallLocationTrainingFieldAndControlsFit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            app.buttons["managementTab-training"].tap(); app.buttons["facility-physical"].tap()
            let kind = app.buttons[pitcher ? "trainingKind-control" : "trainingKind-defense"]
            reveal(kind, app); kind.tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            let field = app.descendants(matching: .any).matching(identifier: "trainingField").firstMatch
            let attempt = app.buttons["trainingAttempt"]
            XCTAssertTrue(attempt.waitForExistence(timeout: 5))
            XCTAssertTrue(app.frame.contains(field.frame)); XCTAssertTrue(app.frame.contains(attempt.frame)); XCTAssertTrue(attempt.isHittable)
            XCTAssertGreaterThanOrEqual(field.frame.height, 150)
            let before = field.value as? String
            app.buttons["locationMove-오른쪽"].tap(); XCTAssertNotEqual(field.value as? String, before)
            capture(app, pitcher ? "v28-small-control-ready" : "v28-small-defense-ready")
            attempt.tap(); XCTAssertFalse(app.buttons["trainingNext"].exists)
            XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout: 8))
            reveal(app.buttons["trainingNext"], app); XCTAssertTrue(app.buttons["trainingNext"].isHittable)
            capture(app, pitcher ? "v28-small-control-feedback" : "v28-small-defense-feedback")
        }
    }

    @MainActor func testV28LocationCareerTrainingMotionResumeAndOneReward() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for (pitcher, kind) in [(true, "control"), (false, "defense"), (true, "defense")] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            let before = status(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-physical"].tap()
            reveal(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            let role = pitcher ? "pitcher" : "batter"
            for round in 1...5 {
                let progress = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
                XCTAssertTrue(progress.waitForExistence(timeout: 5)); XCTAssertTrue(progress.label.contains("\(round) / 5"))
                let move = app.buttons["locationMove-오른쪽"]
                reveal(move, app); XCTAssertGreaterThanOrEqual(move.frame.height, 44); move.tap()
                let attempt = app.buttons["trainingAttempt"]
                reveal(attempt, app); XCTAssertTrue(attempt.isHittable)
                if round == 1 { capture(app, "v28-\(role)-\(kind)-ready") }
                attempt.tap()
                XCTAssertFalse(app.buttons["trainingNext"].exists)
                XCTAssertFalse(app.staticTexts["locationPracticeComparison"].exists)
                XCTAssertFalse(move.isEnabled)
                if round == 1 { capture(app, "v28-\(role)-\(kind)-motion") }
                let next = app.buttons["trainingNext"]
                XCTAssertTrue(next.waitForExistence(timeout: 8))
                XCTAssertTrue(app.staticTexts["locationPracticeComparison"].exists)
                if round == 1 { capture(app, "v28-\(role)-\(kind)-feedback") }
                reveal(next, app); next.tap()
                if round == 2 {
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                    reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
                    XCTAssertTrue(progress.waitForExistence(timeout: 5)); XCTAssertTrue(progress.label.contains("3 / 5"))
                    capture(app, "v28-\(role)-\(kind)-resumed-third-attempt")
                }
            }
            let completed = app.staticTexts["trainingCompleted"]
            XCTAssertTrue(completed.waitForExistence(timeout: 5)); capture(app, "v28-\(role)-\(kind)-result")
            let growth = app.staticTexts["trainingGrowth"].label
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(completed.waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["trainingGrowth"].label, growth)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["closeRoomDetail"].tap(); app.buttons["managementTab-home"].tap()
            let after = status(app)
            XCTAssertEqual(after[0], before[0]); XCTAssertEqual(after[2], "행동 0/1")
            XCTAssertNotEqual(after[1], before[1])
        }
    }

    @MainActor func testV28LargeTextReducedMotionPracticeLocationControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-management-reduced-motion-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            let before = status(app)
            app.buttons["managementLargeMenu"].tap(); app.buttons["훈련"].tap()
            reveal(app.buttons["facility-practice"], app); app.buttons["facility-practice"].tap()
            reveal(app.buttons["openTrainingPractice"], app); app.buttons["openTrainingPractice"].tap()
            reveal(app.buttons["practiceGeneralTraining"], app); app.buttons["practiceGeneralTraining"].tap()
            let category = app.buttons[pitcher ? "trainingCategory-2" : "trainingCategory-1"]
            revealLocationChoice(category, app); category.tap(); XCTAssertTrue(category.isSelected)
            let kind = app.buttons[pitcher ? "trainingKind-control" : "trainingKind-defense"]
            revealLocationChoice(kind, app); kind.tap()
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            let move = app.buttons["locationMove-오른쪽"]
            reveal(move, app); XCTAssertTrue(move.isHittable); XCTAssertGreaterThanOrEqual(move.frame.height, 44); move.tap()
            let attempt = app.buttons["trainingAttempt"]
            reveal(attempt, app); XCTAssertTrue(app.frame.contains(attempt.frame))
            capture(app, pitcher ? "v28-large-reduced-control-ready" : "v28-large-reduced-defense-ready")
            attempt.tap(); XCTAssertFalse(app.buttons["trainingNext"].exists)
            let next = app.buttons["trainingNext"]
            XCTAssertTrue(next.waitForExistence(timeout: 8)); reveal(next, app)
            XCTAssertTrue(next.isHittable); XCTAssertLessThanOrEqual(next.frame.maxX, app.frame.width)
            capture(app, pitcher ? "v28-large-reduced-control-feedback" : "v28-large-reduced-defense-feedback")
            next.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["closeRoomDetail"].tap()
            app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap()
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testV27LiveInningScoreboardsAndResumeBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            app.buttons["clubhouse-rest"].tap(); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
            app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let board = app.descendants(matching: .any).matching(identifier: "careerGameScore").firstMatch
            XCTAssertTrue(board.waitForExistence(timeout: 8)); XCTAssertTrue(board.label.contains("1회"))
            XCTAssertTrue(board.label.contains("9회 미시작")); XCTAssertFalse(board.label.contains("미기록"))
            XCTAssertTrue(app.frame.contains(board.frame))
            XCTAssertTrue(app.buttons[pitcher ? "gamePitch" : "battingTouchSurface"].isHittable)
            capture(app, pitcher ? "v27-pitcher-live-innings" : "v27-batter-live-innings")
            if pitcher { app.buttons["gamePitch"].tap(); app.buttons["gameRelease"].tap() }
            else { app.buttons["gameInput-watch"].tap(); app.buttons["battingTouchSurface"].tap() }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: app.buttons["gameAutomatic"])
            // A home run includes all four bases and its result receipt before returning to pitching.
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
            let score = board.label
            app.buttons["closeRoomDetail"].tap()
            XCTAssertTrue(app.buttons["homeTodayGame"].waitForExistence(timeout: 6)); app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(board.waitForExistence(timeout: 8)); XCTAssertEqual(board.label, score)
            capture(app, pitcher ? "v27-pitcher-resumed-innings" : "v27-batter-resumed-innings")
        }
    }

    @MainActor func testV27LargeInningScoreboardsBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            reveal(app.buttons["clubhouse-rest"], app); app.buttons["clubhouse-rest"].tap()
            reveal(app.buttons["confirmRest"], app); app.buttons["confirmRest"].tap()
            reveal(app.buttons["restDone"], app); app.buttons["restDone"].tap()
            reveal(app.buttons["homeTodayGame"], app); app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            for side in ["away", "home"] {
                let row = app.descendants(matching: .any).matching(identifier: "boardTeam-" + side).firstMatch
                reveal(row, app); XCTAssertTrue(row.exists); XCTAssertTrue(row.label.contains("1회"))
                XCTAssertTrue(row.label.contains("9회 미시작")); XCTAssertFalse(row.label.contains("미기록"))
                XCTAssertGreaterThanOrEqual(row.frame.minX, 0); XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.width)
            }
            capture(app, pitcher ? "v27-large-pitcher-innings" : "v27-large-batter-innings")
        }
    }

    @MainActor func testV26CreationThreeAndFivePitchSelectionsMatchHomeLibrary() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let defaults = ["four-seam", "slider", "changeup", "fork"]
        for count in [3, 5] {
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-management-empty-verification"]
            app.launch()
            let name = app.textFields["playerName"]
            XCTAssertTrue(name.waitForExistence(timeout: 15))
            name.tap(); name.typeText("V26Pitch\(count)")
            if app.buttons["입력 완료"].exists { app.buttons["입력 완료"].tap() }
            reveal(app.buttons["role-pitcher"], app); app.buttons["role-pitcher"].tap()
            reveal(app.buttons["randomSchool"], app); app.buttons["randomSchool"].tap()
            for code in defaults {
                let pitch = app.buttons["creationPitch-" + code]
                reveal(pitch, app); XCTAssertTrue(pitch.isSelected)
                XCTAssertGreaterThanOrEqual(pitch.frame.height, 44)
            }
            let countBadge = app.descendants(matching: .any).matching(identifier: "creationPitchCount").firstMatch
            reveal(countBadge, app); XCTAssertTrue(countBadge.label.contains("보유 4 / 5"))
            let selected: [String]
            if count == 3 {
                let fork = app.buttons["creationPitch-fork"]; reveal(fork, app); fork.tap()
                selected = Array(defaults.prefix(3))
                let minimum = app.buttons["creationPitch-slider"]
                reveal(minimum, app); XCTAssertTrue(minimum.isSelected); XCTAssertFalse(minimum.isEnabled)
            } else {
                let curve = app.buttons["creationPitch-curve"]; reveal(curve, app); curve.tap()
                selected = defaults + ["curve"]
                let sixth = app.buttons["creationPitch-knuckle"]
                reveal(sixth, app); XCTAssertFalse(sixth.isSelected); XCTAssertFalse(sixth.isEnabled)
            }
            reveal(countBadge, app); XCTAssertTrue(countBadge.label.contains("보유 \(count) / 5"))
            capture(app, "v26-creation-\(count)-pitch-limits")
            reveal(app.buttons["createPlayer"], app); app.buttons["createPlayer"].tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("V26Pitch\(count)"))
            capture(app, "v26-created-\(count)-pitch-home")
            app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
            for code in selected {
                let mastery = app.descendants(matching: .any).matching(identifier: code).firstMatch
                reveal(mastery, app); XCTAssertTrue(mastery.exists, "Selected pitch \(code) must appear in player abilities")
            }
            capture(app, "v26-created-\(count)-pitch-abilities")
            reveal(app.buttons["openPitchLibrary"], app); app.buttons["openPitchLibrary"].tap()
            XCTAssertTrue(app.staticTexts["등록 구종 · \(count) / 5"].waitForExistence(timeout: 6))
            let owned = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "pitchLibraryOwned-"))
            XCTAssertEqual(Set(owned.allElementsBoundByIndex.map(\.identifier)), Set(selected.map { "pitchLibraryOwned-" + $0 }))
            capture(app, "v26-created-\(count)-pitch-library")
        }
    }

    @MainActor func testV26CurveStudyFiveAttemptsStoresProgressAndDailyLock() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); pickPitcher(app)
        let before = status(app)
        app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
        reveal(app.buttons["openPitchLibrary"], app); app.buttons["openPitchLibrary"].tap()
        XCTAssertTrue(app.staticTexts["등록 구종 · 4 / 5"].waitForExistence(timeout: 6))
        let progress = app.staticTexts["pitchStudyProgress-curve"]
        reveal(progress, app); let priorProgress = progress.label
        XCTAssertTrue(priorProgress.contains("0.0 / 100"))
        let start = app.buttons["pitchStudyStart-curve"]
        reveal(start, app); XCTAssertTrue(start.isEnabled); capture(app, "v26-curve-study-ready"); start.tap()
        let confirm = app.buttons.matching(identifier: "pitchStudyConfirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.tap()
        let begin = app.buttons["startTraining"]
        XCTAssertTrue(begin.waitForExistence(timeout: 6)); reveal(begin, app); begin.tap()
        for round in 1...5 {
            let attempt = app.buttons["trainingAttempt"]
            reveal(attempt, app)
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: attempt)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            attempt.tap()
            attempt.tap()
            let next = app.buttons["trainingNext"]
            XCTAssertTrue(next.waitForExistence(timeout: 10), "Round \(round) must finish flight and coaching")
            if round == 1 { capture(app, "v26-curve-study-first-coaching") }
            reveal(next, app); next.tap()
        }
        let result = app.staticTexts["pitchStudyResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 6))
        let afterText = try XCTUnwrap(result.label.components(separatedBy: "→").last?.components(separatedBy: "/").first)
        let after = try XCTUnwrap(Double(afterText.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertGreaterThan(after, 0); XCTAssertLessThan(after, 100)
        capture(app, "v26-curve-study-growth-result")
        reveal(app.buttons["trainingReturnHome"], app); app.buttons["trainingReturnHome"].tap()
        XCTAssertTrue(app.staticTexts["등록 구종 · 4 / 5"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pitchLibraryOwned-curve").firstMatch.exists)
        reveal(progress, app); XCTAssertNotEqual(progress.label, priorProgress)
        reveal(start, app); XCTAssertFalse(start.isEnabled)
        let locked = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "오늘 행동을 사용했습니다")).firstMatch
        reveal(locked, app); XCTAssertTrue(locked.exists)
        capture(app, "v26-curve-study-progress-and-daily-lock")
        app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
        XCTAssertEqual(status(app)[0], before[0]); XCTAssertEqual(status(app)[2], "행동 0/1")
        capture(app, "v26-curve-study-home-action-used")
    }

    @MainActor func testPlayerLeagueAndFrozenScoutBoardsBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app)
            let role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
            XCTAssertTrue(app.otherElements["notebookIdentity"].exists || app.descendants(matching: .any).matching(identifier: "notebookIdentity").firstMatch.exists)
            capture(app, role + "-notebook-identity")
            let chart = app.descendants(matching: .any).matching(identifier: "homeAbilityRadar").firstMatch
            reveal(chart, app); XCTAssertTrue(chart.isHittable)
            capture(app, role + "-notebook-abilities")
            close(app); XCTAssertEqual(status(app), before)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-standings"].tap()
            XCTAssertTrue(app.staticTexts["homeLeagueRecord"].waitForExistence(timeout: 8))
            capture(app, role + "-league-overview")
            reveal(app.buttons["openAnnualLeague"], app); app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueProgress"].waitForExistence(timeout: 6))
            capture(app, role + "-league-scoreboard")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
            app.buttons["managementTab-career"].tap(); app.buttons["facility-observation"].tap()
            XCTAssertTrue(app.staticTexts["scoutSavedPeriod"].waitForExistence(timeout: 8))
            let savedPeriod = app.staticTexts["scoutSavedPeriod"].label
            capture(app, role + "-scout-desk")
            reveal(app.buttons["openSavedScoutingReport"], app); app.buttons["openSavedScoutingReport"].tap()
            XCTAssertTrue(app.staticTexts["scoutFrozenDate"].waitForExistence(timeout: 5))
            let frozenDate = app.staticTexts["scoutFrozenDate"].label
            capture(app, role + "-scout-frozen-identity")
            let gradeID = pitcher ? "starter" : "slugger"
            let grade = app.descendants(matching: .any).matching(identifier: "scoutGrade-" + gradeID).firstMatch
            reveal(grade, app); XCTAssertTrue(grade.exists)
            capture(app, role + "-scout-role-evaluation")
            let samples = app.staticTexts["scoutFrozenSample"]
            reveal(samples, app); XCTAssertTrue(samples.exists)
            capture(app, role + "-scout-sample")
            let clubs = app.buttons["scoutClubDetails"]
            reveal(clubs, app); XCTAssertTrue(clubs.exists); clubs.tap()
            let club = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scoutClub-")).firstMatch
            reveal(club, app); XCTAssertTrue(club.exists)
            capture(app, role + "-scout-club-comparison")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.staticTexts["scoutSavedPeriod"], app); XCTAssertEqual(app.staticTexts["scoutSavedPeriod"].label, savedPeriod)
            reveal(app.buttons["openSavedScoutingReport"], app); app.buttons["openSavedScoutingReport"].tap()
            XCTAssertEqual(app.staticTexts["scoutFrozenDate"].label, frozenDate)
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testLineupPowerTendenciesAndRealSeasonBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app)
            openOpponent(app)
            app.buttons["opponentTab-lineup"].tap()
            let first = app.buttons["opponentBatter-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.label.contains("파워")); XCTAssertTrue(first.label.contains("출루 성향")); XCTAssertTrue(first.label.contains("장타 성향"))
            capture(app, pitcher ? "pitcher-lineup-power" : "batter-lineup-power")
            app.buttons["opponentLineupSeason"].tap()
            XCTAssertTrue(first.label.contains("타율")); XCTAssertTrue(first.label.contains("OPS"))
            capture(app, pitcher ? "pitcher-lineup-season" : "batter-lineup-season")
            app.buttons["opponentLineupAbilities"].tap()
            let ninth = app.buttons["opponentBatter-9"]; reveal(ninth, app); ninth.tap()
            XCTAssertTrue(app.staticTexts["opponentIdentity"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["opponentIdentity"].label.contains("9번"))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "opponentStat-WAR").firstMatch.value as? String, "미집계")
            capture(app, pitcher ? "pitcher-ninth-detail" : "batter-ninth-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testLargeTextKeepsDetailValuesAndLineupLabels() {
        let app = launch(large: true)
        app.buttons["managementLargeMenu"].tap(); app.buttons["선수"].tap()
        reveal(app.buttons["facility-abilities"], app); app.buttons["facility-abilities"].tap()
        let weak = app.descendants(matching: .any).matching(identifier: "notebookWeakness").firstMatch
        reveal(weak, app); XCTAssertTrue(weak.isHittable)
        capture(app, "large-notebook-values"); close(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap()
        reveal(app.buttons["facility-analysis"], app); app.buttons["facility-analysis"].tap()
        reveal(app.buttons["hubOpponentAnalysis"], app); app.buttons["hubOpponentAnalysis"].tap()
        XCTAssertTrue(app.buttons["opponentTab-lineup"].waitForExistence(timeout: 5)); app.buttons["opponentTab-lineup"].tap()
        reveal(app.buttons["opponentBatter-1"], app)
        XCTAssertTrue(app.buttons["opponentBatter-1"].label.contains("출루 성향"))
        XCTAssertTrue(app.buttons["opponentBatter-1"].label.contains("장타 성향"))
        capture(app, "large-lineup-labels")
    }

    @MainActor func testCurrentScoutingFileLargeTextBothRoles() {
        let app = launch(large: true)
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap()
                reveal(app.buttons["roomProfile"], app); app.buttons["roomProfile"].tap()
                app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { close(app) }
            }
            let before = status(app)
            app.buttons["managementLargeMenu"].tap(); app.buttons["커리어"].tap()
            reveal(app.buttons["facility-observation"], app); app.buttons["facility-observation"].tap()
            let current = app.buttons["openScoutingReport"]
            reveal(current, app); current.tap()
            XCTAssertTrue(app.staticTexts["scoutActualPlayer"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["scoutActualPlayer"].label.contains(pitcher ? "CareerPitch" : "CareerBat"))
            capture(app, pitcher ? "large-pitcher-current-scout" : "large-batter-current-scout")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testV20TraitsPositionsAndPreparationBothRoles() {
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-player"].tap(); app.buttons["facility-traits"].tap()
            reveal(app.buttons["traitDetails"], app); app.buttons["traitDetails"].tap()
            XCTAssertTrue(app.staticTexts["traitActiveCount"].waitForExistence(timeout: 5))
            capture(app, "v20-" + role + "-traits")
            let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traitToggle-")).firstMatch
            reveal(toggle, app); toggle.tap()
            reveal(app.staticTexts["traitActiveCount"], app)
            XCTAssertEqual(app.staticTexts["traitActiveCount"].label, "활성 0 / 3")
            reveal(toggle, app); toggle.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
            if !pitcher {
                app.buttons["managementTab-player"].tap(); app.buttons["facility-positions"].tap()
                let map = app.buttons["homePositionMap-1B"]; reveal(map, app); map.tap()
                let mastery = app.staticTexts["homeSelectedPositionMastery"]
                reveal(mastery, app); XCTAssertTrue(mastery.exists)
                capture(app, "v20-batter-position-map")
                reveal(app.buttons["openPositionTraining"], app); app.buttons["openPositionTraining"].tap()
                XCTAssertTrue(app.buttons["livePosition-1B"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["livePosition-1B"].isSelected)
                capture(app, "v20-batter-position-ready")
                app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
                XCTAssertEqual(status(app), before)
            }
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.staticTexts["trainingCurrentValue"].waitForExistence(timeout: 5))
            capture(app, "v20-" + role + "-training-ready")
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            app.buttons["managementTab-home"].tap()
            XCTAssertTrue(app.buttons["homeResumeTraining"].waitForExistence(timeout: 5))
            app.buttons["homeResumeTraining"].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch.waitForExistence(timeout: 5))
            capture(app, "v20-" + role + "-training-resume")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(Array(status(app).prefix(2)), Array(before.prefix(2)))
        }
    }

    @MainActor func testV20TrainingResultsAndRecentRecordsRemainStableBothRoles() {
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-management-stats-verification", "-management-v20-completed"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 20))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            let growth = app.staticTexts["trainingGrowth"]
            XCTAssertTrue(growth.waitForExistence(timeout: 6)); let saved = growth.label
            capture(app, "v20-" + role + "-training-result")
            reveal(app.staticTexts["trainingFatigue"], app); capture(app, "v20-" + role + "-growth-receipt")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
            app.buttons["managementTab-player"].tap(); app.buttons["facility-records"].tap()
            let recent = app.descendants(matching: .any).matching(identifier: "homeGameResults").firstMatch
            reveal(recent, app); XCTAssertTrue(recent.exists)
            capture(app, "v20-" + role + "-recent-records")
            reveal(app.buttons["playerOpenSeason"], app); app.buttons["playerOpenSeason"].tap()
            let totals = app.descendants(matching: .any).matching(identifier: "seasonTotals").firstMatch
            reveal(totals, app); XCTAssertTrue(totals.exists)
            capture(app, "v20-" + role + "-season-record")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertEqual(growth.label, saved)
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testV20DomesticOffersAndSeasonGoalsBothRoles() {
        let app = XCUIApplication()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 90))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-career"].tap(); app.buttons["facility-contracts"].tap()
            reveal(app.buttons["openDomesticOffers"], app); app.buttons["openDomesticOffers"].tap()
            XCTAssertTrue(app.staticTexts["liveOfferIssued"].waitForExistence(timeout: 10))
            capture(app, "v20-" + role + "-offers")
            reveal(app.buttons["liveOfferDetail-rookie"], app); app.buttons["liveOfferDetail-rookie"].tap()
            let fit = app.staticTexts["liveOfferFit"]; reveal(fit, app); XCTAssertTrue(fit.exists)
            capture(app, "v20-" + role + "-offer-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["liveOffersCompare"], app); app.buttons["liveOffersCompare"].tap()
            reveal(app.staticTexts["liveOfferCompareCaution"], app); XCTAssertTrue(app.staticTexts["liveOfferCompareCaution"].exists)
            capture(app, "v20-" + role + "-offer-compare")
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
        app.terminate()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-club-season-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 90))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-career"].tap(); app.buttons["facility-goals"].tap()
            reveal(app.buttons["openClubSeasonGoals"], app); app.buttons["openClubSeasonGoals"].tap()
            reveal(app.buttons["startClubSeasonGoal"], app); capture(app, "v20-" + role + "-goal-preview")
            app.buttons["startClubSeasonGoal"].tap()
            let state = app.staticTexts["clubSeasonGoalStatus"]; reveal(state, app)
            XCTAssertTrue(state.label.contains("수행 중")); capture(app, "v20-" + role + "-season-goals")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testV20MarketProjectAndFrozenRoleFeedbackBothRoles() {
        let app = XCUIApplication()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-college-pro-verification", "-career-objectives-verification", "-goal-special-verification", "-overseas-renewal-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 120))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-career"].tap(); app.buttons["facility-contracts"].tap()
            reveal(app.buttons["openContractMarket"], app); app.buttons["openContractMarket"].tap()
            XCTAssertTrue(app.staticTexts["marketSummary"].waitForExistence(timeout: 10))
            capture(app, "v20-" + role + "-market")
            reveal(app.buttons["marketRenewal"], app); app.buttons["marketRenewal"].tap()
            let evaluate = app.buttons["evaluateOverseasRenewal"]
            if evaluate.exists { reveal(evaluate, app); evaluate.tap() }
            XCTAssertFalse(app.staticTexts["overseasRenewalError"].exists)
            capture(app, "v20-" + role + "-renewal")
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
        app.terminate()
        // Renewal QA advances its date; use the existing fresh-project fixture separately.
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-college-pro-verification", "-career-objectives-verification", "-goal-special-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 120))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-career"].tap(); app.buttons["facility-goals"].tap()
            reveal(app.buttons["openCareerObjectives"], app); app.buttons["openCareerObjectives"].tap()
            let start = app.buttons["startCareerProject"]; reveal(start, app); XCTAssertTrue(start.isHittable); start.tap()
            let project = app.staticTexts["projectStatus"]; reveal(project, app); XCTAssertEqual(project.label, "진행 중")
            capture(app, "v20-" + role + "-project")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
        }
        app.terminate()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-club-season-verification", "-club-observation-verification", "-club-review-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 120))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-career"].tap(); app.buttons["facility-goals"].tap()
            reveal(app.buttons["openClubSeasonGoals"], app); app.buttons["openClubSeasonGoals"].tap()
            app.buttons["openClubSeasonObservations"].tap()
            let change = app.staticTexts["clubObservationChange"].firstMatch
            reveal(change, app); XCTAssertTrue(change.exists)
            let fixed = change.label; capture(app, "v20-" + role + "-observation")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["settleClubSeasonGoal"], app); app.buttons["settleClubSeasonGoal"].tap()
            reveal(app.buttons["openClubSeasonReviews"], app); app.buttons["openClubSeasonReviews"].tap()
            let advice = app.staticTexts["clubNextRoleAdvice"]; reveal(advice, app); XCTAssertTrue(advice.exists)
            capture(app, "v20-" + role + "-role-feedback")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["openClubSeasonObservations"], app); app.buttons["openClubSeasonObservations"].tap()
            reveal(change, app); XCTAssertEqual(change.label, fixed)
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            XCTAssertEqual(status(app), before)
            app.buttons["managementTab-player"].tap(); app.buttons["facility-records"].tap()
            reveal(app.buttons["playerOpenSeason"], app); app.buttons["playerOpenSeason"].tap()
            XCTAssertTrue(app.staticTexts["seasonChampion"].waitForExistence(timeout: 10))
            capture(app, "v20-" + role + "-season-final")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
        }
    }

    @MainActor func testV20LargeTextTraitPositionAndTrainingPreparation() {
        let app = launch(large: true)
        let before = status(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["선수"].tap()
        reveal(app.buttons["facility-traits"], app); app.buttons["facility-traits"].tap()
        reveal(app.buttons["traitDetails"], app); app.buttons["traitDetails"].tap()
        reveal(app.staticTexts["traitActiveCount"], app); capture(app, "v20-large-traits")
        app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
        reveal(app.buttons["facility-positions"], app); app.buttons["facility-positions"].tap()
        let position = app.buttons["homePositionSelect-1B"]; reveal(position, app); position.tap()
        let value = app.staticTexts["homeSelectedPositionMastery"]; reveal(value, app); XCTAssertTrue(value.exists)
        capture(app, "v20-large-position")
        close(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["훈련"].tap()
        reveal(app.buttons["facility-training"], app); app.buttons["facility-training"].tap()
        reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
        let current = app.staticTexts["trainingCurrentValue"]; reveal(current, app); XCTAssertTrue(current.isHittable)
        capture(app, "v20-large-training-ready")
        app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
        XCTAssertEqual(status(app), before)
    }

    @MainActor func testV25PitchCourseSelectionLockReceiptAndSavedReview() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); pickPitcher(app)
        app.buttons["clubhouse-rest"].tap(); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
        app.buttons["homeTodayGame"].tap(); app.buttons["opponentTab-plan"].tap()
        reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
        capture(app, "v25-pitcher-course-ready")
        let pad = app.descendants(matching: .any).matching(identifier: "pitchCoursePad").firstMatch
        XCTAssertTrue(pad.waitForExistence(timeout: 8)); XCTAssertTrue(pad.isHittable)
        XCTAssertTrue((pad.value as? String)?.contains("추천 사용") == true)
        let reset = app.buttons["pitchCourseReset"], review = app.buttons["pitchCourseReview"]
        XCTAssertGreaterThanOrEqual(reset.frame.height + 0.000001, 44)
        XCTAssertGreaterThanOrEqual(review.frame.height + 0.000001, 44)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)).tap()
        XCTAssertTrue((pad.value as? String)?.contains("직접 변경") == true)
        reset.tap(); XCTAssertTrue((pad.value as? String)?.contains("추천 사용") == true)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.9)).tap()
        let chosen = pad.value as? String
        capture(app, "v25-pitcher-selected-course")
        app.buttons["gamePitch"].tap()
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.1)).tap()
        XCTAssertEqual(pad.value as? String, chosen)
        app.buttons["gameRelease"].tap()
        let unlocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["gamePitch"])
        XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 15), .completed)
        XCTAssertTrue((pad.value as? String)?.contains("추천 사용") == true)
        review.tap()
        let saved = pad.value as? String
        XCTAssertTrue(saved?.contains("목표 가로") == true); XCTAssertTrue(saved?.contains("실제 가로") == true)
        capture(app, "v25-pitcher-target-and-arrival")
        app.buttons["closeRoomDetail"].tap(); app.buttons["homeTodayGame"].tap()
        XCTAssertTrue(pad.waitForExistence(timeout: 8)); review.tap()
        XCTAssertEqual(pad.value as? String, saved)
        capture(app, "v25-pitcher-restored-course")
    }

    @MainActor func testV25LargeTextCoursePreparationKeepsButtonsReachable() {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); pickPitcher(app)
        reveal(app.buttons["clubhouse-rest"], app); app.buttons["clubhouse-rest"].tap()
        reveal(app.buttons["confirmRest"], app); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
        reveal(app.buttons["homeTodayGame"], app); app.buttons["homeTodayGame"].tap()
        app.buttons["opponentTab-plan"].tap(); reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
        capture(app, "v25-large-course-ready")
        let pad = app.descendants(matching: .any).matching(identifier: "pitchCoursePad").firstMatch
        reveal(pad, app); XCTAssertTrue(pad.isHittable)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue((pad.value as? String)?.contains("직접 변경") == true)
        let reset = app.buttons["pitchCourseReset"]; reveal(reset, app); reset.tap()
        XCTAssertTrue((pad.value as? String)?.contains("추천 사용") == true)
        capture(app, "v25-large-pitch-course")
    }

    @MainActor func testV21GameplayBothRoles() {
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            app.buttons["clubhouse-rest"].tap(); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
            app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let field = app.otherElements["careerMatchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            let board = app.descendants(matching: .any).matching(identifier: "matchScoreboard").firstMatch
            XCTAssertTrue(board.exists)
            XCTAssertFalse(app.buttons["replayLastFieldPlay"].exists)
            capture(app, pitcher ? "v21-pitcher-ready" : "v21-batter-ready")
            if pitcher {
                let pitches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gamePitchChoice-"))
                XCTAssertTrue((3...5).contains(pitches.count))
                let gauge = app.descendants(matching: .any).matching(identifier: "releaseGauge").firstMatch
                for i in 0..<pitches.count {
                    let choice = pitches.element(boundBy: i)
                    XCTAssertTrue(choice.isHittable)
                    XCTAssertGreaterThanOrEqual(choice.frame.height + 0.000001, 44)
                    XCTAssertLessThanOrEqual(choice.frame.maxY, gauge.frame.minY, "Every owned pitch must stay above the release control")
                }
                let selected = pitches.element(boundBy: 1); selected.tap(); XCTAssertTrue(selected.isSelected)
                let pitch = app.buttons["gamePitch"]; XCTAssertTrue(app.frame.contains(pitch.frame))
                XCTAssertTrue(app.frame.contains(selected.frame)); XCTAssertGreaterThanOrEqual(selected.frame.height, 44)
                capture(app, "v21-pitcher-choice")
                pitch.tap(); XCTAssertTrue(app.buttons["gameRelease"].waitForExistence(timeout: 2))
                app.buttons["gameRelease"].tap()
                XCTAssertFalse(selected.isEnabled)
                XCTAssertTrue(app.buttons["gamePitch"].waitForExistence(timeout: 12))
                capture(app, "v21-pitcher-arrived")
            } else {
                let touch = app.buttons["battingTouchSurface"]
                XCTAssertTrue(touch.exists)
                let before = touch.value as? String
                let start = touch.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.52))
                let end = touch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.43))
                start.press(forDuration: 0.05, thenDragTo: end)
                XCTAssertNotEqual(touch.value as? String, before)
                XCTAssertTrue(touch.label.contains("투구 요청"), "A swipe must not begin or resolve a pitch")
                for id in ["watch", "swing", "bunt"] {
                    let choice = app.buttons["gameInput-" + id]
                    XCTAssertTrue(app.frame.contains(choice.frame)); XCTAssertGreaterThanOrEqual(choice.frame.height + 0.000001, 44)
                    choice.tap(); XCTAssertTrue(choice.isSelected)
                }
                app.buttons["gameInput-watch"].tap()
                touch.tap()
                let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "투구 요청"), object: touch)
                XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 12), .completed)
                capture(app, "v21-batter-take")
            }
            let automatic = app.buttons["gameAutomatic"]
            if !pitcher {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: automatic)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed)
                app.buttons["gameInput-swing"].tap()
                let touch = app.buttons["battingTouchSurface"]
                touch.tap(); touch.tap()
            }
            let unlocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: automatic)
            XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 12), .completed)
            let savedCount = app.descendants(matching: .any).matching(identifier: "careerGameCount").firstMatch.label
            app.buttons["closeRoomDetail"].tap()
            XCTAssertTrue(app.buttons["homeTodayGame"].waitForExistence(timeout: 5)); app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "careerGameCount").firstMatch.waitForExistence(timeout: 8))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "careerGameCount").firstMatch.label, savedCount)
            capture(app, pitcher ? "v21-pitcher-resume" : "v21-batter-resume")
            automatic.tap(); XCTAssertTrue(app.buttons["진행하고 결과 저장"].waitForExistence(timeout: 3)); app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 15))
            capture(app, pitcher ? "v21-pitcher-completed" : "v21-batter-completed")
        }
    }

    @MainActor func testV21LargeTextBoardAndChoicesBothRoles() {
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            reveal(app.buttons["clubhouse-rest"], app); app.buttons["clubhouse-rest"].tap()
            reveal(app.buttons["confirmRest"], app); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
            reveal(app.buttons["homeTodayGame"], app); app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let board = app.descendants(matching: .any).matching(identifier: "matchScoreboard").firstMatch
            XCTAssertTrue(board.waitForExistence(timeout: 10)); capture(app, pitcher ? "v21-large-pitcher-board" : "v21-large-batter-board")
            let choice = app.buttons[pitcher ? "gamePitchChoice-slider" : "gameInput-bunt"]
            reveal(choice, app); XCTAssertTrue(choice.isHittable); choice.tap(); XCTAssertTrue(choice.isSelected)
            XCTAssertGreaterThanOrEqual(choice.frame.minX, 0); XCTAssertLessThanOrEqual(choice.frame.maxX, app.frame.width)
            capture(app, pitcher ? "v21-large-pitcher-choices" : "v21-large-batter-choices")
        }
    }

    @MainActor func testV22TimingColorsAndCompactPixelPitches() {
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if pitcher { pickPitcher(app) }
            app.buttons["clubhouse-rest"].tap(); app.buttons["confirmRest"].tap(); app.buttons["restDone"].tap()
            app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            XCTAssertTrue(app.otherElements["careerMatchField"].waitForExistence(timeout: 10))
            if pitcher {
                let pitches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gamePitchChoice-"))
                XCTAssertTrue((3...5).contains(pitches.count))
                let gauge = app.descendants(matching: .any).matching(identifier: "releaseGauge").firstMatch
                for i in 0..<pitches.count {
                    let pitch = pitches.element(boundBy: i)
                    XCTAssertLessThanOrEqual(pitch.frame.width, 108)
                    XCTAssertGreaterThanOrEqual(pitch.frame.height, 44)
                    XCTAssertLessThanOrEqual(pitch.frame.maxY, gauge.frame.minY)
                    XCTAssertTrue(pitch.isHittable)
                }
                pitches.element(boundBy: 1).tap(); XCTAssertTrue(pitches.element(boundBy: 1).isSelected)
                XCTAssertTrue(app.buttons["gamePitch"].isHittable)
                capture(app, "v22-pitcher-pixel-choices")
            } else {
                let gauge = app.descendants(matching: .any).matching(identifier: "battingTimingGauge").firstMatch
                XCTAssertTrue(gauge.label.contains("파랑 빠름")); XCTAssertTrue(gauge.label.contains("금색 정타")); XCTAssertTrue(gauge.label.contains("주황 늦음"))
                XCTAssertTrue(app.frame.contains(gauge.frame))
                capture(app, "v22-batter-timing-colors")
            }
        }
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-stats-verification"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func openOpponent(_ app: XCUIApplication) {
        app.buttons["managementTab-game"].tap(); app.buttons["facility-analysis"].tap()
        reveal(app.buttons["hubOpponentAnalysis"], app); app.buttons["hubOpponentAnalysis"].tap()
        XCTAssertTrue(app.buttons["opponentTab-lineup"].waitForExistence(timeout: 6))
    }
    @MainActor private func pickPitcher(_ app: XCUIApplication) {
        app.buttons["roomProfile"].tap(); app.buttons["homeRole-pitcher"].tap()
        if app.buttons["closeRoomDetail"].exists { close(app) }
        if app.buttons["managementTab-home"].exists { app.buttons["managementTab-home"].tap() }
    }
    @MainActor private func close(_ app: XCUIApplication) {
        app.buttons["closeRoomDetail"].tap(); XCTAssertTrue(app.buttons["roomProfile"].waitForExistence(timeout: 5))
    }
    @MainActor private func status(_ app: XCUIApplication) -> [String] {
        ["calendarDate", "homeFatigue", "calendarAction"].map { app.descendants(matching: .any).matching(identifier: $0).firstMatch.label }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.isHittable { return }
            if element.exists && element.frame.maxY < 170 { app.swipeDown() }
            else { app.swipeUp() }
        }
    }
    @MainActor private func revealLocationChoice(_ element: XCUIElement, _ app: XCUIApplication) {
        // Large text on SE can report a partially clipped choice as hittable above the navigation bar.
        for _ in 0..<18 {
            let exists = element.exists, frame = exists ? element.frame : .zero
            if exists && element.isHittable && frame.minY >= 100 && frame.maxY <= app.frame.maxY - 10 { return }
            let down = exists && frame.minY < 100
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: down ? 0.8 : 0.4)))
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let close = app.buttons["closeRoomDetail"]
        if close.exists && close.isHittable {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in close.frame.minY < 140 }, object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
        }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
