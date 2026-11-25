import SwiftUI

/// 완료 원문의 성적과 지급된 XP만 읽는다. 화면을 열 때 성장 계산을 다시 실행하지 않는다.
struct MatchPlayerReportData {
    struct XPRow: Identifiable {
        let award: MatchAbilityAward
        let share: Double
        var id: String { award.kind.rawValue }
    }
    let summary: MatchResultSummary
    let primary: [MatchResultSummary.Metric]
    let secondary: [MatchResultSummary.Metric]
    let other: [MatchResultSummary.Metric]
    let growth: MatchAbilityGrowth?
    let rows: [XPRow]

    init(summary: MatchResultSummary) {
        self.summary = summary
        let ids = summary.match.role == "pitcher" ? ["innings", "pitchingStrikeouts", "runsAllowed", "pitches"]
            : ["atBats", "hits", "homeRuns", "rbi"]
        let featured = summary.match.appearance ? ids.compactMap { id in summary.metrics.first { $0.id == id } } : []
        primary = Array(featured.prefix(2)); secondary = Array(featured.dropFirst(2))
        other = summary.match.appearance ? summary.metrics.filter { !ids.contains($0.id) } : []
        let storedGrowth = summary.match.appearance ? summary.match.abilityExperience?.result : nil
        growth = storedGrowth
        let totalXP = storedGrowth?.rawXP ?? 0
        rows = (storedGrowth?.awards ?? []).filter { $0.rawXP > 0 }.map { award in
            XPRow(award: award, share: totalXP > 0 ? award.rawXP / totalXP : 0)
        }
    }
}

struct MatchPlayerReport<Portrait: View>: View {
    let data: MatchPlayerReportData
    let name: String
    let number: Int
    let ownTeam: String
    let opponent: String
    var showsSaved = false
    @ViewBuilder let portrait: () -> Portrait
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("내 선수 경기 결과").font(.headline).foregroundStyle(GameTheme.gold)
                if showsSaved {
                    Text("결과 저장 완료").font(.subheadline.bold()).foregroundStyle(GameTheme.growth)
                        .accessibilityIdentifier("gameResultSaved")
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                layout {
                    portrait().frame(width: 72, height: 96).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text((data.summary.match.role == "pitcher" ? "투수" : "타자") + " · #\(number)")
                            .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        Text(name).font(.title3.bold())
                        if data.summary.match.appearance { metrics(data.primary, prominent: true) }
                        else {
                            Text(data.summary.match.role == "pitcher" ? "비등판" : "비출전").font(.title3.bold())
                                .accessibilityIdentifier("gameResultNoAppearance")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !data.secondary.isEmpty { rule; metrics(data.secondary, prominent: false) }
                rule
                Text("내 팀 " + data.summary.outcome).font(.headline).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("careerGameFinished")
                Text("\(ownTeam) \(data.summary.match.teamScore) : \(data.summary.match.opponentScore) \(opponent)")
                    .font(.body.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue("\(data.summary.match.teamScore):\(data.summary.match.opponentScore)")
                    .accessibilityIdentifier("gameFinalScore")
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
                .accessibilityElement(children: .contain).accessibilityIdentifier("gamePlayerReport")
            growth
        }.foregroundStyle(GameTheme.boardInk).accessibilityElement(children: .contain)
    }
    private var rule: some View { Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true) }
    private func metrics(_ rows: [MatchResultSummary.Metric], prominent: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            ForEach(rows) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.label).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    Text(metric.value).font(prominent ? .title.bold() : .title3.bold()).monospacedDigit()
                        .foregroundStyle(prominent ? GameTheme.gold : GameTheme.boardInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore).accessibilityLabel(metric.label + ", " + metric.value)
                    .accessibilityValue(metric.value).accessibilityIdentifier("gameResult-" + metric.id)
            }
        }
    }
    private var growth: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("경기 경험치").font(.headline).foregroundStyle(GameTheme.gold)
            if let result = data.growth {
                Text("경험 XP +\(result.rawXP, specifier: "%.1f")").font(.title3.bold()).foregroundStyle(GameTheme.growth)
                    .accessibilityIdentifier("gameAbilityXP")
                ForEach(data.rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                        layout {
                            Text(row.award.kind.label).font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("+\(row.award.rawXP, specifier: "%.2f") XP").font(.body.monospacedDigit().bold())
                                .foregroundStyle(GameTheme.growth).fixedSize(horizontal: false, vertical: true)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(GameTheme.board)
                                Rectangle().fill(GameTheme.growth).frame(width: geometry.size.width * min(1, max(0, row.share)))
                            }
                        }.frame(height: 7).accessibilityHidden(true)
                        rule
                    }.padding(.vertical, 4).accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.award.kind.label), XP +\(String(format: "%.2f", row.award.rawXP)), 이번 경기 XP의 \(Int((row.share * 100).rounded()))퍼센트")
                        .accessibilityIdentifier("gameAbilityGrowth-" + row.id)
                }
                Text("막대는 이번 경기 총 XP 중 능력별 비중입니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                DisclosureGroup("능력 변화 · 성장 기준") {
                    if let experience = data.summary.match.abilityExperience {
                        MatchAbilityGrowthPanel(experience: experience, prefix: "reportDetail")
                    }
                }.tint(GameTheme.gold).accessibilityIdentifier("gameAbilityGrowthDetails")
            } else {
                Text(data.summary.match.appearance ? "이전 규칙 경기 · 저장된 능력 XP 없음" : "비출전 팀 경기 · 개인 능력 XP 없음")
                    .font(.body).accessibilityIdentifier("gameAbilityXPExcluded")
            }
            rule
            Text("경기 전후 피로").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            Text("\(data.summary.fatigueBefore) → \(data.summary.fatigueAfter)").font(.title3.bold()).monospacedDigit()
                .accessibilityIdentifier("gameResultFatigue")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
    }
}
