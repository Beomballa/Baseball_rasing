import XCTest
import SwiftUI
import UIKit
@testable import BM

@MainActor final class MatchGameHistoryTests: XCTestCase {
    private func history(_ match: CareerMatch, fixture: String? = "integration-205") -> MatchGameHistory {
        MatchGameHistory(match: match, fixtureID: fixture, careerName: "내 선수", homeName: "서울북악고", awayName: "한강청운고")
    }
    private func seventhDouble(role: PlayerRole = .batter) throws -> CareerMatch {
        let scenario = InplayIntegrationTests()
        var match = try scenario.seventhInning(role: role)
        match.balls = 3; match.strikes = 0; match.random = role == .batter ? 2 : 1
        if role == .batter { match.settle() }
        else { try match.advance(.pitch, pitchCode: "four-seam", control: .init(release: 0, pitchTarget: .init(x: 0, y: 0))) }
        let play = scenario.fieldPlay(match, distance: 90, flight: 5, direction: -25)
        scenario.plate("2루타", in: &match, play: play)
        try scenario.validate(match)
        return match
    }

    func testSeventhPairsEachTeamsOwnPlateSequenceAndKeepsBothChangesAfterWalk() throws {
        let match = try seventhDouble(), model = history(match)
        let seventh = try XCTUnwrap(model.innings.first { $0.number == 7 })
        XCTAssertFalse(model.partial); XCTAssertTrue(model.recorded)
        XCTAssertEqual(model.plateCount, match.playerRecords?.plateTrace?.count)
        XCTAssertEqual(seventh.home.entries.map(\.result), ["2루타", "삼진", "삼진", "볼넷", "2루타"])
        XCTAssertEqual(seventh.home.entries.map { $0.order % 9 + 1 }, [6, 7, 8, 9, 1])
        XCTAssertEqual(seventh.away.entries.count, 3)
        XCTAssertEqual(seventh.home.entries[3].changes.count, 2)
        XCTAssertEqual(Set(seventh.home.entries[3].changes.map(\.kind)), ["대주자", "투수 교체"])
        XCTAssertTrue(seventh.home.entries[4].changes.isEmpty)
        XCTAssertEqual(model.changeCount, 2, "교체를 타석 수에 더하지 않는다.")
        XCTAssertTrue(seventh.home.unpairedChanges.isEmpty)
    }

    func testDoubleReadsItsOwnBeforeAfterScoreAndScorerWithoutRecalculatingPitcherRuns() throws {
        for role in PlayerRole.allCases {
            var match = try seventhDouble(role: role)
            let entry = try XCTUnwrap(history(match).innings.last?.home.entries.last)
            XCTAssertEqual(entry.before, "2사 · 1·2루"); XCTAssertEqual(entry.after, "2사 · 2·3루")
            XCTAssertEqual(entry.scoreBefore, "홈 2 : 2 원정"); XCTAssertEqual(entry.scoreAfter, "홈 3 : 2 원정")
            XCTAssertEqual(entry.runs, 1); XCTAssertEqual(entry.scorers, "조태윤 홈인")
            XCTAssertEqual(entry.pitcher, "손상우")
            let runs = match.playerRecords?.away.pitching.map(\.counts.runsAllowed)
            try match.advance(.automatic)
            let archived = try XCTUnwrap(history(match).innings.first { $0.number == 7 }?.home.entries.first { $0.id == entry.id })
            XCTAssertEqual(archived, entry, "최종 점수나 다음 이닝의 점유를 과거 타석에 붙이지 않는다.")
            XCTAssertEqual(runs?.last, 0)
        }
    }

    func testThirdOutShowsInningChangeInsteadOfNextTeamsEmptyBases() throws {
        var match = InplayIntegrationTests().makeMatch()
        for _ in 0..<3 { InplayIntegrationTests().plate("삼진", in: &match) }
        let model = history(match), entry = try XCTUnwrap(model.innings.first?.away.entries.last)
        XCTAssertEqual(entry.before, "2사 · 주자 없음"); XCTAssertEqual(entry.after, "공수교대")
        XCTAssertEqual(model.innings.first?.home.entries.count, 0)
        XCTAssertEqual(model.innings.first?.home.emptyMessage, "아직 끝난 타석이 없습니다.")
    }

