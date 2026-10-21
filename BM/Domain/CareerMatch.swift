import Foundation

enum MatchInput: String, CaseIterable, Codable {
    case watch, swing, bunt, pitch, automatic
    var label: String {
        switch self { case .watch: "지켜보기"; case .swing: "스윙"; case .bunt: "번트"; case .pitch: "투구"; case .automatic: "남은 경기 자동 진행" }
    }
}

struct MatchLine: Codable, Equatable {
    var plateAppearances = 0, atBats = 0, hits = 0, homeRuns = 0, walks = 0, strikeouts = 0, rbi = 0
    var pitchingOuts = 0, pitches = 0, hitsAllowed = 0, runsAllowed = 0, pitchingWalks = 0, pitchingStrikeouts = 0
}

/// The saved RNG and complete field state make retry/resume use the same next pitch.
struct CareerMatch: Codable, Equatable {
    var random: UInt64
    var half = 0, outs = 0, balls = 0, strikes = 0
    var bases = [false, false, false]
    var homeScore = 0, awayScore = 0
    var homeOrder = 0, awayOrder = 0
    let isHome: Bool
    let role: String
    let appearance: Bool
    let contact: Double, power: Double, discipline: Double, mastery: [String: Double]
    var line = MatchLine()
    var fatigueCost = 0.0
    var appliedFatigueCost: Int { Int(((fatigueCost * 10_000).rounded() / 10_000).rounded(.up)) }
    var message = "경기 시작"
    var completed = false
    var abilityStats: MatchAbilityStats?
    var fieldStats: MatchFieldStats?
    var lastFieldPlay: MatchFieldPlay?
    var positionExperience: MatchPositionExperience?
    var abilityExperience: MatchAbilityExperience?
    var detailedFieldVersion: Int?
    var fieldPlays: [MatchDetailedPlay]?
    var runnerProfiles: [FieldRunnerProfile?]?
    var trainingEffectsVersion: Int?
    var controlVersion: Int?
    var lastManual: ManualMatchResult?
    var pitching: MatchPitching?
    var ownPitcherActive: Bool { role == "pitcher" && appearance && pitching?.change(home:isHome) == nil }
    var ownPitcherChange: PitcherChange? { role == "pitcher" && appearance ? pitching?.change(home:isHome) : nil }
    var offense: Bool { (half % 2 == 1) == isHome }
    var ownAtBat: Bool { offense && (isHome ? homeOrder : awayOrder) % 9 == 0 }
    var teamScore: Int { isHome ? homeScore : awayScore }
    var opponentScore: Int { isHome ? awayScore : homeScore }
    var inningLabel: String { completed ? "경기 종료" : "\(half / 2 + 1)회 \(half % 2 == 0 ? "초" : "말")" }

    var executionFactor: Double {
        guard let stats = abilityStats, stats.version == 1 else { return 1 }
        let pressure = bases[1] || bases[2] || (half >= 12 && abs(homeScore - awayScore) <= 2)
        return stats.execution(currentFatigue: min(100, Double(stats.fatigue) + fatigueCost), pressure: pressure)
    }
    func releaseGoodWidth(mastery: Double) -> Double {
        ManualMatchRules.goodWidth(mastery: mastery) * (abilityStats?.controlWidth ?? 1) * executionFactor
    }
    func releasePerfectWidth(mastery: Double) -> Double {
        ManualMatchRules.perfectWidth(mastery: mastery) * (abilityStats?.controlWidth ?? 1) * executionFactor
    }
    func releaseQuality(_ phase: Double, mastery: Double) -> Double {
        max(0, 1 - abs(phase - ManualMatchRules.releaseCenter) / (releaseGoodWidth(mastery: mastery) * 2))
    }

    private mutating func roll() -> Double {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return Double(random >> 11) / 9007199254740992
    }

