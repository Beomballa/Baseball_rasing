import SwiftUI
import SwiftData

struct CareerRootView: View {
    let schools: [School]
    @Query(sort: \CareerPlayer.createdAt) private var players: [CareerPlayer]
    @State private var selectedID: UUID?
    @State private var showCreation = false
    @State private var path: [UUID] = []

    private var selected: CareerPlayer? { players.first(where: { $0.id == selectedID }) ?? players.first }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let player = selected {
                    PlayerHomeView(player: player, players: players,
                                   select: { selectedID = $0 }, create: { showCreation = true },
                                   play: { path.append(player.id) })
                } else {
                    PlayerCreationView(schools: schools, availableRoles: PlayerRole.allCases) { selectedID = $0 }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let player = players.first(where: { $0.id == id }) {
                    MatchView(player: player)
                } else { ContentUnavailableView("선수를 찾을 수 없습니다", systemImage: "person.crop.square") }
            }
            .sheet(isPresented: $showCreation) {
                NavigationStack {
                    PlayerCreationView(schools: schools, availableRoles: PlayerRole.allCases.filter { role in
                        !players.contains(where: { $0.role == role })
                    }) { id in selectedID = id; showCreation = false }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showCreation = false } } }
                }
            }
        }
    }
}
