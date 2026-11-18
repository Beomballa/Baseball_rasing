import XCTest

/// Production screens with in-memory QA players; no installed player store is opened.
final class ManagementDetailFlowTests: XCTestCase {
    @MainActor func testV110RecordedSoundSettingsAreReadOnlyAndRespectMasterMute() {
        continueAfterFailure = false
        let app = XCUIApplication()
        func tapSwitch(_ toggle: XCUIElement) {
            reveal(toggle, app)
            // A partly scrolled label can be hittable underneath the navigation bar.
            for _ in 0..<4 where toggle.frame.minY < 150 { app.swipeDown() }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        for large in [false, true] {
            app.terminate()
            app.launchArguments = ["-management-career-verification"]
            if large {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-management-reduced-motion-verification"]
            }
            app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            let before = status(app)
            app.buttons["clubhouse-settings"].tap()
            let master = app.switches["settingSound"], voice = app.switches["settingUmpireVoice"]
            XCTAssertTrue(master.waitForExistence(timeout: 8))
            let masterWasOn = master.value as? String == "1"
            if !masterWasOn { tapSwitch(master) }
            reveal(voice, app)
            let voiceWasOn = voice.value as? String == "1"
            if !voiceWasOn { tapSwitch(voice) }
            let volume=app.sliders["settingSoundVolume"]
            reveal(volume,app);XCTAssertTrue(volume.isEnabled)
            for id in ["previewSound", "previewCatchSound", "previewCrowdSound", "previewUmpire-strike", "previewUmpire-ball", "previewUmpire-strikeout", "previewUmpire-walk", "previewUmpire-out"] {
                let button = app.buttons[id]
                reveal(button, app)
                XCTAssertTrue(button.isHittable, id)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertTrue(button.isEnabled)
                button.tap()
            }
            capture(app, large ? "v110-audio-large-type" : "v110-audio-standard")
            tapSwitch(voice)
            reveal(app.buttons["previewUmpire-strike"], app)
            XCTAssertFalse(app.buttons["previewUmpire-strike"].isEnabled)
            XCTAssertTrue(app.buttons["previewSound"].isEnabled)
            if voiceWasOn { tapSwitch(voice) }
            tapSwitch(master)
            XCTAssertEqual(master.value as? String, "0")
            XCTAssertFalse(voice.isEnabled)
            XCTAssertFalse(app.buttons["previewSound"].isEnabled)
            XCTAssertFalse(app.buttons["previewCatchSound"].isEnabled)
            reveal(app.buttons["previewUmpire-ball"], app)
            XCTAssertFalse(app.buttons["previewUmpire-ball"].isEnabled)
            if masterWasOn { tapSwitch(master) }
            app.buttons["closeSettings"].tap()
            XCTAssertEqual(status(app), before)
        }
        app.terminate()
    }
    @MainActor func testV153FixedFieldScenesStepThroughSupportWithoutStore() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-field-replay-verification"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.staticTexts["fieldVerificationNotice"].waitForExistence(timeout:10))
        for scenario in ["1루 뜬공","3루 뜬공","외야 사이 타구","포구·낙구 경계"] {
            let menu=app.buttons["fieldVerificationScenario"];reveal(menu,app);menu.tap()
            XCTAssertTrue(app.buttons[scenario].waitForExistence(timeout:5));app.buttons[scenario].tap()
            XCTAssertFalse(app.staticTexts["fieldVerificationError"].exists)
            let next=app.buttons["fieldVerificationNext"],time=app.staticTexts["fieldVerificationTime"]
            XCTAssertTrue(next.waitForExistence(timeout:5));let initial=time.label
            for _ in 0..<6 {reveal(next,app);next.tap()}
            XCTAssertNotEqual(time.label,initial)
            XCTAssertFalse(app.staticTexts["fieldVerificationError"].exists)
            let canvas=app.descendants(matching:.any).matching(identifier:"fieldReplayCanvas").firstMatch
            reveal(canvas,app);XCTAssertTrue(canvas.isHittable)
        }
    }

    @MainActor func testV152LargestMatchControlJumpBothRoles() {
        continueAfterFailure=false
        for pitcher in [false,true] {
            let app=XCUIApplication()
            app.launchArguments=["-management-career-verification","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-management-reduced-motion-verification"]
            app.launch();defer {app.terminate()}
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30))
            if pitcher {v151SelectRole(app,pitcher:true)}
            reveal(app.buttons["clubhouse-rest"],app);app.buttons["clubhouse-rest"].tap()
            reveal(app.buttons["confirmRest"],app);app.buttons["confirmRest"].tap()
            let done=app.buttons["restDone"];XCTAssertTrue(done.waitForExistence(timeout:15));reveal(done,app);done.tap()
            app.buttons["managementLargeMenu"].tap();app.buttons["managementMenu-game"].tap()
            app.buttons["roomPrimary"].tap()
            let entry=app.buttons["openCareerGame"];reveal(entry,app);entry.tap()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout:8));app.buttons["opponentTab-plan"].tap()
            let plan=app.buttons["confirmGamePlan"];reveal(plan,app);plan.tap()
            let jump=app.buttons["gameJumpToControls"]
            XCTAssertTrue(jump.waitForExistence(timeout:10));XCTAssertTrue(jump.isHittable)
            XCTAssertGreaterThanOrEqual(jump.frame.height,44)
            let summary=app.descendants(matching:.any).matching(identifier:"gameControlSummary").firstMatch
            let before=summary.label
            jump.tap()
            XCTAssertTrue(summary.isHittable);XCTAssertEqual(summary.label,before)
            let action=app.buttons[pitcher ? "gamePitch":"accessibleBattingInput"]
            revealLocationChoice(action,app);XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height,44)
            XCTAssertEqual(summary.label,before,"점프·스크롤로 경기 카운트가 바뀌면 안 됩니다.")
            XCTAssertTrue(app.buttons["gameAutomatic"].isEnabled)
        }
    }

    @MainActor func testV169RestUsedShowsReasonAtDisabledAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-management-reduced-motion-verification"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        let rest = app.buttons["clubhouse-rest"]
        reveal(rest, app); rest.tap()
        let confirm = app.buttons["confirmRest"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
        let done = app.buttons["restDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 8))
        let saved = status(app)
        reveal(rest, app); rest.tap()
        let reason = app.staticTexts["restActionGate"]
        XCTAssertTrue(reason.waitForExistence(timeout: 8)); XCTAssertTrue(reason.isHittable)
        XCTAssertTrue(reason.label.contains("이미 사용"))
        XCTAssertFalse(confirm.isEnabled)
        app.buttons["취소 · 돌아가기"].tap()
        XCTAssertEqual(status(app), saved)
    }

    @MainActor func testV56TrainingTerminationResumeAndStoredRewardBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        defer { app.terminate() }
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-v56-disk-session",UUID().uuidString];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            let kind=pitcher ? "control":"defense"
            func openTraining(resuming: Bool = false) {
                app.buttons["managementTab-training"].tap()
                if resuming { app.buttons["roomPrimary"].tap(); return }
                app.buttons["facility-physical"].tap()
                if !app.buttons["trainingKind-"+kind].exists {
                    let choices = app.descendants(matching: .any).matching(identifier: "trainingEquipmentChoices").firstMatch
                    reveal(choices, app)
                    let toggle = choices.elementType == .button ? choices : choices.buttons.firstMatch
                    XCTAssertTrue(toggle.exists); reveal(toggle, app); toggle.tap()
                }
                reveal(app.buttons["trainingKind-"+kind],app);app.buttons["trainingKind-"+kind].tap()
                reveal(app.buttons["openTraining"],app);app.buttons["openTraining"].tap()
            }
            openTraining();reveal(app.buttons["startTraining"],app);app.buttons["startTraining"].tap()
            reveal(app.buttons["trainingAttempt"],app);app.buttons["trainingAttempt"].tap()
            // The command has saved this attempt before presentation starts. Terminate the app itself.
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            let afterAttempt=status(app);openTraining(resuming: true)
            let progress=app.descendants(matching:.any).matching(identifier:"trainingProgress").firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout:8));XCTAssertTrue(progress.label.contains("2 / 5"))
            for _ in 0..<4 {
                reveal(app.buttons["trainingAttempt"],app);app.buttons["trainingAttempt"].tap()
                XCTAssertFalse(app.buttons["trainingNext"].exists)
                XCTAssertTrue(app.buttons["trainingNext"].waitForExistence(timeout:10));app.buttons["trainingNext"].tap()
            }
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout:8))
            let growth=app.staticTexts["trainingGrowth"].label
            let art=app.descendants(matching:.any).matching(identifier:"trainingResultArt-"+kind).firstMatch
            XCTAssertTrue(art.exists);XCTAssertTrue(art.label.contains(pitcher ? "제구" : "수비"))
            app.navigationBars.buttons.element(boundBy:0).tap()
            if app.buttons["closeRoomDetail"].exists { close(app) }
            XCTAssertTrue(app.buttons["managementTab-home"].waitForExistence(timeout: 5)); app.buttons["managementTab-home"].tap()
            let completed=status(app);XCTAssertEqual(completed[0],afterAttempt[0]);XCTAssertEqual(completed[2],"행동 0/1");XCTAssertNotEqual(completed[1],afterAttempt[1])
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            XCTAssertEqual(status(app),completed);openTraining(resuming: true)
            XCTAssertTrue(app.staticTexts["trainingResultStored"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["trainingGrowth"].label,growth)
        }
    }
    @MainActor func testV56MatchTerminationResumeAndCompletedResultBothRoles() {
        continueAfterFailure=false
        let app=XCUIApplication()
        func openTodayGame(completed: Bool = false) {
            let gameTab = app.buttons["managementTab-game"]
            XCTAssertTrue(gameTab.waitForExistence(timeout: 8)); gameTab.tap()
            let facility = app.buttons[completed ? "facility-gameRecords" : "roomPrimary"]
            XCTAssertTrue(facility.waitForExistence(timeout: 8)); facility.tap()
            if completed {
                let schedule = app.buttons["gameSection-schedule"]
                XCTAssertTrue(schedule.waitForExistence(timeout: 8)); schedule.tap()
            }
            let entry = app.buttons["openCareerGame"]
            reveal(entry, app); XCTAssertTrue(entry.waitForExistence(timeout: 8)); entry.tap()
        }
        for pitcher in [false,true] {
            app.terminate();app.launchArguments=["-management-career-verification","-v56-disk-session",UUID().uuidString];app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            app.buttons["clubhouse-rest"].tap();app.buttons["confirmRest"].tap()
            XCTAssertTrue(app.staticTexts["restSaved"].waitForExistence(timeout:10))
            let restDone=app.buttons["restDone"]
            XCTAssertTrue(restDone.waitForExistence(timeout:5))
            restDone.tap();openTodayGame()
            XCTAssertTrue(app.buttons["opponentTab-plan"].waitForExistence(timeout:8));app.buttons["opponentTab-plan"].tap()
            reveal(app.buttons["confirmGamePlan"],app);app.buttons["confirmGamePlan"].tap()
            XCTAssertTrue(app.buttons["gameAutomatic"].waitForExistence(timeout:12))
            if pitcher {app.buttons["gamePitch"].tap();app.buttons["gameRelease"].tap()}
            else {app.buttons["gameInput-watch"].tap();app.buttons["battingTouchSurface"].tap()}
            let automatic=app.buttons["gameAutomatic"]
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:automatic)],timeout:35),.completed)
            let board=app.descendants(matching:.any).matching(identifier:"careerGameScore").firstMatch.label
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            openTodayGame();XCTAssertTrue(automatic.waitForExistence(timeout:12))
            XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"careerGameScore").firstMatch.label,board)
            capture(app,pitcher ? "v56-pitcher-match-resumed":"v56-batter-match-resumed")
            automatic.tap();app.buttons["진행하고 결과 저장"].tap();XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout:30))
            capture(app,pitcher ? "v56-pitcher-match-stored":"v56-batter-match-stored")
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            let completed=status(app);openTodayGame(completed: true);XCTAssertTrue(app.staticTexts["gameResultSaved"].waitForExistence(timeout:12))
            app.terminate();app.launch();XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30));if pitcher {pickPitcher(app)}
            XCTAssertEqual(status(app),completed)
        }
    }
    @MainActor func testV150InvalidQASessionCannotOpenDefaultRecovery() {
        continueAfterFailure=false
        let app=XCUIApplication()
        defer { app.terminate() }
        for arguments in [["-live-career-performance"], ["-live-career-performance","-qa-session","../../Career.store"]] {
            app.terminate();app.launchArguments=arguments;app.launch()
            let retry=app.buttons["retryOpenSave"]
            XCTAssertTrue(retry.waitForExistence(timeout:15))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "saveOpenFailure").firstMatch.exists)
            XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
            let recovery=app.buttons["openFailedSaveRecovery"]
            XCTAssertFalse(recovery.exists && recovery.isEnabled,"검증되지 않은 QA 세션에서 기본 저장 복구를 열면 안 됩니다.")
            XCTAssertFalse(app.staticTexts["homePlayerName"].exists)
            retry.tap()
            XCTAssertTrue(retry.waitForExistence(timeout:5))
            XCTAssertFalse(recovery.exists && recovery.isEnabled)
        }
    }

    @MainActor func testV156CloseDiscardsPendingPreviewAndCanRevalidate() {
        continueAfterFailure=false
        let sessionID = UUID().uuidString
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments=["-management-career-verification","-v56-disk-session",sessionID,"-save-protection-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30))
        let before=status(app)
        for _ in 1...3 {
            let settings=app.buttons["clubhouse-settings"]
            revealLocationChoice(settings,app);XCTAssertTrue(settings.isHittable);settings.tap()
            let date=app.staticTexts["saveVerifiedBackupDate"],confirm=app.buttons["confirmRestoreSave"]
            XCTAssertTrue(date.waitForExistence(timeout:10))
            let preparedDate=date.label
            revealLocationChoice(confirm,app)
            XCTAssertTrue(confirm.isHittable);XCTAssertTrue(confirm.isEnabled)
            confirm.tap()
            XCTAssertTrue(app.buttons["전체 복원"].waitForExistence(timeout:5))
            app.buttons["취소"].tap()
            XCTAssertTrue(confirm.waitForExistence(timeout:5));XCTAssertTrue(confirm.isEnabled)
            XCTAssertEqual(date.label,preparedDate,"확인 취소는 검증 후보를 유지해야 합니다.")
            let close=app.buttons["closeSettings"]
            XCTAssertTrue(close.isHittable);close.tap()
            let closed=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !close.exists},object:close)
            XCTAssertEqual(XCTWaiter.wait(for:[closed],timeout:8),.completed)
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:8))
            XCTAssertEqual(status(app),before,"검증·확인 취소·닫기는 날짜·피로·행동을 바꾸면 안 됩니다.")
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
            app.buttons["creationSection-abilities"].tap()
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
            app.buttons["creationSection-review"].tap()
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
            XCTAssertTrue(app.buttons["roomProfile"].waitForExistence(timeout: 8)); XCTAssertTrue(app.scrollViews["roomPropScroll"].exists)
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
            XCTAssertTrue(app.buttons["roomPrimary"].label.contains("경기 준비"))
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

