import Foundation

enum TrainingKind: String, Codable, CaseIterable {
    case contact, power, discipline, pitch, speed, defense, arm, velocity, control, stuff, stamina, mental
    var initialDirection: Double { self == .stuff ? 0 : 35 }
    var isRaw: Bool { [.velocity, .control, .stuff, .stamina, .mental].contains(self) }
    func allows(_ role: String) -> Bool {
        guard ["batter", "pitcher"].contains(role) else { return false }
        return self == .mental || isField || (role == "pitcher" ? [.pitch, .velocity, .control, .stuff, .stamina].contains(self) : [.contact, .power, .discipline].contains(self))
    }
    var isField: Bool { [.speed, .defense, .arm].contains(self) }
    var label: String {
        switch self { case .contact: "컨택"; case .power: "파워"; case .discipline: "선구안"; case .pitch: "구종"; case .speed: "스피드"; case .defense: "수비"; case .arm: "송구"; case .velocity: "구속"; case .control: "제구"; case .stuff: "구위"; case .stamina: "지구력"; case .mental: "멘탈" }
    }
}

enum SprintFoot: String, Codable { case left, right }

struct TrainingInput: Codable, Equatable {
    var x = 0.5
    var y = 0.5
    var timing: Double?
    var release: Double?
    var force: Double?
    var angle: Double?
    var calledStrike: Bool?
    var footfalls: [SprintFoot]?
    var base: Int?
    var choice: Int?
    var drill: SkillDrillInput?
}

struct TrainingTarget: Codable, Equatable {
    let x: Double
    let y: Double
}

struct ContactTrainingResult: Codable, Equatable {
    let target: TrainingTarget
    let aim: TrainingTarget
    let didSwing: Bool
    let positionScore: Int
    let timingScore: Int
    var total: Int { Int((Double(positionScore) * 0.65 + Double(timingScore) * 0.35).rounded()) }
}

struct PitchStoredSkill: Codable, Equatable, Identifiable {
    let code: String
    let name: String
    let mastery: Double
    let order: Int
    var id: String { code }
}

struct PitchStudy: Codable, Equatable {
    let code: String
    let replacing: String?
    let rosterSnapshot: [PitchStoredSkill]
    let restoredMastery: Double?
    var retired: PitchStoredSkill? { rosterSnapshot.first { $0.code == replacing } }
    func validate(training: CareerTraining) throws {
        guard PitchType(rawValue: code) != nil, training.role == "pitcher", training.selectedKind == .pitch,
              training.pitchCode == code, training.kind == nil, training.trait == nil, training.position == nil,
              !rosterSnapshot.contains(where: { $0.code == code }),
              Set(rosterSnapshot.map(\.code)).count == rosterSnapshot.count,
              rosterSnapshot.allSatisfy({ !$0.code.isEmpty && !$0.name.isEmpty && $0.mastery.isFinite && (0...100).contains($0.mastery) && $0.order >= 0 }),
              replacing == nil ? rosterSnapshot.count < 5 : retired != nil,
              restoredMastery.map({ $0.isFinite && (0...100).contains($0) && training.before == 100 }) ?? (training.before < 100) else {
            throw TrainingError.invalidRecord
        }
    }
}

