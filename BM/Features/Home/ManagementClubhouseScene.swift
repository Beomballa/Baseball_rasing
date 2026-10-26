import SwiftUI

struct ManagementClubhouseScene: View {
    let appearance: PlayerAppearance
    let selection: (ManagementTab) -> Void
    let rest: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: ManagementTheme.Space.compact) {
                ManagementClubhouseBackdrop().frame(maxHeight: 180)
                sign("경기장", id: "game") { selection(.game) }
                sign("훈련장", id: "training") { selection(.training) }
                sign("선수 라커", id: "player") { selection(.player) }
                sign("스카우트실", id: "career") { selection(.career) }
                sign("휴식", id: "rest", action: rest)
            }
        } else {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    ManagementClubhouseBackdrop()
                    sign("경기장", id: "game") { selection(.game) }.frame(width: size.width * 0.34).position(x: size.width * 0.5, y: size.height * 0.16)
                    sign("훈련장", id: "training") { selection(.training) }.frame(width: size.width * 0.36).position(x: size.width * 0.2, y: size.height * 0.4)
                    sign("스카우트실", id: "career") { selection(.career) }.frame(width: size.width * 0.36).position(x: size.width * 0.8, y: size.height * 0.4)
                    sign("휴식", id: "rest", action: rest).frame(width: size.width * 0.34).position(x: size.width * 0.2, y: size.height * 0.72)
                    sign("선수 라커", id: "player") { selection(.player) }.frame(width: size.width * 0.36).position(x: size.width * 0.8, y: size.height * 0.72)
                    PixelPlayer(appearance: appearance).frame(width: 40, height: 50)
                        .position(x: size.width * 0.55, y: size.height * 0.87).accessibilityHidden(true)
                }
            }.aspectRatio(1122.0 / 1402, contentMode: .fit)
        }
    }
    private func sign(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).managementFont(.label).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: ManagementTheme.Control.hit)
                .foregroundStyle(GameTheme.boardInk).background(Color(hex: 0x513623), in: ManagementStepFrame())
                .overlay { ManagementStepFrame().strokeBorder(GameTheme.gold, lineWidth: 2) }
                .contentShape(ManagementStepFrame())
        }.buttonStyle(.plain).accessibilityIdentifier("clubhouse-" + id)
    }
}
