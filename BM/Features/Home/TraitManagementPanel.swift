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
                Text("습득 훈련 준비 중").font(.caption).foregroundStyle(GameTheme.boardMuted)
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
                        ForEach(missing) { card($0, value: value, locked: true) }
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
    private var kind: TrainingKind { switch selected { case .strongArm: .arm; case .cheetah: .speed; case .safeHands: .defense } }
    private var drill: String { switch selected { case .strongArm: "베이스 · 방향 · 강도 조절"; case .cheetah: "4초 교대 달리기"; case .safeHands: "낙하지점 이동 · 포구" } }
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
        FieldTrainingBoard(kind: kind, target: TrainingTarget(x: 0.68, y: 0.4), base: 1,
                           angle: 0, force: 65, steps: 8, appearance: PlayerAppearance(),
                           x: .constant(0.48), y: .constant(0.55), locked: true)
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
                            Text("특성 전용 훈련").bold()
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text("5회").monospaced()
                        }.font(.subheadline)
                        board.frame(height: typeSize.isAccessibilitySize ? 170 : max(120, min(180, geometry.size.height - 490)))
                        Text(drill).font(.subheadline.bold()).foregroundStyle(GameTheme.gold)
                    }
                    Text(reason).font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("acquisitionState")
                    Button(sample == .owned ? "이미 습득한 특성" : sample == .short ? "능력치 조건 미충족" : sample == .locked ? "오늘 훈련 불가" : "훈련 구성 미리보기") { showDrill = true }
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
            .sheet(isPresented: $showDrill) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("훈련 구성 미리보기 · 실제 훈련/보상 없음").font(.caption).foregroundStyle(GameTheme.gold)
                            GamePanel(title: selected.label + " · 5회 과제", onBoard: true) {
                                board.frame(height: 180)
                                Text(drill).font(.headline)
                                Text("5회 평균 점수에 따라 특성 진척만 증가합니다. 능력치 추가 보상은 없습니다.").font(.subheadline)
                            }
                            HStack { ForEach(1...5, id: \.self) { index in
                                Text("\(index)회\n·").font(.subheadline.monospaced()).frame(maxWidth: .infinity, minHeight: 48)
                                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine))
                            } }.accessibilityLabel("훈련 5회 점수 기록 영역")
                            Text("완료: 진척 저장 · 피로 +6 · 오늘 행동 사용\n습득 후: 보유 목록에 추가 · 다음 날 준비 전 활성화")
                                .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                            Button("훈련 선택으로 돌아가기") { showDrill = false }
                                .buttonStyle(GameButtonStyle(onBoard: true)).accessibilityIdentifier("acquisitionCloseDrill")
                        }.padding(12)
                    }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
                        .navigationTitle("과제 구성 시안").navigationBarTitleDisplayMode(.inline)
                }.preferredColorScheme(.dark)
            }
    }
}

#Preview("특성 습득 훈련 시안") { NavigationStack { TraitAcquisitionPreview() } }
#endif
