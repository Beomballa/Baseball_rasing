import SwiftUI
import SwiftData

struct CareerCalendarPanel: View {
    @Environment(\.modelContext) private var context
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    let transition: CareerTransition
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var showSchedule = false
    @State private var confirmBirthday = false
    @State private var errorMessage: String?
    @State private var summary = ""
    @State private var advancing = false

    @State private var scheduleRetry = 0
    private var hasAction: Bool { state.hasAction(on: player.gameDate) }
    private func teamName(_ id: String) -> String { schools.first { $0.id == id }?.name ?? id }
    private func detail(_ fixture: SeasonFixture) -> String {
        "\(fixture.date) · \(teamName(fixture.opponent(of: player.schoolID))) · \(fixture.homeID == player.schoolID ? "홈" : "원정")"
    }
    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
    private func nextDay(confirmed: Bool = false) {
        run {
            if try CalendarProgression.isAnniversaryTomorrow(player: player, state: state), !confirmed {
                confirmBirthday = true
            } else {
                let revision = state.revision
                transition.perform(date: player.gameDate, label: "하루를 마무리하는 중", reduced: reduced) {
                    run {
                        try CalendarProgression.advanceDay(player: player, state: state, revision: revision,
                                                           confirmAnniversary: confirmed, in: context)
                        transition.arrive(on: player.gameDate, reduced: reduced)
                        summary = "하루 진행 완료 · 수면 회복 −\(DailyRecovery.sleep) · \(player.gameDate) 저장"
                    }
                }
            }
        }
    }

