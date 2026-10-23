import Foundation

enum ScoutingInterestLevel: String, Codable {
    case observing, focused, priority
    var label: String {switch self {case .observing:"관찰 관심";case .focused:"집중 관찰";case .priority:"우선 관찰"}}
    static func at(_ fit: Double) -> Self? {fit >= 0 ? .priority : fit >= -3 ? .focused : fit >= -8 ? .observing:nil}
}
struct ScoutingClubInterest: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let roleID: String
    let roleLabel: String
    let level: ScoutingInterestLevel
    let fit: Double
    let reasons: [String]
}
struct ScoutingInterests: Codable, Equatable {
    var version = 1
    let entries: [ScoutingClubInterest]
    let pendingReasons: [String]
    static func make(_ observation: ScoutingObservation) -> Self {
        guard let fit=observation.contractFit else {return Self(entries:[],pendingReasons:["계약 적합도 자료가 필요합니다."])}
        let source=fit.comparisons.first{$0.id == fit.selectedEnvironment && $0.verified}
        let enough=source.map{observation.role == .batter ? $0.totals.line.plateAppearances >= 40:$0.totals.line.pitchingOuts >= 45} ?? false
        var best=[String:ScoutingClubInterest]()
        for club in fit.clubs {
            guard enough, let source, club.recruitment.demand != .none, let f=club.f, let level=ScoutingInterestLevel.at(f),
                  let h=club.h, let c=club.c,
                  let grade=observation.grades.first(where:{$0.id == club.recruitment.roleID}) else {continue}
            if club.recruitment.roleID == "field" && ((observation.positionMastery ?? -1) < 70 || (observation.abilities.originals.first{$0.id == "homeDefense"}?.current ?? -1) < 70) {continue}
            guard let key=club.id.split(separator:"/").first else {continue}
            let id=String(key)
            func number(_ n:Double) -> String {String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),n)}
            let interest=ScoutingClubInterest(id:id,name:club.recruitment.name,roleID:grade.id,roleLabel:grade.label,
                level:level,fit:f,reasons:["\(club.recruitment.demand.label) · \(grade.label) 모집",
                    "역할 기량 \(number(h)) / 구단 기준 \(number(c)) · 적합도 \(number(f))",
                    "동일 환경 \(observation.role == .batter ? "\(source.totals.line.plateAppearances)타석":"\(source.totals.innings)이닝") · 성적 보정 \(number(club.p))"])
            if let old=best[id], old.fit > f || (old.fit == f && old.roleID < grade.id) {continue}
            best[id]=interest
        }
        let entries=best.values.sorted{$0.fit == $1.fit ? $0.id < $1.id:$0.fit > $1.fit}
        var pending=[String]()
        if source == nil {pending.append("검증된 동일 환경 성적이 필요합니다.")}
        if !enough {pending.append(observation.role == .batter ? "관찰 표본 40타석이 필요합니다.":"관찰 표본 15이닝이 필요합니다.")}
        if entries.isEmpty && enough {pending.append("모집 중이며 적합도·역할 조건을 충족한 역할이 없습니다.")}
        return Self(entries:entries,pendingReasons:pending)
    }
}

enum ScoutingInputMode: String, Codable, CaseIterable {
    case automatic, direct, mixed
    var suffix: String { switch self {case .automatic: "auto-v2";case .direct: "direct-v1";case .mixed: "mixed-v1"} }
    var label: String { switch self {case .automatic: "자동";case .direct: "직접";case .mixed: "직접+자동"} }
}
struct ScoutingInputUsage: Codable, Equatable {
    var direct = 0, automatic = 0
    var mode: ScoutingInputMode { direct == 0 ? .automatic : automatic == 0 ? .direct : .mixed }
    mutating func record(direct: Bool) {if direct {self.direct += 1} else {automatic += 1}}
    func validate() throws {
        guard (0...100_000).contains(direct), (0...100_000).contains(automatic) else {throw ScoutingObservationError.invalid}
    }
}

// Counts only completed personal plate appearances; never infer BF from outs (double plays/tag-ups).
struct MatchScoutingPerformance: Codable, Equatable {
    var version = 1
    var manual = false
    var inputs: ScoutingInputUsage?
    static var tracked: Self {var value=Self();value.version=2;value.inputs=ScoutingInputUsage();return value}
    var singles = 0, doubles = 0, homers = 0, sacrificeFlies = 0
    var battersFaced = 0, homersAllowed = 0
    mutating func record(_ result: String, batter: Bool, pitcher: Bool) {
        if batter {
            if result == "안타" { singles += 1 }
            if result == "2루타" { doubles += 1 }
            if result == "홈런" { homers += 1 }
            if result == "희생플라이" { sacrificeFlies += 1 }
        }
        if pitcher { battersFaced += 1; if result == "홈런" { homersAllowed += 1 } }
    }
    func validate(line: MatchLine, role: PlayerRole) throws {
        guard [1,2].contains(version), [singles,doubles,homers,sacrificeFlies,battersFaced,homersAllowed].allSatisfy({ (0...100_000).contains($0) }) else { throw ScoutingObservationError.invalid }
        if version == 1 {guard inputs == nil else {throw ScoutingObservationError.invalid}}
        else {
            guard let inputs, manual == (inputs.direct > 0) else {throw ScoutingObservationError.invalid}
            try inputs.validate()
            if role == .pitcher {guard inputs.direct+inputs.automatic == line.pitches else {throw ScoutingObservationError.invalid}}
        }
        var check = PersonalSeasonTotals(); try check.add(line)
        if role == .batter {
            guard singles+doubles+homers == line.hits, homers == line.homeRuns,
                  line.atBats+line.walks+sacrificeFlies == line.plateAppearances,
                  battersFaced == 0, homersAllowed == 0 else { throw ScoutingObservationError.invalid }
        } else {
            guard singles+doubles+homers+sacrificeFlies == 0,
                  homersAllowed <= line.hitsAllowed,
                  line.hitsAllowed+line.pitchingWalks+line.pitchingStrikeouts <= battersFaced,
                  line.pitchingOuts <= battersFaced*3 else { throw ScoutingObservationError.invalid }
        }
    }
    mutating func add(_ value: Self) throws {
        guard version == value.version else {throw ScoutingObservationError.invalid}
        if version == 2 {
            guard let own=inputs, let added=value.inputs else {throw ScoutingObservationError.invalid}
            inputs=ScoutingInputUsage(direct:own.direct+added.direct,automatic:own.automatic+added.automatic)
            try inputs?.validate()
        }
        let keys: [WritableKeyPath<Self,Int>] = [\.singles,\.doubles,\.homers,\.sacrificeFlies,\.battersFaced,\.homersAllowed]
        for key in keys {
            let sum = self[keyPath:key].addingReportingOverflow(value[keyPath:key])
            guard !sum.overflow, (0...100_000).contains(sum.partialValue) else { throw ScoutingObservationError.invalid }
            self[keyPath:key] = sum.partialValue
        }
        manual = manual || value.manual
    }
    func sample(_ line: MatchLine, role: PlayerRole) -> Int { role == .batter ? line.plateAppearances : battersFaced }
    func contribution(_ line: MatchLine, role: PlayerRole) -> Double? {
        let n = sample(line,role:role); guard n > 0 else { return nil }
        let numerator = role == .batter ? Double(line.walks)*0.7 + Double(singles)*0.9 + Double(doubles)*1.3 + Double(homers)*2 - Double(line.strikeouts)*0.25
            : Double(line.pitchingStrikeouts-line.pitchingWalks-2*homersAllowed)
        return numerator / Double(n)
    }
}

