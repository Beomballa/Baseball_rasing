import XCTest
import SpriteKit
import UIKit
import SwiftData
import SwiftUI
@testable import BM

extension ManualMatchTests {
    func testV143FinishHoldsItsAuthoredFootPositionAndResetsOnCancel() throws {
        let scene = BallparkScene(size: CGSize(width: 320, height: 340))
        scene.configure(hand: "right", kit: 1, role: .pitcher)
        let pitcher = try XCTUnwrap(scene.childNode(withName: "animatedPitcher") as? SKSpriteNode)
        let rig = try XCTUnwrap(pitcher.childNode(withName: "fullBodyPitcher") as? FullBodyPitcherNode)
        let body = try XCTUnwrap(rig.childNode(withName: "pitcherWholeBody") as? SKSpriteNode)
        let width = pitcher.size.width, anchor = pitcher.anchorPoint
        XCTAssertTrue(rig.usesRefinedDelivery)
        rig.apply(progress: 2, canvas: width, anchor: anchor)
        let texture = body.texture, position = body.position, hand = rig.handPoint, index = rig.frameIndex
        rig.apply(progress: 2.2, canvas: width, anchor: anchor)
        XCTAssertEqual(rig.frameIndex, index)
        XCTAssertTrue(body.texture === texture)
        XCTAssertEqual(body.position, position)
        XCTAssertEqual(rig.handPoint, hand)
        rig.apply(progress: 2.2, canvas: width * 2, anchor: anchor)
        XCTAssertEqual(body.size.width, width * 2)
        XCTAssertEqual(rig.handPoint.x, hand.x * 2, accuracy: 0.000001)
        XCTAssertEqual(rig.handPoint.y, hand.y * 2, accuracy: 0.000001)
        scene.cancelDelivery()
        XCTAssertEqual(rig.frameIndex, 0)
        XCTAssertEqual(body.size.width, width)
    }

    func testV124DarkTrouserShadowsKeepClothInsteadOfLeatherColor() throws {
        let camera = try XCTUnwrap(FullBodyPitcherArt.manifest).back
        let url = try XCTUnwrap(Bundle.main.url(forResource: camera.file, withExtension: "png", subdirectory: "MatchArt"))
        let source = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let style = GameUniformStyle(id: "qa-v124-cloth", pattern: "solid", body: 0x245d51, sleeves: 0x503040,
            cap: 0x503040, brim: 0x342539, trim: 0xf4ce61, ink: 0xf1f3ee, mark: [], pants: 0x9eacb8)
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { p in
                let context = CGContext(data: p.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        var checked = 0
        for frame in camera.frames {
            let rect = frame.rect
            let crop = try XCTUnwrap(source.cropping(to: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])))
            let rendered = try XCTUnwrap(FullBodyPitcherArt.image(frame: frame, file: camera.file, kit: style.body,
                style: style, appearance: PlayerAppearance(kit: 1), number: 27, mirrored: false)?.cgImage)
            let original = pixels(crop), actual = pixels(rendered)
            for y in 0..<128 where Double(y)/128 > frame.shirt[1] + frame.shirt[3] * 0.8 {
                for x in 0..<128 {
                    let sx = min(rect[2]-1, Int((Double(x)+0.5)*Double(rect[2])/128))
                    let sy = min(rect[3]-1, Int((Double(y)+0.5)*Double(rect[3])/128))
                    let i = (sy*rect[2]+sx)*4, j = (y*128+x)*4
                    guard original[i+3] > 200, actual[j+3] == 255 else { continue }
                    let rgb = (0..<3).map { Double(original[i+$0])/Double(original[i+3]) }
                    let high = rgb.max()!, low = rgb.min()!
                    guard high > 0.24, high <= 0.5, (high-low)/high < 0.25 else { continue }
                    let observed = (0..<3).map { Double(actual[j+$0]) }
                    let target = [158.0, 172.0, 184.0]
                    for c in 0..<3 {
                        XCTAssertEqual(observed[c]/observed.reduce(0,+), target[c]/target.reduce(0,+), accuracy: 0.015,
                            "A dark neutral trouser pixel must keep the team's cloth hue, not become leather/skin")
                    }
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 100, "Exercise actual dark folds across the atlas, not just white cloth highlights")
    }

    func testV124PitchZoneStaysOnPlateAcrossThrowingHandsAndBatterSides() throws {
        for hand in ["left", "right"] { for side in [OpponentBatterSide.left, .right] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 1, role: .pitcher, batterSide: side)
            XCTAssertEqual(scene.size.width / scene.size.height, 1219.0 / 1290.0, accuracy: 0.000001,
                           "SpriteKit and the overlay must share the artwork aspect ratio without integer truncation")
            let zone = try XCTUnwrap(scene.childNode(withName: "pitchStrikeZone") as? SKShapeNode)
            let bounds = try XCTUnwrap(zone.path).boundingBox
            XCTAssertEqual(bounds.midX / scene.size.width, 0.5, accuracy: 0.000001,
                           "The catcher and plate stay centered when the pitching hand changes")
            XCTAssertEqual(1 - bounds.midY / scene.size.height, 0.465, accuracy: 0.000001)
            XCTAssertEqual(bounds.minX / scene.size.width, 0.434, accuracy: 0.000001)
            XCTAssertEqual(bounds.maxX / scene.size.width, 0.566, accuracy: 0.000001)
            XCTAssertEqual(1 - bounds.maxY / scene.size.height, 0.411, accuracy: 0.000001)
            XCTAssertEqual(1 - bounds.minY / scene.size.height, 0.519, accuracy: 0.000001)
            for value in [0.0, 0.2, 0.5, 0.8, 1.0] {
                let point = scene.arrivalPoint(x: value, y: value)
                let marker = MatchPitchProjection(role: .pitcher).viewPoint(x: value, y: value, size: scene.size)
                XCTAssertEqual(point.x, marker.x, accuracy: 0.000001)
                XCTAssertEqual(scene.size.height - point.y, marker.y, accuracy: 0.000001)
            }
        }}
        let batter = MatchPitchProjection(role: .batter)
        let batterEdge = batter.normalizedPoint(x: 0, y: 0)
        XCTAssertEqual(batterEdge.x, 0.42, accuracy: 0.000001)
        XCTAssertEqual(batterEdge.y, 0.57, accuracy: 0.000001,
                       "The existing batter-camera aiming plane stays unchanged")
    }

    func testV124PitchTargetCornersRemainWholeAtAimExtremesAndAspectFitSizes() throws {
        let targets = [PitchTarget(x: 0, y: 0), PitchTarget(x: 1, y: 0), PitchTarget(x: 0, y: 1),
                       PitchTarget(x: 1, y: 1), PitchTarget(x: 0.5, y: 0.5)]
        for size in [CGSize(width: 320, height: 320 * 1290.0 / 1219.0),
                     CGSize(width: 375, height: 667), CGSize(width: 667, height: 375)] {
            for target in targets {
                let renderer = ImageRenderer(content: PitchingTargetMarker(target: target)
                    .frame(width: size.width, height: size.height))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage?.cgImage)
                let width = image.width, height = image.height
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                pixels.withUnsafeMutableBytes { data in
                    let context = CGContext(data: data.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
                    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
                var minX = width, maxX = -1, minY = height, maxY = -1
                for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 128 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }}
                XCTAssertGreaterThanOrEqual(maxX - minX + 1, 13, "A target at the aim boundary must not lose half of its marker")
                XCTAssertGreaterThanOrEqual(maxY - minY + 1, 13)
                XCTAssertGreaterThan(minX, 0); XCTAssertLessThan(maxX, width - 1)
                XCTAssertGreaterThan(minY, 0); XCTAssertLessThan(maxY, height - 1)
                let point = MatchPitchProjection(role: .pitcher).viewPoint(x: target.x, y: target.y, size: size)
                XCTAssertEqual(Double(minX + maxX) / 2, point.x, accuracy: 1)
            }
        }
    }

    func testV124PitchArrivalUsesDisplayedPlatePlaneAtCenterAndEdgesForBothHands() throws {
        for hand in ["left", "right"] { for target in [PitchTarget(x: 0, y: 0), PitchTarget(x: 1, y: 1), PitchTarget(x: 0.5, y: 0.5)] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 1, role: .pitcher)
            XCTAssertTrue(scene.demonstrate(reduceMotion: false, flightDuration: 0.5,
                x: target.x, y: target.y, preparedRelease: true))
            scene.advanceDelivery(at: ProcessInfo.processInfo.systemUptime + 0.6)
            let received = try XCTUnwrap(scene.childNode(withName: "receivedBaseball"))
            XCTAssertFalse(received.isHidden)
            XCTAssertEqual(received.position.x / scene.size.width, 0.5 + (target.x - 0.5) * 0.22, accuracy: 0.000001)
            XCTAssertEqual(1 - received.position.y / scene.size.height, 0.465 + (target.y - 0.5) * 0.18, accuracy: 0.000001)
            scene.cancelDelivery()
        }}
    }

    func testV143RenderedPitcherPlantsTowardHomeAndReleasesFromProjectedHand() throws {
        var plantedByHand: [String: CGPoint] = [:]
        for hand in ["left", "right"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 1, role: .pitcher)
            let pitcher = try XCTUnwrap(scene.childNode(withName: "animatedPitcher") as? SKSpriteNode)
            let rig = try XCTUnwrap(pitcher.childNode(withName: "fullBodyPitcher") as? FullBodyPitcherNode)
            XCTAssertTrue(rig.usesRefinedDelivery)
            let mound = pitcher.position
            let home = CGPoint(x: scene.size.width * 0.5, y: scene.size.height * (1 - 0.55))
            var plant: CGPoint?
            for progress in [0.88, 0.95, 1.0, 1.3, 1.78, 2] {
                rig.apply(progress: progress, canvas: pitcher.size.width, anchor: pitcher.anchorPoint)
                let foot = rig.convert(rig.leadFoot, to: scene)
                if let plant {
                    XCTAssertEqual(foot.x, plant.x, accuracy: 0.000001)
                    XCTAssertEqual(foot.y, plant.y, accuracy: 0.000001,
                                   "After landing, the displayed foot stays planted through follow-through")
                } else { plant = foot }
            }
            let foot = try XCTUnwrap(plant)
            plantedByHand[hand] = foot
            XCTAssertGreaterThan(foot.y, mound.y, "The stride must advance toward home, not remain on a horizontal mound line")
            XCTAssertLessThan(hypot(foot.x - home.x, foot.y - home.y), hypot(mound.x - home.x, mound.y - home.y))
            XCTAssertEqual(abs(foot.x - mound.x), 45.87287270902384, accuracy: 0.001)
            XCTAssertEqual(foot.y - mound.y, 6.8334276987739, accuracy: 0.001)
            XCTAssertTrue(scene.demonstrate(reduceMotion: false, flightDuration: 1, preparedRelease: true))
            let ball = try XCTUnwrap(scene.childNode(withName: "baseball"))
            let release = rig.convert(rig.handPoint, to: scene)
            XCTAssertEqual(ball.position.x, release.x, accuracy: 0.000001)
            XCTAssertEqual(ball.position.y, release.y, accuracy: 0.000001)
            scene.cancelDelivery()
        }
        let left = try XCTUnwrap(plantedByHand["left"]), right = try XCTUnwrap(plantedByHand["right"])
        XCTAssertEqual(left.x + right.x, 320, accuracy: 0.000001)
        XCTAssertEqual(left.y, right.y, accuracy: 0.000001)
    }
}

