import Foundation

struct MatchFieldStats: Codable, Equatable {
    var version = 1
    let speed: Double
    let defense: Double
    let arm: Double
    let position: String
    var activeTraits: [PlayerTrait]?
    var positionMastery: Double?
}

struct MatchFieldPlay: Codable, Equatable {
    let runnerTime: Double
    let ballTime: Double
    let ownDefense: Bool
    var appliedTraits: [PlayerTrait]?
    var positionDelay: Double?
    var caughtFly: Bool?
    var safe: Bool { caughtFly == true ? false : runnerTime <= ballTime }
}

// First-base races only. Existing matches without this snapshot keep their original rules.
enum MatchFieldRules {
    static func firstBase(runnerSpeed: Double, fielderSpeed: Double, defense: Double, arm: Double,
                          chase: Double, distance: Double, ownDefense: Bool) -> MatchFieldPlay {
        func stat(_ value: Double) -> Double { max(0, min(100, value)) }
        let runner = 27.43 / (5.5 + stat(runnerSpeed) * 0.035)
        let retrieve = chase / (4 + stat(fielderSpeed) * 0.03) + 1 - stat(defense) * 0.006
        let ball = retrieve + distance / (18 + stat(arm) * 0.18)
        return MatchFieldPlay(runnerTime: runner, ballTime: ball, ownDefense: ownDefense)
    }
}


extension MatchFieldRules {
    static func applyingPosition(_ play: MatchFieldPlay, mastery: Double) -> MatchFieldPlay {
        guard play.ownDefense else { return play }
        let delay = 0.25 * (1 - min(100, max(0, mastery)) / 100)
        return MatchFieldPlay(runnerTime: play.runnerTime, ballTime: play.ballTime + delay, ownDefense: true,
                              appliedTraits: play.appliedTraits, positionDelay: delay)
    }
    static func firstBaseV2(runnerSpeed: Double, fielderSpeed: Double, defense: Double, arm: Double,
                            chase: Double, distance: Double, ownDefense: Bool, active: [PlayerTrait]) -> MatchFieldPlay {
        func stat(_ value: Double) -> Double { max(0, min(100, value)) }
        let runnerTraits = ownDefense ? [] : active.filter { $0 == .cheetah }
        let defenseTraits = ownDefense ? active : []
        let start = (0.32 + (100 - stat(runnerSpeed)) * 0.002) * (runnerTraits.contains(.cheetah) ? 0.92 : 1)
        let runner = start + 27.43 / (5.5 + stat(runnerSpeed) * 0.035)
        let reaction = (0.58 - stat(defense) * 0.004) * (defenseTraits.contains(.cheetah) ? 0.92 : 1)
        let pickup = (0.32 - stat(defense) * 0.002) * (defenseTraits.contains(.safeHands) ? 0.90 : 1)
        let transfer = 0.6 - stat(defense) * 0.0035
        let throwTime = distance / ((18 + stat(arm) * 0.18) * (defenseTraits.contains(.strongArm) ? 1.05 : 1))
        let ball = reaction + chase / (4 + stat(fielderSpeed) * 0.03) + pickup + transfer + throwTime
        return MatchFieldPlay(runnerTime: runner, ballTime: ball, ownDefense: ownDefense, appliedTraits: ownDefense ? defenseTraits : runnerTraits)
    }
}

