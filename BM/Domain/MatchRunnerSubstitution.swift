import Foundation

struct MatchBattingOrder: Codable, Equatable {
    let home: [Int]
    let away: [Int]
    func validate() throws {
        guard [home, away].allSatisfy({ $0.count == 9 && Set($0) == Set(0..<9) }) else { throw MatchError.invalidRecord }
    }
}

/// 경기 시작에 고정하는 임시 예비 선수. 영구 NPC 로스터나 성장 기록을 새로 만들지 않는다.
struct MatchReserveRunner: Codable, Equatable {
    let id: String
    let speed: Double
    let defense: Double
    let arm: Double
    let contact: Double
    let power: Double
    let discipline: Double
    static func make(team: MatchNPCTeam, attack: MatchNPCAttackTeam) -> Self {
        let id = "npc-v1/\(attack.competition)/\(attack.year)/\(team.teamID)/reserve-runner-v1"
        // 기존 NPC의 팀 전력·고정 편차·20~95 범위를 그대로 사용한다.
        func rating(_ key: String, offset: Double) -> Double {
            min(95, max(20, team.strength + offset + Double(Int(MatchNPCFielders.hash(id + "/" + key) % 15) - 7)))
        }
        func average(_ key: KeyPath<MatchNPCBatter, Double>) -> Double { attack.batters.reduce(0) { $0 + $1[keyPath: key] } / 9 }
        return Self(id: id, speed: rating("speed", offset: 10), defense: rating("defense", offset: 0),
                    arm: rating("arm", offset: 0), contact: average(\.contact), power: average(\.power), discipline: average(\.discipline))
    }
}

struct MatchRunnerChange: Codable, Equatable {
    let half: Int
    let order: Int
    let base: Int
    let slot: Int
    let original: String
    let replacement: String
    let position: String
    let responsiblePitcher: String?
}

struct MatchRunnerManagement: Codable, Equatable {
    var version = 1
    let home: MatchReserveRunner
    let away: MatchReserveRunner
    var changes: [MatchRunnerChange] = []
    func reserve(home isHome: Bool) -> MatchReserveRunner { isHome ? home : away }
    func change(home isHome: Bool) -> MatchRunnerChange? { changes.first { ($0.half % 2 == 1) == isHome } }
}

extension CareerMatch {
    /// 새 경기만 현재 타순과 예비 선수 능력을 시작 스냅샷에 고정한다.
    mutating func prepareRunnerManagement() {
        guard homeOrder == 0, awayOrder == 0, battingOrder == nil, runnerManagement == nil,
              let fielders = npcFielders, let attack = npcAttack else { return }
        battingOrder = MatchBattingOrder(home: npcLineup(home: true), away: npcLineup(home: false))
        runnerManagement = MatchRunnerManagement(home: .make(team: fielders.home, attack: attack.home),
                                                 away: .make(team: fielders.away, attack: attack.away))
    }

    mutating func applyCoachRunnerChange() {
        guard !completed, half >= 12, abs(homeScore - awayScore) <= 2, balls == 0, strikes == 0,
              let management = runnerManagement, management.change(home: half % 2 == 1) == nil,
              let records = playerRecords, let last = records.plateTrace?.last,
              last.half == half, last.result == "볼넷", last.order + 1 == (half % 2 == 1 ? homeOrder : awayOrder),
              records.runners[0] == last.batter else { return }
        let battingHome = half % 2 == 1, reserve = management.reserve(home: battingHome)
        // 접전 후반의 볼넷 출루자만 교체한다. 기존 득점권 주자·내 선수·투수 타순은 유지한다.
        guard let profile = runnerProfiles?[0], !profile.own, reserve.speed > profile.speed,
              last.batter != records.careerID.uuidString,
              let row = records.homeTeam(batting: half).batting.first(where: { $0.id == last.batter }), row.position != "P" else { return }
        replaceRunner(base: 1, reserve: reserve)
    }

