import SwiftUI
import SwiftData

enum FrozenScoutSection: CaseIterable {
    case summary, abilities, records, clubs
    var title: String { switch self { case .summary: "요약"; case .abilities: "능력·구종"; case .records: "경기·근거"; case .clubs: "관심 구단" } }
}

enum CurrentScoutSection: CaseIterable {
    case abilities, records, archive
    var title: String { switch self { case .abilities: "현재 능력"; case .records: "출전 기록"; case .archive: "관찰 보관함" } }
}

private enum ScoutDeskSection: CaseIterable {
    case interest, funds, basis
    var title: String {
        switch self {
        case .interest: "관심 구단"
        case .funds: "내 자금 관리"
        case .basis: "평가 기준"
        }
    }
}

enum OverseasScoutSection: CaseIterable {
    case summary, clubs, records, growth
    var title: String { switch self { case .summary: "요약·과제"; case .clubs: "관심 구단"; case .records: "성적 비교"; case .growth: "성장 전망" } }
}

enum ObservationReviewSection: CaseIterable {
    case summary, growth, records, projects
    var title: String { switch self { case .summary: "결론·행동"; case .growth: "능력 변화"; case .records: "성적 변화"; case .projects: "관찰 근거" } }
}

private struct V166ScoutSections<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let title: (Selection) -> String
    let identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            Menu {
                ForEach(options, id: \.self) { item in
                    Button { selection = item } label: { Text(title(item)) }
                        .accessibilityIdentifier(identifier + "-" + String(describing: item))
                        .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            } label: {
                HStack(spacing: 12) {
                    Text(title(selection)).managementFont(.label).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").accessibilityHidden(true)
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: ManagementTheme.Control.hit)
                    .foregroundStyle(GameTheme.boardInk)
                    .background(ManagementTheme.Palette.control, in: ManagementStepFrame())
                    .contentShape(ManagementStepFrame())
            }.buttonStyle(.plain)
                .accessibilityLabel("보고서 구역").accessibilityValue(title(selection))
                .accessibilityHint("펼쳐서 확인할 자료를 선택합니다")
                .accessibilityIdentifier(identifier + "Menu")
        } else {
            ManagementSectionTabs(options: options, selection: $selection, title: title, identifier: identifier)
        }
    }
}

struct ScoutingSampleGroup: Identifiable, Codable {
    let id: String
    var totals = PersonalSeasonTotals()
    var performance: MatchScoutingPerformance?
    var hasBatterMinimum: Bool { totals.line.plateAppearances >= 40 }
    var hasPitcherMinimum: Bool { totals.line.pitchingOuts >= 45 }
}

struct ScoutingObservationHomePanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    var archive = false
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \CareerScoutingReport.period, order: .reverse) private var saved: [CareerScoutingReport]
    @State private var error: String?
    @State private var showHistory = false
    @State private var section: ScoutDeskSection = .interest
    @State private var clubSeasons = ScoutClubSeasonContext()
    private var own: [CareerScoutingReport] { saved.filter { $0.playerID == player.id } }
    private func refresh() {
        do {
            try ScoutingObservationStore.ensureCurrent(player: player, calendar: calendar, in: context)
            _ = try ScoutingObservationStore.reports(player: player, calendar: calendar, in: context)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 24 : 16) {
            ScoutDeskHeading(title: archive ? "관찰 파일 · 지난 이력" : "스카우트 데스크", subtitle: "28일마다 남기는 선수의 발자취")
            if !archive {
                V166ScoutSections(options: ScoutDeskSection.allCases, selection: $section,
                                  title: { $0.title }, identifier: "scoutDeskSection")
            }
            if !archive && section == .funds {
                ScoutingFundsPanel(player: player, calendar: calendar)
            } else if !archive && section == .basis {
                ScoutDossier(title: "평가와 계약금", code: "SCOUTING BASIS", stamp: "평가 기준", isPreview: false) {
                    Text("내 역할 기량 H에서 구단 기준 C를 빼고, 검증된 같은 환경의 성적 보정 P를 더해 적합도 F를 구합니다.")
                        .managementFont(.body)
                    Text("관찰일의 기량과 조건은 보고서에 고정됩니다. 시즌 성적은 리그 기록을 표시하고, 우승은 전체 일정의 결과가 확인된 시즌에만 표시합니다.")
                        .managementFont(.body)
                    Text("구단별 예상 계약금은 해당 관찰의 범위입니다. 확정 금액과 발효일은 새 계약 제의에서 확인할 수 있습니다.")
                        .managementFont(.body)
                }
            } else {
                observationContent
            }
        }.padding(16).background(ScoutDeskPalette.surface)
            .overlay(ManagementStepFrame().stroke(GameTheme.boardLine, lineWidth: 2))
            .lineSpacing(typeSize.isAccessibilitySize ? 5 : 3)
            .task(id: "\(player.id)-\(player.gameDate)") { refresh() }
            .task(id: "\(player.id)-\(player.gameDate)-\(calendar.revision)-\(section)-\(own.first?.period ?? -1)") {
                if section == .interest, let interests = try? own.first?.snapshot().interests, !interests.entries.isEmpty {
                    clubSeasons = ScoutClubSeasonContext.load(player: player, calendar: calendar, in: context)
                }
            }
    }

    @ViewBuilder private var observationContent: some View {
            if let error {
                Text(error).font(.body).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutArchiveError")
                Button("보고서 저장 다시 확인", action: refresh).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutArchiveRetry")
            } else if let row = own.first, let value = try? row.snapshot() {
                ScoutObservationFileCover(value: value, schoolID: player.schoolID,
                                          legacySchoolName: player.schoolName, compact: true)
                NavigationLink { SavedScoutingObservationView(value: value, schoolID: player.schoolID, legacySchoolName: player.schoolName, seasons: clubSeasons) } label: {
                    HStack(spacing: 12) {
                        Text("확정 보고서 펼치기").fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("openSavedScoutingReportTitle")
                        Spacer(minLength: 0)
                        Text("›").accessibilityHidden(true)
                    }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("openSavedScoutingReport")
                ScoutingInterestList(value: value, compact: true, seasons: clubSeasons)
                DisclosureGroup("관찰 날짜 · 집계 범위 · 보고서 이력") {
                    ScoutPeriodRibbon(value: value, count: own.count)
                    ScoutObservationDates(value: value, today: player.gameDate)
                }.tint(GameTheme.gold).accessibilityElement(children: .contain).accessibilityIdentifier("scoutDateDetails")
                if archive && own.count > 1 {
                    HomeDetailButton(title: "지난 보고서 \(own.count - 1)건", expanded: $showHistory, identifier: "scoutHistoryDetails")
                    if showHistory {
                        ForEach(own.dropFirst()) { old in
                            if let snapshot = try? old.snapshot() {
                                NavigationLink { SavedScoutingObservationView(value: snapshot, schoolID: player.schoolID, legacySchoolName: player.schoolName, seasons: clubSeasons) } label: {
                                    HStack { Text("FILE \(snapshot.period + 1)").monospaced(); Spacer(); Text(ManagementDisplay.date(snapshot.observedDate)) }
                                }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutHistory-\(snapshot.period)")
                            }
                        }
                    }
                }
            } else {
                Text("현재 주기 보고서 확인 중").font(.body)
            }
            if !archive {
                NavigationLink { ScoutingReportView(player: player, calendar: calendar) } label: { Text("현재 능력 · 출전 자료 보기") }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openScoutingReport")
            }
            DisclosureGroup("보고서 보관과 제의 안내") {
            Text("주기 보고서가 없으면 최초 자료 저장을 확인합니다. 같은 주기는 보존하며 실패 시 위 버튼으로 재시도합니다. 재열기 자체가 매번 저장하는 것은 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("scoutRefreshPolicy")
            Text("관심 구단과 실제 제의는 별개입니다. 자격·심사·제의는 계약 메뉴에서 확인하세요.")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            }.tint(GameTheme.gold)
    }
}

struct ScoutingInterestList: View {
    let value: ScoutingObservation
    var compact = false
    var seasons = ScoutClubSeasonContext()
    @State private var showAll = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let interests = value.interests {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                    Text("관심 구단").font(.headline)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text("\(interests.entries.count)곳").font(.title2.monospaced().bold()).foregroundStyle(GameTheme.gold).accessibilityLabel("관심 구단 \(interests.entries.count)곳").accessibilityIdentifier("scoutInterestCount")
                }
                if interests.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("아직 도착하지 않은 관찰 카드").font(.headline).accessibilityIdentifier("scoutInterestEmpty")
                        if let reason = interests.pendingReasons.first { Text(reason).font(.subheadline).foregroundStyle(GameTheme.boardMuted) }
                        if interests.pendingReasons.count > 1 {
                            DisclosureGroup("추가 확인 조건 \(interests.pendingReasons.count - 1)개") {
                                ForEach(Array(interests.pendingReasons.dropFirst()), id: \.self) { Text($0).font(.subheadline).padding(.top, 8) }
                            }.font(.subheadline).tint(GameTheme.gold)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ScoutDeskPalette.ink).overlay(Rectangle().strokeBorder(GameTheme.boardLine, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                } else {
                    ForEach(compact && !showAll ? Array(interests.entries.prefix(2)) : interests.entries) { entry in
                        ScoutInterestCard(entry: entry, presentation: ScoutingClubPresentation.matching(entry, in: value.contractFit),
                                          forecast: value.signingBonusForecast(clubID: entry.id, roleID: entry.roleID), seasons: seasons)
                    }
                    if compact && interests.entries.count > 2 {
                        HomeDetailButton(title: showAll ? "관심 구단 접기" : "관심 구단 더보기 · 나머지 \(interests.entries.count - 2)곳", expanded: $showAll, identifier: "scoutInterestDetails")
                    }
                }
                Text("\(ManagementDisplay.date(value.observedDate)) 확정 · 다음 \(ManagementDisplay.date(value.nextDate))")
                    .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            } else {
                Text("이전 보고서는 구단 관심을 기록하지 않았습니다. 다음 관찰부터 확인할 수 있습니다.")
                    .font(.subheadline).accessibilityIdentifier("scoutInterestLegacy")
            }
            ScoutStatusTag(text: value.age < 20 ? "진로 준비 · 정식 제의는 20세부터" : "관찰 관심 ≠ 정식 제의", color: GameTheme.gold)
        }
    }
}

