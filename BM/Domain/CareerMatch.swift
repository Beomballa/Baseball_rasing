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

struct MatchInningScores: Codable, Equatable {
    var version = 1
    var away: [Int?] = [0] + Array(repeating: nil, count: 8)
    var home: [Int?] = Array(repeating: nil, count: 9)

    mutating func record(runs: Int, half: Int) {
        if half.isMultiple(of: 2) { away[half / 2] = (away[half / 2] ?? 0) + runs }
        else { home[half / 2] = (home[half / 2] ?? 0) + runs }
    }
    mutating func enter(half: Int) {
        guard (0..<18).contains(half) else { return }
        if half.isMultiple(of: 2) { away[half / 2] = away[half / 2] ?? 0 }
        else { home[half / 2] = home[half / 2] ?? 0 }
    }
    func validate(match: CareerMatch) throws {
        guard version == 1, away.count == 9, home.count == 9,
              (0...18).contains(match.half), match.homeScore >= 0, match.awayScore >= 0,
              match.completed ? (match.half == 18 || match.half == 17 && match.homeScore > match.awayScore) : match.half < 18 else { throw MatchError.invalidRecord }
        let lastHalf = match.completed ? (match.half == 17 && home[8] == nil ? 16 : 17) : match.half
        for half in 0..<18 {
            let value = half.isMultiple(of: 2) ? away[half / 2] : home[half / 2]
            guard half <= lastHalf ? value.map({ $0 >= 0 }) == true : value == nil else { throw MatchError.invalidRecord }
        }
        for (values, total) in [(away, match.awayScore), (home, match.homeScore)] {
            var remaining = total
            for value in values.compactMap({ $0 }) {
                guard value <= remaining else { throw MatchError.invalidRecord }
                remaining -= value
            }
            guard remaining == 0 else { throw MatchError.invalidRecord }
        }
    }
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
    var scoutingPerformance: MatchScoutingPerformance?
    var preparation:MatchPreparation? = nil
    var competition:String?
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
    var battedBallVersion: Int?
    var npcFielders:MatchNPCFielders?
    var npcAttack:MatchNPCAttack? = nil
    var playerRecords:MatchPlayerRecords? = nil
    var inningScores: MatchInningScores? = nil
    var projectFeedback: MatchProjectFeedback? = nil
    var pitchLog: MatchPitchLog? = nil
    var fieldPlays: [MatchDetailedPlay]?
    var homeRuns: [MatchHomeRun]?
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

