import SwiftUI

/// Original pixel shield, bat/diamond motifs, and school number; no borrowed school artwork.
struct SchoolCrest: View {
    let school: School
    private let colors = [0x2773a2, 0x996045, 0x39785e, 0x765b92, 0xa24b53, 0x457b86, 0x626d35, 0x8c6638]
    var body: some View {
        Canvas { context, size in
            let u = floor(min(size.width / 24, size.height / 28))
            let origin = CGPoint(x: (size.width - 24*u)/2, y: (size.height - 28*u)/2)
            func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Int) {
                context.fill(Path(CGRect(x: origin.x + Double(x)*u, y: origin.y + Double(y)*u,
                                         width: Double(w)*u, height: Double(h)*u)), with: .color(Color(hex: color)))
            }
            let n = school.crestNumber
            let color = colors[n % colors.count]
            box(2, 1, 20, 20, 0x101f32); box(5, 21, 14, 3, 0x101f32); box(8, 24, 8, 2, 0x101f32)
            box(3, 2, 18, 18, 0xf2d287); box(6, 20, 12, 3, 0xf2d287); box(9, 23, 6, 2, 0xf2d287)
            box(5, 4, 14, 14, color); box(7, 18, 10, 3, color)
            switch (n / 8) % 3 {
            case 0:
                for i in 0..<5 { box(7+i*2, 6+i*2, 2, 3, 0xfff5d7); box(15-i*2, 6+i*2, 2, 3, 0xfff5d7) }
            case 1:
                for i in 0..<4 { box(11-i, 5+i*2, 2+i*2, 2, 0xfff5d7); box(8+i, 13+i, 8-i*2, 1, 0xfff5d7) }
                box(10, 8, 4, 6, color)
            default:
                box(10, 5, 4, 11, 0xfff5d7); box(7, 8, 10, 4, 0xfff5d7)
                box(8, 7, 8, 2, 0xfff5d7); box(8, 12, 8, 2, 0xfff5d7)
                box(11, 9, 2, 3, color)
            }
            // Six identity pixels keep all 50 shields distinct, even at one palette.
            for bit in 0..<6 { box(6+bit*2, 19, 1, 2, n & (1 << bit) == 0 ? color : 0xfff5d7) }
        }.accessibilityLabel(school.name + " 창작 교표")
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