@MainActor final class ManualMatchTests: XCTestCase {
    func testV121DisplayReceiptRejectsMutationInsideSaveCallback() async throws {
        let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
        let (player,calendar,record)=try fixture(in:context)
        let prepared=try await CareerMatchStore.prepareManual(player:player,state:calendar,record:record,revision:record.revision,
            input:.watch,pitchCode:nil,control:ManualMatchInput())
        let committed=try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context,
            save:{context in try context.save();record.payload=Data("changed-by-observer".utf8)})
        var display=MatchDisplaySnapshot()
        XCTAssertFalse(committed.matches(record))
        XCTAssertThrowsError(try display.refresh(record,committed:committed))
        context.rollback()
        XCTAssertNoThrow(try record.snapshot())
    }
    func testV121LastManualRewardFailureRetryIsAtomic() async throws {
        enum Injected:Error {case save}
        let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
        let (player,calendar,record)=try fixture(in:context)
        var expected=try record.snapshot(),lastBefore=expected
        for _ in 0..<200 where !expected.completed {
            lastBefore=expected
            let ball=expected.delivery(pitchCode:"four-seam")
            try expected.advance(.swing,pitchCode:"four-seam",control:ManualMatchInput(x:ball.x,y:ball.y,timing:MatchDelivery.contactPhase))
        }
        XCTAssertTrue(expected.completed);XCTAssertFalse(lastBefore.completed)
        record.payload=try JSONEncoder().encode(lastBefore);try context.save()
        let payload=record.payload,values=try CareerLifecycleStore.values(player:player,in:context),fatigue=player.fatigue
        let ball=lastBefore.delivery(pitchCode:"four-seam")
        let prepared=try await CareerMatchStore.prepareManual(player:player,state:calendar,record:record,revision:record.revision,
            input:.swing,pitchCode:"four-seam",control:ManualMatchInput(x:ball.x,y:ball.y,timing:MatchDelivery.contactPhase))
        XCTAssertFalse(prepared.preparedOnMainThread)
        var saves=0
        XCTAssertThrowsError(try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context,
            save:{_ in saves+=1;throw Injected.save}))
        XCTAssertEqual(record.payload,payload);XCTAssertFalse(record.completed);XCTAssertEqual(player.fatigue,fatigue)
        XCTAssertEqual(try CareerLifecycleStore.values(player:player,in:context),values)
        let committed=try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context,
            save:{context in saves+=1;try context.save()})
        XCTAssertTrue(record.completed);XCTAssertEqual(committed.updated.random,expected.random)
        XCTAssertEqual(committed.updated.line,expected.line);XCTAssertEqual(committed.updated.abilityExperience,expected.abilityExperience)
        for award in expected.abilityExperience?.result?.awards ?? [] {
            XCTAssertEqual(try CareerTrainingStore.value(player:player,code:nil,kind:award.kind,in:context),award.after)
        }
        let after=record.payload,finalValues=try CareerLifecycleStore.values(player:player,in:context),finalFatigue=player.fatigue
        XCTAssertThrowsError(try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context))
        XCTAssertEqual(saves,2);XCTAssertEqual(record.payload,after);XCTAssertEqual(player.fatigue,finalFatigue)
        XCTAssertEqual(try CareerLifecycleStore.values(player:player,in:context),finalValues)
    }
    func testV121PendingBatDecisionDoesNotInventReceiptOrDuplicateResult() throws {
        let scene=BallparkScene(size:CGSize(width:320,height:320));scene.configure(hand:"right",kit:1,role:.batter)
        let start=ProcessInfo.processInfo.systemUptime,timeline=MatchInputTimeline(startedAt:start,windup:0,duration:1)
        XCTAssertTrue(scene.demonstrate(reduceMotion:false,inputTimeline:timeline))
        scene.awaitBatDecision()
        scene.advanceDelivery(at:timeline.contactAt+0.1)
        let received=try XCTUnwrap(scene.childNode(withName:"receivedBaseball"))
        XCTAssertTrue(received.isHidden,"백그라운드 확정 대기 중 포구 공을 미리 표시하면 안 됨")
        var arrivals=0,completions=0
        scene.finishBat(action:"swing",outcome:"안타",reduced:false,onArrival:{arrivals+=1}) {completions+=1}
        scene.advanceDelivery(at:timeline.contactAt+0.2)
        XCTAssertTrue(received.isHidden)
        scene.advanceDelivery(at:start+5);scene.advanceDelivery(at:start+6)
        XCTAssertEqual(arrivals,1);XCTAssertEqual(completions,1)
        scene.cancelDelivery()
        XCTAssertTrue(scene.demonstrate(reduceMotion:false,inputTimeline:timeline))
        scene.advanceDelivery(at:timeline.contactAt+0.1)
        XCTAssertFalse(received.isHidden,"취소 뒤 다음 투구의 정상 포구 표시를 복구해야 함")
    }
    func testV121PreparedManualMatchesSimulationAndDisplayCacheBothRoles() async throws {
        for role in PlayerRole.allCases {
            let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            let (player,calendar,record)=try fixture(in:context,role:role)
            var display=MatchDisplaySnapshot();_ = try display.refresh(record)
            for _ in 0..<3 where !record.completed {
                let before=try record.snapshot(),delivery=before.delivery(pitchCode:"four-seam")
                let input:MatchInput=role == .batter ? .swing:.pitch
                let control=role == .batter ? ManualMatchInput(x:delivery.x,y:delivery.y,timing:MatchDelivery.contactPhase):ManualMatchInput(release:ManualMatchRules.releaseCenter)
                var expected=before;try expected.advance(input,pitchCode:"four-seam",control:control)
                let prepared=try await CareerMatchStore.prepareManual(player:player,state:calendar,record:record,
                    revision:record.revision,input:input,pitchCode:"four-seam",control:control)
                XCTAssertFalse(prepared.preparedOnMainThread)
                XCTAssertEqual(try record.snapshot(),before,"계산 완료만으로 원장을 변경하지 않음")
                let committed=try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context)
                XCTAssertEqual(committed.previous,before)
                XCTAssertEqual(try display.refresh(record,committed:committed),expected)
                XCTAssertEqual(try record.snapshot(),expected)
                _ = try display.refresh(record)
                XCTAssertEqual(display.decodeCount,1,"검증된 저장 결과를 표시할 때 원장 전체를 다시 해석하지 않음")
                let payload=record.payload
                XCTAssertThrowsError(try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context))
                XCTAssertEqual(record.payload,payload)
            }
        }
    }

    func testV121PreparedManualRejectsStaleMetadataAndCancellation() async throws {
        for damage in 0..<4 {
            let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            let (player,calendar,record)=try fixture(in:context)
            let prepared=try await CareerMatchStore.prepareManual(player:player,state:calendar,record:record,revision:record.revision,
                input:.watch,pitchCode:nil,control:ManualMatchInput())
            let original=record.payload
            switch damage {
            case 0:calendar.revision+=1
            case 1:record.payload=Data("damaged".utf8)
            case 2:player.fatigue+=1
            default:record.opponentID="changed-without-revision"
            }
            let altered=record.payload
            XCTAssertThrowsError(try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context))
            XCTAssertEqual(record.payload,altered);XCTAssertEqual(record.revision,0)
            if damage != 1 {XCTAssertEqual(record.payload,original)}
        }
        let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
        let (player,calendar,record)=try fixture(in:context),payload=record.payload
        let job=Task {try await CareerMatchStore.prepareManual(player:player,state:calendar,record:record,revision:record.revision,
            input:.watch,pitchCode:nil,control:ManualMatchInput())}
        job.cancel()
        do {_ = try await job.value;XCTFail("취소된 준비는 적용 결과를 반환하면 안 됨")} catch is CancellationError {}
        XCTAssertEqual(record.payload,payload);XCTAssertEqual(record.revision,0)
    }

    func testV121PreparedManualSaveFailureRetryAndCompletionRemainOnce() async throws {
        enum Injected:Error {case save}
        for role in PlayerRole.allCases {
            let container=try CareerStore.makeContainer(inMemory:true),context=container.mainContext
            let (player,calendar,record)=try fixture(in:context,role:role)
            let payload=record.payload,revision=record.revision,calendarRevision=calendar.revision,fatigue=player.fatigue
            let match=try record.snapshot(),delivery=match.delivery(pitchCode:"four-seam")
            let input:MatchInput=role == .batter ? .swing:.pitch
            let control=role == .batter ? ManualMatchInput(x:delivery.x,y:delivery.y,timing:MatchDelivery.contactPhase):ManualMatchInput(release:ManualMatchRules.releaseCenter)
            let prepared=try await CareerMatchStore.prepareManual(player:player,state:calendar,record:record,revision:revision,
                input:input,pitchCode:"four-seam",control:control)
            XCTAssertThrowsError(try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context,
                save:{_ in throw Injected.save}))
            XCTAssertEqual(record.payload,payload);XCTAssertEqual(record.revision,revision)
            XCTAssertEqual(calendar.revision,calendarRevision);XCTAssertEqual(player.fatigue,fatigue)
            let committed=try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context)
            var display=MatchDisplaySnapshot();_ = try display.refresh(record,committed:committed)
            let valid=record.payload;record.payload=Data("damaged".utf8)
            XCTAssertThrowsError(try display.refresh(record,committed:committed),"표시 캐시도 원문이 달라지면 재검증해야 함")
            record.payload=valid
            try CareerMatchStore.advance(player:player,state:calendar,record:record,revision:record.revision,input:.automatic,in:context)
            let completed=record.payload,finalFatigue=player.fatigue
            XCTAssertTrue(record.completed)
            XCTAssertThrowsError(try CareerMatchStore.commitManual(prepared,player:player,state:calendar,record:record,in:context))
            let reopened=try CareerMatchStore.start(player:player,state:calendar,in:context)
            XCTAssertEqual(reopened.payload,completed);XCTAssertEqual(player.fatigue,finalFatigue)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerMatchRecord>()),1)
        }
    }
    func testV121ManualCommitStageAuditPreservesSimulationBothRoles() throws {
        let wasEnabled=MatchRenderMetrics.enabled
        MatchRenderMetrics.enabled=true
        defer {MatchRenderMetrics.enabled=wasEnabled;MatchRenderMetrics.reset()}
        for role in PlayerRole.allCases {
            let container=try CareerStore.makeContainer(inMemory:true)
            let (player,calendar,record)=try fixture(in:container.mainContext,role:role)
            MatchRenderMetrics.reset()
            for _ in 0..<3 where !record.completed {
                let before=try record.snapshot(),delivery=before.delivery(pitchCode:"four-seam")
                let input:MatchInput=role == .batter ? .swing:.pitch
                let control=role == .batter ? ManualMatchInput(x:delivery.x,y:delivery.y,timing:MatchDelivery.contactPhase):ManualMatchInput(release:ManualMatchRules.releaseCenter)
                var expected=before;try expected.advance(input,pitchCode:"four-seam",control:control)
                try CareerMatchStore.advance(player:player,state:calendar,record:record,revision:record.revision,input:input,pitchCode:"four-seam",control:control,in:container.mainContext)
                XCTAssertEqual(try record.snapshot(),expected)
            }
            let data=try JSONEncoder().encode(MatchRenderMetrics.lifecycle)
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            attachment.name="v121-commit-stages-"+role.rawValue;attachment.lifetime = .keepAlways;add(attachment)
        }
    }
    private func visiblePitcher(in actor: SKNode) throws -> SKSpriteNode {
        try XCTUnwrap(actor.childNode(withName:"fullBodyPitcher")?.childNode(withName:"pitcherWholeBody") as? SKSpriteNode)
    }
    func testV116BatterSequenceAdvancesThroughPlantContactAndFollow() {
        let phases=[0.0,0.8,1.3,1.9,2.0,2.5,3.0]
        XCTAssertEqual(phases.map {BatterSequencePose(phase:$0).stage},[.ready,.load,.plant,.turn,.contact,.followThrough,.followThrough])
        XCTAssertEqual(phases.map {BatterSequencePose(phase:$0).frame},[0,1,1,1,2,3,3])
        let plant=(0...20).map {BatterSequencePose(phase:Double($0)/10).plant}
        XCTAssertEqual(plant,plant.sorted());XCTAssertEqual(plant.first,0);XCTAssertEqual(plant.last,1)
    }

    func testV116OpponentSequenceBothSidesHandsAndNextBatterReset() throws {
        for hand in ["right","left"] {for side in OpponentBatterSide.allCases {
            let scene=BallparkScene(size:CGSize(width:320,height:340))
            var look=PlayerAppearance();look.uniformTeamID="kbo-0";look.opponentUniformTeamID="kbo-1"
            scene.configure(hand:hand,kit:1,appearance:look,batterSide:side)
            let batter=try XCTUnwrap(scene.childNode(withName:"animatedBatter") as? SKSpriteNode)
            let pitcher=try XCTUnwrap(scene.childNode(withName:"animatedPitcher") as? SKSpriteNode)
            let visible=try visiblePitcher(in:pitcher)
            let ready=batter.texture,pitcherReady=visible.texture,facing=batter.xScale
            let view=SKView(frame:CGRect(origin:.zero,size:scene.size));view.presentScene(scene);scene.isPaused=true
            func capture(_ stage:String) throws {
                let shot=XCTAttachment(image:UIImage(cgImage:try XCTUnwrap(view.texture(from:scene)?.cgImage())))
                shot.name="v116-\(hand)-\(side.rawValue)-\(stage)";shot.lifetime = .keepAlways;add(shot)
                XCTAssertEqual(batter.xScale,facing,"같은 스윙 중 좌우 반전 금지")
            }
            try capture("00-ready")
            for (index,phase) in [0.2,0.4,0.65].enumerated() {scene.preparePitch(phase:phase,reduced:false);try capture("0\(index+1)-pitch-prepare")}
            XCTAssertTrue(scene.demonstrate(reduceMotion:false,flightDuration:1,outcome:"헛스윙",preparedRelease:true))
            let start=ProcessInfo.processInfo.systemUptime
            try capture("04-release")
            for (stage,time) in [("05-load",0.80),("06-plant",0.96),("07-contact",1.01),("08-follow",1.20),("09-settled",1.50)] {
                scene.advanceDelivery(at:start+time);try capture(stage)
            }
            XCTAssertFalse(ready === batter.texture)
            scene.advanceDelivery(at:start+4);XCTAssertTrue(pitcherReady === visible.texture,"판정 확인 뒤 투수 세트 자세 복귀")
            scene.cancelDelivery();XCTAssertTrue(ready === batter.texture);try capture("10-next-batter-ready")
            view.presentScene(nil)
        }}
    }

    func testV116BattedContactDoesNotLeaveCaughtBallAndReceiptCompletesOnce() throws {
        let scene=BallparkScene(size:CGSize(width:320,height:320));scene.configure(hand:"right",kit:1,role:.batter)
        let start=ProcessInfo.processInfo.systemUptime,timeline=MatchInputTimeline(startedAt:start,windup:0.35,duration:1.4)
        var arrivals=0,completions=0
        XCTAssertTrue(scene.demonstrate(reduceMotion:false,inputTimeline:timeline))
        scene.finishBat(action:"swing",outcome:"파울",reduced:false,onArrival:{arrivals += 1}) {completions += 1}
        scene.advanceDelivery(at:timeline.contactAt+0.01)
        XCTAssertEqual(arrivals,1)
        let received=try XCTUnwrap(scene.childNode(withName:"receivedBaseball"))
        XCTAssertTrue(received.isHidden,"접촉한 공을 동시에 미트 포구 공으로 표시하면 안 됨")
        scene.advanceDelivery(at:timeline.contactAt+4);scene.advanceDelivery(at:timeline.contactAt+5)
        XCTAssertEqual(arrivals,1);XCTAssertEqual(completions,1)
    }

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
                let source = try XCTUnwrap(MatchArt.cell(PlayerMotionArt.sourceName(role: role), column: frame % 3, row: frame / 3, columns: 3, rows: 2))
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
            let original = try motionPixels(XCTUnwrap(MatchArt.cell(PlayerMotionArt.sourceName(role: role), column:0,row:0,columns:3,rows:2)))
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
                XCTAssertEqual(ball?.position.x ?? -1,320 * (0.5 + 0.25 * 0.22),accuracy:0.01)
                XCTAssertEqual(ball?.position.y ?? -1,scene.size.height * (1 - (0.465 - 0.2 * 0.18)),accuracy:0.01)
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
                let end=scene.arrivalPoint(x:0.5,y:0.5)
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
                player.pitches = [CareerPitchMastery(code: "knuckle", name: "너클", mastery: 88.1234, order: 2),
                                  CareerPitchMastery(code: "slider", name: "슬라이더", mastery: 32.5678, order: 1),
                                  CareerPitchMastery(code: "four-seam", name: "포심", mastery: 93.4567, order: 0)]
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
    func testV118RigidBodyLengthsDoNotStretchDuringPitch() {
        for i in 0...1272 {
            let pose=PitcherContinuousPose(progress:Double(i)/480)
            let bones:[(CGPoint,CGPoint,Double)]=[
                (pose.hip,pose.chest,PitcherContinuousPose.trunkLength),
                (pose.throwingShoulder,pose.elbow,PitcherContinuousPose.upperArmLength),
                (pose.elbow,pose.wrist,PitcherContinuousPose.forearmLength),
                (pose.gloveShoulder,pose.gloveElbow,PitcherContinuousPose.gloveUpperLength),
                (pose.gloveElbow,pose.glove,PitcherContinuousPose.gloveForearmLength),
                (pose.leadHip,pose.knee,PitcherContinuousPose.thighLength),
                (pose.knee,pose.ankle,PitcherContinuousPose.shinLength),
                (pose.rearHip,pose.rearKnee,PitcherContinuousPose.thighLength),
                (pose.rearKnee,pose.rearAnkle,PitcherContinuousPose.shinLength)]
            for (root,end,length) in bones {
                XCTAssertEqual(hypot(end.x-root.x,end.y-root.y),length,accuracy:0.000001,
                               "A connected limb must rotate without stretching or collapsing")
            }
        }
    }
    func testV118PlantReleaseAndRecoveryKeepContinuousFirmPose() {
        func speed(_ time:Double)->Double {
            let a=PitcherContinuousPose(progress:time-0.001).wrist,b=PitcherContinuousPose(progress:time+0.001).wrist
            return hypot(b.x-a.x,b.y-a.y)/0.002
        }
        XCTAssertGreaterThan(speed(0.99),speed(0.28)*3,"The short release accelerates after the controlled lift")
        XCTAssertLessThan(speed(1.55),speed(0.99)/10,"Follow-through settles rather than continuing to float")
        for time in [0.76,0.86,0.94,1.0,1.045,1.10,1.22,1.38,1.55,1.85] {
            let e=0.000001,a=PitcherContinuousPose(progress:time-e),b=PitcherContinuousPose(progress:time+e)
            for (p,q) in [(a.wrist,b.wrist),(a.knee,b.knee),(a.rearKnee,b.rearKnee),(a.chest,b.chest)] {
                XCTAssertLessThan(hypot(p.x-q.x,p.y-q.y),0.02,"No jump at plant, release or deceleration boundaries")
            }
            XCTAssertEqual(PitcherContinuousPose(progress:time).ankle,CGPoint(x:128,y:440))
        }
        XCTAssertEqual(PitcherContinuousPose(progress:2.65).wrist,PitcherContinuousPose(progress:0).wrist)
    }
    func testV120WholeBodySilhouetteUsesOneSpriteAndTransparentCorners() throws {
        for role in [PlayerRole.pitcher,.batter] {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:"right",kit:1,role:role,jerseyNumber:27)
            let node=try XCTUnwrap(scene.childNode(withName:"animatedPitcher")?.childNode(withName:"fullBodyPitcher") as? FullBodyPitcherNode)
            XCTAssertEqual(node.children.count,1,"The selected whole-body direction must not reintroduce detached limb sprites")
            XCTAssertNil((node.parent as? SKSpriteNode)?.texture,"The old invisible pitcher frames must not remain in the render path")
            let body=try XCTUnwrap(node.childNode(withName:"pitcherWholeBody") as? SKSpriteNode)
            let image=try XCTUnwrap(body.texture?.cgImage())
            var rgba=[UInt8](repeating:0,count:image.width*image.height*4)
            rgba.withUnsafeMutableBytes {p in
                let c=CGContext(data:p.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)
                c?.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            XCTAssertEqual(rgba[3],0);XCTAssertEqual(rgba[(image.width-1)*4+3],0)
            let opaque=stride(from:3,to:rgba.count,by:4).filter {rgba[$0]>200}.count
            XCTAssertGreaterThan(opaque,1000);XCTAssertLessThan(opaque,image.width*image.height/2)
        }
    }
    func testV122WholeBodyRecoveryDoesNotJumpBetweenFootRegistrations() throws {
        let manifest=try XCTUnwrap(FullBodyPitcherArt.manifest)
        for camera in [manifest.back,manifest.front] {
            let before=FullBodyPitcherNode.recoveryOffset(progress:1.78,camera:camera)
            let after=FullBodyPitcherNode.recoveryOffset(progress:1.780001,camera:camera)
            XCTAssertEqual(before.x,after.x,accuracy:0.000001)
            XCTAssertEqual(before.y,after.y,accuracy:0.000001)
            var previous=before
            for index in 1...240 {
                let p=FullBodyPitcherNode.recoveryOffset(progress:1.78+0.87*Double(index)/240,camera:camera)
                XCTAssertLessThan(hypot(p.x-previous.x,p.y-previous.y),0.005)
                previous=p
            }
            XCTAssertEqual(previous.x,camera.frames[31].offset[0],accuracy:0.000001)
            XCTAssertEqual(previous.y,camera.frames[31].offset[1],accuracy:0.000001)
            for time in [0.0,0.48,0.78,1.0,1.78] {
                let frame=camera.frames[FullBodyPitcherArt.index(progress:time)]
                let p=FullBodyPitcherNode.recoveryOffset(progress:time,camera:camera)
                XCTAssertEqual(p.x,frame.offset[0]);XCTAssertEqual(p.y,frame.offset[1])
            }
        }
    }
    func testV123PixelGridKeepsWholeNumberAndVisibleReleaseHand() throws {
        let manifest=try XCTUnwrap(FullBodyPitcherArt.manifest)
        for role in [PlayerRole.pitcher,.batter] {
            let a=try XCTUnwrap(FullBodyPitcherArt.prepare(role:role,appearance:PlayerAppearance(kit:1),number:27,hand:"right"))
            let b=try XCTUnwrap(FullBodyPitcherArt.prepare(role:role,appearance:PlayerAppearance(kit:1),number:54,hand:"right"))
            for index in 0..<32 {
                let image=try XCTUnwrap(a.textures[index].cgImage())
                XCTAssertEqual(image.width,128);XCTAssertEqual(image.height,128)
                var pixels=[UInt8](repeating:0,count:128*128*4)
                pixels.withUnsafeMutableBytes {p in
                    let c=CGContext(data:p.baseAddress,width:128,height:128,bitsPerComponent:8,bytesPerRow:512,
                        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)
                    c?.draw(image,in:CGRect(x:0,y:0,width:128,height:128))
                }
                XCTAssertTrue(stride(from:3,to:pixels.count,by:4).allSatisfy {pixels[$0]==0 || pixels[$0]==255})
                let frame=(role == .pitcher ? manifest.back:manifest.front).frames[index]
                if index==19 {
                    let x=Int(frame.hand[0]*128),y=Int(frame.hand[1]*128)
                    XCTAssertTrue((-2...2).contains {dy in (-2...2).contains {dx in
                        let xx=x+dx,yy=y+dy
                        return xx>=0 && yy>=0 && xx<128 && yy<128 && pixels[(yy*128+xx)*4+3]==255
                    }},"Release ball anchor remains on the actual raster hand")
                }
                if role == .pitcher && [0,14,19,28].contains(index) {
                    XCTAssertNotEqual(a.textures[index].cgImage().dataProvider!.data! as Data,b.textures[index].cgImage().dataProvider!.data! as Data,"Visible back numbers remain readable/distinct")
                }
            }
        }
    }
    func testV123UniformBadgeMovesInsideClothInsteadOfClippingDigits() throws {
        let width=40,height=40
        let cloth=(0..<height).flatMap {y in (0..<width).map {x in (8..<32).contains(x) && (9..<31).contains(y)}}
        for angle in [-0.4,0,0.4] {
            let point=try XCTUnwrap(FullBodyPitcherArt.badgeCenter(near:CGPoint(x:7,y:14),angle:angle,columns:7,rows:5,eligible:cloth,width:width,height:height))
            XCTAssertGreaterThan(point.x,10)
            var bytes=[UInt8](repeating:80,count:width*height*4)
            for i in stride(from:3,to:bytes.count,by:4) {bytes[i]=255}
            PlayerMotionArt.drawNumber(27,at:point,angle:angle,mirrored:false,unit:1,eligible:cloth,bytes:&bytes,width:width,height:height)
            XCTAssertGreaterThan(stride(from:0,to:bytes.count,by:4).filter {bytes[$0] != 80}.count,10)
        }
        XCTAssertNil(FullBodyPitcherArt.badgeCenter(near:.zero,angle:0,columns:7,rows:5,eligible:[Bool](repeating:false,count:1600),width:40,height:40))
    }
    func testV123PitcherFollowsThroughThenRecoversWithoutRewinding() {
        var previous=1.0
        for index in 0...360 {
            let value=PitcherMotionPlayback.progress(elapsed:Double(index)/240)
            XCTAssertGreaterThanOrEqual(value,previous);XCTAssertLessThanOrEqual(value,2.65)
            XCTAssertLessThan(value-previous,0.008);previous=value
        }
        XCTAssertEqual(PitcherMotionPlayback.progress(elapsed:0.42),1.78,accuracy:0.000001)
        XCTAssertEqual(PitcherMotionPlayback.progress(elapsed:1.12),2.65,accuracy:0.000001)
        XCTAssertEqual(PitcherMotionPlayback.progress(elapsed:-1),1)
    }
    func testV123SocksUseTeamColorAndPantsKeepClothColor() throws {
        let style=GameUniformStyle(id:"qa-v123",pattern:"solid",body:0x245d51,sleeves:0x503040,
            cap:0x503040,brim:0x342539,trim:0xf4ce61,ink:0xf1f3ee,mark:[],pants:0x9eacb8)
        let manifest=try XCTUnwrap(FullBodyPitcherArt.manifest)
        func pixels(_ image:CGImage)->[UInt8] {
            var result=[UInt8](repeating:0,count:image.width*image.height*4)
            result.withUnsafeMutableBytes {p in
                let c=CGContext(data:p.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                    bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)
                c?.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            };return result
        }
        var socks=0,pants=0
        for camera in [manifest.back,manifest.front] {
            let url=try XCTUnwrap(Bundle.main.url(forResource:camera.file,withExtension:"png",subdirectory:"MatchArt"))
            let source=try XCTUnwrap(UIImage(contentsOfFile:url.path)?.cgImage)
            for index in [0,14,19,28] {
                let frame=camera.frames[index],r=frame.rect
                let crop=try XCTUnwrap(source.cropping(to:CGRect(x:r[0],y:r[1],width:r[2],height:r[3])))
                let image=try XCTUnwrap(FullBodyPitcherArt.image(frame:frame,file:camera.file,kit:style.body,
                    style:style,appearance:PlayerAppearance(kit:1),number:nil,mirrored:false)?.cgImage)
                let a=pixels(crop),b=pixels(image)
                for y in 80..<112 {for x in 0..<128 {
                    let sx=min(r[2]-1,Int((Double(x)+0.5)*Double(r[2])/128))
                    let sy=min(r[3]-1,Int((Double(y)+0.5)*Double(r[3])/128))
                    let i=(sy*r[2]+sx)*4,j=(y*128+x)*4
                    guard a[i+3]>200,b[j+3]==255 else {continue}
                    let red=Double(a[i]),green=Double(a[i+1]),blue=Double(a[i+2])
                    let hi=max(red,green,blue),lo=min(red,green,blue)
                    let isSock=hi>80 && green>=blue && red>green*1.8 && red>blue*1.8 && abs(green-blue)<(hi-lo)*0.18
                    let isPants=y<100 && hi>160 && (hi-lo)/hi<0.18
                    guard isSock || isPants else {continue}
                    let color=isSock ? style.cap:style.pants
                    let target=[Double((color>>16)&255),Double((color>>8)&255),Double(color&255)]
                    let actual=[Double(b[j]),Double(b[j+1]),Double(b[j+2])]
                    let total=actual.reduce(0,+),expected=target.reduce(0,+)
                    guard total>0 else {continue}
                    for c in 0..<3 {XCTAssertEqual(actual[c]/total,target[c]/expected,accuracy:0.035)}
                    if isSock {socks+=1} else {pants+=1}
                }}
            }
        }
        XCTAssertGreaterThan(socks,40);XCTAssertGreaterThan(pants,100)
    }
    func testV120WholeBodyMaterialMarkersBecomeOwnAndOpponentKitColors() throws {
        func pixels(_ image:CGImage)->[UInt8] {
            var data=[UInt8](repeating:0,count:image.width*image.height*4)
            data.withUnsafeMutableBytes {p in
                let c=CGContext(data:p.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)
                c?.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            };return data
        }
        let metadata=try XCTUnwrap(FullBodyPitcherArt.manifest),appearance=PlayerAppearance(kit:2)
        for role in [PlayerRole.pitcher,.batter] {
            let prepared=try XCTUnwrap(FullBodyPitcherArt.prepare(role:role,appearance:appearance,number:27,hand:"right"))
            let camera=role == .pitcher ? metadata.back:metadata.front
            let url=try XCTUnwrap(Bundle.main.url(forResource:camera.file,withExtension:"png",subdirectory:"MatchArt"))
            let atlas=try XCTUnwrap(UIImage(contentsOfFile:url.path)?.cgImage)
            let kit=role == .pitcher ? appearance.uniformColor:appearance.opponentUniformColor
            let target=[Double((kit>>16)&255),Double((kit>>8)&255),Double(kit&255)],sum=target.reduce(0,+)
            for index in 0..<32 {
                let f=camera.frames[index],rect=f.rect
                let original=try XCTUnwrap(atlas.cropping(to:CGRect(x:rect[0],y:rect[1],width:rect[2],height:rect[3])))
                let rendered=try XCTUnwrap(prepared.textures[index].cgImage()),a=pixels(original),b=pixels(rendered)
                var caps=0,shirts=0
                for oy in stride(from:0,to:rendered.height,by:1) {for ox in stride(from:0,to:rendered.width,by:1) {
                    let x=min(rect[2]-1,Int((Double(ox)+0.5)*Double(rect[2])/Double(rendered.width)))
                    let y=min(rect[3]-1,Int((Double(oy)+0.5)*Double(rect[3])/Double(rendered.height)))
                    let i=(oy*rendered.width+ox)*4,j=(y*rect[2]+x)*4
                    guard a[j+3]>200,b[i+3]>200 else {continue}
                    let r=Double(a[j]),g=Double(a[j+1]),blue=Double(a[j+2])
                    let px=Double(x)/Double(rect[2]),py=Double(y)/Double(rect[3])
                    let cap=g>r*1.4 && g>blue*1.1 && g>70 && px>=f.cap[0] && px<=f.cap[0]+f.cap[2] && py>=f.cap[1] && py<=f.cap[1]+f.cap[3]
                    let shirt=blue>r*1.4 && blue>g*1.3 && blue>100
                    guard cap || shirt else {continue}
                    let out=[Double(b[i]),Double(b[i+1]),Double(b[i+2])],high=out.max()!,low=out.min()!
                    let whiteMark = low>120 && high-low<40 && target.max()!-target.min()!>50
                    guard high>100,!whiteMark else {continue}
                    if role == .batter && shirt && appearance.opponentUniformStyle != nil {
                        let cx=(f.shirt[0]+f.shirt[2]*0.55)*Double(rect[2]),cy=(f.shirt[1]+f.shirt[3]*0.30)*Double(rect[3])
                        if abs(Double(x)-cx)<10 && abs(Double(y)-cy)<10 {continue}
                    }
                    let total=out.reduce(0,+)
                    for c in 0..<3 {XCTAssertEqual(out[c]/total,target[c]/sum,accuracy:0.035,"Technical marker colors must not leak into the displayed kit: role \(role.rawValue) frame \(index) pixel \(x),\(y) source \(r),\(g),\(blue)")}
                    if cap {caps+=1}else{shirts+=1}
                }}
                XCTAssertGreaterThanOrEqual(caps,5);XCTAssertGreaterThanOrEqual(shirts,5)
            }
        }
    }
    func testV120WholeBodyMetadataContactAndCacheRespectSavedAppearance() throws {
        let metadata=try XCTUnwrap(FullBodyPitcherArt.manifest)
        XCTAssertEqual(metadata.progress.count,32)
        var appearance=PlayerAppearance(kit:1);appearance.skin=2;appearance.hair=1
        let a=try XCTUnwrap(FullBodyPitcherArt.prepare(role:.pitcher,appearance:appearance,number:27,hand:"right"))
        let again=try XCTUnwrap(FullBodyPitcherArt.prepare(role:.pitcher,appearance:appearance,number:27,hand:"right"))
        let b=try XCTUnwrap(FullBodyPitcherArt.prepare(role:.pitcher,appearance:appearance,number:54,hand:"right"))
        XCTAssertTrue(a === again);XCTAssertFalse(a === b)
        XCTAssertEqual(a.textures.count,32)
        let first=try XCTUnwrap(a.textures[0].cgImage()),other=try XCTUnwrap(b.textures[0].cgImage())
        XCTAssertNotEqual(CFDataGetLength(first.dataProvider!.data!),0)
        XCTAssertNotEqual(first.dataProvider!.data! as Data,other.dataProvider!.data! as Data,"Saved jersey numbers remain distinct")
        for camera in [metadata.back,metadata.front] {
            XCTAssertEqual(camera.frames.count,32)
            for f in camera.frames {
                XCTAssertEqual(f.clipRows.count,f.rect[3]);XCTAssertGreaterThan(f.shirt[2],0);XCTAssertGreaterThan(f.shirt[3],0)
                XCTAssertTrue(f.hand.allSatisfy { $0.isFinite });XCTAssertTrue(f.offset.allSatisfy { $0.isFinite })
            }
            let planted=(14...27).map {camera.frames[$0]}.map { CGPoint(x:$0.leadFoot[0]+$0.offset[0],y:$0.leadFoot[1]+$0.offset[1]) }
            for p in planted {XCTAssertEqual(p.x,planted[0].x,accuracy:0.000001);XCTAssertEqual(p.y,planted[0].y,accuracy:0.000001)}
            XCTAssertTrue(camera.frames[19].handVisible,"The actual drawn release hand must be known")
            XCTAssertEqual(camera.frames[31].rect,camera.frames[0].rect,"Recovery ends at the same authored ready pose")
        }
        XCTAssertEqual(FullBodyPitcherArt.index(progress:1.0),19)
        XCTAssertEqual(FullBodyPitcherArt.index(progress:3),31)
    }
    func testV117ContinuousJointsAndFootPlantAcrossDenseTimeSamples() {
        var previous=PitcherContinuousPose(progress:0)
        var changed=0
        for i in 1...636 {
            let t=Double(i)/240,pose=PitcherContinuousPose(progress:t)
            for point in [pose.hip,pose.chest,pose.wrist,pose.elbow,pose.glove,pose.knee,pose.ankle,pose.rearAnkle] {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                XCTAssertTrue((-30...550).contains(point.x) && (-30...550).contains(point.y))
            }
            let distance=hypot(pose.wrist.x-previous.wrist.x,pose.wrist.y-previous.wrist.y)
            XCTAssertLessThan(distance,24,"No discontinuous frame replacement at release/pose boundaries")
            if distance>0.001 {changed+=1}
            if (PitcherContinuousPose.plant...1.55).contains(t) {
                XCTAssertEqual(pose.ankle,CGPoint(x:128,y:440),"Lead foot stays grounded through release and deceleration")
            }
            previous=pose
        }
        XCTAssertGreaterThan(changed,600)
        let before=PitcherContinuousPose(progress:0.999999),after=PitcherContinuousPose(progress:1.000001)
        XCTAssertLessThan(hypot(after.wrist.x-before.wrist.x,after.wrist.y-before.wrist.y),0.02)
        XCTAssertEqual(PitcherContinuousPose(progress:2.65).wrist,PitcherContinuousPose(progress:0).wrist)
    }
    func testV117SceneOwnsPreparationClockAndReleasesFromConnectedHand() throws {
        for hand in ["left","right"] {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:hand,kit:2)
            let start=ProcessInfo.processInfo.systemUptime,timeline=MatchInputTimeline(startedAt:start,windup:0,duration:1.8)
            scene.preparePitch(timeline:timeline)
            let rig=try XCTUnwrap(scene.childNode(withName:"animatedPitcher")?.childNode(withName:"fullBodyPitcher") as? FullBodyPitcherNode)
            let first=rig.handPoint
            scene.advanceDelivery(at:start+0.45)
            let middle=rig.handPoint;XCTAssertNotEqual(first,middle)
            scene.advanceDelivery(at:start+0.52);XCTAssertNotEqual(middle,rig.handPoint)
            XCTAssertLessThan(hypot(middle.x-rig.handPoint.x,middle.y-rig.handPoint.y),48)
            let prepared=rig.handPoint
            XCTAssertTrue(scene.demonstrate(reduceMotion:true,flightDuration:1.2,preparedRelease:true))
            XCTAssertEqual(scene.pitchStage,.preparing)
            XCTAssertLessThan(hypot(prepared.x-rig.handPoint.x,prepared.y-rig.handPoint.y),0.001,"Early release continues from the displayed preparation")
            scene.advanceDelivery(at:ProcessInfo.processInfo.systemUptime+0.25)
            XCTAssertEqual(scene.pitchStage,.flight)
            let ball=try XCTUnwrap(scene.childNode(withName:"baseball"))
            XCTAssertEqual(ball.position.x,rig.convert(rig.handPoint,to:scene).x,accuracy:0.001)
            XCTAssertEqual(ball.position.y,rig.convert(rig.handPoint,to:scene).y,accuracy:0.001)
            scene.cancelDelivery();let cancelled=rig.handPoint
            scene.advanceDelivery(at:start+10);XCTAssertEqual(rig.handPoint,cancelled)
        }
    }
    func testV117ActualContinuousSceneCapturesBothCamerasHands() throws {
        for role in [PlayerRole.pitcher,.batter] {for hand in ["right","left"] {
            let scene=BallparkScene(size:CGSize(width:320,height:340));scene.configure(hand:hand,kit:1,role:role,jerseyNumber:27)
            let view=SKView(frame:CGRect(origin:.zero,size:scene.size));view.presentScene(scene)
            let start=ProcessInfo.processInfo.systemUptime,timeline=MatchInputTimeline(startedAt:start,windup:1.2,duration:1.5)
            var arrivals=0
            var releaseOrigin:Double?
            if role == .batter {XCTAssertTrue(scene.demonstrate(reduceMotion:false,onArrival:{arrivals+=1},inputTimeline:timeline))}
            let frames=role == .pitcher && hand == "right" ? 90:18
            for i in 0..<frames {
                let time=Double(i)/Double(frames-1)*2.8
                if role == .pitcher {
                    if time<1.2 {scene.preparePitch(phase:time/1.2*ManualMatchRules.releaseCenter,reduced:false)}
                    else if arrivals == 0 && scene.pitchStage != .flight && scene.pitchStage != .received {
                        XCTAssertTrue(scene.demonstrate(reduceMotion:false,flightDuration:1.5,preparedRelease:true,onArrival:{arrivals+=1}))
                        releaseOrigin=ProcessInfo.processInfo.systemUptime
                    }
                    if time>=1.2,let releaseOrigin {scene.advanceDelivery(at:releaseOrigin+time-1.2)}
                } else {scene.advanceDelivery(at:start+time)}
                let a=XCTAttachment(image:UIImage(cgImage:try XCTUnwrap(view.texture(from:scene)?.cgImage())))
                a.name=String(format:"v120-%@-%@-%03d",role.rawValue,hand,i);a.lifetime = .keepAlways;add(a)
            }
            scene.cancelDelivery();view.presentScene(nil)
        }}
    }
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
                let origin=action == "pitch" ? CGPoint(x:0.5,y:0.465):MatchPresentation.batContact(action:action)
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
                let arrival=scene.arrivalPoint(x:0.5,y:0.5)
                let start=role == .batter ? MatchPresentation.batContact(action:"swing"):CGPoint(x:arrival.x/scene.size.width,y:1-arrival.y/scene.size.height)
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

