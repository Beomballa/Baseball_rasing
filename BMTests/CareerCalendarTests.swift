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
        s.originDate = "2026-02-01"; p.gameDate = "2027-01-20"; try c.save()
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
