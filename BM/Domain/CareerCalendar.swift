import Foundation

struct GameDate: Comparable, Hashable, Sendable, CustomStringConvertible {
    private let value: Date
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    init(_ text: String) throws {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, (1...9998).contains(parts[0]),
              let date = Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            throw CalendarError.invalidDate
        }
        value = date
        guard description == text else { throw CalendarError.invalidDate }
    }

    private init(value: Date) { self.value = value }
    var year: Int { Self.calendar.component(.year, from: value) }
    var description: String {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    func adding(days: Int) -> GameDate {
        GameDate(value: Self.calendar.date(byAdding: .day, value: days, to: value)!)
    }
    func anniversary(in year: Int) -> GameDate {
        GameDate(value: Self.calendar.date(byAdding: .year, value: year - self.year, to: value)!)
    }
    func age(startingAt age: Int, on date: GameDate) -> Int {
        let years = date.year - year
        return age + years - (date < anniversary(in: date.year) ? 1 : 0)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

struct SeasonFixture: Identifiable, Equatable, Sendable {
    let number: Int
    let date: GameDate
    let homeID: String
    let awayID: String
    var id: String { "\(date)-\(homeID)-\(awayID)" }
    func includes(_ schoolID: String) -> Bool { homeID == schoolID || awayID == schoolID }
    func opponent(of schoolID: String) -> String { homeID == schoolID ? awayID : homeID }
    func isAppearance(for role: PlayerRole) -> Bool { role == .batter || (number - 1).isMultiple(of: 5) }
}

enum SeasonSchedule {
    static func group(for playerID: UUID, schoolID: String, schools: [School]) -> [String] {
        // Stable ordering survives relaunches; Swift's randomized Hasher must not seed schedules.
        let seed = playerID.uuidString
        func rank(_ id: String) -> UInt64 {
            (seed + id).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
        let opponents = schools.map(\.id).filter { $0 != schoolID }.sorted {
            let left = rank($0), right = rank($1)
            return left == right ? $0 < $1 : left < right
        }
        return [schoolID] + opponents.prefix(5)
    }

    static func fixtures(year: Int, schoolIDs: [String]) throws -> [SeasonFixture] {
        guard schoolIDs.count == 6, Set(schoolIDs).count == 6 else { throw CalendarError.invalidGroup }
        let first = try GameDate(String(format: "%04d-04-01", year))
        var result: [SeasonFixture] = []
        for cycle in 0..<6 {
            var ring = schoolIDs
            for round in 0..<5 {
                let number = cycle * 5 + round + 1
                for pair in 0..<3 {
                    let a = ring[pair], b = ring[5 - pair]
                    let swap = (cycle + pair).isMultiple(of: 2)
                    result.append(SeasonFixture(number: number, date: first.adding(days: (number - 1) * 6),
                                                homeID: swap ? a : b, awayID: swap ? b : a))
                }
                ring.insert(ring.removeLast(), at: 1)
            }
        }
        return result
    }

    static func academicStatus(age: Int) -> String {
        switch age {
        case ...16: "고1"
        case 17: "고2"
        case 18: "고3"
        case 19: "고교 졸업 · 진로준비"
        default: "성인 · 진로 선택 대기"
        }
    }
}

enum CalendarError: LocalizedError {
    case invalidDate, invalidGroup, actionUsed, preparationRequired, fixturePending, anniversaryConfirmation, staleState
    var errorDescription: String? {
        switch self {
        case .invalidDate: "저장된 날짜를 확인할 수 없습니다. 저장 데이터를 유지한 채 진행을 중단합니다."
        case .invalidGroup: "6팀 일정 정보를 확인할 수 없습니다."
        case .actionUsed: "오늘 행동을 이미 사용했습니다."
        case .preparationRequired: "오늘의 휴식을 먼저 선택해 주세요. 훈련은 다음 구현에서 연결합니다."
        case .fixturePending: "오늘은 경기일입니다. 실제 경기 결과 연결 전까지 날짜를 넘길 수 없습니다."
        case .anniversaryConfirmation: "다음 날은 나이·학적 변경일입니다. 하루 진행으로 확인해 주세요."
        case .staleState: "선수 또는 날짜 상태가 바뀌었습니다. 현재 화면에서 다시 진행해 주세요."
        }
    }
}
