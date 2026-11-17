import Foundation
import SwiftData

@MainActor enum CareerJournal {
    enum Kind: String, CaseIterable {
        case match, training, scouting, contract, award

        var label: String {
            switch self {
            case .match: "경기"
            case .training: "훈련"
            case .scouting: "스카우트"
            case .contract: "계약"
            case .award: "시상"
            }
        }
    }

    struct Fact {
        let label: String
        let value: String
    }

    struct ScoutDetail {
        let title: String
        let status: String
        let clubs: [ScoutClub]
        let samples: [Fact]
        let evidence: [Fact]
    }

    struct ScoutClub: Identifiable {
        let id: String
        let teamID: String
        let name: String
        let stage: ScoutingInterestLevel
        let role: String?
    }

    struct ContractDetail {
        let title: String
        let status: String?
        var reviewedClub: ContractClub? = nil
        var terms: [ContractTerms] = []
        var dates: [ContractDate] = []
        var evidence: [Fact] = []
        var documentStatus: String? = nil
    }

    struct ContractClub {
        let id: String
        let name: String
    }

    struct ContractTerms: Identifiable {
        let id: String
        let club: ContractClub
        let kind: String
        let role: String?
        let economicLabel: String
        let economicIndex: Int
        let signingBonusWon: Int?
        let period: String?
        var dates: [ContractDate]
        var origin: String? = nil
        var salaryStanding: LeagueSalaryStanding? = nil
    }

    struct ContractDate: Hashable {
        let label: String
        let date: String
    }

    enum Destination {
        case match(String)
        case training(String)
        case scouting(ScoutDetail)
        case contract(ContractDetail)
        case award(CareerSeasonAwardRecord)
        case awardPending(CareerSeasonAwardBoard)
    }

    struct Entry: Identifiable {
        let id: String
        let date: GameDate
        let kind: Kind
        let title: String
        let summary: String
        let emphasis: String?
        let destination: Destination
    }

    struct Day: Identifiable {
        let date: GameDate
        let entries: [Entry]
        var id: String { date.description }
    }

