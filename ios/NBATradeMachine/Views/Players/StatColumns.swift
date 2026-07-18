import SwiftUI

/// A single column definition for the stats-history table.
/// The accessor is `@Sendable` so it can be stored in a `nonisolated` context
/// without inheriting `@MainActor` isolation from the target's default isolation.
struct StatColumn {
    let title: String
    let direction: StatDirection
    /// Accessor from a season row to the Double value (nil = dash).
    let value: @Sendable (PlayerSeasonHistory.SeasonRow) -> Double?
}

/// Pure helpers for the stats-history table — nonisolated so they can be
/// called freely in this @MainActor-default target.
nonisolated enum StatColumns {

    // MARK: — Season label

    /// Shortens "2024-25" to "24-25". Returns the input verbatim if it
    /// doesn't match the expected 7-character "20xx-xx" shape.
    static func shortSeason(_ season: String) -> String {
        // Expect exactly 7 chars: "20xx-xx"
        guard season.count == 7,
              season.hasPrefix("20"),
              season.dropFirst(4).hasPrefix("-")
        else { return season }
        let startIndex = season.index(season.startIndex, offsetBy: 2)
        return String(season[startIndex...])
    }

    // MARK: — Number formatting

    /// Formats an optional Double. Returns "—" when nil.
    static func fmt(_ v: Double?, decimals: Int = 1) -> String {
        guard let v else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }

    // MARK: — Cell color

    /// Maps a StatCell to its display Color.
    static func color(for cell: StatCell) -> Color {
        switch cell {
        case .up:      return .green
        case .down:    return .red
        case .injury:  return .yellow
        case .neutral: return .primary
        case .dash:    return .secondary
        }
    }

    // MARK: — Box columns

    /// Box-score column definitions (season rows).
    static let boxColumns: [StatColumn] = [
        StatColumn(title: "MIN",  direction: .higherBetter) { $0.min },
        StatColumn(title: "PTS",  direction: .higherBetter) { $0.box.pts },
        StatColumn(title: "REB",  direction: .higherBetter) { $0.box.reb },
        StatColumn(title: "AST",  direction: .higherBetter) { $0.box.ast },
        StatColumn(title: "STL",  direction: .higherBetter) { $0.box.stl },
        StatColumn(title: "BLK",  direction: .higherBetter) { $0.box.blk },
        StatColumn(title: "TOV",  direction: .lowerBetter)  { $0.box.tov },
        StatColumn(title: "FG%",  direction: .higherBetter) { $0.box.fgPct },
        StatColumn(title: "3P%",  direction: .higherBetter) { $0.box.fg3Pct },
        StatColumn(title: "FT%",  direction: .higherBetter) { $0.box.ftPct },
    ]

    // MARK: — Advanced (season) columns

    /// Advanced-stats column definitions (season rows).
    /// TRB/G reads from box.reb; ORB/G from advanced.oreb; DRB/G from advanced.dreb.
    static let advancedColumns: [StatColumn] = [
        StatColumn(title: "TS%",    direction: .higherBetter) { $0.advanced.tsPct },
        StatColumn(title: "eFG%",   direction: .higherBetter) { $0.advanced.efgPct },
        StatColumn(title: "USG%",   direction: .higherBetter) { $0.advanced.usgPct },
        StatColumn(title: "NetRtg", direction: .higherBetter) { $0.advanced.netRating },
        StatColumn(title: "PER",    direction: .higherBetter) { $0.advanced.per },
        StatColumn(title: "BPM",    direction: .higherBetter) { $0.advanced.bpm },
        StatColumn(title: "AST%",   direction: .higherBetter) { $0.advanced.astPct },
        StatColumn(title: "TRB/G",  direction: .higherBetter) { $0.box.reb },
        StatColumn(title: "ORB/G",  direction: .higherBetter) { $0.advanced.oreb },
        StatColumn(title: "DRB/G",  direction: .higherBetter) { $0.advanced.dreb },
    ]
}
