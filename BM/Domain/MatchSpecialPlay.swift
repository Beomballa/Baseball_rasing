import Foundation

/// 기존 선구안과 주력으로 계산한 출발·확인 시간이다. 새로운 선수 능력치가 아니다.
struct MatchRunnerTiming {
    let delays: [Int: Double]
    let checks: [Int: Double]
}

/// 판정을 다시 시뮬레이션하지 않고 검증할 수 있도록 당시 입력만 고정한다.
/// 당시 입력은 불변 공유하여 중첩 타구 계산에서 큰 값 복사를 피한다.
final class MatchSpecialContext: Codable, Equatable, Sendable {
    let before: MatchPitchState
    let ball: MatchBattedBall?
    let batter: FieldRunnerProfile?
    let stats: MatchFieldStats?
    let npc: [MatchNPCPlayer]?
    let defending: Bool
    let ownBatter: Bool
    let discipline: [String: Double]
    let pitchDuration: Double?
    let runningID: String?
    init(before: MatchPitchState, ball: MatchBattedBall?, batter: FieldRunnerProfile?, stats: MatchFieldStats?,
         npc: [MatchNPCPlayer]?, defending: Bool, ownBatter: Bool, discipline: [String: Double],
         pitchDuration: Double? = nil, runningID: String? = nil) {
        self.before=before;self.ball=ball;self.batter=batter;self.stats=stats;self.npc=npc
        self.defending=defending;self.ownBatter=ownBatter;self.discipline=discipline
        self.pitchDuration=pitchDuration;self.runningID=runningID
    }
    static func ==(lhs: MatchSpecialContext, rhs: MatchSpecialContext) -> Bool {
        lhs.before == rhs.before && lhs.ball == rhs.ball && lhs.batter == rhs.batter && lhs.stats == rhs.stats
            && lhs.npc == rhs.npc && lhs.defending == rhs.defending && lhs.ownBatter == rhs.ownBatter
            && lhs.discipline == rhs.discipline && lhs.pitchDuration == rhs.pitchDuration && lhs.runningID == rhs.runningID
    }

    func read(_ runner: FieldRunnerProfile) -> Double { discipline[runner.id ?? ""] ?? 60 }
    var skills: [DetailedFieldRules.Skill] { DetailedFieldRules.skills(stats: stats, defending: defending, npc: npc) }
    var timing: MatchRunnerTiming {
        let ball = MatchSpecialRules.effectiveBall(self)
        var delays: [Int: Double] = [:], checks: [Int: Double] = [:]
        for (index, runner) in before.runners.enumerated() {
            guard let runner else { continue }
            let uncertainty = (100 - read(runner)) / 100
            let observation: Double
            if let ball {
                let pickup = skills.indices.map { max(ball.flight, skills[$0].reaction + DetailedFieldRules.positions[$0].distance(to: ball.landing)/skills[$0].velocity) + skills[$0].pickup }.min()!
                let thrower = skills.indices.min { skills[$0].reaction + DetailedFieldRules.positions[$0].distance(to: ball.landing)/skills[$0].velocity < skills[$1].reaction + DetailedFieldRules.positions[$1].distance(to: ball.landing)/skills[$1].velocity }!
                observation = pickup + skills[thrower].transfer + ball.landing.distance(to: DetailedFieldRules.bases[2])/skills[thrower].throwVelocity
            } else { observation = 0 }
            delays[index + 1] = observation * uncertainty
            checks[index + 1] = 0.2 + uncertainty * 0.5
        }
        return MatchRunnerTiming(delays: delays, checks: checks)
    }
}

struct MatchSpecialRetirement: Codable, Equatable {
    let from: Int
    let at: Double
    let fielder: Int
    var assists: [Int] = []
}

struct MatchSpecialTag: Codable, Equatable {
    let from: Int
    let at: Double
    let out: Bool
}

struct MatchSpecialField: Codable, Equatable {
    enum Kind: String, Codable { case interference, obstruction, passing, sharedBase }
    let kind: Kind
    let at: Double
    let point: FieldPoint
    let subject: Int
    let fielder: Int
    var settledAt: Double
    var awardedAt: Double? = nil
    var resumeAt: Double? = nil
    var tags: [MatchSpecialTag] = []
    var retirements: [MatchSpecialRetirement] = []
    let context: MatchSpecialContext
    var dead: Bool { kind == .interference || kind == .obstruction }
    var label: String {
        switch kind {
        case .interference: "수비방해 · 주자 아웃 · 볼 데드"
        case .obstruction: "주루방해 · 볼 데드 · 2루 부여"
        case .passing: "선행 주자 추월 · 후속 주자 아웃 · 인플레이"
        case .sharedBase: "같은 루의 두 주자 · 태그 판정"
        }
    }
}

