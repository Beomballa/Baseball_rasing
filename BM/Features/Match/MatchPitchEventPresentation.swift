import SwiftUI
import SpriteKit

struct MatchPitchEventPresentationState {
    let event: MatchPitchEvent
    let resolved: Bool
    var after: MatchPitchState? { resolved ? event.after : nil }
    var afterText: String? {
        guard let after else { return nil }
        if after.half != event.before.half { return "3아웃 · 공수교대" }
        return (after.completed ? "경기 종료 · " : "") + "\(after.outs)아웃 · \(after.occupied)"
    }
    var confirmedCredit: MatchLoosePitchCredit? { resolved ? event.credit : nil }
    var heading: String {
        if event.kind == .foul {
            guard resolved else { return "투구 진행 중" }
            return event.before.strikes == 2 ? "2스트라이크 유지" : "스트라이크 \(event.before.strikes) → \(event.after.strikes)"
        }
        if resolved { return event.label }
        return event.kind == .hitByPitch ? "사구 · 볼 데드" : "포구 실패 · 주자 출발"
    }
}

struct MatchPitchEventNotice: View {
    let event: MatchPitchEvent
    let resolved: Bool
    var name: (String) -> String = { NPCIdentity.name($0) }
    var openComparison: (() -> Void)? = nil

    private var state: MatchPitchEventPresentationState { .init(event: event, resolved: resolved) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.heading).font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("pitchEventHeading")
            if event.kind == .foul {
                Text("파울 · 같은 타자 · 타석 계속").font(.subheadline)
            } else if event.kind == .hitByPitch {
                HStack(alignment: .top, spacing: 16) {
                    diamond.frame(width: 88, height: 88).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) { routes }
                }
                Text(resolved ? "진루 완료 · 다음 타자 0볼 0스트라이크" : "볼 데드 · 부여된 진루를 마칠 때까지 대기")
                    .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            } else if !resolved {
                Text(event.kind == .uncaughtThird ? "타자 주자가 1루 승부를 진행합니다." : "공을 회수하는 동안 주자가 진루합니다.")
                    .font(.subheadline)
            } else {
                routes
                if let observation = event.observation, event.credit != nil {
                    Text(observation.reason).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }
            }
            if resolved {
                Text(state.afterText ?? "").font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("pitchEventAfterState")
                if let credit = state.confirmedCredit {
                  VStack(spacing: 0) {
                    Button { openComparison?() } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("기록").foregroundStyle(GameTheme.boardMuted)
                            Text((credit == .wild ? "투수 · " : "포수 · ") + credit.label + " +1")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(openComparison == nil)
                        .accessibilityHint("이번 투구와 비교 예시를 같은 재생 시점에서 확인합니다.")
                        .accessibilityIdentifier("openPitchCatchComparison")
                  }.accessibilityElement(children: .contain)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
            .foregroundStyle(GameTheme.boardInk).accessibilityElement(children: .contain)
            .accessibilityIdentifier("pitchEventNotice")
    }
    @ViewBuilder private var routes: some View {
        if let play = event.play {
            ForEach(play.runners.sorted(by: { $0.from < $1.from }), id: \.from) { runner in
                let id = runner.profile.id ?? (runner.from == 0 ? event.batter : "")
                let origin = runner.from == 0 ? "타자" : "\(runner.from)루 주자"
                let target = runner.destination == 4 ? "홈" : "\(runner.destination)루"
                Text(origin + " " + name(id) + " · " + (runner.out ? "1루 아웃" : runner.from == runner.destination ? "대기" : "→ " + target))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        } else if event.kind == .uncaughtThird {
            Text("투구 당시 1루 점유 · 2아웃 전에는 타자 진루 불가").font(.subheadline)
        }
    }
    private var diamond: some View {
        Canvas { context, size in
            let points = [CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.9)]
                .map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            var outline = Path(); outline.addLines(points)
            context.stroke(outline, with: .color(GameTheme.boardLine), lineWidth: 2)
            for runner in event.play?.runners ?? [] where runner.destination > runner.from {
                let from = points[runner.from], to = points[runner.destination]
                var route = Path(); route.move(to: from); route.addLine(to: to)
                context.stroke(route, with: .color(GameTheme.gold), style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
                context.draw(Text("›").font(.headline.bold()).foregroundStyle(GameTheme.gold), at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2))
            }
            for i in 0..<4 {
                context.fill(Path(CGRect(x: points[i].x - 4, y: points[i].y - 4, width: 8, height: 8)), with: .color(GameTheme.paper))
            }
        }
    }
}

