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
    var detailedFieldVersion: Int?
    var fieldPlays: [MatchDetailedPlay]?
    var runnerProfiles: [FieldRunnerProfile?]?
    var trainingEffectsVersion: Int?
    var controlVersion: Int?
    var lastManual: ManualMatchResult?
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
        let actualSpeed = role == "pitcher" && abilityStats?.version == 1 ? abilityStats?.speedValue(code: pitchCode ?? "four-seam") : nil
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
            guard appearance, (role == "batter" ? [.watch, .swing, .bunt].contains(input) : input == .pitch) else { throw MatchError.invalidInput }
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
    }

    mutating func settle() {
        while !completed && (!appearance || (role == "batter" ? !ownAtBat : offense)) {
            step(.swing, pitchCode: nil)
        }
    }

    private mutating func step(_ input: MatchInput, pitchCode: String?, control: ManualMatchInput? = nil) {
        let personal = appearance && (role == "batter" ? ownAtBat : !offense)
        if personal && controlVersion == 2 {
            manualStep(input, pitchCode: pitchCode, control: control ?? automaticControl(input, pitchCode: pitchCode))
            return
        }
        let personalBatter = appearance && role == "batter" && ownAtBat
        let personalPitcher = appearance && role == "pitcher" && !offense
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
            traits:batter ? (fieldStats?.activeTraits ?? []).filter { $0 == .cheetah } : [],own:batter)
        if detailedFieldVersion == 1, ["안타","범타"].contains(initial) {
            let depth = bunt ? 3 + roll()*13 : initial == "안타" ? 40 + roll() * 45 : 5 + roll() * 36
            let landing = FieldPoint(x:(roll()-0.5)*depth*1.5,y:depth)
            let flight = DetailedFieldRules.bases[0].distance(to:landing)/(initial == "안타" ? 28 : 20)
            let play = DetailedFieldRules.resolve(half:half,order:half % 2 == 1 ? homeOrder : awayOrder,landing:landing,flight:flight,
                runners:runnerProfiles ?? bases.map { $0 ? FieldRunnerProfile(speed:60) : nil },batter:newRunner,outs:outs,
                stats:fieldStats,defending:!offense && appearance,ownBatter:batter)
            detailed=play;fieldPlays?.append(play)
            if play.ownDefense || batter {
                lastFieldPlay=play.xpPlay
                if play.ownDefense,role == "batter",positionExperience != nil {
                    positionExperience?.events.append(MatchPositionEvent(half:half,order:isHome ? awayOrder : homeOrder,play:play.xpPlay))
                }
            }
            result=play.hitBases == 2 ? "2루타" : play.hitBases == 1 ? "안타" : play.out ? "범타" : "야수 선택"
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
        if batter {
            line.plateAppearances += 1
            if result != "볼넷" { line.atBats += 1 }
            if result == "안타" || result == "2루타" || result == "홈런" { line.hits += 1 }
            if result == "홈런" { line.homeRuns += 1 }
            if result == "볼넷" { line.walks += 1 }
            if result == "삼진" { line.strikeouts += 1 }
        }
        if let detailed {
            runs=detailed.runs;outs += detailed.outsAdded
            if pitcher { line.pitchingOuts += detailed.outsAdded }
            runnerProfiles=detailed.afterRunners;bases=detailed.afterRunners.map { $0 != nil }
        }
        else if result == "홈런" { runs = bases.filter { $0 }.count + 1; bases = [false, false, false];runnerProfiles=runnerProfiles.map { _ in [nil,nil,nil] } }
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
        if pitcher {
            line.runsAllowed += runs
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