enum MatchSpecialRules {
    private static let bags = DetailedFieldRules.bases
    private static let positions = DetailedFieldRules.positions
    // 구장 좌표(미터)에서 몸의 접촉을 비교한다. 렌더링 픽셀과 무관하다.
    private static let contactRadius = 0.7

    /// 굴러가는 공이 최종 지점에 닿기 전, 야수가 실제로 도달할 수 있는 첫 지점을 구한다.
    static func effectiveBall(_ context: MatchSpecialContext) -> MatchBattedBall? {
        guard let ball = context.ball, ball.kind == .ground else { return context.ball }
        var first: Double?
        for index in context.skills.indices {
            let skill = context.skills[index], origin = positions[index]
            for (a,b) in zip(ball.nodes,ball.nodes.dropFirst()) where b.at > max(skill.reaction,ball.firstBounceAt ?? 0) {
                let start = max(a.at,skill.reaction,ball.firstBounceAt ?? 0), end = b.at
                let p = ball.point(at: start), q = ball.point(at: end), dt = end-start
                guard dt > 0 else { continue }
                let x=p.x-origin.x, y=p.y-origin.y, dx=(q.x-p.x)/dt, dy=(q.y-p.y)/dt
                let elapsed=start-skill.reaction, v2=skill.velocity*skill.velocity
                let aa=dx*dx+dy*dy-v2, bb=2*(x*dx+y*dy-v2*elapsed), cc=x*x+y*y-v2*elapsed*elapsed
                var roots: [Double] = cc <= 0 ? [0] : []
                let determinant=bb*bb-4*aa*cc
                if abs(aa)<0.000000001 { if abs(bb)>0.000000001 { roots.append(-cc/bb) } }
                else if determinant>=0 { roots += [(-bb-sqrt(determinant))/(2*aa),(-bb+sqrt(determinant))/(2*aa)] }
                if let root=roots.filter({ $0>=0 && $0<=dt }).min() {
                    let at=start+root
                    if first == nil || at<first! { first=at }
                    break
                }
            }
        }
        return first.map { FieldReviewRules.clipped(ball, at: $0) } ?? ball
    }

    static func context(match: CareerMatch, ball: MatchBattedBall?, batter: FieldRunnerProfile?) -> MatchSpecialContext {
        var discipline: [String: Double] = [:]
        for runner in (match.runnerProfiles ?? []).compactMap({ $0 }) + [batter].compactMap({ $0 }) {
            guard let id = runner.id else { continue }
            if id == match.playerRecords?.careerID.uuidString { discipline[id] = match.discipline }
            else if let reserve = match.runnerManagement?.reserve(home: match.half % 2 == 1), reserve.id == id { discipline[id] = reserve.discipline }
            else { discipline[id] = match.npcAttack?.team(home: match.half % 2 == 1).batters.first { $0.id == id }?.discipline ?? 60 }
        }
        return MatchSpecialContext(before: MatchPitchState(match), ball: ball, batter: batter,
            stats: match.fieldStats, npc: match.npcDefenders,
            defending: !match.offense && match.appearance && (match.role != "pitcher" || match.ownPitcherActive),
            ownBatter: batter?.own == true, discipline: discipline)
    }

    static func field(_ context: MatchSpecialContext) -> MatchDetailedPlay? {
        guard let ball = effectiveBall(context), let batter = context.batter else { return nil }
        var result = DetailedFieldRules.resolve(half: context.before.half, order: context.before.order,
            landing: ball.landing, flight: ball.flight, runners: context.before.runners, batter: batter,
            outs: context.before.outs, stats: context.stats, defending: context.defending, ownBatter: context.ownBatter,
            doublePlayEnabled: true, groundBall: ball.kind == .ground, relayEnabled: true, npc: context.npc,
            continuationEnabled: true, specialContext: context)
        result.version = 5; result.battedBall = ball
        if result.special == nil {
            result.ball = ball.nodes + result.ball.filter { $0.at > ball.flight }
            if ball.kind.airborne {
                let reach = context.skills.indices.map {
                    context.skills[$0].reaction + positions[$0].distance(to: ball.point(at: ball.firstBounceAt ?? ball.flight)) / context.skills[$0].velocity + context.skills[$0].pickup
                }.min()!
                result.fly = .init(caught: false, reachAt: reach)
            }
        }
        result.review = .init(before: context.before)
        if result.special != nil { MatchPitching.transferChoiceResponsibility(&result) }
        return result
    }

