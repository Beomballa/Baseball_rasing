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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var recovering = false
    @State private var recoveryTask: Task<Void, Never>?
    @State private var displayFatigue = 0.0
    @State private var scheduleRetry = 0
    private var scheduleStatus: CalendarScheduleStatus { CalendarScheduleStatus(player: player, state: state) }
    private var renderAppearance: PlayerAppearance {
        ManagementPlayerAffiliation.read(player: player, calendar: state).appearance
    }
    private var fatigueBefore: Int { completed ? before : player.fatigue }
    private var fatigueAfter: Int { completed ? player.fatigue : DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        ManagementPortrait(appearance: renderAppearance, role: player.role, number: player.jerseyNumber)
                            .frame(width: 48, height: 48).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.name + " · #" + String(player.jerseyNumber)).managementFont(.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ManagementDisplay.date(player.gameDate)).managementFont(.helper)
                        }
                        Spacer(minLength: 0)
                    }.padding(16)
                    Image("RestBenchV69").resizable().interpolation(.none).scaledToFill()
                        .frame(height: typeSize.isAccessibilitySize ? 112 : 144).clipped()
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DUGOUT RECOVERY").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.muted)
                        Text(recovering ? "휴식을 저장했어요" : completed ? "회복을 마쳤어요" : "잠깐 쉬어갈까요?")
                            .font(ManagementPixelFont.readable(.sectionTitle)).accessibilityAddTraits(.isHeader)
                        fatigueReceipt
                        Text("피로 \(max(0, fatigueBefore - fatigueAfter)) " + (completed ? "회복" : "회복 예상"))
                            .font(.subheadline.bold()).foregroundStyle(Color(hex: 0x1c6b54))
                            .padding(.horizontal, 8).padding(.vertical, 5).background(Color(hex: 0xd8e1c6))
                        Divider().overlay(GameTheme.muted.opacity(0.3))
                        recoveryOutcome("오늘 행동", value: completed || !used ? "1 / 1 → 0 / 1" : "0 / 1 · 사용 완료")
                        recoveryOutcome("현재 일자", value: ManagementDisplay.date(player.gameDate) + " · 유지")
                        if let error = scheduleStatus.errorMessage, !completed {
                            Text("일정 확인 전에는 휴식할 수 없습니다. " + error).managementFont(.body).accessibilityIdentifier("restScheduleError")
                            Button("일정 다시 확인") { scheduleRetry += 1 }.frame(minHeight: 44).id(scheduleRetry)
                        }
                        if pending && !completed { Text("진행 중인 훈련을 먼저 마쳐 주세요.").managementFont(.body).accessibilityIdentifier("restPendingGate") }
                        else if used && !completed { Text("오늘 행동을 이미 사용했습니다.").managementFont(.body).accessibilityIdentifier("restActionGate") }
                        if let failure { Text(failure).managementFont(.body).foregroundStyle(Color(hex: 0x8b431b)).accessibilityIdentifier("restError") }
                        if completed && !recovering { Text("휴식을 저장했습니다.").managementFont(.label).accessibilityIdentifier("restSaved") }
                    }.padding(16).foregroundStyle(GameTheme.navy).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardInk)
                    DisclosureGroup("다음 날 진행과는 달라요") {
                        Text("휴식은 오늘 행동을 사용해 최대 \(DailyRecovery.rest)을 회복하고 날짜를 유지합니다. 다음 날 진행 시 수면 회복 \(DailyRecovery.sleep)은 별도로 반영됩니다.")
                            .font(.subheadline).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }.font(.subheadline).tint(GameTheme.gold).padding(16)
                }
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                        if typeSize.isAccessibilitySize {
                            Text(fatigueText).managementFont(.label).accessibilityIdentifier("restPinnedFatigue")
                        }
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
    private var fatigueText: String {
        completed ? "피로 \(before) → \(player.fatigue)" : "피로 \(player.fatigue) → \(DailyRecovery.recover(player.fatigue, by: DailyRecovery.rest))"
    }
    private var fatigueReceipt: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            fatigueColumn(title: completed ? "휴식 전 피로" : "현재 피로", value: fatigueBefore,
                progress: Double(fatigueBefore), color: Color(hex: 0x94734f))
            Text(typeSize.isAccessibilitySize ? "↓" : "→").managementFont(.metric).foregroundStyle(GameTheme.muted)
                .accessibilityLabel(fatigueText).accessibilityIdentifier("restFatigueForecast")
            fatigueColumn(title: completed ? "저장된 피로" : "휴식 후 예상", value: fatigueAfter,
                progress: completed ? displayFatigue : Double(fatigueAfter), color: Color(hex: 0x237459))
        }
    }
    private func fatigueColumn(title: String, value: Int, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value)").font(.system(.largeTitle, design: .monospaced, weight: .bold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(GameTheme.muted).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: progress, total: 100).tint(color)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
    }
    private func recoveryOutcome(_ title: String, value: String) -> some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))) {
            Text(title).font(.subheadline).foregroundStyle(GameTheme.muted)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value).font(.subheadline.monospacedDigit().bold()).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
    private func finishRecovery() {
        recoveryTask?.cancel(); displayFatigue = Double(player.fatigue); recovering = false
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
                withAnimation(.easeOut(duration: 3.2)) { displayFatigue = Double(player.fatigue) }
                recoveryTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(3.2)) } catch { return }
                    guard !Task.isCancelled else { return }
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
        case .schedule: "다음 일정 · 날짜 진행"
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
        if case .completed = saved { return .schedule }
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
