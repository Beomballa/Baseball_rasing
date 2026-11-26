import SwiftUI

extension MatchDetailedPlay {
    /// 저장된 중간 사건만 투영한다. 표시 중 어필 판단이나 경기 저장을 실행하지 않는다.
    func appealDisplayMatch(at time: Double, saved: CareerMatch) -> CareerMatch? {
        guard let event = appeal, let before = review?.before, let after = review?.after else { return nil }
        if time >= event.finalizedAt { return after.displayMatch(saved) }
        var match = before.displayMatch(saved)
        guard let stage = event.stages.last(where: { $0.at <= time }) else { return match }
        match.outs = stage.outs
        if half % 2 == 1 { match.homeScore += stage.runs } else { match.awayScore += stage.runs }
        var occupied: [FieldRunnerProfile?] = [nil,nil,nil]
        for runner in runners where !stage.retired.contains(runner.from) {
            var base = runner.from
            if runner.destination > runner.from {
                for next in (runner.from+1)...runner.destination where (runner.arrival(at: next) ?? .infinity) <= time { base = next }
            }
            if (1...3).contains(base), stage.outs < 3 { occupied[base-1] = runner.profile }
        }
        match.runnerProfiles = occupied; match.bases = occupied.map { $0 != nil }
        return match
    }
    func rulePhase(at time: Double) -> String? {
        if let appeal { return appeal.stages.last(where: { $0.at <= time })?.title }
        guard let event = special else { return nil }
        if event.kind == .sharedBase, time < event.at {
            let contacts = runners.filter { $0.from == targetBase || $0.from == targetBase-1 }.compactMap { $0.arrival(at: targetBase) }
            if contacts.count == 2, time >= contacts.max()! { return "\(targetBase)루 두 주자 접촉 · 태그 대기" }
        }
        guard time >= event.at else { return nil }
        switch event.kind {
        case .interference:
            return (outsBefore ?? 0)+outsAdded == 3 ? "수비방해 · 세 번째 아웃 · 볼 데드" : "수비방해 · 주자 아웃 · 볼 데드"
        case .obstruction:
            if time < (event.awardedAt ?? .infinity) { return "주루방해 · 볼 데드 · 주자 정지" }
            if time < (event.resumeAt ?? .infinity) { return "2루 부여 · 야수가 진로를 비웁니다" }
            let arrival = runners.first?.arrival ?? event.settledAt
            return time < arrival ? "타자주자 · 2루로 이동" : "단타 · 2루 도착"
        case .passing: return "선행 주자 추월 · 후속 주자 아웃 · 인플레이"
        case .sharedBase:
            guard let tag = event.tags.last(where: { $0.at <= time }) else { return nil }
            return (tag.from == targetBase ? "선행 주자" : "후속 주자") + (tag.out ? " 태그 아웃" : " 태그 세이프")
        }
    }
}

