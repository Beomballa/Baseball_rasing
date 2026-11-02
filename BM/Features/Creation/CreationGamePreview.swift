import SwiftUI

/// Uses the same raster path as the live match; no career is created for preview.
struct CreationGamePreview: View {
    let draft: PlayerDraft
    @Environment(\.dynamicTypeSize) private var type
    @State private var frame = 0
    @State private var picture: UIImage?
    private var appearance: PlayerAppearance { draft.appearance.wearing(teamID: draft.schoolID) }
    private var key: String { "\(appearance)-\(draft.role)-\(draft.throwingHand)-\(draft.jerseyNumber)-\(frame)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("경기장에서는 이렇게 보여요").managementFont(.sectionTitle)
            let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 16))
            layout {
                VStack(spacing: 8) {
                    CreationAvatarImage(appearance: draft.appearance, role: draft.role,
                        number: Int(draft.jerseyNumber) ?? 10, cap: true, mode: .portrait)
                        .frame(maxWidth: .infinity).frame(height: 170)
                    Text("선택한 얼굴").managementFont(.label)
                }
                VStack(spacing: 8) {
                    if let picture {
                        Image(uiImage: picture).resizable().interpolation(.none).scaledToFit()
                            .scaleEffect(x: draft.role == .pitcher && draft.throwingHand == .left ? -1 : 1, y: 1)
                            .frame(maxWidth: .infinity).frame(height: 170)
                            .accessibilityLabel("실제 경기 \(draft.role.label) 자세 \(frame+1), 등번호 \(draft.jerseyNumber)")
                    }
                    Text(draft.role == .pitcher ? "포수를 향한 뒷모습" : "타석의 옆모습").managementFont(.label)
                }
            }.padding(12).background(GameTheme.navy)
            HStack {
                Text("자세 \(frame+1) / 6").managementFont(.label)
                Spacer()
                Button("다음 자세") { frame=(frame+1)%6 }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("creationNextGamePose")
            }
            Text("선택한 학교의 유니폼 · 모자 · 등번호가 경기에도 이어집니다.").managementFont(.helper)
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("creationGamePreview")
            .onChange(of:draft.role) { _, _ in frame=0 }
            .task(id: key) {
                picture=PlayerMotionArt.image(role:draft.role,frame:frame,appearance:appearance,
                    number:Int(draft.jerseyNumber) ?? 10,hand:draft.throwingHand.rawValue)
            }
    }
}
