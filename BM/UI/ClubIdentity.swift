import Foundation

/// Presentation catalog only. Season rosters and frozen report identities remain engine-owned.
struct ClubIdentity: Identifiable, Equatable {
    enum League: String, CaseIterable, Identifiable {
        case kbo, npb, mlb
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
        var region: String { switch self { case .kbo: "한국"; case .npb: "일본"; case .mlb: "미국" } }
    }
    enum Division: String, CaseIterable {
        case east, west
        var label: String { self == .east ? "동부" : "서부" }
    }
    let league: League
    let index: Int
    let name: String
    let motif: String
    let city: String?
    let division: Division?
    var id: String { league.rawValue + "-" + String(index) }
    var asset: String { "Club-" + id }
    var participates: Bool { league != .kbo || index < 6 }
    var isExpansionClub: Bool { index >= 10 }

    private static let domestic: [Self] = [
        ("인천 하버스", "등대와 항구의 물결"), ("대전 코멧츠", "야구공을 품은 혜성"),
        ("부산 타이즈", "바다의 큰 파도"), ("서울 스타즈", "도시 위의 별"),
        ("광주 폭시스", "여우의 옆얼굴"), ("대구 팔콘스", "날개를 펼친 매"),
        ("수원 기어즈", "산업의 톱니와 날개"), ("창원 실버혼즈", "은빛 영양의 뿔"),
        ("성남 오로라스", "밤하늘의 오로라"), ("전주 크라운즈", "왕관과 월계수")
    ].enumerated().map { index, entry in
        Self(league: .kbo, index: index, name: entry.0, motif: entry.1, city: nil, division: nil)
    }

    // Index is the original catalog and fixture alias. New entries append after the V145 teams.
    private static let japanese: [Self] = overseas(.npb, [
        ("동도 스카이스", "구름과 하늘 지붕", "도쿄", .east),
        ("항남 마리너즈", "바다를 가르는 돛", "요코하마", .east),
        ("서경 피닉스", "불꽃 날개의 봉황", "교토", .west),
        ("북해 스노우스", "눈꽃과 흰 올빼미", "삿포로권", .east),
        ("중앙 레일즈", "철도 바퀴와 속도선", "나고야", .west),
        ("남양 선즈", "수평선의 햇살", "나하", .west),
        ("센다이 스피릿츠", "산의 수호 정령", "센다이", .east),
        ("치바 라군스", "석호의 왜가리", "치바", .east),
        ("사이타마 실버울브스", "달빛 아래 늑대", "사이타마", .east),
        ("고베 오리온즈", "세 별과 항해 나침반", "고베", .west),
        ("모리오카 아이언스", "교차한 망치와 산등성이", "모리오카", .east),
        ("니가타 리드스", "강을 따라 자라는 세 줄기 갈대", "니가타", .east),
        ("히로시마 메이플스", "붉은 단풍잎", "히로시마", .west),
        ("후쿠오카 게일스", "바닷바람을 가르는 풍향계", "후쿠오카", .west),
        ("마쓰야마 시트러스", "잎이 달린 감귤", "마쓰야마", .west)
    ])
    private static let american: [Self] = overseas(.mlb, [
        ("퍼시픽 웨이브스", "해안의 소나무와 파도", "시애틀", .west),
        ("캐니언 호크스", "협곡의 붉은 매", "피닉스", .west),
        ("레이크 베어스", "호숫가의 곰", "시카고", .east),
        ("메트로 나이츠", "도시를 지키는 기사", "뉴욕", .east),
        ("애틀랜틱 세일러스", "나침반과 교차한 노", "노퍽", .east),
        ("프레리 버팔로스", "초원의 들소", "캔자스시티", .west),
        ("텍사스 아르마딜로스", "야구공을 품은 아르마딜로", "댈러스·포트워스", .west),
        ("마이애미 코럴스", "산호와 물결", "마이애미", .east),
        ("볼티모어 라이트하우스", "항로를 밝히는 등대", "볼티모어", .east),
        ("덴버 서밋츠", "두 봉우리와 산 호수", "덴버", .west),
        ("보스턴 브라스", "황동 나팔과 벽돌 아치", "보스턴", .east),
        ("롤리 오크스", "참나무 잎과 도토리", "롤리", .east),
        ("포틀랜드 에버그린스", "겹쳐진 상록수 실루엣", "포틀랜드", .west),
        ("샌디에이고 선레이스", "파도 위로 뜨는 태양", "샌디에이고", .west),
        ("라스베이거스 미라지스", "사막의 신기루와 각진 능선", "라스베이거스", .west)
    ])

    static let all = domestic + japanese + american

    private static func overseas(_ league: League, _ entries: [(name: String, motif: String, city: String, division: Division)]) -> [Self] {
        entries.enumerated().map { index, entry in
            Self(league: league, index: index, name: entry.name, motif: entry.motif, city: entry.city, division: entry.division)
        }
    }

    static func resolve(id: String) -> Self? {
        all.first { $0.id == id }
    }

    static func resolve(name: String) -> Self? {
        let base = [" 육성", " 1군"].reduce(name) { text, suffix in
            text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text
        }
        return all.first { $0.name == base }
    }
}