extension ManualMatchTests {
    func testV52StadiumIdentityIsStableAndDoesNotTouchMatchRNGOrPayload() throws {
        let game=match(),encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(game)
        let identities=(0..<32).map {StadiumIdentity(homeTeamID:"ground-\($0)")}
        XCTAssertEqual(Set(identities.map { $0.theme.rawValue }).count,4)
        XCTAssertEqual(Set(identities.map(\.variation)).count,3)
        for value in identities {
            XCTAssertEqual(value,StadiumIdentity(homeTeamID:value.key))
            XCTAssertEqual(value.sponsors.count,3);XCTAssertEqual(Set(value.sponsors.map(\.name)).count,3)
            XCTAssertEqual(StadiumIdentity(homeTeamID:value.key).sponsors,value.sponsors)
        }
        XCTAssertEqual(try encoder.encode(game),before)
    }
    func testV52MoundAndAnimatedActorsStayFixedAcrossHandsAndBatterSides() throws {
        for hand in ["left","right"] {for side in [OpponentBatterSide.left,.right] {
            let scene=BallparkScene(size:CGSize(width:320,height:340))
            scene.configure(hand:hand,kit:2,batterSide:side)
            XCTAssertEqual(scene.childNode(withName:"fixedStadiumBackground")?.xScale,hand == "left" ? -1 : 1)
            let pitcher=try XCTUnwrap(scene.childNode(withName:"animatedPitcher") as? SKSpriteNode)
            let batter=try XCTUnwrap(scene.childNode(withName:"animatedBatter") as? SKSpriteNode)
            XCTAssertEqual(pitcher.position.x,scene.size.width*(hand == "left" ? 0.24 : 0.76),accuracy:0.001)
            XCTAssertEqual(pitcher.position.y,scene.size.height*(1-0.870),accuracy:0.001)
            XCTAssertEqual(pitcher.size.width,pitcher.size.height,accuracy:0.001)
            XCTAssertEqual(batter.position.x,scene.size.width*(side == .left ? 0.32:0.70),accuracy:0.001)
            XCTAssertNotNil(try visiblePitcher(in:pitcher).texture);XCTAssertNotNil(batter.texture)
            scene.preparePitch(phase:0.3,reduced:true)
            XCTAssertEqual(scene.pitchStage,.preparing)
            XCTAssertEqual(pitcher.position.x,scene.size.width*(hand == "left" ? 0.24 : 0.76),accuracy:0.001)
            let rig=try XCTUnwrap(pitcher.childNode(withName:"fullBodyPitcher") as? FullBodyPitcherNode)
            XCTAssertTrue(rig.leadFoot.x.isFinite)
            let right=PitcherPresentationPose(role:.pitcher,frame:1,hand:"right")
            let left=PitcherPresentationPose(role:.pitcher,frame:1,hand:"left")
            XCTAssertEqual(right.pivot.x+left.pivot.x,1,accuracy:0.001)
            XCTAssertEqual(right.hand.x+left.hand.x,1,accuracy:0.001)
            scene.cancelDelivery()
        }}
    }
    func testV52BatterCameraActuallyAnimatesSeparateOpponentPitcherOnSharedClock() throws {
        for reduced in [false,true] {
            let scene=BallparkScene(size:CGSize(width:320,height:320));scene.configure(hand:"right",kit:0,role:.batter)
            let pitcher=try XCTUnwrap(scene.childNode(withName:"animatedPitcher") as? SKSpriteNode)
            let visible=try visiblePitcher(in:pitcher),initial=visible.texture
            XCTAssertEqual(scene.children.filter {$0.name?.hasPrefix("backgroundFielder-") == true}.count,3)
            let start=ProcessInfo.processInfo.systemUptime,timeline=MatchInputTimeline(startedAt:start,windup:0.5,duration:1.2)
            var arrivals=0
            XCTAssertTrue(scene.demonstrate(reduceMotion:reduced,x:0.7,y:0.4,onArrival:{arrivals += 1},inputTimeline:timeline))
            scene.advanceDelivery(at:start+0.3)
            XCTAssertFalse(initial === visible.texture)
            scene.advanceDelivery(at:timeline.contactAt-0.001);XCTAssertEqual(arrivals,0)
            scene.advanceDelivery(at:timeline.contactAt+0.001);XCTAssertEqual(arrivals,1)
            scene.advanceDelivery(at:timeline.contactAt+1);XCTAssertEqual(arrivals,1)
            XCTAssertEqual(pitcher.position.y,320*(1-0.375),accuracy:0.001)
            XCTAssertEqual(scene.childNode(withName:"receivedBaseball")?.isHidden,false)
            scene.cancelDelivery()
        }
    }
    func testV52CelebrationBudgetAndReducedMotionNeverRestartEffects() {
        for n in 0..<12 {for reduced in [false,true] {
            let dress=StadiumSceneDress(stadium:StadiumIdentity(homeTeamID:"ground-\(n)"),size:CGSize(width:400,height:600),camera:.field)
            XCTAssertNil(dress.celebration);XCTAssertEqual(dress.effectNodeCount,0)
            dress.celebrate(.homeRun,reduced:reduced)
            XCTAssertEqual(dress.floodlightCount,4)
            XCTAssertEqual(dress.animatedLightCount,reduced ? 0:16)
            XCTAssertEqual(dress.celebrationCount,1);XCTAssertLessThanOrEqual(dress.effectNodeCount,40)
            if reduced {XCTAssertEqual(dress.effectNodeCount,0)}
            dress.celebrate(.homeRun,reduced:reduced);dress.celebrate(.doublePlay,reduced:reduced)
            XCTAssertEqual(dress.celebrationCount,1)
            dress.reduceEffects();XCTAssertEqual(dress.effectNodeCount,0)
            XCTAssertEqual(dress.animatedLightCount,0)
        }}
    }
}

