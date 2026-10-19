import SwiftUI

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
