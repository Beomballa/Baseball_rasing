import SwiftUI
import SwiftData

@main struct BMApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-career-path-verification") {
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
            let inputQA = ProcessInfo.processInfo.arguments.contains("-input-fit-verification")
            let interestQA = ProcessInfo.processInfo.arguments.contains("-club-interest-verification")
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
                let c = try CareerStore.makeContainer(inMemory:true), schools = try SchoolCatalog.load()
                let args = ProcessInfo.processInfo.arguments
                let age = args.contains("-career-age20") ? 20 : args.contains("-career-age19") ? 19 : 16
                for role in PlayerRole.allCases {
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
                    if args.contains("-renewal-verification"),age == 20,args.contains("-selection-qualified") {
                        try seedRenewal(player:p,calendar:calendar,in:c.mainContext,empty:args.contains("-renewal-empty"),expired:args.contains("-renewal-expired"))
                    }
                }
                self.schools = schools;self.container = c
            } catch { failure = error.localizedDescription }
        }
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
    }

}
#endif
