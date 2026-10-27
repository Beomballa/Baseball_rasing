import SwiftUI
import SwiftData

struct CareerCalendarPanel: View {
    @Environment(\.modelContext) private var context
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    let transition: CareerTransition
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showSchedule = false
    @State private var showRest = false
    @State private var showHelp = false
    @State private var confirmBirthday = false
    @State private var errorMessage: String?
    @State private var summary = ""
    @State private var advancing = false

    @State private var scheduleRetry = 0
    private var hasAction: Bool { state.hasAction(on: player.gameDate) }
    private func teamName(_ id: String) -> String { CareerTeamDirectory.name(id,schools:schools) }
    @Query private var trainingRecords: [CareerTrainingRecord]
    private var trainingPending: Bool { trainingRecords.contains { $0.playerID == player.id && !$0.completed } }
    private var trainedToday: Bool { trainingRecords.contains { $0.playerID == player.id && $0.gameDate == player.gameDate && $0.completed } }
    @Query private var gameRecords: [CareerMatchRecord]
    @Query private var evaluations: [CareerContractEvaluation]
    private var evaluationUnread: Bool {evaluations.contains {$0.playerID == player.id && !$0.acknowledged}}
    private func detail(_ fixture: SeasonFixture) -> String {
        let id=(try? state.teamID(for:player,on:fixture.date)) ?? player.schoolID
        return "\(ManagementDisplay.date(fixture.date.description)) · \(teamName(fixture.opponent(of:id))) · \(fixture.homeID == id ? "홈" : "원정")"
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
                .font(.caption).foregroundStyle(GameTheme.boardMuted)
            Button("다시 확인") { scheduleRetry += 1 }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                .accessibilityIdentifier("retrySchedule")
        }.id(scheduleRetry)
    }

    var body: some View {
        let _=state.revision
        let status = CalendarScheduleStatus(player: player, state: state)
        let schedule = status.schedule
        let today = schedule?.today
        let nextTeam = schedule?.upcoming.first { $0.date.description > player.gameDate }
        let nextAppearance = schedule?.upcoming.first { $0.date.description > player.gameDate && $0.isAppearance(for: player.role) }
        let savedGame = today.flatMap { fixture in gameRecords.first { $0.playerID == player.id && $0.fixtureID == fixture.id } }
        let gameCompleted = savedGame?.completed == true && (try? savedGame?.snapshot()) != nil
        let decision = try? ClubSelectionStore.projection(player:player,calendar:state,in:context)
        let todayAppearance = savedGame?.appearance ?? ((today?.isAppearance(for:player.role) ?? false) && (decision?.isStarter ?? true))
        return GamePanel(title: "오늘 일정", onBoard: true) {
            if let life=try? player.lifecycle,!life.traitRisk.isEmpty {
                Text("! 특성 유지 주의 · 커리어의 변화 기록을 확인하세요").font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("calendarTraitWarning")
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            if !compact {
            layout {
                Text(ManagementDisplay.date(player.gameDate)).monospacedDigit().bold().accessibilityIdentifier("calendarDate")
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(trainingPending ? "훈련 진행 중 · 이어하기" : hasAction ? (trainedToday ? "오늘 행동 완료 · 훈련" : "오늘 행동 완료 · 휴식") : "오늘 행동 미사용")
                    .font(.caption).accessibilityIdentifier("calendarAction")
            }
            HStack {
                Text("피로 \(player.fatigue) / 100").font(.subheadline.monospaced().bold()).accessibilityIdentifier("homeFatigue")
                Spacer()
                Text(ManagementDisplay.fatigueLabel(player.fatigue)).font(.caption).foregroundStyle(ManagementDisplay.fatigueColor(player.fatigue))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(GameTheme.board)
                    Rectangle().fill(GameTheme.gold).frame(width: max(0, geometry.size.width) * Double(min(100, max(0, player.fatigue))) / 100)
                }.overlay(Rectangle().strokeBorder(GameTheme.boardLine))
            }.frame(height: 7).accessibilityHidden(true)
            }
            if let message = status.errorMessage {
                scheduleError(message)
            } else {
                if !compact {
                if let today {
                    Text("\(today.number) / 30차전 · \(gameCompleted ? "경기 종료" : todayAppearance ? (player.role == .pitcher ? "선발 등판 예정" : "출전 예정") : "비출전 · 팀 경기 예정")")
                        .font(.headline).accessibilityIdentifier("todaySchedule")
                    Text(detail(today)).font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Text(gameCompleted ? "경기 결과 저장 완료 · 다음 날 진행 가능" : "경기일 · 경기 완료 후 다음 날 진행 가능")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("fixtureGate")
                } else {
                    Text("비경기일 · 훈련 / 휴식 준비").font(.headline).accessibilityIdentifier("todaySchedule")
                }
                if let next = nextTeam, next.id != nextAppearance?.id {
                    Text("다음 팀 경기  \(detail(next))").font(.caption)
                }
                if let next = nextAppearance {
                    Text("\(player.role == .pitcher ? "다음 선발" : "다음 출전")  \(detail(next))").font(.caption)
                        .accessibilityIdentifier("nextAppearance")
                } else {
                    Text("올해 남은 기본 출전 차례가 없습니다.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            }                }

            layout {
                Button(hasAction ? (trainedToday ? "오늘 행동 완료" : "휴식 완료") : "오늘 휴식 −\(DailyRecovery.rest)") {
                    showRest = true
                }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).disabled(hasAction || trainingPending || advancing || schedule == nil)
                    .accessibilityIdentifier("restToday")
                Button("다음 날") { nextDay() }.buttonStyle(GameButtonStyle(onBoard: true))
                    .disabled(evaluationUnread || trainingPending || !hasAction || (today != nil && !gameCompleted) || advancing || schedule == nil).accessibilityIdentifier("advanceDay")
            }
            if advancing {
                Button("묶음 진행 중지") { transition.requestCancel() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
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
                }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).disabled(trainingPending || today != nil || schedule == nil)
                    .accessibilityIdentifier("advanceOffDays")
            }
            if evaluationUnread {Text("새 계약 평가 자료를 홈에서 확인한 뒤 날짜를 진행해 주세요.").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractEvaluationDateGate")}
            layout {
                Button("연간 30경기 일정 보기") { showSchedule = true }
                    .font(.caption.bold()).frame(minHeight: 44).accessibilityIdentifier("showSeasonSchedule")
                if !typeSize.isAccessibilitySize { Spacer() }
                Button(showHelp ? "안내 닫기" : "진행 안내") { showHelp.toggle() }.font(.caption).frame(minHeight: 44)
            }.foregroundStyle(GameTheme.gold)
            if showHelp {
                Text("하루에 훈련 또는 휴식 1회 · 수면 회복 −\(DailyRecovery.sleep)\n묶음 진행은 최대 30일 · 매일 저장 · 경기일/나이 변경 전에 정지합니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                if state.legacySave {
                    Text("기존 저장 유지 · 저장 날짜를 나이 진행 기준일로 사용합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            }
            if !summary.isEmpty {
                Text(summary).font(.caption).accessibilityIdentifier("calendarSummary")
            }
        }
        .onDisappear { transition.requestCancel() }
        .confirmationDialog("나이·학적 변경일로 진행할까요?", isPresented: $confirmBirthday, titleVisibility: .visible) {
            Button("확인하고 다음 날") { nextDay(confirmed: true) }
        } message: { Text("게임 달력의 기념일에만 나이가 바뀝니다. 31~40세에는 능력별 노화가 적용되고, 41세에는 기록을 보존하며 은퇴합니다. 성인 도달이 프로 입단을 뜻하지 않습니다.") }
        .alert("날짜 진행을 완료하지 못했습니다", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showRest) {
            CareerRestConfirmation(player: player, state: state, revision: state.revision) {
                summary = "오늘 휴식 저장 · 다음 날 수면 회복 −\(DailyRecovery.sleep)"
            }
        }
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
                                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                                }.listRowBackground(GameTheme.boardPanel)
                            }
                        }
                    }
                }.scrollContentBackground(.hidden).background(GameTheme.board)
                    .navigationTitle("연간 일정").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showSchedule = false } } }
            }.tint(GameTheme.gold).foregroundStyle(GameTheme.boardInk).environment(\.colorScheme, .dark)
        }
    }
}
