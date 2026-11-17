import XCTest
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
}
