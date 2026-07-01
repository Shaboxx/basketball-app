import Foundation

/// The preset scoring format. String-rawValue / `Identifiable` / `Codable` /
/// `CaseIterable` (mirrors `SeasonMode`), with PURE nonisolated mapping accessors.
/// The mapping is a typed SWITCH over the decoded model, NOT a flat rawValue path:
/// `pointsEspn`/`pointsYahoo` are NESTED one level deeper than the category formats.
nonisolated enum FantasyFormat: String, CaseIterable, Identifiable, Codable {
    case nineCat, eightCat, roto, pointsEspn, pointsYahoo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nineCat:     return "9-Cat"
        case .eightCat:    return "8-Cat"
        case .roto:        return "Roto"
        case .pointsEspn:  return "Points (ESPN)"
        case .pointsYahoo: return "Points (Yahoo)"
        }
    }

    var isPoints: Bool { self == .pointsEspn || self == .pointsYahoo }

    /// Resolve this format's value/rank/fpPerGame from a decoded doc. Category
    /// formats live at `formats.X` (fpPerGame nil); points formats live one level
    /// deeper at `formats.points.espn`/`.yahoo` (fpPerGame set).
    func entry(in fv: FantasyValue) -> (value: Double, rank: Int?, fpPerGame: Double?) {
        switch self {
        case .nineCat:     return (fv.formats.nineCat.value,  fv.formats.nineCat.rank,  nil)
        case .eightCat:    return (fv.formats.eightCat.value, fv.formats.eightCat.rank, nil)
        case .roto:        return (fv.formats.roto.value,     fv.formats.roto.rank,     nil)
        case .pointsEspn:  return (fv.formats.points.espn.value,  fv.formats.points.espn.rank,  fv.formats.points.espn.fpPerGame)
        case .pointsYahoo: return (fv.formats.points.yahoo.value, fv.formats.points.yahoo.rank, fv.formats.points.yahoo.fpPerGame)
        }
    }

    /// The replacement value for this format from `_meta` (NESTED for points).
    func replacement(in meta: FantasyMeta) -> Double {
        switch self {
        case .nineCat:     return meta.replacement.nineCat
        case .eightCat:    return meta.replacement.eightCat
        case .roto:        return meta.replacement.roto
        case .pointsEspn:  return meta.replacement.points.espn
        case .pointsYahoo: return meta.replacement.points.yahoo
        }
    }
}
