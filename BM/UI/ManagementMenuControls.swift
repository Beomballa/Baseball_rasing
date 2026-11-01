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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))) {
            stamp("시도", value: "5회")
            stamp("오늘 행동", value: "1회")
            stamp("완료 피로", value: "\(fatigue) → \(min(100, fatigue + TrainingRules.fatigueCost))")
        }.accessibilityElement(children: .combine).accessibilityIdentifier("trainingCostStrip")
    }
    private func stamp(_ title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(GameTheme.muted)
            Text(value).font(.subheadline.monospacedDigit().bold()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.padding(10).frame(maxWidth: .infinity, minHeight: 62).background(GameTheme.navy.opacity(0.06))
            .overlay(Rectangle().strokeBorder(GameTheme.muted, lineWidth: 1))
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

/// A coach's practice card; content remains backed by the existing training commands.
struct TrainingInstructionCard<Content: View>: View {
    let kind: TrainingKind
    var drillVersion: Int? = 1
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    private var steps: [String] {
        if drillVersion != 1 {
            switch kind {
            case .power: return ["힘 조절", "발사각 조절", "5회 결과"]
            case .velocity: return ["동작 확인", "힘 조절", "5회 결과"]
            case .stuff: return ["회전 강도", "방향 조절", "5회 결과"]
            default: break
            }
        }
        return switch kind {
        case .contact: ["타격점 조준", "공 보고 터치", "5회 결과"]
        case .power: ["티 위의 공", "MAX에서 떼기", "5회 결과"]
        case .discipline: ["공의 코스", "볼·스트라이크", "5회 결과"]
        case .pitch: ["그립 선택", "릴리스 입력", "5회 포구"]
        case .speed: ["준비 자세", "좌우 교대", "5회 결과"]
        case .defense: ["낙하지점 확인", "선수 위치 조작", "5회 포구"]
        case .arm: ["베이스 선택", "방향·강도", "5회 송구"]
        case .velocity: ["준비", "회전·릴리스", "3박자 × 5회"]
        case .control: ["목표 코스", "조준·투구", "5회 포구"]
        case .stuff: ["궤적 확인", "손으로 따라가기", "5회 결과"]
        case .stamina: ["호흡 준비", "페이스 유지", "5회 결과"]
        case .mental: ["상황 확인", "집중 조작", "5회 결과"]
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                TrainingEquipmentIcon(kind: kind).frame(width: 42, height: 42).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("COACH / PRACTICE CARD").font(.caption2.monospaced()).foregroundStyle(GameTheme.boardMuted)
                    Text(kind.label + " 훈련").font(ManagementPixelFont.readable(.sectionTitle)).foregroundStyle(GameTheme.paper)
                }
                Spacer(minLength: 0)
            }.padding(16).background(GameTheme.board)
            VStack(alignment: .leading, spacing: 16) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                layout {
                    ForEach(steps.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "%02d", index + 1)).font(.caption.monospaced().bold()).foregroundStyle(GameTheme.green)
                            Text(steps[index]).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.accessibilityElement(children: .combine)
                Rectangle().fill(GameTheme.muted).frame(height: 1).accessibilityHidden(true)
                content
            }.padding(16).foregroundStyle(GameTheme.navy).tint(GameTheme.navy)
                .environment(\.colorScheme, .light).background(ManagementTheme.Palette.paper)
        }.overlay(ManagementStepFrame().strokeBorder(GameTheme.muted, lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("trainingInstructionCard")
    }
}

struct CareerDeskHeader: View {
    let section: ManagementCareerSection
    var body: some View {
        HStack(spacing: 14) {
            Image(section == .goals ? "NavPlayerV1" : "NavCareerV1").resizable().interpolation(.none).frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(section == .observation ? "SCOUT / ARCHIVE" : section == .goals ? "PLAYER / ROADMAP" : "CLUB / CONTRACT")
                    .font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(section == .observation ? "스카우트 관찰 파일" : section == .goals ? "나의 다음 무대" : "제의와 현재 소속")
                    .font(ManagementPixelFont.readable(.sectionTitle)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).foregroundStyle(GameTheme.boardInk)
            .accessibilityIdentifier("managementFileHeader")
    }
}

struct CareerDeskRoute: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Image(icon).resizable().interpolation(.none).frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(ManagementPixelFont.readable(.label)).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("›").font(.title2).foregroundStyle(GameTheme.gold).accessibilityHidden(true)
        }
    }
}

struct CareerDeskRouteStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.multilineTextAlignment(.leading).foregroundStyle(GameTheme.boardInk)
            .padding(16).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(configuration.isPressed ? GameTheme.board : GameTheme.boardPanel, in: ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1))
    }
}

struct CareerMarketCounts: View {
    let retention: Int
    let external: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
            tile("잔류 제의", count: retention)
            tile("외부 제의", count: external)
        }
    }
    private func tile(_ name: String, count: Int) -> some View {
        VStack(spacing: 8) {
            Text(name).font(.subheadline.bold())
            Text("\(count)건").font(ManagementPixelFont.readable(.sectionTitle)).monospacedDigit().foregroundStyle(GameTheme.gold)
        }.frame(maxWidth: .infinity, minHeight: 72).padding(12).background(GameTheme.board)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

struct ContractWindowCalendar: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))) {
            month("4월", role: "진로")
            month("7월", role: "무소속")
            month("11월", role: "프로")
        }
    }
    private func month(_ month: String, role: String) -> some View {
        VStack(spacing: 0) {
            Text(month).font(ManagementPixelFont.readable(.label)).frame(maxWidth: .infinity).padding(7).background(GameTheme.gold).foregroundStyle(GameTheme.navy)
            VStack(spacing: 5) {
                Text("1~14일").font(.subheadline.monospacedDigit().bold())
                Text(role).font(.caption)
            }.padding(10).frame(maxWidth: .infinity).background(GameTheme.board)
        }.overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1)).accessibilityElement(children: .combine)
    }
}