    private func scheduleError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("일정을 불러오지 못했습니다").font(.headline).accessibilityIdentifier("scheduleLookupError")
            Text(message).font(.caption)
            Text("일정 확인 전까지 행동·날짜 진행이 잠깁니다. 기존 저장 데이터는 유지합니다.")
                .font(.caption).foregroundStyle(GameTheme.muted)
            Button("다시 확인") { scheduleRetry += 1 }.buttonStyle(GameButtonStyle(secondary: true))
                .accessibilityIdentifier("retrySchedule")
        }.id(scheduleRetry)
    }

    var body: some View {
        let status = CalendarScheduleStatus(player: player, state: state)
        let schedule = status.schedule
        let today = schedule?.today
        return GamePanel(title: "오늘 일정") {
            HStack {
                Text(player.gameDate).monospacedDigit().bold().accessibilityIdentifier("calendarDate")
                Spacer()
                Text(hasAction ? "오늘 행동 완료 · 휴식" : "오늘 행동 미사용")
                    .font(.caption).accessibilityIdentifier("calendarAction")
            }
            if let message = status.errorMessage {
                scheduleError(message)
            } else {
                if let today {
                    Text("\(today.number) / 30차전 · \(today.isAppearance(for: player.role) ? (player.role == .pitcher ? "선발 등판 예정" : "출전 예정") : "비등판 · 팀 경기 예정")")
                        .font(.headline).accessibilityIdentifier("todaySchedule")
                    Text(detail(today)).font(.subheadline)
                    Text("경기일 · 실제 경기 결과 연결 전까지 날짜 진행 대기")
                        .font(.caption).foregroundStyle(GameTheme.muted).accessibilityIdentifier("fixtureGate")
                } else {
                    Text("비경기일 · 훈련 / 휴식 준비").font(.headline).accessibilityIdentifier("todaySchedule")
                }
                if let next = schedule?.upcoming.first(where: { $0.date.description > player.gameDate }) {
                    Text("다음 팀 경기  \(detail(next))").font(.caption)
                }
                if let next = schedule?.upcoming.first(where: { $0.isAppearance(for: player.role) }) {
                    Text("\(player.role == .pitcher ? "다음 선발" : "다음 출전")  \(detail(next))").font(.caption)
                        .accessibilityIdentifier("nextAppearance")
                } else {
                    Text("고교 일정 이후에는 진로·소속 확정 후 공식 일정을 연결합니다.")
                        .font(.caption).foregroundStyle(GameTheme.muted)
                }
            }
            Button("연간 30경기 일정 보기") { showSchedule = true }
                .font(.subheadline.bold()).accessibilityIdentifier("showSeasonSchedule")
            HStack {
                Button(hasAction ? "휴식 완료" : "오늘 휴식 −\(DailyRecovery.rest)") {
                    run {
                        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
                        summary = "오늘 휴식 저장 · 다음 날 수면 회복 −\(DailyRecovery.sleep)"
                    }
                }.buttonStyle(GameButtonStyle(secondary: true)).disabled(hasAction || advancing || schedule == nil)
                    .accessibilityIdentifier("restToday")
                Button("다음 날") { nextDay() }.buttonStyle(GameButtonStyle())
                    .disabled(!hasAction || today != nil || advancing || schedule == nil).accessibilityIdentifier("advanceDay")
            }
            if advancing {
                Button("묶음 진행 중지") { transition.requestCancel() }.buttonStyle(GameButtonStyle(secondary: true))
            } else {
                Button("다음 일정까지 · 회복 우선") {
                    transition.perform(date: player.gameDate, label: "다음 일정까지 · 회복 우선", reduced: reduced, cancellable: true) {
                        advancing = true
                        summary = ""
                        defer { advancing = false }
                        do {
                            summary = try await CalendarProgression.advanceOffDays(player: player, state: state, in: context, onDaySaved: { date in
                                transition.arrive(on: date, reduced: reduced)
                                try? await Task.sleep(for: .milliseconds(reduced ? 0 : 100))
                            }).message
                        } catch let failure as CalendarAdvanceFailure {
                            summary = failure.summary.message
                            transition.arrive(on: failure.summary.lastSavedDate, reduced: reduced)
                            errorMessage = failure.localizedDescription
                        } catch { errorMessage = error.localizedDescription }
                    }
                }.buttonStyle(GameButtonStyle(secondary: true)).disabled(today != nil || schedule == nil)
                    .accessibilityIdentifier("advanceOffDays")
            }
            Text("최대 30일 · 매일 저장 · 경기일/나이 변경 전에 정지\n현재는 휴식만 연결 · 훈련 성장은 생성하지 않습니다.")
                .font(.caption).foregroundStyle(GameTheme.muted)
            if !summary.isEmpty {
                Text(summary).font(.caption).accessibilityIdentifier("calendarSummary")
            }
        }
        .onDisappear { transition.requestCancel() }
        .confirmationDialog("나이·학적 변경일로 진행할까요?", isPresented: $confirmBirthday, titleVisibility: .visible) {
            Button("확인하고 다음 날") { nextDay(confirmed: true) }
        } message: { Text("게임 달력의 기념일에만 나이가 바뀝니다. 성인 도달이 프로 입단을 뜻하지 않습니다.") }
        .alert("날짜 진행을 완료하지 못했습니다", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showSchedule) {
            NavigationStack {
                List {
                    Section(schedule == nil ? "연간 일정" : "\(player.gameDate.prefix(4))년 · 가상 6팀 조별리그") {
                        if let message = status.errorMessage {
                            scheduleError(message)
                        } else if let schedule {
                            Text("팀당 30경기 · 상대별 6회 / 홈·원정 각 3회\n투수 선발: 1·6·11·16·21·26차전").font(.caption)
                            ForEach(schedule.annual) { fixture in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(fixture.number)차전 · \(detail(fixture))").font(.subheadline.bold())
                                    Text(fixture.isAppearance(for: player.role) ? "\(player.role == .pitcher ? "선발 등판" : "출전") 예정" : "비등판 · 팀 경기")
                                        .font(.caption).foregroundStyle(GameTheme.muted)
                                }.listRowBackground(GameTheme.paper)
                            }
                        }
                    }
                }.scrollContentBackground(.hidden).background(GameTheme.paper)
                    .navigationTitle("연간 일정").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showSchedule = false } } }
            }.tint(GameTheme.navy)
        }
    }
}