struct SavedScoutingObservationView: View {
    let value: ScoutingObservation
    let schoolID: String?
    let legacySchoolName: String?
    var seasons = ScoutClubSeasonContext()
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showOriginals = false
    @State private var showClubs = false
    @State private var section: FrozenScoutSection = .summary
    var body: some View {
        VStack(spacing: 0) {
            V166ScoutSections(options: FrozenScoutSection.allCases, selection: $section,
                              title: { $0.title }, identifier: "frozenScoutSection")
                .padding(16).background(ScoutDeskPalette.ink)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("관찰 확정 · " + ManagementDisplay.date(value.observedDate))
                        .managementFont(.label).accessibilityIdentifier("scoutFrozenDate")
                    if section == .summary {
                        frozenIdentity
                        ManagementPanel("이번 관찰 · 먼저 확인") {
                            Text("확정 자료 · " + ManagementDisplay.date(value.observedDate)).managementFont(.label)
                            if let condition = value.evaluationPending.first {
                                Text(condition).managementFont(.body)
                            } else {
                                Text("기록된 평가 대기 조건 없음 · 제의 여부는 계약 메뉴에서 확인합니다.").managementFont(.body)
                            }
                            Text("현재 능력과 다른 시점의 자료입니다. 관심 구단은 실제 계약 제의와 구분합니다.").managementFont(.helper)
                        }.accessibilityIdentifier("scoutDecisionSummary")
                        DisclosureGroup("선수 정보 · 관찰 원문과 집계 범위") { frozenMetadata }
                            .tint(GameTheme.gold).accessibilityElement(children: .contain).accessibilityIdentifier("scoutFrozenIdentityDetails")
                        reviewConditions
                    } else {
                        v166FrozenCompactIdentity
                    }
                    if section == .clubs {
                        ScoutingInterestList(value: value, seasons: seasons)
                        if let fit = value.contractFit { clubBoard(fit) }
                    }
                    if section == .abilities { roleBoard }
                    if section == .records {
                        frozenSample
                        if let opportunities = value.opportunities, !opportunities.keys.isEmpty {
                            GamePanel(title:"기용과 실제 출전 · 관찰 당시 고정",onBoard:true) {
                                Text("주전 \(opportunities.starts) · 벤치 \(opportunities.bench) · 순번 휴식 \(opportunities.rotationRest)").font(.headline.monospacedDigit()).accessibilityIdentifier("scoutOpportunities")
                                Text("새 기용 규칙으로 완료한 최근365일 경기만 표시합니다. 비출전은 개인 표본·실패 성과로 만들지 않습니다.").font(.subheadline)
                            }
                        }
                        if let fit = value.contractFit {
                            comparisonBoard(fit)
                        } else {
                            ScoutNote(title: "이전 버전 파일", message: "이 보고서는 확정 당시 구단/비교 성적을 기록하지 않았습니다. 원문을 유지하며 다음 관찰부터 새 자료를 확인합니다.", messageIdentifier: "scoutLegacyFit")
                        }
                        DisclosureGroup("선수 프로젝트 · 관찰 근거") {
                            CareerProjectReportEvidence(playerID: value.playerID, period: value.period).padding(.top, 12)
                        }.font(.headline).tint(GameTheme.gold)
                    }
                }.padding(16).fixedSize(horizontal: false, vertical: true)
            }.id(section).accessibilityIdentifier("frozenScoutScroll")
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }
            .lineLimit(nil).lineSpacing(typeSize.isAccessibilitySize ? 5 : 3)
            .background(ScoutDeskPalette.ink).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("확정 관찰 보고서").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
    }
    private var reviewConditions: some View {
        DisclosureGroup("다음 검토 조건 · 계산/계약 절차") {
            VStack(alignment: .leading, spacing: 12) {
                Text("다음 검토를 위한 조건").font(.title3.bold())
                ForEach(value.evaluationPending, id: \.self) { Text($0).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                Text(value.contractFit == nil ? "당시 평가 대기 상태를 보존한 파일입니다." : "역할 기량·성적 적합도는 참고값입니다. 실제 자격·선발 결과·제의는 계약 메뉴에서 확인하세요.")
                    .font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutFrozenPending")
                DisclosureGroup("평가 자료와 계약 절차의 차이") {
                    Text("28일 관찰과 계약 평가 창은 별개입니다. 재조회·시즌 결산으로 제의를 재추첨하지 않습니다.")
                        .font(.subheadline).padding(.top, 8)
                }.font(.subheadline).tint(GameTheme.gold)
            }.fixedSize(horizontal: false, vertical: true)
        }.tint(GameTheme.gold).accessibilityIdentifier("scoutReviewConditions")
    }
    @ViewBuilder private var frozenIdentity: some View {
        if typeSize.isAccessibilitySize {
            v166FrozenSummary
        } else {
            ScoutObservationFileCover(value: value, schoolID: schoolID, legacySchoolName: legacySchoolName)
        }
    }
    private var v166FrozenRole: String {
        value.role == .batter ? FieldPosition(rawValue: value.position)?.label ?? value.position
            : value.hand == "left" ? "좌투" : "우투"
    }
    private var v166FrozenSchool: String {
        if value.age <= 18 { return SchoolCatalog.displayName(id: schoolID, fallback: value.school) }
        return "등록 학교 · " + (value.school == legacySchoolName
            ? SchoolCatalog.displayName(id: schoolID, fallback: value.school) : value.school)
    }
    private var v166FrozenCompactIdentity: some View {
        Text("\(value.name) #\(value.number) · \(value.role.label) · \(v166FrozenRole)")
            .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scoutFrozenCompactIdentity")
    }
    private var v166FrozenSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ManagementPortrait(appearance: value.appearance, role: value.role, number: value.number)
                    .frame(width: 36, height: 40).accessibilityHidden(true)
                Text("\(value.name) #\(value.number)").font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(value.totals.games)경기 · " + (value.role == .batter ? "\(value.totals.line.plateAppearances)타석" : "\(value.totals.innings)이닝"))
                .font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scoutFrozenCoverMetrics")
            Text("\(value.age)세 · \(value.role.label) · \(v166FrozenRole)").font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(v166FrozenSchool).font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("관심 구단 · " + (value.interests.map { "\($0.entries.count)곳" } ?? "미기록"))
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ScoutDossierInk.ink).background(ScoutDossierInk.paper)
            .overlay(Rectangle().strokeBorder(ScoutDossierInk.rule, lineWidth: 1))
            .accessibilityElement(children: .contain).accessibilityIdentifier("scoutFrozenFileCover")
    }
    private var frozenMetadata: some View {
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 16 : 8) {
            Text("주기 \(ManagementDisplay.date(value.periodStart)) ~ \((try? GameDate(value.nextDate).adding(days: -1).description).map(ManagementDisplay.date) ?? "—")")
                .font(.subheadline.monospaced()).fixedSize(horizontal: false, vertical: true)
            Text("성적 집계 "+ManagementDisplay.date(value.sampleStart)+" ~ "+ManagementDisplay.date(value.observedDate)+" · 완료 개인 경기")
                .font(.subheadline).accessibilityIdentifier("scoutFrozenSampleCutoff")
            Text("위 주기 종료일은 관찰 주기의 경계이며 성적 집계 마감일과 다릅니다. 현재 값과 구분해 보관한 당시 자료입니다.")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.padding(.top, typeSize.isAccessibilitySize ? 16 : 8)
            .fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var frozenAbilityCharts: some View {
        ScoutAbilityFileChart(title: "관찰 당시 원본 기량", subtitle: "확정 관찰 · " + ManagementDisplay.date(value.observedDate),
                              values: Array(value.abilities.originals.prefix(4)), identifier: "scoutFrozenVisual")
        if value.role == .pitcher {
            ScoutAbilityFileChart(title: "관찰 당시 구종 · 숙련", subtitle: "같은 확정 파일에 저장된 구종 자료",
                                  values: value.abilities.pitches, identifier: "scoutFrozenPitchVisual")
        }
    }
    private var roleBoard: some View {
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 24 : 16) {
            frozenAbilityCharts
            ScoutDeskHeading(title: "어떤 역할에 가까운가", subtitle: "관찰 당시 역할 기량 H · 100점 기준")
            ForEach(value.grades) { grade in
                VStack(alignment: .leading, spacing: 10) {
                    Text(grade.label + "  " + (grade.score.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "평가 대기"))
                        .font(.headline.monospacedDigit()).accessibilityIdentifier("scoutGrade-\(grade.id)")
                    ScoutSegmentMeter(value: grade.score, maximum: 100, color: GameTheme.growth)
                    DisclosureGroup("역할 기량 구성 보기") { Text(grade.detail).font(.subheadline).padding(.top, 8) }
                        .font(.subheadline).tint(GameTheme.gold)
                }.padding(14).background(ScoutDeskPalette.surface)
            }
            DisclosureGroup("당시 능력 그래프") { HomeRadarChart(values: value.abilities.axes).padding(.top, 16) }
                .font(.headline).tint(GameTheme.gold)
            HomeDetailButton(title: "관찰 당시 원본 능력·구종", expanded: $showOriginals, identifier: "scoutFrozenAbilities")
            if showOriginals { ForEach(value.abilities.originals + value.abilities.pitches) { HomeGrowthRow(value: $0) } }
            DisclosureGroup("H 점수 해석") {
                Text("H는 역할 기초점수95%와 멘탈5%를 조합한 게임 내 기량 참고값입니다. 계약 합격선이나 성공 확률이 아닙니다.")
                    .font(.subheadline).padding(.top, 8)
            }.font(.subheadline).tint(GameTheme.gold)
        }
    }
    private var frozenSample: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoutDeskHeading(title: "그라운드에서 쌓은 증거", subtitle: "\(ManagementDisplay.date(value.sampleStart)) ~ \(ManagementDisplay.date(value.observedDate))")
            CareerEvidenceTag(kind:.official)
            ScoutSeasonTiles(totals: value.totals, role: value.role)
            Text("완료 개인 경기 \(value.totals.games)건 · 미완료 \(value.pending)건 제외")
                .font(.subheadline).accessibilityIdentifier("scoutFrozenSample")
            ForEach(Array(value.groups.enumerated()), id: \.element.id) { index, group in
                ScoutSampleCard(group: group, role: value.role, number: index + 1)
            }
            if value.groups.isEmpty { ScoutNote(title: "출전 자료 대기", message: "완료한 개인 출전이 생기면 다음 관찰에서 표본을 확인합니다.") }
        }
    }
    private func comparisonBoard(_ fit: ScoutingContractFit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoutDeskHeading(title: "같은 경기 환경에서 비교", subtitle: "실제 리그 평균이 아닌 게임 엔진 NPC 기준")
            if fit.comparisons.isEmpty { ScoutNote(title: "성적 보정 P · 중립", message: "완료 개인 경기 자료가 없어 P=0입니다. 성적이 나쁘다는 뜻은 아닙니다.") }
            ForEach(Array(fit.comparisons.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 14) {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top))) {
                        Text("환경 \(index + 1) · 성적 보정 P \(ScoutDeskFormat.signed(row.correction))")
                            .font(.headline).accessibilityIdentifier("scoutComparison-\(index)")
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                        ScoutStatusTag(text: row.verified ? "비교 확인" : "근거 대기", color: row.verified ? GameTheme.growth : GameTheme.gold)
                    }
                    let metricLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                    metricLayout {
                        ScoutValueTile(title: "내 지표", value: ScoutDeskFormat.number(row.value, places: 3))
                        ScoutValueTile(title: "NPC 지표", value: ScoutDeskFormat.number(row.reference?.value, places: 3))
                    }
                    if let inputs = row.performance?.inputs {
                        Text("직접 \(inputs.direct)구 · 자동 \(inputs.automatic)구").font(.subheadline).accessibilityIdentifier("scoutInputUsage-\(index)")
                    }
                    Text(row.reason).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    if let ref = row.reference {
                        DisclosureGroup("비교 표본 보기") {
                            Text("NPC \(ref.totals.games)경기 · " + (value.role == .batter ? "\(ref.totals.line.plateAppearances)타석" : "\(ref.totals.innings)이닝 / \(ref.performance.battersFaced)BF"))
                                .font(.subheadline).padding(.top, 8)
                        }.font(.subheadline).tint(GameTheme.gold)
                    }
                }.padding(14).background(ScoutDeskPalette.surface)
            }
        }
    }
    private func featuredClubs(_ fit: ScoutingContractFit) -> [ScoutingClubFit] {
        let ordered = fit.clubs.filter { $0.recruitment.demand != .none } + fit.clubs.filter { $0.recruitment.demand == .none }
        var names = Set<String>()
        return Array(ordered.filter { names.insert($0.recruitment.name).inserted }.prefix(3))
    }
    private func clubBoard(_ fit: ScoutingContractFit) -> some View {
        let featured = featuredClubs(fit)
        return VStack(alignment: .leading, spacing: 16) {
            ScoutDeskHeading(title: "구단의 기준과 나의 기량", subtitle: "기량 차이와 부족 조건 · 정식 제의는 계약 메뉴")
            ForEach(featured) { club in
                ScoutClubComparisonCard(club: club, roleName: value.grades.first { $0.id == club.recruitment.roleID }?.label ?? club.recruitment.roleID)
            }
            HomeDetailButton(title: "전체 모집 역할·기준·적합도 \(fit.clubs.count)건", expanded: $showClubs, identifier: "scoutClubDetails")
            if showClubs {
                ForEach(fit.clubs.filter { club in !featured.contains(where: { $0.id == club.id }) }) { club in
                    ScoutClubComparisonCard(club: club, roleName: value.grades.first { $0.id == club.recruitment.roleID }?.label ?? club.recruitment.roleID)
                }
            }
            DisclosureGroup("기량 비교를 읽는 방법") {
                Text("F=H−C+P는 부호가 있는 기량 참고값입니다. 성공 확률이 아닙니다. 비교 검증된 환경 중 표본이 가장 큰1개를 사용하며 서로 다른 환경을 합치지 않습니다. 과거 입력 근거가 없으면 P=0 중립입니다. 위치 숙련·원본 수비,나이/진로/권리·등록·예산 심사는 별도입니다.")
                    .font(.subheadline).padding(.top, 8)
            }.font(.subheadline).tint(GameTheme.gold)
        }
    }
}

