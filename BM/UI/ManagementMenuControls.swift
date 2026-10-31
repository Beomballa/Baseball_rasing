import SwiftUI

private struct CareerCompletionNavigationKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (ManagementTab) -> Void)? = nil
}

extension EnvironmentValues {
    var careerCompletionNavigation: (@MainActor @Sendable (ManagementTab) -> Void)? {
        get { self[CareerCompletionNavigationKey.self] }
        set { self[CareerCompletionNavigationKey.self] = newValue }
    }
}

struct ManagementSectionTabs<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let title: (Selection) -> String
    let identifier: String
    var horizontal = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if horizontal && !typeSize.isAccessibilitySize {
            HStack(spacing: 8) { choices }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) { choices }
        }
    }
    private var choices: some View {
        ForEach(options, id: \.self) { item in
                Button { selection = item } label: {
                    Text(title(item)).managementFont(.label).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: ManagementTheme.Control.hit)
                        .foregroundStyle(selection == item ? GameTheme.navy : GameTheme.boardInk)
                        .background(selection == item ? GameTheme.gold : ManagementTheme.Palette.control, in: ManagementStepFrame())
                        .contentShape(ManagementStepFrame())
                }.buttonStyle(.plain).accessibilityIdentifier(identifier + "-" + String(describing: item))
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
        }
    }
}

struct ManagementRoomScene: View {
    let asset: String
    var appearance: PlayerAppearance? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Image(asset).resizable().interpolation(.none).scaledToFit()
            .frame(maxHeight: typeSize.isAccessibilitySize ? 100 : 180)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if let appearance {
                    PixelPlayer(appearance: appearance).frame(width: 48, height: 60).padding(.bottom, 8)
                }
            }.accessibilityHidden(true)
    }
}

enum ManagementPlayerSection: CaseIterable { case abilities, traits, positions, records
    var title: String { switch self { case .abilities: "능력"; case .traits: "특성"; case .positions: "포지션"; case .records: "기록" } }
}
enum ManagementTrainingSection: CaseIterable { case abilities, traits, positions, practice
    var title: String { switch self { case .abilities: "능력"; case .traits: "특성"; case .positions: "포지션"; case .practice: "연습" } }
}

extension TrainingKind {
    var drillDescription: String {
        drillDescription(version: 1)
    }
    func drillDescription(version: Int?) -> String {
        if version == 1 {
            switch self {
            case .power: return "티배팅 · MAX 중앙에서 손 떼기"
            case .velocity: return "준비 → 회전 → 릴리스 · 3박자"
            case .stuff: return "점선 궤적을 시작부터 끝까지 따라 그리기"
            default: break
            }
        }
        return switch self {
        case .contact: "타격 위치와 타이밍"
        case .power: "힘과 발사각 조절"
        case .discipline: "볼·스트라이크 판단"
        case .pitch: "보유 구종과 릴리스 조절"
        case .speed: "양발 교대 달리기"
        case .defense: "낙하지점 이동과 포구"
        case .arm: "베이스·방향·강도 조절"
        case .velocity: "투구 동작과 힘 조절"
        case .control: "목표 코스 조준"
        case .stuff: "회전 강도와 방향 조절"
        case .stamina: "호흡과 달리기 페이스"
        case .mental: "경기 상황 판단"
        }
    }
}


enum ManagementGameSection: CaseIterable { case schedule, analysis, records, standings
    var title: String { switch self { case .schedule: "일정"; case .analysis: "분석"; case .records: "기록"; case .standings: "순위" } }
}


enum ManagementCareerSection: CaseIterable { case observation, goals, contracts
    var title: String { switch self { case .observation: "관찰"; case .goals: "목표"; case .contracts: "계약" } }
}


