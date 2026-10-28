import SwiftUI

struct MatchTimingGauge: View {
    let phase: Double
    let center: Double
    let good: Double
    let perfect: Double
    let label: String
    var batting = false
    var centerLabel = "정타"
    var earlyLabel = "빠름"
    var lateLabel = "늦음"
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold())
            GeometryReader { size in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: batting ? 0x4b8fca : 0x5b5034))
                    if batting {
                        Rectangle().fill(Color(hex: 0xd88454))
                            .frame(width: size.size.width * max(0, 1 - center - good))
                            .offset(x: size.size.width * min(1, center + good))
                    }
                    Rectangle().fill(Color(hex: 0x73b890))
                        .frame(width: size.size.width * good * 2).offset(x: size.size.width * (center - good))
                    Rectangle().fill(GameTheme.gold)
                        .frame(width: size.size.width * perfect * 2).offset(x: size.size.width * (center - perfect))
                    Rectangle().fill(Color(hex: 0xfff4ce)).frame(width: 4)
                        .offset(x: max(0, size.size.width - 4) * phase)
                }
            }.frame(height: 22).clipped()
                .overlay(Rectangle().strokeBorder(Color(hex: 0x9fb7bf), lineWidth: 2))
            if batting {
                if typeSize.isAccessibilitySize {
                    HStack {
                        Text(earlyLabel).foregroundStyle(Color(hex: 0x8cc6f2))
                        Spacer(minLength: 4)
                        Text(centerLabel).foregroundStyle(GameTheme.gold)
                        Text(lateLabel).foregroundStyle(Color(hex: 0xf3a97a))
                    }.font(.caption2.bold()).accessibilityHidden(true)
                } else {
                    GeometryReader { size in
                        Text(earlyLabel).foregroundStyle(Color(hex: 0x8cc6f2)).position(x: 16, y: 7)
                    Text(centerLabel).foregroundStyle(GameTheme.gold).position(x: size.size.width * center, y: 7)
                        Text(lateLabel).foregroundStyle(Color(hex: 0xf3a97a)).position(x: size.size.width - 16, y: 7)
                    }.font(.caption2.bold()).frame(height: 14).accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + (batting ? " · 파랑 \(earlyLabel), 초록 \(centerLabel) 근처, 금색 \(centerLabel) 타이밍, 주황 \(lateLabel)" : " · 초록 구간 GOOD, 노란 구간 PERFECT"))
    }
}

