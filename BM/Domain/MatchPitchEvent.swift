import Foundation

/// 공 하나의 확정 전후 상태. 영상 시계·다시 보기·화면 크기는 판정 입력이 아니다.
struct MatchPitchState: Codable, Equatable {
    let half: Int
    let order: Int
    let outs: Int
    let balls: Int
    let strikes: Int
    let home: Int
    let away: Int
    let runners: [FieldRunnerProfile?]
    let homeOrder: Int
    let awayOrder: Int
    let completed: Bool
    init(_ match: CareerMatch) {
        half = match.half; order = half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder
        outs = match.outs; balls = match.balls; strikes = match.strikes
        home = match.homeScore; away = match.awayScore
        runners = match.runnerProfiles ?? [nil, nil, nil]
        homeOrder = match.homeOrder; awayOrder = match.awayOrder; completed = match.completed
    }
    var ids: [String?] { runners.map { $0?.id } }
    var valid: Bool {
        let counts = (0...2).contains(outs) && (0...3).contains(balls) && (0...2).contains(strikes)
        let score = home >= 0 && away >= 0
        return counts && score && runners.count == 3 && homeOrder >= 0 && awayOrder >= 0
            && order == (half.isMultiple(of: 2) ? awayOrder : homeOrder)
    }
    var occupied: String {
        let values = runners.indices.filter { runners[$0] != nil }.map { "\($0 + 1)" }
        return values.isEmpty ? "주자 없음" : values.joined(separator: "·") + "루"
    }
}

enum MatchLoosePitchCredit: String, Codable { case wild, passed
    var label: String { self == .wild ? "폭투 WP" : "포일 PB" }
}

struct MatchCatchObservation: Codable, Equatable {
    let x: Double
    let y: Double
    let bounced: Bool
    let catchable: Bool
    let difficulty: Double
    let catcherDefense: Double
    let recoveryDistance: Double
    let escape: Double
    var credit: MatchLoosePitchCredit { catchable ? .passed : .wild }
    var reason: String { catchable ? "포수가 보통의 수비로 잡을 수 있는 공을 놓쳤습니다." : "보통의 수비로 막기 어려운 투구가 미트 옆으로 벗어났습니다." }
}

struct MatchPitchField: Codable, Equatable {
    enum Kind: String, Codable { case hitByPitch, uncaughtThird, loose }
    let id: String
    let kind: Kind
    let settledAt: Double
    let strikeReach: Bool
    var summary: String { kind == .hitByPitch ? "사구 · 볼 데드 · 밀리는 주자만 진루" : kind == .uncaughtThird ? "낫아웃 · 1루 승부" : "포구 실패 · 주자 진루" }
}

struct MatchPitchEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case foul, foulBunt, hitByPitch, uncaughtThird, loose }
    let sequence: Int
    let kind: Kind
    let before: MatchPitchState
    let after: MatchPitchState
    /// 볼넷과 같은 투구에 이어진 추가 진루는 보장 진루 뒤 상태에서 시작한다.
    let movementBefore: MatchPitchState?
    let batter: String
    let pitcher: String
    let catcher: String
    let personal: Bool
    let direct: Bool
    let observation: MatchCatchObservation?
    let credit: MatchLoosePitchCredit?
    let plateResult: String?
    var play: MatchDetailedPlay?
    var id: String { "pitch:\(sequence)" }
    var runs: Int { before.half.isMultiple(of: 2) ? after.away - before.away : after.home - before.home }
    var label: String {
        switch kind {
        case .foul: "파울 · 볼 데드"
        case .foulBunt: "2스트라이크 후 파울 번트 · 삼진"
        case .hitByPitch: "사구 · 볼 데드"
        case .uncaughtThird: play.map { $0.out ? "삼진 · 1루 아웃" : "삼진 · 낫아웃 출루" } ?? "삼진 · 타자 아웃"
        case .loose: (plateResult == "볼넷" ? "볼넷 · " : "") + (credit?.label ?? "추가 진루 없음")
        }
    }
}

struct MatchPitchEvents: Codable, Equatable {
    var version = 1
    var events: [MatchPitchEvent] = []
}

enum MatchPitchEventRules {
    /// 경기 정책 v1. 바운드 여부와 포구 가능 범위를 따로 판단한다.
    static func observation(x: Double, y: Double, defense: Double, escape: Double = 0.5) -> MatchCatchObservation {
        let difficulty = max(abs(x - 0.5) / 0.45, abs(y - 0.5) / 0.65)
        return MatchCatchObservation(x: x, y: y, bounced: y > 0.88, catchable: difficulty <= 0.74,
            difficulty: difficulty, catcherDefense: defense,
            recoveryDistance: 8 + escape * 15 + max(0, difficulty - 0.74) * 4, escape: escape)
    }
    static func loses(_ observation: MatchCatchObservation, draw: Double) -> Bool {
        let chance = observation.catchable ? 0.001 + (100 - observation.catcherDefense) * 0.00002
            : min(0.32, 0.025 + (observation.difficulty - 0.74) * 0.18)
        return draw < chance
    }
    static func hitByPitch(x: Double, y: Double, swinging: Bool, left: Bool) -> Bool {
        !swinging && !ManualMatchRules.isStrike(x: x, y: y) && (0.25...0.8).contains(y) && (left ? x > 0.85 : x < 0.15)
    }
    static func canRunOnThird(outs: Int, firstOccupied: Bool) -> Bool { outs == 2 || !firstOccupied }

