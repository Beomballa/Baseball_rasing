import Foundation

enum PlayerTrait: String, Codable, CaseIterable, Identifiable {
    case strongArm = "strong-arm", cheetah, safeHands = "safe-hands"
    var id: String { rawValue }
    var label: String { switch self { case .strongArm: "강견"; case .cheetah: "치타"; case .safeHands: "안정 포구" } }
    var effect: String {
        switch self {
        case .strongArm: "강한 송구로 주자의 진루를 막습니다. 송구 속도 +5%"
        case .cheetah: "빠른 첫발로 주루와 수비에서 먼저 움직입니다. 출발 지연 −8%"
        case .safeHands: "타구를 안정적으로 처리해 다음 플레이로 연결합니다. 공 확보 시간 −10%"
        }
    }
    var condition: String { switch self { case .strongArm: "송구 60 이상"; case .cheetah: "스피드 60 이상"; case .safeHands: "수비 50 이상" } }
    func qualifies(speed: Double, defense: Double, arm: Double) -> Bool {
        switch self { case .strongArm: arm >= 60; case .cheetah: speed >= 60; case .safeHands: defense >= 50 }
    }
}

struct TraitLoadout: Codable, Equatable {
    let owned: [PlayerTrait]
    var active: [PlayerTrait]
    func validate() throws {
        guard Self.valid(owned), Self.valid(active), active.allSatisfy(owned.contains) else { throw TraitError.invalidRecord }
    }
    static func valid(_ list: [PlayerTrait]) -> Bool { list.count <= 3 && Set(list).count == list.count }
    static func initial(speed: Double, defense: Double, arm: Double, choose: (Int) -> Int = { Int.random(in: 0..<$0) }) throws -> Self {
        let eligible = PlayerTrait.allCases.filter { $0.qualifies(speed: speed, defense: defense, arm: arm) }
        guard !eligible.isEmpty else { return Self(owned: [], active: []) }
        let index = choose(eligible.count)
        guard eligible.indices.contains(index) else { throw TraitError.invalidRecord }
        return Self(owned: [eligible[index]], active: [eligible[index]])
    }
}

enum TraitError: LocalizedError {
    case invalidRecord, locked, stale, notOwned
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "특성 정보를 확인할 수 없습니다. 기존 저장은 유지합니다."
        case .locked: "훈련·휴식·경기 시작 후에는 특성을 바꿀 수 없습니다. 다음 날 준비 전에 변경해 주세요."
        case .stale: "날짜나 특성 구성이 바뀌었습니다. 최신 상태를 다시 확인해 주세요."
        case .notOwned: "보유한 특성만 최대 3개 활성화할 수 있습니다."
        }
    }
}
