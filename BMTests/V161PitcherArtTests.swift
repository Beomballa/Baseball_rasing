import XCTest
import CryptoKit
import SpriteKit
import UIKit
@testable import BM

@MainActor final class V161PitcherArtTests: XCTestCase {
    private func bundledDelivery(_ name: String) throws -> FullBodyPitcherArt.RefinedDelivery {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "MatchArt"))
        return try JSONDecoder().decode(FullBodyPitcherArt.RefinedDelivery.self, from: Data(contentsOf: url))
    }

    private func atlas(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MatchArt"))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    }

    private func crop(_ image: CGImage, frame: FullBodyPitcherArt.Frame) throws -> CGImage {
        try XCTUnwrap(image.cropping(to: CGRect(x: frame.rect[0], y: frame.rect[1], width: frame.rect[2], height: frame.rect[3])))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(decoded)
        return bytes
    }

    func testV171BundledPreparationMidpointsMatchApprovedAssetsAndTiming() throws {
        struct ApprovedPreparation: Decodable {
            struct Entry: Decodable {
                let afterBaseIndex: Int
                let progress: Double
                let frame: FullBodyPitcherArt.Frame
            }
            let cell: Int
            let file: String
            let baseFile: String
            let baseManifestSHA256: String
            let baseAtlasSHA256: String
            let entries: [Entry]
        }

        let baseName = "pitcher-delivery-back-v171"
        let midpointName = "pitcher-delivery-back-v171-prep-midpoints"
        func resource(_ name: String, _ ext: String) throws -> Data {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "MatchArt"))
            return try Data(contentsOf: url)
        }
        func sha(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", Int($0)) }.joined() }

        let baseJSON = try resource(baseName, "json"), basePNG = try resource(baseName, "png")
        let midpointJSON = try resource(midpointName, "json"), midpointPNG = try resource(midpointName, "png")
        // The separate approved atlas must leave all original cels and their metadata byte-for-byte unchanged.
        XCTAssertEqual(sha(baseJSON), "ea93a7f01302c85a80bbcabd3d0b3ba3805f9c4cffd8c1ebf566dde9f46bd764")
        XCTAssertEqual(sha(basePNG), "f25b8363d5a17c30adc854a27a3d789b3997e8a4549c56ea91fbcd112f503e36")
        XCTAssertEqual(sha(midpointJSON), "5fe3a92f993125cb245e6da9642bf810c1dbaf26edcbb50d708029afb8d1fc18")
        XCTAssertEqual(sha(midpointPNG), "01a979cdb9bcba17095c7bb88e5b1fef1d7431a750e1a809957ba3a813e4a8f1")

        let base = try JSONDecoder().decode(FullBodyPitcherArt.RefinedDelivery.self, from: baseJSON)
        let approved = try JSONDecoder().decode(ApprovedPreparation.self, from: midpointJSON)
        XCTAssertEqual(base.camera.frames.count, 71)
        XCTAssertEqual(base.progress.count, 71)
        XCTAssertEqual(approved.cell, base.cell)
        XCTAssertEqual(approved.file, midpointName)
        XCTAssertEqual(approved.baseFile, baseName)
        XCTAssertEqual(approved.baseManifestSHA256, sha(baseJSON))
        XCTAssertEqual(approved.baseAtlasSHA256, sha(basePNG))
        XCTAssertEqual(approved.entries.map(\.afterBaseIndex), Array(0..<20))
        XCTAssertEqual(Set(approved.entries.map(\.frame.rect)).count, 20)
        let ready = try XCTUnwrap(base.camera.frames.first)
        for (index, entry) in approved.entries.enumerated() where index < 20 {
            XCTAssertEqual(entry.progress, (base.progress[index] + base.progress[index + 1]) / 2, accuracy: 0.000000001)
            XCTAssertEqual(entry.frame.rearFoot, ready.rearFoot)
            XCTAssertEqual(entry.frame.offset, ready.offset)
            XCTAssertEqual(entry.frame.handVisible, index >= 12)
            XCTAssertEqual(entry.frame.ballInArtwork, index >= 12)
        }
        XCTAssertLessThan(try XCTUnwrap(approved.entries.last).progress, 2000.0 / 3 / 1100)
    }

    func testV161AddsOnlyApprovedEarlyPosesAndPreservesReleaseTimeline() throws {
        let old = try bundledDelivery("pitcher-delivery-back-v143")
        let current = try bundledDelivery("pitcher-delivery-back-v161")
        XCTAssertEqual(current.camera.file, "pitcher-delivery-back-v161")
        XCTAssertEqual(current.cell, old.cell)
        XCTAssertEqual(current.camera.frames.count, 65)
        XCTAssertEqual(current.progress.count, 65)
        let earlyEnd = 2000.0 / 3 / 1100
        XCTAssertEqual(current.progress.filter { $0 <= earlyEnd }.count, 30)
        XCTAssertEqual(current.progress.firstIndex(of: 1), 53)
        XCTAssertEqual(current.progress.last, 2)
        XCTAssertTrue(zip(current.progress, current.progress.dropFirst()).allSatisfy { $0 < $1 })
        for progress in old.progress { XCTAssertTrue(current.progress.contains(progress), "Keep every original key time") }
        XCTAssertEqual(Array(current.progress.dropFirst(30)), Array(old.progress.dropFirst(11)))
        XCTAssertEqual(current.progress[29] - current.progress[28], 200.0 / 3 / 1100, accuracy: 0.000000001,
            "The rejected key9→10 generated poses must stay excluded")
        XCTAssertEqual(current.camera.frames[0].rearFoot, old.camera.frames[0].rearFoot,
            "Retain the scene's nominal anchor while moving only approved raster bodies")
    }

    func testV161PreservesEveryLaterPixelAndContactMetadata() throws {
        let old = try bundledDelivery("pitcher-delivery-back-v143")
        let current = try bundledDelivery("pitcher-delivery-back-v161")
        let oldAtlas = try atlas(old.camera.file), currentAtlas = try atlas(current.camera.file)
        for oldIndex in 11..<old.camera.frames.count {
            let a = old.camera.frames[oldIndex], b = current.camera.frames[oldIndex + 19]
            XCTAssertEqual(try pixels(crop(oldAtlas, frame: a)), try pixels(crop(currentAtlas, frame: b)),
                "Stride, plant, release and finish pixels must be copied exactly")
            XCTAssertEqual(a.hand, b.hand)
            XCTAssertEqual(a.handVisible, b.handVisible)
            XCTAssertEqual(a.leadFoot, b.leadFoot)
            XCTAssertEqual(a.rearFoot, b.rearFoot)
            XCTAssertEqual(a.offset, b.offset)
            XCTAssertEqual(a.shirt, b.shirt)
            XCTAssertEqual(a.cap, b.cap)
            XCTAssertEqual(a.number, b.number)
            XCTAssertEqual(a.numberAngle, b.numberAngle)
            XCTAssertEqual(a.clipRows, b.clipRows)
            XCTAssertEqual(a.coverageRuns, b.coverageRuns)
        }
    }

    func testV171PreservesSilhouetteAndUsesDynamicUniformsAndNumbers() throws {
        let delivery = try XCTUnwrap(FullBodyPitcherArt.refinedDelivery), source = try atlas(delivery.camera.file)
        let green = PlayerAppearance(kit: 1), blue = PlayerAppearance(kit: 0)
        let baseline = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: green, number: 27, hand: "right"))
        let numbered = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: green, number: 54, hand: "right"))
        let colored = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: blue, number: 54, hand: "right"))
        XCTAssertTrue(numbered === FullBodyPitcherArt.prepareRefined(appearance: green, number: 54, hand: "right"))
        XCTAssertFalse(numbered === baseline)
        XCTAssertFalse(numbered === colored)
        for index in delivery.camera.frames.indices {
            let frame = delivery.camera.frames[index]
            let encoded = try pixels(crop(source, frame: frame))
            let a = try pixels(XCTUnwrap(baseline.textures[index].cgImage()))
            let b = try pixels(XCTUnwrap(numbered.textures[index].cgImage()))
            let c = try pixels(XCTUnwrap(colored.textures[index].cgImage()))
            XCTAssertEqual(numbered.textures[index].filteringMode, .nearest)
            XCTAssertTrue(a != b, "Pose \(index) must draw the saved jersey number")
            var materials = [Int](repeating: 0, count: 7), capChanges = 0
            for pixel in 0..<(delivery.cell * delivery.cell) {
                let i = pixel * 4
                if encoded[i + 2] == 250, encoded[i + 1] < 4, encoded[i + 3] == 255,
                   (1...6).contains(Int(encoded[i])) {
                    materials[Int(encoded[i])] += 1
                    if encoded[i] == 2, b[i] != c[i] || b[i + 1] != c[i + 1] || b[i + 2] != c[i + 2] { capChanges += 1 }
                }
            }
            let alpha = stride(from: 3, to: b.count, by: 4)
            XCTAssertEqual(alpha.map { b[$0] }, alpha.map { encoded[$0] }, "Recoloring must preserve the approved silhouette")
            for material in 1...5 { XCTAssertGreaterThan(materials[material], 0, "Pose \(index), material \(material)") }
            XCTAssertEqual(capChanges, materials[2], "Every cap material pixel follows the selected kit")
        }
    }

    func testV171PackedTexturesPreserveAdjacentPosePixels() throws {
        let appearance = PlayerAppearance(kit: 1).wearing(teamID: "kbo-3", away: true)
        let delivery = try XCTUnwrap(FullBodyPitcherArt.refinedDelivery)
        let release = try XCTUnwrap(delivery.progress.firstIndex(of: 1))
        let frames = [0, 1, 8, 9, 11, 12, 13, release - 1, release, release + 1, delivery.progress.count - 1]
        for hand in ["left", "right"] {
            let prepared = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: appearance, number: 54, hand: hand))
            let backing = try XCTUnwrap(prepared.backingAtlas, "Valid V171 frames should use the shared atlas")
            XCTAssertEqual(backing.filteringMode, .nearest)
            XCTAssertEqual(prepared.textures.count, delivery.progress.count)
            for index in frames {
                let packed = prepared.textures[index]
                let separate = try XCTUnwrap(FullBodyPitcherArt.separateRefinedTextureForVerification(
                    index: index, appearance: appearance, number: 54, hand: hand))
                XCTAssertEqual(packed.filteringMode, .nearest)
                XCTAssertEqual(packed.size().width, CGFloat(delivery.cell), accuracy: 0.001)
                XCTAssertEqual(packed.size().height, CGFloat(delivery.cell), accuracy: 0.001)
                let packedImage = packed.cgImage(), separateImage = separate.cgImage()
                XCTAssertEqual(packedImage.width, separateImage.width)
                XCTAssertEqual(packedImage.height, separateImage.height)
                XCTAssertEqual(try pixels(packedImage), try pixels(separateImage), "\(hand) pose \(index)")
            }
        }
    }

    func testV171MatchAndPitchDrillShareApprovedPosesAndPreserveWorldContacts() throws {
        let delivery = try XCTUnwrap(FullBodyPitcherArt.refinedDelivery)
        let previous = try bundledDelivery("pitcher-delivery-back-v161")
        let oldStart = try XCTUnwrap(previous.camera.frames.first)
        let oldRelease = previous.camera.frames[try XCTUnwrap(previous.progress.firstIndex(of: 1))]
        let plantIndex = 29
        let releaseIndex = try XCTUnwrap(delivery.progress.firstIndex(of: 1))
        let finishIndex = delivery.camera.frames.count - 1
        XCTAssertEqual(delivery.camera.file, "pitcher-delivery-back-v171")
        XCTAssertEqual(delivery.progress.count, 71)
        XCTAssertEqual(delivery.progress.first, 0)
        XCTAssertEqual(delivery.progress.last, 2)
        XCTAssertEqual(releaseIndex, 34)
        XCTAssertEqual(delivery.progress[plantIndex], 966.6666667 / 1100, accuracy: 0.000001)
        XCTAssertEqual(delivery.camera.frames[plantIndex...].count, 42)
        let planted = delivery.camera.frames[plantIndex].leadFoot
        XCTAssertTrue(delivery.camera.frames[plantIndex...].allSatisfy { $0.leadFoot == planted })
        XCTAssertEqual(delivery.camera.frames.indices.filter { delivery.camera.frames[$0].ballInArtwork == true },
                       Array(12..<releaseIndex))

        func localContact(_ point: [Double], offset: [Double], anchor: FullBodyPitcherArt.Frame, cell: Int) -> CGPoint {
            let x = (point[0] + offset[0] - anchor.rearFoot[0] - anchor.offset[0]) * Double(cell)
            let y = (anchor.rearFoot[1] + anchor.offset[1] - point[1] - offset[1]) * Double(cell)
            return CGPoint(x: x, y: y)
        }

        let oldPlantContact = localContact(oldRelease.leadFoot, offset: oldRelease.offset, anchor: oldStart, cell: previous.cell)
        let oldReleaseContact = localContact(oldRelease.hand, offset: oldRelease.offset, anchor: oldStart, cell: previous.cell)
        let newStart = try XCTUnwrap(delivery.camera.frames.first)
        let newPlant = delivery.camera.frames[plantIndex]
        let newRelease = delivery.camera.frames[releaseIndex]
        let newPlantContact = localContact(newPlant.leadFoot, offset: newPlant.offset, anchor: newStart, cell: delivery.cell)
        let newReleaseContact = localContact(newRelease.hand, offset: newRelease.offset, anchor: newStart, cell: delivery.cell)
        XCTAssertEqual(newPlantContact.x, oldPlantContact.x, accuracy: 0.000000001)
        XCTAssertEqual(newPlantContact.y, oldPlantContact.y, accuracy: 0.000000001)
        XCTAssertEqual(newReleaseContact.x, oldReleaseContact.x, accuracy: 0.000000001)
        XCTAssertEqual(newReleaseContact.y, oldReleaseContact.y, accuracy: 0.000000001)

        func assertPoint(_ actual: CGPoint, _ expected: CGPoint, _ label: String) {
            // SpriteKit uses Float transforms for scene points. Check exact local
            // registration above and allow the rounding of the composed transform here.
            let xRounding = max(0.000001, CGFloat(Float(expected.x).ulp) * 2)
            let yRounding = max(0.000001, CGFloat(Float(expected.y).ulp) * 2)
            XCTAssertEqual(actual.x, expected.x, accuracy: xRounding, label)
            XCTAssertEqual(actual.y, expected.y, accuracy: yRounding, label)
        }

        for hand in ["left", "right"] {
            let direction: CGFloat = hand == "left" ? -1 : 1
            let appearance = PlayerAppearance(kit: 1).wearing(teamID: "kbo-3", away: true)
            let prepared = try XCTUnwrap(FullBodyPitcherArt.prepareRefined(appearance: appearance, number: 54, hand: hand))
            let game = BallparkScene(size: CGSize(width: 320, height: 339))
            game.configure(hand: hand, kit: 1, appearance: appearance, jerseyNumber: 54)
            let gameActor = try XCTUnwrap(game.childNode(withName: "animatedPitcher") as? SKSpriteNode)
            let gameRig = try XCTUnwrap(gameActor.childNode(withName: "fullBodyPitcher") as? FullBodyPitcherNode)
            let gameBody = try XCTUnwrap(gameRig.childNode(withName: "pitcherWholeBody") as? SKSpriteNode)
            let gameBall = try XCTUnwrap(game.childNode(withName: "baseball"))
            let drill = LocationDrillScene(size: CGSize(width: 320, height: 340))
            drill.configure(kind: .control, appearance: appearance, number: 54, hand: hand)
            let drillActor = try XCTUnwrap(drill.childNode(withName: "locationActor") as? SKSpriteNode)
            let drillRig = try XCTUnwrap(drillActor.childNode(withName: "fullBodyPitcher") as? FullBodyPitcherNode)
            let drillBody = try XCTUnwrap(drillRig.childNode(withName: "pitcherWholeBody") as? SKSpriteNode)
            let drillBall = try XCTUnwrap(drill.childNode(withName: "locationBall"))
            let releaseBeat = (SkillDrillRules.beats.last ?? SkillDrillRules.rhythmDuration) / SkillDrillRules.rhythmDuration
            let captureLabels = [0: "ready", 1: "33ms", 2: "67ms", 4: "133ms", plantIndex: "plant"]
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 320, height: 340))

            func previousContact(_ local: CGPoint, rig: FullBodyPitcherNode, scene: SKScene, scale: CGFloat) -> CGPoint {
                // Project the independently decoded V161 coordinates through SpriteKit's scene transform.
                return rig.convert(CGPoint(x: local.x * scale, y: local.y * scale), to: scene)
            }

            func capture(_ scene: SKScene, _ label: String) throws {
                view.presentScene(scene)
                let image = try XCTUnwrap(view.texture(from: scene)?.cgImage())
                let attachment = XCTAttachment(image: UIImage(cgImage: image))
                attachment.name = "v171-\(hand)-\(label)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }

            func assertSharedFrame(_ index: Int) throws {
                XCTAssertEqual(gameRig.frameIndex, index)
                XCTAssertEqual(drillRig.frameIndex, index)
                XCTAssertEqual(gameRig.displayedFrameIndex, index)
                XCTAssertEqual(drillRig.displayedFrameIndex, index)
                let expected = try pixels(XCTUnwrap(prepared.textures[index].cgImage()))
                XCTAssertEqual(try pixels(XCTUnwrap(gameBody.texture?.cgImage())), expected)
                XCTAssertEqual(try pixels(XCTUnwrap(drillBody.texture?.cgImage())), expected)
            }

            let drillScale: CGFloat = 128 / 164.6666666667
            let gamePlant = previousContact(oldPlantContact, rig: gameRig, scene: game, scale: 1)
            let drillPlant = previousContact(oldPlantContact, rig: drillRig, scene: drill, scale: drillScale)
            func rearFoot(_ frame: FullBodyPitcherArt.Frame, sprite: SKSpriteNode, scene: SKScene) -> CGPoint {
                let local = CGPoint(x: (frame.rearFoot[0] - sprite.anchorPoint.x) * sprite.size.width,
                                    y: (1 - frame.rearFoot[1] - sprite.anchorPoint.y) * sprite.size.height)
                return sprite.convert(local, to: scene)
            }
            let gameRearFoot = rearFoot(newStart, sprite: gameBody, scene: game)
            let drillRearFoot = rearFoot(newStart, sprite: drillBody, scene: drill)
            XCTAssertTrue(gameRig.usesRefinedDelivery)
            XCTAssertTrue(drillRig.usesRefinedDelivery)
            XCTAssertEqual(gameActor.xScale, direction)
            XCTAssertEqual(drillActor.xScale, direction)
            XCTAssertEqual(prepared.preparationMidpoints.keys.sorted(), Array(0..<20))
            for index in 0..<releaseIndex {
                let progress = delivery.progress[index] + 0.00000001
                game.preparePitch(phase: progress * 3 / 2.99 * ManualMatchRules.releaseCenter, reduced: false)
                drill.prepareDrill(phase: progress * releaseBeat)
                try assertSharedFrame(index)
                let frame = delivery.camera.frames[index]
                XCTAssertEqual(gameRig.hasVisibleHand, frame.handVisible)
                XCTAssertEqual(drillRig.hasVisibleHand, frame.handVisible)
                if frame.ballInArtwork == true {
                    XCTAssertTrue(gameBall.isHidden, "An authored held ball must not have a second ball drawn over it")
                    XCTAssertTrue(drillBall.isHidden)
                }
                if index >= plantIndex {
                    assertPoint(gameRig.convert(gameRig.leadFoot, to: game), gamePlant, "Match planted foot")
                    assertPoint(drillRig.convert(drillRig.leadFoot, to: drill), drillPlant, "Training planted foot")
                }
                if let label = captureLabels[index] {
                    try capture(game, "match-\(label)")
                    try capture(drill, "training-\(label)")
                }
                if index < 20 {
                    let midpoint = try XCTUnwrap(prepared.preparationMidpoints[index])
                    let midpointProgress = midpoint.progress + 0.00000001
                    game.preparePitch(phase: midpointProgress * 3 / 2.99 * ManualMatchRules.releaseCenter, reduced: false)
                    drill.prepareDrill(phase: midpointProgress * releaseBeat)
                    XCTAssertEqual(midpoint.textureIndex, delivery.progress.count + index)
                    XCTAssertEqual(gameRig.frameIndex, index)
                    XCTAssertEqual(drillRig.frameIndex, index)
                    XCTAssertEqual(gameRig.displayedFrameIndex, midpoint.textureIndex)
                    XCTAssertEqual(drillRig.displayedFrameIndex, midpoint.textureIndex)
                    XCTAssertEqual(midpoint.texture.filteringMode, .nearest)
                    let expected = try pixels(midpoint.texture.cgImage())
                    XCTAssertNotEqual(expected, try pixels(prepared.textures[index].cgImage()))
                    XCTAssertNotEqual(expected, try pixels(prepared.textures[index + 1].cgImage()))
                    XCTAssertEqual(try pixels(XCTUnwrap(gameBody.texture?.cgImage())), expected)
                    XCTAssertEqual(try pixels(XCTUnwrap(drillBody.texture?.cgImage())), expected)
                    let showsBall = midpoint.frame.ballInArtwork == true
                    XCTAssertEqual(showsBall, index >= 12)
                    for rig in [gameRig, drillRig] {
                        XCTAssertEqual(rig.hasVisibleHand, index >= 12)
                        XCTAssertEqual(rig.hasEmbeddedBall, showsBall)
                    }
                    XCTAssertTrue(gameBall.isHidden, "The separate ball stays hidden during occlusion or when the midpoint already contains it")
                    XCTAssertTrue(drillBall.isHidden)
                    assertPoint(rearFoot(midpoint.frame, sprite: gameBody, scene: game), gameRearFoot, "Match support foot during preparation")
                    assertPoint(rearFoot(midpoint.frame, sprite: drillBody, scene: drill), drillRearFoot, "Training support foot during preparation")
                    if index == 8 || index == 12 {
                        try capture(game, "match-midpoint-\(index)")
                        try capture(drill, "training-midpoint-\(index)")
                    }
                }
            }

            XCTAssertTrue(game.demonstrate(reduceMotion: false, flightDuration: 1, preparedRelease: true))
            let target = TrainingTarget(x: 0.6, y: 0.4)
            let replay = LocationDrillReplay(kind: .control, target: target, input: target, score: 72)
            let started = 40.0
            drill.play(replay, at: started) {}
            drill.advance(at: started + LocationDrillReplay.windup)
            try assertSharedFrame(releaseIndex)
            XCTAssertFalse(gameBall.isHidden)
            XCTAssertFalse(drillBall.isHidden)
            assertPoint(gameBall.position, gameRig.convert(gameRig.handPoint, to: game), "Match ball leaves the shown hand")
            assertPoint(drillBall.position, drillRig.convert(drillRig.handPoint, to: drill), "Training ball leaves the shown hand")
            assertPoint(gameBall.position, previousContact(oldReleaseContact, rig: gameRig, scene: game, scale: 1), "Match release position")
            assertPoint(drillBall.position, previousContact(oldReleaseContact, rig: drillRig, scene: drill, scale: drillScale), "Training release position")
            try capture(game, "match-release")
            try capture(drill, "training-release")

            game.advanceDelivery(at: ProcessInfo.processInfo.systemUptime + 1.1)
            drill.advance(at: started + LocationDrillReplay.windup + LocationDrillReplay.flight + 0.001)
            try assertSharedFrame(finishIndex)
            assertPoint(gameRig.convert(gameRig.leadFoot, to: game), gamePlant, "Match follow-through")
            assertPoint(drillRig.convert(drillRig.leadFoot, to: drill), drillPlant, "Training follow-through")
            try capture(game, "match-finish")
            try capture(drill, "training-finish")
            view.presentScene(nil)
            game.cancelDelivery()
            drill.cancel()
            XCTAssertEqual(gameRig.frameIndex, 0)
            XCTAssertEqual(drillRig.frameIndex, 0)
            XCTAssertEqual(gameRig.displayedFrameIndex, 0)
            XCTAssertEqual(drillRig.displayedFrameIndex, 0)
        }
    }
}
