import Foundation

/// 확정된 위치·시각만 저장한다. 화면의 판정 고리와 재생은 이 값을 읽는다.
struct MatchFieldRuling: Codable, Equatable {
    enum Kind: String, Codable { case fairBase, foul, groundRuleDouble, overthrow }
    let kind: Kind
    let at: Double
    let point: FieldPoint
    var bounceAt: Double? = nil
    var bouncePoint: FieldPoint? = nil
    var awarded: [Int: Int]? = nil
    var label: String {
        switch kind {
        case .fairBase: "베이스 접촉 · 페어 · 인플레이"
        case .foul: "파울 · 볼 데드 · 같은 타석"
        case .groundRuleDouble: "바운드 후 장외 · 인정 2루타"
        case .overthrow: "덕아웃 악송구 · 볼 데드 · 두 베이스 보장"
        }
    }
}

struct MatchFieldReview: Codable, Equatable {
    var version = 1
    var before: MatchPitchState? = nil
    var after: MatchPitchState? = nil
    var ruling: MatchFieldRuling? = nil
    var heldAtSecond: Bool? = nil
    var eventID: String? = nil
}

enum FieldReviewRules {
    static func fenceDistance(direction: Double) -> Double { 110 - abs(direction) * 0.45 }

    /// 새 경기만 타구의 첫 바운드와 이후 구름을 구분한다. 기존 난수 세 개를 그대로 쓴다.
    static func ball(quality: Double, contact: Double, power: Double, bunt: Bool,
                     offsetX: Double, offsetY: Double, timing: Double,
                     speedDraw: Double, angleDraw: Double, directionDraw: Double) -> MatchBattedBall {
        let old = MatchBattedBall.make(quality: quality, contact: contact, power: power, bunt: bunt,
            offsetX: offsetX, offsetY: offsetY, timing: timing,
            speedDraw: speedDraw, angleDraw: angleDraw, directionDraw: directionDraw)
        let direction = old.kind == .ground
            ? max(-54, min(54, (directionDraw-0.5)*100 + timing*160 + offsetX*70)) : old.direction
        let bounce: Double, first: Double, distance: Double, duration: Double
        if old.kind.airborne {
            bounce = old.flight
            first = old.speed * cos(old.angle * .pi/180) * bounce * 0.72
            let carry = max(0, old.speed * cos(old.angle * .pi/180)) * 0.32
            distance = first + carry
            duration = bounce + carry / max(3, old.speed * 0.25)
        } else {
            distance = bunt ? old.distance : 7 + old.speed*2.15 + power*0.12 + angleDraw*12
            duration = distance / (old.speed*0.68)
            bounce = min(0.25, duration*0.1)
            first = min(distance, old.speed*bounce)
        }
        var value = MatchBattedBall(version: 2, kind: old.kind, quality: old.quality,
            contact: old.contact, power: old.power, speed: old.speed, angle: old.angle,
            direction: direction, distance: distance, flight: duration)
        value.firstBounceAt = bounce; value.firstBounceDistance = first
        return value
    }

    static func time(_ ball: MatchBattedBall, distance: Double) -> Double {
        var low = 0.0, high = ball.flight
        for _ in 0..<48 {
            let middle = (low+high)/2
            if hypot(ball.point(at: middle).x, ball.point(at: middle).y) < distance { low = middle }
            else { high = middle }
        }
        return (low+high)/2
    }