    /// 1차 수비의 시간표 위에서 실제 접촉·순서 역전·태그 기회만 찾는다.
    static func applying(_ ordinary: MatchDetailedPlay, intents: [DetailedRunner], context: MatchSpecialContext) -> MatchDetailedPlay {
        var source = ordinary
        guard let ball = effectiveBall(context) else { return ordinary }
        source.version = 5; source.battedBall = ball
        source.ball = ball.nodes + source.ball.filter { $0.at > ball.flight }
        source.review = .init(before: context.before)
        let firstOut = ordinary.runners.compactMap(\.retiredAt).min() ?? .infinity
        var candidates: [(Double, Int, MatchDetailedPlay)] = []

        if ball.kind == .ground {
            let start = max(0, source.pickupAt - context.skills[source.fielder].pickup)
            for runner in intents where runner.from > 0 {
                if let at = contact(runner.nodes, source.fielders[source.fielder], start: start, end: source.pickupAt), at < firstOut {
                    candidates.append((at, 0, interference(source, intents: intents, runner: runner, at: at, context: context)))
                }
            }
        }

        // 1루수의 2루 송구 백업과 진로 비우기도 기존 수비 반응 시간으로 계산한다.
        if context.before.runners.allSatisfy({ $0 == nil }), source.fielder >= 6,
           source.targetRunner == 0, source.targetBase == 2,
           let runner = intents.first(where: { $0.from == 0 }), let first = runner.arrival(at: 1),
           source.receiver != 2 {
            let skill = context.skills[2]
            let cover = skill.reaction + positions[2].distance(to: bags[2]) / skill.velocity
            let start = max(cover, source.ballAt + skill.reaction)
            let clear = FieldPoint(x: 4, y: bags[2].y + 4)
            let finish = start + bags[2].distance(to: clear) / skill.velocity
            source.fielders[2] = [.init(at: 0, point: positions[2]), .init(at: cover, point: bags[2]),
                .init(at: start, point: bags[2]), .init(at: finish, point: clear)]
            if let at = contact(runner.nodes, source.fielders[2], start: max(first, source.releaseAt), end: min(source.outAt, runner.arrival)), at < firstOut {
                candidates.append((at, 1, obstruction(source, intents: intents, runner: runner, at: at, context: context)))
            }
        }

        for trailing in intents where !trailing.out {
            for leading in intents where leading.from > trailing.from {
                if let at = overtaking(trailing, leading), at < firstOut {
                    candidates.append((at, 2, passing(source, intents: intents, runner: trailing, at: at, context: context)))
                }
            }
        }
        if let shared = shared(source, intents: intents, context: context) {
            candidates.append((shared.special!.at, 3, shared))
        }
        return candidates.min { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }?.2 ?? source
    }

    static func clipped(_ nodes: [FieldNode], at: Double) -> [FieldNode] {
        nodes.filter { $0.at < at } + [.init(at: at, point: FieldNode.sample(nodes, at: at))]
    }
    private static func stopped(_ runner: DetailedRunner, at: Double) -> DetailedRunner {
        var value = runner; value.nodes = clipped(runner.nodes, at: at); return value
    }
    private static func walk(_ runner: DetailedRunner, stoppedAt at: Double, resume: Double, to base: Int) -> DetailedRunner {
        var result = stopped(runner, at: at)
        let start = result.nodes.last!.point, end = bags[base]
        let time = max(0.1, start.distance(to: end) / min(3.8, DetailedFieldRules.runnerVelocity(runner.profile) * 0.55))
        result.nodes += [.init(at: resume, point: start), .init(at: resume + time * 0.25, point: start.towards(end, fraction: 0.125)),
                         .init(at: resume + time * 0.75, point: start.towards(end, fraction: 0.875)), .init(at: resume + time, point: end)]
        result.destination = base; result.out = false; result.retiredAt = nil; return result
    }

    private static func interference(_ source: MatchDetailedPlay, intents: [DetailedRunner], runner: DetailedRunner,
                                     at: Double, context: MatchSpecialContext) -> MatchDetailedPlay {
        var after = context.before.runners; after[runner.from - 1] = nil
        let victim = runner.profile.id
        var destinations: [String: Int] = [:]
        if after[0] != nil {
            if after[1] != nil { if let id = after[1]?.id { destinations[id] = 3 }; after[2] = after[1] }
            if let id = after[0]?.id { destinations[id] = 2 }; after[1] = after[0]
        }
        if let id = context.batter?.id { destinations[id] = 1 }
        let resume = at + context.skills[source.fielder].reaction
        let moves = intents.map { move -> DetailedRunner in
            if move.profile.id == victim {
                var result = stopped(move, at: at); result.out = true; result.retiredAt = at; return result
            }
            return walk(move, stoppedAt: at, resume: resume, to: destinations[move.profile.id ?? ""] ?? move.from)
        }
        let event = MatchSpecialField(kind: .interference, at: at, point: FieldNode.sample(source.fielders[source.fielder], at: at),
            subject: runner.from, fielder: source.fielder, settledAt: max(at, moves.map(\.arrival).max() ?? at),
            awardedAt: at, resumeAt: resume, retirements: [.init(from: runner.from, at: at, fielder: source.fielder)], context: context)
        return rebuilt(source, runners: moves, event: event, hitBases: 0, deadAt: at)
    }