extension ManagementDetailFlowTests {
    @MainActor func testV104CreationMatchPreviewAndSoundSettings() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-management-career-verification","-management-empty-verification"]
        app.launch()
        XCTAssertTrue(app.textFields["playerName"].waitForExistence(timeout:30))
        for role in ["batter","pitcher"] {
            app.buttons["creationSection-information"].tap()
            let button=app.buttons["role-"+role];reveal(button,app);button.tap()
            reveal(app.buttons["randomSchool"],app);app.buttons["randomSchool"].tap()
            app.buttons["creationSection-review"].tap()
            let next=app.buttons["creationNextGamePose"]
            if !next.exists {
                let preview=app.descendants(matching:.any).matching(identifier:"creationGamePoseDisclosure").firstMatch
                XCTAssertTrue(preview.waitForExistence(timeout:8));v104RevealCreation(preview,app,targetIdentifier:"creationGamePoseDisclosure")
                XCTAssertTrue(preview.isHittable);preview.tap()
            }
            v104RevealCreation(next,app,targetIdentifier:"creationNextGamePose")
            XCTAssertTrue(next.isHittable);XCTAssertGreaterThanOrEqual(next.frame.height,44)
            let faceCaption=app.staticTexts["creationSelectedFaceCaption"],poseCaption=app.staticTexts["creationGamePoseCaption"]
            XCTAssertTrue(faceCaption.isHittable);XCTAssertTrue(poseCaption.isHittable)
            XCTAssertGreaterThanOrEqual(poseCaption.frame.minX-faceCaption.frame.maxX,12)
            XCTAssertGreaterThanOrEqual(next.frame.minY-max(faceCaption.frame.maxY,poseCaption.frame.maxY),8)
            capture(app,"v104-creation-"+role)
            next.tap();XCTAssertTrue(app.staticTexts["자세 2 / 6"].exists)
            let caption=app.staticTexts["자세 2 / 6"]
            v104RevealCreation(caption,app,targetIdentifier:"자세 2 / 6");XCTAssertTrue(caption.isHittable)
            XCTAssertFalse(app.staticTexts["homePlayerName"].exists)
        }
        app.terminate();app.launchArguments=["-management-career-verification"];app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout:30))
        let before=status(app);app.buttons["clubhouse-settings"].tap()
        let sound=app.switches["settingSound"];XCTAssertTrue(sound.waitForExistence(timeout:8))
        capture(app,"v104-sound-settings")
        if app.buttons["previewSound"].isEnabled {app.buttons["previewSound"].tap()}
        app.buttons["closeSettings"].tap();XCTAssertEqual(status(app),before)
    }

    @MainActor private func v104RevealCreation(_ element: XCUIElement, _ app: XCUIApplication, targetIdentifier: String) {
        let scroll=app.scrollViews["creationScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout:8))
        var audit: [[String:Any]]=[]
        for attempt in 0..<18 {
            let shortcuts=["information","abilities","appearance","review"]
                .map {app.buttons["creationSection-"+$0]}.filter(\.exists)
            let viewport=scroll.frame.intersection(app.windows.firstMatch.frame)
            let top=max(viewport.minY,shortcuts.map(\.frame.maxY).max() ?? viewport.minY)+8
            let bottom=viewport.maxY-12
            XCTAssertGreaterThan(bottom-top,60,"생성 화면의 실제 스크롤 가시 영역이 필요합니다.")
            let exists=element.exists,frame=exists ? element.frame:.zero
            let visible=exists && element.isHittable && frame.minY >= top && frame.maxY <= bottom
            let middle=(top+bottom)/2
            let distance=exists ? frame.midY-middle:CGFloat(80)
            let delta=min(CGFloat(80),max(CGFloat(-80),distance))
            audit.append(["attempt":attempt+1,"scrollIdentifier":"creationScroll",
                "targetIdentifier":targetIdentifier,"targetExists":exists,"targetHittable":exists && element.isHittable,
                "targetEnabled":exists && element.isEnabled,"targetLabel":exists ? element.label:"",
                "matchingButtonCount":app.buttons.matching(identifier:targetIdentifier).count,
                "targetFrame":[Double(frame.minX),Double(frame.minY),Double(frame.width),Double(frame.height)],
                "viewportTop":Double(top),"viewportBottom":Double(bottom),"contentDelta":Double(visible ? 0:delta),
                "fullyVisible":visible])
            if visible {v104RecordCreationAudit(audit,identifier:targetIdentifier);return}
            let origin=app.frame.origin
            let start=app.coordinate(withNormalizedOffset:.zero)
                .withOffset(CGVector(dx:viewport.maxX-origin.x-18,dy:middle-origin.y))
            start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:0,dy:-delta)),
                withVelocity:100,thenHoldForDuration:0.2)
        }
        v104RecordCreationAudit(audit,identifier:targetIdentifier)
        let hierarchy=app.debugDescription
        print("V104 creation accessibility before failure · "+targetIdentifier+"\n"+hierarchy)
        let hierarchyAttachment=XCTAttachment(string:hierarchy)
        hierarchyAttachment.name="V104-creation-accessibility-"+targetIdentifier
        hierarchyAttachment.lifetime = .keepAlways;add(hierarchyAttachment)
        capture(app,"V104-creation-scroll-not-visible")
        XCTFail("생성 화면 항목을 creationScroll의 가시 영역으로 이동하지 못했습니다: "+targetIdentifier)
    }

    @MainActor private func v104RecordCreationAudit(_ audit: [[String:Any]], identifier: String) {
        do {
            let data=try JSONSerialization.data(withJSONObject:audit,options:[.prettyPrinted,.sortedKeys])
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            attachment.name="V104-creation-scroll-"+identifier
            attachment.lifetime = .keepAlways;add(attachment)
        } catch {print("V104 생성 화면 스크롤 근거 기록 실패: "+error.localizedDescription)}
    }

}