    /// 현재 수비·주력의 거리/준비/송구 시간을 사용한다. 웹 시안 초수를 가져오지 않는다.
    static func field(match: CareerMatch, id: String, kind: MatchPitchField.Kind, observation: MatchCatchObservation?,
                      batter: FieldRunnerProfile, allowedOriginal: Set<String>? = nil) -> MatchDetailedPlay {
        let skills = DetailedFieldRules.skills(stats: match.fieldStats, defending: !match.offense && match.appearance, npc: match.npcDefenders)
        let catcher = skills[1], receiver = skills[2], bags = DetailedFieldRules.bases
        let before = match.runnerProfiles ?? [nil, nil, nil]
        // 홈 뒤 원근 좌표의 잘림을 피하되 회수 거리는 유지해 홈 옆 파울 구역에 배치한다.
        let side = (observation?.x ?? 0.5) < 0.5 ? -1.0 : 1.0
        let reach = hypot(4, (observation?.recoveryDistance ?? 3) - 3) / sqrt(2)
        let loose = FieldPoint(x: side * reach, y: DetailedFieldRules.positions[1].y + reach)
        let pickup = kind == .hitByPitch ? 0 : 0.25 + catcher.reaction + loose.distance(to: DetailedFieldRules.positions[1]) / catcher.velocity + catcher.pickup
        let release = pickup + (kind == .uncaughtThird ? catcher.transfer : 0)
        let ballAt = kind == .uncaughtThird ? release + loose.distance(to: bags[1]) / catcher.throwVelocity : pickup
        let control = ballAt + (kind == .uncaughtThird ? receiver.pickup : 0)
        let runStart = kind == .hitByPitch ? 0.2 : 0.22
        let batterAt = runStart + 27.43 / (4 + batter.speed * 0.03)
        let out = kind == .uncaughtThird && control < batterAt
        let third = match.outs + (out ? 1 : 0) >= 3
        var runners: [DetailedRunner] = []
        var after: [FieldRunnerProfile?] = [nil, nil, nil]
        var forced = 0
        while forced < 3 && before[forced] != nil { forced += 1 }
        // 앞 주자부터 도착지를 정해 같은 루의 중복 점유를 막는다.
        for index in (0..<3).reversed() {
            guard let profile = before[index] else { continue }
            let from = index + 1, next = from + 1
            let time = runStart + 27.43 / (4 + profile.speed * 0.03)
            let allowed = allowedOriginal.map { $0.contains(profile.id ?? "") } ?? true
            let open = next == 4 || after[next - 1] == nil
            let advance = kind == .hitByPitch ? index < forced : allowed && open && (kind == .uncaughtThird || time < pickup + 27.43 / catcher.throwVelocity + catcher.transfer)
            let destination = advance ? next : from
            let arrival = advance ? time : 0
            runners.append(DetailedRunner(from: from, destination: destination, profile: profile,
                nodes: advance ? [FieldNode(at: 0, point: bags[from]), FieldNode(at: runStart, point: bags[from]), FieldNode(at: arrival, point: bags[destination])]
                    : [FieldNode(at: 0, point: bags[from])]))
            if destination < 4 && !third { after[destination - 1] = profile }
        }
        if kind != .loose {
            runners.append(DetailedRunner(from: 0, destination: 1, profile: batter,
                nodes: [FieldNode(at: 0, point: bags[0]), FieldNode(at: runStart, point: bags[0]), FieldNode(at: batterAt, point: bags[1])],
                out: out, retiredAt: out ? control : nil))
            if !out && !third { after[0] = batter }
        }
        let runs = third ? 0 : runners.filter { !$0.out && $0.destination == 4 }.count
        let settled = max(control, runners.map(\.arrival).max() ?? 0)
        var fielders = DetailedFieldRules.positions.map { [FieldNode(at: 0, point: $0)] }
        if kind != .hitByPitch {
            fielders[1] = [FieldNode(at: 0, point: DetailedFieldRules.positions[1]), FieldNode(at: pickup, point: loose)]
            if kind == .uncaughtThird { fielders[2].append(FieldNode(at: max(0, ballAt - receiver.reaction), point: bags[1])) }
        }
        let rolledAt = min(pickup, 0.25 + loose.distance(to: bags[0]) / 25)
        let escapedBall = [FieldNode(at: 0, point: bags[0]), FieldNode(at: rolledAt, point: loose)]
        var play = MatchDetailedPlay(half: match.half, order: match.half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder,
            landing: loose, flight: 0, fielder: 1, receiver: 2, ownDefense: false, ownBatter: batter.own,
            appliedTraits: [], positionDelay: 0, pickupAt: pickup, releaseAt: release, ballAt: ballAt, controlAt: control,
            targetBase: 1, targetRunner: kind == .uncaughtThird ? 0 : nil, force: true, out: out,
            runnerAt: kind == .uncaughtThird ? batterAt : nil, runners: runners,
            ball: kind == .uncaughtThird ? escapedBall + [FieldNode(at: release, point: loose), FieldNode(at: ballAt, point: bags[1])]
                : kind == .loose ? escapedBall : [FieldNode(at: 0, point: bags[0])], fielders: fielders, afterRunners: after, runs: runs,
            outsAdded: out ? 1 : 0, hitBases: 0)
        play.pitchEvent = MatchPitchField(id: id, kind: kind, settledAt: settled, strikeReach: kind == .uncaughtThird && !out)
        return play
    }
}

