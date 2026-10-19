import SwiftUI

struct PlayerHomeView: View {
    let player: CareerPlayer
    let players: [CareerPlayer]
    let calendar: CareerCalendarState?
    let schools: [School]
    let select: @MainActor @Sendable (UUID) -> Void
    let create: () -> Void
    let play: () -> Void

    private var age: Int { (try? calendar?.age(of: player)) ?? player.startAge }

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
                            Text("\(player.role.label) · \(player.roleDetail) · \(age)세 / \(SeasonSchedule.academicStatus(age: age))")
                                .font(.subheadline).foregroundStyle(GameTheme.muted).accessibilityIdentifier("homeAge")
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Text(player.gameDate).monospacedDigit()
                        Spacer(); Text("피로 \(player.fatigue) / 100").accessibilityIdentifier("homeFatigue")
                    }.font(.subheadline)
                    if calendar?.legacySave == true {
                        Text("기존 저장 유지 · 저장 날짜를 나이 진행 기준일로 사용")
                            .font(.caption).foregroundStyle(GameTheme.muted)
                    }
                }
                if let calendar {
                    CareerCalendarPanel(player: player, state: calendar, schools: schools).id(player.id)
                } else {
                    Text("달력 정보를 불러오지 못했습니다. 앱을 다시 열어 주세요.").font(.caption)
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
                Button("연습장 입장", action: play).buttonStyle(GameButtonStyle())
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
