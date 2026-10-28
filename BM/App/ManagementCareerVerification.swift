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
                let roles: [PlayerRole] = ProcessInfo.processInfo.arguments.contains("-management-empty-verification") ? []
                    : ProcessInfo.processInfo.arguments.contains("-management-single-role-verification") ? [.batter] : PlayerRole.allCases
                for role in roles {
                    var draft = PlayerDraft(); draft.schoolID = catalog[0].id; draft.role = role
                    draft.name = role == .batter ? "CareerBat" : "CareerPitch"
                    let player = try CareerStore.create(draft, schools: catalog, in: memory.mainContext)
                    if ProcessInfo.processInfo.arguments.contains("-v41-position-verification"),role == .batter {
                        let c=memory.mainContext
                        player.positionRaw=FieldPosition.shortstop.rawValue;player.speed=95;player.defense=50;player.arm=80
                        let profile=try PlayerAbilityStore.profile(playerID:player.id,in:c)!;profile.mental=55
                        let positions=try PlayerPositionStore.profile(playerID:player.id,in:c)!
                        positions.payload=try JSONEncoder().encode(PositionLoadout(primary:.shortstop));try c.save()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-v39-forecast-verification") {
                        let c=memory.mainContext,state=try c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == player.id}!
                        if ProcessInfo.processInfo.arguments.contains("-v39-legacy") {var life=try player.lifecycle;life.development=nil;player.lifecycleData=try JSONEncoder().encode(life);try c.save()}
                        try OverseasReportStore.capture(player:player,calendar:state,date:player.gameDate,revision:state.revision,in:c)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-v38-development-verification") {
                        let c=memory.mainContext,state=try c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == player.id}!
                        var life=try player.lifecycle;life.development=PlayerDevelopment(adopted:player.gameDate,timing:.early)
                        player.lifecycleData=try JSONEncoder().encode(life);try c.save()
                        for i in 0..<(ProcessInfo.processInfo.arguments.contains("-v38-legacy-verification") ? 0:8) {
                            player.gameDate=try GameDate("2026-04-01").adding(days:i*2).description;state.actionDate=nil;player.fatigue=24;try c.save()
                            let row=try CareerTrainingStore.start(player:player,state:state,kind:role == .batter ? .defense:.control,in:c)
                            for _ in 0..<5 {let t=try row.snapshot(),target=t.targets[t.scores.count];try CareerTrainingStore.attempt(player:player,state:state,record:row,revision:row.revision,input:TrainingInput(x:target.x,y:target.y),in:c)}
                        }
                        player.gameDate="2026-04-17";state.actionDate=nil;player.fatigue=24
                        if role == .batter,let profile=try PlayerPositionStore.profile(playerID:player.id,in:c) {
                            var loadout=try profile.snapshot();loadout.skills[FieldPosition.shortstop.rawValue]=PositionSkill(mastery:40,xp:20);profile.payload=try JSONEncoder().encode(loadout)
                        }
                        try c.save()
                        if ProcessInfo.processInfo.arguments.contains("-v38-result-verification") {
                            let row=try CareerTrainingStore.start(player:player,state:state,kind:role == .batter ? .defense:.control,in:c)
                            for _ in 0..<5 {let t=try row.snapshot(),target=t.targets[t.scores.count];try CareerTrainingStore.attempt(player:player,state:state,record:row,revision:row.revision,input:TrainingInput(x:target.x,y:target.y),in:c)}
                        }
                        if ProcessInfo.processInfo.arguments.contains("-v38-legacy-verification") {var life=try player.lifecycle;life.development=nil;player.lifecycleData=try JSONEncoder().encode(life)}
                        try c.save()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-management-v31-lifecycle") {
                        let c=memory.mainContext,state=try c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == player.id}!
                        player.gameDate="2029-04-01";try CareerPathStore.synchronize(player:player,calendar:state,in:c)
                        player.gameDate="2041-03-31";try CareerPathStore.synchronize(player:player,calendar:state,in:c)
                        try c.save()
                        try CalendarProgression.advanceDay(player:player,state:state,revision:state.revision,automaticRest:true,confirmAnniversary:true,in:c)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-management-stats-verification") {
                        let state = try memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }!
                        let fixtures = try state.fixtures(for: player, year: 2026), target = fixtures[5]
                        for date in Set(fixtures.filter { $0.date < target.date }.map(\.date)).sorted() {
                            player.gameDate = date.description
                            try AutomaticLeagueStore.completeDay(player: player, state: state, date: date, in: memory.mainContext)
                        }
                        player.gameDate = target.date.description; try memory.mainContext.save()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-management-v20-completed") {
                        let state = try memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }!
                        let record = try CareerTrainingStore.start(player: player, state: state, pitchCode: role == .pitcher ? "four-seam" : nil, in: memory.mainContext)
                        for _ in 0..<5 {
                            let round = try record.snapshot(), target = round.targets[round.scores.count]
                            let input = role == .batter ? TrainingInput(x: target.x, y: target.y, timing: MatchDelivery.contactPhase) : TrainingInput(release: 0.68)
                            try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision, input: input, in: memory.mainContext)
                        }
                        let match = try CareerMatchStore.start(player: player, state: state, in: memory.mainContext)
                        try CareerMatchStore.advance(player: player, state: state, record: match, revision: match.revision, input: .automatic, in: memory.mainContext)
                    }
                }
                schools = catalog; container = memory
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
