import Foundation

/// 리터치 위반과 수비의 관측·어필은 별개다. 재생 시각은 저장된 사건만 읽는다.
struct MatchAppealDeparture: Codable, Equatable {
    let from: Int
    let at: Double
    let retouchedAt: Double?
    let noticedAt: Double?
}
struct MatchAppealAttempt: Codable, Equatable {
    let from: Int
    let base: Int
    let receiver: Int
    let releaseAt: Double
    let ballAt: Double
    let at: Double
}
struct MatchAppealStage: Codable, Equatable {
    let at: Double
    let outs: Int
    let runs: Int
    let retired: [Int]
    let title: String
    let detail: String
    let finalized: Bool
}
/// 읽기 전용 사건을 힙에 고정해 백그라운드 투구 계산의 값 복사 스택을 줄인다.
final class MatchAppealPlay: Codable, Equatable, Sendable {
    let context: MatchSpecialContext
    let firstTouchedAt: Double
    let departures: [MatchAppealDeparture]
    let attempts: [MatchAppealAttempt]
    let windowClosedAt: Double
    let selected: [Int]
    let provisionalRuns: Int
    let finalizedAt: Double
    let stages: [MatchAppealStage]
    init(context: MatchSpecialContext, firstTouchedAt: Double, departures: [MatchAppealDeparture],
         attempts: [MatchAppealAttempt], windowClosedAt: Double, selected: [Int], provisionalRuns: Int,
         finalizedAt: Double, stages: [MatchAppealStage]) {
        self.context=context;self.firstTouchedAt=firstTouchedAt;self.departures=departures;self.attempts=attempts
        self.windowClosedAt=windowClosedAt;self.selected=selected;self.provisionalRuns=provisionalRuns
        self.finalizedAt=finalizedAt;self.stages=stages
    }
    static func ==(lhs: MatchAppealPlay, rhs: MatchAppealPlay) -> Bool {
        lhs.context == rhs.context && lhs.firstTouchedAt == rhs.firstTouchedAt && lhs.departures == rhs.departures
            && lhs.attempts == rhs.attempts && lhs.windowClosedAt == rhs.windowClosedAt && lhs.selected == rhs.selected
            && lhs.provisionalRuns == rhs.provisionalRuns && lhs.finalizedAt == rhs.finalizedAt && lhs.stages == rhs.stages
    }
    var label: String { provisionalRuns > 0 ? (cancelled ? "어필 성립 · 득점 취소" : "어필 종료 · 득점 인정") : "리터치 어필" }
    var cancelled: Bool { selected.contains { attempts[$0].from == 3 } }
}

enum MatchAppealRules {
    private static let bags = DetailedFieldRules.bases
    private static let positions = DetailedFieldRules.positions

    /// 적법한 어필만 세며, 추가 어필은 유리한 세 번째 아웃을 바꿀 뿐 4아웃을 만들지 않는다.
    static func adjudicate(outsBefore: Int, touchedAt: Double, departures: [MatchAppealDeparture],
                           attempts: [MatchAppealAttempt], closedAt: Double,
                           goals: [(from: Int, at: Double)]) -> (selected: [Int], runs: Int) {
        guard (0...1).contains(outsBefore) else { return ([],0) }
        var selected: [Int] = [], tried = Set<Int>()
        let available = max(0, 2-outsBefore)
        func score(_ indices: [Int]) -> Int {
            let retired = Set(indices.map { attempts[$0].from })
            let third = indices.count == available && available > 0 ? indices.last.map { attempts[$0] } : nil
            return goals.filter { goal in
                !retired.contains(goal.from) && (third == nil || goal.at < third!.at && goal.from > third!.from)
            }.count
        }
        for (index, attempt) in attempts.enumerated() {
            guard attempt.base == attempt.from, (1...3).contains(attempt.from),
                  attempt.at < closedAt, attempt.at >= touchedAt,
                  tried.insert(attempt.from).inserted,
                  let departure = departures.first(where: { $0.from == attempt.from }), departure.at < touchedAt,
                  departure.retouchedAt.map({ $0 > attempt.at }) ?? true else { continue }
            if selected.count < available { selected.append(index) }
            else if available > 0 {
                var revised = selected; revised[revised.count-1] = index
                if score(revised) < score(selected) { selected = revised }
            }
        }
        return (selected, score(selected))
    }