enum ScoutingReportError: LocalizedError {
    case abilities
    var errorDescription: String? { "선수 능력치 자료를 확인할 수 없습니다. 기존 저장을 유지하고 다시 확인해 주세요." }
}

// Read-only projection. It neither evaluates a club nor persists a scouting report.
@MainActor struct ScoutingReportSnapshot {
    let date: GameDate
    let start: GameDate
    let age: Int
    let abilities: HomeAbilitySummary
    let groups: [ScoutingSampleGroup]
    let totals: PersonalSeasonTotals
    let pending: Int

    static func load(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext) throws -> Self {
        let id = player.id
        let profiles = try context.fetch(FetchDescriptor<PlayerAbilities>(predicate: #Predicate { $0.playerID == id }))
        let records = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id }))
        guard profiles.count == 1 else { throw ScoutingReportError.abilities }
        return try make(player: player, calendar: calendar, profile: profiles[0], records: records)
    }

    static func make(player: CareerPlayer, calendar: CareerCalendarState, profile: PlayerAbilities,
                     records: [CareerMatchRecord]) throws -> Self {
        let date = try GameDate(player.gameDate), origin = try GameDate(calendar.originDate)
        guard calendar.playerID == player.id, origin <= date else { throw CalendarError.staleState }
        let start = max(origin, date.adding(days: -364))
        guard profile.playerID == player.id, PlayerRole(rawValue: player.roleRaw) != nil else { throw ScoutingReportError.abilities }
        _ = try profile.value(for: .mental)
        if player.role == .pitcher {
            for kind in [TrainingKind.velocity, .control, .stuff, .stamina] { _ = try profile.value(for: kind) }
        }
        guard Set(player.pitches.map(\.code)).count == player.pitches.count,
              player.pitches.allSatisfy({ $0.mastery.isFinite && (0...100).contains($0.mastery) }) else { throw ScoutingReportError.abilities }
        let abilities = HomeAbilitySummary(player: player, abilities: profile)
        guard abilities.axes.count == 6, abilities.originals.allSatisfy({ $0.current.isFinite && (0...100).contains($0.current) }) else {
            throw ScoutingReportError.abilities
        }
        // Validate the original league/fixture identity, duplicates, role and saved payload before counting.
        for year in start.year...date.year {
            _ = try AnnualLeagueStore.snapshot(player: player, state: calendar, year: year, records: records)
        }
        var bySource: [String: ScoutingSampleGroup] = [:], total = PersonalSeasonTotals(), pending = 0
        for record in records where record.playerID == player.id {
            let day = try GameDate(record.gameDate)
            guard day >= start && day <= date else { continue }
            let match = try record.snapshot()
            if !record.completed { pending += 1; continue }
            guard record.appearance else { continue }
            // Keep legacy/control/training/field/substitution environments separate. No Vref is invented.
            let versions = [match.controlVersion, match.trainingEffectsVersion, match.detailedFieldVersion, match.fieldStats?.version]
                .map { $0.map(String.init) ?? "legacy" }.joined(separator: "/")
            let legacySource = record.rulesVersion + "/" + versions + (match.pitching == nil ? "/starter" : "/relief-v1")
            let source = match.scoutingPerformance.map { match.scoutingEnvironment ?? (legacySource + "/events\($0.version)-unverified") } ?? legacySource
            var group = bySource[source] ?? ScoutingSampleGroup(id: source)
            if let perf = match.scoutingPerformance {
                if group.performance == nil {group.performance=perf.version == 2 ? .tracked:MatchScoutingPerformance()}
                try group.performance?.add(perf)
            }
            try group.totals.add(match.line); bySource[source] = group
            try total.add(match.line)
        }
        return Self(date: date, start: start, age: try calendar.age(of: player), abilities: abilities,
                    groups: bySource.values.sorted { $0.id < $1.id }, totals: total, pending: pending)
    }
}

