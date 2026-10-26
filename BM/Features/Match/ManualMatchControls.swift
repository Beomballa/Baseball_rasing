import SwiftUI

struct MatchTimingGauge: View {
    let phase: Double
    let center: Double
    let good: Double
    let perfect: Double
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold())
            GeometryReader { size in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: 0x5b5034))
                    Rectangle().fill(Color(hex: 0x73b890))
                        .frame(width: size.size.width * good * 2).offset(x: size.size.width * (center - good))
                    Rectangle().fill(GameTheme.gold)
                        .frame(width: size.size.width * perfect * 2).offset(x: size.size.width * (center - perfect))
                    Rectangle().fill(Color(hex: 0xfff4ce)).frame(width: 4)
                        .offset(x: max(0, size.size.width - 4) * phase)
                }
            }.frame(height: 22)
                .overlay(Rectangle().strokeBorder(Color(hex: 0x9fb7bf), lineWidth: 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + " · 초록 구간 GOOD, 노란 구간 PERFECT")
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

// The match does not store inning-by-inning runs or zone averages. Missing history stays missing.
enum MatchBroadcastData {
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
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    private let paper = Color(hex: 0xf3edcf)
    private let muted = Color(hex: 0x93aab8)
    private let panel = Color(hex: 0x0b2538)
    private var activeInning: Int? { match.completed ? nil : match.half / 2 + 1 }
    private var pitchCount: Int? { match.role == "pitcher" ? match.line.pitches : nil }
    private var displayedDate: String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? "\(parts[0])년 \(parts[1])월 \(parts[2])일" : date
    }
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(displayedDate).lineLimit(1)
                Spacer(minLength: 2)
                Text(match.inningLabel).foregroundStyle(GameTheme.gold)
            }.font(.system(.caption2, design: .monospaced, weight: .bold))
            if typeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    accessibleTeam(home: false)
                    accessibleTeam(home: true)
                    Text("이닝별 득점 미집계").font(.caption).foregroundStyle(muted)
                }
            } else {
                VStack(spacing: 1) {
                    inningRow
                    teamRow(home: false)
                    teamRow(home: true)
                }.font(.system(size: 10, weight: .bold, design: .monospaced))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(teamSummary(home: false)). \(teamSummary(home: true)). 이닝별 득점 미집계")
                    .accessibilityIdentifier("careerGameScore")
            }
            Rectangle().fill(Color(hex: 0x426075)).frame(height: 1)
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
            .overlay(Rectangle().strokeBorder(Color(hex: 0x72929e), lineWidth: 2))
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x061a29)).frame(height: 3) }
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
                Text("·").foregroundStyle(muted).frame(maxWidth: .infinity, minHeight: 17)
                    .background(activeInning == inning ? Color(hex: 0x29445a) : .clear)
            }
            Text(String(home ? match.homeScore : match.awayScore)).foregroundStyle(GameTheme.gold).frame(width: 20)
            Text(MatchBroadcastData.hits(match, home: home).map(String.init) ?? "—").frame(width: 20)
            Text(MatchBroadcastData.errors(match, home: home).map(String.init) ?? "—").frame(width: 20)
        }
    }
    private func accessibleTeam(home: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(home ? homeName : awayName).font(.headline)
            Text("R \(home ? match.homeScore : match.awayScore)  H \(MatchBroadcastData.hits(match, home: home).map(String.init) ?? "미집계")  E \(MatchBroadcastData.errors(match, home: home).map(String.init) ?? "미집계")")
                .font(.body.monospaced())
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
