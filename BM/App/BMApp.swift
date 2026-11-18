import SwiftUI
import SwiftData

@main struct BMApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-management-career-verification") {
                ManagementCareerVerification()
            } else if ProcessInfo.processInfo.arguments.contains("-management-components-preview") {
                ManagementFoundationPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-live-career-autoplay") {
                LiveCareerPerformanceRun()
            } else if ProcessInfo.processInfo.arguments.contains("-field-performance-autoplay") {
                FieldPerformanceAutoplay()
            } else if ProcessInfo.processInfo.arguments.contains("-match-presentation-verification") {
                NavigationStack {MatchReplayVerification()}
            } else if ProcessInfo.processInfo.arguments.contains("-home-run-verification") {
                NavigationStack {HomeRunVerification()}
            } else if ProcessInfo.processInfo.arguments.contains("-field-replay-verification") {
                NavigationStack { FieldReplayVerification() }
            } else if ProcessInfo.processInfo.arguments.contains("-career-path-verification") {
                CareerPathVerification()
            } else if ProcessInfo.processInfo.arguments.contains("-scouting-contract-preview") {
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
    @State private var protection: SaveProtection?
    @State private var recoveryBase: URL?
    @State private var showRecovery=false
    @State private var schools: [School] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let container {
                if launchPractice {
                    NavigationStack { TrainingPracticeView() }.modelContainer(container)
                } else {
                    CareerRootView(schools: schools).modelContainer(protection?.container ?? container)
                        .environment(\.saveProtection, protection).id(protection?.generation)
                }
            } else if let errorMessage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ManagementPanel("저장을 열 수 없습니다", surface: .paper) {
                            Text("이 기기의 기록을 보존했습니다. 다시 열거나 백업 파일을 검증할 수 있습니다.")
                                .managementFont(.body)
                            DisclosureGroup("저장 오류 상세") {
                                Text(errorMessage).managementFont(.helper).fixedSize(horizontal: false, vertical: true)
                            }.tint(GameTheme.navy)
                        }.accessibilityElement(children: .contain).accessibilityIdentifier("saveOpenFailure")
                        Button("저장 다시 열기", action: load).buttonStyle(ManagementButtonStyle())
                            .accessibilityIdentifier("retryOpenSave")
                        Button("백업 선택·검증") { showRecovery = true }
                            .buttonStyle(ManagementButtonStyle(variant: .secondary))
                            .disabled(recoveryBase == nil).accessibilityIdentifier("openFailedSaveRecovery")
                    }.frame(maxWidth: 480).padding(16).frame(maxWidth: .infinity, alignment: .center)
                }.background(GameTheme.board.ignoresSafeArea()).foregroundStyle(GameTheme.boardInk)
            } else {
                ProgressView("커리어 불러오는 중")
            }
        }
        .sheet(isPresented:$showRecovery) {
            if let recoveryBase {
                FailedSaveRecoveryView(base: recoveryBase) { session in
                    protection=session; container=session.container
                    schools=(try? SchoolCatalog.load()) ?? []; errorMessage=nil
                }
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
    @MainActor static func storeBaseURL(arguments: [String], bundleID: String?) throws -> URL {
        #if DEBUG
        if arguments.contains("-live-career-performance") {
            return try LiveCareerQA.storeURL(arguments: arguments, bundleID: bundleID)
        }
        #endif
        return SaveArchiveStore.defaultURL()
    }
    @MainActor private func load() {
        recoveryBase=nil
        do {
            let base=try Self.storeBaseURL(arguments: ProcessInfo.processInfo.arguments, bundleID: Bundle.main.bundleIdentifier)
            recoveryBase=base
            let catalog = try SchoolCatalog.load()
            let session=try SaveProtection.open(base: base)
            protection=session
            schools = catalog; container = session.container; errorMessage = nil
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
            let arguments = ProcessInfo.processInfo.arguments
            let diskQA = arguments.contains("-offseason-verification")
            let inputQA = arguments.contains("-input-fit-verification")
            let interestQA = arguments.contains("-club-interest-verification")
            let storeName: String
            if diskQA, let index = arguments.firstIndex(of: "-qa-session") {
                guard arguments.indices.contains(index + 1), let session = UUID(uuidString: arguments[index + 1]) else {
                    throw NSError(domain: "BM.QA", code: 2, userInfo: [NSLocalizedDescriptionKey: "시즌 QA 세션 ID가 올바르지 않습니다."])
                }
                storeName = "offseason-verification-\(session.uuidString).store"
            } else {
                storeName = "offseason-verification.store"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(storeName)
            let store = try diskQA ? CareerStore.makeContainer(url: url) : CareerStore.makeContainer(inMemory: true)
            let c = store.mainContext
            if try c.fetchCount(FetchDescriptor<CareerPlayer>()) > 0 {
                self.schools = schools; container = store; return
            }
            for role in PlayerRole.allCases {
                var draft = PlayerDraft(); draft.schoolID = schools[0].id; draft.role = role
                draft.name = role == .batter ? "SeasonBat" : "SeasonPitch"
                let player = try CareerStore.create(draft, schools: schools, in: c)
                if interestQA {
                    player.contact=75;player.power=75;player.discipline=75;player.defense=75
                    if let abilities=try PlayerAbilityStore.profile(playerID:player.id,in:c) {
                        try abilities.grow(.mental,to:75)
                        if role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try abilities.grow(kind,to:75)}}
                    }
                    for pitch in player.pitches {pitch.mastery=75}
                    try c.save()
                }
                let state = try c.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id }!
                for fixture in try state.fixtures(for: player, year: 2026) {
                    while try GameDate(player.gameDate) < fixture.date {
                        try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, automaticRest: true, in: c)
                    }
                    try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: c)
                    let record = try CareerMatchStore.start(player: player, state: state, in: c)
                    if inputQA && fixture.isAppearance(for:role) {
                        var attempts=0
                        while !record.completed {
                            let match=try record.snapshot()
                            if role == .pitcher && !match.ownPitcherActive || fixture.number%2 == 0 && attempts >= 8 {break}
                            let action:MatchInput=role == .batter ? .swing:.pitch,code=match.mastery.keys.sorted().first
                            try CareerMatchStore.advance(player:player,state:state,record:record,revision:record.revision,input:action,pitchCode:code,control:match.automaticControl(action,pitchCode:code),in:c)
                            attempts += 1
                        }
                    }
                    if !record.completed {try CareerMatchStore.advance(player: player, state: state, record: record, revision: record.revision, input: .automatic, in: c)}
                }
                try CalendarProgression.advanceDay(player: player, state: state, revision: state.revision, in: c)
            }
            self.schools = schools; container = store
        } catch { self.error = error.localizedDescription }
    }
}
#endif