extension CareerMatch {
    mutating func enablePitchEvents() {
        guard pitchEvents == nil else { return }
        pitchEvents = MatchPitchEvents()
        if appearance && role == "batter" { line.hitByPitch = 0; if fieldStats?.position == "C" { line.passedBalls = 0 } }
        if appearance && role == "pitcher" { line.hitBatters = 0; line.wildPitches = 0; line.strikeoutsWithoutOut = 0 }
        if playerRecords != nil {
            for home in [true, false] {
                var team = home ? playerRecords!.home : playerRecords!.away
                for i in team.batting.indices { team.batting[i].counts.hitByPitch = 0 }
                for i in team.pitching.indices {
                    team.pitching[i].counts.hitBatters = 0; team.pitching[i].counts.wildPitches = 0
                    team.pitching[i].counts.uncaughtStrikeouts = 0; team.pitching[i].counts.uncaughtReach = 0
                }
                for i in team.fielding?.indices ?? 0..<0 { team.fielding?[i].passedBalls = 0 }
                if home { playerRecords?.home = team } else { playerRecords?.away = team }
            }
        }
    }
    var pitchEventSequence: Int {
        if let pitchLog { return pitchLog.pitches.count + 1 }
        if let records = playerRecords { return records.home.pitchingTotal.pitches + records.away.pitchingTotal.pitches }
        return (pitchEvents?.events.last?.sequence ?? 0) + 1
    }
    var pitchEventBatter: FieldRunnerProfile {
        let home = half % 2 == 1
        let order = home ? homeOrder : awayOrder
        let own = appearance && role == "batter" && ownAtBat
        let id = playerRecords?.homeTeam(batting: half).batterID(order: order, relief: pitching?.change(home: home) != nil)
        return FieldRunnerProfile(speed: own ? fieldStats?.speed ?? 60 : npcBatterSpeed, own: own,
            responsiblePitcher: pitching?.activeID(home: !home), id: id ?? "batter:\(half):\(order)")
    }
    var pitchEventCatcherDefense: Double {
        DetailedFieldRules.skills(stats: fieldStats, defending: !offense && appearance, npc: npcDefenders)[1].defense
    }
    mutating func appendPitchEvent(kind: MatchPitchEvent.Kind, before: MatchPitchState, movementBefore: MatchPitchState? = nil,
                                  personal: Bool, direct: Bool, observation: MatchCatchObservation? = nil,
                                  credit: MatchLoosePitchCredit? = nil, plateResult: String? = nil, play: MatchDetailedPlay? = nil) {
        guard pitchEvents != nil else { return }
        let attack = before.half % 2 == 1 ? playerRecords?.home : playerRecords?.away
        let defense = before.half % 2 == 1 ? playerRecords?.away : playerRecords?.home
        let relief = pitching?.change(home: before.half % 2 == 0) != nil
        let batter = attack?.batterID(order: before.order, relief: pitching?.change(home: before.half % 2 == 1) != nil) ?? ""
        let pitcher = defense?.pitching[relief ? 1 : 0].id ?? ""
        let catcher = defense?.runnerChanges?.last(where: { $0.position == "C" })?.replacement
            ?? defense?.fielding?.first(where: { $0.position == "C" })?.id ?? ""
        let event = MatchPitchEvent(sequence: pitchEventSequence, kind: kind, before: before, after: MatchPitchState(self),
            movementBefore: movementBefore, batter: batter, pitcher: pitcher, catcher: catcher,
            personal: personal, direct: direct, observation: observation, credit: credit, plateResult: plateResult, play: play)
        pitchEvents?.events.append(event)
    }
    mutating func pitchFoul(before: MatchPitchState, bunt: Bool, batter: Bool, pitcher: Bool, direct: Bool) {
        if bunt && strikes == 2 {
            endPlate("삼진", batter: batter, pitcher: pitcher)
            message = "파울 번트 · 삼진"
            appendPitchEvent(kind: .foulBunt, before: before, personal: batter || pitcher, direct: direct, plateResult: "삼진")
        } else {
            strikes = min(2, strikes + 1); message = "파울"
            appendPitchEvent(kind: .foul, before: before, personal: batter || pitcher, direct: direct)
        }
    }
    mutating func pitchHitByPitch(before: MatchPitchState, batter: Bool, pitcher: Bool, direct: Bool) {
        let play = MatchPitchEventRules.field(match: self, id: "pitch:\(pitchEventSequence)", kind: .hitByPitch,
            observation: nil, batter: pitchEventBatter)
        completePlate(initial: "사구", result: "사구", batter: batter, pitcher: pitcher, newRunner: pitchEventBatter, detailed: play)
        appendPitchEvent(kind: .hitByPitch, before: before, personal: batter || pitcher, direct: direct, plateResult: "사구", play: play)
    }
    mutating func pitchUncaughtThird(before: MatchPitchState, observation: MatchCatchObservation, batter: Bool, pitcher: Bool, direct: Bool) {
        guard MatchPitchEventRules.canRunOnThird(outs: before.outs, firstOccupied: before.runners[0] != nil) else {
            endPlate("삼진", batter: batter, pitcher: pitcher)
            message = "삼진 · 투구 당시 1루 점유로 타자 아웃"
            appendPitchEvent(kind: .uncaughtThird, before: before, personal: batter || pitcher, direct: direct,
                             observation: observation, plateResult: "삼진")
            return
        }
        let entrant = pitchEventBatter
        let play = MatchPitchEventRules.field(match: self, id: "pitch:\(pitchEventSequence)", kind: .uncaughtThird,
                                             observation: observation, batter: entrant)
        completePlate(initial: observation.credit == .wild ? "낫아웃 WP" : "낫아웃 PB", result: "삼진", batter: batter,
                      pitcher: pitcher, newRunner: entrant, detailed: play, cleanForEarned: play)
        // 타자 주자를 잡고 다른 주자가 진루한 경우에는 WP/PB를 중복 부여하지 않는다(9.13).
        let credit = play.out ? nil : observation.credit
        if let credit { recordLooseCredit(credit, defendingHome: before.half % 2 == 0) }
        appendPitchEvent(kind: .uncaughtThird, before: before, personal: batter || pitcher, direct: direct,
                         observation: observation, credit: credit, plateResult: "삼진", play: play)
    }
    mutating func pitchLoose(before: MatchPitchState, observation: MatchCatchObservation, personal: Bool, direct: Bool, walked: Bool) {
        guard !completed else { return }
        defer { closeOfficialReview() }
        let movement = MatchPitchState(self)
        var forced = 0
        while forced < 3 && before.runners[forced] != nil { forced += 1 }
        // 볼넷 보장 진루는 먼저 끝내고, 보장 진루에 포함되지 않은 주자의 추가 시도만 판단한다.
        let allowed = walked ? Set(before.runners.enumerated().compactMap { index, runner in index >= forced ? runner?.id : nil }) : nil
        let play = MatchPitchEventRules.field(match: self, id: "pitch:\(pitchEventSequence)", kind: .loose,
            observation: observation, batter: pitchEventBatter, allowedOriginal: allowed)
        let advanced = play.runners.contains { $0.destination > $0.from }
        if advanced {
            applyLoosePlay(play, credit: observation.credit)
            recordLooseCredit(observation.credit, defendingHome: before.half % 2 == 0)
            message = (walked ? "볼넷 · " : "") + observation.credit.label + " · 주자 진루"
        }
        appendPitchEvent(kind: .loose, before: before, movementBefore: movement, personal: personal, direct: direct,
            observation: observation, credit: advanced ? observation.credit : nil, plateResult: walked ? "볼넷" : nil, play: advanced ? play : nil)
    }
    private mutating func recordLooseCredit(_ credit: MatchLoosePitchCredit, defendingHome: Bool) {
        let active = pitching?.change(home: defendingHome) == nil ? 0 : 1
        if credit == .wild, role == "pitcher", appearance, defendingHome == isHome, active == 0 { line.wildPitches = (line.wildPitches ?? 0) + 1 }
        if credit == .passed, role == "batter", appearance, defendingHome == isHome, fieldStats?.position == "C" { line.passedBalls = (line.passedBalls ?? 0) + 1 }
        guard var records = playerRecords else { return }
        var team = defendingHome ? records.home : records.away
        let index = pitching?.change(home: defendingHome) == nil ? 0 : 1
        if credit == .wild {
            team.pitching[index].counts.wildPitches = (team.pitching[index].counts.wildPitches ?? 0) + 1
        } else if let row = team.fielding?.lastIndex(where: { $0.position == "C" }) {
            let count = (team.fielding?[row].passedBalls ?? 0) + 1
            team.fielding?[row].passedBalls = count
        }
        if defendingHome { records.home = team } else { records.away = team }
        playerRecords = records
    }
    private mutating func applyLoosePlay(_ play: MatchDetailedPlay, credit: MatchLoosePitchCredit) {
        let battingHome = half % 2 == 1
        let before = playerRecords?.runners ?? [nil, nil, nil]
        let goals = play.runners.filter { $0.destination == 4 }.sorted { $0.arrival < $1.arrival }
        runnerProfiles = play.afterRunners; bases = play.afterRunners.map { $0 != nil }
        var responsible: [String] = []
        for goal in goals {
            let tag = goal.profile.responsiblePitcher ?? pitching?.activeID(home: !battingHome) ?? MatchPitching.starterID(home: !battingHome)
            responsible.append(tag); pitching?.runs[tag, default: 0] += 1
        }
        if role == "pitcher", appearance { line.runsAllowed = pitching?.runs[MatchPitching.starterID(home: isHome), default: 0] ?? line.runsAllowed }
        if var records = playerRecords {
            var offense = battingHome ? records.home : records.away, defense = battingHome ? records.away : records.home
            for goal in goals {
                if let id = before[goal.from - 1], let row = offense.batting.firstIndex(where: { $0.id == id }) { offense.batting[row].counts.runs += 1 }
            }
            for tag in responsible { defense.pitching[tag == MatchPitching.reliefID(home: !battingHome) ? 1 : 0].counts.runsAllowed += 1 }
            if var earned = records.earned {
                rememberOfficialLoose(play, credit: credit)
                let credits = earned.observeLoose(play, credit: credit)
                for (tag, count) in credits {
                    let i = tag == MatchPitching.reliefID(home: !battingHome) ? 1 : 0
                    defense.pitching[i].counts.earnedRuns = (defense.pitching[i].counts.earnedRuns ?? 0) + count
                }
                records.earned = earned
            }
            records.runners = play.afterRunners.map { $0?.id }
            if !goals.isEmpty {
                let ids = responsible.map { defense.pitching[$0 == MatchPitching.reliefID(home: !battingHome) ? 1 : 0].id }
                records.decisions?.observe(home: homeScore + (battingHome ? goals.count : 0), away: awayScore + (battingHome ? 0 : goals.count),
                    battingHome: battingHome, pitcher: offense.pitching[offense.pitching[1].counts.pitches > 0 ? 1 : 0].id, responsible: ids)
            }
            if battingHome { records.home = offense; records.away = defense } else { records.away = offense; records.home = defense }
            playerRecords = records
        }
        inningScores?.record(runs: goals.count, half: half)
        if battingHome { homeScore += goals.count } else { awayScore += goals.count }
        if half == 17, homeScore > awayScore {
            completed = true
            if var records = playerRecords, var decisions = records.decisions {
                decisions.finish(records: records); records.decisions = decisions; playerRecords = records
            }
        }
    }
}

