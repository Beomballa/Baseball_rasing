import XCTest
import SwiftUI
import SpriteKit
import SwiftData
@testable import BM

final class MatchFieldReviewTests: XCTestCase {
    func testDroppedFlyAtRoundedEndpointPreservesFlightAndLegacyPayload() throws {
        let flight=3.6288997203302324
        var shot=MatchBattedBall(version:2,kind:.fly,quality:0.6816221607064965,contact:53,power:45,
            speed:30.274766306644693,angle:36.01097666100137,direction:-10.193616388786452,
            distance:63.986071359016414,flight:flight)
        shot.firstBounceAt=flight;shot.firstBounceDistance=shot.distance
        let oldTimes=Array(Set((0...24).map {flight*Double($0)/24}+[flight])).sorted()
        XCTAssertGreaterThan(try XCTUnwrap(oldTimes.last),flight)
        XCTAssertEqual(shot.nodes.last?.at,flight)
        XCTAssertEqual(shot.nodes.filter {$0.at == flight}.count,1)
        XCTAssertTrue(shot.nodes.allSatisfy {$0.at <= flight})
        var legacy=shot;legacy.version=1
        XCTAssertEqual(legacy.nodes.map(\.at),oldTimes)

        var clean=DetailedFieldRules.resolveFly(half:3,order:6,landing:shot.landing,flight:flight,
            runners:[nil,nil,nil],batter:.init(speed:37),outs:0,stats:nil,defending:false,ownBatter:false,relayEnabled:true)
        XCTAssertEqual(clean.fly?.caught,true)
        clean.version=5;clean.battedBall=shot;clean.review = .init()
        let tail=clean.ball.filter {$0.at > flight}
        clean.ball=shot.nodes+tail
        try clean.validate()
        func drop(_ original:MatchDetailedPlay) -> MatchDetailedPlay {
            var result=FieldMisplayRules.applying(to:original,stats:nil,defending:false,
                draws:[0,0.999999,0.999999,0.999999,0.999999,0.999999,0.999999])
            result.battedBall=shot;result.review=original.review
            return result
        }
        let result=drop(clean)
        XCTAssertEqual(result.misplay?.stage,0)
        XCTAssertEqual(result.outsAdded,0)
        XCTAssertNotNil(result.afterRunners[0])
        try result.validate()

        // 이전에 저장한 중복 끝점 경로도 데이터 변경 없이 검증한다.
        var savedClean=clean
        savedClean.ball=oldTimes.map {FieldNode(at:$0,point:shot.point(at:$0))}+tail
        try savedClean.validate()
        let savedDrop=drop(savedClean)
        XCTAssertEqual(savedDrop,result)
        let payload=try JSONEncoder().encode(savedDrop)
        let reopened=try JSONDecoder().decode(MatchDetailedPlay.self,from:payload)
        XCTAssertEqual(reopened,savedDrop)
        try reopened.validate()
        var corrupt=reopened
        corrupt.ball[3]=FieldNode(at:corrupt.ball[3].at,point:.init(x:999,y:999))
        XCTAssertThrowsError(try corrupt.validate())
    }

    private func ball(direction:Double,distance:Double,bounce:Double=0.25,first:Double=5,kind:MatchBattedBall.Kind = .ground) -> MatchBattedBall {
        var value=MatchBattedBall(version:2,kind:kind,quality:0.8,contact:70,power:70,speed:35,angle:kind.airborne ? 30:0,
            direction:direction,distance:distance,flight:5)
        value.firstBounceAt=bounce;value.firstBounceDistance=first;return value
    }
    private func match(_ occupied:[Bool]=[true,false,false],power:Double=70) -> CareerMatch {
        var m=CareerMatch(random:8,isHome:false,role:"batter",appearance:true,contact:70,power:power,discipline:70,mastery:[:])
        m.half=0;m.outs=1;m.balls=1;m.strikes=1;m.fieldReviewVersion=1;m.detailedFieldVersion=5;m.battedBallVersion=1
        m.fieldPlays=[];m.runnerProfiles=occupied.enumerated().map {$0.element ? .init(speed:70,responsiblePitcher:"P-original",id:"R\($0.offset+1)"):nil}
        m.bases=occupied;m.pitchEvents = .init();return m
    }
    private var batter:FieldRunnerProfile {.init(speed:70,own:true,responsiblePitcher:"P-current",id:"B")}

