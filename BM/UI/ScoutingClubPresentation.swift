import Foundation

// Presentation of the saved assessment, without generating a new assessment or changing its reasons.
struct ScoutingClubPresentation: Equatable {
    let club: ScoutingClubFit

    static func matching(_ interest: ScoutingClubInterest, in fit: ScoutingContractFit?) -> Self? {
        let matches = fit?.clubs.filter {
            $0.id == interest.id + "/" + interest.roleID && $0.recruitment.roleID == interest.roleID
        } ?? []
        guard matches.count == 1, let club = matches.first, club.f == interest.fit else { return nil }
        return Self(club: club)
    }

    private static let generalConditions: Set<String> = [
        "진로·권리/등록/예산 심사 전",
        "고교 성적 참고 · 프로 즉시 전력 표본과 구분",
        "20세 미만 · 정식 제의 대상 아님"
    ]

    var generalReviewConditions: [String] {
        club.blockers.filter { Self.generalConditions.contains($0) }
    }

    var recordedImprovementConditions: [String] {
        club.blockers.filter { !Self.generalConditions.contains($0) }
    }

    var improvementConditions: [String] {
        var conditions = recordedImprovementConditions
        if let fit = club.f, fit.isFinite, fit < 0 {
            conditions.insert("관찰 적합도 F " + Self.number(fit) + " · 모집 역할 기량 보완", at: 0)
        }
        return conditions
    }

    var recruitmentContext: String {
        switch club.recruitment.demand {
        case .none: "해당 역할 모집 없음"
        case .depth: "기존 선수층을 보강하는 모집"
        case .vacancy: "주전 자리를 보강하는 모집"
        }
    }

    var competitionContext: String {
        guard club.recruitment.demand != .none else { return "모집이 없어 경쟁 기준을 적용하지 않습니다." }
        guard club.c != nil else { return "경쟁자 자료 미확인 · 공석으로 가정하지 않습니다." }
        if club.recruitment.confirmedEmpty {
            return "확인된 공석 · 리그 역할 하한 " + Self.number(club.recruitment.leagueMinimum)
        }
        return "등록된 경쟁자 자료 반영 · 리그 역할 하한 " + Self.number(club.recruitment.leagueMinimum)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
