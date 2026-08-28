import Foundation

/// A user-authored, locally-persisted custom game (Sol B1). Versioned so a future
/// schema growth decodes forward-compatibly (`decodeIfPresent` + defaults). The
/// family-specific payload is a full engine Definition, so a saved draft
/// dispatches through the SAME `GameLauncher`/gameplay views as a shipped preset
/// (`toLaunch()`), no registry entry required.
nonisolated struct GameDraft: Codable, Equatable, Identifiable {

    /// The bundled definition for one engine family. Hand-Codable (tagged union)
    /// so the encoded form is small + forward-compatible.
    nonisolated enum Payload: Codable, Equatable {
        case roster(GameDefinition)
        case classification(ClassificationDefinition)
        case compare(CompareDefinition)
        case bracket(BracketDefinition)

        var family: CreatorOptions.EngineFamily {
            switch self {
            case .roster:         return .roster
            case .classification: return .classification
            case .compare:        return .compare
            case .bracket:        return .bracket
            }
        }

        private enum CodingKeys: String, CodingKey { case family, roster, classification, compare, bracket }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let fam = try c.decode(CreatorOptions.EngineFamily.self, forKey: .family)
            switch fam {
            case .roster:
                self = .roster(try c.decode(GameDefinition.self, forKey: .roster))
            case .classification:
                self = .classification(try c.decode(ClassificationDefinition.self, forKey: .classification))
            case .compare:
                self = .compare(try c.decode(CompareDefinition.self, forKey: .compare))
            case .bracket:
                self = .bracket(try c.decode(BracketDefinition.self, forKey: .bracket))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(family, forKey: .family)
            switch self {
            case .roster(let d):         try c.encode(d, forKey: .roster)
            case .classification(let d): try c.encode(d, forKey: .classification)
            case .compare(let d):        try c.encode(d, forKey: .compare)
            case .bracket(let d):        try c.encode(d, forKey: .bracket)
            }
        }
    }

    /// Current on-disk schema version (bump on any breaking payload change).
    static let currentSchemaVersion = 1

    let id: String              // uuid
    let createdAt: Date
    let schemaVersion: Int
    let title: String
    let payload: Payload

    var family: CreatorOptions.EngineFamily { payload.family }

    init(id: String = UUID().uuidString, createdAt: Date = Date(),
         schemaVersion: Int = GameDraft.currentSchemaVersion,
         title: String, payload: Payload) {
        self.id = id
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
        self.title = title
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey { case id, createdAt, schemaVersion, title, payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        title = try c.decode(String.self, forKey: .title)
        payload = try c.decode(Payload.self, forKey: .payload)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(title, forKey: .title)
        try c.encode(payload, forKey: .payload)
    }

    /// Dispatch a saved draft exactly like a preset — the setup/hub layer switches
    /// on this the same way it switches on `GameLauncher.resolve`.
    func toLaunch() -> GameLaunch {
        switch payload {
        case .roster(let d):         return .roster(d)
        case .classification(let d): return .classification(d)
        case .compare(let d):        return .compare(d)
        case .bracket(let d):        return .bracket(d)
        }
    }
}
