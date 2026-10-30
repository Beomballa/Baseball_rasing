import Foundation

/// Presentation catalog only. Season rosters and frozen report identities remain engine-owned.
struct ClubIdentity: Identifiable, Equatable {
    enum League: String, CaseIterable, Identifiable {
        case kbo, npb, mlb
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
        var region: String { switch self { case .kbo: "한국"; case .npb: "일본"; case .mlb: "미국" } }
    }
    let league: League
    let index: Int
    let name: String
    let motif: String
    var id: String { league.rawValue + "-" + String(index) }
    var asset: String { "Club-" + id }
    var participates: Bool { index < 6 }
    var participation: String { participates ? "기존 계약 참가 구단" : "도감 전용 · 이번 시즌 미참여" }

    static let all: [Self] = [
        (.kbo, ["인천 하버스", "대전 코멧츠", "부산 타이즈", "서울 스타즈", "광주 폭시스", "대구 팔콘스", "수원 기어즈", "창원 실버혼즈", "성남 오로라스", "전주 크라운즈"],
         ["등대와 항구의 물결", "야구공을 품은 혜성", "바다의 큰 파도", "도시 위의 별", "여우의 옆얼굴", "날개를 펼친 매", "산업의 톱니와 날개", "은빛 영양의 뿔", "밤하늘의 오로라", "왕관과 월계수"]),
        (.npb, ["동도 스카이스", "항남 마리너즈", "서경 피닉스", "북해 스노우스", "중앙 레일즈", "남양 선즈", "센다이 스피릿츠", "치바 라군스", "사이타마 실버울브스", "고베 오리온즈"],
         ["구름과 하늘 지붕", "바다를 가르는 돛", "불꽃 날개의 봉황", "눈꽃과 흰 올빼미", "철도 바퀴와 속도선", "수평선의 햇살", "산의 수호 정령", "석호의 왜가리", "달빛 아래 늑대", "세 별과 항해 나침반"]),
        (.mlb, ["퍼시픽 웨이브스", "캐니언 호크스", "레이크 베어스", "메트로 나이츠", "애틀랜틱 세일러스", "프레리 버팔로스", "텍사스 아르마딜로스", "마이애미 코럴스", "볼티모어 라이트하우스", "덴버 서밋츠"],
         ["해안의 소나무와 파도", "협곡의 붉은 매", "호숫가의 곰", "도시를 지키는 기사", "나침반과 교차한 노", "초원의 들소", "야구공을 품은 아르마딜로", "산호와 물결", "항로를 밝히는 등대", "두 봉우리와 산 호수"])
    ].flatMap { (league: League, names: [String], motifs: [String]) in
        names.enumerated().map { Self(league: league, index: $0.offset, name: $0.element, motif: motifs[$0.offset]) }
    }

    static func resolve(name: String) -> Self? {
        let base = [" 육성", " 1군"].reduce(name) { text, suffix in
            text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text
        }
        return all.first { $0.name == base }
    }
}
