import XCTest
import Foundation

/// 확정된 선수모드 인플레이를 별도 QA 저장에서만 인수한다.
final class InplayAcceptanceFlowTests: XCTestCase {
    @MainActor func testP05P07SavedPitchReplayRestoresCurrentGameWithoutWriting() throws {
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        app.launchArguments = Scenario.gameArguments(session: "B005B007-2026-4124-8000-000000000009", pitcher: false)
        app.launch()
        Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
        Scenario.tap(app, "gameInput-watch"); app.buttons["battingTouchSurface"].tap()
        XCTAssertTrue(app.buttons["pitchEventContinue"].waitForExistence(timeout: 40))
        let after = Scenario.element(app, "pitchEventAfterState").label
        Scenario.tap(app, "pitchEventContinue")
        let fields = ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
        let current = Scenario.labels(app, fields)
        Scenario.tap(app, "gamePlaybackMenu"); Scenario.tap(app, "replayLastPitchEvent")
        XCTAssertTrue(Scenario.element(app, "inplayFieldStage").waitForExistence(timeout: 10))
        XCTAssertFalse(Scenario.element(app, "pitchEventAfterState").exists)
        XCTAssertTrue(app.buttons["pitchEventContinue"].waitForExistence(timeout: 40))
        XCTAssertEqual(Scenario.element(app, "pitchEventAfterState").label, after)
        Scenario.capture(app, name: "P05-P07 saved HBP replay source state", test: self)
        Scenario.tap(app, "pitchEventContinue")
        XCTAssertEqual(Scenario.labels(app, fields), current)
        app.terminate(); app.launch()
        Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
        XCTAssertEqual(Scenario.labels(app, fields), current)
    }

    @MainActor func testP06HitByPitchBatterNormalEntry() throws { try runP05P07NormalPitchEvents(cases: [0]) }

    @MainActor func testP07UncaughtThirdBatterNormalEntry() throws { try runP05P07NormalPitchEvents(cases: [2]) }

    @MainActor func testP07UncaughtThirdPitcherNormalEntry() throws { try runP05P07NormalPitchEvents(cases: [3]) }

    @MainActor func testP07WildPitchBatterNormalEntry() throws { try runP05P07NormalPitchEvents(cases: [4]) }

    @MainActor func testP07WildPitchPitcherNormalEntry() throws { try runP05P07NormalPitchEvents(cases: [5]) }

    @MainActor func testP07PassedBallBatterNormalEntry() throws { try runP05P07NormalPitchEvents(cases: [6]) }

