import CoreGraphics

/// 도트 원화의 발·손 기준점이다. 경기 판정 좌표와 분리된 연출용 정보다.
struct PitcherPresentationPose {
    let width: Double
    private(set) var pivot: CGPoint
    private(set) var hand: CGPoint
    private(set) var foot: CGPoint
    /// 화면 역할과 투구 손에 맞춘 정규화 몸 이동량을 계산한다.
    static func travel(role: PlayerRole, phase: Double, hand: String) -> CGPoint {
        // 자세가 바뀌어도 몸 이동은 연속으로 계산하고 앞발 착지는 원화 기준점을 따른다.
        let p = min(role == .pitcher ? 5 : 7, max(0, phase))
        let progress = min(1, max(0, (p - 1) / (role == .pitcher ? 3 : 4)))
        let ease = progress * progress * (3 - 2 * progress)
        return CGPoint(
            x: role == .pitcher ? (hand == "left" ? 1 : -1) * 0.012 * ease : 0,
            y: role == .pitcher ? -0.014 * ease : 0.009 * ease)
    }
    /// 해당 카메라의 유효 프레임을 받아 원화 기준점을 설정하고 좌투를 반전한다.
    init(role: PlayerRole, frame: Int, hand throwingHand: String) {
        if role == .pitcher {
            let pivots = [
                CGPoint(x: 0.70, y: 0.90), CGPoint(x: 0.57, y: 0.90), CGPoint(x: 0.74, y: 0.90),
                CGPoint(x: 0.41, y: 0.85), CGPoint(x: 0.40, y: 0.85), CGPoint(x: 0.42, y: 0.85),
            ]
            let hands = [
                CGPoint(x: 0.42, y: 0.56), CGPoint(x: 0.38, y: 0.52), CGPoint(x: 0.72, y: 0.37),
                CGPoint(x: 0.78, y: 0.11), CGPoint(x: 0.50, y: 0.65), CGPoint(x: 0.40, y: 0.55),
            ]
            width = 0.52
            pivot = pivots[frame]
            hand = hands[frame]
            // 2번 자세의 앞발(x=.29) 착지 지점을 릴리스까지 유지해 발이 뒤로 밀리지 않게 한다.
            foot = CGPoint(x: frame < 3 ? 0.76 : 0.526, y: frame < 3 ? 0.870 : 0.850)
        } else {
            width = 0.20
            let pivots = [0.5, 0.53, 0.65, 0.65, 0.55, 0.52, 0.50, 0.5]
            pivot = CGPoint(x: pivots[frame], y: 0.965)
            hand = frame == 4 ? CGPoint(x: 0.35, y: 0.08) : CGPoint(x: 0.35, y: 0.42)
            foot = CGPoint(x: 0.50, y: 0.375)
        }
        if throwingHand == "left" {
            if role == .pitcher { self.foot.x = 1 - self.foot.x }
            self.pivot = CGPoint(x: 1 - pivot.x, y: pivot.y)
            self.hand = CGPoint(x: 1 - hand.x, y: hand.y)
        }
    }
}
