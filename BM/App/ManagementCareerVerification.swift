#if DEBUG
import SwiftUI
import SwiftData

/// Uses the production root and commands with an isolated in-memory career.
struct ManagementCareerVerification: View {
    @State private var container: ModelContainer?
    @State private var schools: [School] = []
    @State private var error: String?
    var body: some View {
        Group {
            if let container { CareerRootView(schools: schools).modelContainer(container) }
            else if let error { Text(error).accessibilityIdentifier("managementSeedError") }
            else { ProgressView("관리 화면 QA 준비") }
        }.task {
            guard container == nil && error == nil else { return }
            do {
                let catalog = try SchoolCatalog.load()
                let memory = try CareerStore.makeContainer(inMemory: true)
                for role in PlayerRole.allCases {
                    var draft = PlayerDraft(); draft.schoolID = catalog[0].id; draft.role = role
                    draft.name = role == .batter ? "CareerBat" : "CareerPitch"
                    let player = try CareerStore.create(draft, schools: catalog, in: memory.mainContext)
                    if ProcessInfo.processInfo.arguments.contains("-management-stats-verification") {
                        let state = try memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }!
                        let fixtures = try state.fixtures(for: player, year: 2026), target = fixtures[5]
                        for date in Set(fixtures.filter { $0.date < target.date }.map(\.date)).sorted() {
                            player.gameDate = date.description
                            try AutomaticLeagueStore.completeDay(player: player, state: state, date: date, in: memory.mainContext)
                        }
                        player.gameDate = target.date.description; try memory.mainContext.save()
                    }
                }
                schools = catalog; container = memory
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
