import SwiftUI

/// 표시 시점의 타석 원장만 읽는다. 조회나 다시 보기는 경기 진행·저장을 실행하지 않는다.
struct MatchGameHistory: Identifiable, Equatable {
    struct Change: Identifiable, Equatable {
        let id: String
        let half: Int
        let order: Int
        let team: String
        let kind: String
        let outgoing: String
        let incoming: String
    }
    struct Entry: Identifiable, Equatable {
        let id: String
        let half: Int
        let order: Int
        let ordinal: Int?
        let batter: String
        let pitcher: String
        let result: String
        let before: String
        let after: String
        let scoreBefore: String
        let scoreAfter: String
        let runs: Int
        let scorers: String?
        let changes: [Change]
        var correction: MatchHistoryCorrection? = nil
        var teamID: String? = nil
        var title: String { "\(order % 9 + 1)번 \(batter)" }
    }
    struct Side: Equatable {
        let home: Bool
        let name: String
        let entries: [Entry]
        let unpairedChanges: [Change]
        let emptyMessage: String
        var rowCount: Int { entries.compactMap(\.ordinal).max() ?? 0 }
        func entry(at ordinal: Int) -> Entry? { entries.first { $0.ordinal == ordinal } }
        var unordered: [Entry] { entries.filter { $0.ordinal == nil } }
        func absence(at ordinal: Int) -> String {
            if entries.contains(where: { ($0.ordinal ?? 0) > ordinal }) { return "기록 미확인" }
            return emptyMessage
        }
    }
    struct Inning: Identifiable, Equatable {
        let number: Int
        let home: Side
        let away: Side
        var id: Int { number }
        var rowCount: Int { max(home.rowCount, away.rowCount) }
    }

    let id: String
    let context: String
    let innings: [Inning]
    let recorded: Bool
    let partial: Bool
    let mismatch: Bool
    let pitchEvents: [MatchPitchEvent]
    let runningEvents: [MatchRunningEvent]
    let pitchNames: MatchPitchEventNames
    var plateCount: Int { innings.reduce(0) { $0 + $1.home.entries.count + $1.away.entries.count } }
    var changeCount: Int {
        innings.reduce(0) { count, inning in
            count + [inning.home, inning.away].reduce(0) {
                $0 + $1.unpairedChanges.count + $1.entries.reduce(0) { $0 + $1.changes.count }
            }
        }
    }

