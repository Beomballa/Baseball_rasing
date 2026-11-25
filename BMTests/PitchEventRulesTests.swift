import XCTest
import SwiftData
import SwiftUI
import SpriteKit
@testable import BM

@MainActor final class PitchEventRulesTests: XCTestCase {
    private func plain(_ role: PlayerRole = .batter, mask: Int = 0, outs: Int = 1) -> CareerMatch {
        var match = InplayIntegrationTests().makeMatch(role: role)
        match.playerRecords = nil; match.pitchLog = nil; match.half = 1
        match.outs = outs; match.runnerProfiles = (0..<3).map { index in
            mask & (1 << index) == 0 ? nil : FieldRunnerProfile(speed: 80, responsiblePitcher: MatchPitching.starterID(home: false), id: "R\(index + 1)")
        }
        match.bases = match.runnerProfiles!.map { $0 != nil }
        match.enablePitchEvents()
        return match
    }
    private func recordPitch(_ match: inout CareerMatch) {
        let home = match.half % 2 == 0
        match.pitching?.recordPitch(home: home)
        match.playerRecords?.recordPitch(home: home, relief: match.pitching?.change(home: home) != nil)
        if match.ownPitcherActive && !match.offense { match.line.pitches += 1 }
    }
    func testOrdinaryFoulCountAndThirdStrikeBuntAreDifferent() throws {
        for role in PlayerRole.allCases {
            for strikes in 0...2 {
                var match = plain(role, mask: 5); match.balls = 2; match.strikes = strikes
                let before = MatchPitchState(match), random = match.random
                match.pitchFoul(before: before, bunt: false, batter: role == .batter, pitcher: role == .pitcher, direct: true)
                XCTAssertEqual(match.strikes, min(2, strikes + 1)); XCTAssertEqual(match.balls, 2)
                XCTAssertEqual(match.outs, 1); XCTAssertEqual(match.runnerProfiles, before.runners)
                XCTAssertEqual(match.homeOrder + match.awayOrder, 0); XCTAssertEqual(match.random, random)
                try match.validatePitchEvents()
            }
            var bunt = plain(role); bunt.strikes = 2
            bunt.pitchFoul(before: MatchPitchState(bunt), bunt: true, batter: role == .batter, pitcher: role == .pitcher, direct: true)
            XCTAssertEqual(bunt.outs, 2); XCTAssertEqual(bunt.balls, 0); XCTAssertEqual(bunt.strikes, 0)
            XCTAssertEqual(bunt.pitchEvents?.events.last?.kind, .foulBunt)
        }
    }
    func testHitByPitchAllEightMasksPreserveRunnerIdentityAndOnlyForceContiguousBases() throws {
        for role in PlayerRole.allCases {
            for mask in 0..<8 {
                var match = plain(role, mask: mask)
                let before = MatchPitchState(match)
                match.pitchHitByPitch(before: before, batter: role == .batter, pitcher: role == .pitcher, direct: true)
                let event = try XCTUnwrap(match.pitchEvents?.events.last)
                XCTAssertEqual(event.kind, .hitByPitch); XCTAssertEqual(match.outs, 1)
                XCTAssertEqual(event.runs, mask == 7 ? 1 : 0)
                XCTAssertEqual(match.balls, 0); XCTAssertEqual(match.strikes, 0)
                var forced = 0
                while forced < 3 && before.runners[forced] != nil { forced += 1 }
                for base in 0..<3 where before.runners[base] != nil {
                    if base < forced {
                        if base < 2 { XCTAssertEqual(match.runnerProfiles?[base + 1]?.id, "R\(base + 1)") }
                    } else { XCTAssertEqual(match.runnerProfiles?[base]?.id, "R\(base + 1)") }
                }
                XCTAssertEqual(match.line.hits, 0); XCTAssertEqual(match.line.atBats, 0)
                if role == .batter { XCTAssertEqual(match.line.hitByPitch, 1); XCTAssertEqual(match.line.rbi, mask == 7 ? 1 : 0) }
                try match.validatePitchEvents()
            }
        }
    }
    func testThirdStrikeEligibilityUsesPitchTimeFirstBaseAndOuts() throws {
        for outs in 0...2 { for occupied in [false, true] {
            var match = plain(mask: occupied ? 1 : 0, outs: outs); match.strikes = 2
            let before = MatchPitchState(match)
            let observation = MatchPitchEventRules.observation(x: 0.5, y: 1.5, defense: 60)
            match.pitchUncaughtThird(before: before, observation: observation, batter: true, pitcher: false, direct: true)
            let event = try XCTUnwrap(match.pitchEvents?.events.last)
            XCTAssertEqual(event.play != nil, !occupied || outs == 2)
            XCTAssertEqual(match.line.strikeouts, 1)
            XCTAssertEqual(match.line.hits, 0); XCTAssertEqual(match.line.walks, 0)
            if occupied && outs < 2 {
                XCTAssertEqual(match.outs, outs + 1); XCTAssertEqual(match.runnerProfiles?[0]?.id, "R1")
                XCTAssertNil(event.credit)
            } else {
                let play = try XCTUnwrap(event.play)
                XCTAssertEqual(play.out, play.controlAt < play.runnerAt!)
                if !play.out { XCTAssertEqual(event.credit, .wild) }
                if play.out && outs == 2 { XCTAssertEqual(play.runs, 0); XCTAssertTrue(play.afterRunners.allSatisfy { $0 == nil }) }
            }
            try match.validatePitchEvents()
        }}
    }
    func testLooseClassificationUsesCatchabilityAndOnlyActualAdvanceEarnsCredit() throws {
        let wild = MatchPitchEventRules.observation(x: 1.2, y: 0.5, defense: 60)
        let passed = MatchPitchEventRules.observation(x: 0.5, y: 0.9, defense: 60)
        XCTAssertFalse(wild.bounced); XCTAssertEqual(wild.credit, .wild)
        XCTAssertTrue(passed.bounced); XCTAssertEqual(passed.credit, .passed)
        var empty = plain()
        empty.pitchLoose(before: MatchPitchState(empty), observation: wild, personal: true, direct: true, walked: false)
        XCTAssertNil(empty.pitchEvents?.events.last?.credit)
        var match = plain(mask: 2)
        let before = MatchPitchState(match)
        match.balls += 1
        match.pitchLoose(before: before, observation: wild, personal: true, direct: true, walked: false)
        let event = try XCTUnwrap(match.pitchEvents?.events.last)
        XCTAssertEqual(event.after.ids, [nil, nil, "R2"]); XCTAssertEqual(event.credit, .wild)
        XCTAssertEqual(match.homeOrder + match.awayOrder, 0); XCTAssertEqual(match.outs, 1)
        try match.validatePitchEvents()
    }
    func testNewGamesAutomaticBothRolesValidateAndOldNilRNGIsNotChangedByDisplay() throws {
        for role in PlayerRole.allCases {
            for seed in 1...16 {
                var match = InplayIntegrationTests().makeMatch(role: role); match.random = UInt64(seed)
                match.pitchLog = MatchPitchLog(); match.enablePitchEvents()
                try match.advance(.automatic)
                try match.playerRecords?.validate(match: match)
                try match.validatePitchEvents(); try match.pitchLog?.validate(match: match)
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let payload = try encoder.encode(match), random = match.random
                _ = match.pitchEvents?.events.map(\.label)
                XCTAssertEqual(payload, try encoder.encode(match)); XCTAssertEqual(match.random, random)
            }
        }
    }
    func testRepeatedDirectInputsPreservePersonalAndOfficialPitchCounters() throws {
        for role in PlayerRole.allCases {
          for home in [false, true] {
            for seed in 1...64 {
                var match = InplayIntegrationTests().makeMatch(role: role, isHome: home)
                match.scoutingPerformance = .tracked
                match.random = UInt64(seed); match.pitchLog = MatchPitchLog(); match.enablePitchEvents()
                for step in 0..<250 where !match.completed {
                    let before = match
                    let direct = role == .batter || match.ownPitcherActive
                    let input: MatchInput = direct ? (role == .batter ? .swing : .pitch) : .automatic
                    let control: ManualMatchInput? = direct ? (role == .batter
                        ? ManualMatchInput(x: 0.5, y: 0.5, timing: MatchDelivery.contactPhase)
                        : ManualMatchInput(release: 0.68)) : nil
                    try match.advance(input, pitchCode: role == .pitcher ? "four-seam" : nil, control: control)
                    var checking = "playerRecords"
                    do {
                        try match.playerRecords?.validate(match: match)
                        checking = "pitchEvents"; try match.validatePitchEvents()
                        checking = "pitching"; try match.validatePitching()
                        checking = "runnerManagement"; try match.validateRunnerManagement()
                        checking = "detailedField"; try match.validateDetailedField()
                        checking = "inningScores"; try match.inningScores?.validate(match: match)
                        checking = "pitchLog"; try match.pitchLog?.validate(match: match)
                        checking = "scouting"; try match.scoutingPerformance?.validate(line: match.line, role: role)
                    } catch {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                        for (label, value) in [("before", before), ("after", match)] {
                            let attachment = XCTAttachment(data: try encoder.encode(value), uniformTypeIdentifier: "public.json")
                            attachment.name = "P05-P07 direct ledger \(role.rawValue) home\(home) seed\(seed) step\(step) \(label)"
                            attachment.lifetime = .keepAlways; add(attachment)
                        }
                        XCTFail("개인/공식 투구 기록 불일치(\(checking)): \(role.rawValue), home \(home), seed \(seed), step \(step)")
                        throw error
                    }
                }
                XCTAssertTrue(match.completed, "\(role.rawValue) seed \(seed)")
            }
          }
        }
    }

