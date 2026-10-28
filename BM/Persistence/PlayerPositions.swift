import Foundation
import SwiftData

enum CareerSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] { CareerSchemaV6.models + [PlayerPositions.self] }
    @Model final class PlayerPositions {
        @Attribute(.unique) var playerID: UUID
        var payload: Data
        var revision: Int
        var source: String
        init(playerID: UUID, loadout: PositionLoadout, source: String) throws {
            try loadout.validate()
            self.playerID = playerID; payload = try JSONEncoder().encode(loadout); revision = 0; self.source = source
        }
        func snapshot() throws -> PositionLoadout {
            guard let value = try? JSONDecoder().decode(PositionLoadout.self, from: payload) else { throw TrainingError.invalidRecord }
            try value.validate(); return value
        }
    }
}
typealias PlayerPositions = CareerSchemaV7.PlayerPositions

@MainActor enum PlayerPositionStore {
    static func profile(playerID: UUID, in context: ModelContext) throws -> PlayerPositions? {
        try context.fetch(FetchDescriptor<PlayerPositions>(predicate: #Predicate { $0.playerID == playerID })).first
    }
    static func addMissing(in context: ModelContext, save: CalendarProgression.Save = { try $0.save() }) throws {
        let players = try context.fetch(FetchDescriptor<CareerPlayer>()).filter { $0.role == .batter }
        let existing = Set(try context.fetch(FetchDescriptor<PlayerPositions>()).map(\.playerID))
        let missing = players.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return }
        do {
            for player in missing {
                guard let primary = FieldPosition(rawValue: player.positionRaw) else { throw TrainingError.invalidRecord }
                context.insert(try PlayerPositions(playerID: player.id, loadout: PositionLoadout(primary: primary), source: "legacy-v1"))
            }
            try save(context)
        } catch { context.rollback(); throw error }
    }
}

@MainActor enum DevelopmentStore {
    static func requireIdle(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext) throws {
        guard !context.hasChanges,calendar.playerID==player.id else {throw CalendarError.staleState}
        try CareerTrainingStore.requireNoPending(player:player,in:context)
        let id=player.id
        guard try context.fetchCount(FetchDescriptor<CareerMatchRecord>(predicate:#Predicate {$0.playerID == id && !$0.completed}))==0 else {throw CareerLifecycleError.pending}
    }
    static func adopt(player:CareerPlayer,calendar:CareerCalendarState,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        if try player.lifecycle.development != nil {return}
        try requireIdle(player:player,calendar:calendar,in:context)
        var life=try player.lifecycle;life.development=PlayerDevelopment.initial(playerID:player.id,date:player.gameDate,legacy:true)
        try life.validate(playerID:player.id,today:player.gameDate)
        do {player.lifecycleData=try JSONEncoder().encode(life);calendar.revision += 1;try save(context)} catch {context.rollback();throw error}
    }
    static func switchReason(player:CareerPlayer,calendar:CareerCalendarState,to position:FieldPosition,in context:ModelContext) throws -> String? {
        guard player.role == .batter,position.rawValue != player.positionRaw else {return "현재 주 포지션입니다."}
        try requireIdle(player:player,calendar:calendar,in:context)
        if try player.lifecycle.development == nil {return "성장 수첩에서 새 정책을 먼저 시작해 주세요."}
        if calendar.hasAction(on:player.gameDate) {return "오늘 행동을 이미 사용했습니다."}
        guard let profile=try PlayerPositionStore.profile(playerID:player.id,in:context),try profile.snapshot().skill(position).mastery>=40 else {return "선택 위치 숙련40 필요 · 포지션 훈련으로 준비하세요."}
        let date=try GameDate(player.gameDate)
        if let member=try calendar.registration(for:player),member.level != "college",date >= (try GameDate("\(date.year)-04-01")),date <= (try GameDate("\(date.year)-09-22")) {return "프로 주 포지션 전환은 오프시즌에 가능합니다."}
        if let last=try player.lifecycle.development?.positions.last,try GameDate(last.date).days(to:date)<28 {return "이전 전환 후28일 적응이 필요합니다."}
        return nil
    }
    static func changePosition(player:CareerPlayer,calendar:CareerCalendarState,to position:FieldPosition,date:String,revision:Int,in context:ModelContext,save:CalendarProgression.Save = {try $0.save()}) throws {
        guard date==player.gameDate,revision==calendar.revision else {throw CalendarError.staleState}
        try requireIdle(player:player,calendar:calendar,in:context)
        if let reason=try switchReason(player:player,calendar:calendar,to:position,in:context) {throw DevelopmentError.blocked(reason)}
        guard let profile=try PlayerPositionStore.profile(playerID:player.id,in:context) else {throw TrainingError.invalidRecord}
        let mastery=try profile.snapshot().skill(position).mastery
        guard let old=FieldPosition(rawValue:player.positionRaw) else {throw TrainingError.invalidRecord}
        var life=try player.lifecycle
        guard var development=life.development else {throw TrainingError.invalidRecord}
        development.positions.append(DevelopmentPositionChange(date:date,from:old,to:position,mastery:mastery));life.development=development
        try life.validate(playerID:player.id,today:date)
        do {player.positionRaw=position.rawValue;player.lifecycleData=try JSONEncoder().encode(life);calendar.actionDate=date;calendar.revision += 1;try save(context)} catch {context.rollback();throw error}
    }
}
enum DevelopmentError:LocalizedError {
    case blocked(String)
    var errorDescription:String? {switch self {case .blocked(let message):message}}
}