    func testOldBoundaryDoesNotExposeFutureDoubleOrItsScore() throws {
        var match = try seventhDouble()
        match.homeOrder = 27; match.homeScore = 2
        let model = history(match), seventh = try XCTUnwrap(model.innings.last)
        XCTAssertEqual(seventh.home.entries.count, 4)
        XCTAssertTrue(seventh.home.entries.allSatisfy { $0.runs == 0 })
        XCTAssertEqual(seventh.home.entries.last?.result, "볼넷")
        XCTAssertEqual(seventh.home.entries.last?.changes.count, 2)
        XCTAssertTrue(model.partial)
    }

    func testMissingAndPartialHistoryNeverInventsZerosOrReplacesAnotherFixturesRecords() throws {
        var match = try seventhDouble()
        match.playerRecords?.plateTrace = nil
        let legacy = history(match)
        XCTAssertFalse(legacy.recorded); XCTAssertEqual(legacy.plateCount, 0)
        XCTAssertEqual(legacy.changeCount, 2)
        XCTAssertEqual(legacy.innings.last?.home.unpairedChanges.count, 2)
        XCTAssertEqual(legacy.innings.last?.home.emptyMessage, "기록 미확인")
        let foreign = history(match, fixture: "another-match")
        XCTAssertTrue(foreign.mismatch); XCTAssertEqual(foreign.plateCount, 0); XCTAssertEqual(foreign.changeCount, 0)
        var foreignTeam = match
        let team = try XCTUnwrap(match.playerRecords?.home)
        foreignTeam.playerRecords?.home = MatchTeamRecords(teamID: "foreign-team", lineup: team.lineup,
                                                          batting: team.batting, pitching: team.pitching)
        XCTAssertTrue(history(foreignTeam).mismatch)
        XCTAssertEqual(history(foreignTeam).changeCount, 0)
        match.runnerManagement = nil; match.pitching = nil
        XCTAssertEqual(history(match).changeCount, 0)
    }

    func testDuplicateTraceIsNotCountedTwiceAndMissingNamesRemainExplicit() throws {
        var match = try seventhDouble()
        let event = try XCTUnwrap(match.playerRecords?.plateTrace?.last)
        match.playerRecords?.plateTrace?.append(event)
        let duplicate = history(match)
        XCTAssertTrue(duplicate.partial)
        XCTAssertFalse(duplicate.innings.flatMap { $0.home.entries + $0.away.entries }.contains { $0.id == event.id })
        match.playerRecords?.plateTrace?.removeLast()
        match.playerRecords?.home.batting.removeAll { $0.id == event.batter || $0.id == event.scoring.first?.id }
        let missing = try XCTUnwrap(history(match).innings.last?.home.entries.last)
        XCTAssertEqual(missing.batter, "타자 이름 미기록")
        XCTAssertEqual(missing.scorers, "득점 주자 이름 미기록")
        XCTAssertEqual(missing.runs, 1)
    }

    func testReadRestoreAndDifferentFixturesKeepStableScopedIdentityWithoutWrites() throws {
        let match = try seventhDouble()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(match), restored = try JSONDecoder().decode(CareerMatch.self, from: data)
        let model = history(match)
        for _ in 0..<10 { XCTAssertEqual(history(restored), model) }
        XCTAssertEqual(try encoder.encode(restored), data); XCTAssertEqual(restored.random, match.random)
        let other = InplayIntegrationTests().makeMatch(fixtureID: "other-fixture")
        XCTAssertNotEqual(model.id, history(other, fixture: "other-fixture").id)
        XCTAssertEqual(history(other, fixture: "other-fixture").plateCount, 0)
    }

    func testMissingMiddlePlateKeepsItsPlaceAndUnknownStartDoesNotGuessOrdinal() throws {
        var match = try seventhDouble()
        let home = try XCTUnwrap(history(match).innings.last?.home)
        XCTAssertEqual(home.entries.map(\.ordinal), [1, 2, 3, 4, 5])
        let missingID = home.entries[1].id
        match.playerRecords?.plateTrace?.removeAll { $0.id == missingID }
        let partial = try XCTUnwrap(history(match).innings.last?.home)
        XCTAssertEqual(partial.rowCount, 5); XCTAssertNil(partial.entry(at: 2))
        XCTAssertEqual(partial.entry(at: 3)?.result, "삼진")
        XCTAssertEqual(partial.absence(at: 2), "기록 미확인")
        match.playerRecords?.plateTrace?.removeAll { $0.half != 13 }
        let unknown = try XCTUnwrap(history(match).innings.last?.home)
        XCTAssertEqual(unknown.rowCount, 0)
        XCTAssertEqual(unknown.unordered.count, 4)
        XCTAssertTrue(unknown.entries.allSatisfy { $0.ordinal == nil })
    }

