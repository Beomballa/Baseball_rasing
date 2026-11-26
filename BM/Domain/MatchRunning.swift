import Foundation

/// 주루 의도는 공을 실행하기 전에 저장한다. 조회와 영상 재생은 이 값을 바꾸지 않는다.
struct MatchRunningReservation: Codable, Equatable {
    let runner: String
    let half: Int
    let order: Int
    let pitch: Int
}
struct MatchRunningState: Codable, Equatable {
    var version = 1
    var reservation: MatchRunningReservation?
    var events: [MatchRunningEvent] = []
}
struct MatchRunningField: Codable, Equatable {
    enum Kind: String, Codable { case steal, pickoff, rundown }
    let id: String
    let kind: Kind
    let settledAt: Double
    let turnAt: Double?
    var walkOffAt: Double? = nil
    var label: String {
        switch kind { case .steal: "도루"; case .pickoff: "견제·귀루"; case .rundown: "협살" }
    }
}
struct MatchRunningEvent: Codable, Equatable, Identifiable {
    let index: Int
    let pitch: Int
    let before: MatchPitchState
    let movementBefore: MatchPitchState
    let after: MatchPitchState
    let play: MatchDetailedPlay
    var id: String { play.eventID }
    static func committedAction(previous: CareerMatch, updated: CareerMatch) -> Self? {
        let before = MatchPitchState(previous)
        return updated.running?.events.dropFirst(previous.running?.events.count ?? 0).first {
            $0.before.half == before.half && $0.before.order == before.order
        }
    }
    var recordSummary: String {
        if play.runningEvent?.walkOffAt != nil { return "끝내기 득점" }
        if play.runningEvent?.kind == .pickoff { return play.out ? "견제사 · 도루 실패와 구분" : "귀루 · 도루 기록 변화 없음" }
        if play.out { return "도루 실패" }
        return play.runners.first?.destination == 2 ? "도루" : "귀루"
    }
    var label: String {
        guard let field = play.runningEvent else { return "주루" }
        if field.walkOffAt != nil { return "협살 · 끝내기 득점" }
        return field.label + (play.out ? " · 태그 아웃" : field.kind == .steal && play.runners.first?.destination == 2 ? " · 도루 성공" : " · 귀루 성공")
    }
}

