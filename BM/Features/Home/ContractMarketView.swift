import SwiftUI
import SwiftData

struct ContractMarketView:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    var focusKBOFA = false
    var focusOverseasFA = false
    @Environment(\.modelContext) private var context
    @State private var showHistory=false
    var body:some View {
        let _=calendar.revision
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                switch Result(catching:{
                    (try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context),
                     try ContractMarketStore.domestic(player:player,calendar:calendar,in:context))
                }) {
                case .failure(let error):Text(error.localizedDescription).accessibilityIdentifier("marketError")
                case .success(let loaded):
                    let owner=loaded.0
                    let domestic=loaded.1.sorted {ContractMarketOrder.precedes(status:$0.status,expires:$0.expires,id:$0.id,otherStatus:$1.status,otherExpires:$1.expires,otherID:$1.id)}
                    let state=owner.overseasCareer ?? OverseasCareerJournal()
                    let entries=state.marketEntries(on:player.gameDate).sorted {ContractMarketOrder.precedes(status:$0.status,expires:$0.offer.expires,id:$0.id,otherStatus:$1.status,otherExpires:$1.offer.expires,otherID:$1.id)}
                    let kboResult=Result(catching:{try KBOTransferStore.snapshot(player:player,calendar:calendar,owner:owner,in:context)})
                    let kbo=try? kboResult.get()
                    let kboAvailable=kbo?.offers.filter(\.canDecide).count ?? 0
                    let available=entries.filter {$0.status == "검토 가능"}.count + domestic.filter {$0.status == "검토 가능"}.count + kboAvailable
                    let hasPending=entries.contains {$0.status == "수락 · 발효 대기"} || domestic.contains {$0.status == "수락 · 발효 대기"}
                        || kbo?.offers.contains {$0.status == "수락 · 발효 대기"} == true
                    if focusKBOFA { kboPanel(kboResult) }
                    if focusOverseasFA {
                        FAManagementPanel(player: player, calendar: calendar, focused: true)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("overseasFAMarket")
                    }
                    GamePanel(title:"CONTRACT MARKET · 계약 시장",onBoard:true,contentSpacing:12) {
                        Text("기준일 "+ManagementDisplay.date(player.gameDate)).font(.footnote.monospacedDigit())
                        Text("검토 가능 \(available)건 · 잔류 / 외부 조건 비교").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("marketSummary")
                        CareerMarketCounts(retention: entries.filter {$0.retention && $0.status == "검토 가능"}.count + domestic.filter {$0.renewal != nil && $0.status == "검토 가능"}.count,
                                           external: entries.filter {!$0.retention && $0.status == "검토 가능"}.count + domestic.filter {$0.renewal == nil && $0.status == "검토 가능"}.count + kboAvailable)
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
                    if !focusKBOFA { kboPanel(kboResult) }
                    ForEach(entries.filter {showHistory || ["검토 가능","수락 · 발효 대기"].contains($0.status)}) {entry in
                        GamePanel(title:entry.retention ? "잔류 제의":"외부 제의",onBoard:true,contentSpacing:12) {
                            ClubFileHeader(name:entry.offer.name,subtitle:entry.offer.route.label+" · "+DomesticContractOffer.roleName(entry.offer.roleID))
                            Text(entry.status).font(.headline).foregroundStyle(GameTheme.gold).padding(10).frame(maxWidth:.infinity,alignment:.leading)
                                .background(GameTheme.navy,in:ManagementStepFrame()).overlay {ManagementStepFrame().strokeBorder(GameTheme.gold,lineWidth:2)}.accessibilityIdentifier("marketOfferStatus")
                            ContractTermsTimeline(issued:entry.offer.issued,expires:entry.offer.expires,effective:entry.offer.effective)
                            ContractTermsMetric(title:"연봉지수",value:String(entry.offer.economicIndex),note:"\(entry.offer.years)년 · 실제 통화/출전 보장 아님")
                            if let rank = state.displayedSalaryStanding(for: entry.offer, reports: owner.overseasReports ?? []) {
                                ContractSalaryRankSummary(standing: rank, identifier: "overseasOffer", offerID: entry.id)
                            }
                            if let amount = entry.offer.signingBonusWon { SigningBonusOfferAmount(amount: amount) }
                            Text("경제 기간 종료 · "+ManagementDisplay.date(entry.offer.economicEnd)).font(.footnote.monospacedDigit())
                            if (state.renewalReviews ?? []).contains(where:{$0.offer?.id == entry.id}) {
                                NavigationLink {OverseasRenewalView(player:player,calendar:calendar,selectedOfferID:entry.id)} label: {Text("잔류 조건 상세 · 결정")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketOfferDecision-"+entry.id)
                            } else {
                                NavigationLink {OverseasContractsView(player:player,calendar:calendar,selectedOfferID:entry.id)} label: {Text(entry.retention ? "잔류 조건 상세 · 결정":"외부 조건 상세 · 결정")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("marketOfferDecision-"+entry.id)
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
                        if !hasPending && available == 0 {
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
                        if !focusOverseasFA { FAManagementPanel(player:player,calendar:calendar) }
                    }
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("계약 시장").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark,for:.navigationBar)
    }

    @ViewBuilder
    private func kboPanel(_ result: Result<KBOTransferStore.Snapshot, any Error>) -> some View {
        switch result {
        case .success(let kbo):
            if kbo.membership?.level == "domestic-first-team" || kbo.declaration != nil || !kbo.offers.isEmpty {
                KBOFirstTeamMarketPanel(player: player, calendar: calendar, market: kbo, showHistory: showHistory)
            }
        case .failure(let error):
            GamePanel(title: "KBO 1군 이적", onBoard: true) {
                Text(error.localizedDescription).accessibilityIdentifier("kboFAMarketError")
            }
        }
    }
}


private struct KBOFirstTeamMarketPanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let market: KBOTransferStore.Snapshot
    let showHistory: Bool
    @Environment(\.modelContext) private var context
    @State private var command: (date: String, revision: Int)?
    @State private var failure: String?

    var body: some View {
        GamePanel(title: "KBO 1군 이적", onBoard: true, contentSpacing: 12) {
            if let membership = market.membership, membership.level == "domestic-first-team" {
                ClubFileHeader(name: membership.name, subtitle: "현재 소속")
                Text("FA 인정 \(market.serviceCount) / \(market.requiredSeasons)시즌")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("kboFAServiceProgress")
                ManagementProgress(title: "FA 인정 시즌", value: ManagementProgressValue(
                    current: Double(market.serviceCount), target: Double(market.requiredSeasons)))
            }
            if let declaration = market.declaration {
                let pending = declaration.effective > player.gameDate
                Text(pending ? "FA 선언 완료 · 권리 해제 예정" : "FA 권리 해제 발효")
                    .font(.headline).foregroundStyle(GameTheme.growth)
                    .accessibilityIdentifier("kboFADeclarationStatus")
                Text(declaration.source.name + " · " + ManagementDisplay.date(declaration.effective, includeYear: true))
                    .font(.footnote).foregroundStyle(GameTheme.boardMuted)
            } else if market.membership?.level == "domestic-first-team" {
                Button("KBO FA 선언") { command = (player.gameDate, calendar.revision) }
                    .buttonStyle(MatchPixelButtonStyle(primary: true))
                    .disabled(!market.canDeclare)
                    .accessibilityIdentifier("kboFADeclare")
            }
            if let notice = market.notice {
                Text(notice).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kboFAMarketNotice")
            }
            if market.declaration != nil || market.canEvaluate {
                Button("KBO 1군 제의 심사") {
                    run {
                        try KBOTransferStore.evaluate(player: player, calendar: calendar,
                            date: player.gameDate, revision: calendar.revision, in: context)
                    }
                }
                .buttonStyle(MatchPixelButtonStyle(primary: true))
                .disabled(!market.canEvaluate)
                .accessibilityIdentifier("kboFAEvaluate")
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("kboFAMarketError")
            }
            if market.canReviewClub || market.clubReview != nil {
                KBOClubReviewPanel(player: player, calendar: calendar, market: market)
            }
            ForEach(market.offers.filter { showHistory || $0.canDecide || $0.status == "수락 · 발효 대기" }, id: \.offer.id) { entry in
                let offer = entry.offer
                VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
                    ClubFileHeader(name: offer.name, subtitle: "이적 제의 · " + DomesticContractOffer.roleName(offer.roleID))
                    Text(entry.status).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        .accessibilityIdentifier("kboFAOfferStatus")
                    Text("연봉지수 \(offer.economicIndex) · \(offer.years)년")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardInk)
                    if let standing = offer.salaryStanding {
                        ContractSalaryRankSummary(standing: standing, identifier: "kboFAOffer", offerID: offer.id)
                    }
                    NavigationLink {
                        KBOFirstTeamOfferDetail(player: player, calendar: calendar, offerID: offer.id)
                    } label: {
                        Text("이적 계약서 보기")
                    }
                    .buttonStyle(MatchPixelButtonStyle())
                    .accessibilityIdentifier("kboFAOffer-" + offer.id)
                }
                .padding(ManagementTheme.Space.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GameTheme.navy, in: ManagementStepFrame())
                .overlay {
                    ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: ManagementTheme.Control.border)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kboFirstTeamMarket")
        .managementConfirmationDialog("KBO FA를 선언할까요?",
            isPresented: Binding(get: { command != nil }, set: { if !$0 { command = nil } }),
            titleVisibility: .visible, showsCancel: false) {
                Button("FA 선언 확정") {
                    guard let pending = command else { return }
                    command = nil
                    run {
                        try KBOTransferStore.declareFA(player: player, calendar: calendar, date: pending.date,
                                                       revision: pending.revision, in: context)
                    }
                }
                .accessibilityIdentifier("kboFAConfirmDeclaration")
                Button("취소", role: .cancel) { command = nil }
        } message: {
            Text("계약 종료와 FA 자격을 확인합니다. 기존 소속과 보유권리는 해제일까지 유지됩니다.")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct KBOClubReviewPanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let market: KBOTransferStore.Snapshot
    @Environment(\.modelContext) private var context
    @State private var confirmation = false
    @State private var failure: String?

    var body: some View {
        GamePanel(title: "KBO 1군 · 시즌 잔류 심사", onBoard: true) {
            if let review = market.clubReview {
                Text(review.outcome.label).font(.headline).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("kboClubReviewStatus")
                let sample = review.role == .pitcher ? review.sample.innings + "이닝" : "\(review.count)타석"
                Text("\(review.sample.games)경기 · \(sample)").font(.subheadline.monospacedDigit())
                if review.count < review.minimum {
                    Text("표본 부족 · 심사 기준 \(review.role == .pitcher ? "12이닝" : "40타석")")
                        .font(.footnote)
                } else {
                    Text(review.role == .pitcher
                         ? "9이닝당 실점 \(String(format: "%.2f", review.performance)) · 잔류 기준 5.50 이하"
                         : "출루율 \(String(format: "%.3f", review.performance)) · 잔류 기준 0.300 이상")
                        .font(.footnote)
                }
                if let end = review.economicEnd, let index = review.economicIndex {
                    Text("연봉지수 \(index) · \(review.effective) ~ \(end)").font(.subheadline)
                    if let standing = review.salaryStanding {
                        ContractSalaryRankSummary(standing: standing, identifier: "kboClubReview", offerID: review.id)
                    }
                } else if review.outcome == .release {
                    Text("소속 해제 예정일 · " + ManagementDisplay.date(review.effective, includeYear: true)).font(.subheadline)
                } else if review.count >= review.minimum {
                    Text("커리어 종료일 이전으로 계약 기간을 정할 수 없습니다.").font(.footnote)
                }
                if market.clubReviewConfirmed {
                    Text("결정 저장 · " + ManagementDisplay.date(review.effective, includeYear: true) + " 발효")
                        .font(.footnote.bold()).foregroundStyle(GameTheme.growth)
                } else if market.canDecideClub {
                    Button(review.outcome == .renew ? "재계약 수락" : "방출 통지 확인") { confirmation = true }
                        .buttonStyle(MatchPixelButtonStyle(primary: true))
                        .accessibilityIdentifier("kboClubOpenDecision")
                }
            } else {
                Text("이번 시즌 공식 경기 성적으로 잔류 조건을 확인합니다.").font(.footnote)
                Button("잔류 심사 열기") {
                    run {
                        try KBOTransferStore.reviewClub(player: player, calendar: calendar, date: player.gameDate,
                            revision: calendar.revision, in: context)
                    }
                }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("kboClubReview")
            }
            if let failure { Text(failure).font(.footnote).foregroundStyle(GameTheme.gold) }
        }
        .managementConfirmationDialog("잔류 심사 결정을 확정할까요?", isPresented: $confirmation, titleVisibility: .visible) {
            if let review = market.clubReview {
                Button(review.outcome == .renew ? "재계약 확정" : "방출 확정",
                       role: review.outcome == .release ? .destructive : nil) {
                    run {
                        try KBOTransferStore.decideClub(player: player, calendar: calendar, reviewID: review.id,
                            date: player.gameDate, revision: calendar.revision, in: context)
                    }
                }.accessibilityIdentifier("kboClubConfirmDecision")
            }
        } message: {
            Text("다음 시즌 개막일에 결정한 조건이 적용됩니다.")
        }
    }

    private func run(_ command: () throws -> Void) {
        do { try command(); failure = nil }
        catch { failure = error.localizedDescription }
    }
}

private struct KBOFirstTeamOfferDetail: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let offerID: String
    @Environment(\.modelContext) private var context
    @State private var command: (accepted: Bool, date: String, revision: Int)?
    @State private var failure: String?

    var body: some View {
        let _ = calendar.revision
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                switch Result(catching: { try KBOTransferStore.snapshot(player: player, calendar: calendar, in: context) }) {
                case .failure(let error):
                    Text(error.localizedDescription).accessibilityIdentifier("kboFAOfferError")
                case .success(let market):
                    if let entry = market.offers.first(where: { $0.offer.id == offerID }) {
                        let offer = entry.offer
                        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                            document(offer: offer, origin: entry.origin, status: entry.status)
                            if entry.canDecide {
                                Button("제의 수락") { command = (true, player.gameDate, calendar.revision) }
                                    .buttonStyle(MatchPixelButtonStyle(primary: true))
                                    .accessibilityIdentifier("kboFAAccept")
                                Button("제의 거절") { command = (false, player.gameDate, calendar.revision) }
                                    .buttonStyle(MatchPixelButtonStyle())
                                    .accessibilityIdentifier("kboFAReject")
                            }
                            if let failure {
                                Text(failure).font(.footnote).foregroundStyle(GameTheme.gold)
                                    .accessibilityIdentifier("kboFAOfferError")
                            }
                        }
                        .managementConfirmationDialog(command?.accepted == false ? "이 제의를 거절할까요?" : "이적 제의를 수락할까요?",
                            isPresented: Binding(get: { command != nil }, set: { if !$0 { command = nil } }),
                            titleVisibility: .visible, showsCancel: false) {
                                Button(command?.accepted == false ? "거절 확정" : "수락 확정") { decide() }
                                    .accessibilityIdentifier("kboFAConfirm")
                                Button("취소", role: .cancel) { command = nil }
                        } message: {
                            if command?.accepted == false {
                                Text(offer.name + " 제의를 종료합니다.")
                            } else {
                                Text(ManagementDisplay.date(offer.effective, includeYear: true) + "부터 " + offer.name + "로 등록됩니다.")
                            }
                        }
                    } else {
                        Text("선택한 제의를 찾을 수 없습니다. 계약 시장에서 다시 확인하세요.")
                            .accessibilityIdentifier("kboFAOfferError")
                    }
                }
            }
            .padding(ManagementTheme.Space.screen)
        }
        .background(GameTheme.board)
        .foregroundStyle(GameTheme.boardInk)
        .navigationTitle("KBO 이적 계약서")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accessibilityIdentifier("kboFAContractDetail")
    }

    private func document(offer: KBOTransferOffer, origin: String, status: String) -> some View {
        TransferContractDocument(terms: .init(
            clubID: offer.teamID,
            clubName: offer.name,
            league: "KBO 1군",
            role: DomesticContractOffer.roleName(offer.roleID),
            period: "\(offer.years)년 · \(offer.effective) ~ \(offer.economicEnd)",
            economicLabel: "연봉지수",
            economicIndex: offer.economicIndex,
            signingBonusWon: offer.signingBonusWon,
            origin: origin,
            dates: [.init(label: "발행", date: offer.issued), .init(label: "마감", date: offer.expires),
                    .init(label: "소속 발효", date: offer.effective)],
            status: status,
            salaryRank: offer.salaryStanding.map(TransferContractDocument.SalaryRank.init)
        ), identifier: "transferOffer")
    }

    private func decide() {
        guard let pending = command else { return }
        command = nil
        do {
            try KBOTransferStore.decide(player: player, calendar: calendar, offerID: offerID,
                                        accept: pending.accepted, date: pending.date, revision: pending.revision, in: context)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
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
