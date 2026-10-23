import Foundation

/// Versioned game-balance profiles, not real school or club player ratings.
struct MatchNPCPlayer:Codable,Equatable {
    let id:String
    let position:String
    var speed:Double
    var defense:Double
    var arm:Double
}
struct MatchNPCTeam:Codable,Equatable {
    let teamID:String
    let strength:Double
    var players:[MatchNPCPlayer]
}
struct MatchNPCFielders:Codable,Equatable {
    var version=1
    let year:Int
    let competition:String
    var home:MatchNPCTeam
    var away:MatchNPCTeam
    static func hash(_ text:String) -> UInt64 {
        text.utf8.reduce(UInt64(14695981039346656037)) {($0 ^ UInt64($1)) &* 1099511628211}
    }
    static func make(year:Int,competition:String,homeID:String,awayID:String) -> Self {
        let base=competition == "college" ? 60.0:competition == "domestic-development" ? 66:54
        let offsets:[(Double,Double,Double)]=[(-10,-4,6),(-9,5,8),(-5,3,-3),(5,6,0),(-2,3,7),(6,8,5),(3,0,0),(10,5,1),(4,1,8)]
        func team(_ id:String) -> MatchNPCTeam {
            let key="npc-v1/\(competition)/\(year)/\(id)"
            let strength=base+Double(Int(hash(key+"/team")%13)-6)
            let players=DetailedFieldRules.names.enumerated().map {index,position in
                let playerID=key+"/"+position,offset=offsets[index]
                func value(_ stat:String,_ adjustment:Double) -> Double {
                    min(95,max(20,strength+adjustment+Double(Int(hash(playerID+"/"+stat)%15)-7)))
                }
                return MatchNPCPlayer(id:playerID,position:position,speed:value("speed",offset.0),defense:value("defense",offset.1),arm:value("arm",offset.2))
            }
            return MatchNPCTeam(teamID:id,strength:strength,players:players)
        }
        return Self(year:year,competition:competition,home:team(homeID),away:team(awayID))
    }
    func team(home isHome:Bool) -> MatchNPCTeam {isHome ? home:away}
    func validate() throws {
        guard version == 1,(1...9999).contains(year),["highschool","college","domestic-development"].contains(competition),
              !home.teamID.isEmpty,!away.teamID.isEmpty,home.teamID != away.teamID else {throw MatchError.invalidRecord}
        for team in [home,away] {
            guard team.strength.isFinite,(0...100).contains(team.strength),team.players.map(\.position) == DetailedFieldRules.names,
                  team.players.allSatisfy({$0.id == "npc-v1/\(competition)/\(year)/\(team.teamID)/\($0.position)" && [$0.speed,$0.defense,$0.arm].allSatisfy {$0.isFinite && (0...100).contains($0)}}) else {throw MatchError.invalidRecord}
        }
    }
}

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
    var failedFielding: Bool?
    var safe: Bool { failedFielding == true ? true : caughtFly == true ? false : runnerTime <= ballTime }
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
    var responsiblePitcher: String?
}
/// Game balance model for fair balls, not measured ball-tracking data. Persisted only in new matches.
struct MatchBattedBall: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case ground, line, fly, bunt, buntPop
        var label: String {
            switch self {case .ground:"땅볼";case .line:"라인드라이브";case .fly:"뜬공";case .bunt:"번트 땅볼";case .buntPop:"번트 뜬공"}
        }
        var airborne: Bool { [.line,.fly,.buntPop].contains(self) }
    }
    var version = 1
    let kind: Kind
    let quality: Double
    let contact: Double
    let power: Double
    let speed: Double // metres per second at contact
    let angle: Double // launch angle in degrees
    let direction: Double // fair spray angle, zero is centre field
    let distance: Double
    let flight: Double
    var kmh: Double { speed*3.6 }
    var landing: FieldPoint {
        let radians=direction * .pi/180
        return FieldPoint(x:sin(radians)*distance,y:cos(radians)*distance)
    }
    func point(at time:Double) -> FieldPoint {
        let t=max(0,min(1,time/flight))
        let fraction=kind.airborne ? t+0.15*t*(1-t):(t-0.32*t*t)/0.68
        return FieldPoint(x:landing.x*fraction,y:landing.y*fraction)
    }
    func height(at time:Double) -> Double {
        let t=max(0,min(1,time/flight))
        if kind.airborne {
            let vertical=speed*sin(angle * .pi/180)
            return 4*t*(1-t)*vertical*vertical/(2*9.81)
        }
        return abs(sin(t * .pi*6))*(kind == .bunt ? 0.12:0.55)*(1-t)
    }
    var nodes: [FieldNode] { (0...24).map {let t=flight*Double($0)/24;return FieldNode(at:t,point:point(at:t))} }
    static func make(quality:Double,contact:Double,power:Double,bunt:Bool,offsetX:Double=0,offsetY:Double=0,timing:Double=0,
                     speedDraw:Double,angleDraw:Double,directionDraw:Double) -> Self {
        let q=max(0,min(1,quality)),c=DetailedFieldRules.clamp(contact),p=DetailedFieldRules.clamp(power)
        let direction=max(-28,min(28,(directionDraw-0.5)*48+timing*160+offsetX*70))
        let speed:Double,angle:Double,kind:Kind,distance:Double,flight:Double
        if bunt {
            let pop=q<0.4 && angleDraw>0.55+q
            kind=pop ? .buntPop:.bunt
            speed=4+(1-q)*7+p*0.01+(speedDraw-0.5)
            angle=pop ? 45+angleDraw*20:2+(1-q)*10
        } else {
            speed=12+p*0.16+q*15+(c-50)*0.025+(speedDraw-0.5)*4
            angle=max(-18,min(65,10+(angleDraw-0.5)*90+offsetY*70+(1-q)*12))
            kind=angle<=5 ? .ground:angle<=22 ? .line:.fly
        }
        if kind.airborne {
            flight=max(0.35,2*speed*sin(angle * .pi/180)/9.81)
            distance=min(95,speed*cos(angle * .pi/180)*flight*0.72)
        } else {
            distance=bunt ? 3+(1-q)*10+p*0.015+angleDraw*3:7+speed*1.35+p*0.12+angleDraw*12
            flight=distance/(speed*0.68)
        }
        return Self(kind:kind,quality:q,contact:c,power:p,speed:speed,angle:angle,direction:direction,distance:distance,flight:flight)
    }
    func validate(for play:MatchDetailedPlay) throws {
        guard version == 1,[quality,contact,power,speed,angle,direction,distance,flight].allSatisfy(\.isFinite),
              (0...1).contains(quality),(0...100).contains(contact),(0...100).contains(power),
              (3...48).contains(speed),(-18...65).contains(angle),(-28...28).contains(direction),
              distance>0,distance<=95,flight>0,flight<=12,abs(flight-play.flight)<0.000001,
              landing.distance(to:play.landing)<0.000001,kind.airborne == (play.fly != nil),
              kind != .bunt || play.doublePlayGrounder == false,
              play.ball.count>=nodes.count,
              zip(nodes,play.ball).allSatisfy({abs($0.at-$1.at)<0.000001 && $0.point.distance(to:$1.point)<0.000001}) else {throw MatchError.invalidRecord}
    }
}