enum MatchRunningRules {
    /// 기존 야수 이동·송구 능력을 공유하며 초수나 화면 프레임으로 승부를 결정하지 않는다.
    static func play(match: CareerMatch, kind: MatchRunningField.Kind, id: String, pitchDuration: Double = 0.90,
                     aggressive: Bool = false) -> MatchDetailedPlay? {
        guard let original = match.runnerProfiles, original.count == 3,
              let first = original[0], first.id != nil, original[1] == nil else { return nil }
        let skills = DetailedFieldRules.skills(stats: match.fieldStats,
            defending: !match.offense && match.appearance && (match.role != "pitcher" || match.ownPitcherActive), npc: match.npcDefenders)
        let base = DetailedFieldRules.bases, positions = DetailedFieldRules.positions
        func node(_ t: Double, _ p: FieldPoint) -> FieldNode { .init(at: t, point: p) }
        let velocity = DetailedFieldRules.runnerVelocity(first)
        let distance = base[1].distance(to: base[2])
        let lead = aggressive ? 4.5 : 1.5
        let leadPoint = base[1].towards(base[2], fraction: lead / distance)
        var paths = skills.indices.map { [node(0, positions[$0])] }
        var moving = original.enumerated().compactMap { i, r in r.map {
            DetailedRunner(from: i + 1, destination: i + 1, profile: $0, nodes: [node(0, base[i + 1])])
        }}
        let receiver: Int, handler: Int, target: Int
        let pickup: Double, release: Double, arrival: Double, tag: Double, runnerAt: Double
        let ball: [FieldNode]
        let finalKind: MatchRunningField.Kind
        var turn: Double?
        var retired = false
        if kind == .pickoff {
            handler = 0; receiver = 2; target = 1; pickup = 0
            release = max(skills[0].transfer * 0.6,
                skills[2].reaction + positions[2].distance(to: base[1]) / skills[2].velocity
                    - positions[0].distance(to: base[1]) / skills[0].throwVelocity)
            arrival = release + positions[0].distance(to: base[1]) / skills[0].throwVelocity
            tag = arrival + 0.3 - skills[2].defense * 0.0015
            runnerAt = release + 0.18 + (100 - first.speed) * 0.003 + lead / velocity
            retired = tag < runnerAt; finalKind = .pickoff
            moving[0].nodes = [node(0, leadPoint), node(release + 0.18 + (100 - first.speed) * 0.003, leadPoint),
                               node(retired ? tag : runnerAt, retired ? leadPoint.towards(base[1], fraction: max(0, (tag - release - 0.18 - (100 - first.speed) * 0.003) * velocity / lead)) : base[1])]
            ball = [node(0, positions[0]), node(release, positions[0]), node(arrival, base[1])]
            paths[2] += [node(max(0, arrival - skills[2].pickup), base[1]), node(arrival, base[1])]
        } else {
            handler = 1; pickup = pitchDuration
            let start = 0.18 + (100 - first.speed) * 0.002
            let atSecond = start + (distance - lead) / velocity
            let throwAt = pickup + skills[1].transfer
            let secondAt = throwAt + base[0].distance(to: base[2]) / skills[1].throwVelocity
            let secondTag = secondAt + 0.3 - skills[3].defense * 0.0015
            let outbound = [node(0, leadPoint), node(start, leadPoint), node(atSecond, base[2])]
            // 목표 루에 크게 못 미친 주자는 무리하게 태그로 뛰어들지 않고 귀루한다.
            if secondTag < atSecond, base[2].distance(to: FieldNode.sample(outbound, at: secondAt)) > 3 {
                finalKind = .rundown; turn = secondAt
                receiver = 2; target = 1
                let turning = FieldNode.sample(outbound, at: secondAt)
                let nextRelease = secondAt + skills[3].transfer
                arrival = nextRelease + base[2].distance(to: base[1]) / skills[3].throwVelocity
                runnerAt = secondAt + turning.distance(to: base[1]) / velocity
                let atCatch = turning.towards(base[1], fraction: min(1, (arrival - secondAt) * velocity / max(0.001, turning.distance(to: base[1]))))
                let chase = atCatch.distance(to: base[1]) / (skills[2].velocity + velocity)
                tag = arrival + chase + 0.3 - skills[2].defense * 0.0015
                retired = tag < runnerAt
                let tagPoint = turning.towards(base[1], fraction: min(1, (tag - secondAt) * velocity / max(0.001, turning.distance(to: base[1]))))
                release = throwAt
                moving[0].destination = 1
                moving[0].nodes = [node(0, leadPoint), node(start, leadPoint), node(secondAt, turning),
                                   node(retired ? tag : runnerAt, retired ? tagPoint : base[1])]
                ball = [node(0, positions[0]), node(pickup, base[0]), node(throwAt, base[0]),
                        node(secondAt, base[2]), node(nextRelease, base[2]), node(arrival, base[1]), node(tag, retired ? tagPoint : base[1])]
                paths[1] += [node(pickup, base[0]), node(throwAt, base[0])]
                paths[3] += [node(secondAt, base[2]), node(nextRelease, base[2])]
                paths[2] += [node(arrival, base[1]), node(tag, retired ? tagPoint : base[1])]
                // 2사 협살에서는 후속 송구 사이 3루 주자가 홈을 노린다. 득점도 같은 도착 순서로 판단한다.
                if match.outs == 2, let third = original[2], let row = moving.firstIndex(where: { $0.from == 3 }) {
                    let homeAt = throwAt + distance / DetailedFieldRules.runnerVelocity(third)
                    moving[row].destination = 4
                    moving[row].nodes = [node(0, base[3]), node(throwAt, base[3]), node(homeAt, base[4])]
                }
            } else {
                finalKind = .steal; receiver = 3; target = 2
                release = throwAt; arrival = secondAt; tag = secondTag; runnerAt = atSecond
                retired = secondTag < atSecond
                moving[0].destination = 2
                moving[0].nodes = outbound
                ball = [node(0, positions[0]), node(pickup, base[0]), node(release, base[0]), node(arrival, base[2])]
                paths[1] += [node(pickup, base[0]), node(release, base[0])]
                paths[3] += [node(arrival, base[2])]
            }
        }
        moving[0].out = retired; moving[0].retiredAt = retired ? tag : nil
        if retired {
            let end = FieldNode.sample(moving[0].nodes, at: tag)
            moving[0].nodes = moving[0].nodes.filter { $0.at < tag } + [node(tag, end)]
        }
        var decision = max(tag, retired ? tag : runnerAt)
        let thirdOut = match.outs + (retired ? 1 : 0) == 3
        var after: [FieldRunnerProfile?] = [nil, nil, nil]
        var runs = 0
        for runner in moving where !runner.out {
            if runner.destination == 4 {
                if !thirdOut || runner.arrival < tag { runs += 1 }
            } else { after[runner.destination - 1] = runner.profile }
        }
        if thirdOut {
            after = [nil, nil, nil]
            for i in moving.indices where moving[i].arrival > tag {
                let stopped = FieldNode.sample(moving[i].nodes, at: tag)
                moving[i].nodes = moving[i].nodes.filter { $0.at < tag } + [node(tag, stopped)]
            }
        }
        // 끝내기 홈 터치 뒤의 계획된 태그는 아웃·도루실패로 기록하지 않는다.
        let winningTouch = match.half == 17 && match.homeScore + runs > match.awayScore
            ? moving.filter { !$0.out && $0.destination == 4 && (!thirdOut || $0.arrival < tag) }.map(\.arrival).min() : nil
        var savedBall = ball, savedPaths = paths
        if let winningTouch {
            decision = winningTouch; retired = false
            moving[0].out = false; moving[0].retiredAt = nil; moving[0].destination = 1
            after = original; after[2] = nil
            func trimmed(_ nodes: [FieldNode]) -> [FieldNode] {
                nodes.filter { $0.at < winningTouch } + [node(winningTouch, FieldNode.sample(nodes, at: winningTouch))]
            }
            savedBall = trimmed(ball); savedPaths = paths.map(trimmed)
            for i in moving.indices { moving[i].nodes = trimmed(moving[i].nodes) }
        }
        return MatchDetailedPlay(version: 5, half: match.half, order: match.half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder,
            landing: positions[handler], flight: 0, fielder: handler, receiver: receiver,
            ownDefense: !match.offense && match.appearance, ownBatter: false, appliedTraits: [], positionDelay: 0,
            pickupAt: min(pickup, decision), releaseAt: min(release, decision), ballAt: min(arrival, decision), controlAt: winningTouch ?? tag, targetBase: target, targetRunner: 1,
            force: false, out: retired, runnerAt: winningTouch ?? runnerAt, runners: moving, ball: savedBall, fielders: savedPaths,
            afterRunners: after, runs: runs, outsAdded: retired ? 1 : 0, hitBases: 0, outsBefore: match.outs,
            runningEvent: MatchRunningField(id: id, kind: finalKind, settledAt: decision, turnAt: turn, walkOffAt: winningTouch))
    }
}

