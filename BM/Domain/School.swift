import Foundation

struct School: Codable, Identifiable, Hashable {
    let id: String
    let region: String
    let name: String
}

enum SchoolCatalog {
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