    @MainActor private func runP05P07NormalPitchEvents(cases: Set<Int>) throws {
        executionTimeAllowance = 1_800
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        var audits: [[String: Any]] = []
        // 준비 자료는 규칙 테스트가 별도 UUID 저장에 쓴 투구 직전 상태다. UI에서는 일반 조작만 사용한다.
        for (kindIndex, kind) in ["hbp", "third", "wild", "passed"].enumerated() {
            for roleIndex in 0..<2 {
                let pitcher = roleIndex == 1
                guard cases.contains(kindIndex * 2 + roleIndex) else { continue }
                // 정밀 릴리스 시점이 필요한 두 장면은 규칙/네이티브 캡처로 검사하고 일반 터치 인수와 구분한다.
                if pitcher && (kind == "hbp" || kind == "passed") { continue }
                let session = String(format: "B005B007-2026-4124-8000-%012d", kindIndex * 2 + roleIndex + 1)
                let args = Scenario.gameArguments(session: session, pitcher: pitcher)
                app.launchArguments = args + ["-qa-full-career-root"]
                app.launch(); Scenario.waitHome(app)
                let homeBefore = Scenario.homeState(app)
                Scenario.openGame(app)
                Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
                Scenario.capture(app, name: "P05-P07 \(kind) \(pitcher ? "pitcher" : "batter") before normal input", test: self)
                if pitcher {
                    let pitch = app.buttons["gamePitch"]
                    let point = pitch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    point.tap(); point.tap()
                } else {
                    Scenario.tap(app, "gameInput-watch")
                    app.buttons["battingTouchSurface"].tap()
                }
                let stage = Scenario.element(app, "inplayFieldStage")
                XCTAssertTrue(stage.waitForExistence(timeout: 25), kind + " must enter the existing infield renderer from normal input")
                let after = Scenario.element(app, "pitchEventAfterState")
                XCTAssertFalse(after.exists, "이동 중에는 확정 루 상황·공식 기록을 먼저 보여주지 않는다.")
                XCTAssertFalse(app.buttons["openPitchCatchComparison"].exists)
                Scenario.capture(app, name: "P05-P07 \(kind) \(pitcher ? "pitcher" : "batter") moving", test: self)
                let next = app.buttons["pitchEventContinue"]
                XCTAssertTrue(next.waitForExistence(timeout: 40))
                let state = after.label
                XCTAssertFalse(state.isEmpty)
                let heading = Scenario.element(app, "pitchEventHeading").label
                if kind == "hbp" { XCTAssertTrue(heading.contains("사구")) }
                if kind == "third" { XCTAssertTrue(heading.contains("삼진")) }
                if kind == "wild" || kind == "passed" {
                    XCTAssertTrue(heading.contains(kind == "wild" ? "폭투" : "포일"), heading)
                    let compare = app.buttons["openPitchCatchComparison"]
                    XCTAssertTrue(compare.waitForExistence(timeout: 10))
                    let scroll = app.scrollViews["inplayFieldScroll"]
                    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
                    var hitAudit: [[String: Any]] = []
                    func audit(_ step: String) {
                        let frame = compare.frame
                        hitAudit.append(["step": step, "enabled": compare.isEnabled, "hittable": compare.isHittable,
                            "frame": String(describing: frame), "scroll": String(describing: scroll.frame),
                            "window": String(describing: app.windows.firstMatch.frame)])
                    }
                    audit("beforeScroll")
                    for step in 0..<4 where !compare.isHittable {
                        scroll.swipeUp(velocity: .slow)
                        // 실제 스크롤과 접근성 좌표 갱신을 확인한 뒤 다음 스와이프를 판단한다.
                        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: compare)
                        _ = XCTWaiter.wait(for: [reachable], timeout: 1)
                        audit("scroll-\(step + 1)")
                    }
                    try Scenario.attach(hitAudit, name: "P07 comparison hit audit", test: self)
                    if !compare.isHittable {
                        let tree = XCTAttachment(string: app.debugDescription); tree.name = "P07 live comparison hit hierarchy"; tree.lifetime = .keepAlways; add(tree)
                        Scenario.capture(app, name: "P07 live comparison hit area", test: self)
                    }
                    // iOS 27의 SwiftUI 행은 AX hit point가 없어도 중앙 터치가 전달될 수 있다.
                    // 실제 화면 안의 44pt 영역을 확인하고, 시트가 열린 결과로 터치 성공을 검증한다.
                    let visibleFrame = compare.frame
                    XCTAssertTrue(compare.isEnabled)
                    XCTAssertTrue(scroll.frame.contains(visibleFrame), "기록 행 전체가 스크롤 가시 영역에 있어야 한다.")
                    XCTAssertGreaterThanOrEqual(visibleFrame.height, 44)
                    compare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    XCTAssertTrue(Scenario.element(app, "pitchCatchTimeline").waitForExistence(timeout: 10))
                    Scenario.capture(app, name: "P05-P07 \(kind) \(pitcher ? "pitcher" : "batter") catch comparison", test: self)
                    app.sliders["pitchCatchTimeline"].adjust(toNormalizedSliderPosition: 0.8)
                    Scenario.tap(app, "closePitchCatchComparison")
                    let returned = after.waitForExistence(timeout: 10)
                    if !returned {
                        let tree = XCTAttachment(string: app.debugDescription); tree.name = "P07 after comparison close hierarchy"; tree.lifetime = .keepAlways; add(tree)
                        Scenario.capture(app, name: "P07 after comparison close", test: self)
                    }
                    XCTAssertTrue(returned, "비교를 닫으면 같은 인플레이 기록을 다시 읽을 수 있어야 한다.")
                    XCTAssertEqual(after.label, state, "비교 닫기는 같은 확정 기록으로 돌아간다.")
                    XCTAssertEqual(Scenario.element(app, "fieldReplayPhase").label, "플레이 완료", "읽기 전용 비교를 닫아도 이동 연출을 다시 시작하지 않는다.")
                }
                Scenario.capture(app, name: "P05-P07 \(kind) \(pitcher ? "pitcher" : "batter") resolved", test: self)
                Scenario.tap(app, "inplayReplayAgain")
                XCTAssertFalse(after.exists, "다시 보기에서도 이동 완료 전에는 결과를 숨긴다.")
                XCTAssertTrue(next.waitForExistence(timeout: 40))
                XCTAssertEqual(after.label, state)
                Scenario.tap(app, "pitchEventContinue")
                Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 15)
                let fields = ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
                let saved = Scenario.labels(app, fields)
                app.terminate(); app.launch(); Scenario.waitHome(app)
                XCTAssertEqual(Scenario.homeState(app), homeBefore)
                Scenario.openGame(app)
                XCTAssertEqual(Scenario.labels(app, fields), saved)
                if kind != "hbp" && !(kind == "third" && pitcher) {
                    audits.append(["session": session, "kind": kind, "role": pitcher ? "pitcher" : "batter",
                        "after": state, "reopened": saved, "scope": "normal input, replay, comparison if credited, resume; completion in HBP batter and third pitcher cases"])
                    app.terminate(); continue
                }
                Scenario.tap(app, "gameAutomatic"); Scenario.tap(app, "진행하고 결과 저장")
                XCTAssertTrue(Scenario.element(app, "gameResultSaved").waitForExistence(timeout: 90))
                let resultFields = ["careerGameFinished", "gameFinalScore", "gameResultFatigue", "gameAbilityXP"]
                let result = Scenario.labels(app, resultFields)
                Scenario.tap(app, "gameReturnHome"); Scenario.waitHome(app)
                let completedHome = Scenario.homeState(app)
                app.terminate(); app.launch(); Scenario.waitHome(app)
                XCTAssertEqual(Scenario.homeState(app), completedHome)
                Scenario.openGame(app, completed: true)
                XCTAssertEqual(Scenario.labels(app, resultFields), result)
                audits.append(["session": session, "kind": kind, "role": pitcher ? "pitcher" : "batter",
                    "after": state, "reopened": saved, "result": result, "completedHome": completedHome])
                app.terminate()
            }
        }
        try Scenario.attach(audits, name: "P05-P07 normal input replay comparison resume one-result", test: self)
    }

    @MainActor func testP04HistoryLineupStyleLiveCompletedArchivedAndResumeBothRoles() throws {
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        for pitcher in [false, true] {
            let role = pitcher ? "pitcher" : "batter"
            let direct = Scenario.gameArguments(session: UUID().uuidString, pitcher: pitcher)
            app.launchArguments = direct + ["-qa-prepare-inputs", pitcher ? "16" : "5"]
            app.launch()
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
            app.terminate()
            app.launchArguments = direct + ["-qa-full-career-root"]
            app.launch(); Scenario.waitHome(app); Scenario.openGame(app)
            let liveFields = ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
            let before = Scenario.labels(app, liveFields)
            Scenario.tap(app, "gamePlaybackMenu"); Scenario.tap(app, "경기 계획·출전 선수")
            Scenario.tap(app, "openGameHistory")
            XCTAssertTrue(Scenario.element(app, "gameHistoryContext").waitForExistence(timeout: 10))
            XCTAssertTrue(Scenario.element(app, "gameHistoryCount").label.contains("타석"))
            let plate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gameHistoryDisclosure-")).firstMatch
            XCTAssertTrue(plate.waitForExistence(timeout: 10))
            Scenario.reveal(plate, app: app); plate.tap()
            XCTAssertTrue(app.staticTexts["타석 전"].firstMatch.waitForExistence(timeout: 5))
            Scenario.capture(app, name: "P04 history C \(role) live", test: self)
            Scenario.tap(app, "gameRecordsLineup")
            XCTAssertTrue(Scenario.element(app, "gameLineupComparison").waitForExistence(timeout: 5), "타순과 이력은 같은 경기 정보 시트에서 전환한다.")
            Scenario.tap(app, "openGameHistory")
            XCTAssertTrue(app.staticTexts["타석 전"].firstMatch.waitForExistence(timeout: 5), "탭 전환 뒤 펼친 타석을 유지한다.")
            Scenario.tap(app, "closeGameDetails")
            XCTAssertEqual(Scenario.labels(app, liveFields), before)
            Scenario.tap(app, "gamePlaybackMenu"); Scenario.tap(app, "경기 계획·출전 선수")
            XCTAssertTrue(Scenario.element(app, "gameHistoryContext").waitForExistence(timeout: 5), "같은 경기 시트 재열기는 선택한 이력 탭을 유지한다.")
            XCTAssertTrue(app.staticTexts["타석 전"].firstMatch.waitForExistence(timeout: 5), "시트 재열기에도 펼친 타석을 유지한다.")
            Scenario.capture(app, name: "P04 bundle \(role) records reopened", test: self)
            Scenario.tap(app, "closeGameDetails")
            Scenario.tap(app, "gameAutomatic"); Scenario.tap(app, "진행하고 결과 저장")
            XCTAssertTrue(Scenario.element(app, "gameResultSaved").waitForExistence(timeout: 90))
            Scenario.capture(app, name: "P04 bundle \(role) result report", test: self)
            let resultFields = ["careerGameFinished", "gameFinalScore", "gameResultFatigue", "gameAbilityXP"]
                + (pitcher ? ["gameResult-innings", "gameResult-pitchingStrikeouts"] : ["gameResult-atBats", "gameResult-hits"])
            let result = Scenario.labels(app, resultFields)
            Scenario.tap(app, "openGameHistory")
            XCTAssertTrue(Scenario.element(app, "gameHistoryContext").waitForExistence(timeout: 10))
            XCTAssertTrue(Scenario.element(app, "gameHistoryContext").label.contains("종료 경기"))
            let count = Scenario.element(app, "gameHistoryCount").label
            Scenario.capture(app, name: "P04 history C \(role) completed", test: self)
            Scenario.tap(app, "closeGameHistory")
            XCTAssertEqual(Scenario.labels(app, resultFields), result)
            Scenario.tap(app, "gameReturnHome"); Scenario.waitHome(app)
            let home = Scenario.homeState(app)
            app.terminate(); app.launch(); Scenario.waitHome(app)
            XCTAssertEqual(Scenario.homeState(app), home)
            Scenario.openGame(app, completed: true)
            XCTAssertEqual(Scenario.labels(app, resultFields), result)
            Scenario.tap(app, "openGameHistory")
            XCTAssertTrue(Scenario.element(app, "gameHistoryCount").waitForExistence(timeout: 10))
            XCTAssertEqual(Scenario.element(app, "gameHistoryCount").label, count)
            Scenario.tap(app, "closeGameHistory")
            Scenario.tap(app, "gameReturnHome"); Scenario.waitHome(app)
            Scenario.chooseTab(app, "player"); Scenario.tap(app, "facility-records")
            Scenario.tap(app, "playerOpenCareerJournal")
            Scenario.tap(app, "careerJournalFilter-game")
            let archived = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "careerJournalEvent-match/")).firstMatch
            XCTAssertTrue(archived.waitForExistence(timeout: 10)); Scenario.reveal(archived, app: app); archived.tap()
            let scroll = app.scrollViews["careerJournalMatchScroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 10))
            XCTAssertEqual(Scenario.labels(app, resultFields), result, "지난 경기 성적표도 완료 원문의 성적·XP·피로를 읽는다.")
            Scenario.capture(app, name: "P04 bundle \(role) archived report", test: self)
            let history = app.buttons["openGameHistory"]
            for _ in 0..<8 where !history.isHittable { scroll.swipeUp() }
            XCTAssertTrue(history.isHittable); history.tap()
            XCTAssertTrue(Scenario.element(app, "gameHistoryCount").waitForExistence(timeout: 10))
            XCTAssertEqual(Scenario.element(app, "gameHistoryCount").label, count)
            Scenario.capture(app, name: "P04 history C \(role) archived", test: self)
            Scenario.tap(app, "closeGameHistory")
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            app.terminate(); app.launch(); Scenario.waitHome(app)
            XCTAssertEqual(Scenario.homeState(app), home)
            app.terminate()
        }
    }

    @MainActor func testP04LineupComparisonBothRolesReadOnlyAndResume() throws {
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        for pitcher in [false, true] {
            let role = pitcher ? "pitcher" : "batter"
            app.launchArguments = Scenario.gameArguments(session: UUID().uuidString, pitcher: pitcher)
            app.launch()
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
            let fields = ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
            let before = Scenario.labels(app, fields)
            func openInformation() {
                Scenario.tap(app, "gamePlaybackMenu")
                Scenario.tap(app, "경기 계획·출전 선수")
                XCTAssertTrue(Scenario.element(app, "gameLineupComparison").waitForExistence(timeout: 10))
            }
            openInformation()
            let context = Scenario.element(app, "gameLineupContext").label
            let home = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gameLineup-home-"))
            let away = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gameLineup-away-"))
            XCTAssertEqual(home.count, 9); XCTAssertEqual(away.count, 9)
            let firstHome = home.element(boundBy: 0).label
            let firstAway = away.element(boundBy: 0).label
            let current = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "gameLineup-", "현재 타자"))
            XCTAssertEqual(current.count, 1)
            XCTAssertTrue(app.buttons["gameNPCFielders"].exists)
            Scenario.capture(app, name: "P04 C \(role) lineup top", test: self)
            app.scrollViews["gameInformationScroll"].swipeUp()
            Scenario.capture(app, name: "P04 C \(role) lineup scroll", test: self)
            Scenario.tap(app, "closeGameDetails")
            XCTAssertEqual(Scenario.labels(app, fields), before)
            app.terminate(); app.launch()
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
            XCTAssertEqual(Scenario.labels(app, fields), before)
            openInformation()
            XCTAssertEqual(Scenario.element(app, "gameLineupContext").label, context)
            XCTAssertEqual(home.count, 9); XCTAssertEqual(away.count, 9)
            XCTAssertEqual(home.element(boundBy: 0).label, firstHome)
            XCTAssertEqual(away.element(boundBy: 0).label, firstAway)
            Scenario.tap(app, "closeGameDetails")
            XCTAssertEqual(Scenario.labels(app, fields), before)
            app.terminate()
        }
    }

    @MainActor func testP03RunnerDiamondBothRolesReadOnlyAndResume() throws {
        guard ProcessInfo.processInfo.environment["BM_V188_PRO_VENUE_QA"] == "1" else {
            throw XCTSkip("전용 BM-QA 시뮬레이터에 준비한 합성 프로 시즌 저장을 사용합니다.")
        }
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        for pitcher in [false, true] {
            let role = pitcher ? "pitcher" : "batter"
            // 실제 투구로 준비하는 기존 복수 주자 QA를 재사용한다. 판정·저장 경로는 일반 경기와 같다.
            let direct = Scenario.gameArguments(session: UUID().uuidString, pitcher: pitcher)
                + ["-qa-pro-venue", "pro-falcons", pitcher ? "-qa-pro-homer-against" : "-qa-pro-homer-next", "-qa-pro-homer-runs", "3"]
            app.launchArguments = direct; app.launch()
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 90)
            let fields = ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
            let before = Scenario.labels(app, fields)
            let open = app.buttons["openRunnerDetails"]
            Scenario.capture(app, name: "P03 \(role) ready diamond", test: self)
            print("P03 \(role) diamond frame: \(open.frame), enabled: \(open.isEnabled)")
            func openDetails(edge: Bool = false) {
                XCTAssertTrue(open.waitForExistence(timeout: 10)); XCTAssertTrue(open.isEnabled)
                let frame = open.frame, window = app.windows.firstMatch
                XCTAssertGreaterThanOrEqual(frame.width, 44); XCTAssertGreaterThanOrEqual(frame.height, 44)
                XCTAssertTrue(window.frame.contains(frame))
                // AX 메타데이터와 실제 입력을 구분해 버튼의 중앙·가장자리에 물리 탭을 보낸다.
                let x = edge ? frame.maxX - 2 : frame.midX
                window.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: x - window.frame.minX, dy: frame.midY - window.frame.minY)).tap()
                XCTAssertTrue(Scenario.element(app, "runnerDetailsSheet").waitForExistence(timeout: 10))
            }
            openDetails()
            let context = Scenario.element(app, "runnerDetailsContext").label
            let runner = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "타순", "주력")).firstMatch
            XCTAssertTrue(runner.exists)
            Scenario.capture(app, name: "P03 \(role) runner details", test: self)
            Scenario.tap(app, "closeRunnerDetails")
            XCTAssertEqual(Scenario.labels(app, fields), before)
            XCTAssertTrue(open.exists && open.isEnabled)
            app.terminate(); app.launch()
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 90)
            XCTAssertEqual(Scenario.labels(app, fields), before)
            openDetails(edge: true)
            XCTAssertEqual(Scenario.element(app, "runnerDetailsContext").label, context)
            Scenario.tap(app, "closeRunnerDetails")
            if pitcher {
                Scenario.tap(app, "gamePitch")
                XCTAssertTrue(app.buttons["gameRelease"].waitForExistence(timeout: 3))
            } else {
                let surface = app.buttons["battingTouchSurface"]
                Scenario.tap(app, "battingTouchSurface")
                let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    surface.label != "경기장 · 투구 요청" || Scenario.element(app, "careerGameCount").label != before[1]
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed, "구장 위 SwiftUI 타격 입력은 유지한다.")
            }
            app.terminate()
        }
    }

    @MainActor func testP02SubstitutionJournalBothRolesResultsAndResumeReadOnly() throws {
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        for pitcher in [false, true] {
            let role = pitcher ? "pitcher" : "batter"
            let direct = Scenario.gameArguments(session: UUID().uuidString, pitcher: pitcher)
            app.launchArguments = direct
            app.launch()
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
            // 임시 QA 저장만 준비한 뒤 일반 커리어 진입점에서 경기와 결과 복귀를 검증한다.
            app.terminate()
            app.launchArguments = direct + ["-qa-full-career-root"]
            app.launch()
            Scenario.waitHome(app)
            Scenario.openGame(app)
            Scenario.waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
            XCTAssertFalse(app.buttons["openSubstitutionJournal"].exists, "교체 전에는 빈 일지를 끼워 넣지 않는다.")
            Scenario.tap(app, "gameAutomatic")
            Scenario.tap(app, "진행하고 결과 저장")
            XCTAssertTrue(Scenario.element(app, "gameResultSaved").waitForExistence(timeout: 90))
            let resultFields = ["careerGameFinished", "gameFinalScore", "gameResultFatigue"]
            let final = Scenario.labels(app, resultFields)
            Scenario.tap(app, "openSubstitutionJournal")
            XCTAssertTrue(Scenario.element(app, "gameSubstitutionJournal").waitForExistence(timeout: 10))
            let count = Scenario.element(app, "gameSubstitutionCount").label
            XCTAssertFalse(count.isEmpty)
            Scenario.capture(app, name: "P02 \(role) substitution journal", test: self)
            let entry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "나간 선수", "들어온 선수")).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertTrue(entry.label.contains("나간 선수"))
            XCTAssertTrue(entry.label.contains("들어온 선수"))
            Scenario.tap(app, "closeSubstitutionJournal")
            XCTAssertEqual(Scenario.labels(app, resultFields), final)
            Scenario.tap(app, "gameReturnHome")
            Scenario.waitHome(app)
            let home = Scenario.homeState(app)

            app.terminate()
            app.launchArguments = direct + ["-qa-full-career-root"]
            app.launch()
            Scenario.waitHome(app)
            XCTAssertEqual(Scenario.homeState(app), home)
            Scenario.openGame(app, completed: true)
            XCTAssertEqual(Scenario.labels(app, resultFields), final)
            Scenario.tap(app, "openSubstitutionJournal")
            XCTAssertTrue(Scenario.element(app, "gameSubstitutionJournal").waitForExistence(timeout: 10))
            XCTAssertEqual(Scenario.element(app, "gameSubstitutionCount").label, count)
            Scenario.capture(app, name: "P02 \(role) reopened substitution journal", test: self)
            Scenario.tap(app, "closeSubstitutionJournal")
            Scenario.tap(app, "gameReturnHome")
            Scenario.waitHome(app)
            XCTAssertEqual(Scenario.homeState(app), home)
            app.terminate()
        }
    }

    @MainActor func testP08BatterReservationInfoPauseResumeAndReplay() throws {
        try runP08NormalEntry(index: 0, pauseAndRelaunch: true)
    }

    @MainActor func testP08BatterRundownStartsAfterFiveSeconds() throws {
        try runP08NormalEntry(index: 1, pauseAndRelaunch: false)
    }

    @MainActor func testP08PitcherCoachPickoffNormalEntry() throws {
        try runP08NormalEntry(index: 2, pauseAndRelaunch: false)
    }

    @MainActor func testP08LargeTypePreparationActionsStayVisible() throws {
        try runP08NormalEntry(index: 3, pauseAndRelaunch: false)
    }

    @MainActor private func runP08NormalEntry(index: Int, pauseAndRelaunch: Bool) throws {
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        let session = String(format: "B008B008-2026-4124-8000-%012d", index + 1)
        app.launchArguments = Scenario.gameArguments(session: session, pitcher: index == 2) + ["-qa-full-career-root"]
        if index == 3 { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        defer { app.terminate() }
        Scenario.waitHome(app); let homeBefore = Scenario.homeState(app)
        func openPreparedGame() {
            Scenario.chooseTab(app, "game")
            Scenario.tap(app, "facility-analysis"); Scenario.tap(app, "gameSection-schedule")
            Scenario.tap(app, "openCareerGame", timeout: 30)
        }
        openPreparedGame()
        if index != 2 {
            let reservation=app.buttons["reserveSteal"]
            XCTAssertTrue(reservation.waitForExistence(timeout: 15))
            reservation.tap()
            XCTAssertEqual(app.buttons["reserveSteal"].label, "예약 취소")
            if pauseAndRelaunch {
                app.buttons["openRunnerDetails"].tap()
                XCTAssertTrue(app.buttons["closeRunnerDetails"].waitForExistence(timeout: 10))
                Thread.sleep(forTimeInterval: 6)
                XCTAssertFalse(Scenario.element(app, "inplayFieldStage").exists)
                app.buttons["closeRunnerDetails"].tap()
                Scenario.capture(app, name: "P08 preparation after info pause", test: self)
                app.terminate(); app.launch(); Scenario.waitHome(app); openPreparedGame()
                XCTAssertEqual(app.buttons["reserveSteal"].label, "예약 취소", "저장한 예약을 재개한다.")
                Scenario.capture(app, name: "P08 persisted reservation after relaunch", test: self)
                app.buttons["runningNextPitch"].tap()
            }
        } else {
            Scenario.waitEnabled(app.buttons["gamePitch"], app: app, timeout: 30)
            Scenario.capture(app, name: "P08 pitcher before pickoff", test: self)
            Scenario.tap(app, "gamePitch")
        }
        let stage = Scenario.element(app, "inplayFieldStage")
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        if index == 3 { Scenario.tap(app,"inplayJumpField") }
        let summary = Scenario.element(app, "inplayLastPlaySummary")
        if !app.buttons["pitchEventContinue"].exists {
            XCTAssertFalse(summary.exists, "태그·귀루 확정 전에 결과를 공개하지 않는다.")
            Scenario.capture(app, name: "P08 moving \(index)", test: self)
        }
        XCTAssertTrue(app.buttons["pitchEventContinue"].waitForExistence(timeout: 35))
        let result = summary.label
        XCTAssertTrue(result.contains(index == 2 ? "견제" : index == 1 ? "협살" : "도루"), result)
        if index != 3 {
            for id in ["inplayReplayAgain", "pitchEventContinue"] {
                let frame = app.buttons[id].frame
                XCTAssertGreaterThanOrEqual(frame.width, 80, "완료 조작의 글자가 세로로 압축되지 않는다.")
                XCTAssertLessThanOrEqual(frame.height, 68, "기본 글자의 완료 조작은 한 줄을 유지한다.")
            }
        }
        Scenario.capture(app, name: "P08 resolved \(index)", test: self)
        Scenario.tap(app,"inplayReplayAgain")
        XCTAssertTrue(app.buttons["pitchEventContinue"].waitForExistence(timeout: 35))
        XCTAssertEqual(summary.label, result)
        Scenario.tap(app, "pitchEventContinue")
        XCTAssertFalse(stage.waitForExistence(timeout: 2))
        let field = app.buttons["gamePlaybackMenu"]; XCTAssertTrue(field.waitForExistence(timeout: 15))
        Scenario.tap(app, "gamePlaybackMenu"); Scenario.tap(app, "openGameDetails")
        Scenario.capture(app, name: "P08 read only records \(index)", test: self)
        Scenario.tap(app, "closeGameDetails")
        app.terminate(); app.launch(); Scenario.waitHome(app)
        XCTAssertEqual(Scenario.homeState(app), homeBefore)
    }

    @MainActor func testP09NormalPitchInputReplayAndResume() throws { try runP09P10Entry(index:0) }

    @MainActor func testP10FoulNormalPitchInputReplayAndResume() throws { try runP09P10Entry(index:1) }

    @MainActor func testP10GroundRuleDoubleNormalPitchInputReplayAndResume() throws { try runP09P10Entry(index:2) }

    @MainActor func testP10OverthrowLargeTypeNormalPitchInputReplayAndResume() throws { try runP09P10Entry(index:3) }

    @MainActor private func runP09P10Entry(index:Int) throws {
        continueAfterFailure=false
        typealias Scenario=InplayAcceptanceScenario
        let app=XCUIApplication(bundleIdentifier:Scenario.bundleID)
        let session=String(format:"B009B010-2026-4125-8000-%012d",index+1)
        app.launchArguments=Scenario.gameArguments(session:session,pitcher:true)+["-qa-full-career-root"]
        if index == 3 { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch();defer {app.terminate()}
        Scenario.waitHome(app);let home=Scenario.homeState(app)
        Scenario.openGame(app)
        if index == 3,app.buttons["gameJumpToControls"].exists {Scenario.tap(app,"gameJumpToControls")}
        Scenario.waitEnabled(app.buttons["gamePitch"],app:app)
        Scenario.capture(app,name:"P09-P10 ready \(index)",test:self)
        let touch=app.buttons["gamePitch"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        touch.tap();touch.tap()
        let stage=Scenario.element(app,"inplayFieldStage")
        XCTAssertTrue(stage.waitForExistence(timeout:25))
        let next=app.buttons["pitchEventContinue"]
        if !next.exists {Scenario.capture(app,name:"P09-P10 moving \(index)",test:self)}
        XCTAssertTrue(next.waitForExistence(timeout:45))
        let summary=Scenario.element(app,"inplayLastPlaySummary").label
        if index != 3 {
            let top=Scenario.element(app,"inplayLastPlaySummary").frame.minY
            XCTAssertLessThan(app.buttons["inplayReplayAgain"].frame.maxY-top,180,"완료 요약과 조작 사이에 불필요한 빈 공간을 만들지 않는다.")
        } else {
            Scenario.tap(app,"inplayJumpField")
        }
        if index == 1 {XCTAssertTrue(summary.contains("파울"),summary)}
        if index == 2 {XCTAssertTrue(summary.contains("2루타"),summary)}
        if index == 3 {XCTAssertTrue(summary.contains("악송구"),summary)}
        Scenario.capture(app,name:"P09-P10 resolved \(index)",test:self)
        Scenario.tap(app,"inplayReplayAgain")
        XCTAssertTrue(next.waitForExistence(timeout:45))
        XCTAssertEqual(Scenario.element(app,"inplayLastPlaySummary").label,summary)
        Scenario.tap(app,"pitchEventContinue")
        Scenario.waitEnabled(app.buttons["gameAutomatic"],app:app,timeout:20)
        let ids=["careerGameInning","careerGameCount","boardPitchCount"] + (index == 3 ? ["boardTeam-away","boardTeam-home"]:["careerGameScore"])
        let state=Scenario.labels(app,ids)
        app.terminate();app.launch();Scenario.waitHome(app)
        XCTAssertEqual(Scenario.homeState(app),home)
        Scenario.openGame(app);XCTAssertEqual(Scenario.labels(app,ids),state)
        Scenario.capture(app,name:"P09-P10 resumed \(index)",test:self)
        try Scenario.attach(["session":session,"case":index,"summary":summary,"resumed":state,
            "scope":"isolated QA saved abilities; normal menu and pitch input; replay and disk resume"],name:"P09-P10 normal entry audit",test:self)
    }

    @MainActor func testBothRolesInputResumeAndResultOnce() throws {
        continueAfterFailure = false
        try InplayAcceptanceScenario.game(test:self)
    }
}

@MainActor private enum InplayAcceptanceScenario {
    static let bundleID = "dev.bm.career.performanceqa"

    static func game(test: XCTestCase) throws {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        defer { app.terminate() }
        var audits: [[String: Any]] = []
        for pitcher in [false, true] {
            let role = pitcher ? "pitcher" : "batter"
            let session = UUID().uuidString
            let direct = gameArguments(session: session, pitcher: pitcher)
            // 타자는 첫 타석부터 조작해, 준비된 후반 타석만으로 경기가 끝나는 누락을 막는다.
            let preparedInputs = pitcher ? 16 : 0
            app.launchArguments = direct + ["-qa-prepare-inputs", String(preparedInputs)]
            app.launch()
            waitEnabled(app.buttons["gameAutomatic"], app: app, timeout: 60)
            app.terminate()

            // The first direct launch created this UUID store; full-root never needs a fixed fixture.
            let root = direct + ["-qa-full-career-root"]
            app.launchArguments = root
            app.launch()
            waitHome(app)
            let homeBefore = homeState(app)
            openGame(app)
            let inputs = driveToInplay(app, pitcher: pitcher, test: test)
            let live = labels(app, ["careerGameCount", "careerGameScore", "boardPitchCount"])
            app.terminate()
            XCTAssertFalse(app.launchArguments.contains("-qa-prepare-inputs"))
            app.launch()
            waitHome(app)
            XCTAssertEqual(homeState(app), homeBefore, "An unfinished game must not consume another daily action or fatigue.")
            openGame(app)
            XCTAssertEqual(labels(app, ["careerGameCount", "careerGameScore", "boardPitchCount"]), live)
            tap(app, "gameAutomatic")
            tap(app, "진행하고 결과 저장")
            let saved = element(app, "gameResultSaved")
            XCTAssertTrue(saved.waitForExistence(timeout: 90))
            let result = labels(app, ["careerGameFinished", "gameFinalScore", "gameResultFatigue"])
            capture(app, name: "V161 " + role + " completed game", test: test)
            tap(app, "gameReturnHome")
            closeDetail(app)
            chooseTab(app, "home")
            let completedHome = homeState(app)
            let ticket = soleGameTicket(app)
            app.terminate()
            app.launch()
            waitHome(app)
            XCTAssertEqual(homeState(app), completedHome)
            XCTAssertEqual(soleGameTicket(app), ticket, "Relaunch must keep exactly one completed personal-game ticket.")
            openGame(app, completed: true)
            XCTAssertEqual(labels(app, ["careerGameFinished", "gameFinalScore", "gameResultFatigue"]), result)
            XCTAssertFalse(app.buttons["gameAutomatic"].exists)
            tap(app, "gameReturnHome")
            closeDetail(app)
            chooseTab(app, "home")
            XCTAssertEqual(homeState(app), completedHome, "Reopening the result must not pay fatigue or daily action twice.")
            XCTAssertEqual(soleGameTicket(app), ticket)
            audits.append(["role": role, "session": session, "bundle": bundleID,
                           "sessionStore": "live-career-" + session + ".store",
                           "preparedInputs": preparedInputs, "uiInputsUntilInplay": inputs,
                           "resumedState": live, "result": result, "completedHome": completedHome,
                           "singleCompletedTicket": ticket,
                           "scope": "XCTest UI inputs until one inplay, then remaining entire game automatic. No in-app QA autoplay driver or user store."])
            app.terminate()
        }
        try attach(audits, name: "V161 isolated both-role game resume and one-result audit", test: test)
    }

    static func gameArguments(session: String, pitcher: Bool) -> [String] {
        var arguments = ["-live-career-autoplay", "-qa-session", session]
        if pitcher { arguments.append("-qa-pitcher") }
        XCTAssertFalse(arguments.contains("-live-career-performance"))
        return arguments
    }

    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    static func reveal(_ value: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 {
            if value.isHittable { return }
            if value.exists && !value.frame.isEmpty && value.frame.maxY < app.windows.firstMatch.frame.midY {
                app.swipeDown()
            } else { app.swipeUp() }
        }
        for _ in 0..<10 {
            if value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.isHittable, value.identifier)
    }

    static func waitEnabled(_ button: XCUIElement, app: XCUIApplication, timeout: TimeInterval = 30) {
        XCTAssertTrue(button.waitForExistence(timeout: timeout), button.identifier)
        reveal(button, app: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: timeout), .completed, button.identifier)
    }

    static func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 15) {
        let button = app.buttons[id].firstMatch
        waitEnabled(button, app: app, timeout: timeout)
        button.tap()
    }

    static func waitHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["homePlayerName"].waitForExistence(timeout: 60))
        closeDetail(app)
        chooseTab(app, "home")
    }

    static func closeDetail(_ app: XCUIApplication) {
        let close = app.buttons["closeRoomDetail"]
        if close.exists { reveal(close, app: app); close.tap() }
    }

    static func chooseTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons["managementTab-" + name]
        if tab.exists {
            reveal(tab, app: app); tab.tap()
        } else {
            tap(app, "managementLargeMenu")
            tap(app, "managementMenu-" + name)
        }
    }

    static func labels(_ app: XCUIApplication, _ ids: [String]) -> [String] {
        ids.map { id in
            let value = element(app, id)
            XCTAssertTrue(value.waitForExistence(timeout: 15), id)
            // 상태 읽기에 터치 가능 여부를 요구하지 않는다. 불필요한 스와이프로 경기 시트를 닫지 않는다.
            XCTAssertFalse(value.label.isEmpty, id)
            return value.label
        }
    }

    static func homeState(_ app: XCUIApplication) -> [String] {
        labels(app, ["calendarDate", "homeFatigue", "calendarAction"])
    }

    static func openGame(_ app: XCUIApplication, completed: Bool = false) {
        chooseTab(app, "game")
        tap(app, completed ? "facility-gameRecords" : "facility-analysis")
        tap(app, "gameSection-schedule")
        tap(app, "openCareerGame", timeout: 30)
        let plan = app.buttons["opponentTab-plan"]
        if plan.waitForExistence(timeout: 2) {
            tap(app, "opponentTab-plan"); tap(app, "confirmGamePlan")
        }
        XCTAssertTrue(element(app, completed ? "gameResultSaved" : "gameAutomatic").waitForExistence(timeout: 60))
    }

    static func driveToInplay(_ app: XCUIApplication, pitcher: Bool, test: XCTestCase) -> Int {
        let field = element(app, "inplayFieldStage"), homer = element(app, "homeRunStage")
        for index in 0..<24 {
            if app.buttons["finishAfterPitcherChange"].exists { break }
            waitEnabled(app.buttons["gameAutomatic"], app: app)
            if pitcher {
                tap(app, "gamePitch")
                let release = app.buttons["gameRelease"]
                XCTAssertTrue(release.waitForExistence(timeout: 3))
                Thread.sleep(forTimeInterval: 0.9)
                if release.exists && release.isEnabled { release.tap() }
            } else {
                tap(app, index.isMultiple(of: 3) ? "gameInput-bunt" : "gameInput-swing")
                let surface = app.buttons["battingTouchSurface"]
                XCTAssertTrue(surface.waitForExistence(timeout: 10))
                reveal(surface, app: app); surface.tap()
                Thread.sleep(forTimeInterval: 1.0)
                if surface.exists && surface.isHittable { surface.tap() }
            }
            let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.exists || homer.exists }, object: nil)
            if XCTWaiter.wait(for: [appeared], timeout: 4) == .completed {
                capture(app, name: pitcher ? "V161 pitcher actual inplay" : "V161 batter actual inplay", test: test)
                if field.exists {
                    let context=element(app,"inplayContext").label
                    let inning=Int(context.prefix(while:{$0.isNumber}))
                    if let inning,inning < 9 {
                        let score=element(app,"careerGameScore").label
                        for future in (inning+1)...9 {
                            XCTAssertFalse(score.range(of:"\(future)회 [1-9][0-9]*점",options:.regularExpression) != nil,"미래 이닝 득점을 먼저 공개하지 않는다: "+score)
                        }
                    }
                }
                let next=app.buttons["pitchEventContinue"]
                if next.waitForExistence(timeout:35) {tap(app,"pitchEventContinue")}
                let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !field.exists && !homer.exists }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 45), .completed)
                XCTAssertFalse(app.buttons["retryGameInput"].exists)
                return index + 1
            }
        }
        capture(app, name: "V161 missing actual inplay", test: test)
        XCTFail("Current game controls must resolve at least one inplay before automatic completion.")
        return 0
    }

    static func soleGameTicket(_ app: XCUIApplication) -> [String] {
        chooseTab(app, "player")
        tap(app, "facility-records")
        let tickets = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "recentGame-"))
        XCTAssertEqual(tickets.count, 1, "The isolated fresh role must have exactly one completed personal-game record.")
        let ticket = tickets.firstMatch
        XCTAssertTrue(ticket.exists); reveal(ticket, app: app)
        let state = [ticket.identifier, ticket.label] + labels(app, ["homeAnnualAbilityBudget", "homeAbilityXP"])
        closeDetail(app); chooseTab(app, "home")
        return state
    }

    static func capture(_ app: XCUIApplication, name: String, test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; test.add(attachment)
    }

    static func attach(_ value: Any, name: String, test: XCTestCase) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = name; attachment.lifetime = .keepAlways; test.add(attachment)
    }
}