extension CareerMatch {
    var canPrepareRunning: Bool {
        guard running != nil, !completed, appearance, role == "batter", offense, !ownAtBat,
              let first = runnerProfiles?.first ?? nil, first.own, let id = first.id,
              playerRecords?.careerID.uuidString == id, runnerProfiles?[1] == nil else { return false }
        return true
    }
    private var runningPitchCount: Int {
        pitchLog?.pitches.count ?? playerRecords.map { $0.home.pitchingTotal.pitches + $0.away.pitchingTotal.pitches } ?? 0
    }
    var runningReservation: MatchRunningReservation? {
        guard canPrepareRunning, let id = runnerProfiles?[0]?.id else { return nil }
        return .init(runner: id, half: half, order: half.isMultiple(of: 2) ? awayOrder : homeOrder,
                     pitch: runningPitchCount)
    }
    mutating func enableRunning() {
        guard playerRecords != nil, pitchEvents != nil, half == 0, homeOrder == 0, awayOrder == 0 else { return }
        running = MatchRunningState()
        for i in playerRecords!.home.batting.indices {
            playerRecords?.home.batting[i].counts.stolenBases = 0; playerRecords?.home.batting[i].counts.caughtStealing = 0
        }
        for i in playerRecords!.away.batting.indices {
            playerRecords?.away.batting[i].counts.stolenBases = 0; playerRecords?.away.batting[i].counts.caughtStealing = 0
        }
    }
    mutating func reserveRunning(_ selected: Bool) throws {
        guard let token = runningReservation else { throw MatchError.invalidInput }
        running?.reservation = selected ? token : nil
    }
    mutating func advanceRunning() throws {
        guard canPrepareRunning else { throw MatchError.invalidInput }
        step(.swing, pitchCode: nil)
        running?.reservation = nil
        settle()
        finalizeAbilityExperience()
    }
    var runningEligible: Bool {
        running != nil && !completed && runnerProfiles?[0]?.id != nil && runnerProfiles?[1] == nil
    }
    var coachPickoff: Bool {
        guard runningEligible else { return false }
        // 같은 저장 RNG의 다음 값을 미리 읽기만 하므로 화면 조회가 추첨을 소비하지 않는다.
        var sample = self; sample.random ^= 0x5049434B4F464631
        return sample.roll() < (running?.reservation == runningReservation && canPrepareRunning ? 0.16 : 0.06)
    }
    mutating func resolveRunningPickoff() -> Bool {
        guard coachPickoff else { return false }
        let before = MatchPitchState(self)
        _ = roll()
        guard let play = MatchRunningRules.play(match: self, kind: .pickoff,
            id: "running:\((running?.events.count ?? 0) + 1)", aggressive: running?.reservation != nil) else { return false }
        applyRunning(play, before: before, movement: before)
        running?.reservation = nil
        return true
    }
    /// 같은 공의 파울/사구/타구/보장 진루/포구 실패가 주루 시도보다 우선한다.
    mutating func resolveRunningPitch(before: MatchPitchState, eventCount: Int, fieldCount: Int, homeRunCount: Int, attempted: Bool, pitchFlight: Double = 0.90) {
        defer { running?.reservation = nil }
        guard attempted, !completed, half == before.half, runningEligible,
              before.ids[0] == runnerProfiles?[0]?.id, before.ids[1] == nil,
              (pitchEvents?.events.count ?? 0) == eventCount, (fieldPlays?.count ?? 0) == fieldCount,
              (homeRuns?.count ?? 0) == homeRunCount,
              (half.isMultiple(of: 2) ? awayOrder : homeOrder) == before.order || message == "삼진" else { return }
        let movement = MatchPitchState(self)
        guard let play = MatchRunningRules.play(match: self, kind: .steal,
            id: "running:\((running?.events.count ?? 0) + 1)", pitchDuration: pitchFlight, aggressive: true) else { return }
        applyRunning(play, before: before, movement: movement)
    }
    mutating func applyRunning(_ play: MatchDetailedPlay, before: MatchPitchState, movement: MatchPitchState) {
        rememberOfficialRunning(play)
        defer { closeOfficialReview() }
        let battingHome = half % 2 == 1, defendingHome = !battingHome
        let oldOuts = outs
        let goals = play.runners.filter { !$0.out && $0.destination == 4 && (!(outs + play.outsAdded == 3) || $0.arrival < play.controlAt) }
        var tags: [String] = []
        for goal in goals {
            let tag = goal.profile.responsiblePitcher ?? pitching?.activeID(home: defendingHome) ?? MatchPitching.starterID(home: defendingHome)
            pitching?.runs[tag, default: 0] += 1; tags.append(tag)
        }
        if var records = playerRecords {
            var attack = battingHome ? records.home : records.away, defense = defendingHome ? records.home : records.away
            let pi = pitching?.change(home: defendingHome) == nil ? 0 : 1
            defense.pitching[pi].counts.outs += play.outsAdded
            for tag in tags { defense.pitching[tag == MatchPitching.reliefID(home: defendingHome) ? 1 : 0].counts.runsAllowed += 1 }
            if let id = play.runners.first?.profile.id, let row = attack.batting.firstIndex(where: { $0.id == id }), play.runningEvent?.kind != .pickoff {
                if play.out { attack.batting[row].counts.caughtStealing = (attack.batting[row].counts.caughtStealing ?? 0) + 1 }
                else if play.runners.first?.destination == 2 { attack.batting[row].counts.stolenBases = (attack.batting[row].counts.stolenBases ?? 0) + 1 }
            }
            for goal in goals {
                if let row = attack.batting.firstIndex(where: { $0.id == goal.profile.id }) { attack.batting[row].counts.runs += 1 }
            }
            if var fielding = defense.fielding, play.out {
                let recipient = DetailedFieldRules.names[play.receiver]
                if let row = fielding.lastIndex(where: { $0.position == recipient }) { fielding[row].putouts += 1 }
                let helpers = play.runningEvent?.kind == .rundown ? [1, 3] : [play.fielder]
                for helper in helpers where helper != play.receiver {
                    let position = DetailedFieldRules.names[helper]
                    if let row = fielding.lastIndex(where: { $0.position == position && (position != "P" || $0.id == defense.pitching[pi].id) }) {
                        fielding[row].assists += 1
                    }
                }
                defense.fielding = fielding
            }
            if var earned = records.earned {
                let credits = earned.observeRunning(play)
                for (tag, count) in credits {
                    let pi = tag == MatchPitching.reliefID(home: defendingHome) ? 1 : 0
                    defense.pitching[pi].counts.earnedRuns = (defense.pitching[pi].counts.earnedRuns ?? 0) + count
                }
                records.earned = earned
            }
            records.runners = play.afterRunners.map { $0?.id }
            if !goals.isEmpty {
                let ids = tags.map { defense.pitching[$0 == MatchPitching.reliefID(home: defendingHome) ? 1 : 0].id }
                records.decisions?.observe(home: homeScore + (battingHome ? goals.count : 0), away: awayScore + (battingHome ? 0 : goals.count),
                    battingHome: battingHome, pitcher: attack.pitching[attack.pitching[1].counts.pitches > 0 ? 1 : 0].id, responsible: ids)
            }
            if battingHome { records.home = attack; records.away = defense } else { records.away = attack; records.home = defense }
            playerRecords = records
        }
        if appearance, role == "pitcher" {
            line.runsAllowed = pitching?.runs[MatchPitching.starterID(home: isHome), default: 0] ?? line.runsAllowed
            if defendingHome == isHome, ownPitcherActive { line.pitchingOuts += play.outsAdded }
        }
        runnerProfiles = play.afterRunners; bases = play.afterRunners.map { $0 != nil }
        outs += play.outsAdded
        inningScores?.record(runs: play.runs, half: half)
        if battingHome { homeScore += play.runs } else { awayScore += play.runs }
        if half == 17, homeScore > awayScore { completed = true }
        if outs == 3 {
            half += 1; outs = 0; balls = 0; strikes = 0
            runnerProfiles = [nil, nil, nil]; bases = [false, false, false]; playerRecords?.runners = [nil, nil, nil]
            if playerRecords?.earned != nil { playerRecords?.earned = MatchEarnedState(half: half) }
            if half == 18 || half == 17 && homeScore > awayScore { completed = true }
            if !completed { inningScores?.enter(half: half) }
        }
        if completed, var records = playerRecords, var decisions = records.decisions {
            decisions.finish(records: records); records.decisions = decisions; playerRecords = records
        }
        message = play.summary
        let nextIndex = (running?.events.count ?? 0) + 1
        let event = MatchRunningEvent(index: nextIndex, pitch: pitchLog.map { $0.pitches.count + (play.runningEvent?.kind == .pickoff ? 0 : 1) } ?? runningPitchCount,
            before: before, movementBefore: movement, after: MatchPitchState(self), play: play)
        running?.events.append(event)
        assert(oldOuts + play.outsAdded <= 3)
    }