struct FieldPoint: Codable, Equatable {
    var x: Double
    var y: Double
    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
    func towards(_ other: Self, fraction: Double) -> Self {
        let t = min(1, max(0, fraction))
        if t == 0 { return self }; if t == 1 { return other }
        return Self(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }
}
struct FieldNode: Codable, Equatable {
    let at: Double
    let point: FieldPoint
    static func sample(_ nodes: [Self], at time: Double) -> FieldPoint {
        guard let first = nodes.first else { return FieldPoint(x: 0, y: 0) }
        var previous = first
        for next in nodes.dropFirst() {
            if time <= next.at { return previous.point.towards(next.point, fraction: (time - previous.at) / max(0.000001, next.at - previous.at)) }
            previous = next
        }
        return previous.point
    }
}
struct FieldRunnerProfile: Codable, Equatable {
    let speed: Double
    var traits: [PlayerTrait] = []
    var own = false
}
struct DetailedRunner: Codable, Equatable {
    let from: Int
    var destination: Int
    let profile: FieldRunnerProfile
    var nodes: [FieldNode]
    var out = false
    var retiredAt: Double?
    var arrival: Double { nodes.last?.at ?? 0 }
    func arrival(at base: Int) -> Double? { nodes.dropFirst().first { $0.point == DetailedFieldRules.bases[base] }?.at }
}
struct FieldSecondThrow: Codable, Equatable {
    let receiver: Int
    let releaseAt: Double
    let ballAt: Double
    let controlAt: Double
    let runnerAt: Double
    let ownThrower: Bool
    let traits: [PlayerTrait]
    let positionDelay: Double
    var out: Bool { controlAt < runnerAt }
    var decisionAt: Double { out ? controlAt : max(controlAt,runnerAt) }
}

struct FieldFlyPlay: Codable, Equatable {
    let caught: Bool
    let reachAt: Double
}

struct MatchDetailedPlay: Codable, Equatable {
    var version = 1
    let half: Int
    let order: Int
    let landing: FieldPoint
    let flight: Double
    let fielder: Int
    let receiver: Int
    let ownDefense: Bool
    let ownBatter: Bool
    let appliedTraits: [PlayerTrait]
    let positionDelay: Double
    let pickupAt: Double
    let releaseAt: Double
    let ballAt: Double
    let controlAt: Double
    let targetBase: Int
    let targetRunner: Int?
    let force: Bool
    let out: Bool
    let runnerAt: Double?
    var runners: [DetailedRunner]
    let ball: [FieldNode]
    let fielders: [[FieldNode]]
    let afterRunners: [FieldRunnerProfile?]
    let runs: Int
    let outsAdded: Int
    let hitBases: Int
    var secondThrow: FieldSecondThrow?
    var outsBefore: Int?
    var doublePlayGrounder: Bool?
    var fly: FieldFlyPlay?
    var sacrificeFly: Bool { fly?.caught == true && fielder >= 6 && runs > 0 && (outsBefore ?? 2) < 2 }
    var ownParticipation: Bool { ownDefense || secondThrow?.ownThrower == true }
    var outAt: Double { fly?.caught == true ? controlAt : force ? controlAt : runnerAt ?? controlAt }
    var decisionAt: Double { secondThrow?.decisionAt ?? (out ? outAt : max(controlAt,runnerAt ?? 0)) }
    var duration: Double { max(decisionAt, runners.map(\.arrival).max() ?? 0) + 0.4 }
    var rbi: Int { fly?.caught == true ? runs : secondThrow != nil || out && force && targetRunner != 0 ? 0 : runs }
    var eventID: String { "\(half):\(order)" }
    var summary: String {
        if let fly,fly.caught {
            let caught="\(DetailedFieldRules.names[fielder]) 뜬공 포구"
            guard let targetRunner else { return caught + ((outsBefore ?? 0) == 2 ? " · 이닝 종료" : " · 주자 대기") }
            return caught + " · 태그업 \(targetRunner)루→\(targetBase == 4 ? "홈" : "\(targetBase)루") \(out ? "아웃" : "세이프")"
        }
        if let secondThrow { return secondThrow.out ? "병살 · 2루 아웃 → 1루 아웃" : "병살 무산 · 2루 아웃 → 1루 세이프" }
        let hit = hitBases == 2 ? "2루타" : hitBases == 1 ? "안타" : out && targetRunner != 0 ? "야수 선택" : "땅볼 아웃"
        return (fly != nil ? "뜬공 낙하 · " : "") + "\(hit) · \(targetBase == 4 ? "홈" : "\(targetBase)루") 송구 · \(targetRunner == nil ? "주자 진루 완료" : out ? "아웃" : "세이프")"
    }
    var xpPlay: MatchFieldPlay {
        if fly?.caught == true {
            return MatchFieldPlay(runnerTime:flight,ballTime:fly?.reachAt ?? flight,ownDefense:ownDefense,
                appliedTraits:appliedTraits,positionDelay:ownDefense ? positionDelay : nil,caughtFly:true)
        }
        if let secondThrow, secondThrow.ownThrower || ownBatter {
            return MatchFieldPlay(runnerTime:secondThrow.runnerAt,ballTime:secondThrow.controlAt,ownDefense:secondThrow.ownThrower,
                appliedTraits:secondThrow.ownThrower ? secondThrow.traits : appliedTraits,positionDelay:secondThrow.ownThrower ? secondThrow.positionDelay : nil)
        }
        return MatchFieldPlay(runnerTime: runnerAt ?? controlAt, ballTime: controlAt, ownDefense: ownDefense,
                       appliedTraits: appliedTraits, positionDelay: ownDefense ? positionDelay : nil)
    }
    func validate() throws {
        guard [1,2,3].contains(version), (0..<18).contains(half), order >= 0, (0..<9).contains(fielder), (0..<9).contains(receiver),
              fielder != receiver, (1...4).contains(targetBase), (0...2).contains(outsAdded), outsAdded == (out ? 1 : 0) + (secondThrow?.out == true ? 1 : 0) + (fly?.caught == true ? 1 : 0),
              (0...2).contains(hitBases), (0...4).contains(runs), afterRunners.count == 3, fielders.count == 9,
              [flight,pickupAt,releaseAt,ballAt,controlAt,positionDelay].allSatisfy({ $0.isFinite && $0 >= 0 }),
              flight <= pickupAt, pickupAt <= releaseAt, releaseAt <= ballAt, ballAt <= controlAt,
              TraitLoadout.valid(appliedTraits), Set(runners.map(\.from)).count == runners.count,
              runners.contains(where: { $0.from == 0 }),
              out == (runnerAt.map { controlAt < $0 } ?? false) else { throw MatchError.invalidRecord }
        if version >= 2 {
            guard let outsBefore,(0...2).contains(outsBefore),doublePlayGrounder != nil,outsBefore+outsAdded <= 3 else { throw MatchError.invalidRecord }
        } else if secondThrow != nil || outsBefore != nil || doublePlayGrounder != nil { throw MatchError.invalidRecord }
        if let fly {
            guard version == 3,fly.reachAt.isFinite,fly.reachAt >= 0,secondThrow == nil,doublePlayGrounder == false,
                  fly.caught == (fly.reachAt <= flight) else { throw MatchError.invalidRecord }
            if fly.caught {
                guard hitBases == 0,!force,outsAdded >= 1,pickupAt == flight,
                      runners.contains(where:{ $0.from == 0 && $0.out && $0.retiredAt == flight }),
                      targetRunner == nil || (outsBefore ?? 2) < 2,
                      outsBefore != 2 || runs == 0 && afterRunners.allSatisfy({ $0 == nil }),
                      targetRunner != nil || !out,
                      runners.filter({ $0.from > 0 }).allSatisfy({
                          $0.destination == $0.from || $0.destination == $0.from+1
                      }) else { throw MatchError.invalidRecord }
                if let targetRunner {
                    guard (1...3).contains(targetRunner),targetBase == targetRunner+1,
                          runnerAt.map({ $0 > flight }) == true,
                          ball.last?.point == DetailedFieldRules.bases[targetBase],ball.last?.at == ballAt,
                          runners.contains(where:{ $0.from == targetRunner && $0.destination == targetBase && $0.out == out && $0.retiredAt == (out ? controlAt:nil) }) else { throw MatchError.invalidRecord }
                } else {
                    guard ballAt == flight,controlAt == flight,runners.filter({ $0.from > 0 }).allSatisfy({ $0.destination == $0.from }) else { throw MatchError.invalidRecord }
                }
                var projected:[FieldRunnerProfile?]=[nil,nil,nil]
                var scored=0
                let third=(outsBefore ?? 0)+outsAdded == 3
                for runner in runners where !runner.out {
                    if runner.destination == 4 {
                        if !third || runner.arrival < outAt { scored += 1 }
                    } else {
                        guard (1...3).contains(runner.destination),projected[runner.destination-1] == nil else { throw MatchError.invalidRecord }
                        projected[runner.destination-1]=runner.profile
                    }
                }
                guard runs == scored,afterRunners == (third ? [nil,nil,nil]:projected) else { throw MatchError.invalidRecord }
                for runner in runners where runner.from > 0 {
                    guard runner.nodes.first?.point == DetailedFieldRules.bases[runner.from],
                          runner.nodes.contains(where:{ $0.at == flight && $0.point == DetailedFieldRules.bases[runner.from] }),
                          runner.nodes.filter({ $0.at <= flight }).allSatisfy({ $0.point == DetailedFieldRules.bases[runner.from] }) else { throw MatchError.invalidRecord }
                }
            }
        }
        if let secondThrow {
            guard version >= 2,outsBefore.map({ $0 < 2 }) == true,doublePlayGrounder == true,
                  [0,3,4,5].contains(fielder),targetBase == 2,targetRunner == 1,force,out,
                  secondThrow.receiver == 2,secondThrow.receiver != receiver,
                  [secondThrow.releaseAt,secondThrow.ballAt,secondThrow.controlAt,secondThrow.runnerAt,secondThrow.positionDelay].allSatisfy({ $0.isFinite && $0 >= 0 }),
                  controlAt <= secondThrow.releaseAt,secondThrow.releaseAt <= secondThrow.ballAt,secondThrow.ballAt == secondThrow.controlAt,
                  TraitLoadout.valid(secondThrow.traits),hitBases == 0,!(ownDefense && secondThrow.ownThrower),
                  ball.last?.at == secondThrow.ballAt,ball.last?.point == DetailedFieldRules.bases[1],
                  runners.contains(where: { $0.from == 1 && $0.out && $0.retiredAt == controlAt }),
                  runners.contains(where: { $0.from == 0 && $0.out == secondThrow.out && $0.retiredAt == (secondThrow.out ? secondThrow.controlAt : nil) }),
                  outsBefore != 1 || !secondThrow.out || runs == 0 && afterRunners.allSatisfy({ $0 == nil }) else { throw MatchError.invalidRecord }
        }
        for nodes in [ball] + fielders + runners.map(\.nodes) {
            guard !nodes.isEmpty, nodes.allSatisfy({ $0.at.isFinite && $0.at >= 0 && $0.point.x.isFinite && $0.point.y.isFinite }),
                  zip(nodes,nodes.dropFirst()).allSatisfy({ $0.at <= $1.at }) else { throw MatchError.invalidRecord }
        }
        for runner in runners {
            if let retiredAt=runner.retiredAt {
                guard version >= 2,runner.out,retiredAt.isFinite,retiredAt >= 0 else { throw MatchError.invalidRecord }
            }
            guard (0...3).contains(runner.from), (runner.from...4).contains(runner.destination),
                  runner.profile.speed.isFinite, (0...100).contains(runner.profile.speed), TraitLoadout.valid(runner.profile.traits) else { throw MatchError.invalidRecord }
        }
        if let targetRunner { guard runners.contains(where: { $0.from == targetRunner }) else { throw MatchError.invalidRecord } }
    }
}

enum DetailedFieldRules {
    static let diagonal = 27.43 / sqrt(2.0)
    static let bases = [FieldPoint(x:0,y:0), FieldPoint(x:diagonal,y:diagonal), FieldPoint(x:0,y:diagonal*2), FieldPoint(x:-diagonal,y:diagonal), FieldPoint(x:0,y:0)]
    static let positions = [FieldPoint(x:0,y:18),FieldPoint(x:0,y:-3),FieldPoint(x:20,y:22),FieldPoint(x:10,y:35),FieldPoint(x:-20,y:22),FieldPoint(x:-10,y:35),FieldPoint(x:-32,y:62),FieldPoint(x:0,y:73),FieldPoint(x:32,y:62)]
    static let names = ["P","C","1B","2B","3B","SS","LF","CF","RF"]
    static func clamp(_ stat: Double) -> Double { min(100,max(0,stat)) }
    struct Skill {
        var speed = 60.0, defense = 60.0, arm = 60.0
        var traits: [PlayerTrait] = []
        var positionDelay = 0.0
        var reaction: Double { (0.58 - defense * 0.004) * (traits.contains(.cheetah) ? 0.92 : 1) + positionDelay }
        var pickup: Double { (0.32 - defense * 0.002) * (traits.contains(.safeHands) ? 0.9 : 1) }
        var velocity: Double { 4 + speed * 0.03 }
        var throwVelocity: Double { (18 + arm * 0.18) * (traits.contains(.strongArm) ? 1.05 : 1) }
        var transfer: Double { 0.6 - defense * 0.0035 }
    }
    private struct Throw {
        let base: Int, receiver: Int
        let release: Double, ball: Double, control: Double
    }
    static func resolve(half: Int, order: Int, landing: FieldPoint, flight: Double, runners before: [FieldRunnerProfile?],
                        batter: FieldRunnerProfile, outs: Int, stats: MatchFieldStats?, defending: Bool, ownBatter: Bool,
                        doublePlayEnabled: Bool = false, groundBall: Bool = true) -> MatchDetailedPlay {
        let ownIndex = defending ? names.firstIndex(of: stats?.position ?? "") : nil
        let skills = names.indices.map { index -> Skill in
            guard index == ownIndex, let stats else { return Skill() }
            return Skill(speed:clamp(stats.speed),defense:clamp(stats.defense),arm:clamp(stats.arm),traits:stats.activeTraits ?? [],
                         positionDelay:stats.positionMastery.map { 0.25 * (1 - clamp($0)/100) } ?? 0)
        }
        let handler = names.indices.min {
            max(flight, skills[$0].reaction + positions[$0].distance(to:landing)/skills[$0].velocity) + skills[$0].pickup <
            max(flight, skills[$1].reaction + positions[$1].distance(to:landing)/skills[$1].velocity) + skills[$1].pickup
        }!
        let skill = skills[handler]
        let pickup = max(flight, skill.reaction + positions[handler].distance(to:landing)/skill.velocity) + skill.pickup
        func planThrow(_ base: Int, force: Bool) -> Throw {
            let candidates = base == 1 ? [2,0,3] : base == 2 ? [3,5,0] : base == 3 ? [4,5,0] : [1,0,2]
            let receiver = candidates.first { $0 != handler }!
            let travel = landing.distance(to:bases[base])/skill.throwVelocity
            let cover = skills[receiver].reaction + positions[receiver].distance(to:bases[base])/skills[receiver].velocity
            let release = max(pickup + skill.transfer, cover - travel)
            let ball = release + travel
            return Throw(base:base,receiver:receiver,release:release,ball:ball,control:ball + (force ? 0 : 0.3 - skills[receiver].defense*0.0015))
        }
        func forced(_ from: Int, _ base: Int) -> Bool {
            base == from + 1 && (from == 0 || before.prefix(from).allSatisfy { $0 != nil })
        }
        var runners: [DetailedRunner] = []
        for from in stride(from:3,through:0,by:-1) {
            guard let profile = from == 0 ? batter : before[from-1] else { continue }
            let lead = runners.last
            let maximum = min(from == 0 ? 2 : 4, lead.map { $0.destination < 4 ? $0.destination-1 : 4 } ?? 4)
            let delay = ((from == 0 ? 0.32 : 0.18) + (100-profile.speed)*0.002) * (profile.traits.contains(.cheetah) ? 0.92 : 1)
            let step = 27.43/(5.5+profile.speed*0.035)
            var runner = DetailedRunner(from:from,destination:from,profile:profile,nodes:[FieldNode(at:0,point:bases[from]),FieldNode(at:delay,point:bases[from])])
            if maximum > from {
                for base in (from+1)...maximum {
                    let arrival = max(delay + Double(base-from)*step, (lead?.arrival(at:base)).map { $0+0.25 } ?? 0)
                    if !forced(from,base), planThrow(base,force:false).control + 0.35 < arrival { break }
                    runner.destination=base;runner.nodes.append(FieldNode(at:arrival,point:bases[base]))
                }
            }
            runners.append(runner)
        }
        var candidates: [(runner:Int,at:Double,force:Bool,plan:Throw,priority:Double)] = []
        for (index,runner) in runners.enumerated() where runner.destination > runner.from {
            for base in (runner.from+1)...runner.destination {
                guard let arrival=runner.arrival(at:base), arrival > pickup else { continue }
                let force=forced(runner.from,base),plan=planThrow(base,force:force),margin=arrival-plan.control
                let priority = margin > 0 ? 100 + min(3,margin)*5 + (outs < 2 && base == 4 ? 8 : 0) : -20 + Double(base)*2 + margin
                candidates.append((index,arrival,force,plan,priority))
            }
        }
        var chosen=candidates.max { $0.priority < $1.priority }
        var secondThrow: FieldSecondThrow?
        if doublePlayEnabled,groundBall,outs < 2,before[0] != nil,[0,3,4,5].contains(handler),
           let first=candidates.first(where: { $0.plan.base == 2 && runners[$0.runner].from == 1 && $0.force && $0.plan.control < $0.at }),
           let batterAt=runners.first(where: { $0.from == 0 })?.arrival(at:1) {
            let pivot=first.plan.receiver,firstBase=2
            let travel=bases[2].distance(to:bases[1])/skills[pivot].throwVelocity
            let cover=skills[firstBase].reaction+positions[firstBase].distance(to:bases[1])/skills[firstBase].velocity
            let release=max(first.plan.control+skills[pivot].transfer,cover-travel)
            let next=FieldSecondThrow(receiver:firstBase,releaseAt:release,ballAt:release+travel,controlAt:release+travel,
                runnerAt:batterAt,ownThrower:pivot == ownIndex,traits:skills[pivot].traits,positionDelay:skills[pivot].positionDelay)
            if next.out || chosen.map({ $0.runner == first.runner && $0.plan.base == 2 }) == true {
                chosen=first;secondThrow=next
            }
        }
        let plan=chosen?.plan ?? planThrow(2,force:false)
        let out=chosen.map { $0.plan.control < $0.at } ?? false
        let outAt=chosen?.force == true ? plan.control : chosen?.at ?? plan.control
        if out,let chosen {
            let index=chosen.runner
            runners[index].out=true;runners[index].destination=plan.base
            if doublePlayEnabled { runners[index].retiredAt=outAt }
            let stopped=FieldNode.sample(runners[index].nodes,at:outAt)
            runners[index].nodes=runners[index].nodes.filter { $0.at < outAt }
            runners[index].nodes.append(FieldNode(at:outAt,point:stopped))
        }
        if let secondThrow,let index=runners.firstIndex(where: { $0.from == 0 }) {
            let stop=secondThrow.out ? secondThrow.controlAt : secondThrow.runnerAt
            let point=FieldNode.sample(runners[index].nodes,at:stop)
            runners[index].destination=1;runners[index].out=secondThrow.out
            runners[index].retiredAt=secondThrow.out ? stop : nil
            runners[index].nodes=runners[index].nodes.filter { $0.at < stop }
            runners[index].nodes.append(FieldNode(at:stop,point:point))
        }
        let batterRunner=runners.first { $0.from == 0 }!
        let batterOutBeforeFirst=out && chosen.map { runners[$0.runner].from == 0 && plan.base == 1 } == true
        let forceChoice=out && chosen?.force == true && chosen.map { runners[$0.runner].from != 0 } == true
        let hitBases = secondThrow != nil || batterOutBeforeFirst || forceChoice ? 0 : min(2,batterRunner.out ? max(1,plan.base-1) : batterRunner.destination)
        let outsAdded=(out ? 1 : 0)+(secondThrow?.out == true ? 1 : 0)
        let thirdOut=outs+outsAdded == 3
        let inningOutAt=secondThrow?.out == true ? secondThrow!.controlAt : outAt
        let cancelRuns=thirdOut && (secondThrow?.out == true || chosen?.force == true || batterOutBeforeFirst)
        var after: [FieldRunnerProfile?] = [nil,nil,nil]
        var runs=0
        for runner in runners where !runner.out {
            if runner.destination == 4 {
                if !cancelRuns && (!thirdOut || runner.arrival < inningOutAt) { runs += 1 }
            } else if runner.destination > 0 { after[runner.destination-1]=runner.profile }
        }
        if thirdOut { after=[nil,nil,nil] }
        if thirdOut {
            for index in runners.indices where runners[index].arrival > inningOutAt {
                let stopped=FieldNode.sample(runners[index].nodes,at:inningOutAt)
                runners[index].nodes=runners[index].nodes.filter { $0.at < inningOutAt }
                runners[index].nodes.append(FieldNode(at:inningOutAt,point:stopped))
            }
        }
        var fielderNodes=positions.map { [FieldNode(at:0,point:$0)] }
        fielderNodes[handler].append(FieldNode(at:skill.reaction,point:positions[handler]))
        fielderNodes[handler].append(FieldNode(at:skill.reaction+positions[handler].distance(to:landing)/skill.velocity,point:landing))
        fielderNodes[handler].append(FieldNode(at:pickup,point:landing))
        let cover=skills[plan.receiver].reaction+positions[plan.receiver].distance(to:bases[plan.base])/skills[plan.receiver].velocity
        fielderNodes[plan.receiver].append(FieldNode(at:skills[plan.receiver].reaction,point:positions[plan.receiver]))
        fielderNodes[plan.receiver].append(FieldNode(at:cover,point:bases[plan.base]))
        if let secondThrow {
            let index=secondThrow.receiver
            let cover=skills[index].reaction+positions[index].distance(to:bases[1])/skills[index].velocity
            fielderNodes[index].append(FieldNode(at:skills[index].reaction,point:positions[index]))
            fielderNodes[index].append(FieldNode(at:cover,point:bases[1]))
        }
        // Receiving alone or backing up does not award extra XP.
        for index in positions.indices where index != handler && index != plan.receiver && index != secondThrow?.receiver {
            fielderNodes[index].append(FieldNode(at:pickup,point:positions[index].towards(landing,fraction:0.12)))
        }
        var ballNodes=[FieldNode(at:0,point:bases[0]),FieldNode(at:flight,point:landing),FieldNode(at:plan.release,point:landing),FieldNode(at:plan.ball,point:bases[plan.base])]
        if let secondThrow {
            ballNodes.append(FieldNode(at:secondThrow.releaseAt,point:bases[2]))
            ballNodes.append(FieldNode(at:secondThrow.ballAt,point:bases[1]))
        }
        return MatchDetailedPlay(version:doublePlayEnabled ? 2 : 1,half:half,order:order,landing:landing,flight:flight,fielder:handler,receiver:plan.receiver,
            ownDefense:handler == ownIndex,ownBatter:ownBatter,appliedTraits:handler == ownIndex ? skill.traits : ownBatter ? batter.traits.filter { $0 == .cheetah } : [],positionDelay:skill.positionDelay,
            pickupAt:pickup,releaseAt:plan.release,ballAt:plan.ball,controlAt:plan.control,targetBase:plan.base,
            targetRunner:chosen.map { runners[$0.runner].from },force:chosen?.force ?? false,out:out,runnerAt:chosen?.at,
            runners:runners,ball:ballNodes,fielders:fielderNodes,
            afterRunners:after,runs:runs,outsAdded:outsAdded,hitBases:hitBases,secondThrow:secondThrow,
            outsBefore:doublePlayEnabled ? outs : nil,doublePlayGrounder:doublePlayEnabled ? groundBall : nil)
    }
}

extension CareerMatch {
    func validateDetailedField() throws {
        if let version=detailedFieldVersion {
            guard [1,2,3].contains(version), let plays=fieldPlays, let runners=runnerProfiles,runners.count == 3,
                  runners.map({ $0 != nil }) == bases,Set(plays.map(\.eventID)).count == plays.count else { throw MatchError.invalidRecord }
            for runner in runners.compactMap({ $0 }) {
                guard runner.speed.isFinite,(0...100).contains(runner.speed),TraitLoadout.valid(runner.traits) else { throw MatchError.invalidRecord }
            }
            for play in plays { guard play.version == version else { throw MatchError.invalidRecord };try play.validate() }
        } else if fieldPlays != nil || runnerProfiles != nil { throw MatchError.invalidRecord }
    }
}

extension DetailedFieldRules {
    // A caught fly removes the force. Runners wait on their original bag, then attempt one base.
    static func resolveFly(half:Int,order:Int,landing:FieldPoint,flight:Double,runners before:[FieldRunnerProfile?],
                           batter:FieldRunnerProfile,outs:Int,stats:MatchFieldStats?,defending:Bool,ownBatter:Bool) -> MatchDetailedPlay {
        let ownIndex=defending ? names.firstIndex(of:stats?.position ?? "") : nil
        let skills=names.indices.map { index -> Skill in
            guard index == ownIndex,let stats else { return Skill() }
            return Skill(speed:clamp(stats.speed),defense:clamp(stats.defense),arm:clamp(stats.arm),traits:stats.activeTraits ?? [],
                         positionDelay:stats.positionMastery.map { 0.25*(1-clamp($0)/100) } ?? 0)
        }
        func reach(_ index:Int) -> Double { skills[index].reaction + positions[index].distance(to:landing)/skills[index].velocity + skills[index].pickup }
        let handler=names.indices.min { reach($0) < reach($1) }!,skill=skills[handler],reachAt=reach(handler)
        guard reachAt <= flight else {
            var dropped=resolve(half:half,order:order,landing:landing,flight:flight,runners:before,batter:batter,outs:outs,
                                stats:stats,defending:defending,ownBatter:ownBatter,doublePlayEnabled:true,groundBall:false)
            dropped.version=3;dropped.fly=FieldFlyPlay(caught:false,reachAt:reachAt)
            return dropped
        }
        func throwTo(_ base:Int) -> Throw {
            let candidates=base == 2 ? [3,5,0] : base == 3 ? [4,5,0] : [1,0,2]
            let receiver=candidates.first { $0 != handler }!,travel=landing.distance(to:bases[base])/skill.throwVelocity
            let cover=skills[receiver].reaction+positions[receiver].distance(to:bases[base])/skills[receiver].velocity
            let release=max(flight+skill.transfer,cover-travel),ball=release+travel
            return Throw(base:base,receiver:receiver,release:release,ball:ball,control:ball+0.3-skills[receiver].defense*0.0015)
        }
        var runners:[DetailedRunner]=[]
        var attempts:[(from:Int,at:Double,plan:Throw)]=[]
        var blocked=false
        for from in stride(from:3,through:1,by:-1) {
            guard let profile=before[from-1] else { blocked=false;continue }
            let delay=(0.18+(100-clamp(profile.speed))*0.002)*(profile.traits.contains(.cheetah) ? 0.92:1)
            let arrival=flight+delay+27.43/(5.5+clamp(profile.speed)*0.035),plan=throwTo(from+1)
            let advance=outs < 2 && !blocked && arrival <= plan.control+0.25
            let nodes=advance ? [FieldNode(at:0,point:bases[from]),FieldNode(at:flight,point:bases[from]),
                FieldNode(at:flight+delay,point:bases[from]),FieldNode(at:arrival,point:bases[from+1])]
                : [FieldNode(at:0,point:bases[from]),FieldNode(at:flight,point:bases[from])]
            runners.append(DetailedRunner(from:from,destination:advance ? from+1:from,profile:profile,nodes:nodes))
            if advance { attempts.append((from,arrival,plan)) }
            blocked = !advance
        }
        let chosen=attempts.max {
            let a=($0.plan.control < $0.at ? 100.0:0)+Double($0.from)
            let b=($1.plan.control < $1.at ? 100.0:0)+Double($1.from)
            return a < b
        }
        let plan=chosen?.plan ?? throwTo(2),tagOut=chosen.map { $0.plan.control < $0.at } ?? false
        if tagOut,let chosen,let index=runners.firstIndex(where:{ $0.from == chosen.from }) {
            runners[index].out=true;runners[index].retiredAt=plan.control
            let point=FieldNode.sample(runners[index].nodes,at:plan.control)
            runners[index].nodes=runners[index].nodes.filter { $0.at < plan.control }
            runners[index].nodes.append(FieldNode(at:plan.control,point:point))
        }
        runners.append(DetailedRunner(from:0,destination:0,profile:batter,
            nodes:[FieldNode(at:0,point:bases[0]),FieldNode(at:flight,point:bases[0].towards(bases[1],fraction:0.6))],out:true,retiredAt:flight))
        let added=1+(tagOut ? 1:0),third=outs+added == 3,thirdAt=tagOut ? plan.control:flight
        var after:[FieldRunnerProfile?]=[nil,nil,nil],runs=0
        for runner in runners where !runner.out {
            if runner.destination == 4 {
                // A tag is a time play: a different runner's earlier run can count on the third out.
                if !third || runner.arrival < thirdAt { runs += 1 }
            } else { after[runner.destination-1]=runner.profile }
        }
        if third {
            after=[nil,nil,nil]
            for index in runners.indices where runners[index].arrival > thirdAt {
                let point=FieldNode.sample(runners[index].nodes,at:thirdAt)
                runners[index].nodes=runners[index].nodes.filter { $0.at < thirdAt }
                runners[index].nodes.append(FieldNode(at:thirdAt,point:point))
            }
        }
        var fielders=positions.map { [FieldNode(at:0,point:$0)] }
        fielders[handler].append(FieldNode(at:skill.reaction,point:positions[handler]))
        fielders[handler].append(FieldNode(at:reachAt-skill.pickup,point:landing))
        var ball=[FieldNode(at:0,point:bases[0]),FieldNode(at:flight,point:landing)]
        if chosen != nil {
            let receiver=plan.receiver,cover=skills[receiver].reaction+positions[receiver].distance(to:bases[plan.base])/skills[receiver].velocity
            fielders[receiver].append(FieldNode(at:skills[receiver].reaction,point:positions[receiver]))
            fielders[receiver].append(FieldNode(at:cover,point:bases[plan.base]))
            ball.append(FieldNode(at:plan.release,point:landing));ball.append(FieldNode(at:plan.ball,point:bases[plan.base]))
        }
        let end=chosen == nil ? flight:plan.control
        return MatchDetailedPlay(version:3,half:half,order:order,landing:landing,flight:flight,fielder:handler,receiver:plan.receiver,
            ownDefense:handler == ownIndex,ownBatter:ownBatter,appliedTraits:handler == ownIndex ? skill.traits:ownBatter ? batter.traits:[],positionDelay:skill.positionDelay,
            pickupAt:flight,releaseAt:chosen == nil ? flight:plan.release,ballAt:chosen == nil ? flight:plan.ball,controlAt:end,
            targetBase:plan.base,targetRunner:chosen?.from,force:false,out:tagOut,runnerAt:chosen?.at,
            runners:runners,ball:ball,fielders:fielders,afterRunners:after,runs:runs,outsAdded:added,hitBases:0,
            outsBefore:outs,doublePlayGrounder:false,fly:FieldFlyPlay(caught:true,reachAt:reachAt))
    }
}
