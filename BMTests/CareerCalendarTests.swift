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
            try await CalendarProgression.advanceOffDays(player: player, state: state, in: container.mainContext) { date in
                XCTAssertFalse(container.mainContext.hasChanges)
                dates.append(date)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let summary = try await task.value
        XCTAssertEqual(dates, ["2026-04-03"])
        XCTAssertEqual(summary.days, 1)
        XCTAssertEqual(summary.stop, .cancelled)
        XCTAssertEqual(player.fatigue, 30)
        XCTAssertEqual(player.gameDate, "2026-04-03")
    }

}
