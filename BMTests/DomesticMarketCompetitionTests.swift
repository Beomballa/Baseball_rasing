import XCTest
import SwiftData
@testable import BM

@MainActor final class DomesticMarketCompetitionTests: XCTestCase {
    private func fixture(_ role: PlayerRole = .batter, url: URL? = nil, sample: Bool = false) throws -> (ModelContainer, CareerPlayer, CareerCalendarState) {
        let db = try url.map { try CareerStore.makeContainer(url: $0) } ?? CareerStore.makeContainer(inMemory: true)
        let context = db.mainContext
        var draft = PlayerDraft(); draft.name = "경쟁도회귀"; draft.role = role; draft.schoolID = "hs-ref-001"
        let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        for date in ["2029-04-01", "2030-04-01"] {
            player.gameDate = date
            try CareerPathStore.synchronize(player: player, calendar: calendar, in: context)
        }
        if sample {
            let fixtures = try calendar.fixtures(for: player, year: 2028).filter { $0.isAppearance(for: role) }
            for (index, game) in fixtures.prefix(role == .batter ? 12 : 6).enumerated() {
                player.gameDate = game.date.description
                var match = ScoutingReferenceSimulation.fixture(role: role, position: role == .batter ? player.positionRaw : "P",
                    values: PlayerArchetype.initial(for: role).values, seed: UInt64(700 + index), home: game.homeID == player.schoolID, tracked: true)
                try ScoutingReferenceSimulation.run(&match, mode: .automatic)
                let record = try CareerMatchRecord(player: player, fixture: game, match: match)
                record.completed = true; record.rulesVersion = "native-match-v2"; context.insert(record)
            }
            player.contact = 80; player.power = 80; player.discipline = 80; player.defense = 80
            let abilities = try XCTUnwrap(PlayerAbilityStore.profile(playerID: player.id, in: context))
            try abilities.grow(.mental, to: 80)
            if role == .pitcher {
                for kind in [TrainingKind.velocity, .control, .stuff, .stamina] { try abilities.grow(kind, to: 80) }
                for pitch in player.pitches { pitch.mastery = 80 }
            }
        }
        player.gameDate = "2030-04-01"; try context.save()
        return (db, player, calendar)
    }

    private func selection(rule: String, player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext,
                           april: DomesticSelection? = nil) throws -> ContractEvaluationSnapshot {
        let observation = try ScoutingObservationStore.currentObservation(player: player, calendar: calendar, in: context)
        let window = try XCTUnwrap(ContractEvaluationWindow.containing(GameDate(player.gameDate)))
        let seed = player.id.uuidString + "/\(window.year)"
        let seats = DomesticSelection.market(seed: seed, expanded: rule != "domestic-selection-v1")
        let candidates = rule == "domestic-selection-v3" ? DomesticSelection.competitiveCandidates(seed: seed, month: window.month) : DomesticSelection.candidates(seed: seed, month: window.month)
        let carried = window.month == 7 ? DomesticSelection.carried(seed: seed, april: april, rule: rule) : []
        let sample = try ContractEvaluationStore.graduationSample(player: player, calendar: calendar, observation: observation, in: context)
        let reason = "검증된 졸업 표본40PA/15IP 부족 또는 유효기간 경과 · 동일 형식 인증 평가전 자료 필요"
        let result = DomesticSelection.simulate(observation: observation, seats: window.month == 7 ? seats.filter { $0.route == .rookie } : seats,
            candidates: candidates, carried: carried, sample: sample, sampleReason: reason)
        let value = DomesticSelection(rule: rule, seed: seed, priorMarket: window.month == 4 ? "연간 신규 시장" : april == nil ? "고정 가상4월 NPC 충원 이월" : "4월 고정 NPC 충원 이월 · 미수락 내 예약 해제",
            sample: sample, sampleReason: reason, seats: seats, candidates: candidates, carried: carried, picks: result.picks, results: result.results)
        let history = try XCTUnwrap(CareerPathStore.record(player: player, calendar: calendar, in: context)?.snapshot(player: player, calendar: calendar))
        return ContractEvaluationSnapshot(version: 2, rule: "contracts-window-v1", window: window, evaluatedDate: player.gameDate,
            calendarRevision: calendar.revision, affiliation: history.current, routes: window.routes(age: observation.age, affiliation: history.current.stage),
            observation: observation, pending: ["회귀 검증 고정 자료"], selection: value)
    }

