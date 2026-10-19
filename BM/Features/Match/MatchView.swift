import SwiftUI
import SpriteKit

struct MatchView: View {
    let player: CareerPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 400))
    @State private var cue = "투구 모션과 경기장 연결을 확인해 보세요."
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(player.name) · \(player.role.label)").font(.headline)
                    Text("\(player.schoolName) · \(player.roleDetail)").font(.caption)
                }
                Spacer()
                Text("연습 장면").font(.caption.bold()).padding(8).background(GameTheme.gold)
            }
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .aspectRatio(0.8, contentMode: .fit)
                .overlay(Rectangle().strokeBorder(GameTheme.navy, lineWidth: 3))
                .accessibilityLabel("위에서 보는 도트 야구장")
                .accessibilityIdentifier("spriteKitField")
            Text(cue).font(.subheadline).multilineTextAlignment(.center)
                .accessibilityIdentifier("matchCue")
            Button("투구 연습 보기") {
                if scene.demonstrate(reduceMotion: reduceMotion) { cue = "손에서 릴리스 → 포수 수신 · 기록/피로 변화 없음" }
            }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("demoPitch")
            Text("카운트·성적·성장 판정은 다음 이식 단계입니다.")
                .font(.caption).foregroundStyle(GameTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(16).background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("경기장").navigationBarTitleDisplayMode(.inline)
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.appearance.kit) }
        .onDisappear { scene.removeAllActions() }
    }
}
