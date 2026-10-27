import XCTest
import SpriteKit
import UIKit
import SwiftData
import SwiftUI
@testable import BM

@MainActor final class ManualMatchTests: XCTestCase {
    func testV27InningScoreStatesDistinguishZeroFutureSkippedAndLegacy() throws {
        var game = match(); game.half = 0
        var scores = MatchInningScores()
        game.inningScores = scores
        try scores.validate(match: game)
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: false, inning: 1), "0")
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: true, inning: 1), "·")
        scores.record(runs: 2, half: 0); scores.enter(half: 1)
        game.half = 1; game.awayScore = 2; game.inningScores = scores
        try scores.validate(match: game)
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: false, inning: 1), "2")
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: true, inning: 1), "0")
        game.inningScores = nil
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: false, inning: 1), "—")
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: true, inning: 9), "—")
    }

    func testV27NinthInningSkippedWalkoffAndTieRemainDifferent() throws {
        var game = match(); game.completed = true; game.half = 17
        var scores = MatchInningScores()
        for half in 1...16 { scores.enter(half: half) }
        scores.record(runs: 2, half: 1)
        game.homeScore = 2; game.inningScores = scores
        try scores.validate(match: game)
        XCTAssertNil(scores.home[8])
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: true, inning: 9), "X")
        scores.enter(half: 17); scores.record(runs: 1, half: 17)
        game.homeScore = 3; game.inningScores = scores
        try scores.validate(match: game)
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: true, inning: 9), "1")
        scores.away[0] = 3; game.awayScore = 3; game.half = 18; game.inningScores = scores
        try scores.validate(match: game)
        XCTAssertEqual(game.homeScore, game.awayScore)
        XCTAssertEqual(MatchBroadcastData.inningMark(game, home: true, inning: 9), "1")
    }

    func testV27InningScoreValidationRejectsMalformedOrInventedHistory() throws {
        var game = match(); game.half = 0
        var bad = MatchInningScores(); bad.version = 2
        XCTAssertThrowsError(try bad.validate(match: game))
        bad = MatchInningScores(); bad.away.removeLast()
        XCTAssertThrowsError(try bad.validate(match: game))
        bad = MatchInningScores(); bad.away[0] = -1
        XCTAssertThrowsError(try bad.validate(match: game))
        bad = MatchInningScores(); bad.home[0] = 0
        XCTAssertThrowsError(try bad.validate(match: game))
        bad = MatchInningScores(); bad.away[0] = Int.max
        XCTAssertThrowsError(try bad.validate(match: game))
        bad = MatchInningScores(); game.completed = true
        XCTAssertThrowsError(try bad.validate(match: game))
        game.completed = false; game.half = 18
        XCTAssertThrowsError(try bad.validate(match: game))
    }

    func testV27InningTrackingDoesNotChangeEitherRoleJudgementOrRandomSequence() throws {
        for role in PlayerRole.allCases {
            for seed in UInt64(1)...8 {
                var tracked = match(role: role, seed: seed); tracked.half = 0
                tracked.inningScores = MatchInningScores()
                var legacy = tracked; legacy.inningScores = nil
                try tracked.advance(.automatic); try legacy.advance(.automatic)
                let scores = try XCTUnwrap(tracked.inningScores)
                try scores.validate(match: tracked)
                XCTAssertEqual(scores.away.compactMap { $0 }.reduce(0, +), tracked.awayScore)
                XCTAssertEqual(scores.home.compactMap { $0 }.reduce(0, +), tracked.homeScore)
                tracked.inningScores = nil
                XCTAssertEqual(tracked, legacy)
            }
        }
    }

    func testBroadcastMissingHistoryStaysUnknownAndReadsRecordedHits() throws {
        var legacy = match()
        XCTAssertNil(MatchBroadcastData.hits(legacy, home: true))
        XCTAssertNil(MatchBroadcastData.errors(legacy, home: true))
        legacy.detailedFieldVersion = 5
        XCTAssertNil(MatchBroadcastData.errors(legacy, home: true))
        legacy.fieldPlays = []
        XCTAssertEqual(MatchBroadcastData.errors(legacy, home: true), 0)
        XCTAssertEqual(MatchBroadcastData.errors(legacy, home: false), 0)
        let container = try CareerStore.makeContainer(inMemory: true)
        let (player, calendar, record) = try fixture(in: container.mainContext)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: container.mainContext)
        let completed = try record.snapshot(), payload = record.payload
        XCTAssertEqual(MatchBroadcastData.hits(completed, home: true), completed.playerRecords?.home.battingTotal.hits)
        XCTAssertEqual(MatchBroadcastData.hits(completed, home: false), completed.playerRecords?.away.battingTotal.hits)
        XCTAssertEqual(record.payload, payload)
    }

    func testBattingSwipeIsRelativeClampedAndNeverBecomesTapAfterMovingBack() {
        var swipe = MatchBattingSwipe(x: 0.3, y: 0.7)
        XCTAssertEqual(swipe.move(CGSize(width: 3, height: 2), field: CGSize(width: 400, height: 400)), CGPoint(x: 0.3, y: 0.7))
        XCTAssertTrue(swipe.isTap)
        let moved = swipe.move(CGSize(width: 52, height: -52), field: CGSize(width: 400, height: 400))
        XCTAssertEqual(moved.x, 0.5, accuracy: 0.0001); XCTAssertEqual(moved.y, 0.5, accuracy: 0.0001)
        XCTAssertFalse(swipe.isTap)
        _ = swipe.move(.zero, field: CGSize(width: 400, height: 400)); XCTAssertFalse(swipe.isTap)
        XCTAssertEqual(swipe.move(CGSize(width: 1000, height: -1000), field: .zero), CGPoint(x: 1, y: 0))
    }

    private func motionPixels(_ image: UIImage) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage)
        var data = [UInt8](repeating: 0, count: source.width * source.height * 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
        return data
    }
    func testPersonalMotionAllPosesKeepAlphaAndUsePaletteWithoutEditingSources() throws {
        let style = PlayerAppearance(skin: 5, hair: 4, kit: 1, hairStyle: 2, expression: 2)
        for role in PlayerRole.allCases {
            for frame in 0..<6 {
                let source = try XCTUnwrap(MatchArt.cell(role == .pitcher ? "pitcher-delivery-v2" : "batter-actions", column: frame % 3, row: frame / 3, columns: 3, rows: 2))
                let before = try motionPixels(source)
                let image = try XCTUnwrap(PlayerMotionArt.image(role: role, frame: frame, appearance: style, number: 9, hand: role == .pitcher ? "left" : "right"))
                let after = try motionPixels(image)
                XCTAssertEqual(image.size, source.size)
                XCTAssertNotEqual(before, after)
                XCTAssertTrue(stride(from: 3, to: before.count, by: 4).allSatisfy { before[$0] == after[$0] })
                XCTAssertEqual(try motionPixels(source), before)
                let attachment = XCTAttachment(image: image); attachment.name = "Personal motion \(role.rawValue) pose \(frame)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
    func testPersonalMotionNumbersAndLeftHandKeepReadableDigitOrder() throws {
        let style = PlayerAppearance(kit: 1)
        let right = try motionPixels(XCTUnwrap(PlayerMotionArt.image(role: .pitcher, frame: 0, appearance: style, number: 9, hand: "right")))
        let left = try motionPixels(XCTUnwrap(PlayerMotionArt.image(role: .pitcher, frame: 0, appearance: style, number: 9, hand: "left")))
        func ink(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Bool {
            let i = (y * 512 + x) * 4, a = Int(bytes[i+3]); guard a > 128 else { return false }
            return Int(bytes[i])*255/a > 235 && Int(bytes[i+1])*255/a > 230 && (205..<235).contains(Int(bytes[i+2])*255/a)
        }
        var count = 0
        for y in 241..<291 { for x in 281..<325 {
            XCTAssertEqual(ink(right,x,y),ink(left,606-x,y))
            if ink(right,x,y) { count += 1 }
        } }
        XCTAssertEqual(count, 12 * 7 * 7)
        for number in [0, 7, 27, 99] {
            let value = try motionPixels(XCTUnwrap(PlayerMotionArt.image(role: .pitcher, frame: 0, appearance: style, number: number, hand: "right")))
            XCTAssertNotEqual(value, right)
            if number == 27 {
                let mirrored = try motionPixels(XCTUnwrap(PlayerMotionArt.image(role: .pitcher, frame: 0, appearance: style, number: number, hand: "left")))
                for y in 241..<291 { for x in 270..<337 { XCTAssertEqual(ink(value,x,y),ink(mirrored,606-x,y)) } }
            }
        }
        XCTAssertNil(PlayerMotionArt.image(role: .batter, frame: 6, appearance: style, number: 9, hand: "right"))
        XCTAssertNil(PlayerMotionArt.image(role: .pitcher, frame: 0, appearance: style, number: 100, hand: "right"))
    }
    func testPersonalMotionPaletteUsesSavedSkinHairKitAndKeepsEquipment() throws {
        let style = PlayerAppearance(skin: 5, hair: 4, kit: 1)
        let changed = try motionPixels(XCTUnwrap(PlayerMotionArt.image(role: .pitcher, frame: 0, appearance: style, number: 27, hand: "right")))
        for (point,hex) in [(CGPoint(x:280,y:150),PlayerAppearance.kitColors[1]),(CGPoint(x:222,y:289),PlayerAppearance.skinColors[5]),(CGPoint(x:280,y:199),PlayerAppearance.hairColors[4])] {
            let i = (Int(point.y)*512+Int(point.x))*4, a = Double(changed[i+3])
            let target = [Double((hex >> 16)&255), Double((hex >> 8)&255), Double(hex&255)]
            let ratios = (0..<3).map { Double(changed[i+$0])*255/a/target[$0] }
            XCTAssertEqual(ratios[0],ratios[1],accuracy:0.08); XCTAssertEqual(ratios[1],ratios[2],accuracy:0.08)
        }
        for (role,points) in [(PlayerRole.pitcher,[CGPoint(x:205,y:241),CGPoint(x:270,y:342)]),(.batter,[CGPoint(x:155,y:69),CGPoint(x:220,y:339)])] {
            let original = try motionPixels(XCTUnwrap(MatchArt.cell(role == .pitcher ? "pitcher-delivery-v2" : "batter-actions", column:0,row:0,columns:3,rows:2)))
            let personalized = try motionPixels(XCTUnwrap(PlayerMotionArt.image(role:role,frame:0,appearance:style,number:27,hand:"right")))
            for point in points {
                let i = (Int(point.y)*512+Int(point.x))*4
                XCTAssertEqual(Array(original[i..<(i+4)]),Array(personalized[i..<(i+4)]))
            }
        }
    }

    func testPersonalMotionTextureCacheSeparatesIdentityAndAllPaletteChoicesRender() throws {
        let a = PlayerMotionArt.textures(role: .batter, appearance: PlayerAppearance(), number: 0, hand: "right")
        let b = PlayerMotionArt.textures(role: .batter, appearance: PlayerAppearance(), number: 0, hand: "right")
        XCTAssertEqual(a.count,6); XCTAssertTrue(zip(a,b).allSatisfy { $0 === $1 })
        let other = PlayerMotionArt.textures(role: .batter, appearance: PlayerAppearance(kit: 5), number: 99, hand: "right")
        XCTAssertFalse(a[0] === other[0]); XCTAssertTrue(other.allSatisfy { $0.filteringMode == .nearest })
        for index in 0..<6 {
            XCTAssertNotNil(PlayerMotionArt.image(role: index % 2 == 0 ? .pitcher : .batter, frame: index,
                appearance: PlayerAppearance(skin: index, hair: index, kit: index, hairStyle: index % 3, expression: index % 3), number: index, hand: "left"))
        }
    }

    func testRenderedPitchArrivalPrecedesCompletionAndCancellationDropsCallbacks() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        controller.view = view; window.rootViewController = controller; window.makeKeyAndVisible()
        defer { view.presentScene(nil); window.isHidden = true; previous?.makeKey() }
        for (reduced, prepared) in [(false, true), (true, true), (false, false), (true, false)] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: reduced ? "left" : "right", kit: 0)
            view.presentScene(scene)
            var arrival: Double?, completion: Double?
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: 0.5, preparedRelease: prepared,
                onArrival: { XCTAssertEqual(scene.pitchStage, .received); arrival = ProcessInfo.processInfo.systemUptime },
                completion: { completion = ProcessInfo.processInfo.systemUptime }))
            try await Task.sleep(for: .seconds(0.65 + (prepared ? 0 : MatchDelivery.windup)))
            XCTAssertNotNil(arrival); XCTAssertNil(completion, "포구 직후에는 판정 확인을 위해 다음 투구를 열지 않습니다")
            try await Task.sleep(for: .seconds(1))
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(completion) - XCTUnwrap(arrival), reduced ? 0.75 : 1.0)
            var cancelledCallback = false
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, preparedRelease: true,
                onArrival: { cancelledCallback = true }, completion: { cancelledCallback = true }))
            scene.cancelDelivery()
            try await Task.sleep(for: .seconds(0.3))
            XCTAssertFalse(cancelledCallback); XCTAssertEqual(scene.pitchStage, .idle)
        }
    }

    func testRenderedVelocityOrdersActualReceiptAndReachesEndpointBeforeCall() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene), controller = UIViewController()
        let view = SKView(frame:CGRect(x:0,y:0,width:320,height:340))
        controller.view = view; window.rootViewController = controller; window.makeKeyAndVisible()
        defer { view.presentScene(nil); window.isHidden = true; previous?.makeKey() }
        var elapsed: [Double] = []
        for code in ["four-seam","changeup"] {
            let scene = BallparkScene(size:CGSize(width:320,height:340)); scene.configure(hand:"right",kit:0)
            view.presentScene(scene)
            let duration = MatchDelivery.pitch(code:code,velocity:60).duration
            let started = ProcessInfo.processInfo.systemUptime
            let arrival = expectation(description:code + " actual arrival")
            scene.demonstrate(reduceMotion:false,flightDuration:duration,x:0.75,y:0.3,pitchCode:code,preparedRelease:true,onArrival:{
                let time = ProcessInfo.processInfo.systemUptime - started
                elapsed.append(time)
                XCTAssertGreaterThanOrEqual(time,duration * MatchDelivery.contactPhase - 0.04)
                let ball = scene.childNode(withName:"baseball")
                XCTAssertEqual(ball?.position.x ?? -1,320 * (0.54 + 0.25 * 0.22),accuracy:0.01)
                XCTAssertEqual(ball?.position.y ?? -1,scene.size.height * (1 - (0.43 - 0.2 * 0.24)),accuracy:0.01)
                XCTAssertEqual(scene.pitchStage,.received); arrival.fulfill()
            })
            try await Task.sleep(for:.seconds(0.2)); XCTAssertEqual(scene.pitchStage,.flight)
            await fulfillment(of:[arrival],timeout:3)
            scene.cancelDelivery()
        }
        XCTAssertGreaterThan(elapsed[1]-elapsed[0],0.09)
    }

    func testPitchFlightKeepsVelocityDurationAndVisibleBallUntilActualArrivalIncludingReducedMotion() async throws {
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene),controller=UIViewController()
        let view=SKView(frame:CGRect(x:0,y:0,width:320,height:340))
        controller.view=view;window.rootViewController=controller;window.makeKeyAndVisible()
        defer{view.presentScene(nil);window.isHidden=true;previous?.makeKey()}
        for reduced in [false,true] {
            var times=[Double]()
            for code in ["four-seam","changeup"] {
                let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:reduced ? "left":"right",kit:0)
                view.presentScene(scene)
                let duration=MatchDelivery.pitch(code:code,velocity:60).duration
                XCTAssertEqual(DeliveryPresentation.flight(duration,reduced:reduced,role:.pitcher),duration)
                var arrived=false,finished=false
                let start=ProcessInfo.processInfo.systemUptime,event=expectation(description:"full "+code)
                XCTAssertTrue(scene.demonstrate(reduceMotion:reduced,flightDuration:duration,pitchCode:code,preparedRelease:true,onArrival:{
                    times.append(ProcessInfo.processInfo.systemUptime-start);arrived=true;event.fulfill()
                },completion:{finished=true}))
                try await Task.sleep(for:.seconds(duration*0.45))
                let ball=try XCTUnwrap(scene.childNode(withName:"baseball"))
                XCTAssertEqual(scene.pitchStage,.flight);XCTAssertFalse(arrived);XCTAssertFalse(finished);XCTAssertFalse(ball.isHidden)
                let end=CGPoint(x:scene.size.width*0.54,y:scene.size.height*0.57)
                XCTAssertGreaterThan(hypot(ball.position.x-end.x,ball.position.y-end.y),10)
                XCTAssertGreaterThanOrEqual(ball.frame.width,5)
                await fulfillment(of:[event],timeout:3)
                XCTAssertGreaterThanOrEqual(times.last!,duration-0.04)
                XCTAssertEqual(scene.pitchStage,.received);XCTAssertFalse(finished)
                scene.cancelDelivery();try await Task.sleep(for:.seconds(1.2));XCTAssertFalse(finished)
            }
            XCTAssertGreaterThan(times[1]-times[0],0.15)
        }
    }

    func testPitchPreparationHoldsBallUntilExplicitReleaseForBothHands() {
        for hand in ["left", "right"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 320))
            scene.configure(hand: hand, kit: 0, role: .pitcher)
            for phase in [0.0, 0.3, 0.68, 0.95] {
                scene.preparePitch(phase: phase, reduced: false)
                XCTAssertEqual(scene.pitchStage, .preparing)
                XCTAssertNil(scene.action(forKey: "delivery"))
            }
            XCTAssertTrue(scene.demonstrate(reduceMotion: false, preparedRelease: true))
            XCTAssertEqual(scene.pitchStage, .flight)
            scene.preparePitch(phase: 0.7, reduced: false)
            XCTAssertEqual(scene.pitchStage, .flight)
            scene.cancelDelivery(); XCTAssertEqual(scene.pitchStage, .idle)
            scene.preparePitch(phase: 0.68, reduced: true)
            XCTAssertEqual(scene.pitchStage, .preparing)
            XCTAssertTrue(scene.demonstrate(reduceMotion: true, preparedRelease: true))
            XCTAssertEqual(scene.pitchStage, .flight)
        }
    }

    func testFreePracticeAllKindsAndPositionsLeaveCareerStoreUnchanged() throws {
        let real = try CareerStore.makeContainer(inMemory: true)
        var originals: [CareerPlayer] = []
        for role in PlayerRole.allCases {
            var draft = PlayerDraft(); draft.name = role.label; draft.role = role; draft.schoolID = "hs-ref-001"
            draft.throwingHand = .left; draft.appearance = PlayerAppearance(skin: 3, hair: 4, kit: 5, hairStyle: 2, expression: 1)
            let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: real.mainContext)
            player.contact = 81.2345; player.speed = 77.3456
            if role == .pitcher {
                player.pitches = [CareerSchemaV1.PitchMastery(code: "knuckle", name: "너클", mastery: 88.1234, order: 2),
                                  CareerSchemaV1.PitchMastery(code: "slider", name: "슬라이더", mastery: 32.5678, order: 1),
                                  CareerSchemaV1.PitchMastery(code: "four-seam", name: "포심", mastery: 93.4567, order: 0)]
            }
            let profile = try XCTUnwrap(PlayerAbilityStore.profile(playerID: player.id, in: real.mainContext))
            profile.mental = 78.4321
            if role == .pitcher { profile.velocity = 87.6543; profile.control = 91.2345; profile.stuff = 76.789; profile.stamina = 83.4567 }
            originals.append(player)
        }
        try real.mainContext.save()
        let player = originals[0]
        let calendar = try XCTUnwrap(real.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: real.mainContext)
        let matchRecord = try CareerMatchStore.start(player: player, state: calendar, in: real.mainContext)
        let date = player.gameDate, fatigue = player.fatigue, revision = calendar.revision, original = matchRecord.payload
        let memory = try CareerStore.makeContainer(inMemory: true)
        let copies = try originals.map { try TrainingPractice.copy($0, from: real.mainContext, into: memory.mainContext) }
        for (original, copy) in zip(originals, copies) {
            XCTAssertNotEqual(copy.id, original.id); XCTAssertFalse(copy === original)
            XCTAssertEqual(copy.name, original.name); XCTAssertEqual(copy.appearance, original.appearance)
            XCTAssertEqual(copy.throwingHandRaw, "left"); XCTAssertEqual(copy.contact, 81.2345)
            XCTAssertEqual(copy.speed, 77.3456); XCTAssertEqual(copy.fatigue, 0)
            XCTAssertEqual(copy.pitches.sorted { $0.order < $1.order }.map(\.code), original.pitches.sorted { $0.order < $1.order }.map(\.code))
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: copy.pitches.map { ($0.code, $0.mastery) }), Dictionary(uniqueKeysWithValues: original.pitches.map { ($0.code, $0.mastery) }))
            let a = try XCTUnwrap(PlayerAbilityStore.profile(playerID: original.id, in: real.mainContext))
            let b = try XCTUnwrap(PlayerAbilityStore.profile(playerID: copy.id, in: memory.mainContext))
            XCTAssertFalse(a === b); XCTAssertEqual(a.initialValues, b.initialValues)
            XCTAssertEqual(a.mental, b.mental); XCTAssertEqual(a.velocity, b.velocity); XCTAssertEqual(a.control, b.control)
            XCTAssertEqual(a.stuff, b.stuff); XCTAssertEqual(a.stamina, b.stamina)
        }
        for role in PlayerRole.allCases {
            for kind in TrainingKind.allCases where kind.allows(role.rawValue) {
                for _ in 0..<2 {
                    let copy = try XCTUnwrap(copies.first { $0.role == role })
                    let state = try XCTUnwrap(memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == copy.id })
                    var round = try TrainingPractice.round(player: copy, calendar: state, kind: kind, code: "four-seam", in: memory.mainContext)
                    for _ in 0..<5 {
                        let input: TrainingInput
                        switch kind {
                        case .contact: input = TrainingInput(x: 0.5, y: 0.5, timing: 0.82)
                        case .pitch: input = TrainingInput(release: 0.68)
                        case .power: input = TrainingInput(drill: SkillDrillInput(phase: 0.5))
                        case .velocity: input = TrainingInput(drill: SkillDrillInput(beats: [0.65,1.35,2.05]))
                        case .stuff: input = TrainingInput(drill: SkillDrillInput(trace: SkillDrillRules.curve(round.targets[round.scores.count])))
                        case .discipline: input = TrainingInput(calledStrike: true)
                        case .mental: input = TrainingInput(choice: 0)
                        case .speed, .stamina: input = TrainingInput(footfalls: [])
                        case .arm: input = TrainingInput(force: 70, angle: 35, base: 1)
                        case .control, .defense: input = TrainingInput(x: 0.5, y: 0.5)
                        }
                        try round.attempt(input)
                    }
                    XCTAssertTrue(round.completed)
                    XCTAssertEqual(round.before, try CareerTrainingStore.value(player: originals.first { $0.role == role }!, code: kind == .pitch ? "four-seam" : nil, kind: kind, in: real.mainContext)); XCTAssertEqual(round.fatigue, 0)
                    XCTAssertThrowsError(try round.attempt(TrainingInput()))
                }
            }
        }
        for position in FieldPosition.allCases {
            let copy = copies[0]
            let state = try XCTUnwrap(memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == copy.id })
            var round = try TrainingPractice.round(player: copy, calendar: state, kind: .defense, position: position, in: memory.mainContext)
            XCTAssertEqual(try CareerTrainingRecord(round).snapshot(), round)
            for _ in 0..<5 { try round.attempt(TrainingInput(x: 0.5, y: 0.5, force: 50, angle: 270, base: 1)) }
            XCTAssertTrue(round.completed)
        }
        XCTAssertEqual(player.gameDate, date); XCTAssertEqual(player.fatigue, fatigue)
        XCTAssertEqual(calendar.revision, revision); XCTAssertEqual(matchRecord.payload, original)
        XCTAssertEqual(try real.mainContext.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 0)
        XCTAssertEqual(try memory.mainContext.fetchCount(FetchDescriptor<CareerTrainingRecord>()), 0)
        XCTAssertEqual(try memory.mainContext.fetchCount(FetchDescriptor<CareerMatchRecord>()), 0)
        XCTAssertEqual(try real.mainContext.fetchCount(FetchDescriptor<CareerPlayer>()), 2)
        let pitcher = copies[1], state = try XCTUnwrap(memory.mainContext.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == pitcher.id })
        XCTAssertThrowsError(try TrainingPractice.round(player: pitcher, calendar: state, kind: .pitch, code: "fork", in: memory.mainContext))
        let before = try TrainingPractice.round(player: pitcher, calendar: state, kind: .pitch, code: "four-seam", in: memory.mainContext)
        XCTAssertEqual(before.before, 93.4567)
        originals[1].pitches.first { $0.code == "four-seam" }!.mastery = 1
        XCTAssertEqual(pitcher.pitches.first { $0.code == "four-seam" }?.mastery, 93.4567)
        pitcher.speed = 1; XCTAssertEqual(originals[1].speed, 77.3456)
    }

    private func match(role: PlayerRole = .batter, seed: UInt64 = 42, mastery: Double = 72) -> CareerMatch {
        var match = CareerMatch(random: seed, isHome: role == .batter, role: role.rawValue,
                                appearance: true, contact: 65, power: 75, discipline: 60,
                                mastery: role == .pitcher ? ["four-seam": mastery] : [:])
        match.half = role == .batter ? 1 : 0
        match.controlVersion = 2
        return match
    }
    private func fixture(in context: ModelContext, role: PlayerRole = .batter) throws -> (CareerPlayer, CareerCalendarState, CareerMatchRecord) {
        var draft = PlayerDraft(); draft.name = "직접조작"; draft.schoolID = "hs-ref-001"; draft.role = role
        let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
        try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
        let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
        return (player, calendar, record)
    }

    func testResultSummaryProjectsSavedBatterMetricsWithoutMutation() {
        var state = match(); state.completed = true; state.homeScore = 4; state.awayScore = 2
        state.line = MatchLine(plateAppearances: 5, atBats: 4, hits: 2, homeRuns: 1, walks: 1, strikeouts: 1, rbi: 3)
        let original = state
        let summary = MatchResultSummary(match: state, fatigueBefore: 24, fatigueAfter: 28)
        XCTAssertEqual(summary.outcome, "승리"); XCTAssertEqual(summary.fatigueChange, "+4")
        XCTAssertEqual(summary.metrics.map(\.value), ["5", "4", "2", "1", "3", "1", "1"])
        XCTAssertEqual(state, original)
    }
    func testResultSummaryPitchingOutsAreBaseThreeAndNoInventedERA() {
        var state = match(role: .pitcher); state.line.pitchingOuts = 17; state.line.pitches = 92
        state.line.hitsAllowed = 5; state.line.runsAllowed = 3; state.line.pitchingWalks = 2; state.line.pitchingStrikeouts = 6
        let summary = MatchResultSummary(match: state, fatigueBefore: 6, fatigueAfter: 37)
        XCTAssertEqual(summary.metrics.map(\.value), ["5.2", "92", "5", "3", "2", "6"])
        XCTAssertFalse(summary.metrics.contains { $0.id == "era" })
    }
    func testResultSummarySeparatesAbsentLegacyEmptyAndAppliedTraits() {
        var state = match()
        XCTAssertTrue(MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0).traitMessage.contains("경합이 없습니다"))
        state.lastFieldPlay = MatchFieldPlay(runnerTime: 3, ballTime: 4, ownDefense: false)
        XCTAssertTrue(MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0).traitMessage.contains("미기록"))
        state.lastFieldPlay?.appliedTraits = []
        XCTAssertTrue(MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0).traitMessage.contains("특성 없음"))
        state.lastFieldPlay?.appliedTraits = [.cheetah]
        let summary = MatchResultSummary(match: state, fatigueBefore: 0, fatigueAfter: 0)
        XCTAssertEqual(summary.appliedTraits, [.cheetah]); XCTAssertEqual(summary.fatigueChange, "변화 없음")
        state = CareerMatch(random: 1, isHome: true, role: "pitcher", appearance: false, contact: 60, power: 60, discipline: 60, mastery: [:])
        let absent = MatchResultSummary(match: state, fatigueBefore: 24, fatigueAfter: 24)
        XCTAssertTrue(absent.metrics.isEmpty); XCTAssertTrue(absent.traitMessage.contains("비등판"))
    }

    func testDeliveryPreviewDoesNotConsumeRNGAndSpeedChangesFlightTime() throws {
        let state = match(role: .pitcher)
        XCTAssertEqual(state.delivery(pitchCode: "four-seam"), state.delivery(pitchCode: "four-seam"))
        XCTAssertEqual(state.random, 42)
        XCTAssertLessThan(state.delivery(pitchCode: "four-seam").duration, state.delivery(pitchCode: "changeup").duration)
        let decoded = try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.delivery(), state.delivery())
    }

    func testAimAndTimingMissesCannotBecomeHitsAndPerfectInputRaisesQuality() throws {
        let original = match(); let delivery = original.delivery()
        var centered = original
        try centered.advance(.swing, control: ManualMatchInput(x: delivery.x, y: delivery.y, timing: MatchDelivery.contactPhase))
        XCTAssertEqual(centered.lastManual?.quality, 1); XCTAssertEqual(centered.lastManual?.grade, "정타")
        for seed in 0..<100 {
            var state = match(seed: UInt64(seed)); let target = state.delivery()
            try state.advance(.swing, control: ManualMatchInput(x: target.x, y: target.y, timing: 0.82))
            XCTAssertEqual(state.lastManual?.grade, "정타")
            XCTAssertTrue(["안타", "홈런", "범타"].contains(state.lastManual?.outcome ?? ""))
        }
        for control in [ManualMatchInput(x: delivery.x, y: delivery.y, timing: 0),
                        ManualMatchInput(x: delivery.x < 0.5 ? 1 : 0, y: delivery.y, timing: MatchDelivery.contactPhase)] {
            var missed = original
            try missed.advance(.swing, control: control)
            XCTAssertEqual(missed.lastManual?.quality, 0); XCTAssertEqual(missed.lastManual?.grade, "헛스윙")
            XCTAssertEqual(missed.line.hits, 0); XCTAssertEqual(missed.line.homeRuns, 0)
            XCTAssertEqual(missed.fatigueCost, 1)
        }
    }

    func testNoInputIsIdenticalToWatchingAndUsesActualZoneWithoutFatigue() throws {
        var sawBall = false, sawStrike = false
        for seed in 0..<100 {
            var noInput = match(seed: UInt64(seed)), watched = noInput
            let delivery = noInput.delivery()
            try noInput.advance(.swing, control: ManualMatchInput())
            try watched.advance(.watch, control: ManualMatchInput())
            XCTAssertEqual(noInput, watched); XCTAssertEqual(noInput.fatigueCost, 0)
            XCTAssertEqual(noInput.lastManual?.action, "watch")
            if ManualMatchRules.isStrike(x: delivery.x, y: delivery.y) {
                XCTAssertEqual(noInput.strikes, 1); sawStrike = true
            } else { XCTAssertEqual(noInput.balls, 1); sawBall = true }
        }
        XCTAssertTrue(sawBall && sawStrike)
    }

    func testReleaseMasteryExpandsWindowsAndReducesActualCourseError() throws {
        var low = match(role: .pitcher, mastery: 10), high = match(role: .pitcher, mastery: 90)
        let plan = low.delivery(pitchCode: "four-seam")
        let input = ManualMatchInput(release: 0.80)
        try low.advance(.pitch, pitchCode: "four-seam", control: input)
        try high.advance(.pitch, pitchCode: "four-seam", control: input)
        let lowResult = try XCTUnwrap(low.lastManual), highResult = try XCTUnwrap(high.lastManual)
        XCTAssertEqual(lowResult.grade, "MISS"); XCTAssertEqual(highResult.grade, "GOOD")
        XCTAssertGreaterThan(highResult.quality, lowResult.quality)
        XCTAssertLessThan(abs(highResult.x - plan.x), abs(lowResult.x - plan.x))
        XCTAssertGreaterThan(ManualMatchRules.goodWidth(mastery: 90), ManualMatchRules.goodWidth(mastery: 10))
        var perfect = match(role: .pitcher)
        try perfect.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: 0.68))
        XCTAssertEqual(perfect.lastManual?.grade, "PERFECT"); XCTAssertEqual(perfect.lastManual?.quality, 1)
        XCTAssertEqual(perfect.line.pitches, 1); XCTAssertEqual(perfect.fatigueCost, 0.38, accuracy: 0.0001)
    }

    func testInvalidManualValuesAndRolesLeaveStateUnchanged() throws {
        let original = match()
        for value in [Double.nan, .infinity, -0.1, 1.1] {
            var copy = original
            XCTAssertThrowsError(try copy.advance(.swing, control: ManualMatchInput(x: value, timing: 0.82)))
            XCTAssertEqual(copy, original)
        }
        var pitcher = match(role: .pitcher)
        let before = pitcher
        XCTAssertThrowsError(try pitcher.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(timing: 0.82)))
        XCTAssertEqual(pitcher, before)
        XCTAssertThrowsError(try pitcher.advance(.pitch, pitchCode: "unknown", control: ManualMatchInput(release: 0.68)))
        XCTAssertEqual(pitcher, before)
    }

    func testManualWalkStrikeoutAndBuntConnectToExistingPlateAndBaseProgression() throws {
        for strike in [true, false] {
            let seed = try XCTUnwrap((0..<100).first { value in
                let ball = match(seed: UInt64(value)).delivery()
                return ManualMatchRules.isStrike(x: ball.x, y: ball.y) == strike
            })
            var state = match(seed: UInt64(seed)); state.strikes = strike ? 2 : 0; state.balls = strike ? 0 : 3
            try state.advance(.watch, control: ManualMatchInput())
            XCTAssertEqual(state.line.plateAppearances, 1)
            XCTAssertEqual(state.line.strikeouts, strike ? 1 : 0)
            XCTAssertEqual(state.line.walks, strike ? 0 : 1)
        }
        for seed in 0..<100 {
            var state = match(seed: UInt64(seed)); let ball = state.delivery()
            try state.advance(.bunt, control: ManualMatchInput(x: ball.x, y: ball.y, timing: 0.82))
            XCTAssertEqual(state.line.homeRuns, 0)
        }
    }

    func testV2DirectGeneratedInputsAndAutomaticFinishHaveIdenticalResults() throws {
        var batterStrikeouts = 0
        for role in PlayerRole.allCases {
            for seed in 0..<50 {
                var direct = match(role: role, seed: UInt64(seed))
                direct.settle()
                var automatic = direct
                try automatic.advance(.automatic)
                var count = 0
                while !direct.completed && count < 1000 {
                    let input: MatchInput = role == .batter ? .swing : .pitch
                    let code: String? = role == .pitcher ? "four-seam" : nil
                    let control = direct.automaticControl(input, pitchCode: code)
                    try direct.advance(input, pitchCode: code, control: control)
                    count += 1
                }
                XCTAssertTrue(direct.completed); XCTAssertEqual(direct, automatic)
                if role == .batter { batterStrikeouts += direct.line.strikeouts }
            }
        }
        XCTAssertGreaterThan(batterStrikeouts, 0)
    }

    func testManualSaveFailureRetryAndStaleInputCannotApplyTwice() throws {
        enum Injected: Error { case failure }
        let container = try CareerStore.makeContainer(inMemory: true); let context = container.mainContext
        let (player, calendar, record) = try fixture(in: context)
        let before = try record.snapshot(); let ball = before.delivery()
        let control = ManualMatchInput(x: ball.x, y: ball.y, timing: 0.82)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: 0,
                                                        input: .swing, control: control, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(try record.snapshot(), before); XCTAssertEqual(record.revision, 0)
        XCTAssertEqual(player.fatigue, 6)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: 0, input: .swing, control: control, in: context)
        let once = record.payload
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: 0, input: .swing, control: control, in: context))
        XCTAssertEqual(record.payload, once)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context)
        let fatigue = player.fatigue
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context))
        XCTAssertEqual(player.fatigue, fatigue)
    }

    func testLegacyV1DiskPayloadResumesUpgradesOnlyOnManualSaveAndKeepsCompletedBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        var oldCompleted = Data()
        try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url); let context = container.mainContext
            for role in PlayerRole.allCases {
                let (_, _, record) = try fixture(in: context, role: role)
                let source = try record.snapshot()
                var legacy = CareerMatch(random: source.random, isHome: source.isHome, role: source.role,
                    appearance: source.appearance, contact: source.contact, power: source.power,
                    discipline: source.discipline, mastery: source.mastery)
                if role == .pitcher { try legacy.advance(.automatic) } else { legacy.settle() }
                var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
                dictionary.removeValue(forKey: "controlVersion"); dictionary.removeValue(forKey: "lastManual")
                record.payload = try JSONSerialization.data(withJSONObject: dictionary, options: .sortedKeys)
                record.completed = legacy.completed; record.rulesVersion = "native-match-v1"
                _ = try record.snapshot()
                if role == .pitcher { oldCompleted = record.payload }
            }
            try context.save()
        }
        let reopened = try CareerStore.makeContainer(url: url); let context = reopened.mainContext
        let players = try context.fetch(FetchDescriptor<CareerPlayer>())
        for player in players {
            let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
            let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
            XCTAssertEqual(player.gameDate, "2026-04-01")
            if player.role == .pitcher {
                XCTAssertEqual(record.payload, oldCompleted); XCTAssertEqual(record.rulesVersion, "native-match-v1")
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .pitch, pitchCode: "four-seam", control: ManualMatchInput(release: 0.68), in: context))
                XCTAssertEqual(record.payload, oldCompleted)
            } else {
                XCTAssertNil(try record.snapshot().controlVersion)
                enum Injected: Error { case failure }
                let oldPayload = record.payload
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision,
                                                                input: .swing, control: ManualMatchInput(), in: context, save: { _ in throw Injected.failure }))
                XCTAssertEqual(record.payload, oldPayload)
                XCTAssertEqual(record.rulesVersion, "native-match-v1")
                try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .swing, control: ManualMatchInput(), in: context)
                XCTAssertEqual(record.rulesVersion, "native-match-v2"); XCTAssertEqual(try record.snapshot().controlVersion, 2)
                XCTAssertEqual(try record.snapshot().lastManual?.action, "watch")
            }
        }
        let second = try CareerStore.makeContainer(url: url)
        let records = try second.mainContext.fetch(FetchDescriptor<CareerMatchRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.contains { $0.completed && $0.payload == oldCompleted })
        XCTAssertTrue(records.contains { $0.rulesVersion == "native-match-v2" })
    }

    func testClockTimeoutOnceAndCancellationDoesNotResolveInput() async throws {
        let clock = MatchInputClock(); var count = 0
        clock.start(windup: 0, duration: 0.02) { count += 1; clock.stop() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(count, 1); XCTAssertFalse(clock.running)
        clock.start(windup: 0, duration: 1) { count += 1 }
        clock.stop()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count, 1); XCTAssertFalse(clock.running)
    }
}