    private static func obstruction(_ source: MatchDetailedPlay, intents: [DetailedRunner], runner: DetailedRunner,
                                    at: Double, context: MatchSpecialContext) -> MatchDetailedPlay {
        let award = at + context.skills[2].reaction, resume = award + context.skills[2].transfer
        let moves = [walk(runner, stoppedAt: at, resume: resume, to: 2)]
        var result = rebuilt(source, runners: moves, event: .init(kind: .obstruction, at: at,
            point: FieldNode.sample(runner.nodes, at: at), subject: 0, fielder: 2,
            settledAt: moves[0].arrival, awardedAt: award, resumeAt: resume, context: context), hitBases: 1, deadAt: at)
        let blocked = FieldNode.sample(source.fielders[2], at: at)
        result.fielders[2] = clipped(source.fielders[2], at: at) + [.init(at: award, point: blocked),
            .init(at: resume, point: blocked.towards(FieldPoint(x: 27, y: 18), fraction: 0.5))]
        return result
    }

    private static func passing(_ source: MatchDetailedPlay, intents: [DetailedRunner], runner: DetailedRunner,
                                at: Double, context: MatchSpecialContext) -> MatchDetailedPlay {
        var moves = source.runners
        let subject = moves.firstIndex { $0.from == runner.from }!
        moves[subject] = stopped(runner, at: at); moves[subject].out = true; moves[subject].retiredAt = at
        // 후속 주자가 아웃돼 사라진 포스를 베이스 접촉만으로 중복 판정하지 않는다.
        if source.force, let target = source.targetRunner, target > runner.from,
           let index = moves.firstIndex(where: { $0.from == target }), moves[index].out {
            moves[index] = intents.first { $0.from == target }!
        }
        let closest = source.fielders.indices.min {
            FieldNode.sample(source.fielders[$0], at: at).distance(to: FieldNode.sample(runner.nodes, at: at)) <
                FieldNode.sample(source.fielders[$1], at: at).distance(to: FieldNode.sample(runner.nodes, at: at))
        }!
        var retired = moves.filter(\.out).map { move in
            MatchSpecialRetirement(from: move.from, at: move.retiredAt ?? source.controlAt,
                fielder: move.from == runner.from ? closest : source.receiver,
                assists: move.from == runner.from ? [] : [source.fielder])
        }
        retired.sort { $0.at < $1.at }
        let event = MatchSpecialField(kind: .passing, at: at, point: FieldNode.sample(runner.nodes, at: at),
            subject: runner.from, fielder: closest, settledAt: max(at, source.decisionAt), retirements: retired, context: context)
        let touched = (1...3).filter { base in runner.nodes.contains { $0.at <= at && $0.point == bags[base] } }.max() ?? 0
        let hit = runner.from == 0 ? min(source.hitBases, touched) : source.hitBases
        return rebuilt(source, runners: moves, event: event, hitBases: hit, deadAt: nil)
    }

    static func canTagShared(_ runners: [DetailedRunner], base: Int, ballAt: Double, receiver: DetailedFieldRules.Skill, force: Bool) -> Bool {
        guard let following = runners.first(where: { $0.from == base-1 }), let leading = runners.first(where: { $0.from == base }),
              let a = touching(following, base: base), let b = touching(leading, base: base) else { return false }
        let first = max(ballAt,a.0,b.0) + 0.3-receiver.defense*0.0015
        return first <= b.1 && first + receiver.transfer*0.5 <= a.1 && (force || first + receiver.transfer*0.5 <= b.1)
    }

