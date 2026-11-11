import SwiftUI
import SwiftData

enum SigningBonusDisplay {
    private static let number = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "ko_KR"))

    static func won(_ amount: Int) -> String {
        amount.formatted(number) + "원"
    }

    static func range(_ forecast: SigningBonusForecast) -> String {
        forecast.lowerWon.formatted(number) + " ~ " + won(forecast.upperWon)
    }
}

struct SigningBonusOfferAmount: View {
    let amount: Int?
    var paper = false

    var body: some View {
        ContractTermsMetric(title: "확정 계약금", value: amount.map(SigningBonusDisplay.won) ?? "미기록",
                            note: amount == nil ? "발행 원본" : "게임 내 자금 · 발효일에 한 번 입금", paper: paper,
                            valueIdentifier: "signingBonusOfferAmount")
    }
}

struct ScoutSigningBonusQuote: View {
    let forecast: SigningBonusForecast?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("예상 계약금 · 관찰일 기준").font(.caption.bold())
            Text(forecast.map(SigningBonusDisplay.range) ?? "미산정")
                .managementFont(.body).bold().monospacedDigit()
                .accessibilityIdentifier(identifier)
            if forecast != nil {
                Text("제의 전 예상 범위 · 확정 금액은 제의에서 확인").font(.caption)
            }
        }
        .foregroundStyle(ScoutDossierInk.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ScoutDossierInk.rule.opacity(0.2), in: ManagementStepFrame())
        .overlay { ManagementStepFrame().strokeBorder(ScoutDossierInk.rule, lineWidth: 1) }
    }
}

struct ScoutingFundsView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState

    var body: some View {
        ScrollView {
            ScoutingFundsPanel(player: player, calendar: calendar).padding(16)
        }
        .background(GameTheme.board)
        .navigationTitle("내 자금 관리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.board, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accessibilityIdentifier("scoutFundsScroll")
    }
}

