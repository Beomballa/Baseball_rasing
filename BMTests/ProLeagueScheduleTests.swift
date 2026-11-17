import Foundation
import XCTest
@testable import BM

@MainActor final class ProLeagueScheduleTests: XCTestCase {
    private let domestic = (0..<10).map { "domestic-\($0)" }

    func testV162DomesticScheduleBalancesAllTenTeamsAndOpponents() throws {
        for year in [2026, 2036, 2096] {
            let fixtures = try SeasonSchedule.domesticExpandedFixtures(year: year, teamIDs: domestic)
            XCTAssertEqual(fixtures, try SeasonSchedule.domesticExpandedFixtures(year: year, teamIDs: domestic))
            XCTAssertEqual(fixtures.count, 150)
            XCTAssertEqual(Set(fixtures.map(\.id)).count, 150)
            XCTAssertEqual(fixtures.first?.date.description, "\(year)-04-01")
            XCTAssertEqual(fixtures.last?.date.description, "\(year)-09-22")
            let days = Dictionary(grouping: fixtures, by: \.date)
            XCTAssertEqual(days.count, 30)
            for games in days.values {
                XCTAssertEqual(games.count, 5)
                XCTAssertEqual(Set(games.flatMap { [$0.homeID, $0.awayID] }), Set(domestic))
                XCTAssertTrue(games.allSatisfy { $0.homeID != $0.awayID })
            }
            for team in domestic {
                let own = fixtures.filter { $0.includes(team) }.map { $0.forTeam(team) }
                XCTAssertEqual(own.map(\.number), Array(1...30))
                XCTAssertEqual(own.filter { $0.homeID == team }.count, 15)
                XCTAssertEqual(own.filter { $0.awayID == team }.count, 15)
                XCTAssertEqual(own.filter { $0.isAppearance(for: .pitcher) }.map(\.number), [1, 6, 11, 16, 21, 26])
                let opponents = Dictionary(grouping: own, by: { $0.opponent(of: team) })
                XCTAssertEqual(opponents.count, 9)
                XCTAssertEqual(opponents.values.filter { $0.count == 3 }.count, 6)
                XCTAssertEqual(opponents.values.filter { $0.count == 4 }.count, 3)
                for games in opponents.values {
                    XCTAssertTrue((1...2).contains(games.filter { $0.homeID == team }.count))
                    XCTAssertTrue((1...2).contains(games.filter { $0.awayID == team }.count))
                }
            }
        }
    }

    func testV162DomesticScheduleRejectsIncompleteOrDuplicateTeams() throws {
        XCTAssertThrowsError(try SeasonSchedule.domesticExpandedFixtures(year: 2036, teamIDs: Array(domestic.prefix(9))))
        XCTAssertThrowsError(try SeasonSchedule.domesticExpandedFixtures(year: 2036, teamIDs: domestic + ["extra"]))
        XCTAssertThrowsError(try SeasonSchedule.domesticExpandedFixtures(year: 2036, teamIDs: Array(repeating: "same", count: 10)))
    }

    func testV162DomesticSeasonRequiresAll150FixturesAndAdvancesToApril() throws {
        let fixtures = try SeasonSchedule.domesticExpandedFixtures(year: 2036, teamIDs: domestic)
        let origin = try GameDate("2026-04-01"), opening = try GameDate("2036-04-01")
        let end = try GameDate("2036-09-23")
        let unfinished = try AnnualLeague.make(playerID: UUID(), schoolIDs: domestic, origin: origin,
            startAge: 16, today: opening, year: 2036, official: [], competitionFixtures: fixtures)
        XCTAssertTrue(unfinished.hasFullSchedule)
        XCTAssertFalse(unfinished.isComplete)
        XCTAssertThrowsError(try OffseasonPlan.make(summary: CareerSeasonSummary(league: unfinished, totals: PersonalSeasonTotals()),
            origin: origin, startAge: 16, today: opening))

        let partial = try AnnualLeague.make(playerID: UUID(), schoolIDs: domestic, origin: origin,
            startAge: 16, today: end, year: 2036, official: [], competitionFixtures: Array(fixtures.dropLast()))
        XCTAssertEqual(partial.results.count, 149)
        XCTAssertFalse(partial.hasFullSchedule)
        XCTAssertFalse(partial.isComplete)

        let draws = fixtures.map { LeagueOfficialResult(fixtureID: $0.id, homeScore: 2, awayScore: 2) }
        let completed = try AnnualLeague.make(playerID: UUID(), schoolIDs: domestic, origin: origin,
            startAge: 16, today: end, year: 2036, official: draws, competitionFixtures: fixtures)
        XCTAssertTrue(completed.isComplete)
        XCTAssertEqual(completed.results.count, 150)
        XCTAssertEqual(completed.standings.count, 10)
        XCTAssertTrue(completed.standings.allSatisfy { $0.games == 30 })
        let summary = CareerSeasonSummary(league: completed, totals: PersonalSeasonTotals())
        XCTAssertEqual(summary.champions.count, 10)
        let offseason = try OffseasonPlan.make(summary: summary, origin: origin, startAge: 16, today: end)
        XCTAssertEqual(offseason.target.description, "2037-04-01")
    }

