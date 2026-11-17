import SwiftUI
import SwiftData

struct CareerJournalView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let schools: [School]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState(for: .voiceOver) private var focusedEntryID: String?
    @State private var filter = Filter.all
    @State private var loadState = LoadState.loading
    @State private var selection: CareerJournal.Entry?
    @State private var lastOpenedID: String?

    private enum LoadState {
        case loading, ready([CareerJournal.Day]), failed
    }

    private enum Filter: String, CaseIterable {
        case all, game, training, scout, contract, award

        var kind: CareerJournal.Kind? {
            switch self {
            case .all: nil
            case .game: .match
            case .training: .training
            case .scout: .scouting
            case .contract: .contract
            case .award: .award
            }
        }

        var title: String { kind?.label ?? "전체" }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch loadState {
            case .loading:
                ProgressView("일지 불러오는 중")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                failure
            case .ready(let days):
                timeline(days)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameTheme.board.ignoresSafeArea())
        .foregroundStyle(GameTheme.boardInk)
        .navigationTitle("커리어 일지")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ManagementToolbarAction(title: "기록으로", identifier: "closeCareerJournal") { dismiss() }
        }
        .toolbarBackground(GameTheme.board, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if case .loading = loadState { load() }
        }
        .sheet(item: $selection, onDismiss: { focusedEntryID = lastOpenedID }) { entry in
            NavigationStack {
                CareerJournalDetail(entry: entry, player: player, calendar: calendar, schools: schools)
                    .toolbar {
                        ManagementToolbarAction(title: "목록으로", identifier: "closeCareerJournalDetail") {
                            selection = nil
                        }
                    }
                    .toolbarBackground(GameTheme.board, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .environment(\.careerCompletionNavigation, nil)
            .environment(\.careerMatchVisibility, nil)
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
        }
    }

    private func load() {
        do {
            loadState = .ready(try CareerJournal.load(player: player, calendar: calendar, schools: schools, in: context))
        } catch {
            loadState = .failed
        }
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            Text("저장된 일지를 불러올 수 없습니다.")
                .managementFont(.body)
                .accessibilityIdentifier("careerJournalError")
            Button("다시 확인", action: load)
                .buttonStyle(ManagementButtonStyle(variant: .secondary, compact: true))
                .accessibilityIdentifier("careerJournalRetry")
        }
        .padding(ManagementTheme.Space.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func visibleDays(_ days: [CareerJournal.Day]) -> [CareerJournal.Day] {
        guard let kind = filter.kind else { return days }
        return days.compactMap { day in
            let entries = day.entries.filter { $0.kind == kind }
            return entries.isEmpty ? nil : CareerJournal.Day(date: day.date, entries: entries)
        }
    }

    private func timeline(_ days: [CareerJournal.Day]) -> some View {
        let visible = visibleDays(days)
        let count = visible.reduce(0) { $0 + $1.entries.count }
        return VStack(spacing: 0) {
            filterBar
            ViewThatFits(in: .horizontal) {
                HStack {
                    countLabel(count)
                    Spacer(minLength: ManagementTheme.Space.inline)
                    Text("최신 날짜부터")
                }
                VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                    countLabel(count)
                    Text("최신 날짜부터")
                }
            }
            .managementFont(.helper)
            .foregroundStyle(GameTheme.boardMuted)
            .padding(.horizontal, ManagementTheme.Space.screen)
            .padding(.bottom, ManagementTheme.Space.inline)

            ScrollView {
                if visible.isEmpty {
                    Text(filter == .all ? "아직 저장된 주요 기록이 없습니다." : "이 유형으로 저장된 기록이 없습니다.")
                        .managementFont(.body)
                        .foregroundStyle(GameTheme.boardMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ManagementTheme.Space.screen)
                        .accessibilityIdentifier("careerJournalEmpty")
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visible) { day in
                            dayHeader(day.date)
                            ForEach(day.entries) { entry in
                                eventRow(entry)
                            }
                        }
                    }
                }
            }
            .id(filter)
            .accessibilityIdentifier("careerJournalList")
            .background(GameTheme.boardPanel)
        }
    }

    private func countLabel(_ count: Int) -> some View {
        Text("\(count)건")
            .monospacedDigit()
            .accessibilityIdentifier("careerJournalCount")
    }

    private var filterBar: some View {
        Group {
            if typeSize < .xxLarge {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ManagementTheme.Space.micro) { filters }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                              spacing: ManagementTheme.Space.micro) { filters }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 135 : 100))],
                          spacing: ManagementTheme.Space.micro) {
                    filters
                }
            }
        }
        .padding(.horizontal, ManagementTheme.Space.inline)
        .padding(.vertical, ManagementTheme.Space.inline)
    }

    private var filters: some View {
        ForEach(Filter.allCases, id: \.self) { item in
            Button {
                filter = item
            } label: {
                Text(item.title)
                    .managementFont(.label)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: item == .scout ? 56 : 44, maxWidth: .infinity, minHeight: ManagementTheme.Control.hit)
                    .foregroundStyle(filter == item ? GameTheme.navy : GameTheme.boardInk)
                    .background(filter == item ? GameTheme.gold : GameTheme.boardPanel, in: ManagementStepFrame())
                    .overlay {
                        ManagementStepFrame().strokeBorder(filter == item ? GameTheme.gold : GameTheme.boardLine)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("careerJournalFilter-" + item.rawValue)
            .accessibilityAddTraits(filter == item ? .isSelected : [])
        }
    }

    private func dayHeader(_ date: GameDate) -> some View {
        Text(ManagementDisplay.date(date.description, includeYear: true))
            .managementFont(.label)
            .foregroundStyle(GameTheme.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ManagementTheme.Space.screen)
            .padding(.vertical, ManagementTheme.Space.inline)
            .background(GameTheme.board)
            .overlay(alignment: .bottom) { Rectangle().fill(GameTheme.boardLine).frame(height: 1) }
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("careerJournalDate-" + date.description)
            .accessibilityValue(date.description)
    }

    private func eventRow(_ entry: CareerJournal.Entry) -> some View {
        let featured = entry.emphasis != nil
        let label = [entry.kind.label, entry.title, entry.summary].filter { !$0.isEmpty }.joined(separator: ", ")
        let value = entry.emphasis.map { "핵심 기록 · " + $0 } ?? ""
        return Button {
            lastOpenedID = entry.id
            selection = entry
        } label: {
            JournalEventLabel(entry: entry)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(GameTheme.boardLine.opacity(0.45)).frame(height: 1).allowsHitTesting(false) }
        .overlay(alignment: .leading) {
            if featured { Rectangle().fill(GameTheme.gold).frame(width: ManagementTheme.Control.border).allowsHitTesting(false) }
        }
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint("저장된 상세를 확인합니다")
        .accessibilityIdentifier("careerJournalEvent-" + entry.id)
        .accessibilityFocused($focusedEntryID, equals: entry.id)
    }
}

