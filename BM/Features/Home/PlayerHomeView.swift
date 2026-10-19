import SwiftUI

struct PlayerHomeView: View {
    let player: CareerPlayer
    let players: [CareerPlayer]
    let select: @MainActor @Sendable (UUID) -> Void
    let create: () -> Void
    let play: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("PLAYER CAREER").font(.caption.monospaced().bold())
                    Spacer(); Text("LOCAL SAVE").font(.caption.monospaced())
                }.foregroundStyle(GameTheme.gold).padding(12).background(GameTheme.navy)
                GamePanel(title: "선수 홈") {
                    HStack(spacing: 16) {
                        PixelPlayer(appearance: player.appearance).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(player.name)  #\(player.jerseyNumber)").font(.title2.bold())
                                .accessibilityIdentifier("homePlayerName")
                            Text(player.schoolName).fontWeight(.semibold).accessibilityIdentifier("homeSchool")
                            Text("\(player.role.label) · \(player.roleDetail) · 16세 / 고1")
                                .font(.subheadline).foregroundStyle(GameTheme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Text(player.gameDate).monospacedDigit()
                        Spacer(); Text("피로 \(player.fatigue) / 100")
                    }.font(.subheadline)
                    Text("커리어 시작일 · 오늘 행동 미사용").font(.caption).foregroundStyle(GameTheme.muted)
                }
                GamePanel(title: player.role == .batter ? "주요 능력치" : "보유 구종 · 숙련도") {
                    if player.role == .batter {
                        StatRow(name: "컨택", value: player.contact)
                        StatRow(name: "파워", value: player.power)
                        StatRow(name: "선구안", value: player.discipline)
                    } else {
                        ForEach(player.pitches.sorted { $0.order < $1.order }) { pitch in
                            StatRow(name: pitch.name, value: pitch.mastery)
                        }
                    }
                }
                GamePanel(title: "주루 · 수비") {
                    StatRow(name: "스피드", value: player.speed)
                    StatRow(name: "수비", value: player.defense)
                    StatRow(name: "송구", value: player.arm)
                }
                Button("경기장 입장", action: play).buttonStyle(GameButtonStyle())
                    .accessibilityIdentifier("openMatch")
                Text("경기장 연결 단계 · 연습 장면은 기록에 반영되지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.muted)
                if players.count > 1 {
                    Picker("플레이 선수", selection: Binding(get: { player.id }, set: select)) {
                        ForEach(players) { Text("\($0.role.label) · \($0.name)").tag($0.id) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("homeRolePicker")
                }
                if players.count < PlayerRole.allCases.count {
                    Button("다른 역할 선수 만들기", action: create).buttonStyle(GameButtonStyle(secondary: true))
                        .accessibilityIdentifier("createOtherRole")
                }
            }.padding(16)
        }
        .background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("선수 홈").navigationBarTitleDisplayMode(.inline)
    }
}
