import XCTest

/// Production screens with in-memory QA players; no installed player store is opened.
final class ManagementDetailFlowTests: XCTestCase {
    @MainActor func testV56TrainingTerminationResumeAndStoredRewardBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-v56-disk-session",UUID().uuidString];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            let kind=pitcher ? "control":"defense",role=pitcher ? "pitcher":"batter"
            func openTraining() {
                app.buttons["managementTab-training"].tap();app.buttons["facility-physical"].tap()
                reveal(app.buttons["trainingKind-"+kind],app);app.buttons["trainingKind-"+kind].tap()
                reveal(app.buttons["openTraining"],app);app.buttons["openTraining"].tap()
            }
            openTraining();reveal(app.buttons["startTraining"],app);app.buttons["startTraining"].tap()
            reveal(app.buttons["trainingAttempt"],app);app.buttons["trainingAttempt"].tap()
            // The command has saved this attempt before presentation starts. Terminate the app itself.
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            let afterAttempt=status(app);openTraining()
            let progress=app.descendants(matching:.any).matching(identifier:"trainingProgress").firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout:8));XCTAssertTrue(progress.label.contains("2 / 5"));capture(app,"v56-"+role+"-training-relaunch")
            for _ in 0..<4 {
                reveal(app.buttons["trainingAttempt"],app);app.buttons["trainingAttempt"].tap()
                XCTAssertFalse(app.buttons["trainingNext"].exists)
                XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout:10));app.buttons["trainingNext"].tap()
            }
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout:8))
            let growth=app.staticTexts["trainingGrowth"].label
            let art=app.descendants(matching:.any).matching(identifier:"trainingResultArt-"+kind).firstMatch
            XCTAssertTrue(art.exists);XCTAssertTrue(art.label.contains(pitcher ? "제구" : "수비"))
            capture(app,"v70-"+role+"-training-stored")
            app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout:5));close(app);app.buttons["managementTab-home"].tap()
            let completed=status(app);XCTAssertEqual(completed[0],afterAttempt[0]);XCTAssertEqual(completed[2],"행동 0/1");XCTAssertNotEqual(completed[1],afterAttempt[1])
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            XCTAssertEqual(status(app),completed);openTraining()
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["trainingGrowth"].label,growth)
        }
    }
    @MainActor func testV56MatchTerminationResumeAndCompletedResultBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-v56-disk-session",UUID().uuidString];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            app.buttons["clubhouse-rest"].tap();app.buttons["confirmRest"].tap();app.buttons["restDone"].tap();app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout:8));app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"],app);app.buttons["confirmGamePlan"].tap()
            XCTAssertTrue(app.buttons["gameAutomatic"].waitForExistence(timeout:12))
            if pitcher {app.buttons["gamePitch"].tap();app.buttons["gameRelease"].tap()}
            else {app.buttons["gameInput-watch"].tap();app.buttons["battingTouchSurface"].tap()}
            let automatic=app.buttons["gameAutomatic"]
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:automatic)],timeout:35),.completed)
            let board=app.descendants(matching:.any).matching(identifier:"careerGameScore").firstMatch.label
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            app.buttons["homeTodayGame"].tap();XCTAssertTrue(automatic.waitForExistence(timeout:12))
            XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"careerGameScore").firstMatch.label,board)
            capture(app,pitcher ? "v56-pitcher-match-resumed":"v56-batter-match-resumed")
            automatic.tap();app.buttons["진행하고 결과 저장"].tap();XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout:30))
            capture(app,pitcher ? "v56-pitcher-match-stored":"v56-batter-match-stored")
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            let completed=status(app);app.buttons["homeTodayGame"].tap();XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout:12))
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            XCTAssertEqual(status(app),completed)
        }
    }
    @MainActor func testV56BackupPreviewRestoreAndPickerCancellation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-save-protection-verification","-save-protection-preview"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));let before=status(app)
        app.buttons["clubhouse-settings"].tap();XCTAssertTrue(app.buttons["importSave"].waitForExistence(timeout:8))
        let scope=app.descendants(matching:.any).matching(identifier:"restoreScopeSummary").firstMatch;reveal(scope,app);XCTAssertTrue(scope.exists);capture(app,"v56-backup-verified-comparison")
        let confirm=app.buttons["confirmRestoreSave"];reveal(confirm,app);confirm.tap();app.buttons["취소"].tap();XCTAssertTrue(confirm.exists)
        reveal(app.buttons["importSave"],app);app.buttons["importSave"].tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","취소"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:10));cancel.tap();XCTAssertTrue(confirm.waitForExistence(timeout:8));capture(app,"v56-backup-picker-cancel")
        reveal(confirm,app);confirm.tap();app.buttons["전체 복원"].tap();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:12));XCTAssertEqual(status(app),before)
    }
    @MainActor func testV56SmallLargestTextExportCancellationAndRestoreControls() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-save-protection-verification","-save-protection-preview","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-management-reduced-motion-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));let before=status(app)
        revealLocationChoice(app.buttons["clubhouse-settings"],app);app.buttons["clubhouse-settings"].tap()
        let export=app.buttons["exportSave"];revealLocationChoice(export,app);XCTAssertTrue(export.isHittable);XCTAssertGreaterThanOrEqual(export.frame.height,44);capture(app,"v56-small-large-export")
        export.tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","취소"])).firstMatch
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout:12));capture(app,"v56-small-file-exporter")
        // The system picker exposes Cancel at its root, not inside On My iPhone.
        if !cancel.exists {app.navigationBars.buttons["BackButton"].tap()}
        XCTAssertTrue(cancel.waitForExistence(timeout:5));cancel.tap()
        let size=app.staticTexts["saveExportSize"];revealLocationChoice(size,app);XCTAssertTrue(size.exists)
        let scope=app.descendants(matching:.any).matching(identifier:"restoreScopeSummary").firstMatch;revealLocationChoice(scope,app);XCTAssertTrue(scope.isHittable);capture(app,"v56-small-large-restore-scope")
        let confirm=app.buttons["confirmRestoreSave"];revealLocationChoice(confirm,app);XCTAssertTrue(confirm.isHittable);confirm.tap();XCTAssertTrue(app.buttons["전체 복원"].waitForExistence(timeout:5));capture(app,"v56-small-large-confirm");app.buttons["취소"].tap()
        app.buttons["닫기"].tap();XCTAssertEqual(status(app),before)
    }
    @MainActor func testV51TrainingScreensAndSelectedRoutes() {
        captureV51TrainingRoutes(["contact", "power", "discipline", "velocity", "control", "stuff", "speed", "defense", "arm", "stamina", "mental"])
    }
    @MainActor func testV51DefensePreparationScrollKeepsCenteredInput() {
        captureV51TrainingRoutes(["defense"])
    }
    @MainActor private func captureV51TrainingRoutes(_ kinds: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in kinds {
            app.terminate(); app.launchArguments = ["-management-career-verification"]; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            if ["velocity", "control", "stuff", "stamina"].contains(kind) { pickPitcher(app) }
            app.buttons["managementTab-training"].tap()
            app.buttons[["contact", "power", "discipline"].contains(kind) ? "facility-training" : "facility-physical"].tap()
            revealLocationChoice(app.buttons["trainingKind-" + kind], app); app.buttons["trainingKind-" + kind].tap()
            reveal(app.buttons["openTraining"], app); app.buttons["openTraining"].tap()
            XCTAssertTrue(app.navigationBars[["contact":"컨택","power":"파워","discipline":"선구안","velocity":"구속","control":"제구","stuff":"구위","speed":"스피드","defense":"수비","arm":"송구","stamina":"지구력","mental":"멘탈"][kind]! + " 훈련"].waitForExistence(timeout: 5), "selected route must match " + kind)
            reveal(app.buttons["startTraining"], app); app.buttons["startTraining"].tap()
            if kind == "defense" {
                let field = app.descendants(matching:.any).matching(identifier:"trainingField").firstMatch
                XCTAssertTrue((field.value as? String ?? "").contains("선수 가로 50 세로 50"), "Preparation scrolling must not move the player")
            }
            capture(app, "v51-after-" + kind)
        }
    }

    @MainActor func testV51LibraryAndTraitPoliciesRemainReadOnly() {
        continueAfterFailure = false
        let app = launch(), before = status(app)
        app.buttons["managementTab-player"].tap();app.buttons["facility-traits"].tap()
        capture(app,"v51-trait-owned-active")
        close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        pickPitcher(app)
        let pitcherBefore = status(app)
        app.buttons["managementTab-player"].tap();app.buttons["facility-positions"].tap()
        XCTAssertTrue(app.staticTexts["pitchLibraryCount"].waitForExistence(timeout:5))
        capture(app,"v51-pitch-library-registered")
        let learn = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","pitchStudyStart-")).firstMatch
        reveal(learn,app);XCTAssertTrue(learn.isHittable);capture(app,"v51-pitch-library-learning");learn.tap()
        XCTAssertTrue(app.buttons["pitchStudyConfirm"].waitForExistence(timeout:5));capture(app,"v51-pitch-library-confirm")
        app.buttons["취소"].tap();close(app)
        app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),pitcherBefore)
    }

    @MainActor func testV44SaveSettingsPreviewCancelAndRestoreQAOnly() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-save-protection-verification","-save-protection-preview"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30))
        app.buttons["clubhouse-settings"].tap()
        if !app.switches["settingHaptics"].waitForExistence(timeout: 3) { app.buttons["clubhouse-settings"].tap() }
        XCTAssertTrue(app.switches["settingHaptics"].waitForExistence(timeout:5));capture(app,"v44-save-settings")
        let confirm=app.buttons["confirmRestoreSave"];reveal(confirm,app);XCTAssertTrue(confirm.waitForExistence(timeout:8));capture(app,"v44-verified-preview")
        confirm.tap();XCTAssertTrue(app.buttons["전체 복원"].waitForExistence(timeout:5));app.buttons["취소"].tap()
        XCTAssertTrue(confirm.exists);confirm.tap();app.buttons["전체 복원"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:10));capture(app,"v44-restored-qa-home")
        pickPitcher(app);app.buttons["clubhouse-settings"].tap();XCTAssertTrue(app.buttons["exportSave"].waitForExistence(timeout:8));capture(app,"v44-pitcher-settings")
    }
    @MainActor func testV44SaveSettingsLargestText() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-save-protection-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-management-reduced-motion-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30))
        reveal(app.buttons["clubhouse-settings"],app);app.buttons["clubhouse-settings"].tap()
        let export=app.buttons["exportSave"];reveal(export,app);XCTAssertTrue(export.isHittable);capture(app,"v44-large-export")
        let restore=app.buttons["importSave"];reveal(restore,app);XCTAssertTrue(restore.isHittable);capture(app,"v44-large-import")
    }

    @MainActor func testV42GuidanceBothRolesReadOnly() {
        continueAfterFailure = false
        let app = launch()
        for role in 0..<2 {
            if role == 1 { pickPitcher(app) }
            app.buttons["managementTab-game"].tap()
            if !app.buttons["facility-calendar"].waitForExistence(timeout: 3) { app.buttons["managementTab-game"].tap() }
            app.buttons["facility-calendar"].tap()
            let guide = app.descendants(matching: .any).matching(identifier: "earlyPlayGuidance").firstMatch
            XCTAssertTrue(guide.waitForExistence(timeout: 8))
            reveal(guide, app)
            let detail = app.staticTexts["earlyPlayDetail"]
            XCTAssertTrue(detail.waitForExistence(timeout: 5))
            reveal(detail, app); capture(app, "v42-guidance-\(role)")
            app.swipeDown()
            app.buttons["닫기"].firstMatch.tap()
            app.buttons["managementTab-player"].tap(); app.buttons["facility-abilities"].tap()
            let feedback = app.staticTexts["homeGrowthFeedback"]
            reveal(feedback, app); XCTAssertTrue(feedback.exists); capture(app, "v42-growth-\(role)")
            close(app)
        }
    }

    @MainActor func testV42LargestGuidance() {
        continueAfterFailure = false
        let app = launch(large: true)
        app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap()
        reveal(app.buttons["facility-calendar"], app); app.buttons["facility-calendar"].tap()
        let detail = app.staticTexts["earlyPlayDetail"]
        reveal(detail, app); XCTAssertTrue(detail.isHittable); capture(app, "v42-large-guidance")
    }

    @MainActor func testV41PositionAdviceCompareTrainingAndCatcherStayReadOnly() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v41-position-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25));let before=status(app)
        app.buttons["managementTab-player"].tap();app.buttons["facility-positions"].tap()
        reveal(app.buttons["compareRecommendedPosition"],app);XCTAssertTrue(app.staticTexts["positionRecommendation"].label.contains("중견수"));capture(app,"v41-position-recommendation")
        app.buttons["compareRecommendedPosition"].tap();reveal(app.staticTexts["positionFit"],app);XCTAssertTrue(app.staticTexts["positionFit"].label.contains("76.0"));capture(app,"v41-center-comparison")
        reveal(app.buttons["homePositionSelect-C"],app);app.buttons["homePositionSelect-C"].tap();reveal(app.staticTexts["positionFitUnavailable"],app);XCTAssertTrue(app.staticTexts["positionFitUnavailable"].exists);capture(app,"v41-catcher-unavailable")
        reveal(app.buttons["compareRecommendedPosition"],app);app.buttons["compareRecommendedPosition"].tap();reveal(app.buttons["openPositionTraining"],app);app.buttons["openPositionTraining"].tap()
        XCTAssertTrue(app.buttons["startPositionTraining"].waitForExistence(timeout:8));capture(app,"v41-training-preparation")
        app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
        pickPitcher(app);app.buttons["managementTab-player"].tap();XCTAssertTrue(app.buttons["facility-positions"].label.contains("구종 보관함"));app.buttons["facility-positions"].tap();XCTAssertFalse(app.staticTexts["positionRecommendation"].exists);capture(app,"v41-pitcher-existing-library")
    }
    @MainActor func testV41SmallLargestTextPositionAdvice() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v41-position-verification","-management-reduced-motion-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25));let before=status(app)
        app.buttons["managementLargeMenu"].tap();app.buttons["선수"].tap();reveal(app.buttons["facility-positions"],app);app.buttons["facility-positions"].tap()
        let compare=app.buttons["compareRecommendedPosition"];for _ in 0..<25 {if compare.isHittable {break};app.swipeUp()};XCTAssertTrue(compare.isHittable);capture(app,"v41-small-recommendation");compare.tap()
        reveal(app.staticTexts["positionAdviceReadiness"],app);XCTAssertTrue(app.staticTexts["positionAdviceReadiness"].isHittable);capture(app,"v41-small-readiness");close(app);XCTAssertEqual(status(app),before)
    }

    @MainActor func testV40OverseasReturnCoachingBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-v40-bench-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
            let policy=app.staticTexts["coachNeutralPerformance"];reveal(policy,app);XCTAssertTrue(policy.label.contains("양쪽 성과50"));capture(app,"v40-"+(pitcher ? "pitcher":"batter")+"-neutral-comparison")
            reveal(app.staticTexts["coachRestedGap"],app);XCTAssertTrue(app.staticTexts["coachRestedGap"].exists);capture(app,"v40-"+(pitcher ? "pitcher":"batter")+"-return-plan")
            reveal(app.buttons["coachRest"],app);XCTAssertTrue(app.buttons["coachRest"].isEnabled);app.buttons["coachRest"].tap();capture(app,"v40-"+(pitcher ? "pitcher":"batter")+"-rest-confirm")
            app.buttons["취소 · 돌아가기"].tap()
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before);app.buttons["managementTab-home"].tap()
        }
    }

    @MainActor func testV40SmallLargestTextReturnPlan() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-v40-bench-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap();reveal(app.buttons["facility-game"],app);app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
            let policy=app.staticTexts["coachNeutralPerformance"];for _ in 0..<30 {if policy.isHittable {break};app.swipeUp()};XCTAssertTrue(policy.isHittable);capture(app,"v40-small-"+(pitcher ? "pitcher":"batter"))
            app.navigationBars.buttons.element(boundBy:0).tap();close(app)
        }
    }
    @MainActor func testV39FrozenForecastBothRolesAndLegacy() {
        continueAfterFailure=false
        for legacy in [false,true] {
            let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v39-forecast-verification"]+(legacy ? ["-v39-legacy"]:[]);app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25))
            for pitcher in [false,true] {
                if pitcher {pickPitcher(app)}
                let before=status(app)
                app.buttons["managementTab-career"].tap();app.buttons["facility-contracts"].tap();reveal(app.buttons["openOverseasReport"],app);app.buttons["openOverseasReport"].tap()
                let label=app.staticTexts["growthForecastPolicy"];reveal(label,app);XCTAssertTrue(label.label.contains(legacy ? "V1":"V2"));capture(app,"v39-"+(pitcher ? "pitcher":"batter")+(legacy ? "-legacy":"-forecast"))
                if !legacy {let text=app.staticTexts["growthForecastWindow"];reveal(text,app);XCTAssertTrue(text.label.contains("미래 발동"))}
                app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before);app.buttons["managementTab-home"].tap()
            };app.terminate()
        }
    }

    @MainActor func testV39SmallLargestTextForecastBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v39-forecast-verification","-management-reduced-motion-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            app.buttons["managementLargeMenu"].tap();app.buttons["커리어"].tap();reveal(app.buttons["facility-contracts"],app);app.buttons["facility-contracts"].tap();reveal(app.buttons["openOverseasReport"],app);app.buttons["openOverseasReport"].tap()
            let policy=app.staticTexts["growthForecastPolicy"];for _ in 0..<40 {if policy.isHittable {break};app.swipeUp()}
            XCTAssertTrue(policy.isHittable);capture(app,"v39-small-"+(pitcher ? "pitcher":"batter"))
            app.navigationBars.buttons.element(boundBy:0).tap();close(app)
        }
    }
    @MainActor func testV38GrowthWindowAndPositionConfirmationKeepReadOnlyStateBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v38-development-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-player"].tap();app.buttons["facility-abilities"].tap()
            reveal(app.staticTexts["developmentActiveWindow"],app);XCTAssertTrue(app.staticTexts["developmentActiveWindow"].label.contains(pitcher ? "제구":"수비"))
            capture(app,"v38-"+role+"-growth-window");close(app);XCTAssertEqual(status(app),before)
            if !pitcher {
                app.buttons["facility-positions"].tap();reveal(app.buttons["homePositionSelect-SS"],app);app.buttons["homePositionSelect-SS"].tap()
                reveal(app.buttons["changePrimaryPosition"],app);XCTAssertTrue(app.buttons["changePrimaryPosition"].isEnabled);capture(app,"v38-batter-position-ready")
                app.buttons["changePrimaryPosition"].tap();capture(app,"v38-batter-position-confirm");app.buttons["취소"].tap();close(app);XCTAssertEqual(status(app),before)
                app.buttons["facility-positions"].tap();reveal(app.buttons["homePositionSelect-SS"],app);app.buttons["homePositionSelect-SS"].tap();reveal(app.buttons["changePrimaryPosition"],app);app.buttons["changePrimaryPosition"].tap();app.buttons["전환 확정 · 오늘 행동 사용"].tap()
                reveal(app.staticTexts["homeSelectedPositionMastery"],app);XCTAssertTrue(app.staticTexts["homeSelectedPositionMastery"].label.contains("40.0"));capture(app,"v38-batter-position-applied");close(app)
                XCTAssertEqual(Array(status(app).prefix(2)),Array(before.prefix(2)));XCTAssertNotEqual(status(app).last,before.last)
            }
            app.buttons["managementTab-home"].tap()
        }
    }
    @MainActor func testV38CompletedTrainingShowsCapturedGrowthPolicyReadOnlyBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v38-development-verification","-v38-result-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-player"].tap();app.buttons["facility-abilities"].tap();reveal(app.buttons["developmentTraining"],app);app.buttons["developmentTraining"].tap()
            reveal(app.staticTexts["trainingGrowthPolicy"],app);XCTAssertTrue(app.staticTexts["trainingGrowthPolicy"].label.contains("성장 집중"));capture(app,"v38-"+(pitcher ? "pitcher":"batter")+"-training-policy-result")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before);app.buttons["managementTab-home"].tap()
        }
    }
    @MainActor func testV38LegacyAdoptionDoesNotSpendActionOrRewriteResults() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v38-development-verification","-v38-legacy-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25));let before=status(app)
        app.buttons["managementTab-player"].tap();app.buttons["facility-abilities"].tap();reveal(app.buttons["developmentAdopt"],app);capture(app,"v38-legacy-growth-kept")
        app.buttons["developmentAdopt"].tap();capture(app,"v38-legacy-adopt-confirm");app.buttons["현재 능력을 유지하고 적용"].tap()
        reveal(app.staticTexts["developmentTiming"],app);XCTAssertTrue(app.staticTexts["developmentTiming"].label.contains("균형"));capture(app,"v38-legacy-adopted");close(app);XCTAssertEqual(status(app),before)
    }
    @MainActor func testV38SmallPhoneLargestTextGrowthAndPositionRemainReachable() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-v38-development-verification","-management-reduced-motion-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25));let before=status(app)
        app.buttons["managementLargeMenu"].tap();app.buttons["선수"].tap();app.buttons["facility-abilities"].tap();reveal(app.staticTexts["developmentActiveWindow"],app);XCTAssertTrue(app.staticTexts["developmentActiveWindow"].isHittable);capture(app,"v38-large-growth-window");close(app)
        app.buttons["facility-positions"].tap();reveal(app.buttons["homePositionSelect-SS"],app);app.buttons["homePositionSelect-SS"].tap();reveal(app.buttons["changePrimaryPosition"],app);XCTAssertTrue(app.buttons["changePrimaryPosition"].isHittable);capture(app,"v38-large-position-action");close(app);XCTAssertEqual(status(app),before)
        pickPitcher(app);app.buttons["managementLargeMenu"].tap();app.buttons["선수"].tap();app.buttons["facility-abilities"].tap();reveal(app.staticTexts["developmentActiveWindow"],app);XCTAssertTrue(app.staticTexts["developmentActiveWindow"].isHittable);capture(app,"v38-large-pitcher-window")
    }

    @MainActor func testV36SeasonAndDomesticRenewalShowFrozenBenchContextBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-v36-opportunity-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:150))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-career"].tap();app.buttons["facility-goals"].tap()
            reveal(app.buttons["openClubSeasonGoals"],app);app.buttons["openClubSeasonGoals"].tap();reveal(app.buttons["openClubSeasonReviews"],app);app.buttons["openClubSeasonReviews"].tap()
            let advice=app.staticTexts["clubNextRoleAdvice"];reveal(advice,app);XCTAssertTrue(advice.label.contains("기회 제한"))
            capture(app,"v36-"+role+"-season-finding")
            let counts=app.descendants(matching:.any).matching(identifier:"seasonParticipationCounts").firstMatch;reveal(counts,app);XCTAssertTrue(counts.label.contains("벤치"))
            capture(app,"v36-"+role+"-season-counts")
            let prepare=app.buttons["seasonParticipationPrepare"];reveal(prepare,app);prepare.tap()
            XCTAssertTrue(app.buttons["opportunityCurrentSchedule"].waitForExistence(timeout:10));capture(app,"v36-"+role+"-current-preparation")
            app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();close(app)
            app.buttons["facility-contracts"].tap();reveal(app.buttons["openRenewalOffer"],app);app.buttons["openRenewalOffer"].tap()
            let finding=app.staticTexts["domesticParticipationFinding"];reveal(finding,app);XCTAssertTrue(finding.label.contains("기회 제한"))
            capture(app,"v36-"+role+"-domestic-renewal")
            XCTAssertFalse(app.buttons["acceptRenewalOffer"].exists)
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV36OverseasRenewalContextDoesNotReplaceOriginalOfferBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-career-objectives-verification","-goal-special-verification","-overseas-renewal-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:150))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-career"].tap();app.buttons["facility-contracts"].tap()
            reveal(app.buttons["openOverseasRenewal"],app);app.buttons["openOverseasRenewal"].tap()
            let evaluate=app.buttons["evaluateOverseasRenewal"];reveal(evaluate,app);if evaluate.exists {evaluate.tap()}
            let sample=app.staticTexts["overseasParticipationSample"].firstMatch;reveal(sample,app);XCTAssertTrue(sample.exists)
            capture(app,"v36-"+(pitcher ? "pitcher":"batter")+"-overseas-context")
            XCTAssertFalse(app.staticTexts["overseasRenewalError"].exists)
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV36SmallPhoneLargeTextParticipationCountsAndNextAction() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-v36-opportunity-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:150))
        app.buttons["managementLargeMenu"].tap();app.buttons["커리어"].tap();reveal(app.buttons["facility-goals"],app);app.buttons["facility-goals"].tap()
        reveal(app.buttons["openClubSeasonGoals"],app);app.buttons["openClubSeasonGoals"].tap();reveal(app.buttons["openClubSeasonReviews"],app);app.buttons["openClubSeasonReviews"].tap()
        let sample=app.staticTexts["seasonParticipationSample"];reveal(sample,app);XCTAssertTrue(sample.isHittable);capture(app,"v36-large-sample")
        let prepare=app.buttons["seasonParticipationPrepare"];reveal(prepare,app);XCTAssertTrue(prepare.isHittable);capture(app,"v36-large-action")
    }
    @MainActor func testV35CoachAdviceTrainingPreparationAndConfirmedRestBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-v35-coach-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
            let gap=app.staticTexts["coachScoreGap"];reveal(gap,app);XCTAssertTrue(gap.exists);let score=gap.label
            XCTAssertTrue(app.staticTexts["coachNextEvaluation"].exists)
            capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-coach")
            let train=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","coachTrain-")).firstMatch;reveal(train,app);XCTAssertTrue(train.isEnabled)
            capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-deficits")
            let kind=train.label.replacingOccurrences(of:" 훈련 준비",with:"");train.tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout:10));XCTAssertTrue(app.navigationBars[kind+" 훈련"].exists)
            capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-training-ready")
            app.navigationBars.buttons.element(boundBy:0).tap()
            let rest=app.buttons["coachRest"];reveal(rest,app);rest.tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout:8));capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-rest-preview")
            app.buttons["취소 · 돌아가기"].tap();XCTAssertTrue(app.staticTexts["coachCurrentFatigue"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["coachCurrentFatigue"].label.contains("55"))
            rest.tap();app.buttons["confirmRest"].tap();XCTAssertTrue(app.staticTexts["restSaved"].waitForExistence(timeout:5));XCTAssertEqual(app.buttons["restDone"].label,"코치 피드백으로 돌아가기");app.buttons["restDone"].tap()
            let fatigue=app.staticTexts["coachCurrentFatigue"];XCTAssertTrue(fatigue.waitForExistence(timeout:5));XCTAssertTrue(fatigue.label.contains("37"));XCTAssertFalse(rest.isEnabled)
            capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-rest-used")
            reveal(gap,app);XCTAssertEqual(gap.label,score)
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app).first,before.first)
        }
    }
    @MainActor func testV35CoachResumesSavedTrainingInsteadOfNewAdviceBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-v35-coach-verification","-v35-coach-pending"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
            let resume=app.buttons["coachResumeTraining"];reveal(resume,app);XCTAssertTrue(resume.isEnabled);XCTAssertFalse(app.buttons["coachRest"].isEnabled)
            capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-resume-priority")
            resume.tap();let progress=app.descendants(matching:.any).matching(identifier:"trainingProgress").firstMatch;XCTAssertTrue(progress.waitForExistence(timeout:10))
            XCTAssertFalse(app.buttons["startTraining"].exists);capture(app,"v35-"+(pitcher ? "pitcher":"batter")+"-resume-training")
            app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV35SmallPhoneLargeTextCoachDatesAndActionsRemainReachable() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-v35-coach-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap();reveal(app.buttons["facility-game"],app);app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
        let day=app.staticTexts["coachNextEvaluation"];reveal(day,app);XCTAssertTrue(day.isHittable);capture(app,"v35-large-dates")
        let rest=app.buttons["coachRest"];reveal(rest,app);XCTAssertTrue(rest.isHittable);XCTAssertTrue(rest.isEnabled);capture(app,"v35-large-actions")
    }
    @MainActor func testV34ObservedNPCPerformanceAndFatigueAreReadOnlyBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-v34-npc-evidence"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap()
            reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
            let sample=app.staticTexts["npcPerformanceSample"];reveal(sample,app);XCTAssertTrue(sample.isHittable)
            let result=app.staticTexts["npcPerformanceStatus"];reveal(result,app);XCTAssertTrue(result.label.contains("평가 가능"))
            capture(app,"v34-"+(pitcher ? "pitcher":"batter")+"-actual-performance")
            let fatigue=app.staticTexts["npcFatigueStatus"];reveal(fatigue,app);XCTAssertTrue(fatigue.isHittable);XCTAssertTrue(fatigue.label.contains("준비"))
            capture(app,"v34-"+(pitcher ? "pitcher":"batter")+"-fatigue")
            let first=fatigue.label
            app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["openClubSelection"].tap()
            reveal(fatigue,app);XCTAssertEqual(fatigue.label,first)
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV34SmallPhoneLargeTextSampleAndFatigueRemainReachable() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-v34-npc-evidence","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap()
        reveal(app.buttons["facility-game"],app);app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
        let sample=app.staticTexts["npcPerformanceSample"];reveal(sample,app);XCTAssertTrue(sample.isHittable)
        capture(app,"v34-large-sample")
        let fatigue=app.staticTexts["npcFatigueStatus"];reveal(fatigue,app);XCTAssertTrue(fatigue.isHittable)
        capture(app,"v34-large-fatigue")
    }
    @MainActor func testV33OpponentAndCompetitionShowStoredCompleteProfilesBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-analysis"].tap()
            reveal(app.buttons["hubOpponentAnalysis"],app);app.buttons["hubOpponentAnalysis"].tap()
            XCTAssertTrue(app.buttons["opponentTab-pitcher"].waitForExistence(timeout:10));app.buttons["opponentTab-pitcher"].tap()
            let profile=app.descendants(matching:.any).matching(identifier:"opponentCompletePitcher").firstMatch;reveal(profile,app);XCTAssertTrue(profile.exists)
            let mastery=app.descendants(matching:.any).matching(identifier:"opponentPitchMastery-four-seam").firstMatch;reveal(mastery,app);XCTAssertTrue(mastery.exists)
            capture(app,"v33-"+(pitcher ? "pitcher":"batter")+"-opponent-pitcher")
            app.buttons["opponentTab-batter"].tap()
            let batter=app.descendants(matching:.any).matching(identifier:"opponentCompleteBatter").firstMatch;reveal(batter,app);XCTAssertTrue(batter.exists)
            capture(app,"v33-"+(pitcher ? "pitcher":"batter")+"-opponent-batter")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
            app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
            let values=app.descendants(matching:.any).matching(identifier:"selectionRivalAbilities").firstMatch;reveal(values,app);XCTAssertTrue(values.exists);values.tap()
            let mental=app.descendants(matching:.any).matching(identifier:"selectionRival-homeMental").firstMatch;reveal(mental,app);XCTAssertTrue(mental.exists)
            capture(app,"v33-"+(pitcher ? "pitcher":"batter")+"-rival-abilities")
            if pitcher {
                let pitch=app.descendants(matching:.any).matching(identifier:"selectionRival-pitch-four-seam").firstMatch;reveal(pitch,app);XCTAssertTrue(pitch.exists)
                capture(app,"v33-pitcher-rival-mastery")
            }
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV33LargeTextCompletePitcherAndRivalProfileOnSmallPhone() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap();reveal(app.buttons["facility-analysis"],app);app.buttons["facility-analysis"].tap()
        reveal(app.buttons["hubOpponentAnalysis"],app);app.buttons["hubOpponentAnalysis"].tap();app.buttons["opponentTab-pitcher"].tap()
        let mastery=app.descendants(matching:.any).matching(identifier:"opponentPitchMastery-four-seam").firstMatch;reveal(mastery,app);XCTAssertTrue(mastery.isHittable)
        capture(app,"v33-large-opponent-mastery")
        app.navigationBars.buttons.element(boundBy:0).tap();close(app)
        reveal(app.buttons["facility-game"],app);app.buttons["facility-game"].tap();reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
        let values=app.descendants(matching:.any).matching(identifier:"selectionRivalAbilities").firstMatch;reveal(values,app);values.tap()
        let mental=app.descendants(matching:.any).matching(identifier:"selectionRival-homeMental").firstMatch;reveal(mental,app);XCTAssertTrue(mental.isHittable)
        capture(app,"v33-large-rival-mental")
    }
    @MainActor func testV32BenchCompetitionAndTeamResultBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap()
            let panel=app.staticTexts["clubSelectionStatus"];XCTAssertTrue(panel.waitForExistence(timeout:8));XCTAssertTrue(panel.label.contains("벤치"))
            capture(app,"v32-"+(pitcher ? "pitcher":"batter")+"-selection-home")
            let before=status(app)
            app.buttons["openClubSelection"].tap()
            XCTAssertTrue(app.staticTexts["clubSelectionDetail"].waitForExistence(timeout:6))
            capture(app,"v32-"+(pitcher ? "pitcher":"batter")+"-competition")
            app.swipeUp();capture(app,"v32-"+(pitcher ? "pitcher":"batter")+"-evidence")
            app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertEqual(status(app),before);close(app)
            app.buttons["managementTab-home"].tap();app.buttons["clubhouse-rest"].tap()
            app.buttons["confirmRest"].tap();app.buttons["restDone"].tap()
            app.buttons["homeTodayGame"].tap()
            XCTAssertTrue(app.buttons["gameAutomatic"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["confirmGamePlan"].exists)
            app.buttons["gameAutomatic"].tap();app.buttons["진행하고 결과 저장"].tap()
            let result=app.staticTexts["gameResultNoAppearance"];reveal(result,app);XCTAssertTrue(result.waitForExistence(timeout:10))
            capture(app,"v32-"+(pitcher ? "pitcher":"batter")+"-bench-result")
            let home=app.buttons["gameReturnHome"];reveal(home,app);home.tap();XCTAssertTrue(app.buttons["roomProfile"].waitForExistence(timeout:5))
        }
    }
    @MainActor func testV32FrozenReportShowsBenchOpportunityWithoutPersonalSample() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-club-selection-completed"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            app.buttons["managementTab-career"].tap();app.buttons["facility-observation"].tap()
            reveal(app.buttons["openSavedScoutingReport"],app);app.buttons["openSavedScoutingReport"].tap()
            let opportunities=app.staticTexts["scoutOpportunities"];reveal(opportunities,app)
            XCTAssertTrue(opportunities.exists);XCTAssertTrue(opportunities.label.contains("벤치 1"))
            capture(app,"v32-"+(pitcher ? "pitcher":"batter")+"-observation-opportunities")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app)
            app.buttons["facility-goals"].tap();reveal(app.buttons["openClubSeasonGoals"],app);app.buttons["openClubSeasonGoals"].tap()
            let actual=app.staticTexts["clubGoalOpportunities"];reveal(actual,app);XCTAssertTrue(actual.exists)
            capture(app,"v32-"+(pitcher ? "pitcher":"batter")+"-season-opportunities")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app)
        }
    }
    @MainActor func testV32StarterSelectionAndLargeText() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap()
        reveal(app.buttons["facility-game"],app);app.buttons["facility-game"].tap()
        reveal(app.buttons["openClubSelection"],app);app.buttons["openClubSelection"].tap()
        XCTAssertTrue(app.staticTexts["clubSelectionDetail"].waitForExistence(timeout:5));capture(app,"v32-large-selection")
        reveal(app.staticTexts["selectionOwnScore"],app);capture(app,"v32-large-own-score")
        reveal(app.staticTexts["selectionRivalScore"],app);capture(app,"v32-large-rival-score")
        XCTAssertTrue(app.staticTexts["selectionRivalScore"].isHittable)
    }
    @MainActor func testV31AgingRetirementArchiveAndNewCareerFormBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-management-v31-lifecycle"];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:20))
            if pitcher {pickPitcher(app)}
            app.buttons["managementTab-career"].tap();app.buttons["facility-contracts"].tap()
            let retire=app.buttons["openRetirementConfirmation"];reveal(retire,app);XCTAssertTrue(retire.isHittable)
            capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-aging")
            retire.tap();let confirm=app.buttons["은퇴하고 기록 보존"].firstMatch;XCTAssertTrue(confirm.waitForExistence(timeout:4));capture(app,"v31-retirement-confirmation");confirm.tap()
            let archive=app.descendants(matching:.any).matching(identifier:"retirementArchive").firstMatch
            XCTAssertTrue(archive.waitForExistence(timeout:8));capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-archive")
            let create=app.buttons["archiveNewCareer"];reveal(create,app);create.tap()
            XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout:5));capture(app,"v31-new-career-form")
        }
    }
    @MainActor func testV31ActualOpponentPitchHistoryIsReadOnlyBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-management-stats-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:20))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-analysis"].tap()
            reveal(app.buttons["hubOpponentAnalysis"],app);app.buttons["hubOpponentAnalysis"].tap()
            XCTAssertTrue(app.buttons["opponentTab-pitcher"].waitForExistence(timeout:10));app.buttons["opponentTab-pitcher"].tap()
            let history=app.descendants(matching:.any).matching(identifier:"opponentActualPitchSample").firstMatch
            reveal(history,app);XCTAssertTrue(history.exists);app.swipeUp();capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-pitch-history")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app)
            XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV31ProjectRoutesToAssignedTrainingAndCompletionActions() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-career-objectives-verification","-goal-special-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            app.buttons["managementTab-career"].tap();app.buttons["facility-goals"].tap()
            reveal(app.buttons["openCareerObjectives"],app);app.buttons["openCareerObjectives"].tap()
            reveal(app.buttons["startCareerProject"],app);app.buttons["startCareerProject"].tap()
            reveal(app.buttons["projectAllTasks"],app);app.buttons["projectAllTasks"].tap()
            reveal(app.buttons["projectTrainingAction"],app);let label=app.buttons["projectTrainingAction"].label
            capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-project-route");app.buttons["projectTrainingAction"].tap()
            XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout:8))
            XCTAssertTrue(app.navigationBars.firstMatch.identifier.contains(String(label.split(separator:" ").first!)))
            capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-assigned-training")
            app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();close(app)
        }
    }
    @MainActor func testV31OfficialMatchReceiptAndNextActionsBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-career-objectives-verification","-goal-special-verification","-v31-match-completed"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app)
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap()
            reveal(app.buttons["openCareerGame"],app);app.buttons["openCareerGame"].tap()
            let feedback=app.descendants(matching:.any).matching(identifier:"matchProjectContribution").firstMatch
            reveal(feedback,app);XCTAssertTrue(feedback.exists);capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-match-contribution")
            let action=app.buttons["completionObservationAction"];reveal(action,app);action.tap()
            capture(app,"v31-"+(pitcher ? "pitcher":"batter")+"-next-observation")
            app.navigationBars.buttons.element(boundBy:0).tap()
            reveal(app.buttons["gameReturnHome"],app);app.buttons["gameReturnHome"].tap();close(app)
            XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV31LargeTextRetirementArchiveOnSmallPhone() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-management-v31-lifecycle","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:20))
        app.buttons["managementLargeMenu"].tap();app.buttons["커리어"].tap()
        reveal(app.buttons["facility-contracts"],app);app.buttons["facility-contracts"].tap()
        reveal(app.buttons["openRetirementConfirmation"],app);capture(app,"v31-large-aging");app.buttons["openRetirementConfirmation"].tap()
        app.buttons["은퇴하고 기록 보존"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"retirementArchive").firstMatch.waitForExistence(timeout:8));capture(app,"v31-large-archive")
        let create=app.buttons["archiveNewCareer"];reveal(create,app);XCTAssertTrue(create.isHittable);capture(app,"v31-large-archive-action")
    }
    @MainActor func testV30ThrowFiveAttemptsResumeAndHistoricalResult() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15))
        app.buttons["managementTab-training"].tap();app.buttons["facility-physical"].tap()
        revealLocationChoice(app.buttons["trainingKind-arm"],app);app.buttons["trainingKind-arm"].tap()
        reveal(app.buttons["openTraining"],app);app.buttons["openTraining"].tap()
        reveal(app.buttons["startTraining"],app);app.buttons["startTraining"].tap()
        for attempt in 1...5 {
            let send=app.buttons["trainingAttempt"];reveal(send,app)
            if attempt == 1 {capture(app,"v30-arm-ready")};send.tap()
            XCTAssertFalse(app.buttons["trainingNext"].exists)
            XCTAssertFalse(app.staticTexts["throwPracticeComparison"].exists)
            if attempt == 1 {capture(app,"v30-arm-flight")}
            XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout:9))
            XCTAssertTrue(app.staticTexts["throwPracticeComparison"].exists)
            if attempt == 1 {capture(app,"v30-arm-receive-feedback")}
            reveal(app.buttons["trainingNext"],app);app.buttons["trainingNext"].tap()
            if attempt == 2 {
                app.navigationBars.buttons.element(boundBy:0).tap();reveal(app.buttons["openTraining"],app);app.buttons["openTraining"].tap()
                XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"trainingProgress").firstMatch.label.contains("3 / 5"))
                capture(app,"v30-arm-resumed")
            }
        }
        XCTAssertTrue(app.staticTexts["trainingCompleted"].waitForExistence(timeout:6))
        let growth=app.staticTexts["trainingGrowth"].label
        let receipt=app.descendants(matching:.any).matching(identifier:"trainingProjectFeedback").firstMatch
        reveal(receipt,app);XCTAssertTrue(receipt.exists);capture(app,"v30-arm-completion")
        app.navigationBars.buttons.element(boundBy:0).tap();reveal(app.buttons["openTraining"],app);app.buttons["openTraining"].tap()
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label,growth);capture(app,"v30-arm-reopened")
    }
    @MainActor func testV30BattingDisciplineAndConditioningScenes() {
        continueAfterFailure=false
        let app=XCUIApplication()
        for kind in ["contact","discipline","speed","stamina","mental"] {
            app.terminate();app.launchArguments=["-management-career-verification"];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15))
            if kind == "stamina" {pickPitcher(app)}
            app.buttons["managementTab-training"].tap();app.buttons[["contact","discipline"].contains(kind) ? "facility-training":"facility-physical"].tap()
            revealLocationChoice(app.buttons["trainingKind-"+kind],app);app.buttons["trainingKind-"+kind].tap()
            reveal(app.buttons["openTraining"],app);app.buttons["openTraining"].tap()
            reveal(app.buttons["startTraining"],app);app.buttons["startTraining"].tap()
            let send=app.buttons["trainingAttempt"]
            if kind == "mental" {reveal(app.buttons["mentalChoice-0"],app);capture(app,"v30-mental-ready");app.buttons["mentalChoice-0"].tap()}
            else {
                reveal(send,app);capture(app,"v30-"+kind+"-ready");send.tap()
                if kind == "contact" {send.tap()}
                else if kind == "discipline" {reveal(app.buttons["trainingCallStrike"],app);app.buttons["trainingCallStrike"].tap()}
                else { /* Let the unchanged four-second input window expire; steps are unit-tested. */ }
            }
            XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout:10));capture(app,"v30-"+kind+"-feedback")
        }
    }
    @MainActor func testV30LargeReducedPracticeAndSpecialDrillsStayIsolated() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-management-career-verification","-management-reduced-motion-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15));let before=status(app)
        app.buttons["managementLargeMenu"].tap();app.buttons["훈련"].tap();reveal(app.buttons["facility-practice"],app);app.buttons["facility-practice"].tap()
        reveal(app.buttons["openTrainingPractice"],app);app.buttons["openTrainingPractice"].tap()
        reveal(app.buttons["practiceGeneralTraining"],app);app.buttons["practiceGeneralTraining"].tap()
        revealLocationChoice(app.buttons["trainingCategory-1"],app);app.buttons["trainingCategory-1"].tap()
        revealLocationChoice(app.buttons["trainingKind-arm"],app);app.buttons["trainingKind-arm"].tap()
        reveal(app.buttons["startTraining"],app);app.buttons["startTraining"].tap()
        for _ in 0..<5 {reveal(app.buttons["trainingAttempt"],app);app.buttons["trainingAttempt"].tap();XCTAssertFalse(app.buttons["trainingNext"].exists);XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout:9));reveal(app.buttons["trainingNext"],app);app.buttons["trainingNext"].tap()}
        XCTAssertTrue(app.staticTexts["practiceCompleted"].waitForExistence(timeout:5));XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"trainingProjectFeedback").firstMatch.exists);capture(app,"v30-large-practice-result")
        app.navigationBars.buttons.element(boundBy:0).tap()
        reveal(app.buttons["practiceTrait-strong-arm"],app);app.buttons["practiceTrait-strong-arm"].tap()
        reveal(app.buttons["traitDrillSubmit"],app);capture(app,"v30-large-trait-ready");app.buttons["traitDrillSubmit"].tap()
        XCTAssertFalse(app.staticTexts["traitDrillFeedback"].exists);XCTAssertTrue(app.staticTexts["traitDrillFeedback"].waitForExistence(timeout:7));capture(app,"v30-large-trait-feedback")
        app.buttons["acquisitionCloseDrill"].tap()
        reveal(app.buttons["practicePosition-CF"],app);app.buttons["practicePosition-CF"].tap()
        reveal(app.buttons["positionCatch"],app);app.buttons["positionCatch"].tap();reveal(app.buttons["positionThrow"],app);capture(app,"v30-large-position-ready");app.buttons["positionThrow"].tap()
        XCTAssertFalse(app.staticTexts["positionFeedback"].exists);XCTAssertTrue(app.staticTexts["positionFeedback"].waitForExistence(timeout:7));capture(app,"v30-large-position-feedback")
        app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["closeRoomDetail"].tap()
        app.buttons["managementLargeMenu"].tap();app.buttons["홈"].tap();XCTAssertEqual(status(app),before)
    }

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
                trace.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.794)).press(forDuration: 0.05,
                    thenDragTo: trace.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.206)))
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

    @MainActor func testV44PitchTrainingReturnAfterResultReopen() {
        checkLocationCareerTraining([(true, "control")])
    }
    @MainActor func testV28LocationCareerTrainingMotionResumeAndOneReward() {
        checkLocationCareerTraining([(true, "control"), (false, "defense"), (true, "defense")])
    }
    @MainActor private func checkLocationCareerTraining(_ cases: [(Bool, String)]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        for (pitcher, kind) in cases {
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
            if !app.buttons["closeRoomDetail"].waitForExistence(timeout: 3), app.buttons["BackButton"].exists {
                app.buttons["BackButton"].tap()
            }
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 5))
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
        app.buttons["managementTab-player"].tap()
        let library = app.buttons["facility-positions"]; v60Reveal(library, app); library.tap()
        XCTAssertTrue(app.staticTexts["등록 구종 · 4 / 5"].waitForExistence(timeout: 6))
        let empty = app.buttons["pitchStudySlot-empty"]
        reveal(empty, app); XCTAssertTrue(empty.isSelected)
        let slot = app.buttons["pitchStudySlot-four-seam"]
        reveal(slot, app); slot.tap(); XCTAssertTrue(slot.isSelected)
        reveal(empty, app); empty.tap(); XCTAssertTrue(empty.isSelected)
        capture(app, "v71-pitch-custom-slot")
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
        close(app)
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

