import XCTest
import UIKit
@testable import BM

@MainActor final class ManagementPortraitTests: XCTestCase {
    func testV166EverySavedFacialSelectionProducesAVisibleDistinctPortrait() throws {
        let base = appearance()
        let encoded = try stored(base)
        var rows = [[UIImage]]()
        let dimensions: [(String, Int)] = [("hairStyle", 8), ("eye", 4), ("brow", 4),
                                            ("expression", 6), ("skin", 6), ("hairColor", 6)]
        for (field, count) in dimensions {
            var signatures = Set<Data>(), pictures = [UIImage]()
            for index in 0..<count {
                var selected = base
                switch field {
                case "hairStyle": selected.hairStyle = index
                case "eye": selected.eyeShape = index
                case "brow": selected.browShape = index
                case "expression": selected.expression = index
                case "skin": selected.skin = index
                default: selected.hair = index
                }
                let before = try stored(selected)
                let image = try XCTUnwrap(ManagementPortraitRasterV166.image(selected, number: 27), "Missing \(field) \(index)")
                let source = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(source.width, 256); XCTAssertEqual(source.height, 256)
                let counts = try alphaCounts(image)
                XCTAssertGreaterThan(counts.opaque, 8_000, "Portrait must contain visible artwork: \(field) \(index)")
                XCTAssertGreaterThan(counts.transparent, 1_000, "Atlas cell must retain its transparent margin")
                signatures.insert(try XCTUnwrap(image.pngData()))
                pictures.append(image)
                XCTAssertEqual(try stored(selected), before, "Rendering may not rewrite an appearance")
            }
            XCTAssertEqual(signatures.count, count, "Each saved \(field) option must remain visually distinct")
            rows.append(pictures)
        }
        XCTAssertEqual(try stored(base), encoded)
        attach(sheet(rows, labels: dimensions.map(\.0)), name: "V166-native-independent-appearance-selections")
    }

    func testV166PortraitCacheSeparatesUniformsAndPreservesStoredLook() throws {
        let base = appearance(), original = try stored(base)
        let views = [base.wearing(teamID: "hs-ref-001"), base.wearing(teamID: "kbo-0"),
                     base.wearing(teamID: "kbo-0", away: true), base.wearing(teamID: "npb-12"),
                     base.wearing(teamID: "npb-12", away: true), base.wearing(teamID: "mlb-12"),
                     base.wearing(teamID: "mlb-12", away: true)]
        var keys = Set<String>(), pictures = [UIImage](), images = Set<Data>()
        for look in views {
            let key = ManagementPortraitRasterV166.key(look, role: .pitcher, number: 27, cap: true)
            keys.insert(key)
            let image = try XCTUnwrap(ManagementPortraitRasterV166.image(look, role: .pitcher, number: 27, cap: true))
            let cached = try XCTUnwrap(ManagementPortraitRasterV166.image(look, role: .pitcher, number: 27, cap: true))
            XCTAssertTrue(image === cached, "Unchanged render context should reuse the same raster")
            images.insert(try XCTUnwrap(image.pngData())); pictures.append(image)
            XCTAssertEqual(try stored(look), original, "Team/home-away render context is not a saved appearance mutation")
            XCTAssertTrue(key.contains(ManagementPortraitRasterV166.version))
        }
        XCTAssertEqual(keys.count, views.count)
        XCTAssertEqual(images.count, views.count, "Different club and home-away uniforms must be visible")
        let selected = views[1]
        XCTAssertNotEqual(ManagementPortraitRasterV166.key(selected, number: 27), ManagementPortraitRasterV166.key(selected, number: 18))
        XCTAssertNotEqual(ManagementPortraitRasterV166.key(selected, cap: false), ManagementPortraitRasterV166.key(selected, cap: true))
        XCTAssertNotEqual(ManagementPortraitRasterV166.key(selected, role: .batter), ManagementPortraitRasterV166.key(selected, role: .pitcher))
        attach(sheet([pictures], labels: ["school / KBO H-A / NPB H-A / MLB H-A"]), name: "V166-native-club-home-away-portraits")
    }

    func testV166ApprovedStartingStylesKeepIndependentLegacyFields() throws {
        let base = appearance()
        var pictures = [UIImage]()
        for index in 0..<4 {
            var look = base
            look.skin = index == 2 ? 2 : 0; look.hair = 0
            look.hairStyle = [0, 1, 3, 7][index]
            look.eyeShape = [0, 0, 2, 1][index]
            look.browShape = [0, 1, 1, 3][index]
            look.expression = index < 2 ? 2 : 0
            let original = try stored(look)
            let image = try XCTUnwrap(ManagementPortraitRasterV166.image(look, number: 27))
            pictures.append(image)
            var custom = look; custom.eyeShape = (look.eyeIndex + 1) % PlayerAppearance.eyeNames.count
            pictures.append(try XCTUnwrap(ManagementPortraitRasterV166.image(custom, number: 27)))
            XCTAssertNotEqual(image.pngData(), pictures.last?.pngData(), "A starting style must not suppress later eye selection")
            XCTAssertEqual(try stored(look), original)
        }
        attach(sheet([pictures], labels: ["A / A eyes / B / B eyes / C / C eyes / D / D eyes"]), name: "V166-native-starting-styles-and-custom-eyes")
        var invalid = base; invalid.hairStyle = PlayerAppearance.hairNames.count
        XCTAssertNil(ManagementPortraitRasterV166.image(invalid))
    }

    private func appearance() -> PlayerAppearance {
        var value = PlayerAppearance()
        value.creationVersion = 1; value.schoolKitID = "hs-ref-001"
        value.eyeShape = 0; value.browShape = 0
        return value
    }

    private func stored(_ appearance: PlayerAppearance) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(appearance)
    }

    private func alphaCounts(_ image: UIImage) throws -> (opaque: Int, transparent: Int) {
        let source = try XCTUnwrap(image.cgImage), width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        XCTAssertTrue(valid)
        return (stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 200 }.count,
                stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] < 24 }.count)
    }

    private func sheet(_ rows: [[UIImage]], labels: [String]) -> UIImage {
        let width = max(1, rows.map(\.count).max() ?? 1) * 256, rowHeight = 284
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: max(1, rows.count) * rowHeight), format: format).image { renderer in
            UIColor(red: 0.04, green: 0.13, blue: 0.19, alpha: 1).setFill(); renderer.fill(CGRect(x: 0, y: 0, width: width, height: rows.count * rowHeight))
            for (row, pictures) in rows.enumerated() {
                (labels[row] as NSString).draw(at: CGPoint(x: 8, y: row * rowHeight + 4), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.white])
                for (column, image) in pictures.enumerated() { image.draw(in: CGRect(x: column * 256, y: row * rowHeight + 28, width: 256, height: 256)) }
            }
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
