import XCTest
import SpriteKit
import UIKit
import SwiftData
@testable import BM

@MainActor final class ManagementVenueTests: XCTestCase {
    func testV166RenderedCloseupsKeepActorsAndTeamVenueBothRoles() throws {
        for role in [PlayerRole.batter, .pitcher] {
            for team in ["hs-ref-001", "kbo-0", "npb-12", "mlb-12"] {
                var look = PlayerAppearance(); look.creationVersion = 1
                look = look.wearing(teamID: team)
                let scene = BallparkScene(size: CGSize(width: 320, height: 340))
                scene.configure(hand: role == .pitcher ? "left" : "right", kit: look.kit,
                    role: role, appearance: look, jerseyNumber: 27)
                scene.setStadium(StadiumIdentity(homeTeamID: team))
                XCTAssertNotNil(scene.childNode(withName: "fixedStadiumBackground/clubStadiumBackdrop"))
                let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
                view.presentScene(scene)
                let rendered = try XCTUnwrap(view.texture(from: scene)?.cgImage())
                let attachment = XCTAttachment(image: UIImage(cgImage: rendered))
                attachment.name = "V166-native-closeup-\(role.rawValue)-\(team)"
                attachment.lifetime = .keepAlways; add(attachment)
                view.presentScene(nil)
            }
        }
    }

    func testV166RosterAffiliationAndActionUseEachPlayersOwnCalendarWithoutWrites() throws {
        let schools = try SchoolCatalog.load(), container = try CareerStore.makeContainer(inMemory: true)
        let context = container.mainContext
        var batterDraft = PlayerDraft(); batterDraft.name = "RosterBat"; batterDraft.schoolID = "hs-ref-001"
        var pitcherDraft = PlayerDraft(); pitcherDraft.name = "RosterPitch"; pitcherDraft.role = .pitcher; pitcherDraft.schoolID = "hs-ref-002"
        let batter = try CareerStore.create(batterDraft, schools: schools, in: context)
        let pitcher = try CareerStore.create(pitcherDraft, schools: schools, in: context)
        let calendars = try context.fetch(FetchDescriptor<CareerCalendarState>())
        let first = try XCTUnwrap(calendars.first { $0.playerID == batter.id })
        let second = try XCTUnwrap(calendars.first { $0.playerID == pitcher.id })
        first.actionDate = batter.gameDate; try context.save()
        let originalBatter = batter.lifecycleData, originalPitcher = pitcher.lifecycleData
        let firstRevision = first.revision, secondRevision = second.revision
        let a = ManagementPlayerAffiliation.read(player: batter, calendar: first)
        let b = ManagementPlayerAffiliation.read(player: pitcher, calendar: second)
        XCTAssertEqual(a.name, batter.displaySchoolName); XCTAssertEqual(b.name, pitcher.displaySchoolName)
        XCTAssertEqual(a.appearance.uniformTeamID, batter.schoolID); XCTAssertEqual(b.appearance.uniformTeamID, pitcher.schoolID)
        XCTAssertNotEqual(a.appearance.uniformTeamID, b.appearance.uniformTeamID)
        XCTAssertFalse(a.actionAvailable); XCTAssertTrue(b.actionAvailable)
        XCTAssertEqual(batter.lifecycleData, originalBatter); XCTAssertEqual(pitcher.lifecycleData, originalPitcher)
        XCTAssertEqual(first.revision, firstRevision); XCTAssertEqual(second.revision, secondRevision)
        XCTAssertFalse(context.hasChanges)
    }

    func testV166VenueCompositePreservesTheOriginalPlayingSurfaceBothRoles() throws {
        for role in [PlayerRole.batter, .pitcher] {
            let original = try XCTUnwrap(MatchArt.image(role == .batter ? "batter-field-v52" : "pitcher-field-v52"))
            let source = try pixels(original)
            for team in ["hs-ref-001", "kbo-0", "npb-12", "mlb-12"] {
                let image = try XCTUnwrap(MatchStadiumBackdropArt.art(stadium: StadiumIdentity(homeTeamID: team), role: role)?.image)
                XCTAssertEqual(image.size, original.size)
                let value = try pixels(image)
                let protectedY = role == .pitcher ? 650 : 281
                let start = protectedY * source.width * 4
                XCTAssertEqual(value.width, source.width); XCTAssertEqual(value.height, source.height)
                XCTAssertTrue(value.bytes[start...] == source.bytes[start...], "The plate, mound and playing surface changed for \(role.rawValue)/\(team)")
                XCTAssertFalse(value.bytes[..<(100 * source.width * 4)] == source.bytes[..<(100 * source.width * 4)], "The team stands were not connected")
                let attachment = XCTAttachment(image: image)
                attachment.name = "v166-venue-\(role.rawValue)-\(team)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    func testV166VenueCacheAndSceneKeepCameraProjectionAndPracticeIndependent() throws {
        let first = StadiumIdentity(homeTeamID: "kbo-0"), second = StadiumIdentity(homeTeamID: "npb-12")
        let art = try XCTUnwrap(MatchStadiumBackdropArt.art(stadium: first, role: .pitcher))
        XCTAssertTrue(art === MatchStadiumBackdropArt.art(stadium: first, role: .pitcher))
        XCTAssertFalse(art === MatchStadiumBackdropArt.art(stadium: second, role: .pitcher))
        XCTAssertFalse(art === MatchStadiumBackdropArt.art(stadium: first, role: .batter))
        let scene = BallparkScene(size: CGSize(width: 320, height: 340))
        scene.configure(hand: "left", kit: 0, role: .pitcher)
        let field = try XCTUnwrap(scene.childNode(withName: "fixedStadiumBackground") as? SKSpriteNode)
        let size = scene.size, frame = field.frame, texture = field.texture
        let pitcher = try XCTUnwrap(scene.childNode(withName: "animatedPitcher"))
        let foot = pitcher.position, arrival = scene.arrivalPoint(x: 0.3, y: 0.7)
        scene.setStadium(first)
        XCTAssertEqual(scene.size, size); XCTAssertEqual(field.frame, frame); XCTAssertEqual(field.xScale, -1)
        XCTAssertTrue(field.texture === texture)
        XCTAssertNotNil(field.childNode(withName: "clubStadiumBackdrop"))
        XCTAssertNotNil(scene.childNode(withName: "//match-club-logo-kbo-0"))
        XCTAssertEqual(pitcher.position, foot); XCTAssertEqual(scene.arrivalPoint(x: 0.3, y: 0.7), arrival)
        scene.setStadium(second)
        XCTAssertEqual(field.frame, frame); XCTAssertEqual(pitcher.position, foot)
        XCTAssertEqual(scene.arrivalPoint(x: 0.3, y: 0.7), arrival)
        scene.usePracticeSetting()
        XCTAssertNil(field.childNode(withName: "clubStadiumBackdrop"))
        XCTAssertEqual(scene.arrivalPoint(x: 0.3, y: 0.7), arrival)
    }

    private func pixels(_ image: UIImage) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let source = try XCTUnwrap(image.cgImage), width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.interpolationQuality = .none
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (width, height, bytes)
    }
}
