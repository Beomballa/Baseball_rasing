import XCTest
import SwiftData
@testable import BM

@MainActor final class CareerCalendarTests: XCTestCase {
    private func fixture(date: String = "2026-04-02", role: PlayerRole = .pitcher) throws -> (ModelContainer, CareerPlayer, CareerCalendarState) {
        let container = try CareerStore.makeContainer(inMemory: true)
        var draft = PlayerDraft()
        draft.name = "달력선수"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: container.mainContext)
        let state = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first)
        player.gameDate = date
        try container.mainContext.save()
        return (container, player, state)
    }

    func testAnnualScheduleHasNinetyGamesAndBalancedOpponents() throws {
        let ids = ["A", "B", "C", "D", "E", "F"]
        for year in [2026, 2027, 2028] {
            let games = try SeasonSchedule.fixtures(year: year, schoolIDs: ids)
            XCTAssertEqual(games.count, 90)
            XCTAssertEqual(Set(games.map(\.id)).count, 90)
            XCTAssertEqual(games.first?.date.description, "\(year)-04-01")
            XCTAssertEqual(games.last?.date.description, "\(year)-09-22")
            for team in ids {
                let own = games.filter { $0.includes(team) }
                XCTAssertEqual(own.count, 30)
                XCTAssertEqual(own.filter { $0.homeID == team }.count, 15)
                XCTAssertEqual(own.filter { $0.isAppearance(for: .pitcher) }.map(\.number), [1, 6, 11, 16, 21, 26])
                XCTAssertEqual(own.filter { $0.isAppearance(for: .batter) }.count, 30)
                for opponent in ids where opponent != team {
                    XCTAssertEqual(own.filter { $0.opponent(of: team) == opponent }.count, 6)
                    XCTAssertEqual(own.filter { $0.homeID == team && $0.awayID == opponent }.count, 3)
                }
            }
            for day in Set(games.map(\.date)) {
                let sameDay = games.filter { $0.date == day }
                XCTAssertEqual(sameDay.count, 3)
                XCTAssertEqual(Set(sameDay.flatMap { [$0.homeID, $0.awayID] }).count, 6)
            }
        }
        XCTAssertThrowsError(try SeasonSchedule.fixtures(year: 2026, schoolIDs: ["A", "A"]))
    }

    func testGroupsAreStableUniqueAndContainSelectedSchool() throws {
        let schools = try SchoolCatalog.load()
        let id = UUID()
        let first = SeasonSchedule.group(for: id, schoolID: schools[0].id, schools: schools)
        XCTAssertEqual(first, SeasonSchedule.group(for: id, schoolID: schools[0].id, schools: schools))
        XCTAssertEqual(first.first, schools[0].id)
        XCTAssertEqual(Set(first).count, 6)
    }

    func testStrictDatesAndAgeOnlyOnCalendarAnniversary() throws {
        for invalid in ["2026-02-29", "2026-13-01", "2026-4-1", "garbage", "0000-01-01"] {
            XCTAssertThrowsError(try GameDate(invalid))
        }
        XCTAssertEqual(try GameDate("2028-02-28").adding(days: 1).description, "2028-02-29")
        let start = try GameDate("2026-04-01")
        let expected = [("2026-09-22", 16), ("2027-03-31", 16), ("2027-04-01", 17),
                        ("2028-04-01", 18), ("2029-04-01", 19), ("2030-04-01", 20)]
        for (date, age) in expected { XCTAssertEqual(try start.age(startingAt: 16, on: GameDate(date)), age) }
        XCTAssertEqual(SeasonSchedule.academicStatus(age: 19), "고교 졸업 · 진로준비")
        XCTAssertEqual(SeasonSchedule.academicStatus(age: 20), "성인 · 진로 선택 대기")
    }

    func testDailyRestSleepAndStaleInputCannotDoubleApply() throws {
        let (container, player, state) = try fixture()
        let context = container.mainContext
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: 0, in: context))
        try CalendarProgression.rest(player: player, state: state, revision: 0, in: context)
        XCTAssertEqual(player.fatigue, 34)
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: 0, in: context))
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: 1, in: context))
        try CalendarProgression.advanceDay(player: player, state: state, revision: 1, in: context)
        XCTAssertEqual(player.gameDate, "2026-04-03")
        XCTAssertEqual(player.fatigue, 30)
        XCTAssertFalse(state.hasAction(on: player.gameDate))
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: 1, automaticRest: true, in: context))
        XCTAssertEqual(player.fatigue, 30)
    }

    func testBulkStopsAtTeamGameEvenOnPitcherNonStartAndPreservesStats() async throws {
        let (container, player, state) = try fixture()
        let before = [player.contact, player.power, player.speed, player.defense, player.arm]
        let summary = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext)
        XCTAssertEqual(summary.days, 5)
        XCTAssertEqual(summary.restDays, 5)
        XCTAssertEqual(summary.stop, .fixture)
        XCTAssertEqual(player.gameDate, "2026-04-07")
        XCTAssertEqual(player.fatigue, 0)
        XCTAssertEqual([player.contact, player.power, player.speed, player.defense, player.arm], before)
        let next = try state.upcoming(for: player)
        XCTAssertEqual(next.first?.number, 2)
        XCTAssertEqual(next.first { $0.isAppearance(for: .pitcher) }?.date.description, "2026-05-01")
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision,
                                                               automaticRest: true, in: container.mainContext))
        XCTAssertEqual(player.gameDate, "2026-04-07")
    }

    func testPreparedDayNotRestedAgainDuringBulk() async throws {
        let (container, player, state) = try fixture(date: "2026-04-06")
        player.fatigue = 90
        try CalendarProgression.rest(player: player, state: state, revision: 0, in: container.mainContext)
        let summary = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext)
        XCTAssertEqual(summary.days, 1)
        XCTAssertEqual(summary.restDays, 0)
        XCTAssertEqual(player.fatigue, 68)
    }

    func testBulkLimitCancellationAndAnniversaryConfirmation() async throws {
        let (container, player, state) = try fixture(date: "2026-10-01")
        let summary = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext)
        XCTAssertEqual(summary.days, 30)
        XCTAssertEqual(summary.stop, .limit)
        XCTAssertEqual(player.gameDate, "2026-10-31")
        let task = Task { @MainActor in
            try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext)
        }
        task.cancel()
        let cancelled = try await task.value
        XCTAssertEqual(cancelled.stop, .cancelled)
        XCTAssertEqual(cancelled.days, 0)
        player.gameDate = "2027-03-31"; player.fatigue = 80
        try container.mainContext.save()
        let birthday = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext)
        XCTAssertEqual(birthday.days, 0)
        XCTAssertEqual(birthday.stop, .anniversary)
        XCTAssertEqual(player.fatigue, 80)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision,
                                                               automaticRest: true, in: container.mainContext))
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, automaticRest: true,
                                           confirmAnniversary: true, in: container.mainContext)
        XCTAssertEqual(player.gameDate, "2027-04-01")
        XCTAssertEqual(try state.age(of: player), 17)
        XCTAssertTrue(try CalendarProgression.hasGameToday(player: player, state: state))
        XCTAssertEqual(player.fatigue, 58)
        XCTAssertTrue(try state.fixtures(for: player, year: 2029).isEmpty)
        XCTAssertTrue(try state.fixtures(for: player, year: 2030).isEmpty)
    }

    func testV1DiskMigrationRetainsPlayersAndSavedCalendarReopens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        let schools = try SchoolCatalog.load()
        let ids: [UUID] = try autoreleasepool {
            let schema = Schema(versionedSchema: CareerSchemaV1.self)
            let config = ModelConfiguration("Career", schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            old.mainContext.autosaveEnabled = false
            return try PlayerRole.allCases.map { role in
                var draft = PlayerDraft(); draft.name = role == .batter ? "기존타자" : "기존투수"
                draft.schoolID = schools[0].id; draft.role = role; draft.throwingHand = .left
                draft.jerseyNumber = "42"; draft.appearance = PlayerAppearance(skin: 4, hair: 2, kit: 3, hairStyle: 2, expression: 1)
                let player = CareerSchemaV1.Player(draft: draft, school: schools[0])
                player.gameDate = "2028-04-02"; player.fatigue = 91; player.speed = 71.25
                old.mainContext.insert(player)
                try old.mainContext.save()
                return player.id
            }
        }
        // Open a real V1 SQLite store with the current migration plan, rather than constructing V2 test data.
        do {
            let migrated = try CareerStore.makeContainer(url: url)
            let context = migrated.mainContext
            let players = try context.fetch(FetchDescriptor<CareerPlayer>())
            let calendars = try context.fetch(FetchDescriptor<CareerCalendarState>())
            XCTAssertEqual(Set(players.map(\.id)), Set(ids))
            XCTAssertEqual(calendars.count, 2)
            for player in players {
                let state = try XCTUnwrap(calendars.first { $0.playerID == player.id })
                XCTAssertTrue(state.legacySave)
                XCTAssertEqual(state.originDate, "2028-04-02")
                XCTAssertEqual(try state.age(of: player), 16)
                XCTAssertEqual(player.schoolID, schools[0].id)
                XCTAssertEqual(player.jerseyNumber, 42)
                XCTAssertEqual(player.throwingHandRaw, "left")
                XCTAssertEqual(player.appearance, PlayerAppearance(skin: 4, hair: 2, kit: 3, hairStyle: 2, expression: 1))
                XCTAssertEqual(player.fatigue, 91)
                XCTAssertEqual(player.speed, 71.25)
                XCTAssertEqual(player.contact, 65); XCTAssertEqual(player.power, 75); XCTAssertEqual(player.discipline, 60)
                if player.role == .pitcher {
                    XCTAssertEqual(player.pitches.sorted { $0.order < $1.order }.map(\.mastery), [72, 65, 48, 35])
                    XCTAssertEqual(player.pitches.sorted { $0.order < $1.order }.map(\.code), ["four-seam", "slider", "changeup", "fork"])
                    let result = try await CalendarProgression.advanceOffDays(player: player, state: state, in: context)
                    XCTAssertEqual(result.days, 5)
                }
            }
        }
        let reopened = try CareerStore.makeContainer(url: url)
        let players = try reopened.mainContext.fetch(FetchDescriptor<CareerPlayer>())
        let calendars = try reopened.mainContext.fetch(FetchDescriptor<CareerCalendarState>())
        XCTAssertEqual(calendars.count, 2)
        let pitcher = try XCTUnwrap(players.first { $0.role == .pitcher })
        XCTAssertEqual(pitcher.gameDate, "2028-04-07")
        XCTAssertEqual(pitcher.fatigue, 0)
        XCTAssertEqual(calendars.first { $0.playerID == pitcher.id }?.revision, 5)
        XCTAssertEqual(players.first { $0.role == .batter }?.gameDate, "2028-04-02")
        XCTAssertEqual(players.first { $0.role == .batter }?.fatigue, 91)
    }
    func testTransitionRejectsRepeatedInputAndCancelBeforeCommitDoesNotRunAction() async throws {
        let transition = CareerTransition()
        var calls = 0
        transition.perform(date: "2026-04-02", label: "하루 진행", reduced: true) { calls += 1 }
        transition.perform(date: "2026-04-02", label: "중복 입력", reduced: true) { calls += 100 }
        XCTAssertNotNil(transition.display)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(transition.display)
        transition.perform(date: "2026-04-03", label: "취소", reduced: true) { calls += 100 }
        transition.requestCancel()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(transition.display)
    }

    func testAnimatedBulkNotifiesOnlySavedDaysAndStopsAfterCancellation() async throws {
        let (container, player, state) = try fixture()
        var dates: [String] = []
        let task = Task { @MainActor in
            try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext, onDaySaved: { date in
                XCTAssertFalse(container.mainContext.hasChanges)
                dates.append(date)
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        let summary = try await task.value
        XCTAssertEqual(dates, ["2026-04-03"])
        XCTAssertEqual(summary.days, 1)
        XCTAssertEqual(summary.stop, .cancelled)
        XCTAssertEqual(player.fatigue, 30)
        XCTAssertEqual(player.gameDate, "2026-04-03")
    }

    func testScheduleLookupFailuresAreNotAnEmptyOffDayAndCannotConsumeActions() throws {
        let (container, player, state) = try fixture()
        let validIDs = state.schoolIDs
        let cases: [(String, [String])] = [
            ("invalid-date", validIDs), ("2026-04-02", Array(validIDs.prefix(3))),
            ("2026-04-02", Array(repeating: player.schoolID, count: 6)),
            ("2026-04-02", ["A", "B", "C", "D", "E", "F"])
        ]
        for (date, ids) in cases {
            player.gameDate = date; state.schoolIDs = ids
            try container.mainContext.save()
            let status = CalendarScheduleStatus(player: player, state: state)
            XCTAssertNil(status.schedule)
            XCTAssertNotNil(status.errorMessage)
            XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: 0, in: container.mainContext))
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: player, state: state, revision: 0,
                                                                   automaticRest: true, in: container.mainContext))
            XCTAssertEqual(player.gameDate, date)
            XCTAssertEqual(player.fatigue, 52)
            XCTAssertNil(state.actionDate)
            XCTAssertEqual(state.revision, 0)
            XCTAssertFalse(container.mainContext.hasChanges)
        }
        player.gameDate = "2026-04-02"; state.schoolIDs = validIDs
        try container.mainContext.save()
        let retried = CalendarScheduleStatus(player: player, state: state)
        XCTAssertNil(retried.errorMessage)
        XCTAssertEqual(retried.schedule?.annual.count, 30)
        XCTAssertNil(retried.schedule?.today)
    }

    func testValidEmptyScheduleAfterGraduationIsNotALookupError() throws {
        let (container, player, state) = try fixture(date: "2029-04-02")
        let status = CalendarScheduleStatus(player: player, state: state)
        XCTAssertNil(status.errorMessage)
        XCTAssertTrue(try XCTUnwrap(status.schedule).annual.isEmpty)
        XCTAssertTrue(try XCTUnwrap(status.schedule).upcoming.isEmpty)
        XCTAssertFalse(container.mainContext.hasChanges)
    }

    func testManualAndAutomaticRestHaveIdenticalRecoveryAtFatigueBoundaries() throws {
        for role in PlayerRole.allCases {
            for fatigue in [0, 1, 4, 17, 18, 19, 52, 90, 100] {
                let (manualStore, manual, manualState) = try fixture(role: role)
                let (autoStore, automatic, autoState) = try fixture(role: role)
                manual.fatigue = fatigue; automatic.fatigue = fatigue
                try manualStore.mainContext.save(); try autoStore.mainContext.save()
                try CalendarProgression.rest(player: manual, state: manualState, revision: 0, in: manualStore.mainContext)
                try CalendarProgression.advanceDay(player: manual, state: manualState, revision: 1, in: manualStore.mainContext)
                try CalendarProgression.advanceDay(player: automatic, state: autoState, revision: 0,
                                                   automaticRest: true, in: autoStore.mainContext)
                XCTAssertEqual(manual.fatigue, max(0, fatigue - 22))
                XCTAssertEqual(automatic.fatigue, manual.fatigue)
                XCTAssertEqual(automatic.gameDate, manual.gameDate)
                XCTAssertNil(autoState.actionDate)
                XCTAssertNil(manualState.actionDate)
            }
        }
    }

    func testFirstBulkSaveFailureReportsZeroDaysAndRollsBackTheWholeDay() async throws {
        let (container, player, state) = try fixture()
        let injected = CocoaError(.fileWriteOutOfSpace)
        var notices: [String] = []
        do {
            _ = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext,
                                                             save: { _ in throw injected }, onDaySaved: { notices.append($0) })
            XCTFail("Expected an injected save failure")
        } catch let failure as CalendarAdvanceFailure {
            XCTAssertEqual(failure.summary.days, 0)
            XCTAssertEqual(failure.summary.restDays, 0)
            XCTAssertEqual(failure.summary.lastSavedDate, "2026-04-02")
            XCTAssertEqual(failure.summary.fatigueBefore, 52)
            XCTAssertEqual(failure.summary.fatigueAfter, 52)
            XCTAssertEqual(failure.summary.stop, .failed)
            XCTAssertEqual(failure.reason, injected.localizedDescription)
            XCTAssertTrue(failure.localizedDescription.contains("0일 진행"))
        }
        XCTAssertTrue(notices.isEmpty)
        XCTAssertEqual(player.gameDate, "2026-04-02")
        XCTAssertEqual(player.fatigue, 52)
        XCTAssertEqual(state.revision, 0)
        XCTAssertNil(state.actionDate)
        XCTAssertFalse(container.mainContext.hasChanges)
    }

    func testPartialBulkSaveFailurePreservesCommittedDaysOnDiskAndRetryDoesNotRepeatRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("partial.store")
        let schools = try SchoolCatalog.load()
        var playerID: UUID?
        do {
            let store = try CareerStore.makeContainer(url: url)
            var draft = PlayerDraft(); draft.name = "부분저장"; draft.schoolID = schools[0].id; draft.role = .pitcher
            let player = try CareerStore.create(draft, schools: schools, in: store.mainContext)
            draft.role = .batter
            _ = try CareerStore.create(draft, schools: schools, in: store.mainContext)
            let state = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
            player.gameDate = "2026-04-02"; player.fatigue = 90; playerID = player.id
            try store.mainContext.save()
            var calls = 0
            var notices: [String] = []
            do {
                _ = try await CalendarProgression.advanceOffDays(player: player, state: state, in: store.mainContext, save: { context in
                    calls += 1
                    if calls == 3 { throw CocoaError(.fileWriteOutOfSpace) }
                    try context.save()
                }, onDaySaved: { notices.append($0) })
                XCTFail("Expected failure on the third save")
            } catch let failure as CalendarAdvanceFailure {
                XCTAssertEqual(failure.summary.days, 2)
                XCTAssertEqual(failure.summary.restDays, 2)
                XCTAssertEqual(failure.summary.lastSavedDate, "2026-04-04")
                XCTAssertEqual(failure.summary.fatigueBefore, 90)
                XCTAssertEqual(failure.summary.fatigueAfter, 46)
                XCTAssertTrue(failure.localizedDescription.contains("2일 진행"))
                XCTAssertTrue(failure.localizedDescription.contains("마지막 저장일 2026-04-04"))
                XCTAssertTrue(failure.localizedDescription.contains("90 → 46"))
            }
            XCTAssertEqual(notices, ["2026-04-03", "2026-04-04"])
            XCTAssertEqual(player.gameDate, "2026-04-04")
            XCTAssertEqual(player.fatigue, 46)
            XCTAssertEqual(state.revision, 2)
            XCTAssertFalse(store.mainContext.hasChanges)
        }
        let reopened = try CareerStore.makeContainer(url: url)
        let players = try reopened.mainContext.fetch(FetchDescriptor<CareerPlayer>())
        let pitcher = try XCTUnwrap(players.first { $0.id == playerID })
        let state = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == pitcher.id })
        XCTAssertEqual(pitcher.gameDate, "2026-04-04")
        XCTAssertEqual(pitcher.fatigue, 46)
        XCTAssertEqual(pitcher.pitches.sorted { $0.order < $1.order }.map(\.mastery), [62, 55, 42, 35])
        let retry = try await CalendarProgression.advanceOffDays(player: pitcher, state: state, in: reopened.mainContext)
        XCTAssertEqual(retry.days, 3)
        XCTAssertEqual(retry.restDays, 3)
        XCTAssertEqual(retry.lastSavedDate, "2026-04-07")
        XCTAssertEqual(pitcher.fatigue, 0)
        XCTAssertEqual(state.revision, 5)
        XCTAssertEqual(players.first { $0.role == .batter }?.gameDate, "2026-04-01")
        XCTAssertEqual(players.first { $0.role == .batter }?.fatigue, 24)
    }

    func testFailedSleepPreservesAlreadySavedRestAndRetryOnlyAppliesSleep() async throws {
        let (container, player, state) = try fixture(date: "2026-04-06", role: .batter)
        player.fatigue = 90
        try container.mainContext.save()
        try CalendarProgression.rest(player: player, state: state, revision: 0, in: container.mainContext)
        do {
            _ = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext,
                                                             save: { _ in throw CocoaError(.fileWriteOutOfSpace) })
            XCTFail("Expected save failure")
        } catch let failure as CalendarAdvanceFailure {
            XCTAssertEqual(failure.summary.days, 0)
            XCTAssertEqual(failure.summary.fatigueAfter, 72)
        }
        XCTAssertEqual(player.fatigue, 72)
        XCTAssertEqual(state.actionDate, "2026-04-06")
        XCTAssertEqual(state.revision, 1)
        let retry = try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext)
        XCTAssertEqual(retry.days, 1)
        XCTAssertEqual(retry.restDays, 0)
        XCTAssertEqual(player.fatigue, 68)
    }

    func testFailedManualRestDoesNotConsumeActionOrRecovery() throws {
        let (container, player, state) = try fixture()
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: 0,
                                                         in: container.mainContext, save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(player.fatigue, 52)
        XCTAssertEqual(state.revision, 0)
        XCTAssertNil(state.actionDate)
        try CalendarProgression.rest(player: player, state: state, revision: 0, in: container.mainContext)
        XCTAssertEqual(player.fatigue, 34)
        XCTAssertThrowsError(try CalendarProgression.rest(player: player, state: state, revision: 1, in: container.mainContext))
    }

    private var leagueID:UUID {UUID(uuidString:"00000000-0000-0000-0000-000000000001")!}
    private var leagueTeams:[String] {["A","B","C","D","E","F"]}
    private func league(on date:String="2026-04-01",year:Int=2026,official:[LeagueOfficialResult]=[],pending:Set<String>=[],origin:String="2026-04-01") throws -> AnnualLeague {
        try AnnualLeague.make(playerID:leagueID,schoolIDs:leagueTeams,origin:GameDate(origin),startAge:16,today:GameDate(date),year:year,official:official,pending:pending)
    }
    func testLeagueInitialTodayWaitsAndPastDateSimulatesExactlyThree() throws {
        let first=try league();XCTAssertEqual(first.fixtures.count,90);XCTAssertTrue(first.results.isEmpty)
        XCTAssertTrue(first.standings.allSatisfy {$0.games == 0 && $0.rank == nil && $0.percentage == "—"})
        let next=try league(on:"2026-04-02");XCTAssertEqual(next.results.count,3);XCTAssertTrue(next.results.allSatisfy(\.automatic))
        XCTAssertTrue(next.standings.allSatisfy {$0.games == 1});XCTAssertEqual(next,try league(on:"2026-04-02"))
        XCTAssertEqual(try league(on:"2026-04-06"),next)
    }
    func testLeagueFixedVersionScoreIndependentOracleAndCareerSeed() throws {
        let f=try XCTUnwrap(SeasonSchedule.fixtures(year:2026,schoolIDs:leagueTeams).first)
        XCTAssertEqual(f.id,"2026-04-01-A-F")
        let score=AnnualLeague.automaticScore(playerID:leagueID,fixture:f)
        XCTAssertEqual(score.0,6);XCTAssertEqual(score.1,5)
        let a=try league(on:"2026-09-23")
        let b=try AnnualLeague.make(playerID:UUID(uuidString:"00000000-0000-0000-0000-000000000002")!,schoolIDs:leagueTeams,origin:GameDate("2026-04-01"),startAge:16,today:GameDate("2026-09-23"),year:2026,official:[])
        XCTAssertNotEqual(a.results,b.results)
    }
    func testLeagueActualDrawImmediatelyOverridesAutoWithoutDoubleCounting() throws {
        let id=try XCTUnwrap(league().fixtures.first?.id)
        let official=LeagueOfficialResult(fixtureID:id,homeScore:7,awayScore:7)
        let today=try league(official:[official]);XCTAssertEqual(today.results.count,1);XCTAssertFalse(try XCTUnwrap(today.results.first).automatic)
        XCTAssertEqual(today.standings.filter {$0.draws == 1}.count,2);XCTAssertEqual(today.standings.map(\.wins).reduce(0,+),0)
        let next=try league(on:"2026-04-02",official:[official]);XCTAssertEqual(next.results.count,3)
        XCTAssertEqual(next.results.filter {$0.id == id}.count,1);XCTAssertEqual(next.results.first?.homeScore,7)
        XCTAssertTrue(next.standings.allSatisfy {$0.games == 1})
    }
    func testLeagueFullAnnualScheduleConservesWinsLossesAndDraws() throws {
        for year in [2026,2027,2028] {
            let snapshot=try league(on:"\(year)-09-23",year:year)
            XCTAssertEqual(snapshot.results.count,90);XCTAssertTrue(snapshot.standings.allSatisfy {$0.games == 30})
            XCTAssertEqual(snapshot.standings.map(\.wins).reduce(0,+),snapshot.standings.map(\.losses).reduce(0,+))
            XCTAssertEqual(snapshot.standings.map(\.draws).reduce(0,+),snapshot.results.filter {$0.homeScore == $0.awayScore}.count*2)
            for row in snapshot.standings {
                let own=snapshot.results.filter {$0.fixture.includes(row.id)}
                let wins=own.filter {$0.fixture.homeID == row.id ? $0.homeScore > $0.awayScore:$0.awayScore > $0.homeScore}.count
                let draws=own.filter {$0.homeScore == $0.awayScore}.count
                XCTAssertEqual(row.wins,wins);XCTAssertEqual(row.losses,30-wins-draws);XCTAssertEqual(row.draws,draws)
            }
        }
    }
    func testLeagueExactFractionsSharedCompetitionRanksAndUndefinedStandings() {
        let teams=[LeagueStanding(id:"A",wins:1,losses:1),LeagueStanding(id:"B",wins:3,losses:3),LeagueStanding(id:"C",wins:1,losses:2),LeagueStanding(id:"D",draws:4),LeagueStanding(id:"E",wins:1),LeagueStanding(id:"F",losses:1)]
        let sorted=AnnualLeague.ordered(teams)
        XCTAssertEqual(sorted.map(\.id),["E","A","B","C","F","D"]);XCTAssertEqual(sorted.map(\.rank),[1,2,2,4,5,nil])
        let close=AnnualLeague.ordered([LeagueStanding(id:"A",wins:333,losses:667),LeagueStanding(id:"B",wins:1,losses:2)])
        XCTAssertEqual(close.map(\.percentage),["0.333","0.333"]);XCTAssertEqual(close.map(\.rank),[1,2]);XCTAssertEqual(close.first?.id,"B")
    }
    func testLeagueRejectsDuplicatesDamagedFutureAndUnfinishedPastWithoutInventingResults() throws {
        let id=try XCTUnwrap(league().fixtures.first?.id),a=LeagueOfficialResult(fixtureID:id,homeScore:1,awayScore:0)
        XCTAssertThrowsError(try league(official:[a,a]));XCTAssertThrowsError(try league(official:[LeagueOfficialResult(fixtureID:id,homeScore:-1,awayScore:0)]))
        XCTAssertThrowsError(try league(official:[a],pending:[id]));XCTAssertThrowsError(try league(on:"2026-04-02",pending:[id]))
        XCTAssertTrue(try league(pending:[id]).results.isEmpty)
        XCTAssertThrowsError(try league(on:"2026-03-31",official:[a]))
        XCTAssertThrowsError(try league(on:"2026-04-01",year:2027));XCTAssertThrowsError(try league(official:[LeagueOfficialResult(fixtureID:"missing",homeScore:0,awayScore:0)]))
    }
    func testLeagueCareerStartAgeAndYearBoundariesDoNotResetPriorResults() throws {
        let partial=try league(on:"2026-09-23",origin:"2026-07-01")
        XCTAssertTrue(partial.fixtures.allSatisfy {$0.date >= (try! GameDate("2026-07-01"))});XCTAssertLessThan(partial.fixtures.count,90)
        XCTAssertEqual(try league(on:"2027-01-01",year:2026),try league(on:"2026-09-23"))
        XCTAssertTrue(try league(on:"2027-01-01",year:2027).results.isEmpty)
        XCTAssertTrue(try league(on:"2029-10-01",year:2029).fixtures.isEmpty)
    }
    func testLeagueCompletedMatchAndDateProgressionHaveNoSecondPersonalReward() throws {
        for role in PlayerRole.allCases {
            let (container,p,s)=try fixture(date:"2026-04-01",role:role),c=container.mainContext
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertTrue(try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c).results.isEmpty)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            let actual=try record.snapshot(),before=record.payload,fatigue=p.fatigue,revision=s.revision
            let today=try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c)
            XCTAssertEqual(today.results.count,1);XCTAssertEqual(today.results.first?.homeScore,actual.homeScore)
            for _ in 0..<3 {XCTAssertEqual(try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c),today)}
            XCTAssertEqual(record.payload,before);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
            let next=try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c)
            XCTAssertEqual(next.results.count,3);XCTAssertEqual(next.results.filter {!$0.automatic}.count,1)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).count,1)
            XCTAssertEqual(record.payload,before);XCTAssertEqual(p.fatigue,max(0,fatigue-4))
            let own=try XCTUnwrap(next.standings.first {$0.id == p.schoolID});XCTAssertEqual(own.games,1)
        }
    }
    func testLeagueDateSaveFailureRollbackRetryAndStaleInputDoNotAddResults() throws {
        enum Failure:Error {case injected}
        let (container,p,s)=try fixture(date:"2026-04-01",role:.batter),c=container.mainContext
        try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
        let r=try CareerMatchStore.start(player:p,state:s,in:c)
        try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
        let before=try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c),revision=s.revision,fatigue=p.fatigue
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:revision,in:c,save:{_ in throw Failure.injected}))
        XCTAssertEqual(try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c),before);XCTAssertEqual(p.fatigue,fatigue)
        try CalendarProgression.advanceDay(player:p,state:s,revision:revision,in:c)
        let after=try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c);XCTAssertEqual(after.results.count,3)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c))
        XCTAssertEqual(try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c),after)
    }
    func testLeagueSnapshotRejectsInvalidOwnRecordInsteadOfIgnoringIt() throws {
        let (container,p,s)=try fixture(date:"2026-04-01",role:.batter),c=container.mainContext
        try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
        let r=try CareerMatchStore.start(player:p,state:s,in:c)
        r.opponentID="wrong";try c.save()
        XCTAssertThrowsError(try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c));XCTAssertEqual(r.opponentID,"wrong")
    }
    func testLeagueDiskReloadKeepsOriginalPayloadAndOtherRoleIndependent() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("league.store")
        let saved=try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext
            var draft=PlayerDraft();draft.schoolID="hs-ref-001";draft.name="LeagueBatter"
            let p=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:c)
            draft.role = .pitcher;draft.name="LeaguePitch"
            let other=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:c)
            let s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == p.id})
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let r=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
            return (p.id,other.id,r.payload,try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c),p.fatigue)
        }
        try autoreleasepool {
            let container=try CareerStore.makeContainer(url:url),c=container.mainContext,players=try c.fetch(FetchDescriptor<CareerPlayer>())
            let p=try XCTUnwrap(players.first {$0.id == saved.0}),other=try XCTUnwrap(players.first {$0.id == saved.1})
            let states=try c.fetch(FetchDescriptor<CareerCalendarState>()),s=try XCTUnwrap(states.first {$0.playerID == p.id}),otherState=try XCTUnwrap(states.first {$0.playerID == other.id})
            XCTAssertEqual(try AnnualLeagueStore.load(player:p,state:s,year:2026,in:c),saved.3)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).first?.payload,saved.2);XCTAssertEqual(p.fatigue,saved.4)
            XCTAssertEqual(other.gameDate,"2026-04-01");XCTAssertTrue(try AnnualLeagueStore.load(player:other,state:otherState,year:2026,in:c).results.isEmpty)
        }
    }

    private func finishSeason(player p: CareerPlayer, state s: CareerCalendarState, in c: ModelContext) throws -> [CareerMatchRecord] {
        let fixtures = try s.fixtures(for: p, year: GameDate(p.gameDate).year)
        var records: [CareerMatchRecord] = []
        for f in fixtures {
            while try GameDate(p.gameDate) < f.date {
                try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, automaticRest: true, in: c)
            }
            if !s.hasAction(on: p.gameDate) { try CalendarProgression.rest(player: p, state: s, revision: s.revision, in: c) }
            let r = try CareerMatchStore.start(player: p, state: s, in: c)
            try CareerMatchStore.advance(player: p, state: s, record: r, revision: r.revision, input: .automatic, in: c)
            records.append(r)
        }
        return records
    }
    func testSeasonTotalsUseAggregateDenominatorsIntegerOutsAndZeroDashes() throws {
        var totals = PersonalSeasonTotals()
        XCTAssertEqual(totals.average, "—"); XCTAssertEqual(totals.whip, "—"); XCTAssertEqual(totals.innings, "0.0")
        var a = MatchLine(); a.plateAppearances = 4; a.atBats = 3; a.hits = 2; a.homeRuns = 1; a.walks = 1
        a.pitchingOuts = 4; a.hitsAllowed = 2; a.pitchingWalks = 1
        var b = MatchLine(); b.plateAppearances = 2; b.atBats = 1; b.walks = 1; b.pitchingOuts = 5; b.pitchingWalks = 1
        try totals.add(a); try totals.add(b)
        XCTAssertEqual(totals.games, 2); XCTAssertEqual(totals.average, "0.500")
        XCTAssertEqual(totals.innings, "3.0"); XCTAssertEqual(totals.whip, "1.33")
        XCTAssertEqual(totals.line.walks, 2)
        var bad = MatchLine(); bad.hits = 1
        XCTAssertThrowsError(try totals.add(bad)); XCTAssertEqual(totals.games, 2)
        bad = MatchLine(); bad.pitches = -1; XCTAssertThrowsError(try totals.add(bad))
        bad = MatchLine(); bad.rbi = Int.max; try totals.add(bad)
        bad.rbi = 1; XCTAssertThrowsError(try totals.add(bad)); XCTAssertEqual(totals.line.rbi, Int.max)
    }
    func testSeasonBothRolesThirtyTeamGamesFinalDayPendingThenFinalAndRewardOnce() throws {
        for role in PlayerRole.allCases {
            let (container, p, s) = try fixture(date: "2026-04-01", role: role), c = container.mainContext
            let records = try finishSeason(player: p, state: s, in: c)
            let last = try XCTUnwrap(records.last)
            let unfinished = try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c)
            XCTAssertEqual(records.count, 30); XCTAssertFalse(unfinished.finalized); XCTAssertTrue(unfinished.champions.isEmpty)
            XCTAssertEqual(unfinished.league.results.count, 88)
            let personal = try records.filter(\.appearance).map { try $0.snapshot().line }
            XCTAssertEqual(unfinished.totals.games, role == .batter ? 30 : 6)
            XCTAssertEqual(unfinished.totals.line.hits, personal.reduce(0) { $0 + $1.hits })
            XCTAssertEqual(unfinished.totals.line.pitchingOuts, personal.reduce(0) { $0 + $1.pitchingOuts })
            XCTAssertEqual(unfinished.totals.line.runsAllowed, personal.reduce(0) { $0 + $1.runsAllowed })
            let payloads = records.map(\.payload), fatigue = p.fatigue, revision = s.revision
            XCTAssertThrowsError(try CareerMatchStore.advance(player: p, state: s, record: last, revision: last.revision, input: .automatic, in: c))
            XCTAssertEqual(p.fatigue, fatigue); XCTAssertEqual(s.revision, revision)
            try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, in: c)
            let final = try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c)
            XCTAssertTrue(final.finalized); XCTAssertEqual(final.league.results.count, 90)
            XCTAssertTrue(final.finalStandings.allSatisfy { $0.games == 30 })
            XCTAssertFalse(final.champions.isEmpty); XCTAssertTrue(final.champions.allSatisfy { $0.rank == 1 })
            XCTAssertEqual(final.totals, unfinished.totals); XCTAssertEqual(records.map(\.payload), payloads)
            let endFatigue = p.fatigue, endRevision = s.revision
            for _ in 0..<3 { XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), final) }
            XCTAssertEqual(p.fatigue, endFatigue); XCTAssertEqual(s.revision, endRevision)
            p.gameDate = "2027-01-01"; try c.save()
            XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), final)
            let next = try CareerSeasonStore.load(player: p, state: s, year: 2027, in: c)
            XCTAssertEqual(next.totals.games, 0); XCTAssertFalse(next.finalized)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).count, 30)
        }
    }
    func testSeasonIncompleteAndNonAppearanceNotPersonalAndCorruptionIsError() throws {
        let (container, p, s) = try fixture(date: "2026-04-01", role: .pitcher), c = container.mainContext
        try CalendarProgression.rest(player: p, state: s, revision: s.revision, in: c)
        let r = try CareerMatchStore.start(player: p, state: s, in: c)
        XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c).totals.games, 0)
        try CareerMatchStore.advance(player: p, state: s, record: r, revision: r.revision, input: .automatic, in: c)
        let payload = r.payload
        var m = try r.snapshot(); m.line.hits = -1; r.payload = try JSONEncoder().encode(m); try c.save()
        XCTAssertThrowsError(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c))
        XCTAssertNotEqual(r.payload, payload)
        r.payload = payload; try c.save()
        XCTAssertThrowsError(try CareerSeasonStore.snapshot(player: p, state: s, year: 2026, records: [r, r]))
    }
    func testSeasonFinalTiesAllDrawsAndPartialCareerNeverClaimsThirty() throws {
        let fixtures = try SeasonSchedule.fixtures(year: 2026, schoolIDs: leagueTeams)
        let official = fixtures.map { LeagueOfficialResult(fixtureID: $0.id, homeScore: 2, awayScore: 2) }
        let allDraws = try league(on: "2026-09-23", official: official)
        let final = CareerSeasonSummary(league: allDraws, totals: PersonalSeasonTotals())
        XCTAssertTrue(final.finalized); XCTAssertEqual(final.champions.count, 6)
        XCTAssertTrue(final.finalStandings.allSatisfy { $0.rank == 1 && $0.percentage == "—" })
        let partial = CareerSeasonSummary(league: try league(on: "2026-09-23", origin: "2026-05-01"), totals: PersonalSeasonTotals())
        XCTAssertFalse(partial.finalized); XCTAssertTrue(partial.champions.isEmpty)
        let rows = AnnualLeague.ordered([LeagueStanding(id: "A", wins: 20, losses: 10), LeagueStanding(id: "B", wins: 20, losses: 10), LeagueStanding(id: "C", wins: 19, losses: 11)])
        XCTAssertEqual(rows.map(\.rank), [1, 1, 3])
    }
    func testSeasonDiskReloadPreservesFinalOriginalRecordsAndOtherRole() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("season.store")
        let saved = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), c = container.mainContext
            var draft = PlayerDraft(); draft.schoolID = "hs-ref-001"; draft.name = "SeasonBat"
            let p = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: c)
            draft.role = .pitcher; draft.name = "SeasonPitch"
            let other = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: c)
            let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id })
            let records = try finishSeason(player: p, state: s, in: c)
            try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, in: c)
            return (p.id, other.id, Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0.payload) }), try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), p.fatigue)
        }
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url), c = container.mainContext
            let players = try c.fetch(FetchDescriptor<CareerPlayer>()), states = try c.fetch(FetchDescriptor<CareerCalendarState>())
            let p = try XCTUnwrap(players.first { $0.id == saved.0 }), other = try XCTUnwrap(players.first { $0.id == saved.1 })
            let s = try XCTUnwrap(states.first { $0.playerID == p.id })
            XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), saved.3)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: try c.fetch(FetchDescriptor<CareerMatchRecord>()).map { ($0.key, $0.payload) }), saved.2)
            XCTAssertEqual(p.fatigue, saved.4); XCTAssertEqual(other.gameDate, "2026-04-01")
            let otherState = try XCTUnwrap(states.first { $0.playerID == other.id })
            XCTAssertEqual(try CareerSeasonStore.load(player: other, state: otherState, year: 2026, in: c).totals.games, 0)
        }
    }

    func testSeasonFinalDaySaveFailureCannotFinalizeUntilCommittedRetry() throws {
        enum Failure: Error { case injected }
        let (container, p, s) = try fixture(date: "2026-04-01", role: .pitcher), c = container.mainContext
        _ = try finishSeason(player: p, state: s, in: c)
        let before = try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c)
        let fatigue = p.fatigue, revision = s.revision
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: p, state: s, revision: revision, in: c, save: { _ in throw Failure.injected }))
        XCTAssertEqual(p.gameDate, "2026-09-22"); XCTAssertEqual(p.fatigue, fatigue); XCTAssertEqual(s.revision, revision)
        XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), before)
        try CalendarProgression.advanceDay(player: p, state: s, revision: revision, in: c)
        let final = try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c)
        XCTAssertTrue(final.finalized); XCTAssertEqual(final.totals, before.totals)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player: p, state: s, revision: revision, automaticRest: true, in: c))
        XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), final)
    }

    private func offseasonFixture(role: PlayerRole = .pitcher, year: Int = 2026) throws -> (ModelContainer, CareerPlayer, CareerCalendarState) {
        let (container, p, s) = try fixture(date: "\(year)-04-01", role: role), c = container.mainContext
        _ = try finishSeason(player: p, state: s, in: c)
        try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, in: c)
        return (container, p, s)
    }
    private func offseasonBatch(_ p: CareerPlayer, _ s: CareerCalendarState, _ c: ModelContext, year: Int = 2026,
                                confirmed: Bool = false) async throws -> CalendarAdvanceSummary {
        try await CalendarProgression.advanceOffseason(player: p, state: s, seasonYear: year,
            revision: s.revision, expectedDate: p.gameDate, confirmAnniversary: confirmed, in: c)
    }
    func testOffseasonBothRolesDailyRecoveryThirtyDayBatchesAndOpeningPreserveGrowthAndHistory() async throws {
        for role in PlayerRole.allCases {
            let (container, p, s) = try offseasonFixture(role: role), c = container.mainContext
            let previous = try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c)
            let values = [p.contact, p.power, p.discipline, p.speed, p.defense, p.arm]
            let pitches = Dictionary(uniqueKeysWithValues: p.pitches.map { ($0.code, $0.mastery) })
            let profile = try XCTUnwrap(PlayerAbilityStore.profile(playerID: p.id, in: c))
            let initial = profile.initialValues, mental = profile.mental, velocity = profile.velocity
            let traits = try XCTUnwrap(PlayerTraitStore.profile(playerID: p.id, in: c)), traitData = traits.payload
            let positions = try PlayerPositionStore.profile(playerID: p.id, in: c), positionData = positions?.payload
            let payloads = try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            p.fatigue = 100; s.actionDate = p.gameDate; try c.save()
            let startRevision = s.revision
            var dates: [String] = [], fatigue: [Int] = []
            let first = try await CalendarProgression.advanceOffseason(player: p, state: s, seasonYear: 2026,
                revision: s.revision, expectedDate: p.gameDate, in: c, onDaySaved: { date in
                    XCTAssertFalse(c.hasChanges); dates.append(date); fatigue.append(p.fatigue)
                })
            XCTAssertEqual(first.days, 30); XCTAssertEqual(first.restDays, 29); XCTAssertEqual(first.stop, .limit)
            XCTAssertEqual(dates.count, 30); XCTAssertEqual(Set(dates).count, 30); XCTAssertEqual(fatigue.first, 96)
            XCTAssertEqual(fatigue[1], 74); XCTAssertEqual(p.fatigue, 0)
            XCTAssertEqual(try s.age(of: p), 16)
            while p.gameDate < "2027-03-31" {
                let result = try await offseasonBatch(p, s, c)
                XCTAssertLessThanOrEqual(result.days, 30); XCTAssertGreaterThan(result.days, 0)
            }
            XCTAssertEqual(p.gameDate, "2027-03-31"); XCTAssertEqual(try s.age(of: p), 16)
            let paused = try await offseasonBatch(p, s, c)
            XCTAssertEqual(paused.stop, .anniversary); XCTAssertEqual(paused.days, 0)
            let opened = try await offseasonBatch(p, s, c, confirmed: true)
            XCTAssertEqual(opened.days, 1); XCTAssertEqual(opened.stop, .seasonOpening)
            XCTAssertEqual(p.gameDate, "2027-04-01"); XCTAssertEqual(try s.age(of: p), 17)
            XCTAssertEqual(s.revision, startRevision + 190); XCTAssertNil(s.actionDate)
            XCTAssertEqual(try s.fixtures(for: p, year: 2027).count, 30)
            XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), previous)
            XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2027, in: c).totals.games, 0)
            XCTAssertEqual([p.contact, p.power, p.discipline, p.speed, p.defense, p.arm], values)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: p.pitches.map { ($0.code, $0.mastery) }), pitches)
            XCTAssertEqual(profile.initialValues, initial); XCTAssertEqual(profile.mental, mental); XCTAssertEqual(profile.velocity, velocity)
            XCTAssertEqual(traits.payload, traitData); XCTAssertEqual(positions?.payload, positionData)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload), payloads)
            do { _ = try await offseasonBatch(p, s, c, confirmed: true); XCTFail("opened twice") } catch {}
            XCTAssertEqual(s.revision, startRevision + 190)
            // Opening day is a real fixture: preparation and actual completion still gate the next day.
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, automaticRest: true, in: c))
        }
    }
    func testOffseasonRejectsUnfinishedStalePartialAndPendingTrainingWithoutSaving() async throws {
        let (container, p, s) = try fixture(date: "2026-04-01"), c = container.mainContext
        do { _ = try await offseasonBatch(p, s, c); XCTFail("unfinished") } catch {}
        XCTAssertEqual(p.gameDate, "2026-04-01")
        _ = try finishSeason(player: p, state: s, in: c)
        do { _ = try await offseasonBatch(p, s, c); XCTFail("last day only88") } catch {}
        try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, in: c)
        let date = p.gameDate, revision = s.revision
        for (r, d, year) in [(revision - 1, date, 2026), (revision, "2026-09-22", 2026), (revision, date, 2025)] {
            do { _ = try await CalendarProgression.advanceOffseason(player: p, state: s, seasonYear: year, revision: r, expectedDate: d, in: c); XCTFail("stale") } catch {}
        }
        _ = try CareerTrainingStore.start(player: p, state: s, pitchCode: p.pitches[0].code, in: c)
        let pendingRevision = s.revision
        do { _ = try await offseasonBatch(p, s, c); XCTFail("pending training") } catch {}
        XCTAssertEqual(p.gameDate, date); XCTAssertEqual(s.revision, pendingRevision)
        let summary = CareerSeasonSummary(league: try league(on: "2026-09-23", origin: "2026-05-01"), totals: PersonalSeasonTotals())
        XCTAssertThrowsError(try OffseasonPlan.make(summary: summary, origin: GameDate("2026-05-01"), startAge: 16, today: GameDate("2026-09-23")))
    }
    func testOffseasonCancellationBeforeAndAfterCommittedDaysCanResume() async throws {
        let (container, p, s) = try offseasonFixture(), c = container.mainContext
        p.fatigue = 100; try c.save()
        let revision = s.revision
        let before = Task { @MainActor in try await self.offseasonBatch(p, s, c) }; before.cancel()
        let zero = try await before.value; XCTAssertEqual(zero.days, 0); XCTAssertEqual(zero.stop, .cancelled)
        XCTAssertEqual(p.fatigue, 100); XCTAssertEqual(s.revision, revision)
        var dates: [String] = []
        let task = Task { @MainActor in
            try await CalendarProgression.advanceOffseason(player: p, state: s, seasonYear: 2026, revision: s.revision, expectedDate: p.gameDate, in: c, onDaySaved: { date in
                dates.append(date)
                if dates.count == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        let result = try await task.value
        XCTAssertEqual(result.stop, .cancelled); XCTAssertEqual(result.days, 3)
        XCTAssertEqual(p.gameDate, "2026-09-26"); XCTAssertEqual(p.fatigue, 34)
        let resumed = try await offseasonBatch(p, s, c)
        XCTAssertEqual(resumed.days, 30); XCTAssertEqual(p.gameDate, "2026-10-26")
    }
    func testOffseasonSaveFailureFirstMiddleAndOpeningDayRollBackOnlyFailedDay() async throws {
        enum Failure: Error { case injected }
        let (container, p, s) = try offseasonFixture(), c = container.mainContext
        p.fatigue = 100; try c.save()
        for failAt in [1, 4] {
            let start = try GameDate(p.gameDate), revision = s.revision, beforeFatigue = p.fatigue
            var calls = 0
            do {
                _ = try await CalendarProgression.advanceOffseason(player: p, state: s, seasonYear: 2026, revision: revision, expectedDate: p.gameDate, in: c, save: { context in
                    calls += 1; if calls == failAt { throw Failure.injected }; try context.save()
                }); XCTFail("save failure")
            } catch let error as CalendarAdvanceFailure {
                XCTAssertEqual(error.summary.days, failAt - 1); XCTAssertEqual(error.summary.lastSavedDate, start.adding(days: failAt - 1).description)
                XCTAssertEqual(error.summary.fatigueAfter, max(0, beforeFatigue - (failAt - 1) * 22))
            }
            XCTAssertEqual(s.revision, revision + failAt - 1)
        }
        while p.gameDate < "2027-03-31" { _ = try await offseasonBatch(p, s, c) }
        let revision = s.revision
        do {
            _ = try await CalendarProgression.advanceOffseason(player: p, state: s, seasonYear: 2026, revision: revision, expectedDate: p.gameDate, confirmAnniversary: true, in: c, save: { _ in throw Failure.injected }); XCTFail("birthday failure")
        } catch {}
        XCTAssertEqual(p.gameDate, "2027-03-31"); XCTAssertEqual(try s.age(of: p), 16); XCTAssertEqual(s.revision, revision)
        _ = try await offseasonBatch(p, s, c, confirmed: true)
        XCTAssertEqual(p.gameDate, "2027-04-01"); XCTAssertEqual(try s.age(of: p), 17)
    }
    func testOffseasonUsesLegacyAnniversaryRatherThanUnconditionallyAgingAtOpening() async throws {
        let (container, p, s) = try offseasonFixture(), c = container.mainContext
        // Seed the pre-observation legacy fixture before assigning its original anniversary.
        for report in try c.fetch(FetchDescriptor<CareerScoutingReport>()) { c.delete(report) }
        // Represent a legacy save whose origin predates the new affiliation record.
        for row in try c.fetch(FetchDescriptor<CareerAffiliationRecord>()) { c.delete(row) }
        s.originDate = "2026-02-01"; p.gameDate = "2027-01-20"; try c.save()
        try CareerPathStore.addMissing(in:c)
        let plan = try XCTUnwrap(CareerSeasonStore.offseason(player: p, state: s, in: c))
        XCTAssertEqual(plan.seasonYear, 2026); XCTAssertEqual(plan.age, 16); XCTAssertEqual(plan.targetAge, 17)
        let stopped = try await offseasonBatch(p, s, c)
        XCTAssertEqual(stopped.days, 11); XCTAssertEqual(stopped.stop, .anniversary); XCTAssertEqual(p.gameDate, "2027-01-31")
        _ = try await offseasonBatch(p, s, c, confirmed: true)
        XCTAssertEqual(try s.age(of: p), 17)
        while p.gameDate < "2027-04-01" { _ = try await offseasonBatch(p, s, c) }
        XCTAssertEqual(try s.age(of: p), 17)
    }
    func testOffseasonLeapYearGraduationAndNoAutomaticHighSchoolOrProSeasonAtNineteen() async throws {
        let (container, p, s) = try offseasonFixture(year: 2028), c = container.mainContext
        while p.gameDate < "2029-03-31" { _ = try await offseasonBatch(p, s, c, year: 2028) }
        XCTAssertEqual(try s.age(of: p), 18)
        _ = try await offseasonBatch(p, s, c, year: 2028, confirmed: true)
        XCTAssertEqual(p.gameDate, "2029-04-01"); XCTAssertEqual(try s.age(of: p), 19)
        XCTAssertTrue(try s.fixtures(for: p, year: 2029).isEmpty)
        XCTAssertEqual(p.schoolID, "hs-ref-001"); XCTAssertEqual(SeasonSchedule.academicStatus(age: 19), "고교 졸업 · 진로준비")
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).count, 30)
        let leap = try OffseasonPlan.make(summary: CareerSeasonStore.load(player: p, state: s, year: 2028, in: c), origin: GameDate(s.originDate), startAge: p.startAge, today: GameDate("2029-02-28"))
        XCTAssertEqual(leap.remainingDays, 32)
        // The preceding 2027 offseason includes February29,2028.
        let league2027 = try league(on: "2028-03-31", year: 2027)
        let leapPlan = try OffseasonPlan.make(summary: CareerSeasonSummary(league: league2027, totals: PersonalSeasonTotals()), origin: GameDate("2026-04-01"), startAge: 16, today: GameDate("2028-02-28"))
        XCTAssertEqual(leapPlan.remainingDays, 33)
    }
    func testOffseasonDiskPartialAcrossNewYearReloadPreservesRecordsAndOtherRole() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("offseason.store")
        var savedID: UUID!, oldTotals: CareerSeasonSummary!, oldPayloads: [String: Data] = [:]
        do {
            let container = try CareerStore.makeContainer(url: url), c = container.mainContext
            var draft = PlayerDraft(); draft.schoolID = "hs-ref-001"; draft.role = .pitcher; draft.name = "OffPitch"
            let p = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: c)
            draft.role = .batter; draft.name = "OffBatter"; _ = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: c)
            let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id })
            _ = try finishSeason(player: p, state: s, in: c); try CalendarProgression.advanceDay(player: p, state: s, revision: s.revision, in: c)
            savedID = p.id; oldTotals = try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c)
            oldPayloads = Dictionary(uniqueKeysWithValues: try c.fetch(FetchDescriptor<CareerMatchRecord>()).map { ($0.key, $0.payload) })
            for _ in 0..<4 { _ = try await offseasonBatch(p, s, c) }
            XCTAssertEqual(p.gameDate, "2027-01-21")
        }
        let reopened = try CareerStore.makeContainer(url: url), c = reopened.mainContext
        let players = try c.fetch(FetchDescriptor<CareerPlayer>()), p = try XCTUnwrap(players.first { $0.id == savedID })
        let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id })
        XCTAssertEqual(p.gameDate, "2027-01-21"); XCTAssertEqual(try CareerSeasonStore.offseason(player: p, state: s, in: c)?.seasonYear, 2026)
        while p.gameDate < "2027-03-31" { _ = try await offseasonBatch(p, s, c) }
        _ = try await offseasonBatch(p, s, c, confirmed: true)
        XCTAssertEqual(try CareerSeasonStore.load(player: p, state: s, year: 2026, in: c), oldTotals)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: try c.fetch(FetchDescriptor<CareerMatchRecord>()).map { ($0.key, $0.payload) }), oldPayloads)
        XCTAssertEqual(players.first { $0.id != p.id }?.gameDate, "2026-04-01")
    }
    func testOffseasonCannotSkipAnUnfinishedMatchFromAnotherDate() async throws {
        let (container, p, s) = try offseasonFixture(), c = container.mainContext
        let originalDate = p.gameDate
        p.gameDate = "2027-04-01"; s.actionDate = p.gameDate; try c.save()
        _ = try CareerMatchStore.start(player: p, state: s, in: c)
        p.gameDate = originalDate; s.actionDate = nil; try c.save()
        do { _ = try await offseasonBatch(p, s, c); XCTFail("future pending match") } catch {}
        XCTAssertEqual(p.gameDate, originalDate)
    }

}

