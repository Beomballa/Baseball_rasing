import SwiftUI

/// 확정된 경기 스냅샷만 읽는다. 교체·판정·저장 명령을 다시 실행하지 않는다.
struct MatchSubstitutionJournal: Identifiable, Equatable {
    struct Entry: Identifiable, Equatable {
        let id: String
        let half: Int
        let order: Int
        let home: Bool
        let kind: String
        let outgoing: String
        let incoming: String
        let reason: String
        let detail: String?
        let priority: Int
    }

    struct Group: Identifiable, Equatable {
        let half: Int
        let home: Bool
        let team: String
        let entries: [Entry]
        var id: String { "\(half)-\(home ? "home" : "away")" }
        var inning: String { "\(half / 2 + 1)회 \(half.isMultiple(of: 2) ? "초" : "말")" }
    }

    let id: String
    let groups: [Group]
    var count: Int { groups.reduce(0) { $0 + $1.entries.count } }

    init(match: CareerMatch, careerName: String, homeName: String, awayName: String) {
        var entries: [Entry] = []
        func name(_ id: String?, fallback: String) -> String {
            guard let id else { return fallback }
            if id == match.playerRecords?.careerID.uuidString { return careerName }
            let known = NPCIdentity.name(id)
            return known == "이름 미기록" ? fallback : known
        }
        for change in match.runnerManagement?.changes ?? [] {
            let home = !change.half.isMultiple(of: 2)
            let original = match.npcFielders?.team(home: home).players.first { $0.id == change.original }
            let reserve = match.runnerManagement?.reserve(home: home)
            let detail: String?
            if let original, let reserve, reserve.id == change.replacement {
                let format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
                let difference = reserve.speed - original.speed
                detail = "주력 \(format(original.speed)) → \(format(reserve.speed)) (\(difference >= 0 ? "+" : "")\(format(difference)))"
            } else { detail = nil }
            entries.append(Entry(id: "runner-\(home)-\(change.half)-\(change.order)-\(change.original)",
                half: change.half, order: change.order, home: home, kind: "대주자",
                outgoing: "\(name(change.original, fallback: "기존 주자")) · \(change.slot)번",
                incoming: name(change.replacement, fallback: "대주자"),
                reason: "\(change.base)루 주자를 교체했습니다.", detail: detail, priority: 0))
        }
        for home in [true, false] {
            guard let change = match.pitching?.change(home: home) else { continue }
            let records = home ? match.playerRecords?.home : match.playerRecords?.away
            let attack = match.npcAttack?.team(home: home)
            // 기록에 있는 선수 ID와 일치하는 저장 이름만 사용한다.
            func pitcherName(index: Int, fallback: String) -> String {
                let pitcherID = records?.pitching.indices.contains(index) == true ? records?.pitching[index].id : nil
                if let pitcherID, pitcherID == match.playerRecords?.careerID.uuidString { return careerName }
                let profile = index == 0 ? attack?.starter : attack?.relief
                if let profile, profile.id == pitcherID { return profile.displayName }
                return name(pitcherID, fallback: fallback)
            }
            let left = change.inheritedBases.isEmpty ? "남긴 주자 없음"
                : "남긴 주자 \(change.inheritedBases.map(String.init).joined(separator: "·"))루 · 이후 득점은 선발투수의 실점에 반영됩니다."
            let reason = change.reason == "투구 수 한도" ? "선발투수가 투구 수 한도에 도달했습니다."
                : change.reason == "피로 한도" ? "선발투수가 피로 한도에 도달했습니다." : change.reason
            let outgoing = pitcherName(index: 0, fallback: "선발투수")
            let incoming = pitcherName(index: 1, fallback: "구원투수")
            entries.append(Entry(id: "pitcher-\(home)-\(change.half)-\(change.order)", half: change.half,
                order: change.order, home: home, kind: "투수 교체",
                outgoing: outgoing == "선발투수" ? outgoing : outgoing + " · 선발",
                incoming: incoming == "구원투수" ? incoming : incoming + " · 구원",
                reason: reason, detail: "\(change.pitches)구 · \(left)", priority: 1))
        }
        let sorted = entries.sorted {
            if $0.half != $1.half { return $0.half < $1.half }
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id < $1.id
        }
        var result: [Group] = []
        for entry in sorted {
            if let index = result.firstIndex(where: { $0.half == entry.half && $0.home == entry.home }) {
                let previous = result[index]
                result[index] = Group(half: entry.half, home: entry.home, team: previous.team, entries: previous.entries + [entry])
            } else {
                result.append(Group(half: entry.half, home: entry.home, team: entry.home ? homeName : awayName, entries: [entry]))
            }
        }
        id = match.playerRecords?.fixtureID ?? "saved-match"
        groups = result
    }
}

struct MatchSubstitutionJournalView: View {
    let journal: MatchSubstitutionJournal
    @State private var expanded: Set<Int>
    @Environment(\.dynamicTypeSize) private var typeSize

    init(journal: MatchSubstitutionJournal) {
        self.journal = journal
        let latestHalf = journal.groups.last?.half
        _expanded = State(initialValue: Set([latestHalf].compactMap { $0 }))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("총 \(journal.count)건").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    .accessibilityIdentifier("gameSubstitutionCount")
                if journal.groups.isEmpty {
                    Text("기록된 교체가 없습니다.").font(.body)
                }
                ForEach(Array(Set(journal.groups.map(\.half))).sorted(), id: \.self) { half in
                    let groups = journal.groups.filter { $0.half == half }
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(half) }, set: {
                        if $0 { expanded.insert(half) } else { expanded.remove(half) }
                    })) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(group.team).font(.body.weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    ForEach(group.entries) { entry in entryView(entry) }
                                }
                            }
                        }.padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(groups.first?.inning ?? "").font(.headline).foregroundStyle(GameTheme.gold)
                            Text("\(groups.reduce(0) { $0 + $1.entries.count })건").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        }.frame(minHeight: 44, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(GameTheme.gold)
                    .accessibilityIdentifier("gameSubstitutionGroup-\(half)")
                }
            }
            .padding(16).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(GameTheme.boardPanel).foregroundStyle(GameTheme.boardInk)
        .accessibilityIdentifier("gameSubstitutionJournal")
    }

    private func entryView(_ entry: MatchSubstitutionJournal.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true)
            Text(entry.kind).font(.headline).padding(.top, 4)
            participant("나간 선수", name: entry.outgoing)
            participant("들어온 선수", name: entry.incoming)
            Text(entry.reason).font(.subheadline).padding(.top, 4)
            if let detail = entry.detail {
                Text(detail).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gameSubstitutionEntry-" + entry.id)
    }

    private func participant(_ label: String, name: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(label).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                .frame(width: typeSize.isAccessibilitySize ? nil : 80, alignment: .leading)
            Text(name).font(.body.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
