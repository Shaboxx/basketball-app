import SwiftUI

// MARK: - Mode (shared with PlayerStatsSection; defined as file-private here to avoid
// re-declaration; the section's enum is also private so no conflict at module scope)

private enum GameLogMode: String, CaseIterable {
    case box = "Box"
    case advanced = "Advanced"
}

// MARK: - PlayerGameLogView

/// Game-by-game drill-down for a single player. Loads all available seasons from
/// `playerGameLogs/{slug}/seasons/{season}` and renders them in a
/// `LazyVStack(pinnedViews: [.sectionHeaders])` so each season-average header sticks
/// as the user scrolls. Jumps to `initialSeason` on first appearance.
struct PlayerGameLogView: View {
    let slug: String
    let initialSeason: String

    @StateObject private var statsStore = PlayerStatsHistoryStore()
    @State private var mode: GameLogMode = .box
    @State private var seasons: [PlayerGameLogSeason] = []
    @State private var isLoading = false

    // Season tints — cycle through a small palette so adjacent seasons are distinguishable
    private static let tints: [Color] = [
        Color(.systemBlue).opacity(0.08),
        Color(.systemPurple).opacity(0.08),
        Color(.systemIndigo).opacity(0.08),
        Color(.systemTeal).opacity(0.08),
        Color(.systemGreen).opacity(0.08),
    ]

    private func tintFor(index: Int) -> Color {
        Self.tints[index % Self.tints.count]
    }