    static func ruling(_ ball: MatchBattedBall) -> MatchFieldRuling? {
        let angle = abs(ball.direction) * .pi/180
        let baseDistance = DetailedFieldRules.diagonal * (sin(angle)+cos(angle))
        let nearest = ball.point(at: time(ball, distance: baseDistance))
        let bag = DetailedFieldRules.bases[ball.direction < 0 ? 3 : 1]
        if ball.kind == .ground, ball.distance >= baseDistance, nearest.distance(to: bag) <= 0.46 {
            return .init(kind: .fairBase, at: time(ball, distance: baseDistance), point: nearest)
        }
        if ball.kind == .ground, abs(ball.direction) > 45 {
            let distance = min(ball.distance, DetailedFieldRules.diagonal / max(0.001,cos(angle)))
            let at = time(ball, distance: distance)
            return .init(kind: .foul, at: at, point: ball.point(at: at))
        }
        let fence = fenceDistance(direction: ball.direction)
        if abs(ball.direction) <= 45, ball.distance >= fence,
           let bounce = ball.firstBounceAt, time(ball, distance: fence) >= bounce {
            let at = time(ball, distance: fence)
            return .init(kind: .groundRuleDouble, at: at, point: ball.point(at: at),
                bounceAt: bounce, bouncePoint: ball.point(at: bounce))
        }
        return nil
    }

    static func isHomeRun(_ ball: MatchBattedBall) -> Bool {
        ball.kind.airborne && abs(ball.direction) <= 45
            && ball.distance >= fenceDistance(direction: ball.direction)
            && time(ball, distance: fenceDistance(direction: ball.direction)) < (ball.firstBounceAt ?? ball.flight)
    }

    static func clipped(_ ball:MatchBattedBall,at time:Double) -> MatchBattedBall {
        let point=ball.point(at:time),distance=hypot(point.x,point.y)
        var value=MatchBattedBall(version:2,kind:ball.kind,quality:ball.quality,contact:ball.contact,power:ball.power,
            speed:ball.speed,angle:ball.angle,direction:ball.direction,distance:distance,flight:time)
        value.firstBounceAt=min(time,ball.firstBounceAt ?? time)
        value.firstBounceDistance=min(distance,ball.firstBounceDistance ?? distance)
        return value
    }

    /// 보장 루와 실제 도착은 별개다. 기존 주자는 앞에서부터 배치해 중복 점유를 막는다.
    static func award(match: CareerMatch, ball: MatchBattedBall, ruling: MatchFieldRuling,
                      batter: FieldRunnerProfile, clean: MatchDetailedPlay? = nil) -> MatchDetailedPlay {
        let before = match.runnerProfiles ?? [nil,nil,nil]
        let bags = DetailedFieldRules.bases
        var movements: [DetailedRunner] = [], after: [FieldRunnerProfile?] = [nil,nil,nil]
        var destinations: [Int:Int] = [:], runs = 0
        for from in stride(from: 3, through: 0, by: -1) {
            guard let profile = from == 0 ? batter : before[from-1] else { continue }
            let destination = ruling.kind == .foul ? from : min(4,from+2)
            destinations[from] = destination
            let original = clean?.runners.first { $0.from == from }
            var nodes: [FieldNode]
            if ruling.kind == .foul {
                let lead = from == 0 ? bags[0].towards(bags[1], fraction: 0.15)
                    : bags[from].towards(bags[from+1], fraction: 0.10)
                nodes = [.init(at:0,point:bags[from]), .init(at:ruling.at,point:lead),
                         .init(at:ruling.at+lead.distance(to:bags[from])/DetailedFieldRules.runnerVelocity(profile),point:bags[from])]
            } else {
                nodes = original?.nodes.filter { $0.at < ruling.at } ?? [.init(at:0,point:bags[from])]
                let point = original.map { FieldNode.sample($0.nodes, at:ruling.at) } ?? bags[from]
                nodes.append(.init(at:ruling.at,point:point))
                var passed = from
                if let original {
                    for base in (from+1)...max(from+1,original.destination) where base <= 4 {
                        if (original.arrival(at:base) ?? .infinity) <= ruling.at { passed = base }
                    }
                }
                var t = ruling.at, p = point
                if destination > passed {
                    for base in (passed+1)...destination {
                        t += p.distance(to:bags[base])/DetailedFieldRules.runnerVelocity(profile)
                        nodes.append(.init(at:t,point:bags[base])); p=bags[base]
                    }
                }
            }
            movements.append(.init(from:from,destination:destination,profile:profile,nodes:nodes))
            if destination == 4 { runs += 1 }
            else if destination > 0 { after[destination-1]=profile }
        }
        var boundary=ruling; boundary.awarded = ruling.kind == .foul ? nil : destinations
        var nodes = ball.nodes.filter { $0.at < ruling.at } + [.init(at:ruling.at,point:ruling.point)]
        if let clean, ruling.kind == .overthrow {
            nodes = clean.ball.filter { $0.at <= clean.releaseAt } + [.init(at:ruling.at,point:ruling.point)]
        }
        let handler = clean?.fielder ?? (ball.direction < 0 ? 4 : 2)
        let fielders = clean?.fielders.map { path in
            path.filter { $0.at < ruling.at } + [.init(at:ruling.at,point:FieldNode.sample(path,at:ruling.at))]
        } ?? DetailedFieldRules.positions.map { [.init(at:0,point:$0)] }
        var result = MatchDetailedPlay(version:5,half:match.half,order:match.half.isMultiple(of:2) ? match.awayOrder:match.homeOrder,
            landing:ball.landing,flight:ball.flight,fielder:handler,receiver:handler == 2 ? 3:2,
            ownDefense:clean?.ownDefense ?? false,ownBatter:batter.own,appliedTraits:clean?.appliedTraits ?? [],positionDelay:clean?.positionDelay ?? 0,
            pickupAt:clean?.pickupAt ?? ruling.at,releaseAt:clean?.releaseAt ?? ruling.at,
            ballAt:ruling.at,controlAt:ruling.at,targetBase:2,targetRunner:0,force:false,out:false,runnerAt:nil,
            runners:movements,ball:nodes,fielders:fielders,afterRunners:after,runs:runs,outsAdded:0,
            hitBases:ruling.kind == .groundRuleDouble ? 2:0,outsBefore:match.outs,doublePlayGrounder:false)
        result.battedBall=ball; result.review = .init(before:MatchPitchState(match),ruling:boundary)
        return result
    }