extension CareerMatch {
    var scoutingEnvironment: String? {
        guard let role = PlayerRole(rawValue:role), let perf = scoutingPerformance,
              controlVersion == 2, trainingEffectsVersion == 1, detailedFieldVersion == 5,
              abilityStats?.version == 1, pitching?.version == 1,
              fieldStats?.version == (role == .batter ? 3:2),
              let position = fieldStats?.position else { return nil }
        let batted=battedBallVersion.map {"-batted\($0)"} ?? ""
        return "\(competition ?? "highschool")/\(role.rawValue)/manual2-training1-field5-stats\(fieldStats!.version)-ability1-pitching1\(batted)-events\(perf.version)/\(position)/" + (perf.version == 2 ? (perf.inputs?.mode.suffix ?? "unknown") : perf.manual ? "manual-unverified":"auto-v1")
    }
}

struct ScoutingReference: Codable, Equatable {
    var version = 1
    let environment: String
    let role: PlayerRole
    let position: String
    let profiles: [PlayerInitialValues]
    let gamesPerProfile: Int
    let totals: PersonalSeasonTotals
    let performance: MatchScoutingPerformance
    var inputPolicy: String?
    var inputMode: ScoutingInputMode?
    var value: Double? { performance.contribution(totals.line,role:role) }
    func validate() throws {
        guard [1,2].contains(version), profiles.count == 3, gamesPerProfile == (role == .batter ? 20:6),
              totals.games == profiles.count*gamesPerProfile, value?.isFinite == true else { throw ScoutingObservationError.invalid }
        if version == 1 {
            guard performance.version == 1, !performance.manual, inputPolicy == nil, inputMode == nil,
                  environment.hasSuffix("/\(position)/auto-v1") else {throw ScoutingObservationError.invalid}
        } else {
            guard inputPolicy == "standard-controls-v1", let inputMode, performance.version == 2,
                  performance.inputs?.mode == inputMode,
                  environment.hasSuffix("/\(position)/"+inputMode.suffix) else {throw ScoutingObservationError.invalid}
        }
        try performance.validate(line:totals.line,role:role)
    }
}

@MainActor enum ScoutingReferenceSimulation {
    private static var cache: [String:ScoutingReference] = [:]
    static func make(environment: String, role: PlayerRole, position: String) throws -> ScoutingReference? {
        let mode=ScoutingInputMode.allCases.first{environment.hasSuffix("/"+$0.suffix)}
        let tracked=mode != nil
        guard (tracked || environment.hasSuffix("/auto-v1")), role == .pitcher ? position == "P" : FieldPosition(rawValue:position) != nil else { return nil }
        if let found = cache[environment] { return found }
        let profiles = PlayerArchetype.choices(for:role).map(\.values), count = role == .batter ? 20:6
        var totals = PersonalSeasonTotals(), performance = tracked ? MatchScoutingPerformance.tracked:MatchScoutingPerformance()
        for (index, profile) in profiles.enumerated() {
            for game in 0..<count {
                var match = fixture(role:role,position:position,values:profile,seed:UInt64(811_001+index*1_000+game),home:game%2 == 0,tracked:tracked,
                    battedBallVersion:environment.contains("-batted1-") ? 1:nil)
                // Empty input counts initially identify automatic; match rules/position must still match exactly.
                guard match.scoutingEnvironment?.components(separatedBy:"/").dropLast().joined(separator:"/") == environment.components(separatedBy:"/").dropLast().joined(separator:"/") else {return nil}
                try run(&match,mode:mode ?? .automatic)
                let result = match.scoutingPerformance!
                try result.validate(line:match.line,role:role)
                try totals.add(match.line);try performance.add(result)
            }
        }
        var reference = ScoutingReference(environment:environment,role:role,position:position,profiles:profiles,
            gamesPerProfile:count,totals:totals,performance:performance)
        if tracked {reference.version=2;reference.inputPolicy="standard-controls-v1";reference.inputMode=mode}
        try reference.validate();cache[environment] = reference;return reference
    }
    // The benchmark skill policy is unchanged across routes. Strategy and user precision are performance,
    // not copied into the NPC benchmark. Route equivalence is tested on complete event streams.
    static func run(_ match: inout CareerMatch, mode: ScoutingInputMode) throws {
        var pitches=0
        while !match.completed {
            if mode == .automatic || (mode == .mixed && pitches >= 8) || (match.role == "pitcher" && !match.ownPitcherActive) {
                try match.advance(.automatic);break
            }
            let action: MatchInput=match.role == "batter" ? .swing:.pitch, code=match.mastery.keys.sorted().first
            try match.advance(action,pitchCode:code,control:match.automaticControl(action,pitchCode:code))
            pitches += 1
        }
    }
    static func fixture(role: PlayerRole, position: String, values: PlayerInitialValues, seed: UInt64, home: Bool, tracked: Bool = false,battedBallVersion:Int?=nil) -> CareerMatch {
        var match = CareerMatch(random:seed,isHome:home,role:role.rawValue,appearance:true,
            contact:values.contact,power:values.power,discipline:values.discipline,mastery:values.pitches)
        match.controlVersion=2;match.trainingEffectsVersion=1;match.detailedFieldVersion=5
        match.battedBallVersion=battedBallVersion
        match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.abilityStats=MatchAbilityStats(mental:values.mental,velocity:values.velocity,control:values.control,stuff:values.stuff,stamina:values.stamina,fatigue:24)
        match.fieldStats=MatchFieldStats(speed:values.speed,defense:values.defense,arm:values.arm,position:position)
        match.fieldStats?.version=role == .batter ? 3:2;match.fieldStats?.activeTraits=[]
        if role == .batter {match.fieldStats?.positionMastery=60}
        match.pitching=MatchPitching(startingFatigue:24);match.scoutingPerformance=tracked ? .tracked:MatchScoutingPerformance()
        match.settle();return match
    }
}