struct BattingAimZone: View {
    @Binding var x: Double
    @Binding var y: Double
    let locked: Bool
    var showsGrid = true
    var body: some View {
        GeometryReader { size in
            ZStack {
                Color.clear
                if showsGrid {
                    Rectangle().fill(GameTheme.paper.opacity(0.08))
                    Rectangle().strokeBorder(Color(hex: 0x9fb7bf), lineWidth: 2)
                        .frame(width: size.size.width * 0.6, height: size.size.height * 0.6)
                    Path { path in
                        for part in [0.4, 0.6] {
                            path.move(to: CGPoint(x: size.size.width * part, y: size.size.height * 0.2))
                            path.addLine(to: CGPoint(x: size.size.width * part, y: size.size.height * 0.8))
                            path.move(to: CGPoint(x: size.size.width * 0.2, y: size.size.height * part))
                            path.addLine(to: CGPoint(x: size.size.width * 0.8, y: size.size.height * part))
                        }
                    }.stroke(Color(hex: 0xf3edcf).opacity(0.4), lineWidth: 1)
                }
                if showsGrid {
                    Rectangle().strokeBorder(GameTheme.gold,lineWidth:3).frame(width:16,height:16)
                        .position(x:size.size.width*x,y:size.size.height*y)
                } else {
                    Canvas { context,canvas in
                        let c=CGPoint(x:canvas.width*x,y:canvas.height*y)
                        for dx in [-1.0,1] {for dy in [-1.0,1] {
                            var corner=Path()
                            corner.move(to:CGPoint(x:c.x+dx*3,y:c.y+dy*6))
                            corner.addLine(to:CGPoint(x:c.x+dx*6,y:c.y+dy*6))
                            corner.addLine(to:CGPoint(x:c.x+dx*6,y:c.y+dy*3))
                            context.stroke(corner,with:.color(GameTheme.gold),lineWidth:2)
                        }}
                        context.fill(Path(CGRect(x:c.x-1,y:c.y-1,width:2,height:2)),with:.color(GameTheme.paper))
                    }.allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !locked else { return }
                x = min(1, max(0, value.location.x / size.size.width))
                y = min(1, max(0, value.location.y / size.size.height))
            })
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("타격 포인트")
        .accessibilityValue("가로 \(Int(x * 100)), 세로 \(Int(y * 100))")
        .accessibilityAction(named: "왼쪽") { if !locked { x = max(0, x - 0.1) } }
        .accessibilityAction(named: "오른쪽") { if !locked { x = min(1, x + 0.1) } }
        .accessibilityAction(named: "위") { if !locked { y = max(0, y - 0.1) } }
        .accessibilityAction(named: "아래") { if !locked { y = min(1, y + 0.1) } }
        .accessibilityIdentifier("battingAimZone")
    }
}

// Broadcast values come only from the match snapshot currently being presented.
enum MatchBroadcastData {
    static func inningMark(_ match: CareerMatch, home: Bool, inning: Int) -> String {
        guard (1...9).contains(inning), let scores = match.inningScores else { return "—" }
        if let runs = (home ? scores.home : scores.away)[inning - 1] { return String(runs) }
        return home && inning == 9 && match.completed && match.half == 17 && match.homeScore > match.awayScore ? "X" : "·"
    }
    static func inningDescription(_ match: CareerMatch, home: Bool, inning: Int) -> String {
        let mark = inningMark(match, home: home, inning: inning)
        return "\(inning)회 " + (mark == "—" ? "미기록" : mark == "·" ? "미시작" : mark == "X" ? "미실시" : mark + "점")
    }
    static func inningSummary(_ match: CareerMatch, home: Bool) -> String {
        guard match.inningScores != nil else { return "이닝별 득점 미기록" }
        return (1...9).map { inningDescription(match, home: home, inning: $0) }.joined(separator: ", ")
    }
    static func hits(_ match: CareerMatch, home: Bool) -> Int? {
        guard let records = match.playerRecords else { return nil }
        return (home ? records.home : records.away).battingTotal.hits
    }
    static func errors(_ match: CareerMatch, home: Bool) -> Int? {
        guard match.detailedFieldVersion == 5, let plays = match.fieldPlays,
              plays.allSatisfy({ $0.version == 5 }) else { return nil }
        return plays.filter { $0.misplay != nil && ($0.half.isMultiple(of: 2) == home) }.count
    }
}

struct MatchBroadcastBoard: View {
    let match: CareerMatch
    let homeName: String
    let awayName: String
    let date: String
    let pulse: String?
    let pulseAt: Date
    var stadium: StadiumIdentity = .legacy
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    private let paper = Color(hex: 0xf3edcf)
    private let muted = Color(hex: 0x93aab8)
    private var panel: Color { Color(hex: stadium.theme.panel) }
    private var activeInning: Int? { match.completed ? nil : match.half / 2 + 1 }
    private var pitchCount: Int? { match.role == "pitcher" ? match.line.pitches : nil }
    private var displayedDate: String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? "\(parts[0])년 \(parts[1])월 \(parts[2])일" : date
    }
    var body: some View {
        VStack(spacing: 5) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayedDate).fixedSize(horizontal: false, vertical: true)
                    Text(match.inningLabel).foregroundStyle(GameTheme.gold)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
            } else {
                HStack(spacing: 6) {
                    Text(displayedDate).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(match.inningLabel).foregroundStyle(GameTheme.gold)
                }.font(.system(.caption2, design: .monospaced, weight: .bold))
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    accessibleTeam(home: false)
                    accessibleTeam(home: true)
                }
            } else {
                VStack(spacing: 1) {
                    inningRow
                    teamRow(home: false)
                    teamRow(home: true)
                }.font(.system(size: 10, weight: .bold, design: .monospaced))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(teamSummary(home: false)). \(MatchBroadcastData.inningSummary(match, home: false)). \(teamSummary(home: true)). \(MatchBroadcastData.inningSummary(match, home: true))")
                    .accessibilityIdentifier("careerGameScore")
            }
            Rectangle().fill(Color(hex: stadium.theme.trim)).frame(height: stadium.theme == .brick ? 2 : 1)
            TimelineView(.animation(minimumInterval: 0.2, paused: reduced || pulse == nil)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(pulseAt)
                let blink = !reduced && elapsed >= 0 && elapsed < 1.2 && Int(elapsed / 0.2).isMultiple(of: 2)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            lamps("B", count: match.balls, total: 3, color: Color(hex: 0x67d58a), blink: blink)
                            lamps("S", count: match.strikes, total: 2, color: Color(hex: 0xf3c94e), blink: blink)
                            lamps("O", count: match.outs, total: 2, color: Color(hex: 0xeb6a5b), blink: blink)
                        }.accessibilityElement(children: .ignore)
                            .accessibilityLabel("B \(match.balls) S \(match.strikes) O \(match.outs)")
                            .accessibilityIdentifier("careerGameCount")
                        baseDiamond
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MatchPresentation.pitchName(match.lastManual)).lineLimit(1)
                            .accessibilityIdentifier("boardPitchName")
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(match.lastManual.map { String($0.speed) } ?? "–––")
                                .font(.system(.headline, design: .monospaced, weight: .heavy)).foregroundStyle(GameTheme.gold)
                            Text("km/h").font(.caption2)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("boardPitchSpeed")
                    }.font(.system(.caption2, design: .monospaced, weight: .bold))
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("맑음 22° · 예시").font(.caption2)
                        Text("P \(pitchCount.map(String.init) ?? "—")").font(.system(.caption2, design: .monospaced, weight: .bold))
                            .accessibilityLabel(pitchCount.map { "내 투구 수 \($0)" } ?? "투구 수 미집계").accessibilityIdentifier("boardPitchCount")
                    }.foregroundStyle(muted)
                }
            }
        }.foregroundStyle(paper).padding(8).frame(maxWidth: .infinity)
            .background(panel)
            .overlay(StadiumBoardFrame(stadium: stadium).allowsHitTesting(false).accessibilityHidden(true))
            .accessibilityElement(children: .contain).accessibilityIdentifier("matchScoreboard")
    }
    private var inningRow: some View {
        HStack(spacing: 0) {
            Text("TEAM").foregroundStyle(muted).frame(width: 58, alignment: .leading)
            ForEach(1...9, id: \.self) { inning in
                Text(String(inning)).frame(maxWidth: .infinity, minHeight: 14)
                    .foregroundStyle(activeInning == inning ? GameTheme.gold : muted)
                    .background(activeInning == inning ? Color(hex: 0x29445a) : .clear)
            }
            ForEach(["R", "H", "E"], id: \.self) { Text($0).frame(width: 20).foregroundStyle(muted) }
        }
    }
    private func teamRow(home: Bool) -> some View {
        HStack(spacing: 0) {
            Text(home ? homeName : awayName).lineLimit(1).truncationMode(.tail).frame(width: 58, alignment: .leading)
            ForEach(1...9, id: \.self) { inning in
                Text(MatchBroadcastData.inningMark(match, home: home, inning: inning))
                    .foregroundStyle(activeInning == inning ? GameTheme.gold : paper)
                    .frame(maxWidth: .infinity, minHeight: 17)
                    .background(activeInning == inning ? Color(hex: 0x29445a) : .clear)
            }
            Text(String(home ? match.homeScore : match.awayScore)).foregroundStyle(GameTheme.gold).frame(width: 20)
            Text(MatchBroadcastData.hits(match, home: home).map(String.init) ?? "—").frame(width: 20)
            Text(MatchBroadcastData.errors(match, home: home).map(String.init) ?? "—").frame(width: 20)
        }
    }
    private func accessibleTeam(home: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(home ? homeName : awayName).font(.headline)
            HStack(alignment: .top, spacing: 6) {
                accessibleTotal("R", value: String(home ? match.homeScore : match.awayScore))
                accessibleTotal("H", value: MatchBroadcastData.hits(match, home: home).map(String.init) ?? "—")
                accessibleTotal("E", value: MatchBroadcastData.errors(match, home: home).map(String.init) ?? "—")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 6) {
                ForEach(1...9, id: \.self) { inning in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(inning)회").font(.caption2).foregroundStyle(muted)
                        Text(MatchBroadcastData.inningMark(match, home: home, inning: inning)).font(.headline.monospacedDigit())
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(MatchBroadcastData.inningDescription(match, home: home, inning: inning))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(teamSummary(home: home)). \(MatchBroadcastData.inningSummary(match, home: home))")
            .accessibilityIdentifier(home ? "boardTeam-home" : "boardTeam-away")
    }
    private func accessibleTotal(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(muted)
            Text(value).font(.headline.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func teamSummary(home: Bool) -> String {
        "\(home ? homeName : awayName) 득점 \(home ? match.homeScore : match.awayScore), 안타 \(MatchBroadcastData.hits(match, home: home).map(String.init) ?? "미집계"), 실책 \(MatchBroadcastData.errors(match, home: home).map(String.init) ?? "미집계")"
    }
    private func lamps(_ label: String, count: Int, total: Int, color: Color, blink: Bool) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).frame(width: 9)
            ForEach(0..<total, id: \.self) { i in
                let confirming = pulse == label && i == (count == 0 ? total - 1 : min(count, total) - 1)
                Rectangle().fill(i < count || confirming ? color : Color(hex: 0x294354))
                    .frame(width: 7, height: 6)
                    .opacity(confirming && blink ? 0.2 : 1)
            }
        }
    }
    private var baseDiamond: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Rectangle().fill(match.bases[index] ? GameTheme.gold : Color(hex: 0x294354))
                    .frame(width: 8, height: 8).rotationEffect(.degrees(45))
                    .position(x: index == 0 ? 28 : index == 1 ? 18 : 8, y: index == 1 ? 7 : 17)
            }
        }.frame(width: 36, height: 27)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(match.bases.contains(true) ? "주자 \(match.bases.enumerated().filter { $0.element }.map { String($0.offset + 1) }.joined(separator: ","))루" : "주자 없음")
    }
}