    func validateRunning() throws {
        guard let running else { return }
        guard running.version == 1, running.events.count <= 20_000, let records = playerRecords, pitching != nil,
              records.home.pitching.count == 2, records.away.pitching.count == 2,
              (records.home.pitching + records.away.pitching).allSatisfy({ (0...100_000).contains($0.counts.pitches) }),
              (pitchEvents != nil || role == "league" && !appearance) else { throw MatchError.invalidRecord }
        guard zip(running.events,running.events.dropFirst()).allSatisfy({ $0.pitch <= $1.pitch }) else { throw MatchError.invalidRecord }
        if let reservation = running.reservation { guard reservation == runningReservation else { throw MatchError.invalidRecord } }
        for (i, event) in running.events.enumerated() {
            let play = event.play
            // 가져온 원장의 인덱스·경로를 먼저 검사한 뒤 배열에 접근한다.
            try play.validateRunningField()
            guard event.index == i + 1, event.id == "running:\(i + 1)", event.before.valid, event.after.valid, event.movementBefore.valid,
                  play.half == event.movementBefore.half, event.before.half == play.half,
                  (0...runningPitchCount).contains(event.pitch),
                  event.after.homeOrder == event.movementBefore.homeOrder, event.after.awayOrder == event.movementBefore.awayOrder,
                  play.runners.map({ $0.profile.id }) == event.movementBefore.ids.compactMap({ $0 }),
                  event.after.ids == play.afterRunners.map({ $0?.id }),
                  event.after.home - event.movementBefore.home == (play.half % 2 == 1 ? play.runs : 0),
                  event.after.away - event.movementBefore.away == (play.half % 2 == 0 ? play.runs : 0) else { throw MatchError.invalidRecord }
            let third = event.movementBefore.outs + play.outsAdded == 3
            guard event.after.half == event.movementBefore.half + (third ? 1 : 0),
                  event.after.outs == (third ? 0 : event.movementBefore.outs + play.outsAdded),
                  event.after.balls == (third ? 0 : event.movementBefore.balls),
                  event.after.strikes == (third ? 0 : event.movementBefore.strikes),
                  play.runners.allSatisfy({ event.movementBefore.runners[$0.from - 1] == $0.profile }) else { throw MatchError.invalidRecord }
            let attack = play.half.isMultiple(of: 2) ? records.away : records.home
            let tags = [MatchPitching.starterID(home: play.half.isMultiple(of: 2)), MatchPitching.reliefID(home: play.half.isMultiple(of: 2))]
            guard event.before.runners == event.movementBefore.runners,
                  event.before.home == event.movementBefore.home, event.before.away == event.movementBefore.away,
                  play.runners.allSatisfy({ runner in
                      attack.batting.contains { $0.id == runner.profile.id }
                        && runner.profile.responsiblePitcher.map(tags.contains) == true
                        && runner.profile.own == (appearance && role == "batter" && runner.profile.id == records.careerID.uuidString)
                  }) else { throw MatchError.invalidRecord }
        }
        for team in [playerRecords!.home, playerRecords!.away] {
            for row in team.batting {
                let trials = running.events.filter { $0.play.runners.first?.profile.id == row.id && $0.play.runningEvent?.kind != .pickoff }
                guard (row.counts.stolenBases ?? 0) == trials.filter({ !$0.play.out && $0.play.runners.first?.destination == 2 }).count,
                      (row.counts.caughtStealing ?? 0) == trials.filter({ $0.play.out }).count else { throw MatchError.invalidRecord }
            }
        }
    }
}