/// A forecast only; starting/finishing still belongs to the existing training command.
struct TrainingCostStrip: View {
    let fatigue: Int
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { labels }
            VStack(alignment: .leading, spacing: 8) { labels }
        }.managementFont(.label).accessibilityElement(children: .combine)
            .accessibilityIdentifier("trainingCostStrip")
    }
    @ViewBuilder private var labels: some View {
        Text("5회")
        Text("행동 1회")
        Text("완료 피로 \(fatigue) → \(min(100, fatigue + TrainingRules.fatigueCost))")
    }
}

/// Read-only equipment artwork; choosing a card changes only the preparation UI.
struct TrainingEquipmentIcon: View {
    let kind: TrainingKind
    private var rows: [String] {
        switch kind {
        case .contact, .power:
            ["........GG..", ".......GGGG.", "......GGGGG.", ".....GGGGG..", "....GGGGG...", "...GGGGG....", "...GGGG.....", "..GGG.......", ".GGG........", "GGG.........", ".GG.........", "............"]
        case .discipline, .mental:
            ["............", "............", "....WWWW....", "..WWWWWWWW..", ".WWWNNNNWWW.", "WWWNNGGNNWWW", ".WWNNGGNNWW.", "..WWNNNNWW..", "....WWWW....", "............", "............", "............"]
        case .speed, .stamina:
            ["............", "..GGG.......", "..GGG.......", "..GGG.......", "..GGGG......", "..GGWGG.....", "..GGGWGG....", "..GGGGGGGG..", ".GGGGGGGGGG.", ".WWWWWWWWWW.", "............", "............"]
        case .defense:
            ["...G.G.G....", "..GGGGGGG...", "..GGNGNGG...", "..GGNGNGG...", ".GGGGGGGGG..", "GGGGNNNGGG..", "GGGNNNNNGG..", ".GGGNNNGGG..", "..GGGGGGG...", "...GGGGG....", "....GGG.....", "............"]
        case .control:
            ["....GGGG....", "..GG....GG..", ".G........G.", ".G..WWWW..G.", "G..W....W..G", "G..W.GG.W..G", "G..W.GG.W..G", "G..W....W..G", ".G..WWWW..G.", ".G........G.", "..GG....GG..", "....GGGG...."]
        case .velocity:
            [".......GGG..", "......GGG...", ".....GGG....", "....GGG.....", "...GGGGGGG..", "..GGGGGGGG..", "......GGG...", ".....GGG....", "....GGG.....", "...GGG......", "..GG........", "............"]
        case .stuff:
            ["....WWWW....", "..WW....WW..", ".W..GG....W.", "W..GGGG....W", "W.....GG...W", "......GG...W", ".....GG....W", "....GG.....W", "...GG.....W.", "..GGG....W..", ".GGGGG.WW...", "....GG......"]
        case .arm:
            ["............", "........G...", "........GG..", "..WWWWGGGGG.", ".WRWWRW.GG..", ".WWRRWW.G...", ".WWRRWW.....", ".WRWWRW.....", "..WWWW......", "............", "............", "............"]
        default:
            ["....WWWW....", "..WWWWWWWW..", ".WRWWWWWWRW.", ".WWRWWWWRWW.", "WWRWWWWWWRWW", "WWWRWWWWRWWW", "WWRWWWWWWRWW", "WWWRWWWWRWWW", ".WRWWWWWWRW.", ".WWRWWWWRWW.", "..WWWWWWWW..", "....WWWW...."]
        }
    }
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 12
            for (y, row) in rows.enumerated() {
                for (x, code) in row.enumerated() where code != "." {
                    let color: Color = code == "G" ? GameTheme.gold : code == "W" ? GameTheme.boardInk : code == "R" ? Color(hex: 0xb95444) : GameTheme.navy
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)), with: .color(color))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct TrainingEquipmentSections: View {
    let selection: ManagementTrainingSection
    let pitcher: Bool
    let choose: (ManagementTrainingSection) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 4), spacing: 8) {
            ForEach(ManagementTrainingSection.allCases, id: \.self) { section in
                Button { choose(section) } label: {
                    VStack(spacing: 4) {
                        Group {
                            switch section {
                            case .abilities: TrainingEquipmentIcon(kind: pitcher ? .control : .contact)
                            case .traits: TraitPixelIcon(trait: .strongArm)
                            case .positions: TrainingEquipmentIcon(kind: pitcher ? .pitch : .defense)
                            case .practice: ManagementMenuIcon(tab: .training, size: 28)
                            }
                        }.frame(width: 22, height: 22).accessibilityHidden(true)
                        Text(section == .positions && pitcher ? "구종" : section.title)
                            .font(ManagementPixelFont.readable(.helper)).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, minHeight: 52).padding(.vertical, 6)
                }.buttonStyle(TrainingEquipmentStyle(selected: selection == section))
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                    .accessibilityIdentifier("trainingSection-" + String(describing: section))
            }
        }
    }
}

