import SwiftUI
import SwiftData

struct CareerRootView: View {
    let schools: [School]
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var transition = CareerTransition()
    @Query(sort: \CareerPlayer.createdAt) private var players: [CareerPlayer]
    @Query private var calendars: [CareerCalendarState]
    @State private var selectedID: UUID?
    @State private var showSettings = false
    @State private var showCreation = false
    @State private var initialRegistering = false
    @State private var sheetRegistering = false
    @State private var path: [UUID] = []

    private var selected: CareerPlayer? { players.first(where: { $0.id == selectedID }) ?? players.first(where: {!$0.isRetired}) ?? players.first }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let player = selected, !initialRegistering {
                    if player.isRetired {
                        RetirementArchiveView(player:player,players:players,select:{selectedID=$0},create:{showCreation=true})
                    } else {
                    PlayerHomeView(player: player, players: players,
                                   calendar: calendars.first { $0.playerID == player.id }, schools: schools, transition: transition,
                                   select: { selectedID = $0 }, create: { showCreation = true },
                                   play: {
                                       transition.perform(date: player.gameDate, label: "연습장으로 이동", reduced: reduced) {
                                           path.append(player.id)
                                       }
                                   })
                    }
                } else {
                    PlayerCreationView(schools: schools, availableRoles: PlayerRole.allCases, onSaving: { initialRegistering = $0 }) { selectedID = $0 }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let player = players.first(where: { $0.id == id }) {
                    MatchView(player: player).toolbar(.visible, for: .navigationBar)
                } else { ContentUnavailableView("선수를 찾을 수 없습니다", systemImage: "person.crop.square") }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("설정 · 저장") { showSettings=true }.accessibilityIdentifier("openSaveProtection")
            } }
            .sheet(isPresented: $showSettings) { SaveProtectionView() }
            .sheet(isPresented: $showCreation) {
                NavigationStack {
                    PlayerCreationView(schools: schools, availableRoles: PlayerRole.allCases.filter { role in
                        !players.contains(where: { $0.role == role && !$0.isRetired })
                    }, onSaving: { sheetRegistering = $0 }) { id in selectedID = id; showCreation = false }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showCreation = false }.disabled(sheetRegistering) } }
                }
            }
        }
        .onChange(of:players.map(\.id),initial:true) {_,_ in
            if selectedID == nil {selectedID=players.first(where:{!$0.isRetired})?.id ?? players.first?.id}
        }
        .disabled(transition.display != nil)
        .accessibilityHidden(transition.display != nil)
        .overlay { CareerTransitionOverlay(transition: transition) }
        .onChange(of: scenePhase) { _, phase in if phase == .background { transition.requestCancel() } }
        .onDisappear { transition.requestCancel() }
    }
}


