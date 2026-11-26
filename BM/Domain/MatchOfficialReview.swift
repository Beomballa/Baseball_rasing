import Foundation

struct MatchReviewPlate: Codable, Equatable {
    let context: MatchEarnedPlay
    let play: MatchDetailedPlay?
    let finalResult: String
    let runs: Int
    let relief: Bool
    let deferred: Bool
    let batterID: String
    let pitcherID: String
    let fielderID: String?
    let deferredAssists: [String]
    let personalBatter: Bool
    let personalPitcher: Bool
    let initialRBI: Int
    let finalRBI: Int
    var recordedResult: String { deferred ? "안타" : finalResult }
    var recordedContext: MatchEarnedPlay {
        deferred ? MatchEarnedPlay(half: context.half, order: context.order, initial: context.initial,
            outs: context.outs, batter: context.batter, clean: play, stats: context.stats,
            defending: context.defending, npc: context.npc) : context
    }
}
enum MatchReviewInput: Codable, Equatable {
    case plate(MatchReviewPlate)
    case loose(MatchDetailedPlay, MatchLoosePitchCredit)
    case running(MatchDetailedPlay)
}
struct MatchRecordCorrection: Codable, Equatable, Identifiable {
    let proof: MatchReviewPlate
    let appliedHalf: Int
    let appliedTotal: Int
    let atCompletion: Bool
    var id: String { "\(proof.context.half):\(proof.context.order)" }
    var reason: String { "보통의 수비로 처리할 수 있는 타구를 놓친 것으로 정정" }
    func visible(in match: CareerMatch) -> Bool {
        appliedHalf <= match.half && appliedTotal <= match.homeOrder+match.awayOrder && (!atCompletion || match.completed)
    }
}
struct MatchOfficialReview: Codable, Equatable {
    struct Pending: Codable, Equatable {
        let half: Int
        let origin: MatchEarnedState
        let earnedBefore: [Int]
        var inputs: [MatchReviewInput] = []
        /// 같은 입력 근거에서 공식 분류만 바꿔 자책을 다시 계산한다. 경기나 RNG를 재실행하지 않는다.
        func rebuilt(final: Bool) -> (MatchEarnedState,[Int]) {
            var tracker = origin, totals = earnedBefore
            for input in inputs {
                let credits: [String:Int]
                switch input {
                case .plate(let value):
                    credits = tracker.observe(final ? value.context : value.recordedContext, actual: value.play,
                        result: final ? value.finalResult : value.recordedResult, runs: value.runs, relief: value.relief)
                case .loose(let play, let credit): credits = tracker.observeLoose(play, credit: credit)
                case .running(let play): credits = tracker.observeRunning(play)
                }
                for (tag,count) in credits { totals[tag == MatchPitching.reliefID(home: half % 2 == 0) ? 1 : 0] += count }
            }
            return (tracker,totals)
        }
    }
    var version = 1
    var pending: Pending?
    var changes: [MatchRecordCorrection] = []
}

extension CareerMatch {
    mutating func enableOfficialReviews() {
        guard officialReview == nil, appealRulesVersion == 1, playerRecords?.earned != nil,
              half == 0, homeOrder == 0, awayOrder == 0, fieldPlays?.isEmpty == true else { return }
        officialReview = MatchOfficialReview()
    }

    /// 초기에 안타로 보인 보통 수비의 포구 실수만 반이닝 말 공식 검토 대상으로 보존한다.
    mutating func beginOfficialPlate(result: String, play: MatchDetailedPlay?, clean: MatchDetailedPlay?) -> Bool {
        guard officialReview != nil else { return false }
        let candidate = result == "실책 출루" && play?.misplay?.kind == .fielding
            && play?.misplay?.reachedOnError == true && play?.hitBases == 0 && clean?.out == true
        if candidate, officialReview?.pending == nil, let origin = playerRecords?.earned {
            let defense = half % 2 == 0 ? playerRecords!.home : playerRecords!.away
            officialReview?.pending = .init(half: half, origin: origin,
                earnedBefore: defense.pitching.map { $0.counts.earnedRuns ?? 0 })
        }
        return candidate
    }

