import SwiftUI

enum ManagementButtonVariant { case primary, secondary, paper, destructive }

struct ManagementButtonStyle: ButtonStyle {
    var variant = ManagementButtonVariant.primary
    var selected = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ManagementPixelFont.readable(compact ? .label : .body))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, compact ? ManagementTheme.Space.inline : ManagementTheme.Space.screen)
            .padding(.vertical, compact ? ManagementTheme.Space.inline : ManagementTheme.Space.compact)
            .frame(maxWidth: .infinity)
            .managementButtonChrome(
                variant: configuration.role == .destructive ? .destructive : variant,
                selected: selected, pressed: configuration.isPressed, enabled: enabled, focused: focused,
                minHeight: compact ? ManagementTheme.Control.hit :
                    (variant == .primary ? ManagementTheme.Control.primaryHeight : ManagementTheme.Control.secondaryHeight)
            )
    }
}

private struct ManagementButtonColors {
    let fill: Color
    let ink: Color
    let edge: Color
    let highlight: Color
    let shade: Color

    private init(_ fill: Int, _ ink: Int, _ edge: Int, _ highlight: Int, _ shade: Int) {
        self.fill = Color(hex: fill)
        self.ink = Color(hex: ink)
        self.edge = Color(hex: edge)
        self.highlight = Color(hex: highlight)
        self.shade = Color(hex: shade)
    }

    static let primary = Self(0xedc46f, 0x253b37, 0x644d27, 0xffe2a0, 0xaa823a)
    static let secondary = Self(0x294b44, 0xf6f0d6, 0x112f2c, 0x56776a, 0x112c29)
    static let paper = Self(0xe3e4d6, 0x27413c, 0x758476, 0xf9faea, 0xa8b4a1)
    static let destructive = Self(0x814637, 0xfff0dd, 0x4d2921, 0xae6850, 0x5b3029)
    static let disabled = Self(0xc8cbbb, 0x46564b, 0x9ca797, 0xe0e2d6, 0xa8b1a0)
}

private struct ManagementButtonChrome: ViewModifier {
    let variant: ManagementButtonVariant
    let selected: Bool
    let pressed: Bool
    let enabled: Bool
    let focused: Bool
    let minHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: ManagementButtonColors {
        guard enabled else { return .disabled }
        if selected { return .primary }
        switch variant {
        case .primary: return .primary
        case .secondary: return .secondary
        case .paper: return .paper
        case .destructive: return .destructive
        }
    }

    func body(content: Content) -> some View {
        let isPressed = enabled && pressed
        let shape = ManagementStepFrame()
        content
            .frame(minWidth: ManagementTheme.Control.hit, minHeight: minHeight)
            .foregroundStyle(colors.ink)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(colors.fill)
                    Rectangle().fill(isPressed ? colors.shade : colors.highlight).frame(height: 4)
                    if !isPressed {
                        VStack {
                            Spacer(minLength: 0)
                            Rectangle().fill(colors.shade).frame(height: 4)
                        }
                    }
                }.clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(colors.edge, lineWidth: ManagementTheme.Control.border)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay {
                if focused && enabled {
                    shape.inset(by: ManagementTheme.Control.border)
                        .strokeBorder(Color(hex: 0x2f757c), lineWidth: 2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .offset(y: isPressed && !reduceMotion ? ManagementTheme.Control.depth : 0)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: ManagementTheme.Control.pressDuration), value: isPressed)
    }
}

extension View {
    func managementButtonChrome(variant: ManagementButtonVariant, selected: Bool = false,
                                pressed: Bool, enabled: Bool, focused: Bool = false,
                                minHeight: CGFloat? = nil) -> some View {
        modifier(ManagementButtonChrome(variant: variant, selected: selected, pressed: pressed,
                                        enabled: enabled, focused: focused,
                                        minHeight: max(ManagementTheme.Control.hit, minHeight ?? 0)))
    }
}

enum ManagementActionState: Equatable {
    case ready, locked(String), working
    var enabled: Bool { self == .ready }
    var explanation: String? {
        switch self {
        case .ready: nil
        case .locked(let reason): reason
        case .working: "처리 중 · 같은 요청을 다시 보낼 수 없습니다"
        }
    }
}

struct ManagementActionButton: View {
    let title: String
    var state: ManagementActionState = .ready
    var variant: ManagementButtonVariant = .primary
    var identifier = ""
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            Button(action: action) {
                HStack(spacing: ManagementTheme.Space.inline) {
                    if state == .working { ProgressView().tint(ManagementTheme.Palette.onDark).accessibilityHidden(true) }
                    Text(title)
                }
            }
            .buttonStyle(ManagementButtonStyle(variant: variant)).disabled(!state.enabled)
            .accessibilityIdentifier(identifier)
            if let explanation = state.explanation {
                Text(explanation).managementFont(.helper).foregroundStyle(ManagementTheme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum ManagementSurface { case board, paper }

struct ManagementPanel<Content: View>: View {
    let title: String
    var surface = ManagementSurface.board
    @ViewBuilder let content: Content
    init(_ title: String, surface: ManagementSurface = .board, @ViewBuilder content: () -> Content) {
        self.title = title; self.surface = surface; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            Text(title).managementFont(.sectionTitle).fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(ManagementTheme.Space.screen).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(surface == .board ? ManagementTheme.Palette.onDark : ManagementTheme.Palette.ink)
        .background(surface == .board ? ManagementTheme.Palette.panel : ManagementTheme.Palette.paper, in: ManagementStepFrame())
        .overlay { ManagementStepFrame().strokeBorder(ManagementTheme.Palette.border, lineWidth: ManagementTheme.Control.border) }
    }
}

struct ManagementMetricRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ManagementTheme.Space.inline) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ManagementTheme.Space.inline)
            Text(value).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }.managementFont(.label).accessibilityElement(children: .combine)
    }
}