@MainActor final class MatchPresentationTests: XCTestCase {
    func testPitchLocationCoordinatesSideAndVelocityArePresentationOnly() throws {
        XCTAssertTrue(OpponentBatterSide.left.mapOnRight); XCTAssertFalse(OpponentBatterSide.right.mapOnRight)
        XCTAssertEqual((0..<9).map { OpponentBatterSide.at(order:$0) },[.right,.left,.right,.right,.left,.right,.right,.left,.right])
        XCTAssertEqual(OpponentBatterSide.at(order:10),.left)
        let size=CGSize(width:100,height:100)
        let inside=PitchLocationBoard.marker(x:0.2,y:0.8,size:size)
        XCTAssertEqual(inside.x,24.8,accuracy:0.00001); XCTAssertEqual(inside.y,75.2,accuracy:0.00001)
        let outside=PitchLocationBoard.marker(x:1.2,y:-0.2,size:size)
        XCTAssertEqual(outside.x,92,accuracy:0.00001); XCTAssertEqual(outside.y,8,accuracy:0.00001)
        let fast=MatchDelivery.pitch(code:"four-seam",velocity:60), slow=MatchDelivery.pitch(code:"changeup",velocity:60)
        XCTAssertEqual(fast.exactSpeed,144); XCTAssertEqual(slow.exactSpeed,124)
        XCTAssertEqual(slow.duration/fast.duration,144.0/124,accuracy:0.00001)
        var game=CareerMatch(random:10,isHome:true,role:"pitcher",appearance:true,contact:60,power:60,discipline:60,mastery:["four-seam":60])
        game.awayOrder=1;let original=game
        XCTAssertEqual(game.opponentBatterSide,.left);_ = PitchLocationBoard(result:nil,side:game.opponentBatterSide)
        XCTAssertEqual(game,original)
    }
    func testContactUsesTheSwingAndBuntAtlasBarrels() {
        let swing = MatchPresentation.batContact(action: "swing")
        let bunt = MatchPresentation.batContact(action: "bunt")
        XCTAssertEqual(swing.x, 0.510859375, accuracy: 0.000001)
        XCTAssertEqual(swing.y, 0.66763671875, accuracy: 0.000001)
        XCTAssertEqual(bunt.x, 0.49875, accuracy: 0.000001)
        XCTAssertEqual(bunt.y, 0.6807421875, accuracy: 0.000001)
    }

