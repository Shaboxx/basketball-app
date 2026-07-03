import Foundation

/// A person who runs one or more teams in a league. League-scoped (stored inside
/// the `FantasyLeague` blob). Assigning a manager to a team also sets that team's
/// `ownerName` (the single display source shown on the Teams grid).
nonisolated struct FantasyManager: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey { case id, name }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Manager"
    }
}
