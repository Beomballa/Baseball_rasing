import XCTest
import SwiftUI
import UIKit
@testable import BM

@MainActor final class MatchPlayerReportTests: XCTestCase {
    private func report(_ match: CareerMatch) -> MatchPlayerReportData {
        MatchPlayerReportData(summary: MatchResultSummary(match: match, fatigueBefore: 0, fatigueAfter: 37))
    }
    private func awardedMatch() -> CareerMatch {
        var match = InplayIntegrationTests().makeMatch(role: .pitcher)
        match.completed = true
        match.line.pitchingOuts = 15; match.line.pitchingStrikeouts = 2
        match.line.runsAllowed = 5; match.line.pitches = 95
        let awards = zip([TrainingKind.control, .stuff, .stamina, .mental], [2.8684, 2.3011, 1.5139, 1.8166]).map {
            MatchAbilityAward(kind: $0.0, rawXP: $0.1, before: 60, after: 60.1)
        }
        match.abilityExperience = MatchAbilityExperience(year: 2026, age: 16, fatigue: 0, before: [:], annualBefore: 0,
            result: MatchAbilityGrowth(rawXP: 8.5, participation: 0.8, quality: 0.5, awards: awards))
        return match
    }
    func testPitcherFeaturedMetricsAndAwardedXPAgreeWithStoredResult() {
        let model = report(awardedMatch())
        XCTAssertEqual(model.primary.map(\.value), ["5.0", "2"])
        XCTAssertEqual(model.secondary.map(\.value), ["5", "95"])
        XCTAssertEqual(model.growth?.rawXP, 8.5)
        XCTAssertEqual(model.rows.reduce(0) { $0 + $1.share }, 1, accuracy: 0.000001)
        XCTAssertEqual(model.rows.first!.share, 2.8684 / 8.5, accuracy: 0.000001)
        XCTAssertNotEqual(model.rows.first!.share, model.rows.first!.award.gain, "XP 비중은 능력 증가량이나 다음 레벨 진행률이 아니다.")
        XCTAssertEqual(model.summary.fatigueBefore, 0); XCTAssertEqual(model.summary.fatigueAfter, 37)
    }
    func testBatterMetricsAndNoAppearanceDoNotFabricatePersonalStats() {
        var match = InplayIntegrationTests().makeMatch()
        match.line.atBats = 5; match.line.hits = 1
        XCTAssertEqual(report(match).primary.map(\.value), ["5", "1"])
        XCTAssertEqual(report(match).secondary.map(\.id), ["homeRuns", "rbi"])
        let absent = CareerMatch(random: 1, isHome: true, role: "batter", appearance: false,
            contact: 60, power: 60, discipline: 60, mastery: [:])
        let model = report(absent)
        XCTAssertTrue(model.primary.isEmpty); XCTAssertTrue(model.secondary.isEmpty); XCTAssertTrue(model.other.isEmpty)
        XCTAssertNil(model.growth); XCTAssertTrue(model.rows.isEmpty)
    }
    func testLegacyAndZeroAwardsRemainDistinctAndProjectionDoesNotWritePayload() throws {
        var match = awardedMatch()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(match)
        for _ in 0..<10 { _ = report(match) }
        XCTAssertEqual(try encoder.encode(match), original)
        match.abilityExperience?.result = MatchAbilityGrowth(rawXP: 0, participation: 0, quality: 0, awards: [])
        XCTAssertEqual(report(match).growth?.rawXP, 0); XCTAssertTrue(report(match).rows.isEmpty)
        match.abilityExperience = nil
        XCTAssertNil(report(match).growth)
    }
    private func honoredMatch() -> CareerMatch {
        var match = InplayIntegrationTests().makeMatch()
        let analysis = MatchOppositionAnalysis.make(roster: match.npcFielders!, isHome: match.isHome, attack: match.npcAttack)
        let id = match.playerRecords!.away.lineup[0]
        var batting = MatchBattingCounts(); batting.plateAppearances = 20; batting.atBats = 20; batting.singles = 8
        let row = MatchOpponentSeasonPlayer(id: id, battingGames: 5, pitchingGames: 0, earnedRunGames: 0,
            unscoredPitchingGames: 0, batting: batting, pitching: MatchPitchingCounts())
        var season = MatchOpponentSeason(version: 1, year: 2026, competition: analysis.attack!.competition,
            teamID: analysis.teamID, through: "2026-06-07", uncollectedGames: 0, players: [row])
        season.honors = [LeagueHonor(playerID: id, teamID: analysis.teamID, kind: .average, value: 0.4, tied: true, final: false)]
        match.preparation = MatchPreparation(version: 1, fixtureID: "integration-205", choice: .contact, analysis: analysis, season: season)
        return match
    }
    private func lineup(_ match: CareerMatch, date: String? = "2026-06-08") -> MatchLineupComparison {
        MatchLineupComparison(match: match, fixtureID: "integration-205", careerName: "내 선수",
            homeName: "서울북악고", awayName: "한강청운고", gameDate: date)
    }
    func testHonorsRequireSamePlayerTeamDateAndFrozenValues() throws {
        let match = honoredMatch()
        try match.preparation!.season!.validate(analysis: match.preparation!.analysis, date: GameDate("2026-06-08"))
        XCTAssertEqual(lineup(match).away.entries[0].honors.first?.label, "공동 타율 선두")
        XCTAssertTrue(lineup(match).home.entries.allSatisfy { $0.honors.isEmpty })
        XCTAssertTrue(lineup(match, date: nil).away.entries.allSatisfy { $0.honors.isEmpty })
        XCTAssertTrue(lineup(match, date: "2026-06-09").away.entries.allSatisfy { $0.honors.isEmpty })
        var changed = match
        changed.preparation?.season?.honors = [LeagueHonor(playerID: match.playerRecords!.home.lineup[0],
            teamID: match.playerRecords!.away.teamID, kind: .average, value: 0.4, tied: false, final: true)]
        XCTAssertTrue(lineup(changed).away.entries.allSatisfy { $0.honors.isEmpty })
        changed = match
        changed.preparation = MatchPreparation(version: 1, fixtureID: "other-fixture", choice: .contact,
            analysis: match.preparation!.analysis, season: match.preparation!.season)
        XCTAssertTrue(lineup(changed).away.entries.allSatisfy { $0.honors.isEmpty })
        XCTAssertEqual(LeagueHonor.Kind.allCases.count, 5, "득점왕은 별도 정책 확정 전 추가하지 않는다.")
    }
    func testReliefDoesNotInheritOutgoingPitchersFrozenWinHonor() throws {
        var match = try InplayIntegrationTests().seventhInning(role: .batter)
        let analysis = MatchOppositionAnalysis.make(roster: match.npcFielders!, isHome: match.isHome, attack: match.npcAttack)
        let starter = analysis.attack!.starter.id
        let row = MatchOpponentSeasonPlayer(id: starter, battingGames: 0, pitchingGames: 5, earnedRunGames: 5,
            unscoredPitchingGames: 0, batting: MatchBattingCounts(), pitching: MatchPitchingCounts(), wins: 1)
        var season = MatchOpponentSeason(version: 1, year: 2026, competition: analysis.attack!.competition,
            teamID: analysis.teamID, through: "2026-06-07", uncollectedGames: 0, players: [row])
        season.honors = [LeagueHonor(playerID: starter, teamID: analysis.teamID, kind: .wins, value: 1, tied: false, final: false)]
        match.preparation = MatchPreparation(version: 1, fixtureID: "integration-205", choice: .contact, analysis: analysis, season: season)
        XCTAssertEqual(lineup(match).away.entries.flatMap(\.honors).count, 1)
        match.balls = 3; match.strikes = 0; match.random = 2; match.settle()
        XCTAssertNotNil(match.pitching?.awayChange)
        XCTAssertTrue(lineup(match).away.entries.flatMap(\.honors).isEmpty)
    }
    func testSharedNativeReportAndRecordsLayoutsAtSmallAndLargeType() throws {
        for (size, viewport): (DynamicTypeSize, CGSize) in [(.large, CGSize(width: 390, height: 844)),
            (.large, CGSize(width: 320, height: 568)), (.accessibility5, CGSize(width: 320, height: 568))] {
            for records in [false, true] {
                let view = NavigationStack {
                    Group {
                        if records {
                            VStack(spacing: 0) {
                                MatchRecordTabs(selection: .constant(.lineup)).padding(16)
                                ScrollView {
                                    MatchLineupComparisonView(comparison: lineup(honoredMatch()), schools: SchoolCatalog.bundled).padding(16)
                                }
                            }
                        } else {
                            ScrollView {
                                MatchPlayerReport(data: report(awardedMatch()), name: "내 투수", number: 10, ownTeam: "서울북악고", opponent: "한강청운고") {
                                    DetailGamePortrait(role: .pitcher, appearance: PlayerAppearance(), number: 10, hand: "right", label: "내 선수")
                                }.padding(16)
                            }
                        }
                    }.background(GameTheme.board).navigationTitle(records ? "경기 정보" : "경기 결과").navigationBarTitleDisplayMode(.inline)
                }.preferredColorScheme(.dark).environment(\.dynamicTypeSize, size)
                    .frame(width: viewport.width, height: viewport.height)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: viewport); window.rootViewController = UIHostingController(rootView: view)
                window.makeKeyAndVisible(); defer { window.isHidden = true; previous?.makeKey() }
                window.rootViewController?.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                var drawn = false
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                XCTAssertTrue(drawn); XCTAssertEqual(image.size, viewport)
                let attachment = XCTAttachment(image: image); attachment.name = "P04 bundle \(records ? "records" : "report") \(Int(viewport.width)) \(size)"
                attachment.lifetime = .keepAlways; add(attachment)
                if !records {
                    func scrolls(_ view: UIView) -> [UIScrollView] {
                        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
                    }
                    if let scroll = scrolls(window).max(by: { $0.contentSize.height < $1.contentSize.height }) {
                        scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                        let bottom = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                        }
                        let capture = XCTAttachment(image: bottom); capture.name = "P04 bundle report bottom \(Int(viewport.width)) \(size)"
                        capture.lifetime = .keepAlways; add(capture)
                    }
                }
            }
        }
    }
}