extension CareerMatch {
    /// CPU도 같은 새 사건 규칙과 실제 경기 로스터를 쓴다. 사용자 조작이나 기획 조절판을 흉내 내지 않는다.
    mutating func eventAutomaticStep(pitchCode: String?) -> MatchDelivery {
        let before = MatchPitchState(self), code = deliveryPitchCode(requested: pitchCode)
        let plan = delivery(pitchCode: code)
        _ = roll(); _ = roll()
        let inZone = ManualMatchRules.isStrike(x: plan.x, y: plan.y)
        let swing = npcBatter.map { roll() < $0.swingChance(inZone: inZone, pressure: npcPressure) } ?? inZone
        var observation = MatchPitchEventRules.observation(x: plan.x, y: plan.y, defense: pitchEventCatcherDefense)
        let lost = MatchPitchEventRules.loses(observation, draw: roll())
        if lost { observation = MatchPitchEventRules.observation(x: plan.x, y: plan.y, defense: pitchEventCatcherDefense, escape: roll()) }
        if MatchPitchEventRules.hitByPitch(x: plan.x, y: plan.y, swinging: swing, left: OpponentBatterSide.at(order: before.order) == .left) {
            pitchHitByPitch(before: before, batter: false, pitcher: false, direct: false)
            return plan
        }
        if swing && roll() < 0.13 {
            pitchFoul(before: before, bunt: false, batter: false, pitcher: false, direct: false)
            return plan
        }
        if !swing {
            if inZone { strikes += 1; message = "루킹 스트라이크" } else { balls += 1; message = "볼" }
        } else {
            let hitChance = max(0.04, min(0.65, 0.27 + (npcContact - 60) * 0.002 + (npcActivePitcher?.hitAdjustment(code: code, pressure: npcPressure) ?? 0)))
            let value = roll()
            if value < hitChance {
                let homeRun = roll() < max(0.01, min(0.35, 0.12 + (npcPower - 60) * 0.001 + (npcActivePitcher?.homeRunAdjustment(code: code, pressure: npcPressure) ?? 0)))
                endPlate(homeRun ? "홈런" : "안타", batter: false, pitcher: false)
                return plan
            } else if value < hitChance + 0.35 {
                endPlate("범타", batter: false, pitcher: false); return plan
            } else { strikes += 1; message = "헛스윙" }
        }
        if strikes >= 3 {
            if lost { pitchUncaughtThird(before: before, observation: observation, batter: false, pitcher: false, direct: false) }
            else { endPlate("삼진", batter: false, pitcher: false) }
        } else {
            let walked = balls >= 4
            if walked { endPlate("볼넷", batter: false, pitcher: false) }
            if lost { pitchLoose(before: before, observation: observation, personal: false, direct: false, walked: walked) }
        }
        return plan
    }

