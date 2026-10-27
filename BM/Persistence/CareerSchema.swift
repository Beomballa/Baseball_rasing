import Foundation
import SwiftData

enum CareerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Player.self, PitchMastery.self] }

    @Model final class Player {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var roleRaw: String
        var name: String
        var jerseyNumber: Int
        var schoolID: String
        var schoolName: String
        var positionRaw: String
        var throwingHandRaw: String
        var skin: Int
        var hair: Int
        var kit: Int
        var hairStyle: Int
        var expression: Int
        var startAge: Int
        var gameDate: String
        var fatigue: Int
        var contact: Double
        var power: Double
        var discipline: Double
        var speed: Double
        var defense: Double
        var arm: Double
        var createdAt: Date
        @Relationship(deleteRule: .cascade) var pitches: [PitchMastery]

        init(draft: PlayerDraft, school: School) {
            id = UUID()
            roleRaw = draft.role.rawValue
            name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            jerseyNumber = Int(draft.jerseyNumber) ?? 1
            schoolID = school.id
            schoolName = school.name
            positionRaw = draft.position.rawValue
            throwingHandRaw = draft.throwingHand.rawValue
            skin = draft.appearance.skin
            hair = draft.appearance.hair
            kit = draft.appearance.kit
            hairStyle = draft.appearance.hairStyle
            expression = draft.appearance.expression
            startAge = 16
            gameDate = "2026-04-01"
            fatigue = draft.role == .batter ? 24 : 52
            contact = 65; power = 75; discipline = 60
            speed = draft.role == .batter ? 72 : 55
            defense = draft.role == .batter ? 65 : 60
            arm = draft.role == .batter ? 68 : 70
            createdAt = Date()
            pitches = draft.role == .pitcher ? [
                PitchMastery(code: "four-seam", name: "포심", mastery: 72, order: 0),
                PitchMastery(code: "slider", name: "슬라이더", mastery: 65, order: 1),
                PitchMastery(code: "changeup", name: "체인지업", mastery: 48, order: 2),
                PitchMastery(code: "fork", name: "포크", mastery: 35, order: 3)
            ] : []
        }
        var role: PlayerRole { PlayerRole(rawValue: roleRaw) ?? .batter }
        var appearance: PlayerAppearance {
            PlayerAppearance(skin: skin, hair: hair, kit: kit, hairStyle: hairStyle, expression: expression)
        }
        var roleDetail: String {
            role == .batter ? (FieldPosition(rawValue: positionRaw)?.label ?? positionRaw)
                : (ThrowingHand(rawValue: throwingHandRaw)?.label ?? throwingHandRaw)
        }
    }

    @Model final class PitchMastery {
        var code: String
        var name: String
        var mastery: Double
        var order: Int
        init(code: String, name: String, mastery: Double, order: Int) {
            self.code = code; self.name = name; self.mastery = mastery; self.order = order
        }
    }
}


enum CareerSchemaV15: VersionedSchema {
    static let versionIdentifier = Schema.Version(15,0,0)
    static var models: [any PersistentModel.Type] {
        CareerSchemaV14.models.filter {ObjectIdentifier($0) != ObjectIdentifier(CareerSchemaV1.Player.self) && ObjectIdentifier($0) != ObjectIdentifier(CareerSchemaV1.PitchMastery.self)} + [Player.self,PitchMastery.self,ActiveCareerSlot.self]
    }
    @Model final class PitchMastery {
        var code:String
        var name:String
        var mastery:Double
        var order:Int
        init(code:String,name:String,mastery:Double,order:Int) {self.code=code;self.name=name;self.mastery=mastery;self.order=order}
    }
    @Model final class Player {
        @Attribute(.unique) var id: UUID
        var roleRaw: String
        var name: String
        var jerseyNumber: Int
        var schoolID: String
        var schoolName: String
        var positionRaw: String
        var throwingHandRaw: String
        var skin: Int
        var hair: Int
        var kit: Int
        var hairStyle: Int
        var expression: Int
        var startAge: Int
        var gameDate: String
        var fatigue: Int
        var contact: Double
        var power: Double
        var discipline: Double
        var speed: Double
        var defense: Double
        var arm: Double
        var lifecycleData: Data? = nil
        var createdAt: Date
        @Relationship(deleteRule: .cascade) var pitches: [PitchMastery]