struct ScoutingReportView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var report: ScoutingReportSnapshot?
    @State private var affiliation: ManagementPlayerAffiliation?
    @State private var error: String?
    @State private var showOriginals = false
    @State private var section: CurrentScoutSection = .abilities
    @ScaledMetric(relativeTo: .body) private var scaledGap: CGFloat = 16
    private var gap: CGFloat { min(scaledGap, 24) }

    private func load() {
        do {
            report = try ScoutingReportSnapshot.load(player: player, calendar: calendar, in: context)
            affiliation = ManagementPlayerAffiliation.read(player: player, calendar: calendar)
            error = nil
        } catch { report = nil; affiliation = nil; self.error = error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            if report != nil, error == nil {
                V166ScoutSections(options: CurrentScoutSection.allCases, selection: $section,
                                  title: { $0.title }, identifier: "currentScoutSection")
                    .padding(16).background(ScoutDeskPalette.ink)
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        ScoutNote(title: "관찰 자료를 불러오지 못했습니다", message: error, messageIdentifier: "scoutReportError")
                        Button("다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutReportRetry")
                    } else if let report {
                        if section == .abilities {
                            if typeSize.isAccessibilitySize {
                                v166CurrentSummary(report)
                                currentAbilityBoard(report)
                                DisclosureGroup("선수 표지 · 상세 정보") { v166CurrentOriginalDetails(report) }
                                    .font(.subheadline).tint(GameTheme.gold)
                                    .accessibilityElement(children: .contain).accessibilityIdentifier("scoutCurrentIdentityDetails")
                            } else {
                                identity(report)
                                currentAbilityBoard(report)
                            }
                        }
                        if section == .records { currentSampleBoard(report) }
                        if section == .archive {
                        ScoutingObservationHomePanel(player: player, calendar: calendar, archive: true)
                        VStack(alignment: .leading, spacing: 14) {
                            ScoutDeskHeading(title: "계약 검토로 이어지는 길", subtitle: "현재 자료와 확정 관찰 파일은 구분합니다")
                            ScoutStatusTag(text: report.age < 20 ? "20세 나이 조건 대기" : "20세 이상 · 경로별 자격 확인", color: GameTheme.gold)
                            Text(report.age < 20 ? "나이 조건 대기 · 프로 계약 검토는 20세부터입니다." : "나이 조건 20세 이상 · 실제 진로/권리 자격은 계약 메뉴에서 확인하세요.")
                                .font(.body).accessibilityIdentifier("scoutAgeCondition")
                            Text("역할 H·구단 기준 C·성적 보정 P·적합도 F는 확정 보고서의 당시 버전 자료에서 확인합니다.")
                                .font(.subheadline).accessibilityIdentifier("scoutEvaluationPending")
                            DisclosureGroup("고정 보고서와 진로 절차 안내") {
                                Text("같은 주기의 확정 보고서는 갱신하지 않습니다. 구형 보고서는 원문을 유지하며 다음 주기부터 새 기준을 확인합니다. 실제 선발 결과·제의·소속 발효와 대학/무소속 경로는 계약 메뉴에서 확인하세요. 최근365일 표본만으로 진로를 확정하지 않습니다.")
                                    .font(.subheadline).padding(.top, 8)
                            }.font(.subheadline).tint(GameTheme.gold)
                        }
                        }
                        Button("현재 자료 다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutReportRefresh")
                    }
                }.padding(16).fixedSize(horizontal: false, vertical: true)
            }.id(section).accessibilityIdentifier("currentScoutScroll")
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }
            .lineLimit(nil).lineSpacing(typeSize.isAccessibilitySize ? 5 : 3)
            .background(ScoutDeskPalette.ink).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("내 관찰 보고서").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
            .onAppear(perform: load)
    }
    private func v166CurrentRole(_ report: ScoutingReportSnapshot) -> String {
        "\(report.age)세 · " + (player.role == .batter
            ? "타자 / \(FieldPosition(rawValue: player.positionRaw)?.label ?? player.positionRaw)"
            : "투수 / \(player.throwingHandRaw == "left" ? "좌투" : "우투")")
    }
    private func v166CurrentAffiliation(_ report: ScoutingReportSnapshot) -> String {
        affiliation?.name ?? (report.age <= 18 ? player.displaySchoolName : SeasonSchedule.academicStatus(age: report.age))
    }
    private func v166CurrentSummary(_ report: ScoutingReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ManagementPortrait(appearance: affiliation?.appearance ?? player.appearance, role: player.role,
                                   number: player.jerseyNumber)
                    .frame(width: 36, height: 40).accessibilityHidden(true)
                Text("\(player.name)  #\(player.jerseyNumber)").font(.headline)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("scoutActualPlayer")
            }
            Text("기준일 \(ManagementDisplay.date(report.date.description))")
                .font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutCurrentDate")
            Text(v166CurrentRole(report)).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("scoutActualRole")
            Text(v166CurrentAffiliation(report)).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("scoutActualAffiliation")
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain).accessibilityIdentifier("scoutCurrentSummary")
    }
    private func v166CurrentOriginalDetails(_ report: ScoutingReportSnapshot) -> some View {
        ScoutDossier(title: "선수 관찰 파일", code: "PLAYER RECORD / READ ONLY", stamp: "현재 자료", isPreview: false) {
            Text("\(player.name)  #\(player.jerseyNumber)").font(.title3.bold())
                .accessibilityIdentifier("scoutDetailPlayer")
            Text(v166CurrentRole(report)).font(.subheadline).accessibilityIdentifier("scoutDetailRole")
            Text(v166CurrentAffiliation(report)).font(.subheadline).accessibilityIdentifier("scoutDetailAffiliation")
            if report.age > 18 {
                Text(SeasonSchedule.academicStatus(age: report.age)).font(.subheadline)
                Text("등록 학교 · " + player.displaySchoolName).font(.subheadline)
            }
            Text("기준일 \(ManagementDisplay.date(report.date.description))").font(.subheadline.bold())
                .foregroundStyle(ScoutDossierInk.muted)
            Text("현재 저장 자료 · 성장/날짜 변경 없는 조회").font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
        }
    }
    private func identity(_ report: ScoutingReportSnapshot) -> some View {
        ScoutDossier(title: "선수 관찰 파일", code: "PLAYER RECORD / READ ONLY", stamp: "현재 자료", isPreview: false) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .top, spacing: 18))) {
                ManagementPortrait(appearance: affiliation?.appearance ?? player.appearance, role: player.role,
                                   number: player.jerseyNumber).frame(width: 76, height: 84).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(player.name)  #\(player.jerseyNumber)").font(.title3.bold()).accessibilityIdentifier("scoutActualPlayer")
                    Text("\(report.age)세 · " + (player.role == .batter ? "타자 / \(FieldPosition(rawValue: player.positionRaw)?.label ?? player.positionRaw)" : "투수 / \(player.throwingHandRaw == "left" ? "좌투" : "우투")"))
                        .font(.subheadline).accessibilityIdentifier("scoutActualRole")
                    Text(affiliation?.name ?? (report.age <= 18 ? player.displaySchoolName : SeasonSchedule.academicStatus(age: report.age)))
                        .font(.subheadline).accessibilityIdentifier("scoutActualAffiliation")
                    if report.age > 18 {
                        Text(SeasonSchedule.academicStatus(age: report.age)).font(.subheadline)
                        Text("등록 학교 · " + player.displaySchoolName).font(.subheadline)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            Text("기준일 \(ManagementDisplay.date(report.date.description))").font(.subheadline.bold()).foregroundStyle(ScoutDossierInk.muted)
            Text("현재 저장 자료 · 성장/날짜 변경 없는 조회").font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
        }
    }
    private func currentAbilityBoard(_ report: ScoutingReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 24 : 16) {
            ScoutDeskHeading(title: "지금의 선수 기량", subtitle: "내 실제 능력 · 구단 합격선과 별개")
            ScoutAbilityFileChart(title: "현재 원본 기량", subtitle: "현재 자료 · " + ManagementDisplay.date(report.date.description),
                                  values: Array(report.abilities.originals.prefix(4)), identifier: "scoutCurrentVisual")
            if player.role == .pitcher {
                ScoutAbilityFileChart(title: "현재 구종 · 숙련", subtitle: "현재 선수에게 저장된 구종 자료",
                                      values: report.abilities.pitches, identifier: "scoutCurrentPitchVisual")
            }
            DisclosureGroup("현재 능력 전체 그래프") { HomeRadarChart(values: report.abilities.axes).padding(.top, 16) }
                .font(.subheadline).tint(GameTheme.gold)
            HomeDetailButton(title: "원본 능력치·구종 보기", expanded: $showOriginals, identifier: "scoutAbilityDetails")
            if showOriginals {
                ForEach(report.abilities.originals + report.abilities.pitches) { HomeGrowthRow(value: $0) }
                if !report.abilities.hasInitialValues {
                    Text("저장된 시작값이 없어 현재값만 표시합니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }
            }
        }.padding(16).background(ScoutDeskPalette.surface)
    }
    private func currentSampleBoard(_ report: ScoutingReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoutDeskHeading(title: "실전에서 남긴 기록", subtitle: "최근365일 · \(report.start) ~ \(report.date)")
            ScoutSeasonTiles(totals: report.totals, role: player.role)
            Text("진행 중 경기 \(report.pending)건은 완료 후 반영됩니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            if report.groups.isEmpty {
                ScoutNote(title: "평가 자료 대기", message: "완료한 개인 출전 표본이 없습니다.", messageIdentifier: "scoutSampleWaiting")
            }
            ForEach(Array(report.groups.enumerated()), id: \.element.id) { index, group in
                ScoutSampleCard(group: group, role: player.role, number: index + 1)
            }
            Text("환경별 표본을 따로 비교합니다. 서로 다른 경기 환경의 표본을 합쳐 심사하지 않습니다.")
                .font(.subheadline).foregroundStyle(GameTheme.gold)
        }
    }
}