extension CareerCalendarTests {
    func testCareerPathAgeRoutesDoNotCreateAdmissions() throws {
        XCTAssertEqual(CareerAffiliation.stage(age:18),.school)
        XCTAssertEqual(CareerAffiliation.stage(age:19),.preparation)
        XCTAssertEqual(CareerAffiliation.stage(age:20),.unsigned)
        XCTAssertTrue(CareerRoute.routes(age:19)[0].status.contains("20세"))
        for age in [20,23] { XCTAssertTrue(CareerRoute.routes(age:age)[0].status.contains("심사 대기")) }
        XCTAssertTrue(CareerRoute.routes(age:24)[1].status.contains("종료"))
    }
    func testCareerPathGraduationAndAdultTransitionAreAtomicAndDoNotChangePlayerValues() throws {
        let (container,player,state) = try fixture(date:"2029-03-31")
        let c = container.mainContext
        let school = player.schoolID, speed = player.speed, pitches = player.pitches.sorted {$0.code < $1.code}.map(\.mastery)
        state.actionDate = player.gameDate; try c.save()
        try CalendarProgression.advanceDay(player:player,state:state,revision:state.revision,confirmAnniversary:true,in:c)
        let row = try XCTUnwrap(CareerPathStore.record(player:player,calendar:state,in:c))
        XCTAssertEqual(try row.snapshot(player:player,calendar:state).entries.map(\.stage),[.school,.preparation])
        player.gameDate = "2030-03-31";state.actionDate = player.gameDate;try c.save()
        enum Failure: Error { case disk }
        let payload = row.payload, revision = state.revision, fatigue = player.fatigue
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:player,state:state,revision:revision,confirmAnniversary:true,in:c,save:{_ in throw Failure.disk}))
        XCTAssertEqual(player.gameDate,"2030-03-31");XCTAssertEqual(row.payload,payload);XCTAssertEqual(state.revision,revision);XCTAssertEqual(player.fatigue,fatigue)
        try CalendarProgression.advanceDay(player:player,state:state,revision:revision,confirmAnniversary:true,in:c)
        XCTAssertEqual(try row.snapshot(player:player,calendar:state).entries.map(\.stage),[.school,.preparation,.unsigned])
        XCTAssertEqual(player.schoolID,school);XCTAssertEqual(player.speed,speed);XCTAssertEqual(player.pitches.sorted {$0.code < $1.code}.map(\.mastery),pitches)
        let frozen = row.payload;try CareerPathStore.addMissing(in:c);XCTAssertEqual(row.payload,frozen)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:player,state:state,revision:revision,automaticRest:true,in:c))
    }
    func testCareerPathBatchStopsBeforeGraduation() async throws {
        let (container,player,state) = try fixture(date:"2029-03-30")
        let result = try await CalendarProgression.advanceOffDays(player:player,state:state,in:container.mainContext)
        XCTAssertEqual(result.stop,.anniversary);XCTAssertEqual(player.gameDate,"2029-03-31")
        XCTAssertEqual(try CareerPathStore.record(player:player,calendar:state,in:container.mainContext)?.snapshot(player:player,calendar:state).current.stage,.school)
    }
    func testCareerPathV8MigrationKeepsCurrentSaveAndDoesNotInventHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url = dir.appendingPathComponent("career-path.store"),schools = try SchoolCatalog.load()
        let id:UUID = try autoreleasepool {
            let schema = Schema(versionedSchema:CareerSchemaV8.self)
            let c = try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
            c.mainContext.autosaveEnabled = false
            var draft = PlayerDraft();draft.name = "진로이전";draft.schoolID = schools[0].id;draft.role = .pitcher
            let p = CareerPlayer(draft:draft,school:schools[0]);let calendar = CareerCalendarState(player:p,schools:schools,legacySave:false)
            p.gameDate = "2030-04-01";p.fatigue = 61;p.speed = 63.125;calendar.revision = 7;calendar.actionDate = p.gameDate
            c.mainContext.insert(p);c.mainContext.insert(calendar);try c.mainContext.save();return p.id
        }
        var payload = ""
        do {
            let migrated = try CareerStore.makeContainer(url:url)
            let c = migrated.mainContext
            let player = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first)
            let calendar = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            XCTAssertEqual(player.id,id);XCTAssertEqual(player.speed,63.125);XCTAssertEqual(player.fatigue,61)
            XCTAssertEqual(calendar.revision,7);XCTAssertEqual(calendar.actionDate,"2030-04-01");XCTAssertEqual(player.pitches.count,4)
            let row = try XCTUnwrap(CareerPathStore.record(player:player,calendar:calendar,in:c));let history = try row.snapshot(player:player,calendar:calendar)
            XCTAssertEqual(history.source,"legacy-v1");XCTAssertEqual(history.entries.count,1);XCTAssertEqual(history.current.stage,.unsigned)
            XCTAssertEqual(history.current.since,"2030-04-01");payload = row.payload
        }
        let reopened = try CareerStore.makeContainer(url:url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CareerAffiliationRecord>()).first?.payload,payload)
    }
    func testCareerPathCorruptionIsNotReset() throws {
        let (container,player,state) = try fixture()
        let c = container.mainContext,row = try XCTUnwrap(CareerPathStore.record(player:player,calendar:state,in:container.mainContext))
        row.payload = "broken";try c.save()
        XCTAssertThrowsError(try CareerPathStore.addMissing(in:c));XCTAssertEqual(row.payload,"broken")
    }
}