struct ManagementProgressValue {
    let current: Double?
    let target: Double
    var ratio: Double? {
        guard let current, current.isFinite, target.isFinite, target > 0 else { return nil }
        return min(1, max(0, current / target))
    }
    var display: String {
        guard let current, current.isFinite, target.isFinite, target > 0 else { return "미집계" }
        return current.formatted(.number.precision(.fractionLength(0...1))) + " / " + target.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct ManagementProgress: View {
    let title: String
    let value: ManagementProgressValue
    var color = ManagementTheme.Palette.gold
    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            ManagementMetricRow(title: title, value: value.display)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(ManagementTheme.Palette.control)
                    if let ratio = value.ratio {
                        Rectangle().fill(color).frame(width: geometry.size.width * ratio)
                    }
                }
            }.frame(height: ManagementTheme.Space.inline).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(title + ", " + value.display)
    }
}

struct ManagementPlayerSummary {
    let name: String
    let detail: String
    let date: String
    let fatigue: Double
    let action: String
    let appearance: PlayerAppearance
    var secondaryDetail: String? = nil
}

struct ManagementPlayerHeader: View {
    let summary: ManagementPlayerSummary
    var nameIdentifier = "managementPlayerName"
    var detailIdentifier = "managementPlayerDetail"
    var metadataIdentifier = "managementMetadata"
    var dateIdentifier = "managementDate"
    var actionIdentifier = "managementAction"
    var fatigueIdentifier = "managementFatigue"
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            HStack(alignment: .top, spacing: ManagementTheme.Space.compact) {
                PixelPlayer(appearance: summary.appearance)
                    .frame(width: ManagementTheme.Control.avatar, height: ManagementTheme.Control.avatar)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                    Text(summary.name).managementFont(.screenTitle).accessibilityIdentifier(nameIdentifier)
                    Text(summary.detail).managementFont(.label).foregroundStyle(ManagementTheme.Palette.secondary).accessibilityIdentifier(detailIdentifier)
                    if let detail = summary.secondaryDetail {
                        Text(detail).managementFont(.helper).foregroundStyle(ManagementTheme.Palette.secondary).accessibilityIdentifier(metadataIdentifier)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: ManagementTheme.Space.micro)) : AnyLayout(HStackLayout(spacing: ManagementTheme.Space.inline))) {
                Text(summary.date).monospacedDigit().fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(dateIdentifier)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(summary.action).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(actionIdentifier)
            }.managementFont(.helper).foregroundStyle(ManagementTheme.Palette.secondary)
            ManagementProgress(title: "피로", value: ManagementProgressValue(current: summary.fatigue, target: 100))
                .accessibilityIdentifier(fatigueIdentifier)
        }
        .padding(ManagementTheme.Space.screen)
        .foregroundStyle(ManagementTheme.Palette.onDark).background(ManagementTheme.Palette.canvas)
    }
}


struct ManagementFileHeader: View {
    let eyebrow: String
    let title: String
    let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            Text(eyebrow).managementFont(.label).foregroundStyle(GameTheme.gold)
            Text(title).font(ManagementPixelFont.readable(.screenTitle)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(note).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(GameTheme.boardInk)
            .padding(.bottom, ManagementTheme.Space.inline)
            .accessibilityIdentifier("managementFileHeader")
    }
}


/// Both values come from fixed reports, never from today's mutable player model.
struct ManagementObservationChange: View {
    let title: String
    let before: Double
    let after: Double
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title + String(format: "  %.1f → %.1f  (%+.1f)", before, after, after - before))
                .managementFont(.label).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            VStack(spacing: 6) {
                ManagementProgress(title: "이전 관찰", value: .init(current: before, target: 100), color: GameTheme.boardMuted)
                ManagementProgress(title: "이번 관찰", value: .init(current: after, target: 100), color: GameTheme.gold)
            }.accessibilityHidden(true)
        }.padding(12).background(GameTheme.board)
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1))
    }
}


struct ManagementToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(ManagementPixelFont.readable(.label))
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .managementButtonChrome(variant: .secondary, pressed: configuration.isPressed, enabled: enabled, focused: focused)
    }
}


/// Avoid a second system glass surface over the opaque pixel control on newer iOS.
struct ManagementToolbarAction: ToolbarContent {
    let title: String
    var identifier = ""
    var placement = ToolbarItemPlacement.confirmationAction
    var disabled = false
    let action: () -> Void
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) { item.sharedBackgroundVisibility(.hidden) }
        else { item }
    }
    private var item: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(title, action: action).buttonStyle(ManagementToolbarButtonStyle())
                .disabled(disabled).accessibilityIdentifier(identifier)
        }
    }
}
