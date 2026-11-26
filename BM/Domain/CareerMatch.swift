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
    var hitByPitch: Int? = nil
    var hitBatters: Int? = nil
    var wildPitches: Int? = nil
    var passedBalls: Int? = nil
    var strikeoutsWithoutOut: Int? = nil
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
    enum AutomaticSegmentStop: Equatable {
        case nextAppearance, pitcherReplaced, gameCompleted
    }

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
    var fieldReviewVersion: Int? = nil
    var specialRulesVersion: Int? = nil
    var appealRulesVersion: Int? = nil
    var officialReview: MatchOfficialReview? = nil
    var npcFielders:MatchNPCFielders?
    var npcAttack:MatchNPCAttack? = nil
    var npcReadiness: MatchNPCReadiness? = nil
    var playerRecords:MatchPlayerRecords? = nil
    var lineupSeasons: [MatchOpponentSeason]? = nil
    var battingOrder: MatchBattingOrder? = nil
    var runnerManagement: MatchRunnerManagement? = nil
    var inningScores: MatchInningScores? = nil
    var clubSelection: MatchClubSelection? = nil
    var projectFeedback: MatchProjectFeedback? = nil
    var pitchLog: MatchPitchLog? = nil
    var pitchEvents: MatchPitchEvents? = nil
    var running: MatchRunningState? = nil
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
    var canAdvanceToNextAppearance: Bool {
        !completed && appearance && (role == "batter" ? ownAtBat : ownPitcherActive && !offense)
    }
    var teamScore: Int { isHome ? homeScore : awayScore }
    var opponentScore: Int { isHome ? awayScore : homeScore }
    var inningLabel: String { completed ? "경기 종료" : "\(half / 2 + 1)회 \(half % 2 == 0 ? "초" : "말")" }

    var npcDefenders:[MatchNPCPlayer]? {
        guard let players=npcFielders?.team(home:half % 2 == 0).players else {return nil}
        let batters=npcAttack?.team(home:half % 2 == 0).batters ?? []
        return players.map { player in
            var value = player
            value.positionMastery = batters.first { $0.id == player.id }?.profile?.positionMastery
            if let change = runnerManagement?.change(home: half % 2 == 0), change.position == player.position,
               let reserve = runnerManagement?.reserve(home: half % 2 == 0) {
                value = MatchNPCPlayer(id: reserve.id, position: player.position, speed: reserve.speed,
                    defense: reserve.defense, arm: reserve.arm, positionMastery: value.positionMastery)
            }
            return value
        }
    }
    var npcPressure:Bool {bases[1] || bases[2] || (half >= 12 && abs(homeScore-awayScore) <= 2)}
    var npcContact:Double {guard let batter=npcBatter else {return 60};return batter.contact*batter.execution(pressure:npcPressure)}
    var npcPower:Double {guard let batter=npcBatter else {return 60};return batter.power*batter.execution(pressure:npcPressure)}
    var npcBatterSpeed:Double {
        guard let roster=npcFielders else {return 60}
        let home=half % 2 == 1,team=roster.team(home:home)
        let lineup=npcLineup(home:home)
        let slot = (home ? homeOrder : awayOrder) % 9 + 1
        if runnerManagement?.change(home: home)?.slot == slot { return runnerManagement!.reserve(home: home).speed }
        return team.players[lineup[slot - 1]].speed
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

    mutating func roll() -> Double {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return Double(random >> 11) / 9007199254740992
    }

    func delivery(pitchCode: String? = nil) -> MatchDelivery {
        var copy = self
        let x = copy.roll(), y = copy.roll()
        if let pitcher=npcActivePitcher,!(role == "pitcher" && ownPitcherActive && !offense) {
            let code=deliveryPitchCode(requested:pitchCode),speed=pitcher.speed(code)
            let width=0.6/sqrt(pitcher.zoneChance(pressure:npcPressure))
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
        if input != .automatic, canPrepareRunning { throw MatchError.invalidInput }
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
            while !completed { advanceAutomaticPitch() }
        } else {
            settle()
            if !completed { step(input, pitchCode: pitchCode, control: control, direct: true); settle() }
        }
        finalizeAbilityExperience()
    }

    mutating func advanceToNextAppearance() throws -> AutomaticSegmentStop {
        guard !completed else { throw MatchError.finished }
        guard canAdvanceToNextAppearance else { throw MatchError.invalidInput }
        let startingHalf = half
        let startingOrder = isHome ? homeOrder : awayOrder

        while !completed {
            advanceAutomaticPitch()
            if completed { break }
            if ownPitcherChange != nil { return .pitcherReplaced }
            guard balls == 0, strikes == 0 else { continue }
            // Consume the current appearance even when it is waiting on its first pitch.
            if role == "batter" {
                if ownAtBat && (isHome ? homeOrder : awayOrder) != startingOrder { return .nextAppearance }
            } else if half != startingHalf, !offense, outs == 0 {
                return .nextAppearance
            }
        }

        finalizeAbilityExperience()
        return .gameCompleted
    }

    private mutating func advanceAutomaticPitch() {
        step(role == "batter" ? .swing : .pitch, pitchCode: mastery.keys.sorted().first)
        settle()
    }

    mutating func finalizeAbilityExperience() {
        if completed, let experience = abilityExperience {
            let reward = experience.reward(for: self)
            abilityExperience?.result = reward
        }
    }

    mutating func settle() {
        while !completed && (!appearance || (role == "batter" ? !ownAtBat : offense && ownPitcherActive)) {
            if canPrepareRunning { break }
            step(.swing, pitchCode: nil)
        }
    }

    mutating func step(_ input: MatchInput, pitchCode: String?, control: ManualMatchInput? = nil, direct: Bool = false) {
        applyCoachRunnerChange()
        if resolveRunningPickoff() { return }
        let runningBefore = MatchPitchState(self)
        let runningEventsBefore = pitchEvents?.events.count ?? 0
        let fieldBefore = fieldPlays?.count ?? 0, homeRunsBefore = homeRuns?.count ?? 0
        let attemptedRun: Bool
        if runningEligible {
            if canPrepareRunning { attemptedRun = running?.reservation == runningReservation }
            else {
                var sample = self; sample.random ^= 0x52554E4E494E4731
                attemptedRun = sample.roll() < (0.05 + (runnerProfiles?[0]?.speed ?? 60) * 0.001)
            }
        } else { attemptedRun = false }
        let defendingHome = half % 2 == 0, previousHalf = half
        let previousOrder = homeOrder + awayOrder
        defer { closeOfficialReview() }
        let npcPitchCode=deliveryPitchCode(requested:pitchCode)
        let personalPitch=appearance && (role == "batter" ? ownAtBat:ownPitcherActive && !offense)
        let observedPitch=pitchLog == nil ? nil:ObservedPitch.preparation(match:self,pitchCode:pitchCode)
        var observedZone:Bool?
        var automaticDelivery: MatchDelivery?
        defer {
            if var observedPitch {
                if personalPitch && controlVersion == 2,let actual=lastManual {
                    observedPitch.x=actual.x;observedPitch.y=actual.y;observedPitch.speed=Double(actual.speed)
                    observedPitch.code=actual.pitchCode ?? observedPitch.code
                    observedPitch.inZone=ManualMatchRules.isStrike(x:actual.x,y:actual.y)
                    observedPitch.source=direct ? "direct":"automatic-position"
                } else if let automaticDelivery {
                    observedPitch.x = automaticDelivery.x; observedPitch.y = automaticDelivery.y
                    observedPitch.speed = Double(automaticDelivery.speed)
                    observedPitch.inZone = ManualMatchRules.isStrike(x: automaticDelivery.x, y: automaticDelivery.y)
                    observedPitch.source = "automatic-position"
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
                applyCoachRunnerChange()
            }
        }
        defer {
            let speed = personalPitch ? lastManual.map { Double($0.speed) }
                : automaticDelivery.map { $0.exactSpeed ?? Double($0.speed) } ?? observedPitch?.speed
            let flight = speed.map { 0.90 * 145 / $0 } ?? delivery(pitchCode: pitchCode).flightDuration
            resolveRunningPitch(before: runningBefore, eventCount: runningEventsBefore, fieldCount: fieldBefore,
                homeRunCount: homeRunsBefore, attempted: attemptedRun, pitchFlight: flight)
            resolveSharedPitch(before: runningBefore, eventCount: runningEventsBefore, fieldCount: fieldBefore, homeRunCount: homeRunsBefore, pitchFlight: flight)
        }
        let personal = appearance && (role == "batter" ? ownAtBat : ownPitcherActive && !offense)
        if personal {scoutingPerformance?.inputs?.record(direct:direct)}
        if personal && controlVersion == 2 {
            manualStep(input, pitchCode: pitchCode, control: control ?? automaticControl(input, pitchCode: pitchCode), direct: direct)
            return
        }
        if pitchEvents != nil, !personal {
            automaticDelivery = eventAutomaticStep(pitchCode: pitchCode)
            return
        }
        let personalBatter = appearance && role == "batter" && ownAtBat
        let personalPitcher = ownPitcherActive && !offense
        if personalBatter && input != .watch { fatigueCost += 1 }
        // Endurance is not yet stored; use the documented formula with a provisional 60.
        if personalPitcher { line.pitches += 1; fatigueCost += 0.3 + 0.002 * (100 - 60) }
        let quality = personalPitcher ? (mastery[pitchCode ?? ""] ?? 60) : 60
        let inZone = roll() < (personalPitcher ? (0.5 + quality * 0.002):(npcActivePitcher?.zoneChance(pressure:npcPressure) ?? (0.5 + quality * 0.002)))
        observedZone=inZone
        let swing:Bool
        if personalBatter {swing=input != .watch}
        else if let batter=npcBatter {swing=roll()<batter.swingChance(inZone:inZone,pressure:npcPressure)}
        else {swing=inZone || roll()<0.22}
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" }
            else { balls += 1; message = "볼" }
        } else {
            let baseHit = personalBatter ? 0.14 + contact * 0.002 : 0.27
            let hitChance=npcAttack == nil ? baseHit:max(0.04,min(0.65,baseHit+(personalBatter ? 0:(npcContact-60)*0.002)+(personalPitcher ? 0:(npcActivePitcher?.hitAdjustment(code:npcPitchCode,pressure:npcPressure) ?? 0))))
            let value = roll()
            if value < hitChance {
                let baseHR=personalBatter ? power/500:0.12
                let chance=npcAttack == nil ? baseHR:max(0.01,min(0.35,baseHR+(personalBatter ? 0:(npcPower-60)*0.001)))
                let npcHR = personalPitcher ? 0:(npcActivePitcher?.homeRunAdjustment(code:npcPitchCode,pressure:npcPressure) ?? 0)
                let homeRun = input != .bunt && roll() < (npcActivePitcher?.profile == nil ? chance:max(0.01,min(0.35,chance+npcHR)))
                endPlate(homeRun ? "홈런" : "안타", batter: personalBatter, pitcher: personalPitcher, bunt:input == .bunt)
            } else if value < hitChance + 0.35 {
                endPlate("범타", batter: personalBatter, pitcher: personalPitcher, bunt:input == .bunt)
            } else { strikes += 1; message = "헛스윙" }
        }
        if strikes >= 3 { endPlate("삼진", batter: personalBatter, pitcher: personalPitcher) }
        else if balls >= 4 { endPlate("볼넷", batter: personalBatter, pitcher: personalPitcher) }
    }

    private mutating func manualStep(_ selected: MatchInput, pitchCode: String?, control: ManualMatchInput, direct: Bool) {
        let beforePitch = MatchPitchState(self)
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
        else if let batter=npcBatter {swing=roll()<batter.swingChance(inZone:inZone,pressure:npcPressure)}
        else {swing=inZone || roll()<0.22}
        var catchObservation = MatchPitchEventRules.observation(x: x, y: y, defense: pitchEventCatcherDefense)
        let lost = pitchEvents != nil && MatchPitchEventRules.loses(catchObservation, draw: roll())
        if lost { catchObservation = MatchPitchEventRules.observation(x: x, y: y, defense: pitchEventCatcherDefense, escape: roll()) }
        func receipt(_ outcome: String) -> ManualMatchResult {
            ManualMatchResult(action: input.rawValue, quality: quality, grade: grade, x: x, y: y, speed: plan.speed,
                outcome: outcome, pitchCode: pitcher ? pitchCode : (npcAttack == nil ? "four-seam" : actualCode),
                pitchAim: target.map { PitchAim(recommended: PitchTarget(x: plan.x, y: plan.y), target: $0) },
                pitchEventSequence: pitchEvents?.events.last.flatMap { $0.sequence == pitchEventSequence ? $0.sequence : nil })
        }
        if pitchEvents != nil {
            if MatchPitchEventRules.hitByPitch(x: x, y: y, swinging: swing, left: pitcher && opponentBatterSide == .left) {
                pitchHitByPitch(before: beforePitch, batter: !pitcher, pitcher: pitcher, direct: direct)
                lastManual = receipt(message); return
            }
            let timingError = abs((control.timing ?? MatchDelivery.contactPhase) - MatchDelivery.contactPhase)
            let edgeContact = quality > 0 && timingError > ManualMatchRules.timingWidth(contact: contact) * 0.25
            if swing && (pitcher ? roll() < 0.13 : edgeContact) {
                pitchFoul(before: beforePitch, bunt: input == .bunt, batter: !pitcher, pitcher: pitcher, direct: direct)
                lastManual = receipt(message); return
            }
        }
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" }
            else { balls += 1; message = "볼" }
        } else if !pitcher && quality == 0 {
            strikes += 1; message = "헛스윙"
        } else {
            let baseHit = pitcher ? (abilityStats?.hitChance(quality: quality) ?? (0.36 - quality * 0.20)) : 0.10 + contact * 0.001 + quality * 0.35
            let adjustment=pitcher ? (npcContact-60)*0.002:(npcActivePitcher?.hitAdjustment(code:actualCode,pressure:npcPressure) ?? 0)
            let hitChance=npcAttack == nil ? baseHit:max(0.04,min(0.65,baseHit+adjustment))
            let value = roll()
            if value < hitChance {
                let baseHR=pitcher ? (abilityStats?.homeRunChance(quality: quality) ?? (0.16 - quality * 0.10)):power/500*quality
                let chance=npcAttack == nil ? baseHR:max(0.01,min(0.35,baseHR+(pitcher ? (npcPower-60)*0.001:0)))
                let npcHR = pitcher ? 0:(npcActivePitcher?.homeRunAdjustment(code:actualCode,pressure:npcPressure) ?? 0)
                let homeRun = input != .bunt && roll() < (npcActivePitcher?.profile == nil ? chance:max(0.01,min(0.35,chance+npcHR)))
                endPlate(homeRun ? "홈런" : "안타", batter: !pitcher, pitcher: pitcher, bunt:input == .bunt,
                    battingQuality:pitcher ? nil:quality,pitchingQuality:pitcher ? quality:nil,
                    offsetX:pitcher ? 0:control.x-plan.x,offsetY:pitcher ? 0:control.y-plan.y,
                    timing:pitcher ? 0:(control.timing ?? MatchDelivery.contactPhase)-MatchDelivery.contactPhase,direct:direct)
            } else if !pitcher || value < hitChance + 0.35 {
                endPlate("범타", batter: !pitcher, pitcher: pitcher, bunt:input == .bunt,
                    battingQuality:pitcher ? nil:quality,pitchingQuality:pitcher ? quality:nil,
                    offsetX:pitcher ? 0:control.x-plan.x,offsetY:pitcher ? 0:control.y-plan.y,
                    timing:pitcher ? 0:(control.timing ?? MatchDelivery.contactPhase)-MatchDelivery.contactPhase,direct:direct)
            } else { strikes += 1; message = "헛스윙" }
        }
        let missedContact = message == "헛스윙" || message == "루킹 스트라이크" || message == "볼"
        if strikes >= 3 {
            if lost { pitchUncaughtThird(before: beforePitch, observation: catchObservation, batter: !pitcher, pitcher: pitcher, direct: direct) }
            else { endPlate("삼진", batter: !pitcher, pitcher: pitcher) }
        } else {
            let walked = balls >= 4
            if walked { endPlate("볼넷", batter: !pitcher, pitcher: pitcher) }
            if lost && missedContact { pitchLoose(before: beforePitch, observation: catchObservation, personal: true, direct: direct, walked: walked) }
        }
        lastManual = receipt(message)
    }

    mutating func endPlate(_ initial: String, batter: Bool, pitcher: Bool, bunt:Bool=false,
            battingQuality:Double?=nil,pitchingQuality:Double?=nil,offsetX:Double=0,offsetY:Double=0,timing:Double=0,direct:Bool=false) {
        var result = initial
        let positionOrder=isHome ? awayOrder:homeOrder
        var detailed: MatchDetailedPlay?
        var cleanForEarned:MatchDetailedPlay?
        let newRunner = FieldRunnerProfile(speed:batter ? fieldStats?.speed ?? 60 : npcBatterSpeed,
            traits:batter ? (fieldStats?.activeTraits ?? []).filter { $0 == .cheetah } : [],own:batter, responsiblePitcher:pitching?.activeID(home:half % 2 == 0),
            id: playerRecords.map { $0.homeTeam(batting: half).batterID(order: half % 2 == 1 ? homeOrder : awayOrder, relief: pitching?.change(home: half % 2 == 1) != nil) })
        let reviewBefore = fieldReviewVersion == 1 ? MatchPitchState(self):nil
        defer {
            if let before=reviewBefore {
                finishFieldReview(before:before)
            }
        }
        if fieldReviewVersion == 1,["안타","범타"].contains(initial) {
            resolveReviewedPlate(initial:initial,batter:batter,pitcher:pitcher,entrant:newRunner,bunt:bunt,
                battingQuality:battingQuality,pitchingQuality:pitchingQuality,offsetX:offsetX,offsetY:offsetY,timing:timing,direct:direct)
            return
        }
        if initial == "홈런" {
            let before=bases.enumerated().map {index,occupied in occupied ? (runnerProfiles?[index] ?? FieldRunnerProfile(speed:60)):nil}
            let ownIndex = !offense && appearance && (role != "pitcher" || ownPitcherActive) ? DetailedFieldRules.names.firstIndex(of:fieldStats?.position ?? ""):nil
            let speeds=DetailedFieldRules.names.indices.map {index in index == ownIndex ? fieldStats?.speed ?? 60:npcDefenders?[index].speed ?? 60}
            var event=MatchHomeRun(half:half,order:half%2 == 1 ? homeOrder:awayOrder,seed:random,
                power:batter ? power:npcPower,quality:battingQuality ?? 0.65,directionOffset:offsetX,
                before:before,batter:newRunner,defenderSpeeds:speeds,ownDefender:ownIndex,
                scoreBefore: .init(home: homeScore, away: awayScore))
            if fieldReviewVersion == 1 {
                // 확정 홈런은 재판정하지 않고 기존 거리·방향·비행 시각을 와이드 표시에도 사용한다.
                let distance=Double(event.distance),flight=event.flight,direction=event.direction
                var path=MatchBattedBall(version:2,kind:.fly,quality:event.quality,contact:batter ? contact:npcContact,
                    power:event.power,speed:min(48,max(3,distance/flight/0.72)),angle:35,direction:direction,distance:distance,flight:flight)
                path.firstBounceAt=flight;path.firstBounceDistance=distance;event.trajectory=path
            }
            if homeRuns == nil {homeRuns=[]};homeRuns?.append(event)
        }
        if let version=detailedFieldVersion,[1,2,3,4,5].contains(version), ["안타","범타"].contains(initial) {
            let shot:MatchBattedBall?
            let flyBall:Bool,landing:FieldPoint,flight:Double
            if battedBallVersion == 1 {
                let a=roll(),b=roll(),c=roll()
                let quality=battingQuality ?? max(0.05,0.3+a*0.55-(pitchingQuality ?? 0)*0.35)
                let ball=MatchBattedBall.make(quality:quality,contact:batter ? contact:npcContact,power:batter ? power:npcPower,bunt:bunt,
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
        completePlate(initial: initial, result: result, batter: batter, pitcher: pitcher,
            newRunner: newRunner, detailed: detailed, cleanForEarned: cleanForEarned)
    }

    /// 판정이 끝난 타석을 원장에 반영한다. 표시 시각이나 재생 프레임은 입력으로 받지 않는다.
    mutating func completePlate(initial: String, result finalResult: String, batter: Bool, pitcher: Bool,
                               newRunner: FieldRunnerProfile, detailed: MatchDetailedPlay? = nil,
                               cleanForEarned: MatchDetailedPlay? = nil) {
        let deferredReview = beginOfficialPlate(result: finalResult, play: detailed, clean: cleanForEarned)
        let result = deferredReview ? "안타" : finalResult
        let outsBefore = outs
        let eventHalf = half, eventOrder = half.isMultiple(of: 2) ? awayOrder : homeOrder
        let beforeHome = homeScore, beforeAway = awayScore
        let traceBatter = playerRecords.map { ($0.homeTeam(batting: half)).batterID(order: eventOrder, relief: pitching?.change(home: half % 2 == 1) != nil) }
        let traceBefore = playerRecords?.runners ?? [nil, nil, nil]
        let traceResponsibility = runnerProfiles?.map { $0?.responsiblePitcher } ?? [nil, nil, nil]
        defer {
            if let traceBatter, var records = playerRecords {
                records.appendPlateTrace(half: eventHalf, order: eventOrder, batter: traceBatter,
                    result: result, outsBefore: outsBefore, beforeHome: beforeHome, beforeAway: beforeAway,
                    beforeRunners: traceBefore, responsibility: traceResponsibility, match: self, play: detailed)
                playerRecords = records
            }
            closeOfficialReview()
        }
        scoutingPerformance?.record(result, batter:batter, pitcher:pitcher)
        message = deferredReview ? "안타 · 공식 기록 검토 예정" : detailed?.summary ?? result
        var runs = 0
        let beforeProfiles=runnerProfiles
        var scoring:[String]=[]
        if batter {
            line.plateAppearances += 1
            if result != "볼넷" && result != "사구" && detailed?.sacrificeFly != true { line.atBats += 1 }
            if result == "안타" || result == "2루타" || result == "3루타" || result == "홈런" { line.hits += 1 }
            if result == "홈런" { line.homeRuns += 1 }
            if result == "볼넷" { line.walks += 1 }
            if result == "사구" { line.hitByPitch = (line.hitByPitch ?? 0) + 1 }
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
        else if ["볼넷", "사구"].contains(result) {
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
            if result == "안타" || result == "2루타" || result == "3루타" || result == "홈런" { line.hitsAllowed += 1 }
            if result == "삼진" {
                line.pitchingStrikeouts += 1
                if detailed?.pitchEvent?.strikeReach == true { line.strikeoutsWithoutOut = (line.strikeoutsWithoutOut ?? 0) + 1 }
            }
            if result == "사구" { line.hitBatters = (line.hitBatters ?? 0) + 1 }
            if result == "볼넷" { line.pitchingWalks += 1 }
        }
        // A run on a force third-out is already excluded by the shared field timeline.
        let finalRBI = detailed?.rbi ?? runs
        let creditedRBI = deferredReview ? runs : finalRBI
        if batter { line.rbi += creditedRBI }
        let earnedContext=playerRecords?.earned == nil ? nil:MatchEarnedPlay(half:half,order:half % 2 == 1 ? homeOrder:awayOrder,
            initial:initial,outs:outsBefore,batter:newRunner,clean:cleanForEarned,stats:fieldStats,
            defending:!offense && appearance && (role != "pitcher" || ownPitcherActive),npc:npcDefenders)
        if let earnedContext {
            rememberOfficialPlate(context: earnedContext, play: detailed, result: finalResult, runs: runs,
                deferred: deferredReview, batter: batter, pitcher: pitcher, rbi: finalRBI)
        }
        let recordedEarnedContext = deferredReview ? earnedContext.map {
            MatchEarnedPlay(half: $0.half, order: $0.order, initial: $0.initial, outs: $0.outs, batter: $0.batter,
                clean: detailed, stats: $0.stats, defending: $0.defending, npc: $0.npc)
        } : earnedContext
        playerRecords?.recordPlate(home:half % 2 == 1,order:half % 2 == 1 ? homeOrder:awayOrder,
            battingRelief:pitching?.change(home:half % 2 == 1) != nil,
            pitchingRelief:pitching?.change(home:half % 2 == 0) != nil,
            result:result,play:detailed,runs:runs,outsAdded:outs-outsBefore,
            rbi:creditedRBI,responsible:scoring,earnedContext:recordedEarnedContext,cleanFieldingPlay:cleanForEarned,deferError:deferredReview)
        if runs > 0, var records=playerRecords, records.decisions != nil {
            let battingHome=half % 2 == 1
            let battingTeam=battingHome ? records.home:records.away
            let defense=battingHome ? records.away:records.home
            let orderedTags = result == "홈런" && detailed == nil
                ? (beforeProfiles ?? []).reversed().compactMap {$0?.responsiblePitcher} + [newRunner.responsiblePitcher].compactMap {$0}
                : scoring
            let ids=orderedTags.map { $0 == MatchPitching.reliefID(home:!battingHome) ? defense.pitching[1].id:defense.pitching[0].id }
            records.decisions?.observe(home:homeScore+(battingHome ? runs:0),away:awayScore+(battingHome ? 0:runs),
                battingHome:battingHome,pitcher:battingTeam.pitching[battingTeam.pitching[1].counts.pitches > 0 ? 1:0].id,responsible:ids)
            playerRecords=records
        }
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
        if completed, var records=playerRecords, var decisions=records.decisions {
            decisions.finish(records:records);records.decisions=decisions;playerRecords=records
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
        // 세 번째 아웃으로 비운 점유는 책임투수 승계 과정에서 다시 채우지 않는다.
        if (1...3).contains(destination), play.special == nil || (play.outsBefore ?? 0) + play.outsAdded < 3 {
            play.afterRunners[destination-1]=play.runners[batter].profile
        }
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
        let stamina=own ? abilityStats?.stamina ?? 60:npcAttack?.team(home:home).starter.profile?.stamina ?? 60
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
              l.strikeouts <= l.atBats, l.pitchingStrikeouts <= l.pitchingOuts + (l.strikeoutsWithoutOut ?? 0),
              match.completed ? result == reward(for: match) : result == nil else { throw MatchError.invalidRecord }
    }
}

/// Frozen display inputs for an already-decided home run. Does not consume match RNG or award runs.
struct MatchHomeRun:Codable,Equatable {
    enum CelebrationKind: Equatable {
        case standard, grandSlam, goAhead, walkOff

        var title: String? {
            switch self {
            case .standard: nil
            case .grandSlam: "GRAND SLAM"
            case .goAhead: "GO-AHEAD HOME RUN"
            case .walkOff: "WALK-OFF HOME RUN"
            }
        }
    }

    struct ScoreBefore: Codable, Equatable {
        let home: Int
        let away: Int
    }

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
    // Older home-run records contain the runners but do not carry the score at contact.
    var scoreBefore: ScoreBefore? = nil
    var trajectory: MatchBattedBall? = nil
    var review: MatchFieldReview? = nil
    var eventID:String {"hr-v1/\(half)/\(order)"}
    private var variation:Double {Double(MatchNPCFielders.hash("hr-v1/\(seed)/\(half)/\(order)")%1001)/1000}
    var direction:Double {trajectory?.direction ?? max(-25,min(25,(variation-0.5)*40+directionOffset*18))}
    var fence:Double {110-abs(direction)*0.45}
    var distance:Int {trajectory.map {Int(($0.firstBounceDistance ?? $0.distance).rounded())} ?? Int((fence+8+power*0.12+quality*8+variation*8).rounded())}
    var flight:Double {trajectory.map {$0.firstBounceAt ?? $0.flight} ?? (3.8+Double(distance-110)*0.025)}
    var duration:Double {max(flight,runners.map(\.arrival).max() ?? 0)}
    var runs:Int {before.compactMap {$0}.count+1}
    private var battingDeficit: Int? {
        guard let scoreBefore, scoreBefore.home >= 0, scoreBefore.away >= 0 else { return nil }
        return half.isMultiple(of: 2) ? scoreBefore.home - scoreBefore.away : scoreBefore.away - scoreBefore.home
    }
    var isWalkOff: Bool {
        guard half == 17, let deficit = battingDeficit else { return false }
        return deficit >= 0 && runs > deficit
    }
    var isGoAhead: Bool {
        guard let deficit = battingDeficit else { return false }
        return deficit > 0 && runs > deficit
    }
    var celebrationKind: CelebrationKind {
        if isWalkOff { return .walkOff }
        if isGoAhead { return .goAhead }
        return runs == 4 ? .grandSlam : .standard
    }
    var resultTitle: String {
        switch runs {
        case 1: "SOLO HOME RUN"
        case 4: "GRAND SLAM"
        default: "\(runs)-RUN HOME RUN"
        }
    }
    var resultDistance: String { "DISTANCE \(distance) m" }
    var fenceCrossedAt:Double {
        var low=0.0,high=flight
        for _ in 0..<48 {
            let t=(low+high)/2,p=ball(at:t)
            if hypot(p.x,p.y)<fence {low=t} else {high=t}
        }
        return (low+high)/2
    }
    var runners:[DetailedRunner] {
        let froms=[0]+(1...3).filter {before[$0-1] != nil}
        let earliest=froms.map {from -> Double in
            let profile=from == 0 ? batter:before[from-1]!
            return 0.45+Double(4-from)*27.43/(6.3+profile.speed*0.012)
        }.min() ?? 0
        let start=0.45+(review == nil ? 0:max(0,fenceCrossedAt+0.05-earliest))
        return froms.map {from in
            let profile=from == 0 ? batter:before[from-1]!
            let leg=27.43/(6.3+profile.speed*0.012)
            var nodes=[FieldNode(at:0,point:DetailedFieldRules.bases[from]),FieldNode(at:start,point:DetailedFieldRules.bases[from])]
            for base in (from+1)...4 {nodes.append(FieldNode(at:start+Double(base-from)*leg,point:DetailedFieldRules.bases[base]))}
            return DetailedRunner(from:from,destination:4,profile:profile,nodes:nodes)
        }
    }
    func ball(at time:Double) -> FieldPoint {
        if let trajectory {return trajectory.point(at:time)}
        let p=max(0,min(1,time/flight)),distance=Double(distance)*p*(1.15-0.15*p),radians=direction * .pi/180
        return FieldPoint(x:sin(radians)*distance,y:cos(radians)*distance)
    }
    func height(at time:Double) -> Double {trajectory?.height(at:time) ?? sin(.pi*max(0,min(1,time/flight)))*(24+power*0.05)}
    func defender(_ index:Int,at time:Double) -> FieldPoint {
        let start=DetailedFieldRules.positions[index]
        guard index>=6 else {return start}
        let destination=FieldPoint(x:ball(at:flight).x*0.72,y:88)
        let distance=start.distance(to:destination),travel=max(0,min(flight,time)-0.35)*(4+defenderSpeeds[index]*0.03)
        return start.towards(destination,fraction:travel/max(0.001,distance))
    }
    func validate() throws {
        if let trajectory {
            guard trajectory.version == 2,FieldReviewRules.isHomeRun(trajectory),review != nil else {throw MatchError.invalidRecord}
        }
        if let review {
            guard review.version == 1,let beforeState=review.before,let after=review.after,beforeState.valid,after.valid,
                  beforeState.half == half,beforeState.order == order,beforeState.runners == before,
                  after.half == half,after.outs == beforeState.outs,after.runners.allSatisfy({$0 == nil}),
                  after.home == beforeState.home+(half.isMultiple(of:2) ? 0:runs),
                  after.away == beforeState.away+(half.isMultiple(of:2) ? runs:0),
                  after.homeOrder == beforeState.homeOrder+(half.isMultiple(of:2) ? 0:1),
                  after.awayOrder == beforeState.awayOrder+(half.isMultiple(of:2) ? 1:0),after.balls == 0,after.strikes == 0,
                  after.completed == (half == 17 && after.home > after.away) else {throw MatchError.invalidRecord}
        }
        guard version == 1,(0...17).contains(half),(0...100_000).contains(order),
              [power,quality,directionOffset].allSatisfy(\.isFinite),(0...100).contains(power),(0...1).contains(quality),(-1...1).contains(directionOffset),
              before.count == 3,ownDefender.map({(0..<9).contains($0)}) ?? true,defenderSpeeds.count == 9,defenderSpeeds.allSatisfy({$0.isFinite && (0...100).contains($0)}),
              scoreBefore.map({$0.home >= 0 && $0.away >= 0}) ?? true,
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
    var primaryMeasure:String {criteria.components(separatedBy:" · ").last?.components(separatedBy:" / ").first ?? criteria}
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
        if let battingOrder { return home ? battingOrder.home : battingOrder.away }
        var lineup=MatchNPCAttackTeam.lineup
        if home == isHome,appearance,role == "batter",let own=DetailedFieldRules.names.firstIndex(of:fieldStats?.position ?? "") {lineup=[own]+lineup.filter {$0 != own}}
        return lineup
    }
    var npcBatter:MatchNPCBatter? {
        let home=half%2 == 1
        guard let team=npcAttack?.team(home:home) else {return nil}
        let slot = (home ? homeOrder : awayOrder) % 9
        let original = team.batters[npcLineup(home: home)[slot]]
        if runnerManagement?.change(home: home)?.slot == slot + 1, let reserve = runnerManagement?.reserve(home: home) {
            return MatchNPCBatter(id: reserve.id, position: original.position, contact: reserve.contact, power: reserve.power,
                                  discipline: reserve.discipline, name: NPCIdentity.name(reserve.id), profile: original.profile)
        }
        return original
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
    var hitByPitch: Int? = nil
    var stolenBases: Int? = nil
    var caughtStealing: Int? = nil
    var hits:Int {singles+doubles+triples+homeRuns}
    var totalBases:Int {singles+2*doubles+3*triples+4*homeRuns}
    var average:Double? {atBats == 0 ? nil:Double(hits)/Double(atBats)}
    // 새 사구 기록만 분모에 포함하며, 과거 nil은 기존 계산을 유지한다.
    var onBasePercentage:Double? {let d=atBats+walks+sacrificeFlies+(hitByPitch ?? 0);return d == 0 ? nil:Double(hits+walks+(hitByPitch ?? 0))/Double(d)}
    var sluggingPercentage:Double? {atBats == 0 ? nil:Double(totalBases)/Double(atBats)}
    var ops:Double? {guard let obp=onBasePercentage,let slg=sluggingPercentage else {return nil};return obp+slg}
    static var keys:[WritableKeyPath<Self,Int>] {[\.plateAppearances,\.atBats,\.singles,\.doubles,\.triples,\.homeRuns,\.walks,\.strikeouts,\.runs,\.rbi,\.sacrificeFlies,\.reachedOnError,\.fieldersChoices]}
    mutating func add(_ other:Self) {
        for key in Self.keys { self[keyPath:key] += other[keyPath:key] }
        if hitByPitch != nil || other.hitByPitch != nil { hitByPitch = (hitByPitch ?? 0) + (other.hitByPitch ?? 0) }
        if stolenBases != nil || other.stolenBases != nil { stolenBases = (stolenBases ?? 0) + (other.stolenBases ?? 0) }
        if caughtStealing != nil || other.caughtStealing != nil { caughtStealing = (caughtStealing ?? 0) + (other.caughtStealing ?? 0) }
    }
    func validate() throws {
        guard Self.keys.allSatisfy({(0...100_000).contains(self[keyPath:$0])}),
              [stolenBases,caughtStealing].allSatisfy({(0...100_000).contains($0 ?? 0)}),
              (0...100_000).contains(hitByPitch ?? 0), plateAppearances == atBats+walks+sacrificeFlies+(hitByPitch ?? 0),
              hits+strikeouts+reachedOnError+fieldersChoices <= atBats else {throw MatchError.invalidRecord}
    }
}
struct MatchPitchingCounts:Codable,Equatable {
    var pitches=0,battersFaced=0,outs=0,hits=0,homeRuns=0,walks=0,strikeouts=0,runsAllowed=0
    var earnedRuns:Int? = nil
    var hitBatters: Int? = nil
    var wildPitches: Int? = nil
    var uncaughtStrikeouts: Int? = nil
    var uncaughtReach: Int? = nil
    var era:Double? {guard outs > 0,let earnedRuns else {return nil};return Double(earnedRuns)*27/Double(outs)}
    var innings:String {"\(outs/3).\(outs%3)"}
    static var keys:[WritableKeyPath<Self,Int>] {[\.pitches,\.battersFaced,\.outs,\.hits,\.homeRuns,\.walks,\.strikeouts,\.runsAllowed]}
    mutating func add(_ other:Self) {
        if other.pitches > 0 || other.battersFaced > 0 || other.runsAllowed > 0 {
            earnedRuns=earnedRuns.flatMap {sum in other.earnedRuns.map {sum+$0}}
        }
        for key in Self.keys {self[keyPath:key] += other[keyPath:key]}
        if hitBatters != nil || other.hitBatters != nil { hitBatters = (hitBatters ?? 0) + (other.hitBatters ?? 0) }
        if wildPitches != nil || other.wildPitches != nil { wildPitches = (wildPitches ?? 0) + (other.wildPitches ?? 0) }
        if uncaughtStrikeouts != nil || other.uncaughtStrikeouts != nil { uncaughtStrikeouts = (uncaughtStrikeouts ?? 0) + (other.uncaughtStrikeouts ?? 0) }
        if uncaughtReach != nil || other.uncaughtReach != nil { uncaughtReach = (uncaughtReach ?? 0) + (other.uncaughtReach ?? 0) }
    }
    func validate() throws {
        guard [hitBatters, wildPitches, uncaughtStrikeouts, uncaughtReach].allSatisfy({ (0...100_000).contains($0 ?? 0) }),
              (uncaughtReach ?? 0) <= (uncaughtStrikeouts ?? 0), (uncaughtStrikeouts ?? 0) <= strikeouts,
              earnedRuns.map({(0...runsAllowed).contains($0)}) ?? true,
              Self.keys.allSatisfy({(0...100_000).contains(self[keyPath:$0])}),homeRuns <= hits,
              hits+walks+strikeouts+(hitBatters ?? 0) <= battersFaced,strikeouts <= outs+(uncaughtReach ?? 0) else {throw MatchError.invalidRecord}
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

struct MatchFieldingRecord: Codable, Equatable {
    let id: String
    let position: String
    var putouts = 0
    var assists = 0
    var errors = 0
    var passedBalls: Int? = nil
}

struct MatchFieldingCredits {
    var putouts: [Int] = []
    var assists: Set<Int> = []
    var error: Int?

    static func make(result: String, play: MatchDetailedPlay?, clean: MatchDetailedPlay?, outsAdded: Int, deferError: Bool = false) -> Self? {
        if let play, let appeal = play.appeal {
            return Self(putouts: [play.fielder] + appeal.selected.map { appeal.attempts[$0].receiver },
                        assists: appeal.selected.isEmpty ? [] : Set([play.fielder]))
        }
        if let special = play?.special {
            return Self(putouts: special.retirements.map(\.fielder),
                assists: Set(special.retirements.flatMap(\.assists)), error: special.kind == .obstruction ? special.fielder : nil)
        }
        if let play,play.review?.ruling?.kind == .overthrow {return Self(error:play.fielder)}
        if let pitch = play?.pitchEvent {
            return pitch.kind == .uncaughtThird && outsAdded == 1 ? Self(putouts: [2], assists: [1]) : Self()
        }
        guard let play else {
            if result == "삼진", outsAdded == 1 { return Self(putouts: [1]) }
            if ["볼넷", "사구", "홈런"].contains(result), outsAdded == 0 { return Self() }
            return nil
        }
        // A resolved error replaces the throw path. Only outs retained before the error
        // get credit, with the original throw or catch identifying the fielders involved.
        let ordinary: MatchDetailedPlay
        if play.misplay != nil {
            guard let clean else { return nil }
            ordinary = clean
        } else {
            ordinary = play
        }
        var credit = Self(error: deferError ? nil : play.misplay?.fielder)
        var retired = Set(play.runners.filter(\.out).map(\.from))
        if ordinary.fly?.caught == true, retired.remove(0) != nil {
            credit.putouts.append(ordinary.fielder)
        }
        if ordinary.out, let target = ordinary.targetRunner, retired.remove(target) != nil {
            credit.putouts.append(ordinary.receiver)
            credit.assists.insert(ordinary.fielder)
            if let relay = ordinary.relay { credit.assists.insert(relay.fielder) }
        }
        if let second = ordinary.secondThrow, second.out, retired.remove(0) != nil {
            credit.putouts.append(second.receiver)
            credit.assists.insert(ordinary.receiver)
        }
        if let misplay = play.misplay, !deferError {
            // A completed throw can earn an assist when a later error prevents an out.
            if ordinary.out, (2...4).contains(misplay.stage) { credit.assists.insert(ordinary.fielder) }
            if ordinary.out, misplay.stage == 4, let relay = ordinary.relay { credit.assists.insert(relay.fielder) }
            if ordinary.secondThrow?.out == true, misplay.stage == 6 { credit.assists.insert(ordinary.receiver) }
        }
        guard retired.isEmpty, credit.putouts.count == outsAdded else { return nil }
        return credit
    }
}

struct MatchTeamRecords:Codable,Equatable {
    let teamID:String
    let lineup:[String]
    var batting:[MatchBattingRecord]
    var pitching:[MatchPitchingRecord]
    var fielding: [MatchFieldingRecord]? = nil
    var runnerChanges: [MatchRunnerChange]? = nil
    var battingTotal:MatchBattingCounts {batting.reduce(into:MatchBattingCounts()) {$0.add($1.counts)}}
    // Individual ER charges can differ from reconstructed team ER after a relief change.
    var pitchingTotal:MatchPitchingCounts {pitching.reduce(into:MatchPitchingCounts(earnedRuns:0)) {$0.add($1.counts)}}
    func batterID(order:Int,relief:Bool) -> String {
        let id=runnerChanges?.last(where: { $0.slot == order % 9 + 1 })?.replacement ?? lineup[order % 9]
        return relief && id == pitching[0].id ? pitching[1].id:id
    }
    mutating func battingIndex(order:Int,relief:Bool) -> Int {
        let id=batterID(order:order,relief:relief)
        if let index=batting.firstIndex(where:{$0.id == id}) {return index}
        batting.append(MatchBattingRecord(id:id,order:order % 9+1,position:"P"))
        return batting.count-1
    }

    var fieldingLineup: [MatchFieldingRecord] {
        batting.prefix(9).filter { $0.position != "P" }.map { MatchFieldingRecord(id: $0.id, position: $0.position) }
            + pitching.map { MatchFieldingRecord(id: $0.id, position: "P") }
    }

    fileprivate mutating func recordFielding(_ credit: MatchFieldingCredits?, pitchingIndex: Int) {
        guard var rows = fielding else { return }
        guard let credit else {
            fielding = nil
            return
        }
        let activePitcher = pitching[pitchingIndex].id
        func rowIndex(_ index: Int) -> Int? {
            guard DetailedFieldRules.names.indices.contains(index) else { return nil }
            let position = DetailedFieldRules.names[index]
            let replacement = runnerChanges?.last(where: { $0.position == position })?.replacement
            return rows.firstIndex { row in row.position == position && (position == "P" ? row.id == activePitcher : replacement == nil || row.id == replacement) }
        }
        let putouts = credit.putouts.compactMap(rowIndex)
        let assists = credit.assists.compactMap(rowIndex)
        let error = credit.error.flatMap(rowIndex)
        guard putouts.count == credit.putouts.count, assists.count == credit.assists.count,
              credit.error == nil || error != nil else {
            fielding = nil
            return
        }
        for index in putouts { rows[index].putouts += 1 }
        for index in assists { rows[index].assists += 1 }
        if let error { rows[error].errors += 1 }
        fielding = rows
    }

    func validateFielding(against source: MatchTeamRecords, running: [MatchRunningEvent] = []) throws {
        guard let fielding else { return }
        let expected = source.fieldingLineup + (runnerChanges ?? []).map { MatchFieldingRecord(id: $0.replacement, position: $0.position) }
        let defense = pitchingTotal
        guard fielding.count == expected.count,
              zip(fielding, expected).allSatisfy({ $0.id == $1.id && $0.position == $1.position }),
              fielding.allSatisfy({ (0...defense.outs).contains($0.putouts) &&
                  (0...(defense.battersFaced + running.count)).contains($0.assists) && (0...defense.battersFaced).contains($0.errors) }),
              fielding.reduce(0, { $0 + $1.putouts }) == defense.outs,
              fielding.allSatisfy({ (0...defense.pitches).contains($0.passedBalls ?? 0) }),
              fielding.filter({ $0.position == "C" }).reduce(0, { $0 + $1.putouts }) >= defense.strikeouts - (defense.uncaughtStrikeouts ?? 0) else {
            throw MatchError.invalidRecord
        }
        let errors = fielding.reduce(0) { $0 + $1.errors }
        guard errors <= defense.battersFaced,
              fielding.reduce(0, { $0 + $1.assists }) <= (defense.outs + errors) * 2 else { throw MatchError.invalidRecord }
        for pitcher in pitching where pitcher.counts.pitches == 0 && !running.contains(where: { event in
            event.play.runningEvent?.kind == .pickoff && event.play.out
        }) {
            guard let row = fielding.first(where: { $0.id == pitcher.id && $0.position == "P" }),
                  row.putouts == 0, row.assists == 0, row.errors == 0 else { throw MatchError.invalidRecord }
        }
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
    var decisions:MatchPitcherDecision? = nil
    var plateTrace: [MatchPlateTrace]? = nil
    static func make(match:CareerMatch,careerID:UUID,fixtureID:String,trackEarnedRuns:Bool=false,trackDecisions:Bool=false,
                     trackFielding: Bool = false, trackPlateTrace: Bool = false) -> Self? {
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
        if trackFielding, match.detailedFieldVersion == 5, match.fieldPlays?.isEmpty == true,
           match.homeOrder == 0, match.awayOrder == 0 {
            let positions = Set(DetailedFieldRules.names)
            let fielders = positions.subtracting(["P"])
            let ownPositionKnown = !match.appearance || match.role != "batter"
                || match.fieldStats.map { fielders.contains($0.position) } == true
            if ownPositionKnown, [result.home, result.away].allSatisfy({ Set($0.batting.map(\.position)) == positions }) {
                result.home.fielding = result.home.fieldingLineup
                result.away.fielding = result.away.fieldingLineup
            }
        }
        if trackPlateTrace { result.plateTrace = [] }
        if trackDecisions { result.decisions=MatchPitcherDecision() }
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
                              result:String,play:MatchDetailedPlay?,runs:Int,outsAdded:Int,rbi:Int,responsible:[String],
                              earnedContext:MatchEarnedPlay?=nil,cleanFieldingPlay: MatchDetailedPlay? = nil, deferError: Bool = false) {
        var batters=battingHome ? home:away,pitchers=battingHome ? away:home
        let bi=batters.battingIndex(order:order,relief:battingRelief),pi=pitchingRelief ? 1:0
        let batterID=batters.batting[bi].id,before=runners
        var b=batters.batting[bi].counts,p=pitchers.pitching[pi].counts
        b.plateAppearances += 1;p.battersFaced += 1;p.outs += outsAdded;b.rbi += rbi
        if result == "볼넷" {b.walks += 1;p.walks += 1}
        else if result == "사구" { b.hitByPitch = (b.hitByPitch ?? 0) + 1; p.hitBatters = (p.hitBatters ?? 0) + 1 }
        else if play?.sacrificeFly == true {b.sacrificeFlies += 1}
        else {
            b.atBats += 1
            switch result {
            case "안타":b.singles += 1;p.hits += 1
            case "2루타":b.doubles += 1;p.hits += 1
            case "3루타":b.triples += 1;p.hits += 1
            case "홈런":b.homeRuns += 1;p.hits += 1;p.homeRuns += 1
            case "삼진":
                b.strikeouts += 1;p.strikeouts += 1
                if play?.pitchEvent?.kind == .uncaughtThird {
                    p.uncaughtStrikeouts = (p.uncaughtStrikeouts ?? 0) + 1
                    if play?.out == false { p.uncaughtReach = (p.uncaughtReach ?? 0) + 1 }
                }
            case "실책 출루":b.reachedOnError += 1
            case "야수 선택":b.fieldersChoices += 1
            default:break
            }
        }
        batters.batting[bi].counts=b;pitchers.pitching[pi].counts=p
        if pitchers.fielding != nil {
            let credit = MatchFieldingCredits.make(result: result, play: play, clean: cleanFieldingPlay, outsAdded: outsAdded, deferError: deferError)
            pitchers.recordFielding(credit, pitchingIndex: pi)
        }
        func runnerID(_ from:Int) -> String? {from == 0 ? batterID:(1...3).contains(from) ? before[from-1]:nil}
        let scoring:[String]
        if let play {
            scoring=play.runners.filter {!$0.out && $0.destination == 4}.sorted {$0.arrival < $1.arrival}.prefix(runs).compactMap {runnerID($0.from)}
            runners=[nil,nil,nil]
            for runner in play.runners where !runner.out && (1...3).contains(runner.destination) {runners[runner.destination-1]=runnerID(runner.from)}
        } else if result == "홈런" {scoring=before.compactMap {$0}+[batterID];runners=[nil,nil,nil]}
        else if result == "안타" {scoring=[before[2]].compactMap {$0};runners=[batterID,before[0],before[1]]}
        else if ["볼넷", "사구"].contains(result) {
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
                  (9...(10 + (team.runnerChanges?.count ?? 0))).contains(team.batting.count),Set(team.batting.map(\.id)).count == team.batting.count,
                  Array(team.batting.prefix(9)).map(\.id) == team.lineup else {throw MatchError.invalidRecord}
            for row in team.batting {
                let original=source.batting.first(where:{$0.id == row.id})
                guard (1...9).contains(row.order),
                      original.map({$0.order == row.order && $0.position == row.position}) ??
                        ((row.id == source.pitching[1].id && row.position == "P" && source.batting[row.order-1].position == "P") ||
                         team.runnerChanges?.contains(where: { $0.replacement == row.id && $0.slot == row.order && $0.position == row.position }) == true) else {throw MatchError.invalidRecord}
                try row.counts.validate()
            }
            for row in team.pitching {try row.counts.validate()}
            try team.validateFielding(against: source, running: (match.running?.events ?? []).filter { $0.play.half.isMultiple(of: 2) == isHome })
            let b=team.battingTotal,p=other.pitchingTotal
            let defense=team.pitchingTotal
            let expectedOuts=(isHome ? (match.half+1)/2:match.half/2)*3+((match.half % 2 == 0) == isHome ? match.outs:0)
            guard b.plateAppearances == (isHome ? match.homeOrder:match.awayOrder),
                  b.plateAppearances == p.battersFaced,b.hits == p.hits,b.homeRuns == p.homeRuns,
                  b.walks == p.walks,b.strikeouts == p.strikeouts,(b.hitByPitch ?? 0) == (p.hitBatters ?? 0),
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
        try match.validateRunnerManagement()
        try validatePlateTrace(match: match)
        if let earned {try earned.validate(match:match)}
        if let decisions {try decisions.validate(records:self,match:match)}
        guard (home.pitching+away.pitching).allSatisfy({(earned != nil) == ($0.counts.earnedRuns != nil)}) else {throw MatchError.invalidRecord}
        let offense=match.half % 2 == 1 ? home:away
        guard runners.compactMap({$0}).allSatisfy({id in offense.batting.contains {$0.id == id}}) else {throw MatchError.invalidRecord}
    }
}

struct MatchEarnedPlay: Codable, Equatable {
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
        if context.initial == "낫아웃 PB" {
            outs += 1
        } else if context.initial == "낫아웃 WP", let play = context.clean {
            var after: [EarnedRunner?] = [nil, nil, nil]
            for move in play.runners where !move.out {
                let value = move.from == 0 ? batter : runners[move.from - 1]
                if move.destination == 4 { if outs + play.outsAdded < 3, let value { scored.append(value.token) } }
                else { after[move.destination - 1] = value }
            }
            runners = after; outs += play.outsAdded
        } else if ["안타","범타"].contains(context.initial),let original=context.clean {
            var play = outs == context.outs && runners == actualBefore ? original
                : reconstructedPlay(original,context:context,batter:batter)
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
        } else if ["볼넷", "사구"].contains(context.initial) {
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
    /// 가상 점유가 달라진 경우에만 별도 프레임에서 수비를 재구성한다.
    private func reconstructedPlay(_ original: MatchDetailedPlay, context: MatchEarnedPlay, batter: EarnedRunner) -> MatchDetailedPlay {
        var play: MatchDetailedPlay
        if let appeal = original.appeal {
            var frame = CareerMatch(random:0,isHome:false,role:"league",appearance:false,contact:60,power:60,discipline:60,mastery:[:])
            frame.half = context.half; frame.outs = outs; frame.runnerProfiles = runners.map { $0?.profile }
            frame.homeOrder = appeal.context.before.homeOrder; frame.awayOrder = appeal.context.before.awayOrder
            let input = MatchSpecialContext(before: MatchPitchState(frame), ball: appeal.context.ball, batter: batter.profile,
                stats: context.stats, npc: context.npc, defending: context.defending, ownBatter: batter.profile.own,
                discipline: appeal.context.discipline)
            play = MatchAppealRules.resolve(input) ?? DetailedFieldRules.resolveFly(half:context.half,order:context.order,
                landing:original.landing,flight:original.flight,runners:frame.runnerProfiles!,batter:batter.profile,outs:outs,
                stats:context.stats,defending:context.defending,ownBatter:batter.profile.own,relayEnabled:true,npc:context.npc)
        }
        else if let special = original.special {
            play = MatchSpecialRules.reconstruct(special.context, runners: runners.map { $0?.profile }, outs: outs) ?? original
        }
        else {
            let profiles=runners.map {$0?.profile}
            let airborne=original.review != nil ? original.fly?.caught == true:original.battedBall?.kind.airborne ?? (original.fly != nil)
            if let boundary=original.review?.ruling,boundary.kind == .groundRuleDouble,let ball=original.battedBall {
                var projected=CareerMatch(random:0,isHome:false,role:"league",appearance:false,contact:60,power:60,discipline:60,mastery:[:])
                projected.half=context.half;projected.outs=outs;projected.runnerProfiles=profiles
                projected.homeOrder=context.half.isMultiple(of:2) ? 0:context.order
                projected.awayOrder=context.half.isMultiple(of:2) ? context.order:0
                play=FieldReviewRules.award(match:projected,ball:ball,ruling:boundary,batter:batter.profile)
            } else {
            play=airborne ? DetailedFieldRules.resolveFly(half:context.half,order:context.order,landing:original.landing,flight:original.flight,
                runners:profiles,batter:batter.profile,outs:outs,stats:context.stats,defending:context.defending,ownBatter:batter.profile.own,relayEnabled:true,npc:context.npc)
                : DetailedFieldRules.resolve(half:context.half,order:context.order,landing:original.landing,flight:original.flight,
                runners:profiles,batter:batter.profile,outs:outs,stats:context.stats,defending:context.defending,ownBatter:batter.profile.own,
                doublePlayEnabled:true,groundBall:original.battedBall?.kind == .ground,relayEnabled:true,npc:context.npc,continuationEnabled:original.review != nil)
            }
        }
        return play
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
        var entrant=batter;entrant.unearned=result == "실책 출루" || context.initial == "낫아웃 PB"
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
        else if ["볼넷", "사구"].contains(result) {
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