/// A compact visual plate inside the full 44-point button target.
struct MatchPitchChip: View {
    let name: String
    let mastery: Double
    let selected: Bool
    var code = "four-seam"
    var hand = "right"
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 3) {
            MatchGrip(code: code, hand: hand).frame(width: typeSize.isAccessibilitySize ? 38 : 23, height: typeSize.isAccessibilitySize ? 38 : 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(typeSize.isAccessibilitySize ? .headline : .system(size: 12, weight: .heavy, design: .monospaced))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                HStack(spacing: 3) {
                    HStack(spacing: 1) {
                        ForEach(0..<8, id: \.self) { index in
                            Rectangle().fill(Double(index) < min(100, max(0, mastery))/12.5 ? GameTheme.gold : Color(hex: 0x345365))
                                .frame(maxWidth: 3).frame(height: 3)
                        }
                    }.accessibilityHidden(true)
                    Text(mastery.formatted(.number.precision(.fractionLength(1))))
                        .font(typeSize.isAccessibilitySize ? .body.monospaced().bold() : .system(size: 9, weight: .bold, design: .monospaced))
                }
            }
        }.padding(.leading, 8).padding(.trailing, 5).padding(.vertical, typeSize.isAccessibilitySize ? 10 : 0)
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(selected ? GameTheme.gold : GameTheme.paper)
            .background(ManagementStepFrame().fill(Color(hex: 0x102a3f)))
            .overlay(ManagementStepFrame().strokeBorder(selected ? GameTheme.gold : Color(hex: 0x66818f), lineWidth: 2))
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(GameTheme.gold).frame(width: 3, height: 14).padding(.leading, 5) }
            }
    }
}