    /// 현재 첫 내야 송구가 크게 빗나간 경우만 덕아웃 진입으로 분리한다. 새 난수는 소비하지 않는다.
    static func overthrow(match: CareerMatch, ball: MatchBattedBall, clean: MatchDetailedPlay,
                          resolved: MatchDetailedPlay, batter: FieldRunnerProfile, draw: Double) -> MatchDetailedPlay? {
        guard let error=resolved.misplay,error.kind == .throwing,error.stage == 1,
              clean.fielder < 6,clean.targetBase == 1,
              (clean.runners.first(where:{$0.from == 0})?.arrival(at:1) ?? .infinity) > clean.releaseAt else {return nil}
        let skills=DetailedFieldRules.skills(stats:match.fieldStats,defending:!match.offense && match.appearance,npc:match.npcDefenders)
        let chance=FieldMisplayRules.probability(kind:.throwing,defense:skills[clean.fielder].defense,
            arm:skills[clean.fielder].arm,distance:clean.landing.distance(to:DetailedFieldRules.bases[1]),traits:skills[clean.fielder].traits)
        let deviation=9+18*(1-draw/max(0.000001,chance))
        let bag=DetailedFieldRules.bases[1]
        let escaped=FieldPoint(x:bag.x+deviation,y:bag.y+7)
        guard escaped.x-escaped.y >= 12 else {return nil}
        let point=FieldPoint(x:25,y:8)
        let at=clean.releaseAt+clean.landing.distance(to:point)/skills[clean.fielder].throwVelocity
        return award(match:match,ball:ball,ruling:.init(kind:.overthrow,at:at,point:point),batter:batter,clean:clean)
    }

