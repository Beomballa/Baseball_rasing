import SwiftUI

struct HomeRadarChart: View {
    let values: [HomeAbilityValue]
    @Environment(\.dynamicTypeSize) private var typeSize
    private var hasBaseline: Bool { values.allSatisfy { $0.initial != nil } }
    var body: some View {
        VStack(spacing: 8) {
            if typeSize.isAccessibilitySize {
                ForEach(values) { HomeGrowthRow(value: $0) }
            } else {
                GeometryReader { geometry in
                    let size = geometry.size
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * 0.31
                    ZStack {
                        Canvas { context, _ in
                            func point(_ index: Int, _ value: Double) -> CGPoint {
                                let angle = Double(index) * 2 * .pi / Double(max(1, values.count)) - .pi / 2
                                let distance = radius * min(100, max(0, value)) / 100
                                return CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                            }
                            func polygon(_ scores: [Double]) -> Path {
                                Path { path in
                                    for (index, value) in scores.enumerated() {
                                        let p = point(index, value)
                                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                                    }
                                    path.closeSubpath()
                                }
                            }
                            for level in [25.0, 50, 75, 100] {
                                context.stroke(polygon(Array(repeating: level, count: values.count)), with: .color(GameTheme.boardLine.opacity(0.5)), lineWidth: 1)
                            }
                            for index in values.indices {
                                var line = Path(); line.move(to: center); line.addLine(to: point(index, 100))
                                context.stroke(line, with: .color(GameTheme.boardLine.opacity(0.4)), lineWidth: 1)
                            }
                            let current = polygon(values.map(\.current))
                            context.fill(current, with: .color(GameTheme.growth.opacity(0.16)))
                            context.stroke(current, with: .color(GameTheme.growth), lineWidth: 2)
                            if hasBaseline {
                                context.stroke(polygon(values.compactMap(\.initial)), with: .color(GameTheme.gold), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                            for (index, value) in values.enumerated() {
                                let p = point(index, value.current)
                                context.fill(Path(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(GameTheme.growth))
                            }
                        }
                        ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                            let angle = Double(index) * 2 * .pi / Double(max(1, values.count)) - .pi / 2
                            VStack(spacing: 2) {
                                Text(value.label).foregroundStyle(GameTheme.boardMuted)
                                Text(value.current.formatted(.number.precision(.fractionLength(1)))).bold().foregroundStyle(GameTheme.boardInk)
                            }.font(.caption).monospacedDigit().frame(width: 88)
                                .position(x: center.x + cos(angle) * radius * 1.38, y: center.y + sin(angle) * radius * 1.38)
                        }
                    }
                }.frame(height: 250)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("주요 능력치 그래프, 최대 100. " + values.map { "\($0.label) \($0.current.formatted(.number.precision(.fractionLength(1))))" }.joined(separator: ", "))
                    .accessibilityIdentifier("homeAbilityRadar")
            }
            HStack(spacing: 16) {
                Text("■ 현재").foregroundStyle(GameTheme.growth)
                if hasBaseline { Text("┄ 시작").foregroundStyle(GameTheme.gold) }
                Spacer(); Text("MAX 100").foregroundStyle(GameTheme.boardMuted)
            }.font(.caption.monospaced())
        }
    }
}

struct HomeGrowthRow: View {
    let value: HomeAbilityValue
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(value.label).font(.subheadline.bold())
                Spacer()
                Text(value.current.formatted(.number.precision(.fractionLength(1)))).font(.subheadline.monospaced().bold())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(GameTheme.board)
                    Rectangle().fill(GameTheme.growth.opacity(0.8)).frame(width: max(0, geometry.size.width) * min(100, max(0, value.current)) / 100)
                    if let initial = value.initial {
                        Rectangle().fill(GameTheme.gold).frame(width: 2).offset(x: max(0, geometry.size.width - 2) * min(100, max(0, initial)) / 100)
                    }
                }.overlay(Rectangle().strokeBorder(GameTheme.boardLine.opacity(0.6)))
            }.frame(height: 7).accessibilityHidden(true)
            if let initial = value.initial, let gain = value.growth {
                HStack {
                    Text("시작 \(initial, specifier: "%.1f")")
                    Spacer()
                    Text(gain == 0 ? "변화 없음" : "\(gain > 0 ? "+" : "")\(gain.formatted(.number.precision(.fractionLength(1))))")
                        .foregroundStyle(gain > 0 ? GameTheme.growth : GameTheme.boardMuted)
                }.font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
        }.foregroundStyle(GameTheme.boardInk)
            .accessibilityElement(children: .combine).accessibilityIdentifier(value.id)
    }
}

