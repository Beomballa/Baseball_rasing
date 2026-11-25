import XCTest
import SwiftUI
import UIKit
@testable import BM

@MainActor final class MatchRunnerDetailsTests: XCTestCase {
    private func current(_ match: CareerMatch) -> MatchRunnerDetails? {
        .current(match, careerName: "내 선수", homeName: "서울북악고", awayName: "한강청운고")
    }
    private func resolved(_ play: MatchDetailedPlay, _ match: CareerMatch) -> MatchRunnerDetails? {
        .resolved(play, match: match, careerName: "내 선수", homeName: "서울북악고", awayName: "한강청운고")
    }
    private func double(role: PlayerRole = .batter) throws -> (CareerMatch, MatchDetailedPlay) {
        let scenario = InplayIntegrationTests()
        var match = try scenario.seventhInning(role: role)
        match.balls = 3; match.strikes = 0; match.random = role == .batter ? 2 : 1
        if role == .pitcher {
            try match.advance(.pitch, pitchCode: "four-seam", control: .init(release: 0, pitchTarget: .init(x: 0, y: 0)))
        } else { match.settle() }
        let play = scenario.fieldPlay(match, distance: 90, flight: 5, direction: -25)
        scenario.plate("2루타", in: &match, play: play)
        return (match, play)
    }

    func testCurrentAndResolvedKeepBaseOrderIdentityAndInheritedPitcherBothRoles() throws {
        for role in PlayerRole.allCases {
            let (match, play) = try double(role: role)
            let details = try XCTUnwrap(current(match))
            XCTAssertEqual(details.runners.map(\.base), [2, 3])
            XCTAssertEqual(details.inning, "7회 말"); XCTAssertEqual(details.team, "서울북악고")
            XCTAssertEqual(details.runners.map(\.slot), [1, 9])
            XCTAssertEqual(details.runners.last?.speed, 63)
            XCTAssertEqual(details.runners.last?.name, "대주자")
            XCTAssertEqual(details.runners.last?.origin, "최태현의 볼넷 출루 후 대주자 투입")
            XCTAssertEqual(details.runners.last?.pitcher, role == .batter ? "안승현" : "내 선수")
            XCTAssertEqual(details.runners.first?.pitcher, "손상우")
            if role == .batter {
                XCTAssertEqual(details.runners.first?.name, "내 선수")
                XCTAssertEqual(details.runners.first?.speed, 60)
            }
            XCTAssertEqual(details.runners.first?.origin, "2루타 출루")
            XCTAssertEqual(resolved(play, match), details)
        }
    }

    func testOldReplayUsesItsOwnAfterRunnersInsteadOfCurrentOtherTeamRunners() throws {
        var (match, play) = try double()
        let atEvent = try XCTUnwrap(resolved(play, match))
        var foreign = play; foreign.version += 1
        XCTAssertNil(resolved(foreign, match), "같은 half/order여도 이 경기의 타구가 아니면 상세를 붙이지 않는다.")
        let scenario = InplayIntegrationTests()
        scenario.plate("삼진", in: &match)
        XCTAssertEqual(match.half, 14)
        scenario.plate("볼넷", in: &match)
        XCTAssertEqual(current(match)?.runners.map(\.base), [1])
        XCTAssertEqual(current(match)?.team, "한강청운고")
        XCTAssertEqual(resolved(play, match), atEvent)
        match.playerRecords?.plateTrace = nil
        XCTAssertNil(resolved(play, match), "원장 대응이 없는 과거 장면에 현재 주자를 붙이지 않는다.")
    }

    func testRepeatedReachAndBrokenTraceNeverReuseOldOrigin() throws {
        var (match, _) = try double()
        let own = try XCTUnwrap(match.playerRecords?.careerID.uuidString)
        for _ in 0..<9 { InplayIntegrationTests().plate("볼넷", in: &match) }
        XCTAssertEqual(match.playerRecords?.runners.first, own)
        XCTAssertEqual(current(match)?.runners.first?.origin, "볼넷 출루")
        var (broken, _) = try double()
        broken.playerRecords?.plateTrace?.removeAll { $0.half == 13 && $0.order == 26 }
        XCTAssertEqual(current(broken)?.runners.last?.origin, "대주자 투입 · 이전 출루 경위 미기록")
        XCTAssertEqual(current(broken)?.runners.first?.origin, "2루타 출루")
    }