extension ManualMatchTests {
    func testV52NativeFourThemeBoardsAndBothCameraComponents() throws {
        let ids=(0..<4).map {StadiumIdentity(homeTeamID:"ground-\($0)")}
        XCTAssertEqual(Set(ids.map {$0.theme.rawValue}).count,4)
        for stadium in ids {for role in PlayerRole.allCases {
            let game=match(role:role)
            let scene=BallparkScene(size:CGSize(width:320,height:320))
            scene.configure(hand:role == .pitcher ? "left":"right",kit:1,role:role,batterSide:.right);scene.setStadium(stadium)
            let view=SKView(frame:CGRect(origin:.zero,size:scene.size));view.presentScene(scene)
            let field=UIImage(cgImage:try XCTUnwrap(view.texture(from:scene)?.cgImage()))
            let board=UIHostingController(rootView:MatchBroadcastBoard(match:game,homeName:"연고 홈팀",awayName:"원정 고교",date:"2026-04-01",pulse:nil,pulseAt:.distantPast,stadium:stadium))
            board.view.frame=CGRect(x:0,y:0,width:390,height:174);board.view.backgroundColor = .clear;board.view.layoutIfNeeded()
            let image=UIGraphicsImageRenderer(size:CGSize(width:390,height:174+390*scene.size.height/scene.size.width)).image {context in
                UIColor(GameTheme.navy).setFill();context.fill(CGRect(x:0,y:0,width:390,height:600))
                field.draw(in:CGRect(x:0,y:174,width:390,height:390*scene.size.height/scene.size.width))
                board.view.layer.render(in:context.cgContext)
            }
            let attachment=XCTAttachment(image:image);attachment.name="v52-component-\(stadium.theme.title)-\(role.rawValue)";attachment.lifetime = .keepAlways;add(attachment)
            view.presentScene(nil)
        }}
    }
}

