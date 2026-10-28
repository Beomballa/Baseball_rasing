import SwiftUI
import UIKit

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
    private var key: String {
        let look = appearance
        return "\(role.rawValue):\(hand):\(number):\(look.skin):\(look.hair):\(look.kit):\(look.hairStyle):\(look.expression)"
    }
    var body: some View {
        Group {
            if let portrait { Image(uiImage: portrait).resizable().interpolation(.none).scaledToFit() }
            else { PixelPlayer(appearance: appearance) }
        }.accessibilityLabel(label + " · 등번호 \(number)")
            .task(id: key) {
                if let cached = Self.images.object(forKey: key as NSString) { portrait = cached; return }
                if let image = PlayerMotionArt.image(role: role, frame: 0, appearance: appearance, number: number, hand: hand) {
                    Self.images.setObject(image, forKey: key as NSString); portrait = image
                }
            }
    }
}

struct PlayerNotebookIdentity: View {
    let player: CareerPlayer
    let affiliation: String
    let age: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYER FILE  /  #\(player.jerseyNumber)").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                Text(player.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text(affiliation).font(.subheadline)
                Text("\(age)세 · \(player.role.label) · \(player.roleDetail)").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                Text(ManagementDisplay.date(player.gameDate)).font(.caption.monospaced())
            }.frame(maxWidth: .infinity, alignment: .leading)
            DetailGamePortrait(role: player.role, appearance: player.appearance, number: player.jerseyNumber, hand: player.throwingHandRaw, label: player.name + "의 경기 도트").frame(width: typeSize.isAccessibilitySize ? 96 : 116, height: 138)
        }.padding(16).foregroundStyle(GameTheme.boardInk)
            .background {
                GeometryReader { size in
                    Image("StadiumRoomV2").resizable().interpolation(.none).scaledToFill()
                        .frame(width: size.size.width, height: size.size.height).clipped()
                        .overlay(GameTheme.navy.opacity(0.85))
                }
            }
            .overlay(ManagementStepFrame().stroke(GameTheme.gold, lineWidth: 2))
            .accessibilityIdentifier("notebookIdentity")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(value.label).font(.subheadline.bold())
                Spacer()
                Text(value.current, format: .number.precision(.fractionLength(1))).font(.headline.monospacedDigit()).foregroundStyle(GameTheme.gold)
            }
            Text(value.growthFeedback).font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle().fill(Double(index) < min(10, max(0, value.current / 10)) ? GameTheme.growth : GameTheme.boardLine.opacity(0.24))
                }
            }.frame(height: 9).accessibilityHidden(true)
        }.padding(.vertical, 5).foregroundStyle(GameTheme.boardInk)
            .accessibilityElement(children: .combine).accessibilityIdentifier(value.id)
    }
}
