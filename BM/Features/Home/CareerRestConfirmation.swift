import SwiftUI
import SwiftData
import UIKit

struct CareerRestConfirmation: View {
    let player: CareerPlayer
    let state: CareerCalendarState
    let revision: Int
    var returnTitle = "홈으로 돌아가기"
    var onCompleted: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var training: [CareerTrainingRecord]
    @State private var failure: String?
    @State private var completed = false
    @State private var before = 0
    private var pending: Bool { training.contains { $0.playerID == player.id && !$0.completed } }
    private var used: Bool { state.hasAction(on: player.gameDate) }
    var onContinue: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var recovering = false
    @State private var recoveryTask: Task<Void, Never>?
    @State private var displayFatigue = 0.0
    @State private var scheduleRetry = 0
    @State private var restPose = RestPlayerPose.standing
    private var scheduleStatus: CalendarScheduleStatus { CalendarScheduleStatus(player: player, state: state) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        PixelPlayer(appearance: player.appearance).frame(width: 36, height: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.name + " · #" + String(player.jerseyNumber)).managementFont(.label)
                            Text(ManagementDisplay.date(player.gameDate)).managementFont(.helper)
                        }
                        Spacer(minLength: 0)
                    }.padding(16)
                    RestBenchScene(appearance: player.appearance, number: player.jerseyNumber, pose: restPose)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recovering ? "잠시 숨을 돌리는 중…" : completed ? "몸을 충분히 쉬었어요" : "오늘은 회복에 집중하자")
                            .font(ManagementPixelFont.readable(.sectionTitle)).accessibilityAddTraits(.isHeader)
                        Text(completed ? "피로 \(before) → \(player.fatigue)" : "피로 \(player.fatigue) → \(DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest))")
                            .managementFont(.metric).monospacedDigit().accessibilityIdentifier("restFatigueForecast")
                        ProgressView(value: completed ? displayFatigue : Double(player.fatigue), total: 100).tint(Color(hex: 0x237459))
                            .accessibilityLabel("피로").accessibilityValue("\(player.fatigue) / 100")
                        Text("휴식 최대 −\(DailyRecovery.rest) · 다음 날 수면 −\(DailyRecovery.sleep)은 별도").managementFont(.helper)
                        if let error = scheduleStatus.errorMessage, !completed {
                            Text("일정 확인 전에는 휴식할 수 없습니다. " + error).managementFont(.body).accessibilityIdentifier("restScheduleError")
                            Button("일정 다시 확인") { scheduleRetry += 1 }.frame(minHeight: 44).id(scheduleRetry)
                        }
                        if pending && !completed { Text("진행 중인 훈련을 먼저 마쳐 주세요.").managementFont(.body).accessibilityIdentifier("restPendingGate") }
                        else if used && !completed { Text("오늘 행동을 이미 사용했습니다.").managementFont(.body).accessibilityIdentifier("restActionGate") }
                        if let failure { Text(failure).managementFont(.body).foregroundStyle(Color(hex: 0x8b431b)).accessibilityIdentifier("restError") }
                        if completed && !recovering { Text("휴식을 저장했습니다.").managementFont(.label).accessibilityIdentifier("restSaved") }
                    }.padding(16).foregroundStyle(GameTheme.navy).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardInk)
                }
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                        Text(completed ? "오늘 행동 사용 완료 · 날짜 유지" : "오늘 행동 1회 · 날짜 유지").managementFont(.helper)
                        if recovering {
                            Button("회복 연출 건너뛰기") { finishRecovery() }.buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("skipRestPresentation")
                        } else if completed {
                            if let onContinue {
                                Button("경기 · 다음 일정 확인") { onContinue(); dismiss() }.buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("restGoGame")
                            }
                            Button(returnTitle) { dismiss() }.buttonStyle(ManagementButtonStyle(variant: onContinue == nil ? .primary : .secondary)).accessibilityIdentifier("restDone")
                        } else {
                            Button("휴식하기", action: save).buttonStyle(ManagementButtonStyle())
                                .disabled(used || pending || CalendarScheduleStatus(player: player, state: state).schedule == nil).accessibilityIdentifier("confirmRest")
                            Button("취소 · 돌아가기") { dismiss() }.frame(minHeight: 44)
                        }
                    }.padding(12).foregroundStyle(GameTheme.boardInk).background(GameTheme.board)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .navigationTitle("휴식").navigationBarTitleDisplayMode(.inline)
                .toolbar { ManagementToolbarAction(title: "닫기") { dismiss() } }
        }.preferredColorScheme(.dark).presentationDragIndicator(.visible)
            .onDisappear { recoveryTask?.cancel() }
            .onChange(of: reduced) { _, value in if value && recovering { finishRecovery() } }
    }
    private func finishRecovery() {
        recoveryTask?.cancel(); displayFatigue = Double(player.fatigue); recovering = false; restPose = .standing
    }
    private func save() {
        do {
            let old = player.fatigue
            try CalendarProgression.rest(player: player, state: state, revision: revision, in: context)
            before = old; completed = true; failure = nil; onCompleted?()
            displayFatigue = Double(old)
            if reduced { finishRecovery() }
            else {
                recovering = true
                restPose = .sitDown
                withAnimation(.easeOut(duration: 3.2)) { displayFatigue = Double(player.fatigue) }
                recoveryTask = Task { @MainActor in
                    let steps: [(RestPlayerPose, Double)] = [(.seated, 0.35), (.raiseBottle, 0.45), (.drink, 0.45), (.lowerBottle, 1.1), (.standUp, 0.4), (.standing, 0.45)]
                    for (pose, seconds) in steps {
                        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                        guard !Task.isCancelled else { return }; restPose = pose
                    }
                    finishRecovery()
                }
            }
        } catch { failure = error.localizedDescription }
    }
}


