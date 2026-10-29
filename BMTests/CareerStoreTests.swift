import XCTest
import SwiftData
import SQLite3
import UIKit
@testable import BM

@MainActor final class CareerStoreTests: XCTestCase {
    func testV62EdgeObjectsKeep44PointTargetsInsideRoom() {
        for width in [320.0, 375, 390, 430] {
            let size = CGSize(width: width, height: width * 1660 / 948)
            for x in [0.08, 0.13, 0.5, 0.84, 0.94] {
                let p = ManagementPropPlacement(x: x, y: 0.54, width: 0.10, height: 0.06, kind: .roomSign)
                let rect = p.hitRect(in: size)
                XCTAssertGreaterThanOrEqual(rect.width, 44); XCTAssertGreaterThanOrEqual(rect.height, 44)
                XCTAssertGreaterThanOrEqual(rect.minX, 0); XCTAssertLessThanOrEqual(rect.maxX, size.width)
            }
        }
    }
    func testV60PropTargetsRemainSeparateAndAtLeast44Points() {
        let groups = [["clubhouse-game", "clubhouse-training", "clubhouse-career", "clubhouse-player", "clubhouse-rest", "facility-calendar"],
                      ["facility-abilities", "facility-profile", "facility-traits", "facility-records", "facility-positions"],
                      ["facility-observation", "facility-goals", "facility-observation-calendar", "facility-review", "facility-contracts"]]
        for width in [320.0, 375, 390, 430] {
            let height = width * 1660 / 948
            for ids in groups {
                let boxes = ids.map { id -> CGRect in
                    let p = ManagementPropPlacement.at(id), w = max(44, width * p.width), h = max(44, height * p.height)
                    return CGRect(x: width*p.x-w/2, y: height*p.y-h/2, width: w, height: h)
                }
                for i in boxes.indices {
                    XCTAssertGreaterThanOrEqual(boxes[i].width, 44); XCTAssertGreaterThanOrEqual(boxes[i].height, 44)
                    for j in boxes.indices where j > i {
                        let overlap = boxes[i].intersection(boxes[j])
                        XCTAssertTrue(overlap.isNull || overlap.width < 1 || overlap.height < 1, "\(width): \(ids[i])/\(ids[j])")
                    }
                }
            }
        }
    }
    func testV60PixelFontAndBundledLicenseAreAvailable() throws {
        XCTAssertNotNil(ManagementPixelFont.name)
        let data = try XCTUnwrap(NSDataAsset(name: "ManagementPixelLicenseV59")?.data)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("SIL OPEN FONT LICENSE"))
    }

    func testV50SchoolIdentitiesHaveDistinctRegionalNamesAndValidEmblems() throws {
        let schools = try SchoolCatalog.load()
        XCTAssertEqual(Set(schools.map(\.name)).count, 50)
        XCTAssertTrue(schools.allSatisfy { !$0.name.hasSuffix("체육학교") && $0.locality?.isEmpty == false })
        let emblems = try schools.map { try XCTUnwrap($0.emblem) }
        XCTAssertTrue(emblems.allSatisfy(\.isValid))
        XCTAssertEqual(Set(emblems.map(\.pixels)).count, 50)
        XCTAssertGreaterThanOrEqual(Set(emblems.map(\.style)).count, 15)
        XCTAssertGreaterThanOrEqual(Set(emblems.map(\.motif)).count, 25)
        XCTAssertGreaterThanOrEqual(emblems.filter { $0.glyph != nil }.count, 8)
        XCTAssertEqual(schools.first?.emblem?.glyph, "北")
        XCTAssertEqual(schools.first { $0.id == "hs-ref-023" }?.name, "남양주정산고")
        XCTAssertEqual(schools.filter(\.openingWorldChampion).count, 1)
    }

    func testV50ThreeFieldSchoolDecodeKeepsLegacyCompatibilityAndEmblemValidation() throws {
        let legacy = try JSONDecoder().decode(School.self, from: Data(#"{"id":"custom-school","region":"기존 지역","name":"기존 학교"}"#.utf8))
        XCTAssertNil(legacy.emblem)
        XCTAssertEqual(legacy.locationLabel, "기존 지역")
        let sample = try XCTUnwrap(SchoolCatalog.load().first?.emblem)
        let encoded = try JSONEncoder().encode(sample)
        XCTAssertEqual(try JSONDecoder().decode(SchoolEmblem.self, from: encoded), sample)
        XCTAssertFalse(SchoolEmblem(version: 1, style: "seal", motif: "hanzi", symbol: "북", glyph: "北", palette: sample.palette, pixels: ["0"]).isValid)
        XCTAssertFalse(SchoolEmblem(version: 1, style: "seal", motif: "hanzi", symbol: "북", glyph: "北", palette: [0], pixels: sample.pixels).isValid)
        XCTAssertFalse(SchoolEmblem(version: 1, style: "seal", motif: "hanzi", symbol: "북", glyph: "北", palette: sample.palette, pixels: Array(repeating: String(repeating: "z", count: 32), count: 32)).isValid)
    }

    func testV50SelectionQueriesIncludeSpecificLocalityWithoutChangingRegion() throws {
        let schools = try SchoolCatalog.load()
        let matches = SchoolCatalog.filtered(schools, query: "  종로  북악 ", region: "서울")
        XCTAssertEqual(matches.map(\.id), ["hs-ref-001"])
        XCTAssertEqual(matches.first?.name, "서울북악고")
        XCTAssertTrue(SchoolCatalog.filtered(schools, query: "북악", region: "경기").isEmpty)
    }

    func testV49FictionalSchoolsKeepIDsAndLegacyStoredIdentity() throws {
        let schools = try SchoolCatalog.load()
        XCTAssertEqual(Set(schools.map(\.name)).count, 50)
        XCTAssertEqual(schools.filter(\.openingWorldChampion).count, 1)
        XCTAssertTrue(schools.allSatisfy { (1...63).contains($0.crestNumber) })
        XCTAssertEqual(Set(schools.map(\.crestNumber)).count, 50)
        XCTAssertEqual(schools.first?.name, "서울북악고")
        XCTAssertFalse(schools.contains { $0.name == "경기고" })
        let db = try CareerStore.makeContainer(inMemory: true)
        let player = try CareerStore.create(draft(.batter), schools: schools, in: db.mainContext)
        player.schoolName = "경기고"
        try db.mainContext.save()
        let identity = player.id, pitches = player.pitches.map(\.code), date = player.gameDate
        XCTAssertEqual(player.displaySchoolName, "서울북악고")
        XCTAssertEqual(CareerTeamDirectory.name(player.schoolID), player.displaySchoolName)
        XCTAssertEqual(CareerTeamDirectory.name(player.schoolID, schools: schools), player.displaySchoolName)
        XCTAssertEqual(SchoolCatalog.displayName(id: "custom-school", fallback: "기존 사용자 학교"), "기존 사용자 학교")
        XCTAssertEqual(player.schoolName, "경기고")
        XCTAssertEqual(player.id, identity)
        XCTAssertEqual(player.pitches.map(\.code), pitches)
        XCTAssertEqual(player.gameDate, date)
        XCTAssertFalse(db.mainContext.hasChanges)
    }

    func testV49SchoolFiltersRetainOriginalIDsAndRespectRegionAndWhitespace() throws {
        let schools = try SchoolCatalog.load()
        XCTAssertEqual(SchoolCatalog.filtered(schools, query: "  \n ").map(\.id), schools.map(\.id))
        let selected = try XCTUnwrap(schools.first)
        let matches = SchoolCatalog.filtered(schools, query: "  " + selected.region + "  " + selected.name + " ", region: selected.region)
        XCTAssertTrue(matches.contains(selected))
        XCTAssertTrue(matches.allSatisfy { $0.region == selected.region })
        XCTAssertTrue(SchoolCatalog.filtered(schools, query: "no-such-school").isEmpty)
        XCTAssertTrue(SchoolCatalog.filtered(schools, query: selected.name, region: "no-such-region").isEmpty)
    }

    func testV49AbilitySummariesKeepAllPresetAndCustomBudgets() {
        for archetype in PlayerArchetype.allCases {
            var value = draft(archetype.role)
            value.archetype = archetype
            XCTAssertEqual(value.assignedAbilityPoints, value.abilityBudget)
            if value.role == .pitcher { XCTAssertEqual(value.pitchingAbilityPoints, 224) }
            let original = value.initialValues
            value.allocation = PlayerStatAllocation(role: value.role, base: original)
            value.isCustom = true
            XCTAssertEqual(value.initialValues, original)
            value.allocation?.adjust(value.role == .pitcher ? .velocity : .contact, by: -1)
            XCTAssertEqual(value.assignedAbilityPoints, value.abilityBudget - 1)
            XCTAssertEqual(value.initialAllocation.remaining, 1)
            value.allocation?.adjust(.mental, by: 1)
            XCTAssertEqual(value.assignedAbilityPoints, value.abilityBudget)
            XCTAssertTrue(value.initialAllocation.isValid)
        }
    }

    func testV49SaveFailureKeepsOtherCareerAndDraftThenRetryCreatesOnce() throws {
        enum Failure: Error { case saving }
        let schools = try SchoolCatalog.load(), db = try CareerStore.makeContainer(inMemory: true)
        let c = db.mainContext, existing = try CareerStore.create(draft(.pitcher), schools: schools, in: c)
        var value = draft(); value.isCustom = true
        value.allocation = PlayerStatAllocation(role: .batter, base: value.initialValues)
        let original = value.initialValues, appearance = value.appearance
        XCTAssertThrowsError(try CareerStore.create(value, schools: schools, in: c, save: { _ in throw Failure.saving }))
        XCTAssertEqual(value.initialValues, original); XCTAssertEqual(value.appearance, appearance)
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerPlayer>()), 1)
        XCTAssertEqual(try c.fetch(FetchDescriptor<CareerPlayer>()).first?.id, existing.id)
        let created = try CareerStore.create(value, schools: schools, in: c)
        XCTAssertNotEqual(existing.id, created.id)
        XCTAssertThrowsError(try CareerStore.create(value, schools: schools, in: c))
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<CareerPlayer>()), 2)
    }
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
        XCTAssertEqual(player.schoolName, schools.first { $0.id == "hs-ref-001" }?.name)
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
        for old in [CareerSchemaV1.self as any VersionedSchema.Type,CareerSchemaV12.self,CareerSchemaV14.self] {
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
                if old.versionIdentifier != CareerSchemaV1.versionIdentifier {
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


extension CareerStoreTests {
    func testV56LargeArchiveSynchronousBaseline() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("large.store"),db=try CareerStore.makeContainer(url:url)
        _ = try CareerStore.create(draft(),schools:SchoolCatalog.load(),in:db.mainContext)
        var sqlite:OpaquePointer?;defer {sqlite3_close(sqlite)}
        XCTAssertEqual(sqlite3_open(url.path,&sqlite),SQLITE_OK)
        let bytes=SaveArchiveStore.maximumBytes-512*1024
        XCTAssertEqual(sqlite3_exec(sqlite,"CREATE TABLE BM_QA_PADDING (payload BLOB); INSERT INTO BM_QA_PADDING VALUES (zeroblob(\(bytes)));",nil,nil,nil),SQLITE_OK)
        let start=ProcessInfo.processInfo.systemUptime
        let data=try SaveArchiveStore.export(container:db),exported=ProcessInfo.processInfo.systemUptime
        let archive=try JSONDecoder().decode(CareerSaveArchive.self,from:data)
        let candidate=try SaveArchiveStore.prepare(data,base:url),finished=ProcessInfo.processInfo.systemUptime
        XCTAssertLessThanOrEqual(archive.database.count,SaveArchiveStore.maximumBytes)
        XCTAssertGreaterThan(archive.database.count,63*1024*1024);XCTAssertEqual(candidate.players.count,1)
        print("V56_BASELINE dbBytes=\(archive.database.count) archiveBytes=\(data.count) exportMs=\((exported-start)*1000) decodeAndPrepareMs=\((finished-exported)*1000)")
    }
}

extension CareerStoreTests {
    func testV56RejectsSlotAndAbilityCorruptionBeforeSwitchAndRevalidatesPreview() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let base=dir.appendingPathComponent("original.store"),db=try CareerStore.makeContainer(url:base),c=db.mainContext
        let p=try CareerStore.create(draft(),schools:SchoolCatalog.load(),in:c)
        let archive=try SaveArchiveStore.export(container:db),session=SaveProtection(container:db,base:base)
        let prepared=try SaveArchiveStore.prepare(archive,base:base),pc=prepared.container.mainContext
        let slot=try XCTUnwrap(pc.fetch(FetchDescriptor<ActiveCareerSlot>()).first);slot.roleRaw="pitcher";try pc.save()
        XCTAssertThrowsError(try session.restore(prepared));XCTAssertTrue(session.container === db)
        XCTAssertEqual(try SaveArchiveStore.activeURL(base:base),base)
        let sourceSlot=try XCTUnwrap(c.fetch(FetchDescriptor<ActiveCareerSlot>()).first);c.delete(sourceSlot);try c.save()
        XCTAssertThrowsError(try SaveArchiveStore.prepare(SaveArchiveStore.export(container:db),base:base))
        c.insert(ActiveCareerSlot(role:p.role,playerID:p.id));try c.save()
        let abilities=try XCTUnwrap(PlayerAbilityStore.profile(playerID:p.id,in:c));abilities.mental=101;try c.save()
        XCTAssertThrowsError(try SaveArchiveStore.prepare(SaveArchiveStore.export(container:db),base:base))
        XCTAssertEqual(p.gameDate,"2026-04-01");XCTAssertEqual(try SaveArchiveStore.activeURL(base:base),base)
    }
    func testV56RecoveryCommitFailureRetryAndDuplicateRestoreIsNoOp() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let db=try CareerStore.makeContainer(url:dir.appendingPathComponent("source.store"))
        _ = try CareerStore.create(draft(),schools:SchoolCatalog.load(),in:db.mainContext)
        let base=dir.appendingPathComponent("broken.store"),bytes=Data("unreadable-original".utf8);try bytes.write(to:base)
        let prepared=try SaveArchiveStore.prepare(SaveArchiveStore.export(container:db),base:base)
        let fallback=try CareerStore.makeContainer(inMemory:true),session=SaveProtection(container:fallback,base:base,recoveryOnly:true)
        XCTAssertThrowsError(try session.restore(prepared,commit:{_,_ in throw SaveProtectionError.busy}))
        XCTAssertTrue(session.recoveryOnly);XCTAssertTrue(session.container === fallback)
        try session.restore(prepared);let generation=session.generation
        XCTAssertFalse(session.recoveryOnly);XCTAssertTrue(session.container === prepared.container)
        try session.restore(prepared,commit:{_,_ in XCTFail("duplicate pointer commit")})
        XCTAssertEqual(session.generation,generation);XCTAssertEqual(try Data(contentsOf:base),bytes)
    }
    func testV56BackgroundArchiveNearLimitAndImportFailureKeepOriginal() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("large.store"),db=try CareerStore.makeContainer(url:url)
        _ = try CareerStore.create(draft(.pitcher),schools:SchoolCatalog.load(),in:db.mainContext)
        var sqlite:OpaquePointer?;defer {sqlite3_close(sqlite)}
        XCTAssertEqual(sqlite3_open(url.path,&sqlite),SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(sqlite,"CREATE TABLE BM_QA_PADDING (payload BLOB); INSERT INTO BM_QA_PADDING VALUES (zeroblob(\(SaveArchiveStore.maximumBytes-512*1024)));",nil,nil,nil),SQLITE_OK)
        var ticks=0
        let ticker=Task { @MainActor in while !Task.isCancelled {ticks += 1;try? await Task.sleep(for:.milliseconds(10))} }
        defer {ticker.cancel()}
        let start=ProcessInfo.processInfo.systemUptime,data=try await SaveArchiveStore.exportAsync(container:db)
        let archive=try JSONDecoder().decode(CareerSaveArchive.self,from:data)
        XCTAssertGreaterThan(archive.database.count,63*1024*1024);XCTAssertLessThanOrEqual(archive.database.count,SaveArchiveStore.maximumBytes)
        let file=dir.appendingPathComponent("roundtrip.bmbackup");try data.write(to:file)
        let prepared=try await SaveArchiveStore.prepareFileAsync(file,base:url)
        XCTAssertEqual(prepared.players.count,1);XCTAssertGreaterThan(ticks,1)
        let session=SaveProtection(container:db,base:url)
        try session.restore(prepared);XCTAssertFalse(session.recoveryOnly)
        let broken=dir.appendingPathComponent("bad.bmbackup");try Data("broken".utf8).write(to:broken)
        do {_ = try await SaveArchiveStore.prepareFileAsync(broken,base:url);XCTFail("invalid file accepted")} catch {}
        XCTAssertTrue(session.container === prepared.container)
        let oversized=dir.appendingPathComponent("oversized.bmbackup");_ = FileManager.default.createFile(atPath:oversized.path,contents:nil)
        let handle=try FileHandle(forWritingTo:oversized);try handle.truncate(atOffset:UInt64(SaveArchiveStore.maximumBytes*2+1));try handle.close()
        do {_ = try await SaveArchiveStore.prepareFileAsync(oversized,base:url);XCTFail("oversized input accepted")} catch {}
        print("V56_ASYNC dbBytes=\(archive.database.count) archiveBytes=\(data.count) elapsedMs=\((ProcessInfo.processInfo.systemUptime-start)*1000) mainActorTicks=\(ticks)")
    }
    private func v56PayloadDigests(_ url:URL) throws -> [String:[String]] {
        var db:OpaquePointer?,query:OpaquePointer?;defer {sqlite3_finalize(query);sqlite3_close(db)}
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READONLY,nil)==SQLITE_OK else {throw SaveProtectionError.invalid}
        var tables:[String]=[]
        guard sqlite3_prepare_v2(db,"SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%'",-1,&query,nil)==SQLITE_OK else {throw SaveProtectionError.invalid}
        while sqlite3_step(query)==SQLITE_ROW {if let t=sqlite3_column_text(query,0) {tables.append(String(cString:t))}}
        sqlite3_finalize(query);query=nil
        var result:[String:[String]]=[:]
        for table in tables {
            let name=table.replacingOccurrences(of:"\"",with:"\"\"")
            if sqlite3_prepare_v2(db,"SELECT ZPAYLOAD FROM \"\(name)\"",-1,&query,nil)==SQLITE_OK {
                var values:[String]=[]
                while sqlite3_step(query)==SQLITE_ROW {if let raw=sqlite3_column_blob(query,0) {values.append(SaveArchiveStore.hash(Data(bytes:raw,count:Int(sqlite3_column_bytes(query,0)))))}}
                result[table]=values.sorted()
            }
            sqlite3_finalize(query);query=nil
        }
        return result
    }
    func testV56ExistingSavedCopiesReopenKeepingOriginalPayloadsAndFrozenReports() throws {
        let source=FileManager.default.temporaryDirectory.appendingPathComponent("v56-existing-copies")
        guard FileManager.default.fileExists(atPath:source.path) else {throw XCTSkip("Explicit existing-copy input not provided")}
        for name in ["normal","qa"] {
            let input=source.appendingPathComponent(name+".store"),original=try Data(contentsOf:input)
            let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:dir)}
            let url=dir.appendingPathComponent("working.store");try SaveArchiveStore.snapshot(from:input,to:url)
            let before=try v56PayloadDigests(url)
            try autoreleasepool {let db=try CareerStore.makeContainer(url:url);_ = try SaveArchiveStore.validate(db)}
            let first=try v56PayloadDigests(url)
            for (table,hashes) in before {XCTAssertTrue(hashes.allSatisfy {first[table]?.contains($0)==true},"original payload changed: "+table)}
            try autoreleasepool {let db=try CareerStore.makeContainer(url:url);_ = try SaveArchiveStore.validate(db)}
            XCTAssertEqual(try v56PayloadDigests(url),first);XCTAssertEqual(try Data(contentsOf:input),original)
            print("V56_EXISTING_COPY kind=\(name) payloadTables=\(before.count) preserved=true")
        }
    }
}
