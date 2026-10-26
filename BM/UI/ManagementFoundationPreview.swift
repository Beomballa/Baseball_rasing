#if DEBUG
import SwiftUI

/// Component-only samples: no SwiftData container or career commands are opened.
struct ManagementFoundationPreview: View {
    private enum SampleState: String, CaseIterable {
        case ready = "준비", locked = "잠금", working = "처리 중", error = "오류"
    }
    @State private var tab = ManagementTab.home
    @State private var pitcher = false
    @State private var sampleState = SampleState.ready
    @State private var tapCount = 0
    private var summary: ManagementPlayerSummary {
        var appearance = PlayerAppearance(); appearance.kit = pitcher ? 1 : 0
        return ManagementPlayerSummary(name: pitcher ? "투수 샘플" : "타자 샘플", detail: pitcher ? "16세 · 긴 학교 이름 표시 확인 · 좌투" : "16세 · 긴 학교 이름 표시 확인 · 2루수", date: "시안 날짜 2026.10.26", fatigue: 24, action: "오늘 행동 전", appearance: appearance)
    }
    private var actionState: ManagementActionState {
        switch sampleState {
        case .ready, .error: .ready
        case .locked: .locked("오늘 행동 사용 · 진행 중인 훈련은 이어갈 수 있습니다")
        case .working: .working
        }
    }
    var body: some View {
        ManagementShell(selection: $tab) {
            ManagementPlayerHeader(summary: summary)
        } content: {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.section) {
                VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
                    Text("공통 부품 확인 · 저장 안 함").managementFont(.helper)
                        .foregroundStyle(ManagementTheme.Palette.gold).accessibilityIdentifier("managementPreviewNoStore")
                    Text("\(tab.title) · 공통 UI").managementFont(.screenTitle).accessibilityIdentifier("managementCurrentTab")
                    HStack(spacing: ManagementTheme.Space.compact) {
                        Button("타자") { pitcher = false }
                            .buttonStyle(ManagementButtonStyle(variant: .secondary, selected: !pitcher))
                            .accessibilityAddTraits(!pitcher ? .isSelected : [])
                        Button("투수") { pitcher = true }
                            .buttonStyle(ManagementButtonStyle(variant: .secondary, selected: pitcher))
                            .accessibilityAddTraits(pitcher ? .isSelected : [])
                    }.accessibilityIdentifier("managementRolePicker")
                    Menu {
                        ForEach(SampleState.allCases, id: \.self) { value in
                            Button(value.rawValue) { sampleState = value }
                                .accessibilityIdentifier("managementState-" + value.rawValue)
                        }
                    } label: {
                        Text("상태 예시 · \(sampleState.rawValue)")
                    }.buttonStyle(ManagementButtonStyle(variant: .secondary))
                        .accessibilityIdentifier("managementStateMenu")
                }
                if tab == .home {
                    VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
                        ManagementClubhouseBackdrop()
                        Text("독립 배경 · 간판·선수·버튼은 별도 레이어")
                            .managementFont(.helper).foregroundStyle(ManagementTheme.Palette.secondary)
                    }.accessibilityIdentifier("managementSceneSample")
                }
                ManagementPanel(pitcher ? "구종 훈련 · 표시 예시" : "컨택 훈련 · 표시 예시", surface: .paper) {
                    Text("이 화면의 수치는 시안입니다. 실제 훈련이나 날짜를 진행하지 않습니다.")
                        .managementFont(.body).fixedSize(horizontal: false, vertical: true)
                    ManagementMetricRow(title: pitcher ? "포심 숙련" : "컨택", value: "56.4")
                    ManagementMetricRow(title: "피로 변화 예시", value: "24 → 30")
                }
                ManagementPanel("버튼과 상태") {
                    if sampleState == .error {
                        Text("오류 표시 예시 · 재시도를 선택할 수 있습니다")
                            .managementFont(.helper).foregroundStyle(ManagementTheme.Palette.error)
                    }
                    ManagementActionButton(title: sampleState == .error ? "다시 확인" : "버튼 동작 확인", state: actionState, identifier: "managementPrimaryAction") { tapCount += 1 }
                    Button("보조 버튼") { tapCount += 1 }
                        .buttonStyle(ManagementButtonStyle(variant: .secondary))
                        .accessibilityIdentifier("managementSecondaryAction")
                    Text("이번 화면에서 \(tapCount)회 선택").managementFont(.helper)
                        .foregroundStyle(ManagementTheme.Palette.secondary).accessibilityIdentifier("managementTapCount")
                }
                ManagementPanel("진척과 미집계") {
                    ManagementProgress(title: "표시 예시", value: ManagementProgressValue(current: 2, target: 5), color: ManagementTheme.Palette.growth)
                    ManagementProgress(title: "자료 없는 상태", value: ManagementProgressValue(current: nil, target: 100))
                }
                Text("하단 탭은 이 확인 화면의 선택 상태만 바꿉니다.")
                    .managementFont(.helper).foregroundStyle(ManagementTheme.Palette.secondary)
                    .accessibilityIdentifier("managementLastContent")
            }
        }
        .preferredColorScheme(.dark)
        .frame(maxWidth: ProcessInfo.processInfo.arguments.contains("-management-preview-width-320") ? 320 : nil)
        .frame(maxWidth: .infinity)
        .background(ManagementTheme.Palette.canvas)
    }
}
#endif