    mutating func rememberOfficialPlate(context: MatchEarnedPlay, play: MatchDetailedPlay?, result: String, runs: Int,
                                       deferred: Bool, batter: Bool, pitcher: Bool, rbi: Int) {
        guard officialReview?.pending?.half == context.half, let records = playerRecords else { return }
        let defense = context.half % 2 == 0 ? records.home : records.away
        let relief = pitching?.change(home: context.half % 2 == 0) != nil
        let pitcherID = defense.pitching[relief ? 1 : 0].id
        let fielderID: String?
        if let index = play?.misplay?.fielder {
            let position = DetailedFieldRules.names[index], replacement = defense.runnerChanges?.last(where: { $0.position == position })?.replacement
            fielderID = defense.fielding?.first(where: {
                $0.position == position && (position == "P" ? $0.id == pitcherID : replacement == nil || $0.id == replacement)
            })?.id
        } else { fielderID = nil }
        // 실책이 있어야 성립하는 보살은 안타 잠정 기록과 함께 보류하고 당시 선수 ID를 고정한다.
        let finalCredit = MatchFieldingCredits.make(result: result, play: play, clean: context.clean, outsAdded: play?.outsAdded ?? 0)
        let initialCredit = MatchFieldingCredits.make(result: result, play: play, clean: context.clean, outsAdded: play?.outsAdded ?? 0, deferError: true)
        let assists = deferred ? (finalCredit?.assists ?? []).subtracting(initialCredit?.assists ?? []).sorted().compactMap { index -> String? in
            let position = DetailedFieldRules.names[index]
            let replacement = defense.runnerChanges?.last(where: { $0.position == position })?.replacement
            return defense.fielding?.first(where: { $0.position == position && (position == "P" ? $0.id == pitcherID : replacement == nil || $0.id == replacement) })?.id
        } : []
        officialReview?.pending?.inputs.append(.plate(.init(context: context, play: play, finalResult: result,
            runs: runs, relief: relief, deferred: deferred, batterID: context.batter.id ?? "", pitcherID: pitcherID,
            fielderID: fielderID, deferredAssists: assists, personalBatter: batter, personalPitcher: pitcher,
            initialRBI: deferred ? runs : rbi, finalRBI: rbi)))
    }

    mutating func rememberOfficialLoose(_ play: MatchDetailedPlay, credit: MatchLoosePitchCredit) {
        guard officialReview?.pending?.half == play.half else { return }
        officialReview?.pending?.inputs.append(.loose(play,credit))
    }
    mutating func rememberOfficialRunning(_ play: MatchDetailedPlay) {
        guard officialReview?.pending?.half == play.half else { return }
        officialReview?.pending?.inputs.append(.running(play))
    }

    /// 어필 기회가 닫힌 반이닝만 한 번 확정한다. 날짜·점수·실제 주루·보상은 변경하지 않는다.
    mutating func closeOfficialReview() {
        guard let pending = officialReview?.pending, half != pending.half || completed, var records = playerRecords else { return }
        let battingHome = pending.half % 2 == 1
        var attack = battingHome ? records.home : records.away, defense = battingHome ? records.away : records.home
        for input in pending.inputs {
            guard case .plate(let value) = input, value.deferred,
                  let bi = attack.batting.firstIndex(where: { $0.id == value.batterID }),
                  let pi = defense.pitching.firstIndex(where: { $0.id == value.pitcherID }) else { continue }
            attack.batting[bi].counts.singles -= 1; attack.batting[bi].counts.reachedOnError += 1
            attack.batting[bi].counts.rbi += value.finalRBI-value.initialRBI
            defense.pitching[pi].counts.hits -= 1
            if let fi = defense.fielding?.firstIndex(where: { $0.id == value.fielderID }) { defense.fielding?[fi].errors += 1 }
            for id in value.deferredAssists {
                if let fi = defense.fielding?.firstIndex(where: { $0.id == id }) { defense.fielding?[fi].assists += 1 }
            }
            if value.personalBatter {
                line.hits -= 1; line.rbi += value.finalRBI-value.initialRBI
                if scoutingPerformance != nil { scoutingPerformance?.singles -= 1 }
            }
            if value.personalPitcher { line.hitsAllowed -= 1 }
            if let ti = records.plateTrace?.firstIndex(where: { $0.half == value.context.half && $0.order == value.context.order }) {
                records.plateTrace?[ti].result = value.finalResult
            }
            officialReview?.changes.append(.init(proof: value, appliedHalf: half,
                appliedTotal: homeOrder+awayOrder, atCompletion: completed))
        }
        let (earned,totals) = pending.rebuilt(final: true)
        for index in defense.pitching.indices { defense.pitching[index].counts.earnedRuns = totals[index] }
        if half == pending.half { records.earned = earned }
        if battingHome { records.home = attack; records.away = defense } else { records.away = attack; records.home = defense }
        playerRecords = records; officialReview?.pending = nil
    }