enum RecruitmentDemand: String, Codable { case none, depth, vacancy
    var label: String { switch self {case .none:"모집 없음";case .depth:"뎁스 보강";case .vacancy:"주전 공석"} }
}
struct ClubRoleRecruitment: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let roleID: String
    let demand: RecruitmentDemand
    let leagueMinimum: Double
    let competitor: PlayerInitialValues?
    let confirmedEmpty: Bool
    func criterion(role: PlayerRole) throws -> Double? {
        guard leagueMinimum.isFinite,(0...100).contains(leagueMinimum),!(confirmedEmpty && competitor != nil) else {throw ScoutingObservationError.invalid}
        guard demand != .none else {return nil}
        guard let competitor else {return confirmedEmpty ? leagueMinimum:nil}
        if role == .pitcher, [competitor.velocity,competitor.control,competitor.stuff,competitor.stamina].contains(where:{$0 == nil}) {return nil}
        let abilities = ScoutingClubCatalog.abilities(competitor,role:role)
        guard let h = try ScoutingRoleEvaluation.grades(role:role,abilities:abilities,positionMastery:70).first(where:{$0.id == roleID})?.score else {return nil}
        return max(leagueMinimum,h+(demand == .depth ? 1:2))
    }
}

enum ScoutingClubCatalog {
    // Initial fictional domestic market. These are game data, not real club needs or league averages.
    static func roles(for role: PlayerRole) -> [ClubRoleRecruitment] {
        let names=["인천 하버스","대전 코멧츠","부산 타이즈","서울 스타즈","광주 폭시스","대구 팔콘스"]
        let ids=["harbors","comets","tides","stars","foxes","falcons"]
        let keys=role == .batter ? ["slugger","onBase","field"]:["starter"]
        let minimums=["slugger":65.0,"onBase":62.0,"field":58.0,"starter":65.0]
        return names.enumerated().flatMap { club,name in
            keys.enumerated().map { index,key in
                let demand:RecruitmentDemand = (club+index)%4 == 0 ? .none : (club+index)%3 == 0 ? .vacancy:.depth
                let level=Double(61+club+index*2)
                var values=PlayerInitialValues(contact:level,power:level,discipline:level,speed:level,defense:level,arm:level,mental:level,velocity:level,control:level,stuff:level,stamina:level)
                values.pitches=["four-seam":level,"slider":level,"changeup":level,"fork":level]
                let empty = club == 3 && index == 0
                let missing = club == 5 && index == 0
                return ClubRoleRecruitment(id:ids[club]+"/"+key,name:name,roleID:key,demand:demand,
                    leagueMinimum:minimums[key]!,competitor:empty || missing ? nil:values,confirmedEmpty:empty)
            }
        }
    }
    static func abilities(_ values: PlayerInitialValues, role: PlayerRole) -> HomeAbilitySummary {
        let entries:[(String,Double)] = (role == .batter ? [("homeContact",values.contact),("homePower",values.power),("homeDiscipline",values.discipline)]
            : [("homeVelocity",values.velocity ?? 0),("homeControl",values.control ?? 0),("homeStuff",values.stuff ?? 0),("homeStamina",values.stamina ?? 0)])
            + [("homeSpeed",values.speed),("homeDefense",values.defense),("homeArm",values.arm),("homeMental",values.mental)]
        return HomeAbilitySummary(axes:[],originals:entries.map {HomeAbilityValue(id:$0.0,label:$0.0,current:$0.1,initial:nil)},
            pitches:values.pitches.sorted{$0.key<$1.key}.map{HomeAbilityValue(id:$0.key,label:$0.key,current:$0.value,initial:nil)},hasInitialValues:false)
    }
}

