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
    var onContinue: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var recovering = false
    @State private var recoveryTask: Task<Void, Never>?
    @State private var displayFatigue = 0.0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        PixelPlayer(appearance: player.appearance).frame(width: 36, height: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.name + " · #" + String(player.jerseyNumber)).managementFont(.label)
                            Text(ManagementDisplay.date(player.gameDate)).managementFont(.helper)
                        }
                        Spacer(minLength: 0)
                    }.padding(16)
                    Image("RestBenchV67").resizable().interpolation(.none).scaledToFit().accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recovering ? "잠시 숨을 돌리는 중…" : completed ? "몸을 충분히 쉬었어요" : "오늘은 회복에 집중하자")
                            .font(ManagementPixelFont.readable(.sectionTitle)).accessibilityAddTraits(.isHeader)
                        Text(completed ? "피로 \(before) → \(player.fatigue)" : "피로 \(player.fatigue) → \(DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest))")
                            .managementFont(.metric).monospacedDigit().accessibilityIdentifier("restFatigueForecast")
                        ProgressView(value: completed ? displayFatigue : Double(player.fatigue), total: 100).tint(Color(hex: 0x237459))
                            .accessibilityLabel("피로").accessibilityValue("\(player.fatigue) / 100")
                        Text("휴식 최대 −\(DailyRecovery.rest) · 다음 날 수면 −\(DailyRecovery.sleep)은 별도").managementFont(.helper)
                        if pending && !completed { Text("진행 중인 훈련을 먼저 마쳐 주세요.").managementFont(.body).accessibilityIdentifier("restPendingGate") }
                        else if used && !completed { Text("오늘 행동을 이미 사용했습니다.").managementFont(.body).accessibilityIdentifier("restActionGate") }
                        if let failure { Text(failure).managementFont(.body).foregroundStyle(Color(hex: 0x8b431b)).accessibilityIdentifier("restError") }
                        if completed && !recovering { Text("휴식을 저장했습니다.").managementFont(.label).accessibilityIdentifier("restSaved") }
                    }.padding(16).foregroundStyle(GameTheme.navy).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardInk)
                }
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                        Text(completed ? "오늘 행동 사용 완료 · 날짜 유지" : "오늘 행동 1회 · 날짜 유지").managementFont(.helper)
                        if recovering {
                            Button("회복 연출 건너뛰기") { finishRecovery() }.buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("skipRestPresentation")
                        } else if completed {
                            if let onContinue {
                                Button("경기 · 다음 일정 확인") { onContinue(); dismiss() }.buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("restGoGame")
                            }
                            Button(returnTitle) { dismiss() }.buttonStyle(ManagementButtonStyle(variant: onContinue == nil ? .primary : .secondary)).accessibilityIdentifier("restDone")
                        } else {
                            Button("휴식하기", action: save).buttonStyle(ManagementButtonStyle())
                                .disabled(used || pending || CalendarScheduleStatus(player: player, state: state).schedule == nil).accessibilityIdentifier("confirmRest")
                            Button("취소 · 돌아가기") { dismiss() }.frame(minHeight: 44)
                        }
                    }.padding(12).foregroundStyle(GameTheme.boardInk).background(GameTheme.board)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .navigationTitle("휴식").navigationBarTitleDisplayMode(.inline)
                .toolbar { ManagementToolbarAction(title: "닫기") { dismiss() } }
        }.preferredColorScheme(.dark).presentationDragIndicator(.visible)
            .onDisappear { recoveryTask?.cancel() }
    }
    private func finishRecovery() {
        recoveryTask?.cancel(); displayFatigue = Double(player.fatigue); recovering = false
    }
    private func save() {
        do {
            let old = player.fatigue
            try CalendarProgression.rest(player: player, state: state, revision: revision, in: context)
            before = old; completed = true; failure = nil; onCompleted?()
            displayFatigue = Double(old)
            if reduced { finishRecovery() }
            else {
                recovering = true
                withAnimation(.easeOut(duration: 2.2)) { displayFatigue = Double(player.fatigue) }
                recoveryTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
                    guard !Task.isCancelled else { return }; finishRecovery()
                }
            }
        } catch { failure = error.localizedDescription }
    }
}