extension ManagementDetailFlowTests {
    @MainActor func testV52ControlGuideIsReadOnlyAndNoInputReturnsToReady() {
        let app=XCUIApplication();app.launchArguments=["-management-career-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15))
        app.buttons["clubhouse-rest"].tap();app.buttons["confirmRest"].tap();app.buttons["restDone"].tap();app.buttons["homeTodayGame"].tap()
        XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout:8));app.buttons["opponentTab-plan"].tap()
        reveal(app.buttons["confirmGamePlan"],app);app.buttons["confirmGamePlan"].tap()
        let count=app.descendants(matching:.any).matching(identifier:"careerGameCount").firstMatch
        XCTAssertTrue(count.waitForExistence(timeout:8));let before=count.label
        app.buttons["gamePlaybackMenu"].tap();app.buttons["경기 조작 안내"].tap()
        XCTAssertTrue(app.navigationBars["경기 조작 안내"].waitForExistence(timeout:5));capture(app,"v52-live-control-guide")
        app.navigationBars["경기 조작 안내"].buttons["닫기"].tap()
        XCTAssertEqual(count.label,before)
        app.buttons["gameInput-swing"].tap();app.buttons["battingTouchSurface"].tap()
        let automatic=app.buttons["gameAutomatic"]
        let idle=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:automatic)
        XCTAssertEqual(XCTWaiter.wait(for:[idle],timeout:12),.completed)
        XCTAssertNotEqual(count.label,before);capture(app,"v52-live-batter-no-input")
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV53DailyStatusPartialSaveRetryAndAnnualRulesBothRoles() {
        let app=XCUIApplication()
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-v53-calendar-save-failure"]
            if pitcher {app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
            app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15))
            if pitcher {pickPitcher(app)}
            XCTAssertTrue(app.staticTexts["homeDailyStatus"].label.contains("팀 경기 없음"));capture(app,pitcher ? "v53-large-pitcher-offday":"v53-batter-offday")
            if pitcher {app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap()}
            else {app.buttons["managementTab-game"].tap()}
            reveal(app.buttons["facility-calendar"],app);app.buttons["facility-calendar"].tap()
            let scroll=app.scrollViews["calendarDetailScroll"]
            reveal(app.buttons["showSeasonSchedule"],app);app.buttons["showSeasonSchedule"].tap()
            XCTAssertTrue(app.staticTexts["calendarYearRule"].waitForExistence(timeout:5));capture(app,pitcher ? "v53-large-pitcher-year-rules":"v53-batter-year-rules")
            app.navigationBars["연간 일정"].buttons["닫기"].tap()
            reveal(app.buttons["advanceOffDays"],app);app.buttons["advanceOffDays"].tap()
            let title=app.staticTexts["calendarReceiptTitle"];XCTAssertTrue(title.waitForExistence(timeout:10));reveal(title,app)
            XCTAssertTrue(title.label.contains("일부 진행 저장 완료"))
            XCTAssertTrue(app.staticTexts["calendarReceiptTotals"].label.contains("완료 1일"));XCTAssertTrue(app.staticTexts["calendarReceiptTotals"].label.contains("90 → 68"))
            XCTAssertEqual(scroll.staticTexts["calendarDate"].label,"4월 3일 (금)")
            capture(app,pitcher ? "v53-large-pitcher-partial-receipt":"v53-batter-partial-receipt")
            let retry=app.buttons["retryCalendarProgress"];reveal(retry,app);XCTAssertTrue(retry.isEnabled);retry.tap()
            let date=scroll.staticTexts["calendarDate"]
            let arrived=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","4월 7일 (화)"),object:date)
            XCTAssertEqual(XCTWaiter.wait(for:[arrived],timeout:12),.completed)
            reveal(app.staticTexts["calendarTodayStatus"],app)
            XCTAssertTrue(app.staticTexts["calendarTodayStatus"].label.contains(pitcher ? "비등판일":"타자 출전 예정"))
            capture(app,pitcher ? "v53-large-pitcher-rotation-day":"v53-batter-game-day")
        }
    }
    @MainActor func testV53SeasonMetricsCoverageAndReadOnlyReopenBothRoles() {
        let app=XCUIApplication()
        for legacy in [false,true] {for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-v53-season-records"]
            if legacy {app.launchArguments.append("-v53-season-legacy")}
            app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15))
            if pitcher {pickPitcher(app)}
            let date=app.staticTexts["calendarDate"].firstMatch.label
            app.buttons["managementTab-game"].tap();app.buttons["facility-gameRecords"].tap()
            XCTAssertTrue(app.staticTexts["recentRecordsScope"].waitForExistence(timeout:5));capture(app,"v53-\(pitcher ? "pitcher":"batter")-recent-source-\(legacy ? "legacy":"full")")
            reveal(app.buttons["gameOpenSeason"],app);app.buttons["gameOpenSeason"].tap()
            let metric=app.descendants(matching:.any).matching(identifier: "seasonMetric-"+(pitcher ? "ERA":"OPS")).firstMatch
            reveal(metric,app);XCTAssertTrue(metric.exists)
            XCTAssertEqual(metric.label.contains("미집계"),legacy)
            capture(app,"v53-\(pitcher ? "pitcher":"batter")-season-metrics-\(legacy ? "legacy":"full")")
            let coverage=app.staticTexts["seasonCoverage"];reveal(coverage,app)
            XCTAssertTrue(coverage.label.contains(legacy ? "미수집 1":"미수집 0"));capture(app,"v53-\(pitcher ? "pitcher":"batter")-season-coverage-\(legacy ? "legacy":"full")")
            app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["closeRoomDetail"].tap();app.buttons["managementTab-home"].tap()
            XCTAssertEqual(app.staticTexts["calendarDate"].firstMatch.label,date)
        }}
    }
    @MainActor func testV53LeagueSourceScopeRemainsSeparateBothRoles() {
        let app=XCUIApplication()
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-management-stats-verification"];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:15));if pitcher {pickPitcher(app)}
            app.buttons["managementTab-game"].tap();app.buttons["facility-standings"].tap()
            XCTAssertTrue(app.staticTexts["leagueRecordScope"].waitForExistence(timeout:8))
            reveal(app.buttons["openAnnualLeague"],app);app.buttons["openAnnualLeague"].tap()
            XCTAssertTrue(app.staticTexts["leagueSeasonState"].waitForExistence(timeout:5));capture(app,pitcher ? "v53-pitcher-league-scope":"v53-batter-league-scope")
            let source=app.staticTexts["다른 팀 자동 경기"].firstMatch;reveal(source,app);XCTAssertTrue(source.exists)
            capture(app,pitcher ? "v53-pitcher-auto-source":"v53-batter-auto-source")
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor private func v54Contracts(_ app:XCUIApplication) {
        app.buttons["managementTab-career"].tap();app.buttons["facility-contracts"].tap()
    }
    @MainActor private func v54Element(_ id:String,_ app:XCUIApplication) -> XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    @MainActor func testV54EvaluationGatePreparationAndNoOfferBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:60))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-game"].tap();app.buttons["facility-calendar"].tap()
            let review=app.buttons["calendarOpenContractEvaluation"];reveal(review,app);XCTAssertTrue(review.isHittable);capture(app,"v54-"+role+"-calendar-evaluation-gate");review.tap()
            let guide=v54Element("contractEvaluationNextStep",app);XCTAssertTrue(guide.waitForExistence(timeout:8));XCTAssertTrue(guide.label.contains("정지"))
            capture(app,"v54-"+role+"-fixed-review")
            let acknowledge=app.buttons["acknowledgeContractEvaluation"];reveal(acknowledge,app);acknowledge.tap()
            XCTAssertFalse(app.buttons["acknowledgeContractEvaluation"].exists)
            reveal(app.buttons["openDomesticOffers"],app);app.buttons["openDomesticOffers"].tap()
            XCTAssertTrue(app.staticTexts["liveOffersEmpty"].waitForExistence(timeout:6));capture(app,"v54-"+role+"-no-offer")
            app.navigationBars.buttons.element(boundBy:0).tap()
            let reasons=v54Element("selectionReasons-rookie-preparation",app);reveal(reasons,app);XCTAssertTrue(reasons.exists);capture(app,"v54-"+role+"-selection-reasons")
            app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["닫기"].firstMatch.tap()
            v54Contracts(app)
            let entry=v54Element("careerEntryGuide",app);reveal(entry,app);XCTAssertTrue(entry.label.contains("나이 조건"));capture(app,"v54-"+role+"-career-entry")
            close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV54OfferPriorityAndCollegeReservationBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        for college in [false,true] {
            app.terminate();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified"]
            if college {app.launchArguments.append("-college-pro-verification")}
            app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
            for pitcher in [false,true] {
                if pitcher {pickPitcher(app)}
                let before=status(app),role=pitcher ? "pitcher":"batter"
                v54Contracts(app);reveal(app.buttons["openDomesticOffers"],app);app.buttons["openDomesticOffers"].tap()
                if !college {
                    reveal(app.buttons["liveOffersCompare"],app);app.buttons["liveOffersCompare"].tap()
                    XCTAssertTrue(app.staticTexts["liveOfferCompareCaution"].waitForExistence(timeout:8));capture(app,"v54-"+role+"-offer-comparison-priority")
                    app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap()
                } else {
                    reveal(app.buttons["liveOfferDetail-rookie"],app);app.buttons["liveOfferDetail-rookie"].tap()
                    let accept=app.buttons["acceptLiveOffer"];revealLocationChoice(accept,app);capture(app,"v54-"+role+"-college-pro-offer");accept.tap()
                    XCTAssertTrue(app.buttons["confirmOfferDecision"].firstMatch.waitForExistence(timeout:5));app.buttons["취소"].firstMatch.tap();XCTAssertTrue(accept.exists)
                    revealLocationChoice(accept,app);accept.tap();app.buttons["confirmOfferDecision"].firstMatch.tap()
                    let receipt=app.staticTexts["liveOfferDecisionReceipt"];reveal(receipt,app);XCTAssertTrue(receipt.label.contains("예약"));capture(app,"v54-"+role+"-college-accept-receipt")
                    app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap()
                    let timeline=v54Element("contractRegistrationTimeline",app);reveal(timeline,app)
                    XCTAssertTrue(timeline.label.contains("대학"));XCTAssertTrue(timeline.label.contains("2033-04-01"));capture(app,"v54-"+role+"-pending-affiliation")
                    let market=app.buttons["openContractMarket"];reveal(market,app);market.tap()
                    XCTAssertTrue(v54Element("marketPendingTransition",app).waitForExistence(timeout:8));XCTAssertFalse(app.staticTexts["marketEmpty"].exists)
                    capture(app,"v54-"+role+"-pending-market");app.navigationBars.buttons.element(boundBy:0).tap()
                }
                close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
            }
        }
    }
    @MainActor func testV54ReleasedCertificationReopensSavedAttemptBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-renewal-verification","-release-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            v54Contracts(app);let release=app.buttons["confirmClubRelease"];reveal(release,app);capture(app,"v54-"+role+"-release-ready");release.tap();app.buttons["commitClubRelease"].firstMatch.tap()
            let next=v54Element("reentryNextStep",app);reveal(next,app);XCTAssertTrue(next.exists);capture(app,"v54-"+role+"-reentry-next-step")
            let open=app.buttons["openCertification"];reveal(open,app);open.tap();app.buttons["startCertification"].tap()
            let advance=app.buttons["advanceCertification"];reveal(advance,app);advance.tap()
            let progress=app.staticTexts["certificationProgress"].label
            app.navigationBars.buttons.element(boundBy:0).tap();reveal(open,app);open.tap()
            XCTAssertTrue(app.staticTexts["certificationProgress"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["certificationProgress"].label,progress)
            XCTAssertFalse(app.buttons["startCertification"].exists);capture(app,"v54-"+role+"-certification-resume")
            for _ in 1..<(pitcher ? 2:4) {reveal(advance,app);advance.tap()}
            let result=app.staticTexts["certificationResult"];reveal(result,app);XCTAssertTrue(result.exists);capture(app,"v54-"+role+"-certification-complete")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap()
            XCTAssertEqual(status(app)[0],before[0])
        }
    }
    @MainActor func testV54OverseasFAAndMarketReadOnlyBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-renewal-verification","-pro-career-verification","-fa-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:150))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            v54Contracts(app)
            let context=app.staticTexts["overseasEntryContext"];reveal(context,app);XCTAssertTrue(context.exists);capture(app,"v54-"+role+"-overseas-route-context")
            let fa=v54Element("faQualificationGuide",app);reveal(fa,app);XCTAssertTrue(fa.exists);capture(app,"v54-"+role+"-fa-qualification")
            let declare=app.buttons["declareFA"];revealLocationChoice(declare,app);XCTAssertEqual(declare.isEnabled,pitcher)
            if pitcher {declare.tap();XCTAssertTrue(app.buttons["confirmFADeclaration"].firstMatch.waitForExistence(timeout:5));app.buttons["취소"].firstMatch.tap()}
            let market=app.buttons["openContractMarket"];reveal(market,app);market.tap()
            XCTAssertTrue(app.staticTexts["marketComparisonPriority"].waitForExistence(timeout:8));capture(app,"v54-"+role+"-market-priority")
            let summary=app.staticTexts["marketSummary"].label
            app.navigationBars.buttons.element(boundBy:0).tap();reveal(market,app);market.tap();XCTAssertEqual(app.staticTexts["marketSummary"].label,summary)
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV54SmallLargestTextEvaluationAndMarket() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:60));let before=status(app)
        app.buttons["managementLargeMenu"].tap();app.buttons["경기"].tap();revealLocationChoice(app.buttons["facility-calendar"],app);app.buttons["facility-calendar"].tap()
        let open=app.buttons["calendarOpenContractEvaluation"];revealLocationChoice(open,app);capture(app,"v54-large-evaluation-gate");open.tap()
        let acknowledge=app.buttons["acknowledgeContractEvaluation"];revealLocationChoice(acknowledge,app);XCTAssertTrue(acknowledge.isHittable);capture(app,"v54-large-fixed-evaluation");acknowledge.tap()
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["닫기"].firstMatch.tap()
        app.buttons["managementLargeMenu"].tap();app.buttons["커리어"].tap();revealLocationChoice(app.buttons["facility-contracts"],app);app.buttons["facility-contracts"].tap()
        let market=app.buttons["openContractMarket"];revealLocationChoice(market,app);market.tap()
        let priority=app.staticTexts["marketComparisonPriority"];reveal(priority,app);XCTAssertTrue(priority.isHittable);capture(app,"v54-large-market-priority")
        app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementLargeMenu"].tap();app.buttons["홈"].tap();XCTAssertEqual(status(app),before)
    }
}