/// 두 비교 화면의 시계만 공유한다. 경기 전이·난수·저장에는 접근하지 않는다.
struct PitchCatchComparison: View {
    let event: MatchPitchEvent
    let role: PlayerRole
    let appearance: PlayerAppearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = 0.0
    @State private var playing = false
    private var actual: MatchCatchObservation { event.observation! }
    private var comparison: MatchCatchObservation {
        MatchPitchEventRules.observation(x: actual.credit == .wild ? 0.5 : 1.2, y: 0.6,
            defense: actual.catcherDefense, escape: actual.escape)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(event.label + " · 포구 순간 비교").font(.headline).foregroundStyle(GameTheme.gold)
                    Text("이번 투구와 반대 유형의 비교 예시입니다. 비교 예시는 경기 기록에 반영되지 않습니다.")
                        .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                    VStack(alignment: .leading, spacing: 16) {
                        pane(actual, title: "이번 투구 · " + actual.credit.label)
                        pane(comparison, title: "비교 예시 · " + comparison.credit.label)
                    }
                    Text("공통 재생 시점 \(phase * 100, specifier: "%.0f")%").font(.subheadline.monospacedDigit())
                    Slider(value: $phase, in: 0...1, step: 0.01).accessibilityLabel("포구 비교 재생 시점")
                        .accessibilityIdentifier("pitchCatchTimeline")
                    HStack(spacing: 12) {
                        Button("처음으로") { playing = false; phase = 0 }.buttonStyle(MatchPixelButtonStyle())
                        Button(reduced ? "다음 장면" : playing ? "일시정지" : "같이 재생") {
                            if reduced { phase = min(1, phase + 0.25) }
                            else { if phase == 1 { phase = 0 }; playing.toggle() }
                        }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("pitchCatchPlay")
                    }
                }.padding(16)
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .navigationTitle("포구 순간").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("closePitchCatchComparison")
                }}
        }.preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, value in if value != .active { playing = false } }
            .task(id: playing) {
                guard playing, !reduced else { return }
                let start = ProcessInfo.processInfo.systemUptime - phase * 2.5
                while playing && !Task.isCancelled {
                    phase = min(1, (ProcessInfo.processInfo.systemUptime - start) / 2.5)
                    if phase >= 1 { playing = false; break }
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
                }
            }
    }
    private func pane(_ observation: MatchCatchObservation, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.body.bold())
            CatchFlightCanvas(observation: observation, role: role, appearance: appearance, phase: phase)
                .frame(maxWidth: 310).accessibilityHidden(true)
            Text(observation.bounced ? "홈 앞에서 바운드한 공" : "포구 높이로 들어오는 공")
                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            Text(observation.reason).font(.subheadline)
        }.padding(12).background(GameTheme.boardPanel)
    }
}