struct ScoutingPerformanceComparison: Codable, Equatable, Identifiable {
    let id: String
    let totals: PersonalSeasonTotals
    let performance: MatchScoutingPerformance?
    let reference: ScoutingReference?
    let value: Double?
    let correction: Double
    let verified: Bool
    let reason: String
}
struct ScoutingClubFit: Codable, Equatable, Identifiable {
    let recruitment: ClubRoleRecruitment
    var id: String {recruitment.id}
    let h: Double?
    let c: Double?
    let p: Double
    let f: Double?
    let stage: String
    let blockers: [String]
}
struct ScoutingContractFit: Codable, Equatable {
    var version = 2
    var catalogVersion = "domestic-market-v1"
    let comparisons: [ScoutingPerformanceComparison]
    let selectedEnvironment: String?
    let clubs: [ScoutingClubFit]
    static func round(_ value: Double) -> Double {(value*10_000).rounded()/10_000}
    static func correction(value:Double,reference:Double,n:Int) -> Double {
        guard n > 0 else{return 0};return round(max(-4,min(4,20*(value-reference)*Double(n)/Double(n+200))))
    }
    static func stage(f:Double?) -> String {
        guard let f else{return "평가 자료 대기"}
        return f >= 0 ? "기량상 계약 후보" : f >= -3 ? "보완·테스트 구간" : f >= -8 ? "관찰 구간":"기량 보완 필요"
    }
    static func selected(_ rows:[ScoutingPerformanceComparison],role:PlayerRole) -> ScoutingPerformanceComparison? {
        rows.filter(\.verified).sorted {
            let left=$0.performance!.sample($0.totals.line,role:role),right=$1.performance!.sample($1.totals.line,role:role)
            return left == right ? $0.id < $1.id:left > right
        }.first
    }
    static func blockers(observation: ScoutingObservation, rule: ClubRoleRecruitment, h: Double?, c: Double?, source: ScoutingPerformanceComparison?) -> [String] {
        var result=["진로·권리/등록/예산 심사 전", "고교 성적 참고 · 프로 즉시 전력 표본과 구분"]
        if observation.age < 20 {result.append("20세 미만 · 정식 제의 대상 아님")}
        if rule.demand == .none {result.append("현재 해당 역할 모집 없음")}
        if rule.demand != .none && c == nil {result.append("경쟁자 자료 미확인")}
        if h == nil {result.append("역할 기량 자료 부족")}
        if source == nil {result.append("성적 비교 미검증 · P=0 중립")}
        let enough=source.map{observation.role == .batter ? $0.totals.line.plateAppearances >= 40:$0.totals.line.pitchingOuts >= 45} ?? false
        if !enough {result.append("검증된 동일 환경의 관찰 최소 표본 미달")}
        if rule.roleID == "field" {
            if (observation.positionMastery ?? -1) < 70 {result.append("주 포지션 숙련70 필요")}
            if (observation.abilities.originals.first{$0.id == "homeDefense"}?.current ?? -1) < 70 {result.append("원본 수비70 필요")}
        }
        return result
    }
    @MainActor static func make(_ observation: ScoutingObservation) throws -> Self {
        let rows = try observation.groups.map { group -> ScoutingPerformanceComparison in
            let perf=group.performance
            let ref=try ScoutingReferenceSimulation.make(environment:group.id,role:observation.role,position:observation.role == .batter ? observation.position:"P")
            let v=perf?.contribution(group.totals.line,role:observation.role)
            let verified=(perf?.version == 2 || perf?.manual == false) && ref?.value != nil && v != nil
            let p=verified ? correction(value:v!,reference:ref!.value!,n:perf!.sample(group.totals.line,role:observation.role)):0
            return ScoutingPerformanceComparison(id:group.id,totals:group.totals,performance:perf,reference:ref,value:v,
                correction:p,verified:verified,reason:verified ? "같은 엔진·고교 수준 · \(perf?.inputs?.mode.label ?? "자동") / 표준 NPC 입력 기준" : perf == nil ? "과거 경기의 사건 지표 미기록 · P=0 중립" : "직접 조작/미지원 환경 비교 미검증 · P=0 중립")
        }
        let source=selected(rows,role:observation.role),p=source?.correction ?? 0
        let clubs=try ScoutingClubCatalog.roles(for:observation.role).map { rule -> ScoutingClubFit in
            let h=observation.grades.first{$0.id == rule.roleID}?.score,c=try rule.criterion(role:observation.role)
            let f=h.flatMap{h in c.map{round(h-$0+p)}}
            return ScoutingClubFit(recruitment:rule,h:h,c:c,p:p,f:f,stage:rule.demand == .none ? "모집 없음":stage(f:f),
                blockers:blockers(observation:observation,rule:rule,h:h,c:c,source:source))
        }
        return Self(comparisons:rows,selectedEnvironment:source?.id,clubs:clubs)
    }
    func validate(observation: ScoutingObservation) throws {
        guard [1,2].contains(version), catalogVersion == "domestic-market-v1", comparisons.count == observation.groups.count,
              Set(comparisons.map(\.id)).count == comparisons.count,
              clubs.count == (observation.role == .batter ? 18:6),Set(clubs.map(\.id)).count == clubs.count else {throw ScoutingObservationError.invalid}
        for row in comparisons {
            guard let group=observation.groups.first(where:{$0.id == row.id}),group.totals == row.totals,group.performance == row.performance else {throw ScoutingObservationError.invalid}
            if let perf=row.performance {try perf.validate(line:row.totals.line,role:observation.role)}
            if let ref=row.reference {try ref.validate();guard ref.environment == row.id,ref.role == observation.role else{throw ScoutingObservationError.invalid}}
            let v=row.performance?.contribution(row.totals.line,role:observation.role)
            let verified=(version == 2 && row.performance?.version == 2 || row.performance?.manual == false) && row.reference?.value != nil && v != nil
            let p=verified ? Self.correction(value:v!,reference:row.reference!.value!,n:row.performance!.sample(row.totals.line,role:observation.role)):0
            guard row.value == v,row.verified == verified,row.correction == p else {throw ScoutingObservationError.invalid}
        }
        let source=Self.selected(comparisons,role:observation.role)
        guard selectedEnvironment == source?.id else{throw ScoutingObservationError.invalid}
        for club in clubs {
            let h=observation.grades.first{$0.id == club.recruitment.roleID}?.score,c=try club.recruitment.criterion(role:observation.role)
            let p=source?.correction ?? 0,f=h.flatMap{h in c.map{Self.round(h-$0+p)}}
            guard club.h == h,club.c == c,club.p == p,club.f == f,
                  club.stage == (club.recruitment.demand == .none ? "모집 없음":Self.stage(f:f)),
                  club.blockers == Self.blockers(observation:observation,rule:club.recruitment,h:h,c:c,source:source) else{throw ScoutingObservationError.invalid}
        }
    }
}

