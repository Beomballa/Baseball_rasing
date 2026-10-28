import SwiftUI

/// Shared, authored pixel data keeps native icons and design exports identical.
struct SchoolCrest: View {
    let school: School
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        Canvas { context, size in
            let unit = floor(min(size.width, size.height) / 32 * displayScale) / displayScale
            let origin = CGPoint(x: (size.width - 32*unit)/2, y: (size.height - 32*unit)/2)
            func box(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: Int) {
                context.fill(Path(CGRect(x: origin.x + Double(x)*unit, y: origin.y + Double(y)*unit,
                                         width: Double(width)*unit, height: Double(height)*unit)), with: .color(Color(hex: color)))
            }
            if let emblem = school.emblem, emblem.isValid {
                for (y, row) in emblem.pixels.enumerated() {
                    let pixels = Array(row.utf8)
                    var x = 0
                    while x < pixels.count {
                        let color = pixels[x], start = x
                        while x < pixels.count && pixels[x] == color { x += 1 }
                        if color != 48 { box(start, y, x-start, 1, emblem.palette[Int(color-48)]) }
                    }
                }
            } else {
                // Old three-field/custom school data has no emblem; retain a neutral baseball.
                for (x, y, w, h) in [(10, 4, 12, 24), (6, 8, 20, 16), (4, 12, 24, 8)] { box(x, y, w, h, 0xf2e9ce) }
                for y in stride(from: 8, through: 24, by: 4) { box(9, y, 3, 1, 0x9b4545); box(20, y, 3, 1, 0x9b4545) }
            }
        }.accessibilityLabel(school.name + " 교표 · " + (school.emblem?.symbol ?? "기본 야구공"))
    }
}

struct SchoolReputationLabels: View {
    let school: School
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { labels }
            VStack(alignment: .leading, spacing: 6) { labels }
        }
    }
    @ViewBuilder private var labels: some View {
        Text(school.reputation).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 4)
            .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.boardLine))
        if school.openingWorldChampion {
            Text("2025 우승 · 설정").font(.caption.bold()).foregroundStyle(GameTheme.gold)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.gold))
        }
    }
}

struct PixelPlayer: View {
    let appearance: PlayerAppearance
    var body: some View {
        Canvas { context, size in
            let unit = floor(min(size.width / 16, size.height / 20))
            let origin = CGPoint(x: (size.width - unit * 16) / 2, y: (size.height - unit * 20) / 2)
            func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: Int) {
                context.fill(Path(CGRect(x: origin.x + Double(x) * unit, y: origin.y + Double(y) * unit,
                                         width: Double(w) * unit, height: Double(h) * unit)), with: .color(Color(hex: hex)))
            }
            let skin = PlayerAppearance.skinColors[appearance.skin]
            let hair = PlayerAppearance.hairColors[appearance.hair]
            let kit = PlayerAppearance.kitColors[appearance.kit]
            box(4, 1, 8, 7, 0x14283f); box(5, 2, 6, 6, skin)
            box(4, 1, 8, 2, hair)
            if appearance.hairStyle == 1 { box(4, 3, 2, 2, hair) }
            if appearance.hairStyle == 2 { box(3, 1, 2, 3, hair); box(11, 1, 2, 3, hair) }
            box(6, 4, 1, 1, 0x14283f); box(9, 4, 1, 1, 0x14283f)
            if appearance.expression == 1 { box(6, 3, 2, 1, hair) }
            if appearance.expression == 2 { box(7, 6, 2, 1, 0x85442e) }
            box(4, 8, 8, 7, kit); box(7, 8, 2, 6, 0xf4f0db)
            box(2, 9, 2, 5, skin); box(12, 9, 2, 5, skin)
            box(4, 15, 3, 3, 0xe3e6d9); box(9, 15, 3, 3, 0xe3e6d9)
            box(3, 18, 4, 2, 0x14283f); box(9, 18, 4, 2, 0x14283f)
        }.accessibilityLabel("선택한 도트 선수 외형")
    }
}