    func testVisualFlightKeepsSavedEndpointAndMirrorsOnlyHorizontalBreak() {
        let size = CGSize(width: 320, height: 320), start = CGPoint(x: 160, y: 220), end = CGPoint(x: 160, y: 80)
        for role in PlayerRole.allCases {
            for code in ["four-seam", "slider", "changeup", "fork"] {
                for hand in ["left", "right"] {
                    XCTAssertEqual(MatchBallPath.point(from: start, to: end, size: size, role: role, hand: hand, code: code, progress: 0), start)
                    XCTAssertEqual(MatchBallPath.point(from: start, to: end, size: size, role: role, hand: hand, code: code, progress: 1), end)
                }
            }
            let right = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: "slider", progress: 0.5)
            let left = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "left", code: "slider", progress: 0.5)
            XCTAssertEqual(right.x + left.x, 320, accuracy: 0.0001)
            XCTAssertEqual(right.y, left.y)
            var previous = start
            for step in 1...100 {
                let point = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: "fork", progress: Double(step) / 100)
                XCTAssertLessThan(point.y, previous.y)
                previous = point
            }
        }
    }

    func testFieldFitsCompactAndTallPhonesWithoutStretching() {
        for available in [CGSize(width: 304, height: 480), CGSize(width: 359, height: 560), CGSize(width: 386, height: 730)] {
            for role in PlayerRole.allCases {
                let field = MatchPresentation.fieldSize(available: available, role: role)
                XCTAssertLessThanOrEqual(field.width, available.width)
                XCTAssertLessThanOrEqual(field.height + 310, available.height)
                XCTAssertEqual(field.width / field.height, role == .batter ? 1 : 1219.0 / 1290, accuracy: 0.0001)
            }
        }
    }
    func testMeasuredMatchChromeKeepsFieldRatioAndAvailableSpace() {
        for chrome in [CGFloat(260), 340, 420] {
            for role in PlayerRole.allCases {
                let size = MatchPresentation.fieldSize(available: CGSize(width: 304, height: 600), role: role, chromeHeight: chrome)
                XCTAssertLessThanOrEqual(size.width, 304)
                XCTAssertLessThanOrEqual(size.height + chrome, 600)
                XCTAssertEqual(size.width / size.height, role == .batter ? 1 : 1219.0 / 1290, accuracy: 0.0001)
            }
        }
        let large = MatchPresentation.fieldSize(available: CGSize(width: 304, height: 480), role: .batter, chromeHeight: 600)
        XCTAssertEqual(large.height, 150) // Large text uses scrolling instead of distorting the field.
    }

    func testOnlyNewPitchJudgmentsRequestCountPulse() {
        for value in ["볼", "볼넷"] { XCTAssertEqual(MatchPresentation.countPulse(value), "B") }
        for value in ["루킹 스트라이크", "헛스윙", "삼진"] { XCTAssertEqual(MatchPresentation.countPulse(value), "S") }
        for value in ["안타", "홈런", "범타"] { XCTAssertNil(MatchPresentation.countPulse(value)) }
        XCTAssertNil(MatchPresentation.countPulse(nil))
    }
    func testSavedPitchNameSurvivesSelectionAndLegacyResultDecodes() throws {
        let result = ManualMatchResult(action: "pitch", quality: 1, grade: "GOOD", x: 0.5, y: 0.5, speed: 132, outcome: "볼", pitchCode: "slider")
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(MatchPresentation.pitchName(try JSONDecoder().decode(ManualMatchResult.self, from: data)), "슬라이더")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "pitchCode")
        let restored = try JSONDecoder().decode(ManualMatchResult.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.pitchCode)
        XCTAssertEqual(MatchPresentation.pitchName(restored), "구종 미기록")
        XCTAssertEqual(MatchPresentation.pitchName(nil), "투구 대기")
    }
    func testAllBundledAtlasFramesAndSceneArtLoad() throws {
        for name in MatchArt.names { XCTAssertNotNil(MatchArt.image(name), name) }
        for name in ["pitcher-delivery-v2", "batter-actions"] {
            for i in 0..<6 { XCTAssertNotNil(MatchArt.cell(name, column: i % 3, row: i / 3, columns: 3, rows: 2)) }
        }
        let scene = BallparkScene(size: CGSize(width: 320, height: 400))
        scene.configure(hand: "left", kit: 0, role: .batter)
        XCTAssertEqual(scene.size, CGSize(width: 320, height: 320))
        XCTAssertTrue(scene.demonstrate(reduceMotion: true))
        scene.cancelDelivery()
        scene.configure(hand: "left", kit: 0, role: .pitcher)
        XCTAssertTrue(scene.demonstrate(reduceMotion: false, pitchCode: "slider"))
        scene.cancelDelivery()
    }
}