private struct JournalEventLabel: View {
    let entry: CareerJournal.Entry
    @Environment(\.dynamicTypeSize) private var typeSize

    private var featured: Bool { entry.emphasis != nil }

    var body: some View {
        HStack(alignment: .top, spacing: ManagementTheme.Space.compact) {
            details.frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize { decoration }
        }
        .padding(.horizontal, ManagementTheme.Space.screen)
        .padding(.vertical, ManagementTheme.Space.compact)
        .frame(minHeight: ManagementTheme.Control.hit)
        .background(featured ? GameTheme.gold.opacity(0.055) : .clear)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ManagementTheme.Space.inline) { category }
                VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) { category }
            }
            Text(entry.title)
                .managementFont(.body)
                .bold(featured)
                .foregroundStyle(GameTheme.boardInk)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .managementFont(.helper)
                    .foregroundStyle(GameTheme.boardMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var decoration: some View {
        HStack(spacing: ManagementTheme.Space.inline) {
            if featured {
                eventIcon
                    .padding(ManagementTheme.Space.micro)
                    .background(GameTheme.gold.opacity(0.13), in: ManagementStepFrame())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(featured ? GameTheme.gold : GameTheme.boardMuted)
        }
        .padding(.top, ManagementTheme.Space.micro)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var eventIcon: some View {
        if entry.kind == .award {
            LeagueTrophyPixel().frame(width: ManagementTheme.Control.tabIcon, height: ManagementTheme.Control.tabIcon)
        } else {
            ManagementMenuIcon(tab: entry.kind.icon, size: ManagementTheme.Control.tabIcon)
        }
    }

    @ViewBuilder private var category: some View {
        Text(entry.kind.label)
            .managementFont(.helper)
            .foregroundStyle(GameTheme.boardMuted)
        if let emphasis = entry.emphasis {
            Text(emphasis)
                .managementFont(.helper)
                .bold()
                .foregroundStyle(GameTheme.gold)
                .padding(.horizontal, ManagementTheme.Space.micro)
                .padding(.vertical, 2)
                .overlay { ManagementStepFrame().strokeBorder(GameTheme.gold.opacity(0.7)) }
        }
    }
}

private extension CareerJournal.Kind {
    var icon: ManagementTab {
        switch self {
        case .match: .game
        case .training: .training
        case .scouting, .contract, .award: .career
        }
    }
}

private struct CareerJournalDetail: View {
    let entry: CareerJournal.Entry
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let schools: [School]

    var body: some View {
        switch entry.destination {
        case .match(let key):
            CareerGameView(player: player, calendar: calendar, schools: schools, historyRecordKey: key)
        case .training(let key):
            CareerTrainingHistoryView(player: player, recordKey: key)
        case .scouting(let detail):
            CareerJournalScoutView(detail: detail, date: entry.date)
        case .contract(let detail):
            CareerJournalContractView(detail: detail, date: entry.date)
        case .award(let record):
            CareerJournalAwardView(record: record, date: entry.date, player: player, schools: schools)
        case .awardPending(let board):
            CareerJournalPendingAwardView(board: board, date: entry.date, player: player, schools: schools)
        }
    }
}

private struct CareerJournalAwardView: View {
    let record: CareerSeasonAwardRecord
    let date: GameDate
    let player: CareerPlayer
    let schools: [School]

    private var personalCount: Int {
        let selected = record.bestNine?.slots.contains {
            $0.winner?.playerID == player.id.uuidString && $0.winner?.teamID == record.teamID
        } == true
        let glove = record.goldGlove?.slots.contains {
            $0.winner?.playerID == player.id.uuidString && $0.winner?.teamID == record.teamID
        } == true
        return record.personalHonors.count + (selected ? 1 : 0) + (glove ? 1 : 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                JournalDetailHeader(date: date, title: "\(String(record.year)) \(record.leagueLabel) 시즌 시상",
                                    status: personalCount > 0 ? "내 수상 \(personalCount)개" : nil,
                                    highlighted: personalCount > 0, identifier: "careerJournalAward")
                ManagementPanel("리그 시상 결과") {
                    SeasonAwardLeaders(honors: record.honors, unresolvedKinds: record.unresolvedKinds,
                                       player: player, schools: schools, identifier: "careerJournalAward")
                }
                SeasonBestNinePanel(record: record, player: player, schools: schools, identifier: "careerJournalBestNine")
                SeasonGoldGlovePanel(record: record, player: player, schools: schools, identifier: "careerJournalGoldGlove")
            }
            .padding(ManagementTheme.Space.screen)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(GameTheme.board)
        .foregroundStyle(GameTheme.boardInk)
        .accessibilityIdentifier("careerJournalAwardScroll")
        .navigationTitle("시즌 시상 기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CareerJournalPendingAwardView: View {
    let board: CareerSeasonAwardBoard
    let date: GameDate
    let player: CareerPlayer
    let schools: [School]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                let league = CareerSeasonAwardRecord.leagueLabel(board.competition)
                JournalDetailHeader(date: date, title: "\(String(board.year)) \(league) 시즌 시상",
                                    status: nil, highlighted: false, identifier: "careerJournalAward")
                SeasonBestNinePanel(board: board, player: player, schools: schools, identifier: "careerJournalBestNine")
                SeasonGoldGlovePanel(board: board, player: player, schools: schools, identifier: "careerJournalGoldGlove")
            }
            .padding(ManagementTheme.Space.screen)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(GameTheme.board)
        .foregroundStyle(GameTheme.boardInk)
        .accessibilityIdentifier("careerJournalAwardScroll")
        .navigationTitle("시즌 시상 기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CareerJournalScoutView: View {
    let detail: CareerJournal.ScoutDetail
    let date: GameDate

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsAllClubs = false
    private let previewCount = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                JournalDetailHeader(date: date, title: detail.title, status: detail.status,
                                    highlighted: !detail.clubs.isEmpty, identifier: "careerJournalScout")
                if !detail.clubs.isEmpty { clubs }
                JournalFactsDisclosure(title: "당시 경기 표본", facts: detail.samples,
                                       emptyMessage: "당시 경기 표본이 저장되지 않았습니다.", identifier: "careerJournalScoutSample")
                JournalFactsDisclosure(title: "평가 근거", facts: detail.evidence,
                                       emptyMessage: "당시 평가 근거가 저장되지 않았습니다.", identifier: "careerJournalScoutEvidence")
            }
            .padding(ManagementTheme.Space.screen)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("careerJournalScoutScroll")
        .background(GameTheme.board)
        .foregroundStyle(GameTheme.boardInk)
        .navigationTitle("스카우트 기록")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var clubs: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            ForEach(detail.clubs.prefix(showsAllClubs ? detail.clubs.count : previewCount)) { club in
                clubRow(club)
            }
            if detail.clubs.count > previewCount {
                HomeDetailButton(title: showsAllClubs ? "추가 구단 접기" : "나머지 \(detail.clubs.count - previewCount)곳 보기",
                                 expanded: $showsAllClubs, identifier: "careerJournalScoutMoreClubs")
                    .padding(.horizontal, ManagementTheme.Space.compact)
                    .background(GameTheme.boardPanel, in: ManagementStepFrame())
            }
        }
    }

    private func clubRow(_ club: CareerJournal.ScoutClub) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ManagementTheme.Space.inline))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ManagementTheme.Space.compact))
        return layout {
            JournalClubCrest(teamID: club.teamID, name: club.name, size: 48, identifier: "careerJournalScoutCrest")
            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                Text(club.name).managementFont(.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("careerJournalScoutClubName")
                if let role = club.role {
                    Text(role).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("careerJournalScoutRole")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stageBadge(club.stage)
        }
        .padding(ManagementTheme.Space.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.boardPanel, in: ManagementStepFrame())
        .overlay { ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("careerJournalScoutClub-" + club.id)
    }

    private func stageBadge(_ level: ScoutingInterestLevel) -> some View {
        let color: Color = switch level {
        case .priority: GameTheme.gold
        case .focused: GameTheme.growth
        case .observing: GameTheme.boardMuted
        }
        return Text(level.label).managementFont(.label).foregroundStyle(color)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .padding(.horizontal, ManagementTheme.Space.inline)
            .padding(.vertical, ManagementTheme.Space.micro)
            .background(color.opacity(0.08), in: ManagementStepFrame())
            .overlay { ManagementStepFrame().strokeBorder(color.opacity(0.72)).allowsHitTesting(false) }
            .accessibilityIdentifier("careerJournalScoutStage")
    }
}

private struct CareerJournalContractView: View {
    let detail: CareerJournal.ContractDetail
    let date: GameDate

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let additionalDates = detail.dates.filter { $0.date != date.description }
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                JournalDetailHeader(date: date, title: detail.title, status: detail.documentStatus == nil ? detail.status : nil,
                                    highlighted: !detail.terms.isEmpty, identifier: "careerJournalContract")
                if detail.terms.isEmpty, let club = detail.reviewedClub {
                    ManagementPanel("평가 대상 구단") {
                        clubHeader(club, subtitle: nil, reviewed: true)
                    }
                }
                ForEach(detail.terms) { terms in
                    if let status = detail.documentStatus {
                        document(terms, status: status)
                    } else {
                        offer(terms)
                    }
                }
                if detail.terms.count != 1, !additionalDates.isEmpty {
                    ManagementPanel("기록 일정") { timeline(additionalDates) }
                }
                if !detail.evidence.isEmpty {
                    JournalFactsDisclosure(title: "평가 근거", facts: detail.evidence, identifier: "careerJournalContractEvidence")
                }
            }
            .padding(ManagementTheme.Space.screen)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("careerJournalContractScroll")
        .background(GameTheme.board)
        .foregroundStyle(GameTheme.boardInk)
        .navigationTitle("계약 기록")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func document(_ terms: CareerJournal.ContractTerms, status: String) -> some View {
        TransferContractDocument(terms: .init(
            clubID: terms.club.id,
            clubName: terms.club.name,
            league: terms.kind,
            role: terms.role,
            period: terms.period,
            economicLabel: terms.economicLabel,
            economicIndex: terms.economicIndex,
            signingBonusWon: terms.signingBonusWon,
            origin: terms.origin,
            dates: orderedDates(detail.dates + terms.dates).map { .init(label: $0.label, date: $0.date) },
            status: status,
            salaryRank: terms.salaryStanding.map(TransferContractDocument.SalaryRank.init)
        ), identifier: "careerJournalContract")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("careerJournalContractOffer-" + terms.id)
    }

    private func offer(_ terms: CareerJournal.ContractTerms) -> some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            clubHeader(terms.club, subtitle: terms.kind)
            rule
            Text("주요 조건").managementFont(.label).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ManagementTheme.Space.inline) { metrics(terms, wrap: false) }
                VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) { metrics(terms, wrap: true) }
            }
            if let role = terms.role { termNote("역할", role).accessibilityIdentifier("careerJournalContractMetric-role") }
            if let period = terms.period { termNote("계약 기간", period) }
            let dates = detail.terms.count == 1 ? detail.dates + terms.dates : terms.dates
            if !dates.isEmpty {
                rule
                Text("계약 일정").managementFont(.label).accessibilityAddTraits(.isHeader)
                timeline(dates)
            }
        }
        .padding(ManagementTheme.Space.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.boardPanel, in: ManagementStepFrame())
        .overlay { ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("careerJournalContractOffer-" + terms.id)
    }

    private func clubHeader(_ club: CareerJournal.ContractClub, subtitle: String?, reviewed: Bool = false) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ManagementTheme.Space.inline))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ManagementTheme.Space.compact))
        return layout {
            JournalClubCrest(teamID: club.id, name: club.name, size: 52,
                             identifier: reviewed ? "careerJournalContractReviewedCrest" : "careerJournalContractCrest")
            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                Text(club.name).managementFont(.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(reviewed ? "careerJournalContractReviewedClub" : "careerJournalContractClubName")
                if let subtitle {
                    Text(subtitle).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func metrics(_ terms: CareerJournal.ContractTerms, wrap: Bool) -> some View {
        if let amount = terms.signingBonusWon {
            let digits = amount.formatted(.number.locale(Locale(identifier: "ko_KR")))
            metric("제의 계약금 (원)", digits, id: "bonus", wrap: wrap,
                   spoken: "제의 계약금, " + SigningBonusDisplay.won(amount))
        }
        metric(terms.economicLabel, String(terms.economicIndex), id: "index", wrap: wrap)
    }

    private func metric(_ label: String, _ value: String, id: String, wrap: Bool, spoken: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
            Text(label).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
            Text(value).managementFont(.sectionTitle).monospacedDigit().foregroundStyle(GameTheme.gold)
        }
        .fixedSize(horizontal: !wrap, vertical: true)
        .padding(ManagementTheme.Space.inline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.navy, in: ManagementStepFrame())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken ?? "\(label), \(value)")
        .accessibilityIdentifier("careerJournalContractMetric-" + id)
    }

    private func orderedDates(_ dates: [CareerJournal.ContractDate]) -> [CareerJournal.ContractDate] {
        var seen = Set<CareerJournal.ContractDate>()
        return dates.filter { seen.insert($0).inserted }.enumerated().sorted {
            ($0.element.date, $0.offset) < ($1.element.date, $1.offset)
        }.map(\.element)
    }

    private func timeline(_ dates: [CareerJournal.ContractDate]) -> some View {
        return VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            ForEach(orderedDates(dates), id: \.self) { point in
                HStack(alignment: .top, spacing: ManagementTheme.Space.inline) {
                    Rectangle().fill(GameTheme.gold).frame(width: 5, height: 5)
                        .padding(.top, ManagementTheme.Space.inline).accessibilityHidden(true)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: ManagementTheme.Space.inline) {
                            dateLabel(point.label)
                            Spacer(minLength: ManagementTheme.Space.inline)
                            dateValue(point, wrap: false)
                        }
                        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                            dateLabel(point.label)
                            dateValue(point, wrap: true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("careerJournalContractDates")
    }

    private func dateLabel(_ label: String) -> some View {
        Text(label).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
    }

    private func dateValue(_ point: CareerJournal.ContractDate, wrap: Bool) -> some View {
        let formatted = ManagementDisplay.date(point.date, includeYear: true)
        return Text(typeSize.isAccessibilitySize ? point.date : formatted).managementFont(.label).monospacedDigit()
            .fixedSize(horizontal: !wrap, vertical: true)
            .accessibilityLabel(formatted)
            .accessibilityIdentifier("careerJournalContractDate-" + point.date)
            .accessibilityValue(point.date)
    }

    private func termNote(_ label: String, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ManagementTheme.Space.micro))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ManagementTheme.Space.compact))
        return layout {
            Text(label).managementFont(.helper).foregroundStyle(GameTheme.boardMuted).fixedSize()
            Text(value).managementFont(.label).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true)
    }
}

