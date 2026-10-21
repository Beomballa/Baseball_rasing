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
        case .fixturePending: "오늘 경기를 먼저 완료하고 결과를 저장해 주세요."
        case .anniversaryConfirmation: "다음 날은 나이·학적 변경일입니다. 하루 진행으로 확인해 주세요."
        case .staleState: "선수 또는 날짜 상태가 바뀌었습니다. 현재 화면에서 다시 진행해 주세요."
        }
    }
}

struct LeagueOfficialResult: Equatable {
    let fixtureID: String
    let homeScore: Int
    let awayScore: Int
}
struct LeagueResult: Identifiable, Equatable {
    let fixture: SeasonFixture
    let homeScore: Int
    let awayScore: Int
    let automatic: Bool
    var id: String {fixture.id}
}
struct LeagueStanding: Identifiable, Equatable {
    let id: String
    var wins=0,losses=0,draws=0
    var rank: Int?
    var games: Int {wins+losses+draws}
    var decided: Int {wins+losses}
    var percentage: String {decided == 0 ? "—":String(format:"%.3f",Double(wins)/Double(decided))}
}
struct AnnualLeague: Equatable {
    let year: Int
    let fixtures: [SeasonFixture]
    let results: [LeagueResult]
    let standings: [LeagueStanding]
    let pendingIDs: Set<String>
    static let version="native-league-v1"

    static func ordered(_ teams:[LeagueStanding]) -> [LeagueStanding] {
        let sorted=teams.sorted { a,b in
            if a.decided == 0 || b.decided == 0 {
                if (a.decided == 0) != (b.decided == 0) {return a.decided > 0}
            } else if a.wins*b.decided != b.wins*a.decided {return a.wins*b.decided > b.wins*a.decided}
            return a.id < b.id
        }
        return sorted.enumerated().map { index,item in
            var row=item
            if item.decided > 0 {
                row.rank=sorted.prefix(index).filter {$0.decided > 0 && $0.wins*item.decided > item.wins*$0.decided}.count+1
            }
            return row
        }
    }
    static func make(playerID:UUID,schoolIDs:[String],origin:GameDate,startAge:Int,today:GameDate,year:Int,
                     official:[LeagueOfficialResult],pending:Set<String>=[]) throws -> AnnualLeague {
        guard today >= origin,(origin.year...today.year).contains(year) else {throw LeagueError.invalidRecord}
        let fixtures=try SeasonSchedule.fixtures(year:year,schoolIDs:schoolIDs).filter {
            $0.date >= origin && origin.age(startingAt:startAge,on:$0.date) <= 18
        }
        let eligible=Dictionary(uniqueKeysWithValues:fixtures.map {($0.id,$0)})
        guard Set(official.map(\.fixtureID)).count == official.count,official.allSatisfy({
            eligible[$0.fixtureID].map {$0.date <= today} == true && $0.homeScore >= 0 && $0.awayScore >= 0
        }),pending.allSatisfy({eligible[$0] != nil}),Set(official.map(\.fixtureID)).isDisjoint(with:pending) else {throw LeagueError.invalidRecord}
        guard !pending.contains(where:{eligible[$0]!.date < today}) else {throw LeagueError.unfinishedPast}
        let actual=Dictionary(uniqueKeysWithValues:official.map {($0.fixtureID,$0)})
        var results:[LeagueResult]=[]
        for fixture in fixtures {
            if let saved=actual[fixture.id] {
                results.append(LeagueResult(fixture:fixture,homeScore:saved.homeScore,awayScore:saved.awayScore,automatic:false))
            } else if fixture.date < today {
                let score=automaticScore(playerID:playerID,fixture:fixture)
                results.append(LeagueResult(fixture:fixture,homeScore:score.0,awayScore:score.1,automatic:true))
            }
        }
        var rows=Dictionary(uniqueKeysWithValues:schoolIDs.map {($0,LeagueStanding(id:$0))})
        for game in results {
            let h=game.fixture.homeID,a=game.fixture.awayID
            if game.homeScore == game.awayScore {rows[h]!.draws += 1;rows[a]!.draws += 1}
            else if game.homeScore > game.awayScore {rows[h]!.wins += 1;rows[a]!.losses += 1}
            else {rows[a]!.wins += 1;rows[h]!.losses += 1}
        }
        return AnnualLeague(year:year,fixtures:fixtures,results:results,standings:ordered(Array(rows.values)),pendingIDs:pending)
    }
    // Versioned, stateless team-only simulation. Never change v1 or consume the personal match RNG.
    static func automaticScore(playerID:UUID,fixture:SeasonFixture) -> (Int,Int) {
        var seed=(version+playerID.uuidString+fixture.id).utf8.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
        func draw() -> Int {
            seed=seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32)%6)
        }
        let home=draw()+draw(),away=draw()+draw()
        return (home,away)
    }
}
enum LeagueError: LocalizedError {
    case invalidRecord,unfinishedPast
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "리그 일정이나 경기 기록을 확인할 수 없습니다. 기존 저장은 유지합니다."
        case .unfinishedPast: "이전 날짜의 미완료 경기가 있어 순위를 확정할 수 없습니다. 기존 경기 기록을 유지합니다."
        }
    }
}
