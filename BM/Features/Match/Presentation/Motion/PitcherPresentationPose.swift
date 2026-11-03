import CoreGraphics

// Atlas pivots are presentation metadata. The rubber stays fixed for both hands and batter sides.
struct PitcherPresentationPose {
    let width: Double
    private(set) var pivot: CGPoint
    private(set) var hand: CGPoint
    private(set) var foot: CGPoint
    static func travel(role: PlayerRole, phase: Double, hand: String) -> CGPoint {
        // Forward drift stays continuous at pose boundaries; front-foot re-anchoring is in the atlas metadata.
        let p = min(role == .pitcher ? 5 : 7, max(0, phase))
        let progress = min(1, max(0, (p - 1) / (role == .pitcher ? 3 : 4)))
        let ease = progress * progress * (3 - 2 * progress)
        return CGPoint(x: role == .pitcher ? (hand == "left" ? 1 : -1) * 0.012 * ease : 0,
                       y: role == .pitcher ? -0.014 * ease : 0.009 * ease)
    }
    init(role: PlayerRole, frame: Int, hand throwingHand: String) {
        if role == .pitcher {
            let pivots = [CGPoint(x:0.70,y:0.90),CGPoint(x:0.57,y:0.90),CGPoint(x:0.74,y:0.90),CGPoint(x:0.41,y:0.85),CGPoint(x:0.40,y:0.85),CGPoint(x:0.42,y:0.85)]
            let hands = [CGPoint(x:0.42,y:0.56),CGPoint(x:0.38,y:0.52),CGPoint(x:0.72,y:0.37),CGPoint(x:0.78,y:0.11),CGPoint(x:0.50,y:0.65),CGPoint(x:0.40,y:0.55)]
            width = 0.52; pivot = pivots[frame]; hand = hands[frame]
            // The stride foot in frame 2 is x=.29 while the pivot foot is x=.74.
            // Carry that planted location into release instead of stepping backward on the next frame.
            foot = CGPoint(x: frame < 3 ? 0.76 : 0.526, y: frame < 3 ? 0.870 : 0.850)
        } else {
            width = 0.20
            let pivots = [0.5,0.53,0.65,0.65,0.55,0.52,0.50,0.5]
            pivot = CGPoint(x:pivots[frame],y:0.965)
            hand = frame == 4 ? CGPoint(x:0.35,y:0.08):CGPoint(x:0.35,y:0.42)
            foot = CGPoint(x:0.50,y:0.375)
        }
        if throwingHand == "left" {
            if role == .pitcher { self.foot.x = 1 - self.foot.x }
            self.pivot = CGPoint(x:1-pivot.x,y:pivot.y)
            self.hand = CGPoint(x:1-hand.x,y:hand.y)
        }
    }
}
