import SwiftUI
import SwiftData

@main struct BMApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-scouting-contract-preview") {
                NavigationStack { ScoutingContractPreview() }
            } else if ProcessInfo.processInfo.arguments.contains("-season-summary-verification") || ProcessInfo.processInfo.arguments.contains("-offseason-verification") {
                SeasonSummaryVerification()
            } else if ProcessInfo.processInfo.arguments.contains("-position-training-preview") {
                NavigationStack { PositionTrainingPreview() }
            } else if ProcessInfo.processInfo.arguments.contains("-trait-acquisition-preview") {
                NavigationStack { TraitAcquisitionPreview() }
            } else { AppBootstrapView() }
            #else
            AppBootstrapView()
            #endif
        }
    }
}

struct AppBootstrapView: View {
    @State private var container: ModelContainer?
    @State private var schools: [School] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let container {
                if launchPractice {
                    NavigationStack { TrainingPracticeView() }.modelContainer(container)
                } else {
                    CareerRootView(schools: schools).modelContainer(container)
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("세이브를 열지 못했습니다", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("기존 데이터는 삭제하지 않았습니다.\n\(errorMessage)")
                } actions: {
                    Button("다시 열기", action: load).buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("커리어 불러오는 중")
            }
        }
        .tint(GameTheme.green)
        .task { if container == nil && errorMessage == nil { load() } }
    }

    private var launchPractice: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-training-practice")
        #else
        false
        #endif
    }
    @MainActor private func load() {
        do {
            let catalog = try SchoolCatalog.load()
            let store = try CareerStore.makeContainer()
            schools = catalog; container = store; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

#if DEBUG
/// Isolated UI verification: real automatic match/save paths, never opens the user's disk store.
private struct SeasonSummaryVerification: View {
    @State private var container: ModelContainer?
    @State private var schools: [School] = []
    @State private var error: String?
    var body: some View {
        Group {
            if let container { CareerRootView(schools: schools).modelContainer(container) }
            else if let error { Text(error) }
            else { ProgressView("QA 시즌 구성 중") }
        }.task { if container == nil && error == nil { prepare() } }
    }
    @MainActor private func prepare() {
        do {
            let schools = try SchoolCatalog.load()
            let diskQA = ProcessInfo.processInfo.arguments.contains("-offseason-verification")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("offseason-verification.store")
            let store = try diskQA ? CareerStore.makeContainer(url: url) : CareerStore.makeContainer(inMemory: true)
            let c = store.mainContext
            if try c.fetchCount(FetchDescriptor<CareerPlayer>()) > 0 {
                self.schools = schools; container = store; return
            }
            for role in PlayerRole.allCases {
                var draft = PlayerDraft(); draft.schoolID = schools[0].id; draft.role = role
                draft.name = role == .batter ? "SeasonBat" : "SeasonPitch"
                let player = try CareerStore.create(draft, schools: schools, in: c)
                let state = try c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }!
                for fixture in try state.fixtures(for: player, year: 2026) {
                    while try GameDate(player.gameDate) < fixture.date {
                        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, automaticRest: true, in: c)
                    }
                    try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: c)
                    let record = try CareerMatchStore.start(player: player, state: state, in: c)
                    try CareerMatchStore.advance(player: player, state: state, record: record, revision: record.revision, input: .automatic, in: c)
                }
                try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: c)
            }
            self.schools = schools; container = store
        } catch { self.error = error.localizedDescription }
    }
}
#endif