extension CareerCalendarTests {
    func testCareerPathV8MigrationPreservesBothPendingMatchesAndCompletionOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url = dir.appendingPathComponent("pending-career.store"),schools = try SchoolCatalog.load()
        let original:[UUID:Data] = try autoreleasepool {
            let schema = Schema(versionedSchema:CareerSchemaV8.self)
            let old = try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
            let c = old.mainContext;c.autosaveEnabled = false
            var values:[UUID:Data] = [:]
            for role in PlayerRole.allCases {
                var draft = PlayerDraft();draft.name = role == .batter ? "이어타자":"이어투수";draft.role = role;draft.schoolID = schools[0].id
                let p = try CareerStore.create(draft,schools:schools,in:c)
                let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id })
                try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
                let r = try CareerMatchStore.start(player:p,state:s,in:c)
                try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? "four-seam":nil,in:c)
                values[p.id] = r.payload
            }
            return values
        }
        let migrated = try CareerStore.makeContainer(url:url),c = migrated.mainContext
        for p in try c.fetch(FetchDescriptor<CareerPlayer>()) {
            let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id })
            let r = try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first { $0.playerID == p.id })
            XCTAssertEqual(r.payload,original[p.id]);XCTAssertFalse(r.completed)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,original[p.id])
            XCTAssertEqual(try CareerPathStore.record(player:p,calendar:s,in:c)?.snapshot(player:p,calendar:s).entries.count,1)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let payload = r.payload, fatigue = p.fatigue, revision = s.revision
            XCTAssertTrue(r.completed)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(r.payload,payload);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
        }
    }
}

extension CareerCalendarTests {
    private func evaluationFixture(date:String = "2030-06-30",role:PlayerRole = .pitcher) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let (container,p,s) = try fixture(role:role),c = container.mainContext
        p.gameDate = "2029-04-01";try CareerPathStore.synchronize(player:p,calendar:s,in:c)
        p.gameDate = date;try CareerPathStore.synchronize(player:p,calendar:s,in:c);try c.save()
        return (container,p,s)
    }
    func testContractWindowBoundariesAndRouteEligibility() throws {
        for month in [4,7,11] {
            for day in [1,14] {XCTAssertEqual(ContractEvaluationWindow.containing(try GameDate(String(format:"2030-%02d-%02d",month,day)))?.month,month)}
            XCTAssertNil(ContractEvaluationWindow.containing(try GameDate(String(format:"2030-%02d-15",month))))
        }
        let april = ContractEvaluationWindow(year:2030,month:4),july = ContractEvaluationWindow(year:2030,month:7)
        XCTAssertTrue(april.routes(age:19,affiliation:.preparation).isEmpty)
        XCTAssertEqual(april.routes(age:20,affiliation:.unsigned),["국내 신인","대학 입단"])
        XCTAssertEqual(july.routes(age:23,affiliation:.unsigned),["국내 신인"])
        XCTAssertEqual(april.routes(age:24,affiliation:.unsigned),["국내 전력/검증 테스트"])
        XCTAssertTrue(ContractEvaluationWindow(year:2030,month:11).routes(age:25,affiliation:.unsigned).isEmpty)
    }
    func testContractEvaluationFreezesCurrentInputsSeparatelyFrom28DayReportsBothRoles() throws {
        for role in PlayerRole.allCases {
            let (container,p,s) = try evaluationFixture(date:"2030-04-01",role:role),c = container.mainContext
            let reports = try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload)
            XCTAssertTrue(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c));try c.save()
            let row = try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),payload = row.payload
            let saved = try row.snapshot(player:p,calendar:s)
            XCTAssertEqual(saved.routes,["국내 신인","대학 입단"]);XCTAssertEqual(saved.observation.role,role)
            p.contact += 1;p.speed += 1;try c.save()
            XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
            XCTAssertEqual(row.payload,payload)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload),reports)
            XCTAssertNotNil(saved.selection);XCTAssertTrue(saved.pending.contains(where:{$0.contains("후속")}))
        }
    }
    func testContractEvaluationBulkStopsAtArrivalAndConfirmationDoesNotConsumeDay() async throws {
        let (container,p,s) = try evaluationFixture(),c = container.mainContext
        let before = p.fatigue,result = try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(result.days,1);XCTAssertEqual(result.stop,.evaluation);XCTAssertEqual(p.gameDate,"2030-07-01")
        XCTAssertEqual(p.fatigue,max(0,before-22))
        let row = try XCTUnwrap(ContractEvaluationStore.unread(player:p,calendar:s,in:c)),frozen = row.payload
        XCTAssertEqual(try row.snapshot(player:p,calendar:s).routes,["국내 신인"])
        let zero = try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(zero.days,0);XCTAssertEqual(zero.stop,.evaluation)
        let date = p.gameDate,fatigue = p.fatigue,revision = s.revision
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c))
        try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:date,revision:revision,in:c)
        XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision);XCTAssertEqual(row.payload,frozen)
        try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c)
        XCTAssertEqual(p.gameDate,"2030-07-02");XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).count,1)
    }
    func testContractEvaluationArrivalSaveFailureRollsBackLedgerDateAndRecovery() throws {
        let (container,p,s) = try evaluationFixture(),c = container.mainContext
        let date = p.gameDate,fatigue = p.fatigue,revision = s.revision
        enum Failure:Error {case disk}
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c,save:{_ in throw Failure.disk}))
        XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
        XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).isEmpty)
        try CalendarProgression.advanceDay(player:p,state:s,revision:revision,automaticRest:true,in:c)
        XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).count,1)
    }
    func testContractEvaluationAcknowledgeFailureAndStaleInputDoNotUnlock() throws {
        let (container,p,s) = try evaluationFixture(date:"2030-04-02"),c = container.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let row = try XCTUnwrap(ContractEvaluationStore.unread(player:p,calendar:s,in:c)),payload = row.payload
        enum Failure:Error {case disk}
        XCTAssertThrowsError(try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:p.gameDate,revision:s.revision,in:c,save:{_ in throw Failure.disk}))
        XCTAssertFalse(row.acknowledged);XCTAssertEqual(row.payload,payload)
        XCTAssertThrowsError(try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:p.gameDate,revision:s.revision+1,in:c))
        try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:p.gameDate,revision:s.revision,in:c)
        try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:p.gameDate,revision:s.revision,in:c,save:{_ in XCTFail("duplicate acknowledgement saved")})
    }
    func testContractEvaluationMissedWindowsAndNovemberDoNotInventProfessionalReviews() throws {
        let (container,p,s) = try evaluationFixture(date:"2030-04-15"),c = container.mainContext
        XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
        p.gameDate = "2030-11-01";try c.save()
        XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
        XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).isEmpty)
    }
    func testContractEvaluationFirstEligibleBirthdayInsideWindow() throws {
        let (container,p,s) = try fixture(),c = container.mainContext
        for row in try c.fetch(FetchDescriptor<CareerAffiliationRecord>()) {c.delete(row)}
        s.originDate = "2026-04-10";p.gameDate = "2030-04-09";try c.save();try CareerPathStore.addMissing(in:c)
        XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
        try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,confirmAnniversary:true,in:c)
        let row = try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        XCTAssertEqual(try row.snapshot(player:p,calendar:s).evaluatedDate,"2030-04-10")
    }
    func testContractEvaluationV9DiskMigrationPreservesPendingMatchesAndFreezesOnlyCurrentWindow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url = dir.appendingPathComponent("evaluation.store"),schools = try SchoolCatalog.load()
        let payloads:[UUID:Data] = try autoreleasepool {
            let schema = Schema(versionedSchema:CareerSchemaV9.self)
            let old = try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)]),c = old.mainContext
            c.autosaveEnabled = false;var result:[UUID:Data] = [:]
            for role in PlayerRole.allCases {
                var draft = PlayerDraft();draft.name = "평가이전";draft.role = role;draft.schoolID = schools[0].id
                let p = try CareerStore.create(draft,schools:schools,in:c)
                let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == p.id})
                try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
                let r = try CareerMatchStore.start(player:p,state:s,in:c)
                try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? "four-seam":nil,in:c)
                result[p.id] = r.payload
            }
            return result
        }
        let new = try CareerStore.makeContainer(url:url),c = new.mainContext
        for p in try c.fetch(FetchDescriptor<CareerPlayer>()) {
            let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == p.id})
            let r = try XCTUnwrap(c.fetch(FetchDescriptor<CareerMatchRecord>()).first {$0.playerID == p.id})
            XCTAssertEqual(r.payload,payloads[p.id]);XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).isEmpty)
            try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c)
            let frozen = r.payload,fatigue = p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:r,revision:r.revision,input:.automatic,in:c))
            XCTAssertEqual(r.payload,frozen);XCTAssertEqual(p.fatigue,fatigue)
        }
    }
    func testContractEvaluationCorruptionIsNotReplaced() throws {
        let (container,p,s) = try evaluationFixture(date:"2030-07-10"),c = container.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let row = try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        row.payload = Data("broken".utf8);try c.save()
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c));XCTAssertEqual(row.payload,Data("broken".utf8))
    }
}

extension CareerCalendarTests {
    func testContractEvaluationV9AdultImportReopenAndNextYearKeepOriginalWindowBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url = dir.appendingPathComponent("adult-window.store"),schools = try SchoolCatalog.load()
        try autoreleasepool {
            let schema = Schema(versionedSchema:CareerSchemaV9.self)
            let old = try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)]),c = old.mainContext
            c.autosaveEnabled = false
            var draft = PlayerDraft();draft.name = "창이전";draft.schoolID = schools[0].id
            let p = try CareerStore.create(draft,schools:schools,in:c)
            let s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            p.gameDate = "2029-04-01";try CareerPathStore.synchronize(player:p,calendar:s,in:c)
            p.gameDate = "2030-07-10";try CareerPathStore.synchronize(player:p,calendar:s,in:c);try c.save()
        }
        var frozen = Data()
        do {
            let store = try CareerStore.makeContainer(url:url),c = store.mainContext
            let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let row = try XCTUnwrap(ContractEvaluationStore.unread(player:p,calendar:s,in:c));frozen = row.payload
            XCTAssertEqual(try row.snapshot(player:p,calendar:s).evaluatedDate,"2030-07-10")
            try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:p.gameDate,revision:s.revision,in:c)
            p.contact += 1;try c.save()
        }
        let store = try CareerStore.makeContainer(url:url),c = store.mainContext
        let p = try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s = try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let previous = try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        XCTAssertEqual(previous.payload,frozen);XCTAssertTrue(previous.acknowledged)
        p.gameDate = "2031-04-01";try c.save()
        XCTAssertTrue(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c));try c.save()
        XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).count,2)
        XCTAssertEqual(previous.payload,frozen)
    }
    func testContractEvaluationBulkPartialFailureKeepsOnlyCommittedDatesAndCanRetry() async throws {
        let (store,p,s) = try evaluationFixture(date:"2030-06-29"),c = store.mainContext
        enum Failure:Error {case disk}
        do {
            _ = try await CalendarProgression.advanceOffDays(player:p,state:s,in:c,save:{c in
                if p.gameDate == "2030-07-01" {throw Failure.disk};try c.save()
            });XCTFail("expected injected save failure")
        } catch let error as CalendarAdvanceFailure {
            XCTAssertEqual(error.summary.days,1);XCTAssertEqual(error.summary.lastSavedDate,"2030-06-30")
        }
        XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).isEmpty)
        let retry = try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(retry.days,1);XCTAssertEqual(retry.stop,.evaluation)
        XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).count,1)
    }
}