    static func validateBall(_ ball: MatchBattedBall, play: MatchDetailedPlay) throws {
        guard play.review != nil, ball.version == 2,
              [ball.quality,ball.contact,ball.power,ball.speed,ball.angle,ball.direction,ball.distance,ball.flight].allSatisfy(\.isFinite),
              (0...1).contains(ball.quality),(0...100).contains(ball.contact),(0...100).contains(ball.power),
              (3...48).contains(ball.speed),(-18...65).contains(ball.angle),(-54...54).contains(ball.direction),
              (0...220).contains(ball.distance),ball.distance > 0,(0...20).contains(ball.flight),ball.flight > 0,
              let bounce=ball.firstBounceAt,let distance=ball.firstBounceDistance,
              bounce.isFinite,distance.isFinite,bounce > 0,bounce <= ball.flight,distance >= 0,distance <= ball.distance,
              play.landing.distance(to:ball.landing)<0.000001,play.flight == ball.flight else {throw MatchError.invalidRecord}
        if play.review?.ruling.map({$0.kind != .fairBase}) != true {
            guard play.ball.count >= ball.nodes.count,
                  zip(ball.nodes,play.ball).allSatisfy({abs($0.at-$1.at)<0.000001 && $0.point.distance(to:$1.point)<0.000001}) else {throw MatchError.invalidRecord}
        }
    }

    static func validateReview(_ review: MatchFieldReview, play: MatchDetailedPlay) throws {
        guard review.version == 1,review.before.map(\.valid) ?? true,review.after.map(\.valid) ?? true else {throw MatchError.invalidRecord}
        if let before=review.before {guard before.half == play.half,before.order == play.order,before.outs == play.outsBefore else {throw MatchError.invalidRecord}}
        if let ruling=review.ruling {
            guard ruling.at.isFinite,ruling.at >= 0,ruling.point.x.isFinite,ruling.point.y.isFinite,
                  ruling.bounceAt.map({$0.isFinite && $0 >= 0 && $0 <= ruling.at}) ?? true,
                  ruling.bouncePoint.map({$0.x.isFinite && $0.y.isFinite}) ?? true else {throw MatchError.invalidRecord}
            if ruling.kind != .overthrow {
                guard let ball=play.battedBall,let expected=self.ruling(ball),expected.kind == ruling.kind,
                      abs(expected.at-ruling.at)<0.000001,expected.point.distance(to:ruling.point)<0.000001,
                      expected.bounceAt == ruling.bounceAt,
                      expected.bouncePoint.map {p in ruling.bouncePoint.map {p.distance(to:$0)<0.000001} ?? false} ?? (ruling.bouncePoint == nil) else {throw MatchError.invalidRecord}
            }
        }
        if let before=review.before,let after=review.after {
            let foul=review.ruling?.kind == .foul
            let third=before.outs+play.outsAdded == 3
            let half=before.half+(third ? 1:0)
            guard after.half == half,after.outs == (third ? 0:before.outs+play.outsAdded),
                  after.home == before.home+(before.half.isMultiple(of:2) ? 0:play.runs),
                  after.away == before.away+(before.half.isMultiple(of:2) ? play.runs:0),
                  after.homeOrder == before.homeOrder+(!foul && !before.half.isMultiple(of:2) ? 1:0),
                  after.awayOrder == before.awayOrder+(!foul && before.half.isMultiple(of:2) ? 1:0),
                  after.runners == (third ? [nil,nil,nil]:play.afterRunners),
                  after.balls == (foul ? before.balls:0),after.strikes == (foul ? min(2,before.strikes+1):0),
                  after.completed == (half == 18 || half == 17 && after.home > after.away) else {throw MatchError.invalidRecord}
        }
    }