    func delivery(pitchCode: String? = nil) -> MatchDelivery {
        var copy = self
        let x = copy.roll(), y = copy.roll()
        let speeds = ["four-seam": 145, "slider": 132, "changeup": 125, "fork": 129]
        let actualSpeed = ownPitcherActive && abilityStats?.version == 1 ? abilityStats?.speedValue(code: pitchCode ?? "four-seam") : nil
        return MatchDelivery(x: role == "pitcher" ? 0.25 + x * 0.5 : 0.05 + x * 0.9,
                             y: role == "pitcher" ? 0.25 + y * 0.5 : 0.05 + y * 0.9,
                             speed: actualSpeed.map { Int($0.rounded()) } ?? speeds[pitchCode ?? "four-seam"] ?? 135, exactSpeed: actualSpeed)
    }

    func automaticControl(_ input: MatchInput, pitchCode: String?) -> ManualMatchInput {
        let ball = delivery(pitchCode: pitchCode)
        if role == "pitcher" {
            let spread = 0.9 - (mastery[pitchCode ?? ""] ?? 60) * 0.004
            return ManualMatchInput(release: min(1, max(0, 0.68 + (ball.y - 0.5) * spread)))
        }
        if trainingEffectsVersion == 1, input == .swing, !ManualMatchRules.isStrike(x: ball.x, y: ball.y) {
            var sample = self
            _ = sample.roll(); _ = sample.roll()
            if sample.roll() < max(0, min(100, discipline)) / 100 { return ManualMatchInput() }
        }
        let spread = 1 - contact * 0.007
        return ManualMatchInput(x: min(1, max(0, ball.x + (ball.y - 0.5) * spread)), y: ball.y,
                                timing: input == .watch ? nil : min(1, max(0, MatchDelivery.contactPhase + (ball.x - 0.5) * (0.7 - contact * 0.004))))
    }

    mutating func advance(_ input: MatchInput, pitchCode: String? = nil, control: ManualMatchInput? = nil) throws {
        guard !completed else { throw MatchError.finished }
        if role == "pitcher", input == .pitch, mastery[pitchCode ?? ""] == nil { throw MatchError.invalidInput }
        if input != .automatic {
            guard appearance, (role == "pitcher" ? ownPitcherActive : true), (role == "batter" ? [.watch, .swing, .bunt].contains(input) : input == .pitch) else { throw MatchError.invalidInput }
        }
        if let control {
            try control.validate(for: input, role: role)
            controlVersion = 2
        }
        if input == .automatic {
            while !completed { step(role == "batter" ? .swing : .pitch, pitchCode: mastery.keys.sorted().first); settle() }
        } else {
            settle()
            if !completed { step(input, pitchCode: pitchCode, control: control); settle() }
        }
        if completed, let experience = abilityExperience {
            let reward = experience.reward(for: self)
            abilityExperience?.result = reward
        }
    }

    mutating func settle() {
        while !completed && (!appearance || (role == "batter" ? !ownAtBat : offense && ownPitcherActive)) {
            step(.swing, pitchCode: nil)
        }
    }