    func testLongHalfKeepsTenAndLaterOrdinalsSeparateFromBattingSlots() throws {
        var match = InplayIntegrationTests().makeMatch()
        let scenario = InplayIntegrationTests()
        for _ in 0..<10 { scenario.plate("볼넷", in: &match) }
        for _ in 0..<3 { scenario.plate("삼진", in: &match) }
        let first = try XCTUnwrap(history(match).innings.first)
        XCTAssertEqual(first.away.entries.map(\.ordinal), Array(1...13).map(Optional.some))
        XCTAssertEqual(first.rowCount, 13)
        XCTAssertEqual(first.away.entries[9].order % 9 + 1, 1)
        XCTAssertEqual(first.away.emptyMessage, "초 공격 종료")
        XCTAssertEqual(first.home.emptyMessage, "아직 끝난 타석이 없습니다.")
    }

    func testNewInningWithoutCompletedPlateKeepsLatestRecordedInningAsDefault() throws {
        var match = InplayIntegrationTests().makeMatch()
        let scenario = InplayIntegrationTests()
        for _ in 0..<6 { scenario.plate("삼진", in: &match) }
        XCTAssertEqual(match.half, 2)
        let before = history(match)
        XCTAssertEqual(before.innings.map(\.number), [1])
        XCTAssertEqual(before.innings.last?.number, 1, "빈 2회 대신 확정 타석이 있는 최신 이닝부터 연다.")
        scenario.plate("삼진", in: &match)
        XCTAssertEqual(history(match).innings.map(\.number), [1, 2])
        XCTAssertEqual(history(match).innings.last?.away.entries.count, 1)
    }

    func testUnplayedNinthBottomNeedsRecordedInningEvidence() throws {
        var match = InplayIntegrationTests().makeMatch()
        let scenario = InplayIntegrationTests()
        while !match.completed {
            if match.half == 1 { for _ in 0..<5 { scenario.plate("볼넷", in: &match) } }
            for _ in 0..<3 where !match.completed { scenario.plate("삼진", in: &match) }
        }
        try scenario.validate(match)
        XCTAssertEqual(match.half, 17); XCTAssertNil(match.inningScores?.home[8])
        XCTAssertEqual(history(match).innings.last?.home.emptyMessage, "말 공격 생략")
        match.inningScores = nil
        XCTAssertEqual(history(match).innings.last?.home.emptyMessage, "기록 미확인", "생략 근거가 없으면 생략으로 단정하지 않는다.")
    }

    func testLineupStyleHostedLayouts() throws {
        let model = history(try seventhDouble())
        for (size, viewport): (DynamicTypeSize, CGSize) in [(.large, CGSize(width: 390, height: 844)),
            (.large, CGSize(width: 320, height: 568)), (.accessibility5, CGSize(width: 320, height: 568))] {
            let view = NavigationStack { MatchGameHistoryView(history: model) }
                .environment(\.dynamicTypeSize, size).frame(width: viewport.width, height: viewport.height)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: viewport); window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible(); defer { window.isHidden = true; previous?.makeKey() }
            window.rootViewController?.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            var drawn = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            XCTAssertTrue(drawn); XCTAssertEqual(image.size, viewport)
            let attachment = XCTAttachment(image: image); attachment.name = "P04 history C \(Int(viewport.width)) \(size)"
            attachment.lifetime = .keepAlways; add(attachment)
            func scrollView(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
            }
            let scroll = try XCTUnwrap(scrollView(in: window.rootViewController!.view))
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            window.rootViewController?.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let bottom = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let lower = XCTAttachment(image: bottom); lower.name = "P04 history C \(Int(viewport.width)) \(size) bottom"
            lower.lifetime = .keepAlways; add(lower)
        }
    }
}
