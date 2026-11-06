import SpriteKit

/// 같은 시계에서 준비→로드→착지→접촉→마무리를 전진시킨다. 판정 시각은 호출자가 유지한다.
struct BatterSequencePose {
    enum Stage: String { case ready, load, plant, turn, contact, followThrough }
    let stage: Stage
    let frame: Int
    let plant: Double
    let travel: Double
    init(phase: Double) {
        let p=min(3,max(0,phase))
        stage=p < 0.55 ? .ready:p < 1.05 ? .load:p < 1.75 ? .plant:p < 2 ? .turn:p < 2.25 ? .contact:.followThrough
        frame=p < 0.55 ? 0:p < 2 ? 1:p < 2.25 ? 2:3
        plant=min(1,max(0,(p-1.05)/0.70))
        travel=p < 1 ? -0.012*p:p < 2 ? -0.012*(2-p):0.012*(p-2)
    }
}

/// 앞발 착지용 하체 격자를 한 번 생성해 재사용한다. 머리·팔·배트는 변형하지 않는다.
@MainActor enum BatterPlantMotion {
    private static let frames: [SKWarpGeometryGrid] = (0...24).map { step in
        let columns = 16
        let rows = 16
        let progress = Float(step) / 24
        let ease = progress * progress * (3 - 2 * progress)
        var source: [SIMD2<Float>] = []
        var destination: [SIMD2<Float>] = []
        for row in 0...rows {
            for column in 0...columns {
                let x = Float(column) / Float(columns)
                let y = Float(row) / Float(rows)
                let fromTop = 1 - y
                let side = max(0, min(1, (x - 0.43) / 0.09)) * max(0, min(1, (0.76 - x) / 0.08))
                let leg = max(0, min(1, (fromTop - 0.60) / 0.18)) * max(0, min(1, (0.99 - fromTop) / 0.10))
                source.append(SIMD2(x, y))
                destination.append(SIMD2(x + 0.012 * side * leg * ease, y - 0.10 * side * leg * ease))
            }
        }
        return SKWarpGeometryGrid(
            columns: columns, rows: rows, sourcePositions: source, destinationPositions: destination)
    }
    /// 진행률을 0~1로 제한해 미리 만든 25단계 착지 격자 중 하나를 반환한다.
    static func geometry(progress: Double) -> SKWarpGeometryGrid {
        frames[Int((min(1, max(0, progress)) * 24).rounded())]
    }
}