    static func validateAward(_ play: MatchDetailedPlay) throws {
        guard let ruling=play.review?.ruling, let ball=play.battedBall,
              [MatchFieldRuling.Kind.foul,.groundRuleDouble,.overthrow].contains(ruling.kind),
              (0..<18).contains(play.half),play.order >= 0,(0..<9).contains(play.fielder),(0..<9).contains(play.receiver),
              play.fielders.count == 9,play.afterRunners.count == 3,play.outsAdded == 0,!play.out,
              play.secondThrow == nil,play.relay == nil,play.misplay == nil,
              Set(play.runners.map(\.from)).count == play.runners.count,play.runners.contains(where:{$0.from == 0}),
              play.ball.last == FieldNode(at:ruling.at,point:ruling.point) else {throw MatchError.invalidRecord}
        try validateBall(ball,play:play)
        var after:[FieldRunnerProfile?]=[nil,nil,nil],runs=0
        for runner in play.runners {
            guard (0...3).contains(runner.from),(runner.from...4).contains(runner.destination),!runner.out,
                  runner.profile.speed.isFinite,(0...100).contains(runner.profile.speed),TraitLoadout.valid(runner.profile.traits),
                  runner.destination == (ruling.kind == .foul ? runner.from:min(4,runner.from+2)),
                  runner.nodes.last?.point == DetailedFieldRules.bases[runner.destination] else {throw MatchError.invalidRecord}
            if runner.destination == 4 {runs += 1} else if runner.destination > 0 {guard after[runner.destination-1] == nil else {throw MatchError.invalidRecord};after[runner.destination-1]=runner.profile}
        }
        guard after == play.afterRunners,runs == play.runs,play.hitBases == (ruling.kind == .groundRuleDouble ? 2:0),
              ruling.kind == .foul ? ruling.awarded == nil:ruling.awarded == Dictionary(uniqueKeysWithValues:play.runners.map {($0.from,$0.destination)}),
              ruling.kind != .overthrow || ruling.point == FieldPoint(x:25,y:8) else {throw MatchError.invalidRecord}
        for nodes in [play.ball]+play.fielders+play.runners.map(\.nodes) {
            guard !nodes.isEmpty,nodes.allSatisfy({$0.at.isFinite && $0.at >= 0 && $0.point.x.isFinite && $0.point.y.isFinite}),
                  zip(nodes,nodes.dropFirst()).allSatisfy({$0.at <= $1.at}) else {throw MatchError.invalidRecord}
        }
    }

    static func validateSafeRelay(_ play: MatchDetailedPlay, second: FieldSecondThrow) throws {
        guard play.targetBase == 2,play.targetRunner == 1,!play.out,play.hitBases == 0,
              play.doublePlayGrounder == true,(play.outsBefore ?? 3)<2,second.receiver == 2,
              [second.releaseAt,second.ballAt,second.controlAt,second.runnerAt].allSatisfy({$0.isFinite && $0 >= 0}),
              play.controlAt <= second.releaseAt,second.releaseAt <= second.ballAt,second.ballAt == second.controlAt,
              play.runners.contains(where:{$0.from == 0 && $0.out == second.out}),
              play.runners.contains(where:{$0.from == 1 && !$0.out}),play.ball.last?.point == DetailedFieldRules.bases[1] else {throw MatchError.invalidRecord}
    }
}

extension CareerMatch {
    mutating func enableFieldReview() {
        guard fieldReviewVersion == nil,detailedFieldVersion == 5,battedBallVersion == 1,
              homeOrder == 0,awayOrder == 0,fieldPlays?.isEmpty == true else {return}
        fieldReviewVersion=1
        scoutingPerformance?.triples=0
    }