extension ManualMatchTests {
    func testV75StrideFootFollowsPlantAndReleaseUsesSameDisplayedHand() throws {
        for hand in ["left", "right"] {
            let load = PitcherPresentationPose(role: .pitcher, frame: 2, hand: hand)
            let release = PitcherPresentationPose(role: .pitcher, frame: 3, hand: hand)
            let front = hand == "left" ? 0.71 : 0.29
            XCTAssertEqual(load.foot.x + load.width * (front-load.pivot.x), release.foot.x, accuracy: 0.001)
            XCTAssertLessThan(release.foot.y, load.foot.y)
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 2)
            XCTAssertTrue(scene.demonstrate(reduceMotion: true, flightDuration: 1, preparedRelease: true))
            let ball = try XCTUnwrap(scene.childNode(withName: "baseball"))
            let pitcher = try XCTUnwrap(scene.childNode(withName: "animatedPitcher"))
            let rig=try XCTUnwrap(pitcher.childNode(withName:"fullBodyPitcher") as? FullBodyPitcherNode)
            XCTAssertEqual(ball.position.x,rig.convert(rig.handPoint,to:scene).x,accuracy:0.001)
            XCTAssertEqual(ball.position.y,rig.convert(rig.handPoint,to:scene).y,accuracy:0.001)
            XCTAssertLessThan(pitcher.frame.minX, 320); XCTAssertGreaterThan(pitcher.frame.maxX, 0)
            scene.cancelDelivery()
        }
    }
    func testV75ActualSceneMotionFramesBothHandsAndPracticeSetting() throws {
        for hand in ["left", "right"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 1, appearance: PlayerAppearance(kit: 1), jerseyNumber: 27)
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size)); view.presentScene(scene)
            func capture(_ name: String) throws {
                let image = UIImage(cgImage: try XCTUnwrap(view.texture(from: scene)?.cgImage()))
                let attachment = XCTAttachment(image: image); attachment.name = "v75-pitch-" + hand + "-" + name
                attachment.lifetime = .keepAlways; add(attachment)
            }
            try capture("ready"); scene.preparePitch(phase: 0.3, reduced: false); try capture("load")
            scene.preparePitch(phase: 0.7, reduced: false); try capture("stride")
            XCTAssertTrue(scene.demonstrate(reduceMotion: false, flightDuration: 1, preparedRelease: true))
            let now = ProcessInfo.processInfo.systemUptime
            try capture("release"); scene.advanceDelivery(at: now + 0.5); try capture("follow")
            scene.advanceDelivery(at: now + 1.01); try capture("received")
            scene.cancelDelivery(); scene.usePracticeSetting(); try capture("bullpen")
            XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: "animatedBatter")).isHidden)
            view.presentScene(nil)
        }
        let scene = BallparkScene(size: CGSize(width: 320, height: 320)); scene.configure(hand: "right", kit: 1, role: .batter)
        scene.usePracticeSetting()
        XCTAssertNil(scene.children.first { ($0.name ?? "").hasPrefix("stadiumDress") })
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size)); view.presentScene(scene)
        let ready = XCTAttachment(image: UIImage(cgImage: try XCTUnwrap(view.texture(from: scene)?.cgImage())))
        ready.name = "v75-batting-practice-ready"; ready.lifetime = .keepAlways; add(ready)
        let timeline = MatchInputTimeline(windup: MatchDelivery.windup, duration: 1.6)
        XCTAssertTrue(scene.demonstrate(reduceMotion: false, flightDuration: 1.6, inputTimeline: timeline))
        scene.finishBat(action: "swing", outcome: "헛스윙", reduced: false) {}
        scene.advanceDelivery(at: timeline.contactAt + 0.01)
        let contact = XCTAttachment(image: UIImage(cgImage: try XCTUnwrap(view.texture(from: scene)?.cgImage())))
        contact.name = "v75-batting-contact-facing-pitcher"; contact.lifetime = .keepAlways; add(contact)
        scene.cancelDelivery(); view.presentScene(nil)
    }
}


