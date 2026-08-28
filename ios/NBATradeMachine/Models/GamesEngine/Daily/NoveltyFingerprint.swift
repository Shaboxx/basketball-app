import Foundation

/// A stable structural fingerprint of a challenge definition (spec §29). Used to
/// detect near-duplicate daily/weekly variants so the generator can re-roll for
/// DEVICE-LOCAL variety (the store keeps a small ring buffer). Because a
/// dictionary-ordered encode would fingerprint the SAME definition differently
/// across runs (risk §130), the encoder is pinned to `.sortedKeys`.
nonisolated enum NoveltyFingerprint {

    /// Deterministic FNV-1a-64 over the sorted-key JSON of the launch payload.
    /// The same definition always yields the same short hex string.
    static func fingerprint(_ launch: GameLaunch) -> String {
        let canonical = canonicalBytes(launch)
        return fnv1aHex(canonical)
    }

    /// Sorted-key JSON of the definition inside a launch (stable across runs). A
    /// `.none` launch (unreachable for a generated challenge) fingerprints as a
    /// fixed sentinel.
    static func canonicalBytes(_ launch: GameLaunch) -> [UInt8] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data: Data
        switch launch {
        case .roster(let d):         data = (try? enc.encode(d)) ?? Data()
        case .classification(let d): data = (try? enc.encode(d)) ?? Data()
        case .compare(let d):        data = (try? enc.encode(d)) ?? Data()
        case .bracket(let d):        data = (try? enc.encode(d)) ?? Data()
        case .none:                  data = Data("none".utf8)
        }
        // Prefix a family tag so two families that happen to encode alike never
        // collide.
        let tag: String
        switch launch {
        case .roster:         tag = "r|"
        case .classification: tag = "c|"
        case .compare:        tag = "h|"
        case .bracket:        tag = "b|"
        case .none:           tag = "n|"
        }
        return Array(tag.utf8) + Array(data)
    }

    /// FNV-1a-64 as a zero-padded 16-char hex string.
    static func fnv1aHex(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for b in bytes {
            hash ^= UInt64(b)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }

    /// FNV-1a-64 of a string (used for the canonical challenge seed).
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for b in string.utf8 {
            hash ^= UInt64(b)
            hash = hash &* prime
        }
        return hash
    }
}