// Independent rookie/admission market; pro first-team competitors are never entry criteria.
enum DomesticSelectionRoute: String, Codable, CaseIterable { case rookie, college
    var label: String { self == .rookie ? "국내 신인" : "대학 입단" }
}
struct DomesticSelectionSample: Codable, Equatable {
    let kind: String
    let endDate: String
    let comparison: ScoutingPerformanceComparison
}
struct DomesticSelectionSeat: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let route: DomesticSelectionRoute
    let order: Int
    let roles: [String]
    let budget: Int
}
struct DomesticSelectionCandidate: Codable, Equatable, Identifiable {
    let id: String
    let role: String
    let h: Double
    let p: Double
}
struct DomesticSelectionPick: Codable, Equatable {
    let seatID: String
    let candidateID: String
    let role: String
    let f: Double
    let cost: Int
}
struct DomesticSelectionResult: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let route: DomesticSelectionRoute
    let role: String
    let h: Double?
    let c: Double
    let p: Double
    let f: Double?
    let cost: Int
    let availableBudget: Int
    let availableSeats: Int
    let competition: Int
    let selected: Bool
    let reasons: [String]
    var status: String { selected ? (route == .rookie ? "신인 지명" : "대학 선발 합격") : reasons.contains(where: {$0.contains("자료") || $0.contains("표본")}) ? "심사 보류" : "미선발" }
}
struct DomesticSelection: Codable, Equatable {
    let rule: String
    let seed: String
    let priorMarket: String
    let sample: DomesticSelectionSample?
    let sampleReason: String
    let seats: [DomesticSelectionSeat]
    let candidates: [DomesticSelectionCandidate]
    let carried: [DomesticSelectionPick]
    let picks: [DomesticSelectionPick]
    let results: [DomesticSelectionResult]
    static let roles = ["slugger","onBase","field","starter"]
    static func minimum(_ role:String,route:DomesticSelectionRoute) -> Double {
        (role == "slugger" || role == "starter" ? 52:50) - (route == .college ? 5:0)
    }
    static func cost(_ f:Double) -> Int {Int((100 * max(0.75,min(2,1+0.06*f))).rounded())}
    static func hash(_ text:String) -> UInt64 {text.utf8.reduce(UInt64(14695981039346656037)) {($0 ^ UInt64($1)) &* 1099511628211}}
    static func market(seed:String) -> [DomesticSelectionSeat] {
        let ids=["harbors","comets","tides","stars","foxes","falcons"]
        let clubs=["인천 하버스","대전 코멧츠","부산 타이즈","서울 스타즈","광주 폭시스","대구 팔콘스"]
        let colleges=["해솔대","한빛대","푸른대","다온대","누리대","가온대"]
        // Seeded initial previous-year order is fictional game configuration, not real standings.
        let order=ids.indices.sorted {hash(seed+ids[$0]) < hash(seed+ids[$1])}
        var seats:[DomesticSelectionSeat]=[]
        for round in 0..<3 {for (index,club) in order.enumerated() {
            let role=roles[(club+round)%4]
            seats.append(DomesticSelectionSeat(id:"rookie/"+ids[club]+"/\(round+1)",name:clubs[club],route:.rookie,
                order:round*6+index,roles:[role],budget:330+club*12))
        }}
        for club in ids.indices {for (index,role) in roles.enumerated() {
            seats.append(DomesticSelectionSeat(id:"college/\(club)/"+role,name:colleges[club],route:.college,
                order:club*4+index,roles:[role],budget:520+club*40))
        }}
        return seats
    }
    static func candidates(seed:String,month:Int) -> [DomesticSelectionCandidate] {
        (0..<(month == 4 ? 20:8)).map { index in
            let id="npc/\(month)/\(index)",bits=hash(seed+"/"+id)
            return DomesticSelectionCandidate(id:id,role:roles[index%4],h:Double(46+bits%17),p:Double(Int((bits/17)%7)-3)*0.5)
        }
    }
    static func carried(seed:String,april:DomesticSelection?) -> [DomesticSelectionPick] {
        let picks=april?.picks ?? simulate(observation:nil,seats:market(seed:seed),candidates:candidates(seed:seed,month:4),carried:[],sample:nil,sampleReason:"").picks
        return picks.filter {$0.seatID.hasPrefix("rookie/") && $0.candidateID.hasPrefix("npc/")}
    }
    static func fieldCondition(_ role:String,route:DomesticSelectionRoute,observation:ScoutingObservation) -> [String] {
        guard role == "field" else {return []}
        let mastery=route == .rookie ? 60.0:50.0
        var reasons:[String]=[]
        if (observation.positionMastery ?? -1) < mastery {reasons.append("주 포지션 숙련\(Int(mastery)) 필요")}
        if route == .rookie && (observation.abilities.originals.first {$0.id == "homeDefense"}?.current ?? -1) < 50 {reasons.append("원본 수비50 필요")}
        return reasons
    }
    static func simulate(observation:ScoutingObservation?,seats:[DomesticSelectionSeat],candidates:[DomesticSelectionCandidate],
                         carried:[DomesticSelectionPick],sample:DomesticSelectionSample?,sampleReason:String) -> (picks:[DomesticSelectionPick],results:[DomesticSelectionResult]) {
        let own=observation.map {"player/"+$0.playerID.uuidString},p=sample?.comparison.correction ?? 0
        var picks=carried,results:[DomesticSelectionResult]=[]
        for route in DomesticSelectionRoute.allCases {
            var chosen:Set<String>
            // Each route is an alternative application; one player may qualify for both, never twice within one route.
            chosen=Set(carried.filter {pick in seats.first(where:{$0.id == pick.seatID})?.route == route}.map(\.candidateID))
            let ordered=seats.filter {$0.route == route}.sorted {
                if route == .college,let observation {
                    func best(_ seat:DomesticSelectionSeat) -> Double {
                        seat.roles.compactMap {role in observation.grades.first {$0.id == role}?.score.map {$0-minimum(role,route:route)}}.max() ?? -1000
                    }
                    let a=best($0),b=best($1)
                    if a != b {return a > b}
                }
                return $0.order == $1.order ? $0.id < $1.id:$0.order < $1.order
            }
            for seat in ordered {
                let occupied=picks.contains {$0.seatID == seat.id}
                let spent=picks.filter {pick in seats.first(where:{$0.id == pick.seatID})?.name == seat.name}.reduce(0) {$0+$1.cost}
                let budget=max(0,seat.budget-spent)
                var pool=candidates.filter {!chosen.contains($0.id) && seat.roles.contains($0.role)}.filter {
                    let f=$0.h-minimum($0.role,route:route)+$0.p
                    return f >= 0 && cost(f) <= budget
                }
                var ownRows:[DomesticSelectionResult]=[]
                if let observation,let own {
                    for role in seat.roles where observation.grades.contains(where:{$0.id == role}) {
                        let h=observation.grades.first {$0.id == role}?.score,c=minimum(role,route:route)
                        let f=h.map {ScoutingContractFit.round($0-c+p)},price=cost(f ?? 0)
                        var reasons:[String]=[]
                        if sample == nil {reasons.append(sampleReason)}
                        if h == nil {reasons.append("역할 기량 자료 부족")}
                        reasons += fieldCondition(role,route:route,observation:observation)
                        if let f,f < 0 {reasons.append(String(format:"기량 여유 F %.1f · 기준0 필요",f))}
                        if occupied {reasons.append("연간 모집 자리 충원 완료")}
                        if price > budget {reasons.append("예산 부족 · 필요\(price)/잔여\(budget)지수")}
                        if chosen.contains(own) {reasons.append("동일 경로의 다른 자리에서 이미 선발")}
                        ownRows.append(DomesticSelectionResult(id:seat.id+"/"+role,name:seat.name,route:route,role:role,h:h,c:c,p:p,f:f,
                            cost:price,availableBudget:budget,availableSeats:occupied ? 0:1,competition:pool.count,selected:false,reasons:reasons))
                        if reasons.isEmpty,let h {pool.append(DomesticSelectionCandidate(id:own,role:role,h:h,p:p))}
                    }
                }
                let winner=occupied ? nil:pool.sorted {
                    let a=ScoutingContractFit.round($0.h-minimum($0.role,route:route)+$0.p),b=ScoutingContractFit.round($1.h-minimum($1.role,route:route)+$1.p)
                    return a == b ? $0.id < $1.id:a > b
                }.first
                if let winner {
                    let f=ScoutingContractFit.round(winner.h-minimum(winner.role,route:route)+winner.p)
                    picks.append(DomesticSelectionPick(seatID:seat.id,candidateID:winner.id,role:winner.role,f:f,cost:cost(f)))
                    chosen.insert(winner.id)
                }
                for row in ownRows {
                    let selected=winner?.id == own && winner?.role == row.role
                    let reasons=row.reasons.isEmpty && !selected ? ["후보 경쟁 탈락 · F 내림차순/고정 ID 순"]:row.reasons
                    results.append(DomesticSelectionResult(id:row.id,name:row.name,route:row.route,role:row.role,h:row.h,c:row.c,p:row.p,f:row.f,
                        cost:row.cost,availableBudget:row.availableBudget,availableSeats:row.availableSeats,competition:row.competition,selected:selected,reasons:reasons))
                }
            }
        }
        return (picks,results)
    }
    func validate(observation:ScoutingObservation,window:ContractEvaluationWindow) throws {
        guard rule == "domestic-selection-v1",seed == observation.playerID.uuidString+"/\(window.year)",
              [4,7].contains(window.month),(20...23).contains(observation.age),
              seats == Self.market(seed:seed),Set(candidates.map(\.id)).count == candidates.count,
              candidates == Self.candidates(seed:seed,month:window.month),candidates.allSatisfy({$0.id.hasPrefix("npc/") && Self.roles.contains($0.role) && $0.h.isFinite && (0...100).contains($0.h) && $0.p.isFinite && (-4...4).contains($0.p)}),
              Set(carried.map(\.seatID)).count == carried.count,Set(carried.map(\.candidateID)).count == carried.count,
              carried.allSatisfy({pick in seats.contains(where:{$0.id == pick.seatID && $0.route == .rookie && $0.roles.contains(pick.role)}) && pick.candidateID.hasPrefix("npc/") && pick.f.isFinite && pick.f >= 0 && pick.cost == Self.cost(pick.f)}),
              window.month == 7 || carried.isEmpty else {throw ContractEvaluationError.invalid}
        if let sample {
            let source=sample.comparison,end=try GameDate(sample.endDate),date=try GameDate(observation.observedDate)
            guard source.verified,source.reference?.environment == source.id,source.reference?.role == observation.role,
                  source.reference?.position == (observation.role == .batter ? observation.position:"P"),
                  end <= date,(sample.kind == "졸업 고교 공식시즌" && observation.age == 20 && end.days(to:date) <= 730),
                  observation.role == .batter ? source.totals.line.plateAppearances >= 40:source.totals.line.pitchingOuts >= 45,
                  let perf=source.performance,let reference=source.reference,let v=perf.contribution(source.totals.line,role:observation.role) else {throw ContractEvaluationError.invalid}
            try perf.validate(line:source.totals.line,role:observation.role);try reference.validate()
            guard (perf.version == 2 || !perf.manual),source.value == v,
                  source.correction == ScoutingContractFit.correction(value:v,reference:reference.value!,n:perf.sample(source.totals.line,role:observation.role)) else {throw ContractEvaluationError.invalid}
        }
        let replay=Self.simulate(observation:observation,seats:window.month == 7 ? seats.filter {$0.route == .rookie}:seats,
            candidates:candidates,carried:carried,sample:sample,sampleReason:sampleReason)
        guard replay.picks == picks,replay.results == results else {throw ContractEvaluationError.invalid}
    }
}


