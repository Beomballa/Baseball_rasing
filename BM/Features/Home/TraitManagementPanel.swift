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
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text("활성 \(value.active.count) / 3").font(.headline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("traitActiveCount")
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    ZStack {
                        Rectangle().fill(GameTheme.navy)
                        if index < value.active.count { TraitPixelIcon(trait: value.active[index]).padding(5) }
                        else { Text("□").font(.caption.monospaced()).foregroundStyle(GameTheme.boardMuted).accessibilityHidden(true) }
                    }.frame(width: 40, height: 40).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(index < value.active.count ? "활성 슬롯 \(index + 1), \(value.active[index].label)" : "빈 활성 슬롯 \(index + 1)")
                }
            }
        }
    }
    private func card(_ trait: PlayerTrait, value: TraitLoadout, locked: Bool) -> some View {
        let owned = value.owned.contains(trait), active = value.active.contains(trait)
        let qualifies = trait.qualifies(speed: player.speed, defense: player.defense, arm: player.arm)
        return VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                TraitPixelIcon(trait: trait).frame(width: 36, height: 36)
                Text(trait.label).font(.headline).foregroundStyle(GameTheme.gold)
                Text(active ? "■ 활성" : owned ? "보유 · 비활성" : "미보유")
                    .font(.caption.bold()).foregroundStyle(active ? GameTheme.growth : GameTheme.boardMuted)
            }
            Text(trait.effect).font(.subheadline).accessibilityIdentifier("traitEffect-" + trait.rawValue)
            Text("습득 조건 · " + trait.condition).font(.caption).foregroundStyle(GameTheme.boardMuted)
                .accessibilityIdentifier("traitCondition-" + trait.rawValue)
            if owned {
                Button(active ? "활성 해제" : "활성화") { toggle(trait) }
                    .buttonStyle(GameButtonStyle(secondary: active, onBoard: onBoard))
                    .disabled(locked || (!active && value.active.count >= 3))
                    .accessibilityIdentifier("traitToggle-" + trait.rawValue)
                    .accessibilityLabel(trait.label + (active ? " 활성 해제" : " 활성화"))
            } else {
                Text(qualifies ? "능력치 조건 충족 · 아직 보유하지 않은 특성" : "능력치 조건 미충족")
                    .font(.caption).foregroundStyle(qualifies ? GameTheme.growth : GameTheme.boardMuted)
                Text("훈련 진척 \(value.trainingProgress(trait), specifier: "%.1f") / 100.0").font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("traitProgress-" + trait.rawValue)
                TraitProgressBar(value: value.trainingProgress(trait))
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
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(onBoard ? GameTheme.board : GameTheme.paper)
            .overlay(Rectangle().strokeBorder(active ? GameTheme.gold : GameTheme.boardLine, lineWidth: active ? 2 : 1))
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
                    Text("보유 특성 · \(value.owned.count)").font(.headline).padding(.top, 8)
                    if value.owned.isEmpty { Text("보유한 특성이 없습니다.").font(.subheadline).accessibilityIdentifier("traitOwnedEmpty") }
                    ForEach(PlayerTrait.allCases.filter { value.owned.contains($0) }) { card($0, value: value, locked: reason != nil) }
                    let missing = PlayerTrait.allCases.filter { !value.owned.contains($0) }
                    if !missing.isEmpty {
                        Text("미보유 특성 · \(missing.count)").font(.headline).padding(.top, 8)
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
                        PixelPlayer(appearance: player.appearance).frame(width: 36, height: 48).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(player.name) #\(player.jerseyNumber)").font(.headline).accessibilityIdentifier("traitPlayerName")
                            Text("\(player.schoolName) · \(player.role.label)").font(.caption).foregroundStyle(GameTheme.boardMuted)
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
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 320, y: size.height / 220)
            func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Int) {
                context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)), with: .color(Color(hex: color)))
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ color: Int, _ width: Double = 2) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                context.stroke(p, with: .color(Color(hex: color)), lineWidth: width)
            }
            func point(_ p: TrainingTarget) -> CGPoint { CGPoint(x: p.x * 320, y: p.y * 220) }
            func athlete(_ x: Double, _ y: Double, _ kit: Int, _ stride: Bool = false, _ throwing: Bool = false) {
                box(x - 9, y + 13, 20, 4, 0x22583f)
                let skin = PlayerAppearance.skinColors[appearance.skin]
                box(x - 6, y - 18, 12, 4, PlayerAppearance.hairColors[appearance.hair]); box(x - 5, y - 14, 10, 9, skin)
                box(x - 3, y - 12, 2, 2, 0x132b40); box(x + 2, y - 12, 2, 2, 0x132b40)
                box(x - 6, y - 6, 12, 13, kit); box(x - 1, y - 5, 3, 11, 0xf3edd5)
                box(x - 10, y - 4, 4, 9, skin)
                box(x + 6, y - (throwing ? 13 : 4), 4, 10, skin)
                box(x - 6, y + 7, 5, stride ? 5 : 8, 0xe6e5d3); box(x + 1, y + 7, 5, stride ? 10 : 8, 0xe6e5d3)
                box(x - 8, y + (stride ? 11 : 15), 7, 3, 0x14283f); box(x + 1, y + (stride ? 17 : 15), 7, 3, 0x14283f)
            }
            box(0, 0, 320, 220, 0x326b4d)
            for row in 0..<9 { box(0, Double(row * 25), 320, 12, row.isMultiple(of: 2) ? 0x377654 : 0x326b4d) }
            // Fence, seating, nets and equipment give the drill a distinct place.
            box(0, 0, 320, 23, 0x132b40)
            for col in 0..<32 { box(Double(col * 11), 5, 6, 4, col.isMultiple(of: 3) ? 0x8fa59c : 0x385465); box(Double(col * 11 + 3), 13, 6, 4, 0x526e77) }
            box(0, 23, 320, 10, 0x184a42); box(0, 23, 320, 2, 0xe1c06a)
            for col in 0..<17 { box(Double(col * 20), 26, 2, 7, 0x73918a) }
            for row in 0..<6 { line(CGPoint(x: 8, y: 45 + row * 9), CGPoint(x: 44, y: 45 + row * 9), 0x71998a, 1) }
            for col in 0..<5 { line(CGPoint(x: 8 + col * 9, y: 45), CGPoint(x: 8 + col * 9, y: 90), 0x71998a, 1) }
            box(284, 45, 22, 6, 0x9b7347); box(286, 51, 3, 7, 0x604e38); box(301, 51, 3, 7, 0x604e38)
            for col in 0..<3 { box(286 + Double(col * 7), 42, 4, 3, 0xf0e6ca) }
            if trait == .cheetah {
                box(16, 100, 288, 93, 0x9e7751)
                for row in 0..<3 { line(CGPoint(x: 16, y: 111 + row * 31), CGPoint(x: 304, y: 111 + row * 31), 0xe4d8b0) }
                for y in stride(from: 100, to: 193, by: 10) {
                    for col in 0..<2 { box(280 + Double(col * 5), Double(y), 5, 5, (y / 10 + col).isMultiple(of: 2) ? 0xf1e8cd : 0x17344e) }
                }
                let runner = 36 + min(1, Double(steps) / 16) * 226
                for index in 0..<min(steps, 16) { box(29 + Double(index * 14), index.isMultiple(of: 2) ? 161 : 170, 5, 3, 0xd9bb87) }
                athlete(runner, 143, PlayerAppearance.kitColors[appearance.kit], steps.isMultiple(of: 2) && moving)
                athlete(302, 81, 0x685a51)
            } else {
                let bases = [4, 1, 2, 3, 4].map { point(TrainingRules.basePoint($0)) }
                var dirt = Path(); dirt.addLines(bases); dirt.closeSubpath()
                context.fill(dirt, with: .color(Color(hex: 0x9b724a)))
                context.stroke(dirt, with: .color(Color(hex: 0xf0e4c6)), lineWidth: 2)
                for base in 1...4 { let p = point(TrainingRules.basePoint(base)); box(p.x - 4, p.y - 4, 8, 8, 0xf0e4c6) }
                let t = point(target)
                context.stroke(Path(CGRect(x: t.x - 12, y: t.y - 9, width: 24, height: 18)), with: .color(GameTheme.gold), lineWidth: 2)
                if trait == .strongArm {
                    let origin = point(TrainingTarget(x: 0.5, y: 0.63)), end = point(endpoint)
                    athlete(t.x + 8, t.y - 10, 0x96574a)
                    athlete(origin.x, origin.y + 5, PlayerAppearance.kitColors[appearance.kit], false, moving && motion < 0.2)
                    for fraction in stride(from: 0.15, through: 1.0, by: 0.15) {
                        box(origin.x + (end.x - origin.x) * fraction, origin.y + (end.y - origin.y) * fraction, 2, 2, 0xceba72)
                    }
                    if moving || success != nil {
                        let phase = max(0, min(1, (motion - 0.18) / 0.82))
                        let hand = CGPoint(x: origin.x + 10, y: origin.y - 7)
                        let x = hand.x + (end.x - hand.x) * phase
                        let y = hand.y + (end.y - hand.y) * phase - sin(phase * .pi) * 22
                        box(x - 3, end.y + 4, 8, 2, 0x245039)
                        for i in 1...3 {
                            let trail = max(0, phase - Double(i) * 0.055)
                            box(hand.x + (end.x - hand.x) * trail, hand.y + (end.y - hand.y) * trail - sin(trail * .pi) * 22, 2, 2, 0xc0c89e)
                        }
                        PixelBaseball.draw(in:context,at:CGPoint(x:x,y:y),diameter:9)
                    }
                } else {
                    let p = point(player)
                    athlete(p.x, p.y, PlayerAppearance.kitColors[appearance.kit])
                    box(p.x + 8, p.y - (moving ? 13 : 3), 8, 7, 0xc99759)
                    let height = moving || success != nil ? (1 - motion) * 65 : 65
                    box(t.x - 5, t.y + 4, 11, 3, 0x245039)
                    PixelBaseball.draw(in:context,at:CGPoint(x:t.x,y:t.y-height-sin(motion * .pi)*30+2),diameter:9)
                    if moving && motion > 0.82 && hypot(target.x - player.x, target.y - player.y) < 0.1 {
                        for d in [-1.0, 1] { box(p.x + 11 + d * 10, p.y - 10 + d * 5, 4, 3, 0xecc66b) }
                    }
                    line(CGPoint(x: t.x, y: t.y - height + 9), CGPoint(x: t.x, y: t.y - 6), 0xc1c99c, 1)
                }
                if let success { context.stroke(Path(CGRect(x: t.x - 17, y: t.y - 14, width: 34, height: 28)), with: .color(success ? GameTheme.growth : GameTheme.gold), lineWidth: 3) }
            }
            for x in [60.0, 265] { box(x, 193, 7, 7, 0xd3ab5b); box(x + 2, 188, 3, 5, 0xe8c56f) }
        }.drawingGroup().overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
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
                    TimelineView(.animation(minimumInterval: reduced ? 0.1 : 1.0 / 30, paused: !running)) { time in
                        let elapsed = max(0, time.date.timeIntervalSince(startedAt))
                        let remaining: Double = running ? max(0, 4.0 - elapsed) : (feedback == nil ? 4.0 : 0.0)
                        let seconds = remaining.formatted(.number.precision(.fractionLength(1)))
                        VStack(spacing: 4) {
                            TraitTrainingArena(trait: trait, target: target, player: TrainingTarget(x: x, y: y), endpoint: endpoint,
                                               motion: running ? (reduced ? 1 : min(1, elapsed / 0.9)) : (feedback == nil ? 0 : 1), steps: steps,
                                               moving: running, success: feedback == nil ? nil : scores.last.map { $0 >= 90 }, appearance: player?.appearance ?? PlayerAppearance())
                                .frame(height: typeSize.isAccessibilitySize ? 210 : max(170, min(260, geometry.size.height - (trait == .strongArm ? 420 : 340))))
                                .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                                    guard trait != .cheetah, !running, feedback == nil, errorMessage == nil else { return }
                                    let reserve: CGFloat = trait == .strongArm ? 420 : 340
                                    let height = typeSize.isAccessibilitySize ? 210 : max(170, min(260, geometry.size.height - reserve))
                                    let pointX = event.location.x / max(1, geometry.size.width - 24)
                                    let pointY = event.location.y / height
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
                do { try await Task.sleep(for: .seconds(trait == .cheetah ? 4 : reduced ? 0.1 : 0.9)) } catch { return }
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