    private mutating func step(_ input: MatchInput, pitchCode: String?, control: ManualMatchInput? = nil) {
        let defendingHome = half % 2 == 0, previousHalf = half
        let previousOrder = homeOrder + awayOrder
        pitching?.recordPitch(home:defendingHome)
        defer {
            if homeOrder + awayOrder > previousOrder && !completed {
                finishPitcherPlate(home:defendingHome, previousHalf:previousHalf)
            }
        }
        let personal = appearance && (role == "batter" ? ownAtBat : ownPitcherActive && !offense)
        if personal && controlVersion == 2 {
            manualStep(input, pitchCode: pitchCode, control: control ?? automaticControl(input, pitchCode: pitchCode))
            return
        }
        let personalBatter = appearance && role == "batter" && ownAtBat
        let personalPitcher = ownPitcherActive && !offense
        if personalBatter && input != .watch { fatigueCost += 1 }
        // Endurance is not yet stored; use the documented formula with a provisional 60.
        if personalPitcher { line.pitches += 1; fatigueCost += 0.3 + 0.002 * (100 - 60) }
        let quality = personalPitcher ? (mastery[pitchCode ?? ""] ?? 60) : 60
        let inZone = roll() < (0.5 + quality * 0.002)
        let swing = personalBatter ? input != .watch : (inZone || roll() < 0.22)
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" }
            else { balls += 1; message = "볼" }
        } else {
            let hitChance = personalBatter ? 0.14 + contact * 0.002 : 0.27
            let value = roll()
            if value < hitChance {
                let homeRun = input != .bunt && roll() < (personalBatter ? power / 500 : 0.12)
                endPlate(homeRun ? "홈런" : "안타", batter: personalBatter, pitcher: personalPitcher, bunt:input == .bunt)
            } else if value < hitChance + 0.35 {
                endPlate("범타", batter: personalBatter, pitcher: personalPitcher, bunt:input == .bunt)
            } else { strikes += 1; message = "헛스윙" }
        }
        if strikes >= 3 { endPlate("삼진", batter: personalBatter, pitcher: personalPitcher) }
        else if balls >= 4 { endPlate("볼넷", batter: personalBatter, pitcher: personalPitcher) }
    }

    private mutating func manualStep(_ selected: MatchInput, pitchCode: String?, control: ManualMatchInput) {
        let pitcher = role == "pitcher"
        let input: MatchInput = !pitcher && control.timing == nil ? .watch : selected
        let plan = delivery(pitchCode: pitchCode)
        let directionX = roll() < 0.5 ? -1.0 : 1.0
        let directionY = roll() < 0.5 ? -1.0 : 1.0
        let masteryValue = mastery[pitchCode ?? ""] ?? 60
        let quality = pitcher ? releaseQuality(control.release ?? 0, mastery: masteryValue)
            : ManualMatchRules.battingQuality(input: control, delivery: plan, contact: contact, execution: executionFactor)
        let scatter = pitcher ? (1 - quality) * 0.5 * (abilityStats?.scatterScale ?? 1) : 0
        let x = plan.x + directionX * scatter, y = plan.y + directionY * scatter
        let inZone = ManualMatchRules.isStrike(x: x, y: y)
        let releaseError = abs((control.release ?? 0) - ManualMatchRules.releaseCenter)
        let grade = pitcher ? (releaseError <= releasePerfectWidth(mastery: masteryValue) ? "PERFECT"
            : releaseError <= releaseGoodWidth(mastery: masteryValue) ? "GOOD" : "MISS")
            : input == .watch ? "지켜보기" : quality > 0.7 ? "정타" : quality > 0 ? "컨택" : "헛스윙"
        if pitcher {
            line.pitches += 1
            if let stats = abilityStats { fatigueCost = TrainingRules.round(fatigueCost + stats.pitchCost) }
            else { fatigueCost += 0.38 }
        }
        else if input != .watch { fatigueCost += 1 }
        let swing = pitcher ? (inZone || roll() < 0.22) : input != .watch
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" }
            else { balls += 1; message = "볼" }
        } else if !pitcher && quality == 0 {
            strikes += 1; message = "헛스윙"
        } else {
            let hitChance = pitcher ? (abilityStats?.hitChance(quality: quality) ?? (0.36 - quality * 0.20)) : 0.10 + contact * 0.001 + quality * 0.35
            let value = roll()
            if value < hitChance {
                let homeRun = input != .bunt && roll() < (pitcher ? (abilityStats?.homeRunChance(quality: quality) ?? (0.16 - quality * 0.10)) : power / 500 * quality)
                endPlate(homeRun ? "홈런" : "안타", batter: !pitcher, pitcher: pitcher, bunt:input == .bunt)
            } else if !pitcher || value < hitChance + 0.35 {
                endPlate("범타", batter: !pitcher, pitcher: pitcher, bunt:input == .bunt)
            } else { strikes += 1; message = "헛스윙" }
        }
        if strikes >= 3 { endPlate("삼진", batter: !pitcher, pitcher: pitcher) }
        else if balls >= 4 { endPlate("볼넷", batter: !pitcher, pitcher: pitcher) }
        lastManual = ManualMatchResult(action: input.rawValue, quality: quality, grade: grade,
                                       x: x, y: y, speed: plan.speed, outcome: message, pitchCode: pitcher ? pitchCode : "four-seam")
    }

    private mutating func endPlate(_ initial: String, batter: Bool, pitcher: Bool, bunt:Bool=false) {
        var result = initial
        var detailed: MatchDetailedPlay?
        let newRunner = FieldRunnerProfile(speed:batter ? fieldStats?.speed ?? 60 : 60,
            traits:batter ? (fieldStats?.activeTraits ?? []).filter { $0 == .cheetah } : [],own:batter, responsiblePitcher:pitching?.activeID(home:half % 2 == 0))
        if let version=detailedFieldVersion,[1,2,3,4,5].contains(version), ["안타","범타"].contains(initial) {
            let flyBall = version >= 3 && !bunt && roll() < 0.30
            let depth = flyBall ? 20 + roll()*65 : bunt ? 3 + roll()*13 : initial == "안타" ? 40 + roll() * 45 : 5 + roll() * 36
            let landing = FieldPoint(x:(roll()-0.5)*depth*1.5,y:depth)
            let flight = flyBall ? 2.2 + depth/27 : DetailedFieldRules.bases[0].distance(to:landing)/(initial == "안타" ? 28 : 20)
            var play = flyBall ? DetailedFieldRules.resolveFly(half:half,order:half % 2 == 1 ? homeOrder : awayOrder,landing:landing,flight:flight,
                runners:runnerProfiles ?? bases.map { $0 ? FieldRunnerProfile(speed:60) : nil },batter:newRunner,outs:outs,
                stats:fieldStats,defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),ownBatter:batter,relayEnabled:version >= 4) : DetailedFieldRules.resolve(half:half,order:half % 2 == 1 ? homeOrder : awayOrder,landing:landing,flight:flight,
                runners:runnerProfiles ?? bases.map { $0 ? FieldRunnerProfile(speed:60) : nil },batter:newRunner,outs:outs,
                stats:fieldStats,defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),ownBatter:batter,
                doublePlayEnabled:version >= 2,groundBall:initial == "범타" && !bunt,relayEnabled:version >= 4)
            if version == 5 {
                let draws=(0..<7).map { _ in roll() }
                play=FieldMisplayRules.applying(to:play,stats:fieldStats,defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),draws:draws)
            }
            if version >= 3 { play.version=version }
            if pitching != nil { MatchPitching.transferChoiceResponsibility(&play) }
            detailed=play;fieldPlays?.append(play)
            if play.ownParticipation || batter {
                lastFieldPlay=play.xpPlay
                if play.ownParticipation,role == "batter",positionExperience != nil {
                    positionExperience?.events.append(MatchPositionEvent(half:half,order:isHome ? awayOrder : homeOrder,play:play.xpPlay))
                }
            }
            result=play.misplay?.reachedOnError == true ? "실책 출루" : play.fly?.caught == true ? (play.sacrificeFly ? "희생플라이" : "뜬공") : play.hitBases == 2 ? "2루타" : play.hitBases == 1 ? "안타" : play.out ? "범타" : "야수 선택"
        }
        if detailedFieldVersion == nil, let stats = fieldStats, [1, 2, 3].contains(stats.version), appearance, ["안타", "범타"].contains(result), batter || !offense {
            let positions = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF"]
            let fielder = positions[Int(roll() * 9)]
            let ownDefense = !offense && stats.position == fielder
            if batter || ownDefense {
                let chase = 3 + roll() * 14, distance = 10 + roll() * 30
                var play: MatchFieldPlay
                if stats.version >= 2 {
                    play = MatchFieldRules.firstBaseV2(runnerSpeed: batter ? stats.speed : 60, fielderSpeed: ownDefense ? stats.speed : 60,
                        defense: ownDefense ? stats.defense : 60, arm: ownDefense ? stats.arm : 60, chase: chase, distance: distance,
                        ownDefense: ownDefense, active: stats.activeTraits ?? [])
                } else {
                    play = MatchFieldRules.firstBase(runnerSpeed: batter ? stats.speed : 60,
                                                    fielderSpeed: ownDefense ? stats.speed : 60,
                                                    defense: ownDefense ? stats.defense : 60,
                                                    arm: ownDefense ? stats.arm : 60,
                                                    chase: chase, distance: distance, ownDefense: ownDefense)
                }
                if stats.version == 3, let mastery = stats.positionMastery { play = MatchFieldRules.applyingPosition(play, mastery: mastery) }
                if ownDefense, role == "batter", positionExperience != nil {
                    positionExperience?.events.append(MatchPositionEvent(half: half, order: isHome ? awayOrder : homeOrder, play: play))
                }
                lastFieldPlay = play; result = play.safe ? "안타" : "범타"
            }
        }
        message = detailed?.summary ?? result
        var runs = 0
        let beforeProfiles=runnerProfiles
        var scoring:[String]=[]
        if batter {
            line.plateAppearances += 1
            if result != "볼넷" && detailed?.sacrificeFly != true { line.atBats += 1 }
            if result == "안타" || result == "2루타" || result == "홈런" { line.hits += 1 }
            if result == "홈런" { line.homeRuns += 1 }
            if result == "볼넷" { line.walks += 1 }
            if result == "삼진" { line.strikeouts += 1 }
        }
        if let detailed {
            scoring=detailed.runners.filter { !$0.out && $0.destination == 4 }.sorted {$0.arrival < $1.arrival}.prefix(detailed.runs).compactMap { $0.profile.responsiblePitcher }
            runs=detailed.runs;outs += detailed.outsAdded
            if pitcher { line.pitchingOuts += detailed.outsAdded }
            runnerProfiles=detailed.afterRunners;bases=detailed.afterRunners.map { $0 != nil }
        }
        else if result == "홈런" { scoring=(beforeProfiles ?? []).compactMap { $0?.responsiblePitcher } + [newRunner.responsiblePitcher].compactMap { $0 }; runs = bases.filter { $0 }.count + 1; bases = [false, false, false];runnerProfiles=runnerProfiles.map { _ in [nil,nil,nil] } }
        else if result == "안타" { runs = bases[2] ? 1 : 0; bases = [true, bases[0], bases[1]] }
        else if result == "볼넷" {
            if var profiles=runnerProfiles {
                if bases[0] { if bases[1] { profiles[2]=profiles[1] }; profiles[1]=profiles[0] }
                profiles[0]=newRunner;runnerProfiles=profiles
            }
            if bases[0] {
                if bases[1] { if bases[2] { runs = 1 }; bases[2] = true }
                bases[1] = true
            }
            bases[0] = true
        } else {
            outs += 1
            if pitcher { line.pitchingOuts += 1 }
        }
        if var staff=pitching {
            if result == "볼넷",runs > 0,let id=beforeProfiles?[2]?.responsiblePitcher {scoring=[id]}
            // Missing tags only occur in legacy/debug fixtures; production v1 tags every entrant.
            while scoring.count < runs {scoring.append(staff.activeID(home:half % 2 == 0))}
            for id in scoring {staff.runs[id,default:0] += 1}
            pitching=staff
            if role == "pitcher" && appearance {line.runsAllowed=staff.runs[MatchPitching.starterID(home:isHome),default:0]}
        }
        if pitcher {
            if pitching == nil {line.runsAllowed += runs}
            if result == "안타" || result == "2루타" || result == "홈런" { line.hitsAllowed += 1 }
            if result == "삼진" { line.pitchingStrikeouts += 1 }
            if result == "볼넷" { line.pitchingWalks += 1 }
        }
        // A run on a force third-out is already excluded by the shared field timeline.
        if batter { line.rbi += detailed?.rbi ?? runs }
        if half % 2 == 0 { awayScore += runs; awayOrder += 1 }
        else { homeScore += runs; homeOrder += 1 }
        balls = 0; strikes = 0
        if half == 17 && homeScore > awayScore { completed = true }
        if outs == 3 {
            half += 1; outs = 0; bases = [false, false, false];runnerProfiles=runnerProfiles.map { _ in [nil,nil,nil] }
            if half == 17 && homeScore > awayScore { completed = true }
            if half == 18 { completed = true }
        }
    }
}

