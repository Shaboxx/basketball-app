import SwiftUI

/// Pure, testable logic backing `LineupMakerView`. Kept free of SwiftUI so the
/// eligibility / progressive-row / live-total rules can be unit tested.
enum LineupMakerLogic {

    /// Roster players eligible for `position` (their `roleProfile` columns
    /// include it), excluding any player already placed in the SAME row, sorted
    /// by `depthScore(off:dispOff,def:dispDef)` desc then name. Reuse ACROSS
    /// rows is allowed — the caller only passes this row's used ids.
    static func eligible(roster: [Player], position: String,
                         usedInRowIDs: Set<String>) -> [Player] {
        roster
            .filter { p in
                !usedInRowIDs.contains(p.id)
                    && (TeamDepthChartBuilder.roleProfile(p)?.columns.contains(position) ?? false)
            }
            .sorted { a, b in
                let sa = TeamDepthChartBuilder.depthScore(off: a.dispOff, def: a.dispDef)
                let sb = TeamDepthChartBuilder.depthScore(off: b.dispOff, def: b.dispDef)
                if sa != sb { return sa > sb }
                return a.name < b.name
            }
    }

    /// True only when every position slot in the row is filled.
    static func rowFilled(_ row: [Player?]) -> Bool {
        row.allSatisfy { $0 != nil }
    }

    /// 1 + the count of consecutive completely-filled rows from the top, capped
    /// at `maxRows`. Row r+1 is only revealed once row r is full; a gap stops
    /// the run.
    static func visibleRowCount(_ grid: [[Player?]], maxRows: Int = 5) -> Int {
        var filled = 0
        for row in grid {
            if rowFilled(row) { filled += 1 } else { break }
        }
        return min(maxRows, filled + 1)
    }

    /// Sum of dispTotal / dispOff / dispDef over the row's filled players. When
    /// the row has no filled players, every component is nil.
    static func rowTotals(_ row: [Player?]) -> (tot: Double?, off: Double?, def: Double?) {
        let players = row.compactMap { $0 }
        guard !players.isEmpty else { return (nil, nil, nil) }
        let tot = players.reduce(0.0) { $0 + ($1.dispTotal ?? 0) }
        let off = players.reduce(0.0) { $0 + ($1.dispOff ?? 0) }
        let def = players.reduce(0.0) { $0 + ($1.dispDef ?? 0) }
        return (tot, off, def)
    }
}

/// Interactive five-man-unit builder that mirrors `DepthChartLayersView`: a
/// leading Lineup column (titled with the layer name) then PG/SG/SF/PF/C. Each
/// row is a depth layer; tapping an empty slot opens a player picker filtered to
/// that position's eligible roster players. A full row's Lineup cell opens the
/// generated `LineupBreakdownView`. Rows reveal progressively as the row above
/// fills, capped at five.
struct LineupMakerView: View {
    // Pushed inside sheet-hosted stacks and opens a breakdown SUB-sheet that pushes
    // PlayerDetailView; hold its full dependency set to re-inject across that sub-sheet
    // boundary (inherited from DepthChartLayersView, which supplies all four).
    @EnvironmentObject private var teamsVM: TeamsViewModel
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore

    let roster: [Player]
    let league: TeamDepthChartBuilder.LeagueLayerStats
    var norms: LeagueNorms? = nil

    private var positions: [String] { TeamDepthChartBuilder.positions }
    private let maxRows = 5

    /// 5 rows × 5 positions, all empty to start.
    @State private var grid: [[Player?]] =
        Array(repeating: Array(repeating: nil, count: 5), count: 5)

    /// The slot whose picker sheet is open.
    private struct PickerSlot: Identifiable {
        let row: Int
        let col: Int
        var id: String { "\(row)-\(col)" }
    }
    @State private var pickerSlot: PickerSlot?

    /// The row whose breakdown sheet is open.
    private struct BreakdownRow: Identifiable { let id: Int }
    @State private var breakdownRow: BreakdownRow?

    private static let layerNames = ["Starters", "2nd", "3rd", "4th", "5th"]
    private func layerName(_ row: Int) -> String {
        row < Self.layerNames.count ? Self.layerNames[row] : "\(row + 1)th"
    }

    private var visibleRows: Int { LineupMakerLogic.visibleRowCount(grid, maxRows: maxRows) }

