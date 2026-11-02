import XCTest

/// Isolated in-memory CareerRootView; never opens the installed player's store.
final class ManagementCareerFlowTests: XCTestCase {
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
        let cap = app.buttons["appearanceCap"]; XCTAssertTrue(cap.waitForExistence(timeout: 10)); revealAppearance(cap, app); cap.tap()
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
            let top = scroll.frame.minY + 8
            let bottom = min(scroll.frame.maxY, app.buttons["이 모습으로 계속"].frame.minY) - 8
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            if element.exists && element.frame.midY < top { scroll.swipeDown(velocity: .slow) }
            else { scroll.swipeUp(velocity: .slow) }
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
            reveal(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            XCTAssertEqual(app.staticTexts["trainingHubMethod"].label, pitcher ? "목표 코스 조준" : "타이어 · MAX 중앙에서 손 떼기")
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
            capture(app, pitcher ? "pitcher-training-resume" : "batter-training-resume")
            app.navigationBars.buttons.element(boundBy: 0).tap(); closeDetail(app)
            app.buttons["managementTab-home"].tap()
            XCTAssertTrue(app.buttons["homeResumeTraining"].exists)
            XCTAssertEqual(Array(labels(app).prefix(2)), Array(before.prefix(2)))
            app.buttons["clubhouse-rest"].tap()
            XCTAssertFalse(app.buttons["confirmRest"].isEnabled)
            app.buttons["닫기"].tap()
        }
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
