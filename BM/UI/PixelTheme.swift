import SwiftUI

enum GameTheme {
    static let navy = Color(hex: 0x14283f)
    static let gold = Color(hex: 0xecc66b)
    static let green = Color(hex: 0x126b4c)
    static let paper = Color(hex: 0xf0f4ef)
    static let muted = Color(hex: 0x526478)
    static let board = Color(hex: 0x17344e)
    static let boardPanel = Color(hex: 0x122b3d)
    static let boardLine = Color(hex: 0x73929e)
    static let boardInk = Color(hex: 0xf2edcf)
    static let boardMuted = Color(hex: 0xb9ccd2)
    static let growth = Color(hex: 0x91e6b8)
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
    var onBoard = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced, weight: .bold))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(onBoard ? (isEnabled ? GameTheme.boardInk : GameTheme.boardMuted) : (!isEnabled ? GameTheme.muted : (secondary ? GameTheme.navy : .white)))
            .background(onBoard ? (isEnabled ? (secondary ? Color(hex: 0x334c50) : Color(hex: 0x307855)) : GameTheme.boardPanel) : (!isEnabled ? GameTheme.paper : (secondary ? GameTheme.gold : GameTheme.green)))
            .overlay(Rectangle().strokeBorder(onBoard ? (isEnabled && secondary ? GameTheme.gold : GameTheme.boardLine.opacity(isEnabled ? 1 : 0.45)) : GameTheme.navy.opacity(isEnabled ? 1 : 0.25), lineWidth: 2))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.18)).frame(height: 3).allowsHitTesting(false) }
            .contentTransition(.identity)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct GamePanel<Content: View>: View {
    let title: String
    var onBoard = false
    var contentSpacing: CGFloat?
    @ViewBuilder var content: Content
    init(title: String, onBoard: Bool = false, contentSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.onBoard = onBoard; self.contentSpacing = contentSpacing; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing ?? (onBoard ? 8 : 14)) {
            Text(title).font(.system(.headline, design: .monospaced)).foregroundStyle(onBoard ? GameTheme.boardInk : GameTheme.navy)
            content
        }
        .padding(onBoard ? 12 : 16).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(onBoard ? GameTheme.boardInk : GameTheme.navy)
        .background(onBoard ? GameTheme.boardPanel : .white)
        .overlay(Rectangle().strokeBorder(onBoard ? GameTheme.boardLine : GameTheme.navy.opacity(0.2), lineWidth: 2))
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
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .monospacedDigit().frame(minWidth: 28, alignment: .trailing)
        }.font(.subheadline).accessibilityElement(children: .combine)
    }
}
