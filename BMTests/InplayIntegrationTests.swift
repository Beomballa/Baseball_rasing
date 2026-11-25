import XCTest
import SwiftData
import SpriteKit
@testable import BM

@MainActor final class InplayIntegrationTests: XCTestCase {
    func makeMatch(role: PlayerRole = .batter, homeID: String = "hs-ref-001", awayID: String = "hs-ref-002",
                   careerID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000205")!, fixtureID: String = "integration-205", isHome: Bool? = nil) -> CareerMatch {
        var match = CareerMatch(random: 91, isHome: isHome ?? (role == .batter), role: role.rawValue, appearance: true,
            contact: 70, power: 60, discipline: 60, mastery: ["four-seam": 70])
        match.fieldStats = MatchFieldStats(speed: 60, defense: 60, arm: 60, position: role == .batter ? "SS" : "P")
        match.controlVersion = 2; match.battedBallVersion = 1
        match.detailedFieldVersion = 5; match.fieldPlays = []; match.runnerProfiles = [nil, nil, nil]
        match.pitching = MatchPitching(); match.inningScores = MatchInningScores()
        match.npcFielders = MatchNPCFielders.make(year: 2026, competition: "highschool", homeID: homeID, awayID: awayID)
        match.npcAttack = MatchNPCAttack.makeComplete(roster: match.npcFielders!)
        match.prepareRunnerManagement()
        // 검증용으로 고정한 합법 타순. 9번은 야수이며 내 타자는 기존처럼 1번이다.
        var home = match.npcLineup(home: true); home.swapAt(7, 8)
        match.battingOrder = MatchBattingOrder(home: home, away: match.npcLineup(home: false))
        match.playerRecords = MatchPlayerRecords.make(match: match, careerID: careerID, fixtureID: fixtureID,
            trackEarnedRuns: true, trackDecisions: true, trackFielding: true, trackPlateTrace: true)
        return match
    }

    func plate(_ result: String, in match: inout CareerMatch, play: MatchDetailedPlay? = nil) {
        let defendingHome = match.half % 2 == 0, battingHome = !defendingHome
        let count = result == "볼넷" ? 4 : result == "삼진" ? 3 : 1
        for _ in 0..<count {
            match.pitching?.recordPitch(home: defendingHome)
            match.playerRecords?.recordPitch(home: defendingHome, relief: match.pitching?.change(home: defendingHome) != nil)
            if match.ownPitcherActive && !match.offense { match.line.pitches += 1 }
        }
        let ownBatter = match.role == "batter" && match.ownAtBat
        let ownPitcher = match.ownPitcherActive && !match.offense
        let profile = FieldRunnerProfile(speed: ownBatter ? 60 : match.npcBatterSpeed, own: ownBatter,
            responsiblePitcher: match.pitching?.activeID(home: defendingHome),
            id: match.playerRecords!.homeTeam(batting: match.half).batterID(order: battingHome ? match.homeOrder : match.awayOrder,
                relief: match.pitching?.change(home: battingHome) != nil))
        if let play { match.fieldPlays?.append(play) }
        match.completePlate(initial: play == nil ? result : "안타", result: play == nil ? result : play!.hitBases == 2 ? "2루타" : play!.hitBases == 1 ? "안타" : "범타",
            batter: ownBatter, pitcher: ownPitcher, newRunner: profile, detailed: play, cleanForEarned: play)
    }

    func advanceToSeventh(_ match: inout CareerMatch) {
        while match.half < 13 {
            if match.half < 2 { for _ in 0..<5 { plate("볼넷", in: &match) } }
            for _ in 0..<3 { plate("삼진", in: &match) }
        }
    }

    func fieldPlay(_ match: CareerMatch, distance: Double, flight: Double, direction: Double) -> MatchDetailedPlay {
        let profile = FieldRunnerProfile(speed: match.role == "batter" && match.ownAtBat ? 60 : match.npcBatterSpeed,
            own: match.role == "batter" && match.ownAtBat, responsiblePitcher: match.pitching?.activeID(home: false),
            id: match.playerRecords!.home.batterID(order: match.homeOrder, relief: false))
        let ball = MatchBattedBall(kind: .ground, quality: 0.9, contact: 70, power: 60, speed: 32,
                                  angle: 0, direction: direction, distance: distance, flight: flight)
        var play = DetailedFieldRules.resolve(half: match.half, order: match.homeOrder, landing: ball.landing, flight: flight,
            runners: match.runnerProfiles!, batter: profile, outs: match.outs, stats: match.fieldStats, defending: !match.offense,
            ownBatter: profile.own, doublePlayEnabled: true, groundBall: true, relayEnabled: true, npc: match.npcDefenders)
        play.version = 5; play.battedBall = ball; play.ball = ball.nodes + play.ball.filter { $0.at > ball.flight }
        return play
    }

