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
    var monday: GameDate { adding(days: -((Self.calendar.component(.weekday, from: value) + 5) % 7)) }
    var year: Int { Self.calendar.component(.year, from: value) }
    var description: String {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    func days(to date: GameDate) -> Int { Self.calendar.dateComponents([.day], from: value, to: date.value).day! }
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
                     official:[LeagueOfficialResult],pending:Set<String>=[],competitionFixtures:[SeasonFixture]?=nil,
                     automatic:[LeagueOfficialResult]=[]) throws -> AnnualLeague {
        guard today >= origin,(origin.year...today.year).contains(year) else {throw LeagueError.invalidRecord}
        let fixtures=try competitionFixtures ?? SeasonSchedule.fixtures(year:year,schoolIDs:schoolIDs).filter {
            $0.date >= origin && origin.age(startingAt:startAge,on:$0.date) <= 18
        }
        let eligible=Dictionary(uniqueKeysWithValues:fixtures.map {($0.id,$0)})
        guard Set(official.map(\.fixtureID)).count == official.count,official.allSatisfy({
            eligible[$0.fixtureID].map {$0.date <= today} == true && $0.homeScore >= 0 && $0.awayScore >= 0
        }),pending.allSatisfy({eligible[$0] != nil}),Set(official.map(\.fixtureID)).isDisjoint(with:pending) else {throw LeagueError.invalidRecord}
        guard !pending.contains(where:{eligible[$0]!.date < today}) else {throw LeagueError.unfinishedPast}
        guard Set(automatic.map(\.fixtureID)).count == automatic.count,automatic.allSatisfy({
            eligible[$0.fixtureID].map {$0.date < today} == true && $0.homeScore >= 0 && $0.awayScore >= 0
        }),Set(automatic.map(\.fixtureID)).isDisjoint(with:official.map(\.fixtureID)),
          Set(automatic.map(\.fixtureID)).isDisjoint(with:pending) else {throw LeagueError.invalidRecord}
        let actual=Dictionary(uniqueKeysWithValues:official.map {($0.fixtureID,$0)})
        let simulated=Dictionary(uniqueKeysWithValues:automatic.map {($0.fixtureID,$0)})
        var results:[LeagueResult]=[]
        for fixture in fixtures {
            if let saved=actual[fixture.id] {
                results.append(LeagueResult(fixture:fixture,homeScore:saved.homeScore,awayScore:saved.awayScore,automatic:false))
            } else if let saved=simulated[fixture.id] {
                results.append(LeagueResult(fixture:fixture,homeScore:saved.homeScore,awayScore:saved.awayScore,automatic:true))
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

struct PersonalSeasonTotals: Equatable, Codable {
    var games = 0
    var line = MatchLine()
    var average: String { line.atBats == 0 ? "—" : String(format: "%.3f", Double(line.hits) / Double(line.atBats)) }
    var innings: String { "\(line.pitchingOuts / 3).\(line.pitchingOuts % 3)" }
    var whip: String { line.pitchingOuts == 0 ? "—" : String(format: "%.2f", (Double(line.hitsAllowed) + Double(line.pitchingWalks)) * 3 / Double(line.pitchingOuts)) }

    mutating func add(_ value: MatchLine) throws {
        let keys: [WritableKeyPath<MatchLine, Int>] = [\.plateAppearances, \.atBats, \.hits, \.homeRuns, \.walks, \.strikeouts, \.rbi,
            \.pitchingOuts, \.pitches, \.hitsAllowed, \.runsAllowed, \.pitchingWalks, \.pitchingStrikeouts]
        guard keys.allSatisfy({ value[keyPath: $0] >= 0 }), value.homeRuns <= value.hits,
              value.hits <= value.atBats, value.atBats <= value.plateAppearances,
              value.walks <= value.plateAppearances - value.atBats,
              value.strikeouts <= value.atBats else { throw LeagueError.invalidRecord }
        var next = line
        for key in keys {
            let sum = next[keyPath: key].addingReportingOverflow(value[keyPath: key])
            guard !sum.overflow else { throw LeagueError.invalidRecord }
            next[keyPath: key] = sum.partialValue
        }
        let count = games.addingReportingOverflow(1)
        guard !count.overflow else { throw LeagueError.invalidRecord }
        line = next; games = count.partialValue
    }
}

struct CareerSeasonSummary: Equatable {
    let league: AnnualLeague
    let totals: PersonalSeasonTotals
    // A legacy partial season is not a completed 30-game season.
    var finalized: Bool {
        league.fixtures.count == 90 && league.results.count == 90 && league.pendingIDs.isEmpty &&
        league.standings.count == 6 && league.standings.allSatisfy { $0.games == 30 }
    }
    var finalStandings: [LeagueStanding] {
        guard finalized, league.standings.allSatisfy({ $0.decided == 0 }) else { return league.standings }
        return league.standings.map { var row = $0; row.rank = 1; return row }
    }
    var champions: [LeagueStanding] { finalized ? finalStandings.filter { $0.rank == 1 } : [] }
}

struct OffseasonPlan: Equatable {
    let seasonYear: Int
    let date: GameDate
    let target: GameDate
    let age: Int
    let targetAge: Int
    var remainingDays: Int {
        var day = date, count = 0
        while day < target { day = day.adding(days: 1); count += 1 }
        return count
    }
    static func make(summary: CareerSeasonSummary, origin: GameDate, startAge: Int, today: GameDate) throws -> OffseasonPlan {
        let year = summary.league.year
        guard summary.finalized, year < 9998 else { throw OffseasonError.unavailable }
        let target = try GameDate(String(format: "%04d-04-01", year + 1))
        guard let last = summary.league.fixtures.map(\.date).max(), today > last, today < target else { throw OffseasonError.unavailable }
        return OffseasonPlan(seasonYear: year, date: today, target: target,
            age: origin.age(startingAt: startAge, on: today), targetAge: origin.age(startingAt: startAge, on: target))
    }
}

enum OffseasonError: LocalizedError {
    case unavailable
    var errorDescription: String? { "최신 시즌의 30경기 결산을 마친 뒤 다음 해 4월 1일 전까지만 진행할 수 있습니다. 현재 날짜와 기록을 다시 확인해 주세요." }
}

// Eligibility describes a route, never an admission or contract award.
enum CareerAffiliation: String, Codable {
    case school, preparation, unsigned
    var label: String {
        switch self {
        case .school: "고교 재학"
        case .preparation: "고교 졸업 · 진로 준비"
        case .unsigned: "무소속 · 성인 진로 준비"
        }
    }
    static func stage(age: Int) -> Self { age <= 18 ? .school : age == 19 ? .preparation : .unsigned }
}
struct CareerAffiliationEntry: Codable, Equatable {
    let stage: CareerAffiliation
    let since: String
    let schoolID: String?
    let schoolName: String?
}
struct CareerPathHistory: Codable, Equatable {
    var version = 1
    let playerID: UUID
    let origin: String
    let source: String
    var entries: [CareerAffiliationEntry]
    var current: CareerAffiliationEntry { entries[entries.count - 1] }
    func validate(playerID: UUID, origin: String, today: GameDate, startAge: Int = 16) throws {
        guard version == 1, self.playerID == playerID, self.origin == origin,
              ["initial-v1", "legacy-v1"].contains(source), !entries.isEmpty else { throw CareerPathError.invalid }
        var last: GameDate?
        for (index, entry) in entries.enumerated() {
            let date = try GameDate(entry.since)
            guard date >= (try GameDate(origin)), date <= today, last.map({ date > $0 }) ?? true,
                  entry.stage == CareerAffiliation.stage(age:try GameDate(origin).age(startingAt:startAge,on:date)),
                  (entry.stage == .school ? entry.schoolID != nil && entry.schoolName != nil : entry.schoolID == nil && entry.schoolName == nil),
                  index == 0 || (entries[index - 1].stage == .school && entry.stage == .preparation)
                    || (entries[index - 1].stage == .preparation && entry.stage == .unsigned) else { throw CareerPathError.invalid }
            last = date
        }
    }
}
enum CareerPathError: LocalizedError {
    case invalid
    var errorDescription: String? { "진로·소속 이력을 확인하지 못했습니다. 기존 저장을 유지합니다. 다시 확인해 주세요." }
}
struct CareerRoute: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let detail: String
    static func routes(age: Int) -> [Self] {
        let status = age < 20 ? "20세부터 나이 조건 충족" : age <= 23 ? "나이 조건 충족 · 심사 대기" : "신규 신청 나이 범위 종료"
        return [Self(id:"rookie",title:"국내 신인",status:status,
                     detail:"20~23세 · 신규 프로 경력 없는 아마추어/무소속. 성적·모집·권리·예산 심사 후 결정합니다."),
                Self(id:"college",title:"대학 입단",status:status,
                     detail:"20~23세 · 대학 모집·성적·자리 심사가 필요합니다. 자동 입학하지 않습니다."),
                Self(id:"unsigned",title:"무소속 준비",status:age < 19 ? "고교 졸업 후 가능" : "훈련·휴식으로 준비 가능",
                     detail:"계약 없이 육성을 계속할 수 있습니다. 인증 평가전과 실제 진로 신청은 후속 단계입니다.")]
    }
}

struct ContractEvaluationWindow: Codable, Equatable {
    let year: Int
    let month: Int
    var id: String { String(format:"%04d-%02d",year,month) }
    var start: GameDate { try! GameDate(id+"-01") }
    var end: GameDate { try! GameDate(id+"-14") }
    var label: String { month == 4 ? "4월 · 성인/아마추어 진로" : month == 7 ? "7월 · 무소속 재평가":"11월 · 프로 외부/갱신" }
    static func containing(_ date: GameDate) -> Self? {
        [4,7,11].map { Self(year:date.year,month:$0) }.first { $0.start <= date && date <= $0.end }
    }
    func routes(age: Int, affiliation: CareerAffiliation) -> [String] {
        guard age >= 20, affiliation == .unsigned else { return [] }
        switch month {
        case 4: return age <= 23 ? ["국내 신인","대학 입단"]:["국내 전력/검증 테스트"]
        case 7: return age <= 23 ? ["국내 신인"]:["국내 전력/검증 테스트"]
        default: return [] // Professional affiliation/rights are not yet implemented.
        }
    }
}
enum ContractEvaluationError: LocalizedError {
    case invalid, unread, pendingChanges
    var errorDescription: String? {
        switch self {
        case .invalid: "계약 평가 원장을 확인하지 못했습니다. 기존 자료를 유지하고 다시 확인해 주세요."
        case .unread: "홈에서 새 계약 평가 자료를 확인한 뒤 날짜를 진행해 주세요."
        case .pendingChanges: "다른 저장 작업이 진행 중입니다. 완료한 뒤 다시 확인해 주세요."
        }
    }
}

/// Initial game balance, not a claim about real athletes' aging.
enum CareerAgingRules {
    static func loss(_ kind:TrainingKind,age:Int) -> Double {
        guard (31...40).contains(age),kind != .mental else {return 0}
        let physical:[TrainingKind]=[.power,.speed,.arm,.velocity,.stamina]
        return age <= 33 ? (physical.contains(kind) ? 0.25:0.10):age <= 36 ? (physical.contains(kind) ? 0.50:0.25):(physical.contains(kind) ? 0.75:0.40)
    }
    static func value(_ before:Double,kind:TrainingKind,age:Int,pitch:Bool=false) -> Double {
        let loss=loss(kind,age:age)
        return TrainingRules.round(min(before,max(pitch ? 0:1,before-loss)))
    }
    static let homeIDs:[TrainingKind:String]=[.contact:"homeContact",.power:"homePower",.discipline:"homeDiscipline",.speed:"homeSpeed",.defense:"homeDefense",.arm:"homeArm",.mental:"homeMental",.velocity:"homeVelocity",.control:"homeControl",.stuff:"homeStuff",.stamina:"homeStamina"]
}

struct CareerBalanceYear:Codable {
    let age:Int
    let values:[String:Double]
    let pitches:[String:Double]
    let roleGrades:[String:Double]
    let domesticAbilityRoles:Int
}
enum CareerBalanceSimulation {
    static func run(archetype:PlayerArchetype,score:Double=75,fatigue:Int=40,annualTrainings:Int=180) throws -> [CareerBalanceYear] {
        guard (0...100).contains(score),(0...100).contains(fatigue),(0...365).contains(annualTrainings) else {throw TrainingError.invalidInput}
        let initial=archetype.values,role=archetype.role
        var values:[TrainingKind:Double]=[.contact:initial.contact,.power:initial.power,.discipline:initial.discipline,.speed:initial.speed,.defense:initial.defense,.arm:initial.arm,.mental:initial.mental]
        if role == .pitcher {values[.velocity]=initial.velocity;values[.control]=initial.control;values[.stuff]=initial.stuff;values[.stamina]=initial.stamina}
        var pitches=initial.pitches,output:[CareerBalanceYear]=[]
        let selected:[TrainingKind]=role == .batter ? [.contact,.power,.discipline,.speed,.defense,.arm,.mental]:[.velocity,.control,.stuff,.stamina,.mental]
        let pitchKeys=pitches.keys.sorted()
        for age in 16...40 {
            for (kind,value) in values {values[kind]=CareerAgingRules.value(value,kind:kind,age:age)}
            for (key,value) in pitches {pitches[key]=CareerAgingRules.value(value,kind:.pitch,age:age,pitch:true)}
            for step in 0..<annualTrainings {
                let i=step%(selected.count+pitchKeys.count)
                if i<selected.count {let kind=selected[i];values[kind]=TrainingRules.growth(before:values[kind]!,score:score,fatigue:fatigue,age:age,pitch:false)}
                else {let key=pitchKeys[i-selected.count];pitches[key]=TrainingRules.growth(before:pitches[key]!,score:score,fatigue:fatigue,age:age,pitch:true)}
            }
            let raw=Dictionary(uniqueKeysWithValues:values.map {(CareerAgingRules.homeIDs[$0.key]!,$0.value)})
            let summary=HomeAbilitySummary(axes:[],originals:raw.map {HomeAbilityValue(id:$0.key,label:$0.key,current:$0.value,initial:nil)},pitches:pitches.map {HomeAbilityValue(id:$0.key,label:$0.key,current:$0.value,initial:nil)},hasInitialValues:false)
            let grades=try ScoutingRoleEvaluation.grades(role:role,abilities:summary,positionMastery:60)
            let gradeValues=Dictionary(uniqueKeysWithValues:grades.compactMap {g in g.score.map {(g.id,$0)}})
            output.append(CareerBalanceYear(age:age,values:raw,pitches:pitches,roleGrades:gradeValues,
                domesticAbilityRoles:grades.filter {grade in grade.score.map {$0 >= DomesticSelection.minimum(grade.id,route:.rookie)} ?? false}.count))
        }
        return output
    }
}


struct CareerAgeEvent:Codable,Equatable,Identifiable {
    let id:String
    let date:String
    let age:Int
    let before:[String:Double]
    let after:[String:Double]
}
struct CareerTraitLoss:Codable,Equatable,Identifiable {
    let id:String
    let date:String
    let trait:PlayerTrait
}
struct CareerRetirement:Codable,Equatable {
    let date:String
    let age:Int
    let reason:String
    let affiliation:String
    let games:Int
    let line:MatchLine
    let finalValues:[String:Double]
    let finalPitches:[String:Double]
}
struct CareerLifecycleState:Codable,Equatable {
    var version=1
    var adopted:String?
    var enforceAgeLimit=true
    var aging:[CareerAgeEvent]=[]
    var traitRisk:[String:String]=[:]
    var losses:[CareerTraitLoss]=[]
    var retirement:CareerRetirement?
    func validate(playerID:UUID,today:String) throws {
        guard version == 1,Set(aging.map(\.id)).count == aging.count,Set(losses.map(\.id)).count == losses.count else {throw CareerLifecycleError.invalid}
        if let adopted {guard try GameDate(adopted) <= GameDate(today) else {throw CareerLifecycleError.invalid}}
        for event in aging {
            guard (31...40).contains(event.age),event.date <= today,event.id == playerID.uuidString+":aging-v1:"+event.date,
                  Set(event.before.keys) == Set(event.after.keys),event.before.values.allSatisfy({$0.isFinite && (0...100).contains($0)}),
                  event.after.allSatisfy({k,v in v.isFinite && v>=0 && v <= event.before[k]!}) else {throw CareerLifecycleError.invalid}
        }
        for (key,date) in traitRisk {guard PlayerTrait(rawValue:key) != nil,date <= today,adopted.map({$0 <= date}) ?? false else {throw CareerLifecycleError.invalid}}
        if let retired=retirement {guard retired.date == today,retired.age>=20,retired.games>=0,["voluntary","age-limit"].contains(retired.reason) else {throw CareerLifecycleError.invalid}}
    }
}
enum CareerLifecycleError:LocalizedError {
    case invalid,retired,pending,tooYoung,horizon
    var errorDescription:String? {
        switch self {
        case .invalid:"커리어 변화 기록을 확인할 수 없습니다. 기존 저장은 유지됩니다."
        case .retired:"은퇴한 커리어는 기록 열람만 가능합니다. 새 커리어를 시작해 주세요."
        case .pending:"진행 중인 경기·훈련·평가전을 먼저 마쳐 주세요."
        case .tooYoung:"자율 은퇴는 게임 나이 20세부터 가능합니다."
        case .horizon:"41세 기념일 이후까지 이어지는 새 계약은 체결할 수 없습니다."
        }
    }
}


// Selection is a weekly roster decision, separate from a match's simulation and rewards.
struct ClubSelectionCandidate: Codable, Equatable, Identifiable {
    let id: String
    let h: Double
    let p: Double
    let readiness: Double
    let evidence: String?
    let note: String
    var performance: Double { max(10, min(90, 50 + 10 * p)) }
    var score: Double { 0.60 * h + 0.25 * performance + 0.15 * readiness }
    func validate() throws {
        guard !id.isEmpty, h.isFinite, (0...100).contains(h), p.isFinite, (-4...4).contains(p),
              readiness.isFinite, (0...100).contains(readiness), !note.isEmpty,
              evidence != nil || p == 0 else { throw ContractRegistrationError.invalid }
    }
}
struct ClubSelectionReview: Codable, Equatable, Identifiable {
    var version = 1
    let context: String
    let membershipID: String
    let teamID: String
    let level: String
    let position: String
    let roleID: String
    let date: String
    let week: String
    let own: ClubSelectionCandidate
    let rival: ClubSelectionCandidate
    let incumbent: String
    let selected: String
    let holdUntil: String?
    var id: String { context + "/" + week }
    var isStarter: Bool { selected == own.id }
    var nextReview: String {
        (try? GameDate(week).adding(days: 7).description) ?? week
    }
    var reason: String {
        if let holdUntil, date < holdUntil, incumbent == selected { return "기용 변경 후 관찰 중 · " + holdUntil + "까지 유지" }
        if selected != incumbent { return "도전자가 기존 선수보다 출전점수 5 이상 높음" }
        return "동률 또는 점수 차 5 미만 · 기존 기용 유지"
    }
    static func make(context: String, membershipID: String, teamID: String, level: String, position: String, roleID: String,
                     date: GameDate, own: ClubSelectionCandidate, rival: ClubSelectionCandidate, previous: Self?) throws -> Self {
        let incumbent = previous?.selected ?? own.id
        let held = previous?.holdUntil.map { date.description < $0 } ?? false
        let current = incumbent == own.id ? own : rival
        let challenger = incumbent == own.id ? rival : own
        let selected = !held && challenger.score >= current.score + 5 ? challenger.id : incumbent
        let until = selected != incumbent ? date.adding(days: 14).description : previous?.holdUntil
        let value = Self(context: context, membershipID: membershipID, teamID: teamID, level: level, position: position, roleID: roleID,
                         date: date.description, week: date.monday.description, own: own, rival: rival, incumbent: incumbent, selected: selected, holdUntil: until)
        try value.validate(previous: previous)
        return value
    }
    func validate(previous: Self?) throws {
        let day = try GameDate(date)
        try own.validate(); try rival.validate()
        guard version == 1, week == day.monday.description,
              context == [membershipID,teamID,level,String(day.year),position].joined(separator:"/"),
              !membershipID.isEmpty, !teamID.isEmpty,
              ["domestic-development", "domestic-first-team", "mlb-development", "npb-first-team", "mlb-first-team"].contains(level),
              (position == "P" || FieldPosition(rawValue: position) != nil), ["slugger", "onBase", "field", "starter"].contains(roleID),
              own.id != rival.id, incumbent == (previous?.selected ?? own.id),
              previous.map({ $0.context == context && $0.week < week && $0.own.id == own.id && $0.rival.id == rival.id }) ?? true else { throw ContractRegistrationError.invalid }
        let held = previous?.holdUntil.map { date < $0 } ?? false
        let current = incumbent == own.id ? own : rival, challenger = incumbent == own.id ? rival : own
        let expected = !held && challenger.score >= current.score + 5 ? challenger.id : incumbent
        guard selected == expected, holdUntil == (selected != incumbent ? day.adding(days:14).description : previous?.holdUntil) else { throw ContractRegistrationError.invalid }
    }
}
struct MatchClubSelection: Codable, Equatable {
    let fixtureID: String
    let review: ClubSelectionReview
    let rotationDay: Bool
    var appearance: Bool { rotationDay && review.isStarter }
    func validate(fixtureID: String, playerID: UUID, date: String, competition: String?, appearance: Bool, role: String) throws {
        try review.own.validate(); try review.rival.validate()
        let day=try GameDate(date), opening=try GameDate("\(day.year)-04-01")
        let expectedTurn=role == "batter" || (opening.days(to:day)/6).isMultiple(of:5)
        guard review.version == 1, review.week == day.monday.description, rotationDay == expectedTurn,
              [review.own.id,review.rival.id].contains(review.selected),
              self.fixtureID == fixtureID, review.own.id == playerID.uuidString, review.date <= date,
              review.level == competition, self.appearance == appearance else { throw MatchError.invalidRecord }
    }
}
struct ClubOpportunitySummary: Codable, Equatable {
    let through: String
    let keys: [String]
    let starts: Int
    let bench: Int
    let rotationRest: Int
    func validate() throws {
        _ = try GameDate(through)
        guard Set(keys).count == keys.count, keys == keys.sorted(), starts >= 0, bench >= 0, rotationRest >= 0,
              starts + bench + rotationRest == keys.count else { throw ScoutingObservationError.invalid }
    }
}
