import SwiftUI
import SwiftData

struct TraitManagementPanel: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState?
    var onBoard = false
    var compact = false
    @State private var showDetails = false
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
    var body: some View {
        let _ = calendar?.revision
        GamePanel(title: "보유 · 활성 특성", onBoard: onBoard) {
            if let profile, let value = try? profile.snapshot() {
                HStack {
                    Text("활성 \(value.active.count) / 3").font(.subheadline.bold()).accessibilityIdentifier("traitActiveCount")
                    Spacer()
                    ForEach(0..<3, id: \.self) { index in
                        ZStack {
                            Rectangle().fill(GameTheme.navy)
                            if index < value.active.count { TraitPixelIcon(trait: value.active[index]).padding(4) }
                        }.frame(width: 36, height: 36).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2))
                            .accessibilityLabel(index < value.active.count ? "활성 슬롯 \(index + 1), \(value.active[index].label)" : "빈 활성 슬롯 \(index + 1)")
                    }
                }
                if profile.source == "legacy-v1" {
                    Text("기존 저장 호환: 3종 보유로 등록 · 활성은 직접 선택").font(.caption).foregroundStyle(onBoard ? GameTheme.boardMuted : GameTheme.muted)
                }
                if compact {
                    Text("보유 \(value.owned.count)종 · \(value.active.isEmpty ? "활성 특성 없음" : value.active.map(\.label).joined(separator: " · "))")
                        .font(.caption).foregroundStyle(onBoard ? GameTheme.boardMuted : GameTheme.muted)
                    HomeDetailButton(title: "효과·조건·활성 관리", expanded: $showDetails, identifier: "traitDetails")
                }
                if !compact || showDetails {
                    ForEach(PlayerTrait.allCases) { trait in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                TraitPixelIcon(trait: trait).frame(width: 32, height: 32)
                                Text(trait.label).bold()
                                Spacer()
                                Text(value.active.contains(trait) ? "활성" : value.owned.contains(trait) ? "보유" : "미보유")
                                    .font(.caption.bold()).foregroundStyle(value.active.contains(trait) ? (onBoard ? GameTheme.growth : GameTheme.green) : (onBoard ? GameTheme.boardMuted : GameTheme.muted))
                            }
                            Text(trait.effect).font(.caption)
                            if value.owned.contains(trait) {
                                Button(value.active.contains(trait) ? "활성 해제" : "활성화") { toggle(trait) }
                                    .buttonStyle(GameButtonStyle(secondary: value.active.contains(trait), onBoard: onBoard))
                                    .disabled(lockReason != nil).accessibilityIdentifier("traitToggle-" + trait.rawValue)
                                    .accessibilityLabel(trait.label + (value.active.contains(trait) ? " 활성 해제" : " 활성화"))
                            } else {
                                Text("습득 조건: \(trait.condition) · 특성 훈련은 후속 추가").font(.caption).foregroundStyle(onBoard ? GameTheme.boardMuted : GameTheme.muted)
                            }
                        }.padding(10).overlay(Rectangle().strokeBorder(onBoard ? GameTheme.boardLine : GameTheme.navy.opacity(0.2)))
                            .accessibilityElement(children: .contain).accessibilityIdentifier("traitCard-" + trait.rawValue)
                    }
                }
                if let reason = lockReason {
                    Text(reason).font(.caption).foregroundStyle(onBoard ? GameTheme.boardMuted : GameTheme.muted).accessibilityIdentifier("traitLocked")
                } else if !compact || showDetails { Text("훈련·휴식 전 변경 가능 · 날짜와 피로를 소비하지 않습니다.").font(.caption).foregroundStyle(onBoard ? GameTheme.boardMuted : GameTheme.muted) }
            } else {
                Text(TraitError.invalidRecord.localizedDescription).font(.caption).accessibilityIdentifier("traitLoadError")
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).accessibilityIdentifier("traitSaveError")
                Button("상태 다시 확인") { self.errorMessage = nil }.buttonStyle(GameButtonStyle(secondary: true, onBoard: onBoard))
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
