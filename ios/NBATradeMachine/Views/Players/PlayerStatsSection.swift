import SwiftUI

// MARK: - Route

/// Navigation value for pushing the game-log drill-down.
struct PlayerGameLogRoute: Hashable {
    let slug: String
    let season: String
}

// MARK: - Mode

private enum StatMode: String, CaseIterable {
    case box = "Box"
    case advanced = "Advanced"
}

// MARK: - PlayerStatsSection

/// Card that shows a per-season stats table (Box or Advanced) with a most-recent-game
/// row at the top and season-over-season color coding. Tapping a season row pushes the
/// `PlayerGameLogView` drill-down via `NavigationLink(value:)`.
///
/// Store ownership: `@StateObject` so the section owns its own `PlayerStatsHistoryStore`
/// (the store's init defaults to `FirestoreService.shared`, making it fully self-contained).
/// This avoids adding a global @EnvironmentObject injection site to every PlayerDetailView
/// construction point.
struct PlayerStatsSection: View {
    let player: Player

    @StateObject private var statsStore = PlayerStatsHistoryStore()
    @State private var mode: StatMode = .box

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                modePicker
                    .padding(.bottom, 8)
                tableContent
            }
        } label: {
            Text("Stats").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .task {
            await statsStore.load(slug: player.slug)
        }
    }

    // MARK: - Picker

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(StatMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Table content

    @ViewBuilder
    private var tableContent: some View {
        let phase = statsStore.historyPhaseBySlug[player.slug, default: .idle]
        switch phase {
        case .loading:
            ProgressView().padding()
        case .empty, .failed:
            Text("No season data available")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.vertical, 8)
        case .idle:
            EmptyView()
        case .loaded:
            if let history = statsStore.history(for: player.slug) {
                statsTable(history: history)
            }
        }
    }

    @ViewBuilder
    private func statsTable(history: PlayerSeasonHistory) -> some View {
        let columns = mode == .box ? StatColumns.boxColumns : StatColumns.advancedColumns
        let seasons = history.seasons // already newest-first from the upload pipeline

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                headerRow(columns: columns)

                // Most-recent game row (from the current-season game log)
                if let newestSeason = seasons.first {
                    recentGameRow(columns: columns, season: newestSeason)
                }

                // One row per season (newest first)
                ForEach(Array(seasons.enumerated()), id: \.element.season) { idx, row in
                    let prevRow = (idx + 1) < seasons.count ? seasons[idx + 1] : nil
                    let thisComparable = StatComparison.isSeasonComparable(
                        gp: row.gp,
                        injuryWindowDays: row.injuryWindowDays
                    )
                    let prevComparable = prevRow.map {
                        StatComparison.isSeasonComparable(
                            gp: $0.gp,
                            injuryWindowDays: $0.injuryWindowDays
                        )
                    } ?? false

                    NavigationLink(value: PlayerGameLogRoute(slug: player.slug, season: row.season)) {
                        seasonRowView(
                            columns: columns,
                            row: row,
                            prevRow: prevRow,
                            thisComparable: thisComparable,
                            prevComparable: prevComparable
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                }
            }
        }
    }

    // MARK: - Header row

    private func headerRow(columns: [StatColumn]) -> some View {
        HStack(spacing: 0) {
            // Season label column
            Text("Season")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
                .padding(.horizontal, 4)

            // GP column
            Text("GP")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, 2)

            ForEach(columns, id: \.title) { col in
                Text(col.title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth(col.title), alignment: .trailing)
                    .padding(.horizontal, 2)
            }

            // Chevron spacer
            Spacer().frame(width: 16)
        }
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
    }

    // MARK: - Recent game row

    @ViewBuilder
    private func recentGameRow(columns: [StatColumn], season: PlayerSeasonHistory.SeasonRow) -> some View {
        let logKey = "\(player.slug)/\(season.season)"
        let logPhase = statsStore.seasonPhaseBySlugSeason[logKey, default: .idle]

        let mostRecentGame = statsStore.gameLogs(slug: player.slug, season: season.season)?.games
            .first(where: { !$0.missed })

        HStack(spacing: 0) {
            Text("Last G")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
                .padding(.horizontal, 4)

            // No GP for game row
            Text("—")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, 2)

            if mode == .box {
                ForEach(StatColumns.boxColumns, id: \.title) { col in
                    let gameVal = gameCellValue(col: col, game: mostRecentGame)
                    let avgVal = col.value(season)
                    let cell = (mostRecentGame == nil) ? StatCell.dash
                        : StatComparison.gameCell(col.direction, game: gameVal, seasonAvg: avgVal)
                    Text(StatColumns.fmt(gameVal))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(StatColumns.color(for: cell))
                        .frame(width: columnWidth(col.title), alignment: .trailing)
                        .padding(.horizontal, 2)
                }
            } else {
                // Advanced: TS%, eFG%, GmSc, +/- for the game row
                advancedGameCells(game: mostRecentGame, season: season)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
        }
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill))
        .task {
            if logPhase == .idle || logPhase == .failed {
                await statsStore.loadSeason(slug: player.slug, season: season.season)
            }
        }

        Divider()
    }

    @ViewBuilder
    private func advancedGameCells(game: GameLine?, season: PlayerSeasonHistory.SeasonRow) -> some View {
        let adv = game.flatMap { StatComparison.advancedPerGame($0) }
        let advCols: [(String, StatDirection, Double?, Double?)] = [
            ("TS%",   .higherBetter, adv?.ts.map { $0 * 100 }, season.advanced.tsPct),
            ("eFG%",  .higherBetter, adv?.efg.map { $0 * 100 }, season.advanced.efgPct),
            ("GmSc",  .higherBetter, adv?.gmsc, nil),
            ("+/-",   .higherBetter, game?.plusMinus.map(Double.init), nil),
        ]
        ForEach(advCols, id: \.0) { title, dir, gameVal, avgVal in
            let cell: StatCell = gameVal == nil ? .dash : (avgVal == nil ? .neutral
                : StatComparison.gameCell(dir, game: gameVal, seasonAvg: avgVal))
            Text(StatColumns.fmt(gameVal))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(StatColumns.color(for: cell))
                .frame(width: columnWidth(title), alignment: .trailing)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Season row

    private func seasonRowView(
        columns: [StatColumn],
        row: PlayerSeasonHistory.SeasonRow,
        prevRow: PlayerSeasonHistory.SeasonRow?,
        thisComparable: Bool,
        prevComparable: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Text(StatColumns.shortSeason(row.season))
                .font(.caption2.bold())
                .frame(width: 56, alignment: .leading)
                .padding(.horizontal, 4)

            Text(row.gp.map(String.init) ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, 2)

            ForEach(columns, id: \.title) { col in
                let thisVal = col.value(row)
                let prevVal = prevRow.flatMap { col.value($0) }
                let cell = StatComparison.seasonCell(
                    col.direction,
                    this: thisVal,
                    prev: prevVal,
                    thisComparable: thisComparable,
                    prevComparable: prevComparable
                )
                Text(StatColumns.fmt(thisVal))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(StatColumns.color(for: cell))
                    .frame(width: columnWidth(col.title), alignment: .trailing)
                    .padding(.horizontal, 2)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
        }
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    /// Extract a box stat from a GameLine as a Double for comparison with the season average.
    private func gameCellValue(col: StatColumn, game: GameLine?) -> Double? {
        guard let game else { return nil }
        switch col.title {
        case "MIN": return game.min
        case "PTS": return game.pts.map(Double.init)
        case "REB": return game.reb.map(Double.init)
        case "AST": return game.ast.map(Double.init)
        case "STL": return game.stl.map(Double.init)
        case "BLK": return game.blk.map(Double.init)
        case "TOV": return game.tov.map(Double.init)
        case "FG%":
            guard let fgm = game.fgm, let fga = game.fga, fga > 0 else { return nil }
            return Double(fgm) / Double(fga) * 100
        case "3P%":
            guard let fg3m = game.fg3m, let fg3a = game.fg3a, fg3a > 0 else { return nil }
            return Double(fg3m) / Double(fg3a) * 100
        case "FT%":
            guard let ftm = game.ftm, let fta = game.fta, fta > 0 else { return nil }
            return Double(ftm) / Double(fta) * 100
        default: return nil
        }
    }

    /// Column widths — wider for multi-char titles like "NetRtg", narrower for "GP".
    private func columnWidth(_ title: String) -> CGFloat {
        switch title {
        case "NetRtg", "AST%": return 52
        case "TRB/G", "ORB/G", "DRB/G": return 48
        case "GmSc", "+/-":   return 44
        default:               return 42
        }
    }
}
