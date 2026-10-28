import SwiftUI

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
