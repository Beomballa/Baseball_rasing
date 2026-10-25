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
        let npc=npcFielders.map {"-npc\($0.version)"} ?? ""
        let attack=npcAttack.map {"-attack\($0.version)"} ?? ""
        return "\(competition ?? "highschool")/\(role.rawValue)/manual2-training1-field5-stats\(fieldStats!.version)-ability1-pitching1\(batted)\(npc)\(attack)-events\(perf.version)/\(position)/" + (perf.version == 2 ? (perf.inputs?.mode.suffix ?? "unknown") : perf.manual ? "manual-unverified":"auto-v1")
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
        guard [1,2,3].contains(version), profiles.count == 3, gamesPerProfile == (role == .batter ? 20:6),
              totals.games == profiles.count*gamesPerProfile, value?.isFinite == true else { throw ScoutingObservationError.invalid }
        if version == 1 {
            guard performance.version == 1, !performance.manual, inputPolicy == nil, inputMode == nil,
                  environment.hasSuffix("/\(position)/auto-v1") else {throw ScoutingObservationError.invalid}
        } else {
            guard inputPolicy == (version == 3 ? "adult-standard-controls-v1":"standard-controls-v1"), let inputMode, performance.version == 2,
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
        if environment.contains("-npc1-") && !environment.contains("-batted1-") {return nil}
        if environment.contains("-attack"),!environment.contains("-attack1-") || !environment.contains("-npc1-") {return nil}
        if let found = cache[environment] { return found }
        let profiles = PlayerArchetype.choices(for:role).map(\.values), count = role == .batter ? 20:6
        var totals = PersonalSeasonTotals(), performance = tracked ? MatchScoutingPerformance.tracked:MatchScoutingPerformance()
        for (index, profile) in profiles.enumerated() {
            for game in 0..<count {
                var match = fixture(role:role,position:position,values:profile,seed:UInt64(811_001+index*1_000+game),home:game%2 == 0,tracked:tracked,
                    battedBallVersion:environment.contains("-batted1-") ? 1:nil,npcFieldersVersion:environment.contains("-npc1-") ? 1:nil,npcAttackVersion:environment.contains("-attack1-") ? 1:nil)
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
    static func fixture(role: PlayerRole, position: String, values: PlayerInitialValues, seed: UInt64, home: Bool, tracked: Bool = false,battedBallVersion:Int?=nil,npcFieldersVersion:Int?=nil,fatigue:Int=24,assessmentRoster:MatchNPCFielders?=nil,npcAttackVersion:Int?=nil,competition:String?=nil) -> CareerMatch {
        var match = CareerMatch(random:seed,isHome:home,role:role.rawValue,appearance:true,
            contact:values.contact,power:values.power,discipline:values.discipline,mastery:values.pitches)
        match.controlVersion=2;match.trainingEffectsVersion=1;match.detailedFieldVersion=5
        match.battedBallVersion=battedBallVersion
        if npcFieldersVersion == 1 {
            // Standard high-school reference pool; this is not the user's exact opponent roster.
            let own="hs-ref-001",opponent=String(format:"hs-ref-%03d",2+Int(seed%5))
            match.npcFielders=MatchNPCFielders.make(year:2026,competition:"highschool",homeID:home ? own:opponent,awayID:home ? opponent:own)
        }
        if let assessmentRoster {match.npcFielders=assessmentRoster}
        match.competition=competition
        if npcAttackVersion == 1,let roster=match.npcFielders {match.npcAttack=MatchNPCAttack.make(roster:roster)}
        match.fieldPlays=[];match.runnerProfiles=[nil,nil,nil]
        match.abilityStats=MatchAbilityStats(mental:values.mental,velocity:values.velocity,control:values.control,stuff:values.stuff,stamina:values.stamina,fatigue:fatigue)
        match.fieldStats=MatchFieldStats(speed:values.speed,defense:values.defense,arm:values.arm,position:position)
        match.fieldStats?.version=role == .batter ? 3:2;match.fieldStats?.activeTraits=[]
        if role == .batter {match.fieldStats?.positionMastery=60}
        match.pitching=MatchPitching(startingFatigue:fatigue);match.scoutingPerformance=tracked ? .tracked:MatchScoutingPerformance()
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
    var reentry:Bool? = nil
    var collegeEntry:CollegeProEntry? = nil
    var kind: String {collegeEntry != nil ? "대학 재학생 프로 진출 계약":reentry == true ? "국내 육성팀 재입단 계약":route == .rookie ? "국내 신인 육성 계약":"대학 입단안"}
    var placement: String {route == .rookie ? "국내 육성 · 출전/승격 경쟁":"대학 야구부 · 학적/등록 심사"}
    var economicLabel: String {route == .rookie ? "연봉지수":"선발 지원지수"}
    var period: String {if let entry=collegeEntry {return entry.effectiveDate+"부터 1년 · 대학 소속은 발효 전일까지 유지"};return route == .rookie ? "1개 달력연도 · 발효일 수락 후 확정":"최초 입단 · 최대4개 달력 학년/24세 졸업 규칙"}
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
        guard [2,4,5,6].contains(evaluation.version),
              key == evaluation.observation.playerID.uuidString+":"+evaluation.window.id,
              date >= (try GameDate(evaluation.evaluatedDate)),ContractEvaluationWindow.containing(date) == evaluation.window else {throw ContractOfferError.invalid}
        let expiry=min(date.adding(days:6),evaluation.window.end).description
        let winners=(evaluation.college?.results ?? evaluation.retry?.results ?? evaluation.selection?.results ?? []).filter(\.selected)
        guard winners.count <= 2,Set(winners.map(\.route)).count == winners.count else {throw ContractOfferError.invalid}
        var offers:[DomesticContractOffer]=[]
        for row in winners {
            guard let h=row.h,let f=row.f,f >= 0,row.reasons.isEmpty,row.availableSeats == 1,row.cost <= row.availableBudget else {throw ContractOfferError.invalid}
            var offer=DomesticContractOffer(id:key+"/"+row.id,resultID:row.id,route:row.route,name:row.name,roleID:row.role,
                issuedDate:date.description,expiresDate:expiry,economicIndex:row.cost,years:1,h:h,c:row.c,p:row.p,f:f,
                availableBudget:row.availableBudget,competition:row.competition)
            offer.reentry=[4,5].contains(evaluation.version) ? true:nil
            if let college=evaluation.college {offer.collegeEntry=CollegeProEntry(membershipOfferID:college.membership.offerID,effectiveDate:college.effectiveDate)}
            offers.append(offer)
        }
        offers.sort {a,b in a.route == b.route ? a.id < b.id:a.route == .rookie}
        var reasons:[String]=[]
        if offers.isEmpty {
            reasons=["이번 고정 평가에서 지명·대학 선발된 자리가 없습니다."]
            for reason in (evaluation.college?.results ?? evaluation.retry?.results ?? evaluation.selection?.results ?? []).flatMap(\.reasons) where !reasons.contains(reason) {
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
    var releasedOn:String? = nil
    var economicStart:String? = nil
    var competitionLevel:String? = nil
    func renewing(_ terms:DomesticRenewalOffer) -> Self {
        var value=Self(offerID:offerID,route:route,teamID:teamID,name:name,since:since,economicEnd:terms.economicEnd,enrollmentEnd:enrollmentEnd,economicIndex:terms.economicIndex)
        value.economicStart=terms.effectiveDate;return value
    }
    var level:String {competitionLevel ?? (route == .rookie ? "domestic-development":"college")}
    var label:String {level == "domestic-first-team" ? "국내1군":level == "mlb-development" ? "MLB 조직 육성":level == "npb-first-team" ? "NPB 전력":level == "mlb-first-team" ? "MLB 메이저":route == .rookie ? "국내 육성팀":"대학 소속"}
    func contains(_ date:GameDate) throws -> Bool {
        try date >= GameDate(since) && (enrollmentEnd.map {try date <= GameDate($0)} ?? true) && (releasedOn.map {try date < GameDate($0)} ?? true)
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
    static let americanDevelopmentIDs=(0..<6).map {"us-dev-\($0)"}
    static let domesticFirstIDs=domesticIDs.map {$0.replacingOccurrences(of:"dev-",with:"pro-")}
    static let japaneseFirstIDs=(0..<6).map {"jp-pro-\($0)"}
    static let americanFirstIDs=(0..<6).map {"us-pro-\($0)"}
    static func teams(level:String) -> [String] {
        switch level {case "mlb-development":americanDevelopmentIDs;case "domestic-first-team":domesticFirstIDs;case "npb-first-team":japaneseFirstIDs;case "mlb-first-team":americanFirstIDs;case "college":collegeIDs;default:domesticIDs}
    }
    static let domesticNames=["인천 하버스 육성","대전 코멧츠 육성","부산 타이즈 육성","서울 스타즈 육성","광주 폭시스 육성","대구 팔콘스 육성"]
    static let collegeNames=["해솔대","한빛대","푸른대","다온대","누리대","가온대"]
    static func name(_ id:String,schools:[School]=[]) -> String {
        if let i=domesticIDs.firstIndex(of:id) {return domesticNames[i]}
        if let i=collegeIDs.firstIndex(of:id) {return collegeNames[i]}
        if let i=domesticFirstIDs.firstIndex(of:id) {return domesticNames[i].replacingOccurrences(of:" 육성",with:"")+" 1군"}
        if let i=japaneseFirstIDs.firstIndex(of:id) {return OverseasMarket.japaneseNames[i]}
        if let i=americanFirstIDs.firstIndex(of:id) {return OverseasMarket.americanNames[i]}
        if let i=americanDevelopmentIDs.firstIndex(of:id) {return OverseasMarket.americanNames[i]}
        return schools.first {$0.id == id}?.name ?? id
    }
}
struct DomesticRenewalAcceptance:Codable,Equatable {
    let membershipOfferID:String
    let date:String
    let terms:DomesticRenewalOffer
}
struct DomesticRenewalRejection:Codable,Equatable {let offerID:String;let date:String}
struct DomesticRelease:Codable,Equatable {let membershipOfferID:String;let date:String;let evaluationKey:String}
struct CollegeProEntry:Codable,Equatable {let membershipOfferID:String;let effectiveDate:String}
struct CollegeProTransition:Codable,Equatable {let offerID:String;let source:CollegeProEntry;let acceptedDate:String}
struct CareerContractJournal:Codable,Equatable {
    static func == (lhs:Self,rhs:Self) -> Bool {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        guard let a=try? encoder.encode(lhs),let b=try? encoder.encode(rhs) else {return false}
        return a == b
    }
    var version=1
    let playerID:UUID
    var revision=0
    var decisions:[DomesticOfferDecision]=[]
    var memberships:[CareerMembership]=[]
    var renewals:[DomesticRenewalAcceptance]? = nil
    var renewalRejections:[DomesticRenewalRejection]? = nil
    var releases:[DomesticRelease]? = nil
    var collegeTransitions:[CollegeProTransition]? = nil
    var overseasEligibility:[OverseasEligibilitySnapshot]? = nil
    var overseasReports:[OverseasScoutingReport]? = nil
    var overseasCareer:OverseasCareerJournal? = nil
    var developmentTarget:CareerDevelopmentTarget? = nil
    var developmentProjects:[CareerDevelopmentProject]? = nil
    var developmentReviews:[CareerProjectReview]? = nil
    var gamePlanReports:[MatchPlanObservation]? = nil
    var specialTrainings:[GoalSpecialTraining]? = nil
    var specialAssessments:[GoalSpecialAssessment]? = nil
    var specialReports:[GoalSpecialReport]? = nil
    var seasonGoals:[ClubSeasonGoal]? = nil
    var seasonGoalReports:[ClubSeasonObservation]? = nil
    var seasonReviews:[ClubSeasonReview]? = nil
    func membershipHistory(excludingOverseasRelease:String?=nil,excludingFA:String?=nil) -> [CareerMembership] {
        (memberships+(overseasCareer?.transitions.map(\.destination) ?? [])).sorted {$0.since<$1.since}.map {member in
            var value=member
            value.releasedOn=releases?.first {$0.membershipOfferID == member.offerID}?.date ?? collegeTransitions?.first {$0.source.membershipOfferID == member.offerID}?.source.effectiveDate
            if let end=overseasCareer?.transitions.first(where:{$0.sourceMembershipID == member.offerID})?.destination.since {
                value.releasedOn=value.releasedOn.map {min($0,end)} ?? end
            }
            if let released=overseasCareer?.releases?.first(where:{$0.source.offerID == member.offerID && $0.source.offerID != excludingOverseasRelease}) {
                value.releasedOn=value.releasedOn.map {min($0,released.date)} ?? released.date
            }
            if let fa=overseasCareer?.faDeclarations?.first(where:{$0.source.offerID == member.offerID && $0.id != excludingFA}) {
                value.releasedOn=value.releasedOn.map {min($0,fa.effective)} ?? fa.effective
            }
            return value
        }
    }
    var retryReleases:[DomesticRelease] {
        ((releases ?? [])+(overseasCareer?.releases ?? []).map {DomesticRelease(membershipOfferID:$0.source.offerID,date:$0.date,evaluationKey:$0.reviewID)}).sorted {$0.date<$1.date}
    }
    var activeRetryRelease:DomesticRelease? {
        guard let last=membershipHistory().last,let release=retryReleases.last,last.offerID == release.membershipOfferID else {return nil}
        return release
    }
    func current(on date:GameDate,excludingRenewal:String?=nil,ignoringReleases:Bool=false,excludingMembership:String?=nil,excludingOverseasRenewal:String?=nil,excludingOverseasRelease:String?=nil,excludingFA:String?=nil) throws -> CareerMembership? {
        guard var member=try (ignoringReleases ? memberships:membershipHistory(excludingOverseasRelease:excludingOverseasRelease,excludingFA:excludingFA)).last(where:{try $0.offerID != excludingMembership && $0.contains(date)}) else {return nil}
        member.releasedOn=nil
        for renewal in renewals ?? [] where renewal.membershipOfferID == member.offerID && renewal.terms.id != excludingRenewal {
            if try GameDate(renewal.date)<=date && GameDate(renewal.terms.effectiveDate)<=date {member=member.renewing(renewal.terms)}
        }
        return try projected(member,on:date,excludingRenewal:excludingOverseasRenewal)
    }
    func validate(player:CareerPlayer,calendar:CareerCalendarState,offers:[DomesticContractOffer],reviews:[String:DomesticRenewalReview]=[:]) throws {
        let today=try GameDate(player.gameDate),origin=try GameDate(calendar.originDate)
        try overseasCareer?.validate(owner:self,today:today)
        guard version == 1,playerID == player.id,revision >= 0,
              Set(decisions.map(\.offerID)).count == decisions.count,Set(memberships.map(\.offerID)).count == memberships.count else {throw ContractRegistrationError.invalid}
        let overseas=overseasEligibility ?? []
        guard Set(overseas.map(\.id)).count == overseas.count else {throw ContractRegistrationError.invalid}
        for value in overseas {
            guard value.evidence.origin == calendar.originDate,value.evidence.startAge == player.startAge else {throw ContractRegistrationError.invalid}
            try value.validate(playerID:player.id,today:today)
        }
        let reports=overseasReports ?? []
        guard Set(reports.map(\.id)).count == reports.count else {throw ContractRegistrationError.invalid}
        for report in reports {
            guard report.observation.origin == calendar.originDate else {throw ContractRegistrationError.invalid}
            try report.validate(playerID:player.id,today:today)
        }
        for decision in decisions {
            guard let offer=offers.first(where:{$0.id == decision.offerID}) else {throw ContractRegistrationError.invalid}
            let date=try GameDate(decision.date)
            guard date <= today,date >= (try GameDate(offer.issuedDate)),!(try offer.isExpired(on:date)),
                  (offer.reentry == true ? origin.age(startingAt:player.startAge,on:date) >= 20:(20...23).contains(origin.age(startingAt:player.startAge,on:date))) else {throw ContractRegistrationError.invalid}
            if decision.kind == .accepted {
                guard memberships.contains(try CareerMembership.make(offer:offer,on:offer.collegeEntry.map {try GameDate($0.effectiveDate)} ?? date,origin:origin,startAge:player.startAge)) else {throw ContractRegistrationError.invalid}
            }
        }
        let transitions=collegeTransitions ?? []
        guard Set(transitions.map(\.offerID)).count == transitions.count,
              Set(transitions.map { $0.source.membershipOfferID }).count == transitions.count else {throw ContractRegistrationError.invalid}
        for item in transitions {
            guard let offer=offers.first(where:{$0.id == item.offerID}),offer.route == .rookie,offer.collegeEntry == item.source,
                  decisions.contains(where:{$0.offerID == item.offerID && $0.kind == .accepted && $0.date == item.acceptedDate}),
                  let college=memberships.first(where:{$0.offerID == item.source.membershipOfferID}),college.route == .college,
                  try college.contains(GameDate(item.acceptedDate)),
                  try CollegeProReview.eligible(member:college,age:origin.age(startingAt:player.startAge,on:GameDate(item.acceptedDate)),on:GameDate(item.acceptedDate)),
                  item.source.effectiveDate == (try CollegeProReview.effective(after:GameDate(item.acceptedDate)).description) else {throw ContractRegistrationError.invalid}
        }
        for offer in offers where offer.collegeEntry != nil && decisions.contains(where:{$0.offerID == offer.id && $0.kind == .accepted}) {
            guard transitions.contains(where:{$0.offerID == offer.id}) else {throw ContractRegistrationError.invalid}
        }
        let accepted=renewals ?? []
        guard Set(accepted.map { $0.terms.id }).count == accepted.count else {throw ContractRegistrationError.invalid}
        var lastDate:GameDate?
        for renewal in accepted {
            let date=try GameDate(renewal.date)
            guard let review=reviews.values.first(where:{$0.offer?.id == renewal.terms.id}),review.offer == renewal.terms,
                  review.membership.offerID == renewal.membershipOfferID,review.membership.route == .rookie,
                  date >= (try GameDate(renewal.terms.issuedDate)),date <= (try GameDate(renewal.terms.expiresDate)),date <= today,
                  lastDate == nil || date >= lastDate!,
                  !(renewalRejections ?? []).contains(where:{$0.offerID == renewal.terms.id}),
                  try current(on:GameDate(renewal.terms.issuedDate),excludingRenewal:renewal.terms.id) == review.membership else {throw ContractRegistrationError.invalid}
            lastDate=date
        }
        let rejected=renewalRejections ?? [],released=releases ?? []
        guard Set(rejected.map(\.offerID)).count == rejected.count,
              Set(released.map(\.membershipOfferID)).count == released.count else {throw ContractRegistrationError.invalid}
        for item in rejected {
            let date=try GameDate(item.date)
            guard let terms=reviews.values.compactMap(\.offer).first(where:{$0.id == item.offerID}),
                  date >= (try GameDate(terms.issuedDate)),date <= (try GameDate(terms.expiresDate)),date <= today else {throw ContractRegistrationError.invalid}
        }
        for item in released {
            guard try GameDate(item.date) <= today,
                  let review=reviews[item.evaluationKey],review.membership.offerID == item.membershipOfferID,
                  try releaseEligible(review:review,key:item.evaluationKey,on:GameDate(item.date),reviews:reviews,ignoringReleases:true) else {throw ContractRegistrationError.invalid}
        }
        for (index,member) in memberships.enumerated() {
            guard decisions.contains(where:{$0.offerID == member.offerID && $0.kind == .accepted && ($0.date == member.since || transitions.contains(where: { $0.offerID == member.offerID && $0.source.effectiveDate == member.since }))}) else {throw ContractRegistrationError.invalid}
            if index > 0 {
                let date=try GameDate(member.since),previous=try GameDate(memberships[index-1].since)
                guard try !membershipHistory()[index-1].contains(date),previous < date else {throw ContractRegistrationError.invalid}
            }
        }
    }
    func releaseEligible(review:DomesticRenewalReview,key:String,on date:GameDate,reviews:[String:DomesticRenewalReview],ignoringReleases:Bool=false) throws -> Bool {
        let window=ContractEvaluationWindow(year:try GameDate(String(key.suffix(7))+"-01").year,month:11)
        guard key == playerID.uuidString+":"+window.id,
              window.year < 9998,date > window.end,date < (try GameDate(String(format:"%04d-04-01",window.year+1))),
              let member=try current(on:date,ignoringReleases:ignoringReleases),member == review.membership,
              date > (try GameDate(member.economicEnd)),
              !(renewals ?? []).contains(where:{$0.membershipOfferID == member.offerID && $0.terms.effectiveDate >= member.economicEnd}),
              !reviews.contains(where:{$0.value.membership.offerID == member.offerID && $0.key > key && String($0.key.suffix(7))+"-01" <= date.description}) else {return false}
        if let offer=review.offer {return try (renewalRejections ?? []).contains {$0.offerID == offer.id} || date > (try GameDate(offer.expiresDate))}
        return true
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

// Released players compete for adult development places; adult Vref remains uncalibrated (P=0).
struct DomesticRetryReview:Codable,Equatable {
    var version:Int? = nil
    var certificate:CertifiedAssessment? = nil
    let release:DomesticRelease
    let results:[DomesticSelectionResult]
    static func make(observation:ScoutingObservation,release:DomesticRelease,window:ContractEvaluationWindow,certificate:CertifiedAssessment?=nil,certificationEnabled:Bool=false) throws -> Self {
        let date=try GameDate(observation.observedDate)
        guard observation.age >= 20,[4,7].contains(window.month),window == ContractEvaluationWindow.containing(date),
              try GameDate(release.date)<date else {throw ContractEvaluationError.invalid}
        let groups=observation.groups.filter {$0.id.hasPrefix("domestic-development/") && $0.performance != nil}
        if let certificate {
            try certificate.validate()
            guard certificationEnabled,certificate.playerID == observation.playerID,certificate.releaseOfferID == release.membershipOfferID,
                  certificate.window == window,certificate.role == observation.role,certificate.date >= release.date,certificate.date <= observation.observedDate else {throw ContractEvaluationError.invalid}
        }
        let regular=groups.contains {observation.role == .batter ? $0.hasBatterMinimum:$0.hasPitcherMinimum}
        let enough=regular || certificate?.passed == true
        let seed=observation.playerID.uuidString+"/reentry/"+window.id
        let roles=observation.role == .batter ? ["slugger","onBase","field"]:["starter"]
        var rows:[DomesticSelectionResult]=[]
        for (index,team) in CareerTeamDirectory.domesticIDs.enumerated() {
            for role in roles {
                let bits=DomesticSelection.hash(seed+team+role)
                let c=max(DomesticSelection.minimum(role,route:.rookie),Double(52+bits%19))
                let h=observation.grades.first {$0.id == role}?.score,f=h.map {ScoutingContractFit.round($0-c)}
                let cost=DomesticSelection.cost(f ?? 0),budget=220+Int((bits/19)%101)
                var reasons:[String]=[]
                if !enough {reasons.append(certificationEnabled ? (certificate == nil ? "육성 성적40타석/15이닝 또는 해당 창 인증 평가전 필요":"인증 평가전 성적 미달 · 다음 창 평가전을 준비하세요"):"동일 환경 육성 성적40타석/15이닝 필요 · 인증 평가전은 후속")}
                if h == nil {reasons.append("역할 기량 자료 부족")}
                reasons += DomesticSelection.fieldCondition(role,route:.rookie,observation:observation)
                if let f,f < 0 {reasons.append("성인 역할/고정 후보 경쟁 기준 미달 · F 0 필요")}
                if cost>budget {reasons.append("재입단 예산 부족")}
                rows.append(DomesticSelectionResult(id:"rookie/"+CareerTeamDirectory.domesticIDs[index].dropFirst(4)+"/"+role,
                    name:CareerTeamDirectory.name(team),route:.rookie,role:role,h:h,c:c,p:0,f:f,cost:cost,
                    availableBudget:budget,availableSeats:1,competition:1,selected:false,reasons:reasons))
            }
        }
        let winner=rows.filter {$0.reasons.isEmpty}.sorted {a,b in a.f == b.f ? a.id<b.id:a.f!>b.f!}.first?.id
        var result=Self(release:release,results:rows.map {row in
            DomesticSelectionResult(id:row.id,name:row.name,route:row.route,role:row.role,h:row.h,c:row.c,p:0,f:row.f,
                cost:row.cost,availableBudget:row.availableBudget,availableSeats:1,competition:1,selected:row.id == winner,
                reasons:row.reasons.isEmpty && row.id != winner ? ["다른 재입단 자리 우선 배정"]:row.reasons)
        })
        if certificationEnabled {result.version=2;result.certificate=certificate}
        return result
    }
}

struct CertifiedAssessment:Codable,Equatable {
    var version=1
    let key:String
    let playerID:UUID
    let releaseOfferID:String
    let window:ContractEvaluationWindow
    let date:String
    let role:PlayerRole
    let totals:PersonalSeasonTotals
    let battersFaced:Int
    let homeRunsAllowed:Int
    var score:Double {
        let l=totals.line
        if role == .batter {return l.plateAppearances == 0 ? 0: min(100,100*Double(l.hits+l.walks)/Double(l.plateAppearances))}
        let faced=battersFaced
        return faced == 0 ? 0:max(0,min(100,50+100*Double(l.pitchingStrikeouts-l.pitchingWalks-2*homeRunsAllowed)/Double(faced)))
    }
    var passed:Bool {role == .batter ? totals.line.plateAppearances >= 12 && score >= 25:battersFaced >= 12 && score >= 45}
    func validate() throws {
        guard version == 1,[4,7].contains(window.month),try GameDate(date)<window.start,
              totals.games == (role == .batter ? 4:2),(0...1000).contains(battersFaced),(0...1000).contains(homeRunsAllowed),score.isFinite else {throw MatchError.invalidRecord}
        var check=PersonalSeasonTotals()
        try check.add(totals.line)
    }
}
struct CareerCertification:Codable,Equatable {
    var version=1
    let playerID:UUID
    let releaseOfferID:String
    let window:ContractEvaluationWindow
    let date:String
    let role:PlayerRole
    let position:String
    let values:PlayerInitialValues
    let seed:UInt64
    var calendarRevision:Int
    var games:[CareerMatch]=[]
    var completed:Bool {games.count == (role == .batter ? 4:2)}
    var key:String {playerID.uuidString+":"+releaseOfferID+":"+window.id}
    var assessment:CertifiedAssessment? {
        guard completed else {return nil}
        var totals=PersonalSeasonTotals()
        for game in games {guard (try? totals.add(game.line)) != nil else {return nil}}
        return CertifiedAssessment(key:key,playerID:playerID,releaseOfferID:releaseOfferID,window:window,date:date,role:role,totals:totals,battersFaced:games.reduce(0){$0+($1.scoutingPerformance?.battersFaced ?? 0)},homeRunsAllowed:games.reduce(0){$0+($1.scoutingPerformance?.homersAllowed ?? 0)})
    }
    @MainActor mutating func advance() throws {
        guard !completed else {throw MatchError.finished}
        var match=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:seed &+ UInt64(games.count),home:games.count%2 == 0,tracked:true,battedBallVersion:1)
        try match.advance(.automatic);games.append(match)
    }
    func validate() throws {
        guard version == 1,seed == DomesticSelection.hash(key),games.count <= (role == .batter ? 4:2),calendarRevision >= 0,try GameDate(date)<window.start,
              [4,7].contains(window.month),[values.contact,values.power,values.discipline,values.speed,values.defense,values.arm,values.mental].allSatisfy({$0.isFinite && (0...100).contains($0)}),
              values.pitches.values.allSatisfy({$0.isFinite && (0...100).contains($0)}) else {throw MatchError.invalidRecord}
        for game in games {
            guard game.completed,game.role == role.rawValue,game.appearance,game.abilityExperience == nil,game.positionExperience == nil,
                  let performance=game.scoutingPerformance,performance.inputs?.direct == 0 else {throw MatchError.invalidRecord}
            try performance.validate(line:game.line,role:role)
            try game.validatePitching();try game.validateDetailedField()
        }
        if completed {guard let assessment else {throw MatchError.invalidRecord};try assessment.validate()}
    }
}

enum CertificationError:LocalizedError {
    case pending
    var errorDescription:String? {"진행 중인 인증 평가전을 먼저 완료해 주세요. 저장된 경기부터 이어서 진행할 수 있습니다."}
}


// College early entry is a game rule; contracts start after the current annual season.
struct CollegeProReview:Codable,Equatable {
    let membership:CareerMembership
    let effectiveDate:String
    let results:[DomesticSelectionResult]
    static func effective(after date:GameDate) throws -> GameDate {
        guard date.year < 9995 else {throw ContractEvaluationError.invalid}
        return try GameDate(String(format:"%04d-04-01",date.year+1))
    }
    static func eligible(member:CareerMembership,age:Int,on date:GameDate) throws -> Bool {
        try member.route == .college && (22...23).contains(age) && member.contains(date)
            && date >= GameDate(member.since).anniversary(in:GameDate(member.since).year+2)
    }
    static func make(observation:ScoutingObservation,member:CareerMembership,window:ContractEvaluationWindow) throws -> Self {
        let date=try GameDate(observation.observedDate)
        guard window.month == 11,window == ContractEvaluationWindow.containing(date),
              try eligible(member:member,age:observation.age,on:date) else {throw ContractEvaluationError.invalid}
        // Never combine input modes, seasons, high-school or development statistics.
        let enough=observation.groups.contains {$0.id.hasPrefix("college/") && $0.performance != nil && (observation.role == .batter ? $0.hasBatterMinimum:$0.hasPitcherMinimum)}
        let roles=observation.role == .batter ? ["slugger","onBase","field"]:["starter"]
        let seed=observation.playerID.uuidString+"/college-pro/"+window.id
        var rows:[DomesticSelectionResult]=[]
        for team in CareerTeamDirectory.domesticIDs {
            for role in roles {
                let bits=DomesticSelection.hash(seed+team+role),c=max(DomesticSelection.minimum(role,route:.rookie),Double(52+bits%19))
                let h=observation.grades.first {$0.id == role}?.score,f=h.map {ScoutingContractFit.round($0-c)}
                let cost=DomesticSelection.cost(f ?? 0),budget=220+Int((bits/19)%101)
                var reasons:[String]=[]
                if !enough {reasons.append("동일 환경 대학 공식 성적40타석/15이닝 필요")}
                if h == nil {reasons.append("역할 기량 자료 부족")}
                reasons += DomesticSelection.fieldCondition(role,route:.rookie,observation:observation)
                if let f,f < 0 {reasons.append("국내 역할/고정 후보 경쟁 기준 미달 · F 0 필요")}
                if cost > budget {reasons.append("프로 진출 예산 부족")}
                rows.append(DomesticSelectionResult(id:"rookie/"+team.dropFirst(4)+"/"+role,name:CareerTeamDirectory.name(team),route:.rookie,role:role,h:h,c:c,p:0,f:f,cost:cost,availableBudget:budget,availableSeats:1,competition:1,selected:false,reasons:reasons))
            }
        }
        let winner=rows.filter {$0.reasons.isEmpty}.sorted {a,b in a.f == b.f ? a.id < b.id:a.f! > b.f!}.first?.id
        return Self(membership:member,effectiveDate:try effective(after:date).description,results:rows.map { row in
            DomesticSelectionResult(id:row.id,name:row.name,route:row.route,role:row.role,h:row.h,c:row.c,p:0,f:row.f,cost:row.cost,availableBudget:row.availableBudget,availableSeats:1,competition:1,selected:row.id == winner,reasons:row.reasons.isEmpty && row.id != winner ? ["다른 프로 진출 자리 우선 배정"]:row.reasons)
        })
    }
}

// Eligibility evidence is separate from selection, economic expiry and recognized pro service.
enum OverseasRoute:String,Codable,CaseIterable,Identifiable {
    case mlbDevelopment,npbFirstTeam,mlbFirstTeam
    var id:String {rawValue}
    var label:String {switch self {case .mlbDevelopment:"MLB 조직 육성";case .npbFirstTeam:"NPB 전력";case .mlbFirstTeam:"MLB 메이저 전력"}}
}
enum OverseasEligibilityStatus:String,Codable {case reviewable,blocked,unverified
    var label:String {switch self {case .reviewable:"기량·선발 검토 가능";case .blocked:"조건 부족";case .unverified:"자료 미확인"}}
}
struct OverseasMatchEvidence:Codable,Equatable {
    let key:String
    let date:String
    let level:String
}
struct OverseasCareerEvidence:Codable,Equatable {
    let version:Int
    let playerID:UUID
    let date:String
    let age:Int
    let calendarRevision:Int
    let registrationRevision:Int
    let historySource:String
    let origin:String
    let startAge:Int
    let memberships:[CareerMembership]
    let current:CareerMembership?
    let pendingCollegeEntry:Bool
    let release:DomesticRelease?
    let matches:[OverseasMatchEvidence]
    var approvedRoutes:[OverseasRoute]? = nil
    var gameProYears:[Int]? = nil
    var pendingForeignEntry:Bool? = nil
    var observedProYears:[Int] {Array(Set(matches.filter {$0.level == "domestic-first-team" || $0.level == "npb-first-team"}.compactMap {try? GameDate($0.date).year})).sorted()}
    // Existing saves do not contain MLB-recognized service or nationality/residency evidence.
    var recognizedForeignProSeasons:Int? {nil}
    func validate() throws {
        let today=try GameDate(date)
        guard [1,2].contains(version),age == (try GameDate(origin).age(startingAt:startAge,on:today)),startAge == 16,age >= 16,calendarRevision >= 0,registrationRevision >= 0,
              ["initial-v1","legacy-v1"].contains(historySource),Set(matches.map(\.key)).count == matches.count,
              matches == matches.sorted(by:{$0.key<$1.key}),Set(memberships.map(\.offerID)).count == memberships.count else {throw ContractEvaluationError.invalid}
        for row in matches {
            guard try GameDate(row.date) <= today,(version == 1 ? ["highschool","college","domestic-development"]:["highschool","college","domestic-development","mlb-development","domestic-first-team","npb-first-team","mlb-first-team"]).contains(row.level),row.key.hasPrefix(playerID.uuidString+":") else {throw ContractEvaluationError.invalid}
        }
        if let years=gameProYears {guard years == Array(Set(years)).sorted(),years.allSatisfy({$0<today.year}) else {throw ContractEvaluationError.invalid}}
        if let current {guard memberships.contains(where:{$0.offerID == current.offerID}),try current.contains(today) else {throw ContractEvaluationError.invalid}}
        if let release {guard try GameDate(release.date) <= today,memberships.contains(where:{$0.offerID == release.membershipOfferID && $0.route == .rookie}) else {throw ContractEvaluationError.invalid}}
    }
}
struct OverseasRouteEligibility:Codable,Equatable,Identifiable {
    let route:OverseasRoute
    let status:OverseasEligibilityStatus
    let reasons:[String]
    var id:String {route.id}
}
struct OverseasEligibilitySnapshot:Codable,Equatable {
    let version:Int
    let policy:String
    let evidence:OverseasCareerEvidence
    let routes:[OverseasRouteEligibility]
    var id:String {evidence.playerID.uuidString+":"+evidence.date+":overseas-eligibility-v1:"+String(evidence.calendarRevision)+":"+String(evidence.registrationRevision)}
    static func make(_ evidence:OverseasCareerEvidence) throws -> Self {
        try evidence.validate()
        var routes=OverseasRoute.allCases.map {route -> OverseasRouteEligibility in
            var reasons:[String]=[]
            var status:OverseasEligibilityStatus = .reviewable
            if evidence.age < 20 {status = .blocked;reasons.append("게임 성인 진로는20세부터 · 현재는 관심 관찰만 가능")}
            if evidence.current?.route == .rookie {status = .blocked;reasons.append("현재 구단 보유권리 유지 · 경제 기간 종료와 해외 이적 승인은 별개")}
            if evidence.pendingCollegeEntry {status = .blocked;reasons.append("이미 수락한 국내 프로 전환 예약이 있음")}
            if route != .mlbDevelopment {
                status = status == .blocked ? .blocked:.unverified
                reasons.append("국내 육성팀/대학 성적을 프로1군 성적으로 인정하지 않음 · 전력 경력/표본 필요")
                if evidence.current?.route == .college {status = .blocked;reasons.append("대학에서 NPB/MLB 전력 직행은 현재 지원 경로가 아님")}
            }
            if route == .mlbFirstTeam {
                reasons.append("MLB 인정 해외 프로시즌·기존 미국계약 이력 미확인 · 나이25세만으로 제한 면제하지 않음")
            }
            if route == .mlbDevelopment {
                reasons.append("국제계약 분류/서명기간·등록·선발/예산 확인 필요 · 검토 가능은 정식 제의 자격 확정이 아님")
            }
            if evidence.historySource == "legacy-v1" {reasons.append("기존 저장의 등록 이전 경력은 미확인 · 나이/달력으로 추정하지 않음")}
            return OverseasRouteEligibility(route:route,status:status,reasons:reasons)
        }
        let extended=evidence.approvedRoutes != nil || evidence.gameProYears != nil || evidence.pendingForeignEntry != nil
        if extended,let member=evidence.current,["domestic-first-team","npb-first-team"].contains(member.level) {
            routes=OverseasRoute.allCases.map {route in
                var reasons:[String]=[]
                var status:OverseasEligibilityStatus = .reviewable
                if evidence.approvedRoutes?.contains(route) != true {status = .blocked;reasons.append("현재 창의 게임 구단 해외 이적 승인 필요 · 권리는 유지")}
                if route == .mlbFirstTeam && !(evidence.age >= 25 && (evidence.gameProYears?.count ?? 0) >= 6) {
                    status = .blocked;reasons.append("게임 나이25세·근거 있는1군6개 완료연도 필요")
                }
                if evidence.pendingForeignEntry == true {status = .blocked;reasons.append("이미 수락한 해외 전환 예약이 있음")}
                reasons.append("게임 승인/경력은 실제MLB/NPB의 법적 자격 인증이 아님 · 기량/모집·등록 심사 별도")
                return OverseasRouteEligibility(route:route,status:status,reasons:reasons)
            }
        } else if extended,(evidence.current == nil || evidence.current?.level == "mlb-first-team"),!(evidence.approvedRoutes ?? []).isEmpty {
            routes=OverseasRoute.allCases.map {route in
                let allowed=evidence.approvedRoutes?.contains(route) == true && evidence.pendingForeignEntry != true
                return OverseasRouteEligibility(route:route,status:allowed ? .reviewable:.blocked,reasons:allowed ? ["권리 해제/FA 경로 · 역할·표본/자리·예산 선발은 별도"]:["현재 경로의 지원 자격 또는 전환 예약 확인 필요"])
            }
        } else if evidence.pendingForeignEntry == true {
            routes=routes.map {OverseasRouteEligibility(route:$0.route,status:.blocked,reasons:["이미 수락한 해외 전환 예약이 있음"]+$0.reasons)}
        }
        return Self(version:extended ? 2:1,policy:extended ? "overseas-eligibility-v2/game-reference":"overseas-eligibility-v1/2026-reference",evidence:evidence,routes:routes)
    }
    func validate(playerID:UUID,today:GameDate) throws {
        guard [1,2].contains(version),policy == (version == 1 ? "overseas-eligibility-v1/2026-reference":"overseas-eligibility-v2/game-reference"),evidence.playerID == playerID,
              try GameDate(evidence.date) <= today,self == (try Self.make(evidence)) else {throw ContractEvaluationError.invalid}
    }
}

// New adult reference pool; old high-school/reference versions and frozen reports stay unchanged.
@MainActor extension ScoutingReferenceSimulation {
    static func adultProfiles(level:String,role:PlayerRole) -> [PlayerInitialValues] {
        let extra=level == "college" ? 6.0:level == "domestic-first-team" ? 18:level == "npb-first-team" ? 24:level == "mlb-first-team" ? 30:12.0
        return PlayerArchetype.choices(for:role).map {type in
            let v=type.values
            func up(_ n:Double) -> Double {min(100,n+extra)}
            var value=PlayerInitialValues(contact:up(v.contact),power:up(v.power),discipline:up(v.discipline),speed:up(v.speed),defense:up(v.defense),arm:up(v.arm))
            value.mental=up(v.mental);value.velocity=v.velocity.map(up);value.control=v.control.map(up)
            value.stuff=v.stuff.map(up);value.stamina=v.stamina.map(up);value.pitches=v.pitches.mapValues(up)
            return value
        }
    }
    static func adult(environment:String,role:PlayerRole,position:String) throws -> ScoutingReference? {
        guard let level=environment.components(separatedBy:"/").first,["college","domestic-development","domestic-first-team","mlb-development","npb-first-team","mlb-first-team"].contains(level),
              let mode=ScoutingInputMode.allCases.first(where:{environment.hasSuffix("/"+$0.suffix)}),
              role == .pitcher ? position == "P":FieldPosition(rawValue:position) != nil else {return nil}
        if environment.contains("-attack"),!environment.contains("-attack1-") || !environment.contains("-npc1-") || !environment.contains("-batted1-") {return nil}
        let key="adult-reference-v1/"+environment
        if let found=cache[key] {return found}
        let profiles=adultProfiles(level:level,role:role),count=role == .batter ? 20:6
        var totals=PersonalSeasonTotals(),performance=MatchScoutingPerformance.tracked
        for (index,profile) in profiles.enumerated() {
            for game in 0..<count {
                let seed=UInt64(1_211_001+index*1_000+game),home=game%2 == 0
                let modern=environment.contains("-attack1-"),ids=CareerTeamDirectory.teams(level:level)
                let roster=MatchNPCFielders.make(year:2026,competition:level,homeID:home ? ids[0]:ids[1+Int(seed%5)],awayID:home ? ids[1+Int(seed%5)]:ids[0])
                var match=fixture(role:role,position:position,values:profile,seed:seed,home:home,tracked:true,
                    battedBallVersion:environment.contains("-batted1-") ? 1:nil,npcFieldersVersion:environment.contains("-npc1-") ? 1:nil,
                    assessmentRoster:modern ? roster:nil,npcAttackVersion:modern ? 1:nil,competition:modern ? level:nil)
                match.competition=level
                if !modern,match.npcFielders != nil {match.npcFielders=roster}
                guard match.scoutingEnvironment?.components(separatedBy:"/").dropLast().joined(separator:"/") == environment.components(separatedBy:"/").dropLast().joined(separator:"/") else {return nil}
                try run(&match,mode:mode)
                let perf=match.scoutingPerformance!;try perf.validate(line:match.line,role:role)
                try totals.add(match.line);try performance.add(perf)
            }
        }
        var result=ScoutingReference(environment:environment,role:role,position:position,profiles:profiles,gamesPerProfile:count,totals:totals,performance:performance)
        result.version=3;result.inputPolicy="adult-standard-controls-v1";result.inputMode=mode
        try result.validate();cache[key]=result;return result
    }
}

struct OverseasGrowthProjection:Codable,Equatable,Identifiable {
    let roleID:String
    let current:Double?
    let conservative:Double?
    let baseline:Double?
    let optimistic:Double?
    var id:String {roleID}
    static func make(observation:ScoutingObservation) throws -> [Self] {
        let date=try GameDate(observation.observedDate),origin=try GameDate(observation.origin)
        guard date.year < 9996 else {throw ContractEvaluationError.invalid}
        let end=date.anniversary(in:date.year+2),days=date.days(to:end)
        func projected(roleID:String,score:Double,fatigue:Int) throws -> Double? {
            var values=Dictionary(uniqueKeysWithValues:observation.abilities.originals.map {($0.id,$0.current)})
            var pitches=Dictionary(uniqueKeysWithValues:observation.abilities.pitches.map {($0.id,$0.current)})
            let selected=roleID == "field" ? ["homeContact","homePower","homeDiscipline","homeSpeed","homeDefense","homeArm","homeMental"]:roleID == "starter" ? ["homeVelocity","homeControl","homeStuff","homeStamina","homeMental"]:["homeContact","homePower","homeDiscipline","homeMental"]
            let keys=(selected.filter {values[$0] != nil}+(roleID == "starter" ? pitches.keys.map {"pitch/"+$0}:[])).sorted()
            guard !keys.isEmpty else {return nil}
            for step in 0..<360 {
                let target=date.adding(days:(step+1)*days/360),age=origin.age(startingAt:16,on:target),key=keys[step%keys.count]
                if key.hasPrefix("pitch/") {
                    let pitch=String(key.dropFirst(6)),before=pitches[pitch]!
                    pitches[pitch]=TrainingRules.growth(before:before,score:score,fatigue:fatigue,age:age,pitch:true)
                } else {values[key]=TrainingRules.growth(before:values[key]!,score:score,fatigue:fatigue,age:age,pitch:false)}
            }
            let originals=observation.abilities.originals.map {HomeAbilityValue(id:$0.id,label:$0.label,current:values[$0.id]!,initial:$0.initial)}
            let pitchValues=observation.abilities.pitches.map {HomeAbilityValue(id:$0.id,label:$0.label,current:pitches[$0.id]!,initial:$0.initial)}
            let summary=HomeAbilitySummary(axes:observation.abilities.axes,originals:originals,pitches:pitchValues,hasInitialValues:observation.abilities.hasInitialValues)
            return try ScoutingRoleEvaluation.grades(role:observation.role,abilities:summary,positionMastery:observation.positionMastery).first {$0.id == roleID}?.score
        }
        return try observation.grades.map {grade in
            Self(roleID:grade.id,current:grade.score,conservative:try projected(roleID:grade.id,score:50,fatigue:60),baseline:try projected(roleID:grade.id,score:75,fatigue:40),optimistic:try projected(roleID:grade.id,score:100,fatigue:0))
        }
    }
}
struct OverseasScoutingReport:Codable {
    let version:Int
    let period:Int
    let eligibility:OverseasEligibilitySnapshot
    let observation:ScoutingObservation
    let comparisons:[ScoutingPerformanceComparison]
    let projections:[OverseasGrowthProjection]
    var market:OverseasMarket? = nil
    var id:String {observation.playerID.uuidString+":overseas-report-v1:"+String(period)}
    var selected:ScoutingPerformanceComparison? {ScoutingContractFit.selected(comparisons,role:observation.role)}
    @MainActor static func make(observation:ScoutingObservation,eligibility:OverseasEligibilitySnapshot) throws -> Self {
        let level=eligibility.evidence.current?.level ?? eligibility.evidence.memberships.last?.level ?? "highschool"
        let groups=observation.groups.filter {$0.id.hasPrefix(level+"/")}
        let comparisons=try groups.map {group -> ScoutingPerformanceComparison in
            let ref=try ScoutingReferenceSimulation.adult(environment:group.id,role:observation.role,position:observation.role == .pitcher ? "P":observation.position)
            let value=group.performance?.contribution(group.totals.line,role:observation.role)
            let modern=group.performance?.version == 2,verified=modern && value != nil && ref?.value != nil
            let p=verified ? ScoutingContractFit.correction(value:value!,reference:ref!.value!,n:group.performance!.sample(group.totals.line,role:observation.role)):0
            return ScoutingPerformanceComparison(id:group.id,totals:group.totals,performance:group.performance,reference:ref,value:value,correction:p,verified:verified,reason:verified ? "성인 표준 NPC 기준 · 원소속 수준/입력 환경 분리":"지원 환경/성적 비교 미검증 · P=0")
        }
        var result=Self(version:3,period:observation.period,eligibility:eligibility,observation:observation,comparisons:comparisons,projections:try OverseasGrowthProjection.make(observation:observation))
        result.market=OverseasMarket.make(report:result,version:2);return result
    }
    func validate(playerID:UUID,today:GameDate) throws {
        try eligibility.validate(playerID:playerID,today:today);try observation.validate()
        guard [1,2,3].contains(version),observation.playerID == playerID,period == observation.period,eligibility.evidence.date == observation.observedDate,
              comparisons.count <= observation.groups.count,Set(comparisons.map(\.id)).count == comparisons.count,
              projections == (try OverseasGrowthProjection.make(observation:observation)) else {throw ContractEvaluationError.invalid}
        guard version == 1 ? market == nil:market == OverseasMarket.make(report:self,version:version == 3 ? 2:1) else {throw ContractEvaluationError.invalid}
        let level=eligibility.evidence.current?.level ?? eligibility.evidence.memberships.last?.level ?? "highschool"
        guard comparisons.map(\.id) == observation.groups.filter({$0.id.hasPrefix(level+"/")}).map(\.id) else {throw ContractEvaluationError.invalid}
        for row in comparisons {
            guard let group=observation.groups.first(where:{$0.id == row.id}),group.totals == row.totals,group.performance == row.performance else {throw ContractEvaluationError.invalid}
            if let ref=row.reference {
                try ref.validate()
                guard ref.version == 3,ref.environment == row.id,ref.role == observation.role,ref.position == (observation.role == .pitcher ? "P":observation.position) else {throw ContractEvaluationError.invalid}
            }
            let value=row.performance?.contribution(row.totals.line,role:observation.role)
            let verified=row.performance?.version == 2 && value != nil && row.reference?.value != nil
            let p=verified ? ScoutingContractFit.correction(value:value!,reference:row.reference!.value!,n:row.performance!.sample(row.totals.line,role:observation.role)):0
            guard row.value == value,row.verified == verified,row.correction == p else {throw ContractEvaluationError.invalid}
        }
    }
}

struct OverseasClubEvaluation:Codable,Equatable,Identifiable {
    let id:String
    let name:String
    let route:OverseasRoute
    let roleID:String
    let demand:RecruitmentDemand
    let criterion:Double
    let competitor:Double?
    let budget:Int
    let seats:Int
    let h:Double?
    let projection:Double?
    let p:Double
    let f:Double?
    let interest:ScoutingInterestLevel?
    let blockers:[String]
}
struct OverseasMarket:Codable,Equatable {
    let version:Int
    let seed:String
    let clubs:[OverseasClubEvaluation]
    static let americanNames=["퍼시픽 웨이브스","캐니언 호크스","레이크 베어스","메트로 나이츠","애틀랜틱 세일러스","프레리 버팔로스"]
    static let japaneseNames=["동도 스카이스","항남 마리너즈","서경 피닉스","북해 스노우스","중앙 레일즈","남양 선즈"]
    static func minimum(_ route:OverseasRoute,_ role:String) -> Double {
        let rows:[OverseasRoute:[String:Double]]=[.mlbDevelopment:["slugger":68,"onBase":65,"field":62,"starter":65],.npbFirstTeam:["slugger":80,"onBase":77,"field":73,"starter":76],.mlbFirstTeam:["slugger":88,"onBase":85,"field":81,"starter":84]]
        return rows[route]![role]!
    }
    static func make(report:OverseasScoutingReport,version:Int=1) -> Self {
        let seed=report.observation.playerID.uuidString+"/overseas-market-v1/"+String(report.period)
        let source=report.selected,role=report.observation.role
        let enough=source.map {role == .batter ? $0.totals.line.plateAppearances >= 40:$0.totals.line.pitchingOuts >= 45} ?? false
        let p=enough ? source?.correction ?? 0:0
        var rows:[OverseasClubEvaluation]=[]
        for route in OverseasRoute.allCases {
            let names=route == .npbFirstTeam ? japaneseNames:americanNames
            for index in names.indices {for grade in report.observation.grades {
                let id=route.id+"/\(index)/"+grade.id,bits=DomesticSelection.hash(seed+id)
                let demand:RecruitmentDemand=bits%5 == 0 ? .none:bits%3 == 0 ? .vacancy:.depth
                let minimum=minimum(route,grade.id),competitor=demand == .vacancy ? nil:minimum+Double((bits/11)%9)
                let c=max(minimum,competitor ?? minimum),f=grade.score.map {ScoutingContractFit.round($0-c+p)}
                let budget=(version == 2 && route != .mlbDevelopment ? 800:300)+Int((bits/23)%401),seats=demand == .none ? 0:1
                let projected=report.projections.first {$0.roleID == grade.id}?.baseline
                var blockers:[String]=[]
                if !enough {blockers.append("동일 환경 관찰40타석/15이닝 필요")}
                if seats == 0 {blockers.append("현재 역할 모집 없음")}
                if grade.score == nil {blockers.append("역할 기량 미확인")}
                if let f,f < 0 {blockers.append("현재 기량 F "+String(format:"%+.1f",f)+" · 계약 기준0 보완")}
                if grade.id == "field" {
                    if (report.observation.positionMastery ?? 0)<70 || (report.observation.abilities.originals.first {$0.id == "homeDefense"}?.current ?? 0)<70 {blockers.append("주 포지션/원본 수비70 필요")}
                    let values=Dictionary(uniqueKeysWithValues:report.observation.abilities.originals.map {($0.id,$0.current)})
                    let attack=(values["homeContact"] ?? 0)*0.5+(values["homePower"] ?? 0)*0.15+(values["homeDiscipline"] ?? 0)*0.35
                    if route != .mlbDevelopment && attack < (route == .npbFirstTeam ? 60:68) {blockers.append("수비형 해외 공격 기량 기준 부족")}
                    if report.observation.position == "C" {blockers.append("해외 포수 전용 사건/평가 검증 필요")}
                }
                if let eligibility=report.eligibility.routes.first(where:{$0.route == route}),eligibility.status != .reviewable {blockers += eligibility.reasons}
                let interest=enough && seats>0 ? f.flatMap(ScoutingInterestLevel.at):nil
                rows.append(OverseasClubEvaluation(id:id,name:names[index],route:route,roleID:grade.id,demand:demand,criterion:c,competitor:competitor,budget:budget,seats:seats,h:grade.score,projection:projected,p:p,f:f,interest:interest,blockers:blockers))
            }}
        }
        return Self(version:version,seed:seed,clubs:rows)
    }
}

struct OverseasOffer:Codable,Equatable,Identifiable {
    let id:String
    let clubID:String
    let teamID:String
    let name:String
    let route:OverseasRoute
    let roleID:String
    let issued:String
    let expires:String
    let effective:String
    let economicEnd:String
    let economicIndex:Int
    let years:Int
    let h:Double
    let c:Double
    let p:Double
    let margin:Double
    func membership() -> CareerMembership {
        var value=CareerMembership(offerID:id,route:.rookie,teamID:teamID,name:name,since:effective,economicEnd:economicEnd,enrollmentEnd:nil,economicIndex:economicIndex)
        value.competitionLevel=route == .mlbDevelopment ? "mlb-development":route == .npbFirstTeam ? "npb-first-team":"mlb-first-team"
        return value
    }
}
struct OverseasOfferEvaluation:Codable,Equatable,Identifiable {
    let version:Int
    let id:String
    let window:ContractEvaluationWindow
    let date:String
    let reportID:String
    let source:CareerMembership?
    let registeredAt:String?
    let reservedAtEvaluation:Bool
    var sourceMembershipID:String? {source?.offerID}
    let offers:[OverseasOffer]
    let reasons:[String]
    var professional:OverseasProContext? = nil
    var mobility:OverseasMobilityContext? = nil
    static func make(report:OverseasScoutingReport,window:ContractEvaluationWindow,on date:GameDate,registrationDate:String?,member:CareerMembership?,reserved:Bool) throws -> Self {
        guard window == ContractEvaluationWindow.containing(date),date.year < 9995,
              report.observation.observedDate <= date.description else {throw ContractEvaluationError.invalid}
        let id=report.observation.playerID.uuidString+":overseas-offer-v1:"+window.id
        var reasons:[String]=[],offers:[OverseasOffer]=[]
        if registrationDate == nil || registrationDate! > date.description {reasons.append("게임 국제계약 지원자 등록 필요")}
        if report.observation.age < 20 {reasons.append("게임 성인 진로20세 미충족")}
        if member?.route == .rookie {reasons.append("현 구단 보유권리/이적 승인 확인 필요")}
        if reserved {reasons.append("이미 수락한 소속 전환 예약이 있음")}
        let source=report.selected,enough=source.map {report.observation.role == .batter ? $0.totals.line.plateAppearances >= 40:$0.totals.line.pitchingOuts >= 45} ?? false
        if !enough {reasons.append("검증된 동일 환경 관찰40타석/15이닝 필요")}
        let strengths=report.observation.abilities.originals.filter {$0.id != "homeMental"}+report.observation.abilities.pitches
        if !strengths.contains(where:{$0.current >= 75}) {reasons.append("멘탈 제외 핵심 능력/구종75 이상 필요")}
        if report.market == nil {reasons.append("해외 모집 자료 없음 · 다음 보고서 필요")}
        if reasons.isEmpty {
            let candidates=(report.market?.clubs ?? []).filter {row in
                guard row.route == .mlbDevelopment,row.seats == 1,let h=row.h,let projected=row.projection else {return false}
                let roleSpecific=row.blockers.contains {$0.contains("수비70") || $0.contains("포수 전용")}
                let margin=projected-row.criterion+row.p
                return !roleSpecific && h >= row.criterion-5 && projected >= row.criterion && margin >= 0 && 100+Int((6*margin).rounded()) <= row.budget
            }.sorted {a,b in
                let left=(a.projection ?? 0)-a.criterion+a.p,right=(b.projection ?? 0)-b.criterion+b.p
                return left == right ? a.id<b.id:left>right
            }
            // At most two external clubs; one best role per club.
            var teams=Set<String>()
            for row in candidates {
                let parts=row.id.components(separatedBy:"/")
                guard teams.insert(parts[1]).inserted else {continue}
                let start=try GameDate(String(format:"%04d-04-01",date.year+1)),margin=(row.projection ?? 0)-row.criterion+row.p
                offers.append(OverseasOffer(id:id+"/"+row.id,clubID:row.id,teamID:"us-dev-"+parts[1],name:row.name,route:.mlbDevelopment,roleID:row.roleID,issued:date.description,expires:min(date.adding(days:6),window.end).description,effective:start.description,economicEnd:start.anniversary(in:start.year+1).adding(days:-1).description,economicIndex:100+Int((6*margin).rounded()),years:1,h:row.h!,c:row.criterion,p:row.p,margin:margin))
                if offers.count == 2 {break}
            }
            if offers.isEmpty {reasons.append("성장 전망/현재 기량·역할 조건 또는 모집 예산/경쟁 기준 미달")}
        }
        return Self(version:1,id:id,window:window,date:date.description,reportID:report.id,source:member,registeredAt:registrationDate,reservedAtEvaluation:reserved,offers:offers,reasons:reasons)
    }
}
struct OverseasDecision:Codable,Equatable {let offerID:String;let kind:DomesticOfferDecisionKind;let date:String}
struct OverseasTransition:Codable,Equatable {let offerID:String;let sourceMembershipID:String?;let acceptedDate:String;let destination:CareerMembership}
struct OverseasCareerJournal:Codable,Equatable {
    var version=1
    var registrationDate:String?
    var evaluations:[OverseasOfferEvaluation]=[]
    var decisions:[OverseasDecision]=[]
    var transitions:[OverseasTransition]=[]
    var promotions:[CareerLevelPromotion]? = nil
    var consents:[ClubTransferConsent]? = nil
    var service:[GameProSeasonEvidence]? = nil
    var renewalReviews:[OverseasRenewalReview]? = nil
    var renewalDecisions:[OverseasRenewalDecision]? = nil
    var releases:[OverseasRelease]? = nil
    var faService:[FASeasonEvidence]? = nil
    var faDeclarations:[FADeclaration]? = nil
    func hasPending(on date:String) -> Bool {transitions.contains {$0.destination.since > date}}
    func validate(owner:CareerContractJournal,today:GameDate) throws {
        guard version == 1,Set(evaluations.map(\.id)).count == evaluations.count,Set(decisions.map(\.offerID)).count == decisions.count,
              Set(transitions.map(\.offerID)).count == transitions.count else {throw ContractRegistrationError.invalid}
        if let registrationDate {guard try GameDate(registrationDate) <= today else {throw ContractRegistrationError.invalid}}
        try validateRenewals(owner:owner,today:today)
        try validateReleases(owner:owner,today:today)
        try validateFA(owner:owner,today:today)
        let promotions=promotions ?? []
        guard Set(promotions.map(\.id)).count == promotions.count else {throw ContractRegistrationError.invalid}
        for item in promotions {
            guard item.date <= today.description,try GameDate(item.effective) == CollegeProReview.effective(after:GameDate(item.date)),
                  item.h >= 65,item.sampleCount > 0,
                  let report=owner.overseasReports?.first(where:{$0.id == item.reportID}),
                  report.eligibility.evidence.current?.offerID == item.sourceOfferID,report.eligibility.evidence.current?.level == item.fromLevel,
                  item.sampleCount == (report.observation.role == .batter ? report.selected?.totals.line.plateAppearances:report.selected?.totals.line.pitchingOuts),
                  owner.membershipHistory().contains(where:{$0.offerID == item.sourceOfferID && $0.route == .rookie}) else {throw ContractRegistrationError.invalid}
            if item.fromLevel == "domestic-development" {
                guard item.roleID == nil,item.toLevel == "domestic-first-team",CareerTeamDirectory.domesticFirstIDs.contains(item.teamID),item.h == report.observation.grades.compactMap(\.score).max(),item.sampleCount >= (report.observation.role == .batter ? 40:45) else {throw ContractRegistrationError.invalid}
            } else {
                guard item.fromLevel == "mlb-development",item.toLevel == "mlb-first-team",CareerTeamDirectory.americanFirstIDs.contains(item.teamID),
                      let grade=CareerLevelPromotion.majorRole(report),item.roleID == grade.id,item.h == grade.score,
                      item.sampleCount >= (report.observation.role == .batter ? 100:75) else {throw ContractRegistrationError.invalid}
            }
        }
        let consents=consents ?? []
        guard Set(consents.map(\.id)).count == consents.count else {throw ContractRegistrationError.invalid}
        for item in consents {
            guard let report=owner.overseasReports?.first(where:{$0.id == item.reportID}),let member=try owner.current(on:GameDate(item.date)),let window=try ContractEvaluationWindow.containing(GameDate(item.date)),
                  item == (try ClubTransferConsent.make(report:report,member:member,window:window,on:GameDate(item.date))) else {throw ContractRegistrationError.invalid}
        }
        for evaluation in evaluations {
            guard let report=owner.overseasReports?.first(where:{$0.id == evaluation.reportID}),try GameDate(evaluation.date)<=today,
                  [1,2,3].contains(evaluation.version) else {throw ContractRegistrationError.invalid}
            if evaluation.version == 1 {
                guard evaluation.professional == nil,evaluation.mobility == nil,evaluation == (try OverseasOfferEvaluation.make(report:report,window:evaluation.window,on:GameDate(evaluation.date),registrationDate:evaluation.registeredAt,member:evaluation.source,reserved:evaluation.reservedAtEvaluation)) else {throw ContractRegistrationError.invalid}
            } else if evaluation.version == 2 {
                guard evaluation.mobility == nil,let proof=evaluation.professional,let member=evaluation.source,consents.contains(proof.consent),proof.service.allSatisfy({(service ?? []).contains($0)}),
                      evaluation == (try OverseasOfferEvaluation.makeProfessional(report:report,window:evaluation.window,on:GameDate(evaluation.date),registrationDate:evaluation.registeredAt,member:member,context:proof,reserved:evaluation.reservedAtEvaluation)) else {throw ContractRegistrationError.invalid}
            } else {
                guard evaluation.professional == nil,let proof=evaluation.mobility,
                      (proof.historicalReportID == nil && proof.historicalDate == nil && proof.historicalSample == nil) || owner.overseasReports?.contains(where:{$0.id == proof.historicalReportID && $0.observation.observedDate == proof.historicalDate && $0.selected == proof.historicalSample && $0.eligibility.evidence.current?.offerID == proof.source.offerID && $0.eligibility.evidence.current?.level == proof.source.level}) == true,
                      proof.service.allSatisfy({(faService ?? []).contains($0)}),(proof.internationalService ?? []).allSatisfy({(service ?? []).contains($0)}),
                      (proof.fa.map {(faDeclarations ?? []).contains($0)} ?? false) != (proof.release.map {(releases ?? []).contains($0)} ?? false),
                      evaluation == (try OverseasOfferEvaluation.makeMobility(report:report,window:evaluation.window,on:GameDate(evaluation.date),registrationDate:evaluation.registeredAt,member:evaluation.source,context:proof,reserved:evaluation.reservedAtEvaluation)) else {throw ContractRegistrationError.invalid}
            }
        }
        for evaluation in evaluations {
            if let registered=evaluation.registeredAt {guard registered == registrationDate,registered <= evaluation.date else {throw ContractRegistrationError.invalid}}
            if let source=evaluation.source {guard owner.membershipHistory().contains(where:{$0.offerID == source.offerID}) else {throw ContractRegistrationError.invalid}}
        }
        let offers=evaluations.flatMap(\.offers)
        for decision in decisions {
            guard let offer=offers.first(where:{$0.id == decision.offerID}),decision.date >= offer.issued,decision.date <= offer.expires,decision.date <= today.description else {throw ContractRegistrationError.invalid}
            if decision.kind == .accepted {guard transitions.contains(where:{$0.offerID == offer.id && $0.acceptedDate == decision.date && $0.destination == offer.membership()}) else {throw ContractRegistrationError.invalid}}
        }
        for transition in transitions {
            guard decisions.contains(where:{$0.offerID == transition.offerID && $0.kind == .accepted && $0.date == transition.acceptedDate}),
                  let evaluation=evaluations.first(where:{$0.offers.contains {$0.id == transition.offerID}}),evaluation.sourceMembershipID == transition.sourceMembershipID else {throw ContractRegistrationError.invalid}
        }
    }
}

struct CareerLevelPromotion:Codable,Equatable,Identifiable {
    let id:String
    let sourceOfferID:String
    let reportID:String
    let date:String
    let effective:String
    let fromLevel:String
    let toLevel:String
    let teamID:String
    let h:Double
    let sampleCount:Int
    var roleID:String? = nil
}
struct ClubTransferConsent:Codable,Equatable,Identifiable {
    let id:String
    let sourceOfferID:String
    let reportID:String
    let date:String
    let expires:String
    let approved:Bool
    let reasons:[String]
    static func make(report:OverseasScoutingReport,member:CareerMembership,window:ContractEvaluationWindow,on date:GameDate) throws -> Self {
        guard window.month == 11,window == ContractEvaluationWindow.containing(date),report.observation.observedDate <= date.description else {throw ContractEvaluationError.invalid}
        let source=report.selected,enough=source.map {report.observation.role == .batter ? $0.totals.line.plateAppearances >= 100:$0.totals.line.pitchingOuts >= 75} ?? false
        var reasons:[String]=[]
        if !["domestic-first-team","npb-first-team"].contains(member.level) {reasons.append("국내/일본1군 소속 선수의 구단 승인 경로만 지원")}
        if report.eligibility.evidence.current?.offerID != member.offerID || report.eligibility.evidence.current?.level != member.level {reasons.append("현재 소속 수준의 새 보고서 필요")}
        if !enough {reasons.append("동일 환경1군100타석/25이닝 필요")}
        if (report.observation.grades.compactMap(\.score).max() ?? 0)<75 {reasons.append("구단 이적 검토 역할 기량75 필요")}
        return Self(id:report.observation.playerID.uuidString+":club-consent-v1:"+window.id,sourceOfferID:member.offerID,reportID:report.id,date:date.description,expires:window.end.description,approved:reasons.isEmpty,reasons:reasons)
    }
}
struct GameProSeasonEvidence:Codable,Equatable {
    let year:Int
    let sourceOfferID:String
    let level:String
    let matchKeys:[String]
    static func collect(owner:CareerContractJournal,role:PlayerRole,today:GameDate,rows:[CareerMatchRecord]) throws -> [Self] {
        var result:[Self]=[]
        let years=Set(try rows.map {try GameDate($0.gameDate).year}).sorted()
        for year in years where year < today.year {
            let first=try GameDate(String(format:"%04d-01-01",year)),last=try GameDate(String(format:"%04d-12-31",year))
            guard let start=try owner.current(on:first),let end=try owner.current(on:last),start.offerID == end.offerID,start.level == end.level,["domestic-first-team","npb-first-team"].contains(start.level) else {continue}
            var keys:[String]=[],totals=PersonalSeasonTotals()
            for row in rows where row.completed && row.appearance && row.gameDate >= first.description && row.gameDate <= last.description {
                let match=try row.snapshot();guard match.competition == start.level else {continue}
                try totals.add(match.line);keys.append(row.key)
            }
            let enough=role == .batter ? totals.line.plateAppearances >= 100:totals.line.pitchingOuts >= 75
            if enough {result.append(Self(year:year,sourceOfferID:start.offerID,level:start.level,matchKeys:keys.sorted()))}
        }
        return result
    }
}

extension CareerContractJournal {
    func projected(_ member:CareerMembership,on date:GameDate,excludingRenewal:String?=nil) throws -> CareerMembership {
        var value=member
        if let promotion=overseasCareer?.promotions?.filter({$0.sourceOfferID == member.offerID && $0.effective <= date.description}).sorted(by:{$0.effective<$1.effective}).last {
            value=CareerMembership(offerID:member.offerID,route:member.route,teamID:promotion.teamID,name:CareerTeamDirectory.name(promotion.teamID),since:member.since,economicEnd:member.economicEnd,enrollmentEnd:member.enrollmentEnd,economicIndex:member.economicIndex)
            value.competitionLevel=promotion.toLevel;value.releasedOn=member.releasedOn;value.economicStart=member.economicStart
            if promotion.fromLevel == "mlb-development" {
                let start=try GameDate(promotion.effective)
                value=CareerMembership(offerID:value.offerID,route:value.route,teamID:value.teamID,name:value.name,since:value.since,economicEnd:start.anniversary(in:start.year+1).adding(days:-1).description,enrollmentEnd:nil,economicIndex:100)
                value.competitionLevel=promotion.toLevel;value.economicStart=promotion.effective;value.releasedOn=member.releasedOn
            }
        }
        // Apply signed renewals after placement; promotion must not restore initial pay/term.
        let state=overseasCareer ?? OverseasCareerJournal()
        for review in (state.renewalReviews ?? []).sorted(by:{$0.date<$1.date}) where review.source.offerID == member.offerID {
            guard let offer=review.offer,offer.id != excludingRenewal,offer.effective <= date.description,
                  !(state.promotions ?? []).contains(where:{$0.sourceOfferID == member.offerID && $0.fromLevel == "mlb-development" && $0.effective <= date.description && $0.effective > offer.effective}),
                  (state.renewalDecisions ?? []).contains(where:{$0.offerID == offer.id && $0.kind == .accepted && $0.date <= date.description}) else {continue}
            var updated=CareerMembership(offerID:value.offerID,route:value.route,teamID:value.teamID,name:value.name,since:value.since,economicEnd:offer.economicEnd,enrollmentEnd:value.enrollmentEnd,economicIndex:offer.economicIndex)
            updated.competitionLevel=value.competitionLevel;updated.releasedOn=value.releasedOn;updated.economicStart=offer.effective;value=updated
        }
        return value
    }
}

struct OverseasProContext:Codable,Equatable {
    let consent:ClubTransferConsent
    let service:[GameProSeasonEvidence]
}
extension OverseasOfferEvaluation {
    static func makeProfessional(report:OverseasScoutingReport,window:ContractEvaluationWindow,on date:GameDate,registrationDate:String?,member:CareerMembership,context:OverseasProContext,reserved:Bool) throws -> Self {
        guard window == ContractEvaluationWindow.containing(date),date.year < 9995 else {throw ContractEvaluationError.invalid}
        let id=report.observation.playerID.uuidString+":overseas-offer-v2:"+window.id
        var reasons:[String]=[],offers:[OverseasOffer]=[]
        if registrationDate == nil || registrationDate!>date.description {reasons.append("게임 국제계약 지원자 등록 필요")}
        if !context.consent.approved || context.consent.sourceOfferID != member.offerID || context.consent.date>date.description || context.consent.expires<date.description {reasons.append("유효한 현재 구단 이적 승인 필요")}
        if reserved {reasons.append("이미 수락한 소속/경제기간 전환이 있음")}
        if report.eligibility.evidence.current?.offerID != member.offerID || report.eligibility.evidence.current?.level != member.level {reasons.append("현재1군 수준의 보고서 필요")}
        let source=report.selected,enough=source.map {report.observation.role == .batter ? $0.totals.line.plateAppearances >= 100:$0.totals.line.pitchingOuts >= 75} ?? false
        if !enough {reasons.append("동일 환경 프로1군100타석/25이닝 필요")}
        let age=try GameDate(report.observation.origin).age(startingAt:16,on:date),years=Set(context.service.filter {$0.year<date.year}.map(\.year)).count
        if reasons.isEmpty {
            let candidates=(report.market?.clubs ?? []).filter {row in
                guard row.route != .mlbDevelopment,row.seats == 1,let f=row.f,f>=0,row.h != nil else {return false}
                if row.route == .mlbFirstTeam && !(age >= 25 && years >= 6) {return false}
                if row.blockers.contains(where:{$0.contains("수비70") || $0.contains("공격 기량") || $0.contains("포수 전용")}) {return false}
                let duration=min(f<5 ? 1:f<10 ? 2:3,age>=35 ? 1:age>=30 ? 2:3)
                return (100+Int((6*f).rounded()))*duration <= row.budget
            }.sorted {a,b in a.f == b.f ? a.id<b.id:(a.f ?? 0)>(b.f ?? 0)}
            var ordered:[OverseasClubEvaluation]=[]
            for route in [OverseasRoute.npbFirstTeam,.mlbFirstTeam] {if let best=candidates.first(where:{$0.route == route}) {ordered.append(best)}}
            ordered += candidates.filter {row in !ordered.contains(where:{$0.id == row.id})}
            var teams=Set<String>()
            for row in ordered {
                let parts=row.id.components(separatedBy:"/"),team=(row.route == .npbFirstTeam ? "jp-pro-":"us-pro-")+parts[1]
                guard teams.insert(team).inserted else {continue}
                let start=try GameDate(String(format:"%04d-04-01",date.year+1)),f=row.f!,duration=min(f<5 ? 1:f<10 ? 2:3,age>=35 ? 1:age>=30 ? 2:3)
                offers.append(OverseasOffer(id:id+"/"+row.id,clubID:row.id,teamID:team,name:row.name,route:row.route,roleID:row.roleID,issued:date.description,expires:min(date.adding(days:6),window.end).description,effective:start.description,economicEnd:start.anniversary(in:start.year+duration).adding(days:-1).description,economicIndex:100+Int((6*f).rounded()),years:duration,h:row.h!,c:row.criterion,p:row.p,margin:f))
                if offers.count == 2 {break}
            }
            if offers.isEmpty {reasons.append("전력 기량/역할·자리/예산/경쟁 조건 미달")}
            if !(age >= 25 && years>=6) {reasons.append("MLB 메이저 최초 전력 계약:게임 나이25세·근거 있는1군6개 완료연도 필요")}
        }
        var result=Self(version:2,id:id,window:window,date:date.description,reportID:report.id,source:member,registeredAt:registrationDate,reservedAtEvaluation:reserved,offers:offers,reasons:reasons)
        result.professional=context;return result
    }
}

extension CareerLevelPromotion {
    static func majorRole(_ report:OverseasScoutingReport) -> ScoutingRoleGrade? {
        let values=Dictionary(uniqueKeysWithValues:report.observation.abilities.originals.map {($0.id,$0.current)})
        return report.observation.grades.filter {grade in
            guard let h=grade.score,h >= OverseasMarket.minimum(.mlbFirstTeam,grade.id) else {return false}
            if grade.id == "field" {
                let attack=(values["homeContact"] ?? 0)*0.5+(values["homePower"] ?? 0)*0.15+(values["homeDiscipline"] ?? 0)*0.35
                return report.observation.position != "C" && (report.observation.positionMastery ?? 0)>=70 && (values["homeDefense"] ?? 0)>=70 && attack>=68
            }
            return true
        }.sorted {a,b in a.score == b.score ? a.id<b.id:a.score!>b.score!}.first
    }
}

enum OverseasProgressError:LocalizedError {
    case report,requirements,window,freeAgency
    var errorDescription:String? {
        switch self {
        case .report:"현재 주기의 해외 보고서를 먼저 기록해 주세요. 기존 자료와 소속은 유지됩니다."
        case .freeAgency:"정식 FA는 MLB6/NPB9개 검증 시즌, 계약 마지막 해, 11월1~14일의 별도 선언이 필요합니다. 기존 소속/권리는 유지됩니다."
        case .requirements:"승격 조건이 부족합니다. 현재 소속 수준의 보고서·역할 기량·공식 경기 표본을 확인해 주세요."
        case .window:"현재는 해당 심사 창이 아닙니다. 해외 제의는4·7·11월,승격/구단 승인은11월1~14일에 신청해 주세요."
        }
    }
}

struct OverseasRenewalDecision:Codable,Equatable {
    let offerID:String
    let kind:DomesticOfferDecisionKind
    let date:String
}
struct OverseasRenewalReview:Codable,Equatable,Identifiable {
    let version:Int
    let id:String
    let window:ContractEvaluationWindow
    let date:String
    let reportID:String
    let source:CareerMembership
    let reserved:Bool
    let roleID:String
    let sampleCount:Int
    let criterion:Double?
    let h:Double?
    let p:Double
    let budget:Int?
    let reasons:[String]
    let offer:OverseasOffer?
    static func route(_ member:CareerMembership) -> OverseasRoute? {
        switch member.level {
        case "mlb-development":.mlbDevelopment
        case "npb-first-team":.npbFirstTeam
        case "mlb-first-team":.mlbFirstTeam
        default:nil
        }
    }
    static func eligible(_ member:CareerMembership,on date:GameDate) throws -> Bool {
        guard route(member) != nil,date.year < 9995 else {return false}
        return try GameDate(member.economicEnd) < CollegeProReview.effective(after:date)
    }
    static func nextReview(_ member:CareerMembership,on date:GameDate,economicEnd:String?=nil) throws -> String {
        let year=max(date.year,try GameDate(economicEnd ?? member.economicEnd).year-1)
        let window=ContractEvaluationWindow(year:year,month:11)
        return ContractEvaluationWindow(year:date > window.end ? year+1:year,month:11).start.description
    }
    static func make(report:OverseasScoutingReport,member:CareerMembership,roleID:String,window:ContractEvaluationWindow,on date:GameDate,reserved:Bool) throws -> Self {
        guard window.month == 11,window == ContractEvaluationWindow.containing(date),try eligible(member,on:date),
              let route=route(member),report.observation.observedDate <= date.description,
              report.observation.grades.contains(where:{$0.id == roleID}) else {throw OverseasProgressError.requirements}
        let id=report.observation.playerID.uuidString+":overseas-renewal-v1:"+window.id
        let club=member.teamID.components(separatedBy:"-").last ?? ""
        let row=report.market?.clubs.first {$0.id == route.id+"/"+club+"/"+roleID}
        let sample=report.selected,count=sample.map {report.observation.role == .batter ? $0.totals.line.plateAppearances:$0.totals.line.pitchingOuts} ?? 0
        let minimum=report.observation.role == .batter ? (route == .mlbDevelopment ? 40:100):(route == .mlbDevelopment ? 45:75)
        let h=report.observation.grades.first {$0.id == roleID}?.score,p=sample?.correction ?? 0
        var reasons:[String]=[]
        if reserved {reasons.append("수락한 소속 전환·승격 또는 갱신 예약이 있음")}
        if report.eligibility.evidence.current?.offerID != member.offerID || report.eligibility.evidence.current?.level != member.level {reasons.append("현재 소속·수준의 새 보고서 필요")}
        if count < minimum {reasons.append(report.observation.role == .batter ? "동일 환경 현재 리그\(minimum)타석 필요":"동일 환경 현재 리그\(minimum/3)이닝 필요")}
        if row == nil || h == nil {reasons.append("현재 구단·역할 평가 자료 부족")}
        if row?.seats == 0 {reasons.append("현재 구단의 해당 역할 모집 자리 없음")}
        // Renewal uses the incumbent club's frozen competition, not external transfer eligibility.
        if let row {reasons += row.blockers.filter {$0.contains("수비70") || $0.contains("공격 기량") || $0.contains("포수 전용")}}
        let f=h.flatMap {h in row.map {ScoutingContractFit.round(h-$0.criterion+p)}}
        if let f,f < 0 {reasons.append("현재 구단 역할·경쟁 기준 미달 · F 0 이상 필요")}
        let age=report.observation.age
        var years=route == .mlbDevelopment ? 1:((f ?? 0)<5 ? 1:(f ?? 0)<10 ? 2:3)
        if age >= 30 {years=min(years,2)};if age >= 35 {years=1}
        let price=100+Int((6*max(0,f ?? 0)).rounded())
        if let row,price*years > row.budget {reasons.append("재계약 총액 예산 부족 · 필요\(price*years)/예산\(row.budget)지수")}
        let start=try CollegeProReview.effective(after:date)
        let offer:OverseasOffer
        if reasons.isEmpty,let row,let h,let f {
            offer=OverseasOffer(id:id+"/offer",clubID:row.id,teamID:member.teamID,name:member.name,route:route,roleID:roleID,issued:date.description,expires:min(date.adding(days:6),window.end).description,effective:start.description,economicEnd:start.anniversary(in:start.year+years).adding(days:-1).description,economicIndex:price,years:years,h:h,c:row.criterion,p:p,margin:f)
        } else {
            return Self(version:1,id:id,window:window,date:date.description,reportID:report.id,source:member,reserved:reserved,roleID:roleID,sampleCount:count,criterion:row?.criterion,h:h,p:p,budget:row?.budget,reasons:reasons,offer:nil)
        }
        return Self(version:1,id:id,window:window,date:date.description,reportID:report.id,source:member,reserved:reserved,roleID:roleID,sampleCount:count,criterion:row?.criterion,h:h,p:p,budget:row?.budget,reasons:reasons,offer:offer)
    }
}
extension OverseasCareerJournal {
    func hasPendingRenewal(on date:String) -> Bool {
        (renewalReviews ?? []).contains {review in
            guard let offer=review.offer,offer.effective > date else {return false}
            return (renewalDecisions ?? []).contains {$0.offerID == offer.id && $0.kind == .accepted && $0.date <= date}
        }
    }
    func validateRenewals(owner:CareerContractJournal,today:GameDate) throws {
        let reviews=renewalReviews ?? [],decisions=renewalDecisions ?? []
        guard Set(reviews.map(\.id)).count == reviews.count,Set(reviews.map { $0.window.id }).count == reviews.count,
              Set(decisions.map(\.offerID)).count == decisions.count else {throw ContractRegistrationError.invalid}
        for review in reviews {
            guard review.version == 1,review.date <= today.description,
                  let initial=evaluations.flatMap(\.offers).first(where:{$0.id == review.source.offerID}),
                  review.roleID == ((promotions ?? []).last(where:{$0.sourceOfferID == review.source.offerID && $0.effective <= review.date})?.roleID ?? initial.roleID),
                  let report=owner.overseasReports?.first(where:{$0.id == review.reportID}),
                  review == (try OverseasRenewalReview.make(report:report,member:review.source,roleID:review.roleID,window:review.window,on:GameDate(review.date),reserved:review.reserved)),
                  try owner.current(on:GameDate(review.date),excludingOverseasRenewal:review.offer?.id) == review.source else {throw ContractRegistrationError.invalid}
        }
        for decision in decisions {
            guard let review=reviews.first(where:{$0.offer?.id == decision.offerID}),let offer=review.offer,
                  decision.kind != .closed,decision.date >= offer.issued,decision.date <= offer.expires,decision.date <= today.description else {throw ContractRegistrationError.invalid}
            if decision.kind == .accepted {
                guard !transitions.contains(where:{$0.sourceMembershipID == review.source.offerID && $0.acceptedDate <= decision.date && $0.destination.since > decision.date}),
                      !(promotions ?? []).contains(where:{$0.sourceOfferID == review.source.offerID && $0.date <= decision.date && $0.effective > decision.date}) else {throw ContractRegistrationError.invalid}
            }
        }
    }
}


struct OverseasRelease:Codable,Equatable {
    let source:CareerMembership
    let reviewID:String
    let date:String
}
extension OverseasCareerJournal {
    func releaseReview(owner:CareerContractJournal,on date:GameDate,excludingRelease:String?=nil) throws -> OverseasRenewalReview? {
        guard let member=try owner.current(on:date,excludingOverseasRelease:excludingRelease),OverseasRenewalReview.route(member) != nil,
              let review=(renewalReviews ?? []).last(where:{$0.source.offerID == member.offerID && $0.date <= date.description}),
              date > review.window.end,date <= (try CollegeProReview.effective(after:review.window.start)),
              date > (try GameDate(member.economicEnd)),member == review.source,
              !hasPendingFA(on:date.description),
              !transitions.contains(where:{$0.sourceMembershipID == member.offerID && $0.acceptedDate <= date.description && $0.destination.since > date.description}),
              !(promotions ?? []).contains(where:{$0.sourceOfferID == member.offerID && $0.date <= date.description && $0.effective > date.description}) else {return nil}
        if let offer=review.offer {
            let decision=(renewalDecisions ?? []).first {$0.offerID == offer.id && $0.date <= date.description}
            if decision?.kind == .accepted {return nil}
            if decision?.kind != .rejected && date.description <= offer.expires {return nil}
        }
        return review
    }
    func validateReleases(owner:CareerContractJournal,today:GameDate) throws {
        let rows=releases ?? []
        guard Set(rows.map {$0.source.offerID}).count == rows.count else {throw ContractRegistrationError.invalid}
        for row in rows {
            let date=try GameDate(row.date)
            guard date <= today,let review=try releaseReview(owner:owner,on:date,excludingRelease:row.source.offerID),
                  review.id == row.reviewID,review.source == row.source else {throw ContractRegistrationError.invalid}
        }
    }
}

struct FASeasonEvidence:Codable,Equatable {
    let year:Int
    let sourceID:String
    let level:String
    let matchKeys:[String]
    static func collect(owner:CareerContractJournal,role:PlayerRole,on date:GameDate,rows:[CareerMatchRecord]) throws -> [Self] {
        var result:[Self]=[]
        for year in Set(try rows.map {try GameDate($0.gameDate).year}).sorted() {
            let first=try GameDate("\(year)-04-01"),last=first.adding(days:174)
            guard last < date,let start=try owner.current(on:first),let end=try owner.current(on:last),
                  start.offerID == end.offerID,start.level == end.level,["npb-first-team","mlb-first-team"].contains(start.level) else {continue}
            let fixtures=try SeasonSchedule.fixtures(year:year,schoolIDs:CareerTeamDirectory.teams(level:start.level)).filter {$0.includes(start.teamID)}
            var keys:[String]=[],totals=PersonalSeasonTotals()
            for row in rows where row.completed && row.appearance && row.gameDate >= first.description && row.gameDate <= last.description {
                guard row.playerID == owner.playerID,let fixture=fixtures.first(where:{$0.id == row.fixtureID}),fixture.date.description == row.gameDate,
                      row.key == CareerMatchRecord.key(owner.playerID,fixture.id),row.opponentID == fixture.opponent(of:start.teamID) else {continue}
                let match=try row.snapshot(),day=try GameDate(row.gameDate)
                guard let member=try owner.current(on:day),member.offerID == start.offerID,member.level == start.level,
                      match.competition == start.level,match.role == role.rawValue,match.isHome == (fixture.homeID == start.teamID) else {continue}
                try totals.add(match.line);keys.append(row.key)
            }
            if role == .batter ? totals.line.plateAppearances >= 100:totals.line.pitchingOuts >= 75 {
                result.append(Self(year:year,sourceID:start.offerID,level:start.level,matchKeys:keys.sorted()))
            }
        }
        return result
    }
}
struct FADeclaration:Codable,Equatable,Identifiable {
    let id:String
    let source:CareerMembership
    let date:String
    let effective:String
    let service:[FASeasonEvidence]
    static func minimum(_ level:String) -> Int {level == "mlb-first-team" ? 6:9}
    static func make(member:CareerMembership,on date:GameDate,service:[FASeasonEvidence]) throws -> Self {
        guard let window=ContractEvaluationWindow.containing(date),window.month == 11,
              ["mlb-first-team","npb-first-team"].contains(member.level),date.year < 9995,
              try GameDate(member.economicEnd) < CollegeProReview.effective(after:date),
              Set(service.filter {$0.level == member.level && $0.year <= date.year}.map(\.year)).count >= minimum(member.level) else {throw OverseasProgressError.freeAgency}
        return Self(id:member.offerID+":fa-v1:"+window.id,source:member,date:date.description,effective:try CollegeProReview.effective(after:date).description,service:service)
    }
}
struct OverseasMobilityContext:Codable,Equatable {
    let source:CareerMembership
    let fa:FADeclaration?
    let release:OverseasRelease?
    let service:[FASeasonEvidence]
    var internationalService:[GameProSeasonEvidence]? = nil
    var historicalReportID:String? = nil
    var historicalDate:String? = nil
    var historicalSample:ScoutingPerformanceComparison? = nil
    var label:String {fa != nil ? "정식 FA":"방출 후 재취업"}
}
extension OverseasCareerJournal {
    func hasPendingFA(on date:String) -> Bool {(faDeclarations ?? []).contains {$0.date <= date && $0.effective > date}}
    func mobility(owner:CareerContractJournal,on date:GameDate) throws -> OverseasMobilityContext? {
        let member=try owner.current(on:date),service=faService ?? []
        if let member {
            guard let fa=(faDeclarations ?? []).last(where:{$0.source.offerID == member.offerID && $0.date <= date.description}) else {return nil}
            return try mobilitySample(OverseasMobilityContext(source:fa.source,fa:fa,release:nil,service:service),owner:owner,on:date)
        }
        let lastID=owner.membershipHistory().last?.offerID
        let fa=(faDeclarations ?? []).filter {$0.effective <= date.description && $0.source.offerID == lastID}.max {$0.effective<$1.effective}
        let release=(releases ?? []).filter {$0.date <= date.description && $0.source.offerID == lastID && ["npb-first-team","mlb-first-team"].contains($0.source.level)}.max {$0.date<$1.date}
        if let release,release.date > (fa?.effective ?? "") {return try mobilitySample(OverseasMobilityContext(source:release.source,fa:nil,release:release,service:service),owner:owner,on:date)}
        return try fa.map {try mobilitySample(OverseasMobilityContext(source:$0.source,fa:$0,release:nil,service:service),owner:owner,on:date)}
    }
    func mobilitySample(_ context:OverseasMobilityContext,owner:CareerContractJournal,on date:GameDate) throws -> OverseasMobilityContext {
        var value=context
        value.internationalService=service
        if let report=(owner.overseasReports ?? []).filter({report in
            report.observation.observedDate <= date.description && report.observation.observedDate >= date.adding(days:-730).description &&
            report.eligibility.evidence.current?.offerID == context.source.offerID && report.eligibility.evidence.current?.level == context.source.level &&
            (report.observation.role == .batter ? (report.selected?.totals.line.plateAppearances ?? 0)>=100:(report.selected?.totals.line.pitchingOuts ?? 0)>=75)
        }).max(by:{$0.observation.observedDate<$1.observation.observedDate}) {
            value.historicalReportID=report.id;value.historicalDate=report.observation.observedDate;value.historicalSample=report.selected
        }
        return value
    }
    func validateFA(owner:CareerContractJournal,today:GameDate) throws {
        let entries=faDeclarations ?? [],service=faService ?? []
        guard Set(entries.map(\.id)).count == entries.count,Set(entries.map {$0.source.offerID}).count == entries.count,
              Set(service.map {"\($0.level)/\($0.year)"}).count == service.count else {throw ContractRegistrationError.invalid}
        for row in entries {
            guard row.date <= today.description,row.service.allSatisfy({service.contains($0)}),
                  row == (try FADeclaration.make(member:row.source,on:GameDate(row.date),service:row.service)),
                  try owner.current(on:GameDate(row.date),excludingFA:row.id) == row.source,
                  !(renewalDecisions ?? []).contains(where:{decision in decision.kind == .accepted && decision.date <= row.date && (renewalReviews ?? []).contains {$0.source.offerID == row.source.offerID && $0.offer?.id == decision.offerID && ($0.offer?.effective ?? "") > row.date}}) else {throw ContractRegistrationError.invalid}
        }
    }
}
extension OverseasOfferEvaluation {
    static func makeMobility(report:OverseasScoutingReport,window:ContractEvaluationWindow,on date:GameDate,registrationDate:String?,member:CareerMembership?,context:OverseasMobilityContext,reserved:Bool) throws -> Self {
        guard window == ContractEvaluationWindow.containing(date),date.year < 9995 else {throw OverseasProgressError.window}
        guard (context.fa != nil) != (context.release != nil),context.source == (context.fa?.source ?? context.release?.source) else {throw ContractRegistrationError.invalid}
        let id=report.observation.playerID.uuidString+":overseas-offer-v3:"+window.id
        var reasons:[String]=[],offers:[OverseasOffer]=[]
        if registrationDate == nil || registrationDate! > date.description {reasons.append("게임 국제계약 지원자 등록 필요")}
        if reserved {reasons.append("이미 수락한 소속/갱신 예약이 있음")}
        if report.eligibility.evidence.current?.offerID != member?.offerID {reasons.append("현재 소속 상태의 새28일 보고서 필요")}
        let nextOpening=try CollegeProReview.effective(after:date).description
        if let fa=context.fa {
            if fa.date > date.description || fa.effective > nextOpening || (member != nil && member?.offerID != fa.source.offerID) {reasons.append("유효한 FA 선언/발효 조건 필요")}
        } else if let release=context.release {
            if member != nil || release.date > date.description {reasons.append("실제 방출/권리 해제 확인 필요")}
        } else {reasons.append("방출 또는 FA 선언 근거 없음")}
        let sample=report.selected
        let enough=sample?.id.hasPrefix(context.source.level+"/") == true && (report.observation.role == .batter ? (sample?.totals.line.plateAppearances ?? 0)>=100:(sample?.totals.line.pitchingOuts ?? 0)>=75)
        let previous=context.historicalSample
        let fallback=context.historicalDate.map {$0 <= date.description && $0 >= date.adding(days:-730).description} == true && previous?.id.hasPrefix(context.source.level+"/") == true && (report.observation.role == .batter ? (previous?.totals.line.plateAppearances ?? 0)>=100:(previous?.totals.line.pitchingOuts ?? 0)>=75)
        if !enough && !fallback {reasons.append("최근365일 또는730일 이내 고정 해외1군 보고서100타석/25이닝 필요")}
        if !["npb-first-team","mlb-first-team"].contains(context.source.level) {reasons.append("해외1군 전력 경력 필요")}
        if reasons.isEmpty {
            let allowMajor=context.source.level == "mlb-first-team" || (report.observation.age>=25 && Set((context.internationalService ?? []).map(\.year)).count>=6)
            let age=report.observation.age
            let rows=(report.market?.clubs ?? []).filter {row in
                guard row.route != .mlbDevelopment,(row.route != .mlbFirstTeam || allowMajor),row.seats == 1,let f=row.f,f>=0,row.h != nil else {return false}
                if row.blockers.contains(where:{$0.contains("수비70") || $0.contains("공격 기량") || $0.contains("포수 전용")}) {return false}
                let years=min(f<5 ? 1:f<10 ? 2:3,age>=35 ? 1:age>=30 ? 2:3)
                return (100+Int((6*f).rounded()))*years<=row.budget
            }.sorted {a,b in a.f == b.f ? a.id<b.id:(a.f ?? 0)>(b.f ?? 0)}
            var ordered:[OverseasClubEvaluation]=[]
            for route in [OverseasRoute.npbFirstTeam,.mlbFirstTeam] {if let best=rows.first(where:{$0.route == route}) {ordered.append(best)}}
            ordered += rows.filter {row in !ordered.contains {$0.id == row.id}}
            var teams=Set<String>()
            for row in ordered {
                let team=(row.route == .npbFirstTeam ? "jp-pro-":"us-pro-")+row.id.components(separatedBy:"/")[1]
                guard teams.insert(team).inserted else {continue}
                let start=try CollegeProReview.effective(after:date),f=row.f!,years=min(f<5 ? 1:f<10 ? 2:3,age>=35 ? 1:age>=30 ? 2:3)
                offers.append(OverseasOffer(id:id+"/"+row.id,clubID:row.id,teamID:team,name:row.name,route:row.route,roleID:row.roleID,issued:date.description,expires:min(date.adding(days:6),window.end).description,effective:start.description,economicEnd:start.anniversary(in:start.year+years).adding(days:-1).description,economicIndex:100+Int((6*f).rounded()),years:years,h:row.h!,c:row.criterion,p:row.p,margin:f))
                if offers.count == 2 {break}
            }
            if offers.isEmpty {reasons.append("해외 전력 역할/기량·자리·예산/경쟁 조건 미달")}
        }
        var result=Self(version:3,id:id,window:window,date:date.description,reportID:report.id,source:member,registeredAt:registrationDate,reservedAtEvaluation:reserved,offers:offers,reasons:reasons)
        result.mobility=context;return result
    }
}


// Read-only market projection: original offers and decisions remain the source of truth.
struct ContractMarketEntry:Identifiable,Equatable {
    let offer:OverseasOffer
    let retention:Bool
    let status:String
    var id:String {offer.id}
}
extension OverseasCareerJournal {
    func renewalClosedByTransfer(_ offer:OverseasOffer,on date:String) -> Bool {
        guard let review=(renewalReviews ?? []).first(where:{$0.offer?.id == offer.id}) else {return false}
        return transitions.contains {$0.sourceMembershipID == review.source.offerID && $0.acceptedDate <= date && $0.acceptedDate >= offer.issued && $0.acceptedDate <= offer.expires}
    }
    func nextMarketWindow(after date:GameDate,hasMembership:Bool) -> ContractEvaluationWindow {
        let months=hasMembership ? [11]:[4,7,11]
        return (date.year...date.year+1).flatMap {year in months.map {ContractEvaluationWindow(year:year,month:$0)}}.first {$0.start > date}!
    }
    func marketEntries(on date:String) -> [ContractMarketEntry] {
        func status(_ offer:OverseasOffer,_ kind:DomesticOfferDecisionKind?,closed:Bool=false) -> String {
            if let kind {return kind == .accepted ? (date < offer.effective ? "수락 · 발효 대기":"수락 · 발효 완료"):kind == .rejected ? "거절":"다른 제의 수락 · 종료"}
            if closed {return "다른 제의 수락 · 종료"}
            if date < offer.issued {return "발행 전"}
            return date > offer.expires ? "마감":"검토 가능"
        }
        let renewals=(renewalReviews ?? []).compactMap {review -> ContractMarketEntry? in
            guard let offer=review.offer else {return nil}
            return ContractMarketEntry(offer:offer,retention:true,status:status(offer,(renewalDecisions ?? []).first {$0.offerID == offer.id}?.kind,closed:renewalClosedByTransfer(offer,on:date)))
        }
        let external=evaluations.flatMap {evaluation in evaluation.offers.map {offer in
            ContractMarketEntry(offer:offer,retention:offer.teamID == evaluation.source?.teamID,status:status(offer,decisions.first {$0.offerID == offer.id}?.kind))
        }}
        return (renewals+external).sorted {$0.offer.issued == $1.offer.issued ? $0.id < $1.id:$0.offer.issued > $1.offer.issued}
    }
}


struct DomesticMarketEntry:Identifiable {
    let id:String
    let evaluationKey:String
    let name:String
    let roleID:String
    let label:String
    let economicLabel:String
    let economicIndex:Int
    let period:String
    let issued:String
    let expires:String
    let status:String
    let renewal:DomesticRenewalReview?
    var visible:Bool {["검토 가능","수락 · 발효 대기"].contains(status)}
}


struct CareerDevelopmentTarget:Codable,Equatable {
    let reportID:String
    let clubID:String
    let date:String
}
struct CareerTargetClub:Identifiable {
    let id:String
    let name:String
    let roleID:String
    let route:OverseasRoute?
    let criterion:Double?
    let blockers:[String]
    let fit:Double?
    let demand:String
    var path:String {route?.label ?? "국내 프로 관찰"}
    var training:TrainingKind {switch roleID {case "slugger":.power;case "onBase":.discipline;case "field":.defense;default:.control}}
    static func catalog(_ report:OverseasScoutingReport) -> [Self] {
        let domestic=(report.observation.contractFit?.clubs ?? []).map {row in
            Self(id:"domestic/"+row.id,name:row.recruitment.name,roleID:row.recruitment.roleID,route:nil,criterion:row.c,blockers:row.blockers,fit:row.f,demand:row.recruitment.demand.label)
        }
        let foreign=(report.market?.clubs ?? []).map {row in
            Self(id:row.id,name:row.name,roleID:row.roleID,route:row.route,criterion:row.criterion,blockers:row.blockers,fit:row.f,demand:row.demand.label)
        }
        return domestic+foreign
    }
}
extension CareerContractJournal {
    func validateDevelopment(today:GameDate) throws {
        if let target=developmentTarget {
            guard let report=overseasReports?.first(where:{$0.id == target.reportID}),
                  report.observation.observedDate <= target.date,target.date <= today.description,
                  CareerTargetClub.catalog(report).contains(where:{$0.id == target.clubID}) else {throw ContractRegistrationError.invalid}
        }
    }
}
struct CareerTargetReadiness {
    let currentH:Double?
    let missingH:Double?
    let sample:Int
    let requiredSample:Int
    static func make(club:CareerTargetClub,live:ScoutingObservation,level:String) -> Self {
        let current=live.grades.first {$0.id == club.roleID}?.score
        let sample=live.groups.filter {$0.id.hasPrefix(level+"/")}.map {live.role == .batter ? $0.totals.line.plateAppearances:$0.totals.line.pitchingOuts}.max() ?? 0
        let required=live.role == .batter ? (club.route != nil && club.route != .mlbDevelopment ? 100:40):(club.route != nil && club.route != .mlbDevelopment ? 75:45)
        return Self(currentH:current,missingH:club.criterion.flatMap {criterion in current.map {max(0,criterion-$0)}},sample:sample,requiredSample:required)
    }
}


struct CareerDevelopmentProject:Codable,Equatable,Identifiable {
    let id:String
    let target:CareerDevelopmentTarget
    let start:String
    let end:String
    let period:Int
    let role:PlayerRole
    let level:String
    let training:TrainingKind
    let baselineMatches:[String]
    let baselineTrainings:[String]
    let requiredSample:Int
    var assignment:CareerProjectAssignment? = nil
}
struct CareerProjectProgress:Codable,Equatable {
    let matchKeys:[String]
    let trainingKeys:[String]
    let qualitySessions:Int
    let sample:Int
    let growth:Double
    var complete:Bool {trainingKeys.count >= (task?.trainingGoal ?? 3) && qualitySessions >= (task?.qualityGoal ?? 2) && sample >= requiredSample && (task.map {$0.value >= $0.goal} ?? true)}
    let requiredSample:Int
    var task:CareerProjectTaskProgress? = nil
}
struct CareerProjectReview:Codable,Equatable,Identifiable {
    let projectID:String
    let reportID:String
    let period:Int
    let date:String
    let progress:CareerProjectProgress
    var id:String {projectID+":"+String(period)}
}
extension CareerContractJournal {
    func activeProject(on date:String) -> CareerDevelopmentProject? {
        (developmentProjects ?? []).last {project in
            project.start <= date && date <= project.end && !(developmentReviews ?? []).contains {$0.projectID == project.id && $0.progress.complete}
        }
    }
    func validateProjects(origin:String,today:GameDate,reports:[String:(Int,String)]) throws {
        let projects=developmentProjects ?? [],reviews=developmentReviews ?? []
        guard Set(projects.map(\.id)).count == projects.count,Set(projects.map(\.period)).count == projects.count,Set(reviews.map(\.id)).count == reviews.count else {throw ContractRegistrationError.invalid}
        for project in projects {
            guard let report=overseasReports?.first(where:{$0.id == project.target.reportID}),
                  let club=CareerTargetClub.catalog(report).first(where:{$0.id == project.target.clubID}),
                  project.role == report.observation.role,project.start >= project.target.date,project.start <= today.description,
                  project.end == (try GameDate(project.start).adding(days:27).description),
                  project.period == (try ScoutingPeriod(origin:GameDate(origin),today:GameDate(project.start))).index,
                  project.id == playerID.uuidString+":development-project-v1:"+String(project.period),
                  project.training == (project.assignment?.training ?? club.training),["highschool","college","domestic-development","domestic-first-team","mlb-development","npb-first-team","mlb-first-team"].contains(project.level),
                  (0...(project.role == .batter ? 20:18)).contains(project.requiredSample),
                  Set(project.baselineMatches).count == project.baselineMatches.count,Set(project.baselineTrainings).count == project.baselineTrainings.count else {throw ContractRegistrationError.invalid}
            if let assignment=project.assignment {guard assignment == CareerProjectAssignment.make(club:club,observation:report.observation,level:project.level,sampleGoal:project.requiredSample) else {throw ContractRegistrationError.invalid}}
        }
        for review in reviews {
            guard let project=projects.first(where:{$0.id == review.projectID}),let source=reports[review.reportID],
                  source.0 == review.period,source.1 == review.date,review.date <= today.description,review.date >= project.start,review.period > project.period,
                  review.progress.sample >= 0,review.progress.qualitySessions >= 0,review.progress.qualitySessions <= review.progress.trainingKeys.count,
                  review.progress.growth.isFinite,review.progress.growth >= 0,review.progress.requiredSample == project.requiredSample,
                  Set(review.progress.matchKeys).count == review.progress.matchKeys.count,Set(review.progress.trainingKeys).count == review.progress.trainingKeys.count else {throw ContractRegistrationError.invalid}
            if let assignment=project.assignment {
                guard let task=review.progress.task,task.metric == assignment.metric,task.goal == assignment.metricGoal,
                      task.trainingGoal == assignment.trainingGoal,task.qualityGoal == assignment.qualityGoal,task.value >= 0,
                      Set(task.keys).count == task.keys.count else {throw ContractRegistrationError.invalid}
            } else if review.progress.task != nil {throw ContractRegistrationError.invalid}
        }
    }
}


struct MatchPlanReportItem:Codable,Equatable,Identifiable {
    let matchKey:String
    let date:String
    let role:String
    let preparation:MatchPreparation
    let outcome:MatchPlanOutcome
    let mode:ScoutingInputMode?
    var id:String {matchKey}
}
struct MatchPlanObservation:Codable,Equatable,Identifiable {
    let reportID:String
    let period:Int
    let date:String
    let results:[MatchPlanReportItem]
    var id:String {reportID}
}
extension CareerContractJournal {
    func validateGamePlanReports(origin:String,today:GameDate,reports:[String:(Int,String)]) throws {
        let rows=gamePlanReports ?? [],keys=rows.flatMap {$0.results.map(\.matchKey)}
        guard Set(rows.map(\.period)).count == rows.count,Set(keys).count == keys.count else {throw ContractRegistrationError.invalid}
        for row in rows {
            guard let source=reports[row.reportID],source.0 == row.period,source.1 == row.date,row.date <= today.description,!row.results.isEmpty else {throw ContractRegistrationError.invalid}
            for item in row.results {
                guard item.matchKey == playerID.uuidString+":"+item.preparation.fixtureID,
                      item.preparation.version == (item.preparation.analysis.attack == nil ? 1:2),MatchPlanChoice.choices(item.role).contains(item.preparation.choice),
                      ["batter","pitcher"].contains(item.role),item.date <= row.date,
                      item.preparation.analysis.year == (try GameDate(item.date)).year,
                      (try ScoutingPeriod(origin:GameDate(origin),today:GameDate(item.date))).index < row.period,
                      item.outcome.checks.count == 2,item.outcome.checks.allSatisfy({$0.value >= 0 && $0.target >= 0}) else {throw ContractRegistrationError.invalid}
                if let attack=item.preparation.analysis.attack {
                    try attack.validate()
                    guard attack.year == item.preparation.analysis.year,attack.teamID == item.preparation.analysis.teamID else {throw ContractRegistrationError.invalid}
                }
            }
        }
    }
}


struct GoalSpecialTraining:Codable,Equatable,Identifiable {
    let id:String
    let target:CareerDevelopmentTarget
    let date:String
    let kind:TrainingKind
    let recordKey:String
}
struct GoalSpecialAssessment:Codable,Equatable,Identifiable {
    let id:String
    let target:CareerDevelopmentTarget
    let date:String
    let period:Int
    let role:PlayerRole
    let position:String
    let level:String
    let opponentID:String
    let values:PlayerInitialValues
    let fatigue:Int
    var calendarRevision:Int
    var games:[CareerMatch]=[]
    var playVersion:Int? = nil
    var currentGame:CareerMatch? = nil
    var completed:Bool {games.count == 2}
    var seed:UInt64 {DomesticSelection.hash(id+"/"+target.reportID+"/"+target.clubID)}
    var totals:PersonalSeasonTotals {
        var total=PersonalSeasonTotals();for game in games {_ = try? total.add(game.line)};return total
    }
    var score:Double {
        let line=totals.line
        if role == .batter {return line.plateAppearances == 0 ? 0:ScoutingContractFit.round(100*Double(line.hits+line.walks)/Double(line.plateAppearances))}
        let faced=games.reduce(0){$0+($1.scoutingPerformance?.battersFaced ?? 0)},homers=games.reduce(0){$0+($1.scoutingPerformance?.homersAllowed ?? 0)}
        return faced == 0 ? 0:ScoutingContractFit.round(max(0,min(100,50+100*Double(line.pitchingStrikeouts-line.pitchingWalks-2*homers)/Double(faced))))
    }
    @MainActor private func nextGame() throws -> CareerMatch {
        let home=games.count.isMultiple(of:2),own="goal-evaluation-own"
        let roster=MatchNPCFielders.make(year:try GameDate(date).year,competition:level,homeID:home ? own:opponentID,awayID:home ? opponentID:own)
        var match=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:seed &+ UInt64(games.count),home:home,tracked:true,battedBallVersion:1,fatigue:fatigue,assessmentRoster:roster)
        match.competition=level;return match
    }
    @MainActor mutating func advance() throws {
        guard playVersion == nil else {throw MatchError.invalidInput}
        guard !completed else {throw MatchError.finished}
        var match=try nextGame();try match.advance(.automatic);games.append(match)
    }
    @MainActor mutating func preparePlay() throws {
        guard playVersion == 1 else {throw MatchError.invalidInput}
        guard !completed else {throw MatchError.finished}
        if currentGame?.completed == false {return}
        currentGame=try nextGame()
    }
    mutating func play(_ input:MatchInput,pitchCode:String?,control:ManualMatchInput?) throws {
        guard playVersion == 1,let saved=currentGame else {throw MatchError.invalidInput}
        guard !completed,!saved.completed else {throw MatchError.finished}
        var game=saved;try game.advance(input,pitchCode:pitchCode,control:control)
        currentGame=game;if game.completed {games.append(game)}
    }
    var inputSummary:String {
        games.enumerated().map {"\($0.offset+1)경기 "+($0.element.scoutingPerformance?.inputs?.mode.label ?? "미확인")}.joined(separator:" · ")
    }
    var roleDiagnosis:[String] {
        guard !games.isEmpty else {return ["완료한 평가 경기 후 역할별 진단을 확인합니다."]}
        let roleID=target.clubID.components(separatedBy:"/").last ?? "",line=totals.line
        switch roleID {
        case "slugger":return ["장타 관찰 · 2루타 \(games.reduce(0){$0+($1.scoutingPerformance?.doubles ?? 0)}),홈런 \(line.homeRuns) / \(line.plateAppearances)타석"]
        case "onBase":return ["출루 관찰 · 안타+볼넷 \(line.hits+line.walks),삼진 \(line.strikeouts) / \(line.plateAppearances)타석"]
        case "field":
            let plays=games.flatMap {$0.fieldPlays ?? []}.filter(\.ownParticipation)
            guard !plays.isEmpty else {return ["본인 수비 참여 기회 없음 · 수비 진단 보류","타격 점수로 수비·송구·포지션 조건을 통과시키지 않습니다."]}
            return ["본인 수비 참여 \(plays.count)회 · 본인 실책 \(plays.filter {$0.misplay?.ownError == true}.count)회","공격 참고 점수는 수비 등급이 아닙니다. 포지션/수비·송구의 정식 자격은 별도 심사합니다."]
        default:return ["선발 관찰 · \(totals.innings)이닝 / 탈삼진 \(line.pitchingStrikeouts) / 볼넷 \(line.pitchingWalks)"]
        }
    }
    func validate() throws {
        guard games.count <= 2,(0...100).contains(fatigue),calendarRevision >= 0,!opponentID.isEmpty,
              [values.contact,values.power,values.discipline,values.speed,values.defense,values.arm,values.mental].allSatisfy({$0.isFinite && (0...100).contains($0)}),
              [values.velocity,values.control,values.stuff,values.stamina].compactMap({$0}).allSatisfy({$0.isFinite && (0...100).contains($0)}),
              values.pitches.values.allSatisfy({$0.isFinite && (0...100).contains($0)}) else {throw MatchError.invalidRecord}
        guard playVersion == nil || playVersion == 1 else {throw MatchError.invalidRecord}
        if playVersion == nil {guard currentGame == nil else {throw MatchError.invalidRecord}}
        if let currentGame {
            if currentGame.completed {guard currentGame == games.last else {throw MatchError.invalidRecord}}
            else {guard !completed else {throw MatchError.invalidRecord}}
        }
        for game in games {guard game.completed else {throw MatchError.invalidRecord}}
        for game in games + (currentGame?.completed == false ? [currentGame!]:[]) {
            guard game.appearance,game.role == role.rawValue,game.competition == level,game.abilityExperience == nil,game.positionExperience == nil,
                  game.abilityStats?.fatigue == fatigue,let performance=game.scoutingPerformance,playVersion == 1 || performance.inputs?.direct == 0,
                  let roster=game.npcFielders else {throw MatchError.invalidRecord}
            try roster.validate();try game.validatePitching();try game.validateDetailedField();try performance.validate(line:game.line,role:role)
            var checked=PersonalSeasonTotals();try checked.add(game.line)
        }
        guard score.isFinite,(0...100).contains(score) else {throw MatchError.invalidRecord}
    }
}
enum GoalSpecialEvidenceKind:String,Codable {case training,assessment}
struct GoalSpecialEvidence:Codable,Equatable,Identifiable {
    let id:String
    let kind:GoalSpecialEvidenceKind
    let target:CareerDevelopmentTarget
    let date:String
    let score:Double
    let growth:Double
    let summary:String
}
struct GoalSpecialReport:Codable,Equatable,Identifiable {
    let reportID:String
    let period:Int
    let date:String
    let evidence:[GoalSpecialEvidence]
    var id:String {reportID}
}
struct GoalSpecialRecommendation {
    let kind:TrainingKind
    let current:Double
    let reason:String
    static func make(club:CareerTargetClub,abilities:HomeAbilitySummary) -> Self? {
        let candidates:[TrainingKind]=switch club.roleID {case "slugger":[.power,.contact];case "onBase":[.discipline,.contact];case "field":[.defense,.arm,.speed];default:[.control,.stuff,.velocity,.stamina]}
        let rows=candidates.compactMap {kind -> (TrainingKind,Double)? in
            let id="home"+kind.rawValue.prefix(1).uppercased()+kind.rawValue.dropFirst()
            return abilities.originals.first(where:{$0.id == id && $0.current < 100}).map {(kind,$0.current)}
        }
        guard let low=rows.min(by:{$0.1 == $1.1 ? $0.0.rawValue < $1.0.rawValue:$0.1 < $1.1}) else {return nil}
        return Self(kind:low.0,current:low.1,reason:DomesticContractOffer.roleName(club.roleID)+" 역할의 관련 능력 중 낮은 "+low.0.label+" 보완")
    }
}
extension CareerContractJournal {
    func specialClub(_ target:CareerDevelopmentTarget) -> CareerTargetClub? {
        overseasReports?.first(where:{$0.id == target.reportID}).flatMap {report in CareerTargetClub.catalog(report).first {$0.id == target.clubID}}
    }
    func validateSpecial(origin:String,today:GameDate,reports:[String:(Int,String)]) throws {
        let trainings=specialTrainings ?? [],assessments=specialAssessments ?? [],observations=specialReports ?? []
        guard Set(trainings.map(\.id)).count == trainings.count,Set(trainings.map(\.recordKey)).count == trainings.count,
              Set(assessments.map(\.period)).count == assessments.count,assessments.filter({!$0.completed}).count <= 1,
              Set(observations.map(\.period)).count == observations.count else {throw ContractRegistrationError.invalid}
        for training in trainings {
            guard specialClub(training.target) != nil,training.date <= today.description,training.date >= training.target.date,
                  training.recordKey == playerID.uuidString+":"+training.date,training.id == "goal-training-v1/"+training.recordKey else {throw ContractRegistrationError.invalid}
        }
        for assessment in assessments {
            guard let club=specialClub(assessment.target),assessment.date <= today.description,assessment.date >= assessment.target.date,
                  assessment.id == playerID.uuidString+":goal-assessment-v1:"+String(assessment.period),
                  assessment.period == (try ScoutingPeriod(origin:GameDate(origin),today:GameDate(assessment.date))).index,
                  assessment.level == club.assessmentLevel,assessment.opponentID == club.assessmentTeamID,
                  club.roleID == "starter" ? assessment.role == .pitcher:assessment.role == .batter else {throw ContractRegistrationError.invalid}
            try assessment.validate()
        }
        let keys=observations.flatMap {$0.evidence.map(\.id)}
        guard Set(keys).count == keys.count else {throw ContractRegistrationError.invalid}
        for report in observations {
            guard let source=reports[report.reportID],source.0 == report.period,source.1 == report.date,!report.evidence.isEmpty else {throw ContractRegistrationError.invalid}
            for row in report.evidence {
                guard row.date <= report.date,(try ScoutingPeriod(origin:GameDate(origin),today:GameDate(row.date))).index < report.period,
                      row.score.isFinite,(0...100).contains(row.score),row.growth.isFinite,row.growth >= 0,
                      row.kind == .training ? trainings.contains(where:{$0.id == row.id && $0.target == row.target}):assessments.contains(where:{$0.id == row.id && $0.target == row.target && $0.completed}) else {throw ContractRegistrationError.invalid}
            }
        }
    }
}


extension CareerTargetClub {
    var assessmentLevel:String {switch route {case .mlbDevelopment:"mlb-development";case .npbFirstTeam:"npb-first-team";case .mlbFirstTeam:"mlb-first-team";case nil:"domestic-development"}}
    var assessmentTeamID:String? {
        let parts=id.components(separatedBy:"/")
        guard parts.count == 3 else {return nil}
        if route == nil {let team="dev-"+parts[1];return CareerTeamDirectory.domesticIDs.contains(team) ? team:nil}
        guard let index=Int(parts[1]),(0..<6).contains(index) else {return nil}
        return (route == .npbFirstTeam ? CareerTeamDirectory.japaneseFirstIDs:route == .mlbFirstTeam ? CareerTeamDirectory.americanFirstIDs:CareerTeamDirectory.americanDevelopmentIDs)[index]
    }
}

// Read-only review of frozen reports; never rebuild historical evaluations from live values.
struct ObservationReviewChange:Identifiable {
    let id:String
    let label:String
    let before:Double
    let after:Double
    var difference:Double {after-before}
}
enum ObservationReviewAction:String,Identifiable {
    case report,target,special,training,schedule,position,market
    var id:String {rawValue}
    var reason:String {switch self {
    case .report:"이번 주기의 고정 관찰 자료를 확인합니다."
    case .target:"목표 역할의 자료와 지원 경로·권리 조건을 확인합니다."
    case .special:"목표 역할의 부족한 기량을 관련 훈련으로 보완합니다."
    case .training:"수비 역할의 별도 공격 기량 조건을 컨택·파워·선구안 훈련으로 준비합니다."
    case .schedule:"필요한 공식 출전 표본을 쌓을 일정을 확인합니다."
    case .position:"목표 수비 역할의 포지션 숙련을 준비합니다."
    case .market:"실제로 도착한 제의와 마감을 확인합니다. 조건 충족이 제의 보장은 아닙니다."
    }}
    var label:String {switch self {
    case .report:"관찰 보고서 기록/확인";case .target:"목표 구단·자격 확인";case .special:"부족 능력 특별 훈련 / 평가전";case .training:"공격 능력 훈련 선택";case .schedule:"공식 경기 일정·출전 확인";case .position:"포지션 숙련 훈련";case .market:"실제 제의·계약 시장 확인"
    }}
}
struct ObservationPeriodReview {
    let current:ScoutingObservation
    let previous:ScoutingObservation?
    let overseas:OverseasScoutingReport?
    let previousOverseas:OverseasScoutingReport?
    let target:CareerDevelopmentTarget?
    let stale:Bool
    var comparable:Bool {previous.map {$0.playerID == current.playerID && $0.role == current.role && $0.position == current.position && $0.evaluationVersion == current.evaluationVersion} ?? false}
    var abilities:[ObservationReviewChange] {
        guard let previous,previous.role == current.role else {return []}
        return current.abilities.originals.compactMap {row in
            previous.abilities.originals.first {$0.id == row.id}.map {ObservationReviewChange(id:row.id,label:row.label,before:$0.current,after:row.current)}
        }
    }
    var pitches:[ObservationReviewChange] {
        guard let previous,previous.role == current.role else {return []}
        return current.abilities.pitches.compactMap {row in previous.abilities.pitches.first {$0.id == row.id}.map {ObservationReviewChange(id:row.id,label:row.label,before:$0.current,after:row.current)}}
    }
    var samples:[ObservationReviewChange] {
        guard comparable,let previous else {return []}
        return current.groups.compactMap {group in
            guard let old=previous.groups.first(where:{$0.id == group.id}),group.performance?.version == old.performance?.version,
                  group.performance?.version == 2,let usage=group.performance?.inputs,let oldUsage=old.performance?.inputs,
                  usage.direct+usage.automatic>0,oldUsage.direct+oldUsage.automatic>0,usage.mode == oldUsage.mode else {return nil}
            let count=current.role == .batter ? group.totals.line.plateAppearances:group.totals.line.pitchingOuts
            let before=current.role == .batter ? old.totals.line.plateAppearances:old.totals.line.pitchingOuts
            guard count>0,before>0 else {return nil}
            let level=group.id.components(separatedBy:"/").first ?? ""
            let league=["highschool":"고교","college":"대학","domestic-development":"국내 육성","domestic-first-team":"국내1군","mlb-development":"미국 육성","npb-first-team":"NPB","mlb-first-team":"MLB"][level] ?? "리그 미확인"
            return ObservationReviewChange(id:group.id,label:league+" · "+usage.mode.label,before:Double(before),after:Double(count))
        }
    }
    var performance:[ObservationReviewChange] {
        guard let previous else {return []}
        return samples.compactMap {sample in
            guard let now=current.groups.first(where:{$0.id == sample.id}),let old=previous.groups.first(where:{$0.id == sample.id}),
                  let after=now.performance?.contribution(now.totals.line,role:current.role),let before=old.performance?.contribution(old.totals.line,role:current.role) else {return nil}
            return ObservationReviewChange(id:sample.id,label:current.role == .batter ? "타격 기여 지표":"투구 기여 지표",before:before,after:after)
        }
    }
    private func club(observation:ScoutingObservation,foreign:OverseasScoutingReport?) -> CareerTargetClub? {
        guard let target else {return nil}
        if let foreign {return CareerTargetClub.catalog(foreign).first {$0.id == target.clubID}}
        return observation.contractFit?.clubs.first {"domestic/"+$0.id == target.clubID}.map {row in
            CareerTargetClub(id:"domestic/"+row.id,name:row.recruitment.name,roleID:row.recruitment.roleID,route:nil,criterion:row.c,blockers:row.blockers,fit:row.f,demand:row.recruitment.demand.label)
        }
    }
    var club:CareerTargetClub? {club(observation:current,foreign:overseas)}
    var previousClub:CareerTargetClub? {previous.flatMap {club(observation:$0,foreign:previousOverseas)}}
    var readiness:CareerTargetReadiness? {
        guard let club else {return nil}
        let level=overseas?.eligibility.evidence.current?.level ?? current.contractFit?.selectedEnvironment?.components(separatedBy:"/").first ?? (current.age <= 18 ? "highschool":"unsigned")
        return CareerTargetReadiness.make(club:club,live:current,level:level)
    }
    private func interest(_ observation:ScoutingObservation,_ foreign:OverseasScoutingReport?) -> String {
        guard let target else {return "목표 미선택"}
        if target.clubID.hasPrefix("domestic/") {
            guard let interests=observation.interests else {return "관심 자료 미확인"}
            if let entry=interests.entries.first(where:{"domestic/"+$0.id+"/"+$0.roleID == target.clubID}) {return entry.level.label}
            if let entry=interests.entries.first(where:{target.clubID.hasPrefix("domestic/"+$0.id+"/")}) {return "다른 역할 관심 · "+entry.roleLabel}
            return interests.pendingReasons.isEmpty ? "관심 없음":"관심 없음 / 판단 보류"
        }
        guard let row=foreign?.market?.clubs.first(where:{$0.id == target.clubID}) else {return "관찰 자료 없음"}
        return row.interest?.label ?? "관심 없음 / 심사 보류"
    }
    var roleChange:ObservationReviewChange? {
        guard comparable,let club,let previous,let before=previous.grades.first(where:{$0.id == club.roleID})?.score,let after=current.grades.first(where:{$0.id == club.roleID})?.score else {return nil}
        return ObservationReviewChange(id:club.roleID,label:"역할 기량",before:before,after:after)
    }
    var interestNow:String {interest(current,overseas)}
    var interestBefore:String {previous.map {interest($0,previousOverseas)} ?? "이전 자료 없음"}
    var fieldDefenseMissing:Bool {club?.roleID == "field" && (current.abilities.originals.first {$0.id == "homeDefense"}?.current ?? 0)<70}
    var fieldAttackMissing:Bool {
        guard club?.roleID == "field",let route=club?.route,route != .mlbDevelopment else {return false}
        let values=Dictionary(uniqueKeysWithValues:current.abilities.originals.map {($0.id,$0.current)})
        let attack=(values["homeContact"] ?? 0)*0.5+(values["homePower"] ?? 0)*0.15+(values["homeDiscipline"] ?? 0)*0.35
        return attack < (route == .npbFirstTeam ? 60:68)
    }
    var missing:[String] {
        guard let club,let readiness else {return [target == nil ? "목표 구단과 모집 역할을 먼저 선택해 주세요.":"이번 보고서에 같은 구단·역할 자료가 없습니다. 이전 기준으로 대체하지 않습니다."]}
        var result:[String]=[]
        if let gap=readiness.missingH {if gap>0 {result.append(String(format:"역할 기량 %.1f 보완 필요",gap))}} else {result.append("역할 기량/기준 자료 부족")}
        if readiness.sample<readiness.requiredSample {result.append("동일 수준·단일 환경 공식 표본 \(readiness.sample)/\(readiness.requiredSample)"+(current.role == .batter ? "타석":"아웃"))}
        if club.roleID == "field",(current.positionMastery ?? 0)<70 {result.append("관찰일 포지션 숙련70 필요 · "+(current.positionMastery.map {String(format:"%.1f",$0)} ?? "자료 없음"))}
        if fieldDefenseMissing {result.append("관찰일 원본 수비70 필요")}
        result += club.blockers.filter {!(club.roleID == "field" && ["주 포지션 숙련70 필요","주 포지션/원본 수비70 필요"].contains($0))}
        if let route=club.route,let gate=overseas?.eligibility.routes.first(where:{$0.route == route}) {result += gate.reasons}
        var seen:Set<String>=[];return result.filter {seen.insert($0).inserted}
    }
    var canRecommendOfficialSchedule:Bool {current.age <= 18 || overseas?.eligibility.evidence.current != nil}
    var actions:[ObservationReviewAction] {
        if stale {return [.report,.target]}
        guard let club,let readiness else {return [.target,.report]}
        var values:[ObservationReviewAction]=[]
        if let route=club.route,overseas?.eligibility.routes.first(where:{$0.route == route})?.status != .reviewable {values.append(.target)}
        if readiness.missingH == nil {if !values.contains(.target) {values.append(.target)}} else if (readiness.missingH ?? 0)>0 {values.append(.special)}
        if fieldDefenseMissing && !values.contains(.special) {values.append(.special)}
        if fieldAttackMissing {values.append(.training)}
        if club.roleID == "field",(current.positionMastery ?? 0)<70 {values.append(.position)}
        if readiness.sample<readiness.requiredSample {
            if canRecommendOfficialSchedule {values.append(.schedule)} else if !values.contains(.target) {values.append(.target)}
        }
        values.append(.market);return values
    }
    static func make(observations:[ScoutingObservation],owner:CareerContractJournal,period:Int) -> Self? {
        var sources=Dictionary(uniqueKeysWithValues:observations.map {($0.period,$0)})
        for report in owner.overseasReports ?? [] {sources[report.period]=report.observation}
        guard let current=sources.values.max(by:{$0.period<$1.period}) else {return nil}
        let previous=sources.values.filter {$0.period<current.period}.max {$0.period<$1.period}
        return Self(current:current,previous:previous,overseas:owner.overseasReports?.first {$0.period == current.period},previousOverseas:previous.flatMap {old in owner.overseasReports?.first {$0.period == old.period}},target:owner.developmentTarget,stale:current.period != period)
    }
}

enum CareerProjectMetric:String,Codable {
    case extraBase,onBase,field,control,strikeouts,innings,position,sample
    var label:String {switch self {
    case .extraBase:"공식 경기 2루타·홈런";case .onBase:"공식 경기 안타·볼넷";case .field:"실제 참여 수비";case .control:"3이닝 이상·볼넷1 이하 등판";case .strikeouts:"3이닝 이상·탈삼진3 이상 등판";case .innings:"6이닝 이상 등판";case .position:"시작 포지션 훈련 완료";case .sample:"공식 표본 확보"
    }}
    var unit:String {switch self {case .control,.strikeouts,.innings:"경기";default:"회"}}
    func value(in match:CareerMatch) -> Int {
        switch self {
        case .extraBase:(match.scoutingPerformance?.doubles ?? 0)+match.line.homeRuns
        case .onBase:match.line.hits+match.line.walks
        case .field:match.fieldPlays?.filter(\.ownParticipation).count ?? 0
        case .control:match.line.pitchingOuts >= 9 && match.line.pitchingWalks <= 1 ? 1:0
        case .strikeouts:match.line.pitchingOuts >= 9 && match.line.pitchingStrikeouts >= 3 ? 1:0
        case .innings:match.line.pitchingOuts >= 18 ? 1:0
        case .position,.sample:0
        }
    }
}
struct CareerProjectAssignment:Codable,Equatable {
    var version=1
    let focus:String
    let reason:String
    let demand:String
    let blockers:[String]
    let training:TrainingKind
    let trainingGoal:Int
    let qualityGoal:Int
    let metric:CareerProjectMetric
    let metricGoal:Int
    let position:String?
    static func make(club:CareerTargetClub,observation:ScoutingObservation,level:String,sampleGoal:Int) -> Self {
        let values=Dictionary(uniqueKeysWithValues:observation.abilities.originals.map {($0.id,$0.current)})
        let h=observation.grades.first {$0.id == club.roleID}?.score
        let readiness=CareerTargetReadiness.make(club:club,live:observation,level:level)
        var training=club.training,focus="역할 실전 관찰",reason="목표 역할의 실제 경기 수행을 관찰합니다."
        var metric:CareerProjectMetric = switch club.roleID {case "slugger":.extraBase;case "onBase":.onBase;case "field":.field;default:.control}
        var count=2,quality=1,goal=sampleGoal>0 ? (metric == .field ? 2:metric == .onBase ? 3:1):0,position:String?
        if club.criterion == nil {
            focus="모집·기준 확인 전 준비";reason="현재 모집 기준이 확인되지 않아 개인 훈련을 준비합니다. 구단 요청이나 선발 통과가 아닙니다.";metric = .sample;goal=0
        } else if club.roleID == "field" && (observation.positionMastery ?? 0)<70 {
            focus="주 포지션 숙련 보완";reason="목표 수비 역할의 포지션 숙련70 조건을 준비합니다.";metric = .position;goal=2;position=observation.position;count=3;quality=2
        } else if club.roleID == "field" && (values["homeDefense"] ?? 0)<70 {
            focus="원본 수비 보완";reason="목표 수비 역할의 원본 수비70 조건을 준비합니다.";count=4;quality=2
        } else if club.roleID == "field",let route=club.route,route != .mlbDevelopment,
                  (values["homeContact"] ?? 0)*0.5+(values["homePower"] ?? 0)*0.15+(values["homeDiscipline"] ?? 0)*0.35 < (route == .npbFirstTeam ? 60:68) {
            focus="해외 수비형 공격 보완";reason="수비 역할에도 필요한 별도 공격 기준을 준비합니다."
            training=[TrainingKind.contact,.power,.discipline].min {a,b in
                func amount(_ kind:TrainingKind) -> Double {values["home"+kind.rawValue.prefix(1).uppercased()+kind.rawValue.dropFirst()] ?? 0}
                return amount(a) == amount(b) ? a.rawValue<b.rawValue:amount(a)<amount(b)
            }!;metric = .onBase;goal=sampleGoal>0 ? 1:0;count=3;quality=2
        } else if readiness.sample<readiness.requiredSample {
            focus="공식 출전 표본 확보";reason="해당 수준·단일 환경의 관찰 표본이 부족합니다. 과제 합계는 정식 심사의 환경별 표본과 구분합니다.";metric = .sample;goal=0;count=3;quality=2
        } else if let h,let criterion=club.criterion,h<criterion {
            focus="역할 기량 보완";reason="관찰 역할 기량이 구단 기준보다 낮아 관련 능력 중 낮은 항목을 준비합니다.";training=GoalSpecialRecommendation.make(club:club,abilities:observation.abilities)?.kind ?? club.training;count=4;quality=2
        }
        if club.roleID == "starter",metric != .sample {
            let control=values["homeControl"] ?? 0,stuff=values["homeStuff"] ?? 0,stamina=values["homeStamina"] ?? 0
            if stamina<min(control,stuff) {training = .stamina;metric = .innings}
            else if stuff<control {training = .stuff;metric = .strikeouts}
        }
        if sampleGoal == 0 && metric != .position {goal=0;reason += " 기간 내 개인 출전 일정이 없어 실전 목표는 부여하지 않습니다."}
        return Self(focus:focus,reason:reason,demand:club.demand,blockers:club.blockers,training:training,trainingGoal:count,qualityGoal:quality,metric:metric,metricGoal:goal,position:position)
    }
}
struct CareerProjectTaskProgress:Codable,Equatable {
    let metric:CareerProjectMetric
    let value:Int
    let goal:Int
    let keys:[String]
    let trainingGoal:Int
    let qualityGoal:Int
}

// Accepted recruitment roles describe the club's purpose, not a starting guarantee.
struct CareerClubRole:Codable,Equatable {
    let membershipID:String
    let teamID:String
    let level:String
    let roleID:String?
    let sourceID:String?
    var label:String {
        switch roleID {case "slugger":return "장타 자원";case "onBase":return "출루 자원";case "field":return "수비 자원";case "starter":return "선발 자원";case .some(let id):return id;case nil:return "모집 역할 원본 미확인"}
    }
    var levelLabel:String {switch level {case "college":"대학";case "domestic-development":"국내 육성팀";case "domestic-first-team":"국내 1군";case "mlb-development":"미국 조직 육성";case "npb-first-team":"일본 전력팀";case "mlb-first-team":"메이저";default:"등록 수준 미확인"}}
    static func make(member:CareerMembership,owner:CareerContractJournal,offers:[DomesticContractOffer],on date:String) -> Self {
        let promoted=(owner.overseasCareer?.promotions ?? []).last {$0.sourceOfferID == member.offerID && $0.effective <= date && $0.toLevel == member.level && $0.roleID != nil}
        let domestic=offers.first {offer in offer.id == member.offerID && owner.decisions.contains(where:{$0.offerID == offer.id && $0.kind == .accepted})}
        let foreign=(owner.overseasCareer?.evaluations ?? []).flatMap(\.offers).first {$0.id == member.offerID}
        return Self(membershipID:member.offerID,teamID:member.teamID,level:member.level,roleID:promoted?.roleID ?? domestic?.roleID ?? foreign?.roleID,sourceID:promoted?.id ?? domestic?.id ?? foreign?.id)
    }
}

struct ClubSeasonTarget:Codable,Equatable,Identifiable {
    let metric:String
    let target:Int
    var id:String {metric}
    var label:String {switch metric {case "pa":"타석";case "outs":"투구 아웃";case "hr":"홈런";case "onBase":"안타+볼넷";case "defense":"본인 참여 수비";default:"탈삼진"}}
}
struct ClubSeasonProgress:Codable,Equatable {
    let matchKeys:[String]
    let values:[Int]
}
struct ClubSeasonGoal:Codable,Equatable,Identifiable {
    var version=1
    let id:String
    let year:Int
    let started:String
    let role:CareerClubRole
    let playerRole:String
    let fixtureIDs:[String]
    let excludedKeys:[String]
    let appearances:Int
    let targets:[ClubSeasonTarget]
    var settledOn:String? = nil
    var result:ClubSeasonProgress? = nil
    static func key(_ role:CareerClubRole,year:Int) -> String {"club-season-v1/\(role.membershipID)/\(role.teamID)/\(role.level)/\(year)"}
    static func targets(role:CareerClubRole,playerRole:String,appearances:Int) -> [ClubSeasonTarget] {
        // Deterministic game balance: team emphasis and level, never a real club promise.
        let emphasis=Double(MatchNPCFielders.hash(role.teamID)%3)*0.05
        let level=["domestic-first-team","npb-first-team","mlb-first-team"].contains(role.level) ? 1.1:1.0
        func count(_ rate:Double) -> Int {max(1,Int((Double(appearances)*rate*(level+emphasis)).rounded(.up)))}
        if playerRole == "pitcher" {return [.init(metric:"outs",target:appearances*9),.init(metric:"k",target:count(2))]}
        let extra:ClubSeasonTarget
        switch role.roleID {case "slugger":extra = .init(metric:"hr",target:count(1.0/6));case "field":extra = .init(metric:"defense",target:count(0.5));default:extra = .init(metric:"onBase",target:count(0.9))}
        return [.init(metric:"pa",target:appearances*2),extra]
    }
    func progress(matches:[(key:String,match:CareerMatch)]) -> ClubSeasonProgress {
        var values=targets.map {_ in 0},keys:[String]=[]
        for item in matches.sorted(by:{$0.key < $1.key}) where !keys.contains(item.key) && !excludedKeys.contains(item.key) && item.match.completed && item.match.appearance {
            keys.append(item.key)
            for (i,target) in targets.enumerated() {
                let line=item.match.line
                switch target.metric {
                case "pa":values[i] += line.plateAppearances
                case "outs":values[i] += line.pitchingOuts
                case "hr":values[i] += line.homeRuns
                case "onBase":values[i] += line.hits+line.walks
                case "defense":values[i] += (item.match.fieldPlays ?? []).filter(\.ownParticipation).count
                case "k":values[i] += line.pitchingStrikeouts
                default:break
                }
            }
        }
        return ClubSeasonProgress(matchKeys:keys,values:values)
    }
}
extension CareerContractJournal {
    func validateSeasonGoals(today:GameDate,offers:[DomesticContractOffer]) throws {
        let goals=seasonGoals ?? []
        guard Set(goals.map(\.id)).count == goals.count else {throw ContractRegistrationError.invalid}
        for goal in goals {
            let date=try GameDate(goal.started)
            guard goal.version == 1,goal.year == date.year,date <= today,
                  let member=try current(on:date),member.teamID == goal.role.teamID,member.level == goal.role.level,
                  CareerClubRole.make(member:member,owner:self,offers:offers,on:goal.started) == goal.role,
                  goal.role.roleID != nil,goal.appearances > 0,goal.appearances <= 30,
                  ["batter","pitcher"].contains(goal.playerRole),
                  goal.id == ClubSeasonGoal.key(goal.role,year:goal.year),
                  goal.targets == ClubSeasonGoal.targets(role:goal.role,playerRole:goal.playerRole,appearances:goal.appearances),
                  Set(goal.fixtureIDs).count == goal.fixtureIDs.count,Set(goal.excludedKeys).count == goal.excludedKeys.count else {throw ContractRegistrationError.invalid}
            let eligible=try SeasonSchedule.fixtures(year:goal.year,schoolIDs:CareerTeamDirectory.teams(level:goal.role.level)).filter {$0.includes(goal.role.teamID) && $0.date >= date}
            let remaining=eligible.filter {!goal.excludedKeys.contains(CareerMatchRecord.key(playerID,$0.id))}
            guard goal.fixtureIDs == remaining.map(\.id),goal.appearances == remaining.filter({$0.isAppearance(for:goal.playerRole == "batter" ? .batter:.pitcher)}).count else {throw ContractRegistrationError.invalid}
            if let result=goal.result,let settled=goal.settledOn {
                guard try GameDate(settled) >= date,try GameDate(settled) <= today,result.values.count == goal.targets.count,result.values.allSatisfy({$0 >= 0}),Set(result.matchKeys).count == result.matchKeys.count,
                      result.matchKeys.allSatisfy({key in goal.fixtureIDs.contains(where:{CareerMatchRecord.key(playerID,$0) == key}) && !goal.excludedKeys.contains(key)}) else {throw ContractRegistrationError.invalid}
            } else if goal.result != nil || goal.settledOn != nil {throw ContractRegistrationError.invalid}
        }
    }
}

enum ClubSeasonGoalError:LocalizedError {
    case roleUnavailable,noGames,unfinished
    var errorDescription:String? {switch self {
    case .roleUnavailable:"발효된 소속과 수락한 모집 역할을 먼저 확인해 주세요. 기존 자료는 유지합니다."
    case .noGames:"올해 남은 개인 출전 일정이 없습니다. 다음 시즌에 목표를 확정해 주세요."
    case .unfinished:"리그 30경기를 마친 후 시즌 목표를 결산할 수 있습니다."
    }}
}

enum ClubGoalAction:String,Codable {
    case play,power,discipline,defense,pitch,review
    var label:String {switch self {case .play:"다음 개인 출전 확인";case .power:"파워 훈련으로 장타 보완";case .discipline:"선구안 훈련으로 출루 보완";case .defense:"수비·포지션 훈련 확인";case .pitch:"구종·제구 훈련 확인";case .review:"시즌 목표·결산 확인"}}
    static func make(goal:ClubSeasonGoal,progress:ClubSeasonProgress,final:Bool) -> Self {
        if final {return .review}
        if progress.values[0] < goal.targets[0].target {return .play}
        if progress.values[1] >= goal.targets[1].target {return .review}
        switch goal.targets[1].metric {case "hr":return .power;case "onBase":return .discipline;case "defense":return .defense;default:return .pitch}
    }
}
struct ClubSeasonObservationItem:Codable,Equatable,Identifiable {
    let goalID:String
    let progress:ClubSeasonProgress
    let previousReportID:String?
    let change:[Int]?
    let newMatchKeys:[String]
    let final:Bool
    let action:ClubGoalAction
    var id:String {goalID}
    static func make(goal:ClubSeasonGoal,progress:ClubSeasonProgress,previous:(reportID:String,item:Self)?,final:Bool) -> Self {
        let old=previous?.item.progress
        return Self(goalID:goal.id,progress:progress,previousReportID:previous?.reportID,
            change:old.map {before in zip(progress.values,before.values).map(-)},
            newMatchKeys:progress.matchKeys.filter {!(old?.matchKeys.contains($0) ?? false)},final:final,
            action:ClubGoalAction.make(goal:goal,progress:progress,final:final))
    }
}
struct ClubSeasonObservation:Codable,Equatable,Identifiable {
    var version=1
    let reportID:String
    let period:Int
    let date:String
    let through:String
    let items:[ClubSeasonObservationItem]
    var id:String {reportID}
}
extension CareerContractJournal {
    func validateSeasonObservations(origin:String,today:GameDate,reports:[String:(Int,String)]) throws {
        let rows=seasonGoalReports ?? []
        guard Set(rows.map(\.period)).count == rows.count else {throw ContractRegistrationError.invalid}
        for row in rows {
            let through=try ScoutingPeriod(origin:GameDate(origin),today:GameDate(row.date)).start.adding(days:-1)
            guard row.version == 1,let source=reports[row.reportID],source.0 == row.period,source.1 == row.date,row.date <= today.description,
                  row.through == through.description,Set(row.items.map(\.goalID)).count == row.items.count else {throw ContractRegistrationError.invalid}
            for item in row.items {
                guard let goal=seasonGoals?.first(where:{$0.id == item.goalID}),goal.started <= row.through,
                      item.progress.values.count == goal.targets.count,item.progress.values.allSatisfy({$0 >= 0}),
                      Set(item.progress.matchKeys).count == item.progress.matchKeys.count,
                      item.progress.matchKeys.allSatisfy({key in goal.fixtureIDs.contains(where:{CareerMatchRecord.key(playerID,$0) == key}) && !goal.excludedKeys.contains(key)}) else {throw ContractRegistrationError.invalid}
                let old=rows.filter {$0.period < row.period}.sorted {$0.period > $1.period}.compactMap {r in r.items.first {$0.goalID == item.goalID}.map {(reportID:r.reportID,item:$0)}}.first
                guard item == ClubSeasonObservationItem.make(goal:goal,progress:item.progress,previous:old,final:item.final),
                      item.change?.allSatisfy({$0 >= 0}) ?? true,old?.item.final != true,
                      item.final == (goal.result != nil && (goal.settledOn.map {$0 <= row.through} ?? false)),
                      old.map({Set($0.item.progress.matchKeys).isSubset(of:Set(item.progress.matchKeys))}) ?? true else {throw ContractRegistrationError.invalid}
                if item.final {guard let result=goal.result,let settled=goal.settledOn,settled <= row.through,result == item.progress else {throw ContractRegistrationError.invalid}}
            }
        }
    }
}

enum ClubNextRoleAdvice:String,Codable {
    case sampleNeeded,rolePractice,evidenceNeeded,roleDiscussion
    var label:String {switch self {case .sampleNeeded:"실전 표본 확보";case .rolePractice:"현재 역할 보완";case .evidenceNeeded:"관찰 근거 보강";case .roleDiscussion:"동일 역할 확대 협의"}}
    var detail:String {switch self {
    case .sampleNeeded:"목표의 타석·투구 아웃 표본이 부족합니다. 다음 시즌 공식 개인 출전으로 검증 자료를 쌓으세요."
    case .rolePractice:"출전 표본은 확보했으나 역할 성과 목표가 남았습니다. 해당 능력 훈련과 실전 수행을 우선하세요."
    case .evidenceNeeded:"시즌 목표를 충족했습니다. 역할 기량과 검증된 동일 환경 성적을 보고서에 확보한 뒤 역할을 협의하세요."
    case .roleDiscussion:"목표 성과와 관찰 자료를 확보했습니다. 동일 역할의 책임 확대를 협의할 근거로 활용하세요."
    }}
}
struct ClubSeasonReviewBasis:Codable,Equatable {
    let reportID:String
    let date:String
    let period:Int
    let h:Double?
    let environment:String?
    let sample:Int?
    static func make(goal:ClubSeasonGoal,owner:CareerContractJournal,reportID:String,observation:ScoutingObservation,comparisons:[ScoutingPerformanceComparison],on date:String) throws -> Self? {
        guard observation.observedDate >= goal.started,observation.observedDate <= date,
              try GameDate(observation.observedDate).year == goal.year,observation.role.rawValue == goal.playerRole,
              let member=try owner.current(on:GameDate(observation.observedDate)),member.offerID == goal.role.membershipID,
              member.teamID == goal.role.teamID,member.level == goal.role.level,observation.school == member.name else {return nil}
        let selected=ScoutingContractFit.selected(comparisons.filter {$0.id.hasPrefix(goal.role.level+"/")},role:observation.role)
        return Self(reportID:reportID,date:observation.observedDate,period:observation.period,
            h:observation.grades.first {$0.id == goal.role.roleID}?.score,
            environment:selected?.id,sample:selected.map {goal.playerRole == "batter" ? $0.totals.line.plateAppearances:$0.totals.line.pitchingOuts})
    }
}
struct ClubSeasonReview:Codable,Equatable,Identifiable {
    var version=1
    let id:String
    let goalID:String
    let date:String
    let result:ClubSeasonProgress
    let basis:ClubSeasonReviewBasis?
    let advice:ClubNextRoleAdvice
    static func make(goal:ClubSeasonGoal,on date:String,basis:ClubSeasonReviewBasis?) throws -> Self {
        guard let result=goal.result,result.values.count == 2 else {throw ClubSeasonGoalError.unfinished}
        let advice:ClubNextRoleAdvice
        if result.values[0] < goal.targets[0].target {advice = .sampleNeeded}
        else if result.values[1] < goal.targets[1].target {advice = .rolePractice}
        else if basis?.h == nil || basis?.environment == nil || (basis?.sample ?? 0) < (goal.playerRole == "batter" ? 40:45) {advice = .evidenceNeeded}
        else {advice = .roleDiscussion}
        return Self(id:goal.id+"/review-v1",goalID:goal.id,date:date,result:result,basis:basis,advice:advice)
    }
}
extension CareerContractJournal {
    func validateSeasonReviews(today:GameDate,sources:[String:(ScoutingObservation,[ScoutingPerformanceComparison])]) throws {
        let rows=seasonReviews ?? []
        guard Set(rows.map(\.goalID)).count == rows.count else {throw ContractRegistrationError.invalid}
        for row in rows {
            guard row.version == 1,let goal=seasonGoals?.first(where:{$0.id == row.goalID}),let settled=goal.settledOn,
                  row.date >= settled,try GameDate(row.date) <= today,
                  row == (try ClubSeasonReview.make(goal:goal,on:row.date,basis:row.basis)) else {throw ContractRegistrationError.invalid}
            if let basis=row.basis {
                guard let source=sources[basis.reportID],basis == (try ClubSeasonReviewBasis.make(goal:goal,owner:self,reportID:basis.reportID,observation:source.0,comparisons:source.1,on:row.date)) else {throw ContractRegistrationError.invalid}
            }
        }
    }
}


extension CareerContractJournal {
    func latestSeasonReview(membershipID:String,through year:Int) -> (goal:ClubSeasonGoal,review:ClubSeasonReview)? {
        (seasonReviews ?? []).compactMap {review in
            seasonGoals?.first {$0.id == review.goalID && $0.role.membershipID == membershipID && $0.year <= year}.map {(goal:$0,review:review)}
        }.sorted {a,b in
            if a.goal.year != b.goal.year {return a.goal.year > b.goal.year}
            if a.review.date != b.review.date {return a.review.date > b.review.date}
            return a.review.id < b.review.id
        }.first
    }
}
