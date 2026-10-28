import Foundation

struct SchoolEmblem: Codable, Hashable {
    let version: Int
    let style: String
    let motif: String
    let symbol: String
    let glyph: String?
    let palette: [Int]
    let pixels: [String]

    var isValid: Bool {
        version == 1 && (2...10).contains(palette.count) && palette.allSatisfy { (0...0xffffff).contains($0) }
            && pixels.count == 32 && pixels.allSatisfy { row in
                row.utf8.count == 32 && row.utf8.allSatisfy { $0 >= 48 && Int($0 - 48) < palette.count }
            }
    }
}

struct School: Codable, Identifiable, Hashable {
    let id: String
    let region: String
    let name: String
    var locality: String? = nil
    var emblem: SchoolEmblem? = nil

    var locationLabel: String { locality.map { region + " · " + $0 } ?? region }

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
                (school.name + " " + school.locationLabel).localizedCaseInsensitiveContains($0)
            }
        }
    }

    static func load(bundle: Bundle = .main) throws -> [School] {
        guard let url = bundle.url(forResource: "schools", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let schools = try JSONDecoder().decode([School].self, from: Data(contentsOf: url))
        guard schools.count == 50, Set(schools.map(\.id)).count == 50,
              Set(schools.map(\.name)).count == 50, schools.allSatisfy({ $0.emblem?.isValid != false }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return schools
    }
}

extension CareerPlayer {
    var displaySchoolName: String { SchoolCatalog.displayName(id: schoolID, fallback: schoolName) }
}