// Read-only route selection; commands remain in their existing destination screens.
enum GameLobbyAction: Equatable {
    case unavailable, schedule, training, season, game(String)
    var title: String {
        switch self {
        case .unavailable: "일정 다시 확인"
        case .schedule: "다음 일정 확인"
        case .training: "훈련 이어하기"
        case .season: "시즌 결산 확인"
        case .game(let title): title
        }
    }
    static func resolve(scheduleAvailable: Bool, trainingPending: Bool, seasonComplete: Bool,
                        fixture: SeasonFixture?, saved: CalendarSavedMatch, entry: String) -> Self {
        guard scheduleAvailable else { return .unavailable }
        if trainingPending { return .training }
        if case .playing = saved { return .game(entry) }
        if seasonComplete { return .season }
        return fixture == nil ? .schedule : .game(entry)
    }
}

// Presentation-only poses. Their transitions never invoke a career command.
enum RestPlayerPose: Int, CaseIterable {
    case standing, sitDown, seated, raiseBottle, drink, lowerBottle, standUp
}

@MainActor enum RestPlayerArt {
    static func frames(appearance: PlayerAppearance, number: Int) -> [UIImage] {
        guard appearance.isValid,
              let sample = FieldRasterArt.samples(FieldSpriteMotion(facing: .south, stage: .ready), kind: "fielder", left: false).first,
              let source = FieldRasterArt.image(sample, kit: PlayerAppearance.kitColors[appearance.kit],
                  skin: PlayerAppearance.skinColors[appearance.skin], hair: PlayerAppearance.hairColors[appearance.hair], number: number, back: false),
              let pixels = source.cgImage,
              let head = pixels.cropping(to: CGRect(x: 0, y: 0, width: pixels.width, height: Int(Double(pixels.height) * 0.44))) else { return [] }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return RestPlayerPose.allCases.map { pose in
            UIGraphicsImageRenderer(size: CGSize(width: 160, height: 170), format: format).image { renderer in
                let c = renderer.cgContext; c.interpolationQuality = .none
                if pose == .standing {
                    source.draw(in: CGRect(x: 17, y: 8, width: 126, height: 145)); return
                }
                let lift: CGFloat = pose == .sitDown || pose == .standUp ? -10 : 0
                func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Int) {
                    c.setFillColor(UIColor(Color(hex: color)).cgColor)
                    c.fill(CGRect(x: x, y: y + lift, width: w, height: h))
                }
                let kit = PlayerAppearance.kitColors[appearance.kit], skin = PlayerAppearance.skinColors[appearance.skin]
                // Bent thighs, shins and cleats use the same field uniform palette.
                box(48, 105, 65, 19, 0x102336); box(50, 107, 61, 13, 0xf1f3e9)
                box(94, 117, 19, 36, 0x102336); box(97, 119, 13, 29, 0xf1f3e9)
                box(54, 117, 18, 34, 0x102336); box(57, 119, 12, 27, 0xd1dcda)
                box(92, 147, 29, 9, 0x102336); box(51, 146, 28, 9, 0x102336)
                box(95, 153, 24, 3, 0xf1f3e9); box(54, 152, 23, 3, 0xf1f3e9)
                box(47, 68, 66, 41, 0x102336); box(50, 70, 60, 36, kit)
                box(50, 72, 5, 32, 0x7690a0); box(75, 71, 5, 34, 0xf1f3e9)
                box(40, 75, 12, 18, kit); box(40, 91, 12, 19, skin)
                let raised = pose == .raiseBottle || pose == .drink
                box(109, 76, 13, raised ? 13 : 19, kit)
                box(114, raised ? 62 : 93, 11, raised ? 25 : 17, skin)
                if raised { box(101, 58, 23, 10, skin) }
                if pose == .drink {
                    box(101, 59, 29, 13, 0x102336)
                    box(103, 61, 25, 9, 0x55bdeb)
                    box(111, 61, 8, 9, 0xf1f3e9)
                    box(98, 62, 6, 7, 0xd8f1f2)
                } else {
                    let bottleX: CGFloat = raised ? 102 : 118, bottleY: CGFloat = raised ? 49 : 102
                    box(bottleX, bottleY, 12, 24, 0x102336)
                    box(bottleX + 2, bottleY + 2, 8, 20, 0x55bdeb)
                    box(bottleX + 3, bottleY + 6, 6, 7, 0xf1f3e9)
                    box(bottleX + 2, bottleY - 3, 8, 5, 0xd8f1f2)
                }
                // Reuse the actual personalized match head; only the resting limbs are new.
                UIImage(cgImage: head).draw(in: CGRect(x: 17, y: 8 + lift, width: 126, height: 64))
                let text = String(number) as NSString
                text.draw(at: CGPoint(x: 84, y: 83 + lift), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .black), .foregroundColor: UIColor.white])
            }
        }
    }
}

struct RestBenchScene: View {
    let appearance: PlayerAppearance
    let number: Int
    let pose: RestPlayerPose
    @State private var frames: [UIImage] = []
    private var identity: String { "\(appearance.skin)-\(appearance.hair)-\(appearance.kit)-\(number)" }
    var body: some View {
        ZStack {
            Image("RestBenchV69").resizable().interpolation(.none).scaledToFit()
            GeometryReader { g in
                if frames.indices.contains(pose.rawValue) {
                    Image(uiImage: frames[pose.rawValue]).resizable().interpolation(.none)
                        .frame(width: g.size.width * 0.42, height: g.size.width * 0.446)
                        .position(x: g.size.width * 0.56, y: g.size.height * 0.65)
                } else {
                    PixelPlayer(appearance: appearance).frame(width: 64, height: 80)
                        .position(x: g.size.width * 0.56, y: g.size.height * 0.65)
                }
            }
        }.accessibilityHidden(true)
            .task(id: identity) { frames = RestPlayerArt.frames(appearance: appearance, number: number) }
    }
}
