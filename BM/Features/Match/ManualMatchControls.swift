import SwiftUI

struct MatchTimingGauge: View {
    let phase: Double
    let center: Double
    let good: Double
    let perfect: Double
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold())
            GeometryReader { size in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: 0x5b5034))
                    Rectangle().fill(Color(hex: 0x73b890))
                        .frame(width: size.size.width * good * 2).offset(x: size.size.width * (center - good))
                    Rectangle().fill(GameTheme.gold)
                        .frame(width: size.size.width * perfect * 2).offset(x: size.size.width * (center - perfect))
                    Rectangle().fill(Color(hex: 0xfff4ce)).frame(width: 4)
                        .offset(x: max(0, size.size.width - 4) * phase)
                }
            }.frame(height: 22)
                .overlay(Rectangle().strokeBorder(Color(hex: 0x9fb7bf), lineWidth: 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + " · 초록 구간 GOOD, 노란 구간 PERFECT")
    }
}

struct BattingAimZone: View {
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var showsGrid = true
    var body: some View {
        GeometryReader { size in
            ZStack {
                Color.clear
                if showsGrid {
                    Rectangle().fill(GameTheme.paper.opacity(0.08))
                    Rectangle().strokeBorder(Color(hex: 0x9fb7bf), lineWidth: 2)
                        .frame(width: size.size.width * 0.6, height: size.size.height * 0.6)
                    Path { path in
                        for part in [0.4, 0.6] {
                            path.move(to: CGPoint(x: size.size.width * part, y: size.size.height * 0.2))
                            path.addLine(to: CGPoint(x: size.size.width * part, y: size.size.height * 0.8))
                            path.move(to: CGPoint(x: size.size.width * 0.2, y: size.size.height * part))
                            path.addLine(to: CGPoint(x: size.size.width * 0.8, y: size.size.height * part))
                        }
                    }.stroke(Color(hex: 0xf3edcf).opacity(0.4), lineWidth: 1)
                }
                if showsGrid {
                    Rectangle().strokeBorder(GameTheme.gold,lineWidth:3).frame(width:16,height:16)
                        .position(x:size.size.width*x,y:size.size.height*y)
                } else {
                    Canvas { context,canvas in
                        let c=CGPoint(x:canvas.width*x,y:canvas.height*y)
                        for dx in [-1.0,1] {for dy in [-1.0,1] {
                            var corner=Path()
                            corner.move(to:CGPoint(x:c.x+dx*3,y:c.y+dy*6))
                            corner.addLine(to:CGPoint(x:c.x+dx*6,y:c.y+dy*6))
                            corner.addLine(to:CGPoint(x:c.x+dx*6,y:c.y+dy*3))
                            context.stroke(corner,with:.color(GameTheme.gold),lineWidth:2)
                        }}
                        context.fill(Path(CGRect(x:c.x-1,y:c.y-1,width:2,height:2)),with:.color(GameTheme.paper))
                    }.allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !locked else { return }
                x = min(1, max(0, value.location.x / size.size.width))
                y = min(1, max(0, value.location.y / size.size.height))
            })
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("타격 포인트")
        .accessibilityValue("가로 \(Int(x * 100)), 세로 \(Int(y * 100))")
        .accessibilityAction(named: "왼쪽") { if !locked { x = max(0, x - 0.1) } }
        .accessibilityAction(named: "오른쪽") { if !locked { x = min(1, x + 0.1) } }
        .accessibilityAction(named: "위") { if !locked { y = max(0, y - 0.1) } }
        .accessibilityAction(named: "아래") { if !locked { y = min(1, y + 0.1) } }
        .accessibilityIdentifier("battingAimZone")
    }
}