struct CareerTraining: Codable, Equatable {
    let playerID: UUID
    let date: String
    let role: String
    let pitchCode: String?
    let kind: TrainingKind?
    var trait: PlayerTrait?
    var traitRevision: Int?
    var position: FieldPosition?
    var positionRevision: Int?
    var positionXP: Double?
    var pitchStudy: PitchStudy?
    var drillVersion: Int?
    var growthPolicy:TrainingGrowthPolicy?
    var projectFeedback: TrainingProjectFeedback?
    var isSkillDrill: Bool { drillVersion == 1 && SkillDrillRules.kinds.contains(selectedKind) && trait == nil && position == nil && pitchStudy == nil }
    var selectedKind: TrainingKind { kind ?? (pitchCode == nil ? .contact : .pitch) }
    let before: Double
    let fatigue: Int
    let age: Int
    let targets: [TrainingTarget]
    var scores: [Int] = []
    var lastContact: ContactTrainingResult?
    var calendarRevision: Int
    var completed: Bool { scores.count == 5 }
    var average: Double { scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count) }
    var positionGainXP: Double { completed && position != nil ? PositionTrainingRules.gainedXP(mastery: before, score: average.rounded(), fatigue: fatigue, age: age) : 0 }
    var positionAfter: PositionSkill { PositionTrainingRules.adding(positionGainXP, to: PositionSkill(mastery: before, xp: positionXP ?? 0)) }
    var after: Double { position != nil ? positionAfter.mastery : completed ? (trait == nil && pitchStudy == nil ? (growthPolicy?.after(training:self) ?? TrainingRules.growth(before: before, score: average, fatigue: fatigue, age: age, pitch: pitchCode != nil)) : TrainingRules.traitGrowth(before: before, score: average.rounded(), fatigue: fatigue, age: age)) : before }
    var controlMastery: Double { pitchStudy.map { $0.restoredMastery ?? min(40, 20 + before * 0.2) } ?? before }
    var gain: Double { TrainingRules.round(after - before) }
    var title: String { pitchStudy.map { (PitchType(rawValue: $0.code)?.label ?? $0.code) + ($0.restoredMastery == nil ? " 습득 훈련" : " 재등록 훈련") } ?? (position?.label ?? trait?.label ?? selectedKind.label) + " 훈련" }
    func throwBase(_ round: Int) -> Int { trait == nil ? TrainingRules.throwBase(round) : [1, 2, 3, 2, 1][round] }

    init(playerID: UUID, date: String, role: String, pitchCode: String?, before: Double, fatigue: Int, age: Int, calendarRevision: Int, kind: TrainingKind? = nil, position: FieldPosition? = nil) {
        self.playerID = playerID; self.date = date; self.role = role; self.pitchCode = pitchCode
        self.kind = kind
        self.position = position
        self.before = before; self.fatigue = fatigue; self.age = age; self.calendarRevision = calendarRevision
        var seed = (playerID.uuidString + date + (kind?.rawValue ?? pitchCode ?? "contact") + (position?.rawValue ?? "")).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        func roll() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / 9007199254740992 }
        var inZone = [true, true, true, false, false]
        if kind == .discipline {
            for index in stride(from: 4, through: 1, by: -1) { inZone.swapAt(index, Int(roll() * Double(index + 1))) }
        }
        targets = (0..<5).map { index in
            if let position {
                let origin = PositionTrainingRules.origin(position)
                return TrainingTarget(x: origin.x + (roll() - 0.5) * 0.18, y: origin.y + (roll() - 0.5) * 0.1)
            }
            if kind == .discipline && !inZone[index] {
                return TrainingTarget(x: roll() < 0.5 ? 0.08 : 0.92, y: 0.1 + roll() * 0.8)
            }
            return TrainingTarget(x: 0.25 + roll() * 0.5, y: 0.25 + roll() * 0.5)
        }
    }
    mutating func attempt(_ input: TrainingInput) throws {
        guard !completed else { throw TrainingError.finished }
        let numbers = [input.x, input.y] + [input.timing, input.release].compactMap { $0 }
        guard numbers.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw TrainingError.invalidInput }
        if drillVersion != nil {
            guard isSkillDrill, selectedKind.allows(role), pitchCode == nil, input.timing == nil, input.release == nil,
                  input.force == nil, input.angle == nil, input.calledStrike == nil, input.footfalls == nil,
                  input.base == nil, input.choice == nil, let drill = input.drill else { throw TrainingError.invalidInput }
            scores.append(try SkillDrillRules.score(kind: selectedKind, target: targets[scores.count], input: drill))
            return
        }
        guard input.drill == nil else { throw TrainingError.invalidInput }
        if let position {
            guard role == "batter", selectedKind == .defense, trait == nil, pitchCode == nil else { throw TrainingError.invalidInput }
            scores.append(try PositionTrainingRules.score(position: position, target: targets[scores.count], input: input))
            return
        }
        let score: Double
        guard selectedKind.allows(role), selectedKind == .mental || input.choice == nil,
              [.speed, .stamina].contains(selectedKind) || input.footfalls == nil,
              selectedKind == .arm || input.base == nil else { throw TrainingError.invalidInput }
        switch selectedKind {
        case .mental:
            guard input.timing == nil, input.release == nil, input.force == nil, input.angle == nil, input.calledStrike == nil,
                  let choice = input.choice, (0...2).contains(choice) else { throw TrainingError.invalidInput }
            score = choice == RawTrainingRules.question(targets: targets, round: scores.count).answer ? 100 : 0
        case .velocity, .stuff:
            guard input.timing == nil, input.release == nil, input.calledStrike == nil,
                  let force = input.force, let angle = input.angle, force.isFinite, angle.isFinite,
                  (0...100).contains(force), (0...360).contains(angle) else { throw TrainingError.invalidInput }
            score = RawTrainingRules.directionScore(kind: selectedKind, target: targets[scores.count], force: force, angle: angle)
        case .control:
            guard input.timing == nil, input.release == nil, input.force == nil, input.angle == nil, input.calledStrike == nil else { throw TrainingError.invalidInput }
            let target = targets[scores.count]
            score = max(0, 1 - hypot(input.x - target.x, input.y - target.y) / 0.3) * 100
        case .speed, .stamina:
            guard input.timing == nil, input.release == nil, input.force == nil, input.angle == nil, input.calledStrike == nil,
                  let footfalls = input.footfalls else { throw TrainingError.invalidInput }
            score = min(100, Double(TrainingRules.steps(footfalls)) / 16 * 100)
        case .defense:
            guard input.timing == nil, input.release == nil, input.force == nil, input.angle == nil, input.calledStrike == nil else { throw TrainingError.invalidInput }
            let target = targets[scores.count]
            score = max(0, 1 - hypot(input.x - target.x, input.y - target.y) / 0.55) * 100
        case .arm:
            guard input.timing == nil, input.release == nil, input.calledStrike == nil,
                  let base = input.base, (1...4).contains(base), let force = input.force, let angle = input.angle,
                  force.isFinite, angle.isFinite, (8...100).contains(force), (0...360).contains(angle) else { throw TrainingError.invalidInput }
            let endpoint = TrainingRules.throwEndpoint(angle: angle, force: force)
            let target = TrainingRules.basePoint(throwBase(scores.count))
            score = base == throwBase(scores.count) ? max(0, 1 - hypot(endpoint.x - target.x, endpoint.y - target.y) / 0.3) * 100 : 0
        case .power:
            guard role == "batter", input.timing == nil, input.release == nil, input.calledStrike == nil else { throw TrainingError.invalidInput }
            if input.force == nil && input.angle == nil { score = 0 }
            else {
                guard let force = input.force, let angle = input.angle, force.isFinite, angle.isFinite,
                      (0...100).contains(force), (15...55).contains(angle) else { throw TrainingError.invalidInput }
                let target = TrainingRules.powerTarget(scores.count)
                score = max(0, 1 - abs(TrainingRules.distance(force: force, angle: angle) - target) / (target * 0.35)) * 100
            }
        case .discipline:
            guard role == "batter", input.timing == nil, input.release == nil, input.force == nil, input.angle == nil else { throw TrainingError.invalidInput }
            let target = targets[scores.count]
            score = input.calledStrike == ManualMatchRules.isStrike(x: target.x, y: target.y) ? 100 : 0
        case .pitch:
            guard input.force == nil, input.angle == nil, input.calledStrike == nil else { throw TrainingError.invalidInput }
            guard role == "pitcher", input.timing == nil, let release = input.release else { throw TrainingError.invalidInput }
            score = ManualMatchRules.releaseQuality(release, mastery: controlMastery) * 100
        case .contact:
            guard input.force == nil, input.angle == nil, input.calledStrike == nil else { throw TrainingError.invalidInput }
            guard role == "batter", input.release == nil else { throw TrainingError.invalidInput }
            let result = TrainingRules.contactResult(input: input, target: targets[scores.count], contact: before)
            lastContact = result
            score = Double(result.total)
        }
        scores.append(Int(score.rounded()))
    }
}