struct HomeDetailButton: View {
    let title: String
    @Binding var expanded: Bool
    var identifier: String
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer(); Text(expanded ? "−" : "+").font(.title3.monospaced().bold())
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(GameTheme.gold)
            .accessibilityIdentifier(identifier).accessibilityValue(expanded ? "펼침" : "접힘")
    }
}

struct MatchAbilityGrowthPanel: View {
    let experience: MatchAbilityExperience
    var prefix = "game"
    var body: some View {
        if let result = experience.result {
            GamePanel(title: "경기 능력 성장", onBoard: true) {
                Text("경험 XP +\(result.rawXP, specifier: "%.1f")")
                    .font(.headline).foregroundStyle(GameTheme.growth).accessibilityIdentifier(prefix + "AbilityXP")
                Text("출전 \(result.participation * 100, specifier: "%.0f")% · 성과 보너스 \(result.quality * 30, specifier: "%.0f")%")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                ForEach(result.awards.filter { $0.rawXP > 0 }, id: \.kind) { award in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(award.kind.label) · XP +\(award.rawXP, specifier: "%.2f")").font(.subheadline.bold())
                        Text("\(award.before, specifier: "%.1f") → \(award.after, specifier: "%.1f")")
                            .font(.caption.monospaced()).foregroundStyle(GameTheme.growth)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier(prefix + "AbilityGrowth-" + award.kind.rawValue)
                }
                if result.rawXP == 0 {
                    Text(experience.annualBefore >= MatchAbilityExperience.annualCap ? "올해 경기 성장 예산을 모두 사용했습니다." : "성장 대상의 출전·성과 또는 성장 여유가 없어 XP를 지급하지 않았습니다.")
                        .font(.caption)
                }
                Text("\(String(experience.year))년 예산 \(experience.annualBefore + result.rawXP, specifier: "%.1f") / 80 XP")
                    .font(.caption.monospaced()).accessibilityIdentifier(prefix + "AnnualAbilityXP")
                Text("나이·능력·시작 피로 보정 · 소수 성장은 내부 누적 · 다음 새 경기 반영")
                    .font(.caption2).foregroundStyle(GameTheme.boardMuted)
            }
        }
    }
}

struct MatchAbilityGrowthHomePanel: View {
    let player: CareerPlayer
    let records: [CareerMatchRecord]
    @State private var annualXP: Double?
    @State private var recent: MatchAbilityExperience?
    @State private var recentDate = ""
    @State private var showDetails = false
    @State private var errorMessage: String?
    private var refreshKey: String {
        player.gameDate + records.filter { $0.playerID == player.id }.map { $0.key + ":\($0.revision)" }.joined(separator: ";")
    }
    private func load() {
        do {
            let year = try GameDate(player.gameDate).year
            annualXP = try CareerMatchStore.annualAbilityXP(playerID: player.id, year: year, records: records)
            let latest = records.first(where: { $0.playerID == player.id && $0.completed && $0.appearance })
            recent = try latest?.snapshot().abilityExperience
            recentDate = latest?.gameDate ?? ""
            errorMessage = nil
        } catch { annualXP = nil; recent = nil; errorMessage = error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 8) {
            GamePanel(title: "올해 경기 성장", onBoard: true) {
                if let annualXP {
                    Text("경험 XP \(annualXP, specifier: "%.1f") / 80")
                        .font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("homeAnnualAbilityBudget")
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(GameTheme.boardPanel)
                            Rectangle().fill(GameTheme.growth).frame(width: geometry.size.width * annualXP / 80)
                        }.overlay(Rectangle().strokeBorder(GameTheme.boardLine))
                    }.frame(height: 8).accessibilityHidden(true)
                    if let result = recent?.result {
                        Text("최근 출전 · " + recentDate).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text("경험 XP +\(result.rawXP, specifier: "%.1f")").font(.subheadline.bold())
                            .foregroundStyle(GameTheme.growth).accessibilityIdentifier("homeAbilityXP")
                        HomeDetailButton(title: "최근 경기 성장 내역", expanded: $showDetails, identifier: "homeMatchGrowthDetails")
                    } else {
                        Text("새 규칙의 공식 경기 완료 후 성장 내역이 표시됩니다. 이전 경기는 소급 지급하지 않습니다.").font(.caption)
                    }
                } else if let errorMessage {
                    Text("경기 성장 조회 실패 · " + errorMessage).font(.caption)
                    Button("성장 내역 다시 확인", action: load).buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryAbilityGrowth")
                }
            }
            if let recent, showDetails {
                MatchAbilityGrowthPanel(experience: recent, prefix: "homeRecent")
            }
        }.task(id: refreshKey) { load() }
    }
}