private struct ScoutObservationFileCover: View {
    let value: ScoutingObservation
    let schoolID: String?
    let legacySchoolName: String?
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var gap: CGFloat { typeSize.isAccessibilitySize ? 24 : 16 }
    private var roleLabel: String {
        value.role == .batter ? FieldPosition(rawValue: value.position)?.label ?? value.position
            : value.hand == "left" ? "좌투" : "우투"
    }
    private var schoolName: String {
        if value.age <= 18 { return SchoolCatalog.displayName(id: schoolID, fallback: value.school) }
        return "등록 학교 · " + (value.school == legacySchoolName
            ? SchoolCatalog.displayName(id: schoolID, fallback: value.school) : value.school)
    }
    private var sample: String {
        value.role == .batter ? "\(value.totals.line.plateAppearances)타석" : "\(value.totals.innings)이닝"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                Text("FILE \(String(format: "%02d", value.period + 1))")
                    .font(.subheadline.monospaced().bold()).fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("관찰 확정").font(.caption.bold()).foregroundStyle(ScoutDossierInk.green)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(Rectangle().strokeBorder(ScoutDossierInk.green, lineWidth: 1))
            }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                ManagementPortrait(appearance: value.appearance, role: value.role, number: value.number)
                    .frame(width: typeSize.isAccessibilitySize ? 60 : 76, height: typeSize.isAccessibilitySize ? 64 : 84)
                    .padding(4).background(ScoutDossierInk.rule.opacity(0.35))
                    .overlay(Rectangle().strokeBorder(ScoutDossierInk.rule, lineWidth: 1)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 16 : 8) {
                    Text("\(value.name) #\(value.number)").font(ManagementPixelFont.readable(.sectionTitle))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(value.age)세 · \(value.role.label) · \(roleLabel)").font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(schoolName).font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("관찰일 \(ManagementDisplay.date(value.observedDate))").font(.subheadline.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(compact ? "scoutSavedCoverDate" : "scoutFrozenIdentityDate")
            Rectangle().fill(ScoutDossierInk.rule).frame(height: 1).accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 12) {
                metric("완료 경기", "\(value.totals.games)경기")
                metric("공식 표본", sample)
                metric("관심 구단", value.interests.map { "\($0.entries.count)곳" } ?? "미기록")
            }.accessibilityIdentifier(compact ? "scoutSavedCoverMetrics" : "scoutFrozenCoverMetrics")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ScoutDossierInk.ink).background(ScoutDossierInk.paper)
            .overlay(Rectangle().strokeBorder(ScoutDossierInk.rule, lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(compact ? "scoutSavedFileCover" : "scoutFrozenFileCover")
    }
    private func metric(_ title: String, _ number: String) -> some View {
        (typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))) {
            Text(title).font(.caption).foregroundStyle(ScoutDossierInk.muted)
            if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(number).font(.subheadline.monospaced().bold()).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

private struct ScoutAbilityFileChart: View {
    let title: String
    let subtitle: String
    let values: [HomeAbilityValue]
    let identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize
    private var gap: CGFloat { typeSize.isAccessibilitySize ? 24 : 16 }
    private let colors = [Color(hex: 0x2f7b65), Color(hex: 0xa16436), Color(hex: 0x2e7b94), Color(hex: 0x7e589e)]
    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 16 : 8) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if values.isEmpty {
                Text("저장된 자료 없음").font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
                    .accessibilityIdentifier(identifier + "Empty")
            } else {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                    chartRow(value, color: colors[index % colors.count])
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ScoutDossierInk.ink).background(ScoutDossierInk.paper)
            .overlay(Rectangle().strokeBorder(ScoutDossierInk.rule, lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
    private func chartRow(_ value: HomeAbilityValue, color: Color) -> some View {
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 16 : 8) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))) {
                Text(value.label).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(value.current.formatted(.number.precision(.fractionLength(1))))
                    .font(.headline.monospacedDigit()).fixedSize(horizontal: true, vertical: true)
            }
            ScoutSegmentMeter(value: value.current, maximum: 100, color: color).frame(height: 8)
        }.accessibilityElement(children: .combine).accessibilityIdentifier(identifier + "-" + value.id)
    }
}

