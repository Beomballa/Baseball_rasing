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
    @State private var receipt: CalendarAdvanceSummary?
    @State private var receiptFailure: String?
    #if DEBUG
    @State private var verificationSaveCount=0
    @State private var verificationFailureUsed=false
    #endif

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
                        receipt=nil;receiptFailure=nil
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

    private func saveDay(_ context:ModelContext) throws {
        #if DEBUG
        let args=ProcessInfo.processInfo.arguments
        if args.contains("-management-career-verification"),args.contains("-v53-calendar-save-failure"),!verificationFailureUsed {
            verificationSaveCount += 1
            if verificationSaveCount == 2 {verificationFailureUsed=true;throw CocoaError(.fileWriteOutOfSpace)}
        }
        #endif
        try context.save()
    }
    private func advanceBatch() {
        guard !advancing,transition.display == nil else {return}
        transition.perform(date:player.gameDate,label:"다음 일정까지 · 회복 우선",reduced:reduced,cancellable:true) {
            advancing=true;summary="";receiptFailure=nil
            defer {advancing=false}
            do {
                receipt=try await CalendarProgression.advanceOffDays(player:player,state:state,in:context,save:saveDay,onDaySaved:{date in
                    transition.arrive(on:date,reduced:reduced)
                    try? await Task.sleep(for:.milliseconds(reduced ? 0:100))
                })
            } catch let failure as CalendarAdvanceFailure {
                receipt=failure.summary;receiptFailure=failure.reason
                transition.arrive(on:failure.summary.lastSavedDate,reduced:reduced)
            } catch {errorMessage=error.localizedDescription}
        }
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
        let selection: (starter:Bool?,failed:Bool) = {
            do {return (try ClubSelectionStore.projection(player:player,calendar:state,in:context)?.isStarter,false)}
            catch {return (nil,true)}
        }()
        let todayState=CalendarDayPresentation(role:player.role,fixture:today,saved:CalendarSavedMatch.read(savedGame),
            starter:selection.starter,selectionFailed:selection.failed,actionUsed:hasAction,trainingPending:trainingPending)
        return GamePanel(title: "오늘 일정", onBoard: true) {
            if let life=try? player.lifecycle,!life.traitRisk.isEmpty {
                Text("! 특성 유지 주의 · 커리어의 변화 기록을 확인하세요").font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("calendarTraitWarning")
            }
            if !compact, status.errorMessage == nil {
                let guidance = EarlyPlayGuidance.make(trainingPending: trainingPending,
                    gamePending: gameRecords.contains { $0.playerID == player.id && !$0.completed },
                    actionUsed: hasAction, gameDue: today != nil, gameCompleted: gameCompleted)
                VStack(alignment: .leading, spacing: 8) {
                    Text(guidance.title).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("earlyPlayGuidance")
                    Text(guidance.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("earlyPlayDetail")
                }
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
                    Text("\(today.number) / 30차전 · \(todayState.participation)")
                        .font(.headline).accessibilityIdentifier("todaySchedule")
                    Text(detail(today)).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    Text(todayState.summary).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("calendarTodayStatus")
                    Text(gameCompleted ? "경기 결과 저장 완료 · 다음 날 진행 가능" : "경기일 · 경기 완료 후 다음 날 진행 가능")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("fixtureGate")
                } else {
                    Text("팀 경기 없음 · 훈련 / 휴식일").font(.headline).accessibilityIdentifier("todaySchedule")
                }
                if let next = nextTeam, next.id != nextAppearance?.id {
                    Text("다음 팀 경기  \(detail(next))").font(.caption)
                }
                if let next = nextAppearance {
                    Text("\(player.role == .pitcher ? "다음 선발 차례(기용 별도)" : "다음 기본 출전 차례(기용 별도)")  \(detail(next))").font(.caption)
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
                Button("다음 일정까지 · 회복 우선",action:advanceBatch)
                    .buttonStyle(GameButtonStyle(secondary:true,onBoard:true)).disabled(trainingPending || today != nil || schedule == nil)
                    .accessibilityIdentifier("advanceOffDays")
            }
            if let receipt {
                CalendarProgressReceipt(summary:receipt,failure:receiptFailure,
                    retryEnabled:!advancing && !trainingPending && today == nil && schedule != nil && receipt.lastSavedDate == player.gameDate,
                    retry:advanceBatch)
            }
            if evaluationUnread {Text("새 계약 평가 자료를 홈에서 확인한 뒤 날짜를 진행해 주세요.").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractEvaluationDateGate")}
            layout {
                Button("연간 30경기 일정 보기") { showSchedule = true }
                    .font(.caption.bold()).frame(minHeight: 44).accessibilityIdentifier("showSeasonSchedule")
                if !typeSize.isAccessibilitySize { Spacer() }
                Button(showHelp ? "안내 닫기" : "진행 안내") { showHelp.toggle() }.font(.caption).frame(minHeight: 44)
            }.foregroundStyle(GameTheme.gold)
            if showHelp {
                Text("게임 달력 1년당 팀 30경기 · 시즌 종료만으로 나이가 오르지 않습니다.\n하루에 훈련 또는 휴식 1회 · 수면 회복 −\(DailyRecovery.sleep)\n묶음 진행은 최대 30일 · 매일 저장 · 경기일/나이 변경 전에 정지합니다.")
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
                ScrollView {
                    if let message=status.errorMessage {scheduleError(message).padding(16)}
                    else if let schedule {
                        CalendarAnnualScheduleView(player:player,state:state,schools:schools,schedule:schedule,records:gameRecords,todayState:todayState)
                    }
                }.background(GameTheme.board).navigationTitle("연간 일정").navigationBarTitleDisplayMode(.inline)
                    .toolbar {ToolbarItem(placement:.confirmationAction) {Button("닫기") {showSchedule=false}.frame(minWidth:44,minHeight:44)}}
            }.tint(GameTheme.gold).foregroundStyle(GameTheme.boardInk).environment(\.colorScheme, .dark)
        }
    }
}

struct CalendarProgressReceipt:View {
    let summary:CalendarAdvanceSummary
    let failure:String?
    let retryEnabled:Bool
    let retry:() -> Void
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(failure == nil ? "진행 기록" : summary.days == 0 ? "진행 전 중단 · 저장 유지":"일부 진행 저장 완료")
                .font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("calendarReceiptTitle")
            Text("마지막 저장 · "+ManagementDisplay.date(summary.lastSavedDate)).font(.headline.monospacedDigit())
                .accessibilityIdentifier("calendarReceiptDate")
            Text("완료 \(summary.days)일 · 자동 휴식 \(summary.restDays)회 · 피로 \(summary.fatigueBefore) → \(summary.fatigueAfter)")
                .font(.subheadline.monospacedDigit()).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("calendarReceiptTotals")
            Text(summary.stop.rawValue).font(.subheadline).accessibilityIdentifier("calendarReceiptStop")
            if let failure {
                Text("중단 원인 · "+failure).font(.subheadline).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("calendarReceiptFailure")
                Text("완료한 날짜는 취소되지 않았습니다. 마지막 저장일부터 계속하며 이미 적용한 회복은 반복하지 않습니다.")
                    .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                Button("마지막 저장일부터 다시 진행",action:retry).buttonStyle(ManagementButtonStyle(variant:.secondary))
                    .disabled(!retryEnabled).accessibilityIdentifier("retryCalendarProgress")
            }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(GameTheme.navy,in:ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(failure == nil ? GameTheme.boardLine:GameTheme.gold,lineWidth:2))
            .accessibilityElement(children:.contain).accessibilityIdentifier("calendarProgressReceipt")
    }
}

