import XCTest
@testable import BM

final class ScoutingClubPresentationTests: XCTestCase {
    private let general = [
        "진로·권리/등록/예산 심사 전",
        "고교 성적 참고 · 프로 즉시 전력 표본과 구분",
        "20세 미만 · 정식 제의 대상 아님"
    ]

    private func club(_ id: String = "harbors", role: String = "slugger", demand: RecruitmentDemand = .depth,
                      h: Double? = 70, c: Double? = 72, f: Double? = -2,
                      confirmedEmpty: Bool = false, blockers: [String] = []) -> ScoutingClubFit {
        let values = PlayerInitialValues(contact: 70, power: 70, discipline: 70, speed: 70, defense: 70, arm: 70, mental: 70)
        let recruitment = ClubRoleRecruitment(id: id + "/" + role, name: id, roleID: role, demand: demand,
            leagueMinimum: 65, competitor: confirmedEmpty || c == nil ? nil : values, confirmedEmpty: confirmedEmpty)
        return ScoutingClubFit(recruitment: recruitment, h: h, c: c, p: 0, f: f,
            stage: ScoutingContractFit.stage(f: f), blockers: blockers)
    }

    private func interest(_ id: String = "harbors", role: String = "slugger", fit: Double = -2) -> ScoutingClubInterest {
        ScoutingClubInterest(id: id, name: id, roleID: role, roleLabel: role, level: .observing, fit: fit,
                             reasons: ["저장된 모집 사유", "저장된 비교 사유", "저장된 성적 사유"])
    }

    private func report(_ clubs: [ScoutingClubFit]) -> ScoutingContractFit {
        ScoutingContractFit(comparisons: [], selectedEnvironment: nil, clubs: clubs)
    }

    func testExactClubAndRoleJoinDoesNotTakeDifferentRoleOrHigherFit() throws {
        let power = club(), field = club(role: "field", h: 79, c: 72, f: 7)
        let fit = report([field, club("other"), power])
        let matched = try XCTUnwrap(ScoutingClubPresentation.matching(interest(), in: fit))
        XCTAssertEqual(matched.club, power)
        XCTAssertNil(ScoutingClubPresentation.matching(interest(role: "onBase"), in: fit))
        XCTAssertNil(ScoutingClubPresentation.matching(interest("absent"), in: fit))
        XCTAssertNil(ScoutingClubPresentation.matching(interest(fit: 0), in: fit))
        XCTAssertNil(ScoutingClubPresentation.matching(interest(), in: nil))
        XCTAssertNil(ScoutingClubPresentation.matching(interest(), in: report([power, power])))
    }

    func testActualShortfallAppearsBeforeCommonReviewWithoutChangingFrozenPayload() throws {
        let original = club(role: "field", blockers: general + ["주 포지션 숙련70 필요", "원본 수비70 필요"])
        let fit = report([original]), savedInterest = interest(role: "field")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let fitBytes = try encoder.encode(fit), interestBytes = try encoder.encode(savedInterest)
        let view = try XCTUnwrap(ScoutingClubPresentation.matching(savedInterest, in: fit))
        XCTAssertEqual(view.generalReviewConditions, general)
        XCTAssertEqual(view.recordedImprovementConditions, ["주 포지션 숙련70 필요", "원본 수비70 필요"])
        XCTAssertEqual(view.improvementConditions.first, "관찰 적합도 F -2.0 · 모집 역할 기량 보완")
        XCTAssertEqual(Array(view.improvementConditions.dropFirst()), view.recordedImprovementConditions)
        XCTAssertEqual(view.club.blockers, original.blockers)
        XCTAssertEqual(try encoder.encode(fit), fitBytes)
        XCTAssertEqual(try encoder.encode(savedInterest), interestBytes)
    }

    func testNoRecordedShortfallDoesNotMislabelContractReviewAsTrainingTask() {
        let view = ScoutingClubPresentation(club: club(f: 0, blockers: general))
        XCTAssertTrue(view.improvementConditions.isEmpty)
        XCTAssertEqual(view.generalReviewConditions, general)
        XCTAssertEqual(view.club.f, 0)
    }

    func testUnverifiedCompetitorDoesNotBecomeConfirmedVacancy() {
        let unknown = ScoutingClubPresentation(club: club(c: nil, f: nil, blockers: ["경쟁자 자료 미확인"]))
        XCTAssertTrue(unknown.competitionContext.contains("미확인"))
        XCTAssertTrue(unknown.competitionContext.contains("공석으로 가정하지 않습니다"))
        XCTAssertEqual(unknown.improvementConditions, ["경쟁자 자료 미확인"])
        let vacancy = ScoutingClubPresentation(club: club(demand: .vacancy, c: 65, f: 5, confirmedEmpty: true))
        XCTAssertEqual(vacancy.competitionContext, "확인된 공석 · 리그 역할 하한 65.0")
        let closed = ScoutingClubPresentation(club: club(demand: .none, c: nil, f: nil))
        XCTAssertEqual(closed.competitionContext, "모집이 없어 경쟁 기준을 적용하지 않습니다.")
    }

    func testEachClubKeepsItsSavedCriteriaAndUnknownFutureConditions() {
        let first = ScoutingClubPresentation(club: club(c: 68, f: 2))
        let second = ScoutingClubPresentation(club: club("sharks", c: 76, f: -6,
            blockers: ["다음 버전에서 추가된 개별 조건"]))
        XCTAssertEqual(first.club.c, 68)
        XCTAssertEqual(second.club.c, 76)
        XCTAssertTrue(first.improvementConditions.isEmpty)
        XCTAssertEqual(second.recordedImprovementConditions, ["다음 버전에서 추가된 개별 조건"])
        XCTAssertEqual(second.improvementConditions.count, 2)
        XCTAssertEqual(first.club.h, second.club.h)
        XCTAssertNotEqual(first.club.f, second.club.f)
    }
}