extension CareerCalendarTests {
    private func selectionSeason(_ role:PlayerRole,modeSplit:Bool=false,count:Int?=nil,legacyURL:URL?=nil,legacyVersion:Int=10) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let store:ModelContainer
        if let legacyURL {
            let type:any VersionedSchema.Type
            if legacyVersion == 12 {type=CareerSchemaV12.self} else if legacyVersion == 11 {type=CareerSchemaV11.self} else {type=CareerSchemaV10.self}
            let schema=Schema(versionedSchema:type)
            store=try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:legacyURL,cloudKitDatabase:.none)])
            store.mainContext.autosaveEnabled=false
        } else {store=try CareerStore.makeContainer(inMemory:true)}
        let c=store.mainContext
        var draft=PlayerDraft();draft.name="선발선수";draft.role=role;draft.schoolID="hs-ref-001"
        let p=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:c)
        let s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        p.gameDate="2029-04-01";try CareerPathStore.synchronize(player:p,calendar:s,in:c)
        p.gameDate="2030-04-01";try CareerPathStore.synchronize(player:p,calendar:s,in:c);try c.save()
        let fixtures=try s.fixtures(for:p,year:2028).filter {$0.isAppearance(for:role)}
        for (index,fixture) in fixtures.prefix(count ?? (role == .batter ? 12:6)).enumerated() {
            p.gameDate=fixture.date.description
            var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",
                values:PlayerArchetype.initial(for:role).values,seed:UInt64(700+index),home:fixture.homeID == p.schoolID,tracked:true)
            try ScoutingReferenceSimulation.run(&match,mode:modeSplit && index%2 == 1 ? .direct:.automatic)
            let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
        }
        p.gameDate="2030-04-01";p.contact=80;p.power=80;p.discipline=80;p.defense=80
        let abilities=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c));try abilities.grow(.mental,to:80)
        if role == .pitcher {
            for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try abilities.grow(kind,to:80)}
            for pitch in p.pitches {pitch.mastery=80}
        }
        try c.save();return (store,p,s)
    }
    func testDomesticSelectionGraduationSourceAndBothRoutesUseEntryCriteria() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try selectionSeason(role),c=store.mainContext
            let matchBytes=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            try ContractEvaluationStore.registerCurrent(in:c)
            let row=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
            let value=try row.snapshot(player:p,calendar:s),selection=try XCTUnwrap(value.selection)
            XCTAssertEqual(value.version,2);XCTAssertEqual(selection.sample?.kind,"졸업 고교 공식시즌")
            XCTAssertTrue(value.observation.groups.isEmpty,"730일 졸업 예외와365일 관찰을 혼합하지 않는다")
            XCTAssertEqual(Set(selection.results.filter(\.selected).map(\.route)),Set([.rookie,.college]))
            XCTAssertEqual(selection.results.filter(\.selected).count,2)
            XCTAssertTrue(selection.results.allSatisfy {$0.c == DomesticSelection.minimum($0.role,route:$0.route)})
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matchBytes)
            let bytes=row.payload;p.contact=99;try c.save();try ContractEvaluationStore.registerCurrent(in:c)
            XCTAssertEqual(row.payload,bytes);XCTAssertFalse(c.hasChanges)
        }
    }
    func testDomesticSelectionMissingSamplesNeverInventAdmission() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try evaluationFixture(date:"2030-04-01",role:role),c=store.mainContext
            try ContractEvaluationStore.registerCurrent(in:c)
            let selection=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).selection)
            XCTAssertNil(selection.sample);XCTAssertTrue(selection.results.allSatisfy {!$0.selected && $0.reasons.contains(where:{$0.contains("표본")})})
            XCTAssertTrue(selection.picks.allSatisfy {$0.candidateID.hasPrefix("npc/")})
        }
    }
    func testDomesticSelectionSourceCannotCombineModesAndAge21CannotUseGraduationException() throws {
        let (store,p,s)=try selectionSeason(.batter,modeSplit:true,count:10),c=store.mainContext
        let live=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        let selected=try ContractEvaluationStore.graduationSample(player:p,calendar:s,observation:live,in:c)
        XCTAssertNil(selected,"직접/자동 각5경기를 합쳐40PA를 충족하지 않는다")
        p.gameDate="2031-04-01";try c.save()
        let age21=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        XCTAssertEqual(age21.age,21);XCTAssertNil(try ContractEvaluationStore.graduationSample(player:p,calendar:s,observation:age21,in:c))
    }
    func testDomesticSelectionJulyCarriesAprilNPCSeatsAndBudgetWithoutReselection() throws {
        let (store,p,s)=try selectionSeason(.pitcher),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let april=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),bytes=april.payload
        let a=try XCTUnwrap(april.snapshot(player:p,calendar:s).selection)
        try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:april.key,date:p.gameDate,revision:s.revision,in:c)
        p.gameDate="2030-07-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let july=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).selection)
        XCTAssertEqual(july.carried,a.picks.filter {$0.seatID.hasPrefix("rookie/") && $0.candidateID.hasPrefix("npc/")})
        XCTAssertFalse(july.carried.contains {$0.candidateID.hasPrefix("player/")})
        XCTAssertTrue(july.results.allSatisfy {$0.route == .rookie})
        XCTAssertEqual(Set(july.picks.map(\.seatID)).count,july.picks.count)
        for club in Set(july.seats.filter {$0.route == .rookie}.map(\.name)) {
            let seats=july.seats.filter {$0.route == .rookie && $0.name == club}
            let picks=july.picks.filter {pick in seats.contains {$0.id == pick.seatID}}
            XCTAssertLessThanOrEqual(picks.count,3);XCTAssertLessThanOrEqual(picks.reduce(0){$0+$1.cost},seats[0].budget)
        }
        XCTAssertEqual(april.payload,bytes)
    }
    func testDomesticSelectionFieldThresholdsDifferFromProAndCollege() throws {
        let (store,p,s)=try evaluationFixture(date:"2030-04-01",role:.batter),c=store.mainContext
        var observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        // Real initial primary mastery60 and defense <70 must not inherit the pro70 gate.
        XCTAssertEqual(observation.positionMastery,60)
        XCTAssertTrue(DomesticSelection.fieldCondition("field",route:.college,observation:observation).isEmpty)
        if p.defense >= 50 {XCTAssertTrue(DomesticSelection.fieldCondition("field",route:.rookie,observation:observation).isEmpty)}
        observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        XCTAssertEqual(DomesticSelection.minimum("field",route:.rookie),50)
        XCTAssertEqual(DomesticSelection.minimum("field",route:.college),45)
        XCTAssertEqual(DomesticSelection.cost(0),100);XCTAssertEqual(DomesticSelection.cost(5),130);XCTAssertEqual(DomesticSelection.cost(100),200)
    }
    func testDomesticSelectionBudgetCompetitionAndTieOrder() throws {
        let (store,p,s)=try selectionSeason(.pitcher),c=store.mainContext
        let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        let sample=try XCTUnwrap(ContractEvaluationStore.graduationSample(player:p,calendar:s,observation:observation,in:c))
        let h=try XCTUnwrap(observation.grades[0].score),f=h-52+sample.comparison.correction
        let seat=DomesticSelectionSeat(id:"rookie/test/1",name:"검증 구단",route:.rookie,order:0,roles:["starter"],budget:99)
        let budget=DomesticSelection.simulate(observation:observation,seats:[seat],candidates:[],carried:[],sample:sample,sampleReason:"")
        XCTAssertFalse(budget.results[0].selected);XCTAssertTrue(budget.results[0].reasons.contains {$0.contains("예산 부족")})
        let funded=DomesticSelectionSeat(id:seat.id,name:seat.name,route:.rookie,order:0,roles:seat.roles,budget:500)
        let npc=DomesticSelectionCandidate(id:"npc/first",role:"starter",h:h,p:sample.comparison.correction)
        let tied=DomesticSelection.simulate(observation:observation,seats:[funded],candidates:[npc],carried:[],sample:sample,sampleReason:"")
        XCTAssertEqual(tied.picks[0].candidateID,"npc/first");XCTAssertEqual(tied.picks[0].f,ScoutingContractFit.round(f));XCTAssertTrue(tied.results[0].reasons.contains {$0.contains("경쟁 탈락")})
        let none=DomesticSelection.simulate(observation:observation,seats:[funded],candidates:[],carried:tied.picks,sample:sample,sampleReason:"")
        XCTAssertFalse(none.results[0].selected);XCTAssertEqual(none.results[0].availableSeats,0)
    }
    func testDomesticSelectionOldV1PayloadIsNotRejudgedAndMalformedDecisionIsRejected() throws {
        let (store,p,s)=try evaluationFixture(date:"2030-04-01"),c=store.mainContext
        let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        let old=ContractEvaluationSnapshot(rule:"contracts-window-v1",window:ContractEvaluationWindow(year:2030,month:4),evaluatedDate:p.gameDate,
            calendarRevision:s.revision,affiliation:CareerAffiliationEntry(stage:.unsigned,since:p.gameDate,schoolID:nil,schoolName:nil),routes:["국내 신인","대학 입단"],observation:observation,pending:["선발 심사 대기"])
        let row=try CareerContractEvaluation(playerID:p.id,snapshot:old);c.insert(row);try c.save();let bytes=row.payload
        try ContractEvaluationStore.registerCurrent(in:c);XCTAssertEqual(row.payload,bytes);XCTAssertNil(try row.snapshot(player:p,calendar:s).selection)
        p.gameDate="2030-07-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let new=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),frozen=new.payload
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:frozen) as? [String:Any])
        var selection=try XCTUnwrap(json["selection"] as? [String:Any]);selection["picks"]=[];json["selection"]=selection
        new.payload=try JSONSerialization.data(withJSONObject:json);try c.save()
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c));XCTAssertNotEqual(new.payload,frozen)
    }
}


extension CareerCalendarTests {
    func testDomesticSelectionExactSampleMinimumAndGraduation730DayBoundary() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try selectionSeason(role),c=store.mainContext
            let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
            let old=try XCTUnwrap(ContractEvaluationStore.graduationSample(player:p,calendar:s,observation:observation,in:c))
            let ref=try XCTUnwrap(old.comparison.reference),date=try GameDate(p.gameDate),window=ContractEvaluationWindow(year:2030,month:4)
            func decision(n:Int,days:Int) -> DomesticSelection {
                var line=MatchLine(),perf=MatchScoutingPerformance.tracked
                if role == .batter {line.plateAppearances=n;line.atBats=n;line.hits=10;perf.singles=10;perf.inputs?.automatic=40}
                else {line.pitchingOuts=n;line.pitches=80;line.hitsAllowed=2;line.pitchingWalks=1;line.pitchingStrikeouts=5;perf.battersFaced=20;perf.inputs?.automatic=80}
                let totals=PersonalSeasonTotals(games:1,line:line),v=perf.contribution(line,role:role)!
                let comparison=ScoutingPerformanceComparison(id:ref.environment,totals:totals,performance:perf,reference:ref,value:v,
                    correction:ScoutingContractFit.correction(value:v,reference:ref.value!,n:perf.sample(line,role:role)),verified:true,reason:"경계 검증")
                let sample=DomesticSelectionSample(kind:"졸업 고교 공식시즌",endDate:date.adding(days:-days).description,comparison:comparison)
                let seed=p.id.uuidString+"/2030",seats=DomesticSelection.market(seed:seed),candidates=DomesticSelection.candidates(seed:seed,month:4)
                let result=DomesticSelection.simulate(observation:observation,seats:seats,candidates:candidates,carried:[],sample:sample,sampleReason:"")
                return DomesticSelection(rule:"domestic-selection-v1",seed:seed,priorMarket:"연간 신규 시장",sample:sample,sampleReason:"",seats:seats,candidates:candidates,carried:[],picks:result.picks,results:result.results)
            }
            let minimum=role == .batter ? 40:45
            XCTAssertNoThrow(try decision(n:minimum,days:730).validate(observation:observation,window:window))
            XCTAssertThrowsError(try decision(n:minimum-1,days:730).validate(observation:observation,window:window))
            XCTAssertThrowsError(try decision(n:minimum,days:731).validate(observation:observation,window:window))
        }
    }
    func testDomesticSelectionAnnualCatalogIsFixedAndDoesNotReuseProRoleMinimums() throws {
        let seed="career/2030",market=DomesticSelection.market(seed:seed)
        XCTAssertEqual(market,DomesticSelection.market(seed:seed))
        XCTAssertEqual(market.filter {$0.route == .rookie}.count,18)
        XCTAssertEqual(market.filter {$0.route == .college}.count,24)
        for route in DomesticSelectionRoute.allCases {
            for name in Set(market.filter {$0.route == route}.map(\.name)) {
                let rows=market.filter {$0.name == name}
                XCTAssertEqual(rows.count,route == .rookie ? 3:4)
                if route == .college {XCTAssertEqual(Set(rows.flatMap(\.roles)),Set(DomesticSelection.roles))}
            }
        }
        XCTAssertEqual(DomesticSelection.candidates(seed:seed,month:4),DomesticSelection.candidates(seed:seed,month:4))
        XCTAssertNotEqual(DomesticSelection.candidates(seed:seed,month:4),DomesticSelection.candidates(seed:seed,month:7))
        XCTAssertEqual(DomesticSelection.minimum("starter",route:.rookie),52)
        XCTAssertEqual(DomesticSelection.minimum("starter",route:.college),47)
    }
}


extension CareerCalendarTests {
    func testDomesticOffersIssueExactlyOnceFromBothRoleSelectionsAndFreezeTerms() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try selectionSeason(role),c=store.mainContext
            let date=p.gameDate,fatigue=p.fatigue,revision=s.revision
            try ContractEvaluationStore.registerCurrent(in:c)
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),raw=evaluation.payload
            let row=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first),bytes=row.payload
            let packet=try row.snapshot(evaluation:evaluation,player:p,calendar:s),snapshot=try evaluation.snapshot(player:p,calendar:s)
            XCTAssertEqual(packet.offers.count,2);XCTAssertEqual(Set(packet.offers.map(\.route)),Set([.rookie,.college]))
            for offer in packet.offers {
                let result=try XCTUnwrap(snapshot.selection?.results.first {$0.id == offer.resultID})
                XCTAssertTrue(result.selected);XCTAssertEqual(offer.economicIndex,result.cost);XCTAssertEqual(offer.f,result.f)
                XCTAssertEqual(offer.expiresDate,"2030-04-07");XCTAssertEqual(offer.issuedDate,date)
            }
            XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            p.contact=99;try c.save()
            try ContractEvaluationStore.registerCurrent(in:c)
            XCTAssertFalse(try ContractOfferStore.insertCurrent(player:p,calendar:s,in:c))
            try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:evaluation.key,date:p.gameDate,revision:s.revision,in:c)
            XCTAssertEqual(row.payload,bytes);XCTAssertEqual(evaluation.payload,raw)
            XCTAssertFalse(c.hasChanges)
        }
    }
    func testDomesticOffersInclusiveSevenDaysAndWindowEndHaveNoWallClockDependency() throws {
        let (store,p,s)=try selectionSeason(.pitcher),c=store.mainContext
        p.gameDate="2030-04-12";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let row=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first)
        let packet=try row.snapshot(evaluation:evaluation,player:p,calendar:s),bytes=row.payload
        for offer in packet.offers {
            XCTAssertEqual(offer.expiresDate,"2030-04-14")
            XCTAssertFalse(try offer.isExpired(on:GameDate("2030-04-14")))
            XCTAssertTrue(try offer.isExpired(on:GameDate("2030-04-15")))
        }
        p.gameDate="2030-04-15";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).count,1)
        XCTAssertThrowsError(try DomesticOfferPacket.make(evaluation:evaluation.snapshot(player:p,calendar:s),key:evaluation.key,on:GameDate("2030-04-15")))
    }
    func testDomesticOffersNoSelectionPersistsEmptyReasonsAndCannotRerollAfterGrowth() throws {
        let (store,p,s)=try evaluationFixture(date:"2030-04-01",role:.batter),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let row=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first),bytes=row.payload
        let packet=try row.snapshot(evaluation:evaluation,player:p,calendar:s)
        XCTAssertTrue(packet.offers.isEmpty);XCTAssertTrue(packet.emptyReasons.contains {$0.contains("표본")})
        p.contact=100;p.power=100;p.discipline=100;try c.save()
        try ContractEvaluationStore.registerCurrent(in:c);XCTAssertEqual(row.payload,bytes)
    }
    func testDomesticOffersNewEvaluationAndIssuanceRollbackTogetherWithDateAndFatigue() throws {
        let (store,p,s)=try evaluationFixture(),c=store.mainContext,date=p.gameDate,fatigue=p.fatigue
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
        XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).isEmpty)
        XCTAssertTrue(try ContractOfferStore.records(player:p,calendar:s,in:c).isEmpty)
        try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c)
        XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).count,1)
    }
    func testDomesticOffersSaveFailureDoesNotLeaveAnIssuedPacketAndRetryIsSingle() throws {
        let (store,p,s)=try selectionSeason(.batter),c=store.mainContext
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).isEmpty)
        XCTAssertTrue(try ContractOfferStore.records(player:p,calendar:s,in:c).isEmpty)
        try ContractEvaluationStore.registerCurrent(in:c)
        XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).count,1)
        try ContractEvaluationStore.registerCurrent(in:c);XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).count,1)
    }
    func testDomesticOffersCorruptionAndOrphanAreErrorsAndNeverReplaced() throws {
        let (store,p,s)=try selectionSeason(.pitcher),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let row=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first),bytes=row.payload
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        var offers=try XCTUnwrap(json["offers"] as? [[String:Any]]);offers[0]["economicIndex"]=1;json["offers"]=offers
        row.payload=try JSONSerialization.data(withJSONObject:json);try c.save();let corrupt=row.payload
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c));XCTAssertEqual(row.payload,corrupt)
        row.payload=bytes;row.key += "-orphan";try c.save()
        XCTAssertThrowsError(try ContractOfferStore.records(player:p,calendar:s,in:c))
    }
    func testDomesticOffersV10DiskMigrationIssuesOnlyActiveFrozenSelectionAndReopenPreservesBytes() throws {
        for active in [true,false] {
            let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
            let url=dir.appendingPathComponent("offer-migration.store")
            var evaluationBytes=Data(),matchBytes:[String:Data]=[:],playerID=UUID()
            try autoreleasepool {
                let (store,p,s)=try selectionSeason(.pitcher,legacyURL:url),c=store.mainContext
                try ContractEvaluationStore.registerCurrent(in:c)
                let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
                evaluationBytes=evaluation.payload;playerID=p.id
                matchBytes=Dictionary(uniqueKeysWithValues:try c.fetch(FetchDescriptor<CareerMatchRecord>()).map {($0.key,$0.payload)})
                p.gameDate=active ? "2030-04-12":"2030-04-15";try c.save()
            }
            var issuedBytes:Data?
            try autoreleasepool {
                let store=try CareerStore.makeContainer(url:url),c=store.mainContext
                let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                XCTAssertEqual(p.id,playerID)
                let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
                XCTAssertEqual(evaluation.payload,evaluationBytes)
                XCTAssertEqual(Dictionary(uniqueKeysWithValues:try c.fetch(FetchDescriptor<CareerMatchRecord>()).map {($0.key,$0.payload)}),matchBytes)
                let rows=try ContractOfferStore.records(player:p,calendar:s,in:c)
                XCTAssertEqual(rows.count,active ? 1:0)
                if let row=rows.first {
                    issuedBytes=row.payload
                    let packet=try row.snapshot(evaluation:evaluation,player:p,calendar:s)
                    XCTAssertEqual(packet.issuedDate,"2030-04-12");XCTAssertEqual(packet.offers.count,2)
                }
            }
            let store=try CareerStore.makeContainer(url:url),c=store.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).first?.payload,issuedBytes)
        }
    }
    func testDomesticOffersOldV1EvaluationDoesNotProduceOffersAndJulyCollegeIsNotInvented() throws {
        let (store,p,s)=try selectionSeason(.batter),c=store.mainContext
        let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        let old=ContractEvaluationSnapshot(rule:"contracts-window-v1",window:ContractEvaluationWindow(year:2030,month:4),evaluatedDate:p.gameDate,
            calendarRevision:s.revision,affiliation:CareerAffiliationEntry(stage:.unsigned,since:p.gameDate,schoolID:nil,schoolName:nil),routes:["국내 신인","대학 입단"],observation:observation,pending:["당시 미기록"])
        let evaluation=try CareerContractEvaluation(playerID:p.id,snapshot:old);c.insert(evaluation);try c.save();let bytes=evaluation.payload
        try ContractEvaluationStore.registerCurrent(in:c);XCTAssertTrue(try ContractOfferStore.records(player:p,calendar:s,in:c).isEmpty)
        p.gameDate="2030-07-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let july=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),row=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first)
        XCTAssertTrue(try row.snapshot(evaluation:july,player:p,calendar:s).offers.allSatisfy {$0.route == .rookie})
        XCTAssertEqual(evaluation.payload,bytes)
    }
}


