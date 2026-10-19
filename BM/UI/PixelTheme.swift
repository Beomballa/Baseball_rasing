import SwiftUI

enum GameTheme {
    static let navy = Color(hex: 0x14283f)
    static let gold = Color(hex: 0xecc66b)
    static let green = Color(hex: 0x126b4c)
    static let paper = Color(hex: 0xf0f4ef)
    static let muted = Color(hex: 0x526478)
}

extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct GameButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(!isEnabled ? GameTheme.muted : (secondary ? GameTheme.navy : .white))
            .background(!isEnabled ? GameTheme.paper : (secondary ? GameTheme.gold : GameTheme.green))
            .overlay(Rectangle().strokeBorder(GameTheme.navy.opacity(isEnabled ? 1 : 0.25), lineWidth: 2))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct GamePanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(.headline, design: .monospaced)).foregroundStyle(GameTheme.navy)
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white).overlay(Rectangle().strokeBorder(GameTheme.navy.opacity(0.2), lineWidth: 2))
    }
}

struct StatRow: View {
    let name: String
    let value: Double
    var body: some View {
        HStack(spacing: 12) {
            Text(name).frame(width: 72, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(GameTheme.navy.opacity(0.1))
                    Rectangle().fill(GameTheme.green)
                        .frame(width: max(0, geometry.size.width) * min(100, max(0, value)) / 100)
                }
            }.frame(height: 10).accessibilityHidden(true)
            Text(value.formatted(.number.precision(.fractionLength(0...4))))
                .monospacedDigit().frame(minWidth: 28, alignment: .trailing)
        }.font(.subheadline).accessibilityElement(children: .combine)
    }
}