    func validatePitchEvents() throws {
        guard let ledger = pitchEvents else { return }
        guard ledger.version == 1, ledger.events.count <= 20_000,
              Set(ledger.events.map(\.sequence)).count == ledger.events.count,
              zip(ledger.events, ledger.events.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }) else { throw MatchError.invalidRecord }
        guard [line.hitByPitch, line.hitBatters, line.wildPitches, line.passedBalls, line.strikeoutsWithoutOut]
            .allSatisfy({ $0 == nil || (0...100_000).contains($0!) }) else { throw MatchError.invalidRecord }
        let pitches = pitchLog?.pitches.count ?? playerRecords.map { $0.home.pitchingTotal.pitches + $0.away.pitchingTotal.pitches } ?? 20_000
        for event in ledger.events {
            guard (1...max(1, pitches)).contains(event.sequence), (0..<18).contains(event.before.half),
                  (event.before.half...min(18, event.before.half + 1)).contains(event.after.half),
                  event.before.valid, event.after.valid, (0...4).contains(event.runs),
                  event.after.home >= event.before.home, event.after.away >= event.before.away,
                  event.before.half.isMultiple(of: 2) ? event.before.home == event.after.home : event.before.away == event.after.away,
                  [event.before, event.after].flatMap({ $0.runners.compactMap { $0 } }).allSatisfy({
                      $0.speed.isFinite && (0...100).contains($0.speed) && TraitLoadout.valid($0.traits)
                  }) else { throw MatchError.invalidRecord }
            if let log = pitchLog {
                guard log.pitches.indices.contains(event.sequence - 1) else { throw MatchError.invalidRecord }
                let pitch = log.pitches[event.sequence - 1]
                guard pitch.pitcherID == event.pitcher, pitch.home == event.before.half.isMultiple(of: 2),
                      pitch.balls == event.before.balls, pitch.strikes == event.before.strikes,
                      (pitch.source == "direct") == event.direct else { throw MatchError.invalidRecord }
                if let observed = event.observation {
                    guard pitch.x == observed.x, pitch.y == observed.y else { throw MatchError.invalidRecord }
                }
                if event.kind == .hitByPitch {
                    guard let x = pitch.x, let y = pitch.y, pitch.inZone == false, (0.25...0.8).contains(y),
                          x < 0.15 || x > 0.85 else { throw MatchError.invalidRecord }
                }
            }
            if let observation = event.observation {
                let expected = MatchPitchEventRules.observation(x: observation.x, y: observation.y, defense: observation.catcherDefense, escape: observation.escape)
                guard [observation.x, observation.y, observation.difficulty, observation.catcherDefense, observation.recoveryDistance].allSatisfy(\.isFinite),
                      (0...100).contains(observation.catcherDefense), (0...1).contains(observation.escape),
                      abs(observation.difficulty - expected.difficulty) <= 0.000000001,
                      abs(observation.recoveryDistance - expected.recoveryDistance) <= 0.000000001,
                      observation.bounced == expected.bounced,
                      observation.catchable == expected.catchable || abs(expected.difficulty - 0.74) <= 0.000000001,
                      event.credit == nil || event.credit == observation.credit else { throw MatchError.invalidRecord }
            } else if event.credit != nil { throw MatchError.invalidRecord }
            if let records = playerRecords {
                let offense = event.before.half % 2 == 1 ? records.home : records.away
                let defense = event.before.half % 2 == 1 ? records.away : records.home
                // 구원 투수의 첫 타석은 파울 중 아직 완료 타격 원장 행이 없을 수 있다.
                let known = Set(offense.batting.map(\.id) + offense.pitching.map(\.id))
                let batterExists = known.contains(event.batter)
                let pitcherExists = defense.pitching.contains { $0.id == event.pitcher }
                let catcherExists = defense.fielding?.contains { $0.id == event.catcher && $0.position == "C" } ?? true
                let validRunners = [event.before, event.after].allSatisfy { state in
                    let ids = state.ids.compactMap { $0 }
                    return Set(ids).count == ids.count && ids.allSatisfy { known.contains($0) }
                }
                guard batterExists, pitcherExists, catcherExists, validRunners else { throw MatchError.invalidRecord }
            }
            if let play = event.play {
                if event.kind == .foul, play.review?.ruling?.kind == .foul {try play.validate()} else {try play.validatePitchField()}
                guard play.eventID == event.id, play.half == (event.movementBefore ?? event.before).half,
                      play.afterRunners == (event.after.half == play.half ? event.after.runners : [nil, nil, nil]) else { throw MatchError.invalidRecord }
            }
            switch event.kind {
            case .foul:
                guard event.before.half == event.after.half, event.before.order == event.after.order,
                      event.before.outs == event.after.outs, event.before.ids == event.after.ids, event.runs == 0,
                      event.before.balls == event.after.balls, event.after.strikes == min(2, event.before.strikes + 1),
                      event.plateResult == nil, event.credit == nil else { throw MatchError.invalidRecord }
            case .foulBunt:
                guard event.before.strikes == 2, event.plateResult == "삼진", event.runs == 0 else { throw MatchError.invalidRecord }
            case .hitByPitch:
                guard event.plateResult == "사구", event.play?.pitchEvent?.kind == .hitByPitch, event.credit == nil,
                      event.after.balls == 0, event.after.strikes == 0,
                      event.after.half == event.before.half, event.after.outs == event.before.outs,
                      event.after.order == event.before.order + 1 else { throw MatchError.invalidRecord }
                var expected = event.before.ids
                var forced = 0
                while forced < 3 && event.before.runners[forced] != nil { forced += 1 }
                for index in stride(from: min(2, forced), through: 1, by: -1) { expected[index] = event.before.ids[index - 1] }
                expected[0] = event.play?.runners.first(where: { $0.from == 0 })?.profile.id
                guard event.after.ids == expected, event.runs == (forced == 3 ? 1 : 0),
                      playerRecords == nil || expected[0] == event.batter else { throw MatchError.invalidRecord }
            case .uncaughtThird:
                guard event.before.strikes == 2, event.plateResult == "삼진", event.observation != nil,
                      (event.play != nil) == MatchPitchEventRules.canRunOnThird(outs: event.before.outs, firstOccupied: event.before.runners[0] != nil),
                      event.credit == (event.play?.out == false ? event.observation?.credit : nil) else { throw MatchError.invalidRecord }
            case .loose:
                guard let movement = event.movementBefore, event.observation != nil,
                      event.after.order == movement.order, event.after.outs == movement.outs,
                      (event.credit != nil) == (event.play?.runners.contains(where: { $0.destination > $0.from }) == true) else { throw MatchError.invalidRecord }
            }
        }
        try validatePitchEventCounts(ledger)
    }
    private func validatePitchEventCounts(_ ledger: MatchPitchEvents) throws {
        guard let records = playerRecords else { return }
        let own = isHome ? records.home : records.away
        let id = records.careerID.uuidString
        if appearance, role == "batter", let batter = own.batting.first(where: { $0.id == id }) {
            guard line.hitByPitch == batter.counts.hitByPitch else { throw MatchError.invalidRecord }
            if fieldStats?.position == "C", let catcher = own.fielding?.first(where: { $0.id == id }) {
                guard line.passedBalls == catcher.passedBalls else { throw MatchError.invalidRecord }
            }
        }
        if appearance, role == "pitcher", let pitcher = own.pitching.first(where: { $0.id == id }) {
            guard line.hitBatters == pitcher.counts.hitBatters, line.wildPitches == pitcher.counts.wildPitches,
                  line.strikeoutsWithoutOut == pitcher.counts.uncaughtReach else { throw MatchError.invalidRecord }
        }
        for team in [records.home, records.away] {
            for row in team.batting {
                guard (row.counts.hitByPitch ?? 0) == ledger.events.filter({ $0.kind == .hitByPitch && $0.batter == row.id }).count else { throw MatchError.invalidRecord }
            }
            for row in team.pitching {
                let events = ledger.events.filter { $0.pitcher == row.id }
                guard (row.counts.hitBatters ?? 0) == events.filter({ $0.kind == .hitByPitch }).count,
                      (row.counts.wildPitches ?? 0) == events.filter({ $0.credit == .wild }).count,
                      (row.counts.uncaughtStrikeouts ?? 0) == events.filter({ $0.kind == .uncaughtThird && $0.play != nil }).count,
                      (row.counts.uncaughtReach ?? 0) == events.filter({ $0.kind == .uncaughtThird && $0.play?.out == false }).count else { throw MatchError.invalidRecord }
            }
            for row in team.fielding ?? [] {
                guard (row.passedBalls ?? 0) == ledger.events.filter({ $0.catcher == row.id && $0.credit == .passed }).count else { throw MatchError.invalidRecord }
            }
        }
    }
}