private enum ScoutDeskPalette {
    static let ink = Color(hex: 0x102633)
    static let surface = Color(hex: 0x1a3c4c)
    static let inset = Color(hex: 0x0b202c)
}

private enum ScoutDeskFormat {
    static func number(_ value: Double?, places: Int = 1) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(places))) } ?? "대기"
    }
    static func signed(_ value: Double) -> String {
        (value > 0 ? "+" : "") + number(value)
    }
}

private struct ScoutDeskHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image("NavCareerV1").resizable().interpolation(.none).frame(width: 24, height: 24).accessibilityHidden(true)
                Text(title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            }
            Text(subtitle).font(.subheadline).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScoutPeriodRibbon: View {
    let value: ScoutingObservation
    let count: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            VStack(spacing: 4) {
                Text("FILE").font(.subheadline.monospaced().bold())
                Text(String(format: "%02d", value.period + 1)).font(.system(.largeTitle, design: .monospaced, weight: .black))
            }.foregroundStyle(GameTheme.navy).padding(14).background(GameTheme.gold, in: ManagementStepFrame())
            VStack(alignment: .leading, spacing: 10) {
                Text("\(value.period + 1)차 관찰 · \(ManagementDisplay.date(value.observedDate)) 확정").font(.headline).accessibilityIdentifier("scoutSavedPeriod")
                Text("다음 관찰 \(ManagementDisplay.date(value.nextDate))").font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutNextObservation")
                Text("보고서 \(count)건 · 확정 자료 보관").font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("scoutSavedCount")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(ScoutDeskPalette.inset)
    }
}

private struct ScoutStatusTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.subheadline.bold()).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(ScoutDeskPalette.inset)
            .overlay(Rectangle().strokeBorder(color.opacity(0.8), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ScoutClubSeasonContext {
    struct Season {
        let league: AnnualLeague
        let label: String
        let winnerIDs: Set<String>
    }

    var current: Season?
    var previous: Season?

    @MainActor static func load(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext) -> Self {
        let id = player.id
        guard let today = try? GameDate(player.gameDate), let origin = try? GameDate(calendar.originDate),
              let records = try? context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id })) else {
            return Self()
        }
        func season(_ year: Int) -> Season? {
            guard year >= origin.year, let plan = try? calendar.competition(for: player, year: year),
                  let level = plan.membership?.level,
                  let league = try? AnnualLeagueStore.snapshot(player: player, state: calendar, year: year, records: records) else { return nil }
            let label: String
            switch level {
            case "domestic-development": label = "국내 육성"
            case "domestic-first-team": label = "국내 1군"
            case "mlb-development": label = "MLB 육성"
            case "npb-first-team": label = "NPB"
            case "mlb-first-team": label = "MLB"
            default: return nil
            }
            var winners: Set<String> = []
            if league.isComplete, let automatic = try? AutomaticLeagueStore.records(playerID: id, year: year, in: context) {
                let savedIDs = Set(records.filter(\.completed).map(\.fixtureID)).union(automatic.map(\.fixtureID))
                if league.fixtures.allSatisfy({ savedIDs.contains($0.id) }) {
                    winners = Set(league.displayStandings.filter { $0.rank == 1 }.map(\.id))
                }
            }
            return Season(league: league, label: label, winnerIDs: winners)
        }
        return Self(current: season(today.year), previous: season(today.year - 1))
    }
}

private struct ScoutClubSeasonNote: View {
    let teamIDs: Set<String>
    let seasons: ScoutClubSeasonContext

