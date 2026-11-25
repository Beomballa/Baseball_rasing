import SwiftUI

/// 같은 표시 경계의 루 점유·선수 ID·프로필만 묶는다. 조회로 경기 상태를 바꾸지 않는다.
struct MatchRunnerDetails: Identifiable, Equatable {
    struct Runner: Identifiable, Equatable {
        let base: Int
        let name: String
        let slot: Int?
        let speed: Double?
        let origin: String?
        let pitcher: String?
        let identified: Bool
        var id: Int { base }
    }
    let id: String
    let half: Int
    let team: String
    let runners: [Runner]
    var inning: String { "\(half / 2 + 1)회 \(half.isMultiple(of: 2) ? "초" : "말")" }
    var bases: [Bool] { (1...3).map { base in runners.contains { $0.base == base } } }
    var occupancy: String { runners.map { String($0.base) }.joined(separator: "·") + "루" }

    static func current(_ match: CareerMatch, careerName: String, homeName: String, awayName: String) -> Self? {
        make(match, half: match.half, order: match.half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder,
             occupied: match.bases, ids: match.playerRecords?.runners, profiles: match.runnerProfiles,
             traces: match.playerRecords?.plateTrace, careerName: careerName, homeName: homeName, awayName: awayName)
    }

    /// 다시 보기에는 현재 타석의 주자를 붙이지 않는다. 해당 타구 원장과 주루 경로로 복원 가능한 값만 쓴다.
    static func resolved(_ play: MatchDetailedPlay, match: CareerMatch, careerName: String, homeName: String, awayName: String) -> Self? {
        guard match.fieldPlays?.contains(play) == true, let traces = match.playerRecords?.plateTrace,
              let index = traces.firstIndex(where: { $0.half == play.half && $0.order == play.order }) else { return nil }
        let event = traces[index]
        guard event.afterHalf == event.half, event.afterRunners.count == 3 else { return nil }
        let profiles: [FieldRunnerProfile?] = (0..<3).map { index in
            guard let id = event.afterRunners[index] else { return nil }
            return play.runners.first { runner in
                guard !runner.out, runner.destination == index + 1 else { return false }
                let mappedID = runner.from == 0 ? event.batter : (1...3).contains(runner.from) ? event.beforeRunners[runner.from - 1] : nil
                return mappedID == id && (runner.profile.id == nil || runner.profile.id == id)
            }?.profile
        }
        return make(match, half: event.half, order: event.order + 1,
                    occupied: event.afterRunners.map { $0 != nil }, ids: event.afterRunners, profiles: profiles,
                    traces: Array(traces.prefix(index + 1)), careerName: careerName, homeName: homeName, awayName: awayName,
                    applyBoundaryChange: false)
    }

    private static func make(_ match: CareerMatch, half: Int, order: Int, occupied: [Bool], ids: [String?]?,
                             profiles: [FieldRunnerProfile?]?, traces: [MatchPlateTrace]?, careerName: String,
                             homeName: String, awayName: String, applyBoundaryChange: Bool = true) -> Self? {
        guard occupied.count == 3, occupied.contains(true) else { return nil }
        let home = !half.isMultiple(of: 2)
        let team = home ? match.playerRecords?.home : match.playerRecords?.away
        let attack = match.npcAttack?.team(home: home)
        let changes = match.runnerManagement?.changes ?? team?.runnerChanges ?? []
        let origins = arrivalOrigins(traces ?? [], half: half, order: order, ids: ids, changes: changes,
                                     applyBoundaryChange: applyBoundaryChange)
        func name(_ id: String, fallback: String) -> String {
            if id == match.playerRecords?.careerID.uuidString { return careerName }
            if let batter = attack?.batters.first(where: { $0.id == id }) { return batter.displayName }
            if let pitcher = attack?.starter, pitcher.id == id { return pitcher.displayName }
            if let pitcher = attack?.relief, pitcher.id == id { return pitcher.displayName }
            let known = NPCIdentity.name(id)
            return known == "이름 미기록" ? fallback : known
        }
        func pitcher(_ profile: FieldRunnerProfile?) -> String? {
            let defendingHome = !home
            let index: Int
            switch profile?.responsiblePitcher {
            case MatchPitching.starterID(home: defendingHome): index = 0
            case MatchPitching.reliefID(home: defendingHome): index = 1
            default: return nil
            }
            let pitching = (defendingHome ? match.playerRecords?.home : match.playerRecords?.away)?.pitching
            guard let pitching, pitching.indices.contains(index) else { return nil }
            let id = pitching[index].id
            if id == match.playerRecords?.careerID.uuidString { return careerName }
            let saved = match.npcAttack?.team(home: defendingHome)
            let profile = index == 0 ? saved?.starter : saved?.relief
            if let profile, profile.id == id { return profile.displayName }
            let known = NPCIdentity.name(id)
            return known == "이름 미기록" ? nil : known
        }
        let rows: [Runner] = (0..<3).filter { occupied[$0] }.map { base in
            let id = ids?.count == 3 ? ids?[base] : nil
            let profile = profiles?.count == 3 ? profiles?[base] : nil
            guard let id, let row = team?.batting.first(where: { $0.id == id }),
                  profile?.id == nil || profile?.id == id,
                  profile?.own != true || (id == match.playerRecords?.careerID.uuidString && match.role == "batter" && home == match.isHome) else {
                return Runner(base: base + 1, name: "\(base + 1)루 주자", slot: nil, speed: nil, origin: nil, pitcher: nil, identified: false)
            }
            let reserve = changes.contains { $0.half == half && $0.order <= order && $0.replacement == id }
            let origin = origins[id].map { value in
                value.original == id ? value.result + " 출루" : name(value.original, fallback: "기존 주자") + "의 " + value.result + " 출루 후 대주자 투입"
            } ?? (reserve ? "대주자 투입 · 이전 출루 경위 미기록" : nil)
            return Runner(base: base + 1, name: name(id, fallback: reserve ? "대주자" : "선수명 미기록"),
                          slot: row.order, speed: profile?.speed, origin: origin, pitcher: pitcher(profile), identified: true)
        }
        return Self(id: "\(match.playerRecords?.fixtureID ?? "legacy")/\(half)/\(order)", half: half,
                    team: home ? homeName : awayName, runners: rows)
    }