    func testTraceDoesNotChangeExistingPitchResultsOrLegacyJSON() throws {
        for role in PlayerRole.allCases {
            for seed in 1...8 {
                var a = makeMatch(role: role); a.random = UInt64(seed)
                a.runnerManagement = nil; a.battingOrder = nil; a.playerRecords = MatchPlayerRecords.make(match: a,
                    careerID: a.playerRecords!.careerID, fixtureID: "integration-205", trackEarnedRuns: true, trackDecisions: true)
                var b = a; b.playerRecords?.plateTrace = []
                try a.advance(.automatic); try b.advance(.automatic)
                XCTAssertEqual(a.random, b.random); XCTAssertEqual(a.line, b.line)
                XCTAssertEqual(a.fieldPlays, b.fieldPlays); XCTAssertEqual(a.homeScore, b.homeScore); XCTAssertEqual(a.awayScore, b.awayScore)
                try b.playerRecords?.validate(match: b)
                let restored = try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(b))
                XCTAssertEqual(restored, b)
                XCTAssertNil(a.playerRecords?.plateTrace)
            }
        }
    }

    func seventhInning(role: PlayerRole, initial: CareerMatch? = nil) throws -> CareerMatch {
        var match = initial ?? makeMatch(role: role); advanceToSeventh(&match)
        let first = fieldPlay(match, distance: 90, flight: 5, direction: -25)
        XCTAssertEqual(first.hitBases, 2)
        plate("2루타", in: &match, play: first)
        plate("삼진", in: &match); plate("삼진", in: &match)
        // 기존 한도 판단이 9번 볼넷 직후 발동하도록 투구 수만 고정한다.
        let stamina = role == .pitcher ? 60 : match.npcAttack!.away.starter.profile!.stamina
        let pitches = MatchPitching.limit(stamina: stamina) - 1
        match.pitching?.awayPitches = pitches
        match.playerRecords?.away.pitching[0].counts.pitches = pitches
        if role == .pitcher { match.line.pitches = pitches }
        XCTAssertEqual(match.half, 13); XCTAssertEqual(match.outs, 2)
        XCTAssertEqual(match.homeOrder, 26); XCTAssertEqual(match.bases, [false, true, false])
        try validate(match)
        return match
    }

    func validate(_ match: CareerMatch) throws {
        try match.playerRecords!.validate(match: match)
        try match.validatePitching(); try match.validateDetailedField()
        try match.inningScores!.validate(match: match)
    }

    func testSeventhWalkPinchRunnerReliefDoublePreservesIdentityAndResponsibility() throws {
        for role in PlayerRole.allCases {
            var match = try seventhInning(role: role)
            let original = try XCTUnwrap(match.playerRecords!.runners[1])
            let beforeRuns = match.playerRecords!.away.pitching[0].counts.runsAllowed
            let beforeEarned = try XCTUnwrap(match.playerRecords!.away.pitching[0].counts.earnedRuns)
            let score = match.homeScore
            // 실제 공 입력으로 9번 볼넷을 완료한다. 교체는 step의 공통 확정 경로에서 실행된다.
            match.balls = 3
            match.strikes = 0
            match.random = role == .batter ? 2 : 1
            if role == .pitcher {
                // 바깥 코스의 실제 제구 결과를 사용한다. 결과를 직접 주입하지 않는다.
                try match.advance(.pitch, pitchCode: "four-seam", control: .init(release: 0, pitchTarget: .init(x: 0, y: 0)))
            } else {
                match.settle()
            }
            XCTAssertEqual(match.homeOrder, 27)
            let change = try XCTUnwrap(match.runnerManagement?.changes.first)
            XCTAssertEqual(change.base, 1); XCTAssertEqual(change.slot, 9)
            XCTAssertEqual(match.playerRecords!.runners[1], original)
            XCTAssertEqual(match.playerRecords!.runners[0], change.replacement)
            XCTAssertEqual(match.runnerProfiles![0]?.responsiblePitcher, "away-starter")
            XCTAssertNotNil(match.pitching?.awayChange)
            let token = match.playerRecords!.earned?.runners[0]?.token
            XCTAssertNotNil(token)
            try validate(match)
            let data = try JSONEncoder().encode(match)
            match = try JSONDecoder().decode(CareerMatch.self, from: data)
            let once = match; match.applyCoachRunnerChange(); XCTAssertEqual(match, once)
            let play = fieldPlay(match, distance: 90, flight: 5, direction: -25)
            XCTAssertEqual(play.hitBases, 2); XCTAssertEqual(play.runs, 1); XCTAssertEqual(play.outsAdded, 0)
            plate("2루타", in: &match, play: play)
            XCTAssertEqual(match.homeScore, score + 1); XCTAssertEqual(match.awayScore, 2)
            XCTAssertEqual(match.outs, 2); XCTAssertEqual(match.half, 13)
            XCTAssertEqual(match.bases, [false, true, true]); XCTAssertEqual(match.homeOrder, 28)
            XCTAssertEqual(match.playerRecords!.runners[2], change.replacement)
            XCTAssertEqual(match.playerRecords!.home.batterID(order: 35, relief: false), change.replacement)
            XCTAssertEqual(match.playerRecords!.away.pitching[0].counts.runsAllowed, beforeRuns + 1)
            XCTAssertEqual(match.playerRecords!.away.pitching[0].counts.earnedRuns, beforeEarned + 1)
            XCTAssertEqual(match.playerRecords!.away.pitching[1].counts.runsAllowed, 0)
            XCTAssertEqual(match.playerRecords!.plateTrace!.last!.scoring.map(\.id), [original])
            XCTAssertEqual(match.playerRecords!.plateTrace!.last!.scoring.map(\.pitcher), [match.playerRecords!.away.pitching[0].id])
            XCTAssertEqual(match.playerRecords!.earned?.runners[2]?.token, token)
            try validate(match)
            XCTAssertEqual(match, try JSONDecoder().decode(CareerMatch.self, from: JSONEncoder().encode(match)))
        }
    }

    func testNewMatchesAutomaticCompletionValidatesBothRolesAndPreservesReserveSnapshot() throws {
        var actualChanges = 0
        for role in PlayerRole.allCases {
            for seed in 1...24 {
                var match = makeMatch(role: role); match.random = UInt64(seed)
                let reserve = match.runnerManagement!.home
                try match.advance(.automatic)
                try validate(match)
                XCTAssertEqual(match.runnerManagement!.home, reserve)
                XCTAssertLessThanOrEqual(match.runnerManagement!.changes.count, 2)
                actualChanges += match.runnerManagement!.changes.count
                XCTAssertEqual(match.playerRecords!.plateTrace!.count, match.homeOrder + match.awayOrder)
                let completed = match; match.prepareRunnerManagement(); XCTAssertEqual(match, completed)
            }
        }
        XCTAssertGreaterThan(actualChanges, 0, "전체 자동 진행에서도 실제 코치 기용 경로를 지나야 한다.")
    }

    func testCoachExcludesOwnPlayerPitcherEarlyInningAndAlreadyUsedReserve() throws {
        var match = try seventhInning(role: .batter)
        let beforeWalk = match; match.applyCoachRunnerChange(); XCTAssertEqual(match, beforeWalk)
        plate("볼넷", in: &match)
        let before = match
        var early = match; early.half = 11; early.applyCoachRunnerChange()
        XCTAssertEqual(early.runnerManagement!.changes, [])
        var own = match; own.runnerProfiles![0]?.own = true; own.applyCoachRunnerChange()
        XCTAssertEqual(own.runnerManagement!.changes, [])
        var wide = match; wide.homeScore += 3; wide.applyCoachRunnerChange()
        XCTAssertEqual(wide.runnerManagement!.changes, [])
        var faster = match
        let entrant = faster.runnerProfiles![0]!
        faster.runnerProfiles![0] = FieldRunnerProfile(speed: 100, traits: entrant.traits, own: entrant.own,
            responsiblePitcher: entrant.responsiblePitcher, id: entrant.id)
        faster.applyCoachRunnerChange()
        XCTAssertEqual(faster.runnerManagement!.changes, [])
        match.applyCoachRunnerChange()
        XCTAssertEqual(match.runnerManagement!.changes.count, 1)
        XCTAssertEqual(match.random, before.random)
        let once = match; match.applyCoachRunnerChange(); XCTAssertEqual(match, once)
        let reserve = match.runnerManagement!.home
        let change = match.runnerManagement!.changes[0]
        var laterBat = match; laterBat.homeOrder = 35
        XCTAssertEqual(laterBat.npcBatter?.id, reserve.id)
        XCTAssertEqual(laterBat.npcBatterSpeed, reserve.speed)
        var defense = match; defense.half = 14
        let fielder = defense.npcDefenders?.first { $0.position == change.position }
        XCTAssertEqual(fielder?.id, reserve.id); XCTAssertEqual(fielder?.arm, reserve.arm)
        // 투수 타순은 현재 단일 구원투수 모델을 유지한다.
        var pitcher = before
        let source = pitcher.playerRecords!.home.batting.first { $0.position == "P" }!.id
        pitcher.playerRecords!.runners[0] = source
        pitcher.replaceRunner(base: 1, reserve: pitcher.runnerManagement!.home)
        XCTAssertEqual(pitcher.runnerManagement!.changes, [])
        XCTAssertEqual(before.runnerProfiles![1], match.runnerProfiles![1])
    }

    func testPinchRunnerPreservesUnearnedTokenAndRejectsCorruptChange() throws {
        var match = try seventhInning(role: .batter)
        plate("볼넷", in: &match)
        match.playerRecords!.earned!.runners[0]!.unearned = true
        let token = match.playerRecords!.earned!.runners[0]!.token
        match.applyCoachRunnerChange()
        XCTAssertEqual(match.playerRecords!.earned!.runners[0]!.token, token)
        XCTAssertTrue(match.playerRecords!.earned!.runners[0]!.unearned)
        XCTAssertEqual(match.runnerProfiles![0]?.id, match.playerRecords!.runners[0])
        var corrupt = match; corrupt.runnerManagement!.changes.append(match.runnerManagement!.changes[0])
        XCTAssertThrowsError(try corrupt.validateRunnerManagement())
        corrupt = match; corrupt.playerRecords!.runners[0] = corrupt.playerRecords!.runners[1]
        XCTAssertThrowsError(try corrupt.playerRecords!.validate(match: corrupt))
        corrupt = match; corrupt.playerRecords!.plateTrace!.removeLast()
        XCTAssertThrowsError(try corrupt.playerRecords!.validate(match: corrupt))
    }

    func testDiskResumeSaveFailureRetryAndCompletionApplyOnlyOnce() throws {
        enum Failure: Error { case injected }
        for role in PlayerRole.allCases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("inplay.store")
            let initial = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                var draft = PlayerDraft(); draft.name = "인플레이검증"; draft.role = role
                draft.schoolID = role == .batter ? "hs-ref-001" : "hs-ref-002"
                let schools = try SchoolCatalog.load()
                let player = CareerPlayer(draft: draft, school: try XCTUnwrap(schools.first { $0.id == draft.schoolID }))
                // 무작위 선수 ID에 따라 일정·상대가 바뀌어 대주자 조건이 사라지지 않게 고정한다.
                player.id = UUID(uuidString: role == .batter ? "00000000-0000-0000-0000-000000002051" : "00000000-0000-0000-0000-000000002052")!
                context.insert(player)
                context.insert(CareerCalendarState(player: player, schools: schools, legacySave: false))
                try context.save(); try PlayerPositionStore.addMissing(in: context)
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first { $0.playerID == player.id })
                let fixtures = try state.fixtures(for: player, year: 2026)
                let fixture = try XCTUnwrap(fixtures.first { fixture in
                    guard (fixture.homeID == player.schoolID) == (role == .batter), fixture.isAppearance(for: role) else { return false }
                    let sample = makeMatch(role: role, homeID: fixture.homeID, awayID: fixture.awayID)
                    guard let original = sample.npcFielders?.home.players.first(where: { $0.position == "2B" }),
                          let reserve = sample.runnerManagement?.home else { return false }
                    return reserve.speed > original.speed
                }, "대주자 조건을 만족하는 실제 경기 일정이 필요합니다.")
                player.gameDate = fixture.date.description; try context.save()
                try CalendarProgression.rest(player: player, state: state, revision: state.revision, in: context)
                let record = try CareerMatchStore.start(player: player, state: state, in: context)
                var match = try seventhInning(role: role, initial: makeMatch(role: role, homeID: fixture.homeID,
                    awayID: fixture.awayID, careerID: player.id, fixtureID: fixture.id))
                plate("볼넷", in: &match); match.finishPitcherPlate(home: false, previousHalf: 13); match.applyCoachRunnerChange()
                record.payload = try JSONEncoder().encode(match); record.rulesVersion = "native-match-v2"
                try context.save(); _ = try record.snapshot()
                return (record.payload, player.fatigue)
            }
            let final = try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record = try XCTUnwrap(context.fetch(FetchDescriptor<CareerMatchRecord>()).first)
                XCTAssertEqual(record.payload, initial.0)
                let revision = record.revision, calendarRevision = state.revision
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: record,
                    revision: revision, input: .automatic, in: context, save: { _ in throw Failure.injected }))
                XCTAssertEqual(record.payload, initial.0); XCTAssertEqual(record.revision, revision)
                XCTAssertEqual(player.fatigue, initial.1); XCTAssertEqual(state.revision, calendarRevision)
                try CareerMatchStore.advance(player: player, state: state, record: record,
                    revision: revision, input: .automatic, in: context)
                let match = try record.snapshot(); XCTAssertTrue(record.completed)
                XCTAssertEqual(player.fatigue, min(100, initial.1 + match.appliedFatigueCost))
                XCTAssertEqual(match.runnerManagement!.changes.filter { $0.half % 2 == 1 }.count, 1)
                return (record.payload, player.fatigue, state.revision)
            }
            try autoreleasepool {
                let container = try CareerStore.makeContainer(url: url), context = container.mainContext
                let player = try XCTUnwrap(context.fetch(FetchDescriptor<CareerPlayer>()).first)
                let state = try XCTUnwrap(context.fetch(FetchDescriptor<CareerCalendarState>()).first)
                let record = try CareerMatchStore.start(player: player, state: state, in: context)
                XCTAssertEqual(record.payload, final.0); XCTAssertEqual(player.fatigue, final.1)
                XCTAssertThrowsError(try CareerMatchStore.advance(player: player, state: state, record: record,
                    revision: record.revision, input: .automatic, in: context))
                XCTAssertEqual(record.payload, final.0); XCTAssertEqual(player.fatigue, final.1)
                XCTAssertEqual(state.revision, final.2)
            }
        }
    }

    func testEveryHalfScoresForItsBattingTeamAndPreservesCyclicOrder() throws {
        var match = makeMatch()
        for half in 0..<18 {
            XCTAssertEqual(match.half, half)
            let home = match.homeScore, away = match.awayScore
            plate("홈런", in: &match)
            let event = try XCTUnwrap(match.playerRecords!.plateTrace!.last)
            XCTAssertEqual(event.battingHome, half % 2 == 1)
            XCTAssertEqual(match.homeScore, home + (half % 2 == 1 ? 1 : 0))
            XCTAssertEqual(match.awayScore, away + (half % 2 == 0 ? 1 : 0))
            for _ in 0..<3 { plate("삼진", in: &match) }
            try validate(match)
        }
        XCTAssertTrue(match.completed); XCTAssertEqual(match.homeScore, 9); XCTAssertEqual(match.awayScore, 9)
        XCTAssertEqual(match.homeOrder, 36); XCTAssertEqual(match.awayOrder, 36)
    }

    func testSeventhDoubleSpriteKitReplayReducedAndFinishedFramesNeverWriteRecords() async throws {
        for role in PlayerRole.allCases {
            var match = try seventhInning(role: role)
            plate("볼넷", in: &match); match.finishPitcherPlate(home: false, previousHalf: 13); match.applyCoachRunnerChange()
            let play = fieldPlay(match, distance: 90, flight: 5, direction: -25)
            plate("2루타", in: &match, play: play)
            let saved = match
            let sprites = FieldReplaySprites(appearance: PlayerAppearance(), jerseyNumber: 27,
                ownPosition: role == .batter ? "SS" : "P", throwingHand: "left", ownTeamFielding: role == .pitcher)
            let replay = InplayReplay.field(play), routes = replay.backupRoutes
            let planned = await sprites.requests(duration: replay.duration, reduced: false,
                actorsAt: { replay.actors(sprites, time: $0, reduced: false, finished: false, backupRoutes: routes) })
            let requests = try XCTUnwrap(planned)
            let images = await FieldRasterArt.prepare(requests)
            let prepared = try XCTUnwrap(images)
            let scene = InplayFieldScene(replay: replay, sprites: sprites, prepared: prepared, scoreText: "7회말 3 : 2", stadium: .legacy)
            await scene.preload()
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 320, height: 480)); view.presentScene(scene)
            // 표시 시각은 득점·포구 판정에 되돌려 넣지 않는다. 스킵에 해당하는 완료 프레임도 같은 원장이다.
            for time in [0, play.flight, play.duration, play.duration / 2, play.duration] {
                scene.display(time: time, finished: time == play.duration)
                _ = sprites.actors(play, time: time, reduced: true, finished: time == play.duration, backupRoutes: routes)
                XCTAssertEqual(match, saved)
            }
            let image = UIImage(cgImage: try XCTUnwrap(view.texture(from: scene)?.cgImage()))
            let attachment = XCTAttachment(image: image); attachment.name = "V205 seventh double " + role.rawValue
            attachment.lifetime = .keepAlways; add(attachment)
            view.presentScene(nil)
            try validate(match)
        }
    }
}