struct DetailedRunner: Codable, Equatable {
    let from: Int
    var destination: Int
    var profile: FieldRunnerProfile
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

struct FieldRelay: Codable, Equatable {
    let fielder: Int
    let point: FieldPoint
    let readyAt: Double
    let receiveAt: Double
    let releaseAt: Double
    let directAt: Double
    let ownThrower: Bool
    let traits: [PlayerTrait]
    let positionDelay: Double
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
    var ball: [FieldNode]
    let fielders: [[FieldNode]]
    var afterRunners: [FieldRunnerProfile?]
    let runs: Int
    let outsAdded: Int
    let hitBases: Int
    var secondThrow: FieldSecondThrow?
    var outsBefore: Int?
    var doublePlayGrounder: Bool?
    var fly: FieldFlyPlay?
    var relay: FieldRelay?
    var misplay: FieldMisplay?
    var battedBall: MatchBattedBall?
    var sacrificeFly: Bool { if let misplay { return misplay.sacrificeFly }; return fly?.caught == true && fielder >= 6 && runs > 0 && (outsBefore ?? 2) < 2 }
    var ownParticipation: Bool { if let misplay { return misplay.participation }; return ownDefense || secondThrow?.ownThrower == true || relay?.ownThrower == true }
    var outAt: Double { fly?.caught == true ? controlAt : force ? controlAt : runnerAt ?? controlAt }
    var decisionAt: Double { if misplay != nil { return controlAt }; return secondThrow?.decisionAt ?? (out ? outAt : max(controlAt,runnerAt ?? 0)) }
    var duration: Double { max(decisionAt, runners.map(\.arrival).max() ?? 0) + 0.4 }
    var rbi: Int { if let misplay { return misplay.rbi }; return fly?.caught == true ? runs : secondThrow != nil || out && force && targetRunner != 0 ? 0 : runs }
    var eventID: String { "\(half):\(order)" }
    var summary: String {
        if let misplay {
            let extra=misplay.extraBases.values.reduce(0,+)
            return "\(DetailedFieldRules.names[misplay.fielder]) \(misplay.kind == .fielding ? "포구 실책" : "악송구") · \(misplay.reachedOnError ? "실책 출루 · " : "")추가 진루 \(extra)베이스"
        }
        let route=relay.map { " · \(DetailedFieldRules.names[fielder])→\(DetailedFieldRules.names[$0.fielder]) 중계" } ?? ""
        if let fly,fly.caught {
            let caught="\(DetailedFieldRules.names[fielder]) 뜬공 포구"
            guard let targetRunner else { return caught + ((outsBefore ?? 0) == 2 ? " · 이닝 종료" : " · 주자 대기") }
            return caught + route + " · 태그업 \(targetRunner)루→\(targetBase == 4 ? "홈" : "\(targetBase)루") \(out ? "아웃" : "세이프")"
        }
        if let secondThrow { return secondThrow.out ? "병살 · 2루 아웃 → 1루 아웃" : "병살 무산 · 2루 아웃 → 1루 세이프" }
        let hit = hitBases == 2 ? "2루타" : hitBases == 1 ? "안타" : out && targetRunner != 0 ? "야수 선택" : "땅볼 아웃"
        return (fly != nil ? "뜬공 낙하 · " : "") + "\(hit)" + route + " · \(targetBase == 4 ? "홈" : "\(targetBase)루") 송구 · \(targetRunner == nil ? "주자 진루 완료" : out ? "아웃" : "세이프")"
    }
    var xpPlay: MatchFieldPlay {
        if let misplay {
            return MatchFieldPlay(runnerTime:misplay.at,ballTime:misplay.recoveredAt,ownDefense:misplay.participation,
                appliedTraits:misplay.traits,positionDelay:misplay.positionDelay,caughtFly:misplay.success,failedFielding:!misplay.success)
        }
        if let relay,relay.ownThrower {
            return MatchFieldPlay(runnerTime:runnerAt ?? controlAt,ballTime:controlAt,ownDefense:true,
                appliedTraits:relay.traits,positionDelay:relay.positionDelay)
        }
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
        try battedBall?.validate(for:self)
        if misplay != nil { try FieldMisplayRules.validate(self);return }
        guard [1,2,3,4,5].contains(version), (0..<18).contains(half), order >= 0, (0..<9).contains(fielder), (0..<9).contains(receiver),
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
            guard version >= 3,fly.reachAt.isFinite,fly.reachAt >= 0,secondThrow == nil,doublePlayGrounder == false,
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
        if let relay {
            guard version >= 4,(6...8).contains(fielder),[3,5].contains(relay.fielder),relay.fielder != receiver,
                  secondThrow == nil,!(ownDefense && relay.ownThrower),
                  [relay.readyAt,relay.receiveAt,relay.releaseAt,relay.directAt,relay.positionDelay].allSatisfy({ $0.isFinite && $0 >= 0 }),
                  relay.point.x.isFinite,relay.point.y.isFinite,releaseAt <= relay.receiveAt,
                  relay.readyAt <= relay.receiveAt,relay.receiveAt <= relay.releaseAt,relay.releaseAt <= ballAt,
                  controlAt < relay.directAt,TraitLoadout.valid(relay.traits),
                  ball.contains(where:{ $0.at == relay.receiveAt && $0.point == relay.point }),
                  ball.contains(where:{ $0.at == relay.releaseAt && $0.point == relay.point }),
                  ball.last?.at == ballAt,ball.last?.point == DetailedFieldRules.bases[targetBase],
                  fielders[relay.fielder].contains(where:{ $0.point == relay.point && $0.at <= relay.readyAt }) else { throw MatchError.invalidRecord }
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
    static func skills(stats:MatchFieldStats?,defending:Bool,npc:[MatchNPCPlayer]?) -> [Skill] {
        let ownIndex=defending ? names.firstIndex(of:stats?.position ?? ""):nil
        return names.indices.map {index in
            if index == ownIndex,let stats {
                return Skill(speed:clamp(stats.speed),defense:clamp(stats.defense),arm:clamp(stats.arm),traits:stats.activeTraits ?? [],
                    positionDelay:stats.positionMastery.map {0.25*(1-clamp($0)/100)} ?? 0)
            }
            if let npc {return Skill(speed:npc[index].speed,defense:npc[index].defense,arm:npc[index].arm)}
            return Skill()
        }
    }
    private struct Throw {
        let base: Int, receiver: Int
        let release: Double, ball: Double, control: Double
        var relay: FieldRelay?
    }
    private static func throwPlan(base:Int,receiver:Int,landing:FieldPoint,pickup:Double,handler:Int,
                                  skills:[Skill],ownIndex:Int?,force:Bool,relayEnabled:Bool,legacyFly:Bool=false) -> Throw {
        let skill=skills[handler],distance=landing.distance(to:bases[base])
        func flight(_ d:Double,_ skill:Skill) -> Double {
            d/skill.throwVelocity * (relayEnabled ? 1+max(0,d-40)/80 : 1)
        }
        let travel=flight(distance,skill)
        let cover=skills[receiver].reaction+positions[receiver].distance(to:bases[base])/skills[receiver].velocity
        let release=max(pickup+skill.transfer,cover-travel),ball=release+travel
        let tag=force ? 0:0.3-skills[receiver].defense*0.0015
        let directControl = !relayEnabled && legacyFly ? ball+0.3-skills[receiver].defense*0.0015 : ball+tag
        var best=Throw(base:base,receiver:receiver,release:release,ball:ball,control:directControl)
        guard relayEnabled,handler >= 6 else { return best }
        let point=landing.towards(bases[base],fraction:0.5)
        for index in [3,5] where index != receiver {
            let middle=skills[index]
            let ready=middle.reaction+positions[index].distance(to:point)/middle.velocity+middle.pickup
            let first=flight(landing.distance(to:point),skill),second=flight(point.distance(to:bases[base]),middle)
            let start=max(pickup+skill.transfer,ready-first)
            // Subtracting then adding the flight can round one ULP before the relay is ready.
            let receive=max(ready,start+first)
            let next=max(receive+middle.transfer,cover-second),arrival=next+second
            if arrival+tag < best.control {
                best=Throw(base:base,receiver:receiver,release:start,ball:arrival,control:arrival+tag,
                    relay:FieldRelay(fielder:index,point:point,readyAt:ready,receiveAt:receive,releaseAt:next,directAt:ball+tag,
                        ownThrower:index == ownIndex,traits:middle.traits,positionDelay:middle.positionDelay))
            }
        }
        return best
    }
    private static func relayNodes(_ relay:FieldRelay,skills:[Skill]) -> [FieldNode] {
        let i=relay.fielder
        return [FieldNode(at:0,point:positions[i]),FieldNode(at:skills[i].reaction,point:positions[i]),
            FieldNode(at:relay.readyAt-skills[i].pickup,point:relay.point)]
    }
    private static func throwNodes(_ plan:Throw) -> [FieldNode] {
        var nodes:[FieldNode]=[]
        if let relay=plan.relay {
            nodes.append(FieldNode(at:relay.receiveAt,point:relay.point));nodes.append(FieldNode(at:relay.releaseAt,point:relay.point))
        }
        nodes.append(FieldNode(at:plan.ball,point:bases[plan.base]));return nodes
    }
    static func resolve(half: Int, order: Int, landing: FieldPoint, flight: Double, runners before: [FieldRunnerProfile?],
                        batter: FieldRunnerProfile, outs: Int, stats: MatchFieldStats?, defending: Bool, ownBatter: Bool,
                        doublePlayEnabled: Bool = false, groundBall: Bool = true,relayEnabled:Bool=false,npc:[MatchNPCPlayer]?=nil) -> MatchDetailedPlay {
        let ownIndex = defending ? names.firstIndex(of: stats?.position ?? "") : nil
        let skills=DetailedFieldRules.skills(stats:stats,defending:defending,npc:npc)
        let handler = names.indices.min {
            max(flight, skills[$0].reaction + positions[$0].distance(to:landing)/skills[$0].velocity) + skills[$0].pickup <
            max(flight, skills[$1].reaction + positions[$1].distance(to:landing)/skills[$1].velocity) + skills[$1].pickup
        }!
        let skill = skills[handler]
        let pickup = max(flight, skill.reaction + positions[handler].distance(to:landing)/skill.velocity) + skill.pickup
        func planThrow(_ base: Int, force: Bool) -> Throw {
            let candidates = base == 1 ? [2,0,3] : base == 2 ? [3,5,0] : base == 3 ? [4,5,0] : [1,0,2]
            let receiver = candidates.first { $0 != handler }!
            return throwPlan(base:base,receiver:receiver,landing:landing,pickup:pickup,handler:handler,
                skills:skills,ownIndex:ownIndex,force:force,relayEnabled:relayEnabled)
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
        if let relay=plan.relay { fielderNodes[relay.fielder]=relayNodes(relay,skills:skills) }
        // Receiving alone or backing up does not award extra XP.
        for index in positions.indices where index != handler && index != plan.receiver && index != secondThrow?.receiver && index != plan.relay?.fielder {
            fielderNodes[index].append(FieldNode(at:pickup,point:positions[index].towards(landing,fraction:0.12)))
        }
        var ballNodes=[FieldNode(at:0,point:bases[0]),FieldNode(at:flight,point:landing),FieldNode(at:plan.release,point:landing)] + throwNodes(plan)
        if let secondThrow {
            ballNodes.append(FieldNode(at:secondThrow.releaseAt,point:bases[2]))
            ballNodes.append(FieldNode(at:secondThrow.ballAt,point:bases[1]))
        }
        return MatchDetailedPlay(version:relayEnabled ? 4 : doublePlayEnabled ? 2 : 1,half:half,order:order,landing:landing,flight:flight,fielder:handler,receiver:plan.receiver,
            ownDefense:handler == ownIndex,ownBatter:ownBatter,appliedTraits:handler == ownIndex ? skill.traits : ownBatter ? batter.traits.filter { $0 == .cheetah } : [],positionDelay:skill.positionDelay,
            pickupAt:pickup,releaseAt:plan.release,ballAt:plan.ball,controlAt:plan.control,targetBase:plan.base,
            targetRunner:chosen.map { runners[$0.runner].from },force:chosen?.force ?? false,out:out,runnerAt:chosen?.at,
            runners:runners,ball:ballNodes,fielders:fielderNodes,
            afterRunners:after,runs:runs,outsAdded:outsAdded,hitBases:hitBases,secondThrow:secondThrow,
            outsBefore:doublePlayEnabled ? outs : nil,doublePlayGrounder:doublePlayEnabled ? groundBall : nil,relay:plan.relay)
    }
}

extension CareerMatch {
    func validateDetailedField() throws {
        try validateHomeRuns()
        if let npcFielders {
            try npcFielders.validate()
            guard detailedFieldVersion == 5,battedBallVersion == 1,(0...18).contains(half),homeOrder>=0,awayOrder>=0,npcFielders.competition == (competition ?? "highschool") else {throw MatchError.invalidRecord}
        }
        guard battedBallVersion == nil || battedBallVersion == 1 && detailedFieldVersion == 5 else {throw MatchError.invalidRecord}
        if let version=detailedFieldVersion {
            guard [1,2,3,4,5].contains(version), let plays=fieldPlays, let runners=runnerProfiles,runners.count == 3,
                  runners.map({ $0 != nil }) == bases,Set(plays.map(\.eventID)).count == plays.count else { throw MatchError.invalidRecord }
            for runner in runners.compactMap({ $0 }) {
                guard runner.speed.isFinite,(0...100).contains(runner.speed),TraitLoadout.valid(runner.traits) else { throw MatchError.invalidRecord }
            }
            for play in plays {
                guard play.version == version,(play.battedBall != nil) == (battedBallVersion != nil) else { throw MatchError.invalidRecord }
                try play.validate()
            }
        } else if fieldPlays != nil || runnerProfiles != nil { throw MatchError.invalidRecord }
    }
}

extension DetailedFieldRules {
    // A caught fly removes the force. Runners wait on their original bag, then attempt one base.
    static func resolveFly(half:Int,order:Int,landing:FieldPoint,flight:Double,runners before:[FieldRunnerProfile?],
                           batter:FieldRunnerProfile,outs:Int,stats:MatchFieldStats?,defending:Bool,ownBatter:Bool,relayEnabled:Bool=false,npc:[MatchNPCPlayer]?=nil) -> MatchDetailedPlay {
        let ownIndex=defending ? names.firstIndex(of:stats?.position ?? "") : nil
        let skills=DetailedFieldRules.skills(stats:stats,defending:defending,npc:npc)
        func reach(_ index:Int) -> Double { skills[index].reaction + positions[index].distance(to:landing)/skills[index].velocity + skills[index].pickup }
        let handler=names.indices.min { reach($0) < reach($1) }!,skill=skills[handler],reachAt=reach(handler)
        guard reachAt <= flight else {
            var dropped=resolve(half:half,order:order,landing:landing,flight:flight,runners:before,batter:batter,outs:outs,
                                stats:stats,defending:defending,ownBatter:ownBatter,doublePlayEnabled:true,groundBall:false,relayEnabled:relayEnabled,npc:npc)
            dropped.version=relayEnabled ? 4:3;dropped.fly=FieldFlyPlay(caught:false,reachAt:reachAt)
            return dropped
        }
        func throwTo(_ base:Int) -> Throw {
            let candidates=base == 2 ? [3,5,0] : base == 3 ? [4,5,0] : [1,0,2]
            let receiver=candidates.first { $0 != handler }!
            return throwPlan(base:base,receiver:receiver,landing:landing,pickup:flight,handler:handler,
                skills:skills,ownIndex:ownIndex,force:false,relayEnabled:relayEnabled,legacyFly:true)
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
            ball.append(FieldNode(at:plan.release,point:landing));ball += throwNodes(plan)
            if let relay=plan.relay { fielders[relay.fielder]=relayNodes(relay,skills:skills) }
        }
        let end=chosen == nil ? flight:plan.control
        return MatchDetailedPlay(version:relayEnabled ? 4:3,half:half,order:order,landing:landing,flight:flight,fielder:handler,receiver:plan.receiver,
            ownDefense:handler == ownIndex,ownBatter:ownBatter,appliedTraits:handler == ownIndex ? skill.traits:ownBatter ? batter.traits:[],positionDelay:skill.positionDelay,
            pickupAt:flight,releaseAt:chosen == nil ? flight:plan.release,ballAt:chosen == nil ? flight:plan.ball,controlAt:end,
            targetBase:plan.base,targetRunner:chosen?.from,force:false,out:tagOut,runnerAt:chosen?.at,
            runners:runners,ball:ball,fielders:fielders,afterRunners:after,runs:runs,outsAdded:added,hitBases:0,
            outsBefore:outs,doublePlayGrounder:false,fly:FieldFlyPlay(caught:true,reachAt:reachAt),relay:chosen == nil ? nil:plan.relay)
    }
}

enum FieldMisplayKind: String, Codable { case fielding, throwing }
struct FieldMisplay: Codable, Equatable {
    let kind: FieldMisplayKind
    let stage: Int
    let fielder: Int
    let at: Double
    let scatteredAt: Double
    let recoveredAt: Double
    let loosePoint: FieldPoint
    let recoverer: Int
    let chance: Double
    let draw: Double
    let ownError: Bool
    let ownFielder: Int?
    let participation: Bool
    let success: Bool
    let traits: [PlayerTrait]
    let positionDelay: Double
    let reachedOnError: Bool
    let sacrificeFly: Bool
    let rbi: Int
    let ordinaryHitBases: Int
    let ordinaryRuns: Int
    let ordinaryRBI: Int
    let ordinarySacrificeFly: Bool
    let ordinaryOuts: Int
    let ordinaryDestinations: [Int:Int]
    let extraBases: [Int:Int]
}

enum FieldMisplayRules {
    struct Opportunity {
        let stage: Int, fielder: Int
        let kind: FieldMisplayKind
        let at: Double
        let target: FieldPoint
    }
    static func probability(kind:FieldMisplayKind,defense:Double,arm:Double,distance:Double,traits:[PlayerTrait]) -> Double {
        if kind == .fielding {
            return (0.002+pow(1-DetailedFieldRules.clamp(defense)/100,2)*0.08)*(traits.contains(.safeHands) ? 0.7:1)
        }
        return min(0.12,0.003+pow(1-DetailedFieldRules.clamp(arm)/100,2)*0.09+max(0,distance-40)*0.0002)
    }
    static func opportunities(_ p:MatchDetailedPlay) -> [Opportunity] {
        var result=[Opportunity(stage:0,fielder:p.fielder,kind:.fielding,at:p.pickupAt,target:p.landing)]
        guard p.battedBall == nil ? p.ball.count>2:p.releaseAt>p.pickupAt else { return result }
        result.append(Opportunity(stage:1,fielder:p.fielder,kind:.throwing,at:p.releaseAt,target:p.relay?.point ?? DetailedFieldRules.bases[p.targetBase]))
        if let relay=p.relay {
            result.append(Opportunity(stage:2,fielder:relay.fielder,kind:.fielding,at:relay.receiveAt,target:relay.point))
            result.append(Opportunity(stage:3,fielder:relay.fielder,kind:.throwing,at:relay.releaseAt,target:DetailedFieldRules.bases[p.targetBase]))
        }
        result.append(Opportunity(stage:4,fielder:p.receiver,kind:.fielding,at:p.ballAt,target:DetailedFieldRules.bases[p.targetBase]))
        if let second=p.secondThrow {
            result.append(Opportunity(stage:5,fielder:p.receiver,kind:.throwing,at:second.releaseAt,target:DetailedFieldRules.bases[1]))
            result.append(Opportunity(stage:6,fielder:second.receiver,kind:.fielding,at:second.ballAt,target:DetailedFieldRules.bases[1]))
        }
        return result.sorted { $0.at == $1.at ? $0.stage < $1.stage : $0.at < $1.at }
    }
    static func applying(to clean:MatchDetailedPlay,stats:MatchFieldStats?,defending:Bool,draws:[Double],npc:[MatchNPCPlayer]?=nil) -> MatchDetailedPlay {
        precondition(draws.count == 7 && draws.allSatisfy { $0.isFinite && (0..<1).contains($0) })
        let own=defending ? DetailedFieldRules.names.firstIndex(of:stats?.position ?? "") : nil
        let skills=DetailedFieldRules.skills(stats:stats,defending:defending,npc:npc)
        for event in opportunities(clean) {
            let skill=skills[event.fielder],start=FieldNode.sample(clean.ball,at:event.at)
            let chance=probability(kind:event.kind,defense:skill.defense,arm:skill.arm,distance:start.distance(to:event.target),traits:skill.traits)
            guard draws[event.stage] < chance else {continue}
            if let result=resolve(clean,event:event,skills:skills,own:own,chance:chance,draw:draws[event.stage]) { return result }
        }
        return clean
    }
    private static func resolve(_ clean:MatchDetailedPlay,event:Opportunity,skills:[DetailedFieldRules.Skill],own:Int?,chance:Double,draw:Double) -> MatchDetailedPlay? {
        let bases=DetailedFieldRules.bases,at=event.at
        let positions=clean.fielders.map { FieldNode.sample($0,at:at) }
        let start=FieldNode.sample(clean.ball,at:at),sign=event.target.x >= 0 ? 1.0:-1.0
        let loose=FieldPoint(x:max(-58,min(58,event.target.x+sign*(event.kind == .throwing ? 9:4))),y:max(-3,min(105,event.target.y+(event.kind == .throwing ? 7:-3))))
        let scatter=at+(event.kind == .throwing ? start.distance(to:loose)/skills[event.fielder].throwVelocity:0.25)
        func recovery(_ i:Int) -> Double { skills[i].reaction+positions[i].distance(to:loose)/skills[i].velocity+skills[i].pickup+0.35 }
        let recoverer=positions.indices.min { recovery($0) < recovery($1) }!,recovered=scatter+recovery(recoverer)
        let retired=clean.runners.filter { $0.out && ($0.retiredAt ?? clean.outAt) < at }
        let priorOuts=retired.count
        guard (clean.outsBefore ?? 0)+priorOuts < 3 else {return nil}
        let batterRevived=clean.runners.contains { $0.from == 0 && $0.out } && !retired.contains { $0.from == 0 }
        var result:[DetailedRunner]=[],occupiedLimit=4
        let ordinary=Dictionary(uniqueKeysWithValues:clean.runners.map { ($0.from,$0.destination) })
        var extras:[Int:Int]=[:]
        for r in clean.runners.sorted(by:{ $0.from > $1.from }) {
            if retired.contains(where:{ $0.from == r.from }) {result.append(r);continue}
            if r.destination == 4 && !r.out && r.arrival <= at {result.append(r);continue}
            let current=FieldNode.sample(r.nodes,at:at)
            var passed=r.from
            if r.destination > r.from {
                for b in (r.from+1)...r.destination where (r.arrival(at:b) ?? .infinity) <= at {passed=b}
            }
            let maxBase=min(4,occupiedLimit,min(4,max(r.from == 0 ? 1:r.from,r.destination)+1))
            let forced=batterRevived && (r.from == 0 || (1...r.from).allSatisfy { from in clean.runners.contains { $0.from == from } })
            let guaranteed=min(maxBase,max(forced ? r.from+1 : r.from == 0 ? 1:r.from,r.destination))
            let speed=5.5+DetailedFieldRules.clamp(r.profile.speed)*0.035
            var nodes=r.nodes.filter { $0.at < at };nodes.append(FieldNode(at:at,point:current))
            let moving=current.distance(to:FieldNode.sample(r.nodes,at:max(0,at-0.05))) > 0.001
            let restart=moving ? 0:(0.18+(100-DetailedFieldRules.clamp(r.profile.speed))*0.002)*(r.profile.traits.contains(.cheetah) ? 0.92:1)
            var destination=passed,time=at+restart,point=current
            if restart > 0 {nodes.append(FieldNode(at:time,point:current))}
            if maxBase > passed {
                for b in (passed+1)...maxBase {
                    let arrival=time+point.distance(to:bases[b])/speed
                    let danger=recovered+skills[recoverer].transfer+loose.distance(to:bases[b])/skills[recoverer].throwVelocity
                    if b > guaranteed && arrival > danger {break}
                    destination=b;time=arrival;point=bases[b];nodes.append(FieldNode(at:time,point:point))
                }
            }
            if destination < 4 {occupiedLimit=destination-1}
            result.append(DetailedRunner(from:r.from,destination:destination,profile:r.profile,nodes:nodes))
            if destination > r.destination {extras[r.from]=destination-r.destination}
        }
        let canceled=clean.outsAdded-priorOuts
        guard canceled > 0 || !extras.isEmpty else {return nil}
        var after:[FieldRunnerProfile?]=[nil,nil,nil],runs=0
        for r in result where !r.out {
            if r.destination == 4 {runs += 1}
            else if r.destination > 0 {after[r.destination-1]=r.profile}
        }
        let lead=result.filter { !$0.out && $0.destination > 0 }.max { $0.destination < $1.destination }
        let base=lead?.destination ?? 2
        let receiver=DetailedFieldRules.names.indices.filter { $0 != recoverer }.min {
            positions[$0].distance(to:bases[base])/skills[$0].velocity < positions[$1].distance(to:bases[base])/skills[$1].velocity
        }!
        let travel=loose.distance(to:bases[base])/skills[recoverer].throwVelocity
        let cover=at+skills[receiver].reaction+positions[receiver].distance(to:bases[base])/skills[receiver].velocity
        let release=max(recovered+skills[recoverer].transfer,cover-travel),ballAt=release+travel
        var ball=clean.ball.filter { $0.at < at };ball.append(FieldNode(at:at,point:start))
        ball.append(FieldNode(at:scatter,point:loose));ball.append(FieldNode(at:release,point:loose));ball.append(FieldNode(at:ballAt,point:bases[base]))
        var fielders=clean.fielders.enumerated().map { i,nodes in nodes.filter { $0.at < at }+[FieldNode(at:at,point:positions[i])] }
        fielders[recoverer].append(FieldNode(at:scatter+skills[recoverer].reaction,point:positions[recoverer]))
        fielders[recoverer].append(FieldNode(at:recovered-skills[recoverer].pickup-0.35,point:loose))
        fielders[receiver].append(FieldNode(at:cover,point:bases[base]))
        let handler=clean.ownDefense && clean.pickupAt <= at
        let relay=clean.relay?.ownThrower == true && (clean.relay?.receiveAt ?? .infinity) <= at
        let pivot=clean.secondThrow?.ownThrower == true && clean.controlAt <= at
        let participant=handler || relay || pivot || own == recoverer
        let success=own != event.fielder && (handler && clean.fly?.caught == true && clean.flight < at || handler && clean.out && clean.outAt < at)
        let ownSkill=own.map {skills[$0]}
        let onError=clean.hitBases == 0 && result.contains { $0.from == 0 && !$0.out && $0.destination > 0 } && canceled > 0
        let rbi=min(runs,(event.stage == 0 && clean.fly?.caught == true) ? 0:clean.rbi)
        let error=FieldMisplay(kind:event.kind,stage:event.stage,fielder:event.fielder,at:at,scatteredAt:scatter,recoveredAt:recovered,
            loosePoint:loose,recoverer:recoverer,chance:chance,draw:draw,ownError:own == event.fielder,ownFielder:own,participation:participant,success:success,
            traits:ownSkill?.traits ?? result.first(where:{$0.profile.own})?.profile.traits ?? [],positionDelay:ownSkill?.positionDelay ?? 0,reachedOnError:onError,
            sacrificeFly:clean.sacrificeFly && clean.flight < at,rbi:rbi,ordinaryHitBases:clean.hitBases,ordinaryRuns:clean.runs,ordinaryRBI:clean.rbi,ordinarySacrificeFly:clean.sacrificeFly,
            ordinaryOuts:clean.outsAdded,ordinaryDestinations:ordinary,extraBases:extras)
        return MatchDetailedPlay(version:5,half:clean.half,order:clean.order,landing:clean.landing,flight:clean.flight,fielder:clean.fielder,receiver:receiver,
            ownDefense:clean.ownDefense,ownBatter:clean.ownBatter,appliedTraits:clean.appliedTraits,positionDelay:clean.positionDelay,
            pickupAt:clean.pickupAt,releaseAt:release,ballAt:ballAt,controlAt:ballAt,targetBase:base,targetRunner:nil,force:false,out:false,runnerAt:nil,
            runners:result,ball:ball,fielders:fielders,afterRunners:after,runs:runs,outsAdded:priorOuts,hitBases:clean.hitBases,
            outsBefore:clean.outsBefore,doublePlayGrounder:clean.doublePlayGrounder,fly:clean.fly,misplay:error)
    }
    static func validate(_ p:MatchDetailedPlay) throws {
        guard let e=p.misplay,p.version == 5,(0..<7).contains(e.stage),(0..<9).contains(e.fielder),(0..<9).contains(e.recoverer),
              (0..<9).contains(p.fielder),(0..<9).contains(p.receiver),(0..<18).contains(p.half),p.order >= 0,
              let outs=p.outsBefore,(0...2).contains(outs),(0...2).contains(p.outsAdded),outs+p.outsAdded < 3,
              p.afterRunners.count == 3,p.fielders.count == 9,p.secondThrow == nil,p.relay == nil,!p.out,!p.force,p.targetRunner == nil,p.runnerAt == nil,
              (0...4).contains(p.runs),(1...4).contains(p.targetBase),(0...2).contains(p.hitBases),p.hitBases == e.ordinaryHitBases,
              [e.at,e.scatteredAt,e.recoveredAt,e.chance,e.draw,e.positionDelay,p.flight,p.pickupAt,p.releaseAt,p.ballAt,p.controlAt].allSatisfy({$0.isFinite && $0 >= 0}),
              p.flight <= p.pickupAt,p.pickupAt <= e.at,e.at > 0,e.at <= e.scatteredAt,e.scatteredAt <= e.recoveredAt,e.recoveredAt <= p.releaseAt,p.releaseAt <= p.ballAt,p.controlAt == p.ballAt,
              [0,2,4,6].contains(e.stage) == (e.kind == .fielding),
              (0..<1).contains(e.chance),(0..<e.chance).contains(e.draw),TraitLoadout.valid(e.traits),
              !e.success || e.participation && !e.ownError,
              e.ownFielder.map({(0..<9).contains($0)}) ?? true,e.ownError == (e.ownFielder == e.fielder),(0...p.runs).contains(e.rbi),
              p.runners.contains(where:{$0.from == 0}),Set(p.runners.map(\.from)).count == p.runners.count else {throw MatchError.invalidRecord}
        var after:[FieldRunnerProfile?]=[nil,nil,nil],runs=0,retired=0,expected:[Int:Int]=[:]
        for r in p.runners {
            guard (0...3).contains(r.from),(r.from...4).contains(r.destination),r.profile.speed.isFinite,(0...100).contains(r.profile.speed),TraitLoadout.valid(r.profile.traits),let original=e.ordinaryDestinations[r.from],(r.from...4).contains(original) else {throw MatchError.invalidRecord}
            if r.out {guard let t=r.retiredAt,t.isFinite,t < e.at else {throw MatchError.invalidRecord};retired += 1}
            else if r.destination == 4 {runs += 1}
            else {guard r.destination > 0,after[r.destination-1] == nil else {throw MatchError.invalidRecord};after[r.destination-1]=r.profile}
            if r.destination > original {expected[r.from]=r.destination-original}
        }
        guard retired == p.outsAdded,runs == p.runs,after == p.afterRunners,expected == e.extraBases,
              (0...2).contains(e.ordinaryOuts),e.ordinaryOuts >= p.outsAdded,(0...4).contains(e.ordinaryRuns),(0...e.ordinaryRuns).contains(e.ordinaryRBI),
              e.rbi == min(p.runs,(e.stage == 0 && p.fly?.caught == true) ? 0:e.ordinaryRBI),
              e.sacrificeFly == (e.ordinarySacrificeFly && p.flight < e.at),
              e.reachedOnError == (p.hitBases == 0 && e.ordinaryOuts > p.outsAdded && p.runners.contains(where:{$0.from == 0 && !$0.out && $0.destination > 0})),
              Set(e.ordinaryDestinations.keys) == Set(p.runners.map(\.from)),
              e.ordinaryOuts > p.outsAdded || !expected.isEmpty,
              p.ball.contains(where:{$0.at == e.scatteredAt && $0.point == e.loosePoint}),p.ball.last?.at == p.ballAt,p.ball.last?.point == DetailedFieldRules.bases[p.targetBase] else {throw MatchError.invalidRecord}
        for nodes in [p.ball]+p.fielders+p.runners.map(\.nodes) {
            guard !nodes.isEmpty,nodes.allSatisfy({$0.at.isFinite && $0.at >= 0 && $0.point.x.isFinite && $0.point.y.isFinite}),zip(nodes,nodes.dropFirst()).allSatisfy({$0.at <= $1.at}) else {throw MatchError.invalidRecord}
        }
    }
}
