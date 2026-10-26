import XCTest
import SwiftData
@testable import BM

@MainActor final class ManagementSeasonTests: XCTestCase {
    func testOpponentSeasonFreezeBothRolesResumeAndExactlyOnce() throws {
        for role in PlayerRole.allCases {
            let memory = try CareerStore.makeContainer(inMemory: true), context = memory.mainContext
            var draft = PlayerDraft(); draft.name = "기록선수"; draft.schoolID = "hs-ref-001"; draft.role = role
            let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
            let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            let fixture = try state.fixtures(for: player, year: 2026)[5]
            let all = try state.fixtures(for: player, year: 2026)
            for date in Set(all.filter { $0.date < fixture.date }.map(\.date)).sorted() {
                player.gameDate = date.description
                try AutomaticLeagueStore.completeDay(player: player, state: state, date: date, in: context)
            }
            player.gameDate = fixture.date.description; try context.save()
            let analysis = try CareerMatchStore.opposition(player: player, state: state)
            let preview = try CareerMatchStore.opponentSeason(player: player, state: state, analysis: analysis, in: context)
            XCTAssertFalse(preview.players.isEmpty)
            XCTAssertEqual(preview.through, try fixture.date.adding(days: -1).description)
            let ledger = try CareerMatchStore.seasonPlayerRecords(playerID: player.id, year: 2026, competition: "highschool", through: fixture.date.adding(days: -1), in: context)
            for row in preview.players {
                let original = try XCTUnwrap(ledger.players.first { $0.id == row.id && $0.teamID == preview.teamID })
                XCTAssertEqual(row.batting, original.batting); XCTAssertEqual(row.pitching, original.pitching)
            }
            try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
            let choice: MatchPlanChoice = role == .batter ? .contact : .control
            let record = try CareerMatchStore.startPrepared(player: player, state: state, choice: choice, date: player.gameDate, revision: state.revision, in: context)
            XCTAssertEqual(try record.snapshot().preparation?.season, preview)
            let before = record.payload
            XCTAssertEqual(try CareerMatchStore.start(player: player, state: state, in: context).payload, before)
            try CareerMatchStore.advance(player: player, state: state, record: record, revision: record.revision, input: .automatic, in: context)
            XCTAssertEqual(try record.snapshot().preparation?.season, preview)
            let completed = record.payload, fatigue = player.fatigue
            XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: record, revision: record.revision, input: .automatic, in: context))
            XCTAssertEqual(record.payload, completed); XCTAssertEqual(player.fatigue, fatigue)
            // Old preparations decode without backfilling a new report.
            var match = try record.snapshot(); match.preparation?.season = nil
            record.payload = try JSONEncoder().encode(match); try context.save()
            let legacy = record.payload
            XCTAssertNil(try record.snapshot().preparation?.season)
            XCTAssertEqual(try CareerMatchStore.start(player: player, state: state, in: context).payload, legacy)
        }
    }
    func testSeasonMetricsUnknownCoverageAndRawRounding() throws {
        var batting = MatchBattingCounts(); batting.atBats = 3; batting.plateAppearances = 4; batting.singles = 1; batting.walks = 1
        var pitching = MatchPitchingCounts(earnedRuns: 1); pitching.pitches = 50; pitching.battersFaced = 10; pitching.outs = 8; pitching.hits = 2; pitching.walks = 1; pitching.strikeouts = 3; pitching.runsAllowed = 2
        let row = MatchOpponentSeasonPlayer(id: "test", battingGames: 1, pitchingGames: 1, earnedRunGames: 1, unscoredPitchingGames: 0, batting: batting, pitching: pitching)
        XCTAssertEqual(row.value("AVG"), "0.333"); XCTAssertEqual(row.value("OBP"), "0.500")
        XCTAssertEqual(row.value("OPS"), "0.833"); XCTAssertEqual(row.value("ERA"), "3.38"); XCTAssertEqual(row.value("ER"), "1")
        XCTAssertEqual(row.value("WAR"), "미집계")
        let unknown = MatchOpponentSeasonPlayer(id: "old", battingGames: 0, pitchingGames: 1, earnedRunGames: 0, unscoredPitchingGames: 1, batting: MatchBattingCounts(), pitching: MatchPitchingCounts())
        XCTAssertEqual(unknown.value("AVG"), "미집계"); XCTAssertEqual(unknown.value("ERA"), "미집계")
    }
}
