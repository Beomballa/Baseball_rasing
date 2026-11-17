import XCTest
import SwiftData
@testable import BM

@MainActor final class DomesticExpansionTests: XCTestCase {
    private func observation(date: String = "2030-04-01", role: PlayerRole = .batter) throws -> (ModelContainer, CareerPlayer, CareerCalendarState, ScoutingObservation) {
        let db = try CareerStore.makeContainer(inMemory: true)
        var draft = PlayerDraft()
        draft.name = "편성검증"; draft.role = role; draft.schoolID = "hs-ref-001"
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: db.mainContext)
        let calendar = try XCTUnwrap(db.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first)
        for checkpoint in ["2029-04-01", "2030-04-01", date] {
            player.gameDate = checkpoint
            try CareerPathStore.synchronize(player: player, calendar: calendar, in: db.mainContext)
        }
        try db.mainContext.save()
        return (db, player, calendar, try ScoutingObservationStore.currentObservation(player: player, calendar: calendar, in: db.mainContext))
    }

    private func offer(team: String = "gears") -> DomesticContractOffer {
        DomesticContractOffer(id: "v162/" + team, resultID: "rookie/" + team + "/1", route: .rookie,
            name: CareerTeamDirectory.name("dev-" + team), roleID: "starter", issuedDate: "2030-04-01",
            expiresDate: "2030-04-07", economicIndex: 100, years: 1, h: 70, c: 52, p: 0, f: 18,
            availableBudget: 500, competition: 1)
    }

    func testV162DomesticMarketAddsFourClubsWithoutExpandingCollegeOrRewritingV1() throws {
        let seed = "v162/2030"
        let old = DomesticSelection.market(seed: seed)
        let expanded = DomesticSelection.market(seed: seed, expanded: true)
        XCTAssertEqual(old.filter { $0.route == .rookie }.count, 18)
        XCTAssertEqual(expanded.filter { $0.route == .rookie }.count, 30)
        XCTAssertEqual(expanded.filter { $0.route == .college }, old.filter { $0.route == .college })
        XCTAssertEqual(expanded.filter { $0.route == .college }.count, 24)
        XCTAssertEqual(expanded.filter { $0.route == .rookie }.map(\.order), Array(0..<30))
        XCTAssertEqual(Set(expanded.filter { $0.route == .rookie }.map { $0.id.components(separatedBy: "/")[1] }).count, 10)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(old)
        _ = DomesticSelection.market(seed: seed, expanded: true)
        XCTAssertEqual(try encoder.encode(DomesticSelection.market(seed: seed)), bytes)
        XCTAssertEqual(CareerTeamDirectory.teams(level: "college", expanded: true).count, 6)
        XCTAssertEqual(CareerTeamDirectory.teams(level: "mlb-development", expanded: true).count, 6)
    }

    func testV162SelectionVersionsValidateTheirOwnFrozenMarketsAndRejectCrossedCatalogs() throws {
        let (db, player, calendar, value) = try observation()
        _ = db
        let window = ContractEvaluationWindow(year: 2030, month: 4)
        let seed = player.id.uuidString + "/2030"
        for expanded in [false, true] {
            let seats = DomesticSelection.market(seed: seed, expanded: expanded)
            let candidates = DomesticSelection.candidates(seed: seed, month: 4)
            let result = DomesticSelection.simulate(observation: value, seats: seats, candidates: candidates,
                carried: [], sample: nil, sampleReason: "표본 없음")
            let selection = DomesticSelection(rule: expanded ? "domestic-selection-v2" : "domestic-selection-v1",
                seed: seed, priorMarket: "연간 신규 시장", sample: nil, sampleReason: "표본 없음", seats: seats,
                candidates: candidates, carried: [], picks: result.picks, results: result.results)
            XCTAssertNoThrow(try selection.validate(observation: value, window: window))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(selection)) as? [String: Any])
            object["rule"] = expanded ? "domestic-selection-v1" : "domestic-selection-v2"
            let crossed = try JSONDecoder().decode(DomesticSelection.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try crossed.validate(observation: value, window: window))
        }
        XCTAssertTrue(try calendar.isExpandedDomestic(year: 2030))
    }

    func testV162NewDomesticIdentitiesMapToCatalogAndMembershipWithoutChangingLegacyNames() throws {
        XCTAssertEqual(CareerTeamDirectory.expandedDomesticIDs.prefix(6), CareerTeamDirectory.domesticIDs[...])
        XCTAssertEqual(CareerTeamDirectory.expandedDomesticFirstIDs.prefix(6), CareerTeamDirectory.domesticFirstIDs[...])
        for (index, token) in ["gears", "silverhorns", "auroras", "crowns"].enumerated() {
            let member = try CareerMembership.make(offer: offer(team: token), on: GameDate("2030-04-01"),
                origin: GameDate("2026-04-01"), startAge: 16)
            XCTAssertEqual(member.teamID, "dev-" + token)
            XCTAssertEqual(ClubIdentity.resolve(name: member.name)?.id, "kbo-\(index + 6)")
            XCTAssertTrue(try XCTUnwrap(ClubIdentity.resolve(name: member.name)).participates)
            XCTAssertEqual(try JSONDecoder().decode(CareerMembership.self, from: JSONEncoder().encode(member)), member)
        }
        XCTAssertEqual(CareerTeamDirectory.name("dev-harbors"), "인천 하버스 육성")
        XCTAssertEqual(CareerTeamDirectory.name("pro-harbors"), "인천 하버스 1군")
    }

    func testV162RetryAndCollegeReviewsRetainOldVersionsAndAppendNewCandidates() throws {
        let (db, player, calendar, value) = try observation()
        _ = db
        let release = DomesticRelease(membershipOfferID: "old-club", date: "2029-11-01", evaluationKey: "old-evaluation")
        let window = ContractEvaluationWindow(year: 2030, month: 4)
        let old = try DomesticRetryReview.make(observation: value, release: release, window: window)
        let certified = try DomesticRetryReview.make(observation: value, release: release, window: window, certificationEnabled: true)
        let expanded = try DomesticRetryReview.make(observation: value, release: release, window: window, certificationEnabled: true, expandedMarket: true)
        XCTAssertNil(old.version); XCTAssertEqual(certified.version, 2); XCTAssertEqual(expanded.version, 3)
        XCTAssertEqual(old.results.count, 18); XCTAssertEqual(expanded.results.count, 30)
        XCTAssertEqual(try DomesticRetryReview.make(observation: value, release: release, window: window), old)
        XCTAssertEqual(try JSONDecoder().decode(DomesticRetryReview.self, from: JSONEncoder().encode(old)), old)
        XCTAssertTrue(expanded.results.allSatisfy { !$0.selected }, "Expanded slots do not manufacture an eligible sample.")
        let retrySnapshot = ContractEvaluationSnapshot(version: 5, rule: "contracts-window-v1", window: window,
            evaluatedDate: player.gameDate, calendarRevision: calendar.revision,
            affiliation: CareerAffiliationEntry(stage: .unsigned, since: "2030-04-01", schoolID: nil, schoolName: nil),
            routes: ["무소속 국내 육성팀 재입단"], observation: value, pending: ["표본 없음"], retry: expanded)
        XCTAssertNoThrow(try retrySnapshot.validate(player: player, calendar: calendar))
        let (collegeDB, collegePlayer, collegeCalendar, collegeObservation) = try observation(date: "2032-11-01")
        _ = collegeDB
        let member = CareerMembership(offerID: "college", route: .college, teamID: "college-0", name: "해솔대",
            since: "2030-04-01", economicEnd: "2031-03-31", enrollmentEnd: "2034-03-31", economicIndex: 100)
        let collegeWindow = ContractEvaluationWindow(year: 2032, month: 11)
        let oldCollege = try CollegeProReview.make(observation: collegeObservation, member: member, window: collegeWindow)
        let newCollege = try CollegeProReview.make(observation: collegeObservation, member: member, window: collegeWindow, expandedMarket: true)
        XCTAssertNil(oldCollege.version); XCTAssertEqual(newCollege.version, 2)
        XCTAssertEqual(oldCollege.results.count, 18); XCTAssertEqual(newCollege.results.count, 30)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(oldCollege)) as? [String: Any])
        XCTAssertNil(object["version"])
        let collegeSnapshot = ContractEvaluationSnapshot(version: 6, rule: "contracts-window-v1", window: collegeWindow,
            evaluatedDate: collegePlayer.gameDate, calendarRevision: collegeCalendar.revision,
            affiliation: CareerAffiliationEntry(stage: .unsigned, since: "2030-04-01", schoolID: nil, schoolName: nil),
            routes: ["대학 재학생 프로 진출"], observation: collegeObservation, pending: ["표본 없음"], college: newCollege)
        XCTAssertNoThrow(try collegeSnapshot.validate(player: collegePlayer, calendar: collegeCalendar))
        XCTAssertEqual(player.role, .batter)
    }

    func testV162DomesticSeasonGoalAndParticipationUseRecordedExpandedSchedule() throws {
        let id = UUID(), source = offer()
        let member = try CareerMembership.make(offer: source, on: GameDate("2030-04-01"), origin: GameDate("2026-04-01"), startAge: 16)
        var owner = CareerContractJournal(playerID: id)
        owner.memberships = [member]
        owner.decisions = [DomesticOfferDecision(offerID: source.id, kind: .accepted, date: "2030-04-01")]
        let role = CareerClubRole.make(member: member, owner: owner, offers: [source], on: "2030-04-01")
        let fixtures = try CareerTeamDirectory.fixtures(level: role.level, year: 2030, expanded: true)
            .filter { $0.includes(member.teamID) }.map { $0.forTeam(member.teamID) }
        let n = fixtures.filter { $0.isAppearance(for: .pitcher) }.count
        let goal = ClubSeasonGoal(id: ClubSeasonGoal.key(role, year: 2030), year: 2030, started: "2030-04-01",
            role: role, playerRole: "pitcher", fixtureIDs: fixtures.map(\.id), excludedKeys: [], appearances: n,
            targets: ClubSeasonGoal.targets(role: role, playerRole: "pitcher", appearances: n), expandedSchedule: true)
        owner.seasonGoals = [goal]
        XCTAssertNoThrow(try owner.validateSeasonGoals(today: GameDate("2030-04-01"), offers: [source], expandedFrom: nil, domesticExpandedFrom: 2030))
        XCTAssertThrowsError(try owner.validateSeasonGoals(today: GameDate("2030-04-01"), offers: [source], expandedFrom: nil, domesticExpandedFrom: 2031))
        let games = fixtures.map { fixture in
            let turn = fixture.isAppearance(for: .pitcher)
            return ClubParticipationGame(key: CareerMatchRecord.key(id, fixture.id), fixtureID: fixture.id,
                date: fixture.date.description, rotationDay: turn, appearance: false, kind: turn ? .bench : .rotationRest)
        }
        var basis = ClubParticipationBasis(playerID: id, membershipID: member.offerID, teamID: member.teamID,
            level: member.level, playerRole: "pitcher", year: 2030, from: "2030-04-01", through: "2030-09-22",
            games: games, expandedSchedule: true)
        XCTAssertNoThrow(try basis.validate())
        XCTAssertEqual(basis.turns, 6); XCTAssertEqual(basis.rotationRest, 24)
        basis.expandedSchedule = nil
        XCTAssertThrowsError(try basis.validate(), "The ten-team fixture IDs must not be validated as the legacy six-team league.")
    }

    func testV162ActualNewEvaluationIssuesTenTeamVersionAndRemainsFrozenOnReopen() throws {
        let (db, player, calendar, _) = try observation()
        let context = db.mainContext
        XCTAssertTrue(try ContractEvaluationStore.captureIfDue(player: player, calendar: calendar, in: context))
        try context.save()
        let row = try XCTUnwrap(ContractEvaluationStore.records(player: player, calendar: calendar, in: context).first)
        let snapshot = try row.snapshot(player: player, calendar: calendar)
        let selection = try XCTUnwrap(snapshot.selection)
        XCTAssertEqual(selection.rule, "domestic-selection-v3")
        XCTAssertEqual(selection.seats.filter { $0.route == .rookie }.count, 30)
        XCTAssertEqual(selection.seats.filter { $0.route == .college }.count, 24)
        let original = row.payload
        XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player: player, calendar: calendar, in: context))
        XCTAssertEqual(row.payload, original)
        XCTAssertFalse(context.hasChanges)
    }

    func testV162ObservationCatalogBoundaryKeepsFrozenSixTeamsAndAddsTenOnlyToNewReports() throws {
        for role in PlayerRole.allCases {
            let (db, player, calendar, current) = try observation(role: role)
            let context = db.mainContext
            var legacy = current
            legacy.contractFit = try ScoutingContractFit.make(legacy)
            legacy.interests = ScoutingInterests.make(legacy)
            XCTAssertNoThrow(try legacy.validate())
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let bytes = try encoder.encode(legacy)
            let frozen = try CareerScoutingReport(legacy)
            context.insert(frozen); try context.save()

            let latest = try ScoutingObservationStore.currentObservation(player: player, calendar: calendar, in: context)
            let fit = try XCTUnwrap(latest.contractFit)
            XCTAssertEqual(fit.version, 2)
            XCTAssertEqual(fit.catalogVersion, "domestic-market-v2")
            XCTAssertEqual(fit.clubs.count, role == .batter ? 30 : 10)
            XCTAssertEqual(fit.clubs.prefix(role == .batter ? 18 : 6).map(\.recruitment), legacy.contractFit?.clubs.map(\.recruitment))
            XCTAssertEqual(latest.interests, ScoutingInterests.make(latest))
            XCTAssertNoThrow(try latest.validate())
            XCTAssertEqual(try encoder.encode(frozen.snapshot()), bytes)
            XCTAssertEqual(try frozen.snapshot().contractFit?.catalogVersion, "domestic-market-v1")

            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(latest)) as? [String: Any])
            var changedFit = try XCTUnwrap(object["contractFit"] as? [String: Any])
            changedFit["catalogVersion"] = "domestic-market-v1"; object["contractFit"] = changedFit
            let crossed = try JSONDecoder().decode(ScoutingObservation.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try crossed.validate())
            XCTAssertFalse(context.hasChanges)
        }
    }
}
