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
        return "highschool/\(role.rawValue)/manual2-training1-field5-stats\(fieldStats!.version)-ability1-pitching1-events\(perf.version)/\(position)/" + (perf.version == 2 ? (perf.inputs?.mode.suffix ?? "unknown") : perf.manual ? "manual-unverified":"auto-v1")
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
                var match = fixture(role:role,position:position,values:profile,seed:UInt64(811_001+index*1_000+game),home:game%2 == 0,tracked:tracked)
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
    static func fixture(role: PlayerRole, position: String, values: PlayerInitialValues, seed: UInt64, home: Bool, tracked: Bool = false) -> CareerMatch {
        var match = CareerMatch(random:seed,isHome:home,role:role.rawValue,appearance:true,
            contact:values.contact,power:values.power,discipline:values.discipline,mastery:values.pitches)
        match.controlVersion=2;match.trainingEffectsVersion=1;match.detailedFieldVersion=5
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
