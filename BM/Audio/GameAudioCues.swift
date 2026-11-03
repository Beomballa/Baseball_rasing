import UIKit

/// 경기 효과와 녹음 자산의 대응이다. 확인음만 합성으로 처리한다.
enum GameSoundCue: CaseIterable {
    case contact, catchBall, confirm, crowd
    var recording: GameRecording? {
        switch self {
        case .contact: .contact
        case .catchBall: .catchBall
        case .crowd: .crowd
        case .confirm: nil
        }
    }
}

/// 번들 녹음 자산 이름이다. 파일을 폴더로 옮겨도 이 이름은 유지한다.
enum GameRecording: String, CaseIterable {
    case contact = "BaseballContactV110"
    case catchBall = "BaseballCatchV110"
    case crowd = "BaseballCrowdV110"
    case strike = "UmpireStrikeV110"
    case ball = "UmpireBallV110"
    case out = "UmpireOutV110"
    func data(bundle: Bundle = .main) -> Data? { NSDataAsset(name: rawValue, bundle: bundle)?.data }
}

enum UmpireCall: String, CaseIterable {
    case strike = "스트라이크"
    case ball = "볼"
    case strikeout = "삼진"
    case walk = "볼넷"
    case out = "타구 아웃"

    // 녹음은 Strike/Ball/Out을 사용하고, 삼진·볼넷 등의 구분은 한국어 자막으로 유지한다.
    var recording: GameRecording {
        switch self {
        case .strike: .strike
        case .ball, .walk: .ball
        case .strikeout, .out: .out
        }
    }
    /// 인플레이가 끝난 뒤 실제 추가 아웃이 있을 때만 아웃 콜을 선택한다.
    static func resolvedField(outsAdded: Int) -> Self? { outsAdded > 0 ? .out : nil }

    /// 지원하는 최종 판정만 변환하고 나머지는 음성 없이 자막으로 처리한다.
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