    private static func shared(_ source: MatchDetailedPlay, intents: [DetailedRunner], context: MatchSpecialContext) -> MatchDetailedPlay? {
        let base = source.targetBase
        guard (2...3).contains(base), let following = intents.first(where: { $0.from == base - 1 }),
              let leading = intents.first(where: { $0.from == base }),
              let firstInterval = touching(following, base: base), let secondInterval = touching(leading, base: base) else { return nil }
        let skill = context.skills[source.receiver], firstTag = max(source.ballAt, firstInterval.0, secondInterval.0) + 0.3 - skill.defense * 0.0015
        let secondTag = firstTag + skill.transfer * 0.5
        let force = context.ball != nil && (0..<base).allSatisfy { $0 == 0 || context.before.runners[$0 - 1] != nil }
        guard firstTag <= secondInterval.1, secondTag <= firstInterval.1, (force || secondTag <= secondInterval.1),
              !source.runners.contains(where: { $0.out && ($0.retiredAt ?? 0) < firstTag }) else { return nil }
        let victim = force ? leading.from : following.from
        var moves = intents
        for index in moves.indices where moves[index].from == leading.from || moves[index].from == following.from {
            let out = moves[index].from == victim
            moves[index] = stopped(moves[index], at: out ? (force ? firstTag : secondTag) : secondTag)
            moves[index].destination = base; moves[index].out = out; moves[index].retiredAt = out ? (force ? firstTag : secondTag) : nil
        }
        let event = MatchSpecialField(kind: .sharedBase, at: firstTag, point: bags[base], subject: victim, fielder: source.receiver,
            settledAt: max(secondTag, moves.map(\.arrival).max() ?? secondTag),
            tags: [.init(from: leading.from, at: firstTag, out: force), .init(from: following.from, at: secondTag, out: !force)],
            retirements: [.init(from: victim, at: force ? firstTag : secondTag, fielder: source.receiver, assists: [source.fielder])], context: context)
        return rebuilt(source, runners: moves, event: event, hitBases: force ? 0 : source.hitBases, deadAt: nil)
    }

    private static func rebuilt(_ source: MatchDetailedPlay, runners: [DetailedRunner], event: MatchSpecialField,
                                hitBases: Int, deadAt: Double?) -> MatchDetailedPlay {
        var moves = runners
        let outs = moves.filter(\.out).count, third = event.context.before.outs + outs == 3
        let thirdAt = event.retirements.sorted { $0.at < $1.at }.last?.at ?? event.at
        let sharedForce = event.kind == .sharedBase && event.context.ball != nil
            && (0..<source.targetBase).allSatisfy { $0 == 0 || event.context.before.runners[$0 - 1] != nil }
        let forceThird = third && (sharedForce
            || source.force && event.subject != source.targetRunner && event.retirements.last?.from == source.targetRunner)
        var after: [FieldRunnerProfile?] = [nil,nil,nil], runs = 0
        for move in moves where !move.out {
            if move.destination == 4 {
                if !forceThird && (!third || move.arrival < thirdAt) { runs += 1 }
            } else { after[move.destination - 1] = move.profile }
        }
        if third {
            after = [nil,nil,nil]
            for index in moves.indices where moves[index].arrival > thirdAt { moves[index] = stopped(moves[index], at: thirdAt) }
        }
        var settled = event
        if third { settled.settledAt = min(event.settledAt, thirdAt) }
        var result = MatchDetailedPlay(version: 5, half: source.half, order: source.order, landing: source.landing, flight: source.flight,
            fielder: source.fielder, receiver: source.receiver, ownDefense: source.ownDefense, ownBatter: source.ownBatter,
            appliedTraits: source.appliedTraits, positionDelay: source.positionDelay,
            pickupAt: source.pickupAt, releaseAt: source.releaseAt, ballAt: source.ballAt, controlAt: event.retirements.map(\.at).max() ?? event.at,
            targetBase: source.targetBase, targetRunner: event.subject, force: false, out: outs > 0, runnerAt: nil,
            runners: moves, ball: deadAt.map { clipped(source.ball, at: $0) } ?? source.ball,
            fielders: deadAt.map { at in source.fielders.map { clipped($0, at: at) } } ?? source.fielders,
            afterRunners: after, runs: runs, outsAdded: outs, hitBases: hitBases,
            outsBefore: event.context.before.outs, doublePlayGrounder: false, battedBall: source.battedBall,
            runningEvent: source.runningEvent, review: .init(before: event.context.before))
        result.special = settled
        return result
    }