struct JournalDetailHeader: View {
    let date: GameDate
    let title: String
    let status: String?
    let highlighted: Bool
    let identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let formatted = ManagementDisplay.date(date.description, includeYear: true)
        VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
            Text(typeSize.isAccessibilitySize ? date.description : formatted)
                .managementFont(.label)
                .foregroundStyle(GameTheme.boardMuted)
                .accessibilityLabel(formatted)
                .accessibilityIdentifier("careerJournalDetailDate")
                .accessibilityValue(date.description)
            if typeSize.isAccessibilitySize {
                headline
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ManagementTheme.Space.compact) { headline }
                    VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) { headline }
                }
            }
        }
        .padding(ManagementTheme.Space.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.boardPanel)
        .overlay(alignment: .leading) {
            Rectangle().fill(highlighted ? GameTheme.gold : GameTheme.boardLine)
                .frame(width: ManagementTheme.Control.border).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var headline: some View {
        Text(title).managementFont(.screenTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier + "Title")
        if let status {
            Text(status).managementFont(.label)
                .padding(.horizontal, ManagementTheme.Space.inline)
                .padding(.vertical, ManagementTheme.Space.micro)
                .foregroundStyle(highlighted ? GameTheme.navy : GameTheme.boardInk)
                .background(highlighted ? GameTheme.gold : ManagementTheme.Palette.control, in: ManagementStepFrame())
                .accessibilityIdentifier(identifier + "Status")
        }
    }
}