extension ManualMatchTests {
    func testPixelBaseballHasTransparentCornersWhiteLeatherAndRedSeams() throws {
        XCTAssertEqual(PixelBaseball.rows.count,12)
        XCTAssertTrue(PixelBaseball.rows.allSatisfy {$0.count == 12})
        XCTAssertTrue(PixelBaseball.rows.contains {$0.contains("r")})
        let image=try XCTUnwrap(PixelBaseball.image.cgImage)
        XCTAssertEqual(image.width,12);XCTAssertEqual(image.height,12)
        XCTAssertEqual(PixelBaseball.texture.filteringMode,.nearest)
        let bytes=try XCTUnwrap(image.dataProvider?.data)
        let data=try XCTUnwrap(CFDataGetBytePtr(bytes))
        XCTAssertEqual(data[3],0)
        XCTAssertEqual(data[6*image.bytesPerRow+6*(image.bitsPerPixel/8)+3],255)
    }
    func testStrikeZoneUsesSameArrivalCoordinatesBothRolesAndReceiptIsMatchOnlyLonger() throws {
        for role in PlayerRole.allCases {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:"left",kit:0,role:role)
            let zone=try XCTUnwrap(scene.childNode(withName:"pitchStrikeZone") as? SKShapeNode)
            let a=scene.arrivalPoint(x:0.2,y:0.2),b=scene.arrivalPoint(x:0.8,y:0.8)
            XCTAssertEqual(zone.path?.boundingBox.width ?? 0,b.x-a.x,accuracy:0.01)
            XCTAssertEqual(zone.path?.boundingBox.height ?? 0,a.y-b.y,accuracy:0.01)
            XCTAssertTrue(try XCTUnwrap(scene.childNode(withName:"receivedBaseball")).isHidden)
            XCTAssertTrue(scene.childNode(withName:"baseball") is SKSpriteNode)
        }
        for reduced in [true,false] {
            XCTAssertEqual(DeliveryPresentation.receipt(reduced:reduced,match:true)-DeliveryPresentation.receipt(reduced:reduced),1,accuracy:0.001)
        }
        XCTAssertEqual(DeliveryPresentation.receipt(reduced:false),1.1)
        XCTAssertEqual(DeliveryPresentation.trainingRead(reduced:false),1.1)
    }
    func testRenderedCatchMarkerOnlyAppearsAtArrivalAndMatchesActualPitch() async throws {
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene),controller=UIViewController()
        let view=SKView(frame:CGRect(x:0,y:0,width:320,height:340));controller.view=view;window.rootViewController=controller;window.makeKeyAndVisible()
        defer {view.presentScene(nil);window.isHidden=true;previous?.makeKey()}
        let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:"left",kit:0)
        view.presentScene(scene)
        let marker=try XCTUnwrap(scene.childNode(withName:"receivedBaseball")),arrival=expectation(description:"arrival")
        var finished=false
        XCTAssertTrue(scene.demonstrate(reduceMotion:false,flightDuration:0.4,x:0.9,y:0.1,preparedRelease:true,matchJudgment:true,onArrival:{arrival.fulfill()},completion:{finished=true}))
        XCTAssertTrue(marker.isHidden)
        await fulfillment(of:[arrival],timeout:2)
        XCTAssertFalse(marker.isHidden);XCTAssertEqual(marker.position.x,scene.arrivalPoint(x:0.9,y:0.1).x,accuracy:0.01);XCTAssertEqual(marker.position.y,scene.arrivalPoint(x:0.9,y:0.1).y,accuracy:0.01)
        try await Task.sleep(for:.seconds(1.2));XCTAssertFalse(finished)
        try await Task.sleep(for:.seconds(1.1));XCTAssertTrue(finished)
        scene.cancelDelivery();XCTAssertTrue(marker.isHidden)
    }
    func testRenderedFairContactMovesBeforeHandoffAndCancellationDropsCallbacks() async throws {
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene),controller=UIViewController()
        let view=SKView(frame:CGRect(x:0,y:0,width:320,height:340));controller.view=view;window.rootViewController=controller;window.makeKeyAndVisible()
        defer {view.presentScene(nil);window.isHidden=true;previous?.makeKey()}
        let play=DetailedFieldRules.resolveFly(half:0,order:0,landing:FieldPoint(x:30,y:90),flight:4,
            runners:[nil,nil,nil],batter:FieldRunnerProfile(speed:60),outs:0,stats:nil,defending:false,ownBatter:true)
        for action in ["swing","bunt","pitch"] {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:"left",kit:2,role:action == "pitch" ? .pitcher:.batter)
            view.presentScene(scene)
            var callbacks=0
            let done=expectation(description:action+" shared contact clock")
            let started=ProcessInfo.processInfo.systemUptime
            let arrival={ @MainActor in
                callbacks+=1
                guard let h=scene.fieldHandoff else {XCTFail("contact clock missing");return}
                XCTAssertGreaterThanOrEqual(h.cutAt-h.startedAt,FieldContactPresentation.duration(play)-0.001)
                let origin=action == "pitch" ? CGPoint(x:0.54,y:0.43):MatchPresentation.batContact(action:action)
                XCTAssertGreaterThan(h.sourcePoint.x,origin.x)
                XCTAssertTrue(scene.childNode(withName:"receivedBaseball")!.isHidden)
            }
            if action == "pitch" {
                XCTAssertTrue(scene.demonstrate(reduceMotion:false,flightDuration:0.4,preparedRelease:true,fieldPlay:play,onArrival:arrival,completion:{done.fulfill()}))
            } else {
                scene.finishBat(action:action,outcome:"안타",reduced:false,fieldPlay:play,onArrival:arrival,completion:{done.fulfill()})
            }
            try await Task.sleep(for:.seconds(0.12));XCTAssertEqual(callbacks,0)
            await fulfillment(of:[done],timeout:3)
            XCTAssertEqual(callbacks,1);XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime-started,0.28)
            scene.cancelDelivery();XCTAssertNil(scene.fieldHandoff)
            scene.finishBat(action:"swing",outcome:"안타",reduced:false,fieldPlay:play,onArrival:{callbacks+=1},completion:{callbacks+=1})
            scene.cancelDelivery();try await Task.sleep(for:.seconds(0.4));XCTAssertEqual(callbacks,1)
        }
    }

    func testRenderedHomeRunContactBothRolesWaitsForFlightAndHandsOffWithoutCatch() async throws {
        let windowScene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous=windowScene.windows.first(where:\.isKeyWindow),window=UIWindow(windowScene:windowScene),controller=UIViewController()
        let view=SKView(frame:CGRect(x:0,y:0,width:320,height:340));controller.view=view;window.rootViewController=controller;window.makeKeyAndVisible()
        defer {view.presentScene(nil);window.isHidden=true;previous?.makeKey()}
        let event=MatchHomeRun(half:0,order:0,seed:42,power:80,quality:1,directionOffset:0,before:[nil,nil,nil],batter:FieldRunnerProfile(speed:60,own:true),defenderSpeeds:Array(repeating:60,count:9))
        for role in PlayerRole.allCases {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:"left",kit:2,role:role);view.presentScene(scene)
            var calls=0
            let done=expectation(description:role.rawValue+" home run contact")
            let arrival={ @MainActor in
                calls+=1
                guard let h=scene.fieldHandoff else {XCTFail("Missing contact handoff");return}
                XCTAssertGreaterThanOrEqual(h.cutAt-h.startedAt,0.28)
                XCTAssertTrue(scene.childNode(withName:"receivedBaseball")!.isHidden)
                let start=role == .batter ? MatchPresentation.batContact(action:"swing"):CGPoint(x:0.54,y:0.43)
                let target=HomeRunPresentation.sourcePoint(event,time:h.cutAt-h.startedAt,origin:start,size:scene.size)
                XCTAssertEqual(target.x,h.sourcePoint.x,accuracy:0.001);XCTAssertEqual(target.y,h.sourcePoint.y,accuracy:0.001)
            }
            if role == .pitcher {scene.demonstrate(reduceMotion:false,flightDuration:0.4,preparedRelease:true,homeRun:event,onArrival:arrival,completion:{done.fulfill()})}
            else {scene.finishBat(action:"swing",outcome:"홈런",reduced:false,homeRun:event,onArrival:arrival,completion:{done.fulfill()})}
            try await Task.sleep(for:.seconds(0.12));XCTAssertEqual(calls,0)
            await fulfillment(of:[done],timeout:3);XCTAssertEqual(calls,1)
            scene.cancelDelivery();XCTAssertNil(scene.fieldHandoff)
        }
    }

}


