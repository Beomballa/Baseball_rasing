import XCTest
import UIKit
@testable import BM

final class ClubIdentityTests: XCTestCase {
    func testThirtyIdentitiesDoNotExpandSixTeamEngineRosters() {
        XCTAssertEqual(ClubIdentity.all.count, 30)
        XCTAssertEqual(Set(ClubIdentity.all.map(\.name)).count, 30)
        XCTAssertEqual(Set(ClubIdentity.all.map(\.asset)).count, 30)
        for league in ClubIdentity.League.allCases {
            let clubs = ClubIdentity.all.filter { $0.league == league }
            XCTAssertEqual(clubs.count, 10)
            XCTAssertEqual(clubs.filter(\.participates).count, 6)
        }
        for level in ["domestic-first-team", "npb-first-team", "mlb-first-team", "mlb-development"] {
            let ids = CareerTeamDirectory.teams(level: level)
            XCTAssertEqual(ids.count, 6)
            for id in ids { XCTAssertEqual(ClubIdentity.resolve(name: CareerTeamDirectory.name(id))?.participates, true) }
        }
        for role in [PlayerRole.batter, .pitcher] {
            for row in ScoutingClubCatalog.roles(for: role) {
                XCTAssertEqual(ClubIdentity.resolve(name: row.name)?.participates, true)
            }
        }
    }
    func testLegacyNamesResolveWithoutRewritingSavedNamesOrInventingUnknownIdentity() {
        let saved = ["인천 하버스", "인천 하버스 육성", "인천 하버스 1군"]
        XCTAssertEqual(Set(saved.compactMap { ClubIdentity.resolve(name: $0)?.id }), ["kbo-0"])
        XCTAssertEqual(saved, ["인천 하버스", "인천 하버스 육성", "인천 하버스 1군"])
        XCTAssertNil(ClubIdentity.resolve(name: "해솔대"))
        XCTAssertNil(ClubIdentity.resolve(name: "기존 사용자 구단"))
        XCTAssertNil(ClubIdentity.resolve(name: "인천 하버스 다른 구단"))
        XCTAssertFalse(ClubIdentity.resolve(name: "수원 기어즈")!.participates)
    }
    @MainActor func testEveryIdentityHasItsOwnBundledTransparentAsset() throws {
        for club in ClubIdentity.all {
            let image = try XCTUnwrap(UIImage(named: club.asset), club.asset)
            XCTAssertEqual(image.size, CGSize(width: 384, height: 384))
            XCTAssertNotNil(image.cgImage)
        }
    }
    func testSeasonDisplayDoesNotInventRankChampionOrOtherLeagueResults() {
        let id = CareerTeamDirectory.teams(level: "domestic-first-team")[0]
        let empty = AnnualLeague(year: 2026, fixtures: [], results: [], standings: [LeagueStanding(id:id)], pendingIDs: [])
        XCTAssertTrue(ClubSeasonDisplay.summary(name:"인천 하버스",league:empty).contains("순위 대기"))
        XCTAssertTrue(ClubSeasonDisplay.summary(name:"인천 하버스",league:empty).contains("우승팀 미정"))
        let playing = AnnualLeague(year:2026,fixtures:[],results:[],standings:[LeagueStanding(id:id,wins:3,losses:1,draws:0,rank:1)],pendingIDs:[])
        let text = ClubSeasonDisplay.summary(name:"인천 하버스",league:playing)
        XCTAssertTrue(text.contains("1위"));XCTAssertTrue(text.contains("3승 1패"))
        XCTAssertTrue(text.contains("현재 선두"));XCTAssertTrue(text.contains("우승 미확정"))
        XCTAssertTrue(ClubSeasonDisplay.summary(name:"동도 스카이스",league:playing).contains("미집계"))
        XCTAssertTrue(ClubSeasonDisplay.summary(name:"수원 기어즈",league:playing).contains("미집계"))
        XCTAssertTrue(ClubSeasonDisplay.summary(name:"인천 하버스",league:nil).contains("미집계"))
    }

}
