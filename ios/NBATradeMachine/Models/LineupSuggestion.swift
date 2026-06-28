import Foundation

/// Output model for `LineupNarrator` — the layered written analysis the lineup
/// breakdown renders: `basic` headlines (always visible) + per-category `detail`
/// items (expandable grade / tags / explanation). Plain value types, built
/// in-app from the already-computed `LineupLabel` + player features; not fetched
/// or decoded.
struct LineupSuggestionReport: Equatable {
    /// Ranked plain-language headlines (the default, always-visible list).
    let basic: [SuggestionLine]
    /// Per-category detail items, keyed by category ("offense", "defense",
    /// "tempo", "structure"). Render order is fixed by `SuggestionCategory.order`.
    let detail: [String: [SuggestionDetail]]
}

/// A single basic-layer headline (e.g. "Clogged paint — Jalen Johnson doesn't
/// stretch it"). `confidence` ("high"/"medium"/"low") drives the tentative marker.
struct SuggestionLine: Equatable, Hashable {
    let key: String
    let category: String
    let text: String
    let salience: Double?
    let confidence: String?
}

/// A detail-layer item: the grade, tags, player+stat evidence, and the longer
/// written explanation shown under the expandable section.
struct SuggestionDetail: Equatable, Hashable {
    let key: String
    let category: String
    let grade: String?
    let confidence: String?
    let salience: Double?
    let tags: [String]?
    let evidence: [SuggestionEvidence]?
    let suggestion: String?
    let explanation: String?
}

/// A named piece of supporting evidence ("Jalen Johnson — 3PT% — 31%").
struct SuggestionEvidence: Equatable, Hashable {
    let player: String?
    let stat: String?
    let value: String?
    let pct: String?
    let sample: String?
}

/// The canonical render order + display titles for the `detail` categories.
enum SuggestionCategory {
    /// Fixed display order; categories absent from a report are skipped.
    static let order: [String] = ["offense", "defense", "tempo", "structure"]

    static func title(_ key: String) -> String {
        switch key {
        case "offense": return "Offense"
        case "defense": return "Defense"
        case "tempo": return "Tempo"
        case "structure": return "Structure"
        default: return key.capitalized
        }
    }
}