struct DomesticContractOffer: Codable, Equatable, Identifiable {
    let id: String
    let resultID: String
    let route: DomesticSelectionRoute
    let name: String
    let roleID: String
    let issuedDate: String
    let expiresDate: String
    let economicIndex: Int
    let years: Int
    let h: Double
    let c: Double
    let p: Double
    let f: Double
    let availableBudget: Int
    let competition: Int
    var kind: String {route == .rookie ? "국내 신인 육성 계약":"대학 입단안"}
    var placement: String {route == .rookie ? "국내 육성 · 출전/승격 경쟁":"대학 야구부 · 학적/등록 심사"}
    var economicLabel: String {route == .rookie ? "연봉지수":"선발 지원지수"}
    var period: String {route == .rookie ? "1개 달력연도 · 발효일 수락 후 확정":"최초 입단 · 최대4개 달력 학년/24세 졸업 규칙"}
    func isExpired(on date:GameDate) throws -> Bool {date > (try GameDate(expiresDate))}
    static func roleName(_ id:String) -> String {
        switch id {case "slugger":"장타";case "onBase":"출루";case "field":"수비";default:"선발 투수"}
    }
}
struct DomesticOfferPacket: Codable, Equatable {
    let version: Int
    let rule: String
    let evaluationKey: String
    let issuedDate: String
    let offers: [DomesticContractOffer]
    let emptyReasons: [String]
    static func make(evaluation:ContractEvaluationSnapshot,key:String,on date:GameDate) throws -> Self {
        guard evaluation.version == 2,let selection=evaluation.selection,
              key == evaluation.observation.playerID.uuidString+":"+evaluation.window.id,
              date >= (try GameDate(evaluation.evaluatedDate)),ContractEvaluationWindow.containing(date) == evaluation.window else {throw ContractOfferError.invalid}
        let expiry=min(date.adding(days:6),evaluation.window.end).description
        let winners=selection.results.filter(\.selected)
        guard winners.count <= 2,Set(winners.map(\.route)).count == winners.count else {throw ContractOfferError.invalid}
        var offers:[DomesticContractOffer]=[]
        for row in winners {
            guard let h=row.h,let f=row.f,f >= 0,row.reasons.isEmpty,row.availableSeats == 1,row.cost <= row.availableBudget else {throw ContractOfferError.invalid}
            offers.append(DomesticContractOffer(id:key+"/"+row.id,resultID:row.id,route:row.route,name:row.name,roleID:row.role,
                issuedDate:date.description,expiresDate:expiry,economicIndex:row.cost,years:1,h:h,c:row.c,p:row.p,f:f,
                availableBudget:row.availableBudget,competition:row.competition))
        }
        offers.sort {a,b in a.route == b.route ? a.id < b.id:a.route == .rookie}
        var reasons:[String]=[]
        if offers.isEmpty {
            reasons=["이번 고정 평가에서 지명·대학 선발된 자리가 없습니다."]
            for reason in selection.results.flatMap(\.reasons) where !reasons.contains(reason) {
                reasons.append(reason)
                if reasons.count == 4 {break}
            }
        }
        return Self(version:1,rule:"domestic-offers-v1",evaluationKey:key,issuedDate:date.description,offers:offers,emptyReasons:reasons)
    }
    func validate(evaluation:ContractEvaluationSnapshot,key:String,today:GameDate) throws {
        let issued=try GameDate(issuedDate)
        guard version == 1,rule == "domestic-offers-v1",evaluationKey == key,issued <= today,
              self == (try Self.make(evaluation:evaluation,key:key,on:issued)) else {throw ContractOfferError.invalid}
    }
}
enum ContractOfferError: LocalizedError {
    case invalid, pendingChanges
    var errorDescription: String? {
        switch self {
        case .invalid:"저장된 제의 자료를 확인하지 못했습니다. 기존 제의와 평가 원장을 유지하고 다시 확인해 주세요."
        case .pendingChanges:"다른 저장 작업이 진행 중입니다. 완료한 뒤 제의를 다시 확인해 주세요."
        }
    }
}


