import XCTest
import SwiftData
@testable import BM

@MainActor final class CareerStoreTests: XCTestCase {
    private func draft(_ role: PlayerRole = .batter) -> PlayerDraft {
        var value = PlayerDraft()
        value.name = role == .batter ? "김타자" : "이투수"
        value.jerseyNumber = "27"; value.role = role; value.schoolID = "hs-ref-001"
        value.position = .shortstop; value.throwingHand = .left
        value.appearance = PlayerAppearance(skin: 4, hair: 2, kit: 3, hairStyle: 2, expression: 1)
        return value
    }

    func testV44ArchiveRoundTripKeepsBothPendingRecordsReportsAndOneReward() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let base=dir.appendingPathComponent("original.store")
        let db=try CareerStore.makeContainer(url:base), c=db.mainContext
        let batter=try CareerStore.create(draft(.batter),schools:SchoolCatalog.load(),in:c)
        let pitcher=try CareerStore.create(draft(.pitcher),schools:SchoolCatalog.load(),in:c)
        let states=try c.fetch(FetchDescriptor<CareerCalendarState>())
        let bs=try XCTUnwrap(states.first {$0.playerID == batter.id}), ps=try XCTUnwrap(states.first {$0.playerID == pitcher.id})
        let training=try CareerTrainingStore.start(player:batter,state:bs,in:c)
        for _ in 0..<2 {let round=try training.snapshot(),target=round.targets[round.scores.count]
            try CareerTrainingStore.attempt(player:batter,state:bs,record:training,revision:training.revision,input:TrainingInput(x:target.x,y:target.y,timing:MatchDelivery.contactPhase),in:c)}
        try CalendarProgression.rest(player:pitcher,state:ps,revision:ps.revision,in:c)
        let game=try CareerMatchStore.start(player:pitcher,state:ps,in:c)
        try CareerMatchStore.advance(player:pitcher,state:ps,record:game,revision:game.revision,input:.pitch,pitchCode:pitcher.pitches[0].code,in:c)
        if try c.fetchCount(FetchDescriptor<CareerScoutingReport>()) == 0 {
            c.insert(try CareerScoutingReport(ScoutingObservationStore.currentObservation(player:batter,calendar:bs,in:c))); try c.save()
        }
        let reports=try c.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload)
        XCTAssertFalse(reports.isEmpty)
        let originalTraining=training.payload,originalGame=game.payload
        let archive=try SaveArchiveStore.export(container:db)
        XCTAssertEqual(training.payload,originalTraining);XCTAssertEqual(game.payload,originalGame)
        let candidate=try SaveArchiveStore.prepare(archive,base:base)
        let session=SaveProtection(container:db,base:base)
        enum Failure:Error {case write}
        XCTAssertThrowsError(try session.restore(candidate,commit:{_,_ in throw Failure.write}))
        XCTAssertTrue(session.container === db);XCTAssertEqual(try SaveArchiveStore.activeURL(base:base),base)
        try session.restore(candidate)
        XCTAssertEqual(try SaveArchiveStore.activeURL(base:base),candidate.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath:base.path))
        let rc=candidate.container.mainContext
        XCTAssertEqual(try rc.fetch(FetchDescriptor<CareerTrainingRecord>()).first?.payload,originalTraining)
        XCTAssertEqual(try rc.fetch(FetchDescriptor<CareerMatchRecord>()).first?.payload,originalGame)
        XCTAssertEqual(try rc.fetch(FetchDescriptor<CareerScoutingReport>()).map(\.payload),reports)
        let restored=try XCTUnwrap(rc.fetch(FetchDescriptor<CareerPlayer>()).first {$0.id == pitcher.id})
        let state=try XCTUnwrap(rc.fetch(FetchDescriptor<CareerCalendarState>()).first {$0.playerID == pitcher.id})
        let row=try CareerMatchStore.start(player:restored,state:state,in:rc)
        try CareerMatchStore.advance(player:restored,state:state,record:row,revision:row.revision,input:.automatic,in:rc)
        let result=row.payload,fatigue=restored.fatigue
        XCTAssertThrowsError(try CareerMatchStore.advance(player:restored,state:state,record:row,revision:row.revision,input:.automatic,in:rc))
        XCTAssertEqual(row.payload,result);XCTAssertEqual(restored.fatigue,fatigue)
    }
    func testV44RecoveryFromUnreadableOriginalKeepsOriginalBytesAndReopensGeneration() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let source=try CareerStore.makeContainer(url:dir.appendingPathComponent("source.store"))
        let player=try CareerStore.create(draft(),schools:SchoolCatalog.load(),in:source.mainContext)
        let archive=try SaveArchiveStore.export(container:source)
        let base=dir.appendingPathComponent("broken.store"),broken=Data("broken-original".utf8)
        try broken.write(to:base)
        let candidate=try SaveArchiveStore.prepare(archive,base:base)
        let session=SaveProtection(container:try CareerStore.makeContainer(inMemory:true),base:base,recoveryOnly:true)
        try session.restore(candidate)
        XCTAssertEqual(try Data(contentsOf:base),broken)
        let reopened=try CareerStore.makeContainer(url:SaveArchiveStore.activeURL(base:base))
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CareerPlayer>()).first?.id,player.id)
    }

    func testV44CorruptAndUnsupportedArchiveNeverSelectOrEditOriginal() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let base=dir.appendingPathComponent("original.store"),db=try CareerStore.makeContainer(url:dir.appendingPathComponent("original.store"))
        let p=try CareerStore.create(draft(),schools:SchoolCatalog.load(),in:db.mainContext)
        let bytes=try SaveArchiveStore.export(container:db),a=try JSONDecoder().decode(CareerSaveArchive.self,from:bytes)
        for bad in [CareerSaveArchive(format:99,schema:15,created:a.created,digest:a.digest,database:a.database),CareerSaveArchive(format:1,schema:15,created:a.created,digest:"bad",database:a.database),CareerSaveArchive(format:1,schema:15,created:a.created,digest:SaveArchiveStore.hash(Data("not sqlite".utf8)),database:Data("not sqlite".utf8))] {
            XCTAssertThrowsError(try SaveArchiveStore.prepare(JSONEncoder().encode(bad),base:base))
            XCTAssertEqual(try SaveArchiveStore.activeURL(base:base),base)
            XCTAssertEqual(p.name,"김타자");XCTAssertFalse(db.mainContext.hasChanges)
        }
        p.name="unsaved"
        XCTAssertThrowsError(try SaveArchiveStore.export(container:db))
        db.mainContext.rollback()
    }

    func testBundledSchoolsRetainFiftyUniqueIDs() throws {
        let schools = try SchoolCatalog.load()
        XCTAssertEqual(schools.count, 50)
        XCTAssertEqual(schools.first?.id, "hs-ref-001")
        XCTAssertFalse(schools.contains(where: { $0.name == "부천고" || $0.name == "화순고" }))
    }

    func testInvalidDraftsNeverInsert() throws {
        let schools = try SchoolCatalog.load()
        let container = try CareerStore.makeContainer(inMemory: true)
        for invalid in ["", "   ", "1234567890123", "이름\n다음"] {
            var value = draft(); value.name = invalid
            XCTAssertThrowsError(try CareerStore.create(value, schools: schools, in: container.mainContext))
        }
        for invalid in ["-1", "100", "1.0", "A", ""] {
            var value = draft(); value.jerseyNumber = invalid
            XCTAssertThrowsError(try CareerStore.create(value, schools: schools, in: container.mainContext))
        }
        var invalid = draft(); invalid.schoolID = "unknown"
        XCTAssertThrowsError(try CareerStore.create(invalid, schools: schools, in: container.mainContext))
        invalid = draft(); invalid.appearance.skin = 6
        XCTAssertThrowsError(try CareerStore.create(invalid, schools: schools, in: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CareerPlayer>()), 0)
    }

    func testRoleIsolationAndDuplicateRejection() throws {
        let schools = try SchoolCatalog.load()
        let container = try CareerStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let batter = try CareerStore.create(draft(), schools: schools, in: context)
        let pitcher = try CareerStore.create(draft(.pitcher), schools: schools, in: context)
        XCTAssertNotEqual(batter.id, pitcher.id)
        XCTAssertEqual(batter.positionRaw, "SS")
        XCTAssertEqual(pitcher.throwingHandRaw, "left")
        XCTAssertTrue(batter.pitches.isEmpty)
        XCTAssertEqual(pitcher.pitches.count, 4)
        XCTAssertEqual(Set(pitcher.pitches.map(\.code)).count, 4)
        XCTAssertThrowsError(try CareerStore.create(draft(), schools: schools, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerPlayer>()), 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testDiskSaveReopensWithIdentityAppearanceAndMastery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let schools = try SchoolCatalog.load()
        let id: UUID = try autoreleasepool {
            let container = try CareerStore.makeContainer(url: url)
            let saved = try CareerStore.create(draft(.pitcher), schools: schools, in: container.mainContext)
            return saved.id
        }
        let reopened = try CareerStore.makeContainer(url: url)
        let players = try reopened.mainContext.fetch(FetchDescriptor<CareerPlayer>())
        let player = try XCTUnwrap(players.first)
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(player.id, id)
        XCTAssertEqual(player.name, "이투수")
        XCTAssertEqual(player.jerseyNumber, 27)
        XCTAssertEqual(player.schoolID, "hs-ref-001")
        XCTAssertEqual(player.schoolName, "경기고")
        XCTAssertEqual(player.appearance, draft(.pitcher).appearance)
        XCTAssertEqual(player.throwingHandRaw, "left")
        XCTAssertEqual(player.startAge, 16)
        XCTAssertEqual(player.gameDate, "2026-04-01")
        XCTAssertEqual(player.fatigue, 52)
        XCTAssertEqual(player.pitches.sorted { $0.order < $1.order }.map(\.mastery), [62,55,42,35])
        XCTAssertFalse(reopened.mainContext.autosaveEnabled)
    }
}