private struct BatterTimelineRenderProbe: View {
    let scene: BallparkScene
    let clock: MatchInputClock
    var body: some View {
        VStack(spacing: 4) {
            SpriteView(scene: scene).frame(width: 320, height: 320)
            MatchTimingGauge(phase: clock.phase, center: MatchDelivery.contactPhase, good: 0.09,
                             perfect: 0.025, label: "공 도착 = 노란 중심", batting: true).padding(8)
        }.frame(width: 320).background(GameTheme.board).foregroundStyle(GameTheme.paper)
    }
}

extension ManualMatchTests {
    func testV26PitchCatalogConnectsNamesSpeedGripsAndManualPitching() throws {
        let expected: [String: Int] = ["four-seam": 145, "two-seam": 141, "cutter": 138, "slider": 132, "curve": 118,
                                      "changeup": 125, "fork": 129, "sweeper": 127, "knuckle": 105]
        XCTAssertEqual(PitchType.allCases.count, 9)
        var extraImages = Set<Data>()
        for pitch in PitchType.allCases {
            let speed = MatchDelivery.pitch(code: pitch.rawValue, velocity: 62.5)
            XCTAssertEqual(speed.speed, expected[pitch.rawValue])
            XCTAssertEqual(PitchFlightPresentation(delivery: speed).flightDuration, 0.90 * 145 / Double(expected[pitch.rawValue]!), accuracy: 0.000001)
            let image = try XCTUnwrap(MatchGrip.image(code: pitch.rawValue))
            if ![PitchType.fourSeam, .slider, .changeup].contains(pitch) { extraImages.insert(try XCTUnwrap(image.pngData())) }
            var game = CareerMatch(random: 42, isHome: true, role: "pitcher", appearance: true, contact: 60, power: 60, discipline: 60, mastery: [pitch.rawValue: 50])
            game.controlVersion = 2; game.settle()
            let delivery = game.delivery(pitchCode: pitch.rawValue)
            try game.advance(.pitch, pitchCode: pitch.rawValue, control: ManualMatchInput(release: 0.68, pitchTarget: PitchTarget(x: delivery.x, y: delivery.y)))
            let result = try XCTUnwrap(game.lastManual)
            XCTAssertEqual(result.pitchCode, pitch.rawValue); XCTAssertEqual(result.speed, expected[pitch.rawValue])
            XCTAssertEqual(MatchPresentation.pitchName(result), pitch.label)
        }
        XCTAssertEqual(extraImages.count, 6, "Each extra grip must use its own authored atlas cell")
    }