    var npcDefenders:[MatchNPCPlayer]? {npcFielders?.team(home:half % 2 == 0).players}
    var npcBatterSpeed:Double {
        guard let roster=npcFielders else {return 60}
        let home=half % 2 == 1,team=roster.team(home:home)
        let lineup=npcLineup(home:home)
        return team.players[lineup[(home ? homeOrder:awayOrder)%9]].speed
    }

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
        if let pitcher=npcActivePitcher,!(role == "pitcher" && ownPitcherActive && !offense) {
            let code=deliveryPitchCode(requested:pitchCode),speed=pitcher.speed(code)
            let width=0.6/sqrt(pitcher.zoneChance)
            return MatchDelivery(x:0.5+(x-0.5)*width,y:0.5+(y-0.5)*width,speed:Int(speed.rounded()),exactSpeed:speed)
        }
        let actualSpeed = ownPitcherActive && abilityStats?.version == 1 ? abilityStats?.speedValue(code: pitchCode ?? "four-seam") : nil
        return MatchDelivery(x: role == "pitcher" ? 0.25 + x * 0.5 : 0.05 + x * 0.9,
                             y: role == "pitcher" ? 0.25 + y * 0.5 : 0.05 + y * 0.9,
                             speed: actualSpeed.map { Int($0.rounded()) } ?? PitchType(rawValue: pitchCode ?? "four-seam").map { Int(145 + $0.speedOffset) } ?? 135, exactSpeed: actualSpeed)
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
        if input != .automatic { scoutingPerformance?.manual = true }
        if input == .automatic {
            while !completed { step(role == "batter" ? .swing : .pitch, pitchCode: mastery.keys.sorted().first); settle() }
        } else {
            settle()
            if !completed { step(input, pitchCode: pitchCode, control: control, direct: true); settle() }
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

    private mutating func step(_ input: MatchInput, pitchCode: String?, control: ManualMatchInput? = nil, direct: Bool = false) {
        let defendingHome = half % 2 == 0, previousHalf = half
        let previousOrder = homeOrder + awayOrder
        let personalPitch=appearance && (role == "batter" ? ownAtBat:ownPitcherActive && !offense)
        let observedPitch=pitchLog == nil ? nil:ObservedPitch.preparation(match:self,pitchCode:pitchCode)
        var observedZone:Bool?
        defer {
            if var observedPitch {
                if personalPitch && controlVersion == 2,let actual=lastManual {
                    observedPitch.x=actual.x;observedPitch.y=actual.y;observedPitch.speed=Double(actual.speed)
                    observedPitch.code=actual.pitchCode ?? observedPitch.code
                    observedPitch.inZone=ManualMatchRules.isStrike(x:actual.x,y:actual.y)
                    observedPitch.source=direct ? "direct":"automatic-position"
                } else {observedPitch.inZone=observedZone;observedPitch.source="automatic-zone"}
                observedPitch.outcome=message
                pitchLog?.pitches.append(observedPitch)
            }
        }
        playerRecords?.recordPitch(home:defendingHome,relief:pitching?.change(home:defendingHome) != nil)
        pitching?.recordPitch(home:defendingHome)
        defer {
            if homeOrder + awayOrder > previousOrder && !completed {
                finishPitcherPlate(home:defendingHome, previousHalf:previousHalf)
            }
        }
        let personal = appearance && (role == "batter" ? ownAtBat : ownPitcherActive && !offense)
        if personal {scoutingPerformance?.inputs?.record(direct:direct)}
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
        let inZone = roll() < (personalPitcher ? (0.5 + quality * 0.002):(npcActivePitcher?.zoneChance ?? (0.5 + quality * 0.002)))
        observedZone=inZone
        let swing:Bool
        if personalBatter {swing=input != .watch}
        else if let batter=npcBatter {swing=roll()<batter.swingChance(inZone:inZone)}
        else {swing=inZone || roll()<0.22}
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" }
            else { balls += 1; message = "볼" }
        } else {
            let baseHit = personalBatter ? 0.14 + contact * 0.002 : 0.27
            let hitChance=npcAttack == nil ? baseHit:max(0.04,min(0.65,baseHit+(personalBatter ? 0:((npcBatter?.contact ?? 60)-60)*0.002)+(personalPitcher ? 0:(npcActivePitcher?.hitAdjustment ?? 0))))
            let value = roll()
            if value < hitChance {
                let baseHR=personalBatter ? power/500:0.12
                let chance=npcAttack == nil ? baseHR:max(0.01,min(0.35,baseHR+(personalBatter ? 0:((npcBatter?.power ?? 60)-60)*0.001)))
                let homeRun = input != .bunt && roll() < chance
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
        let actualCode=deliveryPitchCode(requested:pitchCode)
        let plan = delivery(pitchCode: pitchCode)
        let directionX = roll() < 0.5 ? -1.0 : 1.0
        let directionY = roll() < 0.5 ? -1.0 : 1.0
        let masteryValue = mastery[pitchCode ?? ""] ?? 60
        let quality = pitcher ? releaseQuality(control.release ?? 0, mastery: masteryValue)
            : ManualMatchRules.battingQuality(input: control, delivery: plan, contact: contact, execution: executionFactor)
        let scatter = pitcher ? (1 - quality) * 0.5 * (abilityStats?.scatterScale ?? 1) : 0
        let target = pitcher ? control.pitchTarget : nil
        let x = (target?.x ?? plan.x) + directionX * scatter, y = (target?.y ?? plan.y) + directionY * scatter
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
        let swing:Bool
        if !pitcher {swing=input != .watch}
        else if let batter=npcBatter {swing=roll()<batter.swingChance(inZone:inZone)}
        else {swing=inZone || roll()<0.22}
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" }
            else { balls += 1; message = "볼" }
        } else if !pitcher && quality == 0 {
            strikes += 1; message = "헛스윙"
        } else {
            let baseHit = pitcher ? (abilityStats?.hitChance(quality: quality) ?? (0.36 - quality * 0.20)) : 0.10 + contact * 0.001 + quality * 0.35
            let adjustment=pitcher ? ((npcBatter?.contact ?? 60)-60)*0.002:(npcActivePitcher?.hitAdjustment ?? 0)
            let hitChance=npcAttack == nil ? baseHit:max(0.04,min(0.65,baseHit+adjustment))
            let value = roll()
            if value < hitChance {
                let baseHR=pitcher ? (abilityStats?.homeRunChance(quality: quality) ?? (0.16 - quality * 0.10)):power/500*quality
                let chance=npcAttack == nil ? baseHR:max(0.01,min(0.35,baseHR+(pitcher ? ((npcBatter?.power ?? 60)-60)*0.001:0)))
                let homeRun = input != .bunt && roll() < chance
                endPlate(homeRun ? "홈런" : "안타", batter: !pitcher, pitcher: pitcher, bunt:input == .bunt,
                    battingQuality:pitcher ? nil:quality,pitchingQuality:pitcher ? quality:nil,
                    offsetX:pitcher ? 0:control.x-plan.x,offsetY:pitcher ? 0:control.y-plan.y,
                    timing:pitcher ? 0:(control.timing ?? MatchDelivery.contactPhase)-MatchDelivery.contactPhase)
            } else if !pitcher || value < hitChance + 0.35 {
                endPlate("범타", batter: !pitcher, pitcher: pitcher, bunt:input == .bunt,
                    battingQuality:pitcher ? nil:quality,pitchingQuality:pitcher ? quality:nil,
                    offsetX:pitcher ? 0:control.x-plan.x,offsetY:pitcher ? 0:control.y-plan.y,
                    timing:pitcher ? 0:(control.timing ?? MatchDelivery.contactPhase)-MatchDelivery.contactPhase)
            } else { strikes += 1; message = "헛스윙" }
        }
        if strikes >= 3 { endPlate("삼진", batter: !pitcher, pitcher: pitcher) }
        else if balls >= 4 { endPlate("볼넷", batter: !pitcher, pitcher: pitcher) }
        lastManual = ManualMatchResult(action: input.rawValue, quality: quality, grade: grade,
                                       x: x, y: y, speed: plan.speed, outcome: message, pitchCode: pitcher ? pitchCode : (npcAttack == nil ? "four-seam":actualCode),
                                       pitchAim: target.map { PitchAim(recommended: PitchTarget(x: plan.x, y: plan.y), target: $0) })
    }

    private mutating func endPlate(_ initial: String, batter: Bool, pitcher: Bool, bunt:Bool=false,
            battingQuality:Double?=nil,pitchingQuality:Double?=nil,offsetX:Double=0,offsetY:Double=0,timing:Double=0) {
        var result = initial
        let outsBefore=outs,positionOrder=isHome ? awayOrder:homeOrder
        var detailed: MatchDetailedPlay?
        var cleanForEarned:MatchDetailedPlay?
        let newRunner = FieldRunnerProfile(speed:batter ? fieldStats?.speed ?? 60 : npcBatterSpeed,
            traits:batter ? (fieldStats?.activeTraits ?? []).filter { $0 == .cheetah } : [],own:batter, responsiblePitcher:pitching?.activeID(home:half % 2 == 0))
        if initial == "홈런" {
            let before=bases.enumerated().map {index,occupied in occupied ? (runnerProfiles?[index] ?? FieldRunnerProfile(speed:60)):nil}
            let ownIndex = !offense && appearance && (role != "pitcher" || ownPitcherActive) ? DetailedFieldRules.names.firstIndex(of:fieldStats?.position ?? ""):nil
            let speeds=DetailedFieldRules.names.indices.map {index in index == ownIndex ? fieldStats?.speed ?? 60:npcDefenders?[index].speed ?? 60}
            let event=MatchHomeRun(half:half,order:half%2 == 1 ? homeOrder:awayOrder,seed:random,
                power:batter ? power:(npcBatter?.power ?? 60),quality:battingQuality ?? 0.65,directionOffset:offsetX,
                before:before,batter:newRunner,defenderSpeeds:speeds,ownDefender:ownIndex)
            if homeRuns == nil {homeRuns=[]};homeRuns?.append(event)
        }
        if let version=detailedFieldVersion,[1,2,3,4,5].contains(version), ["안타","범타"].contains(initial) {
            let shot:MatchBattedBall?
            let flyBall:Bool,landing:FieldPoint,flight:Double
            if battedBallVersion == 1 {
                let a=roll(),b=roll(),c=roll()
                let quality=battingQuality ?? max(0.05,0.3+a*0.55-(pitchingQuality ?? 0)*0.35)
                let ball=MatchBattedBall.make(quality:quality,contact:batter ? contact:(npcBatter?.contact ?? 60),power:batter ? power:(npcBatter?.power ?? 60),bunt:bunt,
                    offsetX:offsetX,offsetY:offsetY,timing:timing,speedDraw:a,angleDraw:b,directionDraw:c)
                shot=ball;flyBall=ball.kind.airborne;landing=ball.landing;flight=ball.flight
            } else {
                shot=nil
                flyBall = version >= 3 && !bunt && roll() < 0.30
                let depth = flyBall ? 20 + roll()*65 : bunt ? 3 + roll()*13 : initial == "안타" ? 40 + roll() * 45 : 5 + roll() * 36
                landing = FieldPoint(x:(roll()-0.5)*depth*1.5,y:depth)
                flight = flyBall ? 2.2 + depth/27 : DetailedFieldRules.bases[0].distance(to:landing)/(initial == "안타" ? 28 : 20)
            }
            var play = flyBall ? DetailedFieldRules.resolveFly(half:half,order:half % 2 == 1 ? homeOrder : awayOrder,landing:landing,flight:flight,
                runners:runnerProfiles ?? bases.map { $0 ? FieldRunnerProfile(speed:60) : nil },batter:newRunner,outs:outs,
                stats:fieldStats,defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),ownBatter:batter,relayEnabled:version >= 4,npc:npcDefenders) : DetailedFieldRules.resolve(half:half,order:half % 2 == 1 ? homeOrder : awayOrder,landing:landing,flight:flight,
                runners:runnerProfiles ?? bases.map { $0 ? FieldRunnerProfile(speed:60) : nil },batter:newRunner,outs:outs,
                stats:fieldStats,defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),ownBatter:batter,
                doublePlayEnabled:version >= 2,groundBall:shot.map {$0.kind == .ground} ?? (initial == "범타" && !bunt),relayEnabled:version >= 4,npc:npcDefenders)
            if let shot {
                play.ball=shot.nodes+play.ball.filter {$0.at>shot.flight}
                play.battedBall=shot
            }
            cleanForEarned=play
            if version == 5 {
                let draws=(0..<7).map { _ in roll() }
                play=FieldMisplayRules.applying(to:play,stats:fieldStats,defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),draws:draws,npc:npcDefenders)
            }
            play.battedBall=shot
            if version >= 3 { play.version=version }
            if pitching != nil { MatchPitching.transferChoiceResponsibility(&play) }
            detailed=play;fieldPlays?.append(play)
            if play.ownParticipation || batter {
                lastFieldPlay=play.xpPlay
                if play.ownParticipation,role == "batter",positionExperience != nil {
                    positionExperience?.events.append(MatchPositionEvent(half:half,order:positionOrder,play:play.xpPlay))
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
                    positionExperience?.events.append(MatchPositionEvent(half: half, order: positionOrder, play: play))
                }
                lastFieldPlay = play; result = play.safe ? "안타" : "범타"
            }
        }
        scoutingPerformance?.record(result, batter:batter, pitcher:pitcher)
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
        let earnedContext=playerRecords?.earned == nil ? nil:MatchEarnedPlay(half:half,order:half % 2 == 1 ? homeOrder:awayOrder,
            initial:initial,outs:outsBefore,batter:newRunner,clean:cleanForEarned,stats:fieldStats,
            defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),npc:npcDefenders)
        playerRecords?.recordPlate(home:half % 2 == 1,order:half % 2 == 1 ? homeOrder:awayOrder,
            battingRelief:pitching?.change(home:half % 2 == 1) != nil,
            pitchingRelief:pitching?.change(home:half % 2 == 0) != nil,
            result:result,play:detailed,runs:runs,outsAdded:outs-outsBefore,
            rbi:detailed?.rbi ?? runs,responsible:scoring,earnedContext:earnedContext)
        inningScores?.record(runs: runs, half: half)
        if half % 2 == 0 { awayScore += runs; awayOrder += 1 }
        else { homeScore += runs; homeOrder += 1 }
        balls = 0; strikes = 0
        if half == 17 && homeScore > awayScore { completed = true }
        if outs == 3 {
            half += 1; outs = 0; bases = [false, false, false];runnerProfiles=runnerProfiles.map { _ in [nil,nil,nil] }
            playerRecords?.runners=[nil,nil,nil]
            let nextHalf=half
            if playerRecords?.earned != nil {playerRecords?.earned=MatchEarnedState(half:nextHalf)}
            if half == 17 && homeScore > awayScore { completed = true }
            if half == 18 { completed = true }
            if !completed { inningScores?.enter(half: half) }
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

/// Frozen display inputs for an already-decided home run. Does not consume match RNG or award runs.
struct MatchHomeRun:Codable,Equatable {
    var version=1
    let half:Int
    let order:Int
    let seed:UInt64
    let power:Double
    let quality:Double
    let directionOffset:Double
    let before:[FieldRunnerProfile?]
    let batter:FieldRunnerProfile
    let defenderSpeeds:[Double]
    var ownDefender:Int? = nil
    var eventID:String {"hr-v1/\(half)/\(order)"}
    private var variation:Double {Double(MatchNPCFielders.hash("hr-v1/\(seed)/\(half)/\(order)")%1001)/1000}
    var direction:Double {max(-25,min(25,(variation-0.5)*40+directionOffset*18))}
    var fence:Double {110-abs(direction)*0.45}
    var distance:Int {Int((fence+8+power*0.12+quality*8+variation*8).rounded())}
    var flight:Double {3.8+Double(distance-110)*0.025}
    var duration:Double {max(flight,runners.map(\.arrival).max() ?? 0)}
    var runs:Int {before.compactMap {$0}.count+1}
    var runners:[DetailedRunner] {
        ([0]+(1...3).filter {before[$0-1] != nil}).map {from in
            let profile=from == 0 ? batter:before[from-1]!
            let leg=27.43/(6.3+profile.speed*0.012)
            var nodes=[FieldNode(at:0,point:DetailedFieldRules.bases[from]),FieldNode(at:0.45,point:DetailedFieldRules.bases[from])]
            for base in (from+1)...4 {nodes.append(FieldNode(at:0.45+Double(base-from)*leg,point:DetailedFieldRules.bases[base]))}
            return DetailedRunner(from:from,destination:4,profile:profile,nodes:nodes)
        }
    }
    func ball(at time:Double) -> FieldPoint {
        let p=max(0,min(1,time/flight)),distance=Double(distance)*p*(1.15-0.15*p),radians=direction * .pi/180
        return FieldPoint(x:sin(radians)*distance,y:cos(radians)*distance)
    }
    func height(at time:Double) -> Double {sin(.pi*max(0,min(1,time/flight)))*(24+power*0.05)}
    func defender(_ index:Int,at time:Double) -> FieldPoint {
        let start=DetailedFieldRules.positions[index]
        guard index>=6 else {return start}
        let destination=FieldPoint(x:ball(at:flight).x*0.72,y:88)
        let distance=start.distance(to:destination),travel=max(0,min(flight,time)-0.35)*(4+defenderSpeeds[index]*0.03)
        return start.towards(destination,fraction:travel/max(0.001,distance))
    }
    func validate() throws {
        guard version == 1,(0...17).contains(half),(0...100_000).contains(order),
              [power,quality,directionOffset].allSatisfy(\.isFinite),(0...100).contains(power),(0...1).contains(quality),(-1...1).contains(directionOffset),
              before.count == 3,ownDefender.map({(0..<9).contains($0)}) ?? true,defenderSpeeds.count == 9,defenderSpeeds.allSatisfy({$0.isFinite && (0...100).contains($0)}),
              ([batter]+before.compactMap {$0}).allSatisfy({$0.speed.isFinite && (0...100).contains($0.speed) && TraitLoadout.valid($0.traits)}) else {throw MatchError.invalidRecord}
    }
}
extension CareerMatch {
    func validateHomeRuns() throws {
        guard let homeRuns else {return}
        guard homeRuns.count<=1000,Set(homeRuns.map(\.eventID)).count == homeRuns.count else {throw MatchError.invalidRecord}
        for event in homeRuns {
            try event.validate()
            guard event.half<=half,event.order < (event.half%2 == 1 ? homeOrder:awayOrder) else {throw MatchError.invalidRecord}
        }
    }
}


enum MatchPlanChoice:String,Codable,CaseIterable,Identifiable {
    case onBase,contact,power,control,strikeout,innings
    var id:String {rawValue}
    var label:String {switch self {case .onBase:"출루 우선";case .contact:"컨택 집중";case .power:"장타 공략";case .control:"제구 우선";case .strikeout:"탈삼진 승부";case .innings:"이닝 소화"}}
    var executionHint:String {switch self {
    case .onBase:"볼을 끝까지 확인하세요. 무입력은 지켜보기로 처리됩니다."
    case .contact:"타격 포인트를 공에 맞추고 도착 순간에 스윙하세요."
    case .power:"좋은 코스를 기다려 정확한 스윙으로 장타를 노리세요."
    case .control:"포수 추천 코스와 익숙한 구종으로 릴리스 정확도를 확보하세요."
    case .strikeout:"보유 구종의 속도 차이로 승부하되 볼넷 누적에 주의하세요."
    case .innings:"삼진만 노리기보다 정확한 투구로 투구 수와 실점을 관리하세요."
    }}
    static func choices(_ role:String) -> [Self] {role == "batter" ? [.onBase,.contact,.power]:[.control,.strikeout,.innings]}
    var criteria:String {switch self {
    case .onBase:"3타석 이상 · 안타+볼넷1개 이상 / 삼진1개 이하"
    case .contact:"3타석 이상 · 안타1개 이상 / 삼진0개"
    case .power:"3타석 이상 · 2루타+홈런1개 이상 / 삼진1개 이하"
    case .control:"3이닝 이상 · 볼넷1개 이하 / 피안타4개 이하"
    case .strikeout:"3이닝 이상 · 탈삼진3개 이상 / 볼넷1개 이하"
    case .innings:"3이닝 이상 · 6이닝 도달 / 실점3개 이하"
    }}
}
struct MatchOppositionAnalysis:Codable,Equatable {
    let year:Int
    let teamID:String
    let speed:Double
    let defense:Double
    let arm:Double
    let weakestPosition:String
    var attack:MatchNPCAttackTeam? = nil
    static func make(roster:MatchNPCFielders,isHome:Bool,attack:MatchNPCAttack?=nil) -> Self {
        let team=roster.team(home:!isHome),players=team.players
        func average(_ key:KeyPath<MatchNPCPlayer,Double>) -> Double {(players.reduce(0){$0+$1[keyPath:key]}/Double(players.count)*10).rounded()/10}
        let weak=players.filter {$0.position != "P"}.min {$0.defense == $1.defense ? $0.position < $1.position:$0.defense < $1.defense}!
        return Self(year:roster.year,teamID:team.teamID,speed:average(\.speed),defense:average(\.defense),arm:average(\.arm),weakestPosition:weak.position,attack:attack?.team(home:!isHome))
    }
    var tendencies:[String] {[
        speed >= 70 ? "기동력 경계 · 빠른 주자 다수":"주력은 평균 범위 · 출루 억제 우선",
        defense >= 70 ? "안정적인 수비 · 범타 처리 능력 높음":"수비 경합 여지 · 타구 정확도 활용",
        arm >= 70 ? "강한 송구 · 무리한 추가 진루 주의":"송구 경합에서 주력 활용 가능"
    ]}
    func reason(for choice:MatchPlanChoice) -> String {
        if let attack {
            switch choice {
            case .onBase:return String(format:"선발 제구 %.1f · 볼/스트라이크를 구분해 출루 기회를 확인하세요.",attack.starter.control)
            case .contact:return String(format:"선발 포심 %.0f km/h · 구종별 속도 차이에 타격 타이밍을 맞추세요.",attack.starter.fastball)
            case .power:return String(format:"상대 송구 %.1f · 정확한 타구로 장타 기회를 노리세요.",arm)
            case .control:return String(format:"타선 출루 성향 %.1f · 볼넷으로 주자를 내보내지 않는 승부를 우선합니다.",attack.onBase)
            case .strikeout:return String(format:"타선 장타 성향 %.1f · 탈삼진 목표와 볼넷 제한을 함께 확인하세요.",attack.slugging)
            case .innings:return String(format:"출루/장타 성향 %.1f/%.1f · 실점과 투구 아웃을 함께 관리하세요.",attack.onBase,attack.slugging)
            }
        }
        switch choice {
        case .onBase:return defense >= 70 ? "상대 수비가 안정적입니다. 무리한 타구보다 볼넷을 포함한 출루를 목표로 삼으세요.":"안타와 볼넷을 함께 확인해 출루 기회를 늘리는 계획입니다."
        case .contact:return "상대 수비 최저 포지션은 \(weakestPosition)입니다. 타구 정확도를 우선하되 자동으로 해당 위치에 타구가 가는 것은 아닙니다."
        case .power:return arm >= 70 ? "상대 송구가 강합니다. 추가 진루 경합보다 장타 기회를 노리는 계획입니다.":"장타가 필요한 계획입니다. 삼진 억제 조건도 함께 확인하세요."
        case .control:return "상대 주력 \(String(format:"%.1f",speed)). 볼넷으로 주자를 내보내지 않는 승부를 우선합니다."
        case .strikeout:return speed >= 70 ? "빠른 주자의 인플레이 경합을 줄이기 위한 탈삼진 계획입니다.":"탈삼진 목표와 볼넷 제한을 함께 지켜야 합니다."
        case .innings:return "상대 타격 성향은 아직 자료가 없습니다. 실제 실점과 투구 아웃을 기준으로 이닝 소화를 확인합니다."
        }
    }
    func recommended(role:String) -> MatchPlanChoice {
        if let attack {return role == "batter" ? (attack.starter.control < 60 ? .onBase:attack.starter.velocity >= 75 ? .contact:arm >= 70 ? .power:.contact):(attack.slugging >= 70 ? .strikeout:attack.onBase >= 65 ? .control:.innings)}
        return role == "batter" ? (arm >= 70 ? .power:defense >= 70 ? .onBase:.contact):(speed >= 70 ? .strikeout:.control)
    }
}
struct MatchPreparation:Codable,Equatable {
    let version:Int
    let fixtureID:String
    let choice:MatchPlanChoice
    let analysis:MatchOppositionAnalysis
    var season: MatchOpponentSeason? = nil
}
struct MatchPlanCheck:Codable,Equatable {
    let label:String
    let value:Int
    let target:Int
    let atLeast:Bool
    var met:Bool {atLeast ? value >= target:value <= target}
    var detail:String {label+" \(value) / \(target)"+(atLeast ? " 이상":" 이하")}
}
struct MatchPlanOutcome:Codable,Equatable {
    let enough:Bool
    let checks:[MatchPlanCheck]
    var achieved:Int {checks.filter(\.met).count}
    var label:String {!enough ? "개인 표본 부족":achieved == checks.count ? "계획 달성":achieved > 0 ? "부분 달성":"보완 필요"}
    static func make(match:CareerMatch,includingLive:Bool=false) -> Self? {
        guard (match.completed || includingLive),match.appearance,let preparation=match.preparation else {return nil}
        let line=match.line
        func above(_ label:String,_ value:Int,_ target:Int) -> MatchPlanCheck {Self.check(label,value,target,true)}
        func below(_ label:String,_ value:Int,_ target:Int) -> MatchPlanCheck {Self.check(label,value,target,false)}
        let checks:[MatchPlanCheck]
        switch preparation.choice {
        case .onBase:checks=[above("안타+볼넷",line.hits+line.walks,1),below("삼진",line.strikeouts,1)]
        case .contact:checks=[above("안타",line.hits,1),below("삼진",line.strikeouts,0)]
        case .power:checks=[above("2루타+홈런",(match.scoutingPerformance?.doubles ?? 0)+line.homeRuns,1),below("삼진",line.strikeouts,1)]
        case .control:checks=[below("볼넷",line.pitchingWalks,1),below("피안타",line.hitsAllowed,4)]
        case .strikeout:checks=[above("탈삼진",line.pitchingStrikeouts,3),below("볼넷",line.pitchingWalks,1)]
        case .innings:checks=[above("투구 아웃",line.pitchingOuts,18),below("실점",line.runsAllowed,3)]
        }
        return Self(enough:match.role == "batter" ? line.plateAppearances >= 3:line.pitchingOuts >= 9,checks:checks)
    }
    private static func check(_ label:String,_ value:Int,_ target:Int,_ atLeast:Bool) -> MatchPlanCheck {MatchPlanCheck(label:label,value:value,target:target,atLeast:atLeast)}
}


extension CareerMatch {
    func npcLineup(home:Bool) -> [Int] {
        var lineup=MatchNPCAttackTeam.lineup
        if home == isHome,appearance,role == "batter",let own=DetailedFieldRules.names.firstIndex(of:fieldStats?.position ?? "") {lineup=[own]+lineup.filter {$0 != own}}
        return lineup
    }
    var npcBatter:MatchNPCBatter? {
        let home=half%2 == 1
        guard let team=npcAttack?.team(home:home) else {return nil}
        return team.batters[npcLineup(home:home)[(home ? homeOrder:awayOrder)%9]]
    }
    var npcActivePitcher:MatchNPCPitcher? {
        guard let team=npcAttack?.team(home:half%2 == 0) else {return nil}
        return pitching?.change(home:half%2 == 0) == nil ? team.starter:team.relief
    }
    var opponentPitcher:MatchNPCPitcher? {
        guard let team=npcAttack?.team(home:!isHome) else {return nil}
        return pitching?.change(home:!isHome) == nil ? team.starter:team.relief
    }
    func deliveryPitchCode(requested:String?) -> String {
        guard let pitcher=npcActivePitcher,!(role == "pitcher" && ownPitcherActive && !offense) else {return requested ?? "four-seam"}
        let draw=Int((random >> 16)%100)
        return draw < 50 ? "four-seam":pitcher.pitches[1+(draw-50)%(pitcher.pitches.count-1)]
    }
}

// Official-game counters observe existing decisions without drawing randomness or changing the field state.
struct MatchBattingCounts:Codable,Equatable {
    var plateAppearances=0,atBats=0,singles=0,doubles=0,triples=0,homeRuns=0,walks=0,strikeouts=0
    var runs=0,rbi=0,sacrificeFlies=0,reachedOnError=0,fieldersChoices=0
    var hits:Int {singles+doubles+triples+homeRuns}
    var totalBases:Int {singles+2*doubles+3*triples+4*homeRuns}
    var average:Double? {atBats == 0 ? nil:Double(hits)/Double(atBats)}
    // Current engine rules have no HBP or sacrifice-bunt event; their contributions are zero.
    var onBasePercentage:Double? {let d=atBats+walks+sacrificeFlies;return d == 0 ? nil:Double(hits+walks)/Double(d)}
    var sluggingPercentage:Double? {atBats == 0 ? nil:Double(totalBases)/Double(atBats)}
    var ops:Double? {guard let obp=onBasePercentage,let slg=sluggingPercentage else {return nil};return obp+slg}
    static var keys:[WritableKeyPath<Self,Int>] {[\.plateAppearances,\.atBats,\.singles,\.doubles,\.triples,\.homeRuns,\.walks,\.strikeouts,\.runs,\.rbi,\.sacrificeFlies,\.reachedOnError,\.fieldersChoices]}
    mutating func add(_ other:Self) {for key in Self.keys {self[keyPath:key] += other[keyPath:key]}}
    func validate() throws {
        guard Self.keys.allSatisfy({(0...100_000).contains(self[keyPath:$0])}),
              plateAppearances == atBats+walks+sacrificeFlies,
              hits+strikeouts+reachedOnError+fieldersChoices <= atBats else {throw MatchError.invalidRecord}
    }
}
struct MatchPitchingCounts:Codable,Equatable {
    var pitches=0,battersFaced=0,outs=0,hits=0,homeRuns=0,walks=0,strikeouts=0,runsAllowed=0
    var earnedRuns:Int? = nil
    var era:Double? {guard outs > 0,let earnedRuns else {return nil};return Double(earnedRuns)*27/Double(outs)}
    var innings:String {"\(outs/3).\(outs%3)"}
    static var keys:[WritableKeyPath<Self,Int>] {[\.pitches,\.battersFaced,\.outs,\.hits,\.homeRuns,\.walks,\.strikeouts,\.runsAllowed]}
    mutating func add(_ other:Self) {
        if other.pitches > 0 || other.battersFaced > 0 || other.runsAllowed > 0 {
            earnedRuns=earnedRuns.flatMap {sum in other.earnedRuns.map {sum+$0}}
        }
        for key in Self.keys {self[keyPath:key] += other[keyPath:key]}
    }
    func validate() throws {
        guard earnedRuns.map({(0...runsAllowed).contains($0)}) ?? true,
              Self.keys.allSatisfy({(0...100_000).contains(self[keyPath:$0])}),homeRuns <= hits,
              hits+walks+strikeouts <= battersFaced,strikeouts <= outs else {throw MatchError.invalidRecord}
    }
}
struct MatchBattingRecord:Codable,Equatable {
    let id:String
    let order:Int
    let position:String
    var counts=MatchBattingCounts()
}
struct MatchPitchingRecord:Codable,Equatable {
    let id:String
    let role:String
    var counts=MatchPitchingCounts()
}
struct MatchTeamRecords:Codable,Equatable {
    let teamID:String
    let lineup:[String]
    var batting:[MatchBattingRecord]
    var pitching:[MatchPitchingRecord]
    var battingTotal:MatchBattingCounts {batting.reduce(into:MatchBattingCounts()) {$0.add($1.counts)}}
    // Individual ER charges can differ from reconstructed team ER after a relief change.
    var pitchingTotal:MatchPitchingCounts {pitching.reduce(into:MatchPitchingCounts(earnedRuns:0)) {$0.add($1.counts)}}
    func batterID(order:Int,relief:Bool) -> String {
        let id=lineup[order % 9]
        return relief && id == pitching[0].id ? pitching[1].id:id
    }
    mutating func battingIndex(order:Int,relief:Bool) -> Int {
        let id=batterID(order:order,relief:relief)
        if let index=batting.firstIndex(where:{$0.id == id}) {return index}
        batting.append(MatchBattingRecord(id:id,order:order % 9+1,position:"P"))
        return batting.count-1
    }
}
struct MatchPlayerRecords:Codable,Equatable {
    var version=1
    let careerID:UUID
    let fixtureID:String
    let year:Int
    let competition:String
    var home:MatchTeamRecords
    var away:MatchTeamRecords
    // Parallel runner identities observe base movement; existing runner profiles and judgments remain unchanged.
    var runners:[String?]=[nil,nil,nil]
    var earned:MatchEarnedState? = nil
    static func make(match:CareerMatch,careerID:UUID,fixtureID:String,trackEarnedRuns:Bool=false) -> Self? {
        guard let attack=match.npcAttack else {return nil}
        func team(_ isHome:Bool) -> MatchTeamRecords {
            let source=attack.team(home:isHome)
            let ownPitcher=match.appearance && match.role == "pitcher" && isHome == match.isHome
            let starter=ownPitcher ? careerID.uuidString:source.starter.id
            let batting=match.npcLineup(home:isHome).enumerated().map {order,index in
                let npc=source.batters[index]
                let own=match.appearance && match.role == "batter" && isHome == match.isHome && order == 0
                return MatchBattingRecord(id:own ? careerID.uuidString:npc.position == "P" ? starter:npc.id,order:order+1,position:npc.position)
            }
            return MatchTeamRecords(teamID:source.teamID,lineup:batting.map(\.id),batting:batting,
                pitching:[MatchPitchingRecord(id:starter,role:"starter"),MatchPitchingRecord(id:source.relief.id,role:"relief")])
        }
        var result=Self(careerID:careerID,fixtureID:fixtureID,year:attack.year,competition:attack.competition,home:team(true),away:team(false))
        if trackEarnedRuns {
            result.earned=MatchEarnedState(half:match.half)
            for i in 0..<2 {result.home.pitching[i].counts.earnedRuns=0;result.away.pitching[i].counts.earnedRuns=0}
        }
        return result
    }
    mutating func recordPitch(home defendingHome:Bool,relief:Bool) {
        if defendingHome {home.pitching[relief ? 1:0].counts.pitches += 1}
        else {away.pitching[relief ? 1:0].counts.pitches += 1}
    }
    mutating func recordPlate(home battingHome:Bool,order:Int,battingRelief:Bool,pitchingRelief:Bool,
                              result:String,play:MatchDetailedPlay?,runs:Int,outsAdded:Int,rbi:Int,responsible:[String],earnedContext:MatchEarnedPlay?=nil) {
        var batters=battingHome ? home:away,pitchers=battingHome ? away:home
        let bi=batters.battingIndex(order:order,relief:battingRelief),pi=pitchingRelief ? 1:0
        let batterID=batters.batting[bi].id,before=runners
        var b=batters.batting[bi].counts,p=pitchers.pitching[pi].counts
        b.plateAppearances += 1;p.battersFaced += 1;p.outs += outsAdded;b.rbi += rbi
        if result == "볼넷" {b.walks += 1;p.walks += 1}
        else if play?.sacrificeFly == true {b.sacrificeFlies += 1}
        else {
            b.atBats += 1
            switch result {
            case "안타":b.singles += 1;p.hits += 1
            case "2루타":b.doubles += 1;p.hits += 1
            case "3루타":b.triples += 1;p.hits += 1
            case "홈런":b.homeRuns += 1;p.hits += 1;p.homeRuns += 1
            case "삼진":b.strikeouts += 1;p.strikeouts += 1
            case "실책 출루":b.reachedOnError += 1
            case "야수 선택":b.fieldersChoices += 1
            default:break
            }
        }
        batters.batting[bi].counts=b;pitchers.pitching[pi].counts=p
        func runnerID(_ from:Int) -> String? {from == 0 ? batterID:(1...3).contains(from) ? before[from-1]:nil}
        let scoring:[String]
        if let play {
            scoring=play.runners.filter {!$0.out && $0.destination == 4}.sorted {$0.arrival < $1.arrival}.prefix(runs).compactMap {runnerID($0.from)}
            runners=[nil,nil,nil]
            for runner in play.runners where !runner.out && (1...3).contains(runner.destination) {runners[runner.destination-1]=runnerID(runner.from)}
        } else if result == "홈런" {scoring=before.compactMap {$0}+[batterID];runners=[nil,nil,nil]}
        else if result == "안타" {scoring=[before[2]].compactMap {$0};runners=[batterID,before[0],before[1]]}
        else if result == "볼넷" {
            scoring=runs == 1 ? [before[2]].compactMap {$0}:[]
            if before[0] != nil {if before[1] != nil {runners[2]=before[1]};runners[1]=before[0]};runners[0]=batterID
        } else {scoring=[]}
        for id in scoring {if let index=batters.batting.firstIndex(where:{$0.id == id}) {batters.batting[index].counts.runs += 1}}
        for tag in responsible {
            let relief=tag == MatchPitching.reliefID(home:!battingHome)
            pitchers.pitching[relief ? 1:0].counts.runsAllowed += 1
        }
        if var tracker=earned,let earnedContext {
            let credits=tracker.observe(earnedContext,actual:play,result:result,runs:runs,relief:pitchingRelief)
            for (tag,count) in credits {let i=tag == MatchPitching.reliefID(home:!battingHome) ? 1:0;pitchers.pitching[i].counts.earnedRuns=(pitchers.pitching[i].counts.earnedRuns ?? 0)+count}
            earned=tracker
        }
        if battingHome {home=batters;away=pitchers} else {away=batters;home=pitchers}
    }
    func validate(match:CareerMatch) throws {
        guard version == 1,!fixtureID.isEmpty,let expected=Self.make(match:match,careerID:careerID,fixtureID:fixtureID),
              year == expected.year,competition == expected.competition,home.teamID != away.teamID,
              runners.count == 3,runners.map({$0 != nil}) == match.bases,
              (0...18).contains(match.half),(0...2).contains(match.outs) else {throw MatchError.invalidRecord}
        for isHome in [true,false] {
            let team=isHome ? home:away,other=isHome ? away:home,source=isHome ? expected.home:expected.away
            guard team.teamID == source.teamID,team.lineup == source.lineup,team.lineup.count == 9,
                  Set(team.lineup).count == 9,team.pitching.count == 2,
                  team.pitching.map(\.id) == source.pitching.map(\.id),team.pitching.map(\.role) == ["starter","relief"],
                  (9...10).contains(team.batting.count),Set(team.batting.map(\.id)).count == team.batting.count,
                  Array(team.batting.prefix(9)).map(\.id) == team.lineup else {throw MatchError.invalidRecord}
            for row in team.batting {
                let original=source.batting.first(where:{$0.id == row.id})
                guard (1...9).contains(row.order),
                      original.map({$0.order == row.order && $0.position == row.position}) ??
                        (row.id == source.pitching[1].id && row.position == "P" && source.batting[row.order-1].position == "P") else {throw MatchError.invalidRecord}
                try row.counts.validate()
            }
            for row in team.pitching {try row.counts.validate()}
            let b=team.battingTotal,p=other.pitchingTotal
            let defense=team.pitchingTotal
            let expectedOuts=(isHome ? (match.half+1)/2:match.half/2)*3+((match.half % 2 == 0) == isHome ? match.outs:0)
            guard b.plateAppearances == (isHome ? match.homeOrder:match.awayOrder),
                  b.plateAppearances == p.battersFaced,b.hits == p.hits,b.homeRuns == p.homeRuns,
                  b.walks == p.walks,b.strikeouts == p.strikeouts,
                  b.runs == (isHome ? match.homeScore:match.awayScore),b.rbi <= b.runs,
                  defense.outs == expectedOuts,
                  defense.runsAllowed == (isHome ? match.awayScore:match.homeScore) else {throw MatchError.invalidRecord}
            if let staff=match.pitching {
                for i in 0..<2 {
                    let tag=i == 0 ? MatchPitching.starterID(home:isHome):MatchPitching.reliefID(home:isHome)
                    guard team.pitching[i].counts.runsAllowed == staff.runs[tag,default:0] else {throw MatchError.invalidRecord}
                }
            }
        }
        if let earned {try earned.validate(match:match)}
        guard (home.pitching+away.pitching).allSatisfy({(earned != nil) == ($0.counts.earnedRuns != nil)}) else {throw MatchError.invalidRecord}
        let offense=match.half % 2 == 1 ? home:away
        guard runners.compactMap({$0}).allSatisfy({id in offense.batting.contains {$0.id == id}}) else {throw MatchError.invalidRecord}
    }
}

struct MatchEarnedPlay {
    let half:Int,order:Int
    let initial:String
    let outs:Int
    let batter:FieldRunnerProfile
    let clean:MatchDetailedPlay?
    let stats:MatchFieldStats?
    let defending:Bool
    let npc:[MatchNPCPlayer]?
}
struct EarnedRunner:Codable,Equatable {
    let token:String
    var profile:FieldRunnerProfile
    var unearned=false
}
struct EarnedScore:Codable,Equatable {
    let token:String
    let pitcher:String
    let unearned:Bool
}
struct EarnedView:Codable,Equatable {
    let pitcher:String
    var outs:Int
    var runners:[EarnedRunner?]
    var scored:[String]=[]
    mutating func advance(_ context:MatchEarnedPlay,batter:EarnedRunner,actualBefore:[EarnedRunner?]) {
        guard outs < 3 else {return}
        func runner(_ from:Int) -> EarnedRunner? {from == 0 ? batter:(1...3).contains(from) ? runners[from-1]:nil}
        if ["안타","범타"].contains(context.initial),let original=context.clean {
            var play:MatchDetailedPlay
            if outs == context.outs,runners == actualBefore {play=original}
            else {
                let profiles=runners.map {$0?.profile},airborne=original.battedBall?.kind.airborne ?? (original.fly != nil)
                play=airborne ? DetailedFieldRules.resolveFly(half:context.half,order:context.order,landing:original.landing,flight:original.flight,
                    runners:profiles,batter:batter.profile,outs:outs,stats:context.stats,defending:context.defending,ownBatter:batter.profile.own,relayEnabled:true,npc:context.npc)
                    : DetailedFieldRules.resolve(half:context.half,order:context.order,landing:original.landing,flight:original.flight,
                    runners:profiles,batter:batter.profile,outs:outs,stats:context.stats,defending:context.defending,ownBatter:batter.profile.own,
                    doublePlayEnabled:true,groundBall:original.battedBall?.kind == .ground,relayEnabled:true,npc:context.npc)
            }
            MatchPitching.transferChoiceResponsibility(&play)
            let goals=play.runners.filter {!$0.out && $0.destination == 4}.sorted {$0.arrival < $1.arrival}.prefix(play.runs)
            scored += goals.compactMap {runner($0.from)?.token}
            var after:[EarnedRunner?]=[nil,nil,nil]
            for movement in play.runners where !movement.out && (1...3).contains(movement.destination) {
                var value=runner(movement.from);value?.profile=movement.profile;after[movement.destination-1]=value
            }
            runners=after;outs=min(3,outs+play.outsAdded)
        } else if context.initial == "홈런" {
            scored += runners.compactMap {$0?.token}+[batter.token];runners=[nil,nil,nil]
        } else if context.initial == "볼넷" {
            if runners[0] != nil {
                if runners[1] != nil {if let value=runners[2] {scored.append(value.token)};runners[2]=runners[1]}
                runners[1]=runners[0]
            }
            runners[0]=batter
        } else if context.initial == "안타" {
            if let value=runners[2] {scored.append(value.token)};runners=[batter,runners[0],runners[1]]
        } else {outs += 1}
        if outs >= 3 {runners=[nil,nil,nil]}
    }
}
struct MatchEarnedState:Codable,Equatable {
    var version=1
    let half:Int
    var runners:[EarnedRunner?]=[nil,nil,nil]
    var views:[EarnedView]=[]
    var actual:[EarnedScore]=[]
    var awarded:[String]=[]
    var observedRuns=0
    mutating func observe(_ context:MatchEarnedPlay,actual play:MatchDetailedPlay?,result:String,runs:Int,relief:Bool) -> [String:Int] {
        let defendingHome=context.half % 2 == 0
        let pitcher=relief ? MatchPitching.reliefID(home:defendingHome):MatchPitching.starterID(home:defendingHome)
        // A new reliever starts with actual outs/bases, without earlier missed chances (OBR 9.16(i)).
        if !views.contains(where:{$0.pitcher == pitcher}) {views.append(EarnedView(pitcher:pitcher,outs:context.outs,runners:runners))}
        let token="\(context.half)/\(context.order)"
        let before=runners
        let batter=EarnedRunner(token:token,profile:context.batter)
        for i in views.indices {views[i].advance(context,batter:batter,actualBefore:before)}
        var entrant=batter;entrant.unearned=result == "실책 출루"
        if let play,play.hitBases == 0,play.runners.contains(where:{$0.from == 0 && !$0.out}),
           let replaced=play.runners.filter({$0.from > 0 && $0.out}).max(by:{$0.from < $1.from}) {
            entrant.unearned = entrant.unearned || before[replaced.from-1]?.unearned == true
        }
        func runner(_ from:Int) -> EarnedRunner? {from == 0 ? entrant:(1...3).contains(from) ? before[from-1]:nil}
        var goals:[EarnedRunner]=[]
        if let play {
            for movement in play.runners.filter({!$0.out && $0.destination == 4}).sorted(by:{$0.arrival < $1.arrival}).prefix(runs) {
                if var value=runner(movement.from) {value.profile=movement.profile;goals.append(value)}
            }
            runners=[nil,nil,nil]
            for movement in play.runners where !movement.out && (1...3).contains(movement.destination) {
                var value=runner(movement.from);value?.profile=movement.profile;runners[movement.destination-1]=value
            }
        } else if result == "홈런" {goals=before.compactMap {$0}+[entrant];runners=[nil,nil,nil]}
        else if result == "안타" {goals=[before[2]].compactMap {$0};runners=[entrant,before[0],before[1]]}
        else if result == "볼넷" {
            if runs == 1 {goals=[before[2]].compactMap {$0}}
            if before[0] != nil {if before[1] != nil {runners[2]=before[1]};runners[1]=before[0]};runners[0]=entrant
        }
        observedRuns += runs
        actual += goals.map {EarnedScore(token:$0.token,pitcher:$0.profile.responsiblePitcher ?? "",unearned:$0.unearned)}
        var credits=[String:Int]()
        for run in actual where !run.unearned && !awarded.contains(run.token) {
            if views.first(where:{$0.pitcher == run.pitcher})?.scored.contains(run.token) == true {
                credits[run.pitcher,default:0] += 1;awarded.append(run.token)
            }
        }
        return credits
    }
    func validate(match:CareerMatch) throws {
        let tags=[MatchPitching.starterID(home:half % 2 == 0),MatchPitching.reliefID(home:half % 2 == 0)]
        let prefix="\(half)/"
        guard version == 1,half == match.half,runners.count == 3,runners.map({$0 != nil}) == match.bases,
              actual.count == observedRuns,(0...100_000).contains(observedRuns),views.count <= 2,
              Set(views.map(\.pitcher)).count == views.count,Set(actual.map(\.token)).count == actual.count,
              Set(awarded).count == awarded.count,
              actual.allSatisfy({$0.token.hasPrefix(prefix) && tags.contains($0.pitcher)}),
              awarded.allSatisfy({token in actual.contains {$0.token == token && !$0.unearned}}) else {throw MatchError.invalidRecord}
        for view in views {
            guard tags.contains(view.pitcher),(0...3).contains(view.outs),view.runners.count == 3,
                  view.outs < 3 || view.runners.allSatisfy({$0 == nil}),
                  Set(view.scored).count == view.scored.count,view.scored.allSatisfy({$0.hasPrefix(prefix)}) else {throw MatchError.invalidRecord}
        }
        for value in runners.compactMap({$0})+views.flatMap({$0.runners.compactMap {$0}}) {
            guard value.token.hasPrefix(prefix),value.profile.speed.isFinite,(0...100).contains(value.profile.speed),
                  TraitLoadout.valid(value.profile.traits),value.profile.responsiblePitcher.map({tags.contains($0)}) == true else {throw MatchError.invalidRecord}
        }
        for token in awarded {
            guard let run=actual.first(where:{$0.token == token}),views.first(where:{$0.pitcher == run.pitcher})?.scored.contains(token) == true else {throw MatchError.invalidRecord}
        }
    }
}


/// Exact observed inputs/engine decisions. Unknown automatic coordinates remain nil.
struct MatchPitchLog:Codable,Equatable {
    var version=1
    var pitches:[ObservedPitch]=[]
    func validate(match:CareerMatch) throws {
        guard version == 1,let records=match.playerRecords,pitches.count <= 20000 else {throw MatchError.invalidRecord}
        let players=records.home.pitching+records.away.pitching
        guard pitches.count == players.reduce(0,{$0+$1.counts.pitches}) else {throw MatchError.invalidRecord}
        for (i,p) in pitches.enumerated() {
            guard p.sequence == i+1,players.contains(where:{$0.id == p.pitcherID}),PitchType(rawValue:p.code) != nil,
                  p.speed.isFinite,(1...300).contains(p.speed),(0...3).contains(p.balls),(0...2).contains(p.strikes),
                  ["direct","automatic-position","automatic-zone"].contains(p.source),p.inZone != nil,
                  (p.x == nil) == (p.y == nil) else {throw MatchError.invalidRecord}
            if let x=p.x,let y=p.y {guard x.isFinite,y.isFinite,p.inZone == ManualMatchRules.isStrike(x:x,y:y),p.source != "automatic-zone" else {throw MatchError.invalidRecord}}
            else if p.source != "automatic-zone" {throw MatchError.invalidRecord}
        }
        for player in players {guard pitches.filter({$0.pitcherID == player.id}).count == player.counts.pitches else {throw MatchError.invalidRecord}}
    }
}
struct ObservedPitch:Codable,Equatable {
    let sequence:Int
    let pitcherID:String
    let home:Bool
    var code:String
    var speed:Double
    let balls:Int
    let strikes:Int
    var x:Double?
    var y:Double?
    var inZone:Bool?
    var source:String
    var outcome:String
    static func preparation(match:CareerMatch,pitchCode:String?) -> Self? {
        guard let log=match.pitchLog,let records=match.playerRecords else {return nil}
        let home=match.half%2 == 0,team=home ? records.home:records.away
        let index=match.pitching?.change(home:home) == nil ? 0:1
        let code=match.deliveryPitchCode(requested:pitchCode),delivery=match.delivery(pitchCode:pitchCode)
        return Self(sequence:log.pitches.count+1,pitcherID:team.pitching[index].id,home:home,code:code,speed:Double(delivery.speed),balls:match.balls,strikes:match.strikes,source:"automatic-zone",outcome:"")
    }
}