// Preserve explicit demo fixtures for old training/match regression and migration tests.
@MainActor enum LegacyPlayerFixture {
    static func create(_ draft: PlayerDraft, schools: [School], in context: ModelContext) throws -> CareerPlayer {
        let player = CareerPlayer(draft: draft, school: try XCTUnwrap(schools.first { $0.id == draft.schoolID }))
        context.insert(player)
        context.insert(CareerCalendarState(player: player, schools: schools, legacySave: false))
        try context.save()
        if context.container.schema.entities.contains(where: { $0.name == "PlayerPositions" }) {
            try PlayerPositionStore.addMissing(in: context)
        }
        return player
    }
}

extension CareerStoreTests {
    func testV31RealV1AndV14FilesMigrateKeepingIdentityMasteryAndPendingBytes() throws {
        for old in [CareerSchemaV1.self as any VersionedSchema.Type,CareerSchemaV14.self] {
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:folder)}
            let url=folder.appendingPathComponent("old.store"),schools=try SchoolCatalog.load()
            let original=try autoreleasepool { () throws -> (UUID,Data?,Data?) in
                let schema=Schema(versionedSchema:old),db=try ModelContainer(for:schema,configurations:[ModelConfiguration("Career",schema:schema,url:url,cloudKitDatabase:.none)])
                db.mainContext.autosaveEnabled=false
                let historical=CareerSchemaV1.Player(draft:draft(.pitcher),school:schools[0])
                historical.contact=68.1234;historical.pitches[0].mastery=84.25
                db.mainContext.insert(historical)
                var trainingBytes:Data?,matchBytes:Data?
                if old.versionIdentifier == CareerSchemaV14.versionIdentifier {
                    // Construct dependent records with an uninserted player of the same identity.
                    let projection=CareerPlayer(draft:draft(.pitcher),school:schools[0]);projection.id=historical.id
                    let state=CareerCalendarState(player:projection,schools:schools,legacySave:false)
                    db.mainContext.insert(state)
                    let memory=try CareerStore.makeContainer(inMemory:true),c=memory.mainContext
                    let source=try LegacyPlayerFixture.create(draft(.pitcher),schools:schools,in:c)
                    let sourceState=try XCTUnwrap(c.fetch(FetchDescriptor<CareerCalendarState>()).first)
                    let row=try CareerTrainingStore.start(player:source,state:sourceState,pitchCode:"four-seam",in:c)
                    try CareerTrainingStore.attempt(player:source,state:sourceState,record:row,revision:row.revision,input:TrainingInput(release:0.68),in:c)
                    let bytes=String(decoding:row.payload,as:UTF8.self).replacingOccurrences(of:source.id.uuidString,with:historical.id.uuidString)
                    let training=try JSONDecoder().decode(CareerTraining.self,from:Data(bytes.utf8))
                    let copy=try CareerTrainingRecord(training);copy.revision=3;db.mainContext.insert(copy);trainingBytes=copy.payload
                    let fixture=try XCTUnwrap(state.fixtures(for:projection,year:2026).first)
                    var match=CareerMatch(random:42,isHome:true,role:"pitcher",appearance:true,contact:65,power:75,discipline:60,mastery:["four-seam":72])
                    try match.advance(.automatic)
                    let saved=try CareerMatchRecord(player:projection,fixture:fixture,match:match)
                    saved.completed=true;saved.revision=17;db.mainContext.insert(saved);matchBytes=saved.payload
                }
                try db.mainContext.save();return (historical.id,trainingBytes,matchBytes)
            }
            let db=try CareerStore.makeContainer(url:url),c=db.mainContext
            let p=try XCTUnwrap(c.fetch(FetchDescriptor<CareerPlayer>()).first)
            XCTAssertEqual(p.id,original.0);XCTAssertEqual(p.contact,68.1234);XCTAssertEqual(p.pitches.first {$0.order == 0}?.mastery,84.25)
            XCTAssertNil(p.lifecycleData);XCTAssertEqual(try c.fetchCount(FetchDescriptor<ActiveCareerSlot>()),1)
            if let bytes=original.1 {let training=try XCTUnwrap(c.fetch(FetchDescriptor<CareerTrainingRecord>()).first);XCTAssertEqual(training.payload,bytes);XCTAssertEqual(training.revision,3);XCTAssertEqual(try training.snapshot().scores.count,1)}
            if let bytes=original.2 {XCTAssertEqual(try c.fetch(FetchDescriptor<CareerMatchRecord>()).first?.payload,bytes)}
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains {$0.hasPrefix("before-v15-")})
        }
    }
}