enum TrainingRules {
    static let fatigueCost = 6
    static func traitGrowth(before: Double, score: Double, fatigue: Int, age: Int) -> Double {
        let performance = score >= 90 ? 1.3 : score >= 75 ? 1.2 : score >= 50 ? 1.1 : 1
        let level = before < 50 ? 1.0 : before < 80 ? 0.65 : 0.35
        let recovery = fatigue <= 40 ? 1.0 : fatigue < 60 ? 0.8 : 0.5
        return round(min(100, before + 1.2 * performance * level * recovery * ageMultiplier(age)))
    }
    static let contactPerfectWidth = 0.025
    static func contactResult(input: TrainingInput, target: TrainingTarget, contact: Double) -> ContactTrainingResult {
        let aim = TrainingTarget(x: input.x, y: input.y)
        guard let timing = input.timing else {
            return ContactTrainingResult(target: target, aim: aim, didSwing: false, positionScore: 0, timingScore: 0)
        }
        let position = max(0, 1 - hypot(input.x - target.x, input.y - target.y) / ManualMatchRules.contactRadius(contact: contact))
        // The visible yellow PERFECT band is a full-score plateau, not just its center.
        let error = max(0, abs(timing - MatchDelivery.contactPhase) - contactPerfectWidth)
        let time = max(0, 1 - error / (ManualMatchRules.timingWidth(contact: contact) - contactPerfectWidth))
        return ContactTrainingResult(target: target, aim: aim, didSwing: true,
                                     positionScore: Int((position * 100).rounded()), timingScore: Int((time * 100).rounded()))
    }
    static func steps(_ feet: [SprintFoot]) -> Int {
        var last: SprintFoot?, count = 0
        for foot in feet where foot != last { count += 1; last = foot }
        return count
    }
    static func throwBase(_ round: Int) -> Int { [1, 2, 4, 3, 2][round] }
    static func basePoint(_ base: Int) -> TrainingTarget {
        switch base {
        case 1: TrainingTarget(x: 0.78, y: 0.63)
        case 2: TrainingTarget(x: 0.5, y: 0.34)
        case 3: TrainingTarget(x: 0.22, y: 0.63)
        default: TrainingTarget(x: 0.5, y: 0.9)
        }
    }
    static func throwEndpoint(angle: Double, force: Double) -> TrainingTarget {
        TrainingTarget(x: 0.5 + cos(angle * .pi / 180) * force / 100 * 0.55,
                       y: 0.63 + sin(angle * .pi / 180) * force / 100 * 0.55)
    }
    static func powerTarget(_ round: Int) -> Double { [90, 105, 80, 115, 95][round] }
    static func distance(force: Double, angle: Double) -> Double { force * 1.35 * sin(2 * angle * .pi / 180) }
    static func round(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
    static func ageMultiplier(_ age: Int) -> Double {
        switch age {
        case ...18: 3
        case 19: 2.2
        case 20...23: 1.8
        case 24...27: 1.2
        case 28...30: 1
        case 31...33: 0.75
        case 34...36: 0.5
        case 37...40: 0.3
        default: 0.2
        }
    }
    static func growth(before: Double, score: Double, fatigue: Int, age: Int, pitch: Bool) -> Double {
        let base = pitch ? 0.12 : 0.08
        let performance = score >= 90 ? 1.3 : score >= 75 ? 1.2 : score >= 50 ? 1.1 : 1
        return round(min(100, before + base * performance * growthEfficiency(before: before, fatigue: fatigue, age: age)))
    }
    static func growthEfficiency(before: Double, fatigue: Int, age: Int) -> Double {
        let level = before < 50 ? 1.0 : before < 70 ? 0.65 : before < 80 ? 0.4 : before < 90 ? 0.2 : before < 95 ? 0.08 : 0.025
        let recovery = fatigue <= 40 ? 1.0 : fatigue < 60 ? 0.8 : 0.5
        return level * recovery * ageMultiplier(age)
    }
}

enum TrainingError: LocalizedError {
    case pending, actionUsed, invalidInput, stale, finished, invalidRecord, limit
    var errorDescription: String? {
        switch self {
        case .pending: "진행 중인 훈련을 먼저 마쳐 주세요. 저장된 시도부터 이어집니다."
        case .actionUsed: "오늘은 이미 훈련 또는 휴식을 완료했습니다."
        case .invalidInput: "훈련 입력이나 보유 구종을 다시 확인해 주세요."
        case .stale: "훈련 날짜나 선수 상태가 바뀌었습니다. 저장된 훈련을 다시 열어 주세요."
        case .finished: "이미 결과가 저장된 훈련입니다. 보상을 다시 지급하지 않습니다."
        case .invalidRecord: "훈련 기록을 읽을 수 없습니다. 기존 저장은 유지합니다."
        case .limit: "이미 최대 능력치입니다. 다른 능력치·구종이나 휴식을 선택해 주세요."
        }
    }
}


struct MentalTrainingQuestion {
    let prompt: String
    let choices: [String]
    let answer: Int
}

enum RawTrainingRules {
    static let questions = [
        MentalTrainingQuestion(prompt: "실책 직후, 다음 플레이를 앞두고 있다", choices: ["호흡을 고르고 다음 공에 집중", "지난 실수를 계속 복기", "급하게 만회하려고 서두르기"], answer: 0),
        MentalTrainingQuestion(prompt: "접전 후반, 관중의 야유가 들린다", choices: ["관중에게 반응하기", "내 루틴과 다음 작전에 집중", "계획 없이 빠르게 진행"], answer: 1),
        MentalTrainingQuestion(prompt: "몸이 무겁고 통증이 느껴진다", choices: ["무조건 참고 강행", "숨기고 개인 훈련 추가", "코치에게 알리고 상태 확인"], answer: 2),
        MentalTrainingQuestion(prompt: "판정이 아쉽지만 경기는 계속된다", choices: ["확인 후 다음 플레이 준비", "항의 생각에 머무르기", "다음 공을 무조건 강공"], answer: 0),
        MentalTrainingQuestion(prompt: "득점권 위기, 동료가 작전을 제안한다", choices: ["혼자 감으로 결정", "작전을 확인하고 호흡 정리", "준비 없이 바로 시작"], answer: 1)
    ]
    // Saved targets fix the question order and controls across resume/retry.
    static func question(targets: [TrainingTarget], round: Int) -> MentalTrainingQuestion {
        questions[(Int(targets[0].x * 100) + round) % questions.count]
    }
    static func goal(kind: TrainingKind, target: TrainingTarget) -> (force: Double, angle: Double) {
        if kind == .velocity { return (60 + (target.x * 6).rounded() * 5, 15 + (target.y * 8).rounded() * 5) }
        return ((target.y * 10).rounded() * 10, (target.x * 12).rounded() * 30)
    }
    static func directionScore(kind: TrainingKind, target: TrainingTarget, force: Double, angle: Double) -> Double {
        let goal = goal(kind: kind, target: target)
        let difference = abs(angle - goal.angle).truncatingRemainder(dividingBy: 360)
        let error = min(difference, 360 - difference)
        return max(0, 1 - max(abs(force - goal.force) / 40, error / (kind == .velocity ? 35 : 90))) * 100
    }
}

struct SkillDrillInput: Codable, Equatable {
    var phase: Double?
    var beats: [Double?]?
    var trace: [TrainingTarget]?
}

enum SkillDrillRules {
    static let kinds: [TrainingKind] = [.power, .velocity, .stuff]
    static let beats = [0.65, 1.35, 2.05]
    static let rhythmDuration = 2.4
    static let beatWindow = 0.22
    static let perfectWindow = 0.04
    static func recordBeat(_ index: Int, elapsed: Double, taps: inout [Double?]) -> Bool {
        guard taps.count == 3, beats.indices.contains(index), elapsed.isFinite, taps[index] == nil,
              abs(elapsed - beats[index]) <= beatWindow else { return false }
        taps[index] = elapsed; return true
    }
    static func powerDuration(_ target: TrainingTarget) -> Double { 2.4 + target.x * 0.8 }
    static func curve(_ target: TrainingTarget) -> [TrainingTarget] {
        let bend = (target.y < 0.5 ? -1.0 : 1.0) * (0.18 + target.x * 0.12)
        return (0...24).map { i in
            let t = Double(i) / 24
            return TrainingTarget(x: 0.5 + sin(t * .pi) * bend, y: 0.85 - 0.7 * t)
        }
    }
    static func score(kind: TrainingKind, target: TrainingTarget, input: SkillDrillInput) throws -> Int {
        let value: Double
        switch kind {
        case .power:
            guard let phase = input.phase, phase.isFinite, (0...1).contains(phase), input.beats == nil, input.trace == nil else { throw TrainingError.invalidInput }
            value = max(0, 1 - max(0, abs(phase - 0.5) - 0.025) / 0.475)
        case .velocity:
            guard input.phase == nil, input.trace == nil, let taps = input.beats, taps.count == 3,
                  taps.compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...rhythmDuration).contains($0) }) else { throw TrainingError.invalidInput }
            let actual = taps.compactMap { $0 }
            guard zip(actual, actual.dropFirst()).allSatisfy({ $0 < $1 }) else { return 0 }
            value = zip(taps, beats).reduce(0) { sum, pair in
                guard let tap = pair.0 else { return sum }
                return sum + max(0, 1 - max(0, abs(tap - pair.1) - perfectWindow) / (beatWindow - perfectWindow)) / 3
            }
        case .stuff:
            guard input.phase == nil, input.beats == nil, let trace = input.trace, trace.count <= 256,
                  trace.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw TrainingError.invalidInput }
            let reference = curve(target)
            guard let first = trace.first, let last = trace.last, distance(first, reference[0]) <= 0.18,
                  distance(last, reference[24]) <= 0.18, let a = resample(trace), let b = resample(reference) else { return 0 }
            let error = zip(a, b).reduce(0) { $0 + distance($1.0, $1.1) } / Double(a.count)
            let shape = max(0, 1 - max(0, error - 0.015) / 0.16)
            let coverage = Double(b.filter { point in a.contains { distance(point, $0) <= 0.08 } }.count) / Double(b.count)
            value = shape * 0.7 + coverage * 0.3
        default: throw TrainingError.invalidInput
        }
        return Int((min(1, max(0, value)) * 100).rounded())
    }
    private static func distance(_ a: TrainingTarget, _ b: TrainingTarget) -> Double { hypot(a.x - b.x, a.y - b.y) }
    private static func resample(_ points: [TrainingTarget]) -> [TrainingTarget]? {
        guard points.count >= 2 else { return nil }
        var lengths = [0.0]
        for i in 1..<points.count { lengths.append(lengths[i-1] + distance(points[i-1], points[i])) }
        guard let total = lengths.last, total >= 0.02 else { return nil }
        var segment = 1
        return (0...32).map { index in
            let at = total * Double(index) / 32
            while segment < points.count - 1 && lengths[segment] < at { segment += 1 }
            let span = lengths[segment] - lengths[segment-1]
            let t = span > 0 ? (at - lengths[segment-1]) / span : 0
            return TrainingTarget(x: points[segment-1].x + (points[segment].x-points[segment-1].x)*t,
                                  y: points[segment-1].y + (points[segment].y-points[segment-1].y)*t)
        }
    }
}


