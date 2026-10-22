import SwiftUI
import SwiftData

struct ScoutingSampleGroup: Identifiable, Codable {
    let id: String
    var totals = PersonalSeasonTotals()
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
        GamePanel(title: archive ? "28일 관찰 · 저장한 보고서" : "스카우트 관찰 · 내 기록", onBoard: true, contentSpacing: 16) {
            if let error {
                Text(error).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutArchiveError")
                Button("보고서 저장 다시 확인", action: refresh).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutArchiveRetry")
            } else if let row = own.first, let value = try? row.snapshot() {
                Text("\(value.period + 1)차 관찰 · \(value.observedDate) 확정").font(.subheadline.bold()).accessibilityIdentifier("scoutSavedPeriod")
                Text("다음 관찰 \(value.nextDate) · 게임 날짜 기준").font(.caption.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutNextObservation")
                Text("보고서 \(own.count)건 · 같은 주기의 자료는 다시 뽑지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("scoutSavedCount")
                NavigationLink { SavedScoutingObservationView(value: value) } label: { Text("확정 보고서 보기") }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openSavedScoutingReport")
                if archive && own.count > 1 {
                    HomeDetailButton(title: "지난 보고서 \(own.count - 1)건", expanded: $showHistory, identifier: "scoutHistoryDetails")
                    if showHistory {
                        ForEach(own.dropFirst()) { old in
                            if let snapshot = try? old.snapshot() {
                                NavigationLink { SavedScoutingObservationView(value: snapshot) } label: {
                                    Text("\(snapshot.period + 1)차 · \(snapshot.observedDate)")
                                }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutHistory-\(snapshot.period)")
                            }
                        }
                    }
                }
            } else {
                Text("현재 주기 보고서 확인 중").font(.subheadline)
            }
            if !archive {
                NavigationLink { ScoutingReportView(player: player, calendar: calendar) } label: { Text("내 관찰 보고서 · 현재 자료/이력") }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("openScoutingReport")
            }
            Text("구단 관심·제의 생성은 아직 연결 전입니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }.task(id: "\(player.id)-\(player.gameDate)") { refresh() }
    }
}

struct SavedScoutingObservationView: View {
    let value: ScoutingObservation
    @State private var showOriginals = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScoutDossier(title: "\(value.period + 1)차 관찰 보고서", code: "OBSERVATION / FIXED RECORD", stamp: "관찰 확정", isPreview: false) {
                    HStack(alignment: .top, spacing: 16) {
                        PixelPlayer(appearance: value.appearance).frame(width: 38, height: 54).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(value.name) #\(value.number)").font(.headline)
                            Text("\(value.age)세 · \(value.role.label) · " + (value.role == .batter ? FieldPosition(rawValue: value.position)?.label ?? value.position : value.hand == "left" ? "좌투" : "우투")).font(.subheadline)
                            Text(value.age <= 18 ? value.school : "등록 학교 · \(value.school)").font(.subheadline)
                        }
                    }
                    Text("관찰일 \(value.observedDate)").font(.subheadline.bold()).accessibilityIdentifier("scoutFrozenDate")
                    Text("주기 \(value.periodStart) ~ \((try? GameDate(value.nextDate).adding(days: -1).description) ?? "—")").font(.caption.monospaced())
                    Text("당시 자료를 보존한 보고서입니다. 현재 능력·출전 기록과 다를 수 있습니다.").font(.caption).foregroundStyle(ScoutDossierInk.muted)
                }
                GamePanel(title: "역할별 기량 H · 당시 영구 능력", onBoard: true, contentSpacing: 16) {
                    ForEach(value.grades) { grade in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(grade.label + "  " + (grade.score.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "평가 대기"))
                                .font(.headline.monospaced()).accessibilityIdentifier("scoutGrade-\(grade.id)")
                            Text(grade.detail).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    Text("H = 역할 기초점수95% + 멘탈5% · 게임 내 기량 참고값이며 계약 합격을 뜻하지 않습니다.").font(.caption).foregroundStyle(GameTheme.gold)
                    HomeRadarChart(values: value.abilities.axes)
                    HomeDetailButton(title: "관찰 당시 원본 능력·구종", expanded: $showOriginals, identifier: "scoutFrozenAbilities")
                    if showOriginals { ForEach(value.abilities.originals + value.abilities.pitches) { HomeGrowthRow(value: $0) } }
                }
                GamePanel(title: "관찰 당시 출전 표본", onBoard: true, contentSpacing: 16) {
                    Text("\(value.sampleStart) ~ \(value.observedDate)").font(.caption.monospaced())
                    SeasonPersonalRecord(totals: value.totals, role: value.role)
                    Text("완료 개인 경기 \(value.totals.games)건 · 미완료 \(value.pending)건 제외").font(.subheadline).accessibilityIdentifier("scoutFrozenSample")
                    ForEach(Array(value.groups.enumerated()), id: \.element.id) { index, group in
                        Text("환경 \(index + 1) · " + (value.role == .batter ? "\(group.totals.line.plateAppearances)/40타석" : "\(group.totals.innings)/15.0이닝") + " · " + ((value.role == .batter ? group.hasBatterMinimum : group.hasPitcherMinimum) ? "최소 표본 참고 기준 도달" : "표본 부족"))
                            .font(.caption).foregroundStyle(GameTheme.gold)
                    }
                    if value.groups.isEmpty { Text("자료 대기 · 완료한 개인 출전이 없습니다.").font(.caption) }
                }
                GamePanel(title: "평가 대기 사유", onBoard: true, contentSpacing: 16) {
                    ForEach(value.evaluationPending, id: \.self) { Text($0).font(.subheadline) }
                    Text("구단 기준 C·동일 환경 비교 성적 Vref가 준비되지 않아 P/F·육성 전망과 계약 적합도를 확정하지 않습니다.").font(.subheadline).accessibilityIdentifier("scoutFrozenPending")
                    Text("28일 관찰과 계약 평가 창은 별개입니다. 재조회·시즌 결산으로 제의를 재추첨하지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                }
            }.padding(12)
        }.lineSpacing(3).background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("확정 관찰 보고서").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
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
            let source = record.rulesVersion + "/" + versions + (match.pitching == nil ? "/starter" : "/relief-v1")
            var group = bySource[source] ?? ScoutingSampleGroup(id: source)
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
            VStack(alignment: .leading, spacing: gap) {
                if let error {
                    GamePanel(title: "관찰 보고서를 불러오지 못했습니다", onBoard: true) {
                        Text(error).font(.subheadline).accessibilityIdentifier("scoutReportError")
                        Button("다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutReportRetry")
                    }
                } else if let report {
                    ScoutingObservationHomePanel(player: player, calendar: calendar, archive: true)
                    identity(report)
                    GamePanel(title: "현재 능력 · 개인 성장", onBoard: true, contentSpacing: gap) {
                        HomeRadarChart(values: report.abilities.axes)
                        Text("내 현재 능력입니다. 구단의 기량 종합점수나 합격선이 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        HomeDetailButton(title: "원본 능력치·구종 보기", expanded: $showOriginals, identifier: "scoutAbilityDetails")
                        if showOriginals {
                            ForEach(report.abilities.originals) { HomeGrowthRow(value: $0) }
                            ForEach(report.abilities.pitches) { HomeGrowthRow(value: $0) }
                            if !report.abilities.hasInitialValues {
                                Text("저장된 시작값이 없어 현재값만 표시합니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                            }
                        }
                    }
                    GamePanel(title: "실제 출전 표본 · 최근 365일", onBoard: true, contentSpacing: gap) {
                        Text("\(report.start) ~ \(report.date) · 오늘 포함 / 생성일 이후").font(.caption.monospaced()).foregroundStyle(GameTheme.boardMuted)
                        SeasonPersonalRecord(totals: report.totals, role: player.role)
                        Text("진행 중 경기 \(report.pending)건은 완료 후 반영됩니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text("위 합계는 개인 기록 참고용입니다. 서로 다른 경기 환경의 표본을 합쳐 심사하지 않습니다.").font(.caption).foregroundStyle(GameTheme.gold)
                        if report.groups.isEmpty {
                            Text("평가 대기 · 완료한 개인 출전 표본이 없습니다.").font(.subheadline.bold()).accessibilityIdentifier("scoutSampleWaiting")
                        }
                        ForEach(Array(report.groups.enumerated()), id: \.element.id) { index, group in
                            sample(group, number: index + 1)
                        }
                    }
                    GamePanel(title: "평가 준비 · 연결할 조건", onBoard: true, contentSpacing: gap) {
                        Text(report.age < 20 ? "나이 조건 대기 · 프로 계약 검토는 20세부터입니다." : "나이 조건 20세 이상 · 진로/권리 심사는 연결 전입니다.")
                            .font(.subheadline).accessibilityIdentifier("scoutAgeCondition")
                        Text("역할 기량 H는 확정 보고서에서 확인합니다. 구단 기준 C·성적 보정 P·적합도 F는 평가 자료 연결 전입니다.").font(.subheadline).accessibilityIdentifier("scoutEvaluationPending")
                        Text("동일 환경의 비교 성적(Vref)이 아직 없어 성적 보정과 합격 여부를 산출하지 않습니다. 관심 구단·다음 관찰일·제의도 생성하지 않습니다.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        if report.age >= 19 {
                            Text("졸업 시즌 성적 심사·대학/무소속 진로는 후속 단계입니다. 최근 365일 표본만으로 진로를 확정하지 않습니다.")
                                .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    Button("현재 자료 다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutReportRefresh")
                }
            }.padding(12)
        }.lineSpacing(typeSize.isAccessibilitySize ? 5 : 3)
            .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle("내 관찰 보고서").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
            .onAppear(perform: load)
    }
    private func identity(_ report: ScoutingReportSnapshot) -> some View {
        ScoutDossier(title: "선수 관찰 파일", code: "PLAYER RECORD  /  READ ONLY", stamp: "평가 준비", isPreview: false) {
            HStack(alignment: .top, spacing: 16) {
                PixelPlayer(appearance: player.appearance).frame(width: 38, height: 54).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(player.name)  #\(player.jerseyNumber)").font(.headline).accessibilityIdentifier("scoutActualPlayer")
                    Text("\(report.age)세 · " + (player.role == .batter ? "타자 / \(FieldPosition(rawValue: player.positionRaw)?.label ?? player.positionRaw)" : "투수 / \(player.throwingHandRaw == "left" ? "좌투" : "우투")"))
                        .font(.subheadline).accessibilityIdentifier("scoutActualRole")
                    Text(report.age <= 18 ? player.schoolName : SeasonSchedule.academicStatus(age: report.age)).font(.subheadline).accessibilityIdentifier("scoutActualAffiliation")
                    if report.age > 18 { Text("등록 학교 · " + player.schoolName).font(.caption) }
                }
            }
            Text("기준일 \(report.date) · 현재 저장 자료를 읽어 표시합니다.").font(.caption).foregroundStyle(ScoutDossierInk.muted)
            Text("표시용 조회 · 보고서 평가/저장·선수 성장·날짜 진행 없음").font(.caption).foregroundStyle(ScoutDossierInk.muted)
        }
    }
    private func sample(_ group: ScoutingSampleGroup, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("고교 공식 · 경기 환경 \(number)").font(.subheadline.bold())
            if player.role == .batter {
                Text("\(group.totals.games)경기 · \(group.totals.line.plateAppearances) / 40타석").font(.subheadline.monospaced()).accessibilityIdentifier("scoutSample-\(number)")
            } else {
                Text("\(group.totals.games)등판 · \(group.totals.innings) / 15.0이닝").font(.subheadline.monospaced()).accessibilityIdentifier("scoutSample-\(number)")
            }
            let enough = player.role == .batter ? group.hasBatterMinimum : group.hasPitcherMinimum
            Text(enough ? "육성 심사 최소 표본 참고 기준 도달 · 평가/합격 확정 아님" : "표본 부족 · 같은 경기 환경의 실제 출전 기록을 더 쌓아 주세요.")
                .font(.caption).foregroundStyle(enough ? GameTheme.growth : GameTheme.gold)
        }.padding(.vertical,8)
    }
}
