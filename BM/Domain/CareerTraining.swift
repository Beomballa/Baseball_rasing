import Foundation

enum TrainingKind: String, Codable, CaseIterable {
    case contact, power, discipline, pitch, speed, defense, arm
    var isField: Bool { [.speed, .defense, .arm].contains(self) }
    var label: String {
        switch self { case .contact: "컨택"; case .power: "파워"; case .discipline: "선구안"; case .pitch: "구종"; case .speed: "스피드"; case .defense: "수비"; case .arm: "송구" }
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
}

struct TrainingTarget: Codable, Equatable {
    let x: Double
    let y: Double
}

struct CareerTraining: Codable, Equatable {
    let playerID: UUID
    let date: String
    let role: String
    let pitchCode: String?
    let kind: TrainingKind?
    var selectedKind: TrainingKind { kind ?? (pitchCode == nil ? .contact : .pitch) }
    let before: Double
    let fatigue: Int
    let age: Int
    let targets: [TrainingTarget]
    var scores: [Int] = []
    var calendarRevision: Int
    var completed: Bool { scores.count == 5 }
    var average: Double { scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count) }
    var after: Double { completed ? TrainingRules.growth(before: before, score: average, fatigue: fatigue, age: age, pitch: pitchCode != nil) : before }
    var gain: Double { TrainingRules.round(after - before) }
    var title: String { selectedKind.label + " 훈련" }

    init(playerID: UUID, date: String, role: String, pitchCode: String?, before: Double, fatigue: Int, age: Int, calendarRevision: Int, kind: TrainingKind? = nil) {
        self.playerID = playerID; self.date = date; self.role = role; self.pitchCode = pitchCode
        self.kind = kind
        self.before = before; self.fatigue = fatigue; self.age = age; self.calendarRevision = calendarRevision
        var seed = (playerID.uuidString + date + (kind?.rawValue ?? pitchCode ?? "contact")).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        func roll() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / 9007199254740992 }
        var inZone = [true, true, true, false, false]
        if kind == .discipline {
            for index in stride(from: 4, through: 1, by: -1) { inZone.swapAt(index, Int(roll() * Double(index + 1))) }
        }
        targets = (0..<5).map { index in
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
        let score: Double
        guard selectedKind == .speed || input.footfalls == nil,
              selectedKind == .arm || input.base == nil else { throw TrainingError.invalidInput }
        switch selectedKind {
        case .speed:
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
            let target = TrainingRules.basePoint(TrainingRules.throwBase(scores.count))
            score = base == TrainingRules.throwBase(scores.count) ? max(0, 1 - hypot(endpoint.x - target.x, endpoint.y - target.y) / 0.3) * 100 : 0
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
            score = ManualMatchRules.releaseQuality(release, mastery: before) * 100
        case .contact:
            guard input.force == nil, input.angle == nil, input.calledStrike == nil else { throw TrainingError.invalidInput }
            guard role == "batter", input.release == nil else { throw TrainingError.invalidInput }
            if let timing = input.timing {
                let target = targets[scores.count]
                let position = max(0, 1 - hypot(input.x - target.x, input.y - target.y) / ManualMatchRules.contactRadius(contact: before))
                let time = max(0, 1 - abs(timing - MatchDelivery.contactPhase) / ManualMatchRules.timingWidth(contact: before))
                score = (position * 0.65 + time * 0.35) * 100
            } else { score = 0 }
        }
        scores.append(Int(score.rounded()))
    }
}

enum TrainingRules {
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
        let level = before < 50 ? 1.0 : before < 70 ? 0.65 : before < 80 ? 0.4 : before < 90 ? 0.2 : before < 95 ? 0.08 : 0.025
        let recovery = fatigue <= 40 ? 1.0 : fatigue < 60 ? 0.8 : 0.5
        return round(min(100, before + base * performance * level * recovery * ageMultiplier(age)))
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
