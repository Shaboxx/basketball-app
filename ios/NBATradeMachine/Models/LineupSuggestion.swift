import Foundation

/// Decodes `T` if possible, else nil — lets a single malformed element be dropped
/// instead of failing the whole array/map decode. Keeps one bad lineup (or one bad
/// headline) from erasing an entire team's analysis if the backend schema ever drifts.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// The backend-generated written lineup analysis, read from the
/// `lineupSuggestions/{teamId}` Firestore collection (written by
/// `scripts/upload_lineup_suggestions.py` from `compute_lineup_suggestions.py`).
///
/// One document per team holds a `lineups` map keyed by `lineupId` — the five
/// players' NBA ids sorted lexically and joined with "-". The Swift side
/// reconstructs that key from a lineup's `Player.nbaId`s (see
/// `LineupSuggestionMatching`) to pull the matching report.
///
/// Only the prose layer (`basic` headlines + `detail` explanations) is modeled
/// here; the archetype / tags / formations the report also carries are already
/// rendered client-side by `LineupLabeler`, so they are intentionally ignored
/// (Codable drops unmodeled keys). Every analysis field is optional so a thin or
/// older report decodes cleanly rather than failing the whole document.
struct LineupSuggestionsDoc: Codable, Equatable {
    let teamId: String
    let season: String?
    let lineups: [String: LineupSuggestionReport]

    enum CodingKeys: String, CodingKey { case teamId, season, lineups }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = try c.decode(String.self, forKey: .teamId)
        season = try c.decodeIfPresent(String.self, forKey: .season)
        // Lossy per-report decode: a single un-decodable lineup is dropped, not
        // allowed to fail the whole team doc (which would lose ALL its analysis).
        let raw = (try? c.decode([String: Lossy<LineupSuggestionReport>].self, forKey: .lineups)) ?? [:]
        lineups = raw.compactMapValues(\.value)
    }

    init(teamId: String, season: String?, lineups: [String: LineupSuggestionReport]) {
        self.teamId = teamId
        self.season = season
        self.lineups = lineups
    }
}

/// One lineup's written analysis: the always-visible `basic` headlines and the
/// per-category `detail` items shown under the expandable section.
struct LineupSuggestionReport: Codable, Equatable {
    /// Ranked plain-language headlines (the default, always-visible list).
    let basic: [SuggestionLine]
    /// Per-category detail items, keyed by category ("offense", "defense",
    /// "tempo", "structure"). Render order is fixed by `SuggestionCategory.order`.
    let detail: [String: [SuggestionDetail]]

    enum CodingKeys: String, CodingKey { case basic, detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Per-element lossy decode: one malformed headline / detail item is dropped
        // rather than wiping the whole list (a coarse array-level `try?` would).
        basic = ((try? c.decode([Lossy<SuggestionLine>].self, forKey: .basic)) ?? [])
            .compactMap(\.value)
        let rawDetail = (try? c.decode([String: [Lossy<SuggestionDetail>]].self, forKey: .detail)) ?? [:]
        detail = rawDetail.mapValues { $0.compactMap(\.value) }
    }

    /// Memberwise init kept for tests / previews (the decoder init suppresses the
    /// synthesized one).
    init(basic: [SuggestionLine], detail: [String: [SuggestionDetail]]) {
        self.basic = basic
        self.detail = detail
    }
}

/// A single basic-layer headline (e.g. "Run clogged paint — park Jalen Johnson in
/// the dunker spot"). `confidence` reflects the engine's conservative-negative
/// gating ("high" / "medium" / "low").
struct SuggestionLine: Codable, Equatable, Hashable {
    let key: String
    let category: String
    let text: String
    let salience: Double?
    let confidence: String?
}

/// A detail-layer item: the grade, fan-vernacular tags, player+stat evidence, and
/// the longer written explanation shown under the expandable section.
struct SuggestionDetail: Codable, Equatable, Hashable {
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

/// A named piece of supporting evidence ("Jalen Johnson — corner 3 — 11th"). All
/// fields optional; `sample` is often null for tendency observations.
struct SuggestionEvidence: Codable, Equatable, Hashable {
    let player: String?
    let stat: String?
    let value: String?
    let pct: String?
    let sample: String?
}

/// Reconstructs the backend `lineupId` so a lineup of `Player`s can be matched to
/// its report. The backend key is `"-".join(sorted(str(player_id) for ...))` —
/// the five NBA ids sorted lexically and joined with "-". Swift's `String.sorted()`
/// matches Python's lexical sort for the pure-digit id strings.
enum LineupSuggestionMatching {
    /// The lineupId for these players, or nil if any player lacks an `nbaId`
    /// (an incomplete key would risk a wrong match — abstain instead).
    static func lineupId(for players: [Player]) -> String? {
        let ids = players.compactMap { $0.nbaId }.filter { !$0.isEmpty }
        guard ids.count == players.count, !ids.isEmpty else { return nil }
        return ids.sorted().joined(separator: "-")
    }

    /// The matching report in `doc` for these players, or nil if the key can't be
    /// built or the team doc has no report for it.
    static func report(for players: [Player],
                       in doc: LineupSuggestionsDoc) -> LineupSuggestionReport? {
        guard let id = lineupId(for: players) else { return nil }
        return doc.lineups[id]
    }
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
