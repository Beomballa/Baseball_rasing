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
            }.padding(12)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).preferredColorScheme(.dark)
            .navigationTitle("특성 상세 관리").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
