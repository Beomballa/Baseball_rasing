import SwiftUI

struct HomeRadarChart: View {
    let values: [HomeAbilityValue]
    @Environment(\.dynamicTypeSize) private var typeSize
    private var hasBaseline: Bool { values.allSatisfy { $0.initial != nil } }
    var body: some View {
        VStack(spacing: 8) {
            if typeSize.isAccessibilitySize {
                ForEach(values) { HomeGrowthRow(value: $0) }
            } else {
                GeometryReader { geometry in
                    let size = geometry.size
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * 0.31
                    ZStack {
                        Canvas { context, _ in
                            func point(_ index: Int, _ value: Double) -> CGPoint {
                                let angle = Double(index) * .pi / 3 - .pi / 2
                                let distance = radius * min(100, max(0, value)) / 100
                                return CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                            }
                            func polygon(_ scores: [Double]) -> Path {
                                Path { path in
                                    for (index, value) in scores.enumerated() {
                                        let p = point(index, value)
                                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                                    }
                                    path.closeSubpath()
                                }
                            }
                            for level in [25.0, 50, 75, 100] {
                                context.stroke(polygon(Array(repeating: level, count: 6)), with: .color(GameTheme.boardLine.opacity(0.5)), lineWidth: 1)
                            }
                            for index in 0..<6 {
                                var line = Path(); line.move(to: center); line.addLine(to: point(index, 100))
                                context.stroke(line, with: .color(GameTheme.boardLine.opacity(0.4)), lineWidth: 1)
                            }
                            let current = polygon(values.map(\.current))
                            context.fill(current, with: .color(GameTheme.growth.opacity(0.16)))
                            context.stroke(current, with: .color(GameTheme.growth), lineWidth: 2)
                            if hasBaseline {
                                context.stroke(polygon(values.compactMap(\.initial)), with: .color(GameTheme.gold), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                            for (index, value) in values.enumerated() {
                                let p = point(index, value.current)
                                context.fill(Path(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(GameTheme.growth))
                            }
                        }
                        ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                            let angle = Double(index) * .pi / 3 - .pi / 2
                            VStack(spacing: 2) {
                                Text(value.label).foregroundStyle(GameTheme.boardMuted)
                                Text(value.current.formatted(.number.precision(.fractionLength(1)))).bold().foregroundStyle(GameTheme.boardInk)
                            }.font(.caption).monospacedDigit().frame(width: 88)
                                .position(x: center.x + cos(angle) * radius * 1.38, y: center.y + sin(angle) * radius * 1.38)
                        }
                    }
                }.frame(height: 250)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("주요 능력치 그래프, 최대 100. " + values.map { "\($0.label) \($0.current.formatted(.number.precision(.fractionLength(1))))" }.joined(separator: ", "))
                    .accessibilityIdentifier("homeAbilityRadar")
            }
            HStack(spacing: 16) {
                Text("■ 현재").foregroundStyle(GameTheme.growth)
                if hasBaseline { Text("┄ 시작").foregroundStyle(GameTheme.gold) }
                Spacer(); Text("MAX 100").foregroundStyle(GameTheme.boardMuted)
            }.font(.caption.monospaced())
        }
    }
}

struct HomeGrowthRow: View {
    let value: HomeAbilityValue
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(value.label).font(.subheadline.bold())
                Spacer()
                Text(value.current.formatted(.number.precision(.fractionLength(1)))).font(.subheadline.monospaced().bold())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(GameTheme.board)
                    Rectangle().fill(GameTheme.growth.opacity(0.8)).frame(width: max(0, geometry.size.width) * min(100, max(0, value.current)) / 100)
                    if let initial = value.initial {
                        Rectangle().fill(GameTheme.gold).frame(width: 2).offset(x: max(0, geometry.size.width - 2) * min(100, max(0, initial)) / 100)
                    }
                }.overlay(Rectangle().strokeBorder(GameTheme.boardLine.opacity(0.6)))
            }.frame(height: 7).accessibilityHidden(true)
            if let initial = value.initial, let gain = value.growth {
                HStack {
                    Text("시작 \(initial, specifier: "%.1f")")
                    Spacer()
                    Text(gain == 0 ? "변화 없음" : "\(gain > 0 ? "+" : "")\(gain.formatted(.number.precision(.fractionLength(1))))")
                        .foregroundStyle(gain > 0 ? GameTheme.growth : GameTheme.boardMuted)
                }.font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
        }.foregroundStyle(GameTheme.boardInk)
            .accessibilityElement(children: .combine).accessibilityIdentifier(value.id)
    }
}

struct HomeDetailButton: View {
    let title: String
    @Binding var expanded: Bool
    var identifier: String
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer(); Text(expanded ? "−" : "+").font(.title3.monospaced().bold())
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(GameTheme.gold)
            .accessibilityIdentifier(identifier).accessibilityValue(expanded ? "펼침" : "접힘")
    }
}
