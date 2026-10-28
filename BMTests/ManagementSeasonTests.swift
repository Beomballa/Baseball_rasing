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

extension ManagementSeasonTests {
    private func v53Fixture(_ role:PlayerRole) throws -> (ModelContainer,CareerPlayer,CareerCalendarState,CareerMatchRecord) {
        let memory=try CareerStore.makeContainer(inMemory:true),c=memory.mainContext
        var draft=PlayerDraft();draft.role=role;draft.schoolID="hs-ref-001";draft.name="시즌점검"
        let player=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:c)
        let state=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
        try CalendarProgression.rest(player:player,state:state,revision:state.revision,in:c)
        let row=try CareerMatchStore.start(player:player,state:state,in:c)
        try CareerMatchStore.advance(player:player,state:state,record:row,revision:row.revision,input:.automatic,in:c)
        return (memory,player,state,row)
    }
    func testV53DailyTeamAppearanceAndActionAreIndependentAndSavedMatchWins() throws {
        let date=try GameDate("2026-04-07"),fixture=SeasonFixture(number:2,date:date,homeID:"a",awayID:"b")
        for role in PlayerRole.allCases {
            let before=CalendarDayPresentation(role:role,fixture:fixture,saved:.none,starter:true,selectionFailed:false,actionUsed:false,trainingPending:false)
            XCTAssertEqual(before.team,"팀 경기 있음");XCTAssertEqual(before.action,"행동 1/1")
            XCTAssertEqual(before.participation,role == .pitcher ? "비등판일":"타자 출전 예정")
            let stored=CalendarDayPresentation(role:role,fixture:fixture,saved:.completed(false),starter:true,selectionFailed:true,actionUsed:true,trainingPending:false)
            XCTAssertEqual(stored.team,"팀 경기 완료");XCTAssertEqual(stored.participation,"내 출전 없음");XCTAssertEqual(stored.entry,"경기 결과 보기")
            let failed=CalendarDayPresentation(role:role,fixture:fixture,saved:.none,starter:nil,selectionFailed:true,actionUsed:false,trainingPending:false)
            XCTAssertEqual(failed.participation,"기용 확인 필요")
            let absent=CalendarDayPresentation(role:role,fixture:nil,saved:.none,starter:false,selectionFailed:false,actionUsed:false,trainingPending:false)
            XCTAssertEqual(absent.team,"팀 경기 없음")
        }
        let first=SeasonFixture(number:1,date:date,homeID:"a",awayID:"b")
        let bench=CalendarDayPresentation(role:.pitcher,fixture:first,saved:.none,starter:false,selectionFailed:false,actionUsed:true,trainingPending:false)
        XCTAssertEqual(bench.participation,"오늘 벤치");XCTAssertEqual(bench.entry,"팀 경기 진행")
    }
    func testV53CoverageUsesExistingRawCountsBothRolesWithoutMutatingRecords() throws {
        for role in PlayerRole.allCases {
            let (memory,player,state,row)=try v53Fixture(role),c=memory.mainContext
            let original=row.payload,revision=state.revision,fatigue=player.fatigue
            let summary=try CareerSeasonStore.load(player:player,state:state,year:2026,in:c)
            let coverage=try XCTUnwrap(summary.coverage),game=try row.snapshot(),team=game.isHome ? game.playerRecords?.home:game.playerRecords?.away
            XCTAssertEqual(coverage.games,1);XCTAssertEqual(coverage.collectedGames,1);XCTAssertEqual(coverage.missingGames,0)
            if role == .batter {
                let counts=try XCTUnwrap(team?.batting.first {$0.id == player.id.uuidString}?.counts)
                XCTAssertEqual(coverage.batting,counts)
                for code in ["AVG","OBP","SLG","OPS"] {
                    let expected=MatchOpponentSeasonPlayer(id:"own",battingGames:1,pitchingGames:0,earnedRunGames:0,unscoredPitchingGames:0,batting:counts,pitching:MatchPitchingCounts())
                    XCTAssertEqual(coverage.value(code),expected.value(code))
                }
            } else {
                let counts=try XCTUnwrap(team?.pitching.first {$0.id == player.id.uuidString}?.counts)
                XCTAssertEqual(coverage.pitching,counts);XCTAssertEqual(coverage.earnedRunGames,1)
                let expected=MatchOpponentSeasonPlayer(id:"own",battingGames:0,pitchingGames:1,earnedRunGames:1,unscoredPitchingGames:0,batting:MatchBattingCounts(),pitching:counts)
                XCTAssertEqual(coverage.value("ERA"),expected.value("ERA"));XCTAssertEqual(coverage.value("ER"),expected.value("ER"))
            }
            XCTAssertEqual(coverage.value("WAR"),"미집계")
            XCTAssertEqual(row.payload,original);XCTAssertEqual(state.revision,revision);XCTAssertEqual(player.fatigue,fatigue);XCTAssertFalse(c.hasChanges)
        }
    }
    func testV53LegacyAndMixedCoverageCannotInventSeasonOPSOrERA() throws {
        for role in PlayerRole.allCases {
            let (memory,player,_,row)=try v53Fixture(role);_ = memory
            let game=try row.snapshot();var legacy=game;legacy.playerRecords=nil
            var coverage=PersonalSeasonCoverage();coverage.include(game,playerID:player.id);coverage.include(legacy,playerID:player.id)
            XCTAssertEqual(coverage.games,2);XCTAssertEqual(coverage.collectedGames,1);XCTAssertEqual(coverage.missingGames,1)
            for code in ["OPS","ER","ERA"] {XCTAssertEqual(coverage.value(code),"미집계")}
            XCTAssertEqual(coverage.value(role == .batter ? "OPS":"ERA",partial:true),{
                var collected=PersonalSeasonCoverage();collected.include(game,playerID:player.id);return collected.value(role == .batter ? "OPS":"ERA")
            }())
            var empty=PersonalSeasonCoverage();empty.include(legacy,playerID:player.id)
            XCTAssertEqual(empty.value("OPS",partial:true),"미집계");XCTAssertEqual(empty.value("ERA"),"미집계")
            XCTAssertNil(legacy.playerRecords)
        }
    }
    func testV53MixedEarnedCoverageDoesNotTurnUnknownERIntoZero() throws {
        let (memory,player,_,row)=try v53Fixture(.pitcher);_ = memory
        let game=try row.snapshot();var old=game
        if old.isHome {old.playerRecords?.home.pitching[0].counts.earnedRuns=nil} else {old.playerRecords?.away.pitching[0].counts.earnedRuns=nil}
        var coverage=PersonalSeasonCoverage();coverage.include(game,playerID:player.id);coverage.include(old,playerID:player.id)
        XCTAssertTrue(coverage.complete);XCTAssertEqual(coverage.earnedRunGames,1);XCTAssertEqual(coverage.unscoredPitchingGames,1)
        XCTAssertEqual(coverage.value("ER"),"미집계");XCTAssertEqual(coverage.value("ERA"),"미집계")
    }
    func testV53OffseasonMessagesNeverGraduateAdultProfessionalsAgain() throws {
        let date=try GameDate("2026-12-31"),next=try GameDate("2027-04-01")
        for age in [16,17,18,19,25,31,39] {
            let plan=OffseasonPlan(seasonYear:2026,date:date,target:next,age:age,targetAge:age+1)
            if age == 18 {XCTAssertTrue(plan.transitionNotice?.contains("고교 졸업") == true)}
            else if age == 19 {XCTAssertTrue(plan.transitionNotice?.contains("20세") == true)}
            else {XCTAssertNil(plan.transitionNotice)}
        }
        XCTAssertFalse(CalendarError.preparationRequired.localizedDescription.contains("다음 구현"))
    }
    func testV53FinalAllDrawRankMatchesSeasonAndOriginalLeagueRemainsUnchanged() throws {
        let ids=["a","b","c","d","e","f"],origin=try GameDate("2026-04-01"),today=try GameDate("2026-09-23")
        let fixtures=try SeasonSchedule.fixtures(year:2026,schoolIDs:ids)
        let league=try AnnualLeague.make(playerID:UUID(),schoolIDs:ids,origin:origin,startAge:16,today:today,year:2026,
            official:fixtures.map {LeagueOfficialResult(fixtureID:$0.id,homeScore:0,awayScore:0)})
        let summary=CareerSeasonSummary(league:league,totals:PersonalSeasonTotals())
        XCTAssertTrue(league.isComplete);XCTAssertEqual(summary.champions.count,6)
        XCTAssertEqual(league.displayStandings,summary.finalStandings);XCTAssertTrue(league.displayStandings.allSatisfy {$0.rank == 1})
        XCTAssertTrue(league.standings.allSatisfy {$0.rank == nil});XCTAssertTrue(league.displayStandings.allSatisfy {$0.percentage == "—"})
    }
    func testV53SourceLabelsDoNotClaimAutoTeamStatsAsPersonalEvidence() {
        XCTAssertEqual(LeagueRecordSource.label(automatic:true,ownTeam:false),"다른 팀 자동 경기")
        XCTAssertEqual(LeagueRecordSource.label(automatic:true,ownTeam:true),"내 팀 자동 결과")
        XCTAssertEqual(LeagueRecordSource.label(automatic:false,ownTeam:true),"내 팀 경기 원장")
    }
}