struct ScoutingFundsPanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var snapshot: Snapshot?
    @State private var failure: String?
    @State private var saved = false

    private struct Snapshot {
        let finances: CareerFinances
        let date: String
        let revision: Int
    }

    private enum Budget: String {
        case training, living
        var title: String { self == .training ? "훈련" : "생활" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot {
                let finances = snapshot.finances
                balance(finances.balanceWon)
                payments("확정 입금 예정", entries: finances.pending, pending: true)
                payments("거래 내역", entries: Array(finances.transactions.reversed()), pending: false)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scoutingFundsLedger")
                allocation(snapshot)
                DisclosureGroup("예상액과 입금 기준") {
                    Text("관심 구단의 예상액은 관찰일 기준입니다. 수락한 신규 계약은 소속 발효일에 한 번 입금됩니다. 지난 계약은 발행 당시 조건을 따릅니다.")
                        .managementFont(.helper).padding(.top, 8)
                }
                .foregroundStyle(GameTheme.boardInk).tint(GameTheme.gold)
            } else if let failure {
                ManagementPanel("자금 기록을 확인해 주세요") {
                    Text(failure).managementFont(.body).accessibilityIdentifier("scoutFundsLoadError")
                    Button("다시 확인", action: reload).buttonStyle(ManagementButtonStyle(variant: .secondary))
                }
            } else {
                ProgressView("자금 불러오는 중").tint(GameTheme.gold)
            }
        }
        .task(id: "\(player.id)/\(player.gameDate)/\(calendar.revision)") { reload() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoutFundsPanel")
    }

    private func balance(_ amount: Int) -> some View {
        ManagementPanel("보유 잔액") {
            Text(SigningBonusDisplay.won(amount))
                .managementFont(.sectionTitle).bold().monospacedDigit()
                .foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutingFundsBalance")
            Text("발효를 마친 입금이 반영된 게임 내 자금입니다.").managementFont(.helper)
        }
    }

    private func payments(_ title: String, entries: [SigningBonusTransaction], pending: Bool) -> some View {
        ManagementPanel(title, surface: .paper) {
            if entries.isEmpty {
                Text(pending ? "발효를 기다리는 계약금이 없습니다." : "입금된 계약금이 없습니다.")
                    .managementFont(.body)
            } else {
                ForEach(entries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name).managementFont(.body).bold()
                        Text(ManagementDisplay.date(entry.date) + (pending ? " 발효 예정" : " 계약금 입금"))
                            .managementFont(.helper)
                        Text("+" + SigningBonusDisplay.won(entry.amountWon))
                            .managementFont(.label).bold().monospacedDigit().foregroundStyle(ScoutDossierInk.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier((pending ? "scoutFundsPending-" : "scoutFundsTransaction-") + entry.id)
                }
            }
        }
    }

    private func allocation(_ snapshot: Snapshot) -> some View {
        let finances = snapshot.finances
        return ManagementPanel("잔액 예산 배정", surface: .paper) {
            Text("보유 잔액에서 훈련과 생활에 쓸 몫을 나눕니다. 남은 금액은 예비 자금입니다.")
                .managementFont(.helper)
            if finances.balanceWon > 0 {
                Text("한 번에 최대 \(SigningBonusDisplay.won(allocationStep(finances)))씩 조정합니다.")
                    .managementFont(.helper)
                GeometryReader { geometry in
                    let wonToWidth = geometry.size.width / CGFloat(finances.balanceWon)
                    HStack(spacing: 0) {
                        ScoutDossierInk.green.frame(width: CGFloat(finances.trainingWon) * wonToWidth)
                        GameTheme.gold.frame(width: CGFloat(finances.livingWon) * wonToWidth)
                        ScoutDossierInk.rule.frame(width: CGFloat(finances.unallocatedWon) * wonToWidth)
                    }
                }.frame(height: 8).accessibilityHidden(true)
            }
            budget(.training, amount: finances.trainingWon, snapshot: snapshot)
            budget(.living, amount: finances.livingWon, snapshot: snapshot)
            VStack(alignment: .leading, spacing: 4) {
                Text("예비 자금").managementFont(.label)
                Text(SigningBonusDisplay.won(finances.unallocatedWon)).managementFont(.body).bold().monospacedDigit()
                    .accessibilityIdentifier("scoutingFundsReserve")
            }
            if let failure {
                Text(failure).managementFont(.helper).foregroundStyle(ScoutDossierInk.ink)
                    .accessibilityIdentifier("scoutFundsSaveError")
            } else if saved {
                Text("예산 배정을 저장했습니다.").managementFont(.helper).foregroundStyle(ScoutDossierInk.green)
                    .accessibilityIdentifier("scoutFundsSaved")
            }
        }
    }

    private func allocationStep(_ finances: CareerFinances) -> Int {
        max(10_000, finances.balanceWon / 20)
    }

    private func budget(_ kind: Budget, amount: Int, snapshot: Snapshot) -> some View {
        let step = allocationStep(snapshot.finances)
        let decrease = min(step, amount)
        let increase = min(step, snapshot.finances.unallocatedWon)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title + " 예산").managementFont(.label)
                Text(SigningBonusDisplay.won(amount)).managementFont(.body).bold().monospacedDigit()
                    .accessibilityIdentifier("scoutFundsBudget-" + kind.rawValue)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                budgetButton(kind, symbol: "−", change: -decrease, snapshot: snapshot, increase: false)
                budgetButton(kind, symbol: "+", change: increase, snapshot: snapshot, increase: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func budgetButton(_ kind: Budget, symbol: String, change: Int, snapshot: Snapshot, increase: Bool) -> some View {
        Button(symbol) { allocate(kind, change: change, snapshot: snapshot) }
            .buttonStyle(ManagementButtonStyle(variant: .secondary))
            .frame(width: typeSize.isAccessibilitySize ? nil : 64)
            .disabled(change == 0)
            .accessibilityLabel(kind.title + " 예산 " + (increase ? "늘리기" : "줄이기"))
            .accessibilityHint(change == 0 ? "조정할 수 있는 금액이 없습니다." : SigningBonusDisplay.won(abs(change)))
            .accessibilityIdentifier("scoutingFunds" + kind.rawValue.capitalized + (increase ? "Increase" : "Decrease"))
    }

    private func reload() {
        do {
            snapshot = Snapshot(finances: try ContractRegistrationStore.finances(player: player, calendar: calendar, in: context),
                                date: player.gameDate, revision: calendar.revision)
            failure = nil
        } catch {
            snapshot = nil
            failure = error.localizedDescription
        }
    }

    private func allocate(_ kind: Budget, change: Int, snapshot: Snapshot) {
        let finances = snapshot.finances
        saved = false
        do {
            try ContractRegistrationStore.allocateFunds(player: player, calendar: calendar, date: snapshot.date,
                revision: snapshot.revision, trainingWon: finances.trainingWon + (kind == .training ? change : 0),
                livingWon: finances.livingWon + (kind == .living ? change : 0), in: context)
            reload()
            saved = failure == nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
