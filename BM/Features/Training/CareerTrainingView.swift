import SwiftUI
import SwiftData
import SpriteKit

struct CareerTrainingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var chromeHeights: [String: CGFloat] = [:]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    private var reduced: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-management-career-verification") && ProcessInfo.processInfo.arguments.contains("-management-reduced-motion-verification") { return true }
        #endif
        return systemReduced
    }
    let player: CareerPlayer
    let calendar: CareerCalendarState
    var practice = false
    var initialKind: TrainingKind? = nil
    var initialPitchStudyCode: String? = nil
    var replacingPitchCode: String? = nil
    @State private var initialSelectionApplied = false
    @State private var record: CareerTrainingRecord?
    @State private var training: CareerTraining?
    @State private var code = ""
    @State private var pitchVelocity = 62.5
    private func delivery(code: String) -> MatchDelivery { .pitch(code: code, velocity: pitchVelocity) }
    @State private var kind = TrainingKind.contact
    @State private var category = 0
    @State private var footfalls: [SprintFoot] = []
    @State private var lastFootfallTime = 0.0
    @State private var throwAngle = 0.0
    @State private var throwForce = 50.0
    @State private var throwBase = 1
    @State private var force = 70.0
    @State private var angle = 35.0
    @State private var replay: CareerTraining?
    @State private var replayStarted = Date()
    @State private var replayTask: Task<Void, Never>?
    @State private var replayScore: Int?
    @State private var feedbackVisible = false
    @State private var reviewReady = false
    @State private var coachNote: TrainingCoachNote?
    @State private var releaseHint = ""
    @State private var feedbackTick = 0
    @State private var judging = false
    @State private var deliveryArrived = false
    @State private var lastDistance: Double?
    @State private var x = 0.5
    @State private var y = 0.5
    @State private var clock = MatchInputClock()
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 320))
    @State private var locationScene = LocationDrillScene(size: TrainingStageLayout.size)
    @State private var locationReplay: LocationDrillReplay?
    @State private var tireScene = TirePowerScene(size: TrainingStageLayout.size)
    @State private var rhythmTaps: [Double?] = Array(repeating: nil, count: 3)
    @State private var tracePoints: [TrainingTarget] = []
    @State private var traceAnchors = [0.5, 0.5, 0.5]
    @State private var buttonInput = false
    @State private var chosenPhase = 0.25
    @State private var chosenBeats = [0.5, 1.2, 1.9]
    @State private var errorMessage: String?
    @State private var preparationValue: Double?
    @State private var preparationError: String?
    @State private var retryInput: TrainingInput?
    @State private var retryRevision: Int?

    private var displayTraining: CareerTraining? { replay ?? training }
    private var replayLabel: String { feedbackVisible ? "결과 확인 중…" : "동작 진행 중…" }
    private var inputLocked: Bool { retryInput != nil || replay != nil }
    private var isPitcher: Bool { player.role == .pitcher }
    private var selectedKind: TrainingKind { training?.selectedKind ?? (category == 0 && isPitcher ? .pitch : kind) }
    private var studying: Bool { training?.pitchStudy != nil || initialPitchStudyCode != nil }
    private var isLocationDrill: Bool { [.control, .defense].contains(selectedKind) && training?.position == nil && training?.trait == nil }
    private var isSkillDrill: Bool { displayTraining?.isSkillDrill ?? (SkillDrillRules.kinds.contains(selectedKind) && !studying) }
    private var skillHint: String {
        switch selectedKind {
        case .power: "티배팅 · 체중 이동 후 MAX에서 손 떼기"
        case .velocity: "준비 → 회전 → 릴리스 · 3박자"
        default: "점선 궤적을 시작부터 끝까지"
        }
    }
    private var locationTarget: TrainingTarget? { displayTraining.flatMap { $0.completed ? nil : $0.targets[$0.scores.count] } }
    private var title: String { training?.title ?? (studying ? "구종 습득 훈련" : selectedKind.label + " 훈련") }
    private var pitchName: String { selectedKind == .pitch ? (player.pitches.first { $0.code == (training?.pitchCode ?? code) }?.name ?? PitchType(rawValue: training?.pitchCode ?? code)?.label ?? "구종") : selectedKind.label }
    private func load() {
        do {
            if !initialSelectionApplied, let initialPitchStudyCode {
                code = initialPitchStudyCode; category = 0; kind = .pitch; initialSelectionApplied = true
            }
            if !initialSelectionApplied, let initialKind, initialKind.allows(player.roleRaw) {
                kind = initialKind
                category = initialKind.isRaw ? 2 : initialKind.isField ? 1 : 0
                initialSelectionApplied = true
            }
            if isPitcher { pitchVelocity = try CareerTrainingStore.value(player: player, code: nil, kind: .velocity, in: context) }
            if !practice {
                record = try CareerTrainingStore.record(player: player, in: context)
                training = try record?.snapshot()
            }
            angle = selectedKind.initialDirection
            if code.isEmpty { code = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
            loadPreparation()
        } catch { errorMessage = error.localizedDescription }
    }
    private var preparationKey: String { "\(category):\(kind.rawValue):\(code)" }
    private func loadPreparation() {
        do {
            if let studyCode = training?.pitchStudy?.code ?? initialPitchStudyCode {
                preparationValue = try PitchStudyStore.progress(player: player, code: studyCode, in: context)
            } else {
                preparationValue = try CareerTrainingStore.value(player: player, code: selectedKind == .pitch ? code : nil, kind: selectedKind, in: context)
            }
            preparationError = nil
        } catch {
            preparationValue = nil; preparationError = error.localizedDescription
        }
    }
    private func start() {
        do {
            if let initialPitchStudyCode, !practice {
                record = try PitchStudyStore.start(player: player, state: calendar, code: initialPitchStudyCode, replacing: replacingPitchCode, in: context)
                training = try record?.snapshot()
            } else if practice {
                training = try TrainingPractice.round(player: player, calendar: calendar, kind: selectedKind, code: code, in: context)
            } else {
                record = try CareerTrainingStore.start(player: player, state: calendar, pitchCode: selectedKind == .pitch ? code : nil, kind: selectedKind, in: context)
                training = try record?.snapshot()
            }
            angle = selectedKind.initialDirection
        } catch { errorMessage = error.localizedDescription }
    }
    private func beginAttempt() {
        guard let training, !training.completed, !inputLocked else { return }
        if [.speed, .stamina].contains(selectedKind) {
            footfalls = []; lastFootfallTime = 0
            clock.start(windup: 0, duration: 4) { submit(TrainingInput(footfalls: footfalls)) }
            return
        }
        if selectedKind == .discipline {
            judging = true; deliveryArrived = false
            scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, role: player.role, appearance: player.appearance, jerseyNumber: player.jerseyNumber)
            scene.demonstrate(reduceMotion: reduced, flightDuration: 0.9, x: training.targets[training.scores.count].x,
                              y: training.targets[training.scores.count].y, pitchCode: "four-seam",
                              onArrival: { deliveryArrived = true; if replay != nil { skillAnimationFinished() } },
                              inputTimeline: MatchInputTimeline(windup: MatchDelivery.windup, duration: 0.9))
            return
        }
        scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, role: player.role, appearance: player.appearance, jerseyNumber: player.jerseyNumber)
        let timeline = MatchInputTimeline(windup: selectedKind == .pitch ? 0 : MatchDelivery.windup, duration: 1.6)
        if selectedKind == .pitch { scene.preparePitch(phase: 0, reduced: reduced) }
        else { scene.demonstrate(reduceMotion: reduced, flightDuration: 1.6, x: training.targets[training.scores.count].x,
                          y: training.targets[training.scores.count].y, pitchCode: training.pitchCode ?? "four-seam", inputTimeline: timeline) }
        clock.start(timeline: timeline) {
            submit(isPitcher ? TrainingInput(release: 0) : TrainingInput())
        }
    }
    private func submit(_ input: TrainingInput) {
        guard !inputLocked, training != nil, practice || record != nil else { return }
        clock.stop(); judging = false
        replay = training; replayStarted = Date(); feedbackVisible = false; reviewReady = false
        retryInput = input; retryRevision = record?.revision ?? 0
        saveAttempt()
    }
    private func saveAttempt() {
        guard let input = retryInput, let revision = retryRevision else { return }
        if replay == nil { replay = training; replayStarted = Date(); feedbackVisible = false; reviewReady = false }
        do {
            if practice {
                guard var round = training else { return }
                try round.attempt(input); training = round
            } else {
                guard let record else { return }
                try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context)
                training = try record.snapshot()
            }
            if !isSkillDrill, selectedKind == .power, let force = input.force, let angle = input.angle { lastDistance = TrainingRules.distance(force: force, angle: angle) }
            retryInput = nil; retryRevision = nil; errorMessage = nil
            replayScore = training?.scores.last
            if let previous = replay, let score = replayScore { coachNote = TrainingSessionGuide.note(round: previous, input: input, score: score) }
            if isSkillDrill, let previous = replay, let score = replayScore {
                if selectedKind == .power { tireScene.strike(score: score, reduced: reduced, completion: skillAnimationFinished) }
                else {
                    let point = TrainingTarget(x: 0.5, y: 0.5)
                    let flight = PitchFlightPresentation(delivery: delivery(code: "four-seam")).flightDuration
                    let bend = selectedKind == .stuff ? (SkillDrillRules.curve(previous.targets[previous.scores.count])[12].x - 0.5) * 100 : 0
                    locationScene.play(LocationDrillReplay(kind: .control, target: point, input: point, score: score), preparedRelease: selectedKind == .velocity,
                                       flightDuration: flight, curve: bend, completion: skillAnimationFinished)
                }
            } else if isLocationDrill, let previous = replay, let score = replayScore {
                let resolved = LocationDrillReplay(kind: selectedKind, target: previous.targets[previous.scores.count], input: TrainingTarget(x: input.x, y: input.y), score: score)
                locationReplay = resolved
                locationScene.play(resolved) {
                    showFeedback()
                    replayTask = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(DeliveryPresentation.trainingRead(reduced: reduced))) } catch { return }
                        guard !Task.isCancelled else { return }; finishReplay()
                    }
                }
            } else if selectedKind == .pitch, let previous = replay {
                let target = previous.targets[previous.scores.count]
                let release = input.release ?? 0
                releaseHint = abs(release - ManualMatchRules.releaseCenter) <= ManualMatchRules.perfectWidth(mastery: previous.controlMastery)
                    ? "정확한 릴리스" : release < ManualMatchRules.releaseCenter ? "릴리스 빠름" : "릴리스 늦음"
                let started = scene.demonstrate(reduceMotion: reduced, flightDuration: PitchFlightPresentation(delivery: delivery(code: previous.pitchCode ?? "four-seam")).flightDuration, x: target.x, y: target.y,
                                               pitchCode: previous.pitchCode ?? "four-seam", preparedRelease: true,
                                               onArrival: { showFeedback() }, completion: { finishReplay() })
                if !started { scheduleFeedback() }
            } else if selectedKind == .contact {
                let contact = training?.lastContact
                scene.finishBat(action: input.timing == nil ? "watch" : "swing",
                                outcome: (contact?.timingScore ?? 0) >= 60 && (contact?.positionScore ?? 0) >= 60 ? "안타" : "헛스윙",
                                reduced: reduced, onArrival: { showFeedback() }, completion: { finishReplay() })
            } else if selectedKind == .discipline {
                if deliveryArrived { skillAnimationFinished() }
            } else { scheduleFeedback() }
        } catch { replay = nil; scene.cancelDelivery(); errorMessage = error.localizedDescription }
    }
    private func showFeedback() {
        guard replay != nil else { return }
        feedbackVisible = true; feedbackTick += 1
    }
    private func finishReplay() {
        guard replay != nil else { return }
        reviewReady = true
    }
    private func continueSession() {
        guard reviewReady else { return }
        replay = nil; feedbackVisible = false; reviewReady = false; deliveryArrived = false; scene.cancelDelivery()
        locationReplay = nil; locationScene.cancel(); tireScene.cancel()
        rhythmTaps = Array(repeating: nil, count: 3); tracePoints = []; traceAnchors = [0.5,0.5,0.5]
        tireScene.prepare(0); if isSkillDrill { locationScene.prepareDrill(phase: 0) }
        if let target = locationTarget { locationScene.preview(target: target, input: TrainingTarget(x: x, y: y)) }
    }
    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replayScore { TrainingGradeBanner(score: replayScore) }
            if let coachNote {
                Text(coachNote.observation).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                Text(coachNote.next).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trainingCoach")
            }
            if isLocationDrill, let locationReplay {
                Text(locationReplay.comparison).font(.caption.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("locationPracticeComparison")
                Text(selectedKind == .control ? "조준한 위치 그대로 판정 · 별도 투구 오차 없음" : "선택한 위치의 정확도만 판정 · 포구 성공/실패 판정 없음")
                    .font(.caption2).foregroundStyle(GameTheme.boardMuted)
            } else if selectedKind == .arm, let previous = replay {
                Text("◇ 목표 " + String(format: "가로 %.1f 세로 %.1f", TrainingRules.basePoint(previous.throwBase(previous.scores.count)).x*100, TrainingRules.basePoint(previous.throwBase(previous.scores.count)).y*100) + "\n+ 입력 도착 " + String(format: "가로 %.1f 세로 %.1f", TrainingRules.throwEndpoint(angle: throwAngle, force: throwForce).x*100, TrainingRules.throwEndpoint(angle: throwAngle, force: throwForce).y*100))
                    .font(.caption.monospacedDigit()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("throwPracticeComparison")
            } else if !isSkillDrill { TrainingMissionBanner(kind: selectedKind, scores: training?.scores ?? []) }
            Button(training?.completed == true ? "세트 결산 보기" : "다음 시도 · \((training?.scores.count ?? 0) + 1)/5") {
                continueSession()
            }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("trainingNext")
            Text("성장은 5회 평균 성적으로 결정됩니다.").font(.caption2).foregroundStyle(GameTheme.boardMuted)
        }
    }
    private func scheduleFeedback() {
        replayTask?.cancel()
        replayTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(selectedKind == .arm ? TrainingFieldMotion.duration : selectedKind == .mental ? 1.4 : DeliveryPresentation.trainingMotion(reduced: reduced))) } catch { return }
            guard !Task.isCancelled else { return }; showFeedback()
            do { try await Task.sleep(for: .seconds(DeliveryPresentation.trainingRead(reduced: reduced))) } catch { return }
            guard !Task.isCancelled else { return }; finishReplay()
        }
    }
    private func cancelUncommitted() {
        clock.stop(); scene.cancelDelivery(); judging = false; deliveryArrived = false
        replayTask?.cancel(); replayTask = nil; replay = nil; feedbackVisible = false; reviewReady = false; coachNote = nil
        locationScene.cancel(); locationReplay = nil; tireScene.cancel(); tracePoints = []; rhythmTaps = Array(repeating: nil, count: 3)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    if let training, training.completed, replay == nil {
                        VStack(spacing: 8) { result(training); errorControls }.padding(12)
                    } else {
                        VStack(spacing: 8) {
                            VStack(spacing: 8) {
                                HStack(spacing: 10) {
                                    PixelPlayer(appearance: player.appearance).frame(width: 28, height: 36).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pitchName).font(.headline)
                                        Text(isSkillDrill ? skillHint : isLocationDrill && training != nil ? (locationTarget.map { "◇ 목표 " + LocationDrillReplay.coordinate($0) } ?? "훈련 완료") : practice ? "자유 연습 · 성장·날짜·피로 변화 없음" : training == nil ? "5회 도전 · 피로 +6 · 하루 행동 1회" : "도전 기록은 시도마다 저장됩니다")
                                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                                    }
                                    Spacer(minLength: 0)
                                    Text(displayTraining.map { "\(min(5, $0.scores.count + 1)) / 5" } ?? "READY")
                                        .font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                                }.padding(10).background(GameTheme.boardPanel)
                                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("trainingProgress")
                                if practice {
                                    Text("자유 연습 · 실제 성장·날짜·피로 변화 없음")
                                        .font(.caption.bold()).foregroundStyle(GameTheme.gold)
                                        .accessibilityIdentifier("trainingPracticeMode")
                                }
                                if training == nil {
                                    if !studying { selection }
                                    preparationBoard
                                }
                                if let training, !reviewReady, !isLocationDrill, !isSkillDrill { TrainingMissionBanner(kind: selectedKind, scores: (feedbackVisible ? self.training : displayTraining)?.scores ?? training.scores) }
                                if dynamicTypeSize.isAccessibilitySize {
                                    Button("훈련 버튼으로 이동") { scroll.scrollTo("trainingControls", anchor: .bottom) }
                                        .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("trainingJumpControls")
                                }
                            }.background(chromeMeasurement("top"))
                            arena(height: fieldHeight(in: geometry.size))
                            VStack(spacing: 8) {
                                if reviewReady { reviewControls } else { playControls.disabled(replay != nil) }
                                errorControls
                            }.id("trainingControls").background(chromeMeasurement("bottom"))
                        }.padding(12)
                    }
                }
                .onPreferenceChange(TrainingChromeHeightKey.self) { chromeHeights = $0 }
            }
        }
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk).tint(GameTheme.gold)
        .preferredColorScheme(.dark)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(GameTheme.boardPanel, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit, role: player.role, appearance: player.appearance, jerseyNumber: player.jerseyNumber)
            load(); if dynamicTypeSize.isAccessibilitySize { buttonInput = true }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTick) { _, _ in UserDefaults.standard.object(forKey: "bm-haptics-enabled") as? Bool ?? true }
        .onDisappear { cancelUncommitted() }
        .toolbar {
            if practice { Button("훈련 바꾸기") { resetPractice() }.accessibilityIdentifier("practiceChangeTraining") }
        }
        .onChange(of: preparationKey) { _, _ in if training == nil { loadPreparation() } }
        .onChange(of: clock.phase) { _, phase in
            if isSkillDrill && clock.running {
                if selectedKind == .power { tireScene.prepare(phase) }
                else { locationScene.prepareDrill(phase: phase) }
            }
            if selectedKind == .pitch && clock.running { scene.preparePitch(phase: phase, reduced: reduced) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelUncommitted() } }
    }

    private func resetPractice() {
        cancelUncommitted(); training = nil; record = nil; retryInput = nil; retryRevision = nil
        replayScore = nil; errorMessage = nil; footfalls = []; lastDistance = nil
        x = 0.5; y = 0.5; force = 70; angle = selectedKind.initialDirection
    }
    private func fieldHeight(in size: CGSize) -> CGFloat {
        let available = size.height - chromeHeights.values.reduce(0, +) - 40
        if isSkillDrill || isLocationDrill || [.speed,.arm,.stamina,.mental].contains(selectedKind) {
            return min(size.width-24,max(150*320/220,available*320/220))
        }
        return max(150,min(size.width-24,available))
    }
    private func chromeMeasurement(_ section: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TrainingChromeHeightKey.self, value: [section: geometry.size.height])
        }
    }
    private var choiceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3)
    }
    private func option(_ label: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text((selected ? "■ " : "□ ") + label).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        }.buttonStyle(MatchPixelButtonStyle(selected: selected))
            .accessibilityLabel(label).accessibilityIdentifier(id)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var selection: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: choiceColumns, spacing: 6) {
                ForEach(0..<3) { index in
                    option(index == 0 ? (isPitcher ? "구종" : "타격") : index == 1 ? "주루·수비" : (isPitcher ? "투구·멘탈" : "멘탈"), selected: category == index, id: "trainingCategory-\(index)") {
                        category = index; kind = index == 1 ? .speed : index == 2 ? (isPitcher ? .velocity : .mental) : .contact
                    }
                }
            }
            if isPitcher && category == 0 {
                Picker("훈련할 구종", selection: $code) {
                    ForEach(player.pitches.sorted { $0.order < $1.order }) { Text("\($0.name) · \($0.mastery, specifier: "%.1f")").tag($0.code) }
                }.pickerStyle(.menu).tint(GameTheme.gold)
                    .padding(8).frame(maxWidth: .infinity, minHeight: 44).background(GameTheme.boardPanel)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
                    .accessibilityIdentifier("trainingPitchPicker")
            } else {
                LazyVGrid(columns: choiceColumns, spacing: 6) {
                    ForEach(category == 2 ? (isPitcher ? [TrainingKind.velocity, .control, .stuff, .stamina, .mental] : [.mental]) : category == 1 ? [.speed, .defense, .arm] : [.contact, .power, .discipline], id: \.self) { item in
                        option(item.label, selected: kind == item, id: "trainingKind-" + item.rawValue) { kind = item }
                    }
                }
            }
        }
    }
    @ViewBuilder private var playControls: some View {
        if let training = displayTraining {
            if training.isSkillDrill {
                skillControls(training)
                scores((feedbackVisible || replay == nil ? self.training : replay) ?? training)
            } else {
            if selectedKind.isRaw {
                rawControls(training).disabled(retryInput != nil)
            } else if selectedKind.isField {
                fieldControls(training).disabled(retryInput != nil)
            } else if selectedKind == .power {
                powerControls(training)
            } else if selectedKind == .discipline {
                Text(judging ? (deliveryArrived ? "도착 위치 확인 · 볼 / 스트라이크 선택" : "공 비행 중 · 도착 위치를 보고 판단하세요") : "공 보기를 누르고 존 안팎을 판단하세요").font(.caption)
            } else {
                MatchTimingGauge(phase: clock.phase, center: isPitcher ? ManualMatchRules.releaseCenter : MatchDelivery.contactPhase,
                                 good: isPitcher ? ManualMatchRules.goodWidth(mastery: training.controlMastery) : ManualMatchRules.timingWidth(contact: training.before),
                                 perfect: isPitcher ? ManualMatchRules.perfectWidth(mastery: training.controlMastery) : TrainingRules.contactPerfectWidth,
                                 label: isPitcher ? (replay != nil ? (feedbackVisible ? "포구 완료 · 결과 확인" : "릴리스 확정 · 공 비행 중") : clock.running ? "팔 준비 중 · 노란 구간에 릴리스" : "공을 쥐고 투구 준비") : "노란 구간 · 타이밍 100점")
                    .accessibilityIdentifier("trainingTimingGauge")
            }
            if let result = (feedbackVisible || replay == nil ? self.training : replay)?.lastContact { ContactTrainingFeedback(result: result) }
            scores((feedbackVisible || replay == nil ? self.training : replay) ?? training)
            if selectedKind == .pitch, feedbackVisible, dynamicTypeSize.isAccessibilitySize, let replayScore {
                PitchJudgmentToast(title: "포구 완료", detail: "\(delivery(code: training.pitchCode ?? code).speed) km/h(게임 기준) · \(replayScore)점 · \(releaseHint)")
                    .accessibilityIdentifier("trainingCatchToast")
            }
            if let score = training.scores.last, replay == nil { TrainingGradeBanner(score: score) }
            if selectedKind.isRaw {
                rawButtons(training).disabled(retryInput != nil)
            } else if selectedKind.isField {
                Button(replay != nil ? replayLabel : selectedKind == .speed ? (clock.running ? "달리는 중…" : "4초 달리기 시작") : selectedKind == .defense ? "위치 확정 · 공 받기" : "송구!") {
                    if [.speed, .stamina].contains(selectedKind) { beginAttempt() }
                    else if selectedKind == .defense { submit(TrainingInput(x: x, y: y)) }
                    else { submit(TrainingInput(force: throwForce, angle: throwAngle, base: throwBase)) }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil || clock.running)
                    .accessibilityIdentifier("trainingAttempt")
            } else if selectedKind == .discipline {
                if judging {
                    HStack {
                        Button("볼") { submit(TrainingInput(calledStrike: false)) }
                            .accessibilityIdentifier("trainingCallBall")
                        Button("스트라이크") { submit(TrainingInput(calledStrike: true)) }
                            .accessibilityIdentifier("trainingCallStrike")
                    }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                } else {
                    Button("공 보기 · \(training.scores.count + 1)/5") { beginAttempt() }
                        .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                        .accessibilityIdentifier("trainingAttempt")
                }
            } else if selectedKind == .power {
                Button(replay != nil ? replayLabel : "티배팅!") { submit(TrainingInput(force: force, angle: angle)) }
                    .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                    .accessibilityIdentifier("trainingAttempt")
            } else {
                Button(replay != nil ? (feedbackVisible ? "결과 확인 중…" : isPitcher ? "투구·포구 중…" : "타격 동작 중…") : clock.running ? (isPitcher ? "던지기!" : "타격!") : "\(training.scores.count + 1)번째 시도 시작") {
                    if clock.running {
                        submit(isPitcher ? TrainingInput(release: clock.phase) : TrainingInput(x: x, y: y, timing: clock.currentPhase))
                    } else { beginAttempt() }
                }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(retryInput != nil)
                    .accessibilityIdentifier("trainingAttempt")
            }
            }
        } else {
            Button(practice ? "연습 시작" : "훈련 시작") { start() }.buttonStyle(MatchPixelButtonStyle(primary: true))
                .disabled(errorMessage != nil).accessibilityIdentifier("startTraining")
        }
    }
    private func skillAnimationFinished() {
        guard replay != nil else { return }
        showFeedback()
        replayTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(DeliveryPresentation.trainingRead(reduced: reduced))) } catch { return }
            guard !Task.isCancelled else { return }; finishReplay()
        }
    }
    private func beginPower() {
        guard !clock.running, !inputLocked, training?.completed == false, let target = locationTarget else { return }
        clock.start(windup: 0, duration: SkillDrillRules.powerDuration(target)) {
            submit(TrainingInput(drill: SkillDrillInput(phase: 1)))
        }
    }
    private func releasePower() {
        guard clock.running, !inputLocked else { return }
        submit(TrainingInput(drill: SkillDrillInput(phase: clock.currentPhase)))
    }
    private func beginRhythm() {
        guard !clock.running, !inputLocked, training?.completed == false else { return }
        rhythmTaps = Array(repeating: nil, count: 3)
        clock.start(windup: 0, duration: SkillDrillRules.rhythmDuration) {
            submit(TrainingInput(drill: SkillDrillInput(beats: rhythmTaps)))
        }
    }
    private func tapBeat(_ index: Int) {
        guard clock.running, !inputLocked, rhythmTaps[index] == nil else { return }
        let elapsed = clock.currentPhase * SkillDrillRules.rhythmDuration
        guard SkillDrillRules.recordBeat(index, elapsed: elapsed, taps: &rhythmTaps) else { return }
        if rhythmTaps.allSatisfy({ $0 != nil }) { submit(TrainingInput(drill: SkillDrillInput(beats: rhythmTaps))) }
    }
    private func buttonTrace(_ target: TrainingTarget) -> [TrainingTarget] {
        let reference = SkillDrillRules.curve(target)
        return [reference[0]] + (1...3).map { TrainingTarget(x: traceAnchors[$0-1], y: reference[$0*6].y) } + [reference[24]]
    }
    @ViewBuilder private func skillControls(_ round: CareerTraining) -> some View {
        let locked = inputLocked || clock.running
        if selectedKind == .power {
            MatchTimingGauge(phase: buttonInput ? chosenPhase : clock.running || replay != nil ? clock.phase : 0, center: 0.5, good: 0.13, perfect: 0.025, label: "MAX 중앙 · 힘 모아 손 떼기", batting: true, centerLabel: "MAX", earlyLabel: "덜 모음", lateLabel: "넘침")
                .accessibilityIdentifier("skillPowerGauge")
            if buttonInput {
                DrillValueControl(name: "힘 풀기 위치", value: $chosenPhase).disabled(locked)
                Button("위치 확정 · 티배팅") { submit(TrainingInput(drill: SkillDrillInput(phase: chosenPhase))) }
                    .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(inputLocked).accessibilityIdentifier("skillPowerConfirm")
            } else {
                Text(clock.running ? "MAX에서 손을 떼세요" : "누르고 힘 모으기 · MAX에서 떼기")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 58).background(GameTheme.green)
                    .overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2)).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in beginPower() }.onEnded { _ in releasePower() })
                    .accessibilityLabel("길게 눌러 힘을 모으고 중앙에서 손 떼기. 버튼 조작으로도 선택할 수 있습니다.")
                    .accessibilityIdentifier("skillPowerHold").disabled(inputLocked)
            }
        } else if selectedKind == .velocity {
            Text("구속 능력 기준 \(delivery(code: "four-seam").speed) km/h · 리듬 점수는 별도")
                .font(.caption.monospacedDigit()).accessibilityIdentifier("skillVelocityBaseline")
            if buttonInput {
                Text("목표 박자 0.65 · 1.35 · 2.05초").font(.caption.monospacedDigit())
                ForEach(0..<3) { i in
                    DrillValueControl(name: "\(i+1)박 초", value: $chosenBeats[i], range: 0...SkillDrillRules.rhythmDuration, step: 0.05).disabled(locked)
                }
                Button("박자 배치 확정 · 투구") { submit(TrainingInput(drill: SkillDrillInput(beats: chosenBeats.map { Optional($0) }))) }
                    .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(inputLocked).accessibilityIdentifier("skillRhythmConfirm")
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        let elapsed = clock.phase * SkillDrillRules.rhythmDuration
                        let active = clock.running && abs(elapsed - SkillDrillRules.beats[i]) <= SkillDrillRules.perfectWindow
                        let progress = min(1, max(0, (elapsed - SkillDrillRules.beats[i] + SkillDrillRules.beatWindow) / (2 * SkillDrillRules.beatWindow)))
                        Button { tapBeat(i) } label: {
                            VStack(spacing: 4) {
                                Text(rhythmTaps[i] != nil ? "✓" : active ? "지금" : "\(i+1)")
                                Text(["준비","회전","릴리스"][i]).font(.caption)
                                GeometryReader { track in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(GameTheme.boardLine)
                                        Rectangle().fill(GameTheme.gold).frame(width: 3).offset(x: track.size.width * 0.5 - 1.5)
                                        Rectangle().fill(GameTheme.boardInk).frame(width: 2).offset(x: max(0,track.size.width - 2) * progress)
                                    }
                                }.frame(height: 8).accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 50)
                        }.buttonStyle(MatchPixelButtonStyle(selected: active)).disabled(!clock.running || inputLocked || rhythmTaps[i] != nil)
                            .accessibilityValue(rhythmTaps[i] != nil ? "입력 완료" : active ? "지금 입력" : "대기").accessibilityIdentifier("skillBeat-\(i)")
                    }
                }
                Button(clock.running ? "밝아진 노드를 순서대로" : "3박자 투구 시작") { beginRhythm() }
                    .buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(clock.running || inputLocked).accessibilityIdentifier("skillRhythmStart")
            }
        } else if let target = locationTarget {
            if buttonInput {
                ForEach(0..<3) { i in
                    let goal = SkillDrillRules.curve(target)[(i+1)*6]
                    Text("\(i+1)번 지점 목표 가로 \(Int((goal.x*100).rounded()))").font(.caption.monospacedDigit()).accessibilityIdentifier("skillAnchorGoal-\(i)")
                    DrillValueControl(name: "\(i+1)번 가로", value: $traceAnchors[i]).disabled(locked)
                }
            }
            Button("궤적 확정 · 투구") {
                submit(TrainingInput(drill: SkillDrillInput(trace: buttonInput ? buttonTrace(target) : tracePoints)))
            }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(inputLocked).accessibilityIdentifier("skillTraceConfirm")
            if !buttonInput {
                Button("경로 다시 그리기") { tracePoints = [] }.buttonStyle(MatchPixelButtonStyle()).disabled(inputLocked).accessibilityIdentifier("skillTraceClear")
            }
        }
        if replay != nil { Text(replayLabel).font(.caption).accessibilityIdentifier("skillPlaybackState") }
        Button(buttonInput ? "직접 조작으로" : "버튼 조작으로 · 시간 제한 없음") { buttonInput.toggle() }
            .font(.caption).frame(minHeight: 44).disabled(locked).accessibilityIdentifier("skillInputMode")
    }
    private func skillArena(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            SpriteView(scene: selectedKind == .power ? tireScene : locationScene, preferredFramesPerSecond: 30)
                .allowsHitTesting(false).accessibilityHidden(true)
            if selectedKind == .stuff, replay == nil || feedbackVisible {
                SkillTraceBoard(target: locationTarget, points: buttonInput ? .constant(locationTarget.map(buttonTrace) ?? []) : $tracePoints,
                                locked: inputLocked || buttonInput)
                    .frame(width: height * 0.51, height: height * 0.50)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8)
            }
            Text(selectedKind == .power ? "POWER · 티배팅" : selectedKind == .velocity ? "VELOCITY · 리듬 불펜" : replay != nil && !feedbackVisible ? "STUFF · 목표 궤적 시연" : "STUFF · 점선 목표 / 실선 입력")
                .font(.caption.bold()).padding(6).background(GameTheme.navy).allowsHitTesting(false)
        }.frame(width: height, height: height * 220 / 320).clipped().overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("skillPracticeField")
            .onAppear {
                if selectedKind == .power { tireScene.configure(player: player) }
                else { locationScene.configure(kind: .control, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw); locationScene.prepareDrill(phase: 0) }
            }
            .onChange(of: selectedKind) { _, _ in
                if selectedKind == .power { tireScene.configure(player: player) }
                else { locationScene.configure(kind: .control, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw); locationScene.prepareDrill(phase: 0) }
            }
    }
    @ViewBuilder private var errorControls: some View {
    if let errorMessage {
        Text(errorMessage).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("trainingError")
        Button(retryInput == nil ? "기록 다시 확인" : "같은 결과 저장 재시도") {
            if retryInput == nil { self.errorMessage = nil; load() } else { saveAttempt() }
        }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("retryTrainingSave")
    }
    }
    private func scores(_ value: CareerTraining, expanded: Bool = false) -> some View {
        TrainingAttemptStrip(scores: value.scores, expanded: expanded)
            .accessibilityIdentifier("trainingScores")
    }
    private var preparationBoard: some View {
        TrainingPreparationBoard(player: player, name: pitchName, kind: selectedKind, value: preparationValue,
                                 failure: preparationError, practice: practice, studying: studying)
    }
    @ViewBuilder private func arena(height: CGFloat) -> some View {
        if isSkillDrill {
            skillArena(height: height)
        } else if isLocationDrill, let target = locationTarget {
            LocationPracticeBoard(kind: selectedKind, target: target, scene: locationScene, player: player, x: $x, y: $y, locked: inputLocked)
                .frame(width: height, height: height * 220 / 320).clipped()
                .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
                .accessibilityIdentifier("trainingField")
        } else {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: replay == nil && !judging && !clock.running)) { timeline in
        let progress = clock.running && [.speed, .stamina].contains(selectedKind) ? clock.phase : replay == nil ? 0.0 : min(1, max(0, timeline.date.timeIntervalSince(replayStarted) / (selectedKind == .arm ? TrainingFieldMotion.duration : 0.9)))
        let training = displayTraining
        ZStack {
            if selectedKind == .mental {
                MentalPracticeBoard(appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw, round: training?.scores.count ?? 0, reviewing: replay != nil)
            } else if selectedKind.isRaw {
                RawTrainingBoard(kind: selectedKind, training: training, steps: TrainingRules.steps(footfalls), motion: progress, moving: replay != nil || clock.running, force: force, angle: angle, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw, x: $x, y: $y, locked: inputLocked)
            } else if selectedKind.isField {
                FieldTrainingBoard(kind: selectedKind, target: training.flatMap { $0.completed ? nil : $0.targets[$0.scores.count] },
                                   base: training.map { $0.completed ? 1 : TrainingRules.throwBase($0.scores.count) } ?? 1,
                                   angle: throwAngle, force: throwForce, steps: TrainingRules.steps(footfalls), appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw, x: $x, y: $y, locked: inputLocked || training == nil, motion: progress, moving: replay != nil || clock.running)
            } else if selectedKind == .power {
                PowerPracticeBoard(force: force, angle: angle, round: training?.scores.count ?? 0,
                                   motion: progress, playing: replay != nil, appearance: player.appearance)
            } else { SpriteView(scene: scene).allowsHitTesting(false) }
            if selectedKind == .contact, let training, !training.completed {
                let target = training.targets[training.scores.count]
                ZStack {
                    BattingAimZone(x: $x, y: $y, locked: inputLocked)
                    GeometryReader { geometry in
                        Text("◇").font(.system(size: 22,weight: .black)).foregroundStyle(Color(hex: 0x82e6b2))
                            .position(x: geometry.size.width * target.x, y: geometry.size.height * target.y)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }.frame(width: height * 0.16, height: height * 0.22)
                    .position(x: height * 0.5, y: height * 0.68)
                Text("◇ 목표 · □ 조준 · 중앙에서 타격")
                    .font(.caption.bold()).padding(6).background(GameTheme.navy)
                    .frame(maxHeight: .infinity, alignment: .top).padding(6).allowsHitTesting(false)
            }
            if selectedKind == .discipline, let training, !training.completed {
                VStack(spacing: 3) {
                    Text(deliveryArrived ? "직전 공 · + 위치" : "도착 코스").font(.caption2.bold())
                    GeometryReader { geometry in
                        let target = training.targets[training.scores.count]
                        ZStack {
                            Rectangle().fill(GameTheme.navy)
                            Rectangle().strokeBorder(Color(hex: 0xf3edcf), lineWidth: 2)
                                .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6)
                            if deliveryArrived {
                                Text("+").font(.system(size: 18,weight:.black,design:.monospaced)).foregroundStyle(GameTheme.gold)
                                    .position(x: geometry.size.width * target.x,y: geometry.size.height * target.y)
                            }
                        }
                    }.frame(width: min(100,height*0.32),height: min(100,height*0.32))
                }.padding(5).background(GameTheme.navy)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing).padding(8)
                    .allowsHitTesting(false).accessibilityElement(children: .ignore)
                    .accessibilityLabel(deliveryArrived ? "직전 도착 코스" : "도착 코스 대기")
                    .accessibilityValue(deliveryArrived ? "가로 \(Int(training.targets[training.scores.count].x * 100)), 세로 \(Int(training.targets[training.scores.count].y * 100))" : "공 보기로 시작")
            }
            if selectedKind == .power, let training, !training.completed {
                VStack {
                    Text("목표 \(TrainingRules.powerTarget(training.scores.count), specifier: "%.0f")m").bold()
                        .padding(8).background(GameTheme.navy).accessibilityIdentifier("powerTarget")
                    Spacer()
                    if let lastDistance, replay == nil {
                        Text("직전 \(lastDistance, specifier: "%.1f")m · \(training.scores.last ?? 0)점")
                            .font(.caption.bold()).padding(8).background(GameTheme.navy)
                    }
                }.padding(8)
            }
            if selectedKind == .pitch, replay != nil, feedbackVisible, !reviewReady, !dynamicTypeSize.isAccessibilitySize, let replayScore {
                PitchJudgmentToast(title: "포구 완료", detail: "\(delivery(code: training?.pitchCode ?? code).speed) km/h(게임 기준) · \(replayScore)점 · \(releaseHint)")
                    .frame(maxWidth: height * 0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, height * 0.13)
                    .accessibilityIdentifier("trainingCatchToast")
            }
            if selectedKind == .pitch {
                MatchGrip(code: training?.pitchCode ?? code, hand: player.throwingHandRaw)
                    .frame(width: 74, height: 74).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if replay != nil, feedbackVisible, !reviewReady, selectedKind != .pitch, let replayScore {
                TrainingGradeBanner(score: replayScore)
                    .accessibilityIdentifier("trainingReplayFeedback")
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(8).allowsHitTesting(false)
            }
        }.frame(width: height * (isPitcher && !selectedKind.isField && !selectedKind.isRaw ? 1219.0 / 1290 : 1), height: [.speed,.arm,.stamina,.mental].contains(selectedKind) ? height * 220 / 320 : height).clipped()
            .overlay(Rectangle().strokeBorder(GameTheme.gold.opacity(0.5), lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("trainingField")
        }
        }
    }
    @ViewBuilder private func rawControls(_ training: CareerTraining) -> some View {
        if [.velocity, .stuff].contains(selectedKind) {
            if dynamicTypeSize.isAccessibilitySize {
                let goal = RawTrainingRules.goal(kind: selectedKind, target: training.targets[training.scores.count])
                Text("목표 \(Int(goal.force))% · \(Int(goal.angle))°").font(.headline).accessibilityIdentifier("rawTrainingTarget")
            }
            adjustmentLayout {
                adjustment(selectedKind == .stuff ? "회전 강도" : "힘", value: $force, range: 0...100, suffix: "%", identifier: "rawForce")
                TrainingAdjustment(label: selectedKind == .stuff ? "회전 방향" : "발사 방향", value: $angle, range: 0...360, suffix: "°", identifier: "rawAngle", step: selectedKind == .stuff ? 30 : 5)
            }
        } else if selectedKind == .stamina {
            fieldControls(training)
        } else if selectedKind == .control {
            locationControls
        }
    }
    @ViewBuilder private func rawButtons(_ training: CareerTraining) -> some View {
        if selectedKind == .mental {
            let question = RawTrainingRules.question(targets: training.targets, round: training.scores.count)
            Text(question.prompt).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("mentalScenario")
            ForEach(0..<3, id: \.self) { index in
                Button(question.choices[index]) { submit(TrainingInput(choice: index)) }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("mentalChoice-\(index)")
            }
        } else {
            Button(replay != nil ? replayLabel : selectedKind == .stamina ? (clock.running ? "달리는 중…" : "4초 달리기 시작") : selectedKind == .control ? "조준 확정 · 투구" : "\(selectedKind.label) 도전!") {
                if selectedKind == .stamina { beginAttempt() }
                else if selectedKind == .control { submit(TrainingInput(x: x, y: y)) }
                else { submit(TrainingInput(force: force, angle: angle)) }
            }.buttonStyle(MatchPixelButtonStyle(primary: true)).disabled(clock.running)
                .accessibilityIdentifier("trainingAttempt")
        }
    }
    private func powerControls(_ training: CareerTraining) -> some View {
        adjustmentLayout {
            adjustment("힘", value: $force, range: 0...100, suffix: "%", identifier: "powerForce")
            adjustment("각도", value: $angle, range: 15...55, suffix: "°", identifier: "powerAngle")
        }.disabled(retryInput != nil)
    }
    private var adjustmentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private var locationControls: some View {
        VStack(spacing: 6) {
            Text("◇ 목표 · + \(selectedKind == .control ? "조준" : "선수") · 위치 정확도만 채점")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                locationDirection("←", label: "왼쪽", dx: -0.01, dy: 0)
                locationDirection("→", label: "오른쪽", dx: 0.01, dy: 0)
                locationDirection("↑", label: "위쪽", dx: 0, dy: -0.01)
                locationDirection("↓", label: "아래쪽", dx: 0, dy: 0.01)
            }
        }
    }
    private func locationDirection(_ title: String, label: String, dx: Double, dy: Double) -> some View {
        Button {
            guard !inputLocked else { return }
            x = min(1, max(0, x + dx)); y = min(1, max(0, y + dy))
        } label: { Text(title).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
            .buttonStyle(MatchPixelButtonStyle()).disabled(inputLocked)
            .accessibilityLabel((selectedKind == .control ? "조준 " : "선수 ") + label + " 1 이동")
            .accessibilityIdentifier("locationMove-" + label)
    }
    private func adjustment(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, identifier: String) -> some View {
        TrainingAdjustment(label: label, value: value, range: range, suffix: suffix, identifier: identifier)
    }
    private func step(_ foot: SprintFoot) {
        guard clock.running, clock.phase < 1, footfalls.last != foot else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if selectedKind == .stamina && now - lastFootfallTime < 0.18 { return }
        footfalls.append(foot); lastFootfallTime = now
    }
    @ViewBuilder private func fieldControls(_ training: CareerTraining) -> some View {
        if [.speed, .stamina].contains(selectedKind) {
            if selectedKind == .stamina {
                let beat = (clock.phase * 16).truncatingRemainder(dividingBy: 1)
                HStack(spacing: 6) {
                    Rectangle().fill(clock.running && beat < 0.35 ? GameTheme.gold : GameTheme.boardLine).frame(width: 8, height: 8)
                    Text("박자에 맞춰 교대 · 과한 연타는 제외").font(.caption2)
                }.accessibilityLabel("지구력 리듬 안내, 일정한 간격으로 좌우 교대")
            }
            HStack {
                Button("왼발") { step(.left) }.accessibilityIdentifier("sprintLeft")
                Button("오른발") { step(.right) }.accessibilityIdentifier("sprintRight")
            }.buttonStyle(MatchPixelButtonStyle()).disabled(!clock.running)
            ProgressView(value: clock.running || replay != nil ? clock.phase : 0).tint(GameTheme.gold).accessibilityLabel("4초 달리기 진행").accessibilityIdentifier("sprintProgress")
        } else if selectedKind == .defense {
            locationControls
        } else {
            Text("목표 \(TrainingRules.throwBase(training.scores.count) == 4 ? "홈" : "\(TrainingRules.throwBase(training.scores.count))루")").font(.caption.bold())
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible()), GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(1...4, id: \.self) { base in
                    option(base == 4 ? "홈" : "\(base)루", selected: throwBase == base, id: "throwBase-\(base)") { throwBase = base }
                }
            }
            adjustmentLayout {
                adjustment("방향", value: $throwAngle, range: 0...360, suffix: "°", identifier: "throwAngle")
                adjustment("강도", value: $throwForce, range: 8...100, suffix: "%", identifier: "throwForce")
            }.disabled(retryInput != nil)
        }
    }

    private func result(_ value: CareerTraining) -> some View {
        VStack(spacing: 16) {
            TrainingResultHeading(player: player, name: pitchName, average: value.average, practice: practice)
            if !practice {Text("완료 결과 보관 · 재열기/연출은 성장·피로를 다시 적용하지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("trainingResultStored")}
            ManagementPanel("5회 훈련 성적표") {
                scores(value, expanded: true)
                TrainingMissionBanner(kind: value.selectedKind, scores: value.scores, completed: true)
            }
            if practice {
                ManagementPanel("자유 연습 완료", surface: .paper) {
                    Text("점수만 확인 · 실제 선수의 성장·날짜·피로 변화 없음")
                        .font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("practiceCompleted")
                    Text("실전 훈련 기록과 보상에 합산되지 않습니다.")
                        .font(.caption).foregroundStyle(GameTheme.navy.opacity(0.8))
                }
                Button("다시 연습") { resetPractice(); start() }
                    .buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("practiceRetry")
                Button("훈련 선택으로") { resetPractice() }.buttonStyle(MatchPixelButtonStyle())
            } else if let study = value.pitchStudy {
                ManagementPanel("구종 습득 진척", surface: .paper) {
                    Text("\(value.before, specifier: "%.1f") → \(value.after, specifier: "%.1f") / 100")
                        .font(.title3.monospacedDigit().bold()).accessibilityIdentifier("pitchStudyResult")
                    ProgressView(value: value.after, total: 100).tint(GameTheme.growth)
                    Text(value.after == 100 ? "\(pitchName) 등록 완료 · 숙련도 \(study.restoredMastery ?? 20, specifier: "%.1f")" : "진척이 저장됐습니다. 다음 훈련일에 이어서 학습합니다.")
                        .font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("피로 +6 · 오늘 행동 1회 사용 · 같은 결과 재지급 없음").font(.caption)
                    if let retired = study.retired, value.after == 100 {
                        Text("\(retired.name) 숙련도 \(retired.mastery, specifier: "%.1f") 보관 · 재등록 훈련으로 복원")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                TrainingGrowthReceipt(name: pitchName, before: value.before, after: value.after,
                                      gain: value.gain, fatigue: value.fatigue)
            }
            if !practice,let policy=value.growthPolicy {
                ManagementPanel("적용한 성장 정책") {
                    Text("V2 · "+policy.timing.label).font(.headline)
                    Text(policy.windowID == nil ? "이 훈련 시작 당시의 성장 조건을 보존합니다.":"성장 집중 적용 · 관련 능력 한정 보너스 포함").font(.subheadline).accessibilityIdentifier("trainingGrowthPolicy")
                }
            }
            if !practice { TrainingProjectFeedbackPanel(training: value); CareerProjectNextActions(player: player, calendar: calendar) }
            if let result = value.lastContact { ContactTrainingFeedback(result: result) }
            Button(practice ? "연습 메뉴로" : "선수 홈으로") { dismiss() }
                .buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("trainingReturnHome")
        }
    }

}

private struct TrainingPreparationBoard: View {
    let player: CareerPlayer
    let name: String
    let kind: TrainingKind
    let value: Double?
    let failure: String?
    let practice: Bool
    var studying = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var next: Double { min(100, floor(value ?? 0) + 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(practice ? "PRACTICE / 자유 연습" : "TRAINING / 오늘의 훈련").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    Text(name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(practice ? "보유 기량으로 자유롭게 도전" : "시도마다 저장 · 5회 완료 시 성장·피로·행동 반영").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    if let value {
                        Text("현재 \(studying ? "습득 진척" : kind == .pitch ? "구종 숙련도" : "능력치") \(value, specifier: "%.1f")")
                            .font(.headline.monospacedDigit()).accessibilityIdentifier("trainingCurrentValue")
                    } else { Text("현재 능력 미집계").font(.subheadline).foregroundStyle(GameTheme.gold) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    DetailGamePortrait(role: player.role, appearance: player.appearance, number: player.jerseyNumber,
                                       hand: player.throwingHandRaw, label: player.name + "의 훈련 도트")
                        .frame(width: 66, height: 88)
                }
            }
            if let value {
                HStack {
                    Text(studying ? (value >= 100 ? "보관 구종 재등록 · 원숙련 복원" : "습득 목표 100 · 최초 숙련 20") : value >= 100 ? "최대 기량" : "다음 목표 " + next.formatted(.number.precision(.fractionLength(1)))).font(.caption.bold())
                    Spacer(minLength: 4)
                    Text(value >= 100 ? "MAX" : (studying ? "남은 진척 " : "남은 성장 ") + max(0, (studying ? 100 : next) - value).formatted(.number.precision(.fractionLength(1))))
                        .font(.caption.monospacedDigit()).foregroundStyle(GameTheme.boardMuted)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("trainingNextTarget")
                TrainingSegmentTrack(value: studying ? value / 100 : value >= 100 ? 1 : value - floor(value), color: GameTheme.growth)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                TrainingRuleStamp(title: "시도", value: "5회")
                TrainingRuleStamp(title: "피로", value: practice ? "변화 없음" : "\(player.fatigue) → \(min(100, player.fatigue + TrainingRules.fatigueCost))")
                TrainingRuleStamp(title: "행동", value: practice ? "제한 없음" : "오늘 1회 사용")
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(GameTheme.gold).fixedSize(horizontal: false, vertical: true) }
        }.padding(12).background(GameTheme.boardPanel)
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.gold.opacity(0.65), lineWidth: 2))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trainingPreparation")
    }
}

private struct TrainingRuleStamp: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(GameTheme.boardMuted)
            Text(value).bold()
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
            .padding(7).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

private struct TrainingAttemptStrip: View {
    let scores: [Int]
    let expanded: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.adaptive(minimum: 110), spacing: 6)] : Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
    }
    private func color(_ index: Int) -> Color {
        guard index < scores.count else { return GameTheme.boardLine }
        return scores[index] >= 90 ? GameTheme.gold : scores[index] >= 75 ? GameTheme.growth : GameTheme.boardMuted
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                VStack(spacing: expanded ? 6 : 2) {
                    Text("\(index + 1)회").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Text(index < scores.count ? "\(scores[index])" : "·")
                        .font(expanded ? .title3.monospacedDigit().bold() : .caption.monospacedDigit().bold())
                        .foregroundStyle(index < scores.count ? color(index) : GameTheme.boardMuted)
                }.frame(maxWidth: .infinity, minHeight: expanded ? 66 : 38)
                    .background(GameTheme.boardPanel)
                    .overlay(ManagementStepFrame().strokeBorder(index == scores.count ? GameTheme.gold : color(index).opacity(0.65), lineWidth: expanded ? 2 : 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(index + 1)회 " + (index < scores.count ? "\(scores[index])점" : "대기"))
            }
        }
    }
}