extension CareerCalendarTests {
    private func acceptance(_ role:PlayerRole,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState,DomesticOfferPacket) {
        let (store,p,s)=try selectionSeason(role,legacyURL:legacyURL,legacyVersion:12),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let offer=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first)
        return (store,p,s,try offer.snapshot(evaluation:evaluation,player:p,calendar:s))
    }
    func testContractAcceptanceBothRolesAndRoutesAtomicallyRegisterAndCloseOtherOffer() throws {
        for role in PlayerRole.allCases {for route in DomesticSelectionRoute.allCases {
            let (store,p,s,packet)=try acceptance(role),c=store.mainContext,offer=try XCTUnwrap(packet.offers.first {$0.route == route})
            let date=p.gameDate,fatigue=p.fatigue,revision=s.revision,school=p.schoolID
            let evalBytes=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
            let offerBytes=try ContractOfferStore.records(player:p,calendar:s,in:c).map(\.payload)
            let records=Dictionary(uniqueKeysWithValues:try c.fetch(FetchDescriptor<CareerMatchRecord>()).map {($0.key,$0.payload)})
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:revision,in:c)
            let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),member=try XCTUnwrap(value.current(on:GameDate(date)))
            XCTAssertEqual(value.decisions.filter {$0.kind == .accepted}.count,1);XCTAssertEqual(value.decisions.filter {$0.kind == .closed}.count,1)
            XCTAssertEqual(member.route,route);XCTAssertEqual(member.since,date);XCTAssertEqual(p.schoolID,school)
            XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision+1)
            XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload),evalBytes)
            XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).map(\.payload),offerBytes)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues:try c.fetch(FetchDescriptor<CareerMatchRecord>()).map {($0.key,$0.payload)}),records)
            let bytes=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:revision,in:c,save:{_ in XCTFail("duplicate save")})
            XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,bytes)
            let other=try XCTUnwrap(packet.offers.first {$0.id != offer.id})
            XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:other.id,accept:true,date:date,revision:s.revision,in:c))
            let plan=try s.competition(for:p,year:2030)
            XCTAssertEqual(plan.fixtures.count,90);XCTAssertEqual(try s.fixtures(for:p,year:2030).count,30)
            XCTAssertEqual(try s.competition(for:p,year:2028).teamID,school)
            XCTAssertTrue(try ContractEvaluationStore.unread(player:p,calendar:s,in:c) == nil)
            try ContractEvaluationStore.registerCurrent(in:c);XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).count,1)
        }}
    }
    func testContractRejectionKeepsOtherOfferAndNoAffiliationOrRecoveryReward() throws {
        let (store,p,s,packet)=try acceptance(.batter),c=store.mainContext,revision=s.revision,fatigue=p.fatigue
        for offer in packet.offers {
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:false,date:p.gameDate,revision:s.revision,in:c)
        }
        let journal=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        XCTAssertTrue(journal.memberships.isEmpty);XCTAssertEqual(journal.decisions.filter {$0.kind == .rejected}.count,2)
        XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision+2);XCTAssertTrue(try s.fixtures(for:p,year:2030).isEmpty)
        try ContractEvaluationStore.registerCurrent(in:c);XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).count,1)
    }
    func testContractAcceptSaveFailureRollsBackDecisionRegistrationAckAndRevision() throws {
        let (store,p,s,packet)=try acceptance(.pitcher),c=store.mainContext,revision=s.revision,fatigue=p.fatigue
        let offer=packet.offers[0]
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertNil(try ContractRegistrationStore.row(player:p,in:c));XCTAssertEqual(s.revision,revision);XCTAssertEqual(p.fatigue,fatigue)
        XCTAssertNotNil(try ContractEvaluationStore.unread(player:p,calendar:s,in:c));XCTAssertTrue(try s.fixtures(for:p,year:2030).isEmpty)
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c)
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships.count,1)
    }
    func testContractRejectThenAcceptPreservesRejectedDecisionAndFailedSecondSave() throws {
        let (store,p,s,packet)=try acceptance(.batter),c=store.mainContext
        let first=packet.offers[0],second=packet.offers[1]
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:first.id,accept:false,date:p.gameDate,revision:s.revision,in:c)
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),bytes=row.payload,revision=s.revision
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:second.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(s.revision,revision)
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:second.id,accept:true,date:p.gameDate,revision:revision,in:c)
        let journal=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        XCTAssertEqual(journal.decisions.first {$0.offerID == first.id}?.kind,.rejected)
        XCTAssertEqual(journal.memberships.first?.route,.college)
    }
    func testContractDecisionRejectsStaleExpiredAndPendingTrainingOrMatch() throws {
        let (store,p,s,packet)=try acceptance(.batter),c=store.mainContext,offer=packet.offers[0]
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision+1,in:c))
        let training=try CareerTrainingStore.start(player:p,state:s,kind:.contact,in:c),trainingBytes=training.payload
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c))
        XCTAssertEqual(training.payload,trainingBytes);XCTAssertNil(try ContractRegistrationStore.row(player:p,in:c))
        c.delete(training);try c.save()
        let oldDate=p.gameDate,fixture=try XCTUnwrap(s.fixtures(for:p,year:2028).first)
        p.gameDate=fixture.date.description
        let match=ScoutingReferenceSimulation.fixture(role:.batter,position:p.positionRaw,values:PlayerArchetype.initial(for:.batter).values,seed:19,home:fixture.homeID == p.schoolID)
        let record=try CareerMatchRecord(player:p,fixture:fixture,match:match);c.insert(record);p.gameDate=oldDate;try c.save();let bytes=record.payload
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c))
        XCTAssertEqual(record.payload,bytes);c.delete(record);p.gameDate="2030-04-08";try c.save()
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c))
        XCTAssertNil(try ContractRegistrationStore.row(player:p,in:c))
    }
    func testRegisteredAdultMatchResumeFailureAndResultXPApplyOnceBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,packet)=try acceptance(role),c=store.mainContext
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:packet.offers[0].id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertEqual(try record.snapshot().competition,"domestic-development")
            let npc=try XCTUnwrap(record.snapshot().npcFielders)
            XCTAssertEqual(npc.competition,"domestic-development");XCTAssertEqual(npc.year,2030)
            XCTAssertTrue((60...72).contains(npc.home.strength))
            XCTAssertTrue(try record.snapshot().scoutingEnvironment?.hasPrefix("domestic-development/") == true)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            let bytes=record.payload,revision=record.revision
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,bytes)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:revision,input:.automatic,in:c,save:{_ in throw MatchError.invalidRecord}))
            XCTAssertEqual(record.payload,bytes);XCTAssertFalse(record.completed)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:revision,input:.automatic,in:c)
            let completed=record.payload,fatigue=p.fatigue
            XCTAssertTrue(record.completed)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
            XCTAssertEqual(record.payload,completed);XCTAssertEqual(p.fatigue,fatigue)
            let league=try AnnualLeagueStore.load(player:p,state:s,year:2030,in:c)
            XCTAssertEqual(league.results.count,1);XCTAssertFalse(league.results[0].automatic)
            try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c)
            XCTAssertEqual(p.gameDate,"2030-04-02");XCTAssertEqual(try s.registration(for:p)?.level,"domestic-development")
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2030,in:c).totals.games,1)
        }
    }
    func testCollegeAndDomesticTermsGraduationAndRetainedRightsAreSeparate() throws {
        for route in DomesticSelectionRoute.allCases {
            let (store,p,s,packet)=try acceptance(.batter),c=store.mainContext,offer=try XCTUnwrap(packet.offers.first {$0.route == route})
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            let member=try XCTUnwrap(s.registration(for:p))
            XCTAssertEqual(member.economicEnd,"2031-03-31")
            XCTAssertTrue(try member.contains(GameDate("2031-04-01")))
            if route == .college {XCTAssertEqual(member.enrollmentEnd,"2034-03-31");XCTAssertFalse(try member.contains(GameDate("2034-04-01")))}
            else {XCTAssertNil(member.enrollmentEnd);XCTAssertTrue(try member.contains(GameDate("2040-04-01")))}
            p.gameDate="2030-07-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
            XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).count,1,"등록 선수를 무소속으로 재심사하지 않는다")
        }
    }
    func testMidseasonRegistrationOnlySchedulesFuturePersonalGamesAndSeparatesLeagueTeams() throws {
        let (store,p,s)=try selectionSeason(.pitcher),c=store.mainContext
        p.gameDate="2030-04-12";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),row=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first)
        let offer=try XCTUnwrap(row.snapshot(evaluation:evaluation,player:p,calendar:s).offers.first)
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let fixtures=try s.fixtures(for:p,year:2030)
        XCTAssertFalse(fixtures.isEmpty);XCTAssertTrue(fixtures.allSatisfy {$0.date >= (try! GameDate("2030-04-12"))})
        let league=try AnnualLeagueStore.load(player:p,state:s,year:2030,in:c)
        XCTAssertEqual(league.fixtures.count,90);XCTAssertEqual(league.standings.count,6)
        XCTAssertTrue(league.results.allSatisfy(\.automatic));XCTAssertTrue(league.standings.allSatisfy {$0.id.hasPrefix("dev-")})
        XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2030,in:c).totals.games,0)
    }
    func testRegistrationCorruptionStopsScheduleAndDoesNotResetJournal() throws {
        let (store,p,s,packet)=try acceptance(.pitcher),c=store.mainContext
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:packet.offers[0].id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c));row.payload=Data("broken".utf8);try c.save()
        XCTAssertThrowsError(try s.fixtures(for:p,year:2030));XCTAssertNotNil(CalendarScheduleStatus(player:p,state:s).errorMessage)
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c));XCTAssertEqual(row.payload,Data("broken".utf8))
    }
}


extension CareerCalendarTests {
    func testV11DiskMigrationRegistrationReopenKeepsOriginalRecordsAndTerms() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("registration.store")
        var originals:[Data]=[],offerBytes:[Data]=[],school="",journalBytes=Data()
        try autoreleasepool {
            let (store,p,s)=try selectionSeason(.pitcher,legacyURL:url,legacyVersion:11),c=store.mainContext
            try ContractEvaluationStore.registerCurrent(in:c)
            originals=try c.fetch(FetchDescriptor<CareerMatchRecord>()).sorted {$0.key < $1.key}.map(\.payload)
            offerBytes=try ContractOfferStore.records(player:p,calendar:s,in:c).map(\.payload);school=p.schoolID
        }
        try autoreleasepool {
            let store=try CareerStore.makeContainer(url:url),c=store.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            XCTAssertNil(try ContractRegistrationStore.row(player:p,in:c))
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),offerRow=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first)
            let offer=try XCTUnwrap(offerRow.snapshot(evaluation:evaluation,player:p,calendar:s).offers.first {$0.route == .college})
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            journalBytes=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        XCTAssertEqual(p.schoolID,school);XCTAssertEqual(try s.registration(for:p)?.route,.college)
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,journalBytes)
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).sorted {$0.key < $1.key}.map(\.payload),originals)
        XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).map(\.payload),offerBytes)
        XCTAssertEqual(try s.fixtures(for:p,year:2030).count,30)
        try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
        let record=try CareerMatchStore.start(player:p,state:s,in:c)
        XCTAssertEqual(try record.snapshot().competition,"college")
        let npc=try XCTUnwrap(record.snapshot().npcFielders)
        XCTAssertEqual(npc.competition,"college");XCTAssertEqual(npc.year,2030)
        XCTAssertTrue((54...66).contains(npc.home.strength))
        try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
        XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2030,in:c).totals.games,1)
    }
}

extension CareerCalendarTests {
    private func renewalFixture(_ role:PlayerRole,games:Bool=true,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let (store,p,s,packet)=try acceptance(role,legacyURL:legacyURL),c=store.mainContext
        let offer=try XCTUnwrap(packet.offers.first {$0.route == .rookie})
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let member=try XCTUnwrap(s.registration(for:p))
        // Find a fictional annual budget that can fund a strong player's offer; no persisted evaluations are rerolled.
        var year=2030
        for candidate in 2030...2040 {
            p.gameDate="\(candidate)-11-01";try c.save()
            let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
            let window=ContractEvaluationWindow(year:candidate,month:11)
            let review=try DomesticRenewalReview.make(observation:observation,member:member,roleID:offer.roleID,key:CareerContractEvaluation.key(p.id,window.id),window:window)
            if review.budget >= 200 {year=candidate;break}
        }
        if games {
            for (index,fixture) in try s.fixtures(for:p,year:year).filter({$0.isAppearance(for:role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:80,power:80,discipline:80,speed:60,defense:80,arm:65)
                values.velocity=80;values.control=80;values.stuff=80;values.stamina=80
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(5200+index),home:fixture.homeID == member.teamID,tracked:true)
                match.competition="domestic-development";try match.advance(.automatic)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
            }
        }
        p.gameDate="\(year)-11-01";try c.save();return (store,p,s)
    }
    func testDomesticRenewalNovemberIssuesFrozenOfferBothRolesWithoutChangingContractOrRecords() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try renewalFixture(role),c=store.mainContext
            let date=p.gameDate,fatigue=p.fatigue,revision=s.revision,registration=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            let matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            let reports=try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload)
            let oldOffers=try ContractOfferStore.records(player:p,calendar:s,in:c).map(\.payload)
            try ContractEvaluationStore.registerCurrent(in:c)
            let row=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),value=try row.snapshot(player:p,calendar:s)
            XCTAssertEqual(value.version,3);XCTAssertNil(value.selection);XCTAssertEqual(value.routes,["국내 육성팀 재계약"])
            let review=try XCTUnwrap(value.renewal),offer=try XCTUnwrap(review.offer)
            XCTAssertEqual(review.p,0);XCTAssertTrue(review.sampleID?.hasPrefix("domestic-development/") == true)
            XCTAssertTrue(review.reasons.isEmpty);XCTAssertEqual(offer.issuedDate,date)
            XCTAssertEqual(offer.expiresDate,try GameDate(date).adding(days:6).description)
            XCTAssertEqual(offer.years,1);XCTAssertLessThanOrEqual(offer.economicIndex,review.budget)
            XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
            XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,registration)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload),reports)
            XCTAssertEqual(try ContractOfferStore.records(player:p,calendar:s,in:c).map(\.payload),oldOffers)
            let payload=row.payload
            p.contact=99;try c.save()
            try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("same window changed")})
            try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:date,revision:s.revision,in:c)
            try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("acknowledged window changed")})
            XCTAssertEqual(row.payload,payload);XCTAssertEqual(try s.registration(for:p)?.economicEnd,review.membership.economicEnd)
        }
    }
    func testDomesticRenewalNoSampleDoesNotUseGraduationStatsAndNoOfferKeepsRights() throws {
        let (store,p,s)=try renewalFixture(.batter,games:false),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let review=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).renewal)
        XCTAssertNil(review.offer);XCTAssertNil(review.sampleID);XCTAssertEqual(review.sampleCount,0)
        XCTAssertTrue(review.reasons.contains {$0.contains("40타석")});XCTAssertNotNil(try s.registration(for:p))
        let status=try CareerContractStatus(XCTUnwrap(s.registration(for:p)),on:GameDate("2040-11-01"))
        XCTAssertTrue(status.economicExpired);XCTAssertTrue(status.rightsLabel.contains("자동 FA 아님"))
    }
    func testDomesticRenewalOnlyNovemberAndRookieMembershipCanBeEvaluated() throws {
        for route in DomesticSelectionRoute.allCases {
            let (store,p,s,packet)=try acceptance(.pitcher),c=store.mainContext
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:XCTUnwrap(packet.offers.first {$0.route == route}).id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            p.gameDate="2030-07-01";try c.save();XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
            p.gameDate="2030-11-15";try c.save();XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
            p.gameDate="2031-04-01";try c.save();XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
            if route == .college {p.gameDate="2031-11-01";try c.save();XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))}
        }
    }
    func testDomesticRenewalSaveFailureRollsBackEvaluationAndRetryIssuesExactlyOnce() throws {
        let (store,p,s)=try renewalFixture(.pitcher),c=store.mainContext
        let registration=try ContractRegistrationStore.row(player:p,in:c)?.payload,date=p.gameDate,fatigue=p.fatigue
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c,save:{_ in throw CocoaError(.fileWriteUnknown)}))
        XCTAssertNil(try ContractEvaluationStore.records(player:p,calendar:s,in:c).first {$0.key.hasSuffix("-11")})
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,registration)
        XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
        try ContractEvaluationStore.registerCurrent(in:c)
        XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).filter {$0.key.hasSuffix("-11")}.count,1)
        try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("duplicate")})
    }
    func testDomesticRenewalBulkStopsAtNovemberAndAcknowledgementDoesNotRenew() async throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        p.gameDate=try GameDate(p.gameDate).adding(days:-2).description;try c.save()
        let original=try ContractRegistrationStore.row(player:p,in:c)?.payload
        let result=try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(result.days,2);XCTAssertTrue(p.gameDate.hasSuffix("11-01"))
        let row=try XCTUnwrap(ContractEvaluationStore.unread(player:p,calendar:s,in:c))
        XCTAssertNotNil(try row.snapshot(player:p,calendar:s).renewal)
        let date=p.gameDate,fatigue=p.fatigue,rev=s.revision
        try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:date,revision:rev,in:c)
        XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,rev)
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,original)
    }
    func testDomesticRenewalLateWindowExpiryCorruptionAndOldPayloadPreservation() throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        let bytes=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
        p.gameDate=try GameDate(p.gameDate).adding(days:11).description;try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let row=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),value=try row.snapshot(player:p,calendar:s)
        XCTAssertEqual(value.renewal?.offer?.expiresDate,try GameDate(p.gameDate).adding(days:2).description)
        for data in bytes {XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).contains {$0.payload == data})}
        let good=row.payload
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:good) as? [String:Any])
        var renewal=try XCTUnwrap(json["renewal"] as? [String:Any]);renewal["p"]=4;json["renewal"]=renewal
        row.payload=try JSONSerialization.data(withJSONObject:json);try c.save()
        XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in:c))
        XCTAssertNotEqual(row.payload,good)
    }
}

extension CareerCalendarTests {
    func testDomesticRenewalV12DiskReopenPreservesRegistrationOldEvaluationsAndOfferTerms() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer {for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:url.path+suffix)}}
        var original:[Data]=[],registration=Data(),frozen=Data(),offer:DomesticRenewalOffer?
        do {
            let (store,p,s)=try renewalFixture(.pitcher,legacyURL:url),c=store.mainContext
            original=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
            registration=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            try ContractEvaluationStore.registerCurrent(in:c)
            let row=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
            frozen=row.payload;offer=try XCTUnwrap(row.snapshot(player:p,calendar:s).renewal?.offer)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("reopen changed frozen review")})
        let rows=try ContractEvaluationStore.records(player:p,calendar:s,in:c)
        XCTAssertEqual(rows.first?.payload,frozen);XCTAssertEqual(try rows.first?.snapshot(player:p,calendar:s).renewal?.offer,offer)
        XCTAssertTrue(original.allSatisfy {bytes in rows.contains {$0.payload == bytes}})
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,registration)
        XCTAssertEqual(try s.fixtures(for:p,year:GameDate(p.gameDate).year).count,30)
    }
    func testDomesticRenewalPoorAbilityFailsDespiteEnoughGamesAndKeepsCurrentContract() throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        p.contact=5;p.power=5;p.discipline=5;p.defense=5;p.speed=5;p.arm=5
        let profile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c));try profile.grow(.mental,to:5);try c.save()
        let registration=try ContractRegistrationStore.row(player:p,in:c)?.payload
        try ContractEvaluationStore.registerCurrent(in:c)
        let review=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).renewal)
        XCTAssertNotNil(review.totals);XCTAssertNil(review.offer);XCTAssertTrue(review.reasons.contains {$0.contains("기준 미달")})
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,registration)
    }
    func testContractEconomicExpiryRetainsRightsAndCollegeHasNoProfessionalRights() throws {
        for route in DomesticSelectionRoute.allCases {
            let (store,p,s,packet)=try acceptance(.pitcher),c=store.mainContext
            let offer=try XCTUnwrap(packet.offers.first {$0.route == route})
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            let member=try XCTUnwrap(s.registration(for:p)),end=try GameDate(member.economicEnd)
            XCTAssertFalse(try CareerContractStatus(member,on:end).economicExpired)
            let later=try CareerContractStatus(member,on:end.adding(days:1))
            XCTAssertTrue(later.economicExpired)
            XCTAssertTrue(later.rightsLabel.contains(route == .rookie ? "보유권리 유지":"보유권리 없음"))
            XCTAssertEqual(try CareerContractStatus(member,on:GameDate("2030-11-14")).nextReview,route == .rookie ? "2030-11-01":nil)
            XCTAssertEqual(try CareerContractStatus(member,on:GameDate("2030-11-15")).nextReview,route == .rookie ? "2031-11-01":nil)
        }
    }
}

extension CareerCalendarTests {
    func testRenewalAcceptanceBothRolesPreservesOriginalsAndAppliesOnlyEffectiveEconomics() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try renewalFixture(role),c=store.mainContext
            try ContractEvaluationStore.registerCurrent(in:c)
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
            let offer=try XCTUnwrap(evaluation.snapshot(player:p,calendar:s).renewal?.offer)
            let old=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            let date=p.gameDate,fatigue=p.fatigue,action=s.actionDate,revision=s.revision
            let matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),frozen=evaluation.payload
            try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:revision,in:c)
            let updated=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(updated.memberships,old.memberships);XCTAssertEqual(updated.decisions,old.decisions)
            XCTAssertEqual(updated.renewals?.count,1);XCTAssertEqual(updated.revision,old.revision+1)
            XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.actionDate,action)
            XCTAssertEqual(s.revision,revision+1);XCTAssertTrue(evaluation.acknowledged);XCTAssertEqual(evaluation.payload,frozen)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
            let applied=try XCTUnwrap(updated.current(on:GameDate(offer.effectiveDate)))
            XCTAssertEqual(applied.economicEnd,offer.economicEnd);XCTAssertEqual(applied.economicIndex,offer.economicIndex)
            XCTAssertEqual(applied.economicStart,offer.effectiveDate);XCTAssertEqual(applied.teamID,old.memberships.last?.teamID)
            XCTAssertEqual(applied.since,old.memberships.last?.since)
            XCTAssertEqual(try updated.current(on:GameDate(offer.effectiveDate).adding(days:-1)),old.memberships.last)
            try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:revision,in:c,save:{_ in XCTFail("duplicate save")})
            XCTAssertEqual(s.revision,revision+1)
            try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("same window re-evaluation")})
            p.gameDate="\(try GameDate(date).year+1)-11-01";try c.save()
            try ContractEvaluationStore.registerCurrent(in:c)
            let next=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).renewal)
            XCTAssertEqual(next.membership.economicEnd,offer.economicEnd)
            XCTAssertEqual(next.membership.offerID,old.memberships.last?.offerID)
        }
    }
    func testRenewalAcceptanceSaveFailureRollsBackAndRetryPaysNoMatchReward() throws {
        let (store,p,s)=try renewalFixture(.pitcher),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let offer=try XCTUnwrap(evaluation.snapshot(player:p,calendar:s).renewal?.offer)
        let original=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload,revision=s.revision,ack=evaluation.acknowledged
        XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:revision,in:c,save:{_ in throw CalendarError.invalidGroup}))
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,original)
        XCTAssertEqual(s.revision,revision);XCTAssertEqual(evaluation.acknowledged,ack)
        try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:revision,in:c)
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).renewals?.count,1)
    }
    func testRenewalAcceptanceRejectsStaleExpiredAndUnsavedChanges() throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let review=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).renewal)
        let offer=try XCTUnwrap(review.offer),original=try ContractRegistrationStore.row(player:p,in:c)?.payload
        XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision+1,in:c))
        p.fatigue += 1
        XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision,in:c))
        c.rollback();p.gameDate=try GameDate(offer.expiresDate).adding(days:1).description;try c.save()
        XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision,in:c))
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,original)
    }
    func testRenewalAcceptanceDiskReopenAndCorruptTermsAreRejected() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer {for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:url.path+suffix)}}
        var payload=Data(),frozen=Data()
        do {
            let (store,p,s)=try renewalFixture(.batter,legacyURL:url),c=store.mainContext
            try ContractEvaluationStore.registerCurrent(in:c)
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
            let offer=try XCTUnwrap(evaluation.snapshot(player:p,calendar:s).renewal?.offer)
            try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision,in:c)
            payload=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload;frozen=evaluation.payload
            p.gameDate=offer.effectiveDate;try c.save()
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let journal=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        XCTAssertEqual(journal.renewals?.count,1);XCTAssertNotNil(try s.registration(for:p)?.economicStart)
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,payload)
        XCTAssertTrue(try ContractEvaluationStore.records(player:p,calendar:s,in:c).contains {$0.payload == frozen})
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:row.payload) as? [String:Any])
        var renewals=try XCTUnwrap(json["renewals"] as? [[String:Any]]),terms=try XCTUnwrap(renewals[0]["terms"] as? [String:Any])
        terms["economicIndex"]=999;renewals[0]["terms"]=terms;json["renewals"]=renewals
        row.payload=try JSONSerialization.data(withJSONObject:json);try c.save()
        XCTAssertThrowsError(try ContractRegistrationStore.journal(player:p,calendar:s,in:c))
    }
}

extension CareerCalendarTests {
    func testRenewalAcceptanceBlocksPendingTrainingAndMatchWithoutMutatingThem() throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let offer=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).renewal?.offer)
        let training=try CareerTrainingStore.start(player:p,state:s,kind:.contact,in:c),trainingBytes=training.payload
        XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision,in:c))
        XCTAssertEqual(training.payload,trainingBytes);c.delete(training);try c.save()
        let date=p.gameDate,year=try GameDate(date).year+1
        let fixture=try XCTUnwrap(s.fixtures(for:p,year:year).first)
        p.gameDate=fixture.date.description
        let match=ScoutingReferenceSimulation.fixture(role:.batter,position:p.positionRaw,values:PlayerArchetype.initial(for:.batter).values,seed:19,home:fixture.homeID == (try s.registration(for:p)?.teamID))
        let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);c.insert(row);p.gameDate=date;try c.save()
        let bytes=row.payload
        XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:s.revision,in:c))
        XCTAssertEqual(row.payload,bytes);XCTAssertNil(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).renewals)
    }
}

