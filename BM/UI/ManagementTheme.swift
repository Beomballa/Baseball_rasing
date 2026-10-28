import SwiftUI

/// Semantic roles map to design/v2/native-token-map.json; existing gameplay values stay intact.
enum ManagementTheme {
    static let version = "1.0.0"
    enum Spatial {
        static let canvas = Color(hex: 0x102e42)
        static let onCanvas = Color(hex: 0xf2e9ce)
        static let wood = Color(hex: 0x442c1e)
        static let screenInset: CGFloat = 12
        static let facilityMaxWidth: CGFloat = 145
        static let shortContentHeight: CGFloat = 680
    }
    enum Palette {
        static let canvas = GameTheme.board
        static let panel = GameTheme.boardPanel
        static let paper = GameTheme.boardInk
        static let control = Color(hex: 0x203e57)
        static let ink = GameTheme.navy
        static let onDark = GameTheme.boardInk
        static let secondary = GameTheme.boardMuted
        static let secondaryLight = GameTheme.muted
        static let gold = GameTheme.gold
        static let growth = GameTheme.growth
        static let error = Color(hex: 0xffb4a8)
        static let border = GameTheme.boardLine
    }
    enum Space {
        static let micro: CGFloat = 4
        static let inline: CGFloat = 8
        static let compact: CGFloat = 12
        static let screen: CGFloat = 16
        static let section: CGFloat = 24
        static let feature: CGFloat = 32
    }
    enum Control {
        static let hit: CGFloat = 44
        static let primaryHeight: CGFloat = 56
        static let secondaryHeight: CGFloat = 48
        static let border: CGFloat = 2
        static let corner: CGFloat = 4
        static let depth: CGFloat = 2
        static let pressDuration = 0.12
        static let tabHeight: CGFloat = 64
        static let tabIcon: CGFloat = 28
        static let avatar: CGFloat = 40
    }
}

enum ManagementType {
    case screenTitle, sectionTitle, body, label, helper, metric
    var size: CGFloat {
        switch self {
        case .screenTitle: 22
        case .sectionTitle: 20
        case .body: 17
        case .label: 15
        case .helper: 14
        case .metric: 24
        }
    }
    var weight: Font.Weight {
        switch self {
        case .screenTitle, .metric: .bold
        case .sectionTitle, .label: .semibold
        case .body, .helper: .regular
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .screenTitle: .title2
        case .sectionTitle: .title3
        case .body: .body
        case .label: .subheadline
        case .helper: .footnote
        case .metric: .title
        }
    }
}

private struct ManagementFont: ViewModifier {
    let type: ManagementType
    @ScaledMetric private var size: CGFloat
    init(_ type: ManagementType) {
        self.type = type
        _size = ScaledMetric(wrappedValue: type.size, relativeTo: type.relativeTo)
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: type.weight))
    }
}

extension View {
    func managementFont(_ type: ManagementType) -> some View { modifier(ManagementFont(type)) }
}

struct ManagementStepFrame: InsettableShape {
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = min(ManagementTheme.Control.corner, min(r.width, r.height) / 4)
        return Path { p in
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLines([
                CGPoint(x: r.maxX - c, y: r.minY), CGPoint(x: r.maxX - c, y: r.minY + c / 2),
                CGPoint(x: r.maxX, y: r.minY + c / 2), CGPoint(x: r.maxX, y: r.maxY - c),
                CGPoint(x: r.maxX - c / 2, y: r.maxY - c), CGPoint(x: r.maxX - c / 2, y: r.maxY),
                CGPoint(x: r.minX + c, y: r.maxY), CGPoint(x: r.minX + c, y: r.maxY - c / 2),
                CGPoint(x: r.minX, y: r.maxY - c / 2), CGPoint(x: r.minX, y: r.minY + c),
                CGPoint(x: r.minX + c / 2, y: r.minY + c), CGPoint(x: r.minX + c / 2, y: r.minY)
            ])
            p.closeSubpath()
        }
    }
    func inset(by amount: CGFloat) -> ManagementStepFrame {
        var frame = self; frame.insetAmount += amount; return frame
    }
}