    /// Non-nil players in a row, PG-SG-SF-PF-C column order.
    private func rowPlayers(_ row: Int) -> [Player] { grid[row].compactMap { $0 } }

    /// ids already placed in this row (within-row uniqueness; cross-row reuse OK).
    private func usedInRow(_ row: Int) -> Set<String> {
        Set(grid[row].compactMap { $0?.id })
    }

    var body: some View {
        // Outer vertical scroll top-anchors the chart; inner horizontal scroll
        // handles the wide row of columns + the Lineup column. Mirrors
        // DepthChartLayersView.
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    headerRow
                    ForEach(0..<visibleRows, id: \.self) { row in
                        layerRow(row)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("Lineup Maker")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pickerSlot) { slot in
            PlayerPickerSheet(
                players: LineupMakerLogic.eligible(
                    roster: roster, position: positions[slot.col],
                    usedInRowIDs: usedInRow(slot.row)),
                position: positions[slot.col],
                layerStats: league.playerByLayer[slot.row],
                isFilled: grid[slot.row][slot.col] != nil,
                onPick: { player in
                    grid[slot.row][slot.col] = player
                    pickerSlot = nil
                },
                onClear: {
                    grid[slot.row][slot.col] = nil
                    pickerSlot = nil
                }
            )
        }
        .sheet(item: $breakdownRow) { item in
            let row = item.id
            let players = rowPlayers(row)
            NavigationStack {
                LineupBreakdownView(
                    players: players,
                    norms: norms,
                    impacts: players.map { $0.thetaBoard?.total },
                    tier: row == 0 ? "starters" : "bench"
                )
                .navigationDestination(for: Player.self) { p in
                    PlayerDetailView(player: p)
                        .environmentObject(teamsVM)
                        .environmentObject(normsVM)
                        .environmentObject(appSettings)
                        .environmentObject(fantasyStore)
                }
            }
            // Sub-sheet strips the environment — re-inject PlayerDetailView's dependencies.
            .environmentObject(teamsVM)
            .environmentObject(normsVM)
            .environmentObject(appSettings)
            .environmentObject(fantasyStore)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 4) {
            headerCell("Lineup")
            ForEach(positions, id: \.self) { pos in
                headerCell(pos)
            }
        }
    }

    private func headerCell(_ label: String) -> some View {
        Text(label)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: cellWidth)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Rows

    private func layerRow(_ row: Int) -> some View {
        HStack(alignment: .top, spacing: 4) {
            lineupCell(row)
            ForEach(Array(positions.enumerated()), id: \.element) { col, _ in
                slotCell(row: row, col: col)
            }
        }
    }

    /// The leading Lineup cell: layer name + live summed TOT/OFF/DEF, colored vs
    /// the league totals for this layer. When the row is full it becomes a
    /// Button opening the breakdown; otherwise it is a static label.
    @ViewBuilder
    private func lineupCell(_ row: Int) -> some View {
        let totals = LineupMakerLogic.rowTotals(grid[row])
        let stats = league.totalByLayer[row]
        let full = LineupMakerLogic.rowFilled(grid[row])
        if full {
            Button {
                breakdownRow = BreakdownRow(id: row)
            } label: {
                lineupCellBody(row: row, totals: totals, stats: stats, full: true)
            }
            .buttonStyle(.plain)
        } else {
            lineupCellBody(row: row, totals: totals, stats: stats, full: false)
        }
    }