    /// 새 타구 규칙의 결과도 기존 타석 확정 트랜잭션에 한 번만 반영한다.
    mutating func resolveReviewedPlate(initial:String,batter:Bool,pitcher:Bool,entrant:FieldRunnerProfile,bunt:Bool,
                                      battingQuality:Double?,pitchingQuality:Double?,offsetX:Double,offsetY:Double,timing:Double,direct:Bool) {
        let a=roll(),b=roll(),c=roll()
        let quality=battingQuality ?? max(0.05,0.3+a*0.55-(pitchingQuality ?? 0)*0.35)
        var shot=FieldReviewRules.ball(quality:quality,contact:batter ? contact:npcContact,power:batter ? power:npcPower,
            bunt:bunt,offsetX:offsetX,offsetY:offsetY,timing:timing,speedDraw:a,angleDraw:b,directionDraw:c)
        let before=MatchPitchState(self)
        let defending = !offense && appearance && (role != "pitcher" || ownPitcherActive)
        let skills=DetailedFieldRules.skills(stats:fieldStats,defending:defending,npc:npcDefenders)
        let bounce=shot.firstBounceAt ?? shot.flight,bouncePoint=shot.point(at:bounce)
        let reaches=skills.indices.map {skills[$0].reaction+DetailedFieldRules.positions[$0].distance(to:bouncePoint)/skills[$0].velocity+skills[$0].pickup}
        let catchAt=reaches.min() ?? .infinity
        let catchesFly=shot.kind.airborne && !FieldReviewRules.isHomeRun(shot) && catchAt <= bounce
        if catchesFly {shot=FieldReviewRules.clipped(shot,at:bounce)}
        else if !FieldReviewRules.isHomeRun(shot),FieldReviewRules.ruling(shot)?.kind != .foul {
            let stop=FieldReviewRules.ruling(shot)?.at ?? shot.flight
            if let interception=shot.nodes.first(where:{node in
                node.at >= bounce && node.at < stop && skills.indices.contains(where:{i in
                    skills[i].reaction+DetailedFieldRules.positions[i].distance(to:node.point)/skills[i].velocity+skills[i].pickup <= node.at
                })
            }) {shot=FieldReviewRules.clipped(shot,at:interception.at)}
        }
        let ruling=FieldReviewRules.ruling(shot)
        if ruling?.kind == .foul,let ruling {
            var play=FieldReviewRules.award(match:self,ball:shot,ruling:ruling,batter:entrant)
            pitchFoul(before:before,bunt:bunt,batter:batter,pitcher:pitcher,direct:direct)
            play.review?.after=MatchPitchState(self)
            play.review?.eventID=pitchEvents?.events.last?.id
            if let index=pitchEvents?.events.indices.last {pitchEvents?.events[index].play=play}
            return
        }
        if FieldReviewRules.isHomeRun(shot) {
            let ownIndex = !offense && appearance && (role != "pitcher" || ownPitcherActive)
                ? DetailedFieldRules.names.firstIndex(of:fieldStats?.position ?? ""):nil
            var event=MatchHomeRun(half:half,order:before.order,seed:random,power:batter ? power:npcPower,
                quality:quality,directionOffset:offsetX,before:runnerProfiles ?? [nil,nil,nil],batter:entrant,
                defenderSpeeds:DetailedFieldRules.names.indices.map {$0 == ownIndex ? fieldStats?.speed ?? 60:npcDefenders?[$0].speed ?? 60},
                ownDefender:ownIndex,scoreBefore:.init(home:homeScore,away:awayScore))
            event.trajectory=shot;event.review = .init(before:before)
            if homeRuns == nil {homeRuns=[]};homeRuns?.append(event)
            completePlate(initial:"홈런",result:"홈런",batter:batter,pitcher:pitcher,newRunner:entrant)
            return
        }
        var play:MatchDetailedPlay,clean:MatchDetailedPlay?
        if ruling?.kind == .groundRuleDouble,let ruling {
            play=FieldReviewRules.award(match:self,ball:shot,ruling:ruling,batter:entrant)
            clean=play
        } else {
            play = catchesFly
                ? DetailedFieldRules.resolveFly(half:half,order:before.order,landing:shot.landing,flight:shot.flight,
                    runners:runnerProfiles ?? [nil,nil,nil],batter:entrant,outs:outs,stats:fieldStats,defending:defending,
                    ownBatter:batter,relayEnabled:true,npc:npcDefenders)
                : DetailedFieldRules.resolve(half:half,order:before.order,landing:shot.landing,flight:shot.flight,
                    runners:runnerProfiles ?? [nil,nil,nil],batter:entrant,outs:outs,stats:fieldStats,defending:defending,
                    ownBatter:batter,doublePlayEnabled:true,groundBall:shot.kind == .ground,relayEnabled:true,npc:npcDefenders,
                    continuationEnabled:true)
            if shot.kind.airborne && !catchesFly {play.fly = .init(caught:false,reachAt:catchAt)}
            play.version=5;play.battedBall=shot
            play.ball=shot.nodes+play.ball.filter {$0.at > shot.flight}
            if play.review == nil {play.review = .init()}
            play.review?.before=before;play.review?.ruling=ruling
            clean=play
            let draws=(0..<7).map {_ in roll()}
            let resolved=FieldMisplayRules.applying(to:play,stats:fieldStats,defending:defending,draws:draws,npc:npcDefenders)
            if let outside=FieldReviewRules.overthrow(match:self,ball:shot,clean:play,resolved:resolved,batter:entrant,draw:draws[1]) {
                play=outside
            } else {
                play=resolved
                play.battedBall=shot
                play.review = clean?.review
            }
        }
        play.version=5
        if pitching != nil {MatchPitching.transferChoiceResponsibility(&play)}
        if play.ownParticipation || batter {lastFieldPlay=play.xpPlay}
        if play.ownParticipation,role == "batter",positionExperience != nil {
            let order=isHome ? awayOrder:homeOrder
            positionExperience?.events.append(.init(half:half,order:order,play:play.xpPlay))
        }
        let result = play.review?.ruling?.kind == .overthrow ? "실책 출루"
            : play.misplay?.reachedOnError == true ? "실책 출루"
            : play.fly?.caught == true ? (play.sacrificeFly ? "희생플라이":"뜬공")
            : play.hitBases == 3 ? "3루타" : play.hitBases == 2 ? "2루타" : play.hitBases == 1 ? "안타"
            : play.out ? "범타":"야수 선택"
        completePlate(initial:initial,result:result,batter:batter,pitcher:pitcher,newRunner:entrant,detailed:play,cleanForEarned:clean)
        play.review?.after=MatchPitchState(self)
        fieldPlays?.append(play)
    }