    func testV162LegacySixAndBothFifteenTeamDivisionsKeepThirtyGames() throws {
        let legacy = (0..<6).map { "legacy-\($0)" }
        let old = try SeasonSchedule.fixtures(year: 2036, schoolIDs: legacy)
        XCTAssertEqual(old.count, 90)
        XCTAssertEqual(old.first?.id, "2036-04-01-legacy-0-legacy-5")
        for team in legacy {
            XCTAssertEqual(old.filter { $0.includes(team) }.map(\.number), Array(1...30))
            XCTAssertEqual(old.filter { $0.homeID == team }.count, 15)
            XCTAssertEqual(old.filter { $0.awayID == team }.count, 15)
        }
        for eastCount in [7, 8] {
            let east = (0..<eastCount).map { "east-\($0)" }
            let west = (0..<(15-eastCount)).map { "west-\($0)" }
            let fixtures = try SeasonSchedule.expandedFixtures(year: 2036, east: east, west: west)
            let days = Dictionary(grouping: fixtures, by: \.date)
            XCTAssertEqual(fixtures.count, 225)
            XCTAssertEqual(Set(fixtures.map(\.id)).count, 225)
            XCTAssertEqual(days.count, 35)
            for games in days.values {
                let playing = games.flatMap { [$0.homeID, $0.awayID] }
                XCTAssertEqual(Set(playing).count, playing.count)
            }
            for team in east + west {
                let own = fixtures.filter { $0.includes(team) }.map { $0.forTeam(team) }
                XCTAssertEqual(own.map(\.number), Array(1...30))
                XCTAssertEqual(own.filter { $0.homeID == team }.count, 15)
                XCTAssertEqual(own.filter { $0.awayID == team }.count, 15)
                XCTAssertEqual(days.count-own.count, 5)
            }
        }
    }

    func testV162PitcherRotationUsesSavedTeamFixtureNumberAcrossByes() throws {
        let east = (0..<8).map { "east-\($0)" }, west = (0..<7).map { "west-\($0)" }
        let fixtures = try SeasonSchedule.expandedFixtures(year: 2036, east: east, west: west)
        let opening = try GameDate("2036-04-01"), playerID = UUID()
        let own = fixtures.filter { $0.includes(east[0]) }.map { $0.forTeam(east[0]) }
        let mismatch = try XCTUnwrap(own.first {
            $0.isAppearance(for: .pitcher) != (opening.days(to: $0.date)/6).isMultiple(of: 5)
        })
        let review = try pitcherReview(playerID: playerID, team: east[0], date: mismatch.date)
        let selection = MatchClubSelection(fixtureID: mismatch.id, review: review,
            rotationDay: mismatch.isAppearance(for: .pitcher), fixtureNumber: mismatch.number)
        let roundTrip = try JSONDecoder().decode(MatchClubSelection.self, from: JSONEncoder().encode(selection))
        XCTAssertEqual(roundTrip, selection)
        XCTAssertNoThrow(try roundTrip.validate(fixtureID: mismatch.id, playerID: playerID,
            date: mismatch.date.description, competition: "npb-first-team", appearance: selection.appearance, role: "pitcher"))
        var invalid = selection
        invalid.fixtureNumber = 0
        XCTAssertThrowsError(try invalid.validate(fixtureID: mismatch.id, playerID: playerID,
            date: mismatch.date.description, competition: "npb-first-team", appearance: selection.appearance, role: "pitcher"))
        invalid.fixtureNumber = 31
        XCTAssertThrowsError(try invalid.validate(fixtureID: mismatch.id, playerID: playerID,
            date: mismatch.date.description, competition: "npb-first-team", appearance: selection.appearance, role: "pitcher"))
    }

    func testV162LegacySelectionWithoutFixtureNumberKeepsDateRule() throws {
        let day = try GameDate("2036-04-01"), playerID = UUID()
        let review = try pitcherReview(playerID: playerID, team: "old-team", date: day)
        let old = MatchClubSelection(fixtureID: "old-fixture", review: review, rotationDay: true)
        let data = try JSONEncoder().encode(old)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["fixtureNumber"])
        let decoded = try JSONDecoder().decode(MatchClubSelection.self, from: data)
        XCTAssertNil(decoded.fixtureNumber)
        XCTAssertNoThrow(try decoded.validate(fixtureID: "old-fixture", playerID: playerID,
            date: day.description, competition: "npb-first-team", appearance: true, role: "pitcher"))
    }

    private func pitcherReview(playerID: UUID, team: String, date: GameDate) throws -> ClubSelectionReview {
        try ClubSelectionReview.make(context: "membership/\(team)/npb-first-team/\(date.year)/P",
            membershipID: "membership", teamID: team, level: "npb-first-team", position: "P", roleID: "starter",
            date: date,
            own: ClubSelectionCandidate(id: playerID.uuidString, h: 80, p: 0, readiness: 100, evidence: nil, note: "QA"),
            rival: ClubSelectionCandidate(id: "npc", h: 30, p: 0, readiness: 100, evidence: nil, note: "QA"), previous: nil)
    }
}
