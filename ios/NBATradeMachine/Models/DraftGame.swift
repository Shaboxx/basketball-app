import Foundation

/// One entry in the Games hub. Static in code (see `DraftGameRegistry`); `id` is
/// both the stable identity AND the settings-cache key suffix.
nonisolated struct DraftGame: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String        // one line
    let systemImage: String
    let availability: GameAvailability
    let capabilities: SetupCapabilities

    static func == (lhs: DraftGame, rhs: DraftGame) -> Bool { lhs.id == rhs.id }
}

/// The user's last-used setup for one game. Persisted by `GameSetupStore` under
/// `gameSetup.v1.<gameId>`. Forgiving decode: an older blob missing any newer
/// field decodes to that field's default (defaults = 2 humans / 0 CPUs / local).
nonisolated struct GameSetupSettings: Codable, Equatable {
    var humanCount: Int
    var cpuCount: Int
    var playMode: PlayMode

    static let `default` = GameSetupSettings(humanCount: 2, cpuCount: 0, playMode: .localFriends)

    init(humanCount: Int, cpuCount: Int, playMode: PlayMode) {
        self.humanCount = humanCount
        self.cpuCount = cpuCount
        self.playMode = playMode
    }

    enum CodingKeys: String, CodingKey { case humanCount, cpuCount, playMode }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        humanCount = try c.decodeIfPresent(Int.self, forKey: .humanCount) ?? Self.default.humanCount
        cpuCount = try c.decodeIfPresent(Int.self, forKey: .cpuCount) ?? Self.default.cpuCount
        playMode = try c.decodeIfPresent(PlayMode.self, forKey: .playMode) ?? Self.default.playMode
    }
}