    private struct Arrival { let original: String; let result: String }
    private static func arrivalOrigins(_ traces: [MatchPlateTrace], half: Int, order: Int, ids: [String?]?,
                                       changes: [MatchRunnerChange], applyBoundaryChange: Bool) -> [String: Arrival] {
        guard let last = traces.last, last.afterHalf == half, ids?.count == 3 else { return [:] }
        var arrivals: [String: Arrival] = [:]
        var previous: [String?]?
        var previousOrder: Int?
        func replace(_ before: inout [String?], at order: Int) {
            for change in changes where change.half == half && change.order == order && (1...3).contains(change.base) {
                guard before[change.base - 1] == change.original else { continue }
                before[change.base - 1] = change.replacement
                arrivals[change.replacement] = arrivals.removeValue(forKey: change.original)
            }
        }
        for event in traces where event.half == half && event.order < order {
            guard event.beforeRunners.count == 3, event.afterRunners.count == 3 else { arrivals = [:]; previous = nil; previousOrder = nil; continue }
            if var before = previous {
                replace(&before, at: event.order)
                if before != event.beforeRunners || previousOrder.map({ $0 + 1 != event.order }) == true { arrivals = [:] }
            }
            if event.afterRunners.contains(event.batter), !event.beforeRunners.contains(event.batter) {
                arrivals[event.batter] = Arrival(original: event.batter, result: event.result)
            }
            let remaining = Set(event.afterRunners.compactMap { $0 })
            arrivals = arrivals.filter { remaining.contains($0.key) }
            previous = event.afterRunners
            previousOrder = event.order
        }
        guard var boundary = previous, previousOrder.map({ $0 + 1 == order }) == true else { return [:] }
        if applyBoundaryChange { replace(&boundary, at: order) }
        return boundary == ids ? arrivals : [:]
    }
}

struct MatchRunnerDetailsView: View {
    let details: MatchRunnerDetails
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.inning).font(.headline).foregroundStyle(GameTheme.gold)
                    Text(details.team).font(.body.weight(.semibold))
                    Text("주자 \(details.occupancy) · \(details.runners.count)명").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("runnerDetailsContext")
                ForEach(details.runners) { runner in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(runner.base)루").font(.headline).foregroundStyle(GameTheme.gold)
                            Text(runner.name).font(.body.weight(.semibold))
                        }.fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true)
                        if runner.identified {
                            if let slot = runner.slot { information("타순", value: "\(slot)번") }
                            if let speed = runner.speed { information("주력", value: speed.formatted(.number.precision(.fractionLength(0...1)))) }
                            if let origin = runner.origin { information("출루·교체", value: origin) }
                            if let pitcher = runner.pitcher { information("책임투수", value: pitcher) }
                        } else {
                            Text("저장된 선수 상세가 없습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("runnerDetailsBase-\(runner.base)")
                }
            }.padding(16).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
        }.background(GameTheme.boardPanel).foregroundStyle(GameTheme.boardInk)
            .accessibilityIdentifier("runnerDetailsSheet")
    }
    private func information(_ label: String, value: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(label).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                .frame(width: typeSize.isAccessibilitySize ? nil : 76, alignment: .leading)
            Text(value).font(.body).frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
