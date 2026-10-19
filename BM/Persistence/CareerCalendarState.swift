import Foundation
import SwiftData

enum CareerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CareerSchemaV1.Player.self, CareerSchemaV1.PitchMastery.self, CalendarState.self]
    }

    @Model final class CalendarState {
        @Attribute(.unique) var playerID: UUID
        var originDate: String
        var schoolIDs: [String]
        var actionDate: String?
        var revision: Int
        var legacySave: Bool
        var rulesVersion: String

        init(player: CareerPlayer, schools: [School], legacySave: Bool) {
            playerID = player.id
            originDate = player.gameDate
            schoolIDs = SeasonSchedule.group(for: player.id, schoolID: player.schoolID, schools: schools)
            actionDate = nil
            revision = 0
            self.legacySave = legacySave
            rulesVersion = "career-core-v1"
        }
        func age(of player: CareerPlayer) throws -> Int {
            try GameDate(originDate).age(startingAt: player.startAge, on: GameDate(player.gameDate))
        }
        func fixtures(for player: CareerPlayer, year: Int) throws -> [SeasonFixture] {
            let origin = try GameDate(originDate)
            let fixtures = try SeasonSchedule.fixtures(year: year, schoolIDs: schoolIDs)
            return fixtures.filter {
                $0.includes(player.schoolID) && $0.date >= origin && origin.age(startingAt: player.startAge, on: $0.date) <= 18
            }
        }
        func upcoming(for player: CareerPlayer) throws -> [SeasonFixture] {
            let today = try GameDate(player.gameDate)
            return try (today.year...min(today.year + 1, 9998)).flatMap { try fixtures(for: player, year: $0) }
                .filter { $0.date >= today }
        }
        func hasAction(on date: String) -> Bool { actionDate == date }
    }
}

typealias CareerCalendarState = CareerSchemaV2.CalendarState