struct TrainingEquipmentShelf: View {
    let player: CareerPlayer
    let values: [HomeAbilityValue]
    let selection: TrainingKind
    let choose: (TrainingKind) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var kinds: [TrainingKind] { TrainingKind.allCases.filter { $0.allows(player.roleRaw) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("훈련 도구").font(ManagementPixelFont.readable(.label))
                Spacer()
                if !typeSize.isAccessibilitySize { Text("좌우로 선택 ›").font(.caption).foregroundStyle(GameTheme.boardMuted) }
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { ForEach(kinds, id: \.self) { equipment($0) } }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { ForEach(kinds, id: \.self) { equipment($0).frame(width: 106).id($0) } }
                            .padding(.vertical, 2)
                    }.accessibilityIdentifier("trainingEquipmentShelf")
                        .onAppear { proxy.scrollTo(selection, anchor: .center) }
                        .onChange(of: selection) { _, selected in proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }
    private func equipment(_ kind: TrainingKind) -> some View {
        let value = values.first { $0.id.lowercased() == "home" + kind.rawValue.lowercased() }?.current
        return Button { choose(kind) } label: {
            VStack(spacing: 6) {
                if kind == .pitch, let pitch = player.pitches.sorted(by: { $0.order < $1.order }).first {
                    MatchGrip(code: pitch.code, hand: player.throwingHandRaw).frame(width: 40, height: 40).accessibilityHidden(true)
                } else { TrainingEquipmentIcon(kind: kind).frame(width: 36, height: 36) }
                Text(kind.label).font(ManagementPixelFont.readable(.label))
                Text(value.map { String(format: "현재 %.1f", $0) } ?? (kind == .pitch ? "구종별 숙련" : "자료 확인"))
                    .font(.caption.monospacedDigit())
                Text("준비 보기 ›").font(.caption2)
            }.frame(maxWidth: .infinity, minHeight: 100).padding(8)
        }.buttonStyle(TrainingEquipmentStyle(selected: selection == kind))
            .accessibilityAddTraits(selection == kind ? .isSelected : [])
            .accessibilityIdentifier("trainingKind-" + kind.rawValue)
    }
}

private struct TrainingEquipmentStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(GameTheme.boardInk)
            .background(selected ? Color(hex: 0x284d53) : ManagementTheme.Spatial.wood, in: ManagementStepFrame())
            .overlay { ManagementStepFrame().strokeBorder(selected ? GameTheme.gold : GameTheme.boardLine, lineWidth: selected ? 3 : 1) }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Canvas { context, _ in
                        for rect in [CGRect(x: 0, y: 4, width: 4, height: 4), CGRect(x: 4, y: 8, width: 4, height: 4), CGRect(x: 8, y: 4, width: 4, height: 4), CGRect(x: 12, y: 0, width: 4, height: 4)] {
                            context.fill(Path(rect), with: .color(GameTheme.gold))
                        }
                    }.frame(width: 16, height: 12).padding(4).accessibilityHidden(true)
                }
            }
            .transaction { $0.animation = nil }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