    func testOfficialHBPAndLooseRunPreserveInheritedPitcherAndPlateTrace() throws {
        for role in PlayerRole.allCases {
            var match = try InplayIntegrationTests().seventhInning(role: role)
            match.enablePitchEvents(); match.strikes = 1
            let old = match.runnerProfiles![1]!
            let before = MatchPitchState(match)
            recordPitch(&match)
            // 이 장면의 9번은 NPC다. 역할과 현재 타석/등판 여부를 구분한다.
            match.pitchHitByPitch(before: before, batter: role == .batter && match.ownAtBat,
                pitcher: match.ownPitcherActive && !match.offense, direct: true)
            XCTAssertEqual(match.runnerProfiles?[1]?.id, old.id)
            try match.playerRecords?.validate(match: match); try match.validatePitchEvents()
            let looseBefore = MatchPitchState(match)
            recordPitch(&match); match.balls += 1
            match.pitchLoose(before: looseBefore, observation: MatchPitchEventRules.observation(x: 0.5, y: 1.5, defense: 60), personal: true, direct: true, walked: false)
            try match.playerRecords?.validate(match: match); try match.validatePitchEvents()
            InplayIntegrationTests().plate("삼진", in: &match)
            try match.playerRecords?.validate(match: match)
        }
    }
    func testReliefPitcherCanFoulBeforeHisFirstCompletedBattingRow() throws {
        for role in PlayerRole.allCases {
            var match = InplayIntegrationTests().makeMatch(role: role)
            match.half = 1
            let home = match.playerRecords!.home
            match.homeOrder = try XCTUnwrap(home.lineup.firstIndex(of: home.pitching[0].id))
            match.pitching?.homeChange = PitcherChange(half: 0, outs: 3, order: 3, pitches: 90, fatigue: 20,
                reason: "투구 수 한도", inheritedBases: [], outsAtExit: 0, runsAtExit: 0)
            match.enablePitchEvents()
            let before = MatchPitchState(match); recordPitch(&match)
            match.pitchFoul(before: before, bunt: false, batter: false, pitcher: role == .pitcher, direct: true)
            let event = try XCTUnwrap(match.pitchEvents?.events.last)
            XCTAssertEqual(event.batter, home.pitching[1].id)
            XCTAssertFalse(match.playerRecords!.home.batting.contains { $0.id == event.batter })
            XCTAssertEqual(match.homeOrder, before.order); XCTAssertEqual(match.strikes, 1)
            try match.validatePitchEvents()
            XCTAssertEqual(match, try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(match)))
        }
    }

    func testLoadedHitByPitchAfterReliefChargesTheOriginalRunnerPitcher() throws {
        for role in PlayerRole.allCases {
            var match = try InplayIntegrationTests().seventhInning(role: role); match.enablePitchEvents()
            let home = match.homeScore
            let starterRuns = match.playerRecords!.away.pitching[0].counts.runsAllowed
            for attempt in 0..<3 {
                let before = MatchPitchState(match)
                recordPitch(&match)
                match.pitchHitByPitch(before: before, batter: role == .batter && match.ownAtBat,
                    pitcher: match.ownPitcherActive && !match.offense, direct: true)
                if attempt == 0 { match.finishPitcherPlate(home: false, previousHalf: 13) }
            }
            XCTAssertNotNil(match.pitching?.awayChange)
            XCTAssertEqual(match.homeScore, home + 1)
            XCTAssertEqual(match.playerRecords!.away.pitching[0].counts.runsAllowed, starterRuns + 1)
            XCTAssertEqual(match.playerRecords!.away.pitching[1].counts.runsAllowed, 0)
            try match.playerRecords?.validate(match: match); try match.validatePitchEvents(); try match.validatePitching()
        }
    }

    private func control(_ match: CareerMatch, role: PlayerRole, kind: String = "hbp") -> ManualMatchInput {
        role == .batter ? ManualMatchInput() : ManualMatchInput(release: kind == "hbp" ? 0.60 : kind == "passed" ? ManualMatchRules.releaseCenter : 0.05)
    }
    private func findEvent(from ready: CareerMatch, kind: String, role: PlayerRole) throws -> (CareerMatch, CareerMatch, MatchPitchEvent) {
        for seed in 1...80_000 {
            var before = ready; before.random = UInt64(seed) &* 1_099_511_628_211
            let delivery = before.delivery(pitchCode: "four-seam")
            if kind == "hbp", role == .batter,
               !MatchPitchEventRules.hitByPitch(x: delivery.x, y: delivery.y, swinging: false, left: false) { continue }
            if kind == "third", role == .batter, !ManualMatchRules.isStrike(x: delivery.x, y: delivery.y) { continue }
            if kind == "passed", role == .pitcher, !(0.4...0.6).contains(delivery.x) { continue }
            if kind != "hbp" {
                var stream = before; _ = stream.roll(); _ = stream.roll()
                if role == .pitcher { _ = stream.roll() }
                if stream.roll() > 0.08 { continue }
            }
            var after = before
            try after.advance(role == .batter ? .watch : .pitch, pitchCode: "four-seam", control: control(before, role: role, kind: kind))
            guard let sequence = after.lastManual?.pitchEventSequence,
                  let event = after.pitchEvents?.events.first(where: { $0.sequence == sequence }) else { continue }
            let matched = kind == "hbp" ? event.kind == .hitByPitch
                : kind == "third" ? event.kind == .uncaughtThird && event.play != nil
                : event.kind == .loose && event.credit == (kind == "wild" ? .wild : .passed) && event.play != nil
            if matched { return (before, after, event) }
        }
        throw NSError(domain: "PitchEventQA", code: 1, userInfo: [NSLocalizedDescriptionKey: role.rawValue + " " + kind + "의 실제 입력 seed를 찾지 못했습니다."])
    }
    private func readyForEvent(_ initial: CareerMatch, kind: String, role: PlayerRole) throws -> CareerMatch {
        var ready = initial
        if kind == "wild" || kind == "passed" {
            var found: CareerMatch?
            for seed in 1...32 where found == nil {
                var sample = initial; sample.random = UInt64(seed) &* 1_099_511_628_211
                for _ in 0..<70 where !sample.completed && (role == .batter || sample.ownPitcherActive) {
                    if sample.runnerProfiles?.contains(where: { $0 != nil }) == true && (role == .batter ? sample.ownAtBat : !sample.offense) {
                        found = sample; break
                    }
                    if sample.canPrepareRunning { try sample.advanceRunning(); continue }
                    let input: MatchInput = role == .batter ? .swing : .pitch
                    try sample.advance(input, pitchCode: "four-seam", control: sample.automaticControl(input, pitchCode: "four-seam"))
                }
            }
            ready = try XCTUnwrap(found, "실제 자동 타석에서 주자가 있는 준비 상태가 필요합니다.")
        }
        if kind == "third" {
            while ready.strikes < 2 {
                var next: CareerMatch?
                for seed in 1...512 {
                    var before = ready; before.random = UInt64(seed) &* 1_099_511_628_211
                    var sample = before
                    try sample.advance(role == .batter ? .watch : .pitch, pitchCode: "four-seam",
                        control: role == .batter ? ManualMatchInput() : ManualMatchInput(release: ManualMatchRules.releaseCenter))
                    if sample.half == before.half && sample.homeOrder == before.homeOrder && sample.awayOrder == before.awayOrder
                        && sample.strikes == before.strikes + 1 && sample.lastManual?.pitchEventSequence == nil {
                        next = sample; break
                    }
                }
                ready = try XCTUnwrap(next)
            }
        }
        return ready
    }
    func testNewEventDiskFailureRetryResumeAndCompletionOnce() throws {
        enum Failure: Error { case injected }
        for role in PlayerRole.allCases {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pitch-atomic-" + UUID().uuidString + ".store")
            let saved: (Data, Int, Int, String) = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                var draft = PlayerDraft(); draft.name = "투구사건검증"; draft.role = role; draft.schoolID = "hs-ref-001"
                let player = try LegacyPlayerFixture.create(draft, schools: SchoolCatalog.load(), in: context)
                let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
                let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
                let (before, expected, _) = try findEvent(from: record.snapshot(), kind: "hbp", role: role)
                record.payload = try JSONEncoder().encode(before); try context.save()
                let payload = record.payload, revision = record.revision, fatigue = player.fatigue
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
                    input: role == .batter ? .watch : .pitch, pitchCode: "four-seam", control: control(before, role: role), in: context,
                    save: { _ in throw Failure.injected }))
                XCTAssertEqual(record.payload, payload); XCTAssertEqual(record.revision, revision); XCTAssertEqual(player.fatigue, fatigue)
                try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
                    input: role == .batter ? .watch : .pitch, pitchCode: "four-seam", control: control(before, role: role), in: context)
                let actual = try record.snapshot()
                XCTAssertEqual(actual.random, expected.random); XCTAssertEqual(actual.pitchEvents, expected.pitchEvents)
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: revision,
                    input: role == .batter ? .watch : .pitch, pitchCode: "four-seam", control: control(before, role: role), in: context))
                return (record.payload, record.revision, player.fatigue, player.gameDate)
            }
            try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
                let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record = try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first)
                XCTAssertEqual(record.payload, saved.0); XCTAssertEqual(record.revision, saved.1)
                XCTAssertEqual(player.fatigue, saved.2); XCTAssertEqual(player.gameDate, saved.3)
                let history = MatchGameHistory(match: try record.snapshot(), fixtureID: record.fixtureID, careerName: player.name, homeName: "홈", awayName: "원정")
                XCTAssertFalse(history.pitchEvents.isEmpty)
                var candidate=try record.snapshot()
                try candidate.advance(.automatic)
                let checks:[(String,() throws -> Void)] = [
                    ("pitching",{try candidate.validatePitching()}),
                    ("pitchEvents",{try candidate.validatePitchEvents()}),
                    ("running",{try candidate.validateRunning()}),
                    ("field",{try candidate.validateDetailedField()}),
                    ("records",{try candidate.playerRecords?.validate(match:candidate)}),
                    ("position",{try candidate.positionExperience?.validate(match:candidate)}),
                    ("ability",{try candidate.abilityExperience?.validate(match:candidate)})
                ]
                for (name,check) in checks {
                    do {try check()} catch {XCTFail("완료 후보 검증: \(role.rawValue) / \(name)");throw error}
                }
                try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context)
                let payload = record.payload, fatigue = player.fatigue, stateRevision = calendar.revision
                let reopened = try CareerMatchStore.start(player: player, state: calendar, in: context)
                XCTAssertEqual(reopened.id, record.id); XCTAssertEqual(reopened.payload, payload)
                XCTAssertEqual(player.fatigue, fatigue); XCTAssertEqual(calendar.revision, stateRevision)
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: calendar, record: record, revision: record.revision, input: .automatic, in: context))
            }
        }
    }
    func testPrepareNormalEntryFixturesForBothRoles() throws {
        var evidence: [[String: String]] = []
        for (index, kind) in ["hbp", "third", "wild", "passed"].enumerated() {
            for (roleIndex, role) in PlayerRole.allCases.enumerated() {
                let sessions = kind == "hbp" && role == .batter ? [index * 2 + roleIndex + 1, 9] : [index * 2 + roleIndex + 1]
              for sessionIndex in sessions {
                let session = String(format: "B005B007-2026-4124-8000-%012d", sessionIndex)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-career-" + session + ".store")
                // 고정 이름이 있는 전용 QA 세션만 정리하며 실제 사용자 저장에는 접근하지 않는다.
                for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                var draft = PlayerDraft(); draft.name = "투구사건검증"; draft.role = role; draft.schoolID = "hs-ref-001"
                let player = try CareerStore.create(draft, schools: SchoolCatalog.load(), in: context, currentLeagueRules: false)
                let calendar = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                try CalendarProgression.rest(player: player, state: calendar, revision: calendar.revision, in: context)
                let record = try CareerMatchStore.start(player: player, state: calendar, in: context)
                XCTAssertNotNil(try record.snapshot().abilityExperience)
                let ready = try readyForEvent(record.snapshot(), kind: kind, role: role)
                let (before, after, event) = try findEvent(from: ready, kind: kind, role: role)
                record.payload = try JSONEncoder().encode(before); try context.save(); _ = try record.snapshot()
                try after.playerRecords?.validate(match: after); try after.validatePitchEvents()
                XCTAssertEqual(event.before.ids, before.runnerProfiles?.map { $0?.id })
                evidence.append(["session": session, "role": role.rawValue, "kind": kind, "event": event.label,
                    "fixture": record.fixtureID, "before": "\(before.inningLabel) · \(before.outs)아웃 · \(event.before.occupied)",
                    "after": "\(event.after.outs)아웃 · \(event.after.occupied)", "seed": String(before.random)])
              }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "P05-P07 normal-input deterministic fixtures"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testWildAndPassedBallRunsHaveDifferentEarnedRunTreatmentWithoutErrorOrSteal() throws {
        let helper = InplayIntegrationTests()
        for credit in [MatchLoosePitchCredit.wild, .passed] {
            var match = helper.makeMatch(role: .pitcher)
            for _ in 0..<3 { helper.plate("삼진", in: &match) }
            match.enablePitchEvents()
            for _ in 0..<3 { helper.plate("볼넷", in: &match) }
            let before = MatchPitchState(match), scorer = match.runnerProfiles![2]!
            recordPitch(&match); match.balls += 1
            let observation = MatchPitchEventRules.observation(x: credit == .wild ? 1.2 : 0.5, y: 0.6, defense: 60, escape: 1)
            match.pitchLoose(before: before, observation: observation, personal: true, direct: true, walked: false)
            XCTAssertEqual(match.homeScore - before.home, 1)
            XCTAssertEqual(match.pitchEvents?.events.last?.credit, credit)
            let defense = try XCTUnwrap(match.playerRecords?.away)
            XCTAssertEqual(defense.pitching[0].counts.runsAllowed, 1)
            XCTAssertEqual(defense.pitching[0].counts.earnedRuns, credit == .wild ? 1 : 0)
            XCTAssertEqual(defense.pitching[0].counts.wildPitches, credit == .wild ? 1 : 0)
            XCTAssertEqual(defense.fielding?.first(where: { $0.position == "C" })?.passedBalls, credit == .passed ? 1 : 0)
            XCTAssertEqual(defense.fielding?.reduce(0, { $0 + $1.errors }), 0)
            XCTAssertEqual(match.playerRecords?.home.batting.first(where: { $0.id == scorer.id })?.counts.runs, 1)
            try match.playerRecords?.validate(match: match); try match.validatePitchEvents()
            for _ in 0..<3 { helper.plate("삼진", in: &match) }
            try match.playerRecords?.validate(match: match)
        }
    }
    func testLegacyNilEventsKeepRNGAndMissingCountersAfterJSONRoundTrip() throws {
        for role in PlayerRole.allCases {
            var original = InplayIntegrationTests().makeMatch(role: role)
            XCTAssertNil(original.pitchEvents); XCTAssertNil(original.line.hitByPitch); XCTAssertNil(original.line.wildPitches)
            var restored = try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(original))
            try original.advance(.automatic); try restored.advance(.automatic)
            XCTAssertEqual(original, restored); XCTAssertNil(restored.pitchEvents)
            XCTAssertNil(restored.playerRecords?.home.batting.first?.counts.hitByPitch)
            XCTAssertFalse(MatchResultSummary(match: restored, fatigueBefore: 20, fatigueAfter: 20).metrics.contains { $0.id == "hitByPitch" || $0.id == "wildPitches" })
        }
    }
    func testPitchEventNoticesSmallLargeTypeAndReadOnlyProjection() throws {
        var states: [MatchPitchEvent] = []
        var hbp = plain(mask: 5)
        hbp.pitchHitByPitch(before: MatchPitchState(hbp), batter: true, pitcher: false, direct: true)
        states.append(try XCTUnwrap(hbp.pitchEvents?.events.last))
        for credit in [MatchLoosePitchCredit.wild, .passed] {
            var match = plain(mask: 2)
            match.pitchLoose(before: MatchPitchState(match), observation: MatchPitchEventRules.observation(x: credit == .wild ? 1.2 : 0.5, y: 0.9, defense: 60, escape: 1), personal: true, direct: true, walked: false)
            states.append(try XCTUnwrap(match.pitchEvents?.events.last))
        }
        var third = plain(); third.strikes = 2
        third.pitchUncaughtThird(before: MatchPitchState(third), observation: MatchPitchEventRules.observation(x: 1.2, y: 0.6, defense: 60), batter: true, pitcher: false, direct: true)
        states.append(try XCTUnwrap(third.pitchEvents?.events.last))
        for event in states {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let source = try encoder.encode(event)
            for resolved in [false, true] {
                for (width, type): (CGFloat, DynamicTypeSize) in [(390, .large), (320, .large), (320, .accessibility5)] {
                    let view = NavigationStack {
                        ScrollView {
                            MatchPitchEventNotice(event: event, resolved: resolved, name: { _ in "검증 주자" }, openComparison: {})
                                .padding(16)
                        }.background(GameTheme.board).navigationTitle("투구 중 사건")
                    }.environment(\.dynamicTypeSize, type).preferredColorScheme(.dark)
                    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                    let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 844)
                    window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible()
                    defer { window.isHidden = true; previous?.makeKey() }
                    window.rootViewController?.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    var drawn = false
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    XCTAssertTrue(drawn)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "P05-P07 notice \(event.kind.rawValue) \(event.credit?.rawValue ?? "none") \(resolved) \(Int(width)) \(type)"
                    attachment.lifetime = .keepAlways; add(attachment)
                    if !resolved {
                        let text = MatchPitchEventPresentationState(event: event, resolved: false)
                        XCTAssertNil(text.confirmedCredit); XCTAssertNil(text.after)
                    }
                    XCTAssertEqual(try encoder.encode(event), source)
                }
            }
        }
    }

    func testNewPitchRulesUseSeparateScoutingReferenceEnvironment() throws {
        for role in PlayerRole.allCases {
            let position = role == .batter ? "CF" : "P", values = PlayerArchetype.initial(for: role).values
            var old = ScoutingReferenceSimulation.fixture(role: role, position: position, values: values, seed: 42, home: true,
                tracked: true, battedBallVersion: 1, npcFieldersVersion: 1, npcAttackVersion: 2)
            var new = ScoutingReferenceSimulation.fixture(role: role, position: position, values: values, seed: 42, home: true,
                tracked: true, battedBallVersion: 1, npcFieldersVersion: 1, npcAttackVersion: 2, pitchEventsVersion: 1)
            try ScoutingReferenceSimulation.run(&old, mode: .automatic); try ScoutingReferenceSimulation.run(&new, mode: .automatic)
            let oldEnvironment = try XCTUnwrap(old.scoutingEnvironment), environment = try XCTUnwrap(new.scoutingEnvironment)
            XCTAssertNotEqual(oldEnvironment, environment); XCTAssertTrue(environment.contains("-pitchEvents1-"))
            let reference = try XCTUnwrap(ScoutingReferenceSimulation.make(environment: environment, role: role, position: position))
            XCTAssertEqual(reference.environment, environment); try reference.validate()
            XCTAssertEqual(reference, try ScoutingReferenceSimulation.make(environment: environment, role: role, position: position))
        }
    }

    func testEventLedgerCannotDisagreeWithOfficialPitchOrCreditCounters() throws {
        var match = InplayIntegrationTests().makeMatch(); match.enablePitchEvents(); match.pitchLog = MatchPitchLog()
        let (before, after, _) = try findEvent(from: match, kind: "hbp", role: .batter)
        try after.validatePitchEvents()
        var changed = after
        let hitBatters = changed.playerRecords?.away.pitching[0].counts.hitBatters ?? 0
        changed.playerRecords?.away.pitching[0].counts.hitBatters = hitBatters + 1
        XCTAssertThrowsError(try changed.validatePitchEvents())
        changed = after; changed.pitchLog?.pitches.removeAll()
        XCTAssertThrowsError(try changed.validatePitchEvents(), "누락된 투구를 인덱싱하거나 결과를 추정하지 않는다.")
        changed = after
        let sequence = try XCTUnwrap(after.lastManual?.pitchEventSequence)
        changed.pitchLog?.pitches[sequence - 1].x = 0.5
        // 사구에는 별도 포구 관찰이 없으므로, 전후 카운트/투수 연결도 직접 대조한다.
        changed.pitchLog?.pitches[sequence - 1] = ObservedPitch(sequence: sequence, pitcherID: "unknown", home: true,
            code: "four-seam", speed: 140, balls: before.balls, strikes: before.strikes, x: 0.5, y: 0.5,
            inZone: true, source: "direct", outcome: "사구")
        XCTAssertThrowsError(try changed.validatePitchEvents())
    }

    func testNewSeasonCountersRejectNegativeAndOverflowWithoutPartialTotals() throws {
        let keys: [WritableKeyPath<MatchLine, Int?>] = [\.hitByPitch, \.hitBatters, \.wildPitches, \.passedBalls, \.strikeoutsWithoutOut]
        for key in keys {
            var input = MatchLine(); input[keyPath: key] = -1
            var totals = PersonalSeasonTotals(), original = totals
            XCTAssertThrowsError(try totals.add(input)); XCTAssertEqual(totals, original)
            totals.line[keyPath: key] = Int.max; original = totals
            input[keyPath: key] = 1
            XCTAssertThrowsError(try totals.add(input)); XCTAssertEqual(totals, original)
            var match = plain(); match.line[keyPath: key] = -1
            XCTAssertThrowsError(try match.validatePitchEvents())
            match.line[keyPath: key] = Int.max
            XCTAssertThrowsError(try match.validatePitchEvents())
        }
        var legacy = PersonalSeasonTotals(); try legacy.add(MatchLine())
        XCTAssertNil(legacy.line.hitByPitch); XCTAssertNil(legacy.line.wildPitches)
        var current = MatchLine(); current.hitByPitch = 1
        try legacy.add(current); try legacy.add(current)
        XCTAssertEqual(legacy.line.hitByPitch, 2)
    }

    func testPersonalPitchCountersCannotDisagreeWithTheSameOfficialPlayer() throws {
        for role in PlayerRole.allCases {
            var match = InplayIntegrationTests().makeMatch(role: role); match.enablePitchEvents()
            try match.validatePitchEvents()
            let keys: [WritableKeyPath<MatchLine, Int?>] = role == .batter ? [\.hitByPitch] : [\.hitBatters, \.wildPitches, \.strikeoutsWithoutOut]
            for key in keys {
                var changed = match; changed.line[keyPath: key] = (changed.line[keyPath: key] ?? 0) + 1
                XCTAssertThrowsError(try changed.validatePitchEvents())
            }
        }
    }

    func testOriginalCameraDoesNotShowMittPossessionForOrdinaryFoulOrFailedCatch() throws {
        var match = plain(mask: 2)
        match.pitchLoose(before: MatchPitchState(match), observation: MatchPitchEventRules.observation(x: 1.2, y: 0.6, defense: 60, escape: 1), personal: true, direct: true, walked: false)
        let event = try XCTUnwrap(match.pitchEvents?.events.last)
        for role in PlayerRole.allCases {
            for reduced in [false, true] {
                for foul in [false, true] {
                    let scene = BallparkScene(size: CGSize(width: 320, height: 320))
                    scene.configure(hand: "right", kit: 1, role: role)
                    var arrivals = 0
                    let onArrival: @MainActor () -> Void = {
                        arrivals += 1
                        XCTAssertTrue(scene.childNode(withName: "receivedBaseball")!.isHidden,
                            "일반 파울·포구 실패를 미트에 포구된 공으로 표시하지 않는다.")
                    }
                    let outcome = foul ? "파울" : "볼"
                    if role == .pitcher {
                        XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: 0.2, x: 1.2, y: 0.6,
                            outcome: outcome, preparedRelease: true, pitchEvent: foul ? nil : event, onArrival: onArrival))
                    } else {
                        XCTAssertTrue(scene.demonstrate(reduceMotion: reduced, flightDuration: 0.2))
                        scene.finishBat(action: foul ? "swing" : "watch", outcome: outcome, reduced: reduced,
                            pitchEvent: foul ? nil : event, onArrival: onArrival, completion: {})
                    }
                    let start = ProcessInfo.processInfo.systemUptime
                    for step in 0...30 { scene.advanceDelivery(at: start + Double(step) * 0.1) }
                    XCTAssertEqual(arrivals, 1)
                    scene.cancelDelivery()
                }
            }
        }
    }

    func testSavedPitchReplayUsesItsBeforeAndAfterRatherThanLaterMatchState() throws {
        var match = plain(mask: 2)
        let original = match
        match.pitchLoose(before: MatchPitchState(match), observation: MatchPitchEventRules.observation(x: 1.2, y: 0.6, defense: 60, escape: 1), personal: true, direct: true, walked: false)
        let event = try XCTUnwrap(match.pitchEvents?.events.last)
        var later = match; later.half = 13; later.homeScore = 8; later.awayScore = 7
        later.outs = 2; later.homeOrder = 32; later.awayOrder = 30; later.runnerProfiles = [nil, nil, nil]; later.bases = [false, false, false]
        let saved = later
        let before = event.before.displayMatch(later), after = event.after.displayMatch(later)
        XCTAssertEqual(before.half, original.half); XCTAssertEqual(before.homeScore, original.homeScore)
        XCTAssertEqual(before.runnerProfiles, original.runnerProfiles)
        XCTAssertEqual(after.half, event.after.half); XCTAssertEqual(after.runnerProfiles, event.after.runners)
        XCTAssertEqual(after.homeScore, event.after.home); XCTAssertEqual(after.awayScore, event.after.away)
        XCTAssertEqual(later, saved)
        XCTAssertNil(MatchPitchEventPresentationState(event: event, resolved: false).after)
    }

    func testWatchingWaitsForSavedCatchDecisionAtContact() throws {
        let scene = BallparkScene(size: CGSize(width: 320, height: 320))
        scene.configure(hand: "right", kit: 1, role: .batter)
        let timeline = MatchInputTimeline(windup: 0.1, duration: 1)
        XCTAssertTrue(scene.demonstrate(reduceMotion: false, inputTimeline: timeline))
        scene.awaitBatDecision(action: "watch", reduced: false)
        scene.advanceDelivery(at: timeline.contactAt + 0.01)
        XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: "receivedBaseball")).isHidden,
            "지켜보기 입력도 저장된 포구/실패 판정 전에 미트 소유로 표시하지 않는다.")
        scene.cancelDelivery()
    }

    func testFourthBallSettlesForcedAdvanceOnceBeforeLoosePitchAndStopsAtWalkOff() throws {
        for role in PlayerRole.allCases {
            var match = plain(role, mask: 5); match.balls = 3
            let before = MatchPitchState(match)
            match.endPlate("볼넷", batter: role == .batter, pitcher: role == .pitcher)
            let afterWalk = MatchPitchState(match)
            match.pitchLoose(before: before, observation: MatchPitchEventRules.observation(x: 1.2, y: 0.6, defense: 60, escape: 1),
                personal: true, direct: true, walked: true)
            let event = try XCTUnwrap(match.pitchEvents?.events.last)
            XCTAssertEqual(event.plateResult, "볼넷"); XCTAssertEqual(event.movementBefore, afterWalk)
            XCTAssertEqual(match.runnerProfiles?[1]?.id, "R1", "보장 진루한 주자는 같은 사건에서 다시 밀리지 않는다.")
            XCTAssertFalse(match.runnerProfiles?.contains(where: { $0?.id == "R3" }) == true)
            XCTAssertEqual(event.runs, 1); XCTAssertEqual(event.credit, .wild)
            XCTAssertEqual(match.homeOrder + match.awayOrder, 1); XCTAssertEqual(match.balls, 0); XCTAssertEqual(match.strikes, 0)
            if role == .batter { XCTAssertEqual(match.line.walks, 1); XCTAssertEqual(match.line.rbi, 0) }
            else { XCTAssertEqual(match.line.pitchingWalks, 1); XCTAssertEqual(match.line.wildPitches, 1) }
            try match.validatePitchEvents()
        }
        var end = plain(mask: 7); end.half = 17; end.homeScore = 2; end.awayScore = 2; end.balls = 3
        let before = MatchPitchState(end)
        end.endPlate("볼넷", batter: true, pitcher: false)
        XCTAssertTrue(end.completed); let once = end
        end.pitchLoose(before: before, observation: MatchPitchEventRules.observation(x: 1.2, y: 0.6, defense: 60, escape: 1),
            personal: true, direct: true, walked: true)
        XCTAssertEqual(end, once)
    }

    func testLoosePitchCatcherAndBallStayVisibleInOriginalInfieldProjection() throws {
        let match = plain(mask: 2)
        for x in [0.1, 0.5, 1.2] { for escape in [0.0, 0.5, 1.0] {
            let observation = MatchPitchEventRules.observation(x: x, y: 0.6, defense: 60, escape: escape)
            let play = MatchPitchEventRules.field(match: match, id: "pitch:1", kind: .loose,
                observation: observation, batter: match.pitchEventBatter)
            let oldDistance = hypot(4, observation.recoveryDistance - 3)
            XCTAssertEqual(play.landing.distance(to: DetailedFieldRules.positions[1]), oldDistance, accuracy: 0.000000001)
            for index in 0...20 {
                let time = play.pickupAt * Double(index) / 20
                for path in [play.fielders[1], play.ball] {
                    let point = InplayFieldProjection.point(FieldNode.sample(path, at: time), size: CGSize(width: 320, height: 480))
                    XCTAssertTrue((0...320).contains(point.x)); XCTAssertTrue((0...480).contains(point.y))
                }
            }
        }}
    }

}