    private static func touching(_ runner: DetailedRunner, base: Int) -> (Double, Double)? {
        let nodes = runner.nodes
        guard let last = nodes.lastIndex(where: { $0.point == bags[base] }) else { return nil }
        var first = last
        while first > 0 && nodes[first-1].point == bags[base] { first -= 1 }
        return (nodes[first].at, last == nodes.count - 1 ? .infinity : nodes[last].at)
    }
    /// 구간별 상대 위치를 직접 풀어 기기의 프레임 간격과 판정을 분리한다.
    static func contact(_ first: [FieldNode], _ second: [FieldNode], start: Double, end: Double) -> Double? {
        guard start <= end else { return nil }
        let times = Set([start,end] + (first + second).map(\.at).filter { $0 > start && $0 < end }).sorted()
        for (a,b) in zip(times,times.dropFirst()) {
            let p = FieldNode.sample(first, at: a), q = FieldNode.sample(second, at: a)
            let u = FieldNode.sample(first, at: b), v = FieldNode.sample(second, at: b)
            let x = p.x-q.x, y = p.y-q.y, dx = (u.x-v.x)-x, dy = (u.y-v.y)-y
            let c = x*x+y*y-contactRadius*contactRadius
            if c <= 0 { return a }
            let aa = dx*dx+dy*dy, bb = 2*(x*dx+y*dy), d = bb*bb-4*aa*c
            if aa > 0, d >= 0 {
                let t = (-bb-sqrt(d))/(2*aa)
                if (0...1).contains(t) { return a + (b-a)*t }
            }
        }
        return nil
    }
    private static func progress(_ runner: DetailedRunner, at time: Double) -> Double {
        var distance = Double(runner.from) * 27.43
        for (a,b) in zip(runner.nodes,runner.nodes.dropFirst()) {
            if time <= a.at { break }
            distance += a.point.distance(to: b.point) * min(1, (time-a.at)/max(0.000001,b.at-a.at))
        }
        return distance
    }
    static func overtaking(_ following: DetailedRunner, _ leading: DetailedRunner) -> Double? {
        let times = Set((following.nodes + leading.nodes).map(\.at)).sorted()
        for (a,b) in zip(times,times.dropFirst()) {
            let start = progress(following, at: a)-progress(leading, at: a)
            let end = progress(following, at: b)-progress(leading, at: b)
            if start <= 0, end > 0 {
                let at = a+(b-a)*(-start)/(end-start)
                return min(b, at + 0.0000001)
            }
        }
        return nil
    }

    static func validateContext(_ context: MatchSpecialContext) throws {
        guard context.before.valid, context.before.runners.count == 3, (0..<18).contains(context.before.half),
              context.discipline.values.allSatisfy({ $0.isFinite && (0...100).contains($0) }),
              !context.before.completed else { throw MatchError.invalidRecord }
        let profiles = context.before.runners.compactMap({ $0 }) + [context.batter].compactMap({ $0 })
        guard profiles.allSatisfy({ $0.speed.isFinite && (0...100).contains($0.speed) && TraitLoadout.valid($0.traits) && $0.id != nil }),
              Set(profiles.compactMap(\.id)).count == profiles.count else { throw MatchError.invalidRecord }
        if let npc = context.npc {
            guard npc.count == 9, npc.map(\.position) == DetailedFieldRules.names,
                  npc.allSatisfy({ [$0.speed,$0.defense,$0.arm].allSatisfy { $0.isFinite && (0...100).contains($0) } }) else { throw MatchError.invalidRecord }
        }
        if let stats = context.stats {
            guard [stats.speed,stats.defense,stats.arm].allSatisfy({ $0.isFinite && (0...100).contains($0) }),
                  TraitLoadout.valid(stats.activeTraits ?? []) else { throw MatchError.invalidRecord }
        }
        if let ball = context.ball {
            guard ball.version == 2, [ball.speed,ball.flight,ball.distance,ball.direction,ball.angle,ball.quality,ball.contact,ball.power].allSatisfy(\.isFinite),
                  ball.speed > 0, ball.speed < 70, ball.flight > 0, ball.flight <= 12, ball.distance > 0, ball.distance < 250,
                  context.batter != nil else { throw MatchError.invalidRecord }
        }
    }

    static func validateAfter(_ after: MatchPitchState, play: MatchDetailedPlay, before: MatchPitchState) throws {
        let third = before.outs + play.outsAdded == 3
        guard after.valid, after.balls == 0, after.strikes == 0,
              after.completed == (after.half == 18 || after.half == 17 && after.home > after.away),
              after.half == before.half + (third ? 1 : 0), after.outs == (third ? 0 : before.outs + play.outsAdded),
              after.ids == play.afterRunners.map({ $0?.id }),
              after.home == before.home + (before.half % 2 == 1 ? play.runs : 0),
              after.away == before.away + (before.half % 2 == 0 ? play.runs : 0),
              after.homeOrder == before.homeOrder + (before.half % 2 == 1 ? 1 : 0),
              after.awayOrder == before.awayOrder + (before.half % 2 == 0 ? 1 : 0) else { throw MatchError.invalidRecord }
    }

    static func validate(_ play: MatchDetailedPlay) throws {
        guard let event = play.special else { throw MatchError.invalidRecord }
        let context = event.context
        try validateContext(context)
        guard let expected = context.ball == nil ? sharedPitch(context) : field(context), expected.special != nil else { throw MatchError.invalidRecord }
        var comparison = expected
        if play.runningEvent == nil {
            guard play.review?.before == event.context.before else { throw MatchError.invalidRecord }
            if let after = play.review?.after {
                try validateAfter(after, play: play, before: context.before)
            }
            comparison.review?.after = play.review?.after
        }
        guard comparison == play else { throw MatchError.invalidRecord }
    }

