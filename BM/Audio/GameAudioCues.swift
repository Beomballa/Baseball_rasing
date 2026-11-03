import UIKit

enum GameSoundCue: CaseIterable {
    case contact, catchBall, confirm, crowd
    var recording: GameRecording? {
        switch self {case .contact: .contact; case .catchBall: .catchBall; case .crowd: .crowd; case .confirm: nil}
    }
}

enum GameRecording: String, CaseIterable {
    case contact = "BaseballContactV110", catchBall = "BaseballCatchV110", crowd = "BaseballCrowdV110"
    case strike = "UmpireStrikeV110", ball = "UmpireBallV110", out = "UmpireOutV110"
    func data(bundle: Bundle = .main) -> Data? { NSDataAsset(name: rawValue, bundle: bundle)?.data }
}

enum UmpireCall: String, CaseIterable {
    case strike = "스트라이크"
    case ball = "볼"
    case strikeout = "삼진"
    case walk = "볼넷"
    case out = "타구 아웃"

    // The recordings say Strike / Ball / You're out. Detailed outcomes remain Korean captions.
    var recording: GameRecording {
        switch self {case .strike: .strike; case .ball, .walk: .ball; case .strikeout, .out: .out}
    }
    static func resolvedField(outsAdded: Int) -> Self? { outsAdded > 0 ? .out : nil }

    init?(outcome: String) {
        switch outcome {
        case "루킹 스트라이크", "헛스윙": self = .strike
        case "볼": self = .ball
        case "삼진": self = .strikeout
        case "볼넷": self = .walk
        default: return nil
        }
    }
}