    private func lineupCellBody(
        row: Int,
        totals: (tot: Double?, off: Double?, def: Double?),
        stats: (tot: TeamDepthChartBuilder.MetricStats,
                off: TeamDepthChartBuilder.MetricStats,
                def: TeamDepthChartBuilder.MetricStats)?,
        full: Bool
    ) -> some View {
        cellBox {
            VStack(spacing: 2) {
                Text(layerName(row))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("SwishScore")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                metricLine("OVR", totals.tot,
                           TeamDepthChartBuilder.highlight(totals.tot, stats?.tot ?? zero))
                metricLine("OFF", totals.off,
                           TeamDepthChartBuilder.highlight(totals.off, stats?.off ?? zero))
                metricLine("DEF", totals.def,
                           TeamDepthChartBuilder.highlight(totals.def, stats?.def ?? zero))
                if full {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// One position slot: a filled player cell (depth-chart format) or an empty
    /// gray "plus" square. Tapping either opens the picker.
    @ViewBuilder
    private func slotCell(row: Int, col: Int) -> some View {
        let stats = league.playerByLayer[row]
        Button {
            pickerSlot = PickerSlot(row: row, col: col)
        } label: {
            if let player = grid[row][col] {
                cellBox {
                    VStack(spacing: 2) {
                        HeadshotImage(slug: player.slug, size: 28)
                        Text(player.name)
                            .font(.system(size: 10, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text("SwishScore")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        metricLine("OVR", player.dispTotal,
                                   TeamDepthChartBuilder.highlight(player.dispTotal, stats?.tot ?? zero))
                        metricLine("OFF", player.dispOff,
                                   TeamDepthChartBuilder.highlight(player.dispOff, stats?.off ?? zero))
                        metricLine("DEF", player.dispDef,
                                   TeamDepthChartBuilder.highlight(player.dispDef, stats?.def ?? zero))
                    }
                }
            } else {
                emptySlot
            }
        }
        .buttonStyle(.plain)
    }

    private var emptySlot: some View {
        Image(systemName: "plus")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: cellWidth, height: emptySlotHeight)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Cell helpers (mirror DepthChartLayersView)

    private func metricLine(_ label: String, _ value: Double?,
                            _ highlight: TeamDepthChartBuilder.Highlight) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Text(Player.fmtVal(value))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(color(for: highlight))
        }
    }

    private func color(for highlight: TeamDepthChartBuilder.Highlight) -> Color {
        switch highlight {
        case .above: return .green
        case .below: return .red
        case .neutral: return .primary
        }
    }

    private func cellBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(6)
            .frame(width: cellWidth, alignment: .top)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separator), lineWidth: 0.5))   // adapts in dark mode
    }

    private let cellWidth: CGFloat = 66
    private let emptySlotHeight: CGFloat = 86
    private let zero = TeamDepthChartBuilder.MetricStats(mean: 0, std: 0)
}

/// Scrollable player picker presented as an iOS-idiomatic medium/large sheet.
/// Lists eligible players (depth-chart row format: portrait + name + colored
/// TOT/OFF/DEF). When the originating slot is already filled it offers a
/// "Clear slot" affordance at the top.
private struct PlayerPickerSheet: View {
    let players: [Player]
    let position: String
    let layerStats: (tot: TeamDepthChartBuilder.MetricStats,
                     off: TeamDepthChartBuilder.MetricStats,
                     def: TeamDepthChartBuilder.MetricStats)?
    let isFilled: Bool
    let onPick: (Player) -> Void
    let onClear: () -> Void

    private let zero = TeamDepthChartBuilder.MetricStats(mean: 0, std: 0)

    var body: some View {
        NavigationStack {
            List {
                if isFilled {
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Label("Clear slot", systemImage: "xmark.circle")
                    }
                }
                if players.isEmpty {
                    Text("No eligible \(position) available.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(players) { p in
                        Button {
                            onPick(p)
                        } label: {
                            playerRow(p)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Choose \(position)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func playerRow(_ p: Player) -> some View {
        HStack(spacing: 10) {
            HeadshotImage(slug: p.slug, size: 36)
            Text(p.name).font(.subheadline.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SwishScore")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                metricLine("OVR", p.dispTotal,
                           TeamDepthChartBuilder.highlight(p.dispTotal, layerStats?.tot ?? zero))
                metricLine("OFF", p.dispOff,
                           TeamDepthChartBuilder.highlight(p.dispOff, layerStats?.off ?? zero))
                metricLine("DEF", p.dispDef,
                           TeamDepthChartBuilder.highlight(p.dispDef, layerStats?.def ?? zero))
            }
        }
        .contentShape(Rectangle())
    }

    private func metricLine(_ label: String, _ value: Double?,
                            _ highlight: TeamDepthChartBuilder.Highlight) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(Player.fmtVal(value))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(color(for: highlight))
        }
    }

    private func color(for highlight: TeamDepthChartBuilder.Highlight) -> Color {
        switch highlight {
        case .above: return .green
        case .below: return .red
        case .neutral: return .primary
        }
    }
}
