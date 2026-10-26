import XCTest

/// Production screens with in-memory QA players; no installed player store is opened.
final class ManagementDetailFlowTests: XCTestCase {
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
                    XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
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
                    XCTAssertTrue(app.frame.contains(choice.frame)); XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
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
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let close = app.buttons["closeRoomDetail"]
        if close.exists && close.isHittable {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in close.frame.minY < 140 }, object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
        }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