extension InplayAcceptanceFlowTests {
    @MainActor func testV249BothRolesLineupDetailsResumeWithoutChangingGame() throws {
        try v249Details(index: 0, large: false)
        try v249Details(index: 1, large: false)
    }
    @MainActor func testV249LargeTypeLineupDetailsRemainReachable() throws {
        try v249Details(index: 2, large: true)
    }
    @MainActor private func v249Details(index: Int, large: Bool) throws {
        continueAfterFailure = false
        typealias Scenario = InplayAcceptanceScenario
        let app = XCUIApplication(bundleIdentifier: Scenario.bundleID)
        defer { app.terminate() }
        let session = String(format: "B249B249-2026-4125-8000-%012d", index + 1)
        app.launchArguments = Scenario.gameArguments(session: session, pitcher: index == 1) + ["-qa-full-career-root"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); Scenario.waitHome(app); let home = Scenario.homeState(app)
        Scenario.openGame(app)
        let fields = large ? ["careerGameInning", "careerGameCount", "boardTeam-home", "boardTeam-away", "boardPitchCount"]
            : ["careerGameInning", "careerGameCount", "careerGameScore", "boardPitchCount"]
        let game = Scenario.labels(app, fields)
        func openInformation() {
            Scenario.tap(app, "gamePlaybackMenu"); Scenario.tap(app, "경기 계획·출전 선수")
            XCTAssertTrue(Scenario.element(app, "gameLineupComparison").waitForExistence(timeout: 15))
        }
        openInformation()
        for (side, slot) in [("home", 1), ("away", 1), ("home", 9)] {
            let id = "gameLineup-" + side + "-" + String(slot), button = app.buttons[id]
            let scroll = app.scrollViews["gameInformationScroll"]
            for _ in 0..<12 where !button.isHittable {
                if button.exists && button.frame.midY < scroll.frame.minY { scroll.swipeDown(velocity: .slow) }
                else { scroll.swipeUp(velocity: .slow) }
            }
            XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isHittable)
            XCTAssertTrue(button.label.contains(slot == 9 ? "ERA 선두" : side == "home" ? "타율 선두" : "홈런 선두"))
            button.tap()
            XCTAssertTrue(app.buttons["closeLineupPlayerDetail"].waitForExistence(timeout: 10))
            XCTAssertTrue(Scenario.element(app, "gameLineupPlayerDetail").exists)
            Scenario.capture(app, name: "V249 isolated fixture \(index) \(side) slot\(slot) player detail", test: self)
            let detail = app.scrollViews["gameLineupPlayerDetail"]
            let through = Scenario.element(app, "lineupDetailThrough")
            for _ in 0..<8 where !through.isHittable { detail.swipeUp(velocity: .slow) }
            XCTAssertTrue(through.isHittable)
            XCTAssertTrue(through.label.contains("2026-03-31"))
            if slot == 9 { XCTAssertTrue(app.staticTexts["ERA"].exists) }
            Scenario.capture(app, name: "V249 isolated fixture \(index) \(side) slot\(slot) season detail", test: self)
            Scenario.tap(app, "closeLineupPlayerDetail")
            XCTAssertTrue(button.waitForExistence(timeout: 10))
        }
        Scenario.tap(app, "closeGameDetails")
        XCTAssertEqual(Scenario.labels(app, fields), game)
        app.terminate(); app.launch(); Scenario.waitHome(app)
        XCTAssertEqual(Scenario.homeState(app), home)
        Scenario.openGame(app); XCTAssertEqual(Scenario.labels(app, fields), game)
        openInformation()
        XCTAssertTrue(app.buttons["gameLineup-home-1"].label.contains("타율 선두"))
        Scenario.tap(app, "closeGameDetails")
        XCTAssertEqual(Scenario.labels(app, fields), game)
    }
}