private struct JournalClubCrest: View {
    let teamID: String
    let name: String
    let size: CGFloat
    let identifier: String

    var body: some View {
        if let identity = ClubIdentity.resolve(teamID: teamID) {
            Image(identity.asset).interpolation(.none).resizable().scaledToFit()
                .padding(ManagementTheme.Space.micro).frame(width: size, height: size)
                .background(ManagementTheme.Palette.control, in: ManagementStepFrame())
                .accessibilityLabel(name + " 엠블럼")
                .accessibilityIdentifier(identifier)
        }
    }
}

private struct JournalFactsDisclosure: View {
    let title: String
    let facts: [CareerJournal.Fact]
    var emptyMessage: String? = nil
    let identifier: String

    var body: some View {
        JournalDisclosure(title: title, identifier: identifier) {
            if facts.isEmpty, let emptyMessage {
                Text(emptyMessage).managementFont(.body).foregroundStyle(GameTheme.boardMuted)
            }
            VStack(alignment: .leading, spacing: ManagementTheme.Space.inline) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 {
                        Rectangle().fill(GameTheme.boardLine.opacity(0.55)).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                        Text(fact.label).managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                        Text(fact.value).managementFont(.body).lineSpacing(3)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(identifier + "BodyFact-\(index)")
                }
            }
        }
    }
}

struct JournalDisclosure<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: ManagementTheme.Space.inline) {
                    Text(title).managementFont(.label)
                    Spacer(minLength: ManagementTheme.Space.inline)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.bold()).foregroundStyle(GameTheme.gold).accessibilityHidden(true)
                }
                .padding(.horizontal, ManagementTheme.Space.screen)
                .frame(minHeight: ManagementTheme.Control.hit)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "펼침" : "접힘")
            .accessibilityIdentifier(identifier)
            if isExpanded {
                VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
                    Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true)
                    content()
                }
                .padding([.horizontal, .bottom], ManagementTheme.Space.screen)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier + "Body")
            }
        }
        .background(GameTheme.boardPanel, in: ManagementStepFrame())
        .overlay { ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1).allowsHitTesting(false) }
    }
}
