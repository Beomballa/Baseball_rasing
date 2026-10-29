import SwiftUI
import SwiftData

struct HomeRadarChart: View {
    let values: [HomeAbilityValue]
    var onPaper = false
    private var chartGrowth: Color { onPaper ? Color(hex: 0x237459) : GameTheme.growth }
    private var weakestID: String? { values.min { $0.current < $1.current }?.id }
    @Environment(\.dynamicTypeSize) private var typeSize
    private var hasBaseline: Bool { values.allSatisfy { $0.initial != nil } }
    var body: some View {
        VStack(spacing: 8) {
            if typeSize.isAccessibilitySize {
                ForEach(values) { value in
                    HomeGrowthRow(value: value, onPaper: onPaper)
                }
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
                            context.fill(current, with: .color(chartGrowth.opacity(0.16)))
                            context.stroke(current, with: .color(chartGrowth), lineWidth: 2)
                            if hasBaseline {
                                context.stroke(polygon(values.compactMap(\.initial)), with: .color(onPaper ? Color(hex: 0x8b431b) : GameTheme.gold), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                            for (index, value) in values.enumerated() {
                                let p = point(index, value.current)
                                context.fill(Path(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(chartGrowth))
                            }
                        }
                        ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                            let angle = Double(index) * 2 * .pi / Double(max(1, values.count)) - .pi / 2
                            VStack(spacing: 2) {
                                Text(value.label + (value.id == weakestID ? " · 보완" : "")).foregroundStyle(value.id == weakestID ? Color(hex: onPaper ? 0x8b431b : 0xecc66b) : onPaper ? GameTheme.navy : GameTheme.boardMuted)
                                Text(value.current.formatted(.number.precision(.fractionLength(1)))).bold().foregroundStyle(onPaper ? GameTheme.navy : GameTheme.boardInk)
                            }.font(.caption).monospacedDigit().frame(width: 88)
                                .position(x: center.x + cos(angle) * radius * 1.38, y: center.y + sin(angle) * radius * 1.38)
                        }
                    }
                }.frame(height: 250)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("주요 능력치 그래프, 최대 100. " + values.map { "\($0.label) \($0.current.formatted(.number.precision(.fractionLength(1))))" }.joined(separator: ", "))
                    .accessibilityIdentifier("homeAbilityRadar")
            }
            if let changed = values.filter({ ($0.growth ?? 0) > 0 }).max(by: { ($0.growth ?? 0) < ($1.growth ?? 0) }) {
                Text(changed.label + " · " + changed.growthFeedback)
                    .font(.subheadline).foregroundStyle(chartGrowth)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeGrowthFeedback")
            } else {
                Text(hasBaseline ? "시작 대비 성장 변화는 아직 없습니다" : "시작 기록 없음 · 현재 능력만 표시")
                    .font(.subheadline).foregroundStyle(onPaper ? GameTheme.navy : GameTheme.boardMuted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeGrowthFeedback")
            }
            HStack(spacing: 16) {
                Text("■ 현재").foregroundStyle(chartGrowth)
                if hasBaseline { Text("┄ 시작").foregroundStyle(onPaper ? Color(hex: 0x8b431b) : GameTheme.gold) }
                Spacer(); Text("MAX 100").foregroundStyle(onPaper ? GameTheme.navy : GameTheme.boardMuted)
            }.font(.caption.monospaced())
        }
    }
}

struct HomeGrowthRow: View {
    let value: HomeAbilityValue
    var onPaper = false
    private var ink: Color { onPaper ? GameTheme.navy : GameTheme.boardInk }
    private var muted: Color { onPaper ? GameTheme.muted : GameTheme.boardMuted }
    private var growthColor: Color { onPaper ? Color(hex: 0x237459) : GameTheme.growth }
    private var startColor: Color { onPaper ? Color(hex: 0x8b431b) : GameTheme.gold }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(value.label).font(.subheadline.bold())
                Spacer()
                Text(value.current.formatted(.number.precision(.fractionLength(1)))).font(.subheadline.monospaced().bold())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(onPaper ? GameTheme.navy.opacity(0.12) : GameTheme.board)
                    Rectangle().fill(growthColor.opacity(0.8)).frame(width: max(0, geometry.size.width) * min(100, max(0, value.current)) / 100)
                    if let initial = value.initial {
                        Rectangle().fill(startColor).frame(width: 2).offset(x: max(0, geometry.size.width - 2) * min(100, max(0, initial)) / 100)
                    }
                }.overlay(Rectangle().strokeBorder(GameTheme.boardLine.opacity(0.6)))
            }.frame(height: 7).accessibilityHidden(true)
            if let initial = value.initial, let gain = value.growth {
                HStack {
                    Text("시작 \(initial, specifier: "%.1f")")
                    Spacer()
                    Text(value.growthFeedback)
                        .foregroundStyle(gain > 0 ? growthColor : muted)
                }.font(.caption).foregroundStyle(muted)
            }
        }.foregroundStyle(ink)
            .accessibilityElement(children: .combine).accessibilityIdentifier(value.id)
    }
}

