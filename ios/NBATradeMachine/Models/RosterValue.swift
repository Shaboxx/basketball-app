import Foundation

/// SP-A per-player marginal roster value, merged into players/{slug}.rosterValue by
/// scripts/upload_roster_value.py. `byTeam` maps a tricode -> the player's marginal value to that team
/// (the snapshot is own-team only, so it holds the player's own team).
nonisolated struct RosterValue: Codable, Equatable, Hashable {
    let ownTeam: String?
    let byTeam: [String: Double]

    enum CodingKeys: String, CodingKey { case ownTeam, byTeam }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownTeam = try c.decodeIfPresent(String.self, forKey: .ownTeam)
        byTeam = try c.decodeIfPresent([String: Double].self, forKey: .byTeam) ?? [:]
    }
    init(ownTeam: String?, byTeam: [String: Double]) { self.ownTeam = ownTeam; self.byTeam = byTeam }

    /// Marginal value to `tricode` (the snapshot holds the player's own team).
    func value(for tricode: String) -> Double? { byTeam[tricode] }
}
