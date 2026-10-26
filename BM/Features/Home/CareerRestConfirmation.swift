import SwiftUI
import SwiftData

struct CareerRestConfirmation: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let revision: Int
    var onCompleted: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var training: [CareerTrainingRecord]
    @State private var failure: String?
    @State private var completed = false
    @State private var before = 0
    private var pending: Bool { training.contains { $0.playerID == player.id && !$0.completed } }
    private var used: Bool { state.hasAction(on: player.gameDate) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ManagementTheme.Space.section) {
                    Text(player.gameDate + " · " + player.name).managementFont(.label)
                    ManagementRoomScene(asset: "RestRoomV1", appearance: player.appearance)
                    ManagementPanel(completed ? "오늘 회복 완료" : "오늘은 몸을 쉬게 할까요?", surface: .paper) {
                        Text(completed ? "피로 \(before) → \(player.fatigue)" : "피로 \(player.fatigue) → \(DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest))")
                            .managementFont(.metric).accessibilityIdentifier("restFatigueForecast")
                        Text("휴식 회복 최대 \(DailyRecovery.rest) · 오늘 행동 1회").managementFont(.body)
                        Text("날짜는 유지됩니다. 다음 날로 진행할 때 수면 회복 최대 \(DailyRecovery.sleep)이 별도로 적용됩니다.").managementFont(.helper)
                    }
                    if completed {
                        Text("휴식을 저장했습니다. 경기일에는 오늘 경기를 마친 뒤 다음 날로 진행하세요.").managementFont(.body).accessibilityIdentifier("restSaved")
                        Button("홈으로 돌아가기") { dismiss() }.buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("restDone")
                    } else {
                        if pending { Text("진행 중인 훈련을 먼저 마쳐 주세요.").managementFont(.body).accessibilityIdentifier("restPendingGate") }
                        else if used { Text("오늘 행동을 이미 사용했습니다.").managementFont(.body).accessibilityIdentifier("restActionGate") }
                        if let failure { Text(failure).managementFont(.body).foregroundStyle(GameTheme.gold).accessibilityIdentifier("restError") }
                        Button("오늘 휴식 확정") { save() }.buttonStyle(ManagementButtonStyle()).disabled(used || pending || CalendarScheduleStatus(player: player, state: state).schedule == nil).accessibilityIdentifier("confirmRest")
                    }
                }.padding(ManagementTheme.Space.screen)
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .navigationTitle("휴식 라운지").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
                .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.preferredColorScheme(.dark)
    }
    private func save() {
        do {
            let old = player.fatigue
            try CalendarProgression.rest(player: player, state: state, revision: revision, in: context)
            before = old; completed = true; failure = nil; onCompleted?()
        } catch { failure = error.localizedDescription }
    }
}