/// Frozen completion evidence. Reopening this receipt never recomputes today's project.
struct TrainingProjectFeedback: Codable, Equatable {
    let version: Int
    let activityKey: String
    let project: CareerDevelopmentProject?
    let clubName: String?
    let before: CareerProjectProgress?
    let after: CareerProjectProgress?
    static func projected(_ before: CareerProjectProgress, project: CareerDevelopmentProject, training: CareerTraining, key: String) -> CareerProjectProgress {
        let related = training.trait == nil && training.position == nil && training.selectedKind == project.training && !project.baselineTrainings.contains(key)
        var result = CareerProjectProgress(matchKeys: before.matchKeys, trainingKeys: (before.trainingKeys + (related ? [key] : [])).sorted(),
            qualitySessions: before.qualitySessions + (related && training.average >= 75 ? 1 : 0), sample: before.sample,
            growth: TrainingRules.round(before.growth + (related ? training.gain : 0)), requiredSample: before.requiredSample)
        if let task = before.task {
            let contributes = training.trait == nil && training.position != nil && training.position?.rawValue == project.assignment?.position && task.metric == .position && !project.baselineTrainings.contains(key)
            result.task = CareerProjectTaskProgress(metric:task.metric,value:task.value + (contributes ? 1:0),goal:task.goal,
                keys:(task.keys + (contributes ? [key]:[])).sorted(),trainingGoal:task.trainingGoal,qualityGoal:task.qualityGoal)
        }
        return result
    }
    func validate(training: CareerTraining) throws {
        guard version == 1, training.completed, activityKey == "\(training.playerID.uuidString):\(training.date)" else { throw TrainingError.invalidRecord }
        guard let project else {
            guard clubName == nil, before == nil, after == nil else { throw TrainingError.invalidRecord }; return
        }
        guard let before, let after, let clubName, !clubName.isEmpty,
              project.role.rawValue == training.role, project.start <= training.date, training.date <= project.end,
              !before.trainingKeys.contains(activityKey), !(before.task?.keys.contains(activityKey) ?? false),
              after == Self.projected(before,project:project,training:training,key:activityKey) else { throw TrainingError.invalidRecord }
    }
    var trainingContribution: Int { max(0,(after?.trainingKeys.count ?? 0)-(before?.trainingKeys.count ?? 0)) }
    var qualityContribution: Int { max(0,(after?.qualitySessions ?? 0)-(before?.qualitySessions ?? 0)) }
    var taskContribution: Int { max(0,(after?.task?.value ?? 0)-(before?.task?.value ?? 0)) }
    var nextAction: String {
        guard let project, let after else { return "목표 구단을 고르고 선수 프로젝트를 시작해 보세요." }
        if after.complete { return "과제 기준 충족 · 다음 관찰 보고서에서 평가를 확인하세요." }
        if trainingContribution == 0 && taskContribution == 0 { return "이 과제는 \(project.training.label) 훈련과 지정 활동을 집계합니다." }
        if after.trainingKeys.count < (after.task?.trainingGoal ?? 3) || after.qualitySessions < (after.task?.qualityGoal ?? 2) { return "다음 훈련일에 \(project.training.label) 훈련 · 평균 75점 이상에 도전하세요." }
        if let task=after.task,task.value < task.goal { return "지정 관찰 과제의 남은 활동을 진행하세요." }
        return "공식 경기에서 필요한 표본을 더 확보하세요."
    }
}


