import SwiftUI
import SwiftData

struct ContractMarketView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var showHistory=false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        let _=calendar.revision
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                switch Result(catching:{(try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),try ContractMarketStore.domestic(player:player,calendar:calendar,in:context))}) {
                case .failure(let error):Text(error.localizedDescription).accessibilityIdentifier("marketError")
                case .success(let loaded):
                    let owner=loaded.0
                    let domestic=loaded.1.sorted {ContractMarketOrder.precedes(status:$0.status,expires:$0.expires,id:$0.id,otherStatus:$1.status,otherExpires:$1.expires,otherID:$1.id)}
                    let state=owner.overseasCareer ?? OverseasCareerJournal()
                    let entries=state.marketEntries(on:player.gameDate).sorted {ContractMarketOrder.precedes(status:$0.status,expires:$0.offer.expires,id:$0.id,otherStatus:$1.status,otherExpires:$1.offer.expires,otherID:$1.id)}
                    let hasPending=entries.contains {$0.status == "수락 · 발효 대기"} || domestic.contains {$0.status == "수락 · 발효 대기"}
                    GamePanel(title:"CONTRACT MARKET · 계약 시장",onBoard:true,contentSpacing:12) {
                        Text("기준일 "+ManagementDisplay.date(player.gameDate)).font(.footnote.monospacedDigit())
                        Text("검토 가능 \(entries.filter {$0.status == "검토 가능"}.count + domestic.filter {$0.status == "검토 가능"}.count)건 · 잔류 / 외부 조건 비교").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketSummary")
                        CareerMarketCounts(retention: entries.filter {$0.retention && $0.status == "검토 가능"}.count + domestic.filter {$0.renewal != nil && $0.status == "검토 가능"}.count,
                                           external: entries.filter {!$0.retention && $0.status == "검토 가능"}.count + domestic.filter {$0.renewal == nil && $0.status == "검토 가능"}.count)
                        Text("역할·배치 → 발효일·기간 → 경제 지수 순으로 비교 · 출전 보장 없음").font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketComparisonPriority")
                        NavigationLink { ScoutingFundsView(player: player, calendar: calendar) } label: { Text("내 자금 관리") }
                            .buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("openScoutingFunds")
                        if hasPending {ContractNextStep(title:"수락된 변경 발효 대기",timing:"예약된 발효일은 계약·소속에서 확인",action:"다른 제의를 다시 수락하지 않고 현재 소속과 예약 원문을 확인하세요.",identifier:"marketPendingTransition")}
                        DisclosureGroup("경제 지수 · 수락 시 유의사항") {
                            Text("검토 가능 제의는 마감 순입니다. 마감·거절·제의 없음은 자동 방출이나 FA가 아닙니다.").font(.subheadline)
                            Text("연봉지수는 게임 내 비교값입니다. 계약 기간·역할·발효일을 함께 확인하세요. 대학 지원금과 연봉을 같은 금액으로 비교하지 않습니다.").font(.footnote).lineSpacing(4)
                            Text("수락 시 다른 열린 제의를 닫고 발효일까지 현재 소속을 유지합니다.").font(.footnote).foregroundStyle(GameTheme.boardMuted)
                        }.tint(GameTheme.gold)
                    }
                    Button(showHistory ? "이전 제의 접기":"이전 제의 이력 보기") {showHistory.toggle()}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketHistory")
                    ForEach(entries.filter {showHistory || ["검토 가능","수락 · 발효 대기"].contains($0.status)}) {entry in
                        GamePanel(title:entry.retention ? "잔류 제의":"외부 제의",onBoard:true,contentSpacing:12) {
                            ClubFileHeader(name:entry.offer.name,subtitle:entry.offer.route.label+" · "+DomesticContractOffer.roleName(entry.offer.roleID))
                            Text(entry.status).font(.headline).foregroundStyle(GameTheme.gold).padding(10).frame(maxWidth:.infinity,alignment:.leading)
                                .background(GameTheme.navy,in:ManagementStepFrame()).overlay {ManagementStepFrame().strokeBorder(GameTheme.gold,lineWidth:2)}.accessibilityIdentifier("marketOfferStatus")
                            ContractTermsTimeline(issued:entry.offer.issued,expires:entry.offer.expires,effective:entry.offer.effective)
                            ContractTermsMetric(title:"연봉지수",value:String(entry.offer.economicIndex),note:"\(entry.offer.years)년 · 실제 통화/출전 보장 아님")
                            if let amount = entry.offer.signingBonusWon { SigningBonusOfferAmount(amount: amount) }
                            Text("경제 기간 종료 · "+ManagementDisplay.date(entry.offer.economicEnd)).font(.footnote.monospacedDigit())
                            if entry.retention {
                                NavigationLink {OverseasRenewalView(player:player,calendar:calendar)} label: {Text("잔류 조건 상세 · 결정")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketOfferDecision-"+entry.id)
                            } else {
                                NavigationLink {OverseasContractsView(player:player,calendar:calendar)} label: {Text("외부 조건 상세 · 결정")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketOfferDecision-"+entry.id)
                            }
                            Text("출전·승격 보장 없음").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    DomesticMarketCards(player:player,calendar:calendar,entries:domestic,showHistory:showHistory)
                    GamePanel(title:"심사 · 결정 창구",onBoard:true,contentSpacing:12) {
                        NavigationLink {OverseasRenewalView(player:player,calendar:calendar)} label: {Text("잔류 심사 · 수락 / 거절")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketRenewal")
                        NavigationLink {OverseasContractsView(player:player,calendar:calendar)} label: {Text("외부 심사 · 수락 / 거절")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketExternal")
                        NavigationLink {OverseasScoutingReportView(player:player,calendar:calendar)} label: {Text("28일 보고서 · 부족 조건 확인")}.buttonStyle(MatchPixelButtonStyle())
                        Text("국내 신인·대학·육성 제의는 기존 진로 창구에서 확인합니다.").font(.caption)
                        ContractEvaluationHomePanel(player:player,calendar:calendar)
                    }
                    GamePanel(title:"마감 · 제의 없음 · 재도전",onBoard:true,contentSpacing:12) {
                        if !hasPending && !entries.contains(where:{$0.status == "검토 가능"}) && !domestic.contains(where:{$0.status == "검토 가능"}) {
                            Text("현재 검토할 제의 없음").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketEmpty")
                        }
                        Text("같은 평가 창에서는 재심사하거나 만료 제의를 재발행하지 않습니다. 현재 창의 보고서와 부족 조건을 확인하고 다음 유효 창에 새 자료로 도전하세요.").font(.caption).lineSpacing(5)
                        if let date=try? GameDate(player.gameDate),let membership=try? owner.current(on:date) {
                            Text("다음 시장 확인 창 · "+state.nextMarketWindow(after:date,hasMembership:true).start.description+" · 자격 심사 별도").font(.subheadline).foregroundStyle(GameTheme.gold)
                            Text(membership.name+"의 소속·권리는 별도 발효/해제 전까지 유지됩니다.").font(.caption)
                        } else if let date=try? GameDate(player.gameDate) {
                            Text("다음 무소속 확인 창 · "+state.nextMarketWindow(after:date,hasMembership:false).start.description+" · 자격 심사 별도").font(.subheadline).foregroundStyle(GameTheme.gold)
                        }
                        Text("평가 창: 4·7·11월 1~14일. 국내 재입단은 4·7월, 재학생 프로 지원·프로 갱신/이적은 11월에 자격을 확인합니다. 날짜는 홈에서 진행합니다.").font(.caption).lineSpacing(5)
                        OverseasReleasePanel(player:player,calendar:calendar)
                        DomesticReleasePanel(player:player,calendar:calendar)
                        FAManagementPanel(player:player,calendar:calendar)
                    }
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("계약 시장").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
    }
}


struct DomesticMarketCards:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let entries:[DomesticMarketEntry]
    let showHistory:Bool
    @Environment(\.modelContext) private var context
    var body:some View {
        ForEach(entries.filter {showHistory || $0.visible}) {entry in
            GamePanel(title:entry.label,onBoard:true,contentSpacing:12) {
                ClubFileHeader(name:entry.name,subtitle:DomesticContractOffer.roleName(entry.roleID))
                Text(entry.status).font(.headline).foregroundStyle(GameTheme.gold).padding(10).frame(maxWidth:.infinity,alignment:.leading)
                    .background(GameTheme.navy,in:ManagementStepFrame()).overlay {ManagementStepFrame().strokeBorder(GameTheme.gold,lineWidth:2)}.accessibilityIdentifier("domesticMarketStatus")
                Text(entry.period).font(.subheadline).lineSpacing(4)
                ContractTermsTimeline(issued:entry.issued,expires:entry.expires,effective:entry.renewal?.offer?.effectiveDate ?? "상세에서 확인")
                Text("출전 보장 없음 · 상세에서 소속/등록 조건 확인").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                Text(entry.economicLabel+" \(entry.economicIndex)").font(.title2.monospacedDigit().bold()).padding(.vertical,8).accessibilityIdentifier("domesticMarketEconomic")
                if let amount = entry.signingBonusWon { SigningBonusOfferAmount(amount: amount) }
                if let renewal=entry.renewal {
                    NavigationLink {DomesticRenewalDetail(player:player,calendar:calendar,value:renewal,evaluatedDate:entry.issued)} label: {Text("잔류 조건 · 결정")}.buttonStyle(MatchPixelButtonStyle())
                } else if let evaluation=try? ContractEvaluationStore.records(player:player,calendar:calendar,in:context).first(where:{$0.key == entry.evaluationKey}) {
                    NavigationLink {DomesticOffersView(player:player,calendar:calendar,evaluation:evaluation,page:.detail(entry.id))} label: {Text("제의 상세 · 결정")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("domesticMarketDetail")
                }
            }
        }
    }
}
