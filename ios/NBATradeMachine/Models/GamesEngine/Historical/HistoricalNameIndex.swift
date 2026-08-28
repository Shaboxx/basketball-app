import Foundation

/// A NORMALIZED offline name index over the distinct-player set — the answer
/// resolution surface for GRID and CONNECTION typeahead (Sol Q1). Normalizes to
/// lowercase, strips diacritics, and drops punctuation/whitespace, so typed input
/// matches regardless of accents (e.g. "jokic" → "Jokić") or "Jr."/suffix drift.
/// Keys on the distinct-player `id` (duplicate NAMES exist; ids don't), so the UI
/// can disambiguate a duplicate name by showing per-candidate context.
///
/// Pure + nonisolated so it's testable off the main actor and reused by both
/// views.
nonisolated enum HistoricalNameIndex {

    /// Normalize a raw name/query: fold diacritics, lowercase, keep only
    /// letters/digits (drops spaces, periods, apostrophes, hyphens). "José Calderón"
    /// and "jose calderon" both normalize to "josecalderon".
    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: .current)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
    }

    /// Build a `normalizedName → [id]` index (a name may map to several ids when
    /// duplicate names exist). Deterministic: id lists are sorted.
    static func build(_ players: [HistoricalPlayerEntity]) -> [String: [String]] {
        var index: [String: [String]] = [:]
        for p in players {
            index[normalize(p.name), default: []].append(p.id)
        }
        for (k, v) in index { index[k] = v.sorted() }
        return index
    }

    /// Resolve a full typed name to candidate ids via exact-normalized match
    /// (empty if none). Callers use substring `contains` for typeahead; this is the
    /// exact-name resolver for disambiguation/tests.
    static func resolve(_ query: String, in index: [String: [String]]) -> [String] {
        index[normalize(query)] ?? []
    }
}