    func testThirdBaseContactRemainsFairAndShortFoulStopsBeforeBase() throws {
        let fair=ball(direction:-45,distance:55)
        let foul=ball(direction:-52,distance:20)
        let ruling=try XCTUnwrap(FieldReviewRules.ruling(fair))
        XCTAssertEqual(ruling.kind,.fairBase)
        XCTAssertLessThan(ruling.point.distance(to:DetailedFieldRules.bases[3]),0.46)
        let outside=try XCTUnwrap(FieldReviewRules.ruling(foul))
        XCTAssertEqual(outside.kind,.foul)
        XCTAssertLessThan(outside.point.y,DetailedFieldRules.bases[3].y)
    }
    func testFenceDistinguishesFirstBounceFromAirborneCrossing() throws {
        let bounced=ball(direction:0,distance:125,bounce:3.2,first:98,kind:.fly)
        let direct=ball(direction:0,distance:140,bounce:4.7,first:130,kind:.fly)
        let ruling=try XCTUnwrap(FieldReviewRules.ruling(bounced))
        XCTAssertEqual(ruling.kind,.groundRuleDouble)
        XCTAssertLessThan(try XCTUnwrap(ruling.bounceAt),ruling.at)
        XCTAssertEqual(ruling.point.y,110,accuracy:0.000001)
        XCTAssertTrue(FieldReviewRules.isHomeRun(direct))
        XCTAssertNil(FieldReviewRules.ruling(direct))
    }
    func testExistingHomeRunVerdictKeepsRNGAndOutcomeWithSavedFenceTrajectory() throws {
        for seed in UInt64(1)...256 {
            var m=match([true,true,false],power:90);m.random=seed
            var old=m;old.fieldReviewVersion=nil
            old.endPlate("홈런",batter:true,pitcher:false,battingQuality:0.9,offsetY:-0.4)
            m.endPlate("홈런",batter:true,pitcher:false,battingQuality:0.9,offsetY:-0.4)
            try m.validateDetailedField();try m.validateHomeRuns()
            let homeRun=try XCTUnwrap(m.homeRuns?.last),original=try XCTUnwrap(old.homeRuns?.last)
            XCTAssertTrue(FieldReviewRules.isHomeRun(try XCTUnwrap(homeRun.trajectory)))
            XCTAssertNotNil(homeRun.review?.after);XCTAssertEqual(m.random,old.random);XCTAssertEqual(m.line,old.line)
            XCTAssertEqual(m.homeScore,old.homeScore);XCTAssertEqual(m.awayScore,old.awayScore)
            XCTAssertEqual(homeRun.distance,original.distance);XCTAssertEqual(homeRun.flight,original.flight)
            for time in [0,homeRun.flight/2,homeRun.flight] {
                XCTAssertLessThan(homeRun.ball(at:time).distance(to:original.ball(at:time)),0.0000001)
            }
        }
    }
    func testTwoBaseAwardsUsePitchTimeOriginsForAllOccupanciesAndKeepResponsibility() throws {
        let shot=ball(direction:0,distance:125,bounce:3.2,first:98,kind:.fly)
        for mask in 0..<8 {
            let occupied=(0..<3).map {mask & (1 << $0) != 0},m=match(occupied)
            for kind in [MatchFieldRuling.Kind.groundRuleDouble,.overthrow] {
                let ruling=kind == .groundRuleDouble ? try XCTUnwrap(FieldReviewRules.ruling(shot))
                    : MatchFieldRuling(kind:kind,at:3,point:.init(x:25,y:8))
                let p=FieldReviewRules.award(match:m,ball:shot,ruling:ruling,batter:batter)
                try p.validate()
                XCTAssertEqual(p.outsAdded,0);XCTAssertEqual(p.afterRunners[0],nil)
                XCTAssertEqual(p.afterRunners[1]?.id,"B")
                XCTAssertEqual(p.afterRunners[2]?.id,occupied[0] ? "R1":nil)
                XCTAssertEqual(p.runs,occupied.dropFirst().filter {$0}.count)
                XCTAssertEqual(p.runners.first(where:{$0.from == 1})?.profile.responsiblePitcher,occupied[0] ? "P-original":nil)
                XCTAssertEqual(p.rbi,kind == .overthrow ? 0:p.runs)
                XCTAssertTrue(p.runners.filter {$0.destination > $0.from}.allSatisfy {r in
                    ((r.from+1)...r.destination).allSatisfy {r.arrival(at:$0) != nil}
                })
            }
        }
    }
    @MainActor func testWideProjectionMatchesBagsAndShowsFoulTerritory() throws {
        let image=try XCTUnwrap(InplayStadiumArt.image)
        XCTAssertEqual(image.size,CGSize(width:1536,height:1024))
        for width in [320.0,390,430] {
            let size=CGSize(width:width,height:width*2/3)
            for (base,x,y) in [(0,0.499,0.792),(1,0.722,0.541),(2,0.499,0.441),(3,0.276,0.541)] {
                let point=InplayFieldProjection.point(DetailedFieldRules.bases[base],size:size)
                XCTAssertEqual(point.x/width,x,accuracy:0.00001);XCTAssertEqual(point.y/size.height,y,accuracy:0.00001)
            }
            let rubber=InplayFieldProjection.point(.init(x:0,y:18),size:size)
            XCTAssertEqual(rubber.y/size.height,0.5535,accuracy:0.00001)
            for point in DetailedFieldRules.positions + [.init(x:25,y:8),.init(x:-26,y:19)] {
                let screen=InplayFieldProjection.point(point,size:size)
                XCTAssertTrue(CGRect(origin:.zero,size:size).contains(screen))
            }
        }
    }
    @MainActor func testPastInplayBoardDoesNotRevealLaterInningRunsOrHits() throws {
        var m=InplayIntegrationTests().makeMatch()
        m.enablePitchEvents();m.enableRunning();m.enableFieldReview()
        try m.advance(.automatic)
        XCTAssertTrue(m.completed)
        let saved=m,trace=try XCTUnwrap(m.playerRecords?.plateTrace)
        let plays=try XCTUnwrap(m.fieldPlays);XCTAssertFalse(plays.isEmpty)
        for play in plays {
            for time in [0,play.duration] {
                let view=try XCTUnwrap(play.reviewDisplayMatch(at:time,saved:m))
                for home in [true,false] {
                    let order=home ? view.homeOrder:view.awayOrder
                    let hits=trace.filter {$0.battingHome == home && $0.order < order && ["안타","2루타","3루타","홈런"].contains($0.result)}.count
                    XCTAssertEqual(MatchBroadcastData.hits(view,home:home),hits)
                    var total=0
                    for inning in 1...9 {
                        let mark=MatchBroadcastData.inningMark(view,home:home,inning:inning)
                        if (inning-1)*2+(home ? 1:0) > view.half {XCTAssertEqual(mark,"·")}
                        total += Int(mark) ?? 0
                    }
                    XCTAssertEqual(total,home ? view.homeScore:view.awayScore)
                }
            }
        }
        XCTAssertEqual(m,saved,"표시 보정은 원래 원장을 변경하지 않는다.")
    }
    @MainActor func testDoublePlayShowsSecondOutBeforeThirdAndReplayDoesNotWrite() throws {
        var m=match();m.runnerProfiles?[0] = .init(speed:35,id:"R1")
        var p=DetailedFieldRules.resolve(half:0,order:0,landing:.init(x:-8,y:31),flight:1,
            runners:m.runnerProfiles!,batter:.init(speed:35,own:true,id:"B"),outs:1,stats:nil,defending:false,
            ownBatter:true,doublePlayEnabled:true,groundBall:true,relayEnabled:true,continuationEnabled:true)
        p.review?.before=MatchPitchState(m)
        m.completePlate(initial:"범타",result:"범타",batter:true,pitcher:false,newRunner:batter,detailed:p)
        p.review?.after=MatchPitchState(m)
        let second=try XCTUnwrap(p.secondThrow),saved=m
        XCTAssertEqual(p.outsAdded,2)
        let first=try XCTUnwrap(p.reviewDisplayMatch(at:p.controlAt+0.001,saved:m))
        XCTAssertEqual(first.half,0);XCTAssertEqual(first.outs,2)
        let beforeThird=try XCTUnwrap(p.reviewDisplayMatch(at:second.controlAt-0.001,saved:m))
        XCTAssertEqual(beforeThird.half,0);XCTAssertEqual(beforeThird.outs,2)
        let third=try XCTUnwrap(p.reviewDisplayMatch(at:second.controlAt+0.001,saved:m))
        XCTAssertEqual(third.half,1);XCTAssertEqual(third.outs,0)
        for time in [0,p.duration,p.controlAt,p.duration] {_ = p.reviewDisplayMatch(at:time,saved:m)}
        XCTAssertEqual(m,saved)
    }
    @MainActor func testGroundRuleDoubleWaitsForFenceAndHomeTouchAndRejectsForgedAfter() throws {
        var m=match([true,true,false])
        let shot=ball(direction:0,distance:125,bounce:3.2,first:98,kind:.fly)
        let ruling=try XCTUnwrap(FieldReviewRules.ruling(shot))
        var play=FieldReviewRules.award(match:m,ball:shot,ruling:ruling,batter:batter)
        m.completePlate(initial:"안타",result:"2루타",batter:true,pitcher:false,newRunner:batter,detailed:play)
        play.review?.after=MatchPitchState(m)
        try play.validate()
        XCTAssertFalse(FieldReplayPresentation.phase(play,time:ruling.at-0.001,finished:false).contains("인정"))
        let touch=try XCTUnwrap(play.runners.first(where:{$0.from == 2})?.arrival)
        XCTAssertEqual(play.reviewDisplayMatch(at:touch-0.001,saved:m)?.awayScore,0)
        XCTAssertEqual(play.reviewDisplayMatch(at:touch+0.001,saved:m)?.awayScore,1)
        var corrupt=m;corrupt.awayScore += 99
        play.review?.after=MatchPitchState(corrupt)
        XCTAssertThrowsError(try play.validate())
    }
    @MainActor func testShortTraceUsesPastOfCurrentThrowAndDisappearsWhileHeld() throws {
        let p=DetailedFieldRules.resolve(half:0,order:0,landing:.init(x:-8,y:31),flight:1,
            runners:[nil,nil,nil],batter:batter,outs:0,stats:nil,defending:false,ownBatter:true)
        let size=CGSize(width:390,height:260),replay=InplayReplay.field(p)
        XCTAssertTrue(InplayBallTrail.points(replay:replay,time:0,size:size,leftIndex:nil).isEmpty)
        XCTAssertTrue(InplayBallTrail.points(replay:replay,time:(p.pickupAt+p.releaseAt)/2,size:size,leftIndex:nil).isEmpty)
        let time=(p.releaseAt+p.ballAt)/2
        let points=InplayBallTrail.points(replay:replay,time:time,size:size,leftIndex:nil)
        XCTAssertGreaterThan(points.count,1)
        XCTAssertEqual(points.last,replay.ballPoint(time:time,size:size,leftIndex:nil))
        let length=zip(points,points.dropFirst()).reduce(0.0) {$0+hypot($1.1.x-$1.0.x,$1.1.y-$1.0.y)}
        XCTAssertLessThanOrEqual(length,size.width*0.1)
        XCTAssertTrue(InplayBallTrail.points(replay:replay,time:p.duration,size:size,leftIndex:nil).isEmpty)
    }
    func testFoulReturnsOriginalRunnersAndHasNoFakePlateAppearance() throws {
        var found:CareerMatch?
        for seed in UInt64(1)...500 {
            var m=match();m.random=seed
            m.endPlate("범타",batter:true,pitcher:false,battingQuality:0.8,offsetX:-0.7,offsetY:-0.3)
            if m.pitchEvents?.events.last?.play?.review?.ruling?.kind == .foul {found=m;break}
        }
        let m=try XCTUnwrap(found),event=try XCTUnwrap(m.pitchEvents?.events.last),play=try XCTUnwrap(event.play)
        XCTAssertEqual(m.homeOrder+m.awayOrder,0);XCTAssertEqual(m.line.plateAppearances,0)
        XCTAssertEqual(m.strikes,2);XCTAssertEqual(m.outs,1);XCTAssertEqual(m.bases,[true,false,false])
        XCTAssertEqual(play.runners.first(where:{$0.from == 1})?.nodes.last?.point,DetailedFieldRules.bases[1])
        XCTAssertEqual(play.eventID,event.id)
        try play.validate();try m.validatePitchEvents()
    }
    func testSafeSecondCanHoldOrThrowToFirstWithoutInventingForceOut() throws {
        var held:MatchDetailedPlay?,thrown:MatchDetailedPlay?
        for flight in stride(from:1.0,through:3.5,by:0.05) {
            for speed in [30.0,70,100] {
                let play=DetailedFieldRules.resolve(half:0,order:0,landing:.init(x:-8,y:31),flight:flight,
                    runners:[.init(speed:100),nil,nil],batter:.init(speed:speed),outs:1,stats:nil,defending:false,
                    ownBatter:true,doublePlayEnabled:true,groundBall:true,relayEnabled:true,continuationEnabled:true)
                if play.review?.heldAtSecond == true {held=play}
                if !play.out,play.secondThrow?.out == true {thrown=play}
            }
        }
        let hold=try XCTUnwrap(held),next=try XCTUnwrap(thrown)
        try hold.validate();try next.validate()
        XCTAssertEqual(hold.outsAdded,0);XCTAssertEqual(hold.afterRunners.map {$0 != nil},[true,true,false])
        XCTAssertEqual(next.outsAdded,1);XCTAssertEqual(next.afterRunners.map {$0 != nil},[false,true,false])
        XCTAssertFalse(next.runners.first(where:{$0.from == 1})!.out)
    }
    @MainActor func testNewRulesCompleteBothRolesAndHomeSidesWithValidSavedLedgers() throws {
        for role in [PlayerRole.batter,.pitcher] {for home in [false,true] {for seed in UInt64(1)...8 {
            var m=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? "SS":"P",
                values:PlayerArchetype.choices(for:role)[0].values,seed:seed,home:home,tracked:true,
                battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1,fieldReviewVersion:1)
            var attempts=0
            while !m.completed {
                if m.canPrepareRunning {try m.advanceRunning()} else {try m.advance(.automatic)}
                attempts += 1;XCTAssertLessThan(attempts,2000)
            }
            do {
                try m.validateDetailedField();try m.validatePitchEvents();try m.validateRunning()
                try m.playerRecords?.validate(match:m);try m.scoutingPerformance?.validate(line:m.line,role:role)
            } catch {XCTFail("role=\(role) home=\(home) seed=\(seed) error=\(error)");throw error}
            let data=try JSONEncoder().encode(m),copy=try JSONDecoder().decode(CareerMatch.self,from:data)
            XCTAssertEqual(m,copy)
        }}}
    }

    @MainActor func testPrepareP09P10NormalEntryFixtures() throws {
        var evidence:[[String:Any]]=[]
        for (index,kind) in ["normal","foul","groundRuleDouble","overthrow"].enumerated() {
            let session=String(format:"B009B010-2026-4125-8000-%012d",index+1)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("live-career-"+session+".store")
            for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:url.path+suffix)}
            let container=try CareerStore.makeContainer(url:url),context=container.mainContext
            var draft=PlayerDraft();draft.name="수비경계검증";draft.role = .pitcher;draft.schoolID="hs-ref-001"
            let player=try LegacyPlayerFixture.create(draft,schools:SchoolCatalog.load(),in:context)
            let calendar=try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
            try CalendarProgression.rest(player:player,state:calendar,revision:calendar.revision,in:context)
            let record=try CareerMatchStore.start(player:player,state:calendar,in:context)
            var ready=try record.snapshot()
            XCTAssertTrue(ready.ownPitcherActive && !ready.offense)
            // 경계 커버리지를 위한 별도 QA 능력 입력이다. 실제 사용자나 제품의 생성 규칙은 바꾸지 않는다.
            if ready.half.isMultiple(of:2) {
                for i in ready.npcAttack?.away.batters.indices ?? 0..<0 {ready.npcAttack?.away.batters[i].power=90}
            } else {
                for i in ready.npcAttack?.home.batters.indices ?? 0..<0 {ready.npcAttack?.home.batters[i].power=90}
            }
            if let fielders=ready.npcFielders,let attack=ready.npcAttack {
                ready.runnerManagement = .init(home:.make(team:fielders.home,attack:attack.home),
                                               away:.make(team:fielders.away,attack:attack.away))
            }
            try ready.playerRecords?.validate(match:ready)
            var selected:(CareerMatch,CareerMatch,MatchDetailedPlay)?
            for seed in UInt64(1)...20_000 where selected == nil {
                var before=ready;before.random=seed &* 1_099_511_628_211
                var after=before
                try after.advance(.pitch,pitchCode:"four-seam",control:ManualMatchInput(release:0))
                let pitch=after.lastManual?.pitchEventSequence.flatMap {seq in after.pitchEvents?.events.first(where:{$0.sequence == seq})?.play}
                let field=pitch ?? after.fieldPlays?.dropFirst(before.fieldPlays?.count ?? 0).first(where:{$0.half == before.half && $0.order == (before.half.isMultiple(of:2) ? before.awayOrder:before.homeOrder)})
                guard let field else {continue}
                let ruling=field.review?.ruling?.kind
                let matches=kind == "normal" ? field.review != nil && ruling == nil
                    : kind == "foul" ? ruling == .foul
                    : kind == "groundRuleDouble" ? ruling == .groundRuleDouble:ruling == .overthrow
                if matches {
                    let checks:[(String,() throws -> Void)]=[
                        ("field",{try field.validate()}),("matchField",{try after.validateDetailedField()}),
                        ("pitchEvents",{try after.validatePitchEvents()}),
                        ("trace",{try after.playerRecords?.validatePlateTrace(match:after)}),
                        ("earned",{try after.playerRecords?.earned?.validate(match:after)}),
                        ("fielding",{
                            if let records=after.playerRecords,let source=MatchPlayerRecords.make(match:after,careerID:records.careerID,fixtureID:records.fixtureID) {
                                try records.home.validateFielding(against:source.home)
                                try records.away.validateFielding(against:source.away)
                            }
                        }),
                        ("records",{try after.playerRecords?.validate(match:after)})
                    ]
                    for (name,check) in checks {
                        do {try check()} catch {
                            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                            let attachment=XCTAttachment(data:try encoder.encode(field),uniformTypeIdentifier:"public.json")
                            attachment.name="P09 fixture failure \(kind) seed \(seed) \(name)";attachment.lifetime = .keepAlways;add(attachment)
                            let state=XCTAttachment(data:try encoder.encode(after),uniformTypeIdentifier:"public.json")
                            state.name="P09 fixture failed match";state.lifetime = .keepAlways;add(state)
                            XCTFail("QA 후보 \(kind) seed \(seed) / \(name)");throw error
                        }
                    }
                    selected=(before,after,field)
                }
            }
            let source=try XCTUnwrap(selected,"일반 투구 입력에서 "+kind+" 조건을 찾는다.")
            record.payload=try JSONEncoder().encode(source.0);try context.save();_ = try record.snapshot()
            evidence.append(["session":session,"kind":kind,"role":"pitcher","opponentPower":90,"release":0,
                             "fixture":record.fixtureID,"before":source.0.inningLabel,"event":source.2.eventID,
                             "result":source.2.summary,"scope":"independent QA controlled abilities; native production rules; normal UI pitch input"])
        }
        let attachment=XCTAttachment(data:try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]),uniformTypeIdentifier:"public.json")
        attachment.name="P09 P10 native entry fixtures";attachment.lifetime = .keepAlways;add(attachment)
    }

    @MainActor func testReviewEnvironmentSeparatesReferencesAndOldPendingStaysNil() throws {
        for role in PlayerRole.allCases {
            let position=role == .batter ? "SS":"P",values=PlayerArchetype.initial(for:role).values
            var old=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:91,home:true,
                tracked:true,battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1)
            let current=ScoutingReferenceSimulation.fixture(role:role,position:position,values:values,seed:91,home:true,
                tracked:true,battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1,fieldReviewVersion:1)
            let oldEnvironment=try XCTUnwrap(old.scoutingEnvironment),environment=try XCTUnwrap(current.scoutingEnvironment)
            XCTAssertNotEqual(environment,oldEnvironment);XCTAssertTrue(environment.contains("-review1-"))
            let frozen=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:oldEnvironment,role:role,position:position))
            let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
            let bytes=try encoder.encode(frozen)
            let reference=try XCTUnwrap(ScoutingReferenceSimulation.make(environment:environment,role:role,position:position))
            try reference.validate();XCTAssertEqual(reference.environment,environment)
            XCTAssertEqual(try encoder.encode(frozen),bytes)
            try old.advance(.automatic)
            let payload=try JSONEncoder().encode(old)
            var reopened=try JSONDecoder().decode(CareerMatch.self,from:payload)
            reopened.enableFieldReview();XCTAssertEqual(reopened,old);XCTAssertNil(reopened.fieldReviewVersion)
        }
    }

    @MainActor func testHighPowerNPCCompleteGamesKeepConsistentReserveAndOfficialRecords() throws {
        for role in PlayerRole.allCases {for seed in UInt64(1)...8 {
            var m=ScoutingReferenceSimulation.fixture(role:role,position:role == .batter ? "SS":"P",
                values:PlayerArchetype.initial(for:role).values,seed:seed,home:seed.isMultiple(of:2),tracked:true,
                battedBallVersion:1,npcFieldersVersion:1,npcAttackVersion:2,pitchEventsVersion:1,runningVersion:1,fieldReviewVersion:1)
            for i in 0..<9 {m.npcAttack?.home.batters[i].power=90;m.npcAttack?.away.batters[i].power=90}
            if let fielders=m.npcFielders,let attack=m.npcAttack {
                m.runnerManagement = .init(home:.make(team:fielders.home,attack:attack.home),away:.make(team:fielders.away,attack:attack.away))
            }
            try m.advance(.automatic)
            XCTAssertTrue(m.completed);try m.validateDetailedField();try m.playerRecords?.validate(match:m)
            try m.validatePitchEvents();try m.validateRunning()
        }}
    }

    @MainActor func testActualWideSceneAndRulingViewsUseOneProjection() async throws {
        var m=match([true,true,false])
        let shot=ball(direction:0,distance:125,bounce:3.2,first:98,kind:.fly)
        let ruling=try XCTUnwrap(FieldReviewRules.ruling(shot))
        var play=FieldReviewRules.award(match:m,ball:shot,ruling:ruling,batter:batter)
        m.completePlate(initial:"안타",result:"2루타",batter:true,pitcher:false,newRunner:batter,detailed:play)
        play.review?.after=MatchPitchState(m)
        let saved=m
        for width in [320.0,390] {for large in [false,true] {
            let view=DetailedFieldReplayBoard(play:play,appearance:PlayerAppearance(),previewTime:play.duration,
                canvasWidth:width-16,complete:{})
                .dynamicTypeSize(large ? .accessibility5:.large).frame(width:width,height:800,alignment:.top)
            let host=UIHostingController(rootView:view),window=UIWindow(frame:CGRect(x:0,y:0,width:width,height:800))
            window.rootViewController=host;window.makeKeyAndVisible()
            host.view.frame=window.bounds;host.view.layoutIfNeeded()
            try await Task.sleep(for:.seconds(1.2))
            let renderer=UIGraphicsImageRenderer(bounds:host.view.bounds)
            let image=renderer.image {_ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true)}
            let attachment=XCTAttachment(image:image);attachment.name="P09 P10 wide component \(Int(width)) \(large ? "large":"normal")";attachment.lifetime = .keepAlways;add(attachment)
            window.isHidden=true;window.rootViewController=nil
        }}
        let sprites=FieldReplaySprites(appearance:PlayerAppearance(),jerseyNumber:27,ownPosition:"P",throwingHand:"left",ownTeamFielding:true)
        let replay=InplayReplay.field(play)
        let planned=await sprites.requests(duration:replay.duration,reduced:false,actorsAt:{replay.actors(sprites,time:$0,reduced:false,finished:false)})
        let requests=try XCTUnwrap(planned)
        let prepared=await FieldRasterArt.prepare(requests)
        let images=try XCTUnwrap(prepared)
        let scene=InplayFieldScene(replay:replay,sprites:sprites,prepared:images,scoreText:"H 0 : 1 A",stadium:.legacy)
        await scene.preload()
        let sk=SKView(frame:CGRect(x:0,y:0,width:600,height:400));sk.presentScene(scene)
        for time in [0,ruling.at-0.001,ruling.at,play.duration] {
            scene.display(time:time,finished:time>=play.duration)
            XCTAssertEqual(m,saved)
        }
        let png=UIImage(cgImage:try XCTUnwrap(sk.texture(from:scene)?.cgImage()))
        let attachment=XCTAttachment(image:png);attachment.name="P09 P10 wide SpriteKit ground rule double";attachment.lifetime = .keepAlways;add(attachment)
        sk.presentScene(nil)
    }
}
