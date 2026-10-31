import SwiftUI
import SwiftData

struct CareerCalendarPanel: View {
    @Environment(\.modelContext) private var context
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    let transition: CareerTransition
    var compact = false
    var progressionOnly = false
    var onTraining: (() -> Void)? = nil
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
        let concise = compact || progressionOnly
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
        return GamePanel(title: progressionOnly ? "다음 행동 · 일정" : "오늘 일정", onBoard: true) {
            if !concise, let schedule {
                CareerMonthBoard(player: player, state: state, schools: schools,
                                 fixtures: schedule.annual, records: gameRecords)
            }
            if let life=try? player.lifecycle,!life.traitRisk.isEmpty {
                Text("! 특성 유지 주의 · 커리어의 변화 기록을 확인하세요").font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("calendarTraitWarning")
            }
            if !concise, status.errorMessage == nil, showHelp {
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
            if !concise {
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
                if !concise {
                if let today {
                    Text("\(today.number) / 30차전 · \(todayState.participation)")
                        .font(.headline).accessibilityIdentifier("todaySchedule")
                    Text(todayState.summary).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("calendarTodayStatus")
                    Text(gameCompleted ? "경기 결과 저장 완료 · 다음 날 진행 가능" : "경기일 · 경기 완료 후 다음 날 진행 가능")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("fixtureGate")
                } else {
                    Text("팀 경기 없음 · 훈련 / 휴식일").font(.headline).accessibilityIdentifier("todaySchedule")
                }
                DisclosureGroup("다음 팀 경기 · 내 출전 차례") {
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
                }.tint(GameTheme.gold)
            }                }

            if progressionOnly {
                Text(status.errorMessage != nil ? "일정을 다시 확인한 뒤 진행하세요" : evaluationUnread ? "새 계약 평가를 확인한 뒤 진행하세요" : trainingPending ? "진행 중인 훈련을 먼저 마쳐 주세요" : !hasAction ? "훈련 또는 휴식을 선택한 뒤 하루를 마무리하세요" : gameCompleted ? "오늘 경기 저장 완료 · 다음 날로 진행할 수 있어요" : today != nil ? "오늘 경기를 먼저 마쳐 주세요" : "오늘 행동 완료 · 다음 날로 진행할 수 있어요")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("lobbyProgressStatus")
            }
            layout {
                if progressionOnly, !hasAction, !trainingPending, let onTraining {
                    Button("훈련장 가기", action: onTraining).buttonStyle(ManagementButtonStyle(variant: .secondary))
                        .disabled(advancing || schedule == nil)
                        .accessibilityIdentifier("lobbyGoTraining")
                }
                if !progressionOnly || (!hasAction && !trainingPending) {
                Button { showRest = true } label: {
                    CalendarActionLabel(icon: "NavHomeV1", title: hasAction ? (trainedToday ? "오늘 행동 완료" : "휴식 완료") : "오늘 휴식",
                                        detail: hasAction ? "사용 완료" : "최대 −\(DailyRecovery.rest) · 오늘 행동 1회")
                }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).disabled(hasAction || trainingPending || advancing || schedule == nil)
                    .accessibilityIdentifier("restToday")
                }
                Button { nextDay() } label: {
                    CalendarActionLabel(icon: "NavGameV1", title: "다음 날", detail: "하루 마무리 · 수면 최대 −\(DailyRecovery.sleep)")
                }.buttonStyle(GameButtonStyle(onBoard: true))
                    .disabled(evaluationUnread || trainingPending || !hasAction || (today != nil && !gameCompleted) || advancing || schedule == nil).accessibilityIdentifier("advanceDay")
            }
            if advancing {
                Button("묶음 진행 중지") { transition.requestCancel() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
            } else {
                Button(action: advanceBatch) {
                    CalendarActionLabel(icon: "NavCareerV1", title: "다음 일정까지", detail: "회복 우선 · 매일 저장 · 최대 30일")
                }
                    .buttonStyle(GameButtonStyle(secondary:true,onBoard:true)).disabled(trainingPending || today != nil || schedule == nil)
                    .accessibilityIdentifier("advanceOffDays")
            }
            if let receipt {
                CalendarProgressReceipt(summary:receipt,failure:receiptFailure,
                    retryEnabled:!advancing && !trainingPending && today == nil && schedule != nil && receipt.lastSavedDate == player.gameDate,
                    retry:advanceBatch)
            }
            if evaluationUnread {
                Text("새 계약 평가 미확인 · 날짜 진행이 잠겨 있습니다.").font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractEvaluationDateGate")
                NavigationLink {ContractEvaluationReviewScreen(player:player,calendar:state)} label: {Text("고정 평가 확인 · 날짜 진행 잠금 해제")}
                    .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("calendarOpenContractEvaluation")
            }
            layout {
                Button("연간 30경기 일정 보기") { showSchedule = true }
                    .font(.caption.bold()).frame(minHeight: 44).accessibilityIdentifier("showSeasonSchedule")
                if !typeSize.isAccessibilitySize { Spacer() }
                if !progressionOnly { Button(showHelp ? "안내 닫기" : "진행 안내") { showHelp.toggle() }.font(.caption).frame(minHeight: 44) }
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

// Calendar selection is presentation-only; advancement remains owned by CalendarProgression.
struct CareerMonthBoard: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let schools: [School]
    let fixtures: [SeasonFixture]
    let records: [CareerMatchRecord]
    @State private var month: String?
    @State private var selected: String?
    @State private var showAllDays = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var key: String { month ?? String(player.gameDate.prefix(7)) }
    private var first: GameDate? { try? GameDate(key + "-01") }
    private var days: [GameDate] {
        guard let first else { return [] }
        return (0..<31).map { first.adding(days: $0) }.filter { $0.description.hasPrefix(key) }
    }
    private var offset: Int { first.map { $0.monday.days(to: $0) } ?? 0 }
    private var selectedDate: String { selected ?? player.gameDate }
    private func fixture(_ date: String) -> SeasonFixture? { fixtures.first { $0.date.description == date } }
    private func marker(_ date: String) -> String {
        guard let fixture = fixture(date) else { return "" }
        if let record = records.first(where: { $0.playerID == player.id && $0.fixtureID == fixture.id }) {
            switch CalendarSavedMatch.read(record) {
            case .completed: return "완료"
            case .playing: return "진행"
            case .invalid: return "확인"
            case .none: break
            }
        }
        return fixture.isAppearance(for: player.role) ? (player.role == .pitcher ? "등판" : "출전") : "팀"
    }
    private func move(_ step: Int) {
        guard let first else { return }
        let date = step < 0 ? first.adding(days: -1) : first.adding(days: days.count)
        guard date.year == first.year else { return }
        month = String(date.description.prefix(7)); selected = month! + "-01"
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { move(-1) } label: { Text("‹").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("이전 달").disabled(key.hasSuffix("-01"))
                Spacer(minLength: 0)
                Text(key.replacingOccurrences(of: "-", with: " / ")).font(ManagementPixelFont.readable(.label))
                    .accessibilityIdentifier("calendarMonth")
                Spacer(minLength: 0)
                Button { move(1) } label: { Text("›").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("다음 달").disabled(key.hasSuffix("-12"))
            }.foregroundStyle(ScoutDossierInk.paper).background(GameTheme.boardPanel)
            if typeSize.isAccessibilitySize {
                ForEach(days.filter { showAllDays || !marker($0.description).isEmpty || $0.description == player.gameDate || $0.description == selectedDate }, id: \.self) { day in dayButton(day) }
                Button(showAllDays ? "경기일·오늘만 보기" : "비경기일 포함 모든 날짜 보기") { showAllDays.toggle() }
                    .font(.body.bold()).frame(minHeight: 44).accessibilityIdentifier("calendarAllDays")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                    ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) {
                        Text($0).font(.caption.bold()).frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 1).accessibilityHidden(true) }
                    ForEach(days, id: \.self) { day in dayButton(day) }
                }
            }
            Text(player.role == .pitcher ? "등판: 기본 선발 차례 · 팀: 비등판 차례" : "출전: 기본 출전 차례 · 완료: 저장된 경기")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Text("실제 기용은 경기 준비에서 확인").font(.caption.bold())
            VStack(alignment: .leading, spacing: 8) {
                Text(ManagementDisplay.date(selectedDate)).font(.headline).accessibilityIdentifier("calendarSelectedDate")
                if let match = fixture(selectedDate) {
                    let team = (try? state.teamID(for: player, on: match.date)) ?? player.schoolID
                    Text(CareerTeamDirectory.name(match.opponent(of: team), schools: schools) + " · " + (match.homeID == team ? "홈" : "원정"))
                        .font(.subheadline.bold())
                    Text("\(match.number)차전 · " + marker(selectedDate)).font(.subheadline)
                } else { Text("팀 경기 없음 · 훈련 / 휴식 일정").font(.subheadline) }
                if selectedDate != player.gameDate { Text("조회 중 · 실제 오늘은 " + ManagementDisplay.date(player.gameDate)).font(.caption) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(ScoutDossierInk.rule.opacity(0.18))
        }.padding(10).foregroundStyle(ScoutDossierInk.ink).background(ScoutDossierInk.paper)
            .overlay(ManagementStepFrame().strokeBorder(ScoutDossierInk.rule, lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("careerMonthBoard")
            .onChange(of: player.gameDate) { _, date in month = nil; selected = date }
    }
    private func dayButton(_ day: GameDate) -> some View {
        let date = day.description, mark = marker(date), today = date == player.gameDate
        return Button { selected = date } label: {
            VStack(spacing: 3) {
                Text(String(Int(date.suffix(2)) ?? 0)).font(.system(.subheadline, design: .monospaced).bold())
                Text(today ? "오늘" : mark.isEmpty ? "·" : mark).font(.caption2.bold())
                if today && !mark.isEmpty { Text(mark).font(.caption2.bold()) }
            }.frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(date == selectedDate ? ScoutDossierInk.paper : ScoutDossierInk.ink)
                .background(date == selectedDate ? GameTheme.boardPanel : mark.isEmpty ? Color.clear : ScoutDossierInk.rule.opacity(0.22))
                .overlay(Rectangle().strokeBorder(today ? ScoutDossierInk.green : ScoutDossierInk.rule.opacity(0.4), lineWidth: today ? 2 : 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(ManagementDisplay.date(date) + (today ? " 오늘 " : " ") + (mark.isEmpty ? "팀 경기 없음" : mark + " · 실제 기용 별도"))
            .accessibilityAddTraits(date == selectedDate ? .isSelected : [])
            .accessibilityIdentifier("calendarDay-" + date)
    }
}

private struct CalendarActionLabel: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 8) {
            Image(icon).resizable().interpolation(.none).scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
            Text(title).font(ManagementPixelFont.readable(.label))
            Text(detail).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}
