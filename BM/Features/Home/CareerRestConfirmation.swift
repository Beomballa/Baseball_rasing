import SwiftUI
import SwiftData

struct CareerRestConfirmation: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let revision: Int
    var returnTitle = "홈으로 돌아가기"
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
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Image("RestRoomV2").resizable().interpolation(.none).scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().accessibilityHidden(true)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(ManagementDisplay.date(player.gameDate) + " · " + player.name)
                                .managementFont(.label).padding(12).background(GameTheme.board)
                            Color.clear.frame(height: max(24, geometry.size.height * 0.22)).accessibilityHidden(true)
                            ManagementPanel(completed ? "오늘 회복 완료" : "오늘은 몸을 쉬게 할까요?", surface: .paper) {
                                Text(completed ? "피로 \(before) → \(player.fatigue)" : "피로 \(player.fatigue) → \(DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest))")
                                    .managementFont(.metric).accessibilityIdentifier("restFatigueForecast")
                                ManagementProgress(title: completed ? "현재 피로" : "휴식 후 피로", value: .init(current: Double(completed ? player.fatigue : DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest)), target: 100), color: GameTheme.growth)
                                Text(completed ? "오늘 행동 사용 완료" : "오늘 행동 1회 소모").managementFont(.label).padding(8).background(GameTheme.gold.opacity(0.4))
                                Text("지금 최대 −\(DailyRecovery.rest)  ·  취침 시 추가 −\(DailyRecovery.sleep)").managementFont(.body)
                                Text("지금 날짜는 그대로 · 피로는 0 아래로 내려가지 않습니다.").managementFont(.helper)
                                if completed {
                                    Text("휴식을 저장했습니다.").managementFont(.body).accessibilityIdentifier("restSaved")
                                    Button(returnTitle) { dismiss() }.buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("restDone")
                                } else {
                                    if pending { Text("진행 중인 훈련을 먼저 마쳐 주세요.").managementFont(.body).accessibilityIdentifier("restPendingGate") }
                                    else if used { Text("오늘 행동을 이미 사용했습니다.").managementFont(.body).accessibilityIdentifier("restActionGate") }
                                    if let failure { Text(failure).managementFont(.body).foregroundStyle(Color(hex: 0x8b431b)).accessibilityIdentifier("restError") }
                                    Button("오늘 휴식 확정") { save() }.buttonStyle(ManagementButtonStyle())
                                        .disabled(used || pending || CalendarScheduleStatus(player: player, state: state).schedule == nil).accessibilityIdentifier("confirmRest")
                                    Button("취소 · 돌아가기") { dismiss() }.buttonStyle(ManagementButtonStyle(variant: .paper))
                                }
                            }
                        }.padding(12)
                    }
                }.clipped()
            }.background(GameTheme.board)
                .navigationTitle("휴식 라운지").navigationBarTitleDisplayMode(.inline)
                .toolbar { ManagementToolbarAction(title: "닫기") { dismiss() } }
                .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.preferredColorScheme(.dark).presentationDragIndicator(.visible)
    }
    private func save() {
        do {
            let old = player.fatigue
            try CalendarProgression.rest(player: player, state: state, revision: revision, in: context)
            before = old; completed = true; failure = nil; onCompleted?()
        } catch { failure = error.localizedDescription }
    }
}