    var body: some View {
        if let current = seasons.current,
           let row = current.league.displayStandings.first(where: { teamIDs.contains($0.id) }), row.games > 0 {
            let rank = row.rank.map { "\($0)위 · " } ?? ""
            Text("\(current.league.year)년 \(current.label) · \(rank)\(row.wins)승 \(row.losses)패 \(row.draws)무")
                .font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
        }
        ForEach([seasons.current, seasons.previous].compactMap { $0 }.filter { !$0.winnerIDs.isDisjoint(with: teamIDs) },
                id: \.league.year) { season in
            HStack(spacing: 7) {
                LeagueTrophyPixel().frame(width: 18, height: 20).accessibilityHidden(true)
                Text("\(season.league.year)년 \(season.label) 정규 시즌 \(season.winnerIDs.count > 1 ? "공동 우승" : "우승")")
                    .font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ScoutDossierInk.green)
            .accessibilityIdentifier("scoutClubChampion-\(season.league.year)")
        }
    }
}

private struct ScoutClubDossierCard<Content: View>: View {
    let name: String
    let role: String
    let status: String
    let statusIdentifier: String
    let forecast: SigningBonusForecast?
    let quoteIdentifier: String
    let teamIDs: Set<String>
    let seasons: ScoutClubSeasonContext
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ClubBadge(name: name, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).managementFont(.sectionTitle).bold()
                    Text(role).managementFont(.label).foregroundStyle(ScoutDossierInk.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(status).font(.headline).foregroundStyle(ScoutDossierInk.green)
                .accessibilityIdentifier(statusIdentifier)
            ScoutClubSeasonNote(teamIDs: teamIDs, seasons: seasons)
            ScoutSigningBonusQuote(forecast: forecast, identifier: quoteIdentifier)
            content
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ScoutDossierInk.ink)
        .background(ScoutDossierInk.paper, in: ManagementStepFrame())
        .overlay { ManagementStepFrame().strokeBorder(ScoutDossierInk.rule, lineWidth: 2) }
    }
}

private struct ScoutRoleEvidence: View {
    let mine: Double?
    let criterion: Double?
    let correction: Double
    let fit: Double?
    let need: String
    let caution: String?
    let identifier: String?

    private var difference: Double? {
        guard let mine, let criterion else { return nil }
        return mine - criterion
    }

    private var strength: String {
        if let difference, difference >= 0 { return "내 역할 기량이 구단 기준에 도달했습니다." }
        if correction > 0 { return "같은 환경의 성적에서 \(ScoutDeskFormat.signed(correction))점 보정을 받았습니다." }
        return need
    }

    private var concern: String {
        if let difference, difference < 0 {
            return "구단의 역할 기준까지 \(ScoutDeskFormat.number(-difference))점이 필요합니다."
        }
        return caution ?? "기량 확인 후 구단별 등록·계약 조건을 심사합니다."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("내 기량 \(ScoutDeskFormat.number(mine)) / 구단 기준 \(ScoutDeskFormat.number(criterion))")
                .managementFont(.label).monospacedDigit().accessibilityIdentifier(identifier ?? "")
            Text("관찰 적합도 F · " + (fit.map(ScoutDeskFormat.signed) ?? "평가 대기"))
                .managementFont(.label).bold().monospacedDigit()
            assessment("강점", strength)
            assessment("주의점", concern)
        }
    }

    private func assessment(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.bold()).foregroundStyle(ScoutDossierInk.green)
            Text(text).managementFont(.helper)
        }
    }
}

private struct ScoutInterestCard: View {
    let entry: ScoutingClubInterest
    let presentation: ScoutingClubPresentation?
    let forecast: SigningBonusForecast?
    let seasons: ScoutClubSeasonContext
    @State private var expanded = false

    var body: some View {
        ScoutClubDossierCard(name: entry.name, role: entry.roleLabel, status: entry.level.label,
            statusIdentifier: "scoutInterest-" + entry.id, forecast: forecast, quoteIdentifier: "scoutInterestQuote-" + entry.id,
            teamIDs: ["dev-" + entry.id, "pro-" + entry.id], seasons: seasons) {
            if let presentation {
                let club = presentation.club
                ScoutRoleEvidence(mine: club.h, criterion: club.c, correction: club.p, fit: club.f,
                    need: presentation.recruitmentContext, caution: presentation.recordedImprovementConditions.first,
                    identifier: "scoutInterestBasis-" + entry.id)
            } else if let first = entry.reasons.first {
                Text(first).managementFont(.helper)
            }
            HomeDetailButton(title: "보완할 조건과 평가 근거", expanded: $expanded,
                             identifier: "scoutInterestEvidence-" + entry.id, onPaper: true)
            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    if let presentation {
                        Text(presentation.recruitmentContext).managementFont(.label).bold()
                        Text(presentation.competitionContext).managementFont(.helper)
                        if !presentation.improvementConditions.isEmpty {
                            Text("추가 조건 · 관찰일 기준").managementFont(.label).bold()
                            ForEach(presentation.improvementConditions, id: \.self) { Text($0).managementFont(.helper) }
                        }
                    }
                    ForEach(entry.reasons, id: \.self) { Text($0).managementFont(.helper) }
                    if let presentation, !presentation.generalReviewConditions.isEmpty {
                        Text("공통 계약 심사").managementFont(.label).bold()
                        ForEach(presentation.generalReviewConditions, id: \.self) { Text($0).managementFont(.helper) }
                    }
                }
            }
        }
    }
}

struct OverseasScoutInterestCard: View {
    let row: OverseasClubEvaluation
    let report: OverseasScoutingReport
    var seasons = ScoutClubSeasonContext()
    @State private var expanded = false

    private var teamIDs: Set<String> {
        guard let club = ClubIdentity.resolve(name: row.name) else { return [] }
        switch row.route {
        case .mlbDevelopment: return ["us-dev-\(club.index)"]
        case .npbFirstTeam: return ["jp-pro-\(club.index)"]
        case .mlbFirstTeam: return ["us-pro-\(club.index)"]
        }
    }

    var body: some View {
        let forecast = report.signingBonusForecast(clubID: row.id, roleID: row.roleID)
        ScoutClubDossierCard(name: row.name, role: row.route.label + " · " + DomesticContractOffer.roleName(row.roleID),
            status: row.interest?.label ?? "관찰 대기", statusIdentifier: "overseasClubInterest",
            forecast: forecast, quoteIdentifier: "overseasInterestQuote-" + row.id, teamIDs: teamIDs, seasons: seasons) {
            ScoutRoleEvidence(mine: row.h, criterion: row.criterion, correction: row.p, fit: row.f,
                              need: row.demand.label, caution: row.blockers.first, identifier: "overseasClubBasis-" + row.id)
            HomeDetailButton(title: "보완할 조건과 평가 근거", expanded: $expanded,
                             identifier: "overseasClubEvidence-" + row.id, onPaper: true)
            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    Text("모집 · \(row.demand.label) \(row.seats)자리").managementFont(.label).bold()
                    Text("경쟁자 기량 \(ScoutDeskFormat.number(row.competitor)) · 성적 보정 \(ScoutDeskFormat.signed(row.p))")
                        .managementFont(.helper)
                    if !row.blockers.isEmpty {
                        Text("추가 조건 · 관찰일 기준").managementFont(.label).bold()
                        ForEach(row.blockers, id: \.self) { Text($0).managementFont(.helper) }
                    }
                    Text("공통 계약 심사 · 등록, 기간, 모집 자리와 예산을 확인합니다.").managementFont(.helper)
                }
            }
        }
    }
}

private struct ScoutSegmentMeter: View {
    let value: Double?
    let maximum: Double
    let color: Color
    private var ratio: Double? { value.flatMap { $0.isFinite && maximum > 0 ? min(1, max(0, $0 / maximum)) : nil } }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<10) { segment in
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(GameTheme.boardLine.opacity(0.25))
                        if let ratio {
                            Rectangle().fill(color).frame(width: geometry.size.width * min(1, max(0, ratio * 10 - Double(segment))))
                        }
                    }
                }
            }
        }.frame(height: 12).accessibilityHidden(true)
    }
}

