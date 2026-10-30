import SwiftUI

enum ManagementTab: String, CaseIterable, Identifiable {
    case home, player, training, game, career
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "홈"
        case .player: "선수"
        case .training: "훈련"
        case .game: "경기"
        case .career: "커리어"
        }
    }
    var asset: String { "Nav" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() + "V1" }
}

struct ManagementMenuIcon: View {
    let tab: ManagementTab
    var size = ManagementTheme.Control.tabIcon
    var body: some View {
        Image(tab.asset).resizable().interpolation(.none).scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ManagementTabBar: View {
    @Binding var selection: ManagementTab
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                HStack(spacing: ManagementTheme.Space.compact) {
                    ManagementMenuIcon(tab: selection)
                    Text(selection.title).managementFont(.label).foregroundStyle(ManagementTheme.Palette.gold)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(ManagementTab.allCases) { tab in
                            Button(tab.title) { selection = tab }
                                .accessibilityIdentifier("managementMenu-" + tab.rawValue)
                        }
                    } label: {
                        Text("메뉴 선택").managementFont(.label)
                            .padding(.horizontal, ManagementTheme.Space.compact)
                            .frame(minWidth: ManagementTheme.Control.hit, minHeight: ManagementTheme.Control.hit)
                            .background(ManagementTheme.Palette.control, in: ManagementStepFrame())
                    }.accessibilityIdentifier("managementLargeMenu")
                }
                .padding(.horizontal, ManagementTheme.Space.screen)
            } else {
                HStack(spacing: 0) {
                    ForEach(ManagementTab.allCases) { tab in
                        Button { selection = tab } label: {
                            VStack(spacing: ManagementTheme.Space.micro) {
                                ManagementMenuIcon(tab: tab)
                                Text(tab.title).managementFont(.label).fixedSize()
                                Rectangle().fill(selection == tab ? ManagementTheme.Palette.gold : .clear)
                                    .frame(height: ManagementTheme.Control.border).accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: ManagementTheme.Control.tabHeight)
                            .foregroundStyle(selection == tab ? ManagementTheme.Palette.gold : ManagementTheme.Palette.onDark)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selection == tab ? .isSelected : [])
                        .accessibilityIdentifier("managementTab-" + tab.rawValue)
                    }
                }
                .padding(.horizontal, ManagementTheme.Space.inline)
            }
        }
        .frame(minHeight: ManagementTheme.Control.tabHeight)
        .padding(.top, ManagementTheme.Space.inline)
        .foregroundStyle(ManagementTheme.Palette.onDark)
        .background(ManagementTheme.Palette.canvas)
        .overlay(alignment: .top) { Rectangle().fill(ManagementTheme.Palette.border).frame(height: ManagementTheme.Control.border) }
    }
}

struct ManagementShell<Header: View, Content: View>: View {
    @Binding var selection: ManagementTab
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    init(selection: Binding<ManagementTab>, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        _selection = selection; self.header = header(); self.content = content()
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollViewReader { proxy in
                    ScrollView { VStack(spacing: 0) { header; paddedContent }.id("managementContentTop") }
                        .accessibilityIdentifier("managementContent")
                        .onChange(of: selection) { _, _ in proxy.scrollTo("managementContentTop", anchor: .top) }
                }
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollViewReader { proxy in
                        ScrollView { paddedContent.id("managementContentTop") }.accessibilityIdentifier("managementContent")
                            .onChange(of: selection) { _, _ in proxy.scrollTo("managementContentTop", anchor: .top) }
                    }
                }
            }
        }
        .background(ManagementTheme.Palette.canvas.ignoresSafeArea())
        .foregroundStyle(ManagementTheme.Palette.onDark)
        .safeAreaInset(edge: .bottom, spacing: 0) { ManagementTabBar(selection: $selection) }
    }
    private var paddedContent: some View {
        content.padding(ManagementTheme.Space.screen).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ManagementClubhouseBackdrop: View {
    var body: some View {
        Image("ClubhouseV1").resizable().interpolation(.none).scaledToFit().accessibilityHidden(true)
    }
}

/// Pixel-grid artwork, separate from the full-size accessible control.
struct ManagementSettingsButton: View {
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private let pixels = [
        "......####......", "......####......", "..##..####..##..", "..############..",
        "...##########...", "...###....###...", "######....######", "#####......#####",
        "#####......#####", "######....######", "...###....###...", "...##########...",
        "..############..", "..##..####..##..", "......####......", "......####......"
    ]
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Canvas { context, size in
                    let unit = min(size.width, size.height) / 16
                    for (y, row) in pixels.enumerated() {
                        for (x, pixel) in row.enumerated() where pixel == "#" {
                            context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                                                     width: unit, height: unit)), with: .color(GameTheme.gold))
                        }
                    }
                }.frame(width: 24, height: 24).accessibilityHidden(true)
                if typeSize.isAccessibilitySize { Text("설정").font(ManagementPixelFont.readable(.label)) }
            }
        }.buttonStyle(ManagementToolbarButtonStyle())
            .accessibilityLabel("설정").accessibilityHint("설정과 저장 보호 열기")
            .accessibilityIdentifier("clubhouse-settings")
    }
}