private struct TrainingResultHeading: View {
    let player: CareerPlayer
    let name: String
    let average: Double
    let practice: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(practice ? "PRACTICE COMPLETE" : "TRAINING COMPLETE").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(name + " 훈련 완료").font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Text("평균 \(average, specifier: "%.1f")점").font(.title.monospacedDigit().bold())
                    .accessibilityIdentifier("trainingAverage")
                Text(player.name + " · #\(player.jerseyNumber)").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
                DetailGamePortrait(role: player.role, appearance: player.appearance, number: player.jerseyNumber,
                                   hand: player.throwingHandRaw, label: player.name + "의 훈련 도트")
                    .frame(width: 82, height: 108)
            }
        }.padding(16).background(GameTheme.boardPanel)
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.gold, lineWidth: 2))
    }
}

private struct TrainingGrowthReceipt: View {
    let name: String
    let before: Double
    let after: Double
    let gain: Double
    let fatigue: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ManagementPanel("성장 기록", surface: .paper) {
            Text(name).font(.subheadline.bold()).foregroundStyle(GameTheme.navy.opacity(0.8))
            Text("\(before, specifier: "%.1f") → \(after, specifier: "%.1f")")
                .font(.title.monospacedDigit().bold()).foregroundStyle(Color(hex: 0x237459))
                .accessibilityIdentifier("trainingGrowth")
            HStack {
                Text(gain > 0 && gain < 0.05 ? "성장 누적 중 · 0.1 미만" : "성장 +" + String(format: "%.1f", gain)).font(.subheadline.bold()).foregroundStyle(Color(hex: 0x237459))
                Spacer(minLength: 4)
                Text("MAX 100").font(.caption.monospaced()).foregroundStyle(GameTheme.navy.opacity(0.7))
            }
            TrainingSegmentTrack(value: after / 100, color: Color(hex: 0x237459), onPaper: true)
            if after < 100 {
                Text("다음 표시 \(TrainingGrowthDisplay.next(after),specifier: "%.1f")까지 \(Int((TrainingGrowthDisplay.progress(after)*100).rounded(.down)))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(GameTheme.navy)
                    .accessibilityIdentifier("trainingGrowthAccumulation")
                TrainingSegmentTrack(value: TrainingGrowthDisplay.progress(after), color: Color(hex: 0x237459), onPaper: true)
            }
            Divider().overlay(GameTheme.navy.opacity(0.2)).padding(.vertical, 4)
            Text("피로 \(fatigue) → \(min(100, fatigue + TrainingRules.fatigueCost))")
                .font(.subheadline.monospacedDigit().bold()).accessibilityIdentifier("trainingFatigue")
            TrainingSegmentTrack(value: Double(min(100, fatigue + TrainingRules.fatigueCost)) / 100, color: Color(hex: 0x8b431b), onPaper: true)
            Text("보상 저장 완료 · 다음 경기에 반영").font(.caption.bold()).foregroundStyle(GameTheme.navy.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("trainingCompleted")
        }
    }
}

private struct TrainingSegmentTrack: View {
    let value: Double
    let color: Color
    var onPaper = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill((onPaper ? GameTheme.navy : GameTheme.boardLine).opacity(0.16))
                Rectangle().fill(color).frame(width: geometry.size.width * min(1, max(0, value)))
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { _ in
                        Spacer(minLength: 0)
                        Rectangle().fill(onPaper ? GameTheme.boardInk : GameTheme.boardPanel).frame(width: 2)
                    }
                }
            }
        }.frame(height: 10).accessibilityHidden(true)
    }
}

