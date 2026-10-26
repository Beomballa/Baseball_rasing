import SwiftUI

enum ManagementButtonVariant { case primary, secondary, paper }

struct ManagementButtonStyle: ButtonStyle {
    var variant = ManagementButtonVariant.primary
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var background: Color {
        if !enabled { return ManagementTheme.Palette.control }
        if selected { return ManagementTheme.Palette.gold }
        switch variant {
        case .primary: return ManagementTheme.Palette.gold
        case .secondary: return ManagementTheme.Palette.control
        case .paper: return ManagementTheme.Palette.paper
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .managementFont(.body).fontWeight(.semibold)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ManagementTheme.Space.screen)
            .padding(.vertical, ManagementTheme.Space.compact)
            .frame(maxWidth: .infinity, minHeight: variant == .primary ? ManagementTheme.Control.primaryHeight : ManagementTheme.Control.secondaryHeight)
            .foregroundStyle(enabled && (selected || variant != .secondary) ? ManagementTheme.Palette.ink : ManagementTheme.Palette.onDark)
            .background(background, in: ManagementStepFrame())
            .overlay { ManagementStepFrame().strokeBorder(enabled && variant == .primary ? ManagementTheme.Palette.ink : ManagementTheme.Palette.border, lineWidth: ManagementTheme.Control.border) }
            .overlay(alignment: .bottom) {
                Rectangle().fill(ManagementTheme.Palette.ink.opacity(0.35)).frame(height: ManagementTheme.Control.depth)
                    .padding(.horizontal, ManagementTheme.Control.corner).allowsHitTesting(false)
            }
            .contentShape(ManagementStepFrame())
            .offset(y: configuration.isPressed && !reduceMotion ? ManagementTheme.Control.depth : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: ManagementTheme.Control.pressDuration), value: configuration.isPressed)
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