struct MatchProjectFeedback: Codable, Equatable {
    let version: Int
    let activityKey: String
    let date: String
    let project: CareerDevelopmentProject?
    let clubName: String?
    let before: CareerProjectProgress?
    let after: CareerProjectProgress?
    static func projected(_ before: CareerProjectProgress,project:CareerDevelopmentProject,match:CareerMatch,key:String) -> CareerProjectProgress {
        let related=match.completed && match.appearance && match.role == project.role.rawValue && (match.competition ?? "highschool") == project.level && !project.baselineMatches.contains(key)
        let sample=related ? (project.role == .batter ? match.line.plateAppearances:match.line.pitchingOuts):0
        var value=CareerProjectProgress(matchKeys:(before.matchKeys+(related ? [key]:[])).sorted(),trainingKeys:before.trainingKeys,
            qualitySessions:before.qualitySessions,sample:before.sample+sample,growth:before.growth,requiredSample:before.requiredSample)
        if let task=before.task {
            let gain=related ? (project.assignment?.metric.value(in:match) ?? 0):0
            value.task=CareerProjectTaskProgress(metric:task.metric,value:task.value+gain,goal:task.goal,keys:(task.keys+(gain>0 ? [key]:[])).sorted(),trainingGoal:task.trainingGoal,qualityGoal:task.qualityGoal)
        }
        return value
    }
    func validate(match:CareerMatch,key:String,date:String) throws {
        guard version == 1,match.completed,activityKey == key,self.date == date else {throw MatchError.invalidRecord}
        guard let project else {guard clubName == nil,before == nil,after == nil else {throw MatchError.invalidRecord};return}
        guard let before,let after,let clubName,!clubName.isEmpty,project.role.rawValue == match.role,
              project.start <= date,date <= project.end,!before.matchKeys.contains(key),!(before.task?.keys.contains(key) ?? false),
              after == Self.projected(before,project:project,match:match,key:key) else {throw MatchError.invalidRecord}
    }
    var sampleContribution:Int {max(0,(after?.sample ?? 0)-(before?.sample ?? 0))}
    var taskContribution:Int {max(0,(after?.task?.value ?? 0)-(before?.task?.value ?? 0))}
}