extension MatchDetailedPlay {
    func validatePitchField() throws {
        guard let event = pitchEvent, event.id.hasPrefix("pitch:"), (0..<18).contains(half), order >= 0,
              battedBall == nil, misplay == nil, secondThrow == nil, fly == nil, relay == nil,
              fielder == 1, receiver == 2, hitBases == 0, fielders.count == 9, afterRunners.count == 3,
              [flight, pickupAt, releaseAt, ballAt, controlAt, event.settledAt].allSatisfy({ $0.isFinite && $0 >= 0 }),
              flight <= pickupAt, pickupAt <= releaseAt, releaseAt <= ballAt, ballAt <= controlAt,
              event.settledAt >= controlAt, event.settledAt >= (runners.map(\.arrival).max() ?? 0),
              Set(runners.map(\.from)).count == runners.count,
              outsAdded == (out ? 1 : 0), event.kind == .uncaughtThird || !out,
              event.kind != .uncaughtThird || out == (controlAt < (runnerAt ?? 0)) else { throw MatchError.invalidRecord }
        var projected: [FieldRunnerProfile?] = [nil, nil, nil]
        for runner in runners {
            guard (0...3).contains(runner.from), (runner.from...min(4, runner.from + 1)).contains(runner.destination),
                  runner.profile.speed.isFinite, (0...100).contains(runner.profile.speed), TraitLoadout.valid(runner.profile.traits) else { throw MatchError.invalidRecord }
            if !runner.out && runner.destination < 4 {
                guard projected[runner.destination - 1] == nil else { throw MatchError.invalidRecord }
                projected[runner.destination - 1] = runner.profile
            }
        }
        // 세 번째 아웃은 1루 도착 전 타자 주자 아웃이므로 득점이 인정되지 않는다.
        guard runs == 0 || runs == runners.filter({ !$0.out && $0.destination == 4 }).count,
              afterRunners == projected || out && runs == 0 && afterRunners.allSatisfy({ $0 == nil }) else { throw MatchError.invalidRecord }
        for nodes in [ball] + fielders + runners.map(\.nodes) {
            guard !nodes.isEmpty, nodes.allSatisfy({ $0.at.isFinite && $0.at >= 0 && $0.point.x.isFinite && $0.point.y.isFinite }),
                  zip(nodes, nodes.dropFirst()).allSatisfy({ $0.at <= $1.at }) else { throw MatchError.invalidRecord }
        }
    }
}

