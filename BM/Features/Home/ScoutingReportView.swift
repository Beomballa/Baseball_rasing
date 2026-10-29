import SwiftUI
import SwiftData

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
    @Query(sort: \CareerScoutingReport.period, order: .reverse) private var saved: [CareerScoutingReport]
    @State private var error: String?
    @State private var showHistory = false
    private var own: [CareerScoutingReport] { saved.filter { $0.playerID == player.id } }
    private func refresh() {
        do {
            try ScoutingObservationStore.ensureCurrent(player: player, calendar: calendar, in: context)
            _ = try ScoutingObservationStore.reports(player: player, calendar: calendar, in: context)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScoutDeskHeading(title: archive ? "관찰 파일 · 지난 이력" : "스카우트 데스크", subtitle: "28일마다 남기는 선수의 발자취")
            if let error {
                Text(error).font(.body).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutArchiveError")
                Button("보고서 저장 다시 확인", action: refresh).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutArchiveRetry")
            } else if let row = own.first, let value = try? row.snapshot() {
                ScoutPeriodRibbon(value: value, count: own.count)
                CareerManagementNote(title:"관찰과 현재 · 서로 다른 시점",
                    detail:"관찰 "+ManagementDisplay.date(value.observedDate)+" · 성적 집계 "+ManagementDisplay.date(value.sampleStart)+"~"+ManagementDisplay.date(value.observedDate)+" · 오늘 "+ManagementDisplay.date(player.gameDate)+". 최근365일 범위의 완료 개인 경기이며 새28일 경기만의 합계가 아닙니다.",identifier:"scoutObservationClock")
                ScoutingInterestList(value: value, compact: true)
                NavigationLink { SavedScoutingObservationView(value: value, schoolID: player.schoolID, legacySchoolName: player.schoolName) } label: {
                    HStack { Text("확정 보고서 펼치기"); Spacer(); Text("›") }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("openSavedScoutingReport")
                if archive && own.count > 1 {
                    HomeDetailButton(title: "지난 보고서 \(own.count - 1)건", expanded: $showHistory, identifier: "scoutHistoryDetails")
                    if showHistory {
                        ForEach(own.dropFirst()) { old in
                            if let snapshot = try? old.snapshot() {
                                NavigationLink { SavedScoutingObservationView(value: snapshot, schoolID: player.schoolID, legacySchoolName: player.schoolName) } label: {
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
            Text("주기 보고서가 없으면 최초 자료 저장을 확인합니다. 같은 주기는 보존하며 실패 시 위 버튼으로 재시도합니다. 재열기 자체가 매번 저장하는 것은 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("scoutRefreshPolicy")
            Text("관심 구단과 실제 제의는 별개입니다. 자격·심사·제의는 계약 메뉴에서 확인하세요.")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.padding(16).background(ScoutDeskPalette.surface)
            .overlay(ManagementStepFrame().stroke(GameTheme.boardLine, lineWidth: 2))
            .task(id: "\(player.id)-\(player.gameDate)") { refresh() }
    }
}

struct ScoutingInterestList: View {
    let value: ScoutingObservation
    var compact = false
    @State private var showAll = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let interests = value.interests {
                HStack(alignment: .firstTextBaseline) {
                    Text("관심 구단").font(.headline)
                    Spacer()
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
                        ScoutInterestCard(entry: entry)
                    }
                    if compact && interests.entries.count > 2 {
                        HomeDetailButton(title: "관심 구단 전체 \(interests.entries.count)곳", expanded: $showAll, identifier: "scoutInterestDetails")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showOriginals = false
    @State private var showClubs = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                ScoutingInterestList(value: value)
                roleBoard
                frozenSample
                if let opportunities = value.opportunities, !opportunities.keys.isEmpty {
                    GamePanel(title:"기용과 실제 출전 · 관찰 당시 고정",onBoard:true) {
                        Text("주전 \(opportunities.starts) · 벤치 \(opportunities.bench) · 순번 휴식 \(opportunities.rotationRest)").font(.headline.monospacedDigit()).accessibilityIdentifier("scoutOpportunities")
                        Text("새 기용 규칙으로 완료한 최근365일 경기만 표시합니다. 비출전은 개인 표본·실패 성과로 만들지 않습니다.").font(.subheadline)
                    }
                }
                if let fit = value.contractFit {
                    comparisonBoard(fit)
                    clubBoard(fit)
                } else {
                    ScoutNote(title: "이전 버전 파일", message: "이 보고서는 확정 당시 구단/비교 성적을 기록하지 않았습니다. 원문을 유지하며 다음 관찰부터 새 자료를 확인합니다.", messageIdentifier: "scoutLegacyFit")
                }
                DisclosureGroup("다음 검토 조건 · 계산/계약 절차") {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("다음 검토를 위한 조건").font(.title3.bold())
                    ForEach(value.evaluationPending, id: \.self) { Text($0).font(.subheadline) }
                    Text(value.contractFit == nil ? "당시 평가 대기 상태를 보존한 파일입니다." : "역할 기량·성적 적합도는 참고값입니다. 실제 자격·선발 결과·제의는 계약 메뉴에서 확인하세요.")
                        .font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutFrozenPending")
                    DisclosureGroup("평가 자료와 계약 절차의 차이") {
                        Text("28일 관찰과 계약 평가 창은 별개입니다. 재조회·시즌 결산으로 제의를 재추첨하지 않습니다.")
                            .font(.subheadline).padding(.top, 8)
                    }.font(.subheadline).tint(GameTheme.gold)
                }
                }.tint(GameTheme.gold).accessibilityIdentifier("scoutReviewConditions")
                DisclosureGroup("선수 프로젝트 · 관찰 근거") {
                    CareerProjectReportEvidence(playerID: value.playerID, period: value.period).padding(.top, 12)
                }.font(.headline).tint(GameTheme.gold)
            }.padding(16)
        }.lineSpacing(4).background(ScoutDeskPalette.ink).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("확정 관찰 보고서").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
    }
    private var frozenIdentity: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image("NavCareerV1").resizable().interpolation(.none).frame(width: 28, height: 28).accessibilityHidden(true)
                Text("SCOUT ARCHIVE").font(.subheadline.monospaced().bold())
                Spacer(minLength: 0)
                Text("FILE \(value.period + 1)").font(.subheadline.monospaced().bold()).foregroundStyle(GameTheme.gold)
            }.padding(14).background(ScoutDeskPalette.surface)
            ScoutDossier(title: "\(value.period + 1)차 관찰 보고서", code: "OBSERVATION / FIXED RECORD", stamp: "관찰 확정", isPreview: false) {
                HStack(alignment: .top, spacing: 18) {
                    DetailGamePortrait(role: value.role, appearance: value.appearance, number: value.number, hand: value.hand).frame(width: 76, height: 100).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(value.name) #\(value.number)").font(.title3.bold())
                        Text("\(value.age)세 · \(value.role.label) · " + (value.role == .batter ? FieldPosition(rawValue: value.position)?.label ?? value.position : value.hand == "left" ? "좌투" : "우투")).font(.subheadline)
                        Text(value.age <= 18 ? SchoolCatalog.displayName(id: schoolID, fallback: value.school) : "등록 학교 · \(value.school == legacySchoolName ? SchoolCatalog.displayName(id: schoolID, fallback: value.school) : value.school)").font(.subheadline)
                    }
                }
                Text("관찰일 \(ManagementDisplay.date(value.observedDate))").font(.subheadline.bold()).accessibilityIdentifier("scoutFrozenDate")
                Text("주기 \(ManagementDisplay.date(value.periodStart)) ~ \((try? GameDate(value.nextDate).adding(days: -1).description).map(ManagementDisplay.date) ?? "—")").font(.subheadline.monospaced())
                Text("성적 집계 "+ManagementDisplay.date(value.sampleStart)+" ~ "+ManagementDisplay.date(value.observedDate)+" · 완료 개인 경기").font(.subheadline).foregroundStyle(ScoutDossierInk.muted).accessibilityIdentifier("scoutFrozenSampleCutoff")
                Text("위 주기 종료일은 관찰 주기의 경계이며 성적 집계 마감일과 다릅니다. 현재 값과 구분해 보관한 당시 자료입니다.").font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
            }
        }
    }
    private var roleBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    HStack(alignment: .top) {
                        Text("환경 \(index + 1) · 성적 보정 P \(ScoutDeskFormat.signed(row.correction))")
                            .font(.headline).accessibilityIdentifier("scoutComparison-\(index)")
                        Spacer(minLength: 4)
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
    private func clubBoard(_ fit: ScoutingContractFit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoutDeskHeading(title: "구단의 기준과 나의 기량", subtitle: "기량 차이와 부족 조건 · 정식 제의는 계약 메뉴")
            HomeDetailButton(title: "모집 역할·기준·적합도 \(fit.clubs.count)건", expanded: $showClubs, identifier: "scoutClubDetails")
            if showClubs {
                ForEach(fit.clubs) { club in
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
    @State private var error: String?
    @State private var showOriginals = false
    @ScaledMetric(relativeTo: .body) private var scaledGap: CGFloat = 16
    private var gap: CGFloat { min(scaledGap, 24) }

    private func load() {
        do { report = try ScoutingReportSnapshot.load(player: player, calendar: calendar, in: context); error = nil }
        catch { report = nil; self.error = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error {
                    ScoutNote(title: "관찰 자료를 불러오지 못했습니다", message: error, messageIdentifier: "scoutReportError")
                    Button("다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutReportRetry")
                } else if let report {
                    identity(report)
                    currentAbilityBoard(report)
                    currentSampleBoard(report)
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
                    Button("현재 자료 다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutReportRefresh")
                }
            }.padding(16)
        }.lineSpacing(typeSize.isAccessibilitySize ? 5 : 4)
            .background(ScoutDeskPalette.ink).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("내 관찰 보고서").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
            .onAppear(perform: load)
    }
    private func identity(_ report: ScoutingReportSnapshot) -> some View {
        ScoutDossier(title: "선수 관찰 파일", code: "PLAYER RECORD / READ ONLY", stamp: "현재 자료", isPreview: false) {
            HStack(alignment: .top, spacing: 18) {
                DetailGamePortrait(role: player.role, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw).frame(width: 76, height: 100).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(player.name)  #\(player.jerseyNumber)").font(.title3.bold()).accessibilityIdentifier("scoutActualPlayer")
                    Text("\(report.age)세 · " + (player.role == .batter ? "타자 / \(FieldPosition(rawValue: player.positionRaw)?.label ?? player.positionRaw)" : "투수 / \(player.throwingHandRaw == "left" ? "좌투" : "우투")"))
                        .font(.subheadline).accessibilityIdentifier("scoutActualRole")
                    Text(report.age <= 18 ? player.displaySchoolName : SeasonSchedule.academicStatus(age: report.age)).font(.subheadline).accessibilityIdentifier("scoutActualAffiliation")
                    if report.age > 18 { Text("등록 학교 · " + player.displaySchoolName).font(.subheadline) }
                }
            }
            Text("기준일 \(ManagementDisplay.date(report.date.description))").font(.subheadline.bold()).foregroundStyle(ScoutDossierInk.muted)
            Text("현재 저장 자료 · 성장/날짜 변경 없는 조회").font(.subheadline).foregroundStyle(ScoutDossierInk.muted)
        }
    }
    private func currentAbilityBoard(_ report: ScoutingReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoutDeskHeading(title: "지금의 선수 기량", subtitle: "내 실제 능력 · 구단 합격선과 별개")
            HomeRadarChart(values: report.abilities.axes)
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
                Text(title).font(.title3.bold())
            }
            Text(subtitle).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
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

private struct ScoutInterestCard: View {
    let entry: ScoutingClubInterest
    @Environment(\.dynamicTypeSize) private var typeSize
    private var level: Int { switch entry.level { case .observing: 0; case .focused: 1; case .priority: 2 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.name + " · " + entry.level.label).font(.headline).accessibilityIdentifier("scoutInterest-\(entry.id)")
                    Text(entry.roleLabel).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ScoutStatusTag(text: "F " + ScoutDeskFormat.signed(entry.fit), color: entry.fit >= 0 ? GameTheme.growth : GameTheme.gold)
            }
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Rectangle().fill(index <= level ? GameTheme.gold : GameTheme.boardLine.opacity(0.35)).frame(height: 6)
                }
            }.accessibilityHidden(true)
            Text("관찰 관심 → 집중 관찰 → 우선 관찰").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            DisclosureGroup("관심 이유 · \(entry.reasons.count)개") {
                ForEach(entry.reasons, id: \.self) { Text($0).font(.subheadline).padding(.top, 8) }
            }.font(.subheadline).tint(GameTheme.gold)
        }.padding(14).background(ScoutDeskPalette.surface)
            .overlay(alignment: .leading) { Rectangle().fill(GameTheme.gold).frame(width: 3).accessibilityHidden(true) }
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
    private var enough: Bool { role == .batter ? group.hasBatterMinimum : group.hasPitcherMinimum }
    private var amount: Double { Double(role == .batter ? group.totals.line.plateAppearances : group.totals.line.pitchingOuts) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("경기 환경 \(number)").font(.headline)
                Spacer(minLength: 4)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(club.recruitment.name).font(.title3.bold())
            Text(roleName + " · " + club.recruitment.demand.label).font(.subheadline).foregroundStyle(GameTheme.gold)
            Text(club.stage).font(.headline).foregroundStyle(GameTheme.boardInk)
            VStack(alignment: .leading, spacing: 12) {
                comparisonRow("내 역할 기량 H", value: club.h, color: GameTheme.growth)
                comparisonRow("구단 기준 C", value: club.c, color: GameTheme.gold)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ScoutValueTile(title: "성적 보정 P", value: ScoutDeskFormat.signed(club.p))
                ScoutValueTile(title: "기량 차 F", value: club.f.map(ScoutDeskFormat.signed) ?? "평가 대기")
            }
            Text("H \(ScoutDeskFormat.number(club.h)) / C \(ScoutDeskFormat.number(club.c)) / P \(ScoutDeskFormat.number(club.p)) / F \(ScoutDeskFormat.number(club.f))")
                .font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("scoutClub-\(club.id)")
            if !club.blockers.isEmpty {
                DisclosureGroup("보완할 조건 \(club.blockers.count)개") {
                    ForEach(club.blockers, id: \.self) { Text($0).font(.subheadline).padding(.top, 8) }
                }.font(.subheadline).tint(GameTheme.gold)
            }
            if club.c == nil { Text("경쟁자 자료 대기 · 공석으로 가정하지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.gold) }
        }.padding(16).background(ScoutDeskPalette.surface)
            .overlay(ManagementStepFrame().stroke(GameTheme.boardLine, lineWidth: 1))
    }
    private func comparisonRow(_ label: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.subheadline)
                Spacer(minLength: 4)
                Text(ScoutDeskFormat.number(value)).font(.headline.monospacedDigit()).foregroundStyle(color)
            }
            ScoutSegmentMeter(value: value, maximum: 100, color: color)
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