extension ManagementDetailFlowTests {
    @MainActor private func v55Any(_ id:String,_ app:XCUIApplication)->XCUIElement {app.descendants(matching:.any).matching(identifier:id).firstMatch}
    @MainActor func testV55SelectionRetrySourcesAndCoachBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-club-selection-verification","-club-selection-bench","-v35-coach-verification","-v55-selection-detail-failure"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:100))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-game"].tap();app.buttons["facility-game"].tap()
            let failure=app.staticTexts["clubSelectionError"];reveal(failure,app);XCTAssertTrue(failure.exists);capture(app,"v55-"+role+"-selection-error")
            app.buttons["retryClubSelection"].tap();let open=app.buttons["openClubSelection"];reveal(open,app);open.tap()
            let source=v55Any("selectionEvidenceClock",app);reveal(source,app);XCTAssertTrue(source.label.contains("평가"));capture(app,"v55-"+role+"-selection-sources")
            let next=app.staticTexts["coachNextEvaluation"];reveal(next,app);XCTAssertTrue(next.exists);capture(app,"v55-"+role+"-coach-next-evaluation")
            let rest=app.buttons["coachRest"];reveal(rest,app);rest.tap();XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout:6));app.buttons["취소 · 돌아가기"].tap()
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV55ProjectPriorityAndEvidenceBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-career-objectives-verification","-goal-special-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-career"].tap();app.buttons["facility-goals"].tap();reveal(app.buttons["openCareerObjectives"],app);app.buttons["openCareerObjectives"].tap()
            let start=app.buttons["startCareerProject"];reveal(start,app);start.tap()
            let today=v55Any("projectTodayRecommendation",app);reveal(today,app);XCTAssertTrue(today.label.contains("집중 능력"));capture(app,"v55-"+role+"-project-today")
            app.buttons["projectTodayAction"].tap();XCTAssertTrue(app.buttons["startTraining"].waitForExistence(timeout:8));capture(app,"v55-"+role+"-project-training-preparation")
            app.navigationBars.buttons.element(boundBy:0).tap();reveal(app.buttons["projectAllTasks"],app);app.buttons["projectAllTasks"].tap()
            reveal(app.buttons["projectTrainingAction"],app);XCTAssertTrue(app.buttons["projectTrainingAction"].exists);capture(app,"v55-"+role+"-project-all-tasks")
            app.navigationBars.buttons.element(boundBy:0).tap()
            let special=app.buttons["목표 구단 · 특별 훈련 / 평가전"];reveal(special,app);special.tap()
            let training=v55Any("careerEvidence-training",app);reveal(training,app);XCTAssertTrue(training.exists);capture(app,"v55-"+role+"-special-training-scope")
            let diagnostic=v55Any("careerEvidence-diagnostic",app);reveal(diagnostic,app);XCTAssertTrue(diagnostic.label.contains("공식 표본/XP/인증"));capture(app,"v55-"+role+"-assessment-scope")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV55ReportClocksAndPlanMeasureBothRoles() {
        continueAfterFailure=false
        let app=launch()
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-career"].tap();app.buttons["facility-observation"].tap()
            let clock=v55Any("scoutObservationClock",app);reveal(clock,app);XCTAssertTrue(clock.label.contains("365"));capture(app,"v55-"+role+"-observation-clock")
            reveal(app.buttons["openSavedScoutingReport"],app);app.buttons["openSavedScoutingReport"].tap()
            let cutoff=app.staticTexts["scoutFrozenSampleCutoff"];reveal(cutoff,app);XCTAssertTrue(cutoff.label.contains("완료 개인 경기"));capture(app,"v55-"+role+"-frozen-sample-cutoff")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);openOpponent(app)
            app.buttons["opponentTab-plan"].tap();let measure=v55Any("gamePlanPrimaryMeasure",app);reveal(measure,app);XCTAssertTrue(measure.exists);capture(app,"v55-"+role+"-plan-primary-measure")
            app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV55SeasonFeedbackAndProgressBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-club-season-verification","-v36-opportunity-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:150))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-career"].tap();app.buttons["facility-goals"].tap();reveal(app.buttons["openClubSeasonGoals"],app);app.buttons["openClubSeasonGoals"].tap()
            let summary=v55Any("seasonGoalProgressSummary",app);reveal(summary,app);XCTAssertTrue(summary.label.contains("고정 진척"));capture(app,"v55-"+role+"-season-progress")
            reveal(app.buttons["openClubSeasonReviews"],app);app.buttons["openClubSeasonReviews"].tap()
            let interpretation=v55Any("seasonReviewInterpretation",app);reveal(interpretation,app);XCTAssertTrue(interpretation.exists);capture(app,"v55-"+role+"-season-review")
            app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV55GrowthArchiveAndSaveCountsBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-management-v31-lifecycle"];app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:25))
            if pitcher {pickPitcher(app)}
            let role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-player"].tap();app.buttons["facility-abilities"].tap()
            let current=v55Any("developmentCurrentBasis",app);reveal(current,app);XCTAssertTrue(current.exists);capture(app,"v55-"+role+"-growth-current")
            close(app);app.buttons["managementTab-career"].tap();app.buttons["facility-contracts"].tap()
            let policy=app.staticTexts["lifecycleAgingPolicy"];reveal(policy,app);XCTAssertTrue(policy.label.contains("V2"));capture(app,"v55-"+role+"-aging-policy")
            let retire=app.buttons["openRetirementConfirmation"];reveal(retire,app);retire.tap();XCTAssertTrue(app.buttons["은퇴하고 기록 보존"].firstMatch.waitForExistence(timeout:5));app.buttons["취소"].firstMatch.tap()
            retire.tap();app.buttons["은퇴하고 기록 보존"].firstMatch.tap()
            let archive=v55Any("retirementStorageSummary",app);reveal(archive,app);XCTAssertTrue(archive.label.contains("1명"));capture(app,"v55-"+role+"-retirement-storage")
            app.buttons["archiveSaveProtection"].tap();XCTAssertTrue(app.staticTexts["saveCareerCounts"].waitForExistence(timeout:8));capture(app,"v55-"+role+"-save-counts")
            XCTAssertTrue(app.staticTexts["saveSizePending"].exists);app.buttons["닫기"].tap()
            reveal(app.buttons["archiveNewCareer"],app);app.buttons["archiveNewCareer"].tap();XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout:5))
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV55FrozenForecastIsSeparateFromCurrentGrowthBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-career-path-verification","-career-age20","-selection-qualified","-college-pro-verification","-career-objectives-verification"];app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:120))
        for pitcher in [false,true] {
            if pitcher {pickPitcher(app)}
            let before=status(app),role=pitcher ? "pitcher":"batter"
            app.buttons["managementTab-career"].tap();app.buttons["facility-goals"].tap();reveal(app.buttons["openCareerObjectives"],app);app.buttons["openCareerObjectives"].tap()
            let open=app.buttons["objectivesReport"];reveal(open,app);open.tap()
            let basis=v55Any("growthForecastBasis",app);reveal(basis,app);XCTAssertTrue(basis.label.contains("보고서"));capture(app,"v55-"+role+"-frozen-growth-forecast")
            let original=basis.label;app.navigationBars.buttons.element(boundBy:0).tap();reveal(open,app);open.tap();reveal(basis,app);XCTAssertEqual(basis.label,original)
            app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap();close(app);app.buttons["managementTab-home"].tap();XCTAssertEqual(status(app),before)
        }
    }
    @MainActor func testV55SmallLargestTextClocksAndSaveControls() {
        continueAfterFailure=false
        let app=launch(large:true),before=status(app)
        app.buttons["managementLargeMenu"].tap();app.buttons["커리어"].tap();revealLocationChoice(app.buttons["facility-observation"],app);app.buttons["facility-observation"].tap()
        let clock=v55Any("scoutObservationClock",app);revealLocationChoice(clock,app);XCTAssertTrue(clock.isHittable);capture(app,"v55-large-observation-clock")
        close(app);app.buttons["managementLargeMenu"].tap();app.buttons["홈"].tap()
        revealLocationChoice(app.buttons["clubhouse-settings"],app);app.buttons["clubhouse-settings"].tap()
        let counts=app.staticTexts["saveCareerCounts"];revealLocationChoice(counts,app);XCTAssertTrue(counts.isHittable);capture(app,"v55-large-save-counts")
        let export=app.buttons["exportSave"];revealLocationChoice(export,app);XCTAssertTrue(export.isHittable);capture(app,"v55-large-backup-controls")
        app.buttons["닫기"].tap();XCTAssertEqual(status(app),before)
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV60PropRoomsBothRolesKeepDateFatigueAndRoutes() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            capture(app, "v60-" + role + "-home")
            app.buttons["managementTab-player"].tap()
            let graph = app.buttons["facility-abilities"]; v60Reveal(graph, app)
            XCTAssertTrue(graph.label.contains(pitcher ? "구위" : "컨택")); XCTAssertTrue(graph.label.contains("멘탈"))
            capture(app, "v60-" + role + "-chalk")
            graph.tap(); XCTAssertTrue(app.otherElements["homeAbilityRadar"].waitForExistence(timeout: 8)); close(app)
            let book = app.buttons["facility-positions"]; v60Reveal(book, app)
            XCTAssertTrue(book.label.contains(pitcher ? "구종 수첩" : "포지션 수첩")); capture(app, "v60-" + role + "-notebooks")
            app.buttons["managementTab-career"].tap()
            let report = app.buttons["facility-observation"]; v60Reveal(report, app); capture(app, "v60-" + role + "-observation")
            let contracts = app.buttons["facility-contracts"]; v60Reveal(contracts, app); capture(app, "v60-" + role + "-desk")
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
    @MainActor func testV60LargestTextKeepsAbilityValuesAndSettingsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        let before = status(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["선수"].tap()
        let graph = app.buttons["facility-abilities"]; revealLocationChoice(graph, app)
        XCTAssertTrue(graph.label.contains("컨택")); capture(app, "v60-large-ability-list")
        graph.tap(); XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8)); close(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap(); XCTAssertEqual(status(app), before)
        revealLocationChoice(app.buttons["clubhouse-settings"], app); XCTAssertTrue(app.buttons["clubhouse-settings"].isHittable)
    }
    @MainActor private func v60Reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            let scroll = app.scrollViews["roomPropScroll"].exists ? app.scrollViews["roomPropScroll"] : app.scrollViews["gameLobbyScroll"]
            guard scroll.exists else { return }
            if element.isHittable && element.frame.minY >= scroll.frame.minY + 44 && element.frame.maxY <= scroll.frame.maxY { return }
            if element.exists && element.frame.minY < scroll.frame.minY + 44 { scroll.swipeDown() } else { scroll.swipeUp() }
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV60SavedProjectSummaryUsesActualSampleUnits() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-college-pro-verification", "-v31-match-completed"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 120))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app)
            app.buttons["managementTab-career"].tap()
            let goal = app.buttons["facility-goals"]; v60Reveal(goal, app)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "훈련"), object: goal)], timeout: 10), .completed)
            XCTAssertTrue(goal.label.contains(pitcher ? "아웃" : "타석"))
            capture(app, pitcher ? "v60-pitcher-active-project" : "v60-batter-active-project")
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV61TrainingRoomsPreparationAndRestBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-training"].tap()
            capture(app, "v61-" + role + "-training-room")
            let facility = app.buttons["facility-training"]; v60Reveal(facility, app); facility.tap()
            XCTAssertTrue(app.buttons["openTraining"].waitForExistence(timeout: 8))
            capture(app, "v61-" + role + "-training-choice")
            close(app); app.buttons["managementTab-home"].tap()
            let rest = app.buttons["clubhouse-rest"]; v60Reveal(rest, app); rest.tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8))
            capture(app, "v61-" + role + "-rest-confirmation")
            app.buttons["취소 · 돌아가기"].tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
            XCTAssertEqual(status(app), before)
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV62GameHubFilesRemainReadOnlyBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-game"].tap(); capture(app, "v62-" + role + "-stadium")
            for (facility, section) in [("facility-calendar", "schedule"), ("facility-analysis", "analysis"), ("facility-gameRecords", "records"), ("facility-standings", "standings")] {
                let button = app.buttons[facility]; v60Reveal(button, app); button.tap()
                if facility == "facility-calendar" {
                    XCTAssertTrue(app.scrollViews["calendarDetailScroll"].waitForExistence(timeout: 8))
                    capture(app, "v62-" + role + "-" + section)
                    app.buttons["닫기"].tap()
                } else {
                    XCTAssertTrue(app.buttons["gameSection-" + section].waitForExistence(timeout: 8))
                    capture(app, "v62-" + role + "-" + section); close(app)
                }
            }
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV63PlayerFilesAndWeaknessTrainingAreReadOnlyBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-player"].tap()
            let graph = app.buttons["facility-abilities"]; v60Reveal(graph, app); graph.tap()
            XCTAssertTrue(app.otherElements["homeAbilityRadar"].waitForExistence(timeout: 8))
            capture(app, "v63-" + role + "-abilities")
            let train = app.buttons["abilityTrainWeakest"]; reveal(train, app)
            let expected = train.label.replacingOccurrences(of: " 훈련 고르기", with: "")
            train.tap(); XCTAssertTrue(app.buttons["openTraining"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["openTraining"].label.contains(expected)); capture(app, "v63-" + role + "-weakness-training")
            close(app)
            let traits = app.buttons["facility-traits"]; v60Reveal(traits, app); traits.tap()
            XCTAssertTrue(app.buttons["traitDetails"].waitForExistence(timeout: 8)); capture(app, "v63-" + role + "-traits"); close(app)
            let book = app.buttons["facility-positions"]; v60Reveal(book, app); book.tap()
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8)); capture(app, "v63-" + role + "-mastery"); close(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV64FrozenReviewChangesAndContractFilesBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-career-path-verification", "-career-age20", "-selection-qualified", "-college-pro-verification", "-career-objectives-verification", "-observation-review-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 120))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            app.buttons["managementTab-career"].tap()
            let observation = app.buttons["facility-observation"]; v60Reveal(observation, app); observation.tap()
            reveal(app.buttons["openObservationReview"], app); app.buttons["openObservationReview"].tap()
            XCTAssertTrue(app.staticTexts["reviewCurrentDate"].waitForExistence(timeout: 15))
            let date = app.staticTexts["reviewCurrentDate"].label
            let change = app.staticTexts["reviewAbility-homeSpeed"]; reveal(change, app)
            XCTAssertTrue(change.label.contains("+1.0")); capture(app, "v64-" + role + "-fixed-change")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            let contracts = app.buttons["facility-contracts"]; v60Reveal(contracts, app); contracts.tap()
            reveal(app.buttons["openContractMarket"], app); app.buttons["openContractMarket"].tap()
            XCTAssertTrue(app.staticTexts["marketSummary"].waitForExistence(timeout: 15)); capture(app, "v64-" + role + "-market")
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            v60Reveal(observation, app); observation.tap(); reveal(app.buttons["openObservationReview"], app); app.buttons["openObservationReview"].tap()
            XCTAssertTrue(app.staticTexts["reviewCurrentDate"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["reviewCurrentDate"].label, date)
            app.navigationBars.buttons.element(boundBy: 0).tap(); close(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV66LargestTextRoomRoutesCloseAndSettingsStayReadable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        let before = status(app)
        for (tab, facility) in [("선수", "facility-abilities"), ("훈련", "facility-training"), ("경기", "facility-analysis"), ("커리어", "facility-contracts")] {
            app.buttons["managementLargeMenu"].tap(); app.buttons[tab].tap()
            let target = app.buttons[facility]; revealLocationChoice(target, app); target.tap()
            let close = app.buttons["closeRoomDetail"]; XCTAssertTrue(close.waitForExistence(timeout: 8))
            XCTAssertGreaterThanOrEqual(close.frame.height, 44); capture(app, "v66-large-" + facility); close.tap()
        }
        app.buttons["managementLargeMenu"].tap(); app.buttons["홈"].tap()
        let settings = app.buttons["clubhouse-settings"]; revealLocationChoice(settings, app); settings.tap()
        let export = app.buttons["exportSave"]; revealLocationChoice(export, app); XCTAssertTrue(export.isHittable)
        capture(app, "v66-large-save"); app.buttons["closeSettings"].tap(); XCTAssertEqual(status(app), before)
    }
    @MainActor func testV66CreationDraftReviewAndSchoolCancelBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-management-empty-verification"]; app.launch()
        let name = app.textFields["playerName"]; XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap(); name.typeText("V66Draft"); app.buttons["입력 완료"].tap()
        for pitcher in [false, true] {
            let role = pitcher ? "pitcher" : "batter"
            app.buttons["creationSection-information"].tap()
            reveal(app.buttons["role-" + role], app); app.buttons["role-" + role].tap()
            reveal(app.buttons["randomSchool"], app); app.buttons["randomSchool"].tap()
            reveal(app.buttons["schoolPicker"], app); app.buttons["schoolPicker"].tap()
            let close = app.buttons["closeSchoolPicker"]; XCTAssertTrue(close.waitForExistence(timeout: 8))
            XCTAssertGreaterThanOrEqual(close.frame.height, 44); close.tap()
            app.buttons["creationSection-review"].tap()
            let readiness = app.staticTexts["creationReadiness"]; reveal(readiness, app)
            XCTAssertTrue(readiness.label.contains("확인 완료")); capture(app, "v66-" + role + "-registration-review")
            XCTAssertFalse(app.staticTexts["homePlayerName"].exists)
            app.buttons["creationSection-information"].tap(); reveal(name, app); XCTAssertEqual(name.value as? String, "V66Draft")
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV67RestCompletionOnceAndGamePreparationBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app), role = pitcher ? "pitcher" : "batter"
            let rest = app.buttons["clubhouse-rest"]; v60Reveal(rest, app); rest.tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8)); capture(app, "v67-" + role + "-rest-ready")
            app.buttons["confirmRest"].tap()
            XCTAssertTrue(app.staticTexts["restSaved"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["restFatigueForecast"].label.contains(pitcher ? "52 → 34" : "24 → 6")); capture(app, "v67-" + role + "-rest-complete")
            app.buttons["restGoGame"].tap()
            XCTAssertTrue(app.buttons["roomProfile"].waitForExistence(timeout: 8)); XCTAssertTrue(app.scrollViews["gameLobbyScroll"].exists)
            let after = status(app); XCTAssertEqual(after[0], before[0]); XCTAssertEqual(after[2], "행동 0/1")
            capture(app, "v67-" + role + "-game-preparation")
            app.buttons["managementTab-home"].tap(); v60Reveal(rest, app); rest.tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["confirmRest"].isEnabled)
            app.buttons["취소 · 돌아가기"].tap(); XCTAssertEqual(status(app), after)
        }
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV67LargestTextRestAndGameControlsStayReachable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30)); let before = status(app)
        let rest = app.buttons["clubhouse-rest"]; revealLocationChoice(rest, app); rest.tap()
        let confirm = app.buttons["confirmRest"]; XCTAssertTrue(confirm.waitForExistence(timeout: 8)); XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        let receipt=app.staticTexts["restPinnedFatigue"];XCTAssertTrue(receipt.isHittable);XCTAssertTrue(receipt.label.contains("24 → 6"))
        capture(app, "v70-large-rest")
        confirm.tap(); XCTAssertTrue(app.staticTexts["restSaved"].waitForExistence(timeout: 10)); app.buttons["restGoGame"].tap()
        XCTAssertTrue(app.buttons["roomPrimary"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["roomPrimary"].isHittable)
        XCTAssertEqual(status(app)[0], before[0]); capture(app, "v67-large-game")
        let analysis = app.buttons["facility-analysis"]; revealLocationChoice(analysis, app); analysis.tap()
        XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8)); close(app)
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV68GamePreparationRoutesAndReturnKeepStateBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            let before = status(app)
            app.buttons["managementTab-game"].tap()
            XCTAssertEqual(app.buttons["roomPrimary"].label, "오늘 경기 준비")
            capture(app, pitcher ? "v68-pitcher-game" : "v68-batter-game")
            app.buttons["roomPrimary"].tap()
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8)); close(app)
            XCTAssertTrue(app.buttons["roomPrimary"].waitForExistence(timeout: 8))
            let analysis = app.buttons["facility-analysis"]; v60Reveal(analysis, app); analysis.tap()
            XCTAssertTrue(app.buttons["gameSection-analysis"].waitForExistence(timeout: 8)); close(app)
            let records = app.buttons["facility-gameRecords"]; v60Reveal(records, app); records.tap()
            XCTAssertTrue(app.buttons["gameSection-records"].waitForExistence(timeout: 8)); close(app)
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), before)
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV71DetailSectionsAndSpatialRoutesBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        for pitcher in [false, true] {
            if pitcher { pickPitcher(app) }
            app.buttons["managementTab-player"].tap()
            capture(app, "v71-" + (pitcher ? "pitcher" : "batter") + "-locker")
            let abilities = app.buttons["facility-abilities"]; v60Reveal(abilities, app); abilities.tap()
            let traits = app.buttons["playerSection-traits"]; reveal(traits, app); traits.tap()
            XCTAssertTrue(app.buttons["traitDetails"].waitForExistence(timeout: 8), "Section must change inside the existing sheet")
            capture(app, "v71-section-traits")
            let records = app.buttons["playerSection-records"]; reveal(records, app); records.tap()
            XCTAssertTrue(app.buttons["playerOpenSeason"].waitForExistence(timeout: 8))
            capture(app, "v71-section-records"); close(app)
            let traitProp = app.buttons["facility-traits"]; v60Reveal(traitProp, app); traitProp.tap()
            XCTAssertTrue(app.buttons["traitDetails"].waitForExistence(timeout: 8)); close(app)
            let recordProp = app.buttons["facility-records"]; v60Reveal(recordProp, app); recordProp.tap()
            XCTAssertTrue(app.buttons["playerOpenSeason"].waitForExistence(timeout: 8)); close(app)
            app.buttons["managementTab-home"].tap()
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV71CompletedGameAdvancesFromLobbyBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-management-reduced-motion-verification"]; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            if pitcher { pickPitcher(app) }
            let role = pitcher ? "pitcher" : "batter", before = status(app)
            app.buttons["managementTab-game"].tap()
            capture(app, "v71-" + role + "-game-board")
            let nextDay = app.buttons["advanceDay"]; v60Reveal(nextDay, app)
            XCTAssertFalse(nextDay.isEnabled, "A pending game must still block the day")
            let train = app.buttons["lobbyGoTraining"]; v60Reveal(train, app); train.tap()
            XCTAssertTrue(app.buttons["facility-training"].waitForExistence(timeout: 5))
            app.buttons["managementTab-game"].tap()
            let rest = app.buttons["restToday"]; v60Reveal(rest, app); rest.tap()
            XCTAssertTrue(app.buttons["confirmRest"].waitForExistence(timeout: 6)); app.buttons["confirmRest"].tap()
            XCTAssertTrue(app.buttons["restDone"].waitForExistence(timeout: 10)); app.buttons["restDone"].tap()
            app.buttons["roomPrimary"].tap()
            XCTAssertTrue(app.buttons["openCareerGame"].waitForExistence(timeout: 8))
            reveal(app.buttons["openCareerGame"], app); app.buttons["openCareerGame"].tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 8)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let automatic = app.buttons["gameAutomatic"]
            XCTAssertTrue(automatic.waitForExistence(timeout: 12)); automatic.tap(); app.buttons["진행하고 결과 저장"].tap()
            XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout: 30))
            // Return to the spatial root without using result-screen date controls.
            let leave = app.buttons["gameReturnHome"]; reveal(leave, app); leave.tap()
            XCTAssertTrue(app.buttons["closeRoomDetail"].waitForExistence(timeout: 8))
            close(app); app.buttons["managementTab-home"].tap()
            XCTAssertTrue(app.buttons["homeCalendar"].waitForExistence(timeout: 8)); app.buttons["homeCalendar"].tap()
            XCTAssertTrue(app.buttons["managementTab-game"].isSelected)
            v60Reveal(nextDay, app); XCTAssertTrue(nextDay.isEnabled)
            capture(app, "v71-" + role + "-after-game-next-day")
            nextDay.tap()
            let dateChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before[0]), object: app.staticTexts["calendarDate"])
            XCTAssertEqual(XCTWaiter.wait(for: [dateChanged], timeout: 10), .completed)
            XCTAssertEqual(app.staticTexts["calendarAction"].label, "행동 1/1")
            capture(app, "v71-" + role + "-next-day")
            let annual = app.buttons["showSeasonSchedule"]; v60Reveal(annual, app); annual.tap()
            XCTAssertTrue(app.navigationBars["연간 일정"].waitForExistence(timeout: 8))
            let fixture = app.descendants(matching: .any).matching(identifier: "calendarFixture-1").firstMatch
            revealLocationChoice(fixture, app); XCTAssertTrue(fixture.exists)
        }
    }

    @MainActor func testV71LargestTextLibraryAndScheduleRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30)); pickPitcher(app)
        app.buttons["managementLargeMenu"].tap(); app.buttons["선수"].tap()
        let library = app.buttons["facility-positions"]; revealLocationChoice(library, app); library.tap()
        let slot = app.buttons["pitchStudySlot-empty"]; revealLocationChoice(slot, app)
        XCTAssertTrue(slot.isHittable); XCTAssertGreaterThanOrEqual(slot.frame.height, 44)
        XCTAssertTrue(app.frame.contains(slot.frame)); capture(app, "v71-large-pitch-slot")
        close(app); app.buttons["managementLargeMenu"].tap(); app.buttons["경기"].tap()
        let nextDay = app.buttons["advanceDay"]; v60Reveal(nextDay, app)
        XCTAssertTrue(nextDay.isHittable); XCTAssertGreaterThanOrEqual(nextDay.frame.height, 44)
        capture(app, "v71-large-next-action")
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV72TrainingAndGameCompletionRoutesPreserveSavedStateBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        func ready(_ button: XCUIElement, timeout: Double = 35) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: button)], timeout: timeout), .completed)
        }
        for pitcher in [false, true] {
            app.terminate(); app.launchArguments = ["-management-career-verification", "-v56-disk-session", UUID().uuidString]; app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30)); if pitcher { pickPitcher(app) }
            let role = pitcher ? "pitcher" : "batter", before = status(app)
            app.buttons["managementTab-training"].tap(); app.buttons["facility-physical"].tap()
            let kind = app.buttons["trainingKind-" + (pitcher ? "control" : "defense")]; reveal(kind, app); kind.tap()
            let open = app.buttons["openTraining"]; reveal(open, app); open.tap()
            let start = app.buttons["startTraining"]; reveal(start, app); start.tap()
            for _ in 0..<5 {
                let attempt = app.buttons["trainingAttempt"]; reveal(attempt, app); ready(attempt); attempt.tap()
                let next = app.buttons["trainingNext"]; XCTAssertTrue(next.waitForExistence(timeout: 12)); reveal(next, app); next.tap()
            }
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout: 8))
            let growth = app.staticTexts["trainingGrowth"].label
            let player = app.buttons["completionGoPlayer"]; reveal(player, app); capture(app, "v72-" + role + "-training-next-actions"); player.tap()
            XCTAssertTrue(app.buttons["managementTab-player"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["managementTab-player"].isSelected)
            let completedTraining = status(app); XCTAssertEqual(completedTraining[0], before[0]); XCTAssertEqual(completedTraining[2], "행동 0/1")
            app.buttons["managementTab-training"].tap(); app.buttons["roomPrimary"].tap()
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout: 8)); XCTAssertEqual(app.staticTexts["trainingGrowth"].label, growth)
            let game = app.buttons["completionGoGame"]; reveal(game, app); game.tap()
            XCTAssertTrue(app.buttons["managementTab-game"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["managementTab-game"].isSelected)
            XCTAssertEqual(status(app), completedTraining)
            app.buttons["roomPrimary"].tap(); let entry = app.buttons["openCareerGame"]; reveal(entry, app); entry.tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout: 10)); app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"], app); app.buttons["confirmGamePlan"].tap()
            let automatic = app.buttons["gameAutomatic"]; XCTAssertTrue(automatic.waitForExistence(timeout: 12))
            for index in 0..<6 {
                ready(automatic)
                if pitcher {
                    app.buttons["gamePitch"].tap(); XCTAssertTrue(app.buttons["gameRelease"].waitForExistence(timeout: 5)); app.buttons["gameRelease"].tap()
                } else {
                    let action = ["watch", "swing", "bunt"][index % 3]
                    app.buttons["gameInput-" + action].tap(); app.buttons["battingTouchSurface"].tap()
                    if action != "watch" { app.buttons["battingTouchSurface"].tap() }
                }
                ready(automatic)
                XCTAssertFalse(app.staticTexts["gameResultSaved"].exists)
                if index == 2 { capture(app, "v72-" + role + "-manual-progress") }
            }
            let count = app.descendants(matching: .any).matching(identifier: "careerGameCount").firstMatch.label
            app.terminate(); app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30)); if pitcher { pickPitcher(app) }
            app.buttons["homeTodayGame"].tap(); XCTAssertTrue(automatic.waitForExistence(timeout: 12))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "careerGameCount").firstMatch.label, count)
            automatic.tap(); app.buttons["진행하고 결과 저장"].tap(); XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout: 30))
            let next = app.buttons["completionGoGame"]; reveal(next, app); capture(app, "v72-" + role + "-game-next-actions"); next.tap()
            XCTAssertTrue(app.buttons["managementTab-game"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["managementTab-game"].isSelected)
            let completedGame = status(app); XCTAssertEqual(completedGame[0], before[0]); XCTAssertEqual(completedGame[2], "행동 0/1")
            app.buttons["roomPrimary"].tap(); XCTAssertTrue(app.buttons["advanceDay"].waitForExistence(timeout: 8))
            XCTAssertEqual(status(app)[0], before[0]); app.buttons["closeCalendar"].tap()
            app.buttons["managementTab-home"].tap(); XCTAssertEqual(status(app), completedGame)
        }
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV72AcquisitionBoundaryTraitActivationAndPitchReplacementRestore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-v56-disk-session", UUID().uuidString, "-v72-acquisition-boundary", "-management-reduced-motion-verification"]
        app.launch(); XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        app.buttons["managementTab-player"].tap(); app.buttons["facility-traits"].tap(); app.buttons["traitDetails"].tap()
        let trait = app.buttons["traitTraining-strong-arm"]; reveal(trait, app); trait.tap()
        reveal(app.buttons["startTraitTraining"], app); app.buttons["startTraitTraining"].tap()
        for index in 0..<5 {
            let attempt = app.buttons["traitDrillSubmit"]; reveal(attempt, app); attempt.tap()
            XCTAssertTrue(app.staticTexts["traitDrillFeedback"].waitForExistence(timeout: 10))
            if index < 4 { let next = app.buttons["traitDrillNext"]; reveal(next, app); next.tap() }
        }
        XCTAssertTrue(app.staticTexts["traitAcquired"].label.contains("특성 습득")); capture(app, "v72-trait-100-boundary")
        let player = app.buttons["completionGoPlayer"]; reveal(player, app); player.tap()
        XCTAssertTrue(app.buttons["managementTab-player"].waitForExistence(timeout: 8)); app.buttons["facility-traits"].tap(); app.buttons["traitDetails"].tap()
        let toggle = app.buttons["traitToggle-strong-arm"]; reveal(toggle, app); XCTAssertFalse(toggle.isEnabled)
        app.navigationBars.buttons["BackButton"].tap(); close(app); app.buttons["managementTab-game"].tap()
        let day = app.buttons["advanceDay"]; v60Reveal(day, app); XCTAssertTrue(day.isEnabled); day.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "행동 1/1"), object: app.staticTexts["calendarAction"])], timeout: 10), .completed)
        app.buttons["managementTab-player"].tap(); app.buttons["facility-traits"].tap(); app.buttons["traitDetails"].tap(); reveal(toggle, app); XCTAssertTrue(toggle.isEnabled); toggle.tap()
        XCTAssertEqual(app.staticTexts["traitActiveCount"].label, "활성 3 / 3"); capture(app, "v72-trait-three-active"); app.navigationBars.buttons["BackButton"].tap(); close(app)
        pickPitcher(app)
        func library() { app.buttons["managementTab-player"].tap(); let b = app.buttons["facility-positions"]; v60Reveal(b, app); b.tap(); XCTAssertTrue(app.staticTexts["pitchLibraryCount"].waitForExistence(timeout: 8)) }
        func study(_ code: String, replacing: String) {
            let slot = app.buttons["pitchStudySlot-" + replacing]; reveal(slot, app); slot.tap()
            let begin = app.buttons["pitchStudyStart-" + code]; reveal(begin, app); begin.tap()
            let confirm = app.buttons.matching(identifier: "pitchStudyConfirm").firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            let start = app.buttons["startTraining"]; reveal(start, app); start.tap()
            for _ in 0..<5 {
                let attempt = app.buttons["trainingAttempt"]; reveal(attempt, app); attempt.tap(); attempt.tap()
                let next = app.buttons["trainingNext"]; XCTAssertTrue(next.waitForExistence(timeout: 12)); reveal(next, app); next.tap()
            }
            XCTAssertTrue(app.staticTexts["pitchStudyResult"].waitForExistence(timeout: 8)); XCTAssertTrue(app.staticTexts["pitchStudyResult"].label.contains("100.0"))
            capture(app, "v72-pitch-" + code + "-registered")
            let route = app.buttons["completionGoPlayer"]; reveal(route, app); route.tap()
            XCTAssertTrue(app.buttons["managementTab-player"].waitForExistence(timeout: 8))
        }
        library(); XCTAssertFalse(app.buttons["pitchStudySlot-empty"].exists)
        study("cutter", replacing: "four-seam")
        library()
        let cutter = app.descendants(matching: .any).matching(identifier: "pitchLibraryOwned-cutter").firstMatch
        XCTAssertTrue(cutter.waitForExistence(timeout: 8)); XCTAssertTrue(cutter.label.contains("20.0"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pitchLibraryOwned-four-seam").firstMatch.exists)
        close(app); app.buttons["managementTab-game"].tap(); v60Reveal(day, app); day.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "행동 1/1"), object: app.staticTexts["calendarAction"])], timeout: 10), .completed)
        library(); study("four-seam", replacing: "cutter"); library()
        let restored = app.descendants(matching: .any).matching(identifier: "pitchLibraryOwned-four-seam").firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 8)); XCTAssertTrue(restored.label.contains("62.0"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pitchLibraryOwned-cutter").firstMatch.exists)
        capture(app, "v72-pitch-original-mastery-restored")
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV72CoreAccessibilityAndLocalExporterProbe() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-save-protection-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.buttons["managementTab-game"].tap()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.buttons["managementTab-home"].tap()
        let settings = app.buttons["clubhouse-settings"]; revealLocationChoice(settings, app); settings.tap()
        let export = app.buttons["exportSave"]; reveal(export, app); export.tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 12))
        capture(app, "v72-local-exporter-probe")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "V72 local exporter hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "취소"])).firstMatch
        if !cancel.exists { app.navigationBars.buttons["BackButton"].tap() }
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["importSave"].waitForExistence(timeout: 8))
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV72LocalFilesBackupRoundTripUsesIsolatedCareerOnly() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-management-career-verification", "-save-protection-verification"]; app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30)); let before = status(app)
        let settings = app.buttons["clubhouse-settings"]; revealLocationChoice(settings, app); settings.tap()
        let export = app.buttons["exportSave"]; reveal(export, app); export.tap()
        let save = app.buttons["DOCPicker.actionButton"]; XCTAssertTrue(save.waitForExistence(timeout: 12))
        let local = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage")).firstMatch
        if !local.exists {
            let back = app.navigationBars.buttons["BackButton"]; XCTAssertTrue(back.exists); back.tap()
            let onDevice = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "나의 iPhone"])).firstMatch
            XCTAssertTrue(onDevice.waitForExistence(timeout: 5)); onDevice.tap()
        }
        let name = app.textFields["DOCPicker.filenameTextField"]; XCTAssertTrue(name.exists)
        let unique = "BM-QA-V72-" + String(UUID().uuidString.prefix(8))
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50)); name.typeText(unique)
        let actual = name.value as? String ?? unique
        save.tap()
        let exported = app.staticTexts["saveProtectionMessage"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "백업 내보내기 완료"), object: exported)], timeout: 15), .completed)
        capture(app, "v72-local-files-exported")
        let importing = app.buttons["importSave"]; reveal(importing, app); importing.tap()
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["둘러보기"]
        XCTAssertTrue(browse.waitForExistence(timeout: 8)); browse.tap()
        let localFolder = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["나의 iPhone", "On My iPhone"])).firstMatch
        XCTAssertTrue(localFolder.waitForExistence(timeout: 8)); localFolder.tap()
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", actual)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        for _ in 0..<5 where file.frame.maxY > app.tabBars["DOC.browsingModeTabBar"].frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(file.isHittable); file.tap()
        let restore = app.buttons["confirmRestoreSave"]; XCTAssertTrue(restore.waitForExistence(timeout: 15)); reveal(restore, app)
        capture(app, "v72-local-files-verified")
        restore.tap(); XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 5)); app.buttons["취소"].tap(); XCTAssertTrue(restore.exists)
        restore.tap(); app.buttons["전체 복원"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); XCTAssertEqual(status(app), before)
        capture(app, "v72-local-files-restored")
    }
}