    func testV26NewPitchPathsKeepEndpointsHandednessAndFastballFamilySeparation() {
        let size = CGSize(width: 320, height: 320), start = CGPoint(x: 150, y: 240), end = CGPoint(x: 170, y: 90)
        for role in PlayerRole.allCases { for pitch in PitchType.allCases {
            for hand in ["left", "right"] {
                XCTAssertEqual(MatchBallPath.point(from: start, to: end, size: size, role: role, hand: hand, code: pitch.rawValue, progress: 0), start)
                XCTAssertEqual(MatchBallPath.point(from: start, to: end, size: size, role: role, hand: hand, code: pitch.rawValue, progress: 1), end)
            }
            let normal = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: "four-seam", progress: 0.7)
            let right = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: pitch.rawValue, progress: 0.7)
            let left = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "left", code: pitch.rawValue, progress: 0.7)
            XCTAssertEqual(right.x + left.x, normal.x * 2, accuracy: 0.000001); XCTAssertEqual(right.y, left.y)
        } }
        XCTAssertEqual(PlayerInitialValues.breakingRating(["four-seam": 62, "slider": 55, "changeup": 42, "fork": 35]), 49.8, accuracy: 0.000001)
        XCTAssertEqual(PlayerInitialValues.breakingRating(["two-seam": 100, "cutter": 100, "curve": 40]), 40)
    }

    func testV25RecommendedTargetPreservesLegacyManualAndAutomaticResults() throws {
        for seed in 1...12 { for release in [0.0, 0.68, 0.81] {
            var legacy = match(role: .pitcher, seed: UInt64(seed))
            legacy.settle(); var recommended = legacy
            let plan = legacy.delivery(pitchCode: "four-seam")
            try legacy.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: release))
            try recommended.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: release, pitchTarget: PitchTarget(x: plan.x, y: plan.y)))
            XCTAssertEqual(recommended.lastManual?.pitchAim?.recommended, PitchTarget(x: plan.x, y: plan.y))
            XCTAssertEqual(recommended.random, legacy.random)
            recommended.lastManual?.pitchAim = nil
            XCTAssertEqual(recommended, legacy)
        } }
        let old = try JSONDecoder().decode(ManualMatchInput.self, from: Data(#"{"x":0.5,"y":0.5,"release":0.68}"#.utf8))
        XCTAssertNil(old.pitchTarget)
    }

    func testV25SelectedCourseUsesExistingControlScatterAndKeepsOutsideArrival() throws {
        for release in [0.0, 0.68, 0.82] {
            var a = match(role: .pitcher)
            a.settle(); var b = a
            let near = PitchTarget(x: 0.0, y: 1.0), far = PitchTarget(x: 0.8, y: 0.2)
            let plan = a.delivery(pitchCode: "four-seam")
            try a.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: release, pitchTarget: near))
            try b.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: release, pitchTarget: far))
            let first = try XCTUnwrap(a.lastManual), second = try XCTUnwrap(b.lastManual)
            XCTAssertEqual(first.x - near.x, second.x - far.x, accuracy: 0.000001)
            XCTAssertEqual(first.y - near.y, second.y - far.y, accuracy: 0.000001)
            XCTAssertEqual(first.quality, second.quality); XCTAssertEqual(first.speed, plan.speed)
            XCTAssertEqual(first.pitchAim, PitchAim(recommended: PitchTarget(x: plan.x, y: plan.y), target: near))
            if release == 0.68 { XCTAssertEqual(first.x, near.x); XCTAssertEqual(first.y, near.y) }
        }
        var sawOutside = false
        for seed in 1...12 {
            var game = match(role: .pitcher, seed: UInt64(seed))
            try game.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: 0, pitchTarget: PitchTarget(x: 0, y: 1)))
            let result = try XCTUnwrap(game.lastManual)
            sawOutside = sawOutside || result.x < 0 || result.y > 1
        }
        XCTAssertTrue(sawOutside, "Actual misses must not be clamped to the selectable board")
    }

    func testV25InvalidTargetsRejectBeforeMutationAndBatterCannotSubmitPitchTarget() throws {
        for target in [PitchTarget(x: -.infinity, y: 0), PitchTarget(x: 0, y: .nan), PitchTarget(x: -0.01, y: 0.5), PitchTarget(x: 0.5, y: 1.01)] {
            var game = match(role: .pitcher); let before = game
            XCTAssertThrowsError(try game.advance(.pitch, pitchCode: "four-seam", control: ManualMatchInput(release: 0.68, pitchTarget: target)))
            XCTAssertEqual(game, before)
        }
        var batter = match(); let before = batter
        XCTAssertThrowsError(try batter.advance(.swing, control: ManualMatchInput(timing: 0.82, pitchTarget: PitchTarget(x: 0.5, y: 0.5))))
        XCTAssertEqual(batter, before)
    }

    func testV25TargetSaveFailureRetryDiskResumeAndCompletionRemainOnce() throws {
        enum Injected: Error { case failure }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("course.store")
        let container = try CareerStore.makeContainer(url: url), context = container.mainContext
        let (player, calendar, record) = try fixture(in: context, role: .pitcher)
        let original = record.payload, revision = record.revision
        let input = ManualMatchInput(release: 0.82, pitchTarget: PitchTarget(x: 0.1, y: 0.9))
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
            input: .pitch, pitchCode: "four-seam", control: input, in: context, save: { _ in throw Injected.failure }))
        XCTAssertEqual(record.payload, original); XCTAssertEqual(record.revision, revision)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
            input: .pitch, pitchCode: "four-seam", control: input, in: context)
        let saved = try record.snapshot(), bytes = record.payload
        XCTAssertEqual(saved.lastManual?.pitchAim?.target, input.pitchTarget)
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
            input: .pitch, pitchCode: "four-seam", control: input, in: context))
        XCTAssertEqual(record.payload, bytes)
        let reopened = try CareerStore.makeContainer(url: url)
        let restored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CareerMatchRecord>()).first)
        XCTAssertEqual(restored.payload, bytes); XCTAssertEqual(try restored.snapshot(), saved)
        try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context)
        let fatigue = player.fatigue, completed = record.payload
        XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context))
        XCTAssertEqual(player.fatigue, fatigue); XCTAssertEqual(record.payload, completed)
    }

    func testV25BoardCoordinatesRoundTripAndLegacyArrivalHasNoInventedTarget() throws {
        for width in [84.0, 112, 280] { for x in [0.0, 0.2, 0.5, 0.8, 1] { for y in [0.0, 0.2, 0.8, 1] {
            let target = PitchTarget(x: x, y: y), size = CGSize(width: width, height: width)
            let marker = PitchCourseGeometry.marker(target, size: size)
            let restored = PitchCourseGeometry.target(at: marker, size: size)
            XCTAssertEqual(restored.x, x, accuracy: 0.000001); XCTAssertEqual(restored.y, y, accuracy: 0.000001)
        } } }
        XCTAssertEqual(PitchCourseGeometry.target(at: CGPoint(x: -20, y: 300), size: CGSize(width: 100, height: 100)), PitchTarget(x: 0, y: 1))
        let old = try JSONDecoder().decode(ManualMatchResult.self, from: Data(#"{"action":"pitch","quality":1,"grade":"PERFECT","x":0.2,"y":0.3,"speed":145,"outcome":"볼"}"#.utf8))
        XCTAssertNil(old.pitchAim)
    }

    func testV24FlightCalibrationSharesArrivalAcrossSpeedsHandsAndMotionSettings() {
        for speed in [110.5, 125, 129, 132, 145, 160] {
            let delivery = MatchDelivery(x: 0.3, y: 0.7, speed: Int(speed.rounded()), exactSpeed: speed)
            let flight = PitchFlightPresentation(delivery: delivery)
            XCTAssertEqual(flight.flightDuration, 0.90 * 145 / speed, accuracy: 0.000001)
            XCTAssertEqual(delivery.duration, 1.35 * 145 / speed, accuracy: 0.000001)
            let timeline = MatchInputTimeline(startedAt: 100, windup: MatchDelivery.windup, duration: flight.battingDuration)
            XCTAssertEqual(timeline.contactAt - timeline.releaseAt, flight.flightDuration, accuracy: 0.000001)
            XCTAssertEqual(timeline.phase(at: timeline.contactAt), 0.82, accuracy: 0.000001)
            for reduced in [false, true] { for hand in ["left", "right"] {
                let scene = BallparkScene(size: CGSize(width: 320, height: 320))
                scene.configure(hand: hand, kit: 0, role: .batter)
                var arrivals = 0
                XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: flight.flightDuration,
                    x: delivery.x, y: delivery.y, pitchCode: "fork", onArrival: { arrivals += 1 }, inputTimeline: timeline))
                scene.advanceDelivery(at: timeline.contactAt - 0.00001)
                XCTAssertEqual(scene.pitchStage, .flight); XCTAssertEqual(arrivals, 0)
                scene.advanceDelivery(at: timeline.contactAt)
                XCTAssertEqual(scene.pitchStage, .received); XCTAssertEqual(arrivals, 1)
                let marker = scene.childNode(withName: "receivedBaseball")!
                let target = scene.arrivalPoint(x: delivery.x, y: delivery.y)
                XCTAssertEqual(marker.position.x, target.x, accuracy: 0.0001)
                XCTAssertEqual(marker.position.y, target.y, accuracy: 0.0001)
                scene.advanceDelivery(at: timeline.contactAt + 1); XCTAssertEqual(arrivals, 1)
                scene.cancelDelivery()
            } }
        }
    }

    func testV24LateBreakSeparatesPitchTypesWithoutChangingEndpointsOrJudgments() throws {
        let size = CGSize(width: 320, height: 320), start = CGPoint(x: 160, y: 240), end = CGPoint(x: 160, y: 90)
        var game = match(); let original = game
        let payload = try JSONEncoder().encode(game)
        for role in PlayerRole.allCases {
            var drops = [Double]()
            for code in ["four-seam", "slider", "changeup", "fork"] {
                let delivery = game.delivery(pitchCode: code)
                _ = PitchFlightPresentation(delivery: delivery)
                let middle = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: code, progress: 0.7)
                drops.append(middle.y)
                var previous = start
                for step in 0...100 {
                    let p = Double(step) / 100
                    let right = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "right", code: code, progress: p)
                    let left = MatchBallPath.point(from: start, to: end, size: size, role: role, hand: "left", code: code, progress: p)
                    XCTAssertEqual(right.x + left.x, 320, accuracy: 0.000001)
                    XCTAssertEqual(right.y, left.y)
                    if step > 0 { XCTAssertLessThan(right.y, previous.y) }
                    previous = right
                    if step == 0 { XCTAssertEqual(right, start) }
                    if step == 100 { XCTAssertEqual(right, end) }
                }
            }
            XCTAssertTrue(zip(drops, drops.dropFirst()).allSatisfy { $0.0 < $0.1 })
        }
        XCTAssertEqual(game, original)
        XCTAssertEqual(try JSONDecoder().decode(CareerMatch.self, from: payload), game)
        let delivery = game.delivery()
        XCTAssertEqual(ManualMatchRules.battingQuality(input: ManualMatchInput(x: delivery.x, y: delivery.y, timing: 0.82), delivery: delivery, contact: 60), 1)
        try game.advance(.watch, control: ManualMatchInput())
        XCTAssertNotEqual(game, original)
    }

    func testV24BothSceneEntryPathsKeepMotionSettingIndependentFlightAndCatch() {
        let flight = PitchFlightPresentation(delivery: MatchDelivery(x: 0.5, y: 0.5, speed: 129))
        for role in PlayerRole.allCases { for hand in ["left", "right"] {
            var samples = [CGPoint]()
            for reduced in [false, true] {
                let scene = BallparkScene(size: CGSize(width: 320, height: 320))
                scene.configure(hand: hand, kit: 0, role: role)
                let start = ProcessInfo.processInfo.systemUptime
                var calls = 0
                XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: flight.flightDuration, pitchCode: "fork",
                                               preparedRelease: role == .pitcher, onArrival: { calls += 1 }))
                let windup = role == .batter ? MatchDelivery.windup : 0
                scene.advanceDelivery(at: start + windup + flight.flightDuration * 0.6)
                samples.append(scene.childNode(withName: "baseball")!.position)
                scene.advanceDelivery(at: start + windup + flight.flightDuration - 0.01)
                XCTAssertEqual(scene.pitchStage, .flight); XCTAssertEqual(calls, 0)
                scene.advanceDelivery(at: start + windup + flight.flightDuration + 0.01)
                XCTAssertEqual(scene.pitchStage, .received); XCTAssertEqual(calls, 1)
                scene.cancelDelivery()
            }
            XCTAssertEqual(samples[0].x, samples[1].x, accuracy: 0.5)
            XCTAssertEqual(samples[0].y, samples[1].y, accuracy: 0.5)
        } }
    }

    func testV24RenderedFastAndOffspeedArrivalWithBothRolesAndMotionSettings() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = windowScene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: windowScene)
        defer { window.isHidden = true; previous?.makeKey() }
        var metrics = [[String: Double]]()
        for role in PlayerRole.allCases { for reduced in [false, true] {
            let code = reduced ? "fork" : "four-seam"
            let speed = reduced ? 129 : 145
            let flight = PitchFlightPresentation(delivery: MatchDelivery(x: 0.5, y: 0.5, speed: speed))
            let scene = BallparkScene(size: CGSize(width: 320, height: 320))
            scene.configure(hand: reduced ? "left" : "right", kit: 0, role: role)
            let clock = MatchInputClock()
            let controller = UIHostingController(rootView: BatterTimelineRenderProbe(scene: scene, clock: clock))
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(100))
            let timeline = MatchInputTimeline(windup: role == .batter ? MatchDelivery.windup : 0, duration: flight.battingDuration)
            let arrived = expectation(description: "v24 " + role.rawValue + code)
            var arrivalTime = 0.0
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: flight.flightDuration, pitchCode: code,
                preparedRelease: role == .pitcher, onArrival: { arrivalTime = ProcessInfo.processInfo.systemUptime; arrived.fulfill() },
                inputTimeline: role == .batter ? timeline : nil))
            clock.start(timeline: timeline) {}
            try await Task.sleep(for: .seconds((role == .batter ? MatchDelivery.windup : 0) + flight.flightDuration * 0.65))
            XCTAssertEqual(scene.pitchStage, .flight)
            func capture(_ suffix: String) {
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "v24-\(role.rawValue)-\(code)-\(reduced ? "reduced" : "normal")-\(suffix)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            capture("flight")
            await fulfillment(of: [arrived], timeout: 3)
            let expected = (role == .batter ? MatchDelivery.windup : 0) + flight.flightDuration
            XCTAssertGreaterThanOrEqual(arrivalTime - timeline.startedAt, expected - 0.01)
            XCTAssertLessThan(arrivalTime - timeline.startedAt - expected, 0.09)
            XCTAssertEqual(scene.pitchStage, .received)
            XCTAssertEqual(timeline.phase(at: arrivalTime), 0.82, accuracy: 0.065)
            capture("received")
            metrics.append(["pitcher": role == .pitcher ? 1 : 0, "reduced": reduced ? 1 : 0, "speed": Double(speed),
                            "expectedArrival": expected, "actualArrival": arrivalTime - timeline.startedAt,
                            "arrivalPhase": timeline.phase(at: arrivalTime)])
            clock.stop(); scene.cancelDelivery()
        } }
        let data = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "v24-rendered-arrival-metrics"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testBatterSharedTimelineMapsMittArrivalToYellowCenterWithoutChangingSpeedBudget() {
        let duration = MatchDelivery(x: 0.5, y: 0.5, speed: 145).duration
        XCTAssertEqual(duration, 1.35, accuracy: 0.000001)
        let timeline = MatchInputTimeline(startedAt: 100, windup: MatchDelivery.windup, duration: duration)
        XCTAssertEqual(timeline.releaseAt, 100.35, accuracy: 0.000001)
        XCTAssertEqual(timeline.contactAt, 101.457, accuracy: 0.000001)
        XCTAssertEqual(timeline.phase(at: timeline.releaseAt), 0, accuracy: 0.000001)
        XCTAssertEqual(timeline.phase(at: timeline.contactAt), MatchDelivery.contactPhase, accuracy: 0.000001)
        for reduced in [false, true] {
            XCTAssertEqual(DeliveryPresentation.flight(duration, reduced: reduced, role: .batter), duration)
            let scene = BallparkScene(size: CGSize(width: 320, height: 320))
            scene.configure(hand: "right", kit: 0, role: .batter)
            let marker = scene.childNode(withName: "receivedBaseball")!
            var calls = 0
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: duration, onArrival: { calls += 1 }, inputTimeline: timeline))
            scene.advanceDelivery(at: timeline.releaseAt)
            XCTAssertTrue(marker.isHidden); XCTAssertEqual(calls, 0)
            scene.advanceDelivery(at: timeline.contactAt - 0.00001)
            XCTAssertTrue(marker.isHidden); XCTAssertEqual(calls, 0)
            scene.advanceDelivery(at: timeline.contactAt)
            XCTAssertFalse(marker.isHidden); XCTAssertEqual(calls, 1)
            XCTAssertEqual(marker.position.x, scene.arrivalPoint(x: 0.5, y: 0.5).x, accuracy: 0.001)
            scene.advanceDelivery(at: timeline.contactAt + 0.1); XCTAssertEqual(calls, 1)
            scene.cancelDelivery()
        }
    }

    func testBatterEarlyInputAndCancelCannotShowCatchOrResolveBeforeSharedContact() {
        for reduced in [false, true] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 320))
            scene.configure(hand: "left", kit: 0, role: .batter)
            let timeline = MatchInputTimeline(windup: MatchDelivery.windup, duration: 1.35)
            var calls = 0, completions = 0
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: 1.35, inputTimeline: timeline))
            scene.finishBat(action: "swing", outcome: "헛스윙", reduced: reduced, matchJudgment: true,
                            onArrival: { calls += 1 }, completion: { completions += 1 })
            scene.advanceDelivery(at: timeline.contactAt - 0.001)
            XCTAssertTrue(scene.childNode(withName: "receivedBaseball")!.isHidden); XCTAssertEqual(calls, 0)
            scene.advanceDelivery(at: timeline.contactAt)
            XCTAssertEqual(calls, 1); XCTAssertEqual(completions, 0)
            scene.advanceDelivery(at: timeline.contactAt + DeliveryPresentation.receipt(reduced: reduced, match: true) + 0.01)
            XCTAssertEqual(completions, 1)
            scene.advanceDelivery(at: timeline.contactAt + 10); XCTAssertEqual(completions, 1)
            let next = MatchInputTimeline(windup: MatchDelivery.windup, duration: 1.35)
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, onArrival: { calls += 1 }, inputTimeline: next))
            scene.finishBat(action: "watch", outcome: "볼", reduced: reduced, onArrival: { calls += 1 }, completion: { completions += 1 })
            scene.cancelDelivery(); scene.advanceDelivery(at: next.contactAt + 10)
            XCTAssertEqual(calls, 1); XCTAssertEqual(completions, 1)
        }
    }

    func testRenderedBatterCatchAndGaugeUseSameTimeWithBothMotionSettings() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene)
        var samples = [[String: Double]]()
        defer { window.isHidden = true; previous?.makeKey() }
        for reduced in [false, true] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 320)); scene.configure(hand: "right", kit: 0, role: .batter)
            let clock = MatchInputClock()
            let controller = UIHostingController(rootView: BatterTimelineRenderProbe(scene: scene, clock: clock))
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(120))
            let duration = MatchDelivery(x: 0.5, y: 0.5, speed: 145).duration
            let timeline = MatchInputTimeline(windup: MatchDelivery.windup, duration: duration)
            let arrived = expectation(description: reduced ? "reduced mitt at center" : "normal mitt at center")
            var arrivalTime = 0.0, arrivalPhase = 0.0
            XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: duration, onArrival: {
                arrivalTime = ProcessInfo.processInfo.systemUptime
                arrivalPhase = clock.currentPhase
                arrived.fulfill()
            }, inputTimeline: timeline))
            clock.start(timeline: timeline) {}
            try await Task.sleep(for: .milliseconds(700))
            XCTAssertTrue(scene.childNode(withName: "receivedBaseball")!.isHidden)
            let beforeImage = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let before = XCTAttachment(image: beforeImage); before.name = reduced ? "v23-reduced-in-flight" : "v23-normal-in-flight"; before.lifetime = .keepAlways; add(before)
            await fulfillment(of: [arrived], timeout: 3)
            XCTAssertGreaterThanOrEqual(arrivalTime, timeline.contactAt)
            XCTAssertEqual(arrivalPhase, MatchDelivery.contactPhase, accuracy: 0.04)
            XCTAssertFalse(scene.childNode(withName: "receivedBaseball")!.isHidden)
            samples.append(["reduced": reduced ? 1 : 0, "expectedArrival": timeline.contactAt - timeline.startedAt,
                            "actualArrival": arrivalTime - timeline.startedAt, "arrivalPhase": arrivalPhase,
                            "centerPhase": MatchDelivery.contactPhase])
            let afterImage = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let after = XCTAttachment(image: afterImage); after.name = reduced ? "v23-reduced-received" : "v23-normal-received"; after.lifetime = .keepAlways; add(after)
            clock.stop(); scene.cancelDelivery()
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self)); attachment.name = "v23-rendered-arrival-metrics"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
