import SwiftUI
import SwiftData

struct ClubSelectionHomePanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var review: ClubSelectionReview?
    @State private var failure: String?
    @State private var frozen = false
    @State private var emptyReason:String?
    #if DEBUG
    @State private var injectedFailure=false
    #endif
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let review {
                GamePanel(title:"LINEUP · 나의 자리",onBoard:true,contentSpacing:12) {
                    HStack(spacing:12) {
                        DetailGamePortrait(role:player.role,appearance:player.appearance,number:player.jerseyNumber,hand:player.throwingHandRaw).frame(width:46,height:60).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:8) {
                            Text(review.isStarter ? (player.role == .pitcher ? "선발 경쟁 통과":"주전 기용") : "벤치 · 다음 평가 준비").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("clubSelectionStatus")
                            Text(frozen ? "오늘 경기의 확정 기용":"주간 평가 · 경기 시작 때 확정").font(.subheadline)
                        }
                    }
                    Text(review.reason).font(.subheadline)
                    Text("평가 점수차 · 내 점수 − 경쟁자 "+String(format:"%+.1f",review.ownScore-review.rivalScore)).font(.subheadline.monospacedDigit()).accessibilityIdentifier("clubSelectionGap")
                    Text(review.nextReview <= player.gameDate ? "오프시즌 · 다음 개막 후 평가":"다음 평가 "+ManagementDisplay.date(review.nextReview)).font(.subheadline.monospacedDigit()).accessibilityIdentifier("clubSelectionNext")
                    NavigationLink { ClubSelectionScreen(player:player,calendar:calendar,review:review,frozen:frozen) } label: {Text("코치 피드백 · 출전 경쟁")}
                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openClubSelection")
                    Text(player.role == .pitcher ? "선발 기용과 별도로 5경기 순번을 따릅니다. 비등판일에도 훈련·휴식할 수 있습니다.":"벤치일에도 훈련·휴식 후 팀 경기를 진행할 수 있습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }
            } else if let failure {
                Text("기용 자료 확인 필요 · "+failure).font(.subheadline).accessibilityIdentifier("clubSelectionError")
                Button("기용 자료 다시 확인") {load()}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryClubSelection")
            } else if let emptyReason {
                GamePanel(title:"LINEUP · 기용 자료 대기",onBoard:true) {
                    Text(emptyReason).font(.subheadline).accessibilityIdentifier("clubSelectionWaiting")
                    Text("자료 없음은 벤치 판정이나 조회 실패가 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    Button("기용 자료 다시 확인") {load()}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryClubSelection")
                }
            }
        }.task(id:"\(player.id)-\(player.gameDate)-\(calendar.revision)") {load()}
    }
    private func load() {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-v55-selection-detail-failure"),!injectedFailure {
                injectedFailure=true;throw MatchError.invalidRecord
            }
            #endif
            frozen=false;emptyReason=nil
            if let fixture=try calendar.fixtures(for:player,year:GameDate(player.gameDate).year).first(where:{$0.date.description == player.gameDate}),
               let record=try CareerMatchStore.record(player:player,fixture:fixture,in:context) {
                review=try record.snapshot().clubSelection?.review;frozen=true
            } else {review=try ClubSelectionStore.projection(player:player,calendar:calendar,in:context)}
            if review == nil {emptyReason=frozen ? "이 경기에는 기용 평가가 저장되지 않았습니다. 당시 경기를 다시 평가하지 않습니다.":"현재 경로의 주간 기용 평가가 없습니다. 입단/시즌·다음 평가일을 확인하세요."}
            failure=nil
        } catch {review=nil;emptyReason=nil;failure=error.localizedDescription}
    }
}
struct ClubSelectionScreen: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let review: ClubSelectionReview
    let frozen: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private func n(_ value:Double) -> String {String(format:"%.1f",value)}
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                GamePanel(title:"CLUB LINEUP · "+review.position,onBoard:true,contentSpacing:12) {
                    Text(CareerTeamDirectory.name(review.teamID)).font(.title2.bold()).foregroundStyle(GameTheme.gold)
                    Text(review.isStarter ? "나의 자리 · 주전":"나의 자리 · 벤치").font(.headline).accessibilityIdentifier("clubSelectionDetail")
                    Text(ManagementDisplay.date(review.date)+" 평가 · "+(frozen ? "경기 고정":"주간 기용 기준")).font(.subheadline)
                    Text(review.reason).font(.subheadline)
                    Text(review.nextReview <= player.gameDate ? "오프시즌 · 다음 개막 후 평가":"다음 평가 "+ManagementDisplay.date(review.nextReview)).font(.subheadline.monospacedDigit())
                }
                CareerManagementNote(title:frozen ? "경기 시작 때 고정된 기용":"주간 평가일에 고정된 기용",
                    detail:"기용 근거일 "+ManagementDisplay.date(review.date)+" · NPC 성과 집계는 "+(review.rivalEvidence.map {ManagementDisplay.date($0.through)} ?? "당시 자료 미기록")+". 시작한 경기의 능력·성과·피로는 현재 조회로 다시 적용하지 않습니다.",identifier:"selectionEvidenceClock")
                ClubCoachPanel(player:player,calendar:calendar,review:review)
                let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:14)):AnyLayout(HStackLayout(alignment:.top,spacing:12))
                layout {
                    candidate(review.own,title:player.name,isOwn:true)
                    candidate(review.rival,title:NPCIdentity.name(review.rival.id),isOwn:false)
                }
                if let evidence=review.rivalEvidence {NPCSelectionEvidencePanel(evidence:evidence,role:player.role)}
                if let values=review.rivalAbilities {
                    GamePanel(title:"경쟁자의 고정 능력",onBoard:true,contentSpacing:12) {
                        Text("평가 당시 프로필2 · "+review.position).font(.subheadline).foregroundStyle(GameTheme.gold)
                        DisclosureGroup {
                            NPCSelectionAbilityRows(values:values,role:player.role,mastery:review.rivalPositionMastery).padding(.top,12)
                        } label: {
                            Text("고정 능력·구종 펼치기").accessibilityIdentifier("selectionRivalAbilities")
                        }.font(.headline).tint(GameTheme.gold)
                        Text("새 경기와 같은 생성 자료입니다. 이미 확정한 주간 평가와 시작한 경기는 재계산하지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    }
                }
                GamePanel(title:"기용을 준비하는 방법",onBoard:true,contentSpacing:12) {
                    Text("기량 H60% · 성과25% · 준비도15%").font(.headline)
                    Text("성과는 50+10P(10~90), 준비도는 평가 당시100−피로입니다. 내 성과는 고정 보고서, NPC는 동일 환경의 실제 선수 기록을 사용합니다. 표본 부족은 P0 중립입니다.").font(.subheadline)
                    Text("현재 피로 \(player.fatigue)/100 · 훈련으로 기량을 보완하거나 휴식으로 다음 평가를 준비하세요.").font(.subheadline)
                    Text("교체에는 점수 차5 이상이 필요하며 변경 후14일은 관찰합니다. 오늘의 휴식은 이미 고정한 주간 기용을 다시 뽑지 않습니다.").font(.subheadline)
                    Text("비출전 팀 경기는 개인 성적·경기 XP를 만들지 않습니다. 구단 시즌 목표의 원래 기준과 고정 보고서는 보존합니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }
            }.padding(14)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("출전 경쟁").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar).toolbarColorScheme(.dark,for:.navigationBar)
    }
    private func candidate(_ value:ClubSelectionCandidate,title:String,isOwn:Bool) -> some View {
        GamePanel(title:title,onBoard:true,contentSpacing:12) {
            Text("D "+n(review.score(value))+(review.selected == value.id ? " · 기용":" · 도전")).font(.title2.monospacedDigit().bold()).foregroundStyle(review.selected == value.id ? GameTheme.gold:GameTheme.boardInk).accessibilityIdentifier(isOwn ? "selectionOwnScore":"selectionRivalScore")
            ForEach([("역할 기량 H",value.h),("성과",review.neutralPerformance == true ? 50:value.performance),("준비",value.readiness)],id:\.0) {name,number in
                VStack(alignment:.leading,spacing:6) {
                    Text(name+" "+n(number)).font(.subheadline.monospacedDigit())
                    ProgressView(value:number,total:100).tint(isOwn ? GameTheme.growth:GameTheme.gold).accessibilityHidden(true)
                }
            }
            Text((review.neutralPerformance == true ? "원 성과 P (비교 미사용) ":"P ")+n(value.p)).font(.subheadline.monospacedDigit())
            Text(value.note).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            if let evidence=value.evidence {DisclosureGroup("고정 성적 출처") {Text(evidence).font(.caption).textSelection(.enabled)}}
        }.frame(maxWidth:.infinity,alignment:.topLeading)
    }
}


