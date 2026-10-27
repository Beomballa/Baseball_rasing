import SwiftUI
import SwiftData

struct TraitManagementPanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState?
    var onBoard = false
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Query private var profiles: [PlayerTraits]
    @Query private var trainingRecords: [CareerTrainingRecord]
    @State private var errorMessage: String?
    private var profile: PlayerTraits? { profiles.first { $0.playerID == player.id } }
    private var lockReason: String? {
        guard let calendar else { return "달력 정보를 확인할 수 없어 특성을 변경할 수 없습니다." }
        do { try PlayerTraitStore.requireEditable(player: player, state: calendar, in: context); return nil }
        catch { return error.localizedDescription }
    }
    private func toggle(_ trait: PlayerTrait) {
        guard let profile, let calendar else { return }
        do {
            try PlayerTraitStore.toggle(player: player, state: calendar, profile: profile, trait: trait, date: player.gameDate,
                                        revision: profile.revision, calendarRevision: calendar.revision, in: context)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func slots(_ value: TraitLoadout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let summary = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            summary {
                Text("활성 \(value.active.count) / 3").font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("traitActiveCount")
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text("보유 \(value.owned.count)종").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(0..<3, id: \.self) { index in
                    let trait = index < value.active.count ? value.active[index] : nil
                    VStack(spacing: 6) {
                        Text("SLOT 0\(index + 1)").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.boardMuted)
                        if let trait {
                            TraitPixelIcon(trait: trait).frame(width: 36, height: 36)
                            Text(trait.label).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                        } else {
                            Rectangle().strokeBorder(GameTheme.boardLine, style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .frame(width: 32, height: 32)
                            Text("비어 있음").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        }
                    }.padding(10).frame(maxWidth: .infinity, minHeight: 104)
                        .background(GameTheme.navy, in: ManagementStepFrame())
                        .overlay(ManagementStepFrame().strokeBorder(trait == nil ? GameTheme.boardLine : GameTheme.gold, lineWidth: 2))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(trait.map { "활성 슬롯 \(index + 1), " + $0.label } ?? "빈 활성 슬롯 \(index + 1)")
                        .accessibilityIdentifier("traitSlot-\(index + 1)")
                }
            }
        }
    }
    private func conditionValue(_ trait: PlayerTrait) -> Double {
        switch trait { case .strongArm: player.arm; case .cheetah: player.speed; case .safeHands: player.defense }
    }
    private func card(_ trait: PlayerTrait, value: TraitLoadout, locked: Bool) -> some View {
        let owned = value.owned.contains(trait), active = value.active.contains(trait)
        let qualifies = trait.qualifies(speed: player.speed, defense: player.defense, arm: player.arm)
        return VStack(alignment: .leading, spacing: 14) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                TraitPixelIcon(trait: trait).frame(width: 48, height: 48).padding(10)
                    .background(GameTheme.navy).overlay(Rectangle().strokeBorder(active ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                    .opacity(owned ? 1 : 0.65)
                VStack(alignment: .leading, spacing: 6) {
                    Text(trait.label).font(.title3.bold()).foregroundStyle(GameTheme.boardInk)
                    Text(active ? "활성 · 경기 적용" : owned ? "보유 · 비활성" : "미보유 · 훈련으로 습득")
                        .font(.subheadline.bold()).foregroundStyle(active ? GameTheme.growth : GameTheme.boardMuted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("경기 효과").font(.caption.bold()).foregroundStyle(ManagementTheme.Palette.secondaryLight)
                Text(trait.effect).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("traitEffect-" + trait.rawValue)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(ManagementTheme.Palette.ink).background(ManagementTheme.Palette.paper, in: ManagementStepFrame())
            VStack(alignment: .leading, spacing: 8) {
                Text("습득 조건 · " + trait.condition).font(.subheadline.bold()).foregroundStyle(GameTheme.boardInk)
                    .accessibilityIdentifier("traitCondition-" + trait.rawValue)
                layout {
                    Text("현재 능력 \(conditionValue(trait), specifier: "%.1f")").font(.subheadline.monospacedDigit())
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(qualifies ? "충족" : "미충족").font(.subheadline.bold()).foregroundStyle(qualifies ? GameTheme.growth : GameTheme.gold)
                }
            }
            if owned {
                Button(active ? "활성 해제" : "활성화") { toggle(trait) }
                    .buttonStyle(GameButtonStyle(secondary: active, onBoard: onBoard))
                    .disabled(locked || (!active && value.active.count >= 3))
                    .accessibilityIdentifier("traitToggle-" + trait.rawValue)
                    .accessibilityLabel(trait.label + (active ? " 활성 해제" : " 활성화"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("훈련 진척 \(value.trainingProgress(trait), specifier: "%.1f") / 100.0").font(.caption.monospacedDigit())
                        .foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("traitProgress-" + trait.rawValue)
                    TraitProgressBar(value: value.trainingProgress(trait))
                    Text(qualifies ? "조건 충족 · 진척 100 도달 시 습득" : "능력치 조건을 먼저 채워 주세요")
                        .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }
            }
            if let calendar {
                let saved = trainingRecords.first { $0.playerID == player.id && $0.gameDate == player.gameDate }
                let same = (try? saved?.snapshot().trait) == trait
                if same || !owned {
                    NavigationLink {
                        TraitTrainingLiveView(player: player, calendar: calendar, initialTrait: trait)
                    } label: { Text(same ? (saved?.completed == true ? "오늘 특성 훈련 결과" : "특성 훈련 이어하기") : "특성 습득 훈련") }
                        .buttonStyle(GameButtonStyle(onBoard: true)).disabled(!same && (locked || !qualifies))
                        .accessibilityIdentifier("traitTraining-" + trait.rawValue)
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(onBoard ? GameTheme.board : GameTheme.paper, in: ManagementStepFrame())
            .overlay(ManagementStepFrame().strokeBorder(active ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("traitCard-" + trait.rawValue)
    }
    var body: some View {
        let _ = calendar?.revision
        let reason = lockReason
        return GamePanel(title: compact ? "보유 · 활성 특성" : "활성 특성 구성", onBoard: onBoard) {
            if let errorMessage {
                Text(errorMessage).font(.subheadline).foregroundStyle(Color(hex: 0xffb4a8)).accessibilityIdentifier("traitSaveError")
                Button("상태 다시 확인") { self.errorMessage = nil }
                    .buttonStyle(GameButtonStyle(secondary: true, onBoard: onBoard)).accessibilityIdentifier("traitRetry")
            }
            if let profile, let value = try? profile.snapshot() {
                slots(value)
                if let reason {
                    Text(reason).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitLocked")
                } else {
                    Text("훈련·휴식 전 변경 가능 · 날짜와 피로를 소비하지 않습니다.")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("traitEditable")
                }
                if compact {
                    Text("보유 \(value.owned.count)종 · \(value.active.isEmpty ? "활성 특성 없음" : value.active.map(\.label).joined(separator: " · "))")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    NavigationLink {
                        TraitDetailView(player: player, calendar: calendar)
                    } label: { Text("특성 상세 관리 ›") }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: onBoard)).accessibilityIdentifier("traitDetails")
                } else {
                    Text("보유 도감 · \(value.owned.count)").font(.title3.bold()).padding(.top, 12)
                    if value.owned.isEmpty { Text("보유한 특성이 없습니다.").font(.subheadline).accessibilityIdentifier("traitOwnedEmpty") }
                    ForEach(PlayerTrait.allCases.filter { value.owned.contains($0) }) { card($0, value: value, locked: reason != nil) }
                    let missing = PlayerTrait.allCases.filter { !value.owned.contains($0) }
                    if !missing.isEmpty {
                        Text("습득 도전 · \(missing.count)").font(.title3.bold()).padding(.top, 12)
                        ForEach(missing) { card($0, value: value, locked: reason != nil) }
                    }
                }
            } else {
                Text(TraitError.invalidRecord.localizedDescription).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitLoadError")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("traitManagementPanel")
    }

}

struct TraitPixelIcon: View {
    let trait: PlayerTrait
    private var pixels: [String] {
        switch trait {
        case .strongArm: ["............", ".......aa...", "......abba..", "......abba..", "......aaa...", ".....aaaa...", "....aabba...", "...abbbba...", "..abbbbba...", "..aaaaaaa...", "...nnnn.....", "............"]
        case .cheetah: ["............", "...gg.gg....", "..ggggggg...", "..gnggngg...", "...ggngg....", "....ggg.....", "...gngng....", "..ggggggg...", "..gnngnng...", "...gg.gg....", "............", "............"]
        case .safeHands: ["............", "...a.a.a....", "..aaaaaaa...", "..ababaab...", "..abbbbaa...", ".aabbbbaa...", ".abbbbbba...", "..abbbbaa...", "..aabbaaa...", "...aaaaa....", "....nnn.....", "............"]
        }
    }
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 12
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != "." {
                    let color: Color = pixel == "n" ? GameTheme.navy : pixel == "g" ? GameTheme.gold : pixel == "a" ? Color(hex: 0x986743) : Color(hex: 0xefbe91)
                    context.fill(Path(CGRect(x: Double(x) * scale, y: Double(y) * scale, width: scale, height: scale)), with: .color(color))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct TraitDetailView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState?
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GamePanel(title: "선수 특성", onBoard: true) {
                    HStack(spacing: 12) {
                        DetailGamePortrait(role: player.role, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw)
                            .frame(width: 72, height: 88).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(player.name) #\(player.jerseyNumber)").font(.headline).accessibilityIdentifier("traitPlayerName")
                            Text("\(player.schoolName) · \(player.role.label)").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        }
                    }
                    Text("보유 특성 중 최대 3개 활성화").font(.caption).foregroundStyle(GameTheme.gold)
                }
                TraitManagementPanel(player: player, calendar: calendar, onBoard: true)
                #if DEBUG
                NavigationLink("특성 습득 훈련 · 화면 미리보기") { TraitAcquisitionPreview() }
                    .buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                    .accessibilityIdentifier("traitAcquisitionPreview")
                #endif
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("특성 상세 관리").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#if DEBUG
// Sample-only UI: no ModelContext, save, daily action or acquisition calls.
struct TraitAcquisitionPreview: View {
    enum SampleState: String, CaseIterable, Identifiable {
        case ready = "훈련 가능", short = "조건 미달", near = "습득 직전", owned = "보유", locked = "오늘 행동 완료"
        var id: String { rawValue }
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected = PlayerTrait.strongArm
    @State private var sample = SampleState.ready
    @State private var showDrill = false
    private var threshold: Double { selected == .safeHands ? 50 : 60 }
    private var current: Double { threshold + (sample == .short ? -5 : 4) }
    private var progress: Double { sample == .owned ? 100 : sample == .near ? 99.4 : 36.8 }
    private var reason: String {
        switch sample {
        case .short: "먼저 \(selected.condition)을 달성하세요."
        case .owned: "이미 보유 중 · 특성 관리에서 활성화하세요."
        case .locked: "오늘 행동을 사용했습니다. 다음 날 훈련할 수 있습니다."
        default: "5회 훈련 · 완료 시 하루 행동 사용 / 피로 +6"
        }
    }
    private var canPreview: Bool { sample == .ready || sample == .near }
    private var informationLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
    }
    private var board: some View {
        TraitTrainingArena(trait: selected, target: TrainingRules.basePoint(1), player: TrainingTarget(x: 0.48, y: 0.7),
                           endpoint: TrainingRules.basePoint(1), motion: 0, steps: 0, moving: false, success: nil)
            .accessibilityHidden(true)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("화면 시안 · 능력치와 진척은 샘플 / 저장 안 함")
                        .font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("acquisitionPreviewNotice")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 6) {
                        ForEach(PlayerTrait.allCases) { trait in
                            Button { selected = trait } label: {
                                VStack(spacing: 5) {
                                    TraitPixelIcon(trait: trait).frame(width: 26, height: 26)
                                    Text(trait.label).font(.subheadline.bold())
                                }.padding(.vertical, 8).frame(maxWidth: .infinity)
                                    .background(selected == trait ? GameTheme.boardPanel : GameTheme.board)
                                    .overlay(Rectangle().strokeBorder(selected == trait ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityIdentifier("acquisitionTrait-" + trait.rawValue)
                                .accessibilityAddTraits(selected == trait ? .isSelected : [])
                        }
                    }
                    GamePanel(title: selected.label + " 습득", onBoard: true) {
                        Text(selected.effect).font(.subheadline)
                        Text("조건 · \(selected.condition) / 현재 \(current.formatted(.number.precision(.fractionLength(1))))")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("acquisitionCondition")
                        Text(sample == .short ? "조건 미충족" : "능력치 조건 충족")
                            .font(.caption.bold()).foregroundStyle(sample == .short ? GameTheme.gold : GameTheme.growth)
                        informationLayout {
                            Text(sample == .owned ? "습득 완료" : "훈련 진척")
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text("\(progress.formatted(.number.precision(.fractionLength(1)))) / 100.0").monospacedDigit()
                                .accessibilityIdentifier("acquisitionProgress")
                        }.font(.subheadline.bold())
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(GameTheme.navy)
                                Rectangle().fill(GameTheme.gold).frame(width: bar.size.width * progress / 100)
                                HStack(spacing: 0) { ForEach(0..<20) { _ in Rectangle().strokeBorder(GameTheme.boardPanel, lineWidth: 1) } }
                            }
                        }.frame(height: 14).accessibilityHidden(true)
                        Text("100 도달 시 보유 특성에 추가 · 활성화는 직접 선택")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        informationLayout {
                            Text(selected.drillTitle).bold()
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text("5회").monospaced()
                        }.font(.subheadline)
                        board.frame(height: typeSize.isAccessibilitySize ? 190 : max(150, min(210, geometry.size.height - 470)))
                        Text(selected.drillInstruction).font(.caption).foregroundStyle(GameTheme.gold)
                    }
                    Text(reason).font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("acquisitionState")
                    Button(sample == .owned ? "이미 습득한 특성" : sample == .short ? "능력치 조건 미충족" : sample == .locked ? "오늘 훈련 불가" : "훈련 체험 · 5회") { showDrill = true }
                        .buttonStyle(GameButtonStyle(onBoard: true)).disabled(!canPreview).accessibilityIdentifier("acquisitionStartPreview")
                }.padding(12)
            }
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("특성 습득 훈련").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("샘플 상태", selection: $sample) { ForEach(SampleState.allCases) { Text($0.rawValue).tag($0) } }
                    } label: { Text("시안 상태").font(.caption.bold()) }
                        .accessibilityIdentifier("acquisitionSampleState")
                }
            }
            .fullScreenCover(isPresented: $showDrill) { NavigationStack { TraitDrillExperience(trait: selected) } }
    }
}

#endif

struct CareerTrainingDestination: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    var initialKind: TrainingKind? = nil
    @Query private var records: [CareerTrainingRecord]
    var body: some View {
        if let record = records.first(where: { $0.playerID == player.id && $0.gameDate == player.gameDate }),
           (try? record.snapshot().position) != nil {
            PositionTrainingView(player: player, calendar: calendar)
        } else if let record = records.first(where: { $0.playerID == player.id && $0.gameDate == player.gameDate }),
           let training = try? record.snapshot(), let trait = training.trait {
            TraitTrainingLiveView(player: player, calendar: calendar, initialTrait: trait)
        } else { CareerTrainingView(player: player, calendar: calendar, initialKind: initialKind) }
    }
}

struct TraitTrainingLiveView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let initialTrait: PlayerTrait
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected = PlayerTrait.strongArm
    @State private var loadout: TraitLoadout?
    @State private var record: CareerTrainingRecord?
    @State private var errorMessage: String?
    @State private var showDrill = false
    @State private var loaded = false
    private func load(open: Bool = false) {
        do {
            guard let profile = try PlayerTraitStore.profile(playerID: player.id, in: context) else { throw TraitError.invalidRecord }
            loadout = try profile.snapshot()
            record = try CareerTrainingStore.record(player: player, in: context)
            if let record, let trait = try record.snapshot().trait { selected = trait; if open { showDrill = true } }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func start() {
        do {
            record = try CareerTrainingStore.start(player: player, state: calendar, trait: selected, in: context)
            errorMessage = nil; showDrill = true
        } catch { errorMessage = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(player.name) · 피로 \(player.fatigue) · \((try? calendar.age(of: player)) ?? player.startAge)세")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitTrainingError")
                    Button("기록 다시 확인") { load() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                }
                if let loadout {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 1 : 3)) {
                        ForEach(PlayerTrait.allCases) { trait in
                            Button { selected = trait } label: {
                                VStack { TraitPixelIcon(trait: trait).frame(width: 26, height: 26); Text(trait.label).font(.subheadline.bold()) }
                                    .padding(8).frame(maxWidth: .infinity).overlay(Rectangle().strokeBorder(selected == trait ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
                            }.buttonStyle(.plain).disabled(record != nil).accessibilityIdentifier("liveTrait-" + trait.rawValue)
                        }
                    }
                    GamePanel(title: selected.label + " 습득", onBoard: true) {
                        Text(selected.effect).font(.subheadline)
                        Text("습득 조건 · " + selected.condition).font(.caption).foregroundStyle(GameTheme.boardMuted)
                        let value = selected == .strongArm ? player.arm : selected == .cheetah ? player.speed : player.defense
                        Text("현재 \(value, specifier: "%.1f") · \(selected.qualifies(speed: player.speed, defense: player.defense, arm: player.arm) ? "조건 충족" : "조건 미달")").font(.caption)
                        Text("진척 \(loadout.trainingProgress(selected), specifier: "%.1f") / 100.0").font(.headline.monospaced()).accessibilityIdentifier("liveTraitProgress")
                        TraitProgressBar(value: loadout.trainingProgress(selected))
                        Text("100 도달 시 보유 · 다음 날 준비 전에 직접 활성화").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                    TraitTrainingArena(trait: selected, target: TrainingRules.basePoint(1), player: TrainingTarget(x: 0.5, y: 0.65), endpoint: TrainingRules.basePoint(1), motion: 0, steps: 0, moving: false, success: nil, appearance: player.appearance)
                        .frame(height: 195).accessibilityHidden(true)
                    Text(selected.drillInstruction).font(.caption).foregroundStyle(GameTheme.gold)
                    Text("5회 평균으로 진척 증가 · 완료 시 피로 +6 / 하루 행동 사용").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Button(record == nil ? "특성 훈련 시작 · 5회" : record?.completed == true ? "오늘 훈련 결과" : "특성 훈련 이어하기") {
                        if record != nil { showDrill = true } else { start() }
                    }.buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("startTraitTraining")
                        .disabled(errorMessage != nil || (record == nil && (calendar.hasAction(on: player.gameDate) || loadout.owned.contains(selected) || !selected.qualifies(speed: player.speed, defense: player.defense, arm: player.arm))))
                }
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("특성 습득 훈련").navigationBarTitleDisplayMode(.inline)
            .onAppear { if !loaded { loaded = true; selected = initialTrait; load(open: true) } }
            .fullScreenCover(isPresented: $showDrill, onDismiss: { load() }) {
                if let record { NavigationStack { TraitDrillExperience(trait: selected, player: player, calendar: calendar, record: record) } }
            }
    }
}

private struct TraitProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { bar in
            ZStack(alignment: .leading) {
                Rectangle().fill(GameTheme.navy)
                Rectangle().fill(GameTheme.gold).frame(width: bar.size.width * min(100, max(0, value)) / 100)
                HStack(spacing: 0) { ForEach(0..<20) { _ in Rectangle().strokeBorder(GameTheme.boardPanel, lineWidth: 1) } }
            }
        }.frame(height: 14).accessibilityHidden(true)
    }
}

private extension PlayerTrait {
    var drillTitle: String { switch self { case .strongArm: "송구 클리닉"; case .cheetah: "첫발 스프린트"; case .safeHands: "낙구 포구 훈련" } }
    var drillInstruction: String {
        switch self {
        case .strongArm: "베이스 선택 후 훈련장에서 방향·거리를 드래그해 송구하세요."
        case .cheetah: "4초 동안 왼발·오른발을 번갈아 눌러 질주하세요."
        case .safeHands: "선수를 낙하지점으로 옮긴 뒤 글러브를 내미세요."
        }
    }
}

struct TraitTrainingArena: View {
    let trait: PlayerTrait
    let target: TrainingTarget
    let player: TrainingTarget
    let endpoint: TrainingTarget
    let motion: Double
    let steps: Int
    let moving: Bool
    let success: Bool?
    var appearance = PlayerAppearance()
    var number = 1
    var hand = "right"
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 320, y: size.height / 220)
            TrainingFieldArt.background(in: context)
            func point(_ p: TrainingTarget) -> CGPoint { TrainingFieldArt.point(p) }
            @MainActor func actor(_ p: CGPoint, _ facing: FieldFacing, _ stage: FieldSpriteStage, runner: Bool = false, coach: Bool = false) {
                TrainingFieldArt.actor(in: context, at: p, appearance: appearance, number: coach ? 0 : number,
                    hand: hand, motion: FieldSpriteMotion(facing: facing, stage: stage, progress: stage == .catchBall ? 1 : motion, gait: motion * 24, chestCatch: stage == .catchBall), runner: runner, coach: coach)
            }
            let flight = TrainingFieldMotion.flight(motion)
            if trait == .cheetah {
                let lane = CGRect(x: 16, y: 125, width: 288, height: 65)
                context.fill(Path(lane), with: .color(Color(hex: 0xb78450)))
                for y in [133.0,160,187] {
                    var path = Path(); path.move(to: CGPoint(x: 16,y: y)); path.addLine(to: CGPoint(x: 304,y: y))
                    context.stroke(path, with: .color(Color(hex: 0xf3edcf)), lineWidth: 2)
                }
                for i in 0..<8 { context.fill(Path(CGRect(x: 280 + (i%2)*6,y: 125+i*8,width: 6,height: 8)), with: .color(i%2 == 0 ? .white : GameTheme.navy)) }
                let x = 38 + Double(min(16,steps)) / 16 * 232
                actor(CGPoint(x: x,y: 166), .direction(dx: 1,dy: 0), moving ? .run : .ready, runner: true)
                actor(CGPoint(x: 301,y: 103), .direction(dx: -1,dy: 1), .ready, coach: true)
            } else {
                let bases = [4,1,2,3,4].map { point(TrainingRules.basePoint($0)) }
                var dirt = Path(); dirt.addLines(bases); dirt.closeSubpath()
                context.fill(dirt, with: .color(Color(hex: 0xba8851)))
                context.stroke(dirt, with: .color(Color(hex: 0xf3edcf)), lineWidth: 2)
                for base in 1...4 { let p = point(TrainingRules.basePoint(base)); context.fill(Path(CGRect(x:p.x-4,y:p.y-3,width:8,height:6)),with:.color(.white)) }
                let goal = point(target)
                TrainingFieldArt.marker(in: context, at: goal, goal: true)
                if trait == .strongArm {
                    let origin = point(TrainingTarget(x: 0.5,y: 0.63)), end = point(endpoint)
                    let facing = FieldFacing.direction(dx: end.x-origin.x,dy: end.y-origin.y)
                    let throwing = FieldSpriteMotion(facing: facing,stage: .release,progress: 1)
                    let catchFacing = FieldFacing.direction(dx: origin.x-end.x,dy: origin.y-end.y)
                    let catching = FieldSpriteMotion(facing: catchFacing,stage: .catchBall,progress: 1,chestCatch: true)
                    let start = TrainingFieldArt.contact(throwing,origin: origin,hand: true,left: hand == "left")
                    let finish = TrainingFieldArt.contact(catching,origin: end,hand: false,left: hand == "left")
                    let receiver = CGPoint(x:goal.x+(end.x-goal.x)*flight,y:goal.y+(end.y-goal.y)*flight)
                    actor(receiver, catchFacing, moving && flight < 0.8 ? .run : flight >= 0.8 ? .catchBall : .ready, coach: true)
                    actor(origin,facing,moving ? TrainingFieldMotion.stage(motion) : .ready)
                    TrainingFieldArt.marker(in: context, at: end, goal: false)
                    if moving || success != nil {
                        let p = CGPoint(x:start.x+(finish.x-start.x)*flight,y:start.y+(finish.y-start.y)*flight-sin(flight * .pi)*20)
                        if motion >= TrainingFieldMotion.release { PixelBaseball.draw(in:context,at:p,diameter:8) }
                    }
                } else {
                    let p = point(player), facing = FieldFacing.direction(dx: 0,dy: 1)
                    actor(p,facing,moving && flight > 0.8 ? .catchBall : .ready)
                    TrainingFieldArt.marker(in:context,at:p,goal:false)
                    if moving || success != nil {
                        let home = point(TrainingRules.basePoint(4))
                        PixelBaseball.draw(in:context,at:CGPoint(x:home.x+(goal.x-home.x)*flight,y:home.y+(goal.y-home.y)*flight-sin(flight * .pi)*42-10),diameter:8)
                    }
                }
            }
        }.clipped().overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
    }
}

struct TraitDrillExperience: View {
    let trait: PlayerTrait
    var player: CareerPlayer? = nil
    var calendar: CareerCalendarState? = nil
    var record: CareerTrainingRecord? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var scores: [Int] = []
    @State private var selectedBase = 1
    @State private var angle = 0.0
    @State private var force = 51.0
    @State private var x = 0.5
    @State private var y = 0.66
    @State private var running = false
    @State private var startedAt = Date()
    @State private var steps = 0
    @State private var lastFoot = 0
    @State private var feedback: String?
    @State private var pendingScore = 0
    @State private var savedTraining: CareerTraining?
    @State private var pendingInput: TrainingInput?
    @State private var pendingRevision: Int?
    @State private var feet: [SprintFoot] = []
    @State private var errorMessage: String?
    private var finished: Bool { scores.count == 5 }
    private var averageScore: Int { Int((Double(scores.reduce(0) { $0 + $1 }) / 5.0).rounded()) }
    private var attemptIndex: Int { min(4, max(0, scores.count - (feedback == nil ? 0 : 1))) }
    private var targetBase: Int { [1, 2, 3, 2, 1][attemptIndex] }
    private var target: TrainingTarget { trait == .safeHands ? savedTraining?.targets[attemptIndex] ?? TrainingTarget(x: [0.68, 0.3, 0.62, 0.4, 0.52][attemptIndex], y: 0.48) : TrainingRules.basePoint(targetBase) }
    private var endpoint: TrainingTarget { TrainingRules.throwEndpoint(angle: angle, force: force) }
    private var targetText: String { trait == .strongArm ? "목표 \(targetBase)루 · 베이스 선택 + 정확한 송구" : trait == .cheetah ? "4초 / 교대 16걸음 목표" : "금색 낙하지점으로 이동 · 포구" }
    private func submit() {
        guard !running, feedback == nil, !finished, errorMessage == nil else { return }
        pendingScore = trait == .strongArm
            ? (selectedBase == targetBase ? Int((max(0, 1 - hypot(endpoint.x - target.x, endpoint.y - target.y) / 0.3) * 100).rounded()) : 0)
            : Int((max(0, 1 - hypot(x - target.x, y - target.y) / 0.55) * 100).rounded())
        pendingInput = trait == .strongArm ? TrainingInput(force: force, angle: angle, base: selectedBase) : TrainingInput(x: x, y: y)
        pendingRevision = record?.revision; startedAt = Date(); running = true
    }
    private func step(_ foot: Int) {
        guard feedback == nil, !finished, errorMessage == nil else { return }
        guard foot != lastFoot else { return }
        if !running { startedAt = Date(); running = true; pendingRevision = record?.revision }
        lastFoot = foot; steps += 1; feet.append(foot == 1 ? .left : .right)
    }
    private func resolve() {
        if record != nil {
            if trait == .cheetah { pendingInput = TrainingInput(footfalls: feet) }
            running = false; saveInput(); return
        }
        let score = trait == .cheetah ? min(100, Int((Double(steps) / 16 * 100).rounded())) : pendingScore
        scores.append(score); running = false
        feedback = score >= 90 ? "GREAT · 정확한 동작!" : score >= 60 ? "GOOD · 조금 더 정확하게" : "RETRY · \(trait == .strongArm ? "베이스와 방향·힘을 확인하세요" : trait == .cheetah ? "좌·우를 더 빠르게 교대하세요" : "낙하지점에 더 가까이 이동하세요")"
    }
    private func loadRecord() {
        guard let record else { return }
        do {
            let training = try record.snapshot()
            guard training.trait == trait else { throw TrainingError.invalidRecord }
            savedTraining = training; scores = training.scores
            if training.completed { feedback = "훈련 결과 저장 완료" }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func saveInput() {
        guard let player, let calendar, let record, let input = pendingInput, let revision = pendingRevision else { return }
        do {
            try CareerTrainingStore.attempt(player: player, state: calendar, record: record, revision: revision, input: input, in: context)
            loadRecord()
            let score = scores.last ?? 0
            feedback = record.completed ? "훈련 결과 저장 완료" : score >= 90 ? "GREAT · 정확한 동작!" : score >= 60 ? "GOOD · 조금 더 정확하게" : "다음 시도에 다시 도전하세요."
            pendingInput = nil; pendingRevision = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private var controls: some View {
        VStack(spacing: 10) {
            if trait == .strongArm {
                HStack { ForEach(1...3, id: \.self) { base in
                    Button("\(base)루") { selectedBase = base }.buttonStyle(GameButtonStyle(secondary: selectedBase == base, onBoard: true))
                        .accessibilityIdentifier("traitDrillBase-\(base)")
                } }
                HStack {
                    TrainingAdjustment(label: "방향", value: $angle, range: 0...360, suffix: "°", identifier: "traitDrillAngle")
                    TrainingAdjustment(label: "힘", value: $force, range: 8...100, suffix: "%", identifier: "traitDrillForce")
                }
            } else if trait == .safeHands {
                HStack { ForEach(["←", "↑", "↓", "→"], id: \.self) { direction in
                    Button(direction) {
                        if direction == "←" { x = max(0.1, x - 0.05) }; if direction == "→" { x = min(0.9, x + 0.05) }
                        if direction == "↑" { y = max(0.2, y - 0.05) }; if direction == "↓" { y = min(0.9, y + 0.05) }
                    }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true))
                        .accessibilityLabel(["←": "왼쪽", "↑": "위", "↓": "아래", "→": "오른쪽"][direction]!)
                        .accessibilityIdentifier("traitDrillMove-" + direction)
                } }
            }
        }.disabled(running || feedback != nil || finished || errorMessage != nil)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(record == nil ? "체험 모드 · 점수만 표시 / 실제 진척·피로는 그대로" : "확정 시도마다 저장 · 5회 완료 시 진척 반영").font(.caption).foregroundStyle(GameTheme.gold)
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitDrillError")
                        Button(pendingInput == nil ? "기록 다시 확인" : "같은 결과 저장 재시도") {
                            if pendingInput == nil { loadRecord() } else { saveInput() }
                        }.buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("traitDrillRetry")
                    }
                    Text(targetText).font(.subheadline.bold()).accessibilityIdentifier("traitDrillTarget")
                    let mission = TrainingMissionProgress(kind: trait == .cheetah ? .speed : trait == .strongArm ? .arm : .defense, scores: scores)
                    HStack {
                        Text("\(scores.count) / 5").font(.caption.monospaced()).accessibilityIdentifier("traitAttemptCount")
                        Spacer(minLength: 4)
                        Text("목표75점3회 · 성공 \(mission.successes)/3").font(.caption2)
                    }.foregroundStyle(GameTheme.gold)
                    HStack(spacing: 5) { ForEach(0..<5) { index in
                        VStack(spacing: 2) { Text("\(index + 1)회").font(.caption); Text(index < scores.count ? "\(scores[index])" : "·").font(.subheadline.monospaced().bold()) }
                            .frame(maxWidth: .infinity, minHeight: 44).background(GameTheme.boardPanel)
                            .overlay(Rectangle().strokeBorder(index == attemptIndex ? GameTheme.gold : GameTheme.boardLine))
                    } }.accessibilityElement(children: .combine).accessibilityIdentifier("traitDrillScores")
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { time in
                        let elapsed = max(0, time.date.timeIntervalSince(startedAt))
                        let remaining: Double = running ? max(0, 4.0 - elapsed) : (feedback == nil ? 4.0 : 0.0)
                        let seconds = remaining.formatted(.number.precision(.fractionLength(1)))
                        VStack(spacing: 4) {
                            TraitTrainingArena(trait: trait, target: target, player: TrainingTarget(x: x, y: y), endpoint: endpoint,
                                               motion: running ? min(1, elapsed / (trait == .cheetah ? 4 : TrainingFieldMotion.duration)) : (feedback == nil ? 0 : 1), steps: steps,
                                               moving: running, success: feedback == nil ? nil : scores.last.map { $0 >= 90 }, appearance: player?.appearance ?? PlayerAppearance(), number: player?.jerseyNumber ?? 1, hand: player?.throwingHandRaw ?? "right")
                                .frame(height: typeSize.isAccessibilitySize ? 210 : max(170, min(260, geometry.size.height - (trait == .strongArm ? 420 : 340))))
                                .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                                    guard trait != .cheetah, !running, feedback == nil, errorMessage == nil else { return }
                                    let reserve: CGFloat = trait == .strongArm ? 420 : 340
                                    let height = typeSize.isAccessibilitySize ? 210 : max(170, min(260, geometry.size.height - reserve))
                                    let pointX = (event.location.x / max(1, geometry.size.width - 24) * 320 - 32) / 256
                                    let pointY = (event.location.y / height * 220 - 48) / 140
                                    if trait == .safeHands {
                                        x = min(0.9, max(0.1, pointX)); y = min(0.9, max(0.2, pointY))
                                    } else {
                                        let dx = pointX - 0.5, dy = pointY - 0.63
                                        angle = (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                                        force = min(100, max(8, hypot(dx, dy) / 0.55 * 100))
                                    }
                                }, including: trait != .cheetah && !typeSize.isAccessibilitySize && !running && feedback == nil && errorMessage == nil ? .all : .none)
                                .accessibilityElement(children: .ignore).accessibilityLabel("훈련장 · " + trait.drillInstruction)
                                .accessibilityIdentifier("traitDrillArena")
                            if trait == .cheetah {
                                Text("\(steps)걸음 · 남은 \(seconds)초")
                                    .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitDrillSteps")
                            }
                        }
                    }
                    Text(typeSize.isAccessibilitySize && trait != .cheetah ? (trait == .strongArm ? "아래 방향·힘 버튼으로 조절한 뒤 송구하세요." : "아래 이동 버튼으로 낙하지점에 접근한 뒤 포구하세요.") : trait.drillInstruction)
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    controls
                    if let feedback {
                        if let score = scores.last { TrainingGradeBanner(score: score) }
                        Text(feedback).font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitDrillFeedback")
                        if finished {
                            Text("5회 평균 \(averageScore)점 · \(record == nil ? "체험 완료" : "훈련 완료")")
                                .font(.headline).accessibilityIdentifier("traitDrillResult")
                            if let training = savedTraining {
                                Text("진척 \(training.before, specifier: "%.1f") → \(training.after, specifier: "%.1f") · +\(training.gain, specifier: "%.1f")")
                                    .font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitTrainingGrowth")
                                TrainingProjectFeedbackPanel(training: training)
                                Text(training.after == 100 ? "특성 습득! 다음 날 준비 전에 활성화하세요." : "진척 저장 완료 · 다음 훈련에서 이어집니다.")
                                    .font(.subheadline).foregroundStyle(GameTheme.growth).accessibilityIdentifier("traitAcquired")
                                Text("피로 \(training.fatigue) → \(min(100, training.fatigue + 6)) · 오늘 행동 사용").font(.caption)
                            } else { Text("연습 점수만 표시 · 실제 특성·진척 변화 없음").font(.caption).foregroundStyle(GameTheme.boardMuted) }
                        } else {
                            Button("다음 시도 · \(scores.count + 1)/5") { self.feedback = nil; steps = 0; lastFoot = 0; feet = [] }
                                .buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("traitDrillNext")
                        }
                    } else if trait == .cheetah {
                        HStack {
                            Button("왼발") { step(1) }.accessibilityIdentifier("traitDrillLeft")
                            Button("오른발") { step(2) }.accessibilityIdentifier("traitDrillRight")
                        }.buttonStyle(GameButtonStyle(onBoard: true)).disabled(errorMessage != nil)
                    } else {
                        Button(running ? "플레이 중…" : trait == .strongArm ? "송구!" : "글러브 내밀기") { submit() }
                            .buttonStyle(GameButtonStyle(onBoard: true)).disabled(running || errorMessage != nil).accessibilityIdentifier("traitDrillSubmit")
                    }
                    if finished {
                        if record == nil {
                            Button("다시 연습") { scores = []; feedback = nil; steps = 0; running = false; lastFoot = 0; feet = [] }
                                .buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("practiceTraitRetry")
                        }
                        Button("훈련 선택으로 돌아가기") { dismiss() }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("traitDrillFinish")
                    }
                }.padding(12)
            }
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark).tint(GameTheme.gold)
            .navigationTitle(trait.drillTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("닫기") { dismiss() }.foregroundStyle(GameTheme.gold).accessibilityIdentifier("acquisitionCloseDrill")
            } }
            .onAppear { loadRecord() }
            .task(id: running) {
                guard running else { return }
                do { try await Task.sleep(for: .seconds(trait == .cheetah ? 4 : TrainingFieldMotion.duration)) } catch { return }
                guard !Task.isCancelled, running else { return }; resolve()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && running { running = false; steps = 0; lastFoot = 0; feet = []; pendingInput = nil; pendingRevision = nil }
            }
    }
}

#if DEBUG
#Preview("특성 습득 훈련 시안") { NavigationStack { TraitAcquisitionPreview() } }
#endif
