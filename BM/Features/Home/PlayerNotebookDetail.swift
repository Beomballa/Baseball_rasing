import SwiftUI
import UIKit

/// Validates affiliation without writing a player; callers cache the result for their refresh cycle.
@MainActor struct ManagementPlayerAffiliation {
    let name: String
    let appearance: PlayerAppearance
    let age: Int
    let actionAvailable: Bool

    static func read(player: CareerPlayer, calendar: CareerCalendarState?) -> Self {
        guard let calendar else {
            let schoolAge = player.startAge <= 18
            var look = player.appearance.wearing(teamID: schoolAge ? player.schoolID : nil)
            if !schoolAge { look.schoolKitID = nil }
            return Self(name: schoolAge ? player.displaySchoolName : "무소속", appearance: look,
                        age: player.startAge, actionAvailable: true)
        }
        do {
            let age = try calendar.age(of: player)
            let member = try calendar.registration(for: player)
            let team = member?.teamID ?? (age <= 18 ? player.schoolID : nil)
            var look = player.appearance.wearing(teamID: team)
            if team == nil { look.schoolKitID = nil }
            return Self(name: member?.name ?? (age <= 18 ? player.displaySchoolName : "무소속"),
                        appearance: look, age: age, actionAvailable: !calendar.hasAction(on: player.gameDate))
        } catch {
            var look = player.appearance.wearing(teamID: nil); look.schoolKitID = nil
            return Self(name: "소속 조회 오류", appearance: look, age: player.startAge,
                        actionAvailable: !calendar.hasAction(on: player.gameDate))
        }
    }
}

/// A single existing gameplay pose, cached for reading screens; no animation clock or saved state.
struct DetailGamePortrait: View {
    let role: PlayerRole
    let appearance: PlayerAppearance
    let number: Int
    let hand: String
    var label = "경기 도트 선수"
    @State private var portrait: UIImage?
    @MainActor private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 8
        return cache
    }()
    var renderingKey: String {
        PlayerMotionArt.cacheKey(role: role, appearance: appearance, number: number, hand: hand)
    }
    var body: some View {
        Group {
            if let portrait { Image(uiImage: portrait).resizable().interpolation(.none).scaledToFit() }
            else { PixelPlayer(appearance: appearance) }
        }.accessibilityLabel(label + " · 등번호 \(number)")
            .task(id: renderingKey) {
                if let cached = Self.images.object(forKey: renderingKey as NSString) { portrait = cached; return }
                if let image = PlayerMotionArt.image(role: role, frame: 0, appearance: appearance, number: number, hand: hand) {
                    Self.images.setObject(image, forKey: renderingKey as NSString); portrait = image
                }
            }
    }
}

struct PlayerNotebookIdentity: View {
    let player: CareerPlayer
    let affiliation: String
    let age: Int
    var appearanceOverride: PlayerAppearance? = nil
    var actionAvailable: Bool? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            ManagementPortrait(appearance: appearanceOverride ?? player.appearance, role: player.role, number: player.jerseyNumber)
                .frame(width: typeSize.isAccessibilitySize ? 90 : 100, height: 108)
                .background(GameTheme.navy.opacity(0.7))
                .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYER FILE  /  #\(player.jerseyNumber)").font(ManagementPixelFont.readable(.label)).foregroundStyle(GameTheme.gold)
                Text(player.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text(affiliation).font(.subheadline)
                Text("\(age)세 · \(player.role.label) · \(player.roleDetail)").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true)
        let metrics = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        metrics {
            metric("피로", "\(player.fatigue) / 100")
            if let actionAvailable { metric("오늘 행동", actionAvailable ? "1 / 1" : "0 / 1") }
            metric("현재 일자", ManagementDisplay.date(player.gameDate))
        }
        }.padding(16).foregroundStyle(GameTheme.boardInk)
            .background(GameTheme.boardPanel)
            .overlay(ManagementStepFrame().stroke(GameTheme.gold, lineWidth: 2).allowsHitTesting(false))
            .accessibilityIdentifier("notebookIdentity")
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(GameTheme.boardMuted)
            Text(value).font(.subheadline.monospacedDigit().bold()).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlayerNotebookHighlights: View {
    let values: [HomeAbilityValue]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let best = values.max { $0.current < $1.current }
        let next = values.min { $0.current < $1.current }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: 10) {
            if let best { highlight("현재 강점", value: best, color: GameTheme.growth, id: "notebookStrength") }
            if let next { highlight("다음 보완", value: next, color: GameTheme.gold, id: "notebookWeakness") }
        }
    }
    private func highlight(_ title: String, value: HomeAbilityValue, color: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline) {
                Text(value.label).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(value.current, format: .number.precision(.fractionLength(1))).font(.title2.monospacedDigit().bold())
            }
            Text(value.growthFeedback).font(.caption.monospacedDigit())
                .foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
        }.padding(12).foregroundStyle(GameTheme.boardInk).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(color.opacity(0.8), lineWidth: 1))
            .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }
}

struct NotebookAbilityStrip: View {
    let value: HomeAbilityValue
    var onPaper = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(value.label).managementFont(.label).bold()
                Spacer()
                Text(value.current, format: .number.precision(.fractionLength(1))).managementFont(.metric).monospacedDigit().foregroundStyle(onPaper ? GameTheme.navy : GameTheme.gold)
            }
            Text(value.growthFeedback).managementFont(.helper).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle().fill(Double(index) < min(10, max(0, value.current / 10)) ? (onPaper ? Color(hex: 0x237459) : GameTheme.growth) : GameTheme.boardLine.opacity(0.24))
                }
            }.frame(height: 9).accessibilityHidden(true)
        }.padding(.vertical, 5).foregroundStyle(onPaper ? GameTheme.navy : GameTheme.boardInk)
            .accessibilityElement(children: .combine).accessibilityIdentifier(value.id)
    }
}
