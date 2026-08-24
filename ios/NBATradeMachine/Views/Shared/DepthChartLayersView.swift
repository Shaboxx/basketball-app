import SwiftUI

/// Layer-based depth chart shared by the team page and the trade view. Rows are
/// depth layers (Starters / 2nd / 3rd / 4th / 5th); columns are PG SG SF PF C
/// plus a LEADING Lineup column (leftmost) whose per-row cell is titled with the
/// layer name (Starters / 2nd / …) — it doubles as the row label — and sums that
/// layer's filled cells (v2 TOT/OFF/DEF).
///
/// Every player cell's TOT/OFF/DEF and every layer-Lineup's TOT/OFF/DEF are
/// colored green / red against the league distribution for THAT layer:
/// green above mean + 0.75·std, red below mean − 0.75·std, neutral within band.
///
/// Tapping a player cell pushes `PlayerDetailView`; tapping a Lineup cell opens
/// the generated `LineupBreakdownView` for that layer's five players.
struct DepthChartLayersView: View {
    // This view is presented inside sheets (team depth chart, trade depth chart) that strip the
    // environment, and it opens a breakdown SUB-sheet that pushes PlayerDetailView. Hold
    // PlayerDetailView's full dependency set so the sub-sheet can re-inject it. Every presenter
    // (DepthChartSheet, TeamDetailView's depth sheet) supplies all four.
    @EnvironmentObject private var teamsVM: TeamsViewModel
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore

    let columns: [String: ColumnResult]
    let league: TeamDepthChartBuilder.LeagueLayerStats
    var cap: Int = 5
    /// League norms for the lineup-breakdown sheet. nil → the breakdown shows
    /// "unavailable" rather than crashing.
    var norms: LeagueNorms? = nil
    /// Roster backing the bottom "Create Lineups" button (the Lineup Maker).
    /// Empty → the button is hidden.
    var roster: [Player] = []

    private var positions: [String] { TeamDepthChartBuilder.positions }

    /// Identifiable wrapper so a tapped layer index can drive `.sheet(item:)`.
    private struct BreakdownLayer: Identifiable { let id: Int }

    /// The layer whose Lineup cell was tapped (drives the breakdown sheet).
    @State private var breakdownLayer: BreakdownLayer?

    /// The five filled Player cells of `layer` (the layer's lineup), in PG-SG-
    /// SF-PF-C column order.
    private func layerPlayers(_ layer: Int) -> [Player] {
        positions.compactMap { pos -> Player? in
            guard let shown = columns[pos]?.shown, layer < shown.count else { return nil }
            return shown[layer].player
        }
    }

    /// Per-player composite impact (θ-total from thetaBoard) for `layer`, same order as
    /// `layerPlayers`.
    private func layerImpacts(_ layer: Int) -> [Double?] {
        layerPlayers(layer).map { $0.engineImpact }
    }

    /// Tier label the labeler uses: the first (starters) layer is "starters",
    /// every deeper layer is a reserve unit ("bench").
    private func tier(for layer: Int) -> String {
        layer == 0 ? "starters" : "bench"
    }

    /// Layers (0..<cap) that hold at least one filled position cell.
    private var activeLayers: [Int] {
        (0..<cap).filter { layer in
            positions.contains { pos in
                (columns[pos]?.shown.count ?? 0) > layer
            }
        }
    }

    private static let layerNames = ["Starters", "2nd", "3rd", "4th", "5th"]
    private func layerName(_ layer: Int) -> String {
        layer < Self.layerNames.count ? Self.layerNames[layer] : "\(layer + 1)th"
    }

    /// player.id → the FIRST (highest / lowest-index) layer they appear on.
    /// A cell whose layer is greater than this is a repeat appearance and is
    /// rendered grayed. Iterates layers top-down so the first hit wins.
    private var firstAppearanceLayer: [String: Int] {
        var first: [String: Int] = [:]
        for layer in 0..<cap {
            for pos in positions {
                guard let shown = columns[pos]?.shown, layer < shown.count else { continue }
                let id = shown[layer].player.id
                if first[id] == nil { first[id] = layer }
            }
        }
        return first
    }