extension ManagementDetailFlowTests {
    @MainActor private func v151SelectRole(_ app:XCUIApplication,pitcher:Bool) {
        app.buttons["roomProfile"].tap()
        let choice=app.buttons[pitcher ? "homeRole-pitcher":"homeRole-batter"]
        XCTAssertTrue(choice.waitForExistence(timeout:8));revealLocationChoice(choice,app);choice.tap()
        if app.buttons["closeRoomDetail"].exists {close(app)}
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in
            !app.buttons["homeRole-batter"].exists && !app.buttons["homeRole-pitcher"].exists && !app.buttons["closeRoomDetail"].exists
        },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:5),.completed)
        XCTAssertTrue(app.staticTexts["homeAge"].label.contains(pitcher ? "투수":"타자"))
    }

    @MainActor private func selectAbilityTraining(_ kind: String, _ app: XCUIApplication) {
        let group = app.descendants(matching: .any).matching(identifier: "trainingEquipmentChoices").firstMatch
        revealLocationChoice(group, app)
        let toggle = group.elementType == .button ? group : group.buttons.firstMatch
        XCTAssertTrue(toggle.exists)
        revealLocationChoice(toggle, app); toggle.tap()
        let shelf = app.scrollViews["trainingEquipmentShelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 5))
        revealLocationChoice(shelf, app)
        let choice = app.buttons["trainingKind-" + kind]
        for _ in 0..<4 where !choice.isHittable { shelf.swipeLeft() }
        XCTAssertTrue(choice.isHittable, kind)
        choice.tap()
    }

    @MainActor private func revealScoutChoice(_ identifier:String,_ app:XCUIApplication) {
        let prefix=String(identifier.split(separator:"-")[0])
        if app.buttons[prefix+"Menu"].exists {app.buttons[prefix+"Menu"].tap()}
        reveal(app.buttons[identifier],app)
    }

    @MainActor func testV174ControlAutoReadyResumesSavedAttemptsAndRewardOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-v56-disk-session", UUID().uuidString]
        let attempt = app.buttons["trainingAttempt"]
        let next = app.buttons["trainingNext"]
        let autoPrepare = app.switches["trainingControlAutoPrepare"]
        let pending = app.descendants(matching: .any).matching(identifier: "trainingControlAutoPrepareStatus").firstMatch
        let progress = app.descendants(matching: .any).matching(identifier: "trainingProgress").firstMatch
        let stored = app.staticTexts["trainingResultStored"]

        func launchPitcher() {
            app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            v151SelectRole(app, pitcher: true)
        }
        func openSavedTraining() {
            app.buttons["managementTab-training"].tap()
            let entry = app.buttons["roomPrimary"]
            XCTAssertTrue(entry.waitForExistence(timeout: 8))
            entry.tap()
        }
        func ready(at round: Int) {
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"),
                                                   object: attempt)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
            XCTAssertTrue(progress.label.contains("\(round) / 5"), progress.label)
        }
        func throwAndReview() {
            reveal(attempt, app)
            XCTAssertTrue(attempt.isHittable)
            attempt.tap()
            XCTAssertTrue(next.waitForExistence(timeout: 10))
        }
        func turnOnAutoPrepare() {
            reveal(autoPrepare, app)
            XCTAssertTrue(autoPrepare.isHittable)
            XCTAssertEqual(autoPrepare.value as? String, "0")
            autoPrepare.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertTrue(pending.waitForExistence(timeout: 2))
        }
        func staysOffScreen(_ element: XCUIElement) {
            let appears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element)
            appears.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [appears], timeout: 3.5), .completed)
        }
        func fatigueValue(_ label: String) throws -> Int {
            let digits = try XCTUnwrap(label.range(of: "[0-9]+", options: .regularExpression))
            return try XCTUnwrap(Int(label[digits]))
        }

        launchPitcher()
        defer { app.terminate() }
        let initial = status(app)
        app.buttons["managementTab-training"].tap()
        app.buttons["facility-physical"].tap()
        selectAbilityTraining("control", app)
        let open = app.buttons["openTraining"]
        reveal(open, app)
        open.tap()
        let start = app.buttons["startTraining"]
        reveal(start, app)
        start.tap()

        ready(at: 1)
        throwAndReview()
        XCTAssertTrue(next.label.contains("2/5"))
        XCTAssertFalse(pending.exists)
        turnOnAutoPrepare()
        capture(app, "V174 제구 자동 준비 대기")
        ready(at: 2)
        staysOffScreen(next)
        XCTAssertTrue(progress.label.contains("2 / 5"))

        throwAndReview()
        XCTAssertTrue(pending.waitForExistence(timeout: 2))
        app.terminate()
        launchPitcher()
        let resumed = status(app)
        XCTAssertEqual(resumed[0], initial[0])
        XCTAssertEqual(resumed[1], initial[1])
        XCTAssertEqual(resumed[2], "훈련 이어하기")
        openSavedTraining()
        ready(at: 3)
        XCTAssertFalse(pending.exists)
        capture(app, "V174 두 번 저장 후 세 번째 제구 준비")

        throwAndReview()
        turnOnAutoPrepare()
        let closeTraining = app.buttons["closeRoomDetail"]
        XCTAssertTrue(closeTraining.isHittable)
        closeTraining.tap()
        staysOffScreen(next)
        openSavedTraining()
        ready(at: 4)

        throwAndReview()
        turnOnAutoPrepare()
        reveal(next, app)
        next.tap()
        ready(at: 5)
        throwAndReview()
        XCTAssertEqual(next.label, "세트 결산 보기")
        XCTAssertFalse(autoPrepare.exists)
        XCTAssertFalse(pending.exists)
        staysOffScreen(stored)
        reveal(next, app)
        next.tap()
        XCTAssertTrue(stored.waitForExistence(timeout: 8))
        let growth = app.staticTexts["trainingGrowth"].label
        let fatigue = app.staticTexts["trainingFatigue"].label
        capture(app, "V174 제구 다섯 회 저장 결과")

        app.terminate()
        launchPitcher()
        let completed = status(app)
        XCTAssertEqual(completed[0], initial[0])
        XCTAssertEqual(try fatigueValue(completed[1]), min(100, try fatigueValue(initial[1]) + 6))
        XCTAssertEqual(completed[2], "행동 0/1")
        openSavedTraining()
        XCTAssertTrue(stored.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["trainingGrowth"].label, growth)
        XCTAssertEqual(app.staticTexts["trainingFatigue"].label, fatigue)
        XCTAssertFalse(attempt.exists)
    }

    @MainActor func testV175ObservationAndEvaluationReceiptOpenCorrectReadOnlyDestinations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for evaluation in [false, true] {
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                                   "-management-reduced-motion-verification",
                                   evaluation ? "-v175-calendar-evaluation" : "-v175-calendar-observation"]
            app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
            let calendar = app.buttons["facility-calendar"]
            reveal(calendar,app); calendar.tap()
            let advance = app.buttons["advanceOffDays"]
            reveal(advance,app); advance.tap()
            let goal = app.buttons["calendarAdvanceGoalObservation"]
            XCTAssertTrue(goal.waitForExistence(timeout: 5)); goal.tap()
            let stop = app.staticTexts["calendarReceiptStop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 10))
            XCTAssertTrue(stop.label.contains(evaluation ? "계약 평가" : "관찰일"), stop.label)
            let date = app.scrollViews["calendarDetailScroll"].staticTexts["calendarDate"]
            let saved = date.label
            XCTAssertTrue(saved.contains(evaluation ? "7월 1일" : "4월 29일"), saved)
            let destination = app.buttons[evaluation ? "calendarProgressOpenEvaluation" : "calendarProgressOpenObservation"]
            reveal(destination,app); XCTAssertTrue(destination.isHittable)
            capture(app, evaluation ? "V175 관찰일 전 계약 평가 정지" : "V175 관찰일 도착 결과")
            destination.tap()
            let title = evaluation ? "고정 평가 확인" : "확정 관찰 보고서"
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
            if !evaluation {
                let frozen = app.staticTexts["scoutFrozenDate"]
                XCTAssertTrue(frozen.waitForExistence(timeout: 8))
                XCTAssertTrue(frozen.label.contains("4월 29일"), frozen.label)
            }
            app.navigationBars[title].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            XCTAssertEqual(date.label,saved)
            if evaluation {
                reveal(destination,app); destination.tap()
                let acknowledge = app.buttons["acknowledgeContractEvaluation"]
                XCTAssertTrue(acknowledge.waitForExistence(timeout: 5))
                reveal(acknowledge,app); acknowledge.tap()
                XCTAssertTrue(app.staticTexts["contractEvaluationStatus"].label.contains("확인 완료"))
                app.navigationBars[title].buttons.element(boundBy: 0).tap()
                XCTAssertEqual(date.label,saved)
                let resume = app.buttons["calendarProgressContinueObservation"]
                XCTAssertTrue(resume.waitForExistence(timeout: 8))
                reveal(resume,app); resume.tap()
                let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "7월 17일"), object: date)
                XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 12), .completed)
                XCTAssertTrue(stop.label.contains("관찰일"), stop.label)
            }
        }
    }

    @MainActor func testV180CareerJournalOrdersSavedEventsAndOpensHistoryReadOnly() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let session = ProcessInfo.processInfo.environment["BM_V180_JOURNAL_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                               "-management-reduced-motion-verification", "-v180-career-journal", "-v56-disk-session", session]
        app.launch()
        let seedError = app.staticTexts["managementSeedError"]
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60), seedError.exists ? seedError.label : "V180 journal fixture unavailable")
        let homeBefore = status(app)
        capture(app, "V180 journal before viewing")

        func element(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func openJournal() {
            app.buttons["managementTab-player"].tap()
            app.buttons["facility-records"].tap()
            let entry = app.buttons["playerOpenCareerJournal"]
            reveal(entry, app)
            XCTAssertTrue(entry.isHittable)
            capture(app, "V180 journal notebook records entry")
            entry.tap()
            XCTAssertTrue(app.scrollViews["careerJournalList"].waitForExistence(timeout: 10),
                          app.staticTexts["careerJournalError"].exists ? app.staticTexts["careerJournalError"].label : "")
        }
        let list = app.scrollViews["careerJournalList"]
        let eventPrefix = "careerJournalEvent-"
        let datePrefix = "careerJournalDate-"
        let dates = list.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", datePrefix))
        let events = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", eventPrefix))
        func choose(_ filter: String, count: Int) {
            let control = app.buttons["careerJournalFilter-" + filter]
            XCTAssertTrue(control.isHittable)
            control.tap()
            let counter = app.staticTexts["careerJournalCount"]
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(count)건"), object: counter)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
        }
        func detail(_ row: XCUIElement, date: String, checkpoint: String, verify: () -> Void) {
            for _ in 0..<14 where !row.isHittable { list.swipeUp(velocity: .slow) }
            XCTAssertTrue(row.isHittable, row.identifier)
            row.tap()
            let recordedDate = element("careerJournalDetailDate")
            XCTAssertTrue(recordedDate.waitForExistence(timeout: 10), row.identifier)
            XCTAssertEqual(recordedDate.value as? String, date)
            verify()
            capture(app, checkpoint)
            app.buttons["closeCareerJournalDetail"].tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
        }

        openJournal()
        let count = app.staticTexts["careerJournalCount"]
        XCTAssertEqual(count.label, "19건")
        let evaluationRows = events.matching(NSPredicate(format: "identifier BEGINSWITH %@", eventPrefix + "contract/evaluation/"))
        let aprilReview = evaluationRows.matching(NSPredicate(format: "identifier ENDSWITH %@", ":2030-04")).firstMatch
        let novemberReview = evaluationRows.matching(NSPredicate(format: "identifier ENDSWITH %@", ":2030-11")).firstMatch
        let aprilDate = element(datePrefix + "2030-04-01")
        let scoutRows = events.matching(NSPredicate(format: "identifier BEGINSWITH %@", eventPrefix + "scouting/"))
        let aprilObservation = scoutRows.matching(NSPredicate(format: "identifier ENDSWITH %@", ":52")).firstMatch
        for _ in 0..<4 where !aprilObservation.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(aprilDate.exists)
        XCTAssertEqual(dates.matching(identifier: datePrefix + "2030-04-01").count, 1)
        XCTAssertTrue(aprilReview.exists)
        XCTAssertTrue(aprilDate.frame.maxY <= aprilReview.frame.minY)
        XCTAssertTrue(aprilDate.frame.maxY <= aprilObservation.frame.minY)
        let aprilHeading = aprilDate.identifier, aprilHeadingTop = aprilDate.frame.minY
        let aprilRowsBottom = max(aprilReview.frame.maxY, aprilObservation.frame.maxY)
        XCTAssertFalse(dates.allElementsBoundByIndex.contains {
            let start = $0.frame.minY
            return $0.identifier != aprilHeading && start > aprilHeadingTop && start < aprilRowsBottom
        })
        XCTAssertTrue((aprilReview.value as? String ?? "").contains("핵심 기록"))
        capture(app, "V180 journal same-day saved scout and offer")

        // Walk the complete timeline since SwiftUI may only publish the portion it laid out.
        choose("contract", count: 3)
        choose("all", count: 19)
        var seenDates = Set<String>()
        var orderedDates: [String] = []
        var seenRows = Set<String>()
        for _ in 0..<18 {
            let frame = list.frame
            let timelineDates = dates.allElementsBoundByIndex.compactMap { day -> (XCUIElement, CGFloat)? in
                let center = day.frame.midY
                return (frame.minY..<frame.maxY).contains(center) ? (day, center) : nil
            }.sorted { $0.1 < $1.1 }
            for (day, _) in timelineDates {
                let iso = String(day.identifier.dropFirst(datePrefix.count))
                XCTAssertEqual(day.value as? String, iso)
                if seenDates.insert(iso).inserted { orderedDates.append(iso) }
            }
            let visibleRows = events.allElementsBoundByIndex.filter { (frame.minY..<frame.maxY).contains($0.frame.midY) }
                .map(\.identifier)
            XCTAssertEqual(visibleRows.count, Set(visibleRows).count)
            seenRows.formUnion(visibleRows)
            if seenRows.count == 19 && seenDates.contains("2026-04-01") { break }
            list.swipeUp(velocity: .slow)
        }
        XCTAssertEqual(seenRows.count, 19)
        XCTAssertEqual(orderedDates, orderedDates.sorted(by: >))
        XCTAssertEqual(orderedDates.first, "2030-11-01")
        XCTAssertEqual(orderedDates.last, "2026-04-01")
        XCTAssertTrue(orderedDates.contains("2026-04-02"))

        choose("game", count: 13)
        for _ in 0..<14 where !element(datePrefix + "2026-04-01").isHittable { list.swipeUp(velocity: .slow) }
        let openingHeader = element(datePrefix + "2026-04-01")
        XCTAssertTrue(openingHeader.isHittable)
        let opening = try XCTUnwrap(events.allElementsBoundByIndex.first { $0.frame.minY >= openingHeader.frame.maxY })
        let openingID = opening.identifier
        XCTAssertTrue(openingID.hasPrefix(eventPrefix + "match/"))
        var openingScore = ""
        detail(opening, date: "2026-04-01", checkpoint: "V180 journal historical game") {
            let score = app.staticTexts["gameFinalScore"]
            XCTAssertTrue(score.waitForExistence(timeout: 5))
            openingScore = score.label
        }
        choose("training", count: 1)
        let training = events.matching(NSPredicate(format: "identifier ENDSWITH %@", ":2026-04-02")).firstMatch
        detail(training, date: "2026-04-02", checkpoint: "V180 journal historical training") {
            XCTAssertTrue(element("careerJournalTrainingScore").waitForExistence(timeout: 5))
            let growth = element("trainingGrowth")
            reveal(growth, app)
            XCTAssertTrue(growth.exists)
        }
        choose("scout", count: 2)
        detail(aprilObservation, date: "2030-04-01", checkpoint: "V180 journal historical scouting") {
            XCTAssertTrue(element("careerJournalScoutTitle").waitForExistence(timeout: 5))
            let frozen = element("careerJournalDetailDate")
            XCTAssertTrue(frozen.label.contains("4월 1일"), frozen.label)
            XCTAssertFalse(app.buttons["acknowledgeContractEvaluation"].exists)
        }
        choose("contract", count: 3)
        let accepted = events.matching(NSPredicate(format: "identifier BEGINSWITH %@", eventPrefix + "contract/decision/")).firstMatch
        for _ in 0..<4 where !accepted.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(accepted.label.contains("계약 수락"), accepted.label)
        XCTAssertTrue((accepted.value as? String ?? "").contains("핵심 기록"))
        let acceptedLabel = accepted.label
        let offerPrefix = "careerJournalContractOffer-"
        let savedOfferID = String(accepted.identifier.dropFirst((eventPrefix + "contract/decision/").count))
        let savedOffer = element(offerPrefix + savedOfferID)
        let offerCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", offerPrefix))
        let contractScroll = app.scrollViews["careerJournalContractScroll"]
        let evaluationStatus = element("careerJournalContractStatus")
        func inside(_ ancestor: XCUIElement, _ id: String) -> XCUIElement {
            ancestor.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func revealContract(_ target: XCUIElement) {
            for _ in 0..<8 where !target.isHittable { contractScroll.swipeUp(velocity: .slow) }
            XCTAssertTrue(target.isHittable, target.identifier)
        }
        func assertArchiveActions() {
            for id in ["acknowledgeContractEvaluation", "acceptLiveOffer", "rejectLiveOffer", "acceptRenewalOffer", "rejectRenewalOffer"] {
                XCTAssertFalse(app.buttons[id].exists, id)
            }
        }
        var clubLabel = ""
        var indexLabel = ""
        var bonusLabel = ""
        detail(accepted, date: "2030-04-03", checkpoint: "V180 journal historical contract decision") {
            XCTAssertEqual(element("careerJournalContractTitle").label, "계약 수락")
            XCTAssertEqual(offerCards.count, 1)
            XCTAssertTrue(savedOffer.exists)
            let clubName = inside(savedOffer, "careerJournalContractClubName")
            let crest = inside(savedOffer, "careerJournalContractCrest")
            XCTAssertTrue(clubName.exists)
            XCTAssertTrue(crest.exists)
            clubLabel = clubName.label
            XCTAssertTrue(acceptedLabel.contains(clubLabel), clubLabel)
            XCTAssertEqual(crest.label, clubLabel + " 엠블럼")
            let logoFrame = crest.frame, nameFrame = clubName.frame
            XCTAssertTrue(nameFrame.minX >= logoFrame.maxX + 4 || nameFrame.minY >= logoFrame.maxY + 4,
                          "Club name and crest should have independent space")
            indexLabel = inside(savedOffer, "careerJournalContractMetric-index").label
            bonusLabel = inside(savedOffer, "careerJournalContractMetric-bonus").label
            XCTAssertTrue(indexLabel.contains("연봉지수") && indexLabel.contains(where: \.isNumber), indexLabel)
            XCTAssertTrue(bonusLabel.contains("계약금") && bonusLabel.contains("원") && bonusLabel.contains(where: \.isNumber), bonusLabel)
            XCTAssertTrue(inside(savedOffer, "careerJournalContractMetric-role").exists)
            assertArchiveActions()
            capture(app, "V181 contract accepted overview")

            let decisionDate = element("careerJournalContractDate-2030-04-03")
            revealContract(decisionDate)
            XCTAssertEqual(decisionDate.value as? String, "2030-04-03")
            XCTAssertTrue(element("careerJournalContractDates").exists)
            for iso in ["2030-04-01", "2030-04-07"] {
                XCTAssertEqual(element("careerJournalContractDate-" + iso).value as? String, iso)
            }
            capture(app, "V181 contract accepted dates")
        }
        detail(aprilReview, date: "2030-04-01", checkpoint: "V181 contract two saved offers") {
            XCTAssertTrue(evaluationStatus.label.contains("제의 2건"), evaluationStatus.label)
            XCTAssertEqual(offerCards.count, 2)
            XCTAssertEqual(inside(savedOffer, "careerJournalContractClubName").label, clubLabel)
            XCTAssertTrue(inside(savedOffer, "careerJournalContractCrest").exists)
            XCTAssertEqual(inside(savedOffer, "careerJournalContractMetric-index").label, indexLabel)
            XCTAssertEqual(inside(savedOffer, "careerJournalContractMetric-bonus").label, bonusLabel)
            let collegeOffer = offerCards.matching(NSPredicate(format: "identifier CONTAINS %@", "/college/")).firstMatch
            XCTAssertTrue(collegeOffer.exists)
            XCTAssertFalse(inside(collegeOffer, "careerJournalContractCrest").exists)
            XCTAssertTrue(inside(collegeOffer, "careerJournalContractMetric-index").label.contains("선발 지원지수"))
            assertArchiveActions()
        }
        // Restore the top before checking the latest unread review from a potentially scrolled offer list.
        choose("scout", count: 2)
        choose("contract", count: 3)
        detail(novemberReview, date: "2030-11-01", checkpoint: "V180 journal unread contract evaluation") {
            XCTAssertTrue(evaluationStatus.label.contains("제의 없음"), evaluationStatus.label)
            XCTAssertEqual(offerCards.count, 0)
            XCTAssertFalse(element("careerJournalContractCrest").exists)
            let reviewSubject = element("careerJournalContractReviewedClub")
            XCTAssertTrue(reviewSubject.exists)
            XCTAssertTrue(element("careerJournalContractReviewedCrest").exists)
            let evidence = element("careerJournalContractEvidence")
            let body = element("careerJournalContractEvidenceBody")
            XCTAssertFalse(body.exists)
            assertArchiveActions()
            capture(app, "V181 contract unread review without offers")
            revealContract(evidence)
            XCTAssertEqual(evidence.value as? String, "접힘")
            evidence.tap()
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            XCTAssertEqual(evidence.value as? String, "펼침")
            revealContract(body)
            XCTAssertTrue(body.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "40타석 필요")).firstMatch.exists)
            assertArchiveActions()
            capture(app, "V181 contract unread evidence expanded")
        }
        app.buttons["closeCareerJournal"].tap()
        close(app)
        app.buttons["managementTab-home"].tap()
        XCTAssertEqual(status(app), homeBefore)
        capture(app, "V180 journal after viewing")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 20))
        XCTAssertEqual(status(app), homeBefore)
        openJournal()
        XCTAssertEqual(count.label, "19건")
        let restored = events.matching(identifier: openingID).firstMatch
        choose("game", count: 13)
        detail(restored, date: "2026-04-01", checkpoint: "V180 journal reopened saved result") {
            XCTAssertEqual(app.staticTexts["gameFinalScore"].label, openingScore)
        }
        let manifest = XCTAttachment(string: ([session] + orderedDates + seenRows.sorted() + homeBefore).joined(separator: "\n"))
        manifest.name = "V180 journal isolated session and timeline proof"
        manifest.lifetime = .keepAlways
        add(manifest)
    }

    @MainActor func testV181CareerJournalContractLargeTextKeepsCrestAndSavedTermsReadable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let session = ProcessInfo.processInfo.environment["BM_V180_JOURNAL_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                               "-management-reduced-motion-verification", "-v180-career-journal", "-v56-disk-session", session,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60))
        app.buttons["managementLargeMenu"].tap()
        app.buttons["managementMenu-player"].tap()
        let records = app.buttons["facility-records"]
        reveal(records, app)
        records.tap()
        let entry = app.buttons["playerOpenCareerJournal"]
        reveal(entry, app)
        entry.tap()
        let list = app.scrollViews["careerJournalList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        app.buttons["careerJournalFilter-contract"].tap()
        let accepted = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                                        "careerJournalEvent-contract/decision/")).firstMatch
        for _ in 0..<6 where !accepted.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(accepted.isHittable)
        accepted.tap()

        let scroll = app.scrollViews["careerJournalContractScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        func show(_ id: String) -> XCUIElement {
            let target = scroll.descendants(matching: .any).matching(identifier: id).firstMatch
            for _ in 0..<12 where !target.isHittable { scroll.swipeUp(velocity: .slow) }
            XCTAssertTrue(target.isHittable, id)
            return target
        }
        let crest = show("careerJournalContractCrest")
        let name = show("careerJournalContractClubName")
        XCTAssertGreaterThanOrEqual(name.frame.minY, crest.frame.maxY + 4)
        XCTAssertLessThanOrEqual(name.frame.maxX, scroll.frame.maxX)
        capture(app, "V181 contract large text identity")
        XCTAssertTrue(show("careerJournalContractMetric-bonus").label.contains("계약금"))
        XCTAssertFalse(show("careerJournalContractMetric-role").label.isEmpty)
        let effectiveDate = show("careerJournalContractDate-2030-04-03")
        XCTAssertEqual(effectiveDate.value as? String, "2030-04-03")
        capture(app, "V181 contract large text dates")
        app.buttons["closeCareerJournalDetail"].tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    @MainActor func testV182CareerJournalScoutShowsTheSelectedArchivedReport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let environment = ProcessInfo.processInfo.environment
        let session = environment["BM_V182_SCOUT_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                               "-management-reduced-motion-verification", "-v182-scout-journal", "-v56-disk-session", session]
        app.launch()
        let seedError = app.staticTexts["managementSeedError"]
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60),
                      seedError.exists ? seedError.label : "V182 scout journal fixture unavailable")
        let homeBefore = status(app)
        let list = app.scrollViews["careerJournalList"]
        let scroll = app.scrollViews["careerJournalScoutScroll"]
        let clubs = scroll.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "careerJournalScoutClub-"))

        func element(_ identifier: String, in root: XCUIElement) -> XCUIElement {
            root.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        func openJournal() {
            app.buttons["managementTab-player"].tap()
            app.buttons["facility-records"].tap()
            let entry = app.buttons["playerOpenCareerJournal"]
            reveal(entry, app)
            entry.tap()
            XCTAssertTrue(list.waitForExistence(timeout: 10))
            app.buttons["careerJournalFilter-scout"].tap()
            let count = app.staticTexts["careerJournalCount"]
            let savedReports = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "3건"), object: count)
            XCTAssertEqual(XCTWaiter.wait(for: [savedReports], timeout: 5), .completed)
        }
        func openReport(_ period: Int, date: String) {
            let rows = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                                                          "careerJournalEvent-scouting/", ":\(period)"))
            let row = rows.firstMatch
            for _ in 0..<4 where !row.isHittable { list.swipeUp(velocity: .slow) }
            XCTAssertTrue(row.isHittable, date)
            row.tap()
            XCTAssertTrue(scroll.waitForExistence(timeout: 10))
            XCTAssertEqual(element("careerJournalDetailDate", in: scroll).value as? String, date)
        }
        func closeReport() {
            app.buttons["closeCareerJournalDetail"].tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
        }
        func show(_ identifier: String) -> XCUIElement {
            let target = element(identifier, in: scroll)
            for _ in 0..<9 where !target.isHittable { scroll.swipeUp(velocity: .slow) }
            XCTAssertTrue(target.isHittable, identifier)
            return target
        }

        openJournal()
        openReport(2, date: "2026-06-07")
        XCTAssertEqual(clubs.count, 3)
        let firstClub = clubs.firstMatch
        XCTAssertTrue(firstClub.exists)
        let frozenClub = element("careerJournalScoutClubName", in: firstClub).label
        let frozenStage = element("careerJournalScoutStage", in: firstClub).label
        XCTAssertFalse(frozenClub.isEmpty)
        XCTAssertEqual(frozenStage, "우선 관찰")
        XCTAssertTrue(element("careerJournalScoutCrest", in: firstClub).label.contains(frozenClub))
        if let expectedID = environment["BM_V182_SCOUT_EXPECTED_CLUB_ID"],
           let expectedName = environment["BM_V182_SCOUT_EXPECTED_CLUB_NAME"] {
            XCTAssertEqual(firstClub.identifier, "careerJournalScoutClub-" + expectedID)
            XCTAssertEqual(frozenClub, expectedName)
        }
        capture(app, "V182 scout historical interest")
        show("careerJournalScoutMoreClubs").tap()
        XCTAssertEqual(clubs.count, 10)
        show("careerJournalScoutMoreClubs").tap()
        XCTAssertEqual(clubs.count, 3)

        let sampleBody = element("careerJournalScoutSampleBody", in: scroll)
        let evidenceBody = element("careerJournalScoutEvidenceBody", in: scroll)
        XCTAssertFalse(sampleBody.exists)
        XCTAssertFalse(evidenceBody.exists)
        show("careerJournalScoutSample").tap()
        XCTAssertTrue(sampleBody.waitForExistence(timeout: 5))
        let historicalSample = show("careerJournalScoutSampleBodyFact-1").label
        XCTAssertTrue(historicalSample.contains("12경기"), historicalSample)
        let historicalPlateAppearances = show("careerJournalScoutSampleBodyFact-2").label
        XCTAssertTrue(historicalPlateAppearances.contains("55타석"), historicalPlateAppearances)
        XCTAssertFalse(evidenceBody.exists)
        capture(app, "V182 scout saved sample")

        show("careerJournalScoutEvidence").tap()
        XCTAssertTrue(evidenceBody.waitForExistence(timeout: 5))
        XCTAssertTrue(sampleBody.exists)
        _ = show("careerJournalScoutEvidenceBodyFact-0")
        let reasons = evidenceBody.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "20세 미만"))
        XCTAssertTrue(reasons.firstMatch.exists)
        let archivedFit = evidenceBody.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "역할 기량 75.0 / 구단 기준 64.0"))
        XCTAssertTrue(archivedFit.firstMatch.exists)
        XCTAssertFalse(app.buttons["acknowledgeContractEvaluation"].exists)
        for _ in 0..<4 where archivedFit.firstMatch.frame.maxY > scroll.frame.maxY - 16 {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(scroll.frame.contains(archivedFit.firstMatch.frame))
        capture(app, "V182 scout saved evidence")
        closeReport()

        openReport(3, date: "2026-06-24")
        XCTAssertFalse(clubs.firstMatch.exists)
        XCTAssertEqual(element("careerJournalScoutStatus", in: scroll).label, "구단 관심 없음")
        capture(app, "V182 scout later zero interest")
        show("careerJournalScoutSample").tap()
        let laterSample = show("careerJournalScoutSampleBodyFact-1").label
        XCTAssertTrue(laterSample.contains("13경기"), laterSample)
        let laterPlateAppearances = show("careerJournalScoutSampleBodyFact-2").label
        XCTAssertTrue(laterPlateAppearances.contains("59타석"), laterPlateAppearances)
        XCTAssertNotEqual(laterSample, historicalSample)
        closeReport()

        openReport(0, date: "2026-04-01")
        XCTAssertFalse(clubs.firstMatch.exists)
        XCTAssertEqual(element("careerJournalScoutStatus", in: scroll).label, "구단 관심 미기록")
        capture(app, "V182 scout legacy interest unrecorded")
        closeReport()
        app.buttons["closeCareerJournal"].tap()
        close(app)
        app.buttons["managementTab-home"].tap()
        XCTAssertEqual(status(app), homeBefore)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 20))
        XCTAssertEqual(status(app), homeBefore)
        openJournal()
        openReport(2, date: "2026-06-07")
        XCTAssertEqual(element("careerJournalScoutClubName", in: clubs.firstMatch).label, frozenClub)
        XCTAssertEqual(element("careerJournalScoutStage", in: clubs.firstMatch).label, frozenStage)
        closeReport()
    }

    @MainActor func testV183CareerJournalMatchAndTrainingShowSavedDetails() throws {
        struct Archive: Decodable {
            struct Match: Decodable {
                let date: String
                let key: String
                let score: String
                let personal: [String: String]
                let innings: [String]?
            }
            struct Training: Decodable {
                let date: String
                let key: String
                let average: String
                let gain: String
                let attempts: [String]
            }
            let fixtureDate: String
            let matches: [Match]
            let trainings: [Training]
        }

        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let environment = ProcessInfo.processInfo.environment
        let session = environment["BM_V183_RESULT_SESSION"] ?? UUID().uuidString
        let archive = try environment["BM_V183_ARCHIVE_JSON"].map { try JSONDecoder().decode(Archive.self, from: Data($0.utf8)) }
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                               "-management-reduced-motion-verification", "-v183-result-journal", "-v56-disk-session", session]
        app.launch()
        let seedError = app.staticTexts["managementSeedError"]
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60),
                      seedError.exists ? seedError.label : "V183 result journal fixture unavailable")
        let homeBefore = status(app)
        XCTAssertTrue(homeBefore[0].contains("11월 2일"), homeBefore[0])

        let list = app.scrollViews["careerJournalList"]
        let matchScroll = app.scrollViews["careerJournalMatchScroll"]
        let trainingScroll = app.scrollViews["careerJournalTrainingScroll"]
        let matchDate = "2026-04-01", legacyMatchDate = "2028-04-01"
        let trainingDate = "2026-04-02", laterTrainingDate = "2026-04-03"
        let archivedMatch = archive?.matches.first { $0.date == matchDate }
        let legacyMatch = archive?.matches.first { $0.date == legacyMatchDate }
        let archivedTraining = archive?.trainings.first { $0.date == trainingDate }
        let laterTraining = archive?.trainings.first { $0.date == laterTrainingDate }
        if let archive {
            XCTAssertEqual(archive.fixtureDate, "2030-11-02")
            XCTAssertEqual(archive.matches.map(\.date), [matchDate, legacyMatchDate])
            XCTAssertEqual(archive.trainings.map(\.date), [trainingDate, laterTrainingDate])
        }

        func element(_ identifier: String, in root: XCUIElement) -> XCUIElement {
            root.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        func openJournal() {
            app.buttons["managementTab-player"].tap()
            app.buttons["facility-records"].tap()
            let entry = app.buttons["playerOpenCareerJournal"]
            reveal(entry, app)
            entry.tap()
            XCTAssertTrue(list.waitForExistence(timeout: 10))
        }
        func choose(_ filter: String, count: String) {
            app.buttons["careerJournalFilter-" + filter].tap()
            let counter = app.staticTexts["careerJournalCount"]
            let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", count), object: counter)
            XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed)
        }
        func openDetail(_ kind: String, date: String, key: String?, scroll: XCUIElement) {
            let prefix = "careerJournalEvent-\(kind)/"
            let row = if let key { list.buttons[prefix + key] } else {
                list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", prefix, ":" + date)).firstMatch
            }
            for _ in 0..<14 where !row.isHittable { list.swipeUp(velocity: .slow) }
            XCTAssertTrue(row.isHittable, date)
            row.tap()
            XCTAssertTrue(scroll.waitForExistence(timeout: 10), date)
            let recordedDate = element("careerJournalDetailDate", in: scroll)
            XCTAssertTrue(recordedDate.waitForExistence(timeout: 5), date)
            XCTAssertEqual(recordedDate.value as? String, date)
        }
        func closeDetail() {
            app.buttons["closeCareerJournalDetail"].tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
        }
        func show(_ target: XCUIElement, in scroll: XCUIElement) {
            for _ in 0..<8 where !target.isHittable { scroll.swipeUp(velocity: .slow) }
            XCTAssertTrue(target.isHittable, target.identifier)
        }
        func matchSummary(_ stored: Archive.Match?) throws -> String {
            let score = matchScroll.staticTexts["gameFinalScore"]
            XCTAssertTrue(score.isHittable, score.identifier)
            let savedScore = try XCTUnwrap(score.value as? String)
            if let stored { XCTAssertEqual(savedScore, stored.score) }
            let personal = element("careerJournalMatchPersonal", in: matchScroll)
            XCTAssertTrue(personal.exists)
            for stat in ["atBats", "hits", "homeRuns", "rbi"] {
                let metric = element("gameResult-" + stat, in: personal)
                XCTAssertTrue(metric.isHittable, stat)
                let value = try XCTUnwrap(metric.value as? String, stat)
                XCTAssertNotNil(Int(value), stat)
                if let stored { XCTAssertEqual(value, stored.personal[stat], stat) }
            }
            return savedScore
        }
        func trainingSummary(_ stored: Archive.Training?) throws -> (average: String, gain: String) {
            let average = element("careerJournalTrainingScore", in: trainingScroll)
            let growth = element("trainingGrowth", in: trainingScroll)
            XCTAssertTrue(average.isHittable)
            XCTAssertTrue(growth.isHittable)
            let summary = (try XCTUnwrap(average.value as? String), try XCTUnwrap(growth.value as? String))
            if let stored {
                XCTAssertEqual(summary.0, stored.average)
                XCTAssertEqual(summary.1, stored.gain)
            }
            return summary
        }
        func openTrainingAttempts(_ stored: Archive.Training?) throws -> [String] {
            let toggle = trainingScroll.buttons["careerJournalTrainingAttempts"]
            let body = element("careerJournalTrainingAttemptsBody", in: trainingScroll)
            XCTAssertFalse(body.exists)
            XCTAssertFalse(element("careerJournalTrainingAttempt-1", in: trainingScroll).exists)
            show(toggle, in: trainingScroll)
            toggle.tap()
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            let scores = try (1...5).map { round in
                try XCTUnwrap(element("careerJournalTrainingAttempt-\(round)", in: body).value as? String, "Round \(round)")
            }
            if let stored { XCTAssertEqual(scores, stored.attempts) }
            return scores
        }

        openJournal()
        choose("game", count: "13건")
        openDetail("match", date: matchDate, key: archivedMatch?.key, scroll: matchScroll)
        let originalScore = try matchSummary(archivedMatch)
        let inningBody = element("careerJournalMatchInningsBody", in: matchScroll)
        XCTAssertFalse(inningBody.exists)
        XCTAssertFalse(element("careerJournalMatchInning-1", in: matchScroll).exists)
        XCTAssertTrue(matchScroll.buttons["openMatchHighlights"].exists)
        capture(app, "V183 match summary")
        let innings = matchScroll.buttons["careerJournalMatchInnings"]
        show(innings, in: matchScroll)
        innings.tap()
        XCTAssertTrue(inningBody.waitForExistence(timeout: 5))
        let scoreByInning = try (1...9).map { number in
            try XCTUnwrap(element("careerJournalMatchInning-\(number)", in: inningBody).value as? String, "Inning \(number)")
        }
        if let archivedMatch { XCTAssertEqual(scoreByInning, try XCTUnwrap(archivedMatch.innings)) }
        show(element("careerJournalMatchInning-9", in: inningBody), in: matchScroll)
        capture(app, "V183 match innings")
        closeDetail()

        choose("training", count: "2건")
        openDetail("training", date: trainingDate, key: archivedTraining?.key, scroll: trainingScroll)
        let originalTraining = try trainingSummary(archivedTraining)
        XCTAssertEqual(originalTraining.average, "100.0")
        capture(app, "V183 training summary")
        XCTAssertEqual(try openTrainingAttempts(archivedTraining), Array(repeating: "100", count: 5))
        show(element("careerJournalTrainingAttempt-5", in: trainingScroll), in: trainingScroll)
        capture(app, "V183 training attempts")
        closeDetail()
        openDetail("training", date: laterTrainingDate, key: laterTraining?.key, scroll: trainingScroll)
        let recentTraining = try trainingSummary(laterTraining)
        XCTAssertNotEqual(recentTraining.average, originalTraining.average)
        XCTAssertNotEqual(recentTraining.gain, originalTraining.gain)
        capture(app, "V183 training varied summary")
        let recentAttempts = try openTrainingAttempts(laterTraining)
        XCTAssertGreaterThan(Set(recentAttempts).count, 1)
        show(element("careerJournalTrainingAttempt-5", in: trainingScroll), in: trainingScroll)
        capture(app, "V183 training varied attempts")
        closeDetail()

        choose("game", count: "13건")
        openDetail("match", date: legacyMatchDate, key: legacyMatch?.key, scroll: matchScroll)
        _ = try matchSummary(legacyMatch)
        show(innings, in: matchScroll)
        innings.tap()
        XCTAssertTrue(element("careerJournalMatchInningsMissing", in: matchScroll).waitForExistence(timeout: 5))
        XCTAssertFalse(element("careerJournalMatchInning-1", in: matchScroll).exists)
        closeDetail()
        app.buttons["closeCareerJournal"].tap()
        close(app)
        app.buttons["managementTab-home"].tap()
        XCTAssertEqual(status(app), homeBefore)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 20))
        XCTAssertEqual(status(app), homeBefore)
        openJournal()
        choose("game", count: "13건")
        openDetail("match", date: matchDate, key: archivedMatch?.key, scroll: matchScroll)
        XCTAssertEqual(try matchSummary(archivedMatch), originalScore)
        XCTAssertFalse(inningBody.exists)
        closeDetail()
        choose("training", count: "2건")
        openDetail("training", date: trainingDate, key: archivedTraining?.key, scroll: trainingScroll)
        let reopenedTraining = try trainingSummary(archivedTraining)
        XCTAssertEqual(reopenedTraining.average, originalTraining.average)
        XCTAssertEqual(reopenedTraining.gain, originalTraining.gain)
    }

    @MainActor func testV184CareerJournalRestoresFiltersAndTimelinePosition() throws {
        struct PositionedRow: Codable {
            let id: String
            let y: CGFloat
        }
        struct ReturnCheck: Codable {
            let filter: String
            let kind: String
            let date: String
            let count: String
            let scrolled: Bool
            let before: [PositionedRow]
            let after: [PositionedRow]
        }

        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let session = ProcessInfo.processInfo.environment["BM_V184_RESULT_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                               "-management-reduced-motion-verification", "-v183-result-journal", "-v56-disk-session", session]
        app.launch()
        let seedError = app.staticTexts["managementSeedError"]
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60),
                      seedError.exists ? seedError.label : "V184 result journal fixture unavailable")
        let homeBefore = status(app)
        app.buttons["managementTab-player"].tap()
        app.buttons["facility-records"].tap()
        let entry = app.buttons["playerOpenCareerJournal"]
        reveal(entry, app)
        entry.tap()

        let list = app.scrollViews["careerJournalList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let allFilters = ["all", "game", "training", "scout", "contract"]
        let counter = app.staticTexts["careerJournalCount"]
        let eventPrefix = "careerJournalEvent-"
        var checks: [ReturnCheck] = []

        func button(_ filter: String) -> XCUIElement { app.buttons["careerJournalFilter-" + filter] }
        func selection() -> [String] { allFilters.filter { button($0).isSelected } }
        func choose(_ filter: String, count: String) {
            if !button(filter).isSelected { button(filter).tap() }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                button(filter).isSelected && counter.label == count
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, filter)
            XCTAssertEqual(selection(), [filter])
        }
        func visibleRows() -> [PositionedRow] {
            let viewport = list.frame
            return list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", eventPrefix))
                .allElementsBoundByIndex.compactMap { row -> PositionedRow? in
                    let frame = row.frame
                    guard frame.height > 0, frame.maxY > viewport.minY + 2, frame.minY < viewport.maxY - 2 else { return nil }
                    return PositionedRow(id: row.identifier, y: frame.minY - viewport.minY)
                }.sorted { $0.y < $1.y }
        }
        func showRow(_ row: XCUIElement) {
            for _ in 0..<14 where !row.isHittable { list.swipeUp(velocity: .slow) }
            XCTAssertTrue(row.isHittable, row.debugDescription)
        }
        func roundTrip(filter: String, count: String, kind: String, prefix: String? = nil,
                       suffix: String = "", date: String, detail: String, scrolled: Bool = false,
                       moveNearTop: Bool = false, captureName: String? = nil) throws {
            if filter == "all" { choose("game", count: "13건") }
            choose(filter, count: count)
            let initialRows = scrolled ? visibleRows() : []
            let keyPrefix = eventPrefix + (prefix ?? kind + "/")
            let route = suffix.isEmpty ? NSPredicate(format: "identifier BEGINSWITH %@", keyPrefix)
                : NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", keyPrefix, suffix)
            let row = list.buttons.matching(route).firstMatch
            if moveNearTop {
                // Both rows are near the beginning, so move the viewport before opening them.
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.68))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.43))
                start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
            }
            showRow(row)
            let tappedID = row.identifier
            let before = visibleRows()
            let beforeTap = try XCTUnwrap(before.first { $0.id == tappedID })
            XCTAssertGreaterThanOrEqual(before.count, 2, kind)
            if scrolled {
                let sameStart = initialRows.first?.id == before.first?.id
                    && abs((initialRows.first?.y ?? .zero) - (before.first?.y ?? .zero)) <= 10
                XCTAssertFalse(sameStart, "No measured scroll before opening \(kind) in \(filter)")
            }
            if captureName == "game" { capture(app, "V184 game list before") }

            row.tap()
            let detailScroll = app.scrollViews[detail]
            XCTAssertTrue(detailScroll.waitForExistence(timeout: 10), kind)
            let sourceDate = detailScroll.descendants(matching: .any).matching(identifier: "careerJournalDetailDate").firstMatch
            XCTAssertTrue(sourceDate.waitForExistence(timeout: 5), kind)
            XCTAssertEqual(sourceDate.value as? String, date)
            if let captureName { capture(app, "V184 \(captureName) detail") }

            app.buttons["closeCareerJournalDetail"].tap()
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                button(filter).isHittable && list.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed, kind)
            XCTAssertEqual(selection(), [filter], kind)
            XCTAssertEqual(counter.label, count, kind)
            // Sample the viewport before any other gesture or scroll-to-item attempt.
            let after = visibleRows()
            let afterTap = try XCTUnwrap(after.first { $0.id == tappedID }, kind)
            XCTAssertEqual(afterTap.y, beforeTap.y, accuracy: 1, kind)
            XCTAssertEqual(after.map(\.id), before.map(\.id), kind)
            for (expected, actual) in zip(before, after) {
                XCTAssertEqual(actual.y, expected.y, accuracy: 1, "\(kind) / \(actual.id)")
            }
            checks.append(ReturnCheck(filter: filter, kind: kind, date: date, count: count, scrolled: scrolled,
                                      before: before, after: after))
            if captureName == "game" { capture(app, "V184 game list returned") }
            if filter == "all", kind == "training" { capture(app, "V184 all list returned") }
        }

        try roundTrip(filter: "game", count: "13건", kind: "match", suffix: ":2026-04-01", date: "2026-04-01",
                      detail: "careerJournalMatchScroll", scrolled: true, captureName: "game")
        try roundTrip(filter: "training", count: "2건", kind: "training", suffix: ":2026-04-03", date: "2026-04-03",
                      detail: "careerJournalTrainingScroll", captureName: "training")
        try roundTrip(filter: "scout", count: "2건", kind: "scouting", suffix: ":observation-v1:52", date: "2030-04-01",
                      detail: "careerJournalScoutScroll", captureName: "scout")
        try roundTrip(filter: "contract", count: "3건", kind: "contract", prefix: "contract/decision/", date: "2030-04-03",
                      detail: "careerJournalContractScroll", captureName: "contract")
        try roundTrip(filter: "all", count: "20건", kind: "scouting", suffix: ":observation-v1:52", date: "2030-04-01",
                      detail: "careerJournalScoutScroll", scrolled: true, moveNearTop: true)
        try roundTrip(filter: "all", count: "20건", kind: "contract", prefix: "contract/evaluation/", suffix: ":2030-04", date: "2030-04-01",
                      detail: "careerJournalContractScroll", scrolled: true, moveNearTop: true)
        try roundTrip(filter: "all", count: "20건", kind: "training", suffix: ":2026-04-02", date: "2026-04-02",
                      detail: "careerJournalTrainingScroll", scrolled: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = XCTAttachment(data: try encoder.encode(checks), uniformTypeIdentifier: "public.json")
        report.name = "V184 timeline return measurements"
        report.lifetime = .keepAlways
        add(report)

        app.buttons["closeCareerJournal"].tap()
        close(app)
        app.buttons["managementTab-home"].tap()
        XCTAssertEqual(status(app), homeBefore)
    }

    @MainActor func testV184CareerJournalReturnsFromScrolledTrainingAttempts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let session = ProcessInfo.processInfo.environment["BM_V184_RESULT_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-management-career-verification", "-management-single-role-verification",
                               "-management-reduced-motion-verification", "-v183-result-journal", "-v56-disk-session", session,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60))
        app.buttons["managementLargeMenu"].tap()
        app.buttons["managementMenu-player"].tap()
        let records = app.buttons["facility-records"]
        reveal(records, app)
        records.tap()
        let entry = app.buttons["playerOpenCareerJournal"]
        reveal(entry, app)
        entry.tap()

        let list = app.scrollViews["careerJournalList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let filter = app.buttons["careerJournalFilter-training"]
        filter.tap()
        XCTAssertTrue(filter.isSelected)
        XCTAssertEqual(app.staticTexts["careerJournalCount"].label, "2건")
        let row = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "careerJournalEvent-training/", ":2026-04-03")).firstMatch
        for _ in 0..<4 where !row.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable)
        let rowID = row.identifier
        let before = row.frame.minY - list.frame.minY
        row.tap()

        let detail = app.scrollViews["careerJournalTrainingScroll"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let attempts = detail.buttons["careerJournalTrainingAttempts"]
        for _ in 0..<8 where !attempts.isHittable { detail.swipeUp(velocity: .slow) }
        XCTAssertTrue(attempts.isHittable)
        attempts.tap()
        let last = detail.descendants(matching: .any).matching(identifier: "careerJournalTrainingAttempt-5").firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        func lastAttemptIsVisible() -> Bool {
            last.isHittable && detail.frame.contains(last.frame)
        }
        XCTAssertFalse(lastAttemptIsVisible(), "The fifth attempt must start outside the enlarged viewport")
        for _ in 0..<8 where !lastAttemptIsVisible() { detail.swipeUp(velocity: .slow) }
        XCTAssertTrue(lastAttemptIsVisible())
        XCTAssertEqual(last.value as? String, "65")
        capture(app, "V184 training attempts")

        app.buttons["closeCareerJournalDetail"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            filter.isHittable && list.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed)
        XCTAssertTrue(filter.isSelected)
        XCTAssertEqual(app.staticTexts["careerJournalCount"].label, "2건")
        XCTAssertEqual(row.identifier, rowID)
        XCTAssertEqual(row.frame.minY - list.frame.minY, before, accuracy: 1)
    }

    @MainActor func testV185ConnectedCareerFlowResumesAndPaysOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let environment = ProcessInfo.processInfo.environment
        let resumeAtGame = environment["BM_V185_RESUME_AT_GAME"] == "1"
        let resumeAtJournal = environment["BM_V185_RESUME_AT_JOURNAL"] == "1"
        XCTAssertFalse(resumeAtGame && resumeAtJournal, "Choose only one continuation stage")
        let session = resumeAtGame || resumeAtJournal
            ? try XCTUnwrap(environment["BM_V185_SESSION"], "A continuation requires its original QA session")
            : environment["BM_V185_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-management-career-verification", "-management-reduced-motion-verification",
                               "-v185-career-flow", "-v56-disk-session", session]

        func element(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func tap(_ button: XCUIElement, timeout: TimeInterval = 8) {
            XCTAssertTrue(button.waitForExistence(timeout: timeout), button.identifier)
            if !button.isHittable { reveal(button, app) }
            XCTAssertTrue(button.isHittable && button.isEnabled, button.identifier)
            button.tap()
        }
        func waitForLabel(_ value: XCUIElement, containing text: String, timeout: TimeInterval = 12) {
            let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                value.exists && value.label.contains(text)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: timeout), .completed, text)
        }
        func checkpoint(_ name: String) {
            guard environment["BM_V185_STORE_AUDIT"] == "1" else { return }
            let marker = XCTAttachment(string: session)
            marker.name = "V185 store " + name
            marker.lifetime = .keepAlways
            add(marker)
            Thread.sleep(forTimeInterval: 2)
        }
        func launch(on date: String) {
            app.launch()
            let error = app.staticTexts["managementSeedError"]
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30),
                          error.exists ? error.label : "Connected pitcher career must open")
            waitForLabel(element("calendarDate"), containing: date)
        }
        func restart(on date: String) {
            app.terminate()
            launch(on: date)
        }
        let gameEntry = app.buttons["openCareerGame"]
        let attempt = app.buttons["trainingAttempt"]
        let next = app.buttons["trainingNext"]
        let autoPrepare = app.switches["trainingControlAutoPrepare"]
        let autoPending = element("trainingControlAutoPrepareStatus")
        let trainingSaved = app.staticTexts["trainingResultStored"]

        func openSavedTraining() {
            tap(app.buttons["managementTab-training"])
            tap(app.buttons["roomPrimary"])
        }
        func ready(at round: Int) {
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"),
                                                   object: attempt)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
            waitForLabel(element("trainingProgress"), containing: "\(round) / 5")
        }
        func pitchInTraining() {
            tap(attempt)
            XCTAssertTrue(next.waitForExistence(timeout: 12))
        }
        func fatigue(_ value: String) throws -> Int {
            let range = try XCTUnwrap(value.range(of: "[0-9]+", options: .regularExpression))
            return try XCTUnwrap(Int(value[range]))
        }

        func verifyJournal(expectedScore: String) {
            tap(app.buttons["managementTab-player"])
            tap(app.buttons["facility-records"])
            tap(app.buttons["playerOpenCareerJournal"])
            let list = app.scrollViews["careerJournalList"]
            XCTAssertTrue(list.waitForExistence(timeout: 10))
            waitForLabel(app.staticTexts["careerJournalCount"], containing: "4건")
            for (filter, kind, count, dates) in [("game", "match", 1, ["2026-05-01"]),
                                                 ("training", "training", 1, ["2026-04-27"]),
                                                 ("scout", "scouting", 2, ["2026-04-29", "2026-04-01"])] {
                tap(app.buttons["careerJournalFilter-" + filter])
                waitForLabel(app.staticTexts["careerJournalCount"], containing: "\(count)건")
                let rows = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "careerJournalEvent-" + kind + "/"))
                XCTAssertEqual(rows.count, count)
                XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.identifier)).count, count)
                for date in dates {
                    XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "careerJournalDate-" + date).count, 1)
                }
                if filter == "game" {
                    tap(rows.firstMatch)
                    let details = app.scrollViews["careerJournalMatchScroll"]
                    XCTAssertTrue(details.waitForExistence(timeout: 8))
                    let date = element("careerJournalDetailDate")
                    XCTAssertTrue(date.waitForExistence(timeout: 8))
                    XCTAssertEqual(date.value as? String, dates[0])
                    XCTAssertEqual(element("gameFinalScore").label, expectedScore)
                    tap(app.buttons["closeCareerJournalDetail"])
                    XCTAssertTrue(list.waitForExistence(timeout: 8))
                }
            }
            tap(app.buttons["careerJournalFilter-all"])
            waitForLabel(app.staticTexts["careerJournalCount"], containing: "4건")
        }


        func finishJournal(expectedScore: String) {
            let completedHome = status(app)
            verifyJournal(expectedScore: expectedScore)
            checkpoint("journal-read")
            capture(app, "V185 journal unique completed records")
            restart(on: "5월 1일")
            XCTAssertEqual(status(app), completedHome)
            verifyJournal(expectedScore: expectedScore)
            checkpoint("final-relaunch")
        }

        if resumeAtJournal {
            let expectedScore = try XCTUnwrap(environment["BM_V185_EXPECTED_FINAL_SCORE"], "The completed score must come from the original QA session")
            launch(on: "5월 1일")
            XCTAssertEqual(try fatigue(status(app)[1]), 37)
            finishJournal(expectedScore: expectedScore)
            return
        }

        if resumeAtGame {
            launch(on: "5월 1일")
        } else {
            launch(on: "4월 27일")
            let initialHome = status(app)
            checkpoint("training-before")
            tap(app.buttons["managementTab-training"])
            tap(app.buttons["facility-physical"])
            selectAbilityTraining("control", app)
            tap(app.buttons["openTraining"])
            tap(app.buttons["startTraining"])
            ready(at: 1)
            pitchInTraining()
            XCTAssertTrue(next.label.contains("2/5"), next.label)
            XCTAssertFalse(autoPending.exists)
            reveal(autoPrepare, app)
            XCTAssertTrue(autoPrepare.isHittable)
            XCTAssertEqual(autoPrepare.value as? String, "0")
            autoPrepare.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertTrue(autoPending.waitForExistence(timeout: 2))
            ready(at: 2)
            let extraAttempt = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: next)
            extraAttempt.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [extraAttempt], timeout: 3.5), .completed)
            pitchInTraining()
            checkpoint("training-partial")
            restart(on: "4월 27일")
            XCTAssertEqual(Array(status(app).prefix(2)), Array(initialHome.prefix(2)))
            XCTAssertEqual(status(app)[2], "훈련 이어하기")
            openSavedTraining()
            ready(at: 3)
            XCTAssertFalse(autoPending.exists)
            checkpoint("training-restored")
            capture(app, "V185 training restored third attempt")
            for round in 3...5 {
                ready(at: round)
                pitchInTraining()
                if round == 5 { XCTAssertEqual(next.label, "세트 결산 보기") }
                tap(next)
            }
            XCTAssertTrue(trainingSaved.waitForExistence(timeout: 10))
            let trainingResult = [element("trainingGrowth").label, element("trainingFatigue").label]
            XCTAssertFalse(trainingResult.contains(where: \.isEmpty))
            checkpoint("training-completed")
            capture(app, "V185 completed control training")
            restart(on: "4월 27일")
            XCTAssertEqual(try fatigue(status(app)[1]), min(100, try fatigue(initialHome[1]) + 6))
            XCTAssertEqual(status(app)[2], "행동 0/1")
            openSavedTraining()
            XCTAssertTrue(trainingSaved.waitForExistence(timeout: 10))
            XCTAssertEqual([element("trainingGrowth").label, element("trainingFatigue").label], trainingResult)
            XCTAssertFalse(attempt.exists)
            checkpoint("training-reopened")
            close(app)
            tap(app.buttons["managementTab-home"])

            func startObservationAdvance() {
                tap(app.buttons["advanceOffDays"])
                tap(app.buttons["calendarAdvanceGoalObservation"])
            }
            let receiptStop = app.staticTexts["calendarReceiptStop"]
            let receiptDate = app.staticTexts["calendarReceiptDate"]
            tap(app.buttons["facility-calendar"])
            startObservationAdvance()
            waitForLabel(app.staticTexts["transitionDate"], containing: "2026.04.28")
            XCTAssertFalse(receiptStop.exists)
            checkpoint("schedule-partial")
            capture(app, "V185 calendar mid-batch saved day")
            restart(on: "4월 28일")
            checkpoint("schedule-partial-restored")
            tap(app.buttons["facility-calendar"])
            startObservationAdvance()
            waitForLabel(receiptStop, containing: "관찰일")
            waitForLabel(receiptDate, containing: "4월 29일")
            waitForLabel(app.staticTexts["calendarReceiptTotals"], containing: "완료 1일 · 자동 휴식 1회")
            checkpoint("schedule-observation")
            capture(app, "V185 calendar resumed to observation")
            tap(app.buttons["calendarProgressOpenObservation"])
            waitForLabel(app.staticTexts["scoutFrozenDate"], containing: "4월 29일")
            restart(on: "4월 29일")
            tap(app.buttons["facility-calendar"])
            startObservationAdvance()
            waitForLabel(receiptStop, containing: "경기일")
            waitForLabel(receiptDate, containing: "5월 1일")
            waitForLabel(app.staticTexts["calendarReceiptGoal"], containing: "5월 27일")
            waitForLabel(app.staticTexts["calendarReceiptTotals"], containing: "완료 2일 · 자동 휴식 2회")
            checkpoint("schedule-arrived")
            capture(app, "V185 calendar stops before next observation for game")
            tap(app.buttons["calendarProgressOpenMatch"])
            XCTAssertTrue(gameEntry.waitForExistence(timeout: 8))
            XCTAssertFalse(gameEntry.isEnabled)
            restart(on: "5월 1일")
            checkpoint("schedule-restored")

            tap(app.buttons["clubhouse-rest"])
            tap(app.buttons["confirmRest"])
            tap(app.buttons["restDone"])
        }
        XCTAssertEqual(status(app)[2], "행동 0/1", "May 1 rest must already be saved")

        let automatic = app.buttons["gameAutomatic"]
        let gameSaved = element("gameResultSaved")
        let boardIDs = ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
        let resultIDs = ["gameFinalScore", "gameResultFatigue", "gameAbilityXP", "gameAnnualAbilityXP"]
        func labels(_ ids: [String]) -> [String] {
            ids.map { id in
                let value = element(id)
                XCTAssertTrue(value.waitForExistence(timeout: 8), id)
                XCTAssertFalse(value.label.isEmpty, id)
                return value.label
            }
        }
        func openGame(preparing: Bool) {
            tap(app.buttons["homeTodayAction"])
            tap(gameEntry)
            if preparing {
                tap(app.buttons["opponentTab-plan"])
                tap(app.buttons["confirmGamePlan"])
            }
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"),
                                                   object: automatic)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 40), .completed)
        }

        let matchDayHome = status(app)
        openGame(preparing: true)
        let firstPitch = labels(boardIDs)
        checkpoint("match-before")
        tap(automatic)
        let nextInning = app.buttons["gameAutomaticNextAppearance"]
        waitForLabel(nextInning, containing: "다음 내 등판 이닝까지")
        tap(nextInning)
        waitForLabel(app.staticTexts["gameAutomaticBoundary"], containing: "첫 투구 대기", timeout: 30)
        let inningBoundary = labels(boardIDs)
        XCTAssertNotEqual(inningBoundary[0], firstPitch[0])
        XCTAssertEqual(inningBoundary[1], "B 0 S 0 O 0")
        XCTAssertNotEqual(inningBoundary[3], firstPitch[3])
        XCTAssertFalse(gameSaved.exists)
        checkpoint("match-partial")
        capture(app, "V185 match saved next pitching inning")
        restart(on: "5월 1일")
        XCTAssertEqual(status(app), matchDayHome)
        openGame(preparing: false)
        XCTAssertEqual(labels(boardIDs), inningBoundary)
        XCTAssertFalse(gameSaved.exists)
        checkpoint("match-restored")
        tap(automatic)
        tap(app.buttons["진행하고 결과 저장"])
        XCTAssertTrue(gameSaved.waitForExistence(timeout: 90))
        let matchResult = labels(resultIDs)
        checkpoint("match-completed")
        capture(app, "V185 match completed once")

        tap(app.buttons["openMatchHighlights"])
        let highlights = app.scrollViews["matchHighlightsList"]
        XCTAssertTrue(highlights.waitForExistence(timeout: 10))
        let highlightRows = highlights.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matchHighlight-"))
        func replay(_ category: String, required: Bool) {
            let filter = app.buttons["matchHighlightsFilter-" + category]
            tap(filter)
            let count = app.staticTexts["matchHighlightsCount"].label
            if !required, count == "0개" { return }
            let row = highlightRows.firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            let rowID = row.identifier
            let beforeY = row.frame.midY - highlights.frame.minY
            tap(row)
            XCTAssertTrue(app.staticTexts["matchHighlightReplayFinished"].waitForExistence(timeout: 45))
            capture(app, "V185 highlight replay completed " + category)
            tap(app.buttons["closeMatchHighlightReplay"])
            XCTAssertTrue(highlights.waitForExistence(timeout: 10))
            XCTAssertTrue(filter.isSelected)
            XCTAssertEqual(app.staticTexts["matchHighlightsCount"].label, count)
            let returned = highlights.buttons[rowID]
            XCTAssertTrue(returned.isHittable)
            XCTAssertEqual(returned.frame.midY - highlights.frame.minY, beforeY, accuracy: 2)
        }
        replay("field", required: true)
        replay("homeRun", required: false)
        tap(app.buttons["closeMatchHighlights"])
        XCTAssertEqual(labels(resultIDs), matchResult)
        checkpoint("highlights-replayed")
        restart(on: "5월 1일")
        finishJournal(expectedScore: matchResult[0])
    }
}

