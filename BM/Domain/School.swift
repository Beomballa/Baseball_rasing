import Foundation

struct School: Codable, Identifiable, Hashable {
    let id: String
    let region: String
    let name: String

    // Stable fictional identity; presentation never changes roster strength or saved results.
    var crestNumber: Int { Int(id.replacingOccurrences(of: "hs-ref-", with: "")) ?? 0 }
    var reputation: String {
        let value = (crestNumber * 37 + 11) % 100
        return value >= 84 ? "설정 명문" : value >= 60 ? "설정 강팀" : "도전 학교"
    }
    var openingWorldChampion: Bool { id == "hs-ref-023" }
}

enum SchoolCatalog {
    static let bundled: [School] = (try? load()) ?? []

    static func displayName(id: String?, fallback: String) -> String {
        bundled.first { $0.id == id }?.name ?? fallback
    }
    static func filtered(_ schools: [School], query: String, region: String? = nil) -> [School] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return schools.filter { school in
            (region == nil || school.region == region) && terms.allSatisfy {
                (school.name + " " + school.region).localizedCaseInsensitiveContains($0)
            }
        }
    }

    static func load(bundle: Bundle = .main) throws -> [School] {
        guard let url = bundle.url(forResource: "schools", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let schools = try JSONDecoder().decode([School].self, from: Data(contentsOf: url))
        guard schools.count == 50, Set(schools.map(\.id)).count == 50 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return schools
    }
}

extension CareerPlayer {
    var displaySchoolName: String { SchoolCatalog.displayName(id: schoolID, fallback: schoolName) }
}