extension InplayAcceptanceFlowTests {
    @MainActor func testP12NormalAppealReplayAndResume() throws { try p12Entry(index:0) }
    @MainActor func testP12NormalCorrectionResultAndHistory() throws { try p12Entry(index:1) }
    @MainActor private func p12Entry(index:Int) throws {
        continueAfterFailure=false
        typealias Scenario=InplayAcceptanceScenario
        let app=XCUIApplication(bundleIdentifier:Scenario.bundleID)
        let session=String(format:"B012B012-2026-4126-8000-%012d",index+1)
        app.launchArguments=Scenario.gameArguments(session:session,pitcher:true)+["-qa-full-career-root"]
        app.launch();defer {app.terminate()}
        Scenario.waitHome(app);let home=Scenario.homeState(app);Scenario.openGame(app)
        Scenario.waitEnabled(app.buttons["gamePitch"],app:app)
        Scenario.capture(app,name:"P12 normal entry ready \(index)",test:self)
        let frame=app.buttons["gamePitch"].frame
        let touch=app.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:frame.midX,dy:frame.midY))
        touch.tap();touch.tap()
        XCTAssertTrue(Scenario.element(app,"inplayFieldStage").waitForExistence(timeout:25))
        let next=app.buttons["pitchEventContinue"];XCTAssertTrue(next.waitForExistence(timeout:45))
        let summary=Scenario.element(app,"inplayLastPlaySummary").label
        if index == 0 {XCTAssertTrue(summary.contains("어필"),summary);XCTAssertTrue(Scenario.element(app,"appealScoreStatus").exists)}
        else {XCTAssertTrue(summary.contains("공식 기록 검토 예정"),summary)}
        Scenario.capture(app,name:"P12 normal entry resolved \(index)",test:self)
        Scenario.tap(app,"inplayReplayAgain");XCTAssertTrue(next.waitForExistence(timeout:45))
        XCTAssertEqual(Scenario.element(app,"inplayLastPlaySummary").label,summary)
        Scenario.tap(app,"pitchEventContinue")
        Scenario.waitEnabled(app.buttons["gameAutomatic"],app:app)
        let state=Scenario.labels(app,["careerGameInning","careerGameCount","careerGameScore","boardPitchCount"])
        app.terminate();app.launch();Scenario.waitHome(app);XCTAssertEqual(Scenario.homeState(app),home)
        Scenario.openGame(app);XCTAssertEqual(Scenario.labels(app,["careerGameInning","careerGameCount","careerGameScore","boardPitchCount"]),state)
        if index == 1 {
            Scenario.tap(app,"gameAutomatic");Scenario.tap(app,"진행하고 결과 저장")
            XCTAssertTrue(Scenario.element(app,"gameResultSaved").waitForExistence(timeout:90))
            Scenario.tap(app,"openGameHistory")
            let picker=Scenario.element(app,"gameHistoryInning");XCTAssertTrue(picker.waitForExistence(timeout:10));picker.tap()
            app.buttons.matching(identifier:"1회").element(boundBy:0).tap()
            let correction=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","gameHistoryCorrection-")).firstMatch
            XCTAssertTrue(correction.waitForExistence(timeout:10))
            let applied=app.staticTexts["정정 반영"];Scenario.reveal(applied,app:app);XCTAssertTrue(applied.isHittable)
            XCTAssertTrue(app.staticTexts["최초 기록"].exists);XCTAssertTrue(app.staticTexts["해당 타석 1루 유지"].exists)
            Scenario.capture(app,name:"P12 normal entry correction history",test:self)
            XCTAssertTrue(app.staticTexts["기록 변경 이력"].exists)
            Scenario.tap(app,"closeGameHistory")
        }
        try Scenario.attach(["session":session,"case":index,"summary":summary,"resumed":state,
            "scope":"normal pitcher touch; stored abilities; replay and relaunch; correction case finishes then reads original inning"],name:"P12 normal entry audit",test:self)
    }
}