    mutating func finishFieldReview(before:MatchPitchState) {
        let after=MatchPitchState(self)
        if let index=fieldPlays?.lastIndex(where:{$0.half == before.half && $0.order == before.order}) {
            fieldPlays?[index].review?.before=before;fieldPlays?[index].review?.after=after
        }
        if let index=homeRuns?.lastIndex(where:{$0.half == before.half && $0.order == before.order}) {
            homeRuns?[index].review = .init(before:before,after:after)
        }
    }

    func validateFieldReviews() throws {
        guard let fieldReviewVersion else {
            guard fieldPlays?.contains(where:{$0.review != nil || $0.battedBall?.version == 2}) != true,
                  homeRuns?.contains(where:{$0.review != nil || $0.trajectory != nil}) != true,
                  pitchEvents?.events.contains(where:{$0.play?.review != nil}) != true else {throw MatchError.invalidRecord}
            return
        }
        guard fieldReviewVersion == 1,detailedFieldVersion == 5,battedBallVersion == 1 else {throw MatchError.invalidRecord}
        guard homeRuns?.allSatisfy({$0.trajectory?.version == 2 && $0.review?.before != nil && $0.review?.after != nil}) ?? true else {throw MatchError.invalidRecord}
        for event in pitchEvents?.events ?? [] where event.play?.review != nil {
            guard event.kind == .foul,event.play?.review?.before == event.before,
                  event.play?.review?.after == event.after,event.play?.eventID == event.id else {throw MatchError.invalidRecord}
        }
        for play in fieldPlays ?? [] {
            guard let review=play.review,let before=review.before,let after=review.after,
                  before.half == play.half,before.order == play.order,
                  (before.half % 2 == 1 ? after.homeOrder:after.awayOrder) == before.order+1 else {throw MatchError.invalidRecord}
        }
    }
}