#if DEBUG
// This verification path never opens the user's disk container.
struct CareerPathVerification: View {
    @State private var container: ModelContainer?
    @State private var schools: [School] = []
    @State private var failure: String?
    var body: some View {
        Group {
            if let container { CareerRootView(schools:schools).modelContainer(container) }
            else if let failure { Text(failure) }
            else { ProgressView("진로 검증 준비") }
        }.task {
            guard container == nil, failure == nil else { return }
            do {
                let args = ProcessInfo.processInfo.arguments
                let schools = try SchoolCatalog.load()
                let c: ModelContainer
                if let index = args.firstIndex(of: "-v168-finance-qa-session") {
                    guard args.indices.contains(index + 1), let session = UUID(uuidString: args[index + 1]) else {
                        throw NSError(domain: "BM.QA", code: 168, userInfo: [NSLocalizedDescriptionKey: "자금 QA 세션 ID가 올바르지 않습니다."])
                    }
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("v168-finance-qa-\(session.uuidString).store")
                    c = try CareerStore.makeContainer(url: url)
                    if try c.mainContext.fetchCount(FetchDescriptor<CareerPlayer>()) > 0 {
                        self.schools = schools
                        self.container = c
                        return
                    }
                } else {
                    c = try CareerStore.makeContainer(inMemory: true)
                }
                let age = args.contains("-career-age20") ? 20 : args.contains("-career-age19") ? 19 : 16
                let verifyDivisions = args.contains("-v147-divisions-verification")
                for role in verifyDivisions ? [PlayerRole.batter] : PlayerRole.allCases {
                    var draft = PlayerDraft();draft.name = role == .batter ? "CareerBat":"CareerPitch";draft.role = role;draft.schoolID = schools[0].id
                    let p = try CareerStore.create(draft,schools:schools,in:c.mainContext)
                    let calendar = try c.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == p.id }!
                    if age >= 19 {
                        p.gameDate = "2029-04-01";try CareerPathStore.synchronize(player:p,calendar:calendar,in:c.mainContext)
                    }
                    if age >= 20 {
                        p.gameDate = "2030-04-01";try CareerPathStore.synchronize(player:p,calendar:calendar,in:c.mainContext)
                    }
                    if args.contains("-selection-qualified"),age == 20 {
                        let context=c.mainContext
                        for (index,fixture) in try calendar.fixtures(for:p,year:2028).filter({$0.isAppearance(for:role)}).prefix(role == .batter ? 12:6).enumerated() {
                            p.gameDate=fixture.date.description
                            var match=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? p.positionRaw:"P",values:PlayerArchetype.initial(for:role).values,
                                seed:UInt64(700+index),home:fixture.homeID == p.schoolID,tracked:true)
                            try match.advance(.automatic)
                            let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";context.insert(row)
                        }
                        p.gameDate="2030-04-01";p.contact=80;p.power=80;p.discipline=80;p.defense=80
                        let abilities=try PlayerAbilityStore.profile(playerID:p.id,in:context)!
                        try abilities.grow(.mental,to:80)
                        if role == .pitcher {
                            for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try abilities.grow(kind,to:80)}
                            for pitch in p.pitches {pitch.mastery=80}
                        }
                    }
                    _ = try ContractEvaluationStore.captureIfDue(player:p,calendar:calendar,in:c.mainContext)
                    if args.contains("-offer-expired"),age == 20 {p.gameDate="2030-04-08"}
                    try c.mainContext.save()
                    if args.contains("-club-season-verification"),age == 20,args.contains("-selection-qualified") {
                        let evaluation=try ContractEvaluationStore.records(player:p,calendar:calendar,in:c.mainContext).first!
                        let packet=try ContractOfferStore.records(player:p,calendar:calendar,in:c.mainContext).first!.snapshot(evaluation:evaluation,player:p,calendar:calendar)
                        let offer=packet.offers.first {$0.route == .rookie}!
                        try ContractRegistrationStore.decide(player:p,calendar:calendar,offerID:offer.id,accept:true,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                        if args.contains("-club-selection-verification") {
                            let next=try calendar.fixtures(for:p,year:2030).first {$0.date.description >= p.gameDate && $0.isAppearance(for:p.role)}!
                            p.gameDate=next.date.description;calendar.actionDate=nil
                            if args.contains("-club-selection-bench") {
                                p.contact=20;p.power=20;p.discipline=20;p.speed=20;p.defense=20;p.arm=20
                                let profile=try PlayerAbilityStore.profile(playerID:p.id,in:c.mainContext)!
                                profile.mental=20
                                if role == .pitcher {profile.velocity=20;profile.control=20;profile.stuff=20;profile.stamina=20;for pitch in p.pitches {pitch.mastery=20}}
                            }
                            try c.mainContext.save()
                            if args.contains("-v35-coach-verification") {
                                p.fatigue=55
                                _=try ClubSelectionStore.capture(player:p,calendar:calendar,in:c.mainContext);try c.mainContext.save()
                                if args.contains("-v35-coach-pending") {
                                    let training=try CareerTrainingStore.start(player:p,state:calendar,kind:role == .batter ? .contact:.control,in:c.mainContext)
                                    try CareerTrainingStore.attempt(player:p,state:calendar,record:training,revision:training.revision,input:TrainingInput(x:0.5,y:0.5,timing:role == .batter ? 0.5:nil),in:c.mainContext)
                                }
                            }
                            if args.contains("-v34-npc-evidence") {
                                // QA-only observed games, generated by the real completion paths in this in-memory store.
                                let fixtures=try calendar.fixtures(for:p,year:2030)
                                for fixture in fixtures.prefix(15) {
                                    p.gameDate=fixture.date.description;calendar.actionDate=p.gameDate;try c.mainContext.save()
                                    let game=try CareerMatchStore.start(player:p,state:calendar,in:c.mainContext)
                                    try CareerMatchStore.advance(player:p,state:calendar,record:game,revision:game.revision,input:.automatic,in:c.mainContext)
                                    try AutomaticLeagueStore.completeDay(player:p,state:calendar,date:fixture.date,in:c.mainContext);try c.mainContext.save()
                                }
                                p.gameDate=fixtures[14].date.adding(days:1).description;calendar.actionDate=nil
                                // Present a new evaluation, while historical match selections remain frozen.
                                var owner=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:c.mainContext)
                                owner.clubSelections=nil
                                let registration=try ContractRegistrationStore.row(player:p,in:c.mainContext)!
                                registration.payload=try JSONEncoder().encode(owner);try c.mainContext.save()
                            }
                            if args.contains("-club-selection-completed") {
                                try CalendarProgression.rest(player:p,state:calendar,revision:calendar.revision,in:c.mainContext)
                                let game=try CareerMatchStore.start(player:p,state:calendar,in:c.mainContext)
                                try CareerMatchStore.advance(player:p,state:calendar,record:game,revision:game.revision,input:.automatic,in:c.mainContext)
                                p.gameDate=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(p.gameDate)).next.description
                                calendar.actionDate=nil;try c.mainContext.save()
                                try ScoutingObservationStore.ensureCurrent(player:p,calendar:calendar,in:c.mainContext)
                            }
                        }
                        if args.contains("-v36-opportunity-verification") {
                            // Dedicated in-memory QA: actual team-game completion paths, no installed save is opened.
                            p.contact=20;p.power=20;p.discipline=20;p.defense=20;p.arm=20;p.speed=20
                            let abilities=try PlayerAbilityStore.profile(playerID:p.id,in:c.mainContext)!
                            abilities.mental=20
                            if role == .pitcher {abilities.velocity=20;abilities.control=20;abilities.stuff=20;abilities.stamina=20;for pitch in p.pitches {pitch.mastery=20}}
                            try c.mainContext.save()
                            try ClubSeasonStore.start(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                            let fixtures=try calendar.fixtures(for:p,year:2030)
                            for fixture in fixtures {
                                p.gameDate=fixture.date.description;calendar.actionDate=p.gameDate;try c.mainContext.save()
                                let game=try CareerMatchStore.start(player:p,state:calendar,in:c.mainContext)
                                try CareerMatchStore.advance(player:p,state:calendar,record:game,revision:game.revision,input:.automatic,in:c.mainContext)
                            }
                            p.gameDate="2030-09-23";calendar.actionDate=nil;try c.mainContext.save()
                            let goal=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:c.mainContext).seasonGoals!.first!
                            try ClubSeasonStore.settle(goal.id,player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                            p.gameDate="2030-11-01";try c.mainContext.save()
                            _=try ContractEvaluationStore.captureIfDue(player:p,calendar:calendar,in:c.mainContext)
                        }
                        if args.contains("-club-observation-verification") {
                            try ScoutingObservationStore.ensureCurrent(player:p,calendar:calendar,in:c.mainContext)
                            try ClubSeasonStore.start(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                            for _ in 0..<2 {
                                let next=try calendar.fixtures(for:p,year:GameDate(p.gameDate).year).first {$0.date.description >= p.gameDate && $0.isAppearance(for:p.role)}!
                                p.gameDate=next.date.description;calendar.actionDate=nil;try c.mainContext.save()
                                try CalendarProgression.rest(player:p,state:calendar,revision:calendar.revision,in:c.mainContext)
                                let game=try CareerMatchStore.start(player:p,state:calendar,in:c.mainContext)
                                try CareerMatchStore.advance(player:p,state:calendar,record:game,revision:game.revision,input:.automatic,in:c.mainContext)
                                p.gameDate=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(p.gameDate)).next.description;try c.mainContext.save()
                                try ScoutingObservationStore.ensureCurrent(player:p,calendar:calendar,in:c.mainContext)
                            }
                        }
                        if args.contains("-club-review-verification") {
                            // Synthetic end-of-season QA: unplayed team games use the existing automatic league policy.
                            p.gameDate="2030-09-23";try c.mainContext.save()
                            try ScoutingObservationStore.ensureCurrent(player:p,calendar:calendar,in:c.mainContext)
                            try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                        }
                    }
                    if args.contains("-college-pro-verification"),age == 20,args.contains("-selection-qualified") {
                        try seedCollegePro(player:p,calendar:calendar,in:c.mainContext)
                    }
                    if args.contains("-v40-bench-verification"),args.contains("-college-pro-verification") {
                        let context=c.mainContext
                        try OverseasContractStore.register(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
                        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
                        try OverseasContractStore.evaluate(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
                        guard let offer=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:context).overseasCareer?.evaluations.last?.offers.first else {throw OverseasProgressError.requirements}
                        try OverseasContractStore.decide(player:p,calendar:calendar,offerID:offer.id,accept:true,date:p.gameDate,revision:calendar.revision,in:context)
                        p.gameDate=offer.effective;p.contact=20;p.power=20;p.defense=20;p.speed=20;p.arm=20;p.discipline=20;p.fatigue=55
                        let profile=try PlayerAbilityStore.profile(playerID:p.id,in:context)!
                        profile.mental=20;if role == .pitcher {profile.velocity=20;profile.control=20;profile.stuff=20;profile.stamina=20;for pitch in p.pitches {pitch.mastery=20}}
                        try context.save();try DevelopmentStore.adopt(player:p,calendar:calendar,in:context)
                        _=try ClubSelectionStore.capture(player:p,calendar:calendar,in:context);try context.save()
                    }
                    if args.contains("-career-objectives-verification"),args.contains("-college-pro-verification") {
                        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                        if (args.contains("-goal-special-verification") || args.contains("-observation-review-verification") || args.contains("-club-assignment-verification")),
                           let report=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:c.mainContext).overseasReports?.last,
                           let club=CareerTargetClub.catalog(report).first(where:{$0.roleID == (role == .batter ? "field":"starter") && (!args.contains("-club-assignment-verification") || $0.criterion != nil)}) {
                            try OverseasContractStore.selectTarget(player:p,calendar:calendar,reportID:report.id,clubID:club.id,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                            if args.contains("-club-assignment-report-verification") {
                                try OverseasContractStore.startProject(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                                p.gameDate=try GameDate(p.gameDate).adding(days:28).description;calendar.actionDate=nil;try c.mainContext.save()
                                try ScoutingObservationStore.ensureCurrent(player:p,calendar:calendar,in:c.mainContext)
                                try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                                guard try ContractRegistrationStore.journal(player:p,calendar:calendar,in:c.mainContext).developmentReviews?.isEmpty == false else {throw ContractRegistrationError.invalid}
                            }
                            if args.contains("-observation-review-verification") {
                                p.speed=min(100,p.speed+1)
                                p.gameDate=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate(p.gameDate)).next.description
                                calendar.actionDate=nil;try c.mainContext.save()
                                try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                            }
                        }
                    }
                    if args.contains("-overseas-renewal-verification"),args.contains("-college-pro-verification") {
                        try seedOverseasRenewal(player:p,calendar:calendar,in:c.mainContext)
                    }
                    if args.contains("-overseas-release-verification"),args.contains("-overseas-renewal-verification") {
                        try OverseasContractStore.evaluateRenewal(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                        let owner=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:c.mainContext)
                        if let offer=owner.overseasCareer?.renewalReviews?.last?.offer {
                            try OverseasContractStore.decideRenewal(player:p,calendar:calendar,offerID:offer.id,accept:false,date:p.gameDate,revision:calendar.revision,in:c.mainContext)
                        }
                        if let member=try calendar.registration(for:p),let review=owner.overseasCareer?.renewalReviews?.last {
                            p.gameDate=max(review.window.end.adding(days:1),try GameDate(member.economicEnd).adding(days:1)).description
                            try c.mainContext.save()
                        }
                    }
                    if args.contains("-renewal-verification"),age == 20,args.contains("-selection-qualified") {
                        try seedRenewal(player:p,calendar:calendar,in:c.mainContext,empty:args.contains("-renewal-empty"),expired:args.contains("-renewal-expired"))
                    }
                    if args.contains("-pro-career-verification"),args.contains("-renewal-verification") {
                        if verifyDivisions {
                            try calendar.adoptOverseasExpansion(after: GameDate(p.gameDate))
                            try c.mainContext.save()
                        }
                        try seedProCareer(player:p,calendar:calendar,in:c.mainContext)
                        if verifyDivisions {
                            let entry = try acceptProfessionalNPB(player:p,calendar:calendar,in:c.mainContext)
                            p.gameDate = entry.effective
                            if args.contains("-v172-home-qa-long-pro") {
                                let effective = try GameDate(entry.effective)
                                let longOpponents: Set<String> = ["jp-pro-8", "jp-pro-10", "jp-pro-12", "jp-pro-14"]
                                let fixtures = try calendar.fixtures(for: p, year: effective.year)
                                guard let game = fixtures.first(where: {
                                    $0.date >= effective && $0.homeID == entry.teamID && longOpponents.contains($0.awayID)
                                }) else { throw CalendarError.invalidGroup }
                                p.gameDate = game.date.description
                            }
                            calendar.actionDate = nil
                            try c.mainContext.save()
                        }
                    }
                    if args.contains("-fa-verification"),args.contains("-pro-career-verification") {
                        try seedFA(player:p,calendar:calendar,in:c.mainContext)
                    }
                    if args.contains("-v31-match-completed") {
                        let context=c.mainContext
                        guard let fixture=try calendar.upcoming(for:p).first(where:{$0.isAppearance(for:role)}) else {throw MatchError.noFixture}
                        p.gameDate=fixture.date.adding(days:-4).description;calendar.actionDate=nil;try context.save()
                        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
                        let report=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:context).overseasReports!.last!
                        let club=CareerTargetClub.catalog(report).first {$0.roleID == (role == .batter ? "field":"starter")}!
                        try OverseasContractStore.selectTarget(player:p,calendar:calendar,reportID:report.id,clubID:club.id,date:p.gameDate,revision:calendar.revision,in:context)
                        try OverseasContractStore.startProject(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
                        p.gameDate=fixture.date.description;calendar.actionDate=p.gameDate;try context.save()
                        let row=try CareerMatchStore.start(player:p,state:calendar,in:context)
                        try CareerMatchStore.advance(player:p,state:calendar,record:row,revision:row.revision,input:.automatic,in:context)
                    }
                }
                self.schools = schools;self.container = c
            } catch { failure = error.localizedDescription }
        }
    }
    @MainActor private func seedOverseasRenewal(player p:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws {
        try OverseasContractStore.register(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        try OverseasContractStore.evaluate(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        guard let entry=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:context).overseasCareer?.evaluations.last?.offers.first else {throw OverseasProgressError.requirements}
        try OverseasContractStore.decide(player:p,calendar:calendar,offerID:entry.id,accept:true,date:p.gameDate,revision:calendar.revision,in:context)
        let firstYear=try GameDate(entry.effective).year,club=entry.teamID.components(separatedBy:"-").last!
        var chosen=firstYear
        for year in firstYear..<(firstYear+40) {
            let period=try ScoutingPeriod(origin:GameDate(calendar.originDate),today:GameDate("\(year)-11-01")).index
            let seed=p.id.uuidString+"/overseas-market-v1/"+String(period)
            if DomesticSelection.hash(seed+entry.route.id+"/"+club+"/"+entry.roleID)%5 != 0 {chosen=year;break}
        }
        for (index,fixture) in try calendar.fixtures(for:p,year:chosen).filter({$0.isAppearance(for:p.role)}).enumerated() {
            p.gameDate=fixture.date.description
            var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
            values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
            var match=ScoutingReferenceSimulation.fixture(role:p.role,position:p.role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(chosen*100+index),home:fixture.homeID == entry.teamID,tracked:true)
            match.competition="mlb-development";try match.advance(.automatic)
            let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";context.insert(row)
        }
        p.gameDate="\(chosen)-11-01";p.contact=99;p.power=99;p.discipline=99;p.defense=99;p.arm=99;p.speed=99
        let profile=try PlayerAbilityStore.profile(playerID:p.id,in:context)!
        try profile.grow(.mental,to:99)
        if p.role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try profile.grow(kind,to:99)};for pitch in p.pitches {pitch.mastery=99}}
        try context.save()
        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
    }
    @MainActor private func acceptProfessionalNPB(player p:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws -> OverseasOffer {
        try OverseasContractStore.register(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        try OverseasContractStore.requestConsent(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        try OverseasContractStore.evaluate(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        guard let entry=try ContractRegistrationStore.journal(player:p,calendar:calendar,in:context).overseasCareer?.evaluations.last?.offers.first(where:{$0.route == .npbFirstTeam}) else {throw OverseasProgressError.requirements}
        try OverseasContractStore.decide(player:p,calendar:calendar,offerID:entry.id,accept:true,date:p.gameDate,revision:calendar.revision,in:context)
        return entry
    }
    @MainActor private func seedFA(player p:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws {
        let entry = try acceptProfessionalNPB(player:p,calendar:calendar,in:context)
        let first=try GameDate(entry.effective).year,count=p.role == .pitcher ? 9:1
        for year in first..<(first+count) {
            var totals=PersonalSeasonTotals()
            for (index,fixture) in try SeasonSchedule.fixtures(year:year,schoolIDs:CareerTeamDirectory.japaneseFirstIDs).filter({$0.includes(entry.teamID) && $0.isAppearance(for:p.role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
                values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
                var match=ScoutingReferenceSimulation.fixture(role:p.role,position:p.role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(year*100+index),home:fixture.homeID == entry.teamID,tracked:true)
                match.competition="npb-first-team";try match.advance(.automatic)
                let row=try CareerMatchRecord(verificationPlayerID:p.id,teamID:entry.teamID,fixture:fixture,match:match,fatigue:p.fatigue);context.insert(row)
                try totals.add(match.line)
                if p.role == .batter ? totals.line.plateAppearances >= 100:totals.line.pitchingOuts >= 75 {break}
            }
        }
        p.gameDate="\(first+count-1)-11-01";try context.save()
        try OverseasContractStore.collectFAService(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
    }
    @MainActor private func seedProCareer(player p:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws {
        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        try OverseasContractStore.promoteDomestic(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
        let year=try GameDate(p.gameDate).year+1,plan=try calendar.competition(for:p,year:year)
        for (index,fixture) in try calendar.fixtures(for:p,year:year).filter({$0.isAppearance(for:p.role)}).enumerated() {
            p.gameDate=fixture.date.description
            var values=PlayerInitialValues(contact:88,power:88,discipline:88,speed:75,defense:80,arm:80)
            values.velocity=88;values.control=88;values.stuff=88;values.stamina=88
            var match=ScoutingReferenceSimulation.fixture(role:p.role,position:p.role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(year*100+index),home:fixture.homeID == plan.teamID,tracked:true)
            match.competition="domestic-first-team";try match.advance(.automatic)
            let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";context.insert(row)
        }
        p.gameDate="\(year)-11-01"
        p.contact=99;p.power=99;p.discipline=99;p.defense=99;p.arm=99;p.speed=99
        let profile=try PlayerAbilityStore.profile(playerID:p.id,in:context)!
        try profile.grow(.mental,to:99)
        if p.role == .pitcher {for kind in [TrainingKind.velocity,.control,.stuff,.stamina] {try profile.grow(kind,to:99)};for pitch in p.pitches {pitch.mastery=99}}
        try context.save()
        try OverseasReportStore.capture(player:p,calendar:calendar,date:p.gameDate,revision:calendar.revision,in:context)
    }
    @MainActor private func seedCollegePro(player p:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws {
        let evaluation=try ContractEvaluationStore.records(player:p,calendar:calendar,in:context).first!
        let packet=try ContractOfferStore.records(player:p,calendar:calendar,in:context).first!.snapshot(evaluation:evaluation,player:p,calendar:calendar)
        let offer=packet.offers.first {$0.route == .college}!
        try ContractRegistrationStore.decide(player:p,calendar:calendar,offerID:offer.id,accept:true,date:p.gameDate,revision:calendar.revision,in:context)
        let member=try calendar.registration(for:p)!
        for (index,fixture) in try calendar.fixtures(for:p,year:2032).filter({$0.isAppearance(for:p.role)}).enumerated() {
            p.gameDate=fixture.date.description
            var values=PlayerInitialValues(contact:80,power:80,discipline:80,speed:60,defense:80,arm:65)
            values.velocity=80;values.control=80;values.stuff=80;values.stamina=80
            var match=ScoutingReferenceSimulation.fixture(role:p.role,position:p.role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(8200+index),home:fixture.homeID == member.teamID,tracked:true)
            match.competition="college";try match.advance(.automatic)
            let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";context.insert(row)
        }
        p.gameDate="2032-11-01";try context.save()
        _ = try ContractEvaluationStore.captureIfDue(player:p,calendar:calendar,in:context);try context.save()
    }
    @MainActor private func seedRenewal(player p:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext,empty:Bool,expired:Bool) throws {
        let evaluation=try ContractEvaluationStore.records(player:p,calendar:calendar,in:context).first!
        let packet=try ContractOfferStore.records(player:p,calendar:calendar,in:context).first!.snapshot(evaluation:evaluation,player:p,calendar:calendar)
        let offer=packet.offers.first {$0.route == .rookie}!
        try ContractRegistrationStore.decide(player:p,calendar:calendar,offerID:offer.id,accept:true,date:p.gameDate,revision:calendar.revision,in:context)
        let member=try calendar.registration(for:p)!
        var year=2030
        for candidate in 2030...2040 {
            p.gameDate="\(candidate)-11-01";try context.save()
            let observation=try ScoutingObservationStore.currentObservation(player:p,calendar:calendar,in:context)
            let window=ContractEvaluationWindow(year:candidate,month:11)
            let review=try DomesticRenewalReview.make(observation:observation,member:member,roleID:offer.roleID,key:CareerContractEvaluation.key(p.id,window.id),window:window)
            if review.budget >= 200 {year=candidate;break}
        }
        if !empty {
            for (index,fixture) in try calendar.fixtures(for:p,year:year).filter({$0.isAppearance(for:p.role)}).enumerated() {
                p.gameDate=fixture.date.description
                var values=PlayerInitialValues(contact:80,power:80,discipline:80,speed:60,defense:80,arm:65)
                values.velocity=80;values.control=80;values.stuff=80;values.stamina=80
                var match=ScoutingReferenceSimulation.fixture(role:p.role,position:p.role == .batter ? p.positionRaw:"P",values:values,seed:UInt64(5200+index),home:fixture.homeID == member.teamID,tracked:true)
                match.competition="domestic-development";try match.advance(.automatic)
                let row=try CareerMatchRecord(player:p,fixture:fixture,match:match);row.completed=true;row.rulesVersion="native-match-v2";context.insert(row)
            }
        }
        p.gameDate="\(year)-11-01";try context.save()
        _ = try ContractEvaluationStore.captureIfDue(player:p,calendar:calendar,in:context);try context.save()
        if expired {p.gameDate="\(year)-11-08";try context.save()}
        if ProcessInfo.processInfo.arguments.contains("-release-verification") {
            p.gameDate="2035-11-01";try context.save()
            _ = try ContractEvaluationStore.captureIfDue(player:p,calendar:calendar,in:context);try context.save()
            p.gameDate="2035-11-15"
            for row in try ContractEvaluationStore.records(player:p,calendar:calendar,in:context) {row.acknowledged=true}
            try context.save()
            if ProcessInfo.processInfo.arguments.contains("-released-retry-verification") {
                let candidate=try ContractRegistrationStore.releaseCandidate(player:p,calendar:calendar,in:context)!
                try ContractRegistrationStore.release(player:p,calendar:calendar,evaluationKey:candidate.key,date:p.gameDate,revision:calendar.revision,in:context)
                p.gameDate="2036-04-01";try context.save()
                try ContractEvaluationStore.registerCurrent(in:context)
            }
        }
    }

}
#endif

#if DEBUG
enum LiveCareerQA {
    enum OpponentHomeRun: String {
        case walkOff = "walk-off"
        case goAhead = "go-ahead"
        case grandSlam = "grand-slam"

        var runs: Int {
            switch self {
            case .walkOff: 2
            case .goAhead: 3
            case .grandSlam: 4
            }
        }
    }

    static func storeURL(arguments:[String],bundleID:String?) throws -> URL {
        guard bundleID == "dev.bm.career.performanceqa",let index=arguments.firstIndex(of:"-qa-session"),
              index+1<arguments.count,let session=UUID(uuidString:arguments[index+1]) else {
            throw NSError(domain:"BM.QA",code:1,userInfo:[NSLocalizedDescriptionKey:"실제 경기 QA는 별도 앱·세션이 필요합니다."])
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("live-career-\(session.uuidString).store")
    }

    @MainActor static func prepareProVenueHomeRun(player: CareerPlayer, calendar: CareerCalendarState,
                                                 legacySnapshot: CareerMatchReadSnapshot? = nil, in context: ModelContext) throws {
        let row = try CareerMatchStore.start(player: player, state: calendar, in: context)
        if let legacySnapshot, CareerMatchReadSnapshot(row) != legacySnapshot { throw MatchError.invalidRecord }
        guard row.revision == 0 else { return }
        var match = try row.snapshot()
        let pitcher = player.role == .pitcher
        guard pitcher ? match.ownPitcherActive && !match.offense : match.ownAtBat else { throw MatchError.noFixture }
        let requested = try PitchSelectionStore.resolve(player: player, available: Set(match.mastery.keys))
        let pitch = match.deliveryPitchCode(requested: requested)
        let order = match.half.isMultiple(of: 2) ? match.awayOrder : match.homeOrder
        guard (0...1).contains(match.half), order == 0 else { throw MatchError.noFixture }
        let timings = pitcher ? [0.40, ManualMatchRules.releaseCenter, 0.96] : [0.73, 0.82, 0.91]

        // Copy one seed into the pre-input snapshot. The touch event still supplies the real swing or release.
        for _ in 0..<8192 {
            let delivery = match.delivery(pitchCode: pitch)
            let target = PitchTarget(x: delivery.x, y: delivery.y)
            let contacts = try timings.allSatisfy { timing in
                var sample = match
                let control = pitcher ? ManualMatchInput(release: timing, pitchTarget: target)
                    : ManualMatchInput(x: 0.5, y: 0.5, timing: timing)
                try sample.advance(pitcher ? .pitch : .swing, pitchCode: pitch, control: control)
                return sample.homeRuns?.last.map {
                    $0.half == match.half && $0.order == order && $0.batter.own == !pitcher
                } == true
            }
            if contacts {
                row.payload = try JSONEncoder().encode(match)
                try context.save()
                return
            }
            match.random = nextSeed(match.random)
        }
        throw MatchError.noFixture
    }

    private struct PitchBatch {
        let seed: UInt64
        let count: Int
        let control: ManualMatchInput?
    }

    @MainActor static func prepareOpponentHomeRun(_ scenario: OpponentHomeRun, player: CareerPlayer,
                                                  calendar: CareerCalendarState, in context: ModelContext) throws {
        let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
        guard record.revision == 0 else { return }
        var ready = try record.snapshot()
        guard !ready.isHome, ready.ownPitcherActive, !ready.offense else { throw MatchError.noFixture }
        let pitch = try PitchSelectionStore.resolve(player: player, available: Set(ready.mastery.keys))
        let reserve = (scenario.runs - 1) * 4 + 1
        let limit = MatchPitching.limit(stamina: ready.abilityStats?.stamina ?? 60) - 1
        var batches: [PitchBatch] = []

        // Simulate only to pick seeds. The same setup pitches are then stored through the usual match path.
        if scenario == .walkOff {
            while ready.half < 17 {
                let remaining = (17 - ready.half) / 2
                let budget = min(12, (limit - ready.line.pitches - reserve) / remaining)
                let targetGap = remaining == 1 ? scenario.runs - 1 : max(scenario.runs - 1, ready.awayScore - ready.homeScore)
                let result = try nextDefense(from: ready, pitch: pitch, budget: budget, allowedGap: 0...targetGap)
                ready = result.match
                batches.append(result.batch)
            }
        } else if scenario == .goAhead, !(1..<scenario.runs).contains(ready.awayScore - ready.homeScore) {
            let result = try nextDefense(from: ready, pitch: pitch, budget: 18, allowedGap: 1...(scenario.runs - 1))
            ready = result.match
            batches.append(result.batch)
        } else if scenario == .grandSlam, (1..<scenario.runs).contains(ready.awayScore - ready.homeScore) {
            let result = try nextDefense(from: ready, pitch: pitch, budget: 18, allowedGap: Int.min...0)
            ready = result.match
            batches.append(result.batch)
        }

        let setup = try loadBases(from: ready, runners: scenario.runs - 1, pitch: pitch)
        ready = setup.match
        batches.append(setup.batch)
        let half = ready.half, order = ready.homeOrder
        let deliveryCode = ready.deliveryPitchCode(requested: pitch)
        let phases = [0.40, ManualMatchRules.releaseCenter, 0.96]
        for _ in 0..<8192 {
            let delivery = ready.delivery(pitchCode: deliveryCode)
            let target = PitchTarget(x: delivery.x, y: delivery.y)
            let reachesFence = try phases.allSatisfy { phase in
                var sample = ready
                try sample.advance(.pitch, pitchCode: pitch, control: ManualMatchInput(release: phase, pitchTarget: target))
                return sample.lastManual?.outcome == "홈런" && sample.awayScore == ready.awayScore
                    && sample.homeScore == ready.homeScore + scenario.runs && sample.completed == (scenario == .walkOff)
                    && sample.homeRuns?.last.map { $0.half == half && $0.order == order && !$0.batter.own && $0.runs == scenario.runs } == true
            }
            if reachesFence {
                for batch in batches {
                    var previous = try record.snapshot()
                    previous.random = batch.seed
                    record.payload = try JSONEncoder().encode(previous)
                    try context.save()
                    for _ in 0..<batch.count {
                        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision,
                                                     input: .pitch, pitchCode: pitch, control: batch.control, in: context)
                    }
                }
                var saved = try record.snapshot()
                saved.random = ready.random
                guard saved == ready else { throw MatchError.invalidRecord }
                record.payload = try JSONEncoder().encode(ready)
                try context.save()
                return
            }
            ready.random = nextSeed(ready.random)
        }
        throw MatchError.noFixture
    }

    private static func nextDefense(from initial: CareerMatch, pitch: String, budget: Int,
                                    allowedGap: ClosedRange<Int>) throws -> (match: CareerMatch, batch: PitchBatch) {
        guard budget > 0 else { throw MatchError.noFixture }
        let target = max(allowedGap.lowerBound, min(0, allowedGap.upperBound))
        var seed = initial.random
        var best: (match: CareerMatch, batch: PitchBatch)?
        for _ in 0..<768 {
            defer { seed = nextSeed(seed) }
            var sample = initial
            sample.random = seed
            for count in 1...budget {
                try sample.advance(.pitch, pitchCode: pitch)
                if sample.completed || !sample.ownPitcherActive { break }
                if sample.half != initial.half {
                    let gap = sample.awayScore - sample.homeScore
                    if sample.half == initial.half + 2, allowedGap.contains(gap),
                       best.map({ abs(gap - target) < abs($0.match.awayScore - $0.match.homeScore - target) }) ?? true {
                        let candidate = (sample, PitchBatch(seed: seed, count: count, control: nil))
                        if gap == target { return candidate }
                        best = candidate
                    }
                    break
                }
            }
        }
        guard let best else { throw MatchError.noFixture }
        return best
    }

    private static func loadBases(from initial: CareerMatch, runners: Int,
                                  pitch: String) throws -> (match: CareerMatch, batch: PitchBatch) {
        let control = ManualMatchInput(release: ManualMatchRules.releaseCenter, pitchTarget: PitchTarget(x: 0.1, y: 0.1))
        var seed = initial.random
        for _ in 0..<1024 {
            defer { seed = nextSeed(seed) }
            var sample = initial
            sample.random = seed
            for count in 1...(runners * 4) {
                try sample.advance(.pitch, pitchCode: pitch, control: control)
                guard !sample.completed, sample.ownPitcherActive, sample.half == initial.half,
                      sample.homeScore == initial.homeScore, sample.awayScore == initial.awayScore,
                      let outcome = sample.lastManual?.outcome, outcome == "볼" || outcome == "볼넷" else { break }
                if sample.bases.filter({ $0 }).count == runners {
                    return (sample, PitchBatch(seed: seed, count: count, control: control))
                }
            }
        }
        throw MatchError.noFixture
    }

    private static func nextSeed(_ seed: UInt64) -> UInt64 {
        seed &* 6364136223846793005 &+ 1442695040888963407
    }
}

// Uses real creation/calendar/store/view/input paths. Controlled QA inputs, never forced outcomes.
private struct LiveCareerPerformanceRun:View {
    @State private var container:ModelContainer?
    @State private var player:CareerPlayer?
    @State private var calendar:CareerCalendarState?
    @State private var schools:[School]=[]
    @State private var failure:String?
    var body:some View {
        NavigationStack {
            if let container,let player,let calendar {
                CareerGameView(player:player,calendar:calendar,schools:schools).modelContainer(container)
            } else {Text(failure ?? "실제 경기 QA 준비 중")}
        }.task {
            guard container == nil,failure == nil else {return}
            do {
                let args=ProcessInfo.processInfo.arguments
                let url=try LiveCareerQA.storeURL(arguments:args,bundleID:Bundle.main.bundleIdentifier)
                let opponentHomeRun: LiveCareerQA.OpponentHomeRun?
                if let index = args.firstIndex(of: "-qa-v191-opponent-homer") {
                    guard args.indices.contains(index + 1), args.contains("-qa-pitcher"),
                          let scenario = LiveCareerQA.OpponentHomeRun(rawValue: args[index + 1]) else {
                        throw MatchError.invalidInput
                    }
                    opponentHomeRun = scenario
                } else {
                    opponentHomeRun = nil
                }
                let legacyPortland = args.contains("-qa-portland-legacy-save")
                let freshSession = !FileManager.default.fileExists(atPath: url.path)
                let proVenueID: String?
                if let index = args.firstIndex(of: "-qa-v188-publish-venue") {
                    guard opponentHomeRun == nil, args.indices.contains(index + 1),
                          let venue = ProStadium.resolve(args[index + 1]), venue.club.id != args[index + 1] else {
                        throw MatchError.invalidInput
                    }
                    proVenueID = args[index + 1]
                    guard !legacyPortland || (proVenueID == "us-pro-12" && args.contains("-qa-pitcher")) else {
                        throw MatchError.invalidInput
                    }
                    if freshSession {
                        let role: PlayerRole = args.contains("-qa-pitcher") ? .pitcher : .batter
                        let fixture = legacyPortland ? "mlb-portland-legacy-pitcher.store" : "\(venue.club.league.rawValue)-\(role.rawValue).store"
                        let source = FileManager.default.temporaryDirectory
                            .appendingPathComponent("v188-publish-venue", isDirectory: true)
                            .appendingPathComponent(fixture)
                        try FileManager.default.copyItem(at: source, to: url)
                    }
                } else {
                    guard !legacyPortland else { throw MatchError.invalidInput }
                    proVenueID = nil
                }
                let c=try CareerStore.makeContainer(url:url),catalog=try SchoolCatalog.load()
                let p:CareerPlayer
                if let saved=try c.mainContext.fetch(FetchDescriptor<CareerPlayer>()).first {p=saved}
                else {
                    var draft=PlayerDraft();draft.name="ProfileQA";draft.schoolID=catalog[0].id
                    draft.role=args.contains("-qa-pitcher") ? .pitcher:.batter
                    if draft.role == .pitcher {draft.throwingHand = .left}
                    p=try CareerStore.create(draft,schools:catalog,in:c.mainContext)
                }
                let state=try c.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID==p.id}!
                if let proVenueID, state.actionDate == nil {
                    let today = try GameDate(p.gameDate)
                    guard let fixture = try state.fixtures(for: p, year: today.year).first(where: {
                        $0.date >= today && $0.homeID == proVenueID && $0.isAppearance(for: p.role)
                    }) else { throw MatchError.noFixture }
                    p.gameDate = fixture.date.description
                    try c.mainContext.save()
                }
                if let opponentHomeRun, state.actionDate == nil {
                    let today = try GameDate(p.gameDate)
                    guard p.role == .pitcher,
                          let fixture = try state.fixtures(for: p, year: today.year).first(where: {
                              $0.awayID == p.schoolID && $0.isAppearance(for: .pitcher)
                          }) else { throw MatchError.noFixture }
                    p.gameDate = fixture.date.description
                    if opponentHomeRun == .walkOff,
                       let profile = try PlayerAbilityStore.profile(playerID: p.id, in: c.mainContext) {
                        try profile.grow(.stamina, to: 99)
                    }
                    try c.mainContext.save()
                }
                if state.actionDate != p.gameDate {try CalendarProgression.rest(player:p,state:state,revision:state.revision,in:c.mainContext)}
                if let opponentHomeRun {
                    try LiveCareerQA.prepareOpponentHomeRun(opponentHomeRun, player: p, calendar: state, in: c.mainContext)
                }
                if proVenueID != nil {
                    let legacySnapshot: CareerMatchReadSnapshot?
                    if legacyPortland {
                        let fixture = try CareerMatchStore.today(player: p, state: state)
                        guard p.role == .pitcher, fixture.id == "2040-07-17-us-pro-12-us-pro-0",
                              let row = try CareerMatchStore.record(player: p, fixture: fixture, in: c.mainContext) else {
                            throw MatchError.noFixture
                        }
                        if freshSession {
                            let saved = try row.snapshot()
                            guard row.revision == 0, !saved.isHome, saved.ownPitcherActive, saved.half == 1,
                                  let selection = saved.clubSelection, selection.rotationDay, selection.fixtureNumber == nil else {
                                throw MatchError.invalidRecord
                            }
                        }
                        legacySnapshot = CareerMatchReadSnapshot(row)
                    } else {
                        legacySnapshot = nil
                    }
                    try LiveCareerQA.prepareProVenueHomeRun(player: p, calendar: state, legacySnapshot: legacySnapshot, in: c.mainContext)
                }
                schools=catalog;player=p;calendar=state;container=c
            } catch {failure=error.localizedDescription}
        }
    }
}
#endif

import UniformTypeIdentifiers

private struct SaveProtectionKey: EnvironmentKey { static let defaultValue: SaveProtection? = nil }
extension EnvironmentValues {
    var saveProtection: SaveProtection? {
        get { self[SaveProtectionKey.self] }
        set { self[SaveProtectionKey.self] = newValue }
    }
}
struct SaveBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data=data }
    init(configuration: ReadConfiguration) throws {
        guard let data=configuration.file.regularFileContents else { throw SaveProtectionError.invalid }; self.data=data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SaveProtectionView: View {
    var onRestored: (() -> Void)? = nil
    @Environment(\.saveProtection) private var protection
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bm-haptics-enabled") private var haptics = true
    @AppStorage("bm-sound-enabled") private var sound = true
    @AppStorage("bm-umpire-voice-enabled") private var umpireVoice = true
    @AppStorage("bm-sound-volume") private var soundVolume = 0.9
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var audioTypeSize
    @State private var document: SaveBackupDocument?
    @State private var exportBytes:Int?
    @Query private var archivePlayers:[CareerPlayer]
    @State private var exporting=false
    @State private var importing=false
    @State private var prepared: PreparedSave?
    @State private var confirming=false
    @State private var message: String?
    @State private var working:String?
    @State private var failure: SaveOperationFailure?
    @State private var selectedFilename: String?
    #if DEBUG
    @State private var qaFailureRemaining = true
    @State private var qaSeedApplied = false
    #endif
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 16) {
                    if audioTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("백업·복원").managementFont(.sectionTitle).accessibilityAddTraits(.isHeader)
                            Text("확정 전 진행 유지").managementFont(.helper)
                        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("saveCompactHeading")
                    } else {
                        ManagementFileHeader(eyebrow: "LOCAL SAVE", title: "이 기기의 커리어 보관", note: "내보내기 → 파일 검증 → 전체 복원 확인")
                    }
                    if let failure {
                        SaveOperationFailureView(failure: failure,
                            currentState: SaveOperationFailure.currentState(hasProtection: protection != nil,
                                recoveryOnly: protection?.recoveryOnly == true),
                            retryTitle: failureRetry(failure).label, retry: retryFailure)
                            .id("saveOperationFailure")
                    } else if let message {
                        ManagementPanel("저장 작업 결과") {
                            Text(message).managementFont(.body)
                                .accessibilityLabel("저장 작업 결과 · " + message)
                                .accessibilityIdentifier("saveProtectionMessage")
                        }
                    }
                    ManagementPanel("1. 저장 내보내기") {
                        if protection?.recoveryOnly == true {
                            Text("현재 저장 열기 실패 · 선수 수 확인 필요").managementFont(.label).accessibilityIdentifier("saveCareerCountsUnavailable")
                        } else {
                            Text("진행 중 \(archivePlayers.filter {!$0.isRetired}.count)명 · 은퇴 보관 \(archivePlayers.filter(\.isRetired).count)명")
                                .managementFont(.label).accessibilityIdentifier("saveCareerCounts")
                        }
                        Button("백업 파일 만들기",action:exportBackup)
                            .buttonStyle(ManagementButtonStyle(variant:.secondary)).accessibilityIdentifier("exportSave").disabled(protection?.recoveryOnly == true)
                        Text("모든 커리어를 파일로 보관하며 현재 진행은 유지합니다.").managementFont(.helper)
                        if let exportBytes {
                            Text("이번에 만든 백업 파일 · "+ByteCountFormatter.string(fromByteCount:Int64(exportBytes),countStyle:.file))
                                .managementFont(.body).accessibilityIdentifier("saveExportSize")
                        } else {
                            Text("용량은 백업 생성 후 표시됩니다.").managementFont(.helper).accessibilityIdentifier("saveSizePending")
                        }
                        DisclosureGroup("백업 범위·개인정보·용량 안내") {
                            Text("모든 선수·날짜·능력치·고정 보고서·진행 중인 경기와 훈련을 함께 보관합니다. 파일에는 선수 이름과 기록이 포함됩니다. 외부 서버로 자동 전송하지 않습니다.").managementFont(.body)
                            Text("백업 용량은 파일 생성 후 실제 바이트 수로 표시합니다. 크기를 미리 추정하거나 자동으로 내보내지 않습니다.").managementFont(.helper)
                            Text("은퇴 기록은 자동 삭제하지 않습니다. 표시된 백업 파일 크기와 아래 DB 복원 상한은 서로 다른 값입니다.").managementFont(.helper)
                        }.tint(GameTheme.gold).accessibilityIdentifier("saveExportDetails")
                    }
                    ManagementPanel("2. 백업 선택·검증") {
                        if let selectedFilename {
                            Text("선택한 파일 · " + selectedFilename).managementFont(.label)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("saveSelectedFilename")
                        }
                        Button("백업 선택·검증", action: chooseBackup)
                            .buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("importSave")
                        Text("선택한 파일을 별도 저장소에서 검증합니다. 아직 현재 진행에 반영하지 않습니다.").managementFont(.helper)
                        DisclosureGroup("백업 형식·파일 보관 안내") {
                            Text("V15 백업 · DB 상한64MiB(67,108,864바이트). 파일은 암호화되지 않았고 해시는 무결성 확인용입니다. 위 백업 파일 크기와 DB 상한은 다릅니다.").managementFont(.helper)
                        }.tint(GameTheme.gold).accessibilityIdentifier("saveFormatDetails")
                    }
                    if let prepared {
                        ManagementPanel(prepared.state == .discarded ? "3. 백업 다시 검증" : "3. 검증 완료·전체 복원") {
                            Text((prepared.state == .discarded ? "다시 검증할 백업 · " : "검증 완료 · ") + prepared.created.formatted(date: .abbreviated, time: .shortened))
                                .managementFont(.label).accessibilityIdentifier("saveVerifiedBackupDate")
                            CareerManagementNote(title:"전체 복원 영향 · 모든 커리어",detail:"날짜·기록·진행 중 경기와 훈련이 백업 시점으로 바뀝니다. 현재 기록과 합치지 않으며 확정 전까지 기존 저장을 사용합니다.",identifier:"restoreScopeSummary")
                            Text("현재 기기").managementFont(.label)
                            if protection?.recoveryOnly == true {Text("현재 저장은 열리지 않아 날짜/선수를 비교할 수 없습니다.").managementFont(.body)}
                            else {ForEach(archivePlayers) {p in Text(p.name+" · "+p.role.label+" · "+p.gameDate).managementFont(.body)}}
                            Text("복원할 백업").managementFont(.label)
                            ForEach(prepared.players, id: \.self) { Text($0).managementFont(.body) }
                            if prepared.players.isEmpty { Text("선수가 없는 백업입니다.").managementFont(.body) }
                            Button("이 백업으로 전체 복원 확인") { confirming=true }
                                .buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier("confirmRestoreSave")
                                .disabled(prepared.state == .discarded)
                        }
                    }
                    ManagementPanel("기기 설정") {
                        Toggle("경기·훈련 진동", isOn: $haptics).accessibilityIdentifier("settingHaptics")
                        Toggle("경기 소리", isOn: $sound).accessibilityIdentifier("settingSound")
                            .onChange(of:sound) { _, enabled in if enabled {GameSound.shared.play(.confirm)} else {GameSound.shared.stop()} }
                        Text("소리 크기 · \(Int(GameSound.volume(soundVolume)*100))%").managementFont(.label)
                        Slider(value:$soundVolume,in:0...1,step:0.05)
                            .accessibilityLabel("경기 소리 크기").accessibilityValue("\(Int(GameSound.volume(soundVolume)*100))퍼센트")
                            .accessibilityIdentifier("settingSoundVolume").disabled(!sound)
                            .onChange(of:soundVolume) {_,_ in GameSound.shared.updateVolume()}
                        Toggle("심판 음성 · 영어 녹음", isOn: $umpireVoice).disabled(!sound)
                            .accessibilityIdentifier("settingUmpireVoice")
                            .onChange(of: umpireVoice) { _, enabled in if !enabled {GameSound.shared.stopVoice()} }
                        Button("타격음 들어보기") {GameSound.shared.play(.contact)}
                            .buttonStyle(ManagementButtonStyle(variant: .secondary)).disabled(!sound)
                            .accessibilityIdentifier("previewSound")
                        Button("포구음 들어보기") {GameSound.shared.play(.catchBall)}
                            .buttonStyle(ManagementButtonStyle(variant: .secondary)).disabled(!sound)
                            .accessibilityIdentifier("previewCatchSound")
                        Button("홈런 환호 들어보기") {GameSound.shared.play(.crowd)}
                            .buttonStyle(ManagementButtonStyle(variant:.secondary)).disabled(!sound)
                            .accessibilityIdentifier("previewCrowdSound")
                        Text("심판 판정 들어보기").managementFont(.label)
                        LazyVGrid(columns: audioTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                            ForEach(UmpireCall.allCases, id: \.rawValue) { call in
                                Button(call.rawValue) {GameSound.shared.announce(call)}
                                    .buttonStyle(ManagementButtonStyle(variant: .secondary))
                                    .accessibilityLabel("\(call.rawValue) 음성 들어보기")
                                    .accessibilityIdentifier("previewUmpire-\(call)")
                            }
                        }.disabled(!sound || !umpireVoice || voiceOver)
                        Text("iPhone 무음·기기 음량을 따릅니다. 진동은 소리와 별도로 설정합니다. VoiceOver 사용 중에는 심판 음성을 끄고 한국어 화면 판정으로 안내합니다.").managementFont(.body)
                        Text("Strike · Ball · You're out 녹음입니다. 볼넷은 Ball, 삼진·땅볼·뜬공 아웃은 Out 콜과 한국어 판정으로 구분합니다. 목재 배트·글러브·관중 녹음의 출처는 고객지원의 음원·라이선스에서 확인할 수 있습니다.").managementFont(.body)
                    }
                    ManagementPanel("이용 안내·고객지원") {
                        Text("개인정보·기기 저장, 구매·환불과 글꼴 라이선스를 확인할 수 있습니다. 문의 창구와 정식 정책은 준비 중입니다.").managementFont(.body)
                        NavigationLink { SupportInformationView() } label: {
                            Text(SupportInformation.title)
                        }
                        .buttonStyle(ManagementButtonStyle(variant: .secondary))
                        .accessibilityIdentifier("openSupportInformation")
                    }
                }.padding(16).disabled(working != nil)
            }
            .task(id: failure?.id) {
                guard failure != nil else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                scroll.scrollTo("saveOperationFailure", anchor: .top)
            }
            }.safeAreaInset(edge:.bottom) {
                if let working {HStack(spacing:12) {ProgressView();Text(working).font(.subheadline)}.padding(14).frame(maxWidth:.infinity).background(GameTheme.boardPanel).foregroundStyle(GameTheme.boardInk).accessibilityElement(children:.combine).accessibilityIdentifier("saveOperationProgress")}
            }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("설정 · 저장 보호")
                .toolbar { ManagementToolbarAction(title: "닫기", identifier: "closeSettings", disabled: working != nil) { if discardPrepared(for: .discardForClose) {dismiss()} } }
        }
        .interactiveDismissDisabled(working != nil)
        .task {
            #if DEBUG
            do {
                if ProcessInfo.processInfo.arguments.contains("-save-protection-preview"), prepared == nil, let protection {
                    prepared = try SaveArchiveStore.prepare(SaveArchiveStore.export(container: protection.container), base: protection.base)
                }
                try await seedFailureVerification()
            } catch { showFailure(error, during: .validateBackup) }
            #endif
        }
        .onDisappear {
            GameSound.shared.stop()
            if !importing && !exporting && !confirming && working == nil {discardPrepared(for: .discardForClose)}
        }
        .fileExporter(isPresented: $exporting, document: document, contentTypes: [.data], defaultFilename: "BM-career.bmbackup", onCompletion: { result in
            switch result {
            case .success: showMessage("백업 내보내기 완료 · 기기의 진행 기록은 유지됩니다.")
            case .failure(let error):
                if isCancelled(error) { showMessage("내보내기 취소 · 기존 저장은 유지됩니다.") }
                else { showFailure(error, during: .exportFile) }
            }
        }, onCancellation: { showMessage("내보내기 취소 · 기존 저장은 유지됩니다.") })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false,
            onCompletion: { result in
                importBackup(result.flatMap { urls in
                    guard urls.count == 1 else { return .failure(SaveProtectionError.invalid) }
                    return .success(urls[0])
                })
            }, onCancellation: { showMessage("파일 선택 취소 · 기존 저장은 유지됩니다.") })
        .managementAlert("모든 커리어를 백업 시점으로 되돌릴까요?", isPresented: $confirming, kind: .confirmation) {
            Button("전체 복원", role: .destructive) {
                guard working == nil else {return}
                working="검증한 저장으로 전환 중"
                Task { @MainActor in
                    defer {working=nil}
                    do {guard let protection,let prepared else {throw SaveProtectionError.unavailable}
                        #if DEBUG
                        if consumeVerificationFailure("restore") {
                            try protection.restore(prepared, commit: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
                        } else { try protection.restore(prepared) }
                        #else
                        try protection.restore(prepared)
                        #endif
                        onRestored?();dismiss()
                    } catch { showFailure(error, during: .restore) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("현재 데이터와 합치지 않습니다. 복원 전 저장은 삭제하지 않습니다. 백업 이후 진행한 내용은 새 활성 커리어에 표시되지 않습니다.") }
    }
    private func isCancelled(_ error:Error) -> Bool {(error as? CocoaError)?.code == .userCancelled}
    @discardableResult private func discardPrepared(for operation: SaveFailureOperation) -> Bool {
        guard let prepared else {return true}
        do {
            guard let protection else {throw SaveProtectionError.unavailable}
            #if DEBUG
            if consumeVerificationFailure("cleanup") {
                try protection.discard(prepared, remove: { _ in throw CocoaError(.fileWriteNoPermission) })
            } else { try protection.discard(prepared) }
            #else
            try protection.discard(prepared)
            #endif
            self.prepared=nil
            return true
        } catch {
            showFailure(error, during: operation)
            return false
        }
    }
    private func exportBackup() {
        guard working == nil else {return}
        working="백업 파일 만드는 중 · 기존 저장 유지";message=nil;failure=nil
        document=nil;exportBytes=nil
        Task { @MainActor in
            defer {working=nil}
            do {
                guard let protection,!protection.recoveryOnly else {throw SaveProtectionError.unavailable}
                let data=try await SaveArchiveStore.exportAsync(container:protection.container)
                document=SaveBackupDocument(data:data);exportBytes=data.count;exporting=true
            } catch { showFailure(error, during: .createBackup) }
        }
    }
    private func importBackup(_ result:Result<URL,Error>) {
        guard working == nil else {return}
        let url:URL
        do {url=try result.get()}
        catch {
            if isCancelled(error) { showMessage("파일 선택 취소 · 기존 저장은 유지됩니다.") }
            else { showFailure(error, during: .chooseBackup) }
            return
        }
        guard discardPrepared(for: .discardForSelection) else {return}
        selectedFilename=url.lastPathComponent
        working="백업 검증 중 · 확정 전까지 기존 저장 유지";message=nil;failure=nil
        Task { @MainActor in
            let access=url.startAccessingSecurityScopedResource()
            defer {if access {url.stopAccessingSecurityScopedResource()};working=nil}
            do {
                guard let protection else {throw SaveProtectionError.unavailable}
                prepared=try await SaveArchiveStore.prepareFileAsync(url,base:protection.base)
                showMessage("검증 완료 · 아래 날짜와 선수를 비교한 뒤 전체 복원을 결정하세요.")
            } catch { prepared=nil;showFailure(error, during: .validateBackup) }
        }
    }


    private func chooseBackup() {
        guard working == nil, !exporting, !importing, !confirming else { return }
        importing=true
    }
    private func showFailure(_ error: Error, during operation: SaveFailureOperation) {
        message=nil
        failure=SaveOperationFailure(error, operation: operation)
    }
    private func showMessage(_ text: String) {
        failure=nil
        message=text
    }
    private func failureRetry(_ failure: SaveOperationFailure) -> SaveFailureRetry {
        failure.retry(preparedState: prepared?.state, hasExport: document != nil, hasProtection: protection != nil)
    }
    private func retryFailure() {
        guard let failure, working == nil, !exporting, !importing, !confirming else { return }
        switch failureRetry(failure) {
        case .createBackup: exportBackup()
        case .chooseExportLocation: exporting=true
        case .chooseBackup, .chooseAnotherBackup: chooseBackup()
        case .confirmRestore: confirming=true
        case .discardAndClose, .close:
            if discardPrepared(for: .discardForClose) { dismiss() }
        case .discardAndChooseBackup:
            if discardPrepared(for: .discardForSelection) { chooseBackup() }
        }
    }
    #if DEBUG
    private var verificationScenario: String? {
        let arguments=ProcessInfo.processInfo.arguments
        guard arguments.contains("-management-career-verification"),
              arguments.contains("-save-protection-verification"), let protection,
              (protection.base.deletingLastPathComponent().lastPathComponent.hasPrefix("save-qa-") ||
               protection.base.deletingLastPathComponent().lastPathComponent.hasPrefix("v56-resume-")),
              let index=arguments.firstIndex(of: "-save-feedback-failure"), index+1 < arguments.count else { return nil }
        return arguments[index+1]
    }
    private func consumeVerificationFailure(_ scenario: String) -> Bool {
        guard qaFailureRemaining, verificationScenario == scenario else { return false }
        qaFailureRemaining=false
        return true
    }
    private func seedFailureVerification() async throws {
        guard !qaSeedApplied, let scenario=verificationScenario, let protection, prepared == nil, failure == nil,
              !FileManager.default.fileExists(atPath: SaveArchiveStore.pointer(protection.base).path) else { return }
        qaSeedApplied=true
        switch scenario {
        case "export":
            let data=try await SaveArchiveStore.exportAsync(container: protection.container)
            document=SaveBackupDocument(data: data);exportBytes=data.count
            showFailure(CocoaError(.fileWriteNoPermission), during: .exportFile)
        case "verify":
            selectedFilename="BM-QA-invalid.bmbackup"
            do { _ = try await SaveArchiveStore.prepareAsync(Data("invalid-backup".utf8), base: protection.base) }
            catch { showFailure(error, during: .validateBackup) }
        case "restore", "cleanup":
            let data=try await SaveArchiveStore.exportAsync(container: protection.container)
            selectedFilename="BM-QA-valid.bmbackup"
            if scenario == "restore", let player=archivePlayers.first,
               let calendar=try protection.container.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first(where: { $0.playerID == player.id }),
               !calendar.hasAction(on: player.gameDate) {
                try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision,
                    in: protection.container.mainContext)
            }
            prepared=try await SaveArchiveStore.prepareAsync(data, base: protection.base)
        default: break
        }
    }
    #endif
}

private struct FailedSaveRecoveryView: View {
    let base: URL
    var restored: (SaveProtection) -> Void
    @State private var session: SaveProtection?
    @State private var error: String?
    var body: some View {
        Group {
            if let session { SaveProtectionView(onRestored: { restored(session) }).environment(\.saveProtection, session) }
            else if let error { Text(error) }
            else { ProgressView("복구 준비 중") }
        }.task {
            do { session=SaveProtection(container:try CareerStore.makeContainer(inMemory:true),base:base,recoveryOnly:true) }
            catch { self.error=error.localizedDescription }
        }
    }
}