extension CareerCalendarTests {
    private func releaseFixture(_ role:PlayerRole,games:Bool=true,url:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState,String) {
        let (store,p,s,packet)=try acceptance(role,legacyURL:url),c=store.mainContext
        let offer=try XCTUnwrap(packet.offers.first {$0.route == .rookie})
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let member=try XCTUnwrap(s.registration(for:p)),year=2035
        p.gameDate="2035-11-01";try c.save()
        if games {
            for (i,fixture) in try s.fixtures(for:p,year:year).filter({$0.isAppearance(for:role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:80,power:80,discipline:80,speed:60,defense:80,arm:65)
                values.velocity=80;values.control=80;values.stuff=80;values.stamina=80
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(8100+i),home:fixture.homeID == member.teamID,tracked:true)
                match.competition="domestic-development";try match.advance(.automatic)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
            }
        }
        p.gameDate="2035-11-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        return (store,p,s,CareerContractEvaluation.key(p.id,"2035-11"))
    }
    func testRenewalRejectionIsFinalIdempotentAndDoesNotReleaseRights() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try renewalFixture(role),c=store.mainContext
            try ContractEvaluationStore.registerCurrent(in:c)
            let row=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),bytes=row.payload
            let offer=try XCTUnwrap(row.snapshot(player:p,calendar:s).renewal?.offer),member=try s.registration(for:p)
            let date=p.gameDate,fatigue=p.fatigue,revision=s.revision
            XCTAssertThrowsError(try ContractRegistrationStore.rejectRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:revision,in:c,save:{_ in throw CalendarError.invalidGroup}))
            XCTAssertNil(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).renewalRejections)
            try ContractRegistrationStore.rejectRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:revision,in:c)
            XCTAssertEqual(try s.registration(for:p),member);XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(row.payload,bytes);XCTAssertEqual(s.revision,revision+1)
            try ContractRegistrationStore.rejectRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:revision,in:c,save:{_ in XCTFail("duplicate rejection")})
            XCTAssertThrowsError(try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:date,revision:s.revision,in:c))
        }
    }
    func testReleaseBothRolesPreservesHistoryRecordsAndAllowsAdultReentryExactlyOnce() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,key)=try releaseFixture(role),c=store.mainContext
            let old=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            let matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            let evaluations=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
            XCTAssertNotNil(try s.registration(for:p)) // Expired economics alone never releases.
            XCTAssertThrowsError(try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:s.revision,in:c))
            p.gameDate="2035-11-15";try c.save();let date=p.gameDate,fatigue=p.fatigue,action=s.actionDate,revision=s.revision
            XCTAssertTrue(try XCTUnwrap(ContractRegistrationStore.releaseCandidate(player:p,calendar:s,in:c)).eligible)
            try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:date,revision:revision,in:c)
            XCTAssertNil(try s.registration(for:p));XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.actionDate,action)
            let released=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(released.memberships,old.memberships);XCTAssertEqual(released.releases?.count,1)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
            XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload),evaluations)
            XCTAssertEqual(try s.fixtures(for:p,year:2035).count,30);XCTAssertTrue(try s.fixtures(for:p,year:2036).isEmpty)
            _ = try CareerSeasonStore.load(player:p,state:s,year:2035,in:c)
            try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:date,revision:revision,in:c,save:{_ in XCTFail("duplicate release")})
            p.gameDate="2036-04-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
            let snapshot=try evaluation.snapshot(player:p,calendar:s)
            XCTAssertEqual(snapshot.version,5);XCTAssertGreaterThan(snapshot.observation.age,23)
            let packet=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first).snapshot(evaluation:evaluation,player:p,calendar:s)
            let offer=try XCTUnwrap(packet.offers.first);XCTAssertEqual(offer.reentry,true)
            let frozen=evaluation.payload
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships.count,2)
            XCTAssertEqual(evaluation.payload,frozen);XCTAssertNotNil(try s.registration(for:p))
            XCTAssertEqual(try s.fixtures(for:p,year:2036).count,30)
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c,save:{_ in XCTFail("duplicate readmission")})
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            let final=record.payload,after=p.fatigue
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,final)
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
            XCTAssertEqual(record.payload,final);XCTAssertEqual(p.fatigue,after)
        }
    }
    func testReleaseNoOfferRollbackPendingLockAndRetryNoSample() throws {
        let (store,p,s,key)=try releaseFixture(.batter,games:false),c=store.mainContext
        p.gameDate="2035-11-15";try c.save()
        let original=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload,revision=s.revision
        XCTAssertThrowsError(try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:revision+1,in:c))
        XCTAssertThrowsError(try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:revision,in:c,save:{_ in throw CalendarError.invalidGroup}))
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,original);XCTAssertEqual(s.revision,revision)
        let training=try CareerTrainingStore.start(player:p,state:s,kind:.contact,in:c)
        XCTAssertThrowsError(try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:s.revision,in:c))
        c.delete(training);try c.save()
        try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:s.revision,in:c)
        p.gameDate="2036-04-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let packet=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first).snapshot(evaluation:evaluation,player:p,calendar:s)
        XCTAssertTrue(packet.offers.isEmpty)
        let bytes=evaluation.payload
        try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("same-window reroll")})
        XCTAssertEqual(evaluation.payload,bytes)
    }
    func testReleaseDiskReopenPreservesOriginalMembershipAndRejectsForgedReleaseDate() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer {for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:url.path+suffix)}}
        var original=Data()
        do {
            let (store,p,s,key)=try releaseFixture(.pitcher,games:false,url:url),c=store.mainContext
            p.gameDate="2035-11-15";try c.save()
            try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:s.revision,in:c)
            original=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        XCTAssertNil(try s.registration(for:p));XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,original)
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:row.payload) as? [String:Any]),releases=try XCTUnwrap(json["releases"] as? [[String:Any]])
        releases[0]["date"]="2035-11-01";json["releases"]=releases
        row.payload=try JSONSerialization.data(withJSONObject:json);try c.save()
        XCTAssertThrowsError(try ContractRegistrationStore.journal(player:p,calendar:s,in:c))
    }
}

extension CareerCalendarTests {
    func testAcceptedRenewalCannotBeRejectedOrReleasedAndSummerReleaseIsBlocked() throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let row=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let offer=try XCTUnwrap(row.snapshot(player:p,calendar:s).renewal?.offer)
        try ContractRegistrationStore.acceptRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision,in:c)
        XCTAssertThrowsError(try ContractRegistrationStore.rejectRenewal(player:p,calendar:s,offerID:offer.id,date:p.gameDate,revision:s.revision,in:c))
        p.gameDate=try GameDate(String(format:"%04d-11-15",GameDate(p.gameDate).year)).description;try c.save()
        XCTAssertThrowsError(try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:row.key,date:p.gameDate,revision:s.revision,in:c))
        let (second,q,t,key)=try releaseFixture(.pitcher,games:false),ctx=second.mainContext
        q.gameDate="2036-04-01";try ctx.save()
        XCTAssertThrowsError(try ContractRegistrationStore.release(player:q,calendar:t,evaluationKey:key,date:q.gameDate,revision:t.revision,in:ctx))
        XCTAssertNotNil(try t.registration(for:q))
    }
}

extension CareerCalendarTests {
    private func certificationFixture(_ role:PlayerRole) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let (store,p,s,key)=try releaseFixture(role,games:false),c=store.mainContext
        p.gameDate="2035-11-15";try c.save()
        try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:s.revision,in:c)
        return (store,p,s)
    }
    func testCertificationBothRolesResumeCompleteOnceAndSupplyFrozenReentryReview() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try certificationFixture(role),c=store.mainContext
            let official=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            let journal=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            let profile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c))
            let fatigue=p.fatigue,date=p.gameDate,abilities=[profile.mental,profile.velocity ?? 0,profile.control ?? 0,profile.stuff ?? 0,profile.stamina ?? 0]
            let row=try CertificationStore.start(player:p,calendar:s,in:c)
            XCTAssertEqual(try row.snapshot().window.id,"2036-04")
            try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c)
            XCTAssertEqual(try CertificationStore.start(player:p,calendar:s,in:c).payload,row.payload)
            XCTAssertThrowsError(try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c))
            XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,in:c))
            while !row.completed {try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c)}
            let certificate=try XCTUnwrap(row.snapshot().assessment),bytes=row.payload,revision=s.revision
            XCTAssertEqual(p.fatigue,min(100,fatigue+8));XCTAssertEqual(p.gameDate,date);XCTAssertEqual(s.actionDate,date)
            XCTAssertThrowsError(try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c))
            XCTAssertEqual(try CertificationStore.start(player:p,calendar:s,in:c,save:{_ in XCTFail("repeated award")}).payload,bytes)
            XCTAssertEqual(s.revision,revision)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),official)
            XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,journal)
            XCTAssertEqual([profile.mental,profile.velocity ?? 0,profile.control ?? 0,profile.stuff ?? 0,profile.stamina ?? 0],abilities)
            p.gameDate="2036-04-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
            let snapshot=try evaluation.snapshot(player:p,calendar:s)
            XCTAssertEqual(snapshot.version,5);XCTAssertEqual(snapshot.retry?.certificate,certificate)
            let packet=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first).snapshot(evaluation:evaluation,player:p,calendar:s)
            XCTAssertEqual(packet.offers.isEmpty,!certificate.passed)
            let frozen=evaluation.payload
            try ContractEvaluationStore.registerCurrent(in:c,save:{_ in XCTFail("same-window reevaluation")})
            XCTAssertEqual(evaluation.payload,frozen)
            if let offer=packet.offers.first {
                try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
                XCTAssertNotNil(try s.registration(for:p));XCTAssertEqual(evaluation.payload,frozen);XCTAssertEqual(row.payload,bytes)
                XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships.count,2)
            }
        }
    }
    func testCertificationSaveFailureRollbackLocksAndFutureWindowAfterFrozenNoOffer() throws {
        let (store,p,s)=try certificationFixture(.batter),c=store.mainContext
        let revision=s.revision
        XCTAssertThrowsError(try CertificationStore.start(player:p,calendar:s,in:c,save:{_ in throw CalendarError.invalidGroup}))
        XCTAssertTrue(try CertificationStore.records(playerID:p.id,in:c).isEmpty);XCTAssertEqual(s.revision,revision)
        p.gameDate="2036-04-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first),frozen=evaluation.payload
        let row=try CertificationStore.start(player:p,calendar:s,in:c)
        XCTAssertEqual(try row.snapshot().window.id,"2036-07")
        let bytes=row.payload,before=s.revision,fatigue=p.fatigue
        XCTAssertThrowsError(try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision+1,in:c))
        XCTAssertThrowsError(try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c,save:{_ in throw CalendarError.invalidGroup}))
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(s.revision,before);XCTAssertEqual(p.fatigue,fatigue)
        while !row.completed {try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c)}
        XCTAssertEqual(evaluation.payload,frozen)
        XCTAssertNil(try evaluation.snapshot(player:p,calendar:s).retry?.certificate)
    }
    func testCertificationV12MigrationDiskReopenKeepsOriginalsAndPendingProgress() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer {for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:url.path+suffix)}}
        var journal=Data(),official:[Data]=[],progress=Data()
        do {
            let (store,p,s,key)=try releaseFixture(.pitcher,games:false,url:url),c=store.mainContext
            p.gameDate="2035-11-15";try c.save()
            try ContractRegistrationStore.release(player:p,calendar:s,evaluationKey:key,date:p.gameDate,revision:s.revision,in:c)
            journal=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            official=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
        }
        do {
            let store=try CareerStore.makeContainer(url:url),c=store.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,journal)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),official)
            let row=try CertificationStore.start(player:p,calendar:s,in:c)
            try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c);progress=row.payload
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        let row=try CertificationStore.start(player:p,calendar:s,in:c)
        XCTAssertEqual(row.payload,progress);XCTAssertFalse(row.completed)
        try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c)
        XCTAssertTrue(row.completed)
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,journal)
    }
    func testCertificationThresholdsAndPreviousVersionFourReviewArePreserved() throws {
        let (store,p,s)=try certificationFixture(.batter),c=store.mainContext
        p.gameDate="2036-04-01";try c.save()
        let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
        let release=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).releases?.last)
        let window=ContractEvaluationWindow(year:2036,month:4)
        let old=try DomesticRetryReview.make(observation:observation,release:release,window:window)
        XCTAssertNil(old.version);XCTAssertTrue(old.results.allSatisfy {!$0.selected})
        var totals=PersonalSeasonTotals();totals.games=4;totals.line.plateAppearances=12;totals.line.atBats=12;totals.line.hits=6
        let passed=CertifiedAssessment(key:"policy-fixture",playerID:p.id,releaseOfferID:release.membershipOfferID,window:window,date:"2035-11-15",role:.batter,totals:totals,battersFaced:0,homeRunsAllowed:0)
        let updated=try DomesticRetryReview.make(observation:observation,release:release,window:window,certificate:passed,certificationEnabled:true)
        XCTAssertEqual(updated.version,2);XCTAssertTrue(updated.results.contains {$0.selected})
        totals.line.hits=0
        let failed=CertifiedAssessment(key:"policy-fixture",playerID:p.id,releaseOfferID:release.membershipOfferID,window:window,date:"2035-11-15",role:.batter,totals:totals,battersFaced:0,homeRunsAllowed:0)
        XCTAssertTrue(try DomesticRetryReview.make(observation:observation,release:release,window:window,certificate:failed,certificationEnabled:true).results.allSatisfy {!$0.selected})
    }
}

extension CareerCalendarTests {
    private func collegeProFixture(_ role:PlayerRole,games:Bool=true,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let (store,p,s,packet)=try acceptance(role,legacyURL:legacyURL),c=store.mainContext
        let offer=try XCTUnwrap(packet.offers.first {$0.route == .college})
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let member=try XCTUnwrap(s.registration(for:p))
        if games {
            for (index,fixture) in try s.fixtures(for:p,year:2032).filter({$0.isAppearance(for:role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:80,power:80,discipline:80,speed:60,defense:80,arm:65)
                values.velocity=80;values.control=80;values.stuff=80;values.stamina=80
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(8200+index),home:fixture.homeID == member.teamID,tracked:true)
                match.competition="college";try match.advance(.automatic)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
            }
        }
        p.gameDate="2032-11-01";try c.save();return (store,p,s)
    }
    private func collegeProOffer(_ p:CareerPlayer,_ s:CareerCalendarState,_ c:ModelContext) throws -> DomesticContractOffer {
        try ContractEvaluationStore.registerCurrent(in:c)
        let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first)
        let packet=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first).snapshot(evaluation:evaluation,player:p,calendar:s)
        return try XCTUnwrap(packet.offers.first)
    }
    func testCollegeProEligibilityRejectsYoungShortEnrollmentAndWrongWindow() throws {
        let (store,p,s)=try collegeProFixture(.batter,games:false),c=store.mainContext,member=try XCTUnwrap(s.registration(for:p))
        XCTAssertFalse(try CollegeProReview.eligible(member:member,age:21,on:GameDate("2031-11-01")))
        XCTAssertFalse(try CollegeProReview.eligible(member:member,age:22,on:GameDate("2031-11-01")))
        XCTAssertFalse(try CollegeProReview.eligible(member:member,age:24,on:GameDate("2034-11-01")))
        XCTAssertTrue(try CollegeProReview.eligible(member:member,age:22,on:GameDate("2032-11-01")))
        p.gameDate="2032-07-01";try c.save();XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
        p.gameDate="2032-11-01";try c.save();try ContractEvaluationStore.registerCurrent(in:c)
        let value=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first).snapshot(player:p,calendar:s)
        XCTAssertEqual(value.version,6);XCTAssertTrue(try XCTUnwrap(value.college).results.allSatisfy {!$0.selected})
        XCTAssertTrue(value.college!.results.allSatisfy {$0.reasons.contains { $0.contains("대학 공식 성적") }})
    }
    func testCollegeProFrozenSelectionAndAcceptancePreserveAcademicRecordsBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try collegeProFixture(role),c=store.mainContext,original=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            let offer=try collegeProOffer(p,s,c),date=p.gameDate,fatigue=p.fatigue
            let frozen=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
            let matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            XCTAssertNotNil(offer.collegeEntry);XCTAssertNil(offer.reentry);XCTAssertEqual(offer.p,0)
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:s.revision,in:c)
            let journal=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(journal.memberships.first,original.memberships.first);XCTAssertEqual(journal.collegeTransitions?.count,1)
            XCTAssertEqual(try s.registration(for:p)?.route,.college)
            XCTAssertEqual(try journal.current(on:GameDate("2033-03-31"))?.route,.college)
            XCTAssertEqual(try journal.current(on:GameDate("2033-04-01"))?.route,.rookie)
            XCTAssertEqual(journal.memberships.last?.economicEnd,"2034-03-31")
            XCTAssertEqual(journal.memberships.first?.enrollmentEnd,"2034-03-31")
            XCTAssertEqual(try s.competition(for:p,year:2032).membership?.route,.college)
            XCTAssertEqual(try s.competition(for:p,year:2033).membership?.route,.rookie)
            XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload),frozen)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
            XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
            let bytes=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:-1,in:c,save:{_ in XCTFail("duplicate")})
            XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,bytes)
            XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:false,date:date,revision:s.revision,in:c))
            XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c))
        }
    }
    func testCollegeProAcceptanceFailureAndRejectionLeaveEnrollmentIntact() throws {
        let (store,p,s)=try collegeProFixture(.pitcher),c=store.mainContext,offer=try collegeProOffer(p,s,c)
        let bytes=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload,revision=s.revision
        XCTAssertThrowsError(try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,bytes);XCTAssertEqual(s.revision,revision)
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:false,date:p.gameDate,revision:revision,in:c)
        XCTAssertEqual(try s.registration(for:p)?.route,.college)
        XCTAssertNil(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).collegeTransitions)
    }
    func testCollegeProTransitionNextSeasonMatchResumeAndOneTimeResultBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try collegeProFixture(role),c=store.mainContext,offer=try collegeProOffer(p,s,c)
            let college=try CareerSeasonStore.load(player:p,state:s,year:2032,in:c)
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            p.gameDate="2033-04-01";try c.save()
            XCTAssertEqual(try s.registration(for:p)?.route,.rookie)
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,record.payload)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            let completed=record.payload,fatigue=p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
            XCTAssertEqual(record.payload,completed);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2033,in:c).totals.games,1)
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2032,in:c).totals.games,college.totals.games)
            p.gameDate="2033-11-01";try c.save()
            try ContractEvaluationStore.registerCurrent(in:c)
            XCTAssertNotNil(try ContractEvaluationStore.records(player:p,calendar:s,in:c).first?.snapshot(player:p,calendar:s).renewal)
        }
    }
    func testCollegeProLegacyDiskReopenPreservesOriginalsAndPendingTransition() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store")
        var id:UUID!,academic:CareerMembership!,frozen:[Data]=[],records:[Data]=[]
        do {
            let (store,p,s)=try collegeProFixture(.batter,legacyURL:url),c=store.mainContext
            id=p.id;academic=try s.registration(for:p)
            let offer=try collegeProOffer(p,s,c)
            frozen=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
            records=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id})
        let s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        XCTAssertEqual(try s.registration(for:p),academic)
        XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload),frozen)
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),records)
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).collegeTransitions?.count,1)
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),data=row.payload
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        json.removeValue(forKey:"collegeTransitions");row.payload=try JSONSerialization.data(withJSONObject:json)
        XCTAssertThrowsError(try ContractRegistrationStore.journal(player:p,calendar:s,in:c))
        c.rollback()
    }
}


extension CareerCalendarTests {
    func testCollegeProBulkStopsAtNovemberAndRollbackCanRetry() async throws {
        let (store,p,s)=try collegeProFixture(.batter),c=store.mainContext
        p.gameDate="2032-10-31";try c.save()
        let before=s.revision
        do {
            _ = try await CalendarProgression.advanceOffDays(player:p,state:s,in:c,save:{_ in throw MatchError.invalidRecord})
            XCTFail("expected save failure")
        } catch is CalendarAdvanceFailure {}
        XCTAssertEqual(p.gameDate,"2032-10-31");XCTAssertEqual(s.revision,before)
        XCTAssertFalse(try ContractEvaluationStore.records(player:p,calendar:s,in:c).contains {$0.key.hasSuffix("2032-11")})
        let summary=try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(summary.stop,.evaluation);XCTAssertEqual(summary.days,1);XCTAssertEqual(p.gameDate,"2032-11-01")
        let row=try XCTUnwrap(ContractEvaluationStore.unread(player:p,calendar:s,in:c)),bytes=row.payload
        try ContractEvaluationStore.acknowledge(player:p,calendar:s,key:row.key,date:p.gameDate,revision:s.revision,in:c)
        p.power += 1;try c.save()
        XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player:p,calendar:s,in:c));XCTAssertEqual(row.payload,bytes)
    }
}

extension CareerCalendarTests {
    func testOverseasEligibilitySeparatesCollegeDevelopmentRightsAndRecognizedService() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try collegeProFixture(role),c=store.mainContext
            let value=try OverseasEligibilityStore.current(player:p,calendar:s,in:c)
            XCTAssertEqual(value.routes.first?.status,.reviewable)
            XCTAssertEqual(value.routes.first {$0.route == .npbFirstTeam}?.status,.blocked)
            XCTAssertNil(value.evidence.recognizedForeignProSeasons)
            XCTAssertTrue(value.evidence.observedProYears.isEmpty)
            XCTAssertTrue(value.evidence.matches.contains {$0.level == "college"})
            XCTAssertFalse(value.evidence.matches.contains {$0.level == "domestic-first-team"})
        }
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        p.gameDate="2040-11-01";try c.save()
        let value=try OverseasEligibilityStore.current(player:p,calendar:s,in:c)
        XCTAssertTrue(value.routes.allSatisfy {$0.status == .blocked})
        XCTAssertNil(value.evidence.recognizedForeignProSeasons)
        XCTAssertTrue(value.evidence.observedProYears.isEmpty)
    }
    func testOverseasEligibilityCaptureIsIdempotentReadOnlyAndRollbackPreservesJournal() throws {
        let (store,p,s)=try collegeProFixture(.pitcher),c=store.mainContext
        let member=try s.registration(for:p),date=p.gameDate,revision=s.revision,fatigue=p.fatigue
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=row.payload
        XCTAssertThrowsError(try OverseasEligibilityStore.capture(player:p,calendar:s,date:date,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(row.payload,before)
        try OverseasEligibilityStore.capture(player:p,calendar:s,date:date,revision:revision,in:c)
        let bytes=row.payload
        try OverseasEligibilityStore.capture(player:p,calendar:s,date:date,revision:revision,in:c,save:{_ in XCTFail("duplicate")})
        XCTAssertEqual(row.payload,bytes)
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasEligibility?.count,1)
        XCTAssertEqual(try s.registration(for:p),member);XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(s.revision,revision)
        XCTAssertThrowsError(try OverseasEligibilityStore.capture(player:p,calendar:s,date:date,revision:revision-1,in:c))
    }
    func testOverseasEligibilityPendingDomesticEntryAndUnderageAreBlocked() throws {
        let (store,p,s)=try collegeProFixture(.batter),c=store.mainContext,offer=try collegeProOffer(p,s,c)
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let value=try OverseasEligibilityStore.current(player:p,calendar:s,in:c)
        XCTAssertTrue(value.evidence.pendingCollegeEntry);XCTAssertTrue(value.routes.allSatisfy {$0.status == .blocked})
        let (other,young,state)=try fixture(date:"2026-04-01",role:.batter)
        XCTAssertTrue(try OverseasEligibilityStore.current(player:young,calendar:state,in:other.mainContext).routes.allSatisfy {$0.status == .blocked})
    }
    func testOverseasEligibilityDiskReopenPreservesOldAcademicAndMatches() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store")
        var id:UUID!,snapshot:OverseasEligibilitySnapshot!,academic:CareerMembership!,matches:[Data]=[]
        do {
            let (store,p,s)=try collegeProFixture(.batter,legacyURL:url),c=store.mainContext
            id=p.id;academic=try s.registration(for:p);matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            snapshot=try OverseasEligibilityStore.current(player:p,calendar:s,in:c)
            try OverseasEligibilityStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext
        let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasEligibility?.last,snapshot)
        XCTAssertEqual(try s.registration(for:p),academic)
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
    }
}

