import SwiftUI

/// Player-page card: offense = half-court shot map + offensive efficiency; defense =
/// hedged, stat-cited matchup scouting. Each source renders independently (one missing
/// source never blanks the card). NBA-mode, flag-gated by the caller.
struct MatchupCourtSection: View {
    let player: Player
    // Consume the app-wide singletons directly (NOT @EnvironmentObject): PlayerDetailView
    // is presented across sheet/fullScreenCover/navigationDestination boundaries that don't
    // propagate the environment, so an @EnvironmentObject here would crash on those paths.
    @ObservedObject private var shotStore = PlayerShotStore.shared
    @ObservedObject private var matchupStore = MatchupStore.shared
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
                    // SW-6: the "Scouting read" renders ONLY here — inside the .data branch,
                    // under the shot map — so .loading/.collectionEmpty/.playerMissing keep
                    // their existing rows untouched (no scouting read on a loading/missing card).
                    scoutingRead(chart)
                } else { notAvailable("Shot chart") }
            }
            if let mu = matchupStore.matchup(for: player.slug) {
                statLine("As scorer",
                         mu.offense.ptsPerPoss.map { String(format: "%.2f pts/poss", $0) } ?? "—",
                         mu.offense.efg.map { String(format: "%.1f%% eFG", $0 * 100) } ?? "—")
            }
        }
    }

    // "Scouting read": hedged, stat-cited shot-profile conclusions under the shot map. Only
    // invoked from the .data branch (SW-6). An absent profile OR zero families firing -> a
    // single honest caption (never blank, never fabricated). Data-driven entirely by
    // ShotProfileInsight.make(from:).
    @ViewBuilder private func scoutingRead(_ chart: PlayerShotChart) -> some View {
        let insights = ShotProfileInsight.make(from: chart.profile)
        Divider()
        Text("Scouting read").font(.subheadline).bold()
        if insights.isEmpty {
            caption("Scouting read not available yet.")
        } else {
            ForEach(insights) { ins in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ins.headline).font(.subheadline).bold()
                        confidenceChip(ins.confidence)
                    }
                    ForEach(ins.evidence, id: \.self) { b in
                        Text(b).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(ins.basis).font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
        }
    }

    private func confidenceChip(_ c: ShotProfileInsight.Confidence) -> some View {
        Text(c.rawValue)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(c == .high ? 0.22 : 0.12),
                        in: Capsule())
            .foregroundStyle(.secondary)
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
                    // NOTE: per-matchup possession counts are inherently small (a full
                    // season of guarding one player is often 20-60 poss), so the header
                    // avoids a hard "toughest" superlative and each row flags small samples
                    // — the ranking is exploratory, not a confident claim.
                    opponentList("Higher pts/poss allowed so far (small per-matchup samples)", mu.topMatchups.toughest)
                    opponentList("Most-faced opponents so far", mu.topMatchups.mostFrequent)
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
                    if o.partialPoss < MatchupInsight.minPoss {
                        Text("· small").foregroundStyle(.tertiary)   // explicit small-sample flag
                    }
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