    init(match: CareerMatch, fixtureID: String?, careerName: String, homeName: String, awayName: String) {
        id = fixtureID ?? match.playerRecords?.fixtureID ?? "saved-match"
        context = match.completed ? "종료 경기 · 당시 기록" : "\(match.inningLabel) · \(match.outs)아웃"
        let records = match.playerRecords
        let invalidTeams = records.map { records in
            records.home.teamID == records.away.teamID || [true, false].contains { home in
                let team = home ? records.home : records.away
                return match.npcAttack.map { $0.team(home: home).teamID != team.teamID } == true
                    || match.npcFielders.map { $0.team(home: home).teamID != team.teamID } == true
            }
        } ?? false
        let invalidFixture = (fixtureID != nil && records != nil && fixtureID != records?.fixtureID) || invalidTeams
        mismatch = invalidFixture
        pitchNames = MatchPitchEventNames(match: match, careerName: careerName)
        runningEvents = invalidFixture ? [] : match.running?.events ?? []
        pitchEvents = invalidFixture ? [] : (match.pitchEvents?.events ?? []).filter {
            $0.before.half <= match.half && $0.after.half <= match.half
                && $0.after.homeOrder <= match.homeOrder && $0.after.awayOrder <= match.awayOrder
                && $0.after.home <= match.homeScore && $0.after.away <= match.awayScore
        }
        let hasTrace = !invalidFixture && records?.plateTrace != nil
        recorded = hasTrace
        let source = invalidFixture ? [] : records?.plateTrace ?? []
        let multiplicity = Dictionary(grouping: source, by: \.id).mapValues(\.count)
        let events = source.filter { event in
            let runs = event.battingHome ? event.home - event.beforeHome : event.away - event.beforeAway
            return multiplicity[event.id] == 1 && (0..<18).contains(event.half) && event.half <= match.half
                && event.order >= 0 && event.order < (event.battingHome ? match.homeOrder : match.awayOrder)
                && (0...2).contains(event.outsBefore) && (0...2).contains(event.afterOuts)
                && (event.half...min(18, event.half + 1)).contains(event.afterHalf) && event.afterHalf <= match.half
                && event.beforeRunners.count == 3 && event.afterRunners.count == 3
                && (0...4).contains(runs) && event.home >= 0 && event.away >= 0
                && event.beforeHome >= 0 && event.beforeAway >= 0
                && event.home <= match.homeScore && event.away <= match.awayScore
                && (event.battingHome ? event.away == event.beforeAway : event.home == event.beforeHome)
                && (event.battingHome ? event.homeOrder : event.awayOrder) == event.order + 1
                && event.homeOrder <= match.homeOrder && event.awayOrder <= match.awayOrder
        }.sorted { $0.half == $1.half ? $0.order < $1.order : $0.half < $1.half }
        let hasPartialTrace = hasTrace && (events.count != source.count || events.count != match.homeOrder + match.awayOrder)
        partial = hasPartialTrace

        func team(_ home: Bool) -> MatchTeamRecords? { home ? records?.home : records?.away }
        func name(_ id: String, home: Bool, pitcher: Bool = false) -> String? {
            let row = team(home)
            guard pitcher ? row?.pitching.contains(where: { $0.id == id }) == true
                : row?.batting.contains(where: { $0.id == id }) == true else { return nil }
            if id == records?.careerID.uuidString, home == match.isHome { return careerName }
            let attack = match.npcAttack?.team(home: home)
            if attack?.teamID == row?.teamID {
                if let profile = attack?.batters.first(where: { $0.id == id }) { return profile.displayName }
                if let profile = attack?.starter, profile.id == id { return profile.displayName }
                if let profile = attack?.relief, profile.id == id { return profile.displayName }
            }
            let value = NPCIdentity.name(id)
            return value == "이름 미기록" ? nil : value
        }
        func baseState(outs: Int, runners: [String?]) -> String {
            let bases = runners.indices.filter { runners[$0] != nil }.map { String($0 + 1) }
            return "\(outs)사 · " + (bases.isEmpty ? "주자 없음" : bases.joined(separator: "·") + "루")
        }
        func score(_ home: Int, _ away: Int) -> String { "홈 \(home) : \(away) 원정" }

        let journal = MatchSubstitutionJournal(match: match, careerName: careerName, homeName: homeName, awayName: awayName)
        let changes: [Change] = invalidFixture ? [] : journal.groups.flatMap { group in
            group.entries.filter { entry in
                (0..<18).contains(entry.half) && entry.half <= match.half && entry.order >= 0
                    && entry.order <= (entry.half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder)
            }.map { entry in
                Change(id: entry.id, half: entry.half, order: entry.order, team: group.team,
                       kind: entry.kind, outgoing: entry.outgoing, incoming: entry.incoming)
            }
        }
        func startOrder(half: Int) -> Int? {
            if half < 2 { return 0 }
            // 반이닝 시작의 누적 타석 수가 확인될 때만 순번을 붙인다. 누락된 타석을 당기지 않는다.
            guard let boundary = events.last(where: {
                ($0.half == half - 1 || $0.half == half - 2) && $0.afterHalf == $0.half + 1
            }) else { return nil }
            return half.isMultiple(of: 2) ? boundary.awayOrder : boundary.homeOrder
        }
        let entries = events.map { event in
            let runs = event.battingHome ? event.home - event.beforeHome : event.away - event.beforeAway
            let scorerNames = event.scoring.count == runs && Set(event.scoring.map(\.id)).count == runs
                ? event.scoring.compactMap { name($0.id, home: event.battingHome) } : []
            let scorers = runs > 0 ? (scorerNames.isEmpty ? "득점 주자 이름 미기록"
                : scorerNames.joined(separator: "·") + (scorerNames.count < runs ? " 외 득점 주자 이름 미기록" : " 홈인")) : nil
            let correction = match.officialReview?.changes.first { $0.id == event.id }
            let displayed = correction.map { $0.visible(in:match) ? event.result : $0.proof.recordedResult } ?? event.result
            let visible = correction.flatMap { change in change.visible(in:match) ? MatchHistoryCorrection(change:change,
                teamID:team(event.battingHome)?.teamID,team:event.battingHome ? homeName:awayName,home:event.battingHome,
                batter:name(event.batter,home:event.battingHome) ?? "타자 이름 미기록",
                ordinal:startOrder(half:event.half).map { event.order-$0+1 }) : nil }
            return Entry(id: event.id, half: event.half, order: event.order,
                ordinal: startOrder(half: event.half).flatMap { event.order >= $0 ? event.order - $0 + 1 : nil },
                batter: name(event.batter, home: event.battingHome) ?? "타자 이름 미기록",
                pitcher: name(event.pitcher, home: !event.battingHome, pitcher: true) ?? "투수 이름 미기록",
                result: displayed, before: baseState(outs: event.outsBefore, runners: event.beforeRunners),
                after: event.afterHalf == event.half ? baseState(outs: event.afterOuts, runners: event.afterRunners) : "공수교대",
                scoreBefore: score(event.beforeHome, event.beforeAway), scoreAfter: score(event.home, event.away),
                runs: runs, scorers: scorers,
                changes: changes.filter { $0.half == event.half && $0.order == event.order + 1 && event.afterHalf == event.half },
                correction:visible,teamID:team(event.battingHome)?.teamID)
        }
        let paired = Set(entries.flatMap(\.changes).map(\.id))
        var numbers = Set(entries.map { $0.half / 2 + 1 } + changes.map { $0.half / 2 + 1 } + pitchEvents.map { $0.before.half / 2 + 1 } + runningEvents.map { $0.before.half / 2 + 1 })
        if numbers.isEmpty, !match.completed, (0..<18).contains(match.half) { numbers.insert(match.half / 2 + 1) }
        innings = numbers.sorted().map { number in
            func side(_ home: Bool) -> Side {
                let half = (number - 1) * 2 + (home ? 1 : 0)
                let skipped = home && half == 17 && match.completed && match.half == 17
                    && match.homeScore > match.awayScore && match.inningScores?.home.count == 9
                    && match.inningScores?.home[8] == nil
                let closed = events.contains { $0.half == half && $0.afterHalf == half + 1 }
                let message = skipped ? "말 공격 생략"
                    : closed ? (home ? "말 공격 종료" : "초 공격 종료")
                    : !match.completed && half > match.half ? (home ? "말 공격 대기" : "초 공격 대기")
                    : !hasTrace || hasPartialTrace || match.completed ? "기록 미확인" : "아직 끝난 타석이 없습니다."
                return Side(home: home, name: home ? homeName : awayName,
                            entries: entries.filter { $0.half == half },
                            unpairedChanges: changes.filter { $0.half == half && !paired.contains($0.id) }, emptyMessage: message)
            }
            return Inning(number: number, home: side(true), away: side(false))
        }
    }
}