// Versioned training growth is independent of legacy match XP, traits and position XP.
enum DevelopmentTiming:String,Codable,CaseIterable {
    case early,balanced,late
    var label:String {switch self {case .early:"조기 발현";case .balanced:"균형 발현";case .late:"후기 발현"}}
    var ages:ClosedRange<Int> {switch self {case .early:16...22;case .balanced:18...26;case .late:20...30}}
    func factor(age:Int) -> Double {
        switch self {
        case .balanced:1
        case .early:age<=18 ? 1.1:age<=23 ? 0.95:0.9
        case .late:age<=18 ? 0.9:age<=23 ? 1.15:age<=27 ? 1.1:1
        }
    }
}
struct TrainingGrowthPolicy:Codable,Equatable {
    var version=2
    let timing:DevelopmentTiming
    let windowID:String?
    let bonusLimit:Double
    func validate(training:CareerTraining) throws {
        guard version == 2,training.trait == nil,training.position == nil,training.pitchStudy == nil,
              bonusLimit.isFinite,(0...0.6).contains(bonusLimit),windowID == nil ? bonusLimit == 0:(windowID!.hasPrefix(training.playerID.uuidString+":") && windowID!.hasSuffix("/growth-window-v2")) else {throw TrainingError.invalidRecord}
    }
    func base(training:CareerTraining) -> Double {
        DevelopmentRules.growth(before:training.before,score:training.average,fatigue:training.fatigue,age:training.age,pitch:training.pitchCode != nil,timing:timing)
    }
    func bonus(training:CareerTraining) -> Double {TrainingRules.round(min(bonusLimit,100-base(training:training),max(0,base(training:training)-training.before)*0.4))}
    func after(training:CareerTraining) -> Double {TrainingRules.round(min(100,base(training:training)+bonus(training:training)))}
}
enum DevelopmentRules {
    static func growth(before:Double,score:Double,fatigue:Int,age:Int,pitch:Bool,timing:DevelopmentTiming) -> Double {
        let level=before<50 ? 1.0:before<70 ? 0.65:before<80 ? 0.25:before<90 ? 0.10:before<95 ? 0.04:0.0125
        let performance=score>=90 ? 1.3:score>=75 ? 1.2:score>=50 ? 1.1:1
        let recovery=fatigue<=40 ? 1.0:fatigue<60 ? 0.8:0.5
        return TrainingRules.round(min(100,before+(pitch ? 0.12:0.08)*performance*level*recovery*TrainingRules.ageMultiplier(age)*timing.factor(age:age)))
    }
    static func loss(_ kind:TrainingKind,age:Int) -> Double {
        guard age<=40,kind != .mental else {return 0}
        if [.speed,.velocity].contains(kind) {return age<27 ? 0:age<=30 ? 0.35:age<=33 ? 0.6:age<=36 ? 1:1.4}
        if [.power,.arm,.stamina].contains(kind) {return age<29 ? 0:age<=30 ? 0.2:age<=33 ? 0.4:age<=36 ? 0.75:1.1}
        if [.control,.discipline,.pitch].contains(kind) {return age<34 ? 0:age<=36 ? 0.12:0.3}
        return age<31 ? 0:age<=33 ? 0.15:age<=36 ? 0.35:0.65
    }
    static func aged(_ value:Double,kind:TrainingKind,age:Int,pitch:Bool) -> Double {TrainingRules.round(min(value,max(pitch ? 0:1,value-loss(kind,age:age))))}
}
struct DevelopmentProof:Codable,Equatable {
    let key:String
    let date:String
}
struct DevelopmentWindow:Codable,Equatable,Identifiable {
    let id:String
    let kind:TrainingKind
    var pitchCode:String?
    let opened:String
    let expires:String
    let sources:[DevelopmentProof]
    var used=0
    var spent=0.0
    func available(on date:String) -> Bool {date>=opened && date<=expires && used<8 && spent<0.6}
}
struct DevelopmentPositionChange:Codable,Equatable {
    let date:String
    let from:FieldPosition
    let to:FieldPosition
    let mastery:Double
}
struct PlayerDevelopment:Codable,Equatable {
    var version=2
    let adopted:String
    let timing:DevelopmentTiming
    var proofs:[String:[DevelopmentProof]]=[:]
    var windows:[DevelopmentWindow]=[]
    var positions:[DevelopmentPositionChange]=[]
    static func initial(playerID:UUID,date:String,legacy:Bool=false) -> Self {
        let hash=DomesticSelection.hash("development-v2/"+playerID.uuidString)
        return Self(adopted:date,timing:legacy ? .balanced:DevelopmentTiming.allCases[Int(hash%3)])
    }
    var completedPreparation:Int {proofs.values.map(\.count).max() ?? 0}
    func active(on date:String) -> DevelopmentWindow? {windows.last {$0.available(on:date)}}
    func policy(kind:TrainingKind,code:String?=nil,on date:String) -> TrainingGrowthPolicy {
        let window=active(on:date).flatMap {$0.kind == kind && $0.pitchCode == code ? $0:nil}
        return TrainingGrowthPolicy(timing:timing,windowID:window?.id,bonusLimit:window.map {TrainingRules.round(0.6-$0.spent)} ?? 0)
    }
    mutating func complete(_ training:CareerTraining,key:String) throws {
        guard let policy=training.growthPolicy,policy.timing == timing,training.completed,training.date>=adopted else {throw TrainingError.invalidRecord}
        if let id=policy.windowID {
            guard let i=windows.firstIndex(where:{$0.id == id}),windows[i].available(on:training.date),windows[i].kind == training.selectedKind,windows[i].pitchCode == training.pitchCode,
                  policy.bonusLimit == TrainingRules.round(0.6-windows[i].spent) else {throw TrainingError.stale}
            windows[i].used += 1;windows[i].spent=TrainingRules.round(windows[i].spent+min(max(0,training.after-policy.base(training:training)),policy.bonusLimit))
        }
        let day=try GameDate(training.date),from=day.adding(days:-55).description
        for kind in Array(proofs.keys) {proofs[kind]=proofs[kind]!.filter {$0.date>=from}}
        if training.average>=50,training.fatigue<=40,training.before<95 {
            let kind=training.pitchCode.map {"pitch/"+$0} ?? training.selectedKind.rawValue
            guard !proofs.values.flatMap({$0}).contains(where:{$0.key == key}) else {throw TrainingError.invalidRecord}
            proofs[kind]=Array(((proofs[kind] ?? [])+[DevelopmentProof(key:key,date:training.date)]).suffix(8))
            let sources=proofs[kind] ?? []
            if sources.count==8,timing.ages.contains(training.age),active(on:training.date) == nil,try GameDate(adopted).days(to:day)>=14,
               !windows.contains(where:{String($0.opened.prefix(4)) == String(training.date.prefix(4))}) {
                windows.append(DevelopmentWindow(id:key+"/growth-window-v2",kind:training.selectedKind,pitchCode:training.pitchCode,opened:training.date,expires:day.adding(days:27).description,sources:sources))
                proofs[kind]=[]
            }
        }
        try validate(playerID:training.playerID,today:training.date)
    }
    func validate(playerID:UUID,today:String) throws {
        guard version == 2,try GameDate(adopted)<=GameDate(today),windows.count<=25,positions.count<=400,
              Set(windows.map(\.id)).count == windows.count,Set(windows.map {String($0.opened.prefix(4))}).count == windows.count,
              proofs.count<=TrainingKind.allCases.count+PitchType.allCases.count else {throw CareerLifecycleError.invalid}
        var keys:Set<String>=[]
        for (kind,rows) in proofs {
            guard TrainingKind(rawValue:kind) != nil || kind.hasPrefix("pitch/") && PitchType(rawValue:String(kind.dropFirst(6))) != nil,rows.count<=8 else {throw CareerLifecycleError.invalid}
            for row in rows {guard row.key == CareerTrainingRecord.key(playerID,row.date),try GameDate(row.date)>=GameDate(adopted),row.date<=today,keys.insert(row.key).inserted else {throw CareerLifecycleError.invalid}}
        }
        for w in windows {
            guard w.pitchCode == nil ? w.kind != .pitch:(w.kind == .pitch && PitchType(rawValue:w.pitchCode!) != nil),w.opened>=adopted,w.opened<=today,w.expires == (try GameDate(w.opened).adding(days:27).description),
                  (0...8).contains(w.used),w.spent.isFinite,(0...0.6).contains(w.spent),w.sources.count==8,
                  Set(w.sources.map(\.key)).count==8,w.sources.map(\.date) == w.sources.map(\.date).sorted(),w.sources.last?.date == w.opened,w.id == w.sources.last!.key+"/growth-window-v2" else {throw CareerLifecycleError.invalid}
            for row in w.sources {guard row.key == CareerTrainingRecord.key(playerID,row.date),row.date>=adopted,row.date<=w.opened,try GameDate(row.date)>=GameDate(w.opened).adding(days:-55) else {throw CareerLifecycleError.invalid}}
        }
        var previous:DevelopmentPositionChange?
        for change in positions {
            guard change.from != change.to,change.mastery.isFinite,(40...100).contains(change.mastery),change.date>=adopted,change.date<=today,
                  try previous.map {try GameDate($0.date).days(to:GameDate(change.date))>=28 && $0.to==change.from} ?? true else {throw CareerLifecycleError.invalid}
            previous=change
        }
    }
}