    /// 해당 플레이 직후 시점을 기준으로 최초 기록과 나중 정정을 구분한다.
    func officialLabel(for play: MatchDetailedPlay) -> String? {
        if let value = officialReview?.pending?.inputs.compactMap({ input -> MatchReviewPlate? in
            if case .plate(let value) = input, value.deferred, value.context.half == play.half, value.context.order == play.order { return value }
            return nil
        }).first { return value.recordedResult+" · 공식 기록 검토 예정" }
        guard let change = officialReview?.changes.first(where: { $0.id == play.eventID }) else { return nil }
        let after = play.review?.after
        let visible = after.map { change.appliedHalf <= $0.half && change.appliedTotal <= $0.homeOrder+$0.awayOrder
            && (!change.atCompletion || $0.completed) } ?? false
        return visible ? change.proof.finalResult+" · 기록 정정" : change.proof.recordedResult+" · 공식 기록 검토 예정"
    }

    func validateOfficialReviews() throws {
        guard let review = officialReview else { return }
        guard review.version == 1, appealRulesVersion == 1, review.changes.count <= 100_000,
              Set(review.changes.map(\.id)).count == review.changes.count else { throw MatchError.invalidRecord }
        func plate(_ value: MatchReviewPlate) throws {
            guard (0..<18).contains(value.context.half), value.context.order >= 0, (0...2).contains(value.context.outs),
                  (0...4).contains(value.runs), (0...value.runs).contains(value.initialRBI), (0...value.runs).contains(value.finalRBI),
                  value.context.batter.id == value.batterID, value.context.stats == fieldStats,
                  let trace = playerRecords?.plateTrace?.first(where: { $0.half == value.context.half && $0.order == value.context.order }),
                  trace.batter == value.batterID, trace.pitcher == value.pitcherID else { throw MatchError.invalidRecord }
            if let clean = value.context.clean { try clean.validate() }
            if let play = value.play {
                try play.validate()
                guard var saved = ((fieldPlays ?? []) + (pitchEvents?.events.compactMap(\.play) ?? [])).first(where: { $0.eventID == play.eventID }) else { throw MatchError.invalidRecord }
                saved.review?.after = play.review?.after
                guard saved == play else { throw MatchError.invalidRecord }
            }
            if value.deferred {
                guard value.finalResult == "실책 출루", value.play?.misplay?.kind == .fielding,
                      value.play?.misplay?.reachedOnError == true, value.play?.hitBases == 0, value.context.clean?.out == true,
                      value.fielderID != nil else { throw MatchError.invalidRecord }
                let finalCredit = MatchFieldingCredits.make(result: value.finalResult, play: value.play, clean: value.context.clean, outsAdded: value.play?.outsAdded ?? 0)
                let initialCredit = MatchFieldingCredits.make(result: value.finalResult, play: value.play, clean: value.context.clean, outsAdded: value.play?.outsAdded ?? 0, deferError: true)
                let positions = (finalCredit?.assists ?? []).subtracting(initialCredit?.assists ?? []).map { DetailedFieldRules.names[$0] }.sorted()
                let defense = value.context.half % 2 == 0 ? playerRecords?.home : playerRecords?.away
                guard Set(value.deferredAssists).count == value.deferredAssists.count,
                      value.deferredAssists.compactMap({ id in defense?.fielding?.first(where: { $0.id == id })?.position }).sorted() == positions else { throw MatchError.invalidRecord }
            }
        }
        for change in review.changes {
            try plate(change.proof)
            guard change.proof.deferred, change.appliedHalf > change.proof.context.half || change.atCompletion,
                  change.appliedHalf <= half, change.appliedTotal <= homeOrder+awayOrder,
                  playerRecords?.plateTrace?.first(where: { $0.id == change.id })?.result == change.proof.finalResult else { throw MatchError.invalidRecord }
        }
        if let pending = review.pending {
            guard !completed, pending.half == half, pending.origin.half == half,
                  pending.earnedBefore.count == 2, pending.earnedBefore.allSatisfy({ (0...100_000).contains($0) }),
                  pending.inputs.count <= 100_000, !pending.inputs.isEmpty else { throw MatchError.invalidRecord }
            var frame = self; frame.bases = pending.origin.runners.map { $0 != nil }
            try pending.origin.validate(match: frame)
            for input in pending.inputs {
                switch input {
                case .plate(let value): try plate(value)
                case .loose(let value,_):
                    try value.validatePitchField()
                    guard value.half == pending.half, pitchEvents?.events.contains(where: { $0.play == value }) == true else { throw MatchError.invalidRecord }
                case .running(let value):
                    try value.validateRunningField()
                    guard value.half == pending.half, running?.events.contains(where: { $0.play == value }) == true else { throw MatchError.invalidRecord }
                }
            }
            let (expected,totals) = pending.rebuilt(final: false), defense = half % 2 == 0 ? playerRecords?.home : playerRecords?.away
            guard playerRecords?.earned == expected, defense?.pitching.map({ $0.counts.earnedRuns ?? 0 }) == totals else { throw MatchError.invalidRecord }
        }
    }
}