    func testLegacyMismatchEmptyBaseAndWrongPitcherTagDoNotInventDetails() throws {
        var (match, _) = try double()
        match.runnerProfiles?[1]?.responsiblePitcher = "home-starter"
        XCTAssertNil(current(match)?.runners.first?.pitcher)
        match.runnerProfiles?[1]?.id = "wrong-player"
        XCTAssertFalse(try XCTUnwrap(current(match)?.runners.first).identified)
        XCTAssertNil(current(match)?.runners.first?.speed)
        match.playerRecords = nil
        let legacy = try XCTUnwrap(current(match))
        XCTAssertEqual(legacy.runners.map(\.name), ["2루 주자", "3루 주자"])
        XCTAssertTrue(legacy.runners.allSatisfy { !$0.identified && $0.speed == nil && $0.origin == nil && $0.pitcher == nil })
        match.bases = [false, false, false]
        XCTAssertNil(current(match))
    }

    func testPitcherRunnerUsesSavedNameInsteadOfRegeneratingIt() throws {
        var match = InplayIntegrationTests().makeMatch()
        let id = try XCTUnwrap(match.playerRecords?.away.pitching.first?.id)
        match.npcAttack?.away.starter.name = "저장된 투수 이름"
        match.bases = [true, false, false]
        match.playerRecords?.runners = [id, nil, nil]
        match.runnerProfiles = [FieldRunnerProfile(speed: 42, responsiblePitcher: "home-starter", id: id), nil, nil]
        XCTAssertEqual(current(match)?.runners.first?.name, "저장된 투수 이름")
    }

    func testThirdOutAndUnknownEventDoNotShowNextInningDetails() throws {
        var (match, _) = try double()
        let scenario = InplayIntegrationTests()
        let out = scenario.fieldPlay(match, distance: 15, flight: 0.1, direction: 0)
        XCTAssertGreaterThan(out.outsAdded, 0)
        scenario.plate("범타", in: &match, play: out)
        XCTAssertEqual(match.half, 14)
        XCTAssertNil(resolved(out, match))
    }

    func testReadAndRestoreLeaveJSONAndRandomUntouched() throws {
        let (match, play) = try double()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(match)
        let restored = try JSONDecoder().decode(CareerMatch.self, from: before)
        for _ in 0..<20 {
            XCTAssertEqual(current(restored), current(match))
            XCTAssertEqual(resolved(play, restored), resolved(play, match))
        }
        XCTAssertEqual(try encoder.encode(restored), before)
    }

    func testInteractiveDiamondPreservesScoreboardPixelsAndUpdatesLockedState() throws {
        let (match, _) = try double()
        let plain = MatchBroadcastBoard(match: match, homeName: "홈", awayName: "원정", date: "2026-04-19", pulse: nil, pulseAt: .distantPast)
        var interactive = plain; interactive.onRunners = {}; interactive.runnersEnabled = true
        let a = ImageRenderer(content: plain.frame(width: 390)); let b = ImageRenderer(content: interactive.frame(width: 390))
        XCTAssertEqual(try XCTUnwrap(a.uiImage).pngData(), try XCTUnwrap(b.uiImage).pngData())
        var locked = interactive; locked.runnersEnabled = false
        XCTAssertNotEqual(interactive, locked)
    }

    func testSheetHostedAtSmallWidthAndLargestTextReadOnly() throws {
        let (match, _) = try double(); let details = try XCTUnwrap(current(match))
        for (size, viewport): (DynamicTypeSize, CGSize) in [(.large, CGSize(width: 390, height: 844)), (.large, CGSize(width: 320, height: 568)), (.accessibility5, CGSize(width: 320, height: 568))] {
            let view = NavigationStack {
                MatchRunnerDetailsView(details: details).navigationTitle("베이스 주자").navigationBarTitleDisplayMode(.inline)
            }.environment(\.dynamicTypeSize, size).preferredColorScheme(.dark).frame(width: viewport.width, height: viewport.height)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: viewport)
            let host = UIHostingController(rootView: view); window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            var drawn = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            XCTAssertTrue(drawn); XCTAssertEqual(image.size, viewport)
            let attachment = XCTAttachment(image: image); attachment.name = "P03 runners \(Int(viewport.width)) \(size)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(current(match), details)
    }
}