struct MatchHistorySelection {
    var inning: Int?
    var expanded: Set<String> = []
}

enum MatchRecordTab: String, CaseIterable { case lineup, history
    var title: String { self == .lineup ? "타순표" : "경기 이력" }
    var icon: String { self == .lineup ? "NavPlayerV1" : "NavCareerV1" }
}

struct MatchRecordTabs: View {
    @Binding var selection: MatchRecordTab
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            ForEach(MatchRecordTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    HStack(spacing: 8) {
                        Image(tab.icon).resizable().interpolation(.none).scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                        Text(tab.title)
                    }
                }.buttonStyle(MatchPixelButtonStyle(selected: selection == tab, fillsWidth: false))
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier(tab == .history ? "openGameHistory" : "gameRecordsLineup")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MatchGameHistoryView: View {
    let history: MatchGameHistory
    private var externalSelection: Binding<MatchHistorySelection>?
    var embedded: Bool
    @State private var localSelection = MatchHistorySelection()
    @State private var comparison: MatchPitchEvent?
    private var role: PlayerRole
    private var appearance: PlayerAppearance?
    private var selection: Binding<MatchHistorySelection> { externalSelection ?? $localSelection }
    private var selectedInning: Int { selection.wrappedValue.inning ?? history.innings.last?.number ?? 1 }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 116

    init(history: MatchGameHistory, selection: Binding<MatchHistorySelection>? = nil, embedded: Bool = false, role: PlayerRole = .batter, appearance: PlayerAppearance? = nil) {
        self.history = history; self.role = role; self.appearance = appearance
        self.externalSelection = selection
        self.embedded = embedded
    }

    var body: some View {
        if embedded { content }
        else {
            content.navigationTitle("경기 이력").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("closeGameHistory")
                    }
                }
        }
    }
    private var content: some View {
        GeometryReader { geometry in
          ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(history.context).id("history-top").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        .accessibilityIdentifier("gameHistoryContext")
                    Text(history.recorded ? "타석 \(history.plateCount)개 · 교체 \(history.changeCount)건"
                         : "타석별 기록 미수집 · 교체 \(history.changeCount)건")
                        .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        .accessibilityIdentifier("gameHistoryCount")
                    if history.mismatch {
                        Text("이 경기와 타석 기록의 연결을 확인할 수 없습니다.")
                    } else if !history.recorded && history.changeCount == 0 && history.pitchEvents.isEmpty && history.runningEvents.isEmpty {
                        Text("이 경기에는 저장된 타석·교체 기록이 없습니다.")
                    } else {
                        if history.partial {
                            Text("일부 타석 기록이 없습니다. 확인되는 기록만 표시합니다.").font(.subheadline)
                        }
                        HStack(spacing: 8) {
                            Text("조회 이닝").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                            Picker("조회 이닝", selection: Binding(get: { selectedInning }, set: { selection.wrappedValue.inning = $0 })) {
                                ForEach(history.innings) { Text("\($0.number)회").tag($0.number) }
                            }.pickerStyle(.menu).labelsHidden().tint(GameTheme.gold).frame(minHeight: 44)
                                .accessibilityIdentifier("gameHistoryInning")
                        }
                        if let inning = history.innings.first(where: { $0.number == selectedInning }) {
                            inningView(inning, width: geometry.size.width)
                            let running = history.runningEvents.filter { $0.before.half / 2 + 1 == selectedInning }
                            if !running.isEmpty {
                                DisclosureGroup("도루·견제·협살 · \(running.count)건") {
                                    ForEach(running) { event in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(event.before.half / 2 + 1)회 \(event.before.half.isMultiple(of: 2) ? "초" : "말") · " + event.label).font(.headline)
                                            Text(event.play.runners.first?.profile.id.map(history.pitchNames.name) ?? "주자 미기록").font(.body)
                                            Text("\(event.before.outs)아웃 → \((event.play.outsBefore ?? event.movementBefore.outs) + event.play.outsAdded)아웃 · 득점 \(event.play.runs)").font(.subheadline)
                                            Text("공식 기록 · " + event.recordSummary).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                                        }.padding(.vertical, 8).accessibilityElement(children: .combine)
                                    }
                                }.font(.body).accessibilityIdentifier("historyRunningEvents")
                            }
                            let pitches = history.pitchEvents.filter { $0.before.half / 2 + 1 == selectedInning }
                            if !pitches.isEmpty {
                                DisclosureGroup("투구 중 사건 · \(pitches.count)회") {
                                    VStack(alignment: .leading, spacing: 16) {
                                        ForEach(pitches) { event in
                                            Text("\(event.before.half / 2 + 1)회 \(event.before.half.isMultiple(of: 2) ? "초" : "말") · \(event.before.order % 9 + 1)번 타자")
                                                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                                            MatchPitchEventNotice(event: event, resolved: true, name: history.pitchNames.name,
                                                openComparison: appearance == nil ? nil : { comparison = event })
                                        }
                                    }.padding(.top, 8)
                                }.font(.body).accessibilityIdentifier("historyPitchEvents")
                            }
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameTheme.boardPanel).padding(16)
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .accessibilityIdentifier("gameHistory")
                .onChange(of: selectedInning) { _, _ in proxy.scrollTo("history-top", anchor: .top) }
          }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $comparison) { event in
            if let appearance, event.observation != nil { PitchCatchComparison(event: event, role: role, appearance: appearance) }
        }
    }

    private func inningView(_ inning: MatchGameHistory.Inning, width: CGFloat) -> some View {
        let pairWidth = max(0, width - 84)
        let stack = typeSize.isAccessibilitySize || pairWidth < columnWidth * 2 + 8
        let cellWidth = max(0, (pairWidth - 8) / 2)
        return VStack(alignment: .leading, spacing: 16) {
            Text("행 번호는 이닝 내 타석 순서 · 원정이 초에 먼저 공격합니다.")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            if inning.rowCount == 0 {
                Text(history.recorded ? "순번이 확인되는 타석이 없습니다." : "타석 순번과 점수 미기록").font(.body)
            }
            ForEach(0..<inning.rowCount, id: \.self) { index in
                let ordinal = index + 1
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(ordinal)").font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                            .frame(minWidth: 20).accessibilityLabel("각 팀의 \(ordinal)번째 타석")
                        if stack {
                            stacked(inning, ordinal: ordinal)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 8) {
                                    cell(inning.home, number: inning.number, ordinal: ordinal).frame(width: cellWidth)
                                    cell(inning.away, number: inning.number, ordinal: ordinal).frame(width: cellWidth)
                                }
                                stacked(inning, ordinal: ordinal)
                            }
                        }
                    }
                    ForEach((inning.home.entries+inning.away.entries).filter { $0.ordinal == ordinal }.compactMap(\.correction)) { correction in
                        MatchRecordCorrectionCard(value:correction)
                    }
                    Rectangle().fill(GameTheme.boardLine.opacity(0.6)).frame(height: 1).accessibilityHidden(true)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("gameHistoryRow-\(ordinal)")
            }
            forUnpaired(inning.home, number: inning.number)
            forUnpaired(inning.away, number: inning.number)
        }
    }
    private func teamHeading(_ side: MatchGameHistory.Side, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((side.home ? "홈 · " : "원정 · ") + side.name).font(.subheadline.weight(.semibold))
            Text("\(number)회\(side.home ? "말" : "초") 공격").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
    private func stacked(_ inning: MatchGameHistory.Inning, ordinal: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            teamHeading(inning.home, number: inning.number)
            cell(inning.home, number: inning.number, ordinal: ordinal)
            teamHeading(inning.away, number: inning.number)
            cell(inning.away, number: inning.number, ordinal: ordinal)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func cell(_ side: MatchGameHistory.Side, number: Int, ordinal: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let entry = side.entry(at: ordinal) {
                entryView(entry, team: side.name, home: side.home)
            } else {
                teamHeading(side, number:number)
                let reason = side.absence(at: ordinal)
                let previous = ordinal > 1 && side.entry(at: ordinal - 1) == nil ? side.absence(at: ordinal - 1) : nil
                Text(previous == reason ? "—" : reason).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    .accessibilityLabel("\(number)회\(side.home ? "말" : "초"), \(side.name), \(ordinal)번째 타석, \(reason)")
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
    private func entryView(_ entry: MatchGameHistory.Entry, team: String, home: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing:8) {
                MatchTeamCrest(teamID:entry.teamID,name:team,schools:(try? SchoolCatalog.load()) ?? []).frame(width:28,height:28).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text(team).font(.subheadline.weight(.semibold))
                    Text("\(entry.half/2+1)회 "+(home ? "말 · 홈":"초 · 원정")).font(.footnote).foregroundStyle(GameTheme.boardMuted)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            Rectangle().fill(GameTheme.boardLine).frame(height:1).accessibilityHidden(true)
            DisclosureGroup(isExpanded: Binding(get: { selection.wrappedValue.expanded.contains(entry.id) }, set: {
                if $0 { selection.wrappedValue.expanded.insert(entry.id) } else { selection.wrappedValue.expanded.remove(entry.id) }
            })) {
                VStack(alignment: .leading, spacing: 8) {
                    fact("타석 전", value: entry.before)
                    fact("판정 후", value: entry.after)
                    fact("당시 점수", value: entry.scoreBefore + " → " + entry.scoreAfter)
                    fact("상대 투수", value: entry.pitcher)
                }.padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.batter).font(.body.weight(.semibold))
                    Text("\(entry.order % 9 + 1)번 · \(entry.result)").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    if entry.runs > 0 {
                        Text("\(entry.runs)득점 · " + (entry.scorers ?? "득점 주자 이름 미기록"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(GameTheme.gold)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.half / 2 + 1)회\(home ? "말" : "초"), \(team), "
                        + (entry.ordinal.map { "\($0)번째 타석, " } ?? "순번 미기록, ") + entry.title + ", " + entry.result
                        + (entry.runs > 0 ? ", \(entry.runs)득점" : ""))
            }.tint(GameTheme.gold).accessibilityIdentifier("gameHistoryDisclosure-" + entry.id)
            if !entry.changes.isEmpty {
                Text("타석 후 교체").font(.subheadline.weight(.semibold))
                ForEach(entry.changes) { change in changeView(change) }
            }
        }.padding(10).background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:1))
            .accessibilityElement(children: .contain).accessibilityIdentifier("gameHistoryEntry-" + entry.id)
    }
    private func fact(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            Text(value).font(.subheadline)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func changeView(_ change: MatchGameHistory.Change) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.team + " · " + change.kind).font(.subheadline.weight(.semibold))
            Text(change.outgoing + " → " + change.incoming).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("gameHistoryChange-" + change.id)
    }
    @ViewBuilder private func forUnpaired(_ side: MatchGameHistory.Side, number: Int) -> some View {
        if !side.unordered.isEmpty {
            teamHeading(side, number: number)
            Text("순번 미기록").font(.headline).foregroundStyle(GameTheme.gold)
            ForEach(side.unordered) { entryView($0, team: side.name, home: side.home) }
        }
        if !side.unpairedChanges.isEmpty {
            Text("\(number)회\(side.home ? "말" : "초") · 타석 연결 미기록 교체").font(.headline)
            ForEach(side.unpairedChanges) { changeView($0) }
        }
    }
}
