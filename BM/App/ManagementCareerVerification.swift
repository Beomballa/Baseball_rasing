#if DEBUG
import SwiftUI
import SwiftData

/// Uses the production root and commands with an isolated in-memory career.
struct ManagementCareerVerification: View {
    @State private var container: ModelContainer?
    @State private var protection: SaveProtection?
    @State private var schools: [School] = []
    @State private var error: String?
    var body: some View {
        Group {
            if let container { CareerRootView(schools: schools).modelContainer(protection?.container ?? container).environment(\.saveProtection, protection).id(protection?.generation) }
            else if let error { Text(error).accessibilityIdentifier("managementSeedError") }
            else { ProgressView("관리 화면 QA 준비") }
        }
        .tint(ProcessInfo.processInfo.arguments.contains("-management-production-tint-verification") ? GameTheme.green : nil)
        .task {
            guard container == nil && error == nil else { return }
            do {
                let catalog = try SchoolCatalog.load()
                let args=ProcessInfo.processInfo.arguments
                var diskSession:UUID?
                if let index=args.firstIndex(of:"-v56-disk-session") {
                    guard index+1<args.count,let id=UUID(uuidString:args[index+1]) else {throw SaveProtectionError.invalid};diskSession=id
                }
                let testsConnectedFlow = args.contains("-v185-career-flow")
                if testsConnectedFlow, diskSession == nil { throw SaveProtectionError.invalid }
                let saveQA=args.contains("-save-protection-verification") || diskSession != nil
                let base=FileManager.default.temporaryDirectory.appendingPathComponent(diskSession.map {"v56-resume-"+$0.uuidString} ?? ("save-qa-"+UUID().uuidString)).appendingPathComponent("Career.store")
                if saveQA { try FileManager.default.createDirectory(at:base.deletingLastPathComponent(),withIntermediateDirectories:true) }
                let memory = try saveQA ? CareerStore.makeContainer(url:SaveArchiveStore.activeURL(base:base)) : CareerStore.makeContainer(inMemory:true)
                if saveQA { protection=SaveProtection(container:memory,base:base) }
                let existingCount=try memory.mainContext.fetchCount(FetchDescriptor<CareerPlayer>())
                let reopening=diskSession != nil && existingCount>0
                let roles: [PlayerRole] = reopening || ProcessInfo.processInfo.arguments.contains("-management-empty-verification") ? []
                    : testsConnectedFlow ? [.pitcher]
                    : ProcessInfo.processInfo.arguments.contains("-management-single-role-verification") ? [.batter] : PlayerRole.allCases
                for role in roles {
                    var draft = PlayerDraft(); draft.schoolID = catalog[0].id; draft.role = role
                    draft.name = role == .batter ? "CareerBat" : "CareerPitch"
                    let player = try CareerStore.create(draft, schools: catalog, in: memory.mainContext)
                    if testsConnectedFlow {
                        // The off-day precedes the next observation and the pitcher's scheduled fixture.
                        player.gameDate = "2026-04-27"
                        try memory.mainContext.save()
                    }
                    if args.contains("-v180-career-journal") || args.contains("-v183-result-journal") {
                        guard diskSession != nil, roles == [.batter] else { throw SaveProtectionError.invalid }
                        try seedCareerJournal(player: player, includeSecondTraining: args.contains("-v183-result-journal"), in: memory.mainContext)
                    }
                    if args.contains("-v182-scout-journal") {
                        guard diskSession != nil, roles == [.batter] else { throw SaveProtectionError.invalid }
                        try seedScoutJournal(player: player, in: memory.mainContext)
                    }
                    if role == .batter, let fixture = ClubhouseFixture.allCases.first(where: { args.contains($0.argument) }) {
                        try seedClubhouse(fixture, player: player, catalog: catalog, in: memory.mainContext)
                    }
                    if args.contains("-v100-league-names") {
                        let c = memory.mainContext
                        let state = try c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }!
                        let fixtures = try state.fixtures(for: player, year: 2026)
                        for fixture in fixtures.prefix(6) {
                            player.gameDate = fixture.date.description; state.actionDate = nil; try c.save()
                            try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: c)
                            let row = try CareerMatchStore.start(player: player, state: state, in: c)
                            try CareerMatchStore.advance(player: player, state: state, record: row, revision: row.revision, input: .automatic, in: c)
                            try AutomaticLeagueStore.completeDay(player: player, state: state, date: fixture.date, in: c); try c.save()
                        }
                        let leaders = LeagueHonorRules.leaders(try CareerMatchStore.seasonPlayerRecords(playerID: player.id, year: 2026, competition: "highschool", in: c))
                        let teams = Set(leaders.filter { role == .pitcher || $0.playerID.hasSuffix("/starter") }.map(\.teamID))
                        let target = fixtures.dropFirst(6).first { $0.isAppearance(for: role) && teams.contains($0.opponent(of: player.schoolID)) }
                            ?? fixtures.dropFirst(6).first { $0.isAppearance(for: role) }!
                        for fixture in fixtures.dropFirst(6) where fixture.date < target.date {
                            player.gameDate = fixture.date.description; state.actionDate = nil; try c.save()
                            try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: c)
                            let row = try CareerMatchStore.start(player: player, state: state, in: c)
                            try CareerMatchStore.advance(player: player, state: state, record: row, revision: row.revision, input: .automatic, in: c)
                            try AutomaticLeagueStore.completeDay(player: player, state: state, date: fixture.date, in: c); try c.save()
                        }
                        player.gameDate = target.date.description; state.actionDate = nil; try c.save()
                        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: c)
                    }
                    if args.contains("-v99-pitch-study-progress"), role == .pitcher {
                        let context = memory.mainContext
                        var history = CareerTraining(playerID: player.id, date: "2026-03-31", role: "pitcher", pitchCode: "sweeper", before: 30, fatigue: player.fatigue, age: 16, calendarRevision: 0)
                        history.pitchStudy = try PitchStudyStore.preparation(player: player, code: "sweeper", replacing: nil, in: context)
                        history.scores = [100,100,100,100,100]
                        let row = try CareerTrainingRecord(history); row.completed = true; context.insert(row); try context.save()
                    }
                    if args.contains("-v72-acquisition-boundary") {
                        let context = memory.mainContext
                        player.name = role == .batter ? "QA습득경계B" : "QA습득경계P"
                        player.gameDate = "2026-04-02"
                        player.speed = 80; player.defense = 80; player.arm = 80
                        let traits = try context.fetch(FetchDescriptor<PlayerTraits>()).first { $0.playerID == player.id }!
                        traits.payload = try JSONEncoder().encode(TraitLoadout(owned: [.cheetah, .safeHands], active: [.cheetah, .safeHands], progress: [PlayerTrait.strongArm.rawValue: 99]))
                        if role == .pitcher {
                            let extra = CareerPitchMastery(code: "curve", name: "커브", mastery: 61.75, order: 4)
                            context.insert(extra); player.pitches.append(extra)
                            var history = CareerTraining(playerID: player.id, date: "2026-03-31", role: "pitcher", pitchCode: "cutter", before: 98, fatigue: player.fatigue, age: 16, calendarRevision: 0)
                            history.pitchStudy = try PitchStudyStore.preparation(player: player, code: "cutter", replacing: "four-seam", in: context)
                            history.scores = [100, 100, 100, 100, 100]
                            let row = try CareerTrainingRecord(history); row.completed = true; context.insert(row)
                        }
                        try context.save()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-v53-calendar-save-failure") {
                        player.gameDate="2026-04-02";player.fatigue=90;try memory.mainContext.save()
                    }
                    if args.contains("-v175-calendar-observation") || args.contains("-v175-calendar-evaluation") {
                        let context = memory.mainContext
                        let states = try context.fetch(FetchDescriptor<CareerCalendarState>())
                        guard let state = states.first(where: { $0.playerID == player.id }) else { throw CalendarError.staleState }
                        if args.contains("-v175-calendar-evaluation") {
                            player.gameDate = "2029-04-01"
                            try CareerPathStore.synchronize(player: player, calendar: state, in: context)
                            player.gameDate = "2030-06-30"
                            try CareerPathStore.synchronize(player: player, calendar: state, in: context)
                        } else {
                            player.gameDate = "2026-04-27"
                        }
                        try context.save()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-v53-season-records") {
                        let c=memory.mainContext,state=try c.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == player.id}!
                        let fixtures=try state.fixtures(for:player,year:2026)
                        for index in [0,5] {
                            player.gameDate=fixtures[index].date.description;state.actionDate=nil;try c.save()
                            try CalendarProgression.rest(player:player,state:state,revision:state.revision,in:c)
                            let row=try CareerMatchStore.start(player:player,state:state,in:c)
                            try CareerMatchStore.advance(player:player,state:state,record:row,revision:row.revision,input:.automatic,in:c)
                            if index == 5,ProcessInfo.processInfo.arguments.contains("-v53-season-legacy") {
                                var game=try row.snapshot();game.playerRecords=nil;game.pitchLog=nil;game.npcReadiness=nil
                                row.payload=try JSONEncoder().encode(game);try c.save()
                                _ = try row.snapshot()
                            }
                        }
                        player.gameDate=fixtures[6].date.description;state.actionDate=nil;try c.save()
                    }
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

    private enum ClubhouseFixture: String, CaseIterable {
        case game, away, offday, training, season
        var argument: String { "-v172-home-qa-" + rawValue }
    }

    @MainActor private func seedScoutJournal(player: CareerPlayer, in context: ModelContext) throws {
        let playerID = player.id
        let descriptor = FetchDescriptor<CareerCalendarState>(predicate: #Predicate { $0.playerID == playerID })
        guard let state = try context.fetch(descriptor).first,
              let abilities = try PlayerAbilityStore.profile(playerID: playerID, in: context),
              let initialReport = try ScoutingObservationStore.reports(player: player, calendar: state, in: context).first
        else { throw ScoutingObservationError.invalid }

        // Exercise an archived report from before interest tracking was written.
        var legacyReport = try initialReport.snapshot()
        legacyReport.version = 3
        legacyReport.interests = nil
        legacyReport.signingBonusForecasts = nil
        try legacyReport.validate()
        initialReport.payload = try JSONEncoder().encode(legacyReport)

        func setAbilities(_ value: Double) throws {
            player.contact = value
            player.power = value
            player.discipline = value
            player.defense = value
            try abilities.grow(.mental, to: value)
        }

        let fixtures = try state.fixtures(for: player, year: 2026).filter { $0.isAppearance(for: player.role) }
        guard fixtures.count >= 13 else { throw CalendarError.invalidGroup }
        func insertGame(_ fixture: SeasonFixture) throws {
            player.gameDate = fixture.date.description
            var match = ScoutingReferenceSimulation.fixture(role: player.role, position: player.positionRaw,
                values: PlayerArchetype.initial(for: player.role).values, seed: UInt64(200 + fixture.number),
                home: fixture.homeID == player.schoolID)
            try match.advance(.automatic)
            let row = try CareerMatchRecord(player: player, fixture: fixture, match: match)
            row.completed = true
            row.rulesVersion = "native-match-v2"
            context.insert(row)
        }

        try setAbilities(75)
        for fixture in fixtures.prefix(12) { try insertGame(fixture) }
        player.gameDate = fixtures[11].date.adding(days: 1).description
        guard player.gameDate == "2026-06-07" else { throw ScoutingObservationError.invalid }
        try context.save()
        try ScoutingObservationStore.ensureCurrent(player: player, calendar: state, in: context)
        guard let historical = try ScoutingObservationStore.reports(player: player, calendar: state, in: context).first?.snapshot(),
              historical.totals.games == 12, historical.interests?.entries.first?.level == .priority
        else { throw ScoutingObservationError.invalid }

        try insertGame(fixtures[12])
        try setAbilities(10)
        player.gameDate = historical.nextDate
        guard player.gameDate == "2026-06-24" else { throw ScoutingObservationError.invalid }
        try context.save()
        try ScoutingObservationStore.ensureCurrent(player: player, calendar: state, in: context)
        guard let later = try ScoutingObservationStore.reports(player: player, calendar: state, in: context).first?.snapshot(),
              later.totals.games == 13, later.interests?.entries.isEmpty == true
        else { throw ScoutingObservationError.invalid }

        player.gameDate = try GameDate(later.observedDate).adding(days: 1).description
        try context.save()
    }

    @MainActor private func seedCareerJournal(player: CareerPlayer, includeSecondTraining: Bool, in context: ModelContext) throws {
        let playerID = player.id
        let descriptor = FetchDescriptor<CareerCalendarState>(predicate: #Predicate { $0.playerID == playerID })
        guard let state = try context.fetch(descriptor).first else { throw CalendarError.staleState }

        try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
        let match = try CareerMatchStore.start(player: player, state: state, in: context)
        try CareerMatchStore.advance(player: player, state: state, record: match, revision: match.revision, input: .automatic, in: context)
        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)

        let training = try CareerTrainingStore.start(player: player, state: state, kind: .contact, in: context)
        for _ in 0..<5 {
            let round = try training.snapshot()
            let target = round.targets[round.scores.count]
            try CareerTrainingStore.attempt(player: player, state: state, record: training, revision: training.revision,
                input: TrainingInput(x: target.x, y: target.y, timing: MatchDelivery.contactPhase), in: context)
        }
        if includeSecondTraining {
            try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: context)
            let later = try CareerTrainingStore.start(player: player, state: state, kind: .contact, in: context)
            for offset in [0.0, -0.04, -0.08, -0.12, -0.2] {
                let snapshot = try later.snapshot()
                let target = snapshot.targets[snapshot.scores.count]
                try CareerTrainingStore.attempt(player: player, state: state, record: later, revision: later.revision,
                    input: TrainingInput(x: target.x, y: target.y, timing: MatchDelivery.contactPhase + offset), in: context)
            }
        }

        // Use the deterministic school sample from the domestic selection verification.
        let appearances = try state.fixtures(for: player, year: 2028).filter { $0.isAppearance(for: player.role) }.prefix(12)
        for (index, fixture) in appearances.enumerated() {
            player.gameDate = fixture.date.description
            var sample = ScoutingReferenceSimulation.fixture(role: player.role, position: player.positionRaw,
                values: PlayerArchetype.initial(for: player.role).values, seed: UInt64(700 + index),
                home: fixture.homeID == player.schoolID, tracked: true)
            try sample.advance(.automatic)
            let row = try CareerMatchRecord(player: player, fixture: fixture, match: sample)
            row.completed = true
            row.rulesVersion = "native-match-v2"
            context.insert(row)
        }

        state.actionDate = nil
        player.gameDate = "2029-04-01"
        try CareerPathStore.synchronize(player: player, calendar: state, in: context)
        player.gameDate = "2030-04-01"
        try CareerPathStore.synchronize(player: player, calendar: state, in: context)
        player.contact = 80; player.power = 80; player.discipline = 80; player.defense = 80
        guard let abilities = try PlayerAbilityStore.profile(playerID: player.id, in: context) else { throw CalendarError.staleState }
        try abilities.grow(.mental, to: 80)
        try context.save()

        try ScoutingObservationStore.ensureCurrent(player: player, calendar: state, in: context)
        guard try ContractEvaluationStore.captureIfDue(player: player, calendar: state, in: context) else { throw ContractEvaluationError.invalid }
        try context.save()
        guard let evaluation = try ContractEvaluationStore.records(player: player, calendar: state, in: context).first,
              let packet = try ContractOfferStore.records(player: player, calendar: state, in: context).first,
              let offer = try packet.snapshot(evaluation: evaluation, player: player, calendar: state).offers.first(where: { $0.route == .rookie })
        else { throw ContractRegistrationError.invalid }

        player.gameDate = "2030-04-03"
        try context.save()
        try ContractRegistrationStore.decide(player: player, calendar: state, offerID: offer.id, accept: true,
            date: player.gameDate, revision: state.revision, in: context)
        player.gameDate = "2030-11-01"
        try context.save()
        guard try ContractEvaluationStore.captureIfDue(player: player, calendar: state, in: context) else { throw ContractEvaluationError.invalid }
        try context.save()
        player.gameDate = "2030-11-02"
        try context.save()
    }

    @MainActor private func seedClubhouse(_ fixture: ClubhouseFixture, player: CareerPlayer,
                                         catalog: [School], in context: ModelContext) throws {
        let playerID = player.id
        let descriptor = FetchDescriptor<CareerCalendarState>(predicate: #Predicate { $0.playerID == playerID })
        let opponentID = "hs-ref-032"
        guard let state = try context.fetch(descriptor).first,
              catalog.contains(where: { $0.id == opponentID }) else { throw CalendarError.invalidGroup }
        // A fixed six-school group makes the approved home and away pairing repeatable in QA.
        let otherSchools = catalog.filter { $0.id != player.schoolID && $0.id != opponentID }.prefix(4)
        state.schoolIDs = [player.schoolID] + otherSchools.map(\.id) + [opponentID]
        let year = try GameDate(player.gameDate).year
        let fixtures = try state.fixtures(for: player, year: year)
        guard let opening = fixtures.first(where: { $0.homeID == player.schoolID && $0.awayID == opponentID }),
              let away = fixtures.first(where: { $0.awayID == player.schoolID && $0.homeID == opponentID }),
              let final = fixtures.last else { throw CalendarError.invalidGroup }
        let date = switch fixture {
        case .game: opening.date
        case .away: away.date
        case .offday, .training: opening.date.adding(days: 1)
        case .season: final.date.adding(days: 1)
        }
        player.gameDate = date.description
        try context.save()
        if fixture == .training {
            let record = try CareerTrainingStore.start(player: player, state: state, kind: .contact, in: context)
            for _ in 0..<2 {
                let training = try record.snapshot()
                let target = training.targets[training.scores.count]
                try CareerTrainingStore.attempt(player: player, state: state, record: record, revision: record.revision,
                    input: TrainingInput(x: target.x, y: target.y, timing: MatchDelivery.contactPhase), in: context)
            }
        }
    }
}
#endif