extension ManualMatchTests {
    func testV112MoundHeldBallAndMonotonicStrideBothHands() throws {
        for hand in ["right", "left"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 1)
            let pitcher = try XCTUnwrap(scene.childNode(withName: "animatedPitcher") as? SKSpriteNode)
            let ball = try XCTUnwrap(scene.childNode(withName: "baseball"))
            XCTAssertEqual(pitcher.position.y / scene.size.height, 0.13, accuracy: 0.001)
            scene.preparePitch(phase: 0, reduced: false)
            XCTAssertTrue(ball.isHidden, "Do not draw another ball outside the closed glove")
            scene.preparePitch(phase: 0.2, reduced: false)
            XCTAssertTrue(ball.isHidden)
            scene.preparePitch(phase: 0.65, reduced: false)
            XCTAssertFalse(ball.isHidden)
            let visible=try visiblePitcher(in:pitcher)
            let location = pitcher.position, held = ball.position, texture = visible.texture
            scene.preparePitch(phase: 0.2, reduced: true)
            XCTAssertEqual(pitcher.position, location, "Reversing gauge must not rewind the stride")
            XCTAssertEqual(ball.position, held); XCTAssertTrue(texture === visible.texture)
            XCTAssertTrue(scene.demonstrate(reduceMotion: true, flightDuration: 1, preparedRelease: true))
            let rig=try XCTUnwrap(pitcher.childNode(withName:"fullBodyPitcher") as? FullBodyPitcherNode)
            let renderedHand=rig.convert(rig.handPoint,to:scene)
            XCTAssertEqual(ball.position.x, renderedHand.x, accuracy: 0.001)
            XCTAssertEqual(ball.position.y, renderedHand.y, accuracy: 0.001)
            scene.cancelDelivery(); XCTAssertTrue(ball.isHidden)
            scene.preparePitch(phase: 0, reduced: false); XCTAssertTrue(ball.isHidden)
        }
    }

    func testV112MotionContactAndActualSceneFrames() throws {
        for role in [PlayerRole.pitcher, .batter] { for hand in ["right", "left"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340))
            scene.configure(hand: hand, kit: 1, role: role, jerseyNumber: 27)
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size)); view.presentScene(scene)
            func capture(_ stage: String) throws {
                let image = UIImage(cgImage: try XCTUnwrap(view.texture(from: scene)?.cgImage()))
                let a = XCTAttachment(image: image); a.name = "v112-\(role.rawValue)-\(hand)-\(stage)"; a.lifetime = .keepAlways; add(a)
            }
            try capture("00-ready")
            let start = ProcessInfo.processInfo.systemUptime
            let timeline = MatchInputTimeline(startedAt: start, windup: 0.35, duration: 1.4)
            var arrivals = 0
            if role == .pitcher {
                for (index, phase) in [0.2, 0.4, 0.6].enumerated() {
                    scene.preparePitch(phase: phase, reduced: false); try capture("0\(index+1)-prepare")
                }
                XCTAssertTrue(scene.demonstrate(reduceMotion: false, flightDuration: 1.4, preparedRelease: true, onArrival: { arrivals += 1 }))
                try capture("04-release")
                scene.advanceDelivery(at: ProcessInfo.processInfo.systemUptime + 0.3); try capture("05-follow")
                scene.advanceDelivery(at: ProcessInfo.processInfo.systemUptime + 1.41); try capture("06-received")
            } else {
                XCTAssertTrue(scene.demonstrate(reduceMotion: false, inputTimeline: timeline))
                scene.advanceDelivery(at: start+0.15); try capture("01-windup")
                scene.advanceDelivery(at: timeline.releaseAt+0.01); try capture("02-release")
                scene.advanceDelivery(at: timeline.contactAt-0.20); try capture("03-load")
                scene.finishBat(action: "swing", outcome: "헛스윙", reduced: false, onArrival: { arrivals += 1 }) {}
                scene.advanceDelivery(at: timeline.contactAt-0.01); XCTAssertEqual(arrivals,0); try capture("04-plant")
                scene.advanceDelivery(at: timeline.contactAt); XCTAssertEqual(arrivals,1); try capture("05-contact")
                scene.advanceDelivery(at: timeline.contactAt+0.32); try capture("06-follow")
            }
            XCTAssertEqual(arrivals,1)
            scene.advanceDelivery(at: start+10); XCTAssertEqual(arrivals,1)
            scene.cancelDelivery(); view.presentScene(nil)
        }}
    }
}