        init(draft: PlayerDraft, school: School) {
            id = UUID()
            roleRaw = draft.role.rawValue
            name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            jerseyNumber = Int(draft.jerseyNumber) ?? 1
            schoolID = school.id
            schoolName = school.name
            positionRaw = draft.position.rawValue
            throwingHandRaw = draft.throwingHand.rawValue
            skin = draft.appearance.skin
            hair = draft.appearance.hair
            kit = draft.appearance.kit
            hairStyle = draft.appearance.hairStyle
            expression = draft.appearance.expression
            startAge = 16
            gameDate = "2026-04-01"
            fatigue = draft.role == .batter ? 24 : 52
            contact = 65; power = 75; discipline = 60
            speed = draft.role == .batter ? 72 : 55
            defense = draft.role == .batter ? 65 : 60
            arm = draft.role == .batter ? 68 : 70
            createdAt = Date()
            pitches = draft.role == .pitcher ? [
                PitchMastery(code: "four-seam", name: "포심", mastery: 72, order: 0),
                PitchMastery(code: "slider", name: "슬라이더", mastery: 65, order: 1),
                PitchMastery(code: "changeup", name: "체인지업", mastery: 48, order: 2),
                PitchMastery(code: "fork", name: "포크", mastery: 35, order: 3)
            ] : []
        }
        var lifecycle: CareerLifecycleState {
            get throws {
                let value = try lifecycleData.map {try JSONDecoder().decode(CareerLifecycleState.self,from:$0)} ?? CareerLifecycleState()
                try value.validate(playerID:id,today:gameDate)
                return value
            }
        }
        var isRetired: Bool { (try? lifecycle.retirement) != nil }
        var role: PlayerRole { PlayerRole(rawValue: roleRaw) ?? .batter }
        var appearance: PlayerAppearance {
            PlayerAppearance(skin: skin, hair: hair, kit: kit, hairStyle: hairStyle, expression: expression)
        }
        var roleDetail: String {
            role == .batter ? (FieldPosition(rawValue: positionRaw)?.label ?? positionRaw)
                : (ThrowingHand(rawValue: throwingHandRaw)?.label ?? throwingHandRaw)
        }
    }

    @Model final class ActiveCareerSlot {
        @Attribute(.unique) var roleRaw:String
        @Attribute(.unique) var playerID:UUID
        init(role:PlayerRole,playerID:UUID) {roleRaw=role.rawValue;self.playerID=playerID}
    }
}
typealias ActiveCareerSlot = CareerSchemaV15.ActiveCareerSlot

typealias CareerPitchMastery = CareerSchemaV15.PitchMastery
typealias CareerPlayer = CareerSchemaV15.Player

enum CareerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CareerSchemaV1.self, CareerSchemaV2.self, CareerSchemaV3.self, CareerSchemaV4.self, CareerSchemaV5.self, CareerSchemaV6.self, CareerSchemaV7.self, CareerSchemaV8.self, CareerSchemaV9.self, CareerSchemaV10.self, CareerSchemaV11.self, CareerSchemaV12.self, CareerSchemaV13.self, CareerSchemaV14.self, CareerSchemaV15.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: CareerSchemaV1.self, toVersion: CareerSchemaV2.self),
         .lightweight(fromVersion: CareerSchemaV2.self, toVersion: CareerSchemaV3.self),
         .lightweight(fromVersion: CareerSchemaV3.self, toVersion: CareerSchemaV4.self),
         .lightweight(fromVersion: CareerSchemaV4.self, toVersion: CareerSchemaV5.self),
         .lightweight(fromVersion: CareerSchemaV5.self, toVersion: CareerSchemaV6.self),
         .lightweight(fromVersion: CareerSchemaV6.self, toVersion: CareerSchemaV7.self),
         .lightweight(fromVersion: CareerSchemaV7.self, toVersion: CareerSchemaV8.self),
         .lightweight(fromVersion: CareerSchemaV8.self, toVersion: CareerSchemaV9.self),
         .lightweight(fromVersion: CareerSchemaV9.self, toVersion: CareerSchemaV10.self),
         .lightweight(fromVersion: CareerSchemaV10.self, toVersion: CareerSchemaV11.self),
         .lightweight(fromVersion: CareerSchemaV11.self, toVersion: CareerSchemaV12.self),
         .lightweight(fromVersion: CareerSchemaV12.self, toVersion: CareerSchemaV13.self),
         .lightweight(fromVersion: CareerSchemaV13.self, toVersion: CareerSchemaV14.self),
         .lightweight(fromVersion: CareerSchemaV14.self, toVersion: CareerSchemaV15.self)]
    }
}