extension MatchEarnedState {
    /// 실책 없는 가상 이닝도 같은 주자의 도루·태그와 홈 도착 순서로 이동한다.
    mutating func observeRunning(_ play: MatchDetailedPlay) -> [String: Int] {
        let before = runners
        for index in views.indices where views[index].outs < 3 {
            let old = views[index].runners
            var after = old
            for move in play.runners {
                guard let token = before[move.from - 1]?.token, let origin = old.firstIndex(where: { $0?.token == token }) else { continue }
                after[origin] = nil
                if move.out { continue }
                if move.destination == 4 {
                    if views[index].outs + play.outsAdded < 3 || move.arrival < play.controlAt { views[index].scored.append(token) }
                } else { after[move.destination - 1] = old[origin] }
            }
            views[index].outs = min(3, views[index].outs + play.outsAdded); views[index].runners = views[index].outs == 3 ? [nil,nil,nil] : after
        }
        runners = [nil, nil, nil]
        for move in play.runners where !move.out {
            guard let runner = before[move.from - 1] else { continue }
            if move.destination == 4 {
                if (play.outsBefore ?? 0) + play.outsAdded < 3 || move.arrival < play.controlAt {
                    actual.append(.init(token: runner.token, pitcher: runner.profile.responsiblePitcher ?? "", unearned: runner.unearned))
                    observedRuns += 1
                }
            } else { runners[move.destination - 1] = runner }
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
extension MatchDetailedPlay {
    func validateRunningField() throws {
        if special != nil { try MatchSpecialRules.validate(self); return }
        guard let event = runningEvent, pitchEvent == nil, battedBall == nil, misplay == nil, secondThrow == nil, relay == nil,
              (0..<18).contains(half), order >= 0, (0...2).contains(outsBefore ?? -1), (1...3).contains(targetBase),
              afterRunners.count == 3, fielders.count == 9, runs >= 0, runs <= 1, hitBases == 0,
              (0..<9).contains(fielder), (0..<9).contains(receiver), fielder != receiver, targetRunner == 1,
              !force, outsAdded == (out ? 1 : 0), (outsBefore ?? 3) + outsAdded <= 3,
              [pickupAt,releaseAt,ballAt,controlAt,event.settledAt,runnerAt ?? -1].allSatisfy({ $0.isFinite && $0 >= 0 }),
              pickupAt <= releaseAt, releaseAt <= ballAt, ballAt <= controlAt,
              event.settledAt == max(controlAt, out ? controlAt : runnerAt ?? 0),
              out == ((runnerAt ?? 0) > controlAt),
              runners.first?.from == 1, Set(runners.map(\.from)).count == runners.count else { throw MatchError.invalidRecord }
        for nodes in [ball] + fielders + runners.map(\.nodes) {
            guard !nodes.isEmpty, nodes.allSatisfy({ $0.at.isFinite && $0.at >= 0 && $0.point.x.isFinite && $0.point.y.isFinite }),
                  zip(nodes,nodes.dropFirst()).allSatisfy({ $0.at <= $1.at }) else { throw MatchError.invalidRecord }
        }
        guard runners.allSatisfy({ (1...3).contains($0.from) && (1...4).contains($0.destination) && $0.profile.id != nil
            && $0.profile.speed.isFinite && (0...100).contains($0.profile.speed) }),
              runners.filter(\.out).count == outsAdded,
              runners.filter(\.out).allSatisfy({ $0.retiredAt == controlAt }) else { throw MatchError.invalidRecord }
        let third = (outsBefore ?? 0) + outsAdded == 3
        let goals = runners.filter { !$0.out && $0.destination == 4 && (!third || $0.arrival < controlAt) }
        var expected: [FieldRunnerProfile?] = [nil,nil,nil]
        for runner in runners where !runner.out && runner.destination < 4 {
            guard expected[runner.destination - 1] == nil else { throw MatchError.invalidRecord }
            expected[runner.destination - 1] = runner.profile
        }
        guard goals.count == runs, afterRunners == (third ? [nil,nil,nil] : expected) else { throw MatchError.invalidRecord }
    }
}