    /// 책임투수·실책 출루 토큰을 보존한 채 실제 주자와 이후 타순의 선수 ID를 교체한다.
    mutating func replaceRunner(base: Int, reserve: MatchReserveRunner) {
        guard (1...3).contains(base), let management = runnerManagement,
              reserve == management.reserve(home: half % 2 == 1), management.change(home: half % 2 == 1) == nil,
              var records = playerRecords, var profiles = runnerProfiles,
              let original = records.runners[base - 1], let old = profiles[base - 1], !old.own,
              original != records.careerID.uuidString else { return }
        let battingHome = half % 2 == 1
        var team = battingHome ? records.home : records.away
        guard let row = team.batting.first(where: { $0.id == original }), row.position != "P" else { return }
        let change = MatchRunnerChange(half: half, order: battingHome ? homeOrder : awayOrder, base: base,
            slot: row.order, original: original, replacement: reserve.id, position: row.position,
            responsiblePitcher: old.responsiblePitcher)
        let profile = FieldRunnerProfile(speed: reserve.speed, traits: [], own: false,
                                     responsiblePitcher: old.responsiblePitcher, id: reserve.id)
        profiles[base - 1] = profile; records.runners[base - 1] = reserve.id
        team.runnerChanges = (team.runnerChanges ?? []) + [change]
        team.batting.append(MatchBattingRecord(id: reserve.id, order: row.order, position: row.position))
        if team.fielding != nil { team.fielding?.append(MatchFieldingRecord(id: reserve.id, position: row.position)) }
        if var earned = records.earned, let token = earned.runners[base - 1]?.token {
            earned.runners[base - 1]?.profile = profile
            for view in earned.views.indices {
                for bag in earned.views[view].runners.indices where earned.views[view].runners[bag]?.token == token {
                    earned.views[view].runners[bag]?.profile = profile
                }
            }
            records.earned = earned
        }
        if battingHome { records.home = team } else { records.away = team }
        playerRecords = records; runnerProfiles = profiles; runnerManagement?.changes.append(change)
    }

    func validateRunnerManagement() throws {
        try battingOrder?.validate()
        if let order = battingOrder, role == "batter", appearance, let position = fieldStats?.position {
            guard (isHome ? order.home : order.away).first == DetailedFieldRules.names.firstIndex(of: position) else { throw MatchError.invalidRecord }
        }
        guard let management = runnerManagement else {
            guard playerRecords.map({ ($0.home.runnerChanges ?? []).isEmpty && ($0.away.runnerChanges ?? []).isEmpty }) ?? true else { throw MatchError.invalidRecord }
            return
        }
        guard management.version == 1, battingOrder != nil, playerRecords != nil, let fielders = npcFielders, let attack = npcAttack,
              management.home == .make(team: fielders.home, attack: attack.home),
              management.away == .make(team: fielders.away, attack: attack.away), management.changes.count <= 2,
              Set(management.changes.map { $0.half % 2 }).count == management.changes.count else { throw MatchError.invalidRecord }
        guard (playerRecords?.home.runnerChanges ?? []) == management.changes.filter({ $0.half % 2 == 1 }),
              (playerRecords?.away.runnerChanges ?? []) == management.changes.filter({ $0.half % 2 == 0 }) else { throw MatchError.invalidRecord }
        for change in management.changes {
            let battingHome = change.half % 2 == 1
            guard (12..<18).contains(change.half), change.half <= half, change.order >= 0,
                  (1...3).contains(change.base), (1...9).contains(change.slot), change.position != "P",
                  change.original != playerRecords?.careerID.uuidString,
                  playerRecords?.homeTeam(batting: change.half).lineup[change.slot - 1] == change.original,
                  change.replacement == management.reserve(home: battingHome).id,
                  change.responsiblePitcher.map({ MatchPitching.ids.contains($0) }) ?? true,
                  (battingHome ? playerRecords?.home.runnerChanges : playerRecords?.away.runnerChanges)?.contains(change) == true else { throw MatchError.invalidRecord }
        }
    }
}
