import Foundation

/// Persistence for user-authored games behind an interface (Sol B1) so a later
/// Firestore-backed share/publish impl conforms to the SAME protocol with no
/// call-site changes. `load` returns the saved drafts (newest first by
/// convention); `save` upserts by id; `delete` removes by id.
nonisolated protocol GameDefinitionRepository {
    func load() -> [GameDraft]
    func save(_ draft: GameDraft)
    func delete(id: String)
}

/// Local (UserDefaults-backed) repository. Stores the whole draft array as one
/// JSON blob under the versioned key `gameDrafts.v1`, with an injectable
/// `defaults` seam (mirrors `GameSetupStore`). No Firestore, no network.
nonisolated final class LocalGameDefinitionRepository: GameDefinitionRepository {

    static let storageKey = "gameDrafts.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = LocalGameDefinitionRepository.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [GameDraft] {
        // Newest first (stable, deterministic ordering for the list UI).
        decodeSurvivors().sorted { $0.createdAt > $1.createdAt }
    }

    /// Sol fix 5: decode array elements INDEPENDENTLY so ONE corrupt draft loses
    /// only itself, not the whole library. The blob is first decoded to a lenient
    /// array of raw JSON elements; each is then `try?`-decoded to `GameDraft`, keeping
    /// survivors and skipping only the malformed. Returns [] when there's no data or
    /// the outer container isn't even a JSON array.
    private func decodeSurvivors() -> [GameDraft] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let raw = try? JSONDecoder().decode([RawJSON].self, from: data) else {
            return []
        }
        return raw.compactMap { element in
            guard let bytes = try? JSONEncoder().encode(element) else { return nil }
            return try? JSONDecoder().decode(GameDraft.self, from: bytes)
        }
    }

    func save(_ draft: GameDraft) {
        guard var drafts = mutableSnapshot() else { return }   // fix 5: don't clobber
        if let idx = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[idx] = draft        // upsert
        } else {
            drafts.append(draft)
        }
        persist(drafts)
    }

    func delete(id: String) {
        guard var drafts = mutableSnapshot() else { return }   // fix 5: don't clobber
        drafts.removeAll { $0.id == id }
        persist(drafts)
    }

    /// The current drafts to mutate for a save/delete, or nil to ABORT the write.
    /// Sol fix 5: if raw data is present but decodes to ZERO survivors (a total-decode
    /// failure), returning nil preserves the on-disk bytes instead of overwriting good
    /// (but momentarily unreadable) data with a truncated set. When there's no data
    /// at all, an empty array is a legitimate starting point.
    private func mutableSnapshot() -> [GameDraft]? {
        let survivors = decodeSurvivors()
        if survivors.isEmpty, defaults.data(forKey: key) != nil {
            return nil    // present-but-unreadable: quarantine, don't truncate
        }
        return survivors
    }

    private func persist(_ drafts: [GameDraft]) {
        if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: key)
        }
    }
}

/// A permissive JSON value used ONLY to split a stored draft array into its
/// elements so each can be decoded independently (Sol fix 5). It round-trips any
/// JSON element byte-for-structure so a survivor re-encodes to valid `GameDraft`
/// JSON; malformed elements simply fail the subsequent `GameDraft` decode.
private nonisolated enum RawJSON: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([RawJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: RawJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let b):   try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