enum MatchError: LocalizedError {
    case noFixture, preparation, invalidInput, finished, stale, invalidRecord
    var errorDescription: String? {
        switch self {
        case .noFixture: "오늘 진행할 경기가 없습니다."
        case .preparation: "경기 전에 오늘의 훈련 또는 휴식을 먼저 마쳐 주세요."
        case .invalidInput: "현재 역할과 보유 구종에 맞는 입력을 선택해 주세요."
        case .finished: "이미 종료한 경기입니다. 결과를 다시 반영하지 않습니다."
        case .stale: "경기 상태가 변경됐습니다. 화면을 다시 열어 주세요."
        case .invalidRecord: "경기 저장 내용을 확인할 수 없습니다. 기존 데이터를 유지합니다."
        }
    }
}

struct PitcherChange: Codable, Equatable {
    let half: Int
    let outs: Int
    let order: Int
    let pitches: Int
    let fatigue: Double
    let reason: String
    let inheritedBases: [Int]
    let outsAtExit: Int
    let runsAtExit: Int
}

/// One starter and one pooled NPC reliever per side. No permanent roster is invented.
struct MatchPitching: Codable, Equatable {
    var version = 1
    var startingFatigue = 0
    var homePitches = 0, awayPitches = 0
    var homeChange: PitcherChange?, awayChange: PitcherChange?
    var runs: [String:Int] = [:]
    static func starterID(home:Bool) -> String { home ? "home-starter":"away-starter" }
    static func reliefID(home:Bool) -> String { home ? "home-relief":"away-relief" }
    static let ids = ["home-starter","away-starter","home-relief","away-relief"]
    func change(home:Bool) -> PitcherChange? {home ? homeChange:awayChange}
    func count(home:Bool) -> Int {home ? homePitches:awayPitches}
    func activeID(home:Bool) -> String {change(home:home) == nil ? Self.starterID(home:home):Self.reliefID(home:home)}
    mutating func recordPitch(home:Bool) {
        guard change(home:home) == nil else {return}
        if home {homePitches += 1} else {awayPitches += 1}
    }
    static func limit(stamina:Double) -> Int {Int((70+0.4*min(100,max(0,stamina))).rounded())}
    static func transferChoiceResponsibility(_ play:inout MatchDetailedPlay) {
        guard play.hitBases == 0,let batter=play.runners.firstIndex(where:{$0.from == 0 && !$0.out}),
              let replaced=play.runners.filter({$0.from > 0 && $0.out}).max(by:{$0.from < $1.from}),
              let id=replaced.profile.responsiblePitcher else {return}
        play.runners[batter].profile.responsiblePitcher=id
        let destination=play.runners[batter].destination
        if (1...3).contains(destination) {play.afterRunners[destination-1]=play.runners[batter].profile}
    }
}