    private func darkTintFor(index: Int) -> Color {
        let base = Self.tints[index % Self.tints.count]
        // Darken by compositing with a small black layer
        return base.opacity(0.6)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker pinned ABOVE the scroll view (not inside it)
            Picker("", selection: $mode) {
                ForEach(GameLogMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if isLoading && seasons.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if seasons.isEmpty {
                ContentUnavailableView(
                    "No game logs",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Game-by-game data is not available for this player yet.")
                )
            } else {
                VStack(spacing: 0) {
                    // Fixed column-label header — always on screen, labeling the stat
                    // columns. The per-season average rows pin directly beneath it.
                    columnLabelHeader
                    Divider()

                    ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(Array(seasons.enumerated()), id: \.element.season) { idx, seasonDoc in
                                Section {
                                    // Game rows
                                    ForEach(seasonDoc.games, id: \.gameId) { game in
                                        gameRow(game: game, season: seasonDoc, tint: tintFor(index: idx))
                                        Divider()
                                            .padding(.leading, 8)
                                    }
                                } header: {
                                    seasonHeader(seasonDoc: seasonDoc, index: idx)
                                        .id(seasonDoc.season)
                                }
                            }
                        }
                    }
                    .task {
                        // Data is loaded by the root `.task` on the VStack below. This
                        // ScrollView only mounts once `seasons` is non-empty, so it's the
                        // right place to jump to the requested season.
                        if seasons.contains(where: { $0.season == initialSeason }) {
                            withAnimation {
                                proxy.scrollTo(initialSeason, anchor: .top)
                            }
                        }
                    }
                }
                }
            }
        }
        .navigationTitle("Game Log")
        .navigationBarTitleDisplayMode(.inline)
        // The data-loading task MUST live on the always-present root, not inside the
        // `else` branch's ScrollView — that branch only mounts after `seasons` is
        // non-empty, which created a deadlock that pinned the page on "No game logs".
        .task { await loadAllSeasons() }
    }

    // MARK: - Fixed column-label header

    /// Advanced mode in the drill-down shows a 4-stat set (matching `advancedHeaderCells`
    /// and `advancedGameCells`), not the full `StatColumns.advancedColumns`.
    private static let advancedColumnTitles = ["TS%", "eFG%", "GmSc", "+/-"]

    /// A non-scrolling row of column titles pinned above the scroll view so the columns
    /// are always labeled. Mirrors the season-header / game-row column layout exactly
    /// (same first-column and GP widths, same per-stat `colWidth`, same order) so each
    /// label sits directly over its values.
    private var columnLabelHeader: some View {
        HStack(spacing: 0) {
            Text("Season")
                .frame(width: 64, alignment: .leading)
                .padding(.leading, 8)
            Text("GP")
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, 2)
            if mode == .box {
                ForEach(StatColumns.boxColumns, id: \.title) { col in
                    Text(col.title)
                        .frame(width: colWidth(col.title), alignment: .trailing)
                        .padding(.horizontal, 2)
                }
            } else {
                ForEach(Self.advancedColumnTitles, id: \.self) { title in
                    Text(title)
                        .frame(width: colWidth(title), alignment: .trailing)
                        .padding(.horizontal, 2)
                }
            }
            Spacer()
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Season header (sticky)

    @ViewBuilder
    private func seasonHeader(seasonDoc: PlayerGameLogSeason, index: Int) -> some View {
        let playedGames = seasonDoc.games.filter { !$0.missed }
        let cols = headerColumns

        HStack(spacing: 0) {
            // Season label
            Text(StatColumns.shortSeason(seasonDoc.season))
                .font(.caption2.bold())
                .frame(width: 64, alignment: .leading)
                .padding(.leading, 8)

            // GP
            Text("\(playedGames.count)")
                .font(.caption2.bold().monospacedDigit())
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, 2)

            if mode == .box {
                ForEach(StatColumns.boxColumns, id: \.title) { col in
                    let avg = seasonAverage(col: col, games: playedGames)
                    Text(StatColumns.fmt(avg))
                        .font(.caption2.bold().monospacedDigit())
                        .frame(width: colWidth(col.title), alignment: .trailing)
                        .padding(.horizontal, 2)
                }
            } else {
                advancedHeaderCells(games: playedGames)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .background(darkTintFor(index: index).opacity(2.5)) // slightly darker than rows
    }

    @ViewBuilder
    private func advancedHeaderCells(games: [GameLine]) -> some View {
        let header = StatComparison.advancedSeasonHeader(games)
        let advHeaderCols: [(String, Double?)] = [
            ("TS%",  header.ts.map { $0 * 100 }),
            ("eFG%", header.efg.map { $0 * 100 }),
            ("GmSc", header.gmsc),
            ("+/-",  averagePlusMinus(games: games)),
        ]
        ForEach(advHeaderCols, id: \.0) { title, val in
            Text(StatColumns.fmt(val))
                .font(.caption2.bold().monospacedDigit())
                .frame(width: colWidth(title), alignment: .trailing)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Game row

    @ViewBuilder
    private func gameRow(game: GameLine, season: PlayerGameLogSeason, tint: Color) -> some View {
        let playedGames = season.games.filter { !$0.missed }

        HStack(spacing: 0) {
            // Date + opponent label
            VStack(alignment: .leading, spacing: 1) {
                Text(shortDate(game.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(game.missed ? .tertiary : .primary)
                if let opp = game.opp {
                    Text((game.home == true ? "vs " : "@ ") + opp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .leading)
            .padding(.leading, 8)

            if game.missed {
                Text("MISSED")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else if mode == .box {
                // GP column — just show the W/L result
                Text(game.wl ?? "—")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(game.wl == "W" ? .green : game.wl == "L" ? .red : .secondary)
                    .frame(width: 36, alignment: .trailing)
                    .padding(.horizontal, 2)

                ForEach(StatColumns.boxColumns, id: \.title) { col in
                    let gameVal = gameBoxValue(col: col, game: game)
                    let avgVal = seasonAverage(col: col, games: playedGames)
                    let cell = StatComparison.gameCell(col.direction, game: gameVal, seasonAvg: avgVal)
                    Text(StatColumns.fmt(gameVal))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(StatColumns.color(for: cell))
                        .frame(width: colWidth(col.title), alignment: .trailing)
                        .padding(.horizontal, 2)
                }
            } else {
                // Advanced
                Text(game.wl ?? "—")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(game.wl == "W" ? .green : game.wl == "L" ? .red : .secondary)
                    .frame(width: 36, alignment: .trailing)
                    .padding(.horizontal, 2)

                advancedGameCells(game: game, playedGames: playedGames)
            }
        }
        .padding(.vertical, 5)
        .background(tint)
    }

    @ViewBuilder
    private func advancedGameCells(game: GameLine, playedGames: [GameLine]) -> some View {
        let adv = StatComparison.advancedPerGame(game)
        let header = StatComparison.advancedSeasonHeader(playedGames)
        let avgPM = averagePlusMinus(games: playedGames)
        let gamePM = game.plusMinus.map(Double.init)

        let cells: [(String, StatDirection, Double?, Double?)] = [
            ("TS%",  .higherBetter, adv?.ts.map { $0 * 100 }, header.ts.map { $0 * 100 }),
            ("eFG%", .higherBetter, adv?.efg.map { $0 * 100 }, header.efg.map { $0 * 100 }),
            ("GmSc", .higherBetter, adv?.gmsc, header.gmsc),
            ("+/-",  .higherBetter, gamePM, avgPM),
        ]

        ForEach(cells, id: \.0) { title, dir, val, avg in
            let cell: StatCell = val == nil ? .dash : (avg == nil ? .neutral
                : StatComparison.gameCell(dir, game: val, seasonAvg: avg))
            Text(StatColumns.fmt(val))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(StatColumns.color(for: cell))
                .frame(width: colWidth(title), alignment: .trailing)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Data loading

    private func loadAllSeasons() async {
        // Load-once: skip if already loading or already populated (so a re-appear doesn't
        // re-fetch), but retry if a previous attempt failed and left `seasons` empty.
        guard !isLoading, seasons.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let allSeasons: [String]
        do {
            allSeasons = try await FirestoreService.shared.listPlayerGameLogSeasons(slug: slug)
        } catch {
            print("[PlayerGameLogView] listPlayerGameLogSeasons(\(slug)) failed: \(error)")
            return
        }

        var loaded: [PlayerGameLogSeason] = []
        // Load all seasons concurrently
        await withTaskGroup(of: PlayerGameLogSeason?.self) { group in
            for season in allSeasons {
                group.addTask {
                    try? await FirestoreService.shared.fetchPlayerGameLogSeason(slug: self.slug, season: season)
                }
            }
            for await doc in group {
                if let doc { loaded.append(doc) }
            }
        }

        // Sort newest-first
        seasons = loaded.sorted { $0.season > $1.season }
    }

    // MARK: - Stat helpers

    private func seasonAverage(col: StatColumn, games: [GameLine]) -> Double? {
        // Map the column title to a game-level extractor and average it
        let vals: [Double] = games.compactMap { gameBoxValue(col: col, game: $0) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func gameBoxValue(col: StatColumn, game: GameLine) -> Double? {
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

    private func averagePlusMinus(games: [GameLine]) -> Double? {
        let vals = games.compactMap { $0.plusMinus.map(Double.init) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func shortDate(_ iso: String) -> String {
        // "2024-11-15" -> "Nov 15"
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              month >= 1, month <= 12 else { return iso }
        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun",
                          "Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(monthNames[month - 1]) \(day)"
    }

    private var headerColumns: [StatColumn] {
        mode == .box ? StatColumns.boxColumns : StatColumns.advancedColumns
    }

    private func colWidth(_ title: String) -> CGFloat {
        switch title {
        case "NetRtg", "AST%": return 52
        case "TRB/G", "ORB/G", "DRB/G": return 48
        case "GmSc", "+/-":   return 44
        default:               return 42
        }
    }
}