private struct ScoutValueTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            Text(value).font(.title3.monospaced().bold()).foregroundStyle(GameTheme.gold)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(ScoutDeskPalette.inset)
            .accessibilityElement(children: .combine)
    }
}

private struct ScoutSeasonTiles: View {
    let totals: PersonalSeasonTotals
    let role: PlayerRole
    @Environment(\.dynamicTypeSize) private var typeSize
    private var values: [(String, String)] {
        role == .batter ? [("출전", "\(totals.games)경기"), ("타율", totals.average), ("홈런", "\(totals.line.homeRuns)개"), ("타점", "\(totals.line.rbi)점")]
            : [("등판", "\(totals.games)경기"), ("이닝", totals.innings), ("탈삼진", "\(totals.line.pitchingStrikeouts)개"), ("WHIP", totals.whip)]
    }
    private var detail: [(String, Int)] {
        let line = totals.line
        return role == .batter ? [("타석", line.plateAppearances), ("타수", line.atBats), ("안타", line.hits), ("볼넷", line.walks), ("삼진", line.strikeouts)]
            : [("투구 수", line.pitches), ("피안타", line.hitsAllowed), ("볼넷", line.pitchingWalks), ("실점", line.runsAllowed)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(values.indices, id: \.self) { index in ScoutValueTile(title: values[index].0, value: values[index].1) }
            }
            DisclosureGroup("세부 경기 기록") {
                VStack(spacing: 12) {
                    ForEach(detail.indices, id: \.self) { index in
                        HStack {
                            Text(detail[index].0).font(.subheadline)
                            Spacer(minLength: 8)
                            Text(String(detail[index].1)).font(.headline.monospacedDigit()).foregroundStyle(GameTheme.gold)
                        }
                    }
                }.padding(.top, 12).accessibilityElement(children: .combine).accessibilityIdentifier("seasonRecordDetails")
            }.font(.subheadline).tint(GameTheme.gold)
        }
    }
}

private struct ScoutSampleCard: View {
    let group: ScoutingSampleGroup
    let role: PlayerRole
    let number: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    private var enough: Bool { role == .batter ? group.hasBatterMinimum : group.hasPitcherMinimum }
    private var amount: Double { Double(role == .batter ? group.totals.line.plateAppearances : group.totals.line.pitchingOuts) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top))) {
                Text("경기 환경 \(number)").font(.headline)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                ScoutStatusTag(text: enough ? "표본 도달" : "표본 수집 중", color: enough ? GameTheme.growth : GameTheme.gold)
            }
            Text(role == .batter ? "\(group.totals.games)경기 · \(group.totals.line.plateAppearances) / 40타석" : "\(group.totals.games)등판 · \(group.totals.innings) / 15.0이닝")
                .font(.body.monospacedDigit()).accessibilityIdentifier("scoutSample-\(number)")
            ScoutSegmentMeter(value: amount, maximum: role == .batter ? 40 : 45, color: enough ? GameTheme.growth : GameTheme.gold)
            Text(enough ? "같은 환경의 최소 표본 참고 기준 도달 · 합격 확정 아님" : "같은 환경의 실제 출전 기록이 더 필요합니다.")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.padding(14).background(ScoutDeskPalette.surface)
    }
}

private struct ScoutClubComparisonCard: View {
    let club: ScoutingClubFit
    let roleName: String
    private var presentation: ScoutingClubPresentation { ScoutingClubPresentation(club: club) }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScoutDossier(title: "모집 선수 · " + roleName, code: "CLUB SCOUTING FILE", stamp: club.recruitment.demand.label, isPreview: false) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                ClubBadge(name: club.recruitment.name, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(club.recruitment.name).font(.title3.bold())
                    Text(club.stage).font(.subheadline.bold()).foregroundStyle(ScoutDossierInk.green)
                }
            }
            comparisonRow("관찰일 내 역할 기량", value: club.h, color: ScoutDossierInk.green)
            comparisonRow("구단 관찰 기준", value: club.c, color: ScoutDossierInk.ink)
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top))) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("성적 보정 P").font(.caption)
                    Text(ScoutDeskFormat.signed(club.p)).font(.headline.monospacedDigit())
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("기량 차 F").font(.caption)
                    Text(club.f.map(ScoutDeskFormat.signed) ?? "평가 대기").font(.headline.monospacedDigit())
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).background(ScoutDossierInk.rule.opacity(0.15))
            if let first = presentation.improvementConditions.first {
                Text("먼저 보완할 조건").font(.subheadline.bold())
                Text(first).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("기록된 기량·자료 보완 조건 없음 · 계약 심사는 별도입니다.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Text("H \(ScoutDeskFormat.number(club.h)) / C \(ScoutDeskFormat.number(club.c)) / P \(ScoutDeskFormat.number(club.p)) / F \(ScoutDeskFormat.number(club.f))")
                .font(.caption.monospacedDigit()).accessibilityIdentifier("scoutClub-\(club.id)")
            DisclosureGroup("추가 조건") {
                ForEach(Array(presentation.improvementConditions.dropFirst()), id: \.self) { Text($0).font(.subheadline) }
                if !presentation.generalReviewConditions.isEmpty {
                    Text("별도 계약·진로 확인").font(.subheadline.bold()).padding(.top, 8)
                    ForEach(presentation.generalReviewConditions, id: \.self) { Text($0).font(.subheadline) }
                }
            }.tint(ScoutDossierInk.ink)
            Text(presentation.competitionContext).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("관찰 당시 고정 자료 · 계약 제의 아님").font(.caption.bold()).foregroundStyle(ScoutDossierInk.muted)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("scoutClubFile-" + club.id)
    }
    private func comparisonRow(_ label: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())) {
                Text(label).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Text(ScoutDeskFormat.number(value)).font(.headline.monospacedDigit()).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(ScoutDossierInk.rule.opacity(0.3))
                    if let value, value.isFinite {
                        Rectangle().fill(color).frame(width: g.size.width * min(1, max(0, value / 100)))
                    }
                }
            }.frame(height: 8).accessibilityHidden(true)
        }
    }
}

private struct ScoutNote: View {
    let title: String
    let message: String
    var messageIdentifier: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(GameTheme.gold)
            if let messageIdentifier { Text(message).font(.body).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier(messageIdentifier) }
            else { Text(message).font(.body).foregroundStyle(GameTheme.boardMuted) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(ScoutDeskPalette.surface)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine.opacity(0.7), lineWidth: 1))
    }
}

private struct ScoutObservationDates: View {
    let value: ScoutingObservation
    let today: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("관찰과 현재 · 서로 다른 시점").font(ManagementPixelFont.readable(.label)).foregroundStyle(GameTheme.gold)
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))) {
                date("확정 관찰", date: value.observedDate, icon: "NavCareerV1")
                date("지금 내 선수", date: today, icon: "NavPlayerV1")
            }
            HStack(alignment: .top, spacing: 10) {
                Text("집계").font(.caption.bold()).padding(6).background(GameTheme.boardPanel)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ManagementDisplay.date(value.sampleStart) + " ~ " + ManagementDisplay.date(value.observedDate)).font(.subheadline.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                    Text("최근365일 범위의 완료 개인 경기 · 새28일 합계와 구분").font(.caption).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(14).background(ScoutDeskPalette.ink).overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            .accessibilityElement(children: .combine).accessibilityIdentifier("scoutObservationClock")
    }
    private func date(_ title: String, date: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(icon).resizable().interpolation(.none).frame(width: 28, height: 28).accessibilityHidden(true)
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.boardMuted)
            Text(ManagementDisplay.date(date)).font(.subheadline.monospacedDigit().bold()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 84).padding(10).background(ScoutDeskPalette.surface)
            .accessibilityElement(children: .combine)
    }
}