extension CareerMatch {
    var pitchingLabel: String {
        guard let pitching else {return "선발 투수"}
        return pitching.change(home:half % 2 == 0) == nil ? "선발 · \(pitching.count(home:half % 2 == 0))구":"구원 투수"
    }
    mutating func finishPitcherPlate(home:Bool,previousHalf:Int) {
        guard var staff=pitching,staff.change(home:home) == nil else {return}
        let own=role == "pitcher" && appearance && home == isHome
        let stamina=own ? abilityStats?.stamina ?? 60:60
        let fatigue=own ? min(100,Double(staff.startingFatigue)+fatigueCost):0
        guard staff.count(home:home) >= MatchPitching.limit(stamina:stamina) || fatigue >= 100 else {return}
        let sameHalf=half == previousHalf
        let change=PitcherChange(half:previousHalf,outs:sameHalf ? outs:3,order:home ? awayOrder:homeOrder,
            pitches:staff.count(home:home),fatigue:fatigue,reason:fatigue >= 100 ? "피로 한도":"투구 수 한도",
            inheritedBases:sameHalf ? bases.indices.filter {bases[$0]}.map {$0+1}:[],
            outsAtExit:own ? line.pitchingOuts:0,runsAtExit:staff.runs[MatchPitching.starterID(home:home),default:0])
        if home {staff.homeChange=change} else {staff.awayChange=change}
        pitching=staff
    }
    func validatePitching() throws {
        guard let staff=pitching else {return}
        guard staff.version == 1,detailedFieldVersion == 5,(0...100).contains(staff.startingFatigue),staff.homePitches >= 0,staff.awayPitches >= 0,
              staff.runs.allSatisfy({MatchPitching.ids.contains($0.key) && $0.value >= 0}),
              staff.runs["home-starter",default:0]+staff.runs["home-relief",default:0] == awayScore,
              staff.runs["away-starter",default:0]+staff.runs["away-relief",default:0] == homeScore else {throw MatchError.invalidRecord}
        for home in [false,true] {
            if let c=staff.change(home:home) {
                guard (0..<18).contains(c.half),(c.half % 2 == 0) == home,(0...3).contains(c.outs),c.order >= 0,
                      c.pitches == staff.count(home:home),c.pitches > 0,c.fatigue.isFinite,(0...100).contains(c.fatigue),
                      ["피로 한도","투구 수 한도"].contains(c.reason),c.outsAtExit >= 0,c.runsAtExit >= 0,
                      c.inheritedBases.allSatisfy({(1...3).contains($0)}),Set(c.inheritedBases).count == c.inheritedBases.count else {throw MatchError.invalidRecord}
            }
        }
        let profiles=(runnerProfiles ?? []).compactMap {$0}+(fieldPlays ?? []).flatMap {$0.runners.map(\.profile)}
        guard profiles.allSatisfy({$0.responsiblePitcher.map {MatchPitching.ids.contains($0)} ?? true}) else {throw MatchError.invalidRecord}
        if role == "pitcher" && appearance {
            guard line.runsAllowed == staff.runs[MatchPitching.starterID(home:isHome),default:0],
                  line.pitches == staff.count(home:isHome),ownPitcherChange.map({$0.outsAtExit == line.pitchingOuts && $0.runsAtExit <= line.runsAllowed}) ?? true else {throw MatchError.invalidRecord}
        }
    }
}

