import Foundation

enum PitchType: String, Codable, CaseIterable, Identifiable {
    case fourSeam = "four-seam", twoSeam = "two-seam", cutter, slider, curve, changeup, fork, sweeper, knuckle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fourSeam: "포심"
        case .twoSeam: "투심"
        case .cutter: "커터"
        case .slider: "슬라이더"
        case .curve: "커브"
        case .changeup: "체인지업"
        case .fork: "포크"
        case .sweeper: "스위퍼"
        case .knuckle: "너클"
        }
    }
    var initialMastery: Double {
        switch self {
        case .fourSeam: 62
        case .twoSeam, .slider: 55
        case .cutter: 48
        case .curve, .changeup: 42
        case .fork: 35
        case .sweeper: 40
        case .knuckle: 30
        }
    }
    var speedOffset: Double {
        switch self {
        case .fourSeam: 0
        case .twoSeam: -4
        case .cutter: -7
        case .slider: -13
        case .curve: -27
        case .changeup: -20
        case .fork: -16
        case .sweeper: -18
        case .knuckle: -40
        }
    }
    var family: String {
        switch self {
        case .fourSeam, .twoSeam, .cutter: "fast"
        case .slider, .sweeper: "glove"
        case .changeup: "slow"
        case .curve, .fork: "vertical"
        case .knuckle: "float"
        }
    }
}

struct PitchTarget: Codable, Equatable {
    let x: Double
    let y: Double
}

struct PitchAim: Codable, Equatable {
    let recommended: PitchTarget
    let target: PitchTarget
}

struct ManualMatchInput: Codable, Equatable {
    var x = 0.5
    var y = 0.5
    var timing: Double?
    var release: Double?
    var pitchTarget: PitchTarget? = nil

    func validate(for input: MatchInput, role: String) throws {
        let values = [x, y] + [timing, release].compactMap { $0 } + (pitchTarget.map { [$0.x, $0.y] } ?? [])
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }), input != .automatic else { throw MatchError.invalidInput }
        if role == "pitcher" {
            guard input == .pitch, release != nil, timing == nil else { throw MatchError.invalidInput }
        } else {
            guard release == nil, pitchTarget == nil, input != .pitch, input != .watch || timing == nil else { throw MatchError.invalidInput }
        }
    }
}

struct ManualMatchResult: Codable, Equatable {
    let action: String
    let quality: Double
    let grade: String
    let x: Double
    let y: Double
    let speed: Int
    var outcome: String
    var pitchCode: String? = nil
    var pitchAim: PitchAim? = nil
}

struct MatchDelivery: Equatable {
    let x: Double
    let y: Double
    let speed: Int
    var exactSpeed: Double? = nil
    static func pitch(code: String, velocity: Double) -> MatchDelivery {
        let stats = MatchAbilityStats(mental: 60, velocity: velocity, control: nil, stuff: nil, stamina: nil, fatigue: 0)
        let speed = stats.speedValue(code: code)
        return MatchDelivery(x: 0.5, y: 0.5, speed: Int(speed.rounded()), exactSpeed: speed)
    }
    static let windup = 0.35
    static let contactPhase = 0.82
    var duration: Double { 1.35 * 145 / (exactSpeed ?? Double(speed)) }
}

enum ManualMatchRules {
    static let releaseCenter = 0.68
    static func goodWidth(mastery: Double) -> Double { 0.06 + 0.10 * max(0, min(100, mastery)) / 100 }
    static func perfectWidth(mastery: Double) -> Double { 0.018 + 0.032 * max(0, min(100, mastery)) / 100 }
    static func contactRadius(contact: Double) -> Double { 0.12 + max(0, min(100, contact)) * 0.0012 }
    static func timingWidth(contact: Double) -> Double { 0.055 + max(0, min(100, contact)) * 0.0008 }
    static func battingQuality(input: ManualMatchInput, delivery: MatchDelivery, contact: Double, execution: Double = 1) -> Double {
        guard let timing = input.timing else { return 0 }
        let position = hypot(input.x - delivery.x, input.y - delivery.y) / (contactRadius(contact: contact) * execution)
        let time = abs(timing - MatchDelivery.contactPhase) / (timingWidth(contact: contact) * execution)
        return max(0, 1 - max(position, time))
    }
    static func releaseQuality(_ phase: Double, mastery: Double) -> Double {
        max(0, 1 - abs(phase - releaseCenter) / (goodWidth(mastery: mastery) * 2))
    }
    static func isStrike(x: Double, y: Double) -> Bool { (0.2...0.8).contains(x) && (0.2...0.8).contains(y) }
}


/// Version 1 balance parameters for new matches; absent snapshots keep legacy rules.
struct MatchAbilityStats: Codable, Equatable {
    var version = 1
    let mental: Double
    let velocity: Double?
    let control: Double?
    let stuff: Double?
    let stamina: Double?
    let fatigue: Int

    func execution(currentFatigue: Double, pressure: Bool) -> Double {
        let recovery = max(0.7, 1 - max(0, currentFatigue - 40) * 0.005)
        return recovery * (pressure ? 0.92 + 0.0008 * mental : 1)
    }
    var pitchCost: Double { 0.3 + 0.002 * (100 - (stamina ?? 60)) }
    var controlWidth: Double { 0.8 + (control ?? 50) * 0.004 }
    var scatterScale: Double { 1.2 - (control ?? 50) * 0.004 }
    func hitChance(quality: Double) -> Double { max(0.04, min(0.5, 0.36 - quality * 0.20 - ((stuff ?? 50) - 50) * 0.0012)) }
    func homeRunChance(quality: Double) -> Double { max(0.01, min(0.25, 0.16 - quality * 0.10 - ((stuff ?? 50) - 50) * 0.0004)) }
    func speed(code: String) -> Int { Int(speedValue(code: code).rounded()) }
    func speedValue(code: String) -> Double {
        let base: Double = 120 + (velocity ?? 62.5) * 0.4
        return base + (PitchType(rawValue: code)?.speedOffset ?? -10)
    }
}

// Presentation-only provisional lineup; the saved batting order makes it stable on resume.
enum OpponentBatterSide: String, CaseIterable {
    case left, right
    var label: String { self == .left ? "좌타 상대" : "우타 상대" }
    var mapOnRight: Bool { self == .left }
    static func at(order: Int) -> Self { [1,4,7].contains(order % 9) ? .left : .right }
}
extension CareerMatch {
    var opponentBatterSide: OpponentBatterSide { .at(order: isHome ? awayOrder : homeOrder) }
}