extension CareerCalendarTests {
    func testAdultReferenceAllInputModesBothRolesStayInTheirLevelAndValidate() throws {
        for role in PlayerRole.allCases {for level in ["college","domestic-development"] {for mode in ScoutingInputMode.allCases {
            var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? "SS":"P",values:PlayerArchetype.initial(for:role).values,seed:321,home:true,tracked:true,battedBallVersion:1,npcFieldersVersion:1)
            match.competition=level
            match.npcFielders=MatchNPCFielders.make(year:2026,competition:level,homeID:"ref-a",awayID:"ref-b")
            let prefix=try XCTUnwrap(match.scoutingEnvironment).components(separatedBy:"/").dropLast().joined(separator:"/")
            let environment=prefix+"/"+mode.suffix
            let ref=try XCTUnwrap(ScoutingReferenceSimulation.adult(environment:environment,role:role,position:role == .batter ? "SS":"P"))
            try ref.validate();XCTAssertEqual(ref.version,3);XCTAssertEqual(ref.inputMode,mode);XCTAssertTrue(ref.environment.hasPrefix(level+"/"))
            XCTAssertEqual(ref.profiles,ScoutingReferenceSimulation.adultProfiles(level:level,role:role))
            XCTAssertEqual(ref.totals.games,role == .batter ? 60:18)
            XCTAssertEqual(try ScoutingReferenceSimulation.adult(environment:environment,role:role,position:role == .batter ? "SS":"P")?.value,ref.value)
        }}}
    }
    func testOverseasProjectionsAreOrderedBoundedAndDoNotGrowActualPlayers() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try collegeProFixture(role),c=store.mainContext
            let source=try ScoutingObservationStore.currentObservation(player:p,calendar:s,in:c)
            let contact=p.contact,power=p.power,pitches=p.pitches.map(\.mastery),revision=s.revision,fatigue=p.fatigue
            let projections=try OverseasGrowthProjection.make(observation:source)
            XCTAssertEqual(projections.map(\.roleID),source.grades.map(\.id))
            for row in projections {if let h=row.current,let low=row.conservative,let mid=row.baseline,let high=row.optimistic {
                XCTAssertGreaterThanOrEqual(low,h);XCTAssertGreaterThanOrEqual(mid,low);XCTAssertGreaterThanOrEqual(high,mid);XCTAssertLessThanOrEqual(high,100)
            } else {XCTFail("missing projection")}}
            XCTAssertEqual(p.contact,contact);XCTAssertEqual(p.power,power);XCTAssertEqual(p.pitches.map(\.mastery),pitches);XCTAssertEqual(s.revision,revision);XCTAssertEqual(p.fatigue,fatigue)
        }
    }
    func testOverseasReportFreezesOnePeriodAndRollbackDoesNotChangeOldEvaluations() throws {
        let (store,p,s)=try collegeProFixture(.batter),c=store.mainContext
        try ContractEvaluationStore.registerCurrent(in:c)
        let original=try ContractRegistrationStore.row(player:p,in:c)?.payload
        let evaluations=try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload)
        XCTAssertThrowsError(try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,original)
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let before=try XCTUnwrap(OverseasReportStore.current(player:p,calendar:s,in:c))
        XCTAssertFalse(before.comparisons.isEmpty);XCTAssertTrue(before.comparisons.allSatisfy {$0.verified})
        let bytes=try JSONEncoder().encode(before)
        p.power += 1;try c.save()
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c,save:{_ in XCTFail("same period")})
        XCTAssertEqual(try OverseasReportStore.current(player:p,calendar:s,in:c)?.projections,before.projections)
        XCTAssertFalse(bytes.isEmpty);XCTAssertEqual(try ContractEvaluationStore.records(player:p,calendar:s,in:c).map(\.payload),evaluations)
        p.gameDate="2032-12-01";try c.save();try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasReports?.count,2)
    }
    func testOverseasReportLegacyDiskReopenKeepsFrozenComparisonAndOriginalMatches() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,forecasts:[OverseasGrowthProjection]=[],matches:[Data]=[]
        do {
            let (store,p,s)=try collegeProFixture(.pitcher,legacyURL:url),c=store.mainContext
            id=p.id;matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            forecasts=try XCTUnwrap(OverseasReportStore.current(player:p,calendar:s,in:c)).projections
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        let report=try XCTUnwrap(OverseasReportStore.current(player:p,calendar:s,in:c));XCTAssertEqual(report.projections,forecasts)
        XCTAssertTrue(report.comparisons.allSatisfy {$0.verified});XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
    }
}

extension CareerCalendarTests {
    func testOverseasMarketUsesFrozenRoleDemandAndRightsWithoutCreatingOffers() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try collegeProFixture(role),c=store.mainContext
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let report=try XCTUnwrap(OverseasReportStore.current(player:p,calendar:s,in:c)),market=try XCTUnwrap(report.market)
            XCTAssertEqual(report.version,3);XCTAssertEqual(market.clubs.count,role == .batter ? 54:18)
            XCTAssertEqual(market,OverseasMarket.make(report:report,version:2));XCTAssertTrue(market.clubs.contains {$0.interest != nil})
            for row in market.clubs {
                XCTAssertGreaterThanOrEqual(row.criterion,OverseasMarket.minimum(row.route,row.roleID))
                XCTAssertEqual(row.seats,row.demand == .none ? 0:1)
                if row.route != .mlbDevelopment {XCTAssertTrue(row.blockers.contains {$0.contains("대학") || $0.contains("전력")})}
            }
            let members=try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships
            p.power += 1;try c.save()
            XCTAssertEqual(try OverseasReportStore.current(player:p,calendar:s,in:c)?.market,market)
            XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships,members)
        }
    }
    func testOverseasOldReportDoesNotGainMarketAndCorruptMarketIsRejected() throws {
        let (store,p,s)=try collegeProFixture(.batter),c=store.mainContext
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),bytes=row.payload
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]),reports=try XCTUnwrap(json["overseasReports"] as? [[String:Any]])
        reports[0]["market"]=nil;reports[0]["version"]=1;json["overseasReports"]=reports;row.payload=try JSONSerialization.data(withJSONObject:json);try c.save()
        let legacy=try XCTUnwrap(OverseasReportStore.current(player:p,calendar:s,in:c));XCTAssertNil(legacy.market)
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        XCTAssertNil(try OverseasReportStore.current(player:p,calendar:s,in:c)?.market)
        reports[0]["version"]=2;json["overseasReports"]=reports;row.payload=try JSONSerialization.data(withJSONObject:json)
        XCTAssertThrowsError(try ContractRegistrationStore.journal(player:p,calendar:s,in:c));c.rollback()
    }
}

extension CareerCalendarTests {
    private func overseasOfferFixture(_ role:PlayerRole,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState,OverseasOffer) {
        let (store,p,s)=try collegeProFixture(role,legacyURL:legacyURL),c=store.mainContext
        try OverseasContractStore.register(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let offer=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.evaluations.last?.offers.first)
        return (store,p,s,offer)
    }
    func testOverseasDevelopmentOffersFreezeAndAcceptanceSchedulesForeignSeasonBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,offer)=try overseasOfferFixture(role),c=store.mainContext
            let original=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),college=try s.registration(for:p),date=p.gameDate,fatigue=p.fatigue
            let evaluations=try XCTUnwrap(original.overseasCareer?.evaluations)
            XCTAssertEqual(evaluations.last?.offers.count,2)
            try OverseasContractStore.evaluate(player:p,calendar:s,date:date,revision:s.revision,in:c,save:{_ in XCTFail("same window")})
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:s.revision,in:c)
            let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(value.overseasCareer?.evaluations,evaluations);XCTAssertEqual(try s.registration(for:p),college)
            XCTAssertEqual(value.overseasCareer?.decisions.filter {$0.kind == .closed}.count,1)
            XCTAssertEqual(value.memberships,original.memberships);XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(try s.competition(for:p,year:2032).membership?.level,"college")
            XCTAssertEqual(try s.competition(for:p,year:2033).membership?.level,"mlb-development")
            XCTAssertEqual(try s.fixtures(for:p,year:2033).count,30)
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:-1,in:c,save:{_ in XCTFail("duplicate")})
            XCTAssertThrowsError(try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:false,date:date,revision:s.revision,in:c))
        }
    }
    func testOverseasOfferFailureRejectionAndExpiryPreserveCurrentAcademic() throws {
        let (store,p,s,offer)=try overseasOfferFixture(.pitcher),c=store.mainContext,row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=row.payload,revision=s.revision
        XCTAssertThrowsError(try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(row.payload,before);XCTAssertEqual(s.revision,revision)
        try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:false,date:p.gameDate,revision:revision,in:c)
        XCTAssertEqual(try s.registration(for:p)?.level,"college");XCTAssertTrue(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.transitions.isEmpty == true)
        let other=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.evaluations.last?.offers.last)
        p.gameDate="2032-11-08";try c.save()
        XCTAssertThrowsError(try OverseasContractStore.decide(player:p,calendar:s,offerID:other.id,accept:true,date:p.gameDate,revision:s.revision,in:c))
    }
    func testOverseasForeignMatchResumeAndOneTimeResultKeepsOldCollegeSeasonBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,offer)=try overseasOfferFixture(role),c=store.mainContext
            let old=try CareerSeasonStore.load(player:p,state:s,year:2032,in:c).totals.games
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            p.gameDate="2033-04-01";try c.save()
            XCTAssertEqual(try s.registration(for:p)?.level,"mlb-development")
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            XCTAssertEqual(try record.snapshot().competition,"mlb-development")
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,record.payload)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            let bytes=record.payload,fatigue=p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
            XCTAssertEqual(record.payload,bytes);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2033,in:c).totals.games,1)
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:2032,in:c).totals.games,old)
            XCTAssertTrue(try OverseasEligibilityStore.current(player:p,calendar:s,in:c).evidence.matches.contains {$0.level == "mlb-development"})
        }
    }
    func testOverseasOfferLegacyDiskReopenPreservesMembershipAndFrozenTerms() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,terms:OverseasOffer!,college:CareerMembership!
        do {
            let (store,p,s,offer)=try overseasOfferFixture(.batter,legacyURL:url),c=store.mainContext
            id=p.id;terms=offer;college=try s.registration(for:p)
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        XCTAssertEqual(value.overseasCareer?.evaluations.last?.offers.first,terms)
        XCTAssertEqual(try s.registration(for:p),college)
        p.gameDate="2033-04-01";try c.save();XCTAssertEqual(try s.registration(for:p)?.teamID,terms.teamID)
    }
}

extension CareerCalendarTests {
    private func proCareerFixture(_ role:PlayerRole,seasons:Int=1,rating:Double=80,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let (store,p,s)=try renewalFixture(role,legacyURL:legacyURL),c=store.mainContext
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let promotionYear=try GameDate(p.gameDate).year
        try OverseasContractStore.promoteDomestic(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        for year in (promotionYear+1)...(promotionYear+seasons+1) {
            let plan=try s.competition(for:p,year:year)
            XCTAssertEqual(plan.membership?.level,"domestic-first-team")
            for (index,fixture) in try s.fixtures(for:p,year:year).filter({$0.isAppearance(for:role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
                values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(year*100+index),home:fixture.homeID == plan.teamID,tracked:true)
                match.competition="domestic-first-team";try match.advance(.automatic)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
            }
        }
        p.gameDate="\(promotionYear+seasons+1)-11-01"
        if rating > 80 {
            p.contact=rating;p.power=rating;p.discipline=rating;p.speed=rating;p.defense=rating;p.arm=rating
            let profile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c));try profile.grow(.mental,to:rating)
            if role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try profile.grow(kind,to:rating)};for pitch in p.pitches {pitch.mastery=rating}}
        }
        try c.save()
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        return (store,p,s)
    }
    func testDomesticPromotionPreservesOriginalMembershipAndHistoricalLeagueBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try renewalFixture(role),c=store.mainContext,original=try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships
            let year=try GameDate(p.gameDate).year
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let bytes=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)).payload
            XCTAssertThrowsError(try OverseasContractStore.promoteDomestic(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c,save:{_ in throw MatchError.invalidRecord}))
            XCTAssertEqual(try ContractRegistrationStore.row(player:p,in:c)?.payload,bytes)
            try OverseasContractStore.promoteDomestic(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            XCTAssertEqual(try s.registration(for:p)?.level,"domestic-development")
            XCTAssertEqual(try s.competition(for:p,year:year).membership?.level,"domestic-development")
            XCTAssertEqual(try s.competition(for:p,year:year+1).membership?.level,"domestic-first-team")
            XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).memberships,original)
            try OverseasContractStore.promoteDomestic(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c,save:{_ in XCTFail("duplicate")})
        }
    }
    func testProServiceRequiresFullCalendarYearAndActualSamplesAndConsentKeepsRights() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try proCareerFixture(role,seasons:2),c=store.mainContext
            let member=try s.registration(for:p),fatigue=p.fatigue
            try OverseasContractStore.collectService(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(value.overseasCareer?.service?.count,1)
            XCTAssertFalse(value.overseasCareer?.service?.first?.matchKeys.isEmpty ?? true)
            try OverseasContractStore.requestConsent(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            XCTAssertTrue(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.consents?.last?.approved == true)
            XCTAssertEqual(try s.registration(for:p),member);XCTAssertEqual(p.fatigue,fatigue)
            try OverseasContractStore.requestConsent(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c,save:{_ in XCTFail("same window")})
        }
    }
    func testProServiceProofAndPromotionSurviveDiskReopenAndRejectInventedYears() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,evidence:[GameProSeasonEvidence]=[]
        do {
            let (store,p,s)=try proCareerFixture(.batter,seasons:2,legacyURL:url),c=store.mainContext;id=p.id
            try OverseasContractStore.collectService(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            evidence=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.service)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.service,evidence)
        var value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        value.overseasCareer?.service?.append(GameProSeasonEvidence(year:1999,sourceOfferID:evidence[0].sourceOfferID,level:"domestic-first-team",matchKeys:[]))
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c));row.payload=try JSONEncoder().encode(value)
        XCTAssertThrowsError(try ContractRegistrationStore.journal(player:p,calendar:s,in:c));c.rollback()
    }
}

extension CareerCalendarTests {
    private func professionalOffers(_ p:CareerPlayer,_ s:CareerCalendarState,_ c:ModelContext) throws -> [OverseasOffer] {
        try OverseasContractStore.register(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.collectService(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.requestConsent(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        return try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.evaluations.last).offers
    }
    func testNPBProfessionalOffersAndJapaneseMatchDoNotInventMLBExemptionBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try proCareerFixture(role,seasons:1,rating:99),c=store.mainContext
            let offers=try professionalOffers(p,s,c)
            XCTAssertFalse(offers.isEmpty);XCTAssertTrue(offers.allSatisfy {$0.route == .npbFirstTeam})
            let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(value.overseasCareer?.service?.count,0)
            let offer=try XCTUnwrap(offers.first),oldYear=try GameDate(p.gameDate).year,old=try CareerSeasonStore.load(player:p,state:s,year:oldYear,in:c).totals.games
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            p.gameDate=offer.effective;try c.save()
            XCTAssertEqual(try s.registration(for:p)?.level,"npb-first-team");XCTAssertEqual(try s.fixtures(for:p,year:oldYear+1).count,30)
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            XCTAssertEqual(try record.snapshot().competition,"npb-first-team")
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:oldYear,in:c).totals.games,old)
        }
    }
    func testMLBProfessionalSixProvenYearsAndAcceptanceAtomicResumeBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s)=try proCareerFixture(role,seasons:7,rating:99),c=store.mainContext
            let offers=try professionalOffers(p,s,c),value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(value.overseasCareer?.service?.count,6);XCTAssertGreaterThanOrEqual(try s.age(of:p),25)
            XCTAssertTrue(offers.contains {$0.route == .npbFirstTeam});let offer=try XCTUnwrap(offers.first {$0.route == .mlbFirstTeam})
            let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),bytes=row.payload,revision=s.revision
            XCTAssertThrowsError(try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
            XCTAssertEqual(row.payload,bytes);XCTAssertEqual(s.revision,revision)
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c)
            p.gameDate=offer.effective;try c.save();XCTAssertEqual(try s.registration(for:p)?.level,"mlb-first-team")
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,record.payload)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            let completed=record.payload,fatigue=p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
            XCTAssertEqual(record.payload,completed);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:GameDate(p.gameDate).year,in:c).totals.games,1)
        }
    }
}

extension CareerCalendarTests {
    func testOverseasRegisteredCalendarStopsAtUnassessedWindowAndContinuesAfterEmptyResult() async throws {
        let (store,p,s,packet)=try acceptance(.batter),c=store.mainContext,offer=try XCTUnwrap(packet.offers.first {$0.route == .college})
        try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.register(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        p.gameDate="2030-07-01";try c.save()
        XCTAssertTrue(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
        let stopped=try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
        XCTAssertEqual(stopped.days,0);XCTAssertEqual(stopped.stop,.evaluation)
        XCTAssertThrowsError(try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c))
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        XCTAssertFalse(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
        XCTAssertTrue(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.evaluations.last?.offers.isEmpty == true)
        try CalendarProgression.advanceDay(player:p,state:s,revision:s.revision,automaticRest:true,in:c)
        XCTAssertEqual(p.gameDate,"2030-07-02")
    }
}

extension CareerCalendarTests {
    func testProfessionalForeignAcceptanceDiskReopenRetainsServiceAndOldLeagueRecords() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,terms:OverseasOffer!,matches:[Data]=[]
        do {
            let (store,p,s)=try proCareerFixture(.batter,seasons:2,rating:99,legacyURL:url),c=store.mainContext
            id=p.id;terms=try XCTUnwrap(professionalOffers(p,s,c).first {$0.route == .npbFirstTeam})
            matches=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            try OverseasContractStore.decide(player:p,calendar:s,offerID:terms.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        XCTAssertTrue(value.overseasCareer?.evaluations.last?.offers.contains(terms) == true)
        XCTAssertEqual(value.overseasCareer?.service?.count,1)
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matches)
        p.gameDate=terms.effective;try c.save()
        XCTAssertEqual(try s.registration(for:p)?.level,"npb-first-team")
        XCTAssertEqual(try s.competition(for:p,year:GameDate(terms.effective).year).teamID,terms.teamID)
    }
}

extension CareerCalendarTests {
    func testAmericanOrganizationPromotionBothRolesDoesNotCreateInternationalContract() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,offer)=try overseasOfferFixture(role),c=store.mainContext
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            let year=try GameDate(offer.effective).year
            for (index,fixture) in try s.fixtures(for:p,year:year).filter({$0.isAppearance(for:role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
                values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(9000+index),home:fixture.homeID == offer.teamID,tracked:true)
                match.competition="mlb-development";try match.advance(.automatic)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
            }
            p.gameDate="\(year)-11-01";p.contact=99;p.power=99;p.discipline=99
            let profile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c));try profile.grow(.mental,to:99)
            if role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try profile.grow(kind,to:99)};for pitch in p.pitches {pitch.mastery=99}}
            try c.save();try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let original=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),fatigue=p.fatigue
            try OverseasContractStore.promoteAmerican(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let value=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(value.overseasCareer?.evaluations,original.overseasCareer?.evaluations);XCTAssertEqual(value.overseasCareer?.decisions,original.overseasCareer?.decisions)
            XCTAssertEqual(value.overseasCareer?.transitions,original.overseasCareer?.transitions)
            XCTAssertEqual(try s.competition(for:p,year:year).membership?.level,"mlb-development")
            XCTAssertEqual(try s.competition(for:p,year:year+1).membership?.level,"mlb-first-team")
            p.gameDate="\(year+1)-04-01";try c.save()
            let member=try XCTUnwrap(s.registration(for:p));XCTAssertEqual(member.offerID,offer.id);XCTAssertEqual(member.level,"mlb-first-team")
            XCTAssertEqual(member.economicIndex,100);XCTAssertEqual(member.economicEnd,"\(year+2)-03-31");XCTAssertEqual(p.fatigue,fatigue)
        }
    }
}

extension CareerCalendarTests {
    func testOverseasMissingEvidenceShowsPreparationReasonWithoutMutatingJournal() throws {
        let (store,p,s)=try renewalFixture(.batter),c=store.mainContext
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=row.payload
        XCTAssertThrowsError(try OverseasContractStore.promoteDomestic(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)) {error in
            XCTAssertTrue(error.localizedDescription.contains("승격 조건"))
        }
        XCTAssertThrowsError(try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)) {error in
            XCTAssertTrue(error.localizedDescription.contains("보고서"))
        }
        XCTAssertEqual(row.payload,before);XCTAssertFalse(c.hasChanges)
    }
}

extension CareerCalendarTests {
    private func overseasRenewalFixture(_ role:PlayerRole,route:OverseasRoute = .mlbDevelopment,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState,OverseasOffer) {
        let store:ModelContainer,p:CareerPlayer,s:CareerCalendarState,entry:OverseasOffer
        if route == .mlbDevelopment {
            (store,p,s,entry)=try overseasOfferFixture(role,legacyURL:legacyURL)
        } else {
            (store,p,s)=try proCareerFixture(role,seasons:route == .mlbFirstTeam ? 7:1,rating:99,legacyURL:legacyURL)
            entry=try XCTUnwrap(professionalOffers(p,s,store.mainContext).first {$0.route == route})
        }
        let c=store.mainContext
        try OverseasContractStore.decide(player:p,calendar:s,offerID:entry.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        let firstYear=try GameDate(entry.economicEnd).year-1,club=entry.teamID.components(separatedBy:"-").last!
        // Select a future test window with an incumbent opening before capturing any report.
        let year=try XCTUnwrap((firstYear..<(firstYear+40)).first {year in
            let date=try! GameDate("\(year)-11-01"),period=try! ScoutingPeriod(origin:GameDate(s.originDate),today:date).index
            let seed=p.id.uuidString+"/overseas-market-v1/"+String(period)
            return DomesticSelection.hash(seed+route.id+"/"+club+"/"+entry.roleID)%5 != 0
        })
        for (index,fixture) in try s.fixtures(for:p,year:year).filter({$0.isAppearance(for:role)}).enumerated() {
            p.gameDate=fixture.date.description
            var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
            values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
            var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(year*100+index),home:fixture.homeID == entry.teamID,tracked:true)
            match.competition=entry.membership().level;try match.advance(.automatic)
            let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";c.insert(row)
        }
        p.gameDate="\(year)-11-01";p.contact=99;p.power=99;p.discipline=99;p.speed=99;p.defense=99;p.arm=99
        let profile=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c));try profile.grow(.mental,to:99)
        if role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try profile.grow(kind,to:99)};for pitch in p.pitches {pitch.mastery=99}}
        try c.save();try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        return (store,p,s,entry)
    }
    func testOverseasRenewalFreezeAcceptanceAndEffectiveTermsBothRolesAllRoutes() throws {
        for route in OverseasRoute.allCases {for role in PlayerRole.allCases {
            let (store,p,s,entry)=try overseasRenewalFixture(role,route:route),c=store.mainContext
            let old=try XCTUnwrap(s.registration(for:p)),original=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),fatigue=p.fatigue,date=p.gameDate
            let matchBytes=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            XCTAssertTrue(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
            try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:date,revision:s.revision,in:c)
            XCTAssertFalse(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
            let review=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.renewalReviews?.last)
            let offer=try XCTUnwrap(review.offer,review.reasons.joined(separator:" / "))
            try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:date,revision:-1,in:c,save:{_ in XCTFail("same window")})
            try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:s.revision,in:c)
            try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:true,date:date,revision:-1,in:c,save:{_ in XCTFail("duplicate")})
            XCTAssertThrowsError(try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:false,date:date,revision:s.revision,in:c))
            XCTAssertEqual(try s.registration(for:p),old)
            let journal=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(journal.overseasCareer?.transitions,original.overseasCareer?.transitions)
            XCTAssertEqual(journal.memberships,original.memberships)
            XCTAssertEqual(journal.overseasCareer?.renewalReviews?.last,review)
            XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),matchBytes)
            p.gameDate=offer.effective;try c.save()
            let updated=try XCTUnwrap(s.registration(for:p))
            XCTAssertEqual(updated.offerID,entry.id);XCTAssertEqual(updated.since,old.since);XCTAssertEqual(updated.teamID,old.teamID)
            XCTAssertEqual(updated.economicEnd,offer.economicEnd);XCTAssertEqual(updated.economicStart,offer.effective);XCTAssertEqual(updated.economicIndex,offer.economicIndex)
            XCTAssertEqual(try s.fixtures(for:p,year:GameDate(p.gameDate).year).count,30)
        }}
    }
    func testOverseasRenewalRollbackStaleExpiryAndRejectionRetainRights() throws {
        let (store,p,s,_)=try overseasRenewalFixture(.pitcher),c=store.mainContext
        try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),bytes=row.payload,revision=s.revision,member=try s.registration(for:p)
        let offer=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.renewalReviews?.last?.offer)
        XCTAssertThrowsError(try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision-1,in:c))
        XCTAssertThrowsError(try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(row.payload,bytes);XCTAssertEqual(s.revision,revision)
        p.gameDate=try GameDate(offer.expires).adding(days:1).description;try c.save()
        XCTAssertThrowsError(try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c))
        p.gameDate=offer.issued;try c.save()
        try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:false,date:p.gameDate,revision:s.revision,in:c)
        p.gameDate=offer.effective;try c.save()
        XCTAssertEqual(try s.registration(for:p),member)
        XCTAssertFalse(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer!.hasPendingRenewal(on:p.gameDate))
    }
    func testOverseasRenewalEmptyReportFreezeAndMultiYearIneligibility() throws {
        let (store,p,s,_)=try overseasRenewalFixture(.batter),c=store.mainContext
        // Frozen report predates lowering abilities; it must not change after training/stat changes.
        let before=try OverseasReportStore.current(player:p,calendar:s,in:c)
        p.contact=1;p.power=1;p.discipline=1;try c.save()
        try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(OverseasReportStore.current(player:p,calendar:s,in:c)),try encoder.encode(before))
        let member=try XCTUnwrap(s.registration(for:p)),date=try GameDate(p.gameDate)
        var long=CareerMembership(offerID:member.offerID,route:member.route,teamID:member.teamID,name:member.name,since:member.since,economicEnd:"\(date.year+3)-03-31",enrollmentEnd:nil,economicIndex:100)
        long.competitionLevel=member.level
        XCTAssertFalse(try OverseasRenewalReview.eligible(long,on:date))
        let report=try XCTUnwrap(before),role=try XCTUnwrap(report.observation.grades.first?.id)
        let empty=try OverseasRenewalReview.make(report:report,member:member,roleID:role,window:XCTUnwrap(ContractEvaluationWindow.containing(date)),on:date,reserved:true)
        XCTAssertNil(empty.offer);XCTAssertTrue(empty.reasons.contains {$0.contains("예약")})
    }
    func testOverseasRenewalLegacyDiskReopenPreservesRawRecords() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,terms:OverseasOffer!,raw:[Data]=[]
        do {
            let (store,p,s,_)=try overseasRenewalFixture(.pitcher,legacyURL:url),c=store.mainContext
            id=p.id;raw=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            terms=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.renewalReviews?.last?.offer)
            try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:terms.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),raw)
        XCTAssertTrue(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer!.hasPendingRenewal(on:p.gameDate))
        p.gameDate=terms.effective;try c.save();XCTAssertEqual(try s.registration(for:p)?.economicEnd,terms.economicEnd)
    }
}