private struct ContactTrainingFeedback: View {
    let result: ContactTrainingResult
    var body: some View {
        HStack(spacing: 12) {
            Canvas { context, size in
                let target = CGPoint(x: result.target.x * size.width, y: result.target.y * size.height)
                let aim = CGPoint(x: result.aim.x * size.width, y: result.aim.y * size.height)
                var line = Path(); line.move(to: target); line.addLine(to: aim)
                context.stroke(line, with: .color(GameTheme.paper.opacity(0.5)), lineWidth: 1)
                context.stroke(Path(CGRect(x: target.x - 6, y: target.y - 6, width: 12, height: 12)), with: .color(Color(hex: 0x82e6b2)), lineWidth: 2)
                context.stroke(Path(CGRect(x: aim.x - 3, y: aim.y - 3, width: 6, height: 6)), with: .color(GameTheme.gold), lineWidth: 2)
            }.frame(width: 40, height: 40).clipped().background(GameTheme.navy)
                .overlay(Rectangle().strokeBorder(GameTheme.paper.opacity(0.4)))
                .accessibilityLabel("큰 사각 목표와 작은 사각 조준 위치 비교")
            VStack(alignment: .leading, spacing: 4) {
                Text(result.didSwing ? "직전 · 조준 65% / 타이밍 35%" : "지켜보기 · 0점").font(.caption2)
                Text("조준 \(result.positionScore)점 · 타이밍 \(result.timingScore)점")
                    .font(.caption.bold()).accessibilityIdentifier("contactScoreBreakdown")
                Text("종합 \(result.total)점")
                    .font(.caption.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contactTotalScore")
            }
            Spacer(minLength: 0)
        }.padding(8).background(Color(hex: 0x203e57))
            .accessibilityElement(children: .contain).accessibilityIdentifier("contactFeedback")
    }
}

private struct TrainingChromeHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PitchRepertoireView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    @Environment(\.modelContext) private var context
    @State private var progress: [String: Double] = [:]
    @State private var archives: [PitchStoredSkill] = []
    @State private var pending = false
    @State private var blocked: String?
    @State private var replacing = ""
    @State private var selectedCode: String?
    @State private var confirm = false
    @State private var showTraining = false
    private var ordered: [CareerPitchMastery] { player.pitches.sorted { $0.order < $1.order } }
    private var choices: [PitchType] { PitchType.allCases.filter { pitch in !player.pitches.contains { $0.code == pitch.rawValue } } }
    private var canStart: Bool { blocked == nil && !pending && (player.pitches.count < 5 || !replacing.isEmpty) }
    private func load() {
        do {
            archives = try PitchStudyStore.archived(player: player, in: context)
            progress = try Dictionary(uniqueKeysWithValues: choices.map { ($0.rawValue, try PitchStudyStore.progress(player: player, code: $0.rawValue, in: context)) })
            pending = try CareerTrainingStore.record(player: player, in: context).map { !$0.completed } ?? false
            blocked = nil
            if !pending {
                if calendar.hasAction(on: player.gameDate) { blocked = "오늘 행동을 사용했습니다. 다음 훈련일에 시작할 수 있습니다." }
                else {
                    try CareerTrainingStore.requireNoPending(player: player, in: context)
                    let id = player.id, date = player.gameDate
                    if try context.fetchCount(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == id && $0.gameDate == date })) > 0 {
                        blocked = "오늘 경기 기록을 먼저 마친 뒤 다음 훈련일에 구종을 변경하세요."
                    }
                }
            }
        } catch { blocked = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ManagementPanel("등록 구종 · \(ordered.count) / 5") {
                    Text("등록 3~5종 · 경기에 사용할 구종과 숙련도").managementFont(.helper)
                        .accessibilityIdentifier("pitchLibraryCount")
                    ForEach(ordered) { pitch in
                        HStack(spacing: 12) {
                            MatchGrip(code: pitch.code, hand: player.throwingHandRaw).frame(width: 44, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pitch.name).font(.headline)
                                ProgressView(value: pitch.mastery, total: 100).tint(GameTheme.gold)
                            }
                            Text(pitch.mastery.formatted(.number.precision(.fractionLength(1)))).font(.headline.monospacedDigit())
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("pitchLibraryOwned-" + pitch.code)
                    }
                }
                if pending {
                    NavigationLink { CareerTrainingView(player: player, calendar: calendar) } label: { Text("진행 중인 훈련 이어하기") }
                        .buttonStyle(ManagementButtonStyle()).accessibilityIdentifier("pitchLibraryResume")
                }
                ManagementPanel("새 구종 · 습득과 등록", surface: .paper) {
                    Text("5회 훈련 성적에 따라 습득 진척이 쌓입니다. 100에 도달하면 숙련도20으로 등록합니다.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Picker("등록할 자리", selection: $replacing) {
                        Text(player.pitches.count < 5 ? "빈 슬롯에 추가" : "교체할 구종 선택").tag("")
                        ForEach(ordered) { pitch in Text(pitch.name + " 자리 · 기존 숙련 보관").tag(pitch.code) }
                    }.accessibilityIdentifier("pitchStudyReplacement")
                    if let blocked { Text(blocked).font(.caption).foregroundStyle(GameTheme.navy) }
                    if player.pitches.count >= 5 && replacing.isEmpty {
                        Text("등록5개 · 교체할 구종을 먼저 선택하세요.").font(.caption.bold())
                    }
                    ForEach(choices) { pitch in
                        let archived = archives.first { $0.code == pitch.rawValue }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                MatchGrip(code: pitch.rawValue, hand: player.throwingHandRaw).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pitch.label).font(.headline)
                                    Text(archived.map { "보관 숙련 \($0.mastery.formatted(.number.precision(.fractionLength(1)))) · 5회 재등록으로 복원" }
                                         ?? "습득 진척 \((progress[pitch.rawValue] ?? 0).formatted(.number.precision(.fractionLength(1)))) / 100")
                                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("pitchStudyProgress-" + pitch.rawValue)
                                }
                            }
                            ProgressView(value: archived?.mastery ?? progress[pitch.rawValue] ?? 0, total: 100).tint(archived == nil ? GameTheme.growth : GameTheme.gold)
                                .accessibilityLabel(archived == nil ? "습득 진척" : "보관 숙련도")
                            Button(archived == nil ? "\(pitch.label) 습득 훈련" : "\(pitch.label) 재등록 훈련") {
                                selectedCode = pitch.rawValue; confirm = true
                            }.buttonStyle(ManagementButtonStyle(variant: .secondary)).disabled(!canStart)
                                .accessibilityIdentifier("pitchStudyStart-" + pitch.rawValue)
                        }.padding(.vertical, 6)
                    }
                }
                Text("훈련 완료 시 피로+6 · 하루 행동1회. 교체 전 구종은 숙련도를 보관하며, 진행 중인 경기·훈련의 구성은 바꾸지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.paper).navigationTitle("구종 보관함")
            .onAppear(perform: load)
            .alert("구종 훈련을 준비할까요?", isPresented: $confirm) {
                Button("훈련 준비 화면으로") { showTraining = true }.accessibilityIdentifier("pitchStudyConfirm")
                Button("취소", role: .cancel) {}
            } message: {
                Text(replacing.isEmpty ? "새 구종은 빈 슬롯에 추가됩니다. 준비 화면에서 훈련을 시작할 때 일정이 고정됩니다." : ordered.first(where: { $0.code == replacing }).map { "\($0.name) 숙련 \(String(format: "%.1f",$0.mastery)) 보관 → \(PitchType(rawValue: selectedCode ?? "")?.label ?? "새 구종") 등록. 재등록은 보관 숙련을 복원하고 신규는 진척100에 숙련20으로 시작합니다." } ?? "교체할 구종을 다시 확인하세요.")
            }
            .navigationDestination(isPresented: $showTraining) {
                CareerTrainingView(player: player, calendar: calendar, initialKind: .pitch,
                                   initialPitchStudyCode: selectedCode, replacingPitchCode: replacing.isEmpty ? nil : replacing)
            }
    }
}
