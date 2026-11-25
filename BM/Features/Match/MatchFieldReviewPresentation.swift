import SwiftUI

@MainActor enum InplayBallTrail {
    /// 현재 이동 구간의 지난 위치만 잇는다. 포구/보유 때와 새 송구 사이를 가로지르지 않는다.
    static func points(replay:InplayReplay,time:Double,size:CGSize,leftIndex:Int?) -> [CGPoint] {
        let start:Double
        switch replay {
        case .field(let play):
            guard let segment=zip(play.ball,play.ball.dropFirst()).first(where: {
                $0.at <= time && time < $1.at && $0.point != $1.point
            }) else {return []}
            start=max(segment.0.at,time-0.14)
        case .homeRun(let event):
            guard time > 0,time < event.flight else {return []}
            start=max(0,time-0.14)
        }
        guard time > start else {return []}
        var points=(0...7).map {replay.ballPoint(time:start+(time-start)*Double($0)/7,size:size,leftIndex:leftIndex)}
        var length=zip(points,points.dropFirst()).reduce(0.0) {total,pair in
            total+hypot(pair.1.x-pair.0.x,pair.1.y-pair.0.y)
        }
        while points.count > 2,length > size.width*0.1 {
            length -= hypot(points[1].x-points[0].x,points[1].y-points[0].y);points.removeFirst()
        }
        return points
    }
}

extension MatchDetailedPlay {
    var reviewDisplayTimes:[Double] {
        let times = [0,decisionAt,duration] + (review?.ruling.map {[$0.at]+($0.bounceAt.map {[$0]} ?? [])} ?? [])
            + runners.flatMap {$0.nodes.map(\.at)} + runners.compactMap(\.retiredAt)
            + [controlAt] + (secondThrow.map {[$0.controlAt]} ?? [])
        return Array(Set(times.map {max(0,min(duration,$0))})).sorted()
    }

    /// 해당 타구의 전후만 읽는다. 후속 CPU 타석의 상태나 재판정을 섞지 않는다.
    func reviewDisplayMatch(at time:Double,saved:CareerMatch) -> CareerMatch? {
        guard let review,let before=review.before,let after=review.after else {return nil}
        if time >= duration {return after.displayMatch(saved)}
        var match=before.displayMatch(saved)
        let foul=review.ruling?.kind == .foul
        let deadAt=review.ruling?.at ?? .infinity
        if foul {
            if time >= deadAt {match.balls=after.balls;match.strikes=after.strikes}
            return match
        }
        var outs=before.outs
        let retired=runners.filter {$0.out && ($0.retiredAt ?? outAt) <= time}
        outs += retired.count
        let scored=runners.filter {!$0.out && $0.destination == 4 && $0.arrival <= time}.sorted {$0.arrival < $1.arrival}.prefix(runs).count
        if before.half.isMultiple(of:2) {match.awayScore += scored} else {match.homeScore += scored}
        match.outs=min(2,outs)
        var bases:[FieldRunnerProfile?]=[nil,nil,nil]
        for runner in runners where !retired.contains(where:{$0.from == runner.from}) {
            var base=runner.from
            if runner.destination > runner.from {
                for next in (runner.from+1)...runner.destination where (runner.arrival(at:next) ?? .infinity) <= time {base=next}
            }
            if (1...3).contains(base) {bases[base-1]=runner.profile}
        }
        if outs >= 3 {
            match.half=after.half;match.outs=after.outs;bases=after.runners
            match.homeOrder=after.homeOrder;match.awayOrder=after.awayOrder;match.completed=after.completed
        }
        match.runnerProfiles=bases;match.bases=bases.map {$0 != nil}
        return match
    }
}