    var body: some View {
        let firstLayer = firstAppearanceLayer
        // Outer vertical scroll top-anchors the chart (a combined-axis ScrollView
        // vertically centers short content); inner horizontal scroll handles the
        // wide row of position columns + the Lineup column. A pinned bottom
        // "Create Lineups" button opens the interactive Lineup Maker.
        return VStack(spacing: 0) {
            ScrollView(.vertical) {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        headerRow
                        ForEach(activeLayers, id: \.self) { layer in
                            layerRow(layer, firstLayer: firstLayer)
                        }
                        if activeLayers.isEmpty {
                            Text("No rated players to chart.")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding(12)
                }
            }
            if !roster.isEmpty {
                Divider()
                NavigationLink {
                    LineupMakerView(roster: roster, league: league, norms: norms)
                } label: {
                    Text("Create Lineups")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .sheet(item: $breakdownLayer) { item in
            let layer = item.id
            NavigationStack {
                LineupBreakdownView(
                    players: layerPlayers(layer),
                    norms: norms,
                    impacts: layerImpacts(layer),
                    tier: tier(for: layer)
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

    private func layerRow(_ layer: Int, firstLayer: [String: Int]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            totalCell(layer: layer)
            ForEach(positions, id: \.self) { pos in
                playerCell(pos: pos, layer: layer, firstLayer: firstLayer)
            }
        }
    }

    @ViewBuilder
    private func playerCell(pos: String, layer: Int,
                            firstLayer: [String: Int]) -> some View {
        if let shown = columns[pos]?.shown, layer < shown.count {
            let slot = shown[layer]
            let stats = league.playerByLayer[layer]
            // Repeat appearance: this player first showed on an earlier layer.
            let isRepeat = (firstLayer[slot.player.id] ?? layer) < layer
            NavigationLink(value: slot.player) {
                cellBox {
                    VStack(spacing: 2) {
                        HeadshotImage(slug: slot.player.slug, size: 28)
                            .grayscale(isRepeat ? 1 : 0)
                            .opacity(isRepeat ? 0.4 : 1)
                        Text(slot.player.name)
                            .font(.system(size: 10, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(isRepeat ? .secondary : .primary)
                            .opacity(isRepeat ? 0.4 : 1)
                        metricLine("OVR", slot.total,
                                   TeamDepthChartBuilder.highlight(slot.total, stats?.tot ?? zero))
                        metricLine("OFF", slot.off,
                                   TeamDepthChartBuilder.highlight(slot.off, stats?.off ?? zero))
                        metricLine("DEF", slot.def,
                                   TeamDepthChartBuilder.highlight(slot.def, stats?.def ?? zero))
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            cellBox {
                Text("—").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The trailing per-layer Lineup cell, titled with the layer name (Starters /
    /// 2nd / …). Tapping it opens the generated `LineupBreakdownView` for that
    /// layer's five filled players.
    private func totalCell(layer: Int) -> some View {
        let sums = TeamDepthChartBuilder.layerTotals(columns, layer: layer)
        let stats = league.totalByLayer[layer]
        return Button {
            breakdownLayer = BreakdownLayer(id: layer)
        } label: {
            cellBox {
                VStack(spacing: 2) {
                    Text(layerName(layer))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("SwishScore")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    metricLine("OVR", sums.tot,
                               TeamDepthChartBuilder.highlight(sums.tot, stats?.tot ?? zero))
                    metricLine("OFF", sums.off,
                               TeamDepthChartBuilder.highlight(sums.off, stats?.off ?? zero))
                    metricLine("DEF", sums.def,
                               TeamDepthChartBuilder.highlight(sums.def, stats?.def ?? zero))
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cell helpers

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
    private let zero = TeamDepthChartBuilder.MetricStats(mean: 0, std: 0)
}