    private func changed(_ value: DomesticSelection, _ edit: (inout [String: Any]) throws -> Void) throws -> DomesticSelection {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        try edit(&object)
        return try JSONDecoder().decode(DomesticSelection.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testV163CandidateDensityAndRoleQuotasKeepLegacyPrefixAndEncoding() throws {
        for (month, total, quotas) in [(4, 34, [9, 8, 8, 9]), (7, 14, [4, 3, 3, 4])] {
            let seed = "a01/fixed/2030"
            let old = DomesticSelection.candidates(seed: seed, month: month)
            let new = DomesticSelection.competitiveCandidates(seed: seed, month: month)
            XCTAssertEqual(old.count, month == 4 ? 20 : 8); XCTAssertEqual(new.count, total)
            XCTAssertEqual(Array(new.prefix(old.count)), old)
            XCTAssertEqual(DomesticSelection.roles.map { role in new.filter { $0.role == role }.count }, quotas)
            XCTAssertTrue(old.allSatisfy { $0.route == nil })
            XCTAssertTrue(new.dropFirst(old.count).allSatisfy { $0.route == .rookie })
            XCTAssertEqual(Set(new.map(\.id)).count, new.count)
            for candidate in new {
                let bits = DomesticSelection.hash(seed + "/" + candidate.id)
                XCTAssertEqual(candidate.h, Double(46 + bits % 17))
                XCTAssertEqual(candidate.p, Double(Int((bits / 17) % 7) - 3) * 0.5)
            }
            let bytes = try JSONEncoder().encode(old)
            let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
            XCTAssertTrue(objects.allSatisfy { $0["route"] == nil })
            XCTAssertEqual(try JSONDecoder().decode([DomesticSelectionCandidate].self, from: bytes), old)
            XCTAssertEqual(new, DomesticSelection.competitiveCandidates(seed: seed, month: month))
        }
    }

    func testV163RookieOnlyAdditionKeepsEntireCollegePicksAndResultsForBothRoles() throws {
        for role in PlayerRole.allCases {
            let (db, player, calendar) = try fixture(role, sample: true)
            let old = try XCTUnwrap(selection(rule: "domestic-selection-v2", player: player, calendar: calendar, in: db.mainContext).selection)
            let new = try XCTUnwrap(selection(rule: "domestic-selection-v3", player: player, calendar: calendar, in: db.mainContext).selection)
            XCTAssertNotNil(old.sample); XCTAssertEqual(new.sample, old.sample)
            let collegeIDs = Set(old.seats.filter { $0.route == .college }.map(\.id))
            XCTAssertEqual(new.picks.filter { collegeIDs.contains($0.seatID) }, old.picks.filter { collegeIDs.contains($0.seatID) })
            XCTAssertEqual(new.results.filter { $0.route == .college }, old.results.filter { $0.route == .college })
            XCTAssertEqual(new.results.filter { $0.route == .college && $0.selected }.count, 1)
        }
    }

    func testV163AllMarketRulesValidateAndLegacyNilRouteDoesNotChangeStoredJSON() throws {
        let (db, player, calendar) = try fixture()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for rule in ["domestic-selection-v1", "domestic-selection-v2", "domestic-selection-v3"] {
            let snapshot = try selection(rule: rule, player: player, calendar: calendar, in: db.mainContext)
            XCTAssertNoThrow(try snapshot.validate(player: player, calendar: calendar))
            let bytes = try encoder.encode(snapshot)
            let decoded = try JSONDecoder().decode(ContractEvaluationSnapshot.self, from: bytes)
            XCTAssertEqual(try encoder.encode(decoded), bytes)
            XCTAssertEqual(decoded.version, 2, "Outer JSON 3 remains the renewal contract.")
            if rule != "domestic-selection-v3" {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let body = try XCTUnwrap(object["selection"] as? [String: Any])
                let candidates = try XCTUnwrap(body["candidates"] as? [[String: Any]])
                XCTAssertEqual(candidates.count, 20); XCTAssertTrue(candidates.allSatisfy { $0["route"] == nil })
            }
        }
    }

    func testV163StoredAprilV1AndV2KeepTheirJulyRuleAndOriginalBytes() throws {
        for rule in ["domestic-selection-v1", "domestic-selection-v2"] {
            let (db, player, calendar) = try fixture()
            let context = db.mainContext
            let old = try selection(rule: rule, player: player, calendar: calendar, in: context)
            let row = try CareerContractEvaluation(playerID: player.id, snapshot: old)
            context.insert(row); try context.save()
            let bytes = row.payload
            XCTAssertFalse(try ContractEvaluationStore.captureIfDue(player: player, calendar: calendar, in: context))
            player.gameDate = "2030-07-01"; try context.save()
            try ContractEvaluationStore.registerCurrent(in: context)
            let july = try XCTUnwrap(ContractEvaluationStore.records(player: player, calendar: calendar, in: context).first?.snapshot(player: player, calendar: calendar).selection)
            XCTAssertEqual(july.rule, rule); XCTAssertEqual(july.candidates.count, 8)
            XCTAssertEqual(july.carried, old.selection?.picks.filter { $0.seatID.hasPrefix("rookie/") && $0.candidateID.hasPrefix("npc/") })
            XCTAssertFalse(july.carried.contains { $0.candidateID.hasPrefix("player/") })
            XCTAssertEqual(row.payload, bytes)
        }
    }

    func testV163AprilAndJulyUseOneRuleAndCarryOnlyActualNPCPicks() throws {
        let (db, player, calendar) = try fixture(.pitcher, sample: true)
        let context = db.mainContext
        try ContractEvaluationStore.registerCurrent(in: context)
        let april = try XCTUnwrap(ContractEvaluationStore.records(player: player, calendar: calendar, in: context).first)
        let snapshot = try april.snapshot(player: player, calendar: calendar), a = try XCTUnwrap(snapshot.selection), bytes = april.payload
        XCTAssertEqual(a.rule, "domestic-selection-v3"); XCTAssertEqual(snapshot.version, 2)
        player.gameDate = "2030-07-01"; try context.save(); try ContractEvaluationStore.registerCurrent(in: context)
        let july = try XCTUnwrap(ContractEvaluationStore.records(player: player, calendar: calendar, in: context).first?.snapshot(player: player, calendar: calendar).selection)
        XCTAssertEqual(july.rule, a.rule); XCTAssertEqual(july.candidates.count, 14)
        XCTAssertEqual(july.carried, a.picks.filter { $0.seatID.hasPrefix("rookie/") && $0.candidateID.hasPrefix("npc/") })
        XCTAssertFalse(july.carried.contains { $0.candidateID.hasPrefix("player/") })
        XCTAssertEqual(Set(july.picks.map(\.seatID)).count, july.picks.count)
        XCTAssertEqual(Set(july.picks.map(\.candidateID)).count, july.picks.count)
        for club in Set(july.seats.filter { $0.route == .rookie }.map(\.name)) {
            let seats = july.seats.filter { $0.route == .rookie && $0.name == club }
            let picks = july.picks.filter { pick in seats.contains { $0.id == pick.seatID } }
            XCTAssertLessThanOrEqual(picks.count, 3)
            XCTAssertLessThanOrEqual(picks.reduce(0) { $0 + $1.cost }, seats[0].budget)
        }
        XCTAssertEqual(april.payload, bytes)
    }

    func testV163MissingAprilUsesV3VirtualNPCMarketWithoutInventingPlayerSelection() throws {
        let (db, player, calendar) = try fixture()
        let context = db.mainContext
        player.gameDate = "2030-07-01"; try context.save(); try ContractEvaluationStore.registerCurrent(in: context)
        let records = try ContractEvaluationStore.records(player: player, calendar: calendar, in: context)
        XCTAssertEqual(records.count, 1)
        let july = try XCTUnwrap(records.first?.snapshot(player: player, calendar: calendar).selection)
        XCTAssertEqual(july.rule, "domestic-selection-v3")
        XCTAssertEqual(july.carried, DomesticSelection.carried(seed: july.seed, april: nil, rule: "domestic-selection-v3"))
        XCTAssertFalse(july.carried.contains { $0.candidateID.hasPrefix("player/") })
        XCTAssertTrue(july.results.allSatisfy { !$0.selected && $0.reasons.contains { $0.contains("표본") } })
    }

    func testV163ValidationRejectsRouteCandidateRuleAndAnnualRuleTampering() throws {
        let (db, player, calendar) = try fixture()
        let context = db.mainContext
        let snapshot = try selection(rule: "domestic-selection-v3", player: player, calendar: calendar, in: context)
        let value = try XCTUnwrap(snapshot.selection)
        let changedRoute = try changed(value) { object in
            var candidates = try XCTUnwrap(object["candidates"] as? [[String: Any]])
            candidates[candidates.count - 1]["route"] = "college"; object["candidates"] = candidates
        }
        let changedAbility = try changed(value) { object in
            var candidates = try XCTUnwrap(object["candidates"] as? [[String: Any]])
            candidates[candidates.count - 1]["h"] = 99; object["candidates"] = candidates
        }
        let crossedRule = try changed(value) { $0["rule"] = "domestic-selection-v2" }
        for invalid in [changedRoute, changedAbility, crossedRule] {
            XCTAssertThrowsError(try invalid.validate(observation: snapshot.observation, window: snapshot.window))
        }
        XCTAssertThrowsError(try changed(value) { object in
            var candidates = try XCTUnwrap(object["candidates"] as? [[String: Any]])
            candidates[0]["route"] = "overseas"; object["candidates"] = candidates
        })
        let oldApril = try selection(rule: "domestic-selection-v2", player: player, calendar: calendar, in: context)
        context.insert(try CareerContractEvaluation(playerID: player.id, snapshot: oldApril)); try context.save()
        player.gameDate = "2030-07-01"; try context.save()
        let mismatched = try selection(rule: "domestic-selection-v3", player: player, calendar: calendar, in: context, april: oldApril.selection)
        context.insert(try CareerContractEvaluation(playerID: player.id, snapshot: mismatched)); try context.save()
        XCTAssertThrowsError(try ContractEvaluationStore.records(player: player, calendar: calendar, in: context))
    }

    func testV163IssuanceRollbackRetryAndReopenPreserveEvaluationAndOfferBytes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BM-A01-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("qa.store")
        var evaluationBytes = Data(), offerBytes = Data()
        do {
            let (db, player, calendar) = try fixture(.batter, url: url, sample: true)
            let context = db.mainContext
            XCTAssertThrowsError(try ContractEvaluationStore.registerCurrent(in: context, save: { _ in throw MatchError.invalidRecord }))
            XCTAssertTrue(try ContractEvaluationStore.records(player: player, calendar: calendar, in: context).isEmpty)
            XCTAssertTrue(try ContractOfferStore.records(player: player, calendar: calendar, in: context).isEmpty)
            try ContractEvaluationStore.registerCurrent(in: context)
            let evaluation = try XCTUnwrap(ContractEvaluationStore.records(player: player, calendar: calendar, in: context).first)
            let offer = try XCTUnwrap(ContractOfferStore.records(player: player, calendar: calendar, in: context).first)
            let packet = try offer.snapshot(evaluation: evaluation, player: player, calendar: calendar)
            XCTAssertEqual(Set(packet.offers.map(\.route)), Set([.rookie, .college]))
            evaluationBytes = evaluation.payload; offerBytes = offer.payload
            player.contact = 99; try context.save(); try ContractEvaluationStore.registerCurrent(in: context)
            XCTAssertEqual(evaluation.payload, evaluationBytes); XCTAssertEqual(offer.payload, offerBytes)
            XCTAssertFalse(context.hasChanges)
        }
        let db = try CareerStore.makeContainer(url: url), context = db.mainContext
        let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
        let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
        try ContractEvaluationStore.registerCurrent(in: context)
        let evaluations = try ContractEvaluationStore.records(player: player, calendar: calendar, in: context)
        let offers = try ContractOfferStore.records(player: player, calendar: calendar, in: context)
        XCTAssertEqual(evaluations.count, 1); XCTAssertEqual(offers.count, 1)
        XCTAssertEqual(evaluations.first?.payload, evaluationBytes); XCTAssertEqual(offers.first?.payload, offerBytes)
        XCTAssertFalse(context.hasChanges)
    }

    func testV163AnnualValidationRejectsV3AprilDowngradeButKeepsLegacyMixedRules() throws {
        for julyRule in ["domestic-selection-v1", "domestic-selection-v2"] {
            let (db, player, calendar) = try fixture()
            let context = db.mainContext
            let april = try selection(rule: "domestic-selection-v3", player: player, calendar: calendar, in: context)
            XCTAssertNoThrow(try april.validate(player: player, calendar: calendar))
            context.insert(try CareerContractEvaluation(playerID: player.id, snapshot: april)); try context.save()
            player.gameDate = "2030-07-01"; try context.save()
            // A six-team snapshot can replay its own virtual April, but cannot replace a stored v3 April.
            let july = try selection(rule: julyRule, player: player, calendar: calendar, in: context,
                april: julyRule == "domestic-selection-v2" ? april.selection : nil)
            XCTAssertNoThrow(try july.validate(player: player, calendar: calendar))
            context.insert(try CareerContractEvaluation(playerID: player.id, snapshot: july)); try context.save()
            XCTAssertThrowsError(try ContractEvaluationStore.records(player: player, calendar: calendar, in: context))
        }
        let (db, player, calendar) = try fixture()
        let context = db.mainContext
        let april = try selection(rule: "domestic-selection-v1", player: player, calendar: calendar, in: context)
        context.insert(try CareerContractEvaluation(playerID: player.id, snapshot: april)); try context.save()
        player.gameDate = "2030-07-01"; try context.save()
        let july = try selection(rule: "domestic-selection-v2", player: player, calendar: calendar, in: context, april: april.selection)
        XCTAssertNoThrow(try july.validate(player: player, calendar: calendar))
        context.insert(try CareerContractEvaluation(playerID: player.id, snapshot: july)); try context.save()
        XCTAssertEqual(try ContractEvaluationStore.records(player: player, calendar: calendar, in: context).count, 2,
            "Do not impose the new annual rule guard on historical v1/v2 combinations.")
    }
}