struct HomeDetailButton: View {
    let title: String
    @Binding var expanded: Bool
    var identifier: String
    var onPaper = false
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer(); Text(expanded ? "−" : "+").font(.title3.monospaced().bold())
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(onPaper ? GameTheme.navy : GameTheme.gold)
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


struct DevelopmentHomePanel:View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var failure:String?
    @State private var confirm=false
    var body:some View {
        GamePanel(title:"GROWTH NOTE · 성장 수첩",onBoard:true) {
            if let life=try? player.lifecycle {
                if let development=life.development {
                    HStack(alignment:.firstTextBaseline) {
                        Text(development.timing.label).font(.title3.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("developmentTiming")
                        Spacer(minLength:8)
                        Text("정책 V2").font(.caption.monospaced())
                    }
                    CareerManagementNote(title:"현재 저장된 발현 · 실제 훈련에 적용",detail:"발현 시기와 이미 열린 집중을 표시합니다. 아래 준비 횟수는 미래 발동 확률이나 최대 잠재력 수치가 아닙니다.",identifier:"developmentCurrentBasis")
                    if let window=development.active(on:player.gameDate) {
                        Text((window.pitchCode.flatMap {PitchType(rawValue:$0)?.label} ?? window.kind.label)+" · 성장 집중 중").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("developmentActiveWindow")
                        Text("남은 \(8-window.used)회 · "+ManagementDisplay.date(window.expires)+"까지").font(.subheadline.monospacedDigit())
                        ProgressView(value:Double(window.used),total:8).tint(GameTheme.gold)
                        Text("관련 훈련 성장에만 보너스 · 추가 성장 예산 \(max(0,0.6-window.spent),specifier:"%.1f") 남음").font(.subheadline)
                        NavigationLink {CareerTrainingDestination(player:player,calendar:calendar,initialKind:window.kind)} label: {Text((window.pitchCode.flatMap {PitchType(rawValue:$0)?.label} ?? window.kind.label)+" 훈련 · 준비/이어하기")}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("developmentTraining")
                    } else {
                        let from=(try? GameDate(player.gameDate).adding(days:-55).description) ?? player.gameDate
                        let preparations=development.proofs.mapValues {$0.filter {$0.date>=from}}.filter {!$0.value.isEmpty}.sorted {$0.value.count == $1.value.count ? $0.key<$1.key:$0.value.count>$1.value.count}
                        if let first=preparations.first {
                            let label=TrainingKind(rawValue:first.key)?.label ?? PitchType(rawValue:String(first.key.dropFirst(6)))?.label ?? "구종"
                            Text(label+" 준비 · \(first.value.count) / 8회").font(.headline).accessibilityIdentifier("developmentPreparation")
                            ProgressView(value:Double(first.value.count),total:8).tint(GameTheme.growth)
                        } else {Text("꾸준한 훈련에서 성장 조짐을 발견합니다.").font(.subheadline).accessibilityIdentifier("developmentPreparation")}

                    }
                    DisclosureGroup("성장 규칙·집중 조건") {
                    Text("고교의 기초 성장은 빠르게 · 높은 능력은 천천히").font(.subheadline)
                    Text("성장 집중 시기 \(development.timing.ages.lowerBound)~\(development.timing.ages.upperBound)세 · 최대 능력이나 성공 보장이 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        Text("최근56일 같은 능력8회 · 평균50점 이상·시작 피로40 이하. 적용 후14일과 발현 시기 조건,연1회를 확인합니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    }.tint(GameTheme.gold).accessibilityIdentifier("developmentRules")
                    DisclosureGroup("성장·노화와 전환 기록") {
                        Text("정책 적용 · "+ManagementDisplay.date(development.adopted)+" 이후 새 훈련부터. 구속·주력은27세,파워·송구·지구력은29세,복합 기술은31세,제구·선구안·구종은34세부터 게임용 감소를 적용합니다. 기존 경기XP/특성·포지션XP는 종전 규칙입니다.").font(.subheadline)
                        ForEach(development.windows) {w in Text(ManagementDisplay.date(w.opened)+" · "+w.kind.label+" 집중 · 사용\(w.used)/8").font(.subheadline)}
                        ForEach(Array(development.positions.enumerated()),id:\.offset) {_,change in Text(ManagementDisplay.date(change.date)+" · "+change.from.label+" → "+change.to.label).font(.subheadline)}
                    }.tint(GameTheme.gold)
                } else {
                    Text("기존 성장 정책 유지 중").font(.headline).accessibilityIdentifier("developmentLegacy")
                    Text("새 정책은 이후 시작하는 능력 훈련·미래 노화에 적용합니다. 현재 능력·구종·기록·진행 중 훈련은 그대로 보존합니다.").font(.subheadline)
                    Button("새 성장 수첩 시작") {confirm=true}.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("developmentAdopt")
                }
            } else {Text("성장 기록을 읽지 못했습니다.").foregroundStyle(GameTheme.gold)}
            if let failure {Text(failure).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("developmentError")}
        }.alert("새 성장 정책 적용",isPresented:$confirm) {
            Button("현재 능력을 유지하고 적용") {do {try DevelopmentStore.adopt(player:player,calendar:calendar,in:context);failure=nil} catch {failure=error.localizedDescription}}
            Button("취소",role:.cancel) {}
        } message: {Text("기존 선수는 균형 발현으로 시작합니다. 과거 훈련·경기·노화는 다시 계산하지 않습니다. 날짜·피로·오늘 행동은 유지됩니다.")}
    }
}


struct OverseasGrowthPanel:View {
    let projections:[OverseasGrowthProjection]
    let policy:OverseasGrowthPolicy?
    let date:String
    var body:some View {
        GamePanel(title:"2년 성장 전망 · 역할 기량",onBoard:true,contentSpacing:12) {
            CareerManagementNote(title:"보고서 당시 고정된 가정 · 실제 성장과 구분",detail:"기준일 "+ManagementDisplay.date(date)+". 현재 선수의 준비 횟수로 전망을 다시 계산하지 않으며 미래 발현 확률을 예측하지 않습니다.",identifier:"growthForecastBasis")
                        ForEach(projections) {row in
                            Text(DomesticContractOffer.roleName(row.roleID)).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                            Text("현재 \(number(row.current)) → 기준 \(number(row.baseline))\n보수 \(number(row.conservative)) / 낙관 \(number(row.optimistic))")
                                .font(.subheadline.monospaced()).lineSpacing(6).accessibilityIdentifier("overseasProjection-"+row.roleID)
                        }
            if let policy {
                Text("성장 모형 V2 · "+policy.development.timing.label).font(.headline).accessibilityIdentifier("growthForecastPolicy")
                Text("고구간 성장 감속 · 미래 기념일 노화 · 41세 전까지만 계산").font(.subheadline)
                Text(policy.development.active(on:date) == nil ? "확인된 성장 집중 없음 · 미래 발동은 가정하지 않음":"현재 발동한 집중의 남은 기한·횟수·추가 예산만 반영").font(.subheadline).accessibilityIdentifier("growthForecastWindow")
            } else {Text("고정 비교모형 V1 · 당시 규칙 보존").font(.subheadline).accessibilityIdentifier("growthForecastPolicy")}
            Text("2개 달력연도 · 연180회 가정 · 보수 점수50/피로60, 기준75/40, 낙관100/0. 선택 역할의 능력·구종을 순환 훈련합니다. 피로는 시나리오 고정값이며 실제 일정 예측이 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            Text("경기 XP·부상·미래 성장 집중은 미포함. 전망은 하락할 수도 있으며 실제 성장·훈련 보상·계약이나 주전을 보장하지 않습니다.").font(.subheadline)
        }
    }
    private func number(_ n:Double?) -> String {n.map {String(format:"%.1f",$0)} ?? "자료 부족"}
}


struct CareerManagementNote:View {
    let title:String
    let detail:String
    let identifier:String
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.headline).foregroundStyle(GameTheme.gold)
            Text(detail).font(.subheadline).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal:false,vertical:true)
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(GameTheme.boardPanel,in:ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine,lineWidth:1))
            .accessibilityElement(children:.combine).accessibilityIdentifier(identifier)
    }
}
struct CareerEvidenceTag:View {
    let kind:CareerEvidenceKind
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Text(kind.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
            Text(kind.purpose).font(.subheadline).fixedSize(horizontal:false,vertical:true)
        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(GameTheme.board,in:ManagementStepFrame())
            .accessibilityElement(children:.combine).accessibilityIdentifier("careerEvidence-"+String(describing:kind))
    }
}
