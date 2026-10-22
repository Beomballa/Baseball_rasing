import SwiftUI
import SwiftData

struct ScoutingSampleGroup: Identifiable {
    let id: String
    var totals = PersonalSeasonTotals()
    var hasBatterMinimum: Bool { totals.line.plateAppearances >= 40 }
    var hasPitcherMinimum: Bool { totals.line.pitchingOuts >= 45 }
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
                        Text("종합 기량 H·구단 기준 C·성적 보정 P·적합도 F: 평가 엔진 연결 전").font(.subheadline).accessibilityIdentifier("scoutEvaluationPending")
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