private struct NPCSelectionAbilityRows: View {
    let values:PlayerInitialValues
    let role:PlayerRole
    let mastery:Double?
    private var rows:[HomeAbilityValue] {
        let labels=["homeContact":"컨택","homePower":"파워","homeDiscipline":"선구안","homeSpeed":"스피드","homeDefense":"수비","homeArm":"송구","homeMental":"멘탈","homeVelocity":"구속 능력","homeControl":"제구","homeStuff":"구위","homeStamina":"지구력"]
        let originals=ScoutingClubCatalog.abilities(values,role:role).originals.map {HomeAbilityValue(id:$0.id,label:labels[$0.id] ?? $0.id,current:$0.current,initial:nil)}
        let pitches=values.pitches.keys.sorted().map {HomeAbilityValue(id:"pitch-"+$0,label:(PitchType(rawValue:$0)?.label ?? $0)+" 숙련",current:values.pitches[$0]!,initial:nil)}
        let position=mastery.map {[HomeAbilityValue(id:"position",label:"위치 숙련",current:$0,initial:nil)]} ?? []
        return originals+pitches+position
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            ForEach(rows) {row in
                HStack {
                    Text(row.label).font(.subheadline)
                    Spacer()
                    Text(String(format:"%.1f",row.current)).font(.headline.monospacedDigit()).foregroundStyle(GameTheme.gold)
                }.accessibilityElement(children:.combine).accessibilityIdentifier("selectionRival-"+row.id)
                ProgressView(value:row.current,total:100).tint(GameTheme.growth).accessibilityHidden(true)
            }
        }
    }
}


