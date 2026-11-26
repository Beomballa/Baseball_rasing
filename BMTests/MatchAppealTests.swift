import XCTest
@testable import BM

final class MatchAppealTests: XCTestCase {
    private func attempt(_ from: Int, at: Double) -> MatchAppealAttempt {
        .init(from: from, base: from, receiver: from == 1 ? 2 : 4, releaseAt: at-0.5, ballAt: at-0.1, at: at)
    }
    func testApprovedThreePathsKeepThreeOutsAndOnlyAdoptedAppealCancelsRun() {
        let departed: [MatchAppealDeparture] = [1,3].map { .init(from: $0, at: 1.2, retouchedAt: nil, noticedAt: 2) }
        for (path, selected, runs) in [([attempt(1,at:5.05)],[0],1),
                                      ([attempt(3,at:5.05)],[0],0),
                                      ([attempt(1,at:5.05),attempt(3,at:6.82)],[1],0)] {
            let result = MatchAppealRules.adjudicate(outsBefore: 1, touchedAt: 1.85, departures: departed,
                attempts: path, closedAt: 8, goals: [(3,3.7)])
            XCTAssertEqual(result.selected, selected); XCTAssertEqual(result.runs, runs)
            XCTAssertEqual(1+1+result.selected.count, 3)
        }
    }
    func testRetouchedLateDuplicateAndUnappealedViolationsDoNotCreateOut() {
        let departed = [MatchAppealDeparture(from: 3, at: 1.2, retouchedAt: 4, noticedAt: 2)]
        let restored = MatchAppealRules.adjudicate(outsBefore: 1, touchedAt: 1.85, departures: departed,
            attempts: [attempt(3,at:5)], closedAt: 8, goals: [])
        XCTAssertTrue(restored.selected.isEmpty)
        let missing = [MatchAppealDeparture(from: 3, at: 1.2, retouchedAt: nil, noticedAt: nil)]
        let expired = MatchAppealRules.adjudicate(outsBefore: 1, touchedAt: 1.85, departures: missing,
            attempts: [attempt(3,at:8),attempt(3,at:9)], closedAt: 8, goals: [(3,3.7)])
        XCTAssertEqual(expired.runs, 1); XCTAssertTrue(expired.selected.isEmpty)
        let absent = MatchAppealRules.adjudicate(outsBefore: 1, touchedAt: 1.85, departures: missing,
            attempts: [], closedAt: 8, goals: [(3,3.7)])
        XCTAssertEqual(absent.runs, 1); XCTAssertTrue(absent.selected.isEmpty)
    }
    func testAutomaticPhysicalInputsPersistSeparateDepartureObservationAndAppeal() throws {
        var cases: [String:Int] = [:]
        for distance in [15.0,25,35,50,65] {
            for direction in [-40.0,-20,0,20,40] {
                for flight in [1.85,2.5,3.8,5] {
                    for reads in [(0.0,75.0),(90,0),(0,0),(100,100)] {
                        var match = CareerMatch(random: 1, isHome: false, role: "league", appearance: false,
                            contact: 60, power: 60, discipline: 60, mastery: [:])
                        match.outs = 1
                        match.runnerProfiles = [.init(speed: 100, responsiblePitcher: "home-starter", id: "R1"),nil,
                                                .init(speed: 100, responsiblePitcher: "home-relief", id: "R3")]
                        var ball = MatchBattedBall(kind: .line, quality: 0.9, contact: 70, power: 60,
                            speed: 32, angle: 10, direction: direction, distance: distance, flight: flight)
                        ball.version = 2
                        let context = MatchSpecialContext(before: MatchPitchState(match), ball: ball,
                            batter: .init(speed:60,responsiblePitcher:"home-relief",id:"B1"), stats: nil, npc: nil,
                            defending: false, ownBatter: false, discipline: ["R1":reads.0,"R3":reads.1,"B1":60])
                        guard let play = MatchAppealRules.resolve(context), let event = play.appeal else { continue }
                        try play.validate()
                        XCTAssertLessThanOrEqual(1+play.outsAdded, 3)
                        XCTAssertEqual(try JSONDecoder().decode(MatchDetailedPlay.self, from: JSONEncoder().encode(play)), play)
                        let key = event.attempts.map { String($0.from) }.joined(separator:"-")
                        cases[key,default:0] += 1
                    }
                }
            }
        }
        print("P12_AUTO_APPEALS",cases)
        XCTAssertFalse(cases.isEmpty)
        XCTAssertNotNil(cases["1"]); XCTAssertNotNil(cases["3"]); XCTAssertNotNil(cases["1-3"])
    }
    @MainActor func testBothRolesGeneralGameLedgersAndLegacyNil() throws {
        for role in PlayerRole.allCases {
            for seed in 1...16 {
                var match = InplayIntegrationTests().makeMatch(role:role); match.random = UInt64(seed)
                match.enablePitchEvents(); match.enableRunning(); match.enableFieldReview(); match.enableSpecialPlays(); match.enableAppeals()
                XCTAssertEqual(match.appealRulesVersion, 1)
                try match.advance(.automatic)
                do { try match.playerRecords?.validate(match:match); try match.validateDetailedField(); try match.validateRunning() }
                catch {
                    print("P12_INVALID",role.rawValue,seed)
                    let a=XCTAttachment(data:try JSONEncoder().encode(match),uniformTypeIdentifier:"public.json");a.name="P12-invalid";a.lifetime = .keepAlways;add(a)
                    throw error
                }
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(match)),match)
            }
            var old = InplayIntegrationTests().makeMatch(role:role)
            old.enablePitchEvents();old.enableRunning();old.enableFieldReview();old.enableSpecialPlays()
            var copy = old; try old.advance(.automatic);try copy.advance(.automatic)
            XCTAssertEqual(old,copy);XCTAssertNil(copy.appealRulesVersion)
            copy.enableAppeals();XCTAssertNil(copy.appealRulesVersion)
        }
    }
}
