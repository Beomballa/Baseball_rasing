import XCTest
import SwiftData
import SwiftUI
@testable import BM

@MainActor final class MatchOfficialReviewTests: XCTestCase {
    func match(_ role: PlayerRole) -> CareerMatch {
        var value = InplayIntegrationTests().makeMatch(role:role,isHome:role == .pitcher)
        value.enablePitchEvents();value.enableRunning();value.enableFieldReview();value.enableSpecialPlays();value.enableAppeals();value.enableOfficialReviews()
        return value
    }
    /// 야구 엔진의 보통 포구 실수 입력을 고정한다. 실제 서비스 RNG를 바꾸는 조절판이 아니다.
    func errorPlate(_ match: inout CareerMatch) throws {
        let home = match.half % 2 == 1, personalBatter = match.role == "batter" && match.ownAtBat
        let personalPitcher = match.ownPitcherActive && !match.offense
        let entrant = FieldRunnerProfile(speed:60,own:personalBatter,responsiblePitcher:match.pitching!.activeID(home:!home),
            id:match.playerRecords!.homeTeam(batting:match.half).batterID(order: home ? match.homeOrder:match.awayOrder,relief:match.pitching?.change(home:home) != nil))
        let original = FieldReviewRules.ball(quality:0.7,contact:70,power:60,bunt:false,offsetX:0,offsetY:0,timing:0,speedDraw:0.15,angleDraw:0.05,directionDraw:0.5)
        let ball = try XCTUnwrap(MatchSpecialRules.effectiveBall(MatchSpecialRules.context(match:match,ball:original,batter:entrant)))
        var clean = DetailedFieldRules.resolve(half:match.half,order:home ? match.homeOrder:match.awayOrder,
            landing:ball.landing,flight:ball.flight,runners:match.runnerProfiles!,batter:entrant,outs:match.outs,
            stats:match.fieldStats,defending:!match.offense,ownBatter:personalBatter,doublePlayEnabled:true,
            groundBall:true,relayEnabled:true,npc:match.npcDefenders,continuationEnabled:true)
        clean.version=5;clean.battedBall=ball;clean.ball=ball.nodes+clean.ball.filter {$0.at > ball.flight}
        clean.review = .init(before:MatchPitchState(match))
        XCTAssertTrue(clean.out)
        var play = FieldMisplayRules.applying(to:clean,stats:match.fieldStats,defending:!match.offense,
            draws:[0,0.5,0.5,0.5,0.5,0.5,0.5],npc:match.npcDefenders)
        play.battedBall=ball;play.review=clean.review
        XCTAssertEqual(play.misplay?.kind,.fielding);XCTAssertEqual(play.misplay?.reachedOnError,true)
        match.pitching?.recordPitch(home:!home)
        match.playerRecords?.recordPitch(home:!home,relief:match.pitching?.change(home:!home) != nil)
        if personalPitcher {match.line.pitches += 1;match.scoutingPerformance?.inputs?.record(direct:false)}
        match.completePlate(initial:"범타",result:"실책 출루",batter:personalBatter,pitcher:personalPitcher,
            newRunner:entrant,detailed:play,cleanForEarned:clean)
        play.review?.after=MatchPitchState(match);match.fieldPlays?.append(play)
    }
    func testHalfCloseChangesOnlyOfficialClassificationAndEarnedProof() throws {
        for role in PlayerRole.allCases {
            var value = match(role)
            try errorPlate(&value)
            XCTAssertNotNil(value.officialReview?.pending)
            XCTAssertEqual(value.playerRecords?.plateTrace?.last?.result,"안타")
            XCTAssertEqual(value.playerRecords?.away.battingTotal.hits,1)
            XCTAssertEqual(value.playerRecords?.home.fielding?.reduce(0){$0+$1.errors},0)
            try value.playerRecords?.validate(match:value);try value.validateDetailedField()
            let pending = try JSONEncoder().encode(value)
            value = try JSONDecoder().decode(CareerMatch.self,from:pending)
            InplayIntegrationTests().plate("홈런",in:&value)
            XCTAssertEqual(value.awayScore,2);XCTAssertEqual(value.playerRecords?.home.pitching[0].counts.earnedRuns,2)
            let rng = value.random
            for _ in 0..<3 { InplayIntegrationTests().plate("삼진",in:&value) }
            XCTAssertEqual(value.random,rng);XCTAssertEqual(value.awayScore,2)
            XCTAssertNil(value.officialReview?.pending);XCTAssertEqual(value.officialReview?.changes.count,1)
            XCTAssertEqual(value.playerRecords?.plateTrace?.first?.result,"실책 출루")
            XCTAssertEqual(value.playerRecords?.away.battingTotal.reachedOnError,1)
            XCTAssertEqual(value.playerRecords?.home.fielding?.reduce(0){$0+$1.errors},1)
            XCTAssertEqual(value.playerRecords?.home.pitching[0].counts.earnedRuns,1)
            let snapshot=value;value.closeOfficialReview();XCTAssertEqual(value,snapshot)
            try value.playerRecords?.validate(match:value);try value.validateDetailedField()
        }
    }
    func testGeneralGamesBothRolesKeepFinalCountersAndOldNil() throws {
        var corrected = 0, appealed = 0
        for role in PlayerRole.allCases {
            for seed in 1...32 {
                var value = match(role); value.random = UInt64(seed)
                try value.advance(.automatic)
                do {try value.playerRecords?.validate(match:value);try value.validateDetailedField();try value.validateRunning()}
                catch {
                    print("P12_REVIEW_INVALID",role.rawValue,seed)
                    let a=XCTAttachment(data:try JSONEncoder().encode(value),uniformTypeIdentifier:"public.json");a.name="P12-review-invalid";a.lifetime = .keepAlways;add(a)
                    throw error
                }
                corrected += value.officialReview?.changes.count ?? 0
                appealed += value.fieldPlays?.filter {$0.appeal != nil}.count ?? 0
                XCTAssertNil(value.officialReview?.pending)
                XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(value)),value)
            }
            var old=match(role);old.appealRulesVersion=nil;old.officialReview=nil
            try old.advance(.automatic)
            let copy=try JSONDecoder().decode(CareerMatch.self,from:JSONEncoder().encode(old))
            XCTAssertEqual(old,copy);XCTAssertNil(copy.officialReview)
        }
        print("P12_GENERAL_REVIEW",corrected,"APPEALS",appealed)
        XCTAssertGreaterThan(corrected,0);XCTAssertGreaterThan(appealed,0)
    }
    func testCorrectionRejectsChangedProofAndNeverAppearsBeforeClosure() throws {
        var value=match(.batter);try errorPlate(&value)
        for _ in 0..<3 {InplayIntegrationTests().plate("삼진",in:&value)}
        let change=try XCTUnwrap(value.officialReview?.changes.first)
        XCTAssertTrue(change.visible(in:value))
        var earlier=value;earlier.half=change.proof.context.half
        XCTAssertFalse(change.visible(in:earlier))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
        var review=try XCTUnwrap(json["officialReview"] as? [String:Any]);var changes=try XCTUnwrap(review["changes"] as? [[String:Any]])
        changes[0]["appliedTotal"]=9999;review["changes"]=changes;json["officialReview"]=review
        let forged=try JSONDecoder().decode(CareerMatch.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertThrowsError(try forged.validateOfficialReviews())
    }
    func testPendingDiskReopenRollbackRetryAndCompletionOnceBothRoles() throws {
        enum Failure: Error { case injected }
        for role in PlayerRole.allCases {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("p12-review-"+UUID().uuidString+".store")
            let saved:(UUID,Data)=try autoreleasepool {
                let container=try CareerStore.makeContainer(url:url),context=container.mainContext
                var draft=PlayerDraft();draft.name="정정저장검증";draft.role=role;draft.schoolID="hs-ref-001"
                let player=try LegacyPlayerFixture.create(draft,schools:SchoolCatalog.load(),in:context)
                let calendar=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                try CalendarProgression.rest(player:player,state:calendar,revision:calendar.revision,in:context)
                let record=try CareerMatchStore.start(player:player,state:calendar,in:context)
                var value=try record.snapshot();XCTAssertEqual(value.officialReview?.version,1)
                // 독립 QA의 공/타구 고정 입력이다. 투구 좌표 원장은 별도 직접 입력 회귀에서 검증한다.
                value.pitchLog=nil
                try errorPlate(&value)
                XCTAssertNotNil(value.officialReview?.pending)
                record.payload=try JSONEncoder().encode(value);try context.save();_ = try record.snapshot()
                return (player.id,record.payload)
            }
            try autoreleasepool {
                let container=try CareerStore.makeContainer(url:url),context=container.mainContext
                let player=try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first { $0.id == saved.0 })
                let calendar=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == saved.0 })
                let record=try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first { $0.playerID == saved.0 })
                XCTAssertEqual(record.payload,saved.1);XCTAssertNotNil(try record.snapshot().officialReview?.pending)
                let revision=record.revision,day=player.gameDate,fatigue=player.fatigue
                XCTAssertThrowsError(try CareerMatchStore.advance(player:player,state:calendar,record:record,revision:revision,
                    input:.automatic,in:context,save:{_ in throw Failure.injected}))
                XCTAssertEqual(record.payload,saved.1);XCTAssertEqual(record.revision,revision)
                XCTAssertEqual(player.gameDate,day);XCTAssertEqual(player.fatigue,fatigue)
                try CareerMatchStore.advance(player:player,state:calendar,record:record,revision:revision,input:.automatic,in:context)
                let final=try record.snapshot();XCTAssertTrue(final.completed);XCTAssertNil(final.officialReview?.pending)
                XCTAssertGreaterThan(final.officialReview?.changes.count ?? 0,0)
                let payload=record.payload,chargedFatigue=player.fatigue
                XCTAssertThrowsError(try CareerMatchStore.advance(player:player,state:calendar,record:record,revision:record.revision,input:.automatic,in:context))
                XCTAssertEqual(record.payload,payload);XCTAssertEqual(player.fatigue,chargedFatigue)
            }
        }
    }
    func testReferenceEnvironmentSeparatesAppealAndOfficialReviewFromFrozenReports() throws {
        for role in PlayerRole.allCases {
            let position=role == .batter ? "SS":"P",values=PlayerArchetype.initial(for:role).values
            let old=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:91,home:true,tracked:true,
                battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1,fieldReviewVersion:1,specialRulesVersion:1)
            let current=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:91,home:true,tracked:true,
                battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1,fieldReviewVersion:1,
                specialRulesVersion:1,appealRulesVersion:1,officialReviewVersion:1)
            let environment=try XCTUnwrap(current.scoutingEnvironment)
            XCTAssertTrue(environment.contains("-appeal1-official1-"));XCTAssertNotEqual(old.scoutingEnvironment,environment)
            let reference=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:environment,role:role,position:position))
            try reference.validate();XCTAssertEqual(reference.environment,environment)
            XCTAssertNil(old.officialReview);XCTAssertNil(old.appealRulesVersion)
        }
    }

    func appealFixture() throws -> (MatchDetailedPlay,CareerMatch) {
        for distance in [15.0,25,35,50,65] {for direction in [-40.0,-20,0,20,40] {for flight in [1.85,2.5,3.8,5] {
            var before=CareerMatch(random:1,isHome:false,role:"league",appearance:false,contact:60,power:60,discipline:60,mastery:[:])
            before.outs=1;before.runnerProfiles=[.init(speed:100,id:"R1"),nil,.init(speed:100,id:"R3")]
            var ball=MatchBattedBall(kind:.line,quality:0.9,contact:70,power:60,speed:32,angle:10,direction:direction,distance:distance,flight:flight);ball.version=2
            let context=MatchSpecialContext(before:MatchPitchState(before),ball:ball,batter:.init(speed:60,id:"B1"),stats:nil,npc:nil,
                defending:false,ownBatter:false,discipline:["R1":0,"R3":0,"B1":60])
            guard var play=MatchAppealRules.resolve(context),let event=play.appeal,event.attempts.count == 2,
                  event.stages.contains(where:{$0.runs == 1}),play.runs == 0 else {continue}
            var saved=before;saved.half=1;saved.outs=0;saved.awayOrder=1;saved.runnerProfiles=[nil,nil,nil];saved.bases=[false,false,false]
            play.review?.after=MatchPitchState(saved)
            return (play,saved)
        }}}
        throw MatchError.invalidRecord
    }
    func testAppealDisplayReadsSavedStagesAndCannotRevealCancellationOrNextInningEarly() throws {
        let (play,saved)=try appealFixture(),event=try XCTUnwrap(play.appeal)
        try play.validate()
        let touch=try XCTUnwrap(event.stages.first {$0.runs == 1}),cancel=try XCTUnwrap(event.stages.first {$0.detail.contains("취소")})
        XCTAssertEqual(play.reviewDisplayMatch(at:touch.at-0.0001,saved:saved)?.awayScore,0)
        XCTAssertEqual(play.reviewDisplayMatch(at:touch.at+0.0001,saved:saved)?.awayScore,1)
        XCTAssertEqual(play.reviewDisplayMatch(at:cancel.at-0.0001,saved:saved)?.awayScore,1)
        XCTAssertEqual(play.reviewDisplayMatch(at:cancel.at+0.0001,saved:saved)?.awayScore,0)
        XCTAssertEqual(play.reviewDisplayMatch(at:cancel.at+0.0001,saved:saved)?.outs,3)
        XCTAssertEqual(play.reviewDisplayMatch(at:cancel.at+0.0001,saved:saved)?.half,play.half)
        XCTAssertEqual(play.reviewDisplayMatch(at:event.finalizedAt,saved:saved)?.half,1)
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let bytes=try encoder.encode(saved)
        for time in play.reviewDisplayTimes {_ = play.reviewDisplayMatch(at:time,saved:saved);_ = play.rulePhase(at:time)}
        XCTAssertEqual(try encoder.encode(saved),bytes)
    }
    func testCorrectionHistoryUsesFrozenTeamAndShowsInitialRecordDuringOldReplay() throws {
        var value=match(.batter);try errorPlate(&value)
        for _ in 0..<3 {InplayIntegrationTests().plate("삼진",in:&value)}
        let history=MatchGameHistory(match:value,fixtureID:value.playerRecords?.fixtureID,careerName:"내선수",homeName:"서울북악고",awayName:"한강청운고")
        let entry=try XCTUnwrap(history.innings.first?.away.entries.first)
        XCTAssertEqual(entry.result,"실책 출루");XCTAssertNotNil(entry.correction)
        XCTAssertEqual(entry.teamID,value.playerRecords?.away.teamID)
        var old=value;old.half=0
        let replay=MatchGameHistory(match:old,fixtureID:old.playerRecords?.fixtureID,careerName:"내선수",homeName:"서울북악고",awayName:"한강청운고")
        XCTAssertEqual(replay.innings.first?.away.entries.first?.result,"안타")
        XCTAssertNil(replay.innings.first?.away.entries.first?.correction)
    }
    func testNativeRuleAndCorrectionScreensSmallLargeAndReducedMotion() async throws {
        var value=match(.batter);try errorPlate(&value)
        for _ in 0..<3 {InplayIntegrationTests().plate("삼진",in:&value)}
        let history=MatchGameHistory(match:value,fixtureID:value.playerRecords?.fixtureID,careerName:"내선수",homeName:"서울북악고",awayName:"한강청운고")
        let correction=try XCTUnwrap(history.innings.first?.away.entries.first?.correction)
        var pending=match(.batter);try errorPlate(&pending)
        let pendingPlay=try XCTUnwrap(pending.fieldPlays?.last),pendingLabel=try XCTUnwrap(pending.officialLabel(for:pendingPlay))
        XCTAssertEqual(FieldReplayPresentation.resultTitle(pendingPlay,officialRecordLabel:pendingLabel),"포구 놓침")
        let pendingDetail=try XCTUnwrap(FieldReplayPresentation.errorDetail(pendingPlay,ownTeamFielding:true,officialRecordLabel:pendingLabel))
        XCTAssertTrue(pendingDetail.contains("공식 기록 검토 예정"));XCTAssertFalse(pendingDetail.contains("안타 제외"));XCTAssertFalse(pendingDetail.contains("실책 출루"))
        let (appeal,_)=try appealFixture()
        var scenes:[(String,MatchDetailedPlay,Double)]=[]
        for kind:MatchSpecialField.Kind in [.interference,.obstruction,.passing,.sharedBase] {
            let play=try XCTUnwrap(MatchSpecialRules.field(MatchSpecialPlayTests().fieldInput(kind)))
            let event=try XCTUnwrap(play.special)
            XCTAssertFalse(play.rulePhase(at:event.at-0.0001)?.contains("아웃") ?? false)
            XCTAssertNotNil(play.rulePhase(at:event.at+0.0001))
            scenes.append((kind.rawValue,play,event.at+0.001))
        }
        scenes.append(("correction-pending",pendingPlay,pendingPlay.duration))
        scenes.append(("appeal-provisional",appeal,try XCTUnwrap(appeal.appeal?.stages.first {$0.runs == 1}).at+0.001))
        scenes.append(("appeal-cancelled",appeal,try XCTUnwrap(appeal.appeal?.stages.first {$0.detail.contains("취소")}).at+0.001))
        for width in [320.0,390] {
            let large=width == 320
            for (name,play,time) in scenes {
                let view=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:time,reduceMotionOverride:true,playbackMode:.stills,canvasWidth:width-16,officialRecordLabel:name == "correction-pending" ? pendingLabel:nil,complete:{})
                    .dynamicTypeSize(large ? .accessibility5:.large)
                    .frame(width:width,height:800,alignment:.top)
                try await capture(view,name:"P12 \(name) \(Int(width))",width:width,height:800)
            }
            let card=ScrollView { MatchRecordCorrectionCard(value:correction) }.foregroundStyle(GameTheme.boardInk).background(GameTheme.boardPanel)
                .dynamicTypeSize(large ? .accessibility5:.large).frame(width:width,height:1000,alignment:.top)
            try await capture(card,name:"P12 correction card \(Int(width))",width:width,height:1000)
            let view=NavigationStack {MatchGameHistoryView(history:history)}.dynamicTypeSize(large ? .accessibility5:.large)
                .frame(width:width,height:844)
            try await capture(view,name:"P12 correction history \(Int(width))",width:width,height:844)
        }
    }
    private func capture<V:View>(_ view: V,name: String,width: Double,height: Double) async throws {
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
        let previous=scene.windows.first {$0.isKeyWindow},window=UIWindow(windowScene:scene)
        window.frame=CGRect(x:0,y:0,width:width,height:height);window.rootViewController=UIHostingController(rootView:view)
        window.makeKeyAndVisible();defer {window.isHidden=true;previous?.makeKey()}
        window.rootViewController?.view.layoutIfNeeded();try await Task.sleep(for:.seconds(1.2))
        let image=UIGraphicsImageRenderer(bounds:window.bounds).image {_ in
            XCTAssertTrue(window.drawHierarchy(in:window.bounds,afterScreenUpdates:true))
        }
        XCTAssertEqual(image.size.width,width)
        let attachment=XCTAttachment(image:image);attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }

    func testDetailedPlayCopiesKeepOriginalAndFlatLegacyJSON() async throws {
        let original=try XCTUnwrap(MatchSpecialRules.field(MatchSpecialPlayTests().fieldInput(.interference)))
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let before=try encoder.encode(original)
        var copy=original;copy.version=4;copy.review?.eventID="copy-only";copy.runners[0].out.toggle()
        XCTAssertNotEqual(copy,original)
        XCTAssertEqual(try encoder.encode(original),before)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:before) as? [String:Any])
        XCTAssertNil(object["storage"]);XCTAssertNil(object["value"])
        var legacy=object;legacy.removeValue(forKey:"appeal")
        XCTAssertEqual(try JSONDecoder().decode(MatchDetailedPlay.self,from:JSONSerialization.data(withJSONObject:legacy)),original)
        let versions=await withTaskGroup(of:Int.self) { group in
            for index in 1...8 {group.addTask {var fork=original;fork.version=index;return fork.version}}
            var result:[Int]=[];for await version in group {result.append(version)};return result.sorted()
        }
        XCTAssertEqual(versions,Array(1...8));XCTAssertEqual(try encoder.encode(original),before)
    }
    func testBackgroundCalculationAndEveryPitchKeepBoundedOuts() async throws {
        for role in PlayerRole.allCases {
            let initial=match(role)
            let final = try await Task.detached {
                var games=0
                for seed in 1...16 {
                    var value=initial;value.random=UInt64(seed)
                    while !value.completed {
                        guard (0...2).contains(value.outs) else {throw MatchError.invalidRecord}
                        value.step(role == .pitcher ? .pitch:.swing,pitchCode:"four-seam")
                        guard (0...2).contains(value.outs) else {throw MatchError.invalidRecord}
                        try value.playerRecords?.validate(match:value)
                    }
                    try value.validateDetailedField();try value.validateRunning();games += 1
                }
                return games
            }.value
            XCTAssertEqual(final,16)
        }
    }
    func testPrepareP12NormalEntryFixtures() throws {
        var evidence:[[String:Any]]=[]
        for (index,kind) in ["appeal","correction"].enumerated() {
            let session=String(format:"B012B012-2026-4126-8000-%012d",index+1)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("live-career-"+session+".store")
            for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:url.path+suffix)}
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            var draft=PlayerDraft();draft.name="어필정정검증";draft.role = .pitcher;draft.schoolID="hs-ref-001"
            let player=try LegacyPlayerFixture.create(draft,schools:SchoolCatalog.load(),in:context)
            let calendar=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            try CalendarProgression.rest(player:player,state:calendar,revision:calendar.revision,in:context)
            let record=try CareerMatchStore.start(player:player,state:calendar,in:context)
            let ready=try record.snapshot();XCTAssertTrue(ready.ownPitcherActive && !ready.offense)
            print("P12_FIXTURE_READY",kind)
            var selected:(CareerMatch,CareerMatch,MatchDetailedPlay,UInt64)?
            for seed in UInt64(1)...200 where selected == nil {
                var before=ready;before.random=seed &* 1_099_511_628_211
                for _ in 0..<100 where !before.completed && before.half == ready.half && before.ownPitcherActive && !before.offense {
                    var after=before
                    try after.advance(.pitch,pitchCode:"four-seam",control:.init(release:0))
                    let field=after.fieldPlays?.dropFirst(before.fieldPlays?.count ?? 0).first {
                        $0.half == before.half && $0.order == (before.half % 2 == 1 ? before.homeOrder:before.awayOrder)
                    }
                    if let field {
                        let valid=kind == "appeal" ? field.appeal != nil
                            : after.officialReview?.pending?.inputs.contains(where:{ input in
                                if case .plate(let value)=input {return value.deferred && !value.deferredAssists.isEmpty && value.context.half == field.half && value.context.order == field.order};return false
                            }) == true
                        if valid {
                            do {
                                print("P12_FIXTURE_FOUND",kind,seed,field.eventID)
                                try after.playerRecords?.validate(match:after)
                                print("P12_FIXTURE_RECORDS_OK",kind)
                                try after.validateDetailedField()
                            } catch {
                                let a=XCTAttachment(data:try JSONEncoder().encode(after),uniformTypeIdentifier:"public.json")
                                a.name="P12 fixture invalid "+kind;a.lifetime = .keepAlways;add(a)
                                throw error
                            }
                            if kind == "correction" {
                                let proof=try XCTUnwrap(after.officialReview?.pending?.inputs.compactMap { input -> MatchReviewPlate? in
                                    if case .plate(let value)=input, value.deferred {return value};return nil
                                }.first)
                                XCTAssertFalse(proof.deferredAssists.isEmpty,"송구 후 포구 실수의 보살도 정정 전까지 보류한다.")
                                var final=after;try final.advance(.automatic)
                                try final.playerRecords?.validate(match:final);try final.validateDetailedField()
                                let correction=try XCTUnwrap(final.officialReview?.changes.first {$0.id == field.eventID})
                                XCTAssertEqual(correction.proof.deferredAssists,proof.deferredAssists)
                                let defense=field.half % 2 == 0 ? final.playerRecords?.home:final.playerRecords?.away
                                for id in proof.deferredAssists {XCTAssertGreaterThanOrEqual(defense?.fielding?.first {$0.id == id}?.assists ?? 0,1)}
                            }
                            selected=(before,after,field,seed);break
                        }
                    }
                    before=after
                }
            }
            let found=try XCTUnwrap(selected,"실제 일반 투구 입력으로 "+kind+" 장면을 찾는다")
            record.payload=try JSONEncoder().encode(found.0);try context.save()
            print("P12_FIXTURE_SAVING",kind)
            _ = try record.snapshot()
            evidence.append(["session":session,"kind":kind,"role":"pitcher","seed":found.3,"half":found.2.half,
                             "event":found.2.eventID,"summary":found.2.summary,"scope":"unchanged saved abilities; native normal pitch input; no forced outcome"])
        }
        let a=XCTAttachment(data:try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]),uniformTypeIdentifier:"public.json")
        a.name="P12 normal entry fixtures";a.lifetime = .keepAlways;add(a)
    }

}