extension CareerCalendarTests {
    func testOverseasRenewalEmptySampleFreezesAndCalendarStopsAtNovember() async throws {
        for role in PlayerRole.allCases {
            let (store,p,s,entry)=try overseasOfferFixture(role),c=store.mainContext
            try OverseasContractStore.decide(player:p,calendar:s,offerID:entry.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            let year=try GameDate(entry.effective).year
            p.gameDate="\(year)-10-31";s.actionDate=nil;try c.save()
            let summary=try await CalendarProgression.advanceOffDays(player:p,state:s,in:c)
            XCTAssertEqual(summary.stop,.evaluation);XCTAssertEqual(p.gameDate,"\(year)-11-01")
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let review=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.renewalReviews?.last)
            XCTAssertNil(review.offer);XCTAssertTrue(review.reasons.contains {$0.contains("동일 환경")})
            XCTAssertFalse(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
            try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:-1,in:c,save:{_ in XCTFail("empty result also fixed")})
            XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.renewalReviews?.last,review)
        }
    }
    func testOverseasRenewalNextSeasonResumeAndOneTimeResultBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,_)=try overseasRenewalFixture(role),c=store.mainContext
            try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let terms=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.renewalReviews?.last?.offer)
            try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:terms.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            p.gameDate=terms.effective;try c.save();try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let record=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,record.payload)
            let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=row.payload
            XCTAssertThrowsError(try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c))
            XCTAssertEqual(row.payload,before)
            try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c)
            let bytes=record.payload,fatigue=p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:record,revision:record.revision,input:.automatic,in:c))
            XCTAssertEqual(record.payload,bytes);XCTAssertEqual(p.fatigue,fatigue)
            XCTAssertEqual(try CareerSeasonStore.load(player:p,state:s,year:GameDate(p.gameDate).year,in:c).totals.games,1)
        }
    }
    func testOverseasRenewalProjectionKeepsPromotionAndEconomicChronology() throws {
        let (store,p,s,_)=try overseasRenewalFixture(.pitcher),c=store.mainContext
        try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        var owner=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        let review=try XCTUnwrap(owner.overseasCareer?.renewalReviews?.last),terms=try XCTUnwrap(review.offer)
        try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:terms.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        XCTAssertThrowsError(try OverseasContractStore.promoteAmerican(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c))
        owner=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
        // Projection unit test: an older minor renewal cannot overwrite a later major placement.
        let start=try GameDate(terms.effective).anniversary(in:GameDate(terms.effective).year+1)
        let promotion=CareerLevelPromotion(id:"projection-only",sourceOfferID:review.source.offerID,reportID:review.reportID,date:start.adding(days:-150).description,effective:start.description,fromLevel:"mlb-development",toLevel:"mlb-first-team",teamID:review.source.teamID.replacingOccurrences(of:"us-dev-",with:"us-pro-"),h:99,sampleCount:100,roleID:"starter")
        owner.overseasCareer?.promotions=[promotion]
        let promoted=try owner.projected(review.source,on:start)
        XCTAssertEqual(promoted.level,"mlb-first-team");XCTAssertEqual(promoted.economicStart,start.description)
        XCTAssertEqual(promoted.economicEnd,start.anniversary(in:start.year+1).adding(days:-1).description)
        XCTAssertEqual(promoted.economicIndex,100)
    }
    func testOverseasRenewalPendingTrainingAndEvaluationSaveFailureDoNotWrite() throws {
        let (store,p,s,_)=try overseasRenewalFixture(.batter),c=store.mainContext
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=row.payload,revision=s.revision
        XCTAssertThrowsError(try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(row.payload,before);XCTAssertEqual(s.revision,revision)
        _ = try CareerTrainingStore.start(player:p,state:s,kind:.contact,in:c)
        XCTAssertThrowsError(try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c))
        XCTAssertEqual(row.payload,before)
    }
}

extension CareerCalendarTests {
    private func overseasReleaseFixture(_ role:PlayerRole,route:OverseasRoute = .mlbDevelopment,released:Bool=true,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState,CareerMembership) {
        let (store,p,s,_)=try overseasRenewalFixture(role,route:route,legacyURL:legacyURL),c=store.mainContext
        try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let member=try XCTUnwrap(s.registration(for:p)),state=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer)
        let review=try XCTUnwrap(state.renewalReviews?.last)
        if let offer=review.offer {try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:false,date:p.gameDate,revision:s.revision,in:c)}
        p.gameDate=max(review.window.end.adding(days:1),try GameDate(member.economicEnd).adding(days:1)).description
        try c.save()
        if released {try OverseasContractStore.release(player:p,calendar:s,membershipID:member.offerID,date:p.gameDate,revision:s.revision,in:c)}
        return (store,p,s,member)
    }
    func testOverseasReleaseIsExplicitAndKeepsAllRoutesHistoryAndRecords() throws {
        for route in OverseasRoute.allCases {
            let (store,p,s,member)=try overseasReleaseFixture(.pitcher,route:route,released:false),c=store.mainContext
            let before=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),bytes=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),date=p.gameDate,fatigue=p.fatigue
            XCTAssertNotNil(try s.registration(for:p));XCTAssertTrue(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer!.releases == nil)
            try OverseasContractStore.release(player:p,calendar:s,membershipID:member.offerID,date:date,revision:s.revision,in:c)
            let after=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertNil(try s.registration(for:p));XCTAssertEqual(after.overseasCareer?.transitions,before.overseasCareer?.transitions)
            XCTAssertEqual(after.overseasCareer?.renewalReviews,before.overseasCareer?.renewalReviews);XCTAssertEqual(after.memberships,before.memberships)
            XCTAssertEqual(after.membershipHistory().last?.releasedOn,date);XCTAssertEqual(after.retryReleases.last?.membershipOfferID,member.offerID)
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),bytes);XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue)
            try OverseasContractStore.release(player:p,calendar:s,membershipID:member.offerID,date:date,revision:-1,in:c,save:{_ in XCTFail("duplicate")})
        }
    }
    func testOverseasReleaseRejectsEarlyAcceptedRenewalStaleAndSaveFailure() throws {
        let (store,p,s,_)=try overseasRenewalFixture(.batter),c=store.mainContext
        try OverseasContractStore.evaluateRenewal(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let owner=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),member=try XCTUnwrap(s.registration(for:p)),offer=try XCTUnwrap(owner.overseasCareer?.renewalReviews?.last?.offer)
        XCTAssertThrowsError(try OverseasContractStore.release(player:p,calendar:s,membershipID:member.offerID,date:p.gameDate,revision:s.revision,in:c))
        try OverseasContractStore.decideRenewal(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        p.gameDate=try GameDate(member.economicEnd).adding(days:1).description;try c.save()
        XCTAssertThrowsError(try OverseasContractStore.release(player:p,calendar:s,membershipID:member.offerID,date:p.gameDate,revision:s.revision,in:c))
        let (other,q,t,source)=try overseasReleaseFixture(.pitcher,released:false),d=other.mainContext
        let row=try XCTUnwrap(ContractRegistrationStore.row(player:q,in:d)),raw=row.payload,revision=t.revision
        XCTAssertThrowsError(try OverseasContractStore.release(player:q,calendar:t,membershipID:source.offerID,date:q.gameDate,revision:revision-1,in:d))
        XCTAssertThrowsError(try OverseasContractStore.release(player:q,calendar:t,membershipID:source.offerID,date:q.gameDate,revision:revision,in:d,save:{_ in throw MatchError.invalidRecord}))
        XCTAssertEqual(row.payload,raw);XCTAssertEqual(t.revision,revision);XCTAssertEqual(try t.registration(for:q),source)
        _ = try CareerTrainingStore.start(player:q,state:t,pitchCode:q.pitches[0].code,in:d)
        XCTAssertThrowsError(try OverseasContractStore.release(player:q,calendar:t,membershipID:source.offerID,date:q.gameDate,revision:t.revision,in:d))
    }
    func testOverseasReleaseCertificationReentryAndNextMatchResumeBothRoles() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,source)=try overseasReleaseFixture(role),c=store.mainContext
            let original=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            let row=try CertificationStore.start(player:p,calendar:s,in:c)
            try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c)
            XCTAssertEqual(try CertificationStore.start(player:p,calendar:s,in:c).payload,row.payload)
            while !row.completed {try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c)}
            let result=try row.snapshot(),certificate=try XCTUnwrap(result.assessment),raw=row.payload
            XCTAssertTrue(certificate.passed);XCTAssertEqual(result.releaseOfferID,source.offerID)
            p.gameDate=result.window.start.description;try c.save();try ContractEvaluationStore.registerCurrent(in:c)
            let evaluation=try XCTUnwrap(ContractEvaluationStore.records(player:p,calendar:s,in:c).first {$0.key == CareerContractEvaluation.key(p.id,result.window.id)})
            let snapshot=try evaluation.snapshot(player:p,calendar:s)
            XCTAssertEqual(snapshot.retry?.certificate,certificate)
            let packet=try XCTUnwrap(ContractOfferStore.records(player:p,calendar:s,in:c).first {$0.key == evaluation.key}).snapshot(evaluation:evaluation,player:p,calendar:s)
            let offer=try XCTUnwrap(packet.offers.first)
            try ContractRegistrationStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            XCTAssertEqual(try s.registration(for:p)?.level,"domestic-development")
            XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),original);XCTAssertEqual(row.payload,raw)
            let fixture=try XCTUnwrap(s.upcoming(for:p).first {$0.isAppearance(for:role)})
            p.gameDate=fixture.date.description;s.actionDate=nil;try c.save()
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let match=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:match,revision:match.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,match.payload)
            try CareerMatchStore.advance(player:p,state:s,record:match,revision:match.revision,input:.automatic,in:c)
            let saved=match.payload,fatigue=p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:match,revision:match.revision,input:.automatic,in:c))
            XCTAssertEqual(match.payload,saved);XCTAssertEqual(p.fatigue,fatigue)
        }
    }
    func testOverseasReleaseDiskReopenKeepsSourceAndUnfinishedCertification() throws {
        var stage="fixture"
        do {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,bytes:Data!,source:CareerMembership!
        do {
            let (store,p,s,member)=try overseasReleaseFixture(.batter,legacyURL:url),c=store.mainContext
            id=p.id;source=member
            XCTAssertFalse(c.hasChanges,"foreign fixture must be saved")
        }
        // Legacy fixture is V12; open the product container to migrate to V13 before certification.
        do {
            stage="migration"
            let store=try CareerStore.makeContainer(url:url),c=store.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
            stage="migrated journal"
            _ = try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            stage="certificate start"
            let row=try CertificationStore.start(player:p,calendar:s,in:c)
            stage="certificate advance"
            try CertificationStore.advance(player:p,calendar:s,row:row,revision:row.revision,in:c);bytes=row.payload
        }
        stage="reopen"
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        XCTAssertFalse(c.hasChanges,"reopened context")
        let resumed=try CertificationStore.start(player:p,calendar:s,in:c)
        XCTAssertNil(try s.registration(for:p));XCTAssertEqual(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.releases?.last?.source,source)
        XCTAssertEqual(resumed.payload,bytes)
        XCTAssertFalse(c.hasChanges,"read-only journal must not leave changes")
        XCTAssertEqual(try CertificationStore.start(player:p,calendar:s,in:c).payload,bytes)
        } catch {XCTFail("\(stage): \(String(reflecting:error))")}
    }
}

extension CareerCalendarTests {
    private func faFixture(_ role:PlayerRole,route:OverseasRoute = .npbFirstTeam,legacyURL:URL?=nil) throws -> (ModelContainer,CareerPlayer,CareerCalendarState) {
        let (store,p,s,_)=try overseasRenewalFixture(role,route:route,legacyURL:legacyURL),c=store.mainContext
        let owner=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),member=try XCTUnwrap(s.registration(for:p)),start=try GameDate(p.gameDate).year+1
        let existing=try FASeasonEvidence.collect(owner:owner,role:role,on:GameDate(p.gameDate),rows:c.fetch(FetchDescriptor<CareerMatchRecord>())).filter {$0.level == member.level}.count
        let missing=FADeclaration.minimum(member.level)-existing
        for year in start..<(start+missing) {
            var totals=PersonalSeasonTotals()
            for (index,fixture) in try SeasonSchedule.fixtures(year:year,schoolIDs:CareerTeamDirectory.teams(level:member.level)).filter({$0.includes(member.teamID) && $0.isAppearance(for:role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
                values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
                var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(year*100+index),home:fixture.homeID == member.teamID,tracked:true)
                match.competition=member.level;try match.advance(.automatic)
                let row=try CareerMatchRecord(verificationPlayerID:p.id,teamID:member.teamID,fixture:fixture,match:match,fatigue:p.fatigue);c.insert(row)
                try totals.add(match.line)
                if role == .batter ? totals.line.plateAppearances >= 100:totals.line.pitchingOuts >= 75 {break}
            }
        }
        p.gameDate="\(start+missing-1)-11-01";try c.save()
        try OverseasContractStore.collectFAService(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        return (store,p,s)
    }
    func testFAServiceSeparatesLeaguesRequiresRegistrationSampleAndExactThreshold() throws {
        let (store,p,s)=try faFixture(.pitcher,route:.mlbFirstTeam),c=store.mainContext
        let journal=try ContractRegistrationStore.journal(player:p,calendar:s,in:c),member=try XCTUnwrap(s.registration(for:p)),service=try XCTUnwrap(journal.overseasCareer?.faService)
        XCTAssertEqual(service.filter {$0.level == "mlb-first-team"}.count,6);XCTAssertEqual(service.filter {$0.level == "npb-first-team"}.count,0)
        XCTAssertThrowsError(try FADeclaration.make(member:member,on:GameDate(p.gameDate),service:Array(service.dropLast())))
        let all=try c.fetch(FetchDescriptor<CareerMatchRecord>())
        let withoutLast=all.filter {!$0.gameDate.hasPrefix(String(service.last!.year))}
        XCTAssertEqual(try FASeasonEvidence.collect(owner:journal,role:p.role,on:GameDate(p.gameDate),rows:withoutLast).count,5)
        XCTAssertThrowsError(try FADeclaration.make(member:member,on:GameDate("\(GameDate(p.gameDate).year)-04-01"),service:service))

        let raw=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),fatigue=p.fatigue,date=p.gameDate
        try OverseasContractStore.declareFA(player:p,calendar:s,date:date,revision:s.revision,in:c)
        XCTAssertEqual(try s.registration(for:p),member)
        let state=try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer!,fa=try XCTUnwrap(state.faDeclarations?.last)
        XCTAssertNil(state.releases);XCTAssertEqual(fa.service,service)
        try OverseasContractStore.declareFA(player:p,calendar:s,date:date,revision:-1,in:c,save:{_ in XCTFail("repeat declaration")})
        XCTAssertEqual(p.gameDate,date);XCTAssertEqual(p.fatigue,fatigue);XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),raw)
        p.gameDate=fa.effective;try c.save();XCTAssertNil(try s.registration(for:p))
        XCTAssertTrue(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).retryReleases.isEmpty)
        XCTAssertNil(try ContractRegistrationStore.journal(player:p,calendar:s,in:c).activeRetryRelease)
        XCTAssertThrowsError(try CertificationStore.start(player:p,calendar:s,in:c))

    }
    func testNPBFABothRolesCreatesFrozenProfessionalOffersAndPreservesNextMatchOnce() throws {
        for role in PlayerRole.allCases {
            var stage="fixture"
            do {
            let (store,p,s)=try faFixture(role),c=store.mainContext
            stage="journal"
            let owner=try ContractRegistrationStore.journal(player:p,calendar:s,in:c)
            XCTAssertEqual(owner.overseasCareer?.faService?.filter {$0.level == "npb-first-team"}.count,9)
            let registration=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=registration.payload,revision=s.revision
            XCTAssertThrowsError(try OverseasContractStore.declareFA(player:p,calendar:s,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
            XCTAssertEqual(registration.payload,before);XCTAssertEqual(s.revision,revision)
            stage="declare"
            try OverseasContractStore.declareFA(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            XCTAssertTrue(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
            stage="report"
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            stage="evaluation"
            try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let evaluation=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer?.evaluations.last)
            XCTAssertFalse(try OverseasContractStore.needsEvaluation(player:p,calendar:s,in:c))
            XCTAssertEqual(evaluation.version,3);XCTAssertNotNil(evaluation.mobility?.fa);XCTAssertNil(evaluation.mobility?.release)
            let offer=try XCTUnwrap(evaluation.offers.first,evaluation.reasons.joined(separator:" / "))
            try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:-1,in:c,save:{_ in XCTFail("same window")})
            stage="accept"
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
            stage="effective"
            p.gameDate=offer.effective;try c.save()
            XCTAssertEqual(try s.registration(for:p)?.teamID,offer.teamID)
            XCTAssertEqual(try s.fixtures(for:p,year:GameDate(p.gameDate).year).count,30)
            stage="match"
            try CalendarProgression.rest(player:p,state:s,revision:s.revision,in:c)
            let row=try CareerMatchStore.start(player:p,state:s,in:c)
            try CareerMatchStore.advance(player:p,state:s,record:row,revision:row.revision,input:role == .batter ? .watch:.pitch,pitchCode:role == .pitcher ? p.pitches[0].code:nil,in:c)
            XCTAssertEqual(try CareerMatchStore.start(player:p,state:s,in:c).payload,row.payload)
            try CareerMatchStore.advance(player:p,state:s,record:row,revision:row.revision,input:.automatic,in:c)
            let raw=row.payload,fatigue=p.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player:p,state:s,record:row,revision:row.revision,input:.automatic,in:c))
            XCTAssertEqual(row.payload,raw);XCTAssertEqual(p.fatigue,fatigue)
            } catch {XCTFail("\(role) \(stage): \(String(reflecting:error))")}
        }
    }
    func testReleasedProfessionalCanReenterWithoutReceivingFAQualification() throws {
        for role in PlayerRole.allCases {
            let (store,p,s,source)=try overseasReleaseFixture(role,route:.npbFirstTeam),c=store.mainContext
            let date=try GameDate(p.gameDate)
            p.gameDate=try CertificationStore.target(on:date).start.description;try c.save()
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            try OverseasContractStore.collectFAService(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let state=try ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer!,evaluation=try XCTUnwrap(state.evaluations.last)
            XCTAssertEqual(evaluation.version,3);XCTAssertNil(state.faDeclarations);XCTAssertEqual(evaluation.mobility?.release?.source,source)
            XCTAssertTrue(evaluation.offers.allSatisfy {$0.route == .npbFirstTeam})
            let offer=try XCTUnwrap(evaluation.offers.first,evaluation.reasons.joined(separator:" / "))
            let row=try XCTUnwrap(ContractRegistrationStore.row(player:p,in:c)),before=row.payload,revision=s.revision
            XCTAssertThrowsError(try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c,save:{_ in throw MatchError.invalidRecord}))
            XCTAssertEqual(row.payload,before);XCTAssertEqual(s.revision,revision)
            try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:revision,in:c)
            p.gameDate=offer.effective;try c.save();XCTAssertEqual(try s.registration(for:p)?.level,"npb-first-team")
        }
    }
}

extension CareerCalendarTests {
    func testFADiskReopenPreservesDeclarationAndFrozenMobilityOffer() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("career.store");var id:UUID!,offer:OverseasOffer!,declaration:FADeclaration!,records:[Data]=[]
        do {
            let (store,p,s)=try faFixture(.pitcher,legacyURL:url),c=store.mainContext
            id=p.id;records=try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload)
            try OverseasContractStore.declareFA(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
            let state=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer)
            declaration=try XCTUnwrap(state.faDeclarations?.last);offer=try XCTUnwrap(state.evaluations.last?.offers.first)
        }
        let store=try CareerStore.makeContainer(url:url),c=store.mainContext,p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == id}),s=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == id})
        let state=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer)
        XCTAssertEqual(state.faDeclarations?.last,declaration);XCTAssertEqual(state.evaluations.last?.offers.first,offer)
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).map(\.payload),records)
        try OverseasContractStore.decide(player:p,calendar:s,offerID:offer.id,accept:true,date:p.gameDate,revision:s.revision,in:c)
        p.gameDate=offer.effective;try c.save();XCTAssertEqual(try s.registration(for:p)?.teamID,offer.teamID)
    }
    func testReleasedMajorLeaguerCanReceiveMajorOfferBeforeSixFASeasons() throws {
        let (store,p,s,_)=try overseasReleaseFixture(.pitcher,route:.mlbFirstTeam),c=store.mainContext
        p.gameDate=try CertificationStore.target(on:GameDate(p.gameDate)).start.description;try c.save()
        try OverseasContractStore.collectFAService(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasReportStore.capture(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        try OverseasContractStore.evaluate(player:p,calendar:s,date:p.gameDate,revision:s.revision,in:c)
        let state=try XCTUnwrap(ContractRegistrationStore.journal(player:p,calendar:s,in:c).overseasCareer)
        XCTAssertLessThan(state.faService?.filter {$0.level == "mlb-first-team"}.count ?? 0,6)
        XCTAssertNil(state.faDeclarations);XCTAssertNotNil(state.evaluations.last?.mobility?.release)
        XCTAssertTrue(state.evaluations.last?.offers.contains {$0.route == .mlbFirstTeam} == true)
    }
}