    /// 실책 없는 가상 이닝에서도 같은 타구와 당시 능력을 사용한다. 난수를 다시 뽑지 않는다.
    static func reconstruct(_ context: MatchSpecialContext, runners: [FieldRunnerProfile?], outs: Int) -> MatchDetailedPlay? {
        guard let ball = context.ball, let batter = context.batter, outs < 3 else { return nil }
        var projected = CareerMatch(random: 0, isHome: false, role: "league", appearance: false, contact: 60, power: 60, discipline: 60, mastery: [:])
        projected.half = context.before.half; projected.outs = outs; projected.runnerProfiles = runners
        projected.homeOrder = context.before.homeOrder; projected.awayOrder = context.before.awayOrder
        let revised = MatchSpecialContext(before: MatchPitchState(projected), ball: ball, batter: batter,
            stats: context.stats, npc: context.npc, defending: context.defending, ownBatter: context.ownBatter, discipline: context.discipline)
        return field(revised)
    }

    /// 2루 주자의 실제 귀루와 1루 주자의 확인 지연이 겹치고, 포수가 두 주자를 태그할 때만 성립한다.
    static func sharedPitch(_ context: MatchSpecialContext) -> MatchDetailedPlay? {
        guard context.ball == nil, let flight = context.pitchDuration, flight.isFinite, flight > 0, flight < 5,
              let id = context.runningID, context.before.runners.count == 3,
              let first = context.before.runners[0], let second = context.before.runners[1] else { return nil }
        let skills = context.skills, catcher = skills[1], receiver = skills[3]
        let release = flight + catcher.transfer
        let arrive = max(release + bags[0].distance(to: bags[2]) / catcher.throwVelocity,
                         receiver.reaction + positions[3].distance(to: bags[2]) / receiver.velocity)
        let firstStart = 0.18 + (100-first.speed)*0.002
        let firstAt = firstStart + (27.43-4.5) / DetailedFieldRules.runnerVelocity(first)
        let lead = 1.5 + second.speed * 0.03
        let leadPoint = bags[2].towards(bags[3], fraction: lead/27.43)
        let turn = max(flight, lead/DetailedFieldRules.runnerVelocity(second)) + 0.18 + (100-context.read(second))*0.002
        let returned = turn + lead/DetailedFieldRules.runnerVelocity(second)
        let thirdAt = firstStart + (27.43-lead)/DetailedFieldRules.runnerVelocity(second)
        let thirdTag = release + bags[0].distance(to: bags[3])/catcher.throwVelocity + 0.3 - skills[4].defense*0.0015
        let notice = returned + 0.2 + (100-context.read(first))*0.012
        guard thirdAt > thirdTag, returned < firstAt, notice >= firstAt, firstAt < arrive else { return nil }
        let final = arrive + 0.3 - receiver.defense*0.0015 + receiver.transfer*0.5
        var moves = context.before.runners.enumerated().compactMap { index, runner in runner.map {
            DetailedRunner(from: index+1, destination: index+1, profile: $0, nodes: [.init(at: 0, point: bags[index+1])])
        }}
        moves[0].destination = 2
        moves[0].nodes = [.init(at: 0, point: bags[1].towards(bags[2], fraction: 4.5/27.43)),
                          .init(at: firstStart, point: bags[1].towards(bags[2], fraction: 4.5/27.43)),
                          .init(at: firstAt, point: bags[2]), .init(at: final, point: bags[2])]
        moves[1].nodes = [.init(at: 0, point: bags[2]), .init(at: flight, point: leadPoint),
                          .init(at: turn, point: leadPoint), .init(at: returned, point: bags[2]), .init(at: final, point: bags[2])]
        var paths = positions.map { [FieldNode(at: 0, point: $0)] }
        paths[1] += [.init(at: flight, point: bags[0]), .init(at: release, point: bags[0])]
        paths[3] += [.init(at: arrive, point: bags[2]), .init(at: final, point: bags[2])]
        let source = MatchDetailedPlay(version: 5, half: context.before.half, order: context.before.order,
            landing: bags[0], flight: 0, fielder: 1, receiver: 3, ownDefense: context.defending, ownBatter: false,
            appliedTraits: [], positionDelay: 0, pickupAt: flight, releaseAt: release, ballAt: arrive,
            controlAt: final, targetBase: 2, targetRunner: 1, force: false, out: false, runnerAt: firstAt,
            runners: moves, ball: [.init(at: 0, point: positions[0]), .init(at: flight, point: bags[0]),
                                  .init(at: release, point: bags[0]), .init(at: arrive, point: bags[2])],
            fielders: paths, afterRunners: context.before.runners, runs: 0, outsAdded: 0, hitBases: 0,
            outsBefore: context.before.outs, runningEvent: .init(id: id, kind: .steal, settledAt: final, turnAt: turn))
        guard var result = shared(source, intents: moves, context: context) else { return nil }
        result.runningEvent = .init(id: id, kind: .steal, settledAt: result.special!.settledAt, turnAt: turn)
        return result
    }
}