extension ManagementDetailFlowTests {
    @MainActor func testV201ExportAndValidationFailuresOpenTheCorrectPickerAndKeepCareer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for scenario in ["export", "verify"] {
            app.terminate()
            app.launchArguments = ["-management-career-verification", "-save-protection-verification",
                                   "-save-feedback-failure", scenario]
            app.launch()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
            let before = status(app)
            let settings = app.buttons["clubhouse-settings"]
            revealLocationChoice(settings, app); settings.tap()
            XCTAssertTrue(app.staticTexts["saveFailureTitle"].waitForExistence(timeout: 15))
            let retry = app.buttons["saveFailureRetry"]
            reveal(retry, app)
            XCTAssertEqual(retry.label, scenario == "export" ? "저장 위치 다시 선택" : "다른 백업 선택")
            XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
            capture(app, "V201-" + scenario + "-failure")
            retry.tap()
            let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "취소"])).firstMatch
            if !cancel.waitForExistence(timeout: 3) {
                let back = app.navigationBars.buttons["BackButton"]
                XCTAssertTrue(back.exists); back.tap()
            }
            XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
            XCTAssertTrue(app.staticTexts["saveProtectionMessage"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["saveFailureTitle"].exists)
            app.buttons["closeSettings"].tap()
            XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 10))
            XCTAssertEqual(status(app), before)
        }
    }

    @MainActor func testV201RestoreFailureRequiresConfirmationAndReopensTheRestoredCareerOnce() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-save-protection-verification",
                               "-v56-disk-session", UUID().uuidString, "-save-feedback-failure", "restore"]
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        let before = status(app)
        let settings = app.buttons["clubhouse-settings"]
        revealLocationChoice(settings, app); settings.tap()
        let restore = app.buttons["confirmRestoreSave"]
        XCTAssertTrue(restore.waitForExistence(timeout: 15)); reveal(restore, app); restore.tap()
        app.buttons["전체 복원"].tap()
        let title = app.staticTexts["saveFailureTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        XCTAssertEqual(title.label, "기기 저장 공간이 부족해요")
        let retry = app.buttons["saveFailureRetry"]
        reveal(retry, app); XCTAssertEqual(retry.label, "복원 다시 확인")
        capture(app, "V201-restore-write-failure")
        retry.tap()
        XCTAssertTrue(app.buttons["전체 복원"].waitForExistence(timeout: 5))
        app.buttons["취소"].tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); reveal(retry, app); retry.tap()
        app.buttons["전체 복원"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15))
        XCTAssertEqual(status(app), before)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        XCTAssertEqual(status(app), before)
        capture(app, "V201-restored-career-after-relaunch")
    }

    @MainActor func testV201CleanupFailureRetriesOnlyThePreparedCopyAndCloses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-save-protection-verification",
                               "-save-feedback-failure", "cleanup"]
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        let before = status(app)
        let settings = app.buttons["clubhouse-settings"]
        revealLocationChoice(settings, app); settings.tap()
        XCTAssertTrue(app.buttons["confirmRestoreSave"].waitForExistence(timeout: 15))
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.staticTexts["saveFailureTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmRestoreSave"].isEnabled)
        let retry = app.buttons["saveFailureRetry"]
        reveal(retry, app); XCTAssertEqual(retry.label, "정리 다시 시도")
        capture(app, "V201-discarded-copy-cleanup-failure")
        retry.tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 10))
        XCTAssertEqual(status(app), before)
    }

    @MainActor func testV201FailureRetryRemainsReachableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-management-career-verification", "-save-protection-verification",
                               "-save-feedback-failure", "verify", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 30))
        let settings = app.buttons["clubhouse-settings"]
        revealLocationChoice(settings, app); settings.tap()
        let retry = app.buttons["saveFailureRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15)); revealLocationChoice(retry, app)
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertLessThanOrEqual(retry.frame.maxX, app.frame.maxX)
        capture(app, "V201-largest-text-failure-retry")
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 10))
    }
}