extension ManualMatchTests {
    func testV112WatchedPitchSettlesAndFoulKeepsSwingFollowThrough() throws {
        for outcome in ["스트라이크", "볼", "파울", "헛스윙"] {
            let scene = BallparkScene(size: CGSize(width: 320, height: 340)); scene.configure(hand: "right", kit: 1)
            let batter = try XCTUnwrap(scene.childNode(withName: "animatedBatter") as? SKSpriteNode)
            let ready = batter.texture
            XCTAssertTrue(scene.demonstrate(reduceMotion: true, flightDuration: 1, outcome: outcome, preparedRelease: true))
            let start = ProcessInfo.processInfo.systemUptime
            scene.advanceDelivery(at: start+0.9); XCTAssertFalse(ready === batter.texture)
            scene.advanceDelivery(at: start+1.01)
            if outcome == "볼" || outcome == "스트라이크" { XCTAssertTrue(ready === batter.texture) }
            else {
                let contact = batter.texture
                scene.advanceDelivery(at: start+1.4)
                XCTAssertFalse(contact === batter.texture); XCTAssertFalse(ready === batter.texture)
            }
            scene.cancelDelivery(); XCTAssertTrue(ready === batter.texture)
        }
    }
    /// 단계별 함수로 분리해도 같은 프레임 재호출과 취소가 콜백을 중복 실행하지 않아야 한다.
    func testV115DeliveryStagesCompleteOnceAndDropCancelledCallbacks() {
        for role in [PlayerRole.batter, .pitcher] {
            for reduced in [false, true] {
                let scene = BallparkScene(size: CGSize(width: 320, height: 340))
                scene.configure(hand: "right", kit: 1, role: role)
                var events: [String] = []
                func startPitch() {
                    let timeline = MatchInputTimeline(windup: 0.35, duration: 1.4)
                    XCTAssertTrue(scene.demonstrate(
                        reduceMotion: reduced, flightDuration: 1.4, preparedRelease: true,
                        onArrival: { events.append("arrival") },
                        completion: { events.append("completion") }, inputTimeline: timeline
                    ))
                }
                startPitch()
                let afterFlight = ProcessInfo.processInfo.systemUptime + 3
                scene.advanceDelivery(at: afterFlight)
                XCTAssertEqual(events, ["arrival"])
                scene.advanceDelivery(at: afterFlight)
                XCTAssertEqual(events, ["arrival"], "같은 프레임에서는 포구 대기를 건너뛰지 않는다")
                scene.advanceDelivery(at: afterFlight + 3)
                scene.advanceDelivery(at: afterFlight + 4)
                XCTAssertEqual(events, ["arrival", "completion"])
                startPitch()
                scene.cancelDelivery()
                scene.advanceDelivery(at: afterFlight + 10)
                XCTAssertEqual(events, ["arrival", "completion"], "취소한 투구 콜백은 실행하지 않는다")
            }
        }
    }

}

