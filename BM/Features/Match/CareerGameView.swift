import SwiftUI
import SwiftData
import SpriteKit

struct CareerGameView: View {
    let player: CareerPlayer
    let calendar: CareerCalendarState
    let schools: [School]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var record: CareerMatchRecord?
    @State private var error: String?
    @State private var pitchCode = ""
    @State private var confirmAutomatic = false
    @State private var scene = BallparkScene(size: CGSize(width: 320, height: 400))

    private func updateBoard() {
        guard let match = try? record?.snapshot() else { return }
        scene.updateScoreboard("BM | \(match.teamScore):\(match.opponentScore) | B\(match.balls) S\(match.strikes) O\(match.outs)")
    }
    private func load() {
        do {
            record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            updateBoard()
            if pitchCode.isEmpty { pitchCode = player.pitches.sorted { $0.order < $1.order }.first?.code ?? "" }
        } catch { self.error = error.localizedDescription }
    }
    private func advance(_ input: MatchInput) {
        guard let record else { return }
        do {
            try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision,
                                         input: input, pitchCode: pitchCode, in: context)
            updateBoard()
            _ = scene.demonstrate(reduceMotion: reduced)
        } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let record, let match = try? record.snapshot() {
                    GamePanel(title: "\(record.gameDate) · \(match.inningLabel)") {
                        Text("\(player.schoolName)  \(match.teamScore) : \(match.opponentScore)  \(schools.first { $0.id == record.opponentID }?.name ?? record.opponentID)")
                            .font(.headline.monospaced()).accessibilityIdentifier("careerGameScore")
                        Text("B \(match.balls)   S \(match.strikes)   O \(match.outs) · 주자 \(match.bases.enumerated().filter { $0.element }.map { String($0.offset + 1) }.joined(separator: ","))")
                            .font(.subheadline.monospaced()).accessibilityIdentifier("careerGameCount")
                    }
                    SpriteView(scene: scene).aspectRatio(0.8, contentMode: .fit).frame(maxHeight: 310)
                        .overlay(Rectangle().strokeBorder(GameTheme.navy, lineWidth: 3))
                        .accessibilityLabel("도트 야구장 · 경기 상황은 위 점수판에서 확인")
                    Text(match.message).font(.headline).accessibilityIdentifier("careerGameMessage")
                    if match.completed {
                        GamePanel(title: "경기 결과 저장 완료") {
                            Text(match.teamScore == match.opponentScore ? "무승부" : (match.teamScore > match.opponentScore ? "승리" : "패배"))
                                .font(.title2.bold()).accessibilityIdentifier("careerGameFinished")
                            Text(record.appearance ? (player.role == .batter
                                ? "\(match.line.atBats)타수 \(match.line.hits)안타 · HR \(match.line.homeRuns) · BB \(match.line.walks) · K \(match.line.strikeouts)"
                                : "\(match.line.pitchingOuts / 3).\(match.line.pitchingOuts % 3)이닝 · \(match.line.pitches)구 · K \(match.line.pitchingStrikeouts) · 실점 \(match.line.runsAllowed)") : "비등판 · 개인 기록/피로 변화 없음")
                            Text("피로 \(record.fatigueBefore) → \(record.fatigueAfter)")
                            Text("홈에서 다음 날로 진행할 수 있습니다.").font(.caption)
                        }
                        Button("선수 홈으로") { dismiss() }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("gameReturnHome")
                    } else {
                        if record.appearance {
                            if player.role == .pitcher {
                                Picker("구종", selection: $pitchCode) {
                                    ForEach(player.pitches.sorted { $0.order < $1.order }) { Text($0.name).tag($0.code) }
                                }.accessibilityIdentifier("gamePitchPicker")
                                Button("투구") { advance(.pitch) }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("gamePitch")
                            } else {
                                HStack {
                                    ForEach([MatchInput.watch, .swing, .bunt], id: \.rawValue) { input in
                                        Button(input.label) { advance(input) }.buttonStyle(GameButtonStyle(secondary: input != .swing))
                                            .accessibilityIdentifier("gameInput-\(input.rawValue)")
                                    }
                                }
                            }
                        }
                        Button(record.appearance ? "남은 경기 자동 마무리" : "비등판 팀 경기 진행") { confirmAutomatic = true }
                            .buttonStyle(GameButtonStyle(secondary: true)).accessibilityIdentifier("gameAutomatic")
                        Text("공마다 저장 · 동료 플레이 자동 · 9회 동점은 무승부\n기본 판정 단계 · 타격 포인트/릴리스 조작과 상세 수비는 후속 이식")
                            .font(.caption).foregroundStyle(GameTheme.muted)
                    }
                } else {
                    Text(error ?? "경기 불러오는 중")
                    Button("다시 확인") { load() }.buttonStyle(GameButtonStyle())
                }
            }.padding(16)
        }
        .background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("공식 일정 경기").navigationBarTitleDisplayMode(.inline)
        .onAppear { scene.configure(hand: player.throwingHandRaw, kit: player.kit); load() }
        .onDisappear { scene.removeAllActions() }
        .confirmationDialog("남은 경기를 자동으로 진행할까요?", isPresented: $confirmAutomatic, titleVisibility: .visible) {
            Button("진행하고 결과 저장") { advance(.automatic) }
        } message: { Text("현재 카운트·주자에서 이어서 진행합니다. 실제 출전 성적과 피로를 반영하며 취소할 수 없습니다.") }
        .alert("경기를 저장하지 못했습니다", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }
}
