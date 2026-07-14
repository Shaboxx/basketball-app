import SwiftUI

/// Player-page card: offense = half-court shot map + offensive efficiency; defense =
/// hedged, stat-cited matchup scouting. Each source renders independently (one missing
/// source never blanks the card). NBA-mode, flag-gated by the caller.
struct MatchupCourtSection: View {
    let player: Player
    @EnvironmentObject var shotStore: PlayerShotStore
    @EnvironmentObject var matchupStore: MatchupStore
    @State private var side: Side = .offense
    @State private var showZoneFG = false
    @State private var isExpanded = true
    enum Side: String, CaseIterable { case offense = "Offense", defense = "Defense" }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $side) {
                    ForEach(Side.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                switch side {
                case .offense: offense
                case .defense: defense
                }
            }.padding(.top, 6)
        } label: { Text("Matchups").font(.headline) }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // Shot map (SHOT store) and offense stats (MATCHUP store) render INDEPENDENTLY —
    // one missing source never hides the other.
    @ViewBuilder private var offense: some View {
        VStack(alignment: .leading, spacing: 8) {
            let chart = shotStore.chart(for: player.slug)
            switch FantasyEmptyState.decide(phase: shotStore.phase, hasData: chart != nil) {
            case .loading: loadingRow("Loading shot chart…")
            case .collectionEmpty, .playerMissing: notAvailable("Shot chart")
            case .data:
                if let chart {
                    HalfCourtView(points: chart.points, zones: chart.zones, showZoneFG: $showZoneFG)
                    caption("\(chart.meta.fga) FGA · season \(chart.meta.season)")
                } else { notAvailable("Shot chart") }
            }
            if let mu = matchupStore.matchup(for: player.slug) {
                statLine("As scorer",
                         mu.offense.ptsPerPoss.map { String(format: "%.2f pts/poss", $0) } ?? "—",
                         mu.offense.efg.map { String(format: "%.1f%% eFG", $0 * 100) } ?? "—")
            }
        }
    }

    @ViewBuilder private var defense: some View {
        let mu = matchupStore.matchup(for: player.slug)
        switch FantasyEmptyState.decide(phase: matchupStore.phase, hasData: mu != nil) {
        case .loading: loadingRow("Loading matchup data…")
        case .collectionEmpty, .playerMissing: notAvailable("Matchup scouting")
        case .data:
            if let mu {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MatchupInsight.defensiveInsights(from: mu)) { ins in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ins.headline).font(.subheadline).bold()
                            Text(ins.evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if mu.byPosition.contains(where: { $0.value.ptsPerPoss != nil }) {
                        Divider()
                        Text("Defends by position (pts/poss allowed)").font(.caption).foregroundStyle(.secondary)
                        ForEach(["G", "F", "C"], id: \.self) { pos in
                            if let s = mu.byPosition[pos], let ppp = s.ptsPerPoss {
                                barRow(label: posLabel(pos), value: ppp)
                            }
                        }
                    }
                    opponentList("Toughest matchups (most pts/poss allowed)", mu.topMatchups.toughest)
                    opponentList("Most-faced opponents", mu.topMatchups.mostFrequent)
                    caption("spatial defense map coming soon")
                }
            } else { notAvailable("Matchup scouting") }
        }
    }

    @ViewBuilder private func opponentList(_ title: String, _ ops: [Matchup.Opponent]) -> some View {
        if !ops.isEmpty {
            Divider()
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(ops.prefix(3)) { o in
                HStack {
                    Text(o.offName)
                    Spacer()
                    Text(o.ptsPerPoss.map { String(format: "%.2f p/poss", $0) } ?? "—").foregroundStyle(.secondary)
                    Text("· \(Int(o.partialPoss.rounded())) poss").foregroundStyle(.secondary)
                }.font(.caption).monospacedDigit()
            }
        }
    }

    private func posLabel(_ p: String) -> String {
        ["G": "Guards", "F": "Forwards", "C": "Centers"][p] ?? p
    }
    private func barRow(label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 68, alignment: .leading)
            GeometryReader { geo in
                let frac = min(1.0, max(0.0, value / 0.4))   // ~0.4 pts/partial-poss caps the bar
                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.6))
                    .frame(width: geo.size.width * frac)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 10)
            Text(String(format: "%.2f", value)).font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
    private func loadingRow(_ t: String) -> some View {
        HStack(spacing: 8) { ProgressView(); Text(t).foregroundStyle(.secondary) }
    }
    private func notAvailable(_ what: String) -> some View {
        Text("\(what) not available yet (season 2025-26).").font(.callout).foregroundStyle(.secondary)
    }
    private func statLine(_ k: String, _ a: String, _ b: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(a).bold(); Text("·").foregroundStyle(.secondary); Text(b).bold() }
            .font(.caption).monospacedDigit()
    }
    private func caption(_ t: String) -> some View {
        Text(t).font(.caption2).foregroundStyle(.secondary)
    }
}