    static func load(player: CareerPlayer, calendar: CareerCalendarState, schools: [School], in context: ModelContext) throws -> [Day] {
        guard calendar.playerID == player.id else { throw CalendarError.staleState }
        let today = try GameDate(player.gameDate)
        let journal = try ContractRegistrationStore.journal(player: player, calendar: calendar, in: context)
        let entries = try matchEntries(player: player, schools: schools, in: context)
            + trainingEntries(player: player, in: context)
            + scoutingEntries(player: player, calendar: calendar, overseas: journal.overseasReports ?? [], in: context)
            + contractEntries(player: player, calendar: calendar, journal: journal, today: today, in: context)
            + awardEntries(player: player, calendar: calendar, in: context)
        var seen = Set<String>()
        let grouped = Dictionary(grouping: entries.filter { $0.date <= today && seen.insert($0.id).inserted }, by: \.date)
        return grouped.keys.sorted(by: >).map { date in
            Day(date: date, entries: (grouped[date] ?? []).sorted {
                ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id)
            })
        }
    }

    private static func awardEntries(player: CareerPlayer, calendar: CareerCalendarState, in context: ModelContext) throws -> [Entry] {
        try CareerSeasonAwardStore.journalBoards(player: player, state: calendar, in: context).map { day in
            let board = day.board
            let title = "\(board.year) \(CareerSeasonAwardRecord.leagueLabel(board.competition)) 시즌 시상"
            let id = "award/\(player.id.uuidString)/\(board.year)/\(board.competition)"
            guard let award = board.record else {
                return Entry(id: id, date: day.date, kind: .award, title: title,
                             summary: "올해의팀·골든글러브 보류 · 경기 기록 부족", emphasis: nil, destination: .awardPending(board))
            }
            let winners = award.bestNine?.slots.compactMap(\.winner) ?? []
            let gloves = award.goldGlove?.slots.compactMap(\.winner) ?? []
            let teamLabel = winners.isEmpty ? "올해의팀 보류" : "올해의팀 \(winners.count)/9"
            let gloveLabel = gloves.isEmpty ? "골든글러브 보류" : "골든글러브 \(gloves.count)/9"
            let personal = award.personalHonors
            let madeTeam = winners.contains { $0.playerID == player.id.uuidString && $0.teamID == award.teamID }
            let gotGlove = gloves.contains { $0.playerID == player.id.uuidString && $0.teamID == award.teamID }
            let lead = personal.first?.label ?? (award.honors.isEmpty ? "" : "개인 타이틀 확정")
            let summary = [lead, teamLabel, gloveLabel].filter { !$0.isEmpty }.joined(separator: " · ")
            let emphasis = gotGlove ? "내 골든글러브" : madeTeam ? "내 올해의팀" : personal.isEmpty ? nil : "내 수상"
            return Entry(id: id, date: day.date, kind: .award, title: title, summary: summary,
                         emphasis: emphasis, destination: .award(award))
        }
    }

    private static func matchEntries(player: CareerPlayer, schools: [School], in context: ModelContext) throws -> [Entry] {
        let owner = player.id
        let records = try context.fetch(FetchDescriptor<CareerMatchRecord>(predicate: #Predicate { $0.playerID == owner && $0.completed }))
            .filter { $0.key == CareerMatchRecord.key(owner, $0.fixtureID) }
            .sorted { ($0.gameDate, $0.key) < ($1.gameDate, $1.key) }
        var hasAppeared = false
        var hasHomered = false
        return try records.map { record in
            let match = try record.snapshot()
            let result = match.teamScore == match.opponentScore ? "무승부" : match.teamScore > match.opponentScore ? "승리" : "패배"
            let score = "\(match.teamScore):\(match.opponentScore) \(result)"
            let line = match.line
            let personal: String
            var emphasis: String?
            if !match.appearance {
                personal = "비출전"
            } else if match.role == PlayerRole.pitcher.rawValue {
                personal = "\(line.pitchingOuts / 3).\(line.pitchingOuts % 3)이닝 · 탈삼진 \(line.pitchingStrikeouts)"
            } else {
                personal = "\(line.atBats)타수 \(line.hits)안타" + (line.homeRuns > 0 ? " · 홈런 \(line.homeRuns)" : "")
                if line.homeRuns > 0 {
                    emphasis = hasHomered ? "홈런" : "기록상 첫 홈런"
                    hasHomered = true
                }
            }
            if match.appearance {
                if !hasAppeared, emphasis == nil { emphasis = "기록상 첫 출전" }
                hasAppeared = true
            }
            return Entry(id: "match/" + record.key, date: try GameDate(record.gameDate), kind: .match,
                         title: CareerTeamDirectory.name(record.opponentID, schools: schools) + "전",
                         summary: score + " · " + personal, emphasis: emphasis, destination: .match(record.key))
        }
    }

    private static func trainingEntries(player: CareerPlayer, in context: ModelContext) throws -> [Entry] {
        let owner = player.id
        return try context.fetch(FetchDescriptor<CareerTrainingRecord>(predicate: #Predicate { $0.playerID == owner && $0.completed }))
            .map { record in
                let training = try record.snapshot()
                let gain = training.position != nil ? "숙련 XP +" + number(training.positionGainXP) : "성장 " + String(format: "%+.1f", training.gain)
                return Entry(id: "training/" + record.key, date: try GameDate(record.gameDate), kind: .training,
                             title: training.title, summary: "평균 " + number(training.average) + "점 · " + gain,
                             emphasis: trainingMilestone(training), destination: .training(record.key))
            }
    }

    private static func trainingMilestone(_ training: CareerTraining) -> String? {
        if training.pitchStudy?.restoredMastery != nil { return "구종 재등록" }
        guard training.before < 100, training.after >= 100 else { return nil }
        if training.pitchStudy != nil { return "구종 습득 완료" }
        if training.trait != nil { return "특성 획득" }
        if training.position != nil { return "포지션 숙련도 100" }
        if training.selectedKind == .pitch { return "구종 숙련도 100" }
        return "능력치 100"
    }

    private static func scoutingEntries(player: CareerPlayer, calendar: CareerCalendarState, overseas: [OverseasScoutingReport], in context: ModelContext) throws -> [Entry] {
        var previousDomestic: Set<String>?
        let domestic = try ScoutingObservationStore.reports(player: player, calendar: calendar, in: context).reversed().map { record in
            let value = try record.snapshot()
            let interested = value.interests?.entries ?? []
            let current = Set(interested.map(\.id))
            let added = previousDomestic.map { current.subtracting($0) }
            previousDomestic = value.interests == nil ? nil : current
            let title = "국내 스카우트 관찰"
            let interest = scoutInterestStatus(available: value.interests != nil, count: current.count)
            let club = interested.first { added?.contains($0.id) ?? true }
            let clubs = interested.map {
                ScoutClub(id: $0.id, teamID: "dev-" + $0.id, name: $0.name, stage: $0.level, role: $0.roleLabel)
            }
            let selected = value.contractFit.flatMap { fit in fit.comparisons.first { $0.id == fit.selectedEnvironment } }
            let evidence = interested.flatMap { scoutFacts($0.name, $0.reasons) }
                + scoutFacts("관심 판단 조건", value.interests?.pendingReasons ?? [])
                + scoutFacts("공통 평가 조건", value.evaluationPending)
            return Entry(id: "scouting/" + record.key, date: try GameDate(record.observedDate), kind: .scouting,
                         title: title, summary: [sample(value), interest, club?.name].compactMap { $0 }.joined(separator: " · "),
                         emphasis: interestEmphasis(current: current, added: added),
                         destination: .scouting(ScoutDetail(title: title, status: interest, clubs: clubs,
                                                           samples: scoutSamples(value, selected: selected), evidence: evidence)))
        }
        var previousOverseas: Set<String>?
        let international = try overseas.sorted { $0.period < $1.period }.map { report in
            let value = report.observation
            let candidates = (report.market?.clubs ?? []).filter { $0.interest != nil }.sorted {
                let lhs = $0.f ?? -.infinity, rhs = $1.f ?? -.infinity
                return lhs == rhs ? $0.id < $1.id : lhs > rhs
            }
            var current = Set<String>()
            let interested = candidates.filter { current.insert($0.name).inserted }
            let added = previousOverseas.map { current.subtracting($0) }
            previousOverseas = report.market == nil ? nil : current
            let title = "해외 스카우트 관찰"
            let interest = scoutInterestStatus(available: report.market != nil, count: interested.count)
            let clubs = interested.compactMap { row -> ScoutClub? in
                guard let stage = row.interest else { return nil }
                return ScoutClub(id: row.id, teamID: overseasTeamID(row), name: row.name, stage: stage,
                                 role: row.route.label + " · " + DomesticContractOffer.roleName(row.roleID))
            }
            let routeFacts = report.eligibility.routes.map { route in
                Fact(label: route.route.label, value: ([route.status.label] + route.reasons).joined(separator: "\n"))
            }
            let clubFacts = interested.map { club in
                var reasons = ["모집 \(club.demand.label) · \(club.seats)자리"]
                if let score = club.h, let fit = club.f {
                    reasons.append("역할 기량 \(number(score)) / 구단 기준 \(number(club.criterion)) · 적합도 \(number(fit))")
                }
                reasons.append("성적 보정 \(number(club.p))")
                return Fact(label: club.name, value: (reasons + club.blockers).joined(separator: "\n"))
            }
            let selected = report.selected
            return Entry(id: "scouting/" + report.id, date: try GameDate(value.observedDate), kind: .scouting,
                         title: title, summary: sample(value) + " · " + interest,
                         emphasis: interestEmphasis(current: current, added: added),
                         destination: .scouting(ScoutDetail(title: title, status: interest, clubs: clubs,
                                                           samples: scoutSamples(value, selected: selected), evidence: routeFacts + clubFacts)))
        }
        return domestic + international
    }

    private static func scoutInterestStatus(available: Bool, count: Int) -> String {
        guard available else { return "구단 관심 미기록" }
        return count == 0 ? "구단 관심 없음" : "관심 구단 \(count)곳"
    }

    private static func scoutSamples(_ value: ScoutingObservation, selected: ScoutingPerformanceComparison?) -> [Fact] {
        let pitcher = value.role == .pitcher
        var facts = [Fact(label: "표본 기간", value: value.sampleStart + " ~ " + value.observedDate),
                     Fact(label: "공식 경기", value: "\(value.totals.games)경기"),
                     Fact(label: pitcher ? "투구 이닝" : "타석",
                          value: pitcher ? "\(value.totals.innings)이닝" : "\(value.totals.line.plateAppearances)타석")]
        if value.totals.games > 0 {
            let line = value.totals.line
            facts.append(pitcher
                ? Fact(label: "투구 성적", value: "탈삼진 \(line.pitchingStrikeouts) · 실점 \(line.runsAllowed) · WHIP \(value.totals.whip)")
                : Fact(label: "타격 성적", value: "타율 \(value.totals.average) · 홈런 \(line.homeRuns) · 타점 \(line.rbi)"))
        }
        if let selected {
            facts.append(Fact(label: "평가에 반영한 동일 환경", value: sample(selected.totals, role: value.role)))
            facts.append(Fact(label: "비교 기준", value: selected.reason))
        }
        if value.pending > 0 { facts.append(Fact(label: "관찰일 미완료 경기", value: "\(value.pending)경기")) }
        return facts
    }

    private static func scoutFacts(_ label: String, _ reasons: [String]) -> [Fact] {
        reasons.isEmpty ? [] : [Fact(label: label, value: reasons.joined(separator: "\n"))]
    }

    private static func overseasTeamID(_ row: OverseasClubEvaluation) -> String {
        guard let index = row.id.split(separator: "/").dropFirst().first else { return row.id }
        let prefix: String
        switch row.route {
        case .mlbDevelopment: prefix = "us-dev-"
        case .npbFirstTeam: prefix = "jp-pro-"
        case .mlbFirstTeam: prefix = "us-pro-"
        }
        return prefix + index
    }

    private static func interestEmphasis(current: Set<String>, added: Set<String>?) -> String? {
        guard !current.isEmpty else { return nil }
        if let added { return added.isEmpty ? nil : "새 구단 관심" }
        return "관심 구단"
    }

    private static func contractEntries(player: CareerPlayer, calendar: CareerCalendarState, journal: CareerContractJournal,
                                        today: GameDate, in context: ModelContext) throws -> [Entry] {
        let evaluations = try ContractEvaluationStore.records(player: player, calendar: calendar, in: context)
        let packets = try ContractOfferStore.records(player: player, calendar: calendar, in: context)
        let packetsByKey = Dictionary(uniqueKeysWithValues: packets.map { ($0.key, $0) })
        var domesticOffers: [String: DomesticContractOffer] = [:]
        var renewalOffers: [String: ContractTerms] = [:]
        var rows: [Entry] = []
        for evaluation in evaluations {
            let value = try evaluation.snapshot(player: player, calendar: calendar)
            let packet = try packetsByKey[evaluation.key]?.snapshot(evaluation: evaluation, player: player, calendar: calendar)
            let issued = packet?.offers ?? []
            for offer in issued { domesticOffers[offer.id] = offer }
            let renewal = value.renewal.flatMap { review in review.offer.map { renewalTerms($0, review: review) } }
            if let renewal { renewalOffers[renewal.id] = renewal }

            var offersOnDate = (packet?.issuedDate == value.evaluatedDate ? issued : []).map { domesticTerms($0) }
            if let renewal, value.renewal?.offer?.issuedDate == value.evaluatedDate {
                offersOnDate.append(renewal)
            }
            let routes = value.routes.joined(separator: " · ")
            let archivedSample = value.selection?.sample
            let totals = archivedSample?.comparison.totals ?? value.renewal?.totals ?? value.observation.totals
            var facts = [Fact(label: "평가 경로", value: routes), Fact(label: "평가 시점 표본", value: sample(totals, role: value.observation.role))]
            if let archivedSample {
                facts.append(Fact(label: "표본 출처", value: "\(archivedSample.kind) · \(archivedSample.endDate) 종료"))
            }
            let results = value.college?.results ?? value.retry?.results ?? value.selection?.results ?? []
            if !results.isEmpty {
                let selected = results.filter(\.selected)
                let selection = selected.isEmpty ? "선발된 구단 없음" : selected.map { "\($0.name) · \($0.status)" }.joined(separator: "\n")
                facts.append(Fact(label: "선발 결과", value: selection))
            }
            let reasons = value.renewal?.reasons ?? packet?.emptyReasons ?? []
            if !reasons.isEmpty { facts.append(Fact(label: "평가 근거", value: reasons.joined(separator: "\n"))) }
            let emptyStatus: String
            if !issued.isEmpty || renewal != nil { emptyStatus = "당일 제의 없음" }
            else { emptyStatus = packet == nil && value.renewal == nil ? "제의 기록 없음" : "제의 없음" }
            let evaluationDetail = ContractDetail(title: "국내 계약 평가", status: offerStatus(offersOnDate, empty: emptyStatus),
                                                  reviewedClub: (value.renewal?.membership ?? value.college?.membership).map(club),
                                                  terms: offersOnDate, dates: [ContractDate(label: "평가일", date: value.evaluatedDate)], evidence: facts)
            rows.append(try contractEntry(id: "contract/evaluation/" + evaluation.key, date: value.evaluatedDate,
                                   summary: routes + (offersOnDate.isEmpty ? "" : " · 제의 \(offersOnDate.count)건"),
                                   emphasis: offersOnDate.isEmpty ? nil : renewal != nil ? "재계약 제의" : "계약 제의", detail: evaluationDetail))
            if let packet, packet.issuedDate != value.evaluatedDate, !issued.isEmpty {
                let detail = ContractDetail(title: "국내 계약 제의", status: "제의 \(issued.count)건", terms: issued.map { domesticTerms($0) },
                                            dates: [ContractDate(label: "평가일", date: value.evaluatedDate)])
                rows.append(try contractEntry(id: "contract/issue/" + evaluation.key, date: packet.issuedDate,
                                       summary: issued.map(\.name).joined(separator: " · "), emphasis: "계약 제의",
                                       detail: detail))
            }
            if let renewal, let date = value.renewal?.offer?.issuedDate, date != value.evaluatedDate {
                rows.append(try contractEntry(id: "contract/issue/" + renewal.id, date: date,
                                              summary: renewal.club.name, emphasis: "재계약 제의",
                                              detail: ContractDetail(title: "국내 재계약 제의", status: "제의 1건", terms: [renewal])))
            }
        }
        let memberships = Dictionary(uniqueKeysWithValues: journal.memberships.map { ($0.offerID, $0) })
        for decision in journal.decisions where decision.kind != .closed {
            guard let offer = domesticOffers[decision.offerID] else { continue }
            let accepted = decision.kind == .accepted
            let member = accepted ? memberships[offer.id] : nil
            let source = offer.collegeEntry.flatMap { memberships[$0.membershipOfferID] }
            rows += try decisionRows(terms: domesticTerms(offer, membership: member, source: source), date: decision.date,
                                     accepted: accepted, effective: member?.since, today: today)
        }
        for renewal in journal.renewals ?? [] {
            guard let terms = renewalOffers[renewal.terms.id] else { continue }
            rows += try decisionRows(terms: terms, date: renewal.date, accepted: true, renewal: true,
                                     effective: renewal.terms.effectiveDate, today: today)
        }
        for decision in journal.renewalRejections ?? [] {
            guard let terms = renewalOffers[decision.offerID] else { continue }
            rows += try decisionRows(terms: terms, date: decision.date, accepted: false, renewal: true, today: today)
        }
        if let overseas = journal.overseasCareer {
            rows += try overseasContractEntries(overseas, today: today)
        }
        if let market = journal.kboTransfers {
            for evaluation in market.evaluations {
                guard let declaration = market.declarations.first(where: { $0.id == evaluation.declarationID }) else { continue }
                for offer in evaluation.offers {
                    let terms = ContractTerms(id: offer.id, club: ContractClub(id: offer.teamID, name: offer.name),
                        kind: "KBO 1군 FA", role: DomesticContractOffer.roleName(offer.roleID),
                        economicLabel: "연봉지수", economicIndex: offer.economicIndex, signingBonusWon: offer.signingBonusWon,
                        period: "\(offer.years)년 · \(offer.effective) ~ \(offer.economicEnd)",
                        dates: termDates(issued: offer.issued, expires: offer.expires, proposed: offer.effective, end: offer.economicEnd),
                        origin: declaration.source.name, salaryStanding: offer.salaryStanding)
                    guard let decision = market.decisions.first(where: { $0.offerID == offer.id }), decision.kind != .closed else { continue }
                    let accepted = decision.kind == .accepted
                    rows += try decisionRows(terms: terms, date: decision.date, accepted: accepted,
                                             effective: accepted ? offer.effective : nil, today: today)
                }
            }
        }
        return rows
    }

    private static func overseasContractEntries(_ career: OverseasCareerJournal, today: GameDate) throws -> [Entry] {
        var rows: [Entry] = []
        var offers: [String: ContractTerms] = [:]
        for evaluation in career.evaluations {
            let summary = evaluation.offers.isEmpty ? "저장된 제의 없음" : "해외 구단 제의 \(evaluation.offers.count)건"
            let source = evaluation.source ?? evaluation.mobility?.source
            let terms = evaluation.offers.map { overseasTerms($0, source: source) }
            for offer in terms { offers[offer.id] = offer }
            let detail = ContractDetail(title: "해외 계약 평가", status: offerStatus(terms), terms: terms,
                                        dates: [ContractDate(label: "평가일", date: evaluation.date)], evidence: reasonFacts(evaluation.reasons))
            rows.append(try contractEntry(id: "contract/evaluation/" + evaluation.id, date: evaluation.date,
                                          summary: summary, emphasis: terms.isEmpty ? nil : "해외 계약 제의", detail: detail))
        }
        for decision in career.decisions where decision.kind != .closed {
            guard let terms = offers[decision.offerID] else { continue }
            let effective = career.transitions.first { $0.offerID == decision.offerID }?.destination.since
            rows += try decisionRows(terms: terms, date: decision.date, accepted: decision.kind == .accepted,
                                     effective: effective, today: today)
        }
        var renewalOffers: [String: OverseasOffer] = [:]
        for review in career.renewalReviews ?? [] {
            if let offer = review.offer { renewalOffers[offer.id] = offer }
            let terms = review.offer.map { [overseasTerms($0, renewal: true)] } ?? []
            let detail = ContractDetail(title: "해외 재계약 평가", status: offerStatus(terms), reviewedClub: club(review.source), terms: terms,
                                        dates: [ContractDate(label: "평가일", date: review.date)], evidence: reasonFacts(review.reasons))
            rows.append(try contractEntry(id: "contract/evaluation/" + review.id, date: review.date,
                                   summary: review.source.name + (review.offer == nil ? " · 저장된 제의 없음" : " · 제의 1건"),
                                   emphasis: review.offer == nil ? nil : "재계약 제의", detail: detail))
        }
        for decision in career.renewalDecisions ?? [] where decision.kind != .closed {
            guard let offer = renewalOffers[decision.offerID] else { continue }
            let accepted = decision.kind == .accepted
            rows += try decisionRows(terms: overseasTerms(offer, renewal: true), date: decision.date, accepted: accepted, renewal: true,
                                     effective: accepted ? offer.effective : nil, today: today)
        }
        return rows
    }

    private static func decisionRows(terms: ContractTerms, date: String, accepted: Bool, renewal: Bool = false,
                                     effective: String? = nil, today: GameDate) throws -> [Entry] {
        let type = renewal ? "재계약" : "계약"
        let decision = accepted ? type + " 수락" : type + " 거절"
        let occurred = try GameDate(date)
        let effectiveDate = try accepted ? effective.map(GameDate.init) : nil
        let effectiveLabel = effectiveDate.map { $0 > today ? "발효 예정" : "발효일" } ?? ""
        let summary = effectiveDate.map { effectiveLabel + " " + $0.description } ?? "결정일 " + date
        let documentStatus = effectiveDate.map { $0 > today ? "수락 완료 · 발효 예정" : "수락 완료 · 발효 완료" } ?? decision
        var schedule = [ContractDate(label: "결정일", date: date)]
        var archivedTerms = terms
        if let effectiveDate {
            schedule.append(ContractDate(label: effectiveLabel, date: effectiveDate.description))
            let proposed = ContractDate(label: "제의상 발효일", date: effectiveDate.description)
            archivedTerms.dates.removeAll { $0 == proposed }
        }
        var rows = [try contractEntry(id: "contract/decision/" + terms.id, date: date, title: terms.club.name + " " + decision,
                                      summary: summary, emphasis: accepted ? decision : nil,
                                      detail: ContractDetail(title: decision, status: nil, terms: [archivedTerms], dates: schedule,
                                                             documentStatus: documentStatus))]
        if let effectiveDate, effectiveDate != occurred, effectiveDate <= today {
            let label = type + " 발효"
            rows.append(try contractEntry(id: "contract/effective/" + terms.id, date: effectiveDate.description, title: terms.club.name + " " + label,
                                          summary: "수락일 " + date, emphasis: label,
                                          detail: ContractDetail(title: label, status: nil, terms: [archivedTerms], dates: schedule,
                                                                 documentStatus: "발효 완료")))
        }
        return rows
    }

    private static func contractEntry(id: String, date: String, title: String? = nil, summary: String, emphasis: String?, detail: ContractDetail) throws -> Entry {
        Entry(id: id, date: try GameDate(date), kind: .contract, title: title ?? detail.title, summary: summary, emphasis: emphasis, destination: .contract(detail))
    }

    private static func domesticTerms(_ offer: DomesticContractOffer, membership: CareerMembership? = nil,
                                      source: CareerMembership? = nil) -> ContractTerms {
        let prefix = offer.route == .rookie ? "dev-" : "college-"
        // Validated offers carry a `route/team/role` result key, including proposals without a membership.
        let teamID = offer.resultID.split(separator: "/").dropFirst().first.map { prefix + $0 } ?? offer.resultID
        let period: String
        if let membership, offer.route == .rookie {
            period = "\(offer.years)년 · \(membership.since) ~ \(membership.economicEnd)"
        }
        else if offer.collegeEntry != nil { period = "1년 · 대학 소속은 발효 전일까지 유지" }
        else { period = offer.period }
        var dates = termDates(issued: offer.issuedDate, expires: offer.expiresDate,
                              proposed: offer.collegeEntry?.effectiveDate, end: membership?.economicEnd)
        if let end = membership?.enrollmentEnd { dates.append(ContractDate(label: "학적 기한", date: end)) }
        return ContractTerms(id: offer.id, club: ContractClub(id: teamID, name: offer.name), kind: offer.kind,
                             role: DomesticContractOffer.roleName(offer.roleID), economicLabel: offer.economicLabel,
                             economicIndex: offer.economicIndex, signingBonusWon: offer.signingBonusWon, period: period, dates: dates,
                             origin: source?.name)
    }

    private static func renewalTerms(_ offer: DomesticRenewalOffer, review: DomesticRenewalReview) -> ContractTerms {
        ContractTerms(id: offer.id, club: club(review.membership), kind: "국내 육성팀 재계약", role: DomesticContractOffer.roleName(review.roleID),
                      economicLabel: "연봉지수", economicIndex: offer.economicIndex, signingBonusWon: nil, period: "\(offer.years)년",
                      dates: termDates(issued: offer.issuedDate, expires: offer.expiresDate, proposed: offer.effectiveDate, end: offer.economicEnd))
    }

    private static func overseasTerms(_ offer: OverseasOffer, renewal: Bool = false, source: CareerMembership? = nil) -> ContractTerms {
        ContractTerms(id: offer.id, club: ContractClub(id: offer.teamID, name: offer.name), kind: offer.route.label + (renewal ? " 재계약" : " 계약"),
                      role: DomesticContractOffer.roleName(offer.roleID), economicLabel: "연봉지수", economicIndex: offer.economicIndex,
                      signingBonusWon: offer.signingBonusWon, period: "\(offer.years)년 · \(offer.effective) ~ \(offer.economicEnd)",
                      dates: termDates(issued: offer.issued, expires: offer.expires, proposed: offer.effective, end: offer.economicEnd),
                      origin: source?.teamID == offer.teamID ? nil : source?.name)
    }

    private static func club(_ membership: CareerMembership) -> ContractClub {
        ContractClub(id: membership.teamID, name: membership.name)
    }

    private static func termDates(issued: String, expires: String, proposed: String?, end: String?) -> [ContractDate] {
        var dates = [ContractDate(label: "제의일", date: issued), ContractDate(label: "마감일", date: expires)]
        if let proposed { dates.append(ContractDate(label: "제의상 발효일", date: proposed)) }
        if let end { dates.append(ContractDate(label: "경제기간 종료일", date: end)) }
        return dates
    }

    private static func offerStatus(_ terms: [ContractTerms], empty: String = "제의 없음") -> String {
        terms.isEmpty ? empty : "제의 \(terms.count)건"
    }

    private static func reasonFacts(_ reasons: [String]) -> [Fact] {
        reasons.isEmpty ? [] : [Fact(label: "평가 근거", value: reasons.joined(separator: "\n"))]
    }

    private static func sample(_ value: ScoutingObservation) -> String {
        sample(value.totals, role: value.role)
    }

    private static func sample(_ totals: PersonalSeasonTotals, role: PlayerRole) -> String {
        "\(totals.games)경기 · " + (role == .pitcher ? "\(totals.innings)이닝" : "\(totals.line.plateAppearances)타석")
    }

    private static func number(_ value: Double) -> String { String(format: "%.1f", value) }
}
