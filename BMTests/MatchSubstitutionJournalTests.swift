import XCTest
import SwiftUI
import UIKit
@testable import BM

@MainActor final class MatchSubstitutionJournalTests: XCTestCase {
    private func journal(_ match: CareerMatch) -> MatchSubstitutionJournal {
        MatchSubstitutionJournal(match: match, careerName: "내 선수", homeName: "서울북악고", awayName: "한강청운고")
    }

    private func changedMatch(role: PlayerRole = .batter) throws -> CareerMatch {
        let scenario = InplayIntegrationTests()
        var match = try scenario.seventhInning(role: role)
        match.balls = 3; match.strikes = 0; match.random = role == .batter ? 2 : 1
        if role == .pitcher {
            try match.advance(.pitch, pitchCode: "four-seam", control: .init(release: 0, pitchTarget: .init(x: 0, y: 0)))
        } else { match.settle() }
        return match
    }

    func testSameBoundaryUsesRealRunnerAndPitcherIDsWithoutDuplicateLedgerEvents() throws {
        let match = try changedMatch()
        let result = journal(match)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.groups.map(\.half), [13, 13])
        XCTAssertEqual(result.groups.map(\.home), [true, false])
        let runner = try XCTUnwrap(result.groups.first?.entries.first)
        XCTAssertEqual(runner.kind, "대주자")
        XCTAssertEqual(runner.outgoing, "최태현 · 9번")
        XCTAssertEqual(runner.incoming, "대주자")
        XCTAssertEqual(runner.detail, "주력 57 → 63 (+6)")
        let pitcher = try XCTUnwrap(result.groups.last?.entries.first)
        XCTAssertEqual(pitcher.outgoing, "안승현 · 선발")
        XCTAssertEqual(pitcher.incoming, "손상우 · 구원")
        XCTAssertTrue(pitcher.detail?.contains("남긴 주자 1·2루") == true)
        XCTAssertEqual(match.playerRecords?.home.runnerChanges?.count, 1)
        // 원장에도 남은 대주자 사건을 다시 읽어 2건으로 세지 않는다.
        XCTAssertEqual(result.groups.flatMap(\.entries).filter { $0.kind == "대주자" }.count, 1)
    }

    func testOwnPitcherAndDefendingTeamStayFixedAfterInningChanges() throws {
        var match = try changedMatch(role: .pitcher)
        let initial = journal(match)
        let pitcher = try XCTUnwrap(initial.groups.last?.entries.first)
        XCTAssertEqual(pitcher.outgoing, "내 선수 · 선발")
        let scenario = InplayIntegrationTests()
        scenario.plate("삼진", in: &match)
        XCTAssertEqual(match.half, 14)
        XCTAssertEqual(journal(match), initial)
        XCTAssertEqual(initial.groups.last?.team, "한강청운고")
    }

    func testTopBottomAndExtraInningsUseEventHalfAndPitcherTeam() throws {
        var match = InplayIntegrationTests().makeMatch()
        let original = try XCTUnwrap(match.playerRecords?.away.batting.first { $0.position != "P" })
        let reserve = try XCTUnwrap(match.runnerManagement?.away)
        match.runnerManagement?.changes = [.init(half: 18, order: 40, base: 1, slot: original.order,
            original: original.id, replacement: reserve.id, position: original.position, responsiblePitcher: "home-starter")]
        match.pitching?.homeChange = PitcherChange(half: 18, outs: 2, order: 40, pitches: 94, fatigue: 0,
            reason: "투구 수 한도", inheritedBases: [1], outsAtExit: 0, runsAtExit: 0)
        match.pitching?.awayChange = PitcherChange(half: 19, outs: 0, order: 41, pitches: 94, fatigue: 0,
            reason: "투구 수 한도", inheritedBases: [], outsAtExit: 0, runsAtExit: 0)
        let result = journal(match)
        XCTAssertEqual(result.groups.map(\.inning), ["10회 초", "10회 초", "10회 말"])
        XCTAssertEqual(result.groups.map(\.home), [false, true, false])
        XCTAssertEqual(result.groups.map(\.team), ["한강청운고", "서울북악고", "한강청운고"])
        XCTAssertEqual(Set(result.groups.flatMap(\.entries).map(\.id)).count, 3)
    }

    func testLegacyAndMissingSnapshotsDoNotInventNamesOrAbilityValues() throws {
        var match = try changedMatch()
        match.npcFielders = nil; match.npcAttack = nil; match.playerRecords = nil
        let result = journal(match)
        XCTAssertNil(result.groups.first?.entries.first?.detail)
        XCTAssertEqual(result.groups.first?.entries.first?.incoming, "대주자")
        XCTAssertEqual(result.groups.last?.entries.first?.outgoing, "선발투수")
        XCTAssertEqual(result.groups.last?.entries.first?.incoming, "구원투수")
        match.runnerManagement = nil; match.pitching = nil
        XCTAssertEqual(journal(match).count, 0)
    }

    func testRepeatedReadingAndDiskStyleResumeDoNotChangeMatchJSONOrRandomState() throws {
        let match = try changedMatch()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(match)
        let restored = try JSONDecoder().decode(CareerMatch.self, from: before)
        let expected = journal(match)
        for _ in 0..<20 { XCTAssertEqual(journal(restored), expected) }
        XCTAssertEqual(try encoder.encode(restored), before)
        XCTAssertEqual(restored.random, match.random)
        XCTAssertEqual(restored.line, match.line)
    }

    func testJournalHostedAtSmallWidthAndLargestTextWithoutMutatingSnapshot() throws {
        let match = try changedMatch()
        let data = journal(match)
        let cases: [(DynamicTypeSize, CGSize)] = [(.large, CGSize(width: 320, height: 568)),
            (.large, CGSize(width: 390, height: 844)), (.accessibility5, CGSize(width: 320, height: 568))]
        for (size, viewport) in cases {
            let view = NavigationStack {
                MatchSubstitutionJournalView(journal: data).navigationTitle("교체 일지")
                    .navigationBarTitleDisplayMode(.inline)
            }.environment(\.dynamicTypeSize, size).transaction { $0.disablesAnimations = true }
                .preferredColorScheme(.dark)
                .frame(width: viewport.width, height: viewport.height)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: viewport)
            let host = UIHostingController(rootView: view)
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            var drawn = false
            let image = renderer.image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            XCTAssertTrue(drawn)
            XCTAssertEqual(image.size, viewport)
            let attachment = XCTAttachment(image: image)
            attachment.name = "P02 journal \(Int(viewport.width)) \(size)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(journal(match), data)
    }
}