extension ManagementSeasonTests {
    func testV53OtherTeamLedgerNeverFillsPersonalSeasonCoverage() throws {
        for role in PlayerRole.allCases {
            let memory=try CareerStore.makeContainer(inMemory:true),c=memory.mainContext
            var draft=PlayerDraft();draft.role=role;draft.schoolID="hs-ref-001";draft.name="자동표본분리"
            let player=try CareerStore.create(draft,schools:SchoolCatalog.load(),in:c)
            let state=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
            player.gameDate="2026-04-01";try c.save();let fatigue=player.fatigue
            try AutomaticLeagueStore.completeDay(player:player,state:state,date:GameDate("2026-04-01"),in:c);try c.save()
            let count=try AutomaticLeagueStore.records(playerID:player.id,year:2026,in:c).count
            XCTAssertGreaterThan(count,0)
            try AutomaticLeagueStore.completeDay(player:player,state:state,date:GameDate("2026-04-01"),in:c);try c.save()
            XCTAssertEqual(try AutomaticLeagueStore.records(playerID:player.id,year:2026,in:c).count,count)
            player.gameDate="2026-04-02";try c.save()
            let season=try CareerSeasonStore.load(player:player,state:state,year:2026,in:c)
            XCTAssertEqual(season.totals.games,0);XCTAssertEqual(season.coverage?.games,0)
            XCTAssertEqual(season.coverage?.value("OPS"),"미집계");XCTAssertEqual(player.fatigue,fatigue)
            XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerMatchRecord>()),0);XCTAssertFalse(c.hasChanges)
        }
    }
    func testV53DamagedSavedMatchIsNotDisplayedAsUpcomingOrRepaired() throws {
        let (memory,player,_,row)=try v53Fixture(.batter);row.payload=Data([0xff]);try memory.mainContext.save()
        let original=row.payload,state=CalendarSavedMatch.read(row)
        XCTAssertEqual(state,.invalid);XCTAssertEqual(row.payload,original)
        let fixture=SeasonFixture(number:1,date:try GameDate(player.gameDate),homeID:"a",awayID:"b")
        let copy=CalendarDayPresentation(role:.batter,fixture:fixture,saved:state,starter:true,selectionFailed:false,actionUsed:true,trainingPending:false)
        XCTAssertEqual(copy.participation,"경기 기록 확인 필요")
        XCTAssertEqual(row.payload,original);XCTAssertFalse(memory.mainContext.hasChanges)
    }
    func testV53LegacyDetailGapCanReopenValidatedSeasonWithoutBackfill() throws {
        for role in PlayerRole.allCases {
            let (memory,player,state,row)=try v53Fixture(role),c=memory.mainContext
            var old=try row.snapshot();old.playerRecords=nil;old.pitchLog=nil;old.npcReadiness=nil
            row.payload=try JSONEncoder().encode(old);try c.save();let original=row.payload
            let season=try CareerSeasonStore.load(player:player,state:state,year:2026,in:c)
            XCTAssertEqual(season.coverage?.missingGames,1);XCTAssertEqual(season.totals.games,1)
            XCTAssertEqual(season.coverage?.value(role == .batter ? "OPS":"ERA"),"미집계")
            XCTAssertEqual(row.payload,original);XCTAssertFalse(c.hasChanges)
        }
    }
}