/// 타석 사이의 진루를 건너뛰거나 가짜 타석으로 만들지 않고, 다음 타석/현재 원장 경계에 연결한다.
struct MatchTraceBoundary {
    var half: Int
    var outs: Int
    var home: Int
    var away: Int
    var homeOrder: Int
    var awayOrder: Int
    var runners: [String?]
    func resolving(in match: CareerMatch) throws -> Self {
        var state = self
        var changedAt: String?
        func changes() throws {
            let order = state.half % 2 == 1 ? state.homeOrder : state.awayOrder
            let key = "\(state.half):\(order)"
            guard changedAt != key else { return }
            let team = state.half % 2 == 1 ? match.playerRecords?.home : match.playerRecords?.away
            for change in team?.runnerChanges ?? [] where change.half == state.half && change.order == order {
                guard state.runners[change.base - 1] == change.original || state.runners[change.base - 1] == change.replacement else { throw MatchError.invalidRecord }
                state.runners[change.base - 1] = change.replacement
            }
            changedAt = key
        }
        struct Movement {
            let sequence: Int
            let ordinal: Int
            let before: MatchPitchState
            let after: MatchPitchState
        }
        let loose = (match.pitchEvents?.events ?? []).filter { $0.kind == .loose && $0.play != nil }.compactMap { event in
            event.movementBefore.map { Movement(sequence: event.sequence, ordinal: 0, before: $0, after: event.after) }
        }
        let running = (match.running?.events ?? []).map { Movement(sequence: $0.pitch, ordinal: $0.index, before: $0.movementBefore, after: $0.after) }
        try changes()
        for movement in (loose + running).sorted(by: { ($0.sequence, $0.ordinal) < ($1.sequence, $1.ordinal) }) {
            let before = movement.before
            let currentOrder = state.half % 2 == 1 ? state.homeOrder : state.awayOrder
            guard before.half == state.half, before.order == currentOrder else { continue }
            try changes()
            guard before.ids == state.runners, before.home == state.home, before.away == state.away,
                  before.outs == state.outs, before.homeOrder == state.homeOrder, before.awayOrder == state.awayOrder else { throw MatchError.invalidRecord }
            state.half = movement.after.half; state.outs = movement.after.outs
            state.home = movement.after.home; state.away = movement.after.away; state.runners = movement.after.ids
            state.homeOrder = movement.after.homeOrder; state.awayOrder = movement.after.awayOrder
        }
        try changes()
        return state
    }
}

