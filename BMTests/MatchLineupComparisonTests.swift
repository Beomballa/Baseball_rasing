import XCTest
import SwiftUI
import UIKit
@testable import BM

@MainActor final class MatchLineupComparisonTests: XCTestCase {
    private func projection(_ match: CareerMatch) -> MatchLineupComparison {
        MatchLineupComparison(match: match, fixtureID: match.playerRecords?.fixtureID, careerName: "내 선수",
                              homeName: "서울북악고", awayName: "한강청운고")
    }
    private func walk() throws -> (CareerMatch, CareerMatch) {
        var match = try InplayIntegrationTests().seventhInning(role: .batter)
        let before = match
        match.balls = 3; match.strikes = 0; match.random = 2; match.settle()
        return (before, match)
    }

    func testNinthWalkChangesCurrentSlotAndKeepsExactlyNinePlaces() throws {
        let (before, after) = try walk()
        let a = projection(before), b = projection(after)
        XCTAssertEqual(a.home.entries[8].name, "최태현")
        XCTAssertEqual(a.away.entries[8].name, "안승현")
        XCTAssertEqual(a.home.status(slot: 9), "현재 타자"); XCTAssertEqual(a.home.status(slot: 1), "다음 타자")
        XCTAssertEqual(b.home.entries.count, 9); XCTAssertEqual(b.away.entries.count, 9)
        XCTAssertGreaterThan(after.playerRecords!.home.batting.count, 9)
        XCTAssertEqual(b.home.entries[8].name, "대주자")
        XCTAssertEqual(b.home.entries[8].note, "최태현 대신"); XCTAssertNil(b.home.entries[8].position)
        XCTAssertEqual(b.away.entries[8].name, "손상우"); XCTAssertEqual(b.away.entries[8].position, "구원 투수")
        XCTAssertEqual(b.home.status(slot: 1), "현재 타자"); XCTAssertEqual(b.home.status(slot: 2), "다음 타자")
        XCTAssertEqual(projection(before), a)
    }

    func testFutureChangesDoNotAppearAtEarlierDisplayBoundaryAndDoublePreservesSlot() throws {
        let (before, changed) = try walk()
        var oldBoundary = changed; oldBoundary.homeOrder = before.homeOrder; oldBoundary.awayOrder = before.awayOrder
        XCTAssertEqual(projection(oldBoundary).home.entries, projection(before).home.entries)
        XCTAssertEqual(projection(oldBoundary).away.entries, projection(before).away.entries)
        var after = changed
        let scenario = InplayIntegrationTests(), play = scenario.fieldPlay(after, distance: 90, flight: 5, direction: -25)
        scenario.plate("2루타", in: &after, play: play)
        let result = projection(after)
        XCTAssertEqual(result.home.status(slot: 2), "현재 타자")
        XCTAssertEqual(result.home.status(slot: 3), "다음 타자")
        XCTAssertEqual(result.home.entries[8], projection(changed).home.entries[8])
        XCTAssertEqual(result.away.entries[8], projection(changed).away.entries[8])
    }

    func testOffenseDefenseAndNineToOneAreIndependentOfPlayerRole() throws {
        for role in PlayerRole.allCases {
            var match = InplayIntegrationTests().makeMatch(role: role)
            match.homeOrder = 26; match.awayOrder = 8
            for half in 0..<18 {
                match.half = half
                let model = projection(match)
                let offense = half.isMultiple(of: 2) ? model.away : model.home
                let defense = half.isMultiple(of: 2) ? model.home : model.away
                XCTAssertEqual(offense.status(slot: 9), "현재 타자")
                XCTAssertEqual(offense.status(slot: 1), "다음 타자")
                XCTAssertEqual(defense.status(slot: 9), "다음 공격 선두")
                XCTAssertFalse((1...9).contains { defense.status(slot: $0) == "현재 타자" })
            }
            match.half = 18; match.completed = true
            let final = projection(match)
            XCTAssertEqual(final.context, "최종 타순")
            XCTAssertTrue((1...9).allSatisfy { final.home.status(slot: $0) == nil && final.away.status(slot: $0) == nil })
        }
    }