private struct CatchFlightCanvas: View {
    let observation: MatchCatchObservation
    let role: PlayerRole
    let appearance: PlayerAppearance
    let phase: Double
    @State private var catcher: UIImage?
    private var background: UIImage? { MatchArt.image(role == .batter ? "batter-field-v52" : "pitcher-field-v52") }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let end = MatchPitchProjection(role: role).normalizedPoint(x: observation.x, y: observation.y)
            let start = role == .batter ? CGPoint(x: 0.51, y: 0.455) : CGPoint(x: 0.32, y: 0.55)
            ZStack {
                if let image = background {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                }
                if let catcher {
                    Image(uiImage: catcher).resizable().interpolation(.none).scaledToFit()
                        .frame(width: size.width * (role == .batter ? 0.28 : 0.22), height: size.height * (role == .batter ? 0.28 : 0.22))
                        .position(x: size.width * 0.5, y: size.height * (role == .batter ? 0.74 : 0.41))
                }
                Canvas { context, _ in
                    let origin = CGPoint(x: start.x * size.width, y: start.y * size.height)
                    let contact = CGPoint(x: end.x * size.width, y: end.y * size.height)
                    let exit = CGPoint(x: contact.x + 0.12 * size.width, y: contact.y + 0.16 * size.height)
                    var path = Path(); path.move(to: origin); path.addLine(to: contact); path.addLine(to: exit)
                    context.stroke(path, with: .color(GameTheme.paper.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    let progress = phase < 0.6 ? phase / 0.6 : (phase - 0.6) / 0.4
                    let from = phase < 0.6 ? origin : contact, to = phase < 0.6 ? contact : exit
                    var ball = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
                    if observation.bounced && phase >= 0.6 { ball.y -= 20 * sin(progress * .pi) }
                    context.stroke(Path(ellipseIn: CGRect(x: contact.x - 6, y: contact.y - 6, width: 12, height: 12)), with: .color(GameTheme.gold), style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    context.fill(Path(CGRect(x: ball.x - 4, y: ball.y - 4, width: 8, height: 8)), with: .color(.white))
                }
            }.frame(width: size.width, height: size.height).clipped()
        }.aspectRatio(background.map { $0.size.width / $0.size.height } ?? 1, contentMode: .fit)
            .task {
                if let texture = OpponentMotionArt.textures("catcher-parts", columns: 2, rows: 2,
                    ownKit: appearance.uniformColor, opponent: false,
                    teamColor: role == .pitcher ? appearance.uniformColor : appearance.opponentUniformColor,
                    style: role == .pitcher ? appearance.uniformStyle : appearance.opponentUniformStyle).first {
                    catcher = UIImage(cgImage: texture.cgImage())
                }
            }
    }
}

/// 이름과 상태는 해당 경기 원장에서만 읽는다. 조회 시 최신 구단/선수 정보로 덮지 않는다.
struct MatchPitchEventNames: Equatable {
    private let values: [String: String]
    init(match: CareerMatch, careerName: String) {
        var names: [String: String] = [:]
        for team in [match.npcAttack?.home, match.npcAttack?.away].compactMap({ $0 }) {
            for batter in team.batters { names[batter.id] = batter.displayName }
            names[team.starter.id] = team.starter.displayName
            names[team.relief.id] = team.relief.displayName
        }
        if let id = match.playerRecords?.careerID { names[id.uuidString] = careerName }
        for team in [match.playerRecords?.home, match.playerRecords?.away].compactMap({ $0 }) {
            for change in team.runnerChanges ?? [] where names[change.replacement] == nil { names[change.replacement] = "대주자" }
        }
        values = names
    }
    func name(_ id: String) -> String {
        if let name = values[id] { return name }
        let name = NPCIdentity.name(id)
        return name == "이름 미기록" ? "이름 미기록" : name
    }
}

extension MatchPitchState {
    /// 저장 완료 상태를 복사해 해당 투구 도착 시점만 투영한다. 엔진·저장·보상은 실행하지 않는다.
    func displayMatch(_ saved: CareerMatch) -> CareerMatch {
        var match = saved
        match.half = half; match.outs = outs; match.balls = balls; match.strikes = strikes
        match.homeScore = home; match.awayScore = away; match.homeOrder = homeOrder; match.awayOrder = awayOrder
        match.runnerProfiles = runners; match.bases = runners.map { $0 != nil }; match.completed = completed
        return match
    }
}



// 주루의 표시 시점만 투영한다. 같은 저장 결과의 포구·터치·태그 경계를 읽고 다시 판정하지 않는다.
extension MatchRunningEvent {
    var displayTimes: [Double] { play.runningDisplayTimes }
    func displayMatch(at time: Double, saved: CareerMatch) -> CareerMatch {
        if time >= play.decisionAt { return after.displayMatch(saved) }
        if time < play.pickupAt { return before.displayMatch(saved) }
        var match = movementBefore.displayMatch(saved)
        let third = (play.outsBefore ?? 0) + play.outsAdded == 3
        for runner in play.runners where !runner.out && runner.arrival <= time {
            if runner.destination == 4, !third || runner.arrival < play.controlAt {
                match.runnerProfiles?[runner.from - 1] = nil
                if play.half.isMultiple(of: 2) { match.awayScore += 1 } else { match.homeScore += 1 }
            } else if runner.destination != runner.from, (1...3).contains(runner.destination) {
                match.runnerProfiles?[runner.from - 1] = nil
                match.runnerProfiles?[runner.destination - 1] = runner.profile
            }
        }
        match.bases = match.runnerProfiles?.map { $0 != nil } ?? match.bases
        return match
    }
}


extension MatchDetailedPlay {
    var runningDisplayTimes: [Double] {
        guard runningEvent != nil else { return [] }
        return Array(Set([pickupAt,controlAt,decisionAt] + runners.filter { !$0.out }.map(\.arrival)))
            .filter { $0 >= 0 && $0 <= decisionAt }.sorted()
    }
}
