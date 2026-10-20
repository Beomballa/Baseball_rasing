import Foundation

struct TrainingInput: Codable, Equatable {
    var x = 0.5
    var y = 0.5
    var timing: Double?
    var release: Double?
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
    var title: String { pitchCode == nil ? "컨택 훈련" : "구종 훈련" }

    init(playerID: UUID, date: String, role: String, pitchCode: String?, before: Double, fatigue: Int, age: Int, calendarRevision: Int) {
        self.playerID = playerID; self.date = date; self.role = role; self.pitchCode = pitchCode
        self.before = before; self.fatigue = fatigue; self.age = age; self.calendarRevision = calendarRevision
        var seed = (playerID.uuidString + date + (pitchCode ?? "contact")).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        func roll() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / 9007199254740992 }
        targets = (0..<5).map { _ in TrainingTarget(x: 0.25 + roll() * 0.5, y: 0.25 + roll() * 0.5) }
    }
    mutating func attempt(_ input: TrainingInput) throws {
        guard !completed else { throw TrainingError.finished }
        let numbers = [input.x, input.y] + [input.timing, input.release].compactMap { $0 }
        guard numbers.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw TrainingError.invalidInput }
        let score: Double
        if pitchCode != nil {
            guard role == "pitcher", input.timing == nil, let release = input.release else { throw TrainingError.invalidInput }
            score = ManualMatchRules.releaseQuality(release, mastery: before) * 100
        } else {
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
        case .limit: "이미 최대 능력치입니다. 다른 구종이나 휴식을 선택해 주세요."
        }
    }
}
