import XCTest

/// Isolated in-memory CareerRootView; never opens the installed player's store.
final class ManagementCareerFlowTests: XCTestCase {
    @MainActor func testV168HomeVenueStaysInsideClubhouseAndOtherMenusKeepTheirRooms() {
        v168RoomVenueBoundary(large: false)
    }

    @MainActor func testV168RoomMenusAtLargestTextDoNotAddCroppedVenueHeaders() {
        v168RoomVenueBoundary(large: true)
    }

    @MainActor private func v168RoomVenueBoundary(large: Bool) {
        continueAfterFailure = false
        let app = launch(large: large)
        defer { app.terminate() }
        let before = labels(app)
        for (tab, title) in [("home", "홈"), ("player", "선수"), ("training", "훈련"), ("career", "커리어")] {
            v99Menu(tab, title: title, app: app)
            let banners = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "managementVenue-"))
            XCTAssertEqual(banners.count, 0, "Only the dedicated game menu may show the separate stadium header")
            if !large {
                let homeVenue = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "managementHomeVenue-")).firstMatch
                if tab == "home" { XCTAssertTrue(homeVenue.waitForExistence(timeout: 8)) }
                else {
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "managementRoomScene-" + tab).firstMatch.waitForExistence(timeout: 8), tab)
                    XCTAssertFalse(homeVenue.exists)
                }
            }
            capture(app, "v168-" + tab + (large ? "-largest" : "-regular"))
        }
        v99Menu("game", title: "경기", app: app)
        let gameVenue = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "managementVenue-")).firstMatch
        XCTAssertTrue(gameVenue.waitForExistence(timeout: 8), "The separate game menu venue must remain available")
        capture(app, "v168-game" + (large ? "-largest" : "-regular"))
        v99Menu("home", title: "홈", app: app)
        XCTAssertEqual(labels(app), before, "Reading menu artwork must not change the day, action, or fatigue")
    }

    @MainActor func testV107TrainingReviewSmallLargeTextResumeBothRoles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-v56-disk-session", UUID().uuidString,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]
            app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            if pitcher {
                app.buttons["roomProfile"].tap(); XCTAssertTrue(app.buttons["homeRole-pitcher"].waitForExistence(timeout: 5)); app.buttons["homeRole-pitcher"].tap()
                if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
            }
            app.buttons["managementLargeMenu"].tap(); app.buttons["managementMenu-training"].tap(); app.buttons["facility-physical"].tap()
            expand("trainingEquipmentChoices", app)
            let kind = app.buttons["trainingKind-" + (pitcher ? "control" : "defense")]
            revealV107(kind, app); kind.tap()
            let open = app.buttons["openTraining"]; revealV107(open, app); open.tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            let start = app.buttons["startTraining"]; revealV107(start, app); start.tap()
            for round in 0..<5 {
                let attempt = app.buttons["trainingAttempt"]; revealV107(attempt, app)
                XCTAssertTrue(attempt.isHittable); XCTAssertGreaterThanOrEqual(attempt.frame.height, 44)
                attempt.tap()
                let next = app.buttons["trainingNext"]
                XCTAssertTrue(next.waitForExistence(timeout: 15))
                let review = app.descendants(matching: .any).matching(identifier: "trainingAttemptReview").firstMatch
                revealV107(review, app); XCTAssertTrue(review.exists); XCTAssertFalse(review.label.isEmpty)
                if round == 0 {
                    try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
                    capture(app, "v107-" + (pitcher ? "pitcher" : "batter") + "-large-review")
                }
                revealV107(next, app); XCTAssertTrue(next.isHittable); XCTAssertGreaterThanOrEqual(next.frame.height, 44); next.tap()
                if round == 1 {
                    app.terminate(); app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
                    if pitcher {
                        app.buttons["roomProfile"].tap(); XCTAssertTrue(app.buttons["homeRole-pitcher"].waitForExistence(timeout: 5))
                        app.buttons["homeRole-pitcher"].tap()
                        if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
                    }
                    app.buttons["managementLargeMenu"].tap(); app.buttons["managementMenu-training"].tap()
                    let resume = app.buttons["roomPrimary"]; revealV107(resume, app); resume.tap()
                    let progress = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
                    XCTAssertTrue(progress.waitForExistence(timeout: 10)); XCTAssertTrue(progress.label.contains("3 / 5"))
                }
            }
            let heading = app.descendants(matching: .any).matching(identifier: "trainingSummaryHeading").firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 8)); XCTAssertFalse(heading.label.isEmpty)
            capture(app, "v107-" + (pitcher ? "pitcher" : "batter") + "-large-summary")
            let done = app.buttons["trainingReturnHome"]; revealV107(done, app)
            XCTAssertTrue(done.isHittable); XCTAssertGreaterThanOrEqual(done.frame.height, 44)
            done.tap()
        }
    }

    @MainActor func testV106CoreDescriptionsAndRecordCoverage() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v100-league-names"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30))
        for pitcher in [false,true] {
            if pitcher {switchToPitcher(app)}
            let before=labels(app)
            try app.performAccessibilityAudit(for:[.sufficientElementDescription,.trait])
            app.buttons["managementTab-game"].tap();app.buttons["facility-standings"].tap()
            let open=app.buttons["openLeaguePlayers"];reveal(open,app);open.tap()
            let names=app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@","npcName-"))
            XCTAssertTrue(names.firstMatch.waitForExistence(timeout:8))
            try app.performAccessibilityAudit(for:[.sufficientElementDescription,.trait])
            let decisions=app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@","pitcherDecisions-"))
            let first=decisions.firstMatch;reveal(first,app)
            XCTAssertTrue(first.exists);XCTAssertTrue(first.label.contains("채점") || first.label.contains("미집계"))
            capture(app,"v106-"+(pitcher ? "pitcher":"batter")+"-decision-coverage")
            app.navigationBars.buttons.element(boundBy:0).tap();closeDetail(app)
            app.buttons["managementTab-home"].tap();XCTAssertEqual(labels(app),before)
        }
    }
    @MainActor func testV103ExtractedSelectionRetryCoachAndCancelBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified",
            "-club-season-verification", "-club-selection-verification", "-club-selection-bench",
            "-v35-coach-verification", "-v55-selection-detail-failure"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 100))
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let before = labels(app)
            let prefix = "v103-" + (pitcher ? "pitcher" : "batter")
            app.buttons["managementTab-game"].tap(); app.buttons["facility-analysis"].tap()
            app.buttons["gameSection-schedule"].tap()
            let failure = app.staticTexts["clubSelectionError"]
            reveal(failure, app); XCTAssertTrue(failure.exists)
            capture(app, prefix + "-selection-error")
            let retry = app.buttons["retryClubSelection"]; reveal(retry, app); retry.tap()
            XCTAssertFalse(failure.exists)
            let open = app.buttons["openClubSelection"]; reveal(open, app); open.tap()
            let source = app.descendants(matching: .any).matching(identifier: "selectionEvidenceClock").firstMatch
            reveal(source, app); XCTAssertTrue(source.label.contains("평가"))
            capture(app, prefix + "-selection-source")
            let next = app.staticTexts["coachNextEvaluation"]; reveal(next, app)
            XCTAssertTrue(next.exists); capture(app, prefix + "-coach-next")
            let rest = app.buttons["coachRest"]; reveal(rest, app); rest.tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 6))
            app.buttons["취소 · 돌아가기"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(labels(app), before)
        }
    }
    @MainActor func testV102FreePracticePreparationBothRolesDoesNotChangeCareer() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let before = labels(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-practice"].tap()
            let open = app.buttons["openTrainingPractice"]; reveal(open, app); open.tap()
            XCTAssertTrue(app.staticTexts["practiceIsolation"].waitForExistence(timeout: 8))
            app.buttons["practiceGeneralTraining"].tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            capture(app, "v102-practice-" + (pitcher ? "pitcher" : "batter"))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            closeDetail(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(labels(app), before)
        }
    }
    @MainActor func testV102PreparationAndFirstCareerActionBothRoles() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let prefix = "v102-" + (pitcher ? "pitcher" : "batter")
            let before = labels(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            let prepare = app.buttons["openTraining"]
            XCTAssertTrue(prepare.waitForExistence(timeout: 8)); XCTAssertTrue(prepare.isHittable)
            XCTAssertLessThanOrEqual(prepare.frame.maxY, app.frame.maxY)
            capture(app, prefix + "-training-first")
            expand("trainingEquipmentChoices", app)
            let power = app.buttons[pitcher ? "trainingKind-pitch" : "trainingKind-power"]
            reveal(power, app); power.tap()
            reveal(prepare, app); prepare.tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            capture(app, prefix + "-preparation")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-career"].tap(); app.buttons["facility-goals"].tap()
            XCTAssertTrue(app.staticTexts["careerFirstStep"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["openGoalSpecial"].exists)
            capture(app, prefix + "-first-goal")
            expand("careerOtherRoutes", app)
            XCTAssertTrue(app.buttons["openGoalSpecial"].waitForExistence(timeout: 3))
            let observation = app.buttons["careerSection-observation"]; reveal(observation, app); observation.tap()
            XCTAssertTrue(app.staticTexts["scoutInterestCount"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "scoutObservationClock").firstMatch.exists)
            capture(app, prefix + "-observation-first")
            let report = app.buttons["openSavedScoutingReport"]; reveal(report, app); report.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "scoutDecisionSummary").firstMatch.waitForExistence(timeout: 8))
            capture(app, prefix + "-frozen-first")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(labels(app), before)
        }
    }
    @MainActor func testV100SmallLargeTextRosterAndLeaders() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-v100-league-names", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher {
                app.buttons["roomProfile"].tap(); XCTAssertTrue(app.buttons["homeRole-pitcher"].waitForExistence(timeout: 5))
                app.buttons["homeRole-pitcher"].tap(); if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
            }
            let before = labels(app)
            app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap(); app.buttons["facility-standings"].tap()
            let list = app.buttons["openLeaguePlayers"]; reveal(list, app); list.tap()
            let name = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "npcName-")).firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 10)); reveal(name, app)
            XCTAssertTrue(name.isHittable); XCTAssertLessThanOrEqual(name.frame.maxX, app.frame.maxX)
            capture(app, pitcher ? "v100-large-pitcher-roster" : "v100-large-batter-roster")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap(); XCTAssertEqual(labels(app), before)
        }
    }
    @MainActor func testV100NamedRostersAndHonorsBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-v100-league-names"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let before = labels(app)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-standings"].tap()
            let list = app.buttons["openLeaguePlayers"]; reveal(list, app); list.tap()
            let names = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "npcName-"))
            XCTAssertTrue(names.firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(names.firstMatch.label.contains("미기록"))
            capture(app, pitcher ? "v100-pitcher-league-players" : "v100-batter-league-players")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["facility-analysis"].tap(); reveal(app.buttons["hubOpponentAnalysis"], app); app.buttons["hubOpponentAnalysis"].tap()
            XCTAssertTrue(app.buttons["opponentTab-lineup"].waitForExistence(timeout: 8))
            let heading = app.staticTexts["opponentIdentity"]; XCTAssertTrue(heading.exists)
            XCTAssertFalse(["선발 투수", "현재 구원 투수"].contains(heading.label)); capture(app, pitcher ? "v100-pitcher-opponent" : "v100-batter-opponent")
            app.buttons["opponentTab-lineup"].tap()
            let first = app.buttons["opponentBatter-1"]; XCTAssertTrue(first.waitForExistence(timeout: 5)); XCTAssertFalse(first.label.hasPrefix("1번 CF ·"))
            capture(app, pitcher ? "v100-pitcher-lineup" : "v100-batter-lineup")
            app.buttons["opponentTab-plan"].tap()
            let plan = app.buttons[pitcher ? "planChoice-control" : "planChoice-contact"]
            reveal(plan, app); plan.tap(); app.buttons["confirmGamePlan"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "careerMatchField").firstMatch.waitForExistence(timeout: 12))
            capture(app, pitcher ? "v100-pitcher-game" : "v100-batter-game")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(labels(app), before)
        }
    }
    @MainActor func testV99TrainingAndCareerDocumentsBothRoles() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            app.buttons["managementTab-training"].tap(); app.buttons["facility-training"].tap()
            expand("trainingMethodDetails", app)
            let method = app.descendants(matching: .any).matching(identifier: "trainingHubMethod").firstMatch; reveal(method, app)
            XCTAssertTrue(method.exists); capture(app, "v99-" + (pitcher ? "pitcher" : "batter") + "-training")
            let prepare = app.buttons["openTraining"]; reveal(prepare, app); XCTAssertTrue(prepare.isHittable)
            capture(app, "v99-" + (pitcher ? "pitcher" : "batter") + "-training-card")
            closeDetail(app)
            app.buttons["managementTab-career"].tap(); app.buttons["facility-observation"].tap()
            expand("scoutDateDetails", app)
            let clock = app.descendants(matching: .any).matching(identifier: "scoutObservationClock").firstMatch
            reveal(clock, app); XCTAssertTrue(clock.exists); capture(app, "v99-" + (pitcher ? "pitcher" : "batter") + "-scout")
            let report = app.buttons["openSavedScoutingReport"]; reveal(report, app); report.tap()
            XCTAssertTrue(app.staticTexts["scoutFrozenDate"].waitForExistence(timeout: 5))
            capture(app, "v99-" + (pitcher ? "pitcher" : "batter") + "-frozen")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let goals = app.buttons["careerSection-goals"]; reveal(goals, app); goals.tap()
            XCTAssertTrue(app.buttons["openCareerObjectives"].waitForExistence(timeout: 5)); capture(app, "v99-" + (pitcher ? "pitcher" : "batter") + "-goals")
            let contracts = app.buttons["careerSection-contracts"]; reveal(contracts, app); contracts.tap()
            XCTAssertTrue(app.buttons["openContractMarket"].waitForExistence(timeout: 5)); capture(app, "v99-" + (pitcher ? "pitcher" : "batter") + "-contracts")
            closeDetail(app)
        }
    }
    @MainActor func testV99StudyContinuationAndLargeDocuments() { v99StudyFlow(large: true) }
    @MainActor func testV99StudyContinuationRegularDocuments() { v99StudyFlow(large: false) }
    @MainActor private func v99StudyFlow(large: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-v99-pitch-study-progress"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"] }
        let prefix = large ? "v99-large" : "v99-regular"
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        app.buttons["roomProfile"].tap(); XCTAssertTrue(app.buttons["homeRole-pitcher"].waitForExistence(timeout: 5))
        app.buttons["homeRole-pitcher"].tap()
        if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
        v99Menu("home", title: "홈", app: app)
        let before = labels(app)
        v99Menu("training", title: "훈련", app: app); v99RevealFacility(app.buttons["facility-training"], app); app.buttons["facility-training"].tap()
        let resume = app.buttons["pitchStudyContinue"]; reveal(resume, app)
        if !resume.exists { capture(app, "v99-study-missing"); print(app.debugDescription) }
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); XCTAssertTrue(resume.isEnabled)
        XCTAssertGreaterThanOrEqual(resume.frame.height, 44); capture(app, prefix + "-study-continuation")
        resume.tap(); XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["스위퍼 습득 훈련"].exists)
        capture(app, prefix + "-study-preparation")
        app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
        v99Menu("home", title: "홈", app: app); XCTAssertEqual(labels(app), before)
        v99Menu("career", title: "커리어", app: app); v99RevealFacility(app.buttons["facility-observation"], app); app.buttons["facility-observation"].tap()
        expand("scoutDateDetails", app)
        let clock = app.descendants(matching: .any).matching(identifier: "scoutObservationClock").firstMatch
        reveal(clock, app); XCTAssertTrue(clock.label.contains("365")); capture(app, prefix + "-scout-dates")
        let contracts = app.buttons["careerSection-contracts"]; reveal(contracts, app); contracts.tap()
        let windows = app.descendants(matching: .any).matching(identifier: "contractWindows").firstMatch
        reveal(windows, app); XCTAssertTrue(windows.exists); capture(app, prefix + "-contract-windows")
        if !large {
            let market = app.buttons["openContractMarket"]; reveal(market, app); market.tap()
            XCTAssertTrue(app.staticTexts["marketSummary"].waitForExistence(timeout: 8))
            capture(app, "v99-contract-market")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        closeDetail(app); v99Menu("home", title: "홈", app: app); XCTAssertEqual(labels(app), before)
    }
    @MainActor private func v99RevealFacility(_ element: XCUIElement, _ app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        if !element.isHittable { reveal(element, app) }
    }
    @MainActor private func v99Menu(_ id: String, title: String, app: XCUIApplication) {
        if app.buttons["managementTab-" + id].exists { app.buttons["managementTab-" + id].tap() }
        else { app.buttons["managementLargeMenu"].tap(); app.buttons[title].tap() }
    }
    @MainActor func testV98AppearanceSelectionsSchoolChangeAndCreationBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-management-empty-verification"]; app.launch()
            XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 20))
            if pitcher { reveal(app.buttons["role-pitcher"], app); app.buttons["role-pitcher"].tap() }
            let name = app.textFields["playerName"]; name.tap(); name.typeText(pitcher ? "LookPitch" : "LookBat")
            app.buttons["입력 완료"].tap()
            reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
            let school = app.buttons["hs-ref-001"]; reveal(school, app); school.tap()
            app.buttons["creationSection-appearance"].tap()
            XCTAssertTrue(app.buttons["hairStyle-0"].waitForExistence(timeout: 10))
            capture(app, pitcher ? "v98-pitcher-hair" : "v98-batter-hair")
            let hair = app.buttons["hairStyle-4"]; revealAppearance(hair, app); hair.tap(); XCTAssertTrue(hair.isSelected)
            let face = app.buttons["appearanceTab-face"]; revealAppearance(face, app); face.tap()
            let eye = app.buttons["eyeShape-2"]; revealAppearance(eye, app); eye.tap(); XCTAssertTrue(eye.isSelected)
            let brow = app.buttons["browShape-3"]; revealAppearance(brow, app); brow.tap(); XCTAssertTrue(brow.isSelected)
            capture(app, pitcher ? "v98-pitcher-face" : "v98-batter-face")
            let expressions = app.buttons["appearanceTab-expression"]; revealAppearance(expressions, app); expressions.tap()
            let expression = app.buttons["expression-4"]; revealAppearance(expression, app); expression.tap()
            capture(app, pitcher ? "v98-pitcher-expression" : "v98-batter-expression")
            let colors = app.buttons["appearanceTab-colors"]; revealAppearance(colors, app); colors.tap()
            let skin = app.buttons["appearanceColor-skin-2"]; revealAppearance(skin, app); skin.tap()
            let color = app.buttons["appearanceColor-hair-4"]; revealAppearance(color, app); color.tap()
            let kit = app.descendants(matching: .any).matching(identifier: "appearanceSchoolKit").firstMatch
            revealAppearance(kit, app); XCTAssertTrue(kit.label.contains("서울북악고"))
            capture(app, pitcher ? "v98-pitcher-colors" : "v98-batter-colors")
            app.buttons["creationSection-information"].tap(); reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
            let other = app.buttons["hs-ref-002"]; reveal(other, app); other.tap()
            app.buttons["creationSection-appearance"].tap(); app.buttons["appearanceTab-colors"].tap()
            revealAppearance(kit, app); XCTAssertTrue(kit.label.contains("한강청운고"))
            XCTAssertTrue(app.buttons["appearanceColor-skin-2"].isSelected)
            capture(app, pitcher ? "v98-pitcher-school-changed" : "v98-batter-school-changed")
            app.buttons["이 모습으로 계속"].tap()
            let create = app.buttons["createPlayer"]; reveal(create, app); create.tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains(pitcher ? "LookPitch" : "LookBat"))
            capture(app, pitcher ? "v98-pitcher-created-home" : "v98-batter-created-home")
        }
    }
    @MainActor func testV98AppearanceLargeTextSmallScreenActions() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-empty-verification",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 20))
        app.buttons["creationSection-appearance"].tap()
        let cap = app.buttons["appearanceCap"]; XCTAssertTrue(cap.waitForExistence(timeout: 10)); revealAppearance(cap, app)
        XCTAssertEqual(cap.value as? String, "벗음")
        cap.tap(); XCTAssertEqual(cap.value as? String, "착용")
        cap.tap()
        XCTAssertEqual(cap.value as? String, "벗음")
        let next = app.buttons["이 모습으로 계속"]
        XCTAssertTrue(next.isHittable); XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        let colors = app.buttons["appearanceTab-colors"]
        revealAppearance(colors, app); colors.tap()
        XCTAssertTrue(colors.isSelected)
        let skin = app.buttons["appearanceColor-skin-5"]; revealAppearance(skin, app); skin.tap(); XCTAssertTrue(skin.isSelected)
        capture(app, "v98-large-colors")
        next.tap(); XCTAssertTrue(app.staticTexts["creationReadiness"].waitForExistence(timeout: 10))
    }
    @MainActor private func revealAppearance(_ element: XCUIElement, _ app: XCUIApplication) {
        let scroll = app.scrollViews["appearanceEditorScroll"]
        for _ in 0..<12 {
            let shortcuts = ["information", "abilities", "appearance", "review"].map { app.buttons["creationSection-" + $0] }.filter(\.exists)
            let top = max(scroll.frame.minY, shortcuts.map(\.frame.maxY).max() ?? scroll.frame.minY) + 8
            let bottom = min(scroll.frame.maxY, app.buttons["이 모습으로 계속"].frame.minY) - 8
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: (top + bottom) / 2))
            let delta = min(120, (bottom - top) / 3) * (element.exists && element.frame.midY < top ? 1.0 : -1.0)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
        }
        XCTFail("외형 선택 항목을 조작 가능한 스크롤 영역으로 이동하지 못했습니다")
    }

    @MainActor func testV50RegionalSchoolEmblemsCreationAndHomeBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-management-empty-verification"]
            app.launch()
            XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 15))
            if pitcher { reveal(app.buttons["role-pitcher"], app); app.buttons["role-pitcher"].tap() }
            app.buttons["creationSection-information"].tap()
            let name = app.textFields["playerName"]; name.tap(); name.typeText(pitcher ? "SchoolPitch" : "SchoolBat")
            app.buttons["입력 완료"].tap()
            reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
            capture(app, pitcher ? "v50-pitcher-school-list" : "v50-batter-school-list")
            let search = app.textFields["schoolSearch"]; search.tap(); search.typeText(pitcher ? "잠실" : "종로")
            app.buttons["검색 완료"].tap()
            let row = app.buttons[pitcher ? "hs-ref-005" : "hs-ref-001"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains(pitcher ? "가람 호랑이" : "북악의 북"))
            capture(app, pitcher ? "v50-tiger-school" : "v50-hanja-school")
            row.tap()
            app.buttons["creationSection-review"].tap()
            XCTAssertTrue(app.staticTexts["creationReadiness"].waitForExistence(timeout: 5))
            capture(app, pitcher ? "v50-pitcher-school-review" : "v50-batter-school-review")
            reveal(app.buttons["createPlayer"], app); app.buttons["createPlayer"].tap()
            XCTAssertTrue(app.staticTexts["homeSchool"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["homeSchool"].label, pitcher ? "잠실가람고" : "서울북악고")
            capture(app, pitcher ? "v50-pitcher-school-home" : "v50-batter-school-home")
        }
    }

    @MainActor func testV49FictionalChampionSchoolAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-management-empty-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout: 15))
        reveal(app.buttons["schoolPicker"], app)
        capture(app, "v50-large-school-entry")
        app.buttons["schoolPicker"].tap()
        XCTAssertTrue(app.textFields["schoolSearch"].waitForExistence(timeout: 5))
        let search = app.textFields["schoolSearch"]; search.tap(); search.typeText("남양주정산고")
        app.buttons["검색 완료"].tap()
        let row = app.buttons["hs-ref-023"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("2025 우승"))
        XCTAssertTrue(row.label.contains("남양주정산고"))
        capture(app, "v49-fictional-champion-large")
        row.tap()
        XCTAssertTrue(app.buttons["schoolPicker"].label.contains("남양주정산고"))
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
        app.buttons["검색 지우기"].tap(); search.tap(); search.typeText("서울북악고")
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
        reveal(app.buttons["schoolPicker"], app); XCTAssertTrue(app.buttons["schoolPicker"].label.contains("서울북악고"))
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
            expand("trainingMethodDetails", app)
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
                         ("game", "facility-analysis", "hubOpponentAnalysis"),
                         ("career", "facility-goals", "openCareerObjectives")]
            for (tab, facility, detail) in cases {
                app.buttons["managementTab-" + tab].tap()
                XCTAssertTrue(app.buttons[facility].isHittable, facility)
                // The training notebook remains an in-scene action; other rooms use their own facilities.
                if tab == "training" {
                    XCTAssertTrue(app.buttons["roomPrimary"].isHittable)
                    XCTAssertTrue(app.frame.contains(app.buttons["roomPrimary"].frame))
                }
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
            expand("trainingEquipmentChoices", app)
            let shelf = app.scrollViews["trainingEquipmentShelf"]
            XCTAssertTrue(shelf.waitForExistence(timeout: 5)); reveal(shelf, app)
            let choice = app.buttons["trainingKind-" + kind]
            for _ in 0..<4 where !choice.isHittable { shelf.swipeLeft() }
            XCTAssertTrue(choice.isHittable, kind); choice.tap()
            expand("trainingMethodDetails", app)
            reveal(app.staticTexts["trainingHubMethod"], app)
            XCTAssertEqual(app.staticTexts["trainingHubMethod"].label, pitcher ? "목표 코스 조준" : "티배팅 · MAX 중앙에서 손 떼기")
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
            let navigationArena = v166SettledTrainingGeometry(app, pitcher: pitcher, route: "navigation")
            capture(app, pitcher ? "pitcher-training-resume" : "batter-training-resume")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-home"].tap()
            XCTAssertEqual(Array(labels(app).prefix(2)), Array(before.prefix(2)))
            let homeTraining = app.buttons["clubhouse-training"]
            reveal(homeTraining, app); XCTAssertTrue(homeTraining.isHittable); homeTraining.tap()
            let resumed = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
            XCTAssertTrue(resumed.waitForExistence(timeout: 8))
            XCTAssertTrue(resumed.label.contains(pitcher ? "제구" : "파워"), resumed.label)
            XCTAssertFalse(app.buttons["startTraining"].exists)
            _ = v166SettledTrainingGeometry(app, pitcher: pitcher, route: "home", referenceArena: navigationArena)
            capture(app, pitcher ? "pitcher-home-training-resume" : "batter-home-training-resume")
            closeDetail(app)
            XCTAssertEqual(Array(labels(app).prefix(2)), Array(before.prefix(2)))
            app.buttons["clubhouse-rest"].tap()
            XCTAssertFalse(app.buttons["confirmRest"].isEnabled)
            app.buttons["닫기"].tap()
        }
    }

    @MainActor private func v166SettledTrainingGeometry(_ app: XCUIApplication, pitcher: Bool, route: String,
                                                       referenceArena: CGRect? = nil) -> CGRect {
        let arenaID = pitcher ? "trainingField" : "skillPracticeField"
        let controlID = pitcher ? "trainingAttempt" : "skillPowerHold"
        let scroll = app.scrollViews["careerTrainingScroll"]
        let arena = app.descendants(matching: .any).matching(identifier: arenaID).firstMatch
        let control = app.descendants(matching: .any).matching(identifier: controlID).firstMatch
        let progress = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
        var previous: [CGRect] = [], consecutive = 0, samples: [[String: Any]] = []
        func numbers(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height].map(Double.init) }
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let viewport = scroll.exists ? scroll.frame.intersection(app.windows.firstMatch.frame) : .zero
            let field = arena.exists ? arena.frame : .zero
            let action = control.exists ? control.frame : .zero
            let heading = progress.exists ? progress.frame : .zero
            let frames = [viewport, field, action, heading]
            let same = previous.count == frames.count && zip(previous, frames).allSatisfy { old, new in
                zip(numbers(old), numbers(new)).allSatisfy { abs($0 - $1) <= 1 }
            }
            let visible = viewport.insetBy(dx: -1, dy: -1)
            let ready = scroll.exists && arena.exists && control.exists && progress.exists
                && frames.allSatisfy { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }
                && control.isEnabled && control.isHittable
                && visible.contains(field) && visible.contains(action) && visible.contains(heading)
            consecutive = ready ? (same ? consecutive + 1 : 1) : 0
            samples.append(["viewport": numbers(viewport), "arena": numbers(field), "control": numbers(action),
                "progress": numbers(heading), "controlExists": control.exists,
                "controlEnabled": control.exists && control.isEnabled, "controlHittable": control.exists && control.isHittable,
                "ready": ready, "consecutiveReadySamples": consecutive])
            previous = frames
            return consecutive >= 2
        }, object: nil)
        let result = XCTWaiter.wait(for: [stable], timeout: 10)
        let finalArena = arena.exists ? arena.frame : .zero
        let evidence: [String: Any] = ["route": route, "role": pitcher ? "pitcher" : "batter",
            "arenaIdentifier": arenaID, "controlIdentifier": controlID, "samples": samples,
            "waitResult": result.rawValue, "requiredConsecutiveSamples": 2, "frameTolerancePoints": 1,
            "sourceMinimumArenaHeight": 150, "sourceArenaWidthToHeight": pitcher ? 320.0 / 340 : 320.0 / 220,
            "sourceMinimumArenaWidth": pitcher ? 150.0 * 320 / 340 : 150.0 * 320 / 220,
            "finalArena": numbers(finalArena), "atSourceMinimumHeight": abs(finalArena.height - 150) <= 1,
            "navigationReferenceArena": referenceArena.map(numbers) ?? [],
            "homeToNavigationWidthRatio": referenceArena.map { $0.width > 0 ? Double(finalArena.width / $0.width) : 0 } ?? 0,
            "limits": "Two visible stable samples gate the screenshot. For the same viewport, home resume must retain navigation arena width within 1pt. Actual play and largest active layout remain outside this case."]
        do {
            let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "V166-training-geometry-" + (pitcher ? "pitcher-" : "batter-") + route
            attachment.lifetime = .keepAlways; add(attachment)
        } catch { XCTFail("훈련 화면 geometry 근거 기록 실패: " + error.localizedDescription) }
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "V166-training-geometry-failed-" + route
            hierarchy.lifetime = .keepAlways; add(hierarchy)
            capture(app, "V166-training-not-settled-" + (pitcher ? "pitcher-" : "batter-") + route)
        }
        XCTAssertEqual(result, .completed, "훈련장·진행 정보·실제 조작 영역이 두 번 연속 가시 상태로 정착해야 합니다.")
        if let referenceArena {
            XCTAssertGreaterThanOrEqual(finalArena.width, referenceArena.width - 1,
                "같은 훈련과 화면 크기에서 홈 이어하기 경기장이 일반 이어하기보다 축소되면 안 됩니다.")
        }
        return finalArena
    }

    @MainActor func testRestGameCompletionAndNextDayBothRoles() {
        continueAfterFailure = false
        let app = launch()
        for pitcher in [false, true] {
            if pitcher { switchToPitcher(app) }
            let originalDate = app.staticTexts["calendarDate"].label
            app.buttons["clubhouse-rest"].tap()
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].label.contains(pitcher ? "52 → 34" : "24 → 6"))
            app.buttons["confirmRest"].tap(); XCTAssertTrue(app.staticTexts["restSaved"].waitForExistence(timeout: 10))
            app.buttons["restDone"].tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].label, originalDate)
            XCTAssertTrue(app.staticTexts["calendarAction"].label.contains("0/1"))
            app.buttons["managementTab-game"].tap(); app.buttons["facility-analysis"].tap()
            app.buttons["gameSection-schedule"].tap()
            let enter = app.buttons["openCareerGame"]; reveal(enter, app); enter.tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let automatic = app.buttons["gameAutomatic"]; XCTAssertTrue(automatic.waitForExistence(timeout: 10))
            reveal(automatic, app); automatic.tap(); app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["careerGameFinished"].waitForExistence(timeout: 15))
            let score = app.staticTexts["gameFinalScore"]
            XCTAssertTrue(score.isHittable)
            XCTAssertTrue(app.staticTexts["gameResultSaved"].isHittable)
            capture(app, pitcher ? "pitcher-completed" : "batter-completed")
            reveal(app.buttons["gameReturnHome"], app); app.buttons["gameReturnHome"].tap()
            XCTAssertTrue(enter.waitForExistence(timeout: 8))
            let completed = labels(app)
            reveal(enter, app); enter.tap()
            XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout: 8))
            reveal(app.buttons["gameReturnHome"], app); app.buttons["gameReturnHome"].tap()
            closeDetail(app)
            XCTAssertEqual(labels(app), completed)
            app.buttons["managementTab-game"].tap(); app.buttons["facility-gameRecords"].tap()
            XCTAssertTrue(app.buttons["gameOpenSeason"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "homeGameResults").firstMatch.exists)
            closeDetail(app)
            app.buttons["facility-calendar"].tap()
            reveal(app.buttons["advanceDay"], app); XCTAssertTrue(app.buttons["advanceDay"].isEnabled)
            app.buttons["advanceDay"].tap()
            let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "4월 2일 (목)"), object: app.scrollViews["calendarDetailScroll"].staticTexts["calendarDate"])
            XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed)
            app.buttons["closeCalendar"].tap(); app.buttons["managementTab-home"].tap()
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

    @MainActor func testV166ApprovedManagementScreensReadOnlyBothRoles() {
        v166ApprovedScreens(large: false)
    }

    @MainActor func testV166ApprovedManagementScreensLargestTextBothRoles() {
        v166ApprovedScreens(large: true)
    }

    @MainActor private func v166ApprovedScreens(large: Bool) {
        continueAfterFailure = false
        let app = launch(large: large)
        defer { app.terminate() }
        let prefix = large ? "V166-approved-largest" : "V166-approved-regular"
        for pitcher in [false, true] {
            if pitcher { v166SwitchToPitcher(app) }
            let role = pitcher ? "pitcher" : "batter", before = labels(app)
            app.buttons["roomProfile"].tap()
            for id in ["homeRole-batter", "homeRole-pitcher"] {
                let card = app.buttons[id]
                XCTAssertTrue(card.waitForExistence(timeout: 8)); reveal(card, app)
                XCTAssertGreaterThanOrEqual(card.frame.height, 44)
                XCTAssertGreaterThanOrEqual(card.frame.width, 44)
            }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notebookIdentity").firstMatch.exists)
            capture(app, prefix + "-" + role + "-player-cards")
            closeDetail(app)

            v99Menu("training", title: "훈련", app: app)
            v166Tap("facility-training", app)
            capture(app, prefix + "-" + role + "-training-hub")
            v166Tap("openTraining", app)
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout: 8))
            capture(app, prefix + "-" + role + "-training-preparation-no-start")
            v166CheckVisibleTextBounds(app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            closeDetail(app)

            v99Menu("home", title: "홈", app: app)
            XCTAssertEqual(labels(app), before)
            v166Tap("clubhouse-rest", app)
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].waitForExistence(timeout: 8))
            capture(app, prefix + "-" + role + "-recovery-before-confirmation")
            let cancel = app.buttons["취소 · 돌아가기"]
            reveal(cancel, app); XCTAssertTrue(cancel.isHittable); cancel.tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
            XCTAssertEqual(labels(app), before)
            XCTAssertFalse(app.staticTexts["restSaved"].exists)

            v99Menu("career", title: "커리어", app: app)
            v166Tap("facility-observation", app)
            let cover = app.descendants(matching: .any).matching(identifier: "scoutSavedFileCover").firstMatch
            XCTAssertTrue(cover.waitForExistence(timeout: 8)); reveal(cover, app)
            capture(app, prefix + "-" + role + "-saved-report-cover")
            v166Tap("openSavedScoutingReport", app)
            let date = app.staticTexts["scoutFrozenDate"]
            XCTAssertTrue(date.waitForExistence(timeout: 8))
            let originalDate = date.label
            for section in ["summary", "abilities", "records", "clubs"] {
                v166Tap("frozenScoutSection-" + section, app)
                v166CheckSelectedReportSection("frozenScoutSection", section: section, app: app)
                XCTAssertEqual(date.label, originalDate)
                let fullIdentity = app.descendants(matching: .any).matching(identifier: "scoutFrozenFileCover").firstMatch
                let compactIdentity = app.descendants(matching: .any).matching(identifier: "scoutFrozenCompactIdentity").firstMatch
                if section == "summary" {
                    XCTAssertTrue(fullIdentity.waitForExistence(timeout: 8))
                    XCTAssertFalse(compactIdentity.exists)
                } else {
                    XCTAssertTrue(compactIdentity.waitForExistence(timeout: 8))
                    XCTAssertFalse(fullIdentity.exists)
                }
                v166CheckVisibleTextBounds(app)
                capture(app, prefix + "-" + role + "-frozen-" + section)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            v166Tap("openScoutingReport", app)
            let actualPlayer = app.staticTexts["scoutActualPlayer"]
            XCTAssertTrue(actualPlayer.waitForExistence(timeout: 8))
            if large {
                let currentDate = app.staticTexts["scoutCurrentDate"]
                XCTAssertTrue(currentDate.waitForExistence(timeout: 8))
                capture(app, prefix + "-" + role + "-current-initial-viewport")
                let window = app.windows.firstMatch.frame, navigation = app.navigationBars.firstMatch.frame
                for text in [actualPlayer, currentDate] {
                    XCTAssertTrue(text.isHittable, text.identifier)
                    XCTAssertGreaterThanOrEqual(text.frame.minY, navigation.maxY - 1, text.identifier)
                    XCTAssertLessThanOrEqual(text.frame.maxY, window.maxY + 1, text.identifier)
                    XCTAssertGreaterThanOrEqual(text.frame.minX, window.minX - 1, text.identifier)
                    XCTAssertLessThanOrEqual(text.frame.maxX, window.maxX + 1, text.identifier)
                }
            }
            for section in ["abilities", "records", "archive"] {
                v166Tap("currentScoutSection-" + section, app)
                v166CheckSelectedReportSection("currentScoutSection", section: section, app: app)
                v166CheckVisibleTextBounds(app)
                capture(app, prefix + "-" + role + (section == "abilities" ? "-current-report" : "-current-" + section))
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            closeDetail(app)

            v99Menu("game", title: "경기", app: app)
            let entry = app.buttons["roomPrimary"]
            XCTAssertTrue(entry.waitForExistence(timeout: 8)); reveal(entry, app)
            XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
            capture(app, prefix + "-" + role + "-team-stadium-menu")
            v99Menu("home", title: "홈", app: app)
            XCTAssertEqual(labels(app), before, "Reading screens and cancelling preparation/rest must not consume the day or action")
        }
    }

    @MainActor private func v166SwitchToPitcher(_ app: XCUIApplication) {
        app.buttons["roomProfile"].tap()
        let choice = app.buttons["homeRole-pitcher"]
        XCTAssertTrue(choice.waitForExistence(timeout: 8)); reveal(choice, app)
        XCTAssertTrue(choice.isHittable); choice.tap()
        if app.buttons["closeRoomDetail"].exists { closeDetail(app) }
        v99Menu("home", title: "홈", app: app)
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["homePlayerName"].label.contains("CareerPitch"))
    }

    @MainActor private func v166CheckSelectedReportSection(_ identifier: String, section: String, app: XCUIApplication) {
        let menu = app.buttons[identifier + "Menu"]
        if menu.exists {
            let titles = identifier == "currentScoutSection"
                ? ["abilities": "현재 능력", "records": "출전 기록", "archive": "관찰 보관함"]
                : ["summary": "요약", "abilities": "능력·구종", "records": "경기·근거", "clubs": "관심 구단"]
            XCTAssertEqual(menu.value as? String, titles[section])
        } else {
            XCTAssertTrue(app.buttons[identifier + "-" + section].isSelected)
        }
    }

    @MainActor func testV166ApprovedCreationStyleAndTypeReachFinalCardWithoutRegistration() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for pitcher in [false, true] {
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-management-empty-verification"]
            app.launch()
            let name = app.textFields["playerName"]
            XCTAssertTrue(name.waitForExistence(timeout: 20))
            name.tap(); name.typeText(pitcher ? "CardPitch" : "CardBat")
            app.buttons["입력 완료"].tap()
            if pitcher { reveal(app.buttons["role-pitcher"], app); app.buttons["role-pitcher"].tap() }
            reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
            let school = app.buttons["hs-ref-001"]; reveal(school, app); school.tap()
            app.buttons["creationSection-abilities"].tap()
            let archetype = app.buttons[pitcher ? "archetype-endurance" : "archetype-onBase"]
            reveal(archetype, app); XCTAssertTrue(archetype.isHittable); archetype.tap()
            let summary = app.staticTexts["archetypePreviewTitle"]
            reveal(summary, app)
            XCTAssertTrue(summary.label.contains(pitcher ? "지구력형" : "출루형"))
            capture(app, "V166-approved-creation-" + (pitcher ? "pitcher" : "batter") + "-type-chart")
            app.buttons["creationSection-appearance"].tap()
            let preset = app.buttons["appearancePreset-3"]
            XCTAssertTrue(preset.waitForExistence(timeout: 8)); revealAppearance(preset, app); preset.tap()
            let hair = app.buttons["hairStyle-7"]; revealAppearance(hair, app)
            XCTAssertTrue(hair.isSelected, "Style D must remain editable through the saved hairstyle controls")
            capture(app, "V166-approved-creation-" + (pitcher ? "pitcher" : "batter") + "-style-D")
            app.buttons["이 모습으로 계속"].tap()
            capture(app, "V166-approved-creation-" + (pitcher ? "pitcher" : "batter") + "-final-card-cover")
            let budget = app.staticTexts["creationReviewBudget"]
            reveal(budget, app); XCTAssertTrue(budget.exists)
            XCTAssertTrue(budget.label.contains(pitcher ? "459" : "388"))
            XCTAssertTrue(budget.label.contains(pitcher ? "지구력형" : "출루형"))
            if pitcher { XCTAssertTrue(app.staticTexts["creationReviewPitches"].exists) }
            capture(app, "V166-approved-creation-" + (pitcher ? "pitcher" : "batter") + "-final-card-no-save")
            let create = app.buttons["createPlayer"]; reveal(create, app); XCTAssertTrue(create.isEnabled)
            XCTAssertFalse(app.staticTexts["homePlayerName"].exists, "This case stops before registering the local QA draft")
        }
    }

    @MainActor func testV166ControlsKeepContentInsetsAndCreationCloseRegular() {
        v166CheckReadability(large: false)
    }

    @MainActor func testV166ControlsKeepContentInsetsAndCreationCloseLargestText() {
        v166CheckReadability(large: true)
    }

    @MainActor private func v166CheckReadability(large: Bool) {
        continueAfterFailure = false
        let prefix = large ? "V166-largest" : "V166-regular"
        let app = XCUIApplication(bundleIdentifier: "dev.bm.career.performanceqa")
        defer { app.terminate() }

        v166Launch(app, large: large, singleRole: false)
        capture(app, prefix + "-home")
        app.buttons["roomProfile"].tap()
        XCTAssertTrue(app.buttons["homeRole-batter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeRole-pitcher"].exists)
        capture(app, prefix + "-player-list")
        app.terminate()

        v166Launch(app, large: large, singleRole: true)
        let before = labels(app)
        v99Menu("player", title: "선수", app: app)
        v166Tap("facility-abilities", app)
        v166Tap("createOtherRole", app)
        XCTAssertTrue(app.buttons["createPlayer"].waitForExistence(timeout: 8))
        let availableRole = app.buttons["role-pitcher"]
        v166RevealCreationRole(availableRole, app: app)
        XCTAssertTrue(availableRole.waitForExistence(timeout: 5))
        XCTAssertTrue(availableRole.isHittable)
        XCTAssertTrue(availableRole.isSelected)
        XCTAssertFalse(app.buttons["role-batter"].exists)
        let close = app.buttons["closePlayerCreation"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(close.label.contains("닫기"), close.label)
        let closeLabel = close.label
        v166CheckBounds(close, app: app)
        XCTAssertGreaterThanOrEqual(close.frame.width, close.frame.height - 1)
        capture(app, prefix + "-creation-close-and-current-avatar")
        close.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["playerName"].exists)
        v99Menu("home", title: "홈", app: app)
        XCTAssertEqual(labels(app), before)

        v99Menu("player", title: "선수", app: app)
        v166Tap("facility-abilities", app)
        XCTAssertTrue(app.buttons["createOtherRole"].exists, "취소만으로 미생성 역할 슬롯이 소비되면 안 됩니다.")
        v166CloseRoom(app)
        v99Menu("home", title: "홈", app: app)
        XCTAssertEqual(labels(app), before)

        v99Menu("career", title: "커리어", app: app)
        v166Tap("facility-observation", app)
        let report = app.buttons["openSavedScoutingReport"]
        XCTAssertTrue(report.waitForExistence(timeout: 8))
        reveal(report, app)
        XCTAssertTrue(report.isHittable)
        let title = app.staticTexts["openSavedScoutingReportTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.isHittable)
        v166CheckBounds(report, app: app)
        let leftInset = title.frame.minX - report.frame.minX
        let trailingSpace = report.frame.maxX - title.frame.maxX
        let reportHeight = report.frame.height
        XCTAssertGreaterThanOrEqual(leftInset, 10, "확정 보고서 제목이 버튼 테두리에 붙으면 안 됩니다.")
        XCTAssertGreaterThanOrEqual(trailingSpace, 10, "제목의 마지막 글자가 버튼 테두리에 붙으면 안 됩니다.")
        XCTAssertGreaterThanOrEqual(report.frame.height, title.frame.height + 14)
        capture(app, prefix + "-scout-desk-content-insets")
        report.tap()
        let frozenDate = app.staticTexts["scoutFrozenDate"]
        XCTAssertTrue(frozenDate.waitForExistence(timeout: 8))
        let originalDate = frozenDate.label
        v166Tap("frozenScoutSection-abilities", app)
        XCTAssertEqual(frozenDate.label, originalDate)
        v166Tap("frozenScoutSection-summary", app)
        XCTAssertEqual(frozenDate.label, originalDate)
        v166CheckVisibleTextBounds(app)
        capture(app, prefix + "-frozen-report-summary")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        v166CloseRoom(app)
        v99Menu("home", title: "홈", app: app)
        XCTAssertEqual(labels(app), before)

        v99Menu("training", title: "훈련", app: app)
        v166Tap("facility-training", app)
        capture(app, prefix + "-training-hub-no-start")
        v166CloseRoom(app)
        v99Menu("home", title: "홈", app: app)
        XCTAssertEqual(labels(app), before)
        v166Tap("clubhouse-rest", app)
        XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8))
        capture(app, prefix + "-rest-confirmation-no-save")
        let cancel = app.buttons["취소 · 돌아가기"]
        reveal(cancel, app)
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
        XCTAssertEqual(labels(app), before)
        XCTAssertFalse(app.staticTexts["restSaved"].exists)

        let audit: [String: Any] = [
            "fontMode": large ? "accessibilityXXXL" : "regular",
            "bundle": "dev.bm.career.performanceqa",
            "storage": "management in-memory verification; fresh fixtures after relaunch",
            "homeStateBefore": before,
            "homeStateAfter": labels(app),
            "scoutTitleLeftInset": Double(leftInset),
            "scoutTitleTrailingSpace": Double(trailingSpace),
            "scoutButtonHeight": Double(reportHeight),
            "creationCloseLabel": closeLabel,
            "frozenObservedDate": originalDate,
            "trainingStartCommands": 0,
            "restSaveCommands": 0,
            "playerRegistrationCommands": 0,
            "humanInputs": 0,
            "limits": "Representative navigation/geometry assertions and still captures. Not all 204 button call sites, actual VoiceOver, full glyph/animation quality, physical-device performance or approved screen redesign."
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: audit, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = prefix + "-readability-audit"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch { XCTFail("V166 QA audit could not be encoded: " + error.localizedDescription) }
    }

    @MainActor private func v166Launch(_ app: XCUIApplication, large: Bool, singleRole: Bool) {
        app.launchArguments = ["-management-career-verification"]
        if singleRole { app.launchArguments += ["-management-single-role-verification"] }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 20))
    }

    @MainActor private func v166Tap(_ identifier: String, _ app: XCUIApplication) {
        let prefix = String(identifier.split(separator: "-").first ?? "")
        if ["frozenScoutSection", "currentScoutSection"].contains(prefix), app.buttons[prefix + "Menu"].exists {
            app.buttons[prefix + "Menu"].tap()
        }
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 8), identifier)
        if !button.isHittable { reveal(button, app) }
        XCTAssertTrue(button.isHittable, identifier)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.001, identifier)
        button.tap()
    }

    @MainActor private func v166RevealCreationRole(_ role: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews["creationScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        for attempt in 0..<8 {
            let shortcuts = ["information", "abilities", "appearance", "review"]
                .map { app.buttons["creationSection-" + $0] }.filter(\.exists)
            let window = app.windows.firstMatch.frame
            let scrollFrame = scroll.frame
            let appFrame = app.frame
            let top = max(scrollFrame.minY, shortcuts.map(\.frame.maxY).max() ?? scrollFrame.minY) + 8
            let bottom = min(scrollFrame.maxY, window.maxY) - 8
            XCTAssertGreaterThan(bottom - top, 20, "생성 모달의 스크롤 가시 영역이 유효해야 합니다.")
            let visibleMidY = (top + bottom) / 2
            let exists = role.exists
            let hittable = exists && role.isHittable
            let frame = exists ? role.frame : .zero
            let visible = hittable && frame.midY > top && frame.midY < bottom
            let travelLimit = min(CGFloat(80), (bottom - top) / 2 - 8)
            let delta = visible ? 0 : min(travelLimit, max(-travelLimit, exists ? frame.midY - visibleMidY : 80))
            let audit: [String: Any] = [
                "attempt": attempt + 1,
                "scrollIdentifier": "creationScroll",
                "roleExists": exists,
                "roleHittable": hittable,
                "roleFrame": [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
                "scrollFrame": [Double(scrollFrame.minX), Double(scrollFrame.minY), Double(scrollFrame.width), Double(scrollFrame.height)],
                "windowFrame": [Double(window.minX), Double(window.minY), Double(window.width), Double(window.height)],
                "appOrigin": [Double(appFrame.minX), Double(appFrame.minY)],
                "visibleTop": Double(top),
                "visibleBottom": Double(bottom),
                "visibleMidY": Double(visibleMidY),
                "contentDelta": Double(delta),
                "roleVisible": visible,
                "maximumDragDistance": 80,
                "velocity": 100
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: audit, options: [.prettyPrinted, .sortedKeys])
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "V166-creation-role-scroll-\(attempt + 1)-geometry"
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch { XCTFail("V166 생성 모달 스크롤 근거를 기록하지 못했습니다: " + error.localizedDescription) }
            if visible { return }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.midX - appFrame.minX, dy: visibleMidY - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -delta)),
                        withVelocity: 100, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(role.exists && role.isHittable, "생성 모달의 역할 선택을 8회 이내 미세 스크롤로 찾지 못했습니다.")
    }

    @MainActor private func v166CheckVisibleTextBounds(_ app: XCUIApplication) {
        for text in app.staticTexts.allElementsBoundByIndex where text.isHittable && !text.label.isEmpty {
            XCTAssertGreaterThanOrEqual(text.frame.minX, app.frame.minX - 1, text.label)
            XCTAssertLessThanOrEqual(text.frame.maxX, app.frame.maxX + 1, text.label)
            XCTAssertFalse(text.label.contains("�"), text.label)
        }
    }

    @MainActor private func v166CheckBounds(_ element: XCUIElement, app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(element.frame.width, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX - 1)
        XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX + 1)
        XCTAssertGreaterThanOrEqual(element.frame.minY, window.minY - 1)
        XCTAssertLessThanOrEqual(element.frame.maxY, window.maxY + 1)
    }

    @MainActor private func v166CloseRoom(_ app: XCUIApplication) {
        closeDetail(app)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["closeRoomDetail"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
    }

    @MainActor private func expand(_ id: String, _ app: XCUIApplication) {
        let group = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(group, app)
        let button = group.elementType == .button ? group : group.buttons.firstMatch
        XCTAssertTrue(button.exists); reveal(button, app); button.tap()
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
            let detail = app.scrollViews["roomDetailScroll"]
            let calendar = app.scrollViews["calendarDetailScroll"]
            let scroll = detail.exists ? detail : calendar.exists ? calendar : app.scrollViews.firstMatch
            let shortcuts = ["information", "abilities", "appearance", "review"].map { app.buttons["creationSection-" + $0] }.filter(\.exists)
            let visibleTop = max(scroll.frame.minY, shortcuts.map(\.frame.maxY).max() ?? scroll.frame.minY)
            // SwiftUI may report a partially occluded button as hittable behind the fixed shortcuts.
            if element.isHittable && (shortcuts.isEmpty || element.frame.midY > visibleTop + 8 && element.frame.midY < app.frame.maxY - 44) { return }
            if element.exists && element.frame.midY < visibleTop + 8 { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
    }
    @MainActor private func revealV107(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<24 {
            let training = app.scrollViews["careerTrainingScroll"]
            let detail = app.scrollViews["roomDetailScroll"]
            let scroll = training.exists ? training : detail.exists ? detail : app.scrollViews.firstMatch
            let nav = app.navigationBars.firstMatch
            let close = app.buttons["closeRoomDetail"]
            let top = max(scroll.frame.minY, nav.exists ? nav.frame.maxY : 0, detail.exists && close.exists ? close.frame.maxY : 0) + 8
            let bottom = min(scroll.frame.maxY, app.frame.maxY - 16) - 8
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            if !element.exists || element.frame.midY > bottom + scroll.frame.height { scroll.swipeUp(); continue }
            if element.frame.midY < top - scroll.frame.height { scroll.swipeDown(); continue }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: (top + bottom) / 2))
            let delta = min(160, (bottom - top) / 3) * (element.frame.midY < top ? 1.0 : -1.0)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
        }
        capture(app, "v107-unreachable-control")
        XCTFail("훈련 조작을 헤더에 가리지 않는 위치로 이동하지 못했습니다")
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
