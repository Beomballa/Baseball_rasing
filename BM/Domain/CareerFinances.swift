import Foundation

struct SigningBonusForecast: Codable, Equatable {
    let version: Int
    let clubID: String
    let roleID: String
    let lowerWon: Int
    let upperWon: Int
}

struct SigningBonusTerms: Codable, Equatable {
    let version: Int
    let amountWon: Int
}

enum SigningBonusPolicy {
    // Fictional game ranges in millions of won. V1 is frozen for save validation.
    static let version = 1
    private static let domestic: [String: ClosedRange<Int>] = [
        "harbors": 60...110, "comets": 55...100, "tides": 40...85, "stars": 75...125,
        "foxes": 50...90, "falcons": 65...115, "gears": 45...90, "silverhorns": 60...105,
        "auroras": 50...95, "crowns": 70...120
    ]
    private static let americanDevelopment = [
        95...155, 85...140, 105...165, 115...185, 90...150, 80...135
    ]
    private static let japaneseFirstTeam = [
        120...195, 135...215, 115...190, 125...205, 105...180, 110...185, 140...220,
        120...200, 130...210, 145...225, 110...180, 115...190, 140...215, 135...210, 105...175
    ]
    private static let americanFirstTeam = [
        170...280, 180...290, 165...270, 210...330, 195...310, 160...260, 190...305,
        185...300, 175...285, 180...295, 205...325, 170...275, 185...300, 195...315, 200...320
    ]

    private static let rolePremium = ["slugger": 8, "onBase": 4, "field": 0, "starter": 12]

    private static func quote(clubID: String, roleID: String, range: ClosedRange<Int>) -> SigningBonusForecast? {
        guard let premium = rolePremium[roleID] else { return nil }
        return SigningBonusForecast(version: version, clubID: clubID, roleID: roleID,
                                    lowerWon: (range.lowerBound + premium) * 1_000_000,
                                    upperWon: (range.upperBound + premium) * 1_000_000)
    }

    static func domesticQuote(clubID: String, roleID: String) -> SigningBonusForecast? {
        guard let range = domestic[clubID] else { return nil }
        return quote(clubID: clubID, roleID: roleID, range: range)
    }

    static func overseasQuote(clubID: String, route: OverseasRoute, roleID: String) -> SigningBonusForecast? {
        let parts = clubID.split(separator: "/")
        guard parts.count == 3, parts[0] == route.rawValue, let index = Int(parts[1]), parts[2] == roleID else { return nil }
        let ranges: [ClosedRange<Int>]
        switch route {
        case .mlbDevelopment: ranges = americanDevelopment
        case .npbFirstTeam: ranges = japaneseFirstTeam
        case .mlbFirstTeam: ranges = americanFirstTeam
        }
        guard ranges.indices.contains(index) else { return nil }
        return quote(clubID: clubID, roleID: roleID, range: ranges[index])
    }

    static func domesticForecasts(for observation: ScoutingObservation) -> [SigningBonusForecast] {
        (observation.contractFit?.clubs ?? []).compactMap { club in
            guard club.recruitment.demand != .none, let clubID = club.id.split(separator: "/").first else { return nil }
            return domesticQuote(clubID: String(clubID), roleID: club.recruitment.roleID)
        }
    }

    static func overseasForecasts(for report: OverseasScoutingReport) -> [SigningBonusForecast] {
        (report.market?.clubs ?? []).compactMap { club in
            guard club.seats > 0 else { return nil }
            return overseasQuote(clubID: club.id, route: club.route, roleID: club.roleID)
        }
    }

    static func terms(for quote: SigningBonusForecast) -> SigningBonusTerms {
        SigningBonusTerms(version: quote.version, amountWon: (quote.lowerWon + quote.upperWon) / 2)
    }
}

struct SigningBonusTransaction: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let date: String
    let amountWon: Int
}

struct CareerFinances: Equatable {
    let transactions: [SigningBonusTransaction]
    let pending: [SigningBonusTransaction]
    let trainingWon: Int
    let livingWon: Int

    var balanceWon: Int { transactions.reduce(0) { $0 + $1.amountWon } }
    var unallocatedWon: Int { balanceWon - trainingWon - livingWon }
}

struct CareerSigningFunds: Codable, Equatable {
    var version = 1
    var entries: [SigningBonusTransaction] = []
    var trainingWon = 0
    var livingWon = 0
}

enum CareerFinanceError: LocalizedError {
    case allocation

    var errorDescription: String? { "훈련비와 생활비 배분의 합계는 현재 잔액 이하여야 합니다." }
}