struct MatchAbilityAward: Codable, Equatable {
    let kind: TrainingKind
    let rawXP: Double
    let before: Double
    let after: Double
    var gain: Double { TrainingRules.round(after - before) }
}

struct MatchAbilityGrowth: Codable, Equatable {
    let rawXP: Double
    let participation: Double
    let quality: Double
    let awards: [MatchAbilityAward]
}

/// Optional match payload: old in-progress and completed matches never acquire this reward.
struct MatchAbilityExperience: Codable, Equatable {
    var version = 1
    let year: Int
    let age: Int
    let fatigue: Int
    let before: [String: Double]
    let annualBefore: Double
    var result: MatchAbilityGrowth?
    static let annualCap = 80.0
    static func kinds(role: String) -> [TrainingKind] {
        role == "batter" ? [.contact, .power, .discipline, .mental] : [.control, .stuff, .stamina, .mental]
    }
    func reward(for match: CareerMatch) -> MatchAbilityGrowth {
        let line = match.line, batter = match.role == "batter"
        let pa = Double(line.plateAppearances), outs = Double(line.pitchingOuts)
        let participation = !match.appearance ? 0 : batter ? min(1, pa / 4)
            : line.pitches > 0 ? max(0.2, min(1, outs / 18)) : 0
        let quality = batter ? min(1, Double(line.hits + line.walks + 2 * line.homeRuns) / max(1, pa))
            : 0.5 * min(1, Double(line.pitchingStrikeouts) / max(1, outs))
                + 0.5 * (1 - min(1, Double(line.hitsAllowed + line.pitchingWalks) / max(1, outs)))
        let kinds = Self.kinds(role: match.role)
        let weights: [Double] = batter
            ? [Double(line.atBats), Double(4 * line.homeRuns), pa + Double(2 * line.walks), pa]
            : [1 + max(0, 1 - Double(line.pitchingWalks) * 4 / Double(max(1, line.pitches))),
               outs > 0 ? 1 + 2 * Double(line.pitchingStrikeouts) / outs : 0, min(1, outs / 18), 1]
        let eligible = kinds.indices.filter { before[kinds[$0].rawValue, default: 100] < 100 && weights[$0] > 0 }
        let totalWeight = eligible.reduce(0.0) { $0 + weights[$1] }
        let raw = match.completed && totalWeight > 0
            ? TrainingRules.round(min(max(0, Self.annualCap - annualBefore), (batter ? 2 : 10) * participation * (1 + 0.3 * quality))) : 0
        var remaining = raw
        let awards = kinds.indices.map { index in
            let value = before[kinds[index].rawValue, default: 100]
            // Keep the sum of rounded allocations equal to the annual raw budget exactly.
            let allocation = !eligible.contains(index) ? 0 : index == eligible.last ? remaining
                : min(remaining, TrainingRules.round(raw * weights[index] / (totalWeight > 0 ? totalWeight : 1)))
            remaining = TrainingRules.round(remaining - allocation)
            return MatchAbilityAward(kind: kinds[index], rawXP: allocation, before: value,
                after: TrainingRules.round(min(100, value + allocation / 100 * TrainingRules.growthEfficiency(before: value, fatigue: fatigue, age: age))))
        }
        return MatchAbilityGrowth(rawXP: raw, participation: participation, quality: quality, awards: awards)
    }
    func validate(match: CareerMatch) throws {
        let kinds = Self.kinds(role: match.role)
        guard version == 1, ["batter", "pitcher"].contains(match.role), match.appearance,
              (1...9999).contains(year), (1...120).contains(age), (0...100).contains(fatigue),
              annualBefore.isFinite, (0...Self.annualCap).contains(annualBefore),
              Set(before.keys) == Set(kinds.map(\.rawValue)),
              before.values.allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { throw MatchError.invalidRecord }
        guard let stats = match.abilityStats, stats.version == 1, stats.mental == before["mental"], stats.fatigue == fatigue,
              match.role == "batter" ? (match.contact == before["contact"] && match.power == before["power"] && match.discipline == before["discipline"])
                : (stats.control == before["control"] && stats.stuff == before["stuff"] && stats.stamina == before["stamina"]) else { throw MatchError.invalidRecord }
        let l = match.line
        guard [l.plateAppearances,l.atBats,l.hits,l.homeRuns,l.walks,l.strikeouts,l.pitchingOuts,l.pitches,l.hitsAllowed,l.pitchingWalks,l.pitchingStrikeouts].allSatisfy({ (0...100_000).contains($0) }),
              l.homeRuns <= l.hits, l.hits <= l.atBats, l.atBats + l.walks <= l.plateAppearances,
              l.strikeouts <= l.atBats, l.pitchingStrikeouts <= l.pitchingOuts,
              match.completed ? result == reward(for: match) : result == nil else { throw MatchError.invalidRecord }
    }
}