// Offer originals remain immutable. Explicit decisions and registrations are a separate journal.
enum DomesticOfferDecisionKind:String,Codable {case accepted,rejected,closed}
struct DomesticOfferDecision:Codable,Equatable {
    let offerID:String
    let kind:DomesticOfferDecisionKind
    let date:String
}
struct CareerMembership:Codable,Equatable {
    let offerID:String
    let route:DomesticSelectionRoute
    let teamID:String
    let name:String
    let since:String
    let economicEnd:String
    let enrollmentEnd:String?
    let economicIndex:Int
    var level:String {route == .rookie ? "domestic-development":"college"}
    var label:String {route == .rookie ? "국내 육성팀":"대학 소속"}
    func contains(_ date:GameDate) throws -> Bool {
        try date >= GameDate(since) && (enrollmentEnd.map {try date <= GameDate($0)} ?? true)
    }
    static func make(offer:DomesticContractOffer,on date:GameDate,origin:GameDate,startAge:Int) throws -> Self {
        let parts=offer.resultID.components(separatedBy:"/")
        guard parts.count >= 3,date.year < 9995 else {throw ContractRegistrationError.invalid}
        let ids=offer.route == .rookie ? CareerTeamDirectory.domesticIDs:CareerTeamDirectory.collegeIDs
        let id=offer.route == .rookie ? "dev-"+parts[1]:"college-"+parts[1]
        guard ids.contains(id) else {throw ContractRegistrationError.invalid}
        let economicEnd=date.anniversary(in:date.year+1).adding(days:-1)
        let graduation=min(date.anniversary(in:date.year+4),origin.anniversary(in:origin.year+24-startAge)).adding(days:-1)
        return Self(offerID:offer.id,route:offer.route,teamID:id,name:CareerTeamDirectory.name(id),since:date.description,
            economicEnd:economicEnd.description,enrollmentEnd:offer.route == .college ? graduation.description:nil,economicIndex:offer.economicIndex)
    }
}
enum CareerTeamDirectory {
    static let domesticIDs=["harbors","comets","tides","stars","foxes","falcons"].map {"dev-"+$0}
    static let collegeIDs=(0..<6).map {"college-\($0)"}
    static let domesticNames=["인천 하버스 육성","대전 코멧츠 육성","부산 타이즈 육성","서울 스타즈 육성","광주 폭시스 육성","대구 팔콘스 육성"]
    static let collegeNames=["해솔대","한빛대","푸른대","다온대","누리대","가온대"]
    static func name(_ id:String,schools:[School]=[]) -> String {
        if let i=domesticIDs.firstIndex(of:id) {return domesticNames[i]}
        if let i=collegeIDs.firstIndex(of:id) {return collegeNames[i]}
        return schools.first {$0.id == id}?.name ?? id
    }
}
struct CareerContractJournal:Codable,Equatable {
    var version=1
    let playerID:UUID
    var revision=0
    var decisions:[DomesticOfferDecision]=[]
    var memberships:[CareerMembership]=[]
    func current(on date:GameDate) throws -> CareerMembership? {try memberships.last(where:{try $0.contains(date)})}
    func validate(player:CareerPlayer,calendar:CareerCalendarState,offers:[DomesticContractOffer]) throws {
        let today=try GameDate(player.gameDate),origin=try GameDate(calendar.originDate)
        guard version == 1,playerID == player.id,revision >= 0,
              Set(decisions.map(\.offerID)).count == decisions.count,Set(memberships.map(\.offerID)).count == memberships.count else {throw ContractRegistrationError.invalid}
        for decision in decisions {
            guard let offer=offers.first(where:{$0.id == decision.offerID}) else {throw ContractRegistrationError.invalid}
            let date=try GameDate(decision.date)
            guard date <= today,date >= (try GameDate(offer.issuedDate)),!(try offer.isExpired(on:date)),
                  (20...23).contains(origin.age(startingAt:player.startAge,on:date)) else {throw ContractRegistrationError.invalid}
            if decision.kind == .accepted {
                guard memberships.contains(try CareerMembership.make(offer:offer,on:date,origin:origin,startAge:player.startAge)) else {throw ContractRegistrationError.invalid}
            }
        }
        for (index,member) in memberships.enumerated() {
            guard decisions.contains(where:{$0.offerID == member.offerID && $0.kind == .accepted && $0.date == member.since}) else {throw ContractRegistrationError.invalid}
            if index > 0 {
                let date=try GameDate(member.since),previous=try GameDate(memberships[index-1].since)
                guard try !memberships[index-1].contains(date),previous < date else {throw ContractRegistrationError.invalid}
            }
        }
    }
}
struct CareerCompetitionPlan {
    let teamID:String
    let teamIDs:[String]
    let fixtures:[SeasonFixture]
    let membership:CareerMembership?
}
enum ContractRegistrationError:LocalizedError {
    case invalid,stale,closed,expired,busy,registered
    var errorDescription:String? {
        switch self {
        case .invalid:"계약 결정/소속 등록 자료를 확인하지 못했습니다. 기존 자료를 유지합니다."
        case .stale:"날짜나 제의 상태가 바뀌었습니다. 최신 조건을 확인한 뒤 다시 선택해 주세요."
        case .closed:"이미 결정되거나 닫힌 제의입니다. 같은 창에서 다시 발행하지 않습니다."
        case .expired:"제의가 만료되었습니다. 다음 허용 창을 준비해 주세요."
        case .busy:"진행 중인 경기·훈련 또는 다른 저장을 마친 뒤 소속을 변경해 주세요."
        case .registered:"유효한 소속/보유 권리가 있습니다. 중복 입단할 수 없습니다."
        }
    }
}

