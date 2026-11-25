import XCTest
import SpriteKit
import CryptoKit
import UIKit
@testable import BM

@MainActor final class InplayWideStadiumArtTests: XCTestCase {
    func testApprovedCatalogCoversSchoolsClubsAliasesAndNormalizedBoards() throws {
        let catalog=try XCTUnwrap(InplayWideStadiumArt.catalog)
        let expected=Set(SchoolCatalog.bundled.map(\.id)+ClubIdentity.all.map(\.id))
        XCTAssertEqual(Set(catalog.venues.keys),expected);XCTAssertEqual(catalog.venues.count,90)
        let aliases=CareerTeamDirectory.expandedDomesticFirstIDs+CareerTeamDirectory.japaneseExpandedFirstIDs+CareerTeamDirectory.americanExpandedFirstIDs
        XCTAssertEqual(Set(catalog.aliases.keys),Set(aliases));XCTAssertEqual(catalog.aliases.count,40)
        for (id,venue) in catalog.venues {
            XCTAssertTrue(venue.valid,id)
            for width in [320.0,390,430,600] {
                let size=CGSize(width:width,height:width*2/3),frame=venue.boardRect.topLeftFrame(in:size)
                XCTAssertTrue(CGRect(origin:.zero,size:size).contains(frame),id)
                let board=try XCTUnwrap(InplayStadiumArt.scoreboard(StadiumIdentity(homeTeamID:id),in:size))
                XCTAssertEqual(board.frame,frame,id)
            }
        }
    }
    func testAllNinetyBundledFilesMatchApprovedHashesAndAliasCache() throws {
        let url=try XCTUnwrap(Bundle.main.url(forResource:"venues",withExtension:"json",subdirectory:InplayWideStadiumArt.directory))
        func hash(_ data:Data) -> String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        XCTAssertEqual(hash(try Data(contentsOf:url)),"8d4a202975ae633e64915cb4be227914b15682e54a62b4b0cc0cf369e9ee3411")
        let catalog=try XCTUnwrap(InplayWideStadiumArt.catalog)
        for id in catalog.venues.keys.sorted() {
            try autoreleasepool {
                let art=try XCTUnwrap(InplayWideStadiumArt.artwork(for:.init(homeTeamID:id)),id)
                XCTAssertEqual(art.canonicalID,id);XCTAssertEqual(art.image.size,CGSize(width:1536,height:1024))
                let imageURL=url.deletingLastPathComponent().appendingPathComponent(art.venue.asset)
                XCTAssertEqual(hash(try Data(contentsOf:imageURL)),art.venue.sha256,id)
            }
        }
        for (alias,id) in catalog.aliases {
            let canonical=try XCTUnwrap(InplayWideStadiumArt.artwork(for:.init(homeTeamID:id)))
            let mapped=try XCTUnwrap(InplayWideStadiumArt.artwork(for:.init(homeTeamID:alias)))
            XCTAssertTrue(canonical === mapped,alias);XCTAssertEqual(mapped.canonicalID,id)
            XCTAssertEqual(StadiumIdentity(homeTeamID:alias).pro?.club.id,id)
        }
    }
    func testUnknownHomeKeepsV240WithoutInventingVenue() throws {
        for id in ["legacy-ground","college-0","unregistered-home"] {
            let stadium=StadiumIdentity(homeTeamID:id)
            XCTAssertNil(InplayWideStadiumArt.venue(for:stadium));XCTAssertNil(InplayWideStadiumArt.artwork(for:stadium))
            XCTAssertTrue(try XCTUnwrap(InplayStadiumArt.backgroundImage(for:stadium)) === XCTUnwrap(InplayStadiumArt.image))
        }
    }
    func testActualFieldAndHomeRunScenesUseVenueBoardAndSameProjection() async throws {
        let play=try FieldVerificationScenario.single.make()
        let homeRun=try XCTUnwrap(MatchReplayFixture.make(pitcher:false).compactMap(\.homeRun).first)
        let sprites=FieldReplaySprites(appearance:PlayerAppearance(),jerseyNumber:27,ownPosition:"P",throwingHand:"right",ownTeamFielding:true)
        for replay in [InplayReplay.field(play),.homeRun(homeRun)] {
            let planned=await sprites.requests(duration:replay.duration,reduced:false,
                actorsAt:{replay.actors(sprites,time:$0,reduced:false,finished:false)})
            let requests=try XCTUnwrap(planned)
            let preparedImages=await FieldRasterArt.prepare(requests)
            let prepared=try XCTUnwrap(preparedImages)
            for id in ["hs-ref-001","hs-ref-024","kbo-0","npb-0","mlb-1"] {
                let stadium=StadiumIdentity(homeTeamID:id)
                let scene=InplayFieldScene(replay:replay,sprites:sprites,prepared:prepared,scoreText:"H 3 : 2 A",stadium:stadium)
                await scene.preload()
                let view=SKView(frame:CGRect(origin:.zero,size:scene.size));view.presentScene(scene)
                scene.display(time:replay.duration,finished:true)
                let frame=try XCTUnwrap(InplayStadiumArt.scoreboard(stadium,in:scene.size)).frame
                let board=try XCTUnwrap(scene.childNode(withName:"//inplay-scoreboard"))
                // SpriteKit 좌표 저장의 서브픽셀 반올림만 허용한다.
                XCTAssertEqual(board.position.x,frame.midX,accuracy:0.001)
                XCTAssertEqual(board.position.y,scene.size.height-frame.midY,accuracy:0.001)
                if case .homeRun = replay {
                    let banner=try XCTUnwrap(scene.childNode(withName:"//home-run-banner"))
                    XCTAssertFalse(board.calculateAccumulatedFrame().intersects(banner.calculateAccumulatedFrame()),id)
                }
                let image=UIImage(cgImage:try XCTUnwrap(view.texture(from:scene)?.cgImage()))
                let attachment=XCTAttachment(image:image)
                attachment.name="V241 \(id) \(replay.eventID) actual SpriteKit";attachment.lifetime = .keepAlways;add(attachment)
                view.presentScene(nil)
            }
        }
    }
}