enum PitchCourseGeometry {
    static func target(at point: CGPoint, size: CGSize) -> PitchTarget {
        PitchTarget(x: min(1, max(0, (point.x / max(1, size.width) - 0.08) / 0.84)),
                    y: min(1, max(0, (point.y / max(1, size.height) - 0.08) / 0.84)))
    }
    static func marker(_ target: PitchTarget, size: CGSize) -> CGPoint {
        PitchLocationBoard.marker(x: target.x, y: target.y, size: size)
    }
}

struct PitchCourseDiagram: View {
    let recommended: PitchTarget?
    let target: PitchTarget?
    let actual: PitchTarget?
    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint {
                PitchCourseGeometry.marker(PitchTarget(x: x, y: y), size: size)
            }
            let a = point(0.2, 0.2), b = point(0.8, 0.8)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x112c3b)))
            context.stroke(Path(CGRect(x: a.x, y: a.y, width: b.x-a.x, height: b.y-a.y)),
                           with: .color(GameTheme.boardInk), lineWidth: 1.5)
            for part in [0.4, 0.6] {
                var lines = Path()
                lines.move(to: CGPoint(x: point(part, 0).x, y: a.y)); lines.addLine(to: CGPoint(x: point(part, 0).x, y: b.y))
                lines.move(to: CGPoint(x: a.x, y: point(0, part).y)); lines.addLine(to: CGPoint(x: b.x, y: point(0, part).y))
                context.stroke(lines, with: .color(GameTheme.boardLine), lineWidth: 0.7)
            }
            if let recommended {
                let p = PitchCourseGeometry.marker(recommended, size: size)
                var diamond = Path()
                diamond.move(to: CGPoint(x: p.x, y: p.y-7)); diamond.addLine(to: CGPoint(x: p.x+7, y: p.y))
                diamond.addLine(to: CGPoint(x: p.x, y: p.y+7)); diamond.addLine(to: CGPoint(x: p.x-7, y: p.y)); diamond.closeSubpath()
                context.stroke(diamond, with: .color(Color(hex: 0x8cc6f2)), lineWidth: 2)
            }
            if let target {
                let p = PitchCourseGeometry.marker(target, size: size)
                var cross = Path()
                cross.move(to: CGPoint(x: p.x-5, y: p.y)); cross.addLine(to: CGPoint(x: p.x+5, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y-5)); cross.addLine(to: CGPoint(x: p.x, y: p.y+5))
                context.stroke(cross, with: .color(GameTheme.gold), lineWidth: 2)
            }
            if let actual { PixelBaseball.draw(in: context, at: PitchCourseGeometry.marker(actual, size: size), diameter: 9) }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct PitchCourseControl: View {
    let recommended: PitchTarget
    @Binding var selection: PitchTarget?
    let locked: Bool
    let result: ManualMatchResult?
    var arrived = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var reviewingLast = false
    private var reviewing: Bool { arrived || reviewingLast }
    private var editable: Bool { !locked && !reviewing }
    private var selected: PitchTarget { selection ?? recommended }
    private var status: String {
        reviewing ? (arrived ? "도착 비교" : "직전 코스") : selection == nil ? "추천 코스" : "직접 조준"
    }
    private var displayedStatus: String {
        guard reviewing, !typeSize.isAccessibilitySize else { return status }
        return (result?.pitchAim == nil ? "목표 미집계" : status) + " · ●실제"
    }
    private var coordinateSummary: String {
        if reviewing, let result {
            let actual = "실제 가로 \(Int((result.x * 100).rounded())), 세로 \(Int((result.y * 100).rounded()))"
            guard let aim = result.pitchAim else { return "목표 기록 없음, " + actual }
            return "목표 가로 \(Int((aim.target.x * 100).rounded())), 세로 \(Int((aim.target.y * 100).rounded())), " + actual
        }
        return "\(selection == nil ? "추천 사용" : "직접 변경"), 목표 가로 \(Int((selected.x * 100).rounded())), 세로 \(Int((selected.y * 100).rounded()))"
    }
    private func move(x: Double, y: Double) {
        guard editable else { return }
        selection = PitchTarget(x: min(1, max(0, selected.x+x)), y: min(1, max(0, selected.y+y)))
    }
    private var coursePad: some View {
        GeometryReader { geometry in
            PitchCourseDiagram(recommended: reviewing ? result?.pitchAim?.recommended : recommended,
                               target: reviewing ? result?.pitchAim?.target : selected,
                               actual: reviewing ? result.map { PitchTarget(x: $0.x, y: $0.y) } : nil)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard editable else { return }
                    selection = PitchCourseGeometry.target(at: value.location, size: geometry.size)
                })
        }.aspectRatio(1, contentMode: .fit).frame(minHeight: 84)
            .accessibilityRepresentation {
                Text("투구 목표 코스")
                    .accessibilityValue(coordinateSummary)
                    .accessibilityHint(editable ? "동작 메뉴에서 왼쪽, 오른쪽, 위, 아래로 목표를 변경하세요" : "투구 중이거나 직전 코스를 확인하고 있습니다")
                    .accessibilityAction(named: "왼쪽") { move(x: -0.1, y: 0) }
                    .accessibilityAction(named: "오른쪽") { move(x: 0.1, y: 0) }
                    .accessibilityAction(named: "위") { move(x: 0, y: -0.1) }
                    .accessibilityAction(named: "아래") { move(x: 0, y: 0.1) }
                    .accessibilityIdentifier("pitchCoursePad")
            }
    }
    private var legend: some View {
        HStack(spacing: 4) {
            Text("◇추천").foregroundStyle(Color(hex: 0x8cc6f2))
            Text("+목표").foregroundStyle(GameTheme.gold)
        }.font(typeSize.isAccessibilitySize ? .caption : .system(size: 10, weight: .bold, design: .monospaced))
            .accessibilityHidden(true)
    }
    private var courseActions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: 2)) : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            Button { selection = nil; reviewingLast = false } label: { Text("추천").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                .disabled(locked).accessibilityLabel("포수 추천으로 복귀").accessibilityIdentifier("pitchCourseReset")
            Button { reviewingLast.toggle() } label: { Text(reviewingLast ? "닫기" : "직전").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                .disabled(locked || result == nil).accessibilityLabel(reviewingLast ? "직전 코스 닫기" : "직전 목표와 실제 코스 보기")
                .accessibilityIdentifier("pitchCourseReview")
        }.font(typeSize.isAccessibilitySize ? .caption.bold() : .system(size: 12, weight: .bold, design: .monospaced))
            .buttonStyle(.plain).foregroundStyle(GameTheme.paper).background(Color(hex: 0x254659))
    }
    var body: some View {
        VStack(spacing: 3) {
            Text(displayedStatus)
                .font(typeSize.isAccessibilitySize ? .headline : .system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(GameTheme.gold).accessibilityIdentifier("pitchCourseStatus")
            if typeSize.isAccessibilitySize {
                coursePad
                legend
                if reviewing { Text(result?.pitchAim == nil ? "목표 기록 없음" : "● 실제 도착").font(.caption).foregroundStyle(GameTheme.paper) }
                courseActions
            } else {
                HStack(alignment: .top, spacing: 2) {
                    VStack(spacing: 3) { coursePad.frame(width: 84, height: 84); legend }.frame(width: 84)
                    courseActions.frame(width: 44)
                }
            }
        }.padding(5).background(GameTheme.board.opacity(0.96))
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pitchCourseControl")
            .onChange(of: locked) { _, _ in reviewingLast = false }
            .onChange(of: result) { _, _ in reviewingLast = false }
    }
}