// Economic terms never imply a release of the club's registration rights.
struct CareerContractStatus: Equatable {
    let membership: CareerMembership
    let economicExpired: Bool
    let nextReview: String?
    init(_ membership: CareerMembership, on date: GameDate) throws {
        self.membership=membership
        economicExpired=date > (try GameDate(membership.economicEnd))
        nextReview=membership.route == .rookie ? ContractEvaluationWindow(year:date > ContractEvaluationWindow(year:date.year,month:11).end ? date.year+1:date.year,month:11).start.description:nil
    }
    var economicLabel: String {economicExpired ? "경제 기간 종료 · 갱신 미확정":"경제 계약 유효"}
    var rightsLabel: String {membership.route == .rookie ? "구단 보유권리 유지 · 자동 FA 아님":"대학 학적 · 프로 구단 보유권리 없음"}
}
struct DomesticRenewalOffer: Codable, Equatable, Identifiable {
    let id: String
    let issuedDate: String
    let expiresDate: String
    let effectiveDate: String
    let economicEnd: String
    let economicIndex: Int
    var years: Int {1}
}
struct DomesticRenewalReview: Codable, Equatable {
    let rule: String
    let membership: CareerMembership
    let roleID: String
    let h: Double?
    let c: Double
    let p: Double
    let f: Double?
    let competitorH: Double
    let budget: Int
    let sampleID: String?
    let sampleCount: Int
    let totals: PersonalSeasonTotals?
    let reasons: [String]
    let offer: DomesticRenewalOffer?
    static func make(observation: ScoutingObservation, member: CareerMembership, roleID: String,
                     key: String, window: ContractEvaluationWindow) throws -> Self {
        let date=try GameDate(observation.observedDate)
        guard member.route == .rookie,try member.contains(date),window.month == 11,
              window == ContractEvaluationWindow.containing(date),observation.age >= 20,
              observation.school == member.name,key == observation.playerID.uuidString+":"+window.id,
              let club=CareerTeamDirectory.domesticIDs.firstIndex(of:member.teamID),
              observation.grades.contains(where:{$0.id == roleID}) else {throw ContractEvaluationError.invalid}
        // One fixed current-club role, one incumbent slot. These are development-team game data.
        let bits=DomesticSelection.hash(key+"/renewal/"+member.teamID+"/"+roleID)
        let competitor=Double(48+bits%19)
        let c=max(DomesticSelection.minimum(roleID,route:.rookie),competitor+1)
        let budget=330+club*12-Int(75+(bits/19)%101)
        let groups=observation.groups.filter {$0.id.hasPrefix("domestic-development/") && $0.performance != nil}
        let eligible=groups.filter {observation.role == .batter ? $0.hasBatterMinimum:$0.hasPitcherMinimum}
        let sample=(eligible.isEmpty ? groups:eligible).sorted {
            let a=$0.performance!.sample($0.totals.line,role:observation.role),b=$1.performance!.sample($1.totals.line,role:observation.role)
            return a == b ? $0.id < $1.id:a > b
        }.first
        let n=sample.flatMap {group in group.performance.map {$0.sample(group.totals.line,role:observation.role)}} ?? 0
        let enough=sample.map {observation.role == .batter ? $0.hasBatterMinimum:$0.hasPitcherMinimum} ?? false
        let h=observation.grades.first {$0.id == roleID}?.score
        // Adult Vref has not been calibrated. Actual sample is shown; no invented performance bonus.
        let p=0.0,f=h.map {ScoutingContractFit.round($0-c+p)}
        let cost=DomesticSelection.cost(f ?? 0)
        var reasons:[String]=[]
        if !enough {reasons.append(observation.role == .batter ? "동일 환경 육성 경기40타석 필요":"동일 환경 육성 경기15이닝 필요")}
        if h == nil {reasons.append("모집 역할 기량 자료 부족")}
        reasons += DomesticSelection.fieldCondition(roleID,route:.rookie,observation:observation)
        if let f,f < 0 {reasons.append("역할/경쟁 기준 미달 · F 0 이상 필요")}
        if cost > budget {reasons.append("갱신 예산 부족 · 필요\(cost)/잔여\(budget)지수")}
        let start=max(try GameDate(member.economicEnd).adding(days:1),date)
        let offer=reasons.isEmpty ? DomesticRenewalOffer(id:key+"/renewal/"+member.teamID,issuedDate:date.description,
            expiresDate:min(date.adding(days:6),window.end).description,effectiveDate:start.description,
            economicEnd:start.anniversary(in:start.year+1).adding(days:-1).description,economicIndex:cost):nil
        return Self(rule:"domestic-renewal-v1",membership:member,roleID:roleID,h:h,c:c,p:p,f:f,competitorH:competitor,budget:budget,
            sampleID:sample?.id,sampleCount:n,totals:sample?.totals,reasons:reasons,offer:offer)
    }
    func validate(observation: ScoutingObservation,key: String,window: ContractEvaluationWindow) throws {
        guard self == (try Self.make(observation:observation,member:membership,roleID:roleID,key:key,window:window)) else {throw ContractEvaluationError.invalid}
    }
}