extension MatchEarnedState {
    mutating func observeLoose(_ play: MatchDetailedPlay, credit: MatchLoosePitchCredit) -> [String: Int] {
        let before = runners
        let moving = play.runners.filter { $0.destination > $0.from }
        if credit == .wild {
            for index in views.indices where views[index].outs < 3 {
                let old = views[index].runners
                var after = old
                for base in (0..<3).reversed() {
                    guard let runner = old[base], moving.contains(where: { before[$0.from - 1]?.token == runner.token }) else { continue }
                    after[base] = nil
                    if base == 2 { views[index].scored.append(runner.token) } else { after[base + 1] = runner }
                }
                views[index].runners = after
            }
        }
        runners = [nil, nil, nil]
        for movement in play.runners {
            guard let runner = before[movement.from - 1] else { continue }
            if movement.destination == 4 {
                actual.append(EarnedScore(token: runner.token, pitcher: runner.profile.responsiblePitcher ?? "", unearned: runner.unearned))
                observedRuns += 1
            } else { runners[movement.destination - 1] = runner }
        }
        var credits: [String: Int] = [:]
        for run in actual where !run.unearned && !awarded.contains(run.token) {
            if views.first(where: { $0.pitcher == run.pitcher })?.scored.contains(run.token) == true {
                credits[run.pitcher, default: 0] += 1; awarded.append(run.token)
            }
        }
        return credits
    }
}