extension CareerMatch {
    mutating func enableSpecialPlays() {
        guard specialRulesVersion == nil, fieldReviewVersion == 1, playerRecords != nil,
              half == 0, homeOrder == 0, awayOrder == 0, fieldPlays?.isEmpty == true else { return }
        specialRulesVersion = 1
    }

    mutating func resolveSharedPitch(before: MatchPitchState, eventCount: Int, fieldCount: Int, homeRunCount: Int, pitchFlight: Double) {
        guard specialRulesVersion == 1, running != nil, !completed, before.half == half,
              before.homeOrder == homeOrder, before.awayOrder == awayOrder,
              before.runners == runnerProfiles, before.runners[0]?.own == false,
              pitchEvents?.events.count == eventCount, fieldPlays?.count == fieldCount, homeRuns?.count == homeRunCount else { return }
        let movement = MatchPitchState(self)
        let source = MatchSpecialRules.context(match: self, ball: nil, batter: nil)
        let inputs = MatchSpecialContext(before:source.before,ball:nil,batter:nil,stats:source.stats,npc:source.npc,
            defending:source.defending,ownBatter:source.ownBatter,discipline:source.discipline,
            pitchDuration:pitchFlight,runningID:"running:\((running?.events.count ?? 0)+1)")
        if let play = MatchSpecialRules.sharedPitch(inputs) { applyRunning(play, before: before, movement: movement) }
    }

    func validateSpecialPlays() throws {
        let plays = (fieldPlays ?? []) + (running?.events.map(\.play) ?? [])
        guard specialRulesVersion == nil || specialRulesVersion == 1 && fieldReviewVersion == 1 && playerRecords != nil,
              specialRulesVersion != nil || !plays.contains(where: { $0.special != nil }) else { throw MatchError.invalidRecord }
        for play in plays {
            guard let event = play.special else { continue }
            try validateFieldContext(event.context, play: play)
        }
    }
    func validateFieldContext(_ context: MatchSpecialContext, play: MatchDetailedPlay) throws {
        var frame = self
        frame.half = play.half
        frame.homeOrder = context.before.homeOrder; frame.awayOrder = context.before.awayOrder
        frame.runnerManagement?.changes = (runnerManagement?.changes ?? []).filter {
            $0.half < play.half || $0.half == play.half && $0.order <= context.before.order
        }
        let change = pitching?.change(home: isHome)
        let ownActive = change.map { play.half < $0.half || play.half == $0.half && context.before.order < $0.order } ?? true
        let expectedDefense = (play.half % 2 == 1) != isHome && appearance && (role != "pitcher" || ownActive)
        guard context.stats == fieldStats, context.before.half == play.half, context.before.order == play.order,
              context.npc == frame.npcDefenders, context.defending == expectedDefense,
              context.ownBatter == (context.batter?.own == true),
              context.before.ids.compactMap({ $0 }).allSatisfy({ id in
                  let attack = play.half % 2 == 1 ? playerRecords?.home : playerRecords?.away
                  return attack?.batting.contains(where: { $0.id == id }) == true
              }) else { throw MatchError.invalidRecord }
        if context.ball != nil, let traces = playerRecords?.plateTrace {
            guard let trace = traces.first(where: { $0.half == play.half && $0.order == play.order }),
                  trace.batter == context.batter?.id, trace.outsBefore == context.before.outs,
                  trace.beforeHome == context.before.home, trace.beforeAway == context.before.away,
                  trace.beforeRunners == context.before.ids,
                  trace.afterRunners == play.review?.after?.ids else { throw MatchError.invalidRecord }
        }
        for runner in context.before.runners.compactMap({ $0 }) + [context.batter].compactMap({ $0 }) {
            guard let id = runner.id else { throw MatchError.invalidRecord }
            let reserve = runnerManagement?.reserve(home: play.half % 2 == 1)
            let expected = id == playerRecords?.careerID.uuidString ? discipline : reserve?.id == id ? reserve!.discipline
                : npcAttack?.team(home: play.half % 2 == 1).batters.first { $0.id == id }?.discipline ?? 60
            guard context.discipline[id] == expected else { throw MatchError.invalidRecord }
        }
    }

}
