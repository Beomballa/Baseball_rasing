import XCTest
import UIKit
@testable import BM

final class ClubIdentityTests: XCTestCase {
    @MainActor func testV197OnlyTopTenPercentReceivesPremiumSalaryPresentation() {
        for (position, isPremium) in [(1, true), (10, true), (11, false), (70, false), (100, false)] {
            let standing = LeagueSalaryStanding(version: 1, competition: "domestic-first-team",
                year: 2039, teamCount: 10, sampleCount: 101, rank: position)
            let rank = TransferContractDocument.SalaryRank(standing)
            XCTAssertEqual(rank.isPremium, isPremium)
            XCTAssertEqual(rank.title, "리그 연봉지수 상위 \(position)%")
            XCTAssertEqual(rank.comparison, standing.comparison)
            XCTAssertEqual(rank.presentationIdentifier, isPremium ? "SalaryRankPremium" : "SalaryRankNeutral")
        }
    }

    func testV196KBOOfferSalaryStandingUsesEffectiveSeasonRosterAndSharedRanks() throws {
        let league = "domestic-first-team"
        let expanded = try XCTUnwrap(LeagueSalaryStanding.benchmark(competition: league, year: 2039, expanded: true))
        let legacy = try XCTUnwrap(LeagueSalaryStanding.benchmark(competition: league, year: 2039, expanded: false))
        XCTAssertEqual(expanded.teamCount, 10)
        XCTAssertEqual(expanded.indices.count, 100)
        XCTAssertEqual(legacy.indices.count, 60)
        XCTAssertNil(LeagueSalaryStanding.benchmark(competition: "npb-first-team", year: 2039, expanded: true))
        XCTAssertEqual(expanded.indices, LeagueSalaryStanding.benchmark(competition: league, year: 2039, expanded: true)?.indices)
        XCTAssertNotEqual(expanded.indices, LeagueSalaryStanding.benchmark(competition: league, year: 2040, expanded: true)?.indices)

        let maximum = try XCTUnwrap(expanded.indices.max())
        let tied = try XCTUnwrap(expanded.standing(economicIndex: maximum))
        XCTAssertEqual(tied.sampleCount, 101)
        XCTAssertEqual(tied.rank, 1)
        XCTAssertEqual(tied.topPercent, 1)
        let minimum = try XCTUnwrap(expanded.indices.min())
        XCTAssertEqual(expanded.standing(economicIndex: minimum - 1)?.topPercent, 100)
        XCTAssertEqual(tied, try JSONDecoder().decode(LeagueSalaryStanding.self, from: JSONEncoder().encode(tied)))
    }

    @MainActor func testHomeVenueUsesParentArtworkForDevelopmentTeams() throws {
        let pairs = CareerTeamDirectory.expandedDomesticIDs.map { ($0, "pro-" + $0.dropFirst("dev-".count)) }
            + CareerTeamDirectory.americanDevelopmentIDs.map { ($0, "us-pro-" + $0.dropFirst("us-dev-".count)) }
        for (developmentID, parentID) in pairs {
            let parent = try XCTUnwrap(StadiumIdentity(homeTeamID: parentID).backdrop, parentID)
            let home = try XCTUnwrap(ManagementHomeVenueArt.backdrop(for: StadiumIdentity(homeTeamID: developmentID)), developmentID)
            XCTAssertEqual(home.imageName, parent.imageName, developmentID)
            XCTAssertEqual(home.name, parent.name, developmentID)
        }
        XCTAssertNil(ManagementHomeVenueArt.backdrop(for: StadiumIdentity(homeTeamID: "college-0")))
        XCTAssertNil(ManagementHomeVenueArt.backdrop(for: StadiumIdentity(homeTeamID: "dev-unknown")))
    }

    func testFortyIdentitiesKeepLegacyRostersAndMatchExpandedProLeagues() {
        XCTAssertEqual(ClubIdentity.all.count, 40)
        XCTAssertEqual(Set(ClubIdentity.all.map(\.name)).count, 40)
        XCTAssertEqual(Set(ClubIdentity.all.map(\.asset)).count, 40)
        for league in ClubIdentity.League.allCases {
            let clubs = ClubIdentity.all.filter { $0.league == league }
            XCTAssertEqual(clubs.count, league == .kbo ? 10:15)
            XCTAssertEqual(clubs.filter(\.participates).count, clubs.count)
        }
        for (level, count) in [("domestic-first-team",10),("npb-first-team",15),("mlb-first-team",15)] {
            let ids = CareerTeamDirectory.teams(level: level, expanded: true)
            XCTAssertEqual(ids.count, count)
            XCTAssertTrue(ids.allSatisfy { ClubIdentity.resolve(name: CareerTeamDirectory.name($0))?.participates == true })
            for id in ids {
                XCTAssertEqual(ClubIdentity.resolve(teamID: id), ClubIdentity.resolve(name: CareerTeamDirectory.name(id)))
            }
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
        XCTAssertTrue(ClubIdentity.resolve(name: "수원 기어즈")!.participates)
        XCTAssertEqual(ClubIdentity.resolve(teamID: "dev-harbors"), ClubIdentity.resolve(id: "kbo-0"))
        XCTAssertEqual(ClubIdentity.resolve(teamID: "us-dev-2"), ClubIdentity.resolve(id: "mlb-2"))
        XCTAssertNil(ClubIdentity.resolve(teamID: "college-0"))
    }
    @MainActor func testEveryIdentityHasItsOwnBundledTransparentAsset() throws {
        for club in ClubIdentity.all {
            let image = try XCTUnwrap(UIImage(named: club.asset), club.asset)
            XCTAssertEqual(image.size, CGSize(width: 384, height: 384))
            XCTAssertNotNil(image.cgImage)
        }
    }
    @MainActor func testV162AllFortyProSeasonTeamsResolveHomeVenueAndBothUniforms() throws {
        for (level, league) in [("domestic-first-team",ClubIdentity.League.kbo),("npb-first-team",.npb),("mlb-first-team",.mlb)] {
            for (index, team) in CareerTeamDirectory.teams(level: level, expanded: true).enumerated() {
                let id = league.id+"-\(index)"
                XCTAssertEqual(StadiumIdentity(homeTeamID: team).pro?.club.id, id)
                XCTAssertNotNil(StadiumIdentity(homeTeamID: team).backdrop)
                XCTAssertEqual(GameUniformStyles.find(team)?.id, id+":home")
                XCTAssertEqual(GameUniformStyles.find(team, away: true)?.id, id+":away")
            }
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