struct CareerLifecyclePanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var showConfirmation=false
    @State private var error:String?
    var body:some View {
        ManagementPanel("커리어 변화 · 은퇴") {
            if let life=try? player.lifecycle {
                Text("게임 나이 \((try? calendar.age(of:player)) ?? player.startAge)세 · 41세 기념일 은퇴").managementFont(.label)
                Text("31세부터 매년 기념일에 능력별 노화가 반영됩니다. 멘탈·포지션 숙련도는 자동 감소하지 않습니다.").managementFont(.body)
                if let latest=life.aging.last {
                    Text("\(latest.age)세 기념일 · \(latest.date)").managementFont(.label)
                    ForEach(latest.before.keys.sorted(),id:\.self) {key in
                        if let before=latest.before[key],let after=latest.after[key],before != after {
                            Text("\(Self.label(key)): \(before.formatted(.number.precision(.fractionLength(1)) )) → \(after.formatted(.number.precision(.fractionLength(1))))").managementFont(.body)
                        }
                    }
                }
                ForEach(life.traitRisk.keys.sorted(),id:\.self) {key in
                    if let trait=PlayerTrait(rawValue:key),let since=life.traitRisk[key] {
                        let days=(try? GameDate(since).days(to:GameDate(player.gameDate))) ?? 0
                        Text("! \(trait.label) 유지 주의 · \(days+1)/28일 · 기준 회복 시 초기화").managementFont(.body)
                    }
                }
                ForEach(life.losses) {loss in Text("\(loss.date) · \(loss.trait.label) 상실 · 특성 훈련으로 재습득 가능").managementFont(.helper)}
            } else {Text(CareerLifecycleError.invalid.localizedDescription).managementFont(.body)}
            Button("커리어 은퇴 확인") {showConfirmation=true}.buttonStyle(ManagementButtonStyle(variant:.secondary))
                .disabled(((try? calendar.age(of:player)) ?? 0)<20).accessibilityIdentifier("openRetirementConfirmation")
            if let error {Text(error).managementFont(.body).accessibilityIdentifier("retirementError")}
        }
        .confirmationDialog("이 선수를 은퇴 처리할까요?",isPresented:$showConfirmation,titleVisibility:.visible) {
            Button("은퇴하고 기록 보존",role:.destructive) {
                do {try CareerLifecycleStore.retire(player:player,state:calendar,date:player.gameDate,revision:calendar.revision,in:context)} catch {self.error=error.localizedDescription}
            }.accessibilityIdentifier("confirmRetirement")
            Button("취소",role:.cancel) {}
        } message: {Text("능력치·구종·경기와 소속 이력은 보존됩니다. 이후 날짜·훈련·경기는 진행할 수 없고 새 커리어를 만들 수 있습니다. 미래 경제 지급은 종료되며 자동 FA나 방출로 처리하지 않습니다.")}
    }
    static func label(_ key:String) -> String {
        if key.hasPrefix("pitch/"),let pitch=PitchType(rawValue:String(key.dropFirst(6))) {return pitch.label}
        return TrainingKind(rawValue:key)?.label ?? key
    }
}
struct RetirementArchiveView:View {
    let player:CareerPlayer
    let players:[CareerPlayer]
    let select:(UUID)->Void
    let create:()->Void
    var body:some View {
        ScrollView {
            VStack(spacing:16) {
                HStack(spacing:16) {PixelPlayer(appearance:player.appearance).frame(width:64,height:88).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:8) {Text(player.name+" · #"+String(player.jerseyNumber)).managementFont(.screenTitle);Text("은퇴 선수 기록실").managementFont(.label)}
                }.accessibilityElement(children:.combine).accessibilityIdentifier("retirementArchive")
                if let life=try? player.lifecycle,let final=life.retirement {
                    ManagementPanel("커리어 결산") {
                        Text("\(final.age)세 · \(final.date)").managementFont(.label)
                        Text(final.reason == "age-limit" ? "41세 기념일 은퇴":"자율 은퇴").managementFont(.body)
                        Text("최종 소속 · \(final.affiliation)").managementFont(.body)
                        Text("공식 출전 \(final.games)경기").managementFont(.label)
                        if player.role == .batter {
                            Text("\(final.line.plateAppearances)타석 · \(final.line.hits)안타 · \(final.line.homeRuns)홈런 · \(final.line.rbi)타점").managementFont(.body)
                        } else {
                            Text("\(final.line.pitchingOuts/3).\(final.line.pitchingOuts%3)이닝 · \(final.line.pitchingStrikeouts)K · \(final.line.runsAllowed)실점").managementFont(.body)
                        }
                    }
                    ManagementPanel("최종 능력 · 구종") {
                        ForEach(final.finalValues.keys.sorted(),id:\.self) {key in Text("\(CareerLifecyclePanel.label(key)) · \(final.finalValues[key]!.formatted(.number.precision(.fractionLength(1))))").managementFont(.body)}
                        ForEach(final.finalPitches.keys.sorted(),id:\.self) {key in Text("\(PitchType(rawValue:key)?.label ?? key) · \(final.finalPitches[key]!.formatted(.number.precision(.fractionLength(1))))").managementFont(.body)}
                    }
                    Text("원 경기·훈련·관찰·소속 원장은 저장소에 보존됩니다. 이 화면은 은퇴 당시 요약을 읽습니다.").managementFont(.helper)
                }
                RetirementSavedHistoryView(player:player)
                if PlayerRole.allCases.contains(where:{role in !players.contains {$0.role == role && !$0.isRetired}}) {
                    Button("새 커리어 만들기",action:create).buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("archiveNewCareer")
                }
                ForEach(players.filter {$0.id != player.id}) {other in
                    Button("\(other.name) · \(other.isRetired ? "은퇴 기록":"진행 중 커리어")") {select(other.id)}.buttonStyle(ManagementButtonStyle(variant:.secondary))
                }
            }.padding(16)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark).tint(GameTheme.gold)
            .navigationTitle("커리어 기록실").toolbarBackground(GameTheme.board,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
    }
}


private struct RetirementSavedHistoryView:View {
    let player:CareerPlayer
    @Environment(\.modelContext) private var context
    @State private var games:[String]=[]
    @State private var memberships:[String]=[]
    @State private var failure:String?
    var body:some View {
        ManagementPanel("보존된 원기록") {
            DisclosureGroup("공식 경기 \(games.count)건") {
                LazyVStack(alignment:.leading,spacing:12) {ForEach(Array(games.enumerated()),id:\.offset) {_,line in Text(line).managementFont(.body)}}
            }
            DisclosureGroup("소속 이력 \(memberships.count)건") {ForEach(Array(memberships.enumerated()),id:\.offset) {_,line in Text(line).managementFont(.body)}}
            if let failure {Text(failure).managementFont(.body)}
        }.task(id:player.id) {
            do {
                let id=player.id,rows=try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id && $0.completed},sortBy:[SortDescriptor(\.gameDate,order:.reverse)]))
                games=try rows.map {row in
                    let game=try row.snapshot(),line=game.line
                    let stats=player.role == .batter ? "\(line.atBats)타수 \(line.hits)안타 \(line.homeRuns)홈런":"\(line.pitchingOuts/3).\(line.pitchingOuts%3)이닝 \(line.pitchingStrikeouts)K \(line.runsAllowed)실점"
                    return row.gameDate+" · "+(row.appearance ? stats:"비출전 팀 경기")
                }
                if let calendar=try context.fetch(FetchDescriptor<CareerCalendarState>(predicate:#Predicate {$0.playerID == id})).first {
                    let owner=try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
                    memberships=owner.membershipHistory().map {"\($0.name) · \($0.since) · 원 계약 경제 종료 \($0.economicEnd)"}
                }
            } catch {failure=error.localizedDescription}
        }
    }
}