// A read-only identity derived from the saved home team, never from the match RNG.
struct StadiumIdentity: Equatable, Sendable {
    enum Theme: Int, CaseIterable, Sendable {
        case harbor, brick, grove, metro
        var title: String { ["항구", "벽돌", "숲", "도시"][rawValue] }
        var panel: Int { [0x0b2538, 0x30251f, 0x132e29, 0x171f38][rawValue] }
        var trim: Int { [0x64b8bc, 0xc78b62, 0xa5b975, 0x8b9dda][rawValue] }
        var accent: Int { [0x80ddd3, 0xf2bd80, 0xd7d88b, 0xb8c9ff][rawValue] }
    }
    let key: String
    let seed: UInt64
    var theme: Theme { Theme(rawValue: Int(seed % 4))! }
    var variation: Int { Int((seed / 4) % 3) }
    static let legacy = StadiumIdentity(homeTeamID: "legacy-ground")
    init(homeTeamID: String) {
        key = homeTeamID
        seed = homeTeamID.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    var sponsors: [Sponsor] {
        let start = Int((seed / 12) % UInt64(Self.catalog.count))
        return (0..<3).map { Self.catalog[(start + $0 * 3) % Self.catalog.count] }
    }
    struct Sponsor: Equatable, Sendable { let name: String; let mark: String }
    static let catalog: [Sponsor] = [
        .init(name: "모루 기어", mark: "M"), .init(name: "아홉별 식품", mark: "9"),
        .init(name: "다람 운송", mark: "D"), .init(name: "잔디 서점", mark: "J"),
        .init(name: "누리 바람", mark: "N"), .init(name: "오름 공방", mark: "O"),
        .init(name: "초록 쉼표", mark: "+"), .init(name: "바다 링크", mark: "B")
    ]
}

private struct StadiumBoardFrame: View {
    let stadium: StadiumIdentity
    var body: some View {
        GeometryReader { g in
            let color = Color(hex: stadium.theme.trim)
            ZStack {
                Rectangle().strokeBorder(color, lineWidth: 2)
                if stadium.theme == .brick {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle().fill(color).frame(width: 8, height: 3)
                            .position(x: 10 + CGFloat(i) * (g.size.width-20)/4, y: 2)
                    }
                } else if stadium.theme == .grove {
                    Rectangle().fill(color).frame(width: 5, height: max(0,g.size.height-8)).position(x: 3,y:g.size.height/2)
                    Rectangle().fill(color).frame(width: 5, height: max(0,g.size.height-8)).position(x: g.size.width-3,y:g.size.height/2)
                } else {
                    ForEach(0..<(stadium.variation+3), id: \.self) { i in
                        Rectangle().fill(color).frame(width: stadium.theme == .metro ? 12 : 5, height: 3)
                            .position(x: g.size.width-10-CGFloat(i)*16,y: g.size.height-2)
                    }
                }
            }
        }
    }
}
