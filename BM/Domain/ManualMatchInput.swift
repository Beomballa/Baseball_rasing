import Foundation

struct ManualMatchInput: Codable, Equatable {
    var x = 0.5
    var y = 0.5
    var timing: Double?
    var release: Double?

    func validate(for input: MatchInput, role: String) throws {
        let values = [x, y] + [timing, release].compactMap { $0 }
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }), input != .automatic else { throw MatchError.invalidInput }
        if role == "pitcher" {
            guard input == .pitch, release != nil, timing == nil else { throw MatchError.invalidInput }
        } else {
            guard release == nil, input != .pitch, input != .watch || timing == nil else { throw MatchError.invalidInput }
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
}

struct MatchDelivery: Equatable {
    let x: Double
    let y: Double
    let speed: Int
    static let windup = 0.35
    static let contactPhase = 0.82
    var duration: Double { 1.35 * 145 / Double(speed) }
}

enum ManualMatchRules {
    static let releaseCenter = 0.68
    static func goodWidth(mastery: Double) -> Double { 0.06 + 0.10 * max(0, min(100, mastery)) / 100 }
    static func perfectWidth(mastery: Double) -> Double { 0.018 + 0.032 * max(0, min(100, mastery)) / 100 }
    static func contactRadius(contact: Double) -> Double { 0.12 + max(0, min(100, contact)) * 0.0012 }
    static func timingWidth(contact: Double) -> Double { 0.055 + max(0, min(100, contact)) * 0.0008 }
    static func battingQuality(input: ManualMatchInput, delivery: MatchDelivery, contact: Double) -> Double {
        guard let timing = input.timing else { return 0 }
        let position = hypot(input.x - delivery.x, input.y - delivery.y) / contactRadius(contact: contact)
        let time = abs(timing - MatchDelivery.contactPhase) / timingWidth(contact: contact)
        return max(0, 1 - max(position, time))
    }
    static func releaseQuality(_ phase: Double, mastery: Double) -> Double {
        max(0, 1 - abs(phase - releaseCenter) / (goodWidth(mastery: mastery) * 2))
    }
    static func isStrike(x: Double, y: Double) -> Bool { (0.2...0.8).contains(x) && (0.2...0.8).contains(y) }
}