extension ManagementDetailFlowTests {
    @MainActor func testV201LocalFilesBackupRoundTripUsesIsolatedCareerOnly() {
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
        let unique = "BM-QA-V201-" + String(UUID().uuidString.prefix(8))
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50)); name.typeText(unique)
        XCTAssertTrue((name.value as? String ?? "").hasPrefix(unique))
        save.tap()
        let exported = app.staticTexts["saveProtectionMessage"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "백업 내보내기 완료"), object: exported)], timeout: 15), .completed)
        capture(app, "V201-local-files-exported")
        let importing = app.buttons["importSave"]; reveal(importing, app); importing.tap()
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["둘러보기"]
        XCTAssertTrue(browse.waitForExistence(timeout: 8)); browse.tap()
        let localFolder = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["나의 iPhone", "On My iPhone"])).firstMatch
        XCTAssertTrue(localFolder.waitForExistence(timeout: 8)); localFolder.tap()
        let search = app.searchFields.matching(NSPredicate(format: "label IN %@", ["검색", "Search"])).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText(unique)
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", unique)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        for _ in 0..<5 where file.frame.maxY > app.tabBars["DOC.browsingModeTabBar"].frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(file.isHittable); file.tap()
        let restore = app.buttons["confirmRestoreSave"]; XCTAssertTrue(restore.waitForExistence(timeout: 15)); reveal(restore, app)
        capture(app, "V201-local-files-verified")
        restore.tap(); XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 5)); app.buttons["취소"].tap(); XCTAssertTrue(restore.exists)
        restore.tap(); app.buttons["전체 복원"].tap()
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 15)); XCTAssertEqual(status(app), before)
        capture(app, "V201-local-files-restored")
    }
}