private struct NPCSelectionEvidencePanel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let evidence:NPCSelectionEvidence
    let role:PlayerRole
    private func n(_ value:Double) -> String {String(format:"%.1f",value)}
    var body: some View {
        GamePanel(title:"경쟁자의 실제 성과 · 컨디션",onBoard:true,contentSpacing:14) {
            Text(ManagementDisplay.date(evidence.through)+" 완료 기록까지 · 평가 기준").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            if let performance=evidence.performance {
                let sample=role == .pitcher ? performance.pitching.outs:performance.batting.plateAppearances
                let needed=role == .pitcher ? 45:40
                Text(role == .pitcher ? "실제 \(performance.pitching.innings)이닝 / 기준 15.0이닝":"실제 \(sample)타석 / 기준 40타석")
                    .font(.headline.monospacedDigit()).accessibilityIdentifier("npcPerformanceSample")
                ProgressView(value:Double(min(sample,needed)),total:Double(needed)).tint(GameTheme.gold).accessibilityHidden(true)
                Text(performance.enough ? "평가 가능 · P "+n(performance.correction):"표본 대기 · P0 중립")
                    .font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("npcPerformanceStatus")
                if role == .pitcher {
                    Text("K \(performance.pitching.strikeouts) · BB \(performance.pitching.walks) · 피홈런 \(performance.pitching.homeRuns)").font(.subheadline.monospacedDigit())
                } else {
                    Text("안타 \(performance.batting.hits) · 장타 \(performance.batting.doubles+performance.batting.triples+performance.batting.homeRuns) · 출루 \(performance.batting.hits+performance.batting.walks)").font(.subheadline.monospacedDigit())
                }
                Text("완료 \(performance.games)경기 · 같은 포지션 비교 \(performance.peerPlayers)명").font(.subheadline)
                Text("같은 리그·포지션·조작 환경끼리 비교합니다. 비교군 2명과 기준 표본이 필요하며, 내 성과는 종전 고정 보고서를 유지합니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                DisclosureGroup("실제 경기 출처 \(performance.fixtures.count)개") {
                    Text(performance.environment).font(.caption).textSelection(.enabled)
                    ForEach(performance.fixtures,id:\.self) {Text($0).font(.caption).textSelection(.enabled)}
                }.font(.subheadline).tint(GameTheme.gold)
            } else {
                Text("아직 같은 환경의 출전 기록이 없습니다. P0 중립으로 평가합니다.").font(.subheadline).accessibilityIdentifier("npcPerformanceStatus")
            }
            Text("피로 "+n(evidence.fatigue)+" / 100"+(typeSize.isAccessibilitySize ? "\n":" · ")+"준비 "+n(100-evidence.fatigue))
                .font(.headline.monospacedDigit()).accessibilityIdentifier("npcFatigueStatus")
            ProgressView(value:evidence.fatigue,total:100).tint(GameTheme.gold).accessibilityHidden(true)
            if let date=evidence.lastWorkloadDate,let cost=evidence.lastCost {
                Text(ManagementDisplay.date(date)+" 출전량 +"+n(cost)+" · 이후 날짜 회복 반영").font(.subheadline)
                Text("피로 기록 시작 "+ManagementDisplay.date((evidence.trackingSince ?? date))).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            } else {
                Text("피로 기록 시작 전 · 기준 0. 과거 경기의 피로를 임의 복원하지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            }
            Text("출전 타석 +1 · 투구 수×지구력 비용\n수면 −4 · 비출전일 휴식 −18").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }
    }
}


private struct ClubCoachPanel: View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let review:ClubSelectionReview
    @Environment(\.modelContext) private var context
    @State private var feedback:ClubCoachFeedback?
    @State private var pendingTraining:CareerTraining?
    @State private var actionState:ClubCoachActionState = .blocked("준비 상태 확인 중")
    @State private var failure:String?
    @State private var showRest=false
    private func n(_ value:Double) -> String {String(format:"%.1f",value)}
    var body: some View {
        GamePanel(title:"DUGOUT · 코치 피드백",onBoard:true,contentSpacing:14) {
            if let feedback {
                Text(review.isStarter ? "현재 자리를 지키는 준비":"다음 출전 기회를 준비하세요").font(.headline).foregroundStyle(GameTheme.gold)
                Text("내 점수 "+n(review.ownScore)+" · 경쟁자 "+n(review.rivalScore))
                    .font(.headline.monospacedDigit()).accessibilityIdentifier("coachScores")
                Text("점수 차이 "+String(format:"%+.1f",feedback.scoreGap)+" · 내 점수 − 경쟁자")
                    .font(.subheadline.monospacedDigit()).accessibilityIdentifier("coachScoreGap")
                if !review.isStarter {
                    Text(feedback.pointsToChallenge>0 ? "교체 비교선까지 약 "+n((feedback.pointsToChallenge*10).rounded(.up)/10)+"점 · 경쟁자보다 5점 높아야 합니다.":"점수 조건 충족 · 관찰 기간과 다음 평가를 확인하세요.").font(.subheadline)
                }
                if review.neutralPerformance == true {
                    Text("실제 성과 원문 보존 · 이번 기용 비교에서만 양쪽 성과50 사용").font(.subheadline).accessibilityIdentifier("coachNeutralPerformance")
                    Text("수집 표본이 갖춰진 다음 평가부터 기존 성과 비교로 돌아갑니다. 평가전 점수를 공식 성과로 대체하지 않습니다.").font(.subheadline)
                }
                Text("다음 평가 · "+ManagementDisplay.date(feedback.nextEvaluation)).font(.headline).accessibilityIdentifier("coachNextEvaluation")
                if feedback.nextEvaluation != feedback.reconsideration {
                    Text("기용 관찰 중 · 교체 재검토 "+ManagementDisplay.date(feedback.reconsideration)+"부터").font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("coachReconsideration")
                }
                Text("점수는 "+ManagementDisplay.date(review.date)+" 평가 기준입니다. 오늘 훈련·휴식으로 이미 확정된 기용을 다시 뽑지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                let rested=0.6*review.own.h+0.25*(review.neutralPerformance == true ? 50:review.own.performance)+15
                Text("당시 기량·성과를 유지하고 완전 회복하면 비교선까지 \(max(0,review.rivalScore+5-rested),specifier:"%.1f")점").font(.subheadline).accessibilityIdentifier("coachRestedGap")
                Text("현재 경쟁자와 당시 기량/성과를 고정한 조건 비교입니다. 휴식1회로 피로가0이 되거나 복귀가 확정되는 뜻은 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                if let development=(try? player.lifecycle)?.development {
                    Text("성장 준비 · "+development.timing.label+" · 고구간 성장 감속 적용").font(.subheadline).accessibilityIdentifier("coachDevelopment")
                    if let window=development.active(on:player.gameDate) {
                        Text(window.kind.label+" 집중 · 남은 \(8-window.used)세트 · "+ManagementDisplay.date(window.expires)+"까지").font(.headline)
                        NavigationLink {CareerTrainingView(player:player,calendar:calendar,initialKind:window.kind)} label: {Text("집중 능력 훈련 준비")}.buttonStyle(MatchPixelButtonStyle()).disabled(!actionState.canTrain).accessibilityIdentifier("coachFocusedTraining")
                    }
                }
                if !feedback.deficits.isEmpty {
                    Text("현재 내 능력 ↔ 평가 당시 경쟁자").font(.subheadline.bold())
                    ForEach(feedback.deficits) {deficit in
                        VStack(alignment:.leading,spacing:8) {
                            Text(deficit.kind.label+" · 현재 "+n(deficit.current)+" / 경쟁자 "+n(deficit.reference)).font(.headline.monospacedDigit()).accessibilityIdentifier("coachDeficit-"+deficit.id)
                            ProgressView(value:deficit.current,total:100).tint(GameTheme.growth).accessibilityHidden(true)
                            NavigationLink {CareerTrainingView(player:player,calendar:calendar,initialKind:deficit.kind)} label: {Text(deficit.kind.label+" 훈련 준비")}
                                .buttonStyle(MatchPixelButtonStyle(primary:true)).disabled(!actionState.canTrain).accessibilityIdentifier("coachTrain-"+deficit.id)
                        }
                    }
                    Text("역할 기량에 반영되는 격차 순입니다. 현재 능력의 보완 제안이며 평가 당시 내 개별 능력을 복원한 값은 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                } else {
                    Text(feedback.hasAbilityBasis ? "비교 가능한 원본 능력에서 보완할 격차가 없습니다. 구종 숙련·경기 성과와 컨디션도 함께 확인하세요.":"경쟁자의 당시 개별 능력 자료가 없어 부족한 능력을 추정하지 않습니다.").font(.subheadline)
                    NavigationLink {CareerTrainingView(player:player,calendar:calendar)} label: {Text("훈련장 선택 화면")}
                        .buttonStyle(MatchPixelButtonStyle()).disabled(!actionState.canTrain).accessibilityIdentifier("coachTrainingLibrary")
                }
                if actionState == .resume {
                    NavigationLink {resumeDestination} label: {Text("진행 중인 훈련 이어하기")}
                        .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("coachResumeTraining")
                }
                Text("현재 피로 \(player.fatigue) / 100 · 휴식 후 \(DailyRecovery.recover(player.fatigue,by:DailyRecovery.rest))").font(.headline.monospacedDigit()).accessibilityIdentifier("coachCurrentFatigue")
                Button("휴식 라운지 · 회복 확인") {showRest=true}
                    .buttonStyle(MatchPixelButtonStyle()).disabled(!actionState.canRest).accessibilityIdentifier("coachRest")
                Text(actionState.message).font(.subheadline).accessibilityIdentifier("coachActionState")
            }
            if let failure {
                Text("코치 자료 확인 필요 · "+failure).font(.subheadline).accessibilityIdentifier("coachError")
                Button("코치 자료 다시 확인",action:load).buttonStyle(MatchPixelButtonStyle())
            }
        }.task(id:"\(player.gameDate)-\(calendar.revision)") {load()}
            .sheet(isPresented:$showRest,onDismiss:load) {
                CareerRestConfirmation(player:player,state:calendar,revision:calendar.revision,returnTitle:"코치 피드백으로 돌아가기")
            }
    }
    @ViewBuilder private var resumeDestination:some View {
        if let trait=pendingTraining?.trait {TraitTrainingLiveView(player:player,calendar:calendar,initialTrait:trait)}
        else if let position=pendingTraining?.position {PositionTrainingView(player:player,calendar:calendar,initialPosition:position)}
        else {CareerTrainingView(player:player,calendar:calendar)}
    }
    private func load() {
        do {
            pendingTraining=try CareerTrainingStore.record(player:player,in:context)?.snapshot()
            feedback=try ClubCoachStore.feedback(player:player,calendar:calendar,review:review,in:context)
            actionState=ClubCoachStore.actions(player:player,calendar:calendar,in:context);failure=nil
        } catch {feedback=nil;actionState = .blocked(error.localizedDescription);failure=error.localizedDescription}
    }
}


struct ClubParticipationFeedbackPanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let feedback:ClubParticipationFeedback
    let prefix:String
    var showFinding=true
    var sampleScope="심사 표본은 원 평가의 단일 환경 자료이며 기용 횟수와 분모를 합치지 않습니다."
    @Environment(\.dynamicTypeSize) private var typeSize
    private var workload:String {
        player.role == .batter ? "\(feedback.sample) / \(feedback.required)타석":"\(feedback.sample/3).\(feedback.sample%3) / \(feedback.required/3).\(feedback.required%3)이닝"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("OPPORTUNITY · 당시 기용 맥락").font(.headline).foregroundStyle(GameTheme.gold)
            if showFinding {Text(feedback.finding.label).font(.headline).accessibilityIdentifier(prefix+"Finding");Text(feedback.finding.detail).font(.subheadline)}
            Text("평가 표본 · "+workload).font(.headline.monospacedDigit()).accessibilityIdentifier(prefix+"Sample")
            ProgressView(value:Double(min(feedback.sample,feedback.required)),total:Double(max(1,feedback.required))).tint(GameTheme.gold).accessibilityHidden(true)
            if let basis=feedback.basis {
                Text(ManagementDisplay.date(basis.from)+" ~ "+ManagementDisplay.date(basis.through)+" · \(basis.year)년 "+CareerTeamDirectory.name(basis.teamID)).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(alignment:.top,spacing:14))
                layout {
                    count("실제 출전",basis.starts)
                    count("벤치",basis.bench)
                    count("순번 휴식",basis.rotationRest)
                }.accessibilityElement(children:.combine).accessibilityIdentifier(prefix+"Counts")
                Text("예정 순번 \(basis.turns)회 · 기용 근거 미확인 \(basis.unknownTurns)회").font(.subheadline.monospacedDigit()).accessibilityIdentifier(prefix+"Coverage")
                Text("기용 집계는 위 소속·수준·기간입니다. "+sampleScope).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                DisclosureGroup {
                    ForEach(basis.games) {game in
                        Text(ManagementDisplay.date(game.date)+" · "+kind(game.kind)+" · "+game.key).font(.caption).textSelection(.enabled)
                    }
                } label: {Text("기용 근거 \(basis.games.count)경기").frame(minHeight:44)}.font(.subheadline).tint(GameTheme.gold)
            } else {
                Text("당시 기용 자료 미수집 · 과거 벤치/휴식 사유를 소급 생성하지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier(prefix+"Legacy")
            }
            if feedback.finding == .opportunityLimited {
                NavigationLink {ClubOpportunityPreparation(player:player,calendar:calendar)} label: {Text("현재 출전 경쟁 · 준비 확인")}
                    .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier(prefix+"Prepare")
            }
            Text("기존 표본·기량·역할 목표·계약 조건을 유지합니다. 기회 부족만으로 자격을 완화하거나 성과 점수를 가산하지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(GameTheme.boardPanel,in:ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine,lineWidth:2))
    }
    private func count(_ title:String,_ value:Int) -> some View {
        VStack(alignment:.leading,spacing:6) {Text(title).font(.subheadline);Text("\(value)").font(.title2.bold().monospacedDigit()).foregroundStyle(GameTheme.gold)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func kind(_ value:ClubParticipationKind) -> String {
        switch value {case .start:"출전";case .bench:"벤치";case .rotationRest:"순번 휴식";case .legacy:"당시 기용 사유 미수집";case .missing:"당시 미완료/미기록"}
    }
}
private struct ClubOpportunityPreparation:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                GamePanel(title:"NEXT CHANCE · 현재 준비",onBoard:true) {
                    Text(ManagementDisplay.date(player.gameDate)+" · "+player.name).font(.headline)
                    Text("과거 평가 원문은 보존하고 현재 출전 경쟁·훈련·다음 일정을 확인합니다.").font(.subheadline)
                }
                ClubSelectionHomePanel(player:player,calendar:calendar)
                NavigationLink {ObservationScheduleView(player:player,calendar:calendar)} label: {Text("현재 개인 출전 일정 확인")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("opportunityCurrentSchedule")
                NavigationLink {CareerTrainingView(player:player,calendar:calendar)} label: {Text("현재 훈련 선택 · 이어하기")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("opportunityCurrentTraining")
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("현재 출전 준비").navigationBarTitleDisplayMode(.inline)
    }
}