    func testMissingAndPartialDataDoNotUseTodaysOrDefaultLineup() throws {
        var match = InplayIntegrationTests().makeMatch()
        match.playerRecords?.home.batting.removeAll { $0.order == 4 }
        XCTAssertFalse(projection(match).home.entries[3].recorded)
        XCTAssertEqual(projection(match).home.entries[3].name, "선수 미기록")
        XCTAssertEqual(projection(match).home.entries.count, 9)
        match.playerRecords = nil
        let frozenLegacy = projection(match)
        XCTAssertTrue(frozenLegacy.available)
        XCTAssertFalse(frozenLegacy.home.entries[0].recorded, "내 선수의 ID를 잃었을 때 해당 NPC로 채우지 않는다.")
        match.battingOrder = nil
        let missing = projection(match)
        XCTAssertFalse(missing.available)
        XCTAssertTrue((1...9).allSatisfy { missing.home.status(slot: $0) == nil && missing.away.status(slot: $0) == nil })
    }

    func testOriginalIdentityMustMatchFrozenOrderAndFixture() throws {
        var match = InplayIntegrationTests().makeMatch()
        var order = match.battingOrder!.home; order.swapAt(1, 2)
        match.battingOrder = MatchBattingOrder(home: order, away: match.battingOrder!.away)
        XCTAssertFalse(projection(match).home.entries[1].recorded)
        XCTAssertFalse(projection(match).home.entries[2].recorded)
        let mismatch = MatchLineupComparison(match: match, fixtureID: "another-fixture", careerName: "내 선수", homeName: "홈", awayName: "원정")
        XCTAssertFalse(mismatch.available)
    }

    func testSavedNamesAndUnknownReplacementAreNotRegenerated() throws {
        var (_, match) = try walk()
        match.npcAttack?.away.relief.name = "저장된 구원 이름"
        XCTAssertEqual(projection(match).away.entries[8].name, "저장된 구원 이름")
        let original = try XCTUnwrap(match.runnerManagement?.changes.first)
        match.runnerManagement?.changes = [MatchRunnerChange(half: original.half, order: original.order, base: original.base,
            slot: original.slot, original: original.original, replacement: "unknown-player", position: original.position,
            responsiblePitcher: original.responsiblePitcher)]
        XCTAssertFalse(projection(match).home.entries[8].recorded)
    }

    func testReadAndRestoreNeverMutatePayloadOrRandom() throws {
        let (_, match) = try walk()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(match), restored = try JSONDecoder().decode(CareerMatch.self, from: before)
        for _ in 0..<20 { XCTAssertEqual(projection(restored), projection(match)) }
        XCTAssertEqual(try encoder.encode(restored), before)
        XCTAssertEqual(restored.random, match.random)
    }

    func testTwoColumnAndLargeTextHostedLayouts() throws {
        let (_, match) = try walk()
        for (size, viewport): (DynamicTypeSize, CGSize) in [(.large, CGSize(width: 390, height: 844)),
            (.large, CGSize(width: 320, height: 568)), (.accessibility5, CGSize(width: 320, height: 568))] {
            let model = projection(match)
            let view = NavigationStack {
                ScrollView { MatchLineupComparisonView(comparison: model).padding(16) }
                    .background(GameTheme.board).navigationTitle("경기 정보").navigationBarTitleDisplayMode(.inline)
            }.preferredColorScheme(.dark).environment(\.dynamicTypeSize, size).frame(width: viewport.width, height: viewport.height)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: viewport); window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible(); defer { window.isHidden = true; previous?.makeKey() }
            window.rootViewController?.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            var drawn = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            XCTAssertTrue(drawn); XCTAssertEqual(image.size, viewport)
            let attachment = XCTAttachment(image: image); attachment.name = "P04 C lineup \(Int(viewport.width)) \(size)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