extension DomesticOfferPacket {
    func withSigningBonuses() throws -> Self {
        let priced = try offers.map { offer -> DomesticContractOffer in
            guard offer.route == .rookie else { return offer }
            let parts = offer.resultID.split(separator: "/")
            guard parts.count >= 3,
                  let quote = SigningBonusPolicy.domesticQuote(clubID: String(parts[1]), roleID: offer.roleID) else {
                throw ContractOfferError.invalid
            }
            var result = offer
            result.signingBonusTerms = SigningBonusPolicy.terms(for: quote)
            return result
        }
        return Self(version: 2, rule: "domestic-offers-v2", evaluationKey: evaluationKey,
                    issuedDate: issuedDate, offers: priced, emptyReasons: emptyReasons, horizon: horizon)
    }
}

extension OverseasOfferEvaluation {
    func withSigningBonuses(policy: Int?) throws -> Self {
        guard let policy else { return self }
        guard policy == SigningBonusPolicy.version else { throw ContractRegistrationError.invalid }
        var result = self
        result.offers = try offers.map { offer in
            guard let quote = SigningBonusPolicy.overseasQuote(clubID: offer.clubID, route: offer.route, roleID: offer.roleID) else {
                throw ContractRegistrationError.invalid
            }
            var priced = offer
            priced.signingBonusTerms = SigningBonusPolicy.terms(for: quote)
            return priced
        }
        result.signingBonusPolicy = policy
        return result
    }
}

extension CareerContractJournal {
    var requiresFinanceVersion: Bool {
        signingFunds != nil
            || overseasReports?.contains(where: { $0.signingBonusForecasts != nil }) == true
            || overseasCareer?.evaluations.contains(where: { $0.signingBonusPolicy != nil }) == true
    }

    var hasSupportedVersion: Bool { version == (requiresFinanceVersion ? 2 : 1) }

    mutating func scheduleSigningBonus(offerID: String, name: String, effectiveDate: String, amountWon: Int?) throws {
        guard let amountWon else { return }
        var funds = signingFunds ?? CareerSigningFunds()
        let entry = SigningBonusTransaction(id: offerID, name: name, date: effectiveDate, amountWon: amountWon)
        if let existing = funds.entries.first(where: { $0.id == offerID }) {
            guard existing == entry else { throw ContractRegistrationError.invalid }
            return
        }
        funds.entries.append(entry)
        funds.entries.sort(by: Self.signingBonusOrder)
        signingFunds = funds
        version = 2
    }

    private static func signingBonusOrder(_ lhs: SigningBonusTransaction, _ rhs: SigningBonusTransaction) -> Bool {
        lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
    }

    func finances(on today: GameDate) throws -> CareerFinances {
        let funds = signingFunds ?? CareerSigningFunds()
        var contractHistory = self
        contractHistory.retiredOn = nil
        let eligible = try funds.entries.filter { entry in
            if let retiredOn, retiredOn < entry.date { return false }
            // An accepted offer appears in the balance with its effective membership on the saved game date.
            return try contractHistory.current(on: GameDate(entry.date))?.offerID == entry.id
        }
        return CareerFinances(transactions: eligible.filter { $0.date <= today.description },
                              pending: eligible.filter { $0.date > today.description },
                              trainingWon: funds.trainingWon, livingWon: funds.livingWon)
    }

    func validateFinances(domesticOffers: [DomesticContractOffer], today: GameDate) throws {
        let domesticByID = domesticOffers.reduce(into: [String: DomesticContractOffer]()) { $0[$1.id] = $1 }
        let overseasByID = (overseasCareer?.evaluations.flatMap(\.offers) ?? []).reduce(into: [String: OverseasOffer]()) { $0[$1.id] = $1 }
        let domestic = memberships.compactMap { member -> SigningBonusTransaction? in
            guard let offer = domesticByID[member.offerID], let amount = offer.signingBonusWon else { return nil }
            return SigningBonusTransaction(id: offer.id, name: offer.name, date: member.since, amountWon: amount)
        }
        let overseas = (overseasCareer?.transitions ?? []).compactMap { transition -> SigningBonusTransaction? in
            guard let offer = overseasByID[transition.offerID], let amount = offer.signingBonusWon else { return nil }
            return SigningBonusTransaction(id: offer.id, name: offer.name, date: transition.destination.since, amountWon: amount)
        }
        let expected = (domestic + overseas).sorted(by: Self.signingBonusOrder)
        guard Set(expected.map(\.id)).count == expected.count,
              expected == (signingFunds?.entries ?? []), (signingFunds?.version ?? 1) == 1 else { throw ContractRegistrationError.invalid }
        let funds = try finances(on: today)
        guard funds.trainingWon >= 0, funds.livingWon >= 0, funds.trainingWon <= funds.balanceWon,
              funds.livingWon <= funds.balanceWon - funds.trainingWon else { throw ContractRegistrationError.invalid }
    }
}
