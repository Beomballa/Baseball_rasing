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

    func testV167ApprovedReferenceGeometryAndNoseRGBRemainFaithful() throws {
        let atlas = try XCTUnwrap(UIImage(named: "ManagementPortraitReferenceV167")?.cgImage)
        XCTAssertEqual(atlas.width, 1254); XCTAssertEqual(atlas.height, 1254)
        let rawA = try v167Pixels(UIImage(cgImage: v167GridCell(atlas, column: 0, row: 0, columns: 2, rows: 2)))
        // Direct RGBA samples from the approved PNG (stdlib PNG decode), before UIKit resizing.
        // Distinct top/nose/shirt samples detect an accidental bitmap Y flip in this test utility.
        for (x, y, expected) in [(300, 80, [3, 12, 29, 251]), (375, 293, [255, 203, 153, 253]),
                                  (380, 302, [92, 41, 25, 253]), (300, 560, [36, 91, 60, 253])] {
            let actual = rawA.rgba(x, y)
            for channel in 0..<4 { XCTAssertLessThanOrEqual(abs(actual[channel] - expected[channel]), 3,
                                                           "Reference PNG coordinate orientation or color decoding changed") }
        }
        XCTAssertNotEqual(ManagementPortraitRasterV166.version, "v166-layered-1", "Repair must invalidate old cached portraits")
        var comparisons = [[UIImage]]()
        for index in 0..<4 {
            let look = v167StartingLook(index), original = try stored(look)
            let reference = try v167ApprovedCell(index, atlas: atlas)
            let actual = try XCTUnwrap(ManagementPortraitRasterV166.image(look, number: 27))
            let expectedPixels = try v167Pixels(reference), actualPixels = try v167Pixels(actual)
            XCTAssertEqual(actualPixels.width, 256); XCTAssertEqual(actualPixels.height, 256)
            var compared = 0, changed = 0, totalError = 0, alphaChanges = 0
            // The approved browser uses the complete 627px cell, not an alpha-tight or stretched head.
            for y in 0..<154 { for x in 0..<256 {
                let source = expectedPixels.rgba(x, y), rendered = actualPixels.rgba(x, y)
                if abs(source[3] - rendered[3]) > 2 { alphaChanges += 1 }
                // Uniform greens can start above the neckline in C/D; face/hair RGB remains source artwork.
                guard source[3] > 245, !(source[1] > source[0] + 3 && source[1] > source[2] + 3) else { continue }
                let error = (0..<3).map { abs(source[$0] - rendered[$0]) }
                compared += 1; totalError += error.reduce(0, +)
                if error.max()! > 3 { changed += 1 }
            } }
            XCTAssertGreaterThan(compared, 8_000, "Reference comparison must include actual face/hair artwork")
            XCTAssertLessThanOrEqual(alphaChanges, 8, "\(index): approved head silhouette/scale moved")
            XCTAssertLessThanOrEqual(Double(changed) / Double(max(1, compared)), 0.01,
                                     "\(index): facial feature geometry or palette differs from the approved cell")
            XCTAssertLessThanOrEqual(Double(totalError) / Double(max(1, compared * 3)), 1.5)
            v167AssertSameRegion(expectedPixels, actualPixels, rect: v167Landmarks[index].nose,
                                 message: "Canonical \(index) nose RGB must survive compositing")
            XCTAssertEqual(try stored(look), original)
            comparisons.append([reference, actual])
        }
        attach(sheet(comparisons, labels: ["A reference / native", "B reference / native", "C reference / native", "D reference / native"]),
               name: "V167-native-approved-reference-geometry-and-nose")
        try v167CaptureAllHairCustomAndCaps()
    }

    func testV167AllIndependentChoicesProtectNoseAndJawAtEverySkinTone() throws {
        // Source reference families are fixed by the approved A-D artwork; alternative hair must not move a face.
        let families = [0, 1, 0, 2, 0, 1, 0, 3]
        for hairStyle in PlayerAppearance.hairNames.indices {
            let family = families[hairStyle], landmark = v167Landmarks[family]
            let jaw = CGRect(x: 90, y: landmark.mouth.maxY + 2, width: 110, height: 185 - landmark.mouth.maxY - 2)
            for skin in PlayerAppearance.skinColors.indices {
                var base = v167StartingLook(family); base.hairStyle = hairStyle; base.skin = skin
                let baseline = try v167Pixels(XCTUnwrap(ManagementPortraitRasterV166.image(base, number: 27)))
                for (field, count) in [("eye", 4), ("brow", 4), ("mouth", 6), ("hairColor", 6)] {
                    for selection in 0..<count {
                        var look = base
                        switch field {
                        case "eye": look.eyeShape = selection
                        case "brow": look.browShape = selection
                        case "mouth": look.expression = selection
                        default: look.hair = selection
                        }
                        let original = try stored(look)
                        let rendered = try v167Pixels(XCTUnwrap(ManagementPortraitRasterV166.image(look, number: 27)))
                        let context = "hair \(hairStyle), skin \(skin), \(field) \(selection)"
                        v167AssertSameRegion(baseline, rendered, rect: landmark.nose, message: context + " nose")
                        v167AssertSameRegion(baseline, rendered, rect: jaw, message: context + " jaw/neck")
                        XCTAssertEqual(try stored(look), original)
                    }
                }
                var combined = base
                combined.eyeShape = 3; combined.browShape = 3; combined.expression = 5; combined.hair = 5
                let rendered = try v167Pixels(XCTUnwrap(ManagementPortraitRasterV166.image(combined, number: 27)))
                v167AssertSameRegion(baseline, rendered, rect: landmark.nose, message: "combined hair \(hairStyle), skin \(skin) nose")
                v167AssertSameRegion(baseline, rendered, rect: jaw, message: "combined hair \(hairStyle), skin \(skin) jaw/neck")
            }
        }
    }

    func testV167SkinVariantsKeepNoseChromaAndShadowRange() throws {
        let atlas = try XCTUnwrap(UIImage(named: "ManagementPortraitReferenceV167")?.cgImage)
        var pictures = [[UIImage]]()
        for index in 0..<4 {
            let source = try v167Pixels(v167ApprovedCell(index, atlas: atlas)), rect = v167Landmarks[index].nose
            let points = v167Points(in: rect).filter { x, y in
                let pixel = source.rgba(x, y)
                return pixel[3] > 220 && pixel[0] > 40 && pixel[0] > pixel[1] + 12 && pixel[1] > pixel[2] + 4
            }
            XCTAssertGreaterThan(points.count, 15, "Nose test must measure source shading, not empty pixels")
            let referenceChroma = v167Deviation(points.map { x, y in
                let p = source.rgba(x, y); return Double(p[1]) / Double(max(1, p[0]))
            })
            let referenceRed = points.map { source.rgba($0.0, $0.1)[0] }
            let referenceRange = (referenceRed.max() ?? 0) - (referenceRed.min() ?? 0)
            XCTAssertGreaterThan(referenceChroma, 0.015); XCTAssertGreaterThan(referenceRange, 25)
            var row = [UIImage]()
            for skin in PlayerAppearance.skinColors.indices {
                var look = v167StartingLook(index); look.skin = skin
                let image = try XCTUnwrap(ManagementPortraitRasterV166.image(look, number: 27)), pixels = try v167Pixels(image)
                let ratios = points.map { x, y in
                    let p = pixels.rgba(x, y); return Double(p[1]) / Double(max(1, p[0]))
                }
                let red = points.map { pixels.rgba($0.0, $0.1)[0] }
                XCTAssertGreaterThan(v167Deviation(ratios), referenceChroma * 0.25,
                                     "\(index)/\(skin): nose chroma must not collapse into one R-derived tint")
                XCTAssertGreaterThan(Double((red.max() ?? 0) - (red.min() ?? 0)), Double(referenceRange) * 0.2,
                                     "\(index)/\(skin): preserve dark/light facial shading at every skin tone")
                row.append(image)
            }
            pictures.append(row)
        }
        attach(sheet(pictures, labels: ["A six skin tones", "B six skin tones", "C six skin tones", "D six skin tones"]),
               name: "V167-native-nose-chroma-six-skin-tones")
    }

    func testV167ChangedFeaturesKeepSourceInkAspectAndNativeEvidence() throws {
        let atlas = try XCTUnwrap(UIImage(named: "ManagementFeaturesV166")?.cgImage)
        let landmark = v167Landmarks[0], canonical = [0, 0, 2], targets = [landmark.eyes, landmark.brows, landmark.mouth]
        var rows = [[UIImage]]()
        for (row, count) in [(0, 4), (1, 4), (2, 6)] {
            var pictures = [UIImage]()
            for selection in 0..<count {
                var look = v167StartingLook(0)
                if row == 0 { look.eyeShape = selection }
                else if row == 1 { look.browShape = selection }
                else { look.expression = selection }
                let image = try XCTUnwrap(ManagementPortraitRasterV166.image(look, number: 27))
                pictures.append(image)
                if selection == canonical[row] { continue }
                let glyph = try v167GridCell(atlas, column: selection, row: row, columns: 6, rows: 3)
                let sourcePixels = try v167Pixels(UIImage(cgImage: glyph))
                let sourceInk = try XCTUnwrap(v167InkBounds(sourcePixels, rect: CGRect(x: 0, y: 0, width: sourcePixels.width, height: sourcePixels.height)))
                let nativeInk = try XCTUnwrap(v167InkBounds(try v167Pixels(image), rect: targets[row].insetBy(dx: 1, dy: 1), excluding: landmark.nose),
                                             "\(row)/\(selection): selected glyph must contain visible ink")
                let sourceAspect = sourceInk.width / sourceInk.height
                // Three output pixels cover nearest-neighbor quantization of the smallest 2-3px mouth lines.
                XCTAssertLessThanOrEqual(abs(nativeInk.height - nativeInk.width / sourceAspect), 3,
                                         "\(row)/\(selection): glyph ink is stretched independently in X/Y")
            }
            rows.append(pictures)
        }
        attach(sheet(rows, labels: ["eyes 0-3", "brows 0-3", "mouth 0-5"]), name: "V167-native-independent-feature-aspect")
    }

    private func v167CaptureAllHairCustomAndCaps() throws {
        let families = [0, 1, 0, 2, 0, 1, 0, 3]
        var originals = [UIImage](), originalCaps = [UIImage](), customs = [UIImage](), customCaps = [UIImage]()
        for hairStyle in PlayerAppearance.hairNames.indices {
            let family = families[hairStyle], nose = v167Landmarks[family].nose
            var original = v167StartingLook(family); original.hairStyle = hairStyle
            let plain = try XCTUnwrap(ManagementPortraitRasterV166.image(original, number: 27))
            let cap = try XCTUnwrap(ManagementPortraitRasterV166.image(original, number: 27, cap: true))
            originals.append(plain); originalCaps.append(cap)
            v167AssertSameRegion(try v167Pixels(plain), try v167Pixels(cap), rect: nose, message: "hair \(hairStyle) cap cannot erase the nose")
            var custom = original
            custom.eyeShape = (hairStyle + 1) % 4; custom.browShape = (hairStyle + 2) % 4
            custom.expression = (hairStyle + 3) % 6; custom.hair = (hairStyle + 1) % 6; custom.skin = (hairStyle + 2) % 6
            let selected = try XCTUnwrap(ManagementPortraitRasterV166.image(custom, number: 27))
            let selectedCap = try XCTUnwrap(ManagementPortraitRasterV166.image(custom, number: 27, cap: true))
            customs.append(selected); customCaps.append(selectedCap)
            v167AssertSameRegion(try v167Pixels(selected), try v167Pixels(selectedCap), rect: nose, message: "custom hair \(hairStyle) cap cannot erase the nose")
        }
        attach(sheet([originals, originalCaps, customs, customCaps],
                     labels: ["all8hair native", "all8hair caps", "all8hair custom skin/hair/features", "all8hair custom + caps"]),
               name: "V167-native-all8hair-custom-and-caps")
    }

    private struct V167Landmark {
        let eyes: CGRect, brows: CGRect, mouth: CGRect, nose: CGRect
    }
    // Approved 627px source-cell measurements, normalized to 256px. See the V166 iteration02
    // paintPortrait crop and V167 reference-landmarks.json; these are reference ROIs, not renderer APIs.
    private var v167Landmarks: [V167Landmark] {
        [V167Landmark(eyes: CGRect(x: 114, y: 99, width: 62, height: 16), brows: CGRect(x: 114, y: 90, width: 62, height: 10), mouth: CGRect(x: 134, y: 132, width: 25, height: 13), nose: CGRect(x: 147, y: 112, width: 12, height: 16)),
         V167Landmark(eyes: CGRect(x: 101, y: 96, width: 61, height: 14), brows: CGRect(x: 101, y: 86, width: 61, height: 11), mouth: CGRect(x: 121, y: 130, width: 27, height: 13), nose: CGRect(x: 135, y: 107, width: 13, height: 18)),
         V167Landmark(eyes: CGRect(x: 116, y: 73, width: 63, height: 15), brows: CGRect(x: 116, y: 63, width: 64, height: 12), mouth: CGRect(x: 134, y: 108, width: 31, height: 16), nose: CGRect(x: 145, y: 88, width: 18, height: 20)),
         V167Landmark(eyes: CGRect(x: 107, y: 80, width: 62, height: 15), brows: CGRect(x: 106, y: 68, width: 64, height: 14), mouth: CGRect(x: 126, y: 114, width: 29, height: 14), nose: CGRect(x: 145, y: 94, width: 15, height: 20))]
    }
    private func v167StartingLook(_ index: Int) -> PlayerAppearance {
        var look = appearance()
        look.skin = [0, 0, 2, 0][index]; look.hair = 0
        look.hairStyle = [0, 1, 3, 7][index]
        look.eyeShape = [0, 0, 2, 1][index]; look.browShape = [0, 1, 1, 3][index]
        look.expression = [2, 2, 0, 0][index]
        return look
    }
    private struct V167Pixels {
        let width: Int, height: Int, bytes: [UInt8]
        func rgba(_ x: Int, _ y: Int) -> [Int] {
            let offset = (y * width + x) * 4, alpha = Int(bytes[offset + 3])
            return (0..<3).map { alpha > 0 ? min(255, Int(bytes[offset + $0]) * 255 / alpha) : 0 } + [alpha]
        }
    }
    private func v167Pixels(_ image: UIImage) throws -> V167Pixels {
        let source = try XCTUnwrap(image.cgImage), width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none; context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        XCTAssertTrue(valid)
        return V167Pixels(width: width, height: height, bytes: bytes)
    }
    private func v167GridCell(_ source: CGImage, column: Int, row: Int, columns: Int, rows: Int) throws -> CGImage {
        let left = Int((Double(column) * Double(source.width) / Double(columns)).rounded())
        let right = Int((Double(column + 1) * Double(source.width) / Double(columns)).rounded())
        let top = Int((Double(row) * Double(source.height) / Double(rows)).rounded())
        let bottom = Int((Double(row + 1) * Double(source.height) / Double(rows)).rounded())
        return try XCTUnwrap(source.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)))
    }
    private func v167ApprovedCell(_ index: Int, atlas: CGImage) throws -> UIImage {
        let cell = try v167GridCell(atlas, column: index % 2, row: index / 2, columns: 2, rows: 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            renderer.cgContext.interpolationQuality = .none
            UIImage(cgImage: cell).draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
        }
    }
    private func v167Points(in rect: CGRect) -> [(Int, Int)] {
        (Int(rect.minY)..<Int(rect.maxY)).flatMap { y in (Int(rect.minX)..<Int(rect.maxX)).map { ($0, y) } }
    }
    private func v167AssertSameRegion(_ expected: V167Pixels, _ actual: V167Pixels, rect: CGRect, message: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        var maximum = 0, firstChanged = ""
        for (x, y) in v167Points(in: rect) {
            let left = expected.rgba(x, y), right = actual.rgba(x, y)
            let difference = zip(left, right).map { abs($0.0 - $0.1) }.max() ?? 0
            if difference > maximum { maximum = difference; firstChanged = " (\(x),\(y)): \(left) vs \(right)" }
        }
        XCTAssertLessThanOrEqual(maximum, 1, message + firstChanged, file: file, line: line)
    }
    private func v167Deviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count))
    }
    private func v167InkBounds(_ pixels: V167Pixels, rect: CGRect, excluding protected: CGRect? = nil) -> CGRect? {
        let points = v167Points(in: rect).filter { x, y in
            if protected?.contains(CGPoint(x: x, y: y)) == true { return false }
            let pixel = pixels.rgba(x, y), rgb = Array(pixel.prefix(3))
            return pixel[3] > 180 && rgb.max()! < 130 && rgb.max()! - rgb.min()! < 100
        }
        guard let first = points.first else { return nil }
        var left = first.0, right = first.0, top = first.1, bottom = first.1
        for (x, y) in points { left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y) }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
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