    /// 실제 능력과 동선에서 조기 출발·관측·송구를 계산한다. 별도 발생 확률이나 최적 루 강제 선택은 없다.
    static func resolve(_ context: MatchSpecialContext) -> MatchDetailedPlay? {
        guard let ball = context.ball, ball.kind.airborne, let batter = context.batter,
              context.before.outs < 2, context.before.runners.contains(where: { $0 != nil }) else { return nil }
        let skills = context.skills, flight = ball.flight
        let source = DetailedFieldRules.resolveFly(half: context.before.half, order: context.before.order,
            landing: ball.landing, flight: flight, runners: context.before.runners, batter: batter,
            outs: context.before.outs, stats: context.stats, defending: context.defending,
            ownBatter: context.ownBatter, relayEnabled: true, npc: context.npc)
        guard source.fly?.caught == true else { return nil }
        var moves = source.runners, departures: [MatchAppealDeparture] = []
        var blocked = false
        for from in stride(from: 3, through: 1, by: -1) {
            guard let index = moves.firstIndex(where: { $0.from == from }) else { blocked = false; continue }
            let runner = moves[index], read = context.read(runner.profile)
            let ordinary = runner.destination > from
            let advancing = !blocked && (ordinary || (from == 1 && read < 82))
            if advancing {
                let delay = (0.18+(100-runner.profile.speed)*0.002) * (runner.profile.traits.contains(.cheetah) ? 0.92 : 1)
                let depart = max(skills[source.fielder].reaction, flight+delay-(100-read)*0.014)
                let arrival = depart + 27.43/DetailedFieldRules.runnerVelocity(runner.profile)
                moves[index] = DetailedRunner(from: from, destination: from+1, profile: runner.profile,
                    nodes: [.init(at: 0, point: bags[from]),.init(at: depart, point: bags[from]),.init(at: arrival, point: bags[from+1])])
                let gap = max(0, flight-depart)*DetailedFieldRules.runnerVelocity(runner.profile)
                let observers = skills.indices.filter { $0 != source.fielder && positions[$0].distance(to: bags[from]) <= 20+skills[$0].defense*0.6
                    && gap > 1.8-skills[$0].defense*0.012 }
                let noticed = observers.map { flight+skills[$0].reaction+positions[$0].distance(to: ball.landing)/20 }.min()
                departures.append(.init(from: from, at: depart, retouchedAt: nil, noticedAt: noticed))
            }
            blocked = !advancing
        }
        guard departures.contains(where: { $0.at < flight }) else { return nil }
        var paths = source.fielders.map { MatchSpecialRules.clipped($0, at: flight) }
        var ballPath = ball.nodes, holder = source.fielder, point = ball.landing
        var attempts: [MatchAppealAttempt] = [], now = flight+skills[holder].transfer
        var selected: [Int] = [], closed = max(flight,moves.map(\.arrival).max() ?? flight)+0.4
        let goals = moves.filter { $0.destination == 4 && !$0.out }.map { (from: $0.from, at: $0.arrival) }
        let known = departures.filter { $0.noticedAt != nil && $0.at < flight }
        if let firstNotice = known.compactMap(\.noticedAt).min() { now = max(now, firstNotice) }
        var remaining = known
        for _ in 0..<3 {
            let ready = remaining.filter { ($0.noticedAt ?? .infinity) <= now }
            let target = ready.min { point.distance(to: bags[$0.from]) < point.distance(to: bags[$1.from]) }
            guard let target else { break }
            // 세 번째 아웃 뒤에는 이미 관측한 다른 주자의 어필이 득점을 바꿀 때만 계속한다.
            if context.before.outs+1+selected.count >= 3,
               !goals.contains(where: { $0.from <= target.from }) { break }
            let receiver = ([2,3,4][target.from-1] == holder ? 0 : [2,3,4][target.from-1])
            let release = now+skills[holder].transfer
            let cover = flight + FieldNode.sample(paths[receiver], at: flight).distance(to: bags[target.from])/skills[receiver].velocity
            let arrival = max(release+point.distance(to: bags[target.from])/skills[holder].throwVelocity, cover)
            let at = arrival+0.3-skills[receiver].defense*0.0015
            if context.before.outs+1+selected.count >= 3, at >= closed { break }
            attempts.append(.init(from: target.from, base: target.from, receiver: receiver, releaseAt: release, ballAt: arrival, at: at))
            ballPath += [.init(at: release, point: point),.init(at: arrival, point: bags[target.from]),.init(at: at, point: bags[target.from])]
            paths[receiver] += [.init(at: arrival, point: bags[target.from]),.init(at: at, point: bags[target.from])]
            remaining.removeAll { $0.from == target.from }
            let provisional = adjudicate(outsBefore: context.before.outs, touchedAt: flight, departures: departures,
                attempts: attempts, closedAt: .infinity, goals: goals)
            selected = provisional.selected
            if context.before.outs+1+selected.count >= 3, attempts.count == selected.count {
                // 수비 철수의 기회 종료는 야수의 실제 이동 시간으로 정한다.
                let exit = (0...5).map { i in positions[i].distance(to: FieldPoint(x: positions[i].x < 0 ? -45 : 45, y: -4))/skills[i].velocity }.max() ?? 0
                closed = at+exit
            }
            if context.before.outs+1+selected.count < 3 { closed = max(closed,at+skills[receiver].transfer) }
            holder = receiver; point = bags[target.from]; now = at
            if let nextNotice = remaining.compactMap(\.noticedAt).min() { now = max(now, nextNotice) }
        }
        let decision = adjudicate(outsBefore: context.before.outs, touchedAt: flight, departures: departures,
            attempts: attempts, closedAt: closed, goals: goals)
        let retired = Dictionary(uniqueKeysWithValues: decision.selected.map { (attempts[$0].from, attempts[$0].at) })
        let third = context.before.outs+1+retired.count == 3
        var after: [FieldRunnerProfile?] = [nil,nil,nil]
        for index in moves.indices where moves[index].from > 0 {
            if let at = retired[moves[index].from] {
                moves[index].nodes = MatchSpecialRules.clipped(moves[index].nodes, at: at)
                moves[index].out = true; moves[index].retiredAt = at
            } else if !third, moves[index].destination < 4 { after[moves[index].destination-1] = moves[index].profile }
        }
        let end = max(closed, ballPath.last?.at ?? flight, moves.map(\.arrival).max() ?? flight)
        var result = MatchDetailedPlay(version: 5, half: source.half, order: source.order, landing: source.landing, flight: flight,
            fielder: source.fielder, receiver: attempts.last?.receiver ?? source.receiver, ownDefense: source.ownDefense,
            ownBatter: source.ownBatter, appliedTraits: source.appliedTraits, positionDelay: source.positionDelay,
            pickupAt: flight, releaseAt: attempts.first?.releaseAt ?? flight, ballAt: attempts.first?.ballAt ?? flight,
            controlAt: decision.selected.last.map { attempts[$0].at } ?? flight, targetBase: attempts.last?.base ?? source.targetBase,
            targetRunner: decision.selected.last.map { attempts[$0].from }, force: false, out: !retired.isEmpty, runnerAt: nil,
            runners: moves, ball: ballPath, fielders: paths, afterRunners: after, runs: decision.runs,
            outsAdded: 1+retired.count, hitBases: 0, outsBefore: context.before.outs, doublePlayGrounder: false,
            fly: source.fly, battedBall: ball, review: .init(before: context.before))
        let times = Array(Set([flight,closed]+goals.map(\.at)+attempts.map(\.at))).sorted()
        var stages: [MatchAppealStage] = [], previousRuns = 0
        for time in times {
            let currentAttempts = attempts.filter { $0.at <= time }
            let ruling = adjudicate(outsBefore: context.before.outs, touchedAt: flight, departures: departures,
                attempts: currentAttempts, closedAt: closed, goals: goals.filter { $0.at <= time })
            let final = time >= closed, count = final ? decision.runs : ruling.runs
            let retiredNow = ruling.selected.map { currentAttempts[$0].from }
            let attempt = currentAttempts.last.flatMap { abs($0.at-time) < 0.000001 ? $0 : nil }
            let title = attempt.map { "\($0.base)루 리터치 어필 성립" }
                ?? (final ? "어필 가능 기간 종료" : time == flight ? "타구 포구 · 타자 아웃" : "3루 주자 홈 터치")
            let detail = count < previousRuns ? "\(previousRuns) → \(count)점 · 취소 · 득점 주자의 조기 출발"
                : count > 0 ? "\(count)점 " + (final ? "인정" : "잠정 · 어필 확인 중")
                : "득점 없음 · " + (final ? "판정 확정" : "리터치와 어필 확인")
            stages.append(.init(at: time, outs: min(3,context.before.outs+1+retiredNow.count), runs: count,
                retired: [0]+retiredNow, title: title, detail: detail, finalized: final))
            previousRuns = count
        }
        result.appeal = .init(context: context, firstTouchedAt: flight, departures: departures, attempts: attempts,
            windowClosedAt: closed, selected: decision.selected, provisionalRuns: goals.filter { goal in
                let firstThird = attempts.count >= 2-context.before.outs ? attempts[1-context.before.outs].at : .infinity
                return goal.at < firstThird
            }.count, finalizedAt: end, stages: stages)
        return result
    }

