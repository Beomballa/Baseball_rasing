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
        case .preparationRequired: "오늘 훈련 또는 휴식 1회를 먼저 마쳐 주세요. 진행 중인 훈련은 이어서 완료해 주세요."
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
    var coverage:PersonalSeasonCoverage? = nil
    // A legacy partial season is not a completed 30-game season.
    var finalized:Bool {league.isComplete}
    var finalStandings:[LeagueStanding] {league.displayStandings}
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
    var development:PlayerDevelopment?
    func validate(playerID:UUID,today:String) throws {
        guard version == 1,Set(aging.map(\.id)).count == aging.count,Set(losses.map(\.id)).count == losses.count else {throw CareerLifecycleError.invalid}
        try development?.validate(playerID:playerID,today:today)
        if let adopted {guard try GameDate(adopted) <= GameDate(today) else {throw CareerLifecycleError.invalid}}
        for event in aging {
            guard ((31...40).contains(event.age) && event.id == playerID.uuidString+":aging-v1:"+event.date) || ((27...40).contains(event.age) && development.map {event.date>$0.adopted} == true && event.id == playerID.uuidString+":aging-v2:"+event.date) else {throw CareerLifecycleError.invalid}
            guard event.date <= today,
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
    var neutralPerformance:Bool?
    func score(_ candidate:ClubSelectionCandidate) -> Double {neutralPerformance == true ? 0.60*candidate.h+0.25*50+0.15*candidate.readiness:candidate.score}
    var ownScore:Double {score(own)}
    var rivalScore:Double {score(rival)}
    var rivalAbilities:PlayerInitialValues? = nil
    var rivalPositionMastery:Double? = nil
    var rivalEvidence: NPCSelectionEvidence? = nil
    var id: String { context + "/" + week }
    var isStarter: Bool { selected == own.id }
    var nextReview: String {
        (try? GameDate(week).adding(days: 7).description) ?? week
    }
    var reason: String {
        if neutralPerformance == true {return "공식 성과 표본 미확인 · 양쪽 성과 중립 비교 / 5점 차·14일 관찰 유지"}
        if let holdUntil, date < holdUntil, incumbent == selected { return "기용 변경 후 관찰 중 · " + holdUntil + "까지 유지" }
        if selected != incumbent { return "도전자가 기존 선수보다 출전점수 5 이상 높음" }
        return "동률 또는 점수 차 5 미만 · 기존 기용 유지"
    }
    static func make(context: String, membershipID: String, teamID: String, level: String, position: String, roleID: String,
                     date: GameDate, own: ClubSelectionCandidate, rival: ClubSelectionCandidate, previous: Self?, rivalAbilities:PlayerInitialValues?=nil, rivalPositionMastery:Double?=nil, rivalEvidence:NPCSelectionEvidence?=nil,neutralPerformance:Bool?=nil) throws -> Self {
        let incumbent = previous?.selected ?? own.id
        let held = previous?.holdUntil.map { date.description < $0 } ?? false
        let current = incumbent == own.id ? own : rival
        let challenger = incumbent == own.id ? rival : own
        func score(_ c:ClubSelectionCandidate) -> Double {neutralPerformance == true ? 0.6*c.h+12.5+0.15*c.readiness:c.score}
        let selected = !held && score(challenger) >= score(current) + 5 ? challenger.id : incumbent
        let until = selected != incumbent ? date.adding(days: 14).description : previous?.holdUntil
        var value = Self(context: context, membershipID: membershipID, teamID: teamID, level: level, position: position, roleID: roleID,
                         date: date.description, week: date.monday.description, own: own, rival: rival, incumbent: incumbent, selected: selected, holdUntil: until)
        value.neutralPerformance=neutralPerformance
        value.rivalAbilities=rivalAbilities;value.rivalPositionMastery=rivalPositionMastery;value.rivalEvidence=rivalEvidence
        try value.validate(previous: previous)
        return value
    }
    func validateRivalBasis() throws {
        guard neutralPerformance == nil || (neutralPerformance == true && own.evidence == nil && ["mlb-development","npb-first-team","mlb-first-team"].contains(level)) else {throw ContractRegistrationError.invalid}
        try rivalEvidence?.validate(review:self)
        guard let values=rivalAbilities else {guard rivalPositionMastery == nil else {throw ContractRegistrationError.invalid};return}
        guard let mastery=rivalPositionMastery,mastery.isFinite,(0...100).contains(mastery),
              roleID != "starter" || [values.velocity,values.control,values.stuff,values.stamina].allSatisfy({$0 != nil}) else {throw ContractRegistrationError.invalid}
        let role:PlayerRole=roleID == "starter" ? .pitcher:.batter
        let score=try ScoutingRoleEvaluation.grades(role:role,abilities:ScoutingClubCatalog.abilities(values,role:role),positionMastery:mastery).first {$0.id == roleID}?.score
        guard score == rival.h else {throw ContractRegistrationError.invalid}
    }
    func validate(previous: Self?) throws {
        let day = try GameDate(date)
        try own.validate(); try rival.validate();try validateRivalBasis()
        guard neutralPerformance == nil || (neutralPerformance == true && own.evidence == nil && ["mlb-development","npb-first-team","mlb-first-team"].contains(level)) else {throw ContractRegistrationError.invalid}
        guard version == 1, week == day.monday.description,
              context == [membershipID,teamID,level,String(day.year),position].joined(separator:"/"),
              !membershipID.isEmpty, !teamID.isEmpty,
              ["domestic-development", "domestic-first-team", "mlb-development", "npb-first-team", "mlb-first-team"].contains(level),
              (position == "P" || FieldPosition(rawValue: position) != nil), ["slugger", "onBase", "field", "starter"].contains(roleID),
              own.id != rival.id, incumbent == (previous?.selected ?? own.id),
              previous.map({ $0.context == context && $0.week < week && $0.own.id == own.id && $0.rival.id == rival.id }) ?? true else { throw ContractRegistrationError.invalid }
        let held = previous?.holdUntil.map { date < $0 } ?? false
        let current = incumbent == own.id ? own : rival, challenger = incumbent == own.id ? rival : own
        let expected = !held && score(challenger) >= score(current) + 5 ? challenger.id : incumbent
        guard selected == expected, holdUntil == (selected != incumbent ? day.adding(days:14).description : previous?.holdUntil) else { throw ContractRegistrationError.invalid }
    }
}
struct MatchClubSelection: Codable, Equatable {
    let fixtureID: String
    let review: ClubSelectionReview
    let rotationDay: Bool
    var appearance: Bool { rotationDay && review.isStarter }
    func validate(fixtureID: String, playerID: UUID, date: String, competition: String?, appearance: Bool, role: String) throws {
        try review.own.validate(); try review.rival.validate();try review.validateRivalBasis()
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


// Workload observes completed official counts; it never changes match execution or rewards.
struct MatchNPCReadiness: Codable, Equatable {
    var version = 1
    let date: String
    let players: [NPCReadinessPlayer]
    func validate(match: CareerMatch, date: String) throws {
        guard version == 1, self.date == date, let attack=match.npcAttack, attack.version == 2,
              match.playerRecords != nil, match.controlVersion == 2, match.detailedFieldVersion == 5,
              match.battedBallVersion == 1 else {throw MatchError.invalidRecord}
        _ = try GameDate(date)
        let expected=Set([attack.home,attack.away].flatMap {team in
            team.batters.map(\.id)+[team.starter.id,team.relief.id]
        })
        guard Set(players.map(\.id)) == expected, players.count == expected.count else {throw MatchError.invalidRecord}
        for player in players {
            guard player.fatigue.isFinite,(0...100).contains(player.fatigue) else {throw MatchError.invalidRecord}
        }
    }
    func cost(for id: String, match: CareerMatch) -> Double {
        guard match.completed, let attack=match.npcAttack,let records=match.playerRecords else {return 0}
        var cost=0.0
        for (team,counts) in [(attack.home,records.home),(attack.away,records.away)] {
            cost += Double(counts.batting.first {$0.id == id}?.counts.plateAppearances ?? 0)
            if let pitcher=[team.starter,team.relief].first(where:{$0.id == id}),let profile=pitcher.profile {
                let pitchCost=MatchAbilityStats(mental:profile.mental,velocity:pitcher.velocity,control:pitcher.control,stuff:profile.stuff,stamina:profile.stamina,fatigue:0).pitchCost
                cost += Double(counts.pitching.first {$0.id == id}?.counts.pitches ?? 0)*pitchCost
            }
        }
        return TrainingRules.round(cost)
    }
    func fatigue(for id:String, match:CareerMatch, on date:GameDate) throws -> Double {
        guard let before=players.first(where:{$0.id == id}),date >= (try GameDate(self.date)) else {throw MatchError.invalidRecord}
        let days=try GameDate(self.date).days(to:date),load=cost(for:id,match:match)
        let after=min(100,before.fatigue+load)
        guard days > 0 else {return after}
        let firstRecovery=Double(DailyRecovery.sleep+(load == 0 ? DailyRecovery.rest:0))
        return TrainingRules.round(max(0,after-firstRecovery-Double(days-1)*Double(DailyRecovery.sleep+DailyRecovery.rest)))
    }
}
struct NPCReadinessPlayer: Codable, Equatable {
    let id: String
    let fatigue: Double
}

struct NPCSelectionPerformance: Codable, Equatable {
    let environment: String
    let fixtures: [String]
    let games: Int
    let batting: MatchBattingCounts
    let pitching: MatchPitchingCounts
    let peerBatting: MatchBattingCounts
    let peerPitching: MatchPitchingCounts
    let peerPlayers: Int
    var isPitcher: Bool {environment.hasSuffix("/P")}
    var sample: Int {isPitcher ? pitching.battersFaced:batting.plateAppearances}
    var enough: Bool {
        peerPlayers >= 2 && (isPitcher ? pitching.outs >= 45 && peerPitching.outs >= 45:batting.plateAppearances >= 40 && peerBatting.plateAppearances >= 40)
    }
    private func contribution(_ batting:MatchBattingCounts,_ pitching:MatchPitchingCounts) -> Double {
        if isPitcher {return pitching.battersFaced == 0 ? 0:Double(pitching.strikeouts-pitching.walks-2*pitching.homeRuns)/Double(pitching.battersFaced)}
        let numerator=Double(batting.walks)*0.7+Double(batting.singles)*0.9+Double(batting.doubles)*1.3+Double(batting.triples)*1.7+Double(batting.homeRuns)*2-Double(batting.strikeouts)*0.25
        return batting.plateAppearances == 0 ? 0:numerator/Double(batting.plateAppearances)
    }
    var correction: Double {
        enough ? ScoutingContractFit.correction(value:contribution(batting,pitching),reference:contribution(peerBatting,peerPitching),n:sample):0
    }
    func validate() throws {
        try batting.validate();try pitching.validate();try peerBatting.validate();try peerPitching.validate()
        guard environment.hasPrefix("npc-selection-v1/"),games>=0,peerPlayers>=0,
              games<=fixtures.count,fixtures == Array(Set(fixtures)).sorted() else {throw ContractRegistrationError.invalid}
    }
}
struct NPCSelectionEvidence: Codable, Equatable {
    var version = 1
    let through: String
    let performance: NPCSelectionPerformance?
    let fatigue: Double
    let trackingSince: String?
    let lastWorkloadKey: String?
    let lastWorkloadDate: String?
    let lastCost: Double?
    var p: Double {performance?.correction ?? 0}
    var source: String? {performance.map {$0.environment+"/through/"+through}}
    func validate(review:ClubSelectionReview) throws {
        guard version == 1,try GameDate(through) == GameDate(review.date).adding(days:-1),
              fatigue.isFinite,(0...100).contains(fatigue),review.rival.readiness == 100-fatigue,
              review.rival.p == p,review.rival.evidence == source else {throw ContractRegistrationError.invalid}
        try performance?.validate()
        if let performance {
            guard performance.environment.hasPrefix("npc-selection-v1/"+review.level+"/"),
                  performance.environment.hasSuffix("/"+review.position) else {throw ContractRegistrationError.invalid}
        }
        if let trackingSince, let lastWorkloadDate, let lastWorkloadKey,let lastCost {
            guard !lastWorkloadKey.isEmpty,try GameDate(trackingSince) <= GameDate(lastWorkloadDate),
                  try GameDate(lastWorkloadDate) <= GameDate(through),lastCost.isFinite,lastCost>=0 else {throw ContractRegistrationError.invalid}
        } else {
            guard trackingSince == nil,lastWorkloadDate == nil,lastWorkloadKey == nil,lastCost == nil,fatigue == 0 else {throw ContractRegistrationError.invalid}
        }
    }
}


// Read-only coaching: saved decision scores and live training advice have separate time bases.
struct ClubCoachDeficit: Equatable, Identifiable {
    let kind: TrainingKind
    let current: Double
    let reference: Double
    let roleImpact: Double
    var id:String {kind.rawValue}
    var gap:Double {reference-current}
}
struct ClubCoachFeedback {
    let review:ClubSelectionReview
    let nextEvaluation:String
    let reconsideration:String
    let deficits:[ClubCoachDeficit]
    var scoreGap:Double {review.ownScore-review.rivalScore}
    var pointsToChallenge:Double {max(0,review.rivalScore+5-review.ownScore)}
    var hasAbilityBasis:Bool {review.rivalAbilities != nil}
    static func dates(review:ClubSelectionReview,on date:GameDate) throws -> (next:String,change:String) {
        func scheduled(_ day:GameDate) throws -> GameDate {
            let opening=try GameDate("\(day.year)-04-01"),closing=try GameDate("\(day.year)-09-22")
            if day<opening {return opening}
            return day>closing ? try GameDate("\(day.year+1)-04-01"):day
        }
        guard date >= (try GameDate(review.date)) else {throw ContractRegistrationError.invalid}
        let upcoming=max(try GameDate(review.nextReview),date.monday.adding(days:7))
        let next=try scheduled(upcoming)
        var change=next
        if let hold=review.holdUntil {
            while change < (try GameDate(hold)) {change=try scheduled(change.adding(days:7))}
        }
        return (next.description,change.description)
    }
    static func make(review:ClubSelectionReview,abilities:HomeAbilitySummary,role:PlayerRole,mastery:Double?,on date:GameDate) throws -> Self {
        try review.own.validate();try review.rival.validate();try review.validateRivalBasis()
        guard (role == .pitcher) == (review.roleID == "starter") else {throw ContractRegistrationError.invalid}
        let dates=try dates(review:review,on:date)
        guard let reference=review.rivalAbilities else {return Self(review:review,nextEvaluation:dates.next,reconsideration:dates.change,deficits:[])}
        let target=ScoutingClubCatalog.abilities(reference,role:role)
        guard let base=try ScoutingRoleEvaluation.grades(role:role,abilities:abilities,positionMastery:mastery).first(where:{$0.id == review.roleID})?.score else {throw ScoutingObservationError.invalid}
        var deficits:[ClubCoachDeficit]=[]
        for kind in TrainingKind.allCases where kind != .pitch && kind.allows(role.rawValue) {
            guard let id=CareerAgingRules.homeIDs[kind],let own=abilities.originals.first(where:{$0.id == id}),
                  let rival=target.originals.first(where:{$0.id == id}),rival.current>own.current else {continue}
            let replaced=abilities.originals.map {$0.id == id ? HomeAbilityValue(id:$0.id,label:$0.label,current:rival.current,initial:$0.initial):$0}
            let changed=HomeAbilitySummary(axes:abilities.axes,originals:replaced,pitches:abilities.pitches,hasInitialValues:abilities.hasInitialValues)
            guard let h=try ScoutingRoleEvaluation.grades(role:role,abilities:changed,positionMastery:mastery).first(where:{$0.id == review.roleID})?.score,h>base else {continue}
            deficits.append(ClubCoachDeficit(kind:kind,current:own.current,reference:rival.current,roleImpact:h-base))
        }
        deficits.sort {$0.roleImpact == $1.roleImpact ? $0.id<$1.id:$0.roleImpact>$1.roleImpact}
        return Self(review:review,nextEvaluation:dates.next,reconsideration:dates.change,deficits:Array(deficits.prefix(3)))
    }
}

enum ClubCoachActionState: Equatable {
    case available,resume,used,blocked(String)
    var canTrain:Bool {self == .available}
    var canRest:Bool {self == .available}
    var message:String {
        switch self {
        case .available:"오늘 행동을 선택할 수 있습니다. 준비 화면에서 확인한 뒤 시작하세요."
        case .resume:"진행 중인 훈련을 먼저 이어서 마쳐 주세요. 저장된 종목과 시도를 유지합니다."
        case .used:"오늘 행동을 사용했습니다. 오늘 경기를 마치거나 다음 일정으로 진행한 뒤 준비하세요."
        case .blocked(let reason):reason
        }
    }
}

// Read-only daily copy: team schedule, personal appearance and the daily action are independent.
enum CalendarSavedMatch: Equatable {
    case none, playing(Bool), completed(Bool), invalid
    @MainActor static func read(_ record: CareerMatchRecord?) -> Self {
        guard let record else {return .none}
        guard let game=try? record.snapshot() else {return .invalid}
        return game.completed ? .completed(game.appearance):.playing(game.appearance)
    }
}
struct CalendarDayPresentation: Equatable {
    let team: String
    let participation: String
    let action: String
    let entry: String
    var summary: String { [team,participation,action].joined(separator:" · ") }
    init(role:PlayerRole,fixture:SeasonFixture?,saved:CalendarSavedMatch,starter:Bool?,selectionFailed:Bool,actionUsed:Bool,trainingPending:Bool) {
        action=trainingPending ? "훈련 진행 중":actionUsed ? "행동 0/1":"행동 1/1"
        guard let fixture else {team="팀 경기 없음";participation="훈련·휴식일";entry="다음 일정 확인";return}
        switch saved {
        case .completed(let appeared):team="팀 경기 완료";participation=appeared ? "내 출전 완료":"내 출전 없음";entry="경기 결과 보기"
        case .playing(let appeared):team="팀 경기 진행 중";participation=appeared ? "내 경기 이어하기":"내 출전 없음";entry=appeared ? "경기 이어하기":"팀 경기 이어하기"
        case .invalid:team="팀 경기 있음";participation="경기 기록 확인 필요";entry="경기 기록 확인"
        case .none:
            team="팀 경기 있음"
            if selectionFailed {participation="기용 확인 필요";entry="기용 다시 확인"}
            else if !fixture.isAppearance(for:role) {participation="비등판일";entry="팀 경기 진행"}
            else if starter == false {participation="오늘 벤치";entry="팀 경기 진행"}
            else {participation=role == .pitcher ? "선발 등판 예정":"타자 출전 예정";entry="오늘 경기 준비"}
        }
    }
}

struct PersonalSeasonCoverage: Equatable {
    private(set) var games=0,collectedGames=0,earnedRunGames=0,unscoredPitchingGames=0
    private(set) var batting=MatchBattingCounts()
    private(set) var pitching=MatchPitchingCounts(earnedRuns:0)
    var missingGames:Int {games-collectedGames}
    var complete:Bool {games>0 && games == collectedGames}
    mutating func include(_ match:CareerMatch,playerID:UUID) {
        games += 1
        guard let ledger=match.playerRecords else {return}
        let team=match.isHome ? ledger.home:ledger.away,id=playerID.uuidString
        if match.role == "batter",let counts=team.batting.first(where:{$0.id == id})?.counts {
            collectedGames += 1;batting.add(counts)
        } else if match.role == "pitcher",let counts=team.pitching.first(where:{$0.id == id})?.counts {
            collectedGames += 1;pitching.add(counts)
            if counts.earnedRuns == nil {unscoredPitchingGames += 1} else {earnedRunGames += 1}
        }
    }
    func value(_ code:String,partial:Bool=false) -> String {
        guard (partial ? collectedGames>0:complete) else {return "미집계"}
        return MatchOpponentSeasonPlayer(id:"personal",battingGames:collectedGames,pitchingGames:collectedGames,
            earnedRunGames:earnedRunGames,unscoredPitchingGames:unscoredPitchingGames,batting:batting,pitching:pitching).value(code)
    }
    var label:String {"개인 출전 \(games)경기 · 상세 수집 \(collectedGames) · 미수집 \(missingGames)"}
}

extension AnnualLeague {
    var isComplete:Bool {fixtures.count == 90 && results.count == 90 && pendingIDs.isEmpty && standings.count == 6 && standings.allSatisfy {$0.games == 30}}
    var displayStandings:[LeagueStanding] {
        guard isComplete,standings.allSatisfy({$0.decided == 0}) else {return standings}
        return standings.map {var row=$0;row.rank=1;return row}
    }
}
enum LeagueRecordSource {
    static func label(automatic:Bool,ownTeam:Bool) -> String {
        automatic ? (ownTeam ? "내 팀 자동 결과":"다른 팀 자동 경기") : "내 팀 경기 원장"
    }
}
extension OffseasonPlan {
    var transitionNotice:String? {
        if age<=18 && targetAge>=19 {return "고교 졸업·진로준비 시기입니다. 프로·대학 입단은 별도 선발과 계약이 필요합니다."}
        if age<20 && targetAge>=20 {return "20세 진로 심사 시기입니다. 현재 소속·보유 권리와 실제 제의에 따라 진로가 결정됩니다."}
        return nil
    }
}