struct MatchFieldReviewNotice: View {
    let play:MatchDetailedPlay
    let time:Double
    var body:some View {
        if let ruling=play.review?.ruling,time >= ruling.at,ruling.kind == .overthrow {
            VStack(alignment:.leading,spacing:8) {
                Text("볼 데드 · 투구 당시 위치에서 두 베이스").font(.headline).foregroundStyle(GameTheme.gold)
                ForEach(play.runners.sorted {$0.from < $1.from},id:\.from) {runner in
                    let source=runner.from == 0 ? "타자주자":"\(runner.from)루 주자"
                    let destination=runner.destination == 4 ? "홈":"\(runner.destination)루"
                    HStack(alignment:.top) {
                        Text(source).frame(maxWidth:.infinity,alignment:.leading)
                        Text(destination + (time >= runner.arrival ? " 도착":" 보장 · 이동 중"))
                            .foregroundStyle(time >= runner.arrival ? GameTheme.boardInk:GameTheme.gold)
                    }.font(.subheadline).fixedSize(horizontal:false,vertical:true)
                }
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(GameTheme.boardPanel)
                .foregroundStyle(GameTheme.boardInk).accessibilityElement(children:.contain)
                .accessibilityIdentifier("fieldAwardRoutes")
        }
    }
}

extension FieldReplayPresentation {
    static func reviewedPhase(_ play:MatchDetailedPlay,time:Double) -> String? {
        guard let review=play.review else {return nil}
        if let ruling=review.ruling,time >= ruling.at {
            if ruling.kind == .foul {return "파울 · 볼 데드 · 원래 루로 귀루"}
            if ruling.kind == .groundRuleDouble {return "인정 2루타 · 볼 데드 · 보장 진루 중"}
            if ruling.kind == .overthrow {return "덕아웃 악송구 · 볼 데드 · 보장 진루 중"}
        }
        let names=["투수","포수","1루수","2루수","3루수","유격수","좌익수","중견수","우익수"]
        if time < play.pickupAt {return nil}
        if review.heldAtSecond == true,time >= play.ballAt {return "2루수 포구 · 공 보유"}
        if let next=play.secondThrow,time >= play.ballAt {
            return time < next.releaseAt ? "2루수 포구 · 1루 재송구 준비"
                : time < next.ballAt ? "2루수 → 1루수 송구":"1루수 포구 · 베이스 터치 확인"
        }
        if let relay=play.relay,time >= play.releaseAt {
            return time < relay.receiveAt ? names[play.fielder]+" → "+names[relay.fielder]+" 중계"
                : time < relay.releaseAt ? names[relay.fielder]+" 포구 · 송구 준비"
                : time < play.ballAt ? names[relay.fielder]+" → "+names[play.receiver]+" 송구"
                : names[play.receiver]+" 포구 · 태그 확인"
        }
        if time < play.releaseAt {return names[play.fielder]+" 포구 · 송구 준비"}
        return time < play.ballAt ? names[play.fielder]+" → "+names[play.receiver]+" 송구"
            : names[play.receiver]+" 포구 · 주자와 베이스 확인"
    }
}

extension MatchHomeRun {
    var reviewDisplayTimes:[Double] {
        Array(Set([0,fenceCrossedAt,flight,duration]+runners.flatMap {$0.nodes.map(\.at)})).sorted()
    }
    func reviewDisplayMatch(at time:Double,saved:CareerMatch) -> CareerMatch? {
        guard let before=review?.before,let after=review?.after else {return nil}
        if time >= duration {return after.displayMatch(saved)}
        var match=before.displayMatch(saved),bases:[FieldRunnerProfile?]=[nil,nil,nil]
        let scored=runners.filter {$0.arrival <= time}.count
        if half.isMultiple(of:2) {match.awayScore += scored} else {match.homeScore += scored}
        for runner in runners where runner.arrival > time {
            var base=runner.from
            for next in (runner.from+1)...4 where (runner.arrival(at:next) ?? .infinity) <= time {base=next}
            if (1...3).contains(base) {bases[base-1]=runner.profile}
        }
        match.runnerProfiles=bases;match.bases=bases.map {$0 != nil};return match
    }
}

struct MatchFieldRulingOverlay:View {
    let play:MatchDetailedPlay
    let time:Double
    private var marks:[(String,FieldPoint,Bool)] {
        guard let ruling=play.review?.ruling else {return []}
        var marks:[(String,FieldPoint,Bool)]=[]
        if let at=ruling.bounceAt,let point=ruling.bouncePoint,time >= at {marks.append(("바운드",point,true))}
        if time >= ruling.at {
            let label:String
            switch ruling.kind {case .fairBase:label="페어";case .foul:label="파울";case .groundRuleDouble:label="장외";case .overthrow:label="볼 데드"}
            marks.append((label,ruling.point,false))
        }
        return marks
    }
    var body:some View {
        GeometryReader {geometry in
            ForEach(marks.indices,id:\.self) {index in
                let mark=marks[index],point=InplayFieldProjection.point(mark.1,size:geometry.size)
                let label=CGPoint(x:min(geometry.size.width-44,max(44,point.x+(mark.2 ? -48:48))),
                                  y:min(geometry.size.height-18,max(18,point.y+(mark.2 ? 30:-26))))
                Path {path in path.move(to:point);path.addLine(to:label)}
                    .stroke(GameTheme.gold.opacity(0.7),lineWidth:1)
                Circle().strokeBorder(GameTheme.gold,style:StrokeStyle(lineWidth:2,dash:mark.2 ? [3,3]:[]))
                    .frame(width:18,height:18).position(point)
                Text(mark.0).font(.caption.bold()).foregroundStyle(GameTheme.paper)
                    .padding(.horizontal,4).padding(.vertical,2).background(GameTheme.navy)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize().position(label)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MatchHomeRunRulingOverlay:View {
    let event:MatchHomeRun
    let time:Double
    var body:some View {
        if event.review != nil,time >= event.fenceCrossedAt {
            GeometryReader {geometry in
                let point=InplayFieldProjection.point(event.ball(at:event.fenceCrossedAt),size:geometry.size)
                Circle().strokeBorder(GameTheme.gold,lineWidth:2).frame(width:18,height:18).position(point)
                Text("직접 장외").font(.caption.bold()).foregroundStyle(GameTheme.paper)
                    .padding(.horizontal,4).padding(.vertical,2).background(GameTheme.navy).fixedSize()
                    .position(x:min(geometry.size.width-36,max(36,point.x)),y:max(12,point.y-24))
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