struct CalendarAnnualScheduleView:View {
    let player:CareerPlayer
    let state:CareerCalendarState
    let schools:[School]
    let schedule:CalendarScheduleStatus.Schedule
    let records:[CareerMatchRecord]
    let todayState:CalendarDayPresentation
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        LazyVStack(alignment:.leading,spacing:12) {
            GamePanel(title:"SEASON CALENDAR · "+String(player.gameDate.prefix(4)),onBoard:true) {
                Text("게임 1년 · 팀당 30경기").font(.title3.bold()).foregroundStyle(GameTheme.gold)
                Text("6팀 조별리그 · 상대별 6회 / 홈·원정 각 3회").font(.subheadline)
                if schedule.annual.count < 30 {
                    Text("내 등록 대상 \(schedule.annual.count)경기 · 부분 시즌").font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                }
                Text("투수 기본 선발 차례 1·6·11·16·21·26차전 · 실제 기용은 경기 준비에서 확인합니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                Text("나이는 시작일 기념일에만 증가 · 시즌 결산이나 다음 연도 버튼만으로 한 살을 더하지 않습니다.")
                    .font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("calendarYearRule")
                if schedule.annual.isEmpty {Text("현재 진로에서 올해 출전 대상인 일정이 없습니다.").font(.headline)}
            }
            ForEach(schedule.annual) {fixture in
                let saved=records.first {$0.playerID == player.id && $0.fixtureID == fixture.id}
                let mark=CalendarSavedMatch.read(saved)
                let text=fixture.date.description == player.gameDate ? todayState.participation:rowStatus(fixture,mark:mark)
                let team=(try? state.teamID(for:player,on:fixture.date)) ?? player.schoolID
                let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(alignment:.center,spacing:12))
                layout {
                    Text("\(fixture.number)차전").font(.headline.monospacedDigit()).foregroundStyle(GameTheme.gold).frame(minWidth:52)
                    VStack(alignment:.leading,spacing:6) {
                        Text(ManagementDisplay.date(fixture.date.description)).font(.subheadline.monospacedDigit())
                        Text(CareerTeamDirectory.name(fixture.opponent(of:team),schools:schools)+" · "+(fixture.homeID == team ? "홈":"원정")).font(.headline)
                        Text(text).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    }
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                    .background(GameTheme.boardPanel,in:ManagementStepFrame())
                    .overlay(ManagementStepFrame().strokeBorder(fixture.date.description == player.gameDate ? GameTheme.gold:GameTheme.boardLine,lineWidth:2))
                    .accessibilityElement(children:.combine).accessibilityIdentifier("calendarFixture-\(fixture.number)")
            }
        }.padding(16)
    }
    private func rowStatus(_ fixture:SeasonFixture,mark:CalendarSavedMatch) -> String {
        switch mark {
        case .completed(let appeared):return appeared ? "경기 완료 · 내 출전 기록":"팀 경기 완료 · 내 출전 없음"
        case .playing(let appeared):return appeared ? "내 경기 진행 중":"팀 경기 진행 중 · 내 출전 없음"
        case .invalid:return "경기 기록 확인 필요"
        case .none:
            if fixture.date.description < player.gameDate {return "개인 경기 원장 없음 · 출전 성적 미생성"}
            return fixture.isAppearance(for:player.role) ? "기본 출전 차례 · 기용 평가 전":"비등판 차례 · 팀 경기"
        }
    }
}