extension ManualMatchTests {
    func testV143SharesDeliveryInMatchPitchTrainingAndBullpenDrills() throws {
        let cases: [(String, String?)] = [("left", nil), ("right", nil), ("left", "npb-13")]
        for (hand, club) in cases {
            let appearance = PlayerAppearance(kit: 1).wearing(teamID: club)
            let captureID = club.map { "v148-\($0)-\(hand)" } ?? "v143-\(hand)"
            let firstStarted = ProcessInfo.processInfo.systemUptime
            let variant = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: appearance, number: 54, hand: hand))
            let firstDuration = ProcessInfo.processInfo.systemUptime - firstStarted
            let repeatStarted = ProcessInfo.processInfo.systemUptime
            let repeated = FullBodyPitcherArt.prepareRefined(appearance: appearance, number: 54, hand: hand)
            let repeatDuration = ProcessInfo.processInfo.systemUptime - repeatStarted
            XCTAssertTrue(variant === repeated)
            let timing = XCTAttachment(string: String(format: "First preparation %.3f ms; cached preparation %.3f ms", firstDuration * 1000, repeatDuration * 1000))
            timing.name = "\(captureID)-prep-timing"
            timing.lifetime = .keepAlways
            add(timing)
            let originalNumber = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: appearance, number: 27, hand: hand))
            let manifest = try XCTUnwrap(variant.refined)
            let releaseIndex = try XCTUnwrap(manifest.progress.firstIndex(of: 1))
            XCTAssertEqual(variant.textures.count, 46)
            XCTAssertFalse(variant === originalNumber)
            let customRelease = try XCTUnwrap(variant.textures[releaseIndex].cgImage())
            let originalRelease = try XCTUnwrap(originalNumber.textures[releaseIndex].cgImage())
            XCTAssertNotEqual(customRelease.dataProvider!.data! as Data, originalRelease.dataProvider!.data! as Data)
            func checkRelease(_ rig: FullBodyPitcherNode, _ sprite: SKSpriteNode) throws {
                XCTAssertTrue(rig.usesRefinedDelivery)
                XCTAssertEqual(rig.frameIndex, releaseIndex)
                let displayed = try XCTUnwrap(sprite.texture?.cgImage())
                XCTAssertEqual(displayed.dataProvider!.data! as Data, customRelease.dataProvider!.data! as Data)
            }

            let game = BallparkScene(size: CGSize(width: 320, height: 339))
            game.configure(hand: hand, kit: 1, appearance: appearance, jerseyNumber: 54)
            game.setStadium(StadiumIdentity(homeTeamID: "pro-harbors"))
            let matchRig = try XCTUnwrap(game.childNode(withName: "//fullBodyPitcher") as? FullBodyPitcherNode)
            let matchSprite = try XCTUnwrap(matchRig.childNode(withName: "pitcherWholeBody") as? SKSpriteNode)
            let view = SKView(frame: CGRect(origin: .zero, size: game.size))
            view.presentScene(game)
            func capture(_ scene: SKScene, _ stage: String) throws {
                let rendered = try XCTUnwrap(view.texture(from: scene)?.cgImage())
                let attachment = XCTAttachment(image: UIImage(cgImage: rendered))
                attachment.name = "\(captureID)-\(stage)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            game.preparePitch(phase: ManualMatchRules.releaseCenter * 0.91, reduced: false)
            try capture(game, "match-plant")
            XCTAssertTrue(game.demonstrate(reduceMotion: false, flightDuration: 1, preparedRelease: true))
            try checkRelease(matchRig, matchSprite)
            try capture(game, "match-release")
            game.advanceDelivery(at: ProcessInfo.processInfo.systemUptime + 1.1)
            XCTAssertEqual(matchRig.frameIndex, variant.textures.count - 1)
            try capture(game, "match-finish")

            game.cancelDelivery()
            game.usePracticeSetting()
            XCTAssertTrue(game.demonstrate(reduceMotion: false, flightDuration: 1, preparedRelease: true))
            try checkRelease(matchRig, matchSprite)
            try capture(game, "pitch-training-release")
            game.cancelDelivery()
            view.presentScene(nil)

            let bullpen = LocationDrillScene(size: CGSize(width: 320, height: 340))
            bullpen.configure(kind: .control, appearance: appearance, number: 54, hand: hand)
            let trainingRig = try XCTUnwrap(bullpen.childNode(withName: "//fullBodyPitcher") as? FullBodyPitcherNode)
            let trainingSprite = try XCTUnwrap(trainingRig.childNode(withName: "pitcherWholeBody") as? SKSpriteNode)
            let ball = try XCTUnwrap(bullpen.childNode(withName: "locationBall"))
            let target = TrainingTarget(x: 0.7, y: 0.4)
            let replay = LocationDrillReplay(kind: .control, target: target, input: target, score: 72)
            view.presentScene(bullpen)
            var completions = 0
            let now = 40.0
            bullpen.play(replay, at: now, preparedRelease: false) { completions += 1 }
            XCTAssertTrue(ball.isHidden)
            bullpen.advance(at: now + LocationDrillReplay.windup)
            try checkRelease(trainingRig, trainingSprite)
            let release = trainingRig.convert(trainingRig.handPoint, to: bullpen)
            XCTAssertEqual(ball.position.x, release.x, accuracy: 0.000001)
            XCTAssertEqual(ball.position.y, release.y, accuracy: 0.000001)
            try capture(bullpen, "bullpen-release")
            bullpen.advance(at: now + LocationDrillReplay.windup + LocationDrillReplay.flight + 0.001)
            XCTAssertEqual(trainingRig.frameIndex, variant.textures.count - 1)
            XCTAssertEqual(completions, 0)
            try capture(bullpen, "bullpen-finish")
            bullpen.advance(at: now + 3)
            bullpen.advance(at: now + 4)
            XCTAssertEqual(completions, 1)
            bullpen.prepareDrill(phase: 0.65)
            let earlyFrame = trainingRig.frameIndex
            XCTAssertLessThan(earlyFrame, releaseIndex)
            bullpen.play(replay, at: now + 5, preparedRelease: true) { completions += 1 }
            XCTAssertEqual(trainingRig.frameIndex, earlyFrame, "Early rhythm input continues the visible windup")
            bullpen.advance(at: now + 5.15)
            XCTAssertGreaterThanOrEqual(trainingRig.frameIndex, releaseIndex)
            bullpen.cancel()
            XCTAssertEqual(trainingRig.frameIndex, 0)
            XCTAssertTrue(ball.isHidden)
            view.presentScene(nil)
        }
    }
}