    static func validate(_ play: MatchDetailedPlay) throws {
        guard let event = play.appeal else { throw MatchError.invalidRecord }
        try MatchSpecialRules.validateContext(event.context)
        guard var expected = resolve(event.context), expected.appeal != nil,
              play.special == nil, play.runningEvent == nil, play.pitchEvent == nil else { throw MatchError.invalidRecord }
        if let after = play.review?.after { try MatchSpecialRules.validateAfter(after, play: play, before: event.context.before) }
        expected.review?.after = play.review?.after
        guard play == expected else { throw MatchError.invalidRecord }
    }
}

extension CareerMatch {
    mutating func enableAppeals() {
        guard appealRulesVersion == nil, specialRulesVersion == 1, half == 0, homeOrder == 0, awayOrder == 0,
              fieldPlays?.isEmpty == true else { return }
        appealRulesVersion = 1
    }
    func validateAppeals() throws {
        guard appealRulesVersion == nil || appealRulesVersion == 1 && specialRulesVersion == 1,
              appealRulesVersion != nil || fieldPlays?.contains(where: { $0.appeal != nil }) != true else { throw MatchError.invalidRecord }
        for play in fieldPlays ?? [] where play.appeal != nil {
            try MatchAppealRules.validate(play)
            guard let context = play.appeal?.context else { throw MatchError.invalidRecord }
            try validateFieldContext(context, play: play)
        }
    }
}
