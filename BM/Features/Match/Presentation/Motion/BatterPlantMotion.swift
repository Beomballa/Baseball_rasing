import SpriteKit

// The lifted front leg in the authored load pose settles before torso/barrel contact.
// Cache a small lower-body-only mesh; head, arms and bat are never bent or cross-faded.
@MainActor enum BatterPlantMotion {
    private static let frames: [SKWarpGeometryGrid] = (0...24).map { step in
        let columns = 16, rows = 16
        let progress = Float(step) / 24
        let ease = progress * progress * (3 - 2 * progress)
        var source: [SIMD2<Float>] = [], destination: [SIMD2<Float>] = []
        for row in 0...rows { for column in 0...columns {
            let x = Float(column) / Float(columns), y = Float(row) / Float(rows)
            let fromTop = 1 - y
            let side = max(0, min(1, (x - 0.43) / 0.09)) * max(0, min(1, (0.76 - x) / 0.08))
            let leg = max(0, min(1, (fromTop - 0.60) / 0.18)) * max(0, min(1, (0.99 - fromTop) / 0.10))
            source.append(SIMD2(x, y))
            destination.append(SIMD2(x + 0.012 * side * leg * ease, y - 0.10 * side * leg * ease))
        }}
        return SKWarpGeometryGrid(columns: columns, rows: rows, sourcePositions: source, destinationPositions: destination)
    }
    static func geometry(progress: Double) -> SKWarpGeometryGrid {
        frames[Int((min(1, max(0, progress)) * 24).rounded())]
    }
}
