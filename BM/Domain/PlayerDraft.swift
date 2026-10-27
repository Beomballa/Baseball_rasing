import Foundation

enum PlayerRole: String, Codable, CaseIterable, Identifiable {
    case batter, pitcher
    var id: String { rawValue }
    var label: String { self == .batter ? "타자" : "투수" }
}

enum FieldPosition: String, Codable, CaseIterable, Identifiable {
    case catcher = "C", first = "1B", second = "2B", third = "3B", shortstop = "SS", left = "LF", center = "CF", right = "RF"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .catcher: "포수"
        case .first: "1루수"
        case .second: "2루수"
        case .third: "3루수"
        case .shortstop: "유격수"
        case .left: "좌익수"
        case .center: "중견수"
        case .right: "우익수"
        }
    }
}

enum ThrowingHand: String, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var label: String { self == .right ? "우투" : "좌투" }
}

struct PlayerAppearance: Equatable, Codable {
    var skin = 0
    var hair = 0
    var kit = 0
    var hairStyle = 0
    var expression = 0
    static let skinColors = [0xefbe91, 0xc88d62, 0x895739, 0xf7d5b2, 0xb5764c, 0x65432f]
    static let hairColors = [0x242b35, 0x68432e, 0xa9743f, 0x3e303a, 0xc6a368, 0x8f949c]
    static let kitColors = [0x214e72, 0x226e55, 0x80464b, 0x654d86, 0x9c6234, 0x43525f]
    var isValid: Bool {
        (0..<6).contains(skin) && (0..<6).contains(hair) && (0..<6).contains(kit)
        && (0..<3).contains(hairStyle) && (0..<3).contains(expression)
    }
}

struct PlayerDraft {
    var name = ""
    var jerseyNumber = "1"
    var role: PlayerRole = .batter
    var archetype: PlayerArchetype?
    var selectedArchetype: PlayerArchetype { archetype ?? .initial(for: role) }
    var isCustom = false
    var allocation: PlayerStatAllocation?
    static let defaultPitchCodes = ["four-seam", "slider", "changeup", "fork"]
    var pitchCodes: [String]?
    var selectedPitchCodes: [String] { role == .pitcher ? pitchCodes ?? Self.defaultPitchCodes : [] }
    var initialValues: PlayerInitialValues {
        var values = isCustom ? allocation?.values ?? selectedArchetype.values : selectedArchetype.values
        if role == .pitcher {
            let original = values.pitches
            values.pitches = selectedPitchCodes.reduce(into: [:]) { result, code in
                guard let pitch = PitchType(rawValue: code) else { return }
                result[code] = original[code] ?? pitch.initialMastery
            }
        }
        return values
    }
    var schoolID = ""
    var position: FieldPosition = .center
    var throwingHand: ThrowingHand = .right
    var appearance = PlayerAppearance()

    func validate(schools: [School]) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 12,
              !cleanName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CreationError.invalidName
        }
        guard jerseyNumber.range(of: "^[0-9]{1,2}$", options: .regularExpression) != nil,
              let number = Int(jerseyNumber), (0...99).contains(number) else { throw CreationError.invalidNumber }
        guard schools.contains(where: { $0.id == schoolID }) else { throw CreationError.invalidSchool }
        guard appearance.isValid else { throw CreationError.invalidAppearance }
        guard selectedArchetype.role == role else { throw CreationError.invalidArchetype }
        if isCustom {
            guard let allocation, allocation.role == role, allocation.isValid else { throw CreationError.invalidAllocation }
        }
        if role == .pitcher {
            guard (3...5).contains(selectedPitchCodes.count), Set(selectedPitchCodes).count == selectedPitchCodes.count,
                  selectedPitchCodes.allSatisfy({ PitchType(rawValue: $0) != nil }) else { throw CreationError.invalidPitches }
        }
    }
}

enum CreationError: LocalizedError {
    case invalidName, invalidNumber, invalidSchool, invalidAppearance, invalidArchetype, invalidAllocation, invalidPitches, roleAlreadyExists
    var errorDescription: String? {
        switch self {
        case .invalidName: "이름은 공백만 입력할 수 없으며 1~12자로 입력해 주세요."
        case .invalidNumber: "등번호는 0~99 사이의 숫자로 입력해 주세요."
        case .invalidSchool: "소속 학교를 선택해 주세요."
        case .invalidAppearance: "외형 선택을 다시 확인해 주세요."
        case .invalidArchetype: "선수 역할에 맞는 유형을 선택해 주세요."
        case .invalidAllocation: "사용자 지정 능력치를 0~100 범위에서 남은 포인트 없이 배분해 주세요."
        case .invalidPitches: "서로 다른 구종을 3~5개 선택해 주세요."
        case .roleAlreadyExists: "이미 해당 역할의 선수가 있습니다. 홈에서 확인해 주세요."
        }
    }
}