struct MatchInplayRuleOverlay: View {
    let play: MatchDetailedPlay
    let time: Double
    private var marker: (FieldPoint,String)? {
        if let event = play.special, time >= event.at {
            switch event.kind {
            case .interference: return (event.point,"수비방해")
            case .obstruction: return (event.point,"주루방해")
            case .passing: return (event.point,"추월")
            case .sharedBase:
                let tag = event.tags.last { $0.at <= time }
                return (event.point,tag?.out == true ? "태그 아웃" : "태그 확인")
            }
        }
        return nil
    }
    var body: some View {
        GeometryReader { geometry in
            if let event = play.special, event.kind == .obstruction,
               let runner = play.runners.first(where: { $0.from == 0 }) {
                let nodes = runner.nodes.filter { $0.at <= time } + [.init(at:time,point:FieldNode.sample(runner.nodes,at:time))]
                Path { path in
                    for (index,node) in nodes.enumerated() {
                        let point = InplayFieldProjection.point(node.point,size:geometry.size)
                        if index == 0 { path.move(to:point) } else { path.addLine(to:point) }
                    }
                }.stroke(GameTheme.gold,style:StrokeStyle(lineWidth:2,dash:[4,3]))
            }
            if let marker {
                let point = InplayFieldProjection.point(marker.0,size:geometry.size)
                Circle().strokeBorder(GameTheme.gold,lineWidth:2).frame(width:22,height:22).position(point)
                Text(marker.1).font(.caption.bold()).dynamicTypeSize(...DynamicTypeSize.xxxLarge).foregroundStyle(GameTheme.paper)
                    .padding(.horizontal,4).padding(.vertical,2).background(GameTheme.navy).fixedSize()
                    .position(x:min(geometry.size.width-44,max(44,point.x)),y:max(14,point.y-24))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct MatchInplayRuleNotice: View {
    let play: MatchDetailedPlay
    let time: Double
    var body: some View {
        if let event = play.appeal, let stage = event.stages.last(where: { $0.at <= time }) {
            Text(stage.detail).font(.subheadline.weight(.semibold)).foregroundStyle(GameTheme.boardInk)
                .frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                .padding(.horizontal,8).padding(.bottom,6).accessibilityIdentifier("appealScoreStatus")
        }
    }
}

struct MatchHistoryCorrection: Equatable, Identifiable {
    let change: MatchRecordCorrection
    let teamID: String?
    let team: String
    let home: Bool
    let batter: String
    let ordinal: Int?
    var id: String { change.id }
    var original: String { (change.proof.play?.fielder ?? 6) < 6 ? "내야 안타" : "안타" }
    var applied: String {
        if change.atCompletion { return "경기 완료 처리 전" }
        return "\(change.appliedHalf/2+1)회 \(change.appliedHalf % 2 == 0 ? "초" : "말") 시작 전"
    }
    var base: String {
        guard let runner = change.proof.play?.runners.first(where: { $0.from == 0 }), !runner.out else { return "주자 상태 미기록" }
        return runner.destination == 4 ? "해당 타석 홈 도착" : "해당 타석 \(runner.destination)루 유지"
    }
}
struct MatchRecordCorrectionCard: View {
    let value: MatchHistoryCorrection
    private let schools = (try? SchoolCatalog.load()) ?? []
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var stampSize: CGFloat = 28
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8))
                : AnyLayout(HStackLayout(alignment:.center,spacing:8))
            layout {
                HStack(alignment:.top,spacing:8) {
                    MatchTeamCrest(teamID:value.teamID,name:value.team,schools:schools).frame(width:28,height:28).accessibilityHidden(true)
                    Text(value.team+" · "+(value.home ? "홈":"원정")).font(.subheadline.weight(.semibold))
                }.frame(maxWidth:.infinity,alignment:.leading)
                Text("기록 변경 이력").font(.subheadline.weight(.semibold)).foregroundStyle(GameTheme.gold)
            }
            Rectangle().fill(GameTheme.boardLine).frame(height:1).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:4) {
                Text(value.batter).font(.body.weight(.semibold))
                Text("\(value.change.proof.context.order % 9+1)번 타자 · \(value.change.proof.context.half/2+1)회 "
                    + (value.home ? "말":"초") + (value.ordinal.map { " \($0)번째 타석" } ?? " · 순번 미기록"))
                    .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            }
            VStack(alignment:.leading,spacing:16) {
                stamp("H",label:"최초 기록",result:value.original,time:"해당 타석 판정")
                stamp("E",label:"정정 반영",result:"실책 출루",time:value.applied)
            }
            Rectangle().fill(GameTheme.boardLine).frame(height:1).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:8) {
                Text("정정 사유").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                Text(value.change.reason).font(.subheadline)
                Text(value.base).font(.subheadline.weight(.semibold)).foregroundStyle(GameTheme.gold)
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(GameTheme.board)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:1))
            .fixedSize(horizontal:false,vertical:true).accessibilityElement(children:.contain)
            .accessibilityIdentifier("gameHistoryCorrection-"+value.id)
    }
    private func stamp(_ mark: String,label: String,result: String,time: String) -> some View {
        HStack(alignment:.top,spacing:12) {
            Text(mark).font(.subheadline.monospaced().bold()).frame(width:stampSize,height:stampSize)
                .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:1)).foregroundStyle(mark == "E" ? GameTheme.gold:GameTheme.boardInk)
            VStack(alignment:.leading,spacing:4) {
                Text(label).font(.footnote).foregroundStyle(GameTheme.boardMuted)
                Text(result).font(.body.weight(.semibold))
                Text(time).font(.footnote).foregroundStyle(GameTheme.boardMuted)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
    }
}
