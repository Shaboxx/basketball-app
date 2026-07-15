import SwiftUI

/// PURE decision for the `.task` reset/rebuild step (B-3 + B-9). Encodes the spec's two
/// binding reset rules AND the B-3 stamping fix in one unit-testable place:
///   - Rule 1 (appearance): ALWAYS reset the transient bindings (mode/blend) — so
///     `resetToDefaults` is unconditionally true.
///   - Rule 2 (grid invalidation): rebuild the grid only when the slug is not the cached one.
///   - B-3 stamping: stamp `newCacheSlug` ONLY when a grid actually built (slug changed AND a
///     chart was available). Otherwise leave the cache key UNCHANGED — nil/stale if the chart
///     wasn't ready yet (so the later nil -> present transition rebuilds), or the still-valid
///     cached slug if nothing changed.
nonisolated enum CourtVizTransition {
    static func apply(oldCacheSlug: String?,
                      newSlug: String,
                      chartAvailable: Bool) -> (resetToDefaults: Bool,
                                                rebuildGrid: Bool,
                                                newCacheSlug: String?) {
        let slugChanged = (newSlug != oldCacheSlug)
        // Rebuild only when the slug is uncached/changed AND a chart is actually available.
        let rebuild = slugChanged && chartAvailable
        // Stamp the key ONLY when we built (B-3); else keep the existing cache key untouched.
        let newKey: String? = rebuild ? newSlug : oldCacheSlug
        return (resetToDefaults: true, rebuildGrid: rebuild, newCacheSlug: newKey)
    }

    /// Revision-aware decision (heat-model v2 final-review fix, sol diff defect 1): a
    /// leagueRevision bump with an UNCHANGED cached slug means the league field was REPLACED
    /// (bundle seed -> valid Firestore doc, or a future refetch). That fire must REBUILD the
    /// grids from the new field but must NOT reset the user's transient controls — reset
    /// belongs to appearance/slug/chart-flip transitions only (a background data refresh may
    /// never wipe an active tap-cycle/slider/mode selection).
    static func applyV2(oldCacheSlug: String?, newSlug: String, chartAvailable: Bool,
                        oldRevision: Int?, newRevision: Int)
        -> (resetToDefaults: Bool, rebuildGrid: Bool, newCacheSlug: String?, newCacheRevision: Int?) {
        let base = apply(oldCacheSlug: oldCacheSlug, newSlug: newSlug, chartAvailable: chartAvailable)
        let slugChanged = (newSlug != oldCacheSlug)
        // Revision-only refresh: same cached slug, a previously-stamped revision, a new revision.
        let revisionOnly = !slugChanged && oldRevision != nil && oldRevision != newRevision
        let rebuild = base.rebuildGrid || (revisionOnly && chartAvailable)
        return (resetToDefaults: !revisionOnly,
                rebuildGrid: rebuild,
                newCacheSlug: rebuild ? newSlug : oldCacheSlug,
                newCacheRevision: rebuild ? newRevision : oldRevision)
    }
}

/// Heat sub-mode (D2): mode 1 colors vs the cell league baseline; mode 2 colors expected
/// points per shot vs leagueMeanPPS. The view is handed whichever grid the parent selects.
nonisolated enum HeatMode: String, CaseIterable { case vsLeague = "vs league", pointsPerShot = "Points/shot" }

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
    @State private var zoneLabelMode: ZoneLabelMode = .off
    @State private var heatBlend: Double = 0
    @State private var heatGrid: HeatGrid? = nil
    @State private var heatGridEP: HeatGrid? = nil
    @State private var heatMode: HeatMode = .vsLeague
    @State private var heatGridSlug: String? = nil
    @State private var heatGridRevision: Int? = nil
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
        // On the STABLE card view, NOT the offense subtree: an Offense→Defense→Offense toggle
        // recreates the offense subtree and a subtree-attached task would re-fire there,
        // resetting the tap-cycle/slider mid-session. Here it fires only on card appearance,
        // player-slug change, or the chart's nil→present availability flip (composite id).
        .task(id: Self.heatTaskID(slug: player.slug,
                                  chartAvailable: shotStore.chart(for: player.slug) != nil,
                                  leagueRevision: shotStore.leagueRevision)) {
            let chart = shotStore.chart(for: player.slug)
            let decision = CourtVizTransition.applyV2(oldCacheSlug: heatGridSlug,
                                                      newSlug: player.slug,
                                                      chartAvailable: chart != nil,
                                                      oldRevision: heatGridRevision,
                                                      newRevision: shotStore.leagueRevision)
            if decision.resetToDefaults {
                zoneLabelMode = .off
                heatBlend = 0
                heatMode = .vsLeague
            }
            if decision.rebuildGrid, let chart, let league = shotStore.league {
                heatGrid = HeatField.build(points: chart.points, overallFGA: chart.meta.fga,
                                           overallFGM: chart.meta.fgm, league: league)
                // EP grid built ONLY when the mean-PPS anchor is present (no ?? 0 fallback, F7).
                if let pps = shotStore.leagueMeanPPS {
                    heatGridEP = HeatField.buildEP(points: chart.points, overallFGA: chart.meta.fga,
                                                   overallFGM: chart.meta.fgm, league: league,
                                                   leagueMeanPPS: pps)
                } else {
                    heatGridEP = nil
                }
                heatGridSlug = decision.newCacheSlug
                heatGridRevision = decision.newCacheRevision
            } else if decision.rebuildGrid, shotStore.league == nil {
                // chart present but league not loaded yet: leave the grids nil (heat unavailable);
                // do NOT stamp the slug/revision so the league-arrival rebuild rebuilds. The
                // composite id re-fires on the next leagueRevision bump (PF9).
                heatGrid = nil; heatGridEP = nil
            } else {
                heatGridSlug = decision.newCacheSlug
                heatGridRevision = decision.newCacheRevision
            }
        }
    }

    // Shot map (SHOT store) and offense stats (MATCHUP store) render INDEPENDENTLY —
    // one missing source never hides the other.
    @ViewBuilder private var offense: some View {
        VStack(alignment: .leading, spacing: 8) {
            let phase = FantasyEmptyState.decide(phase: shotStore.phase,
                                                 hasData: shotStore.chart(for: player.slug) != nil)
            switch phase {
            case .loading: loadingRow("Loading shot chart…")
            case .collectionEmpty, .playerMissing: notAvailable("Shot chart")
            case .data:
                if let chart = shotStore.chart(for: player.slug) {
                    let leagueMissing = shotStore.league == nil
                    let unavailable = Self.heatUnavailable(pointsEmpty: chart.points.isEmpty,
                                                           metaFGA: chart.meta.fga,
                                                           leagueMissing: leagueMissing)
                    let epAvailable = Self.epModeAvailable(league: shotStore.league,
                                                           pps: shotStore.leagueMeanPPS)
                    let active = Self.activeGrid(mode: heatMode,
                                                 vsLeague: heatGridSlug == player.slug ? heatGrid : nil,
                                                 ep: heatGridSlug == player.slug ? heatGridEP : nil)
                    HalfCourtView(points: chart.points,
                                  zones: chart.zones,
                                  zoneLabelMode: zoneLabelMode,
                                  heatBlend: heatBlend,
                                  heatGrid: active,                       // parent swaps mode-1 / EP
                                  onTap: { zoneLabelMode = zoneLabelMode.next })
                    caption("\(chart.meta.fga) FGA · season \(chart.meta.season)")
                    HStack(spacing: 8) {
                        Text("Dot").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: $heatBlend, in: 0...1).disabled(unavailable)
                        Text("Heat").font(.caption2).foregroundStyle(.secondary)
                    }
                    // Segmented control visible only when blended in (D2); the Points/shot segment
                    // is present only when the EP anchor is available.
                    if Self.showsHeatModeControl(heatBlend: heatBlend) {
                        Picker("", selection: $heatMode) {
                            Text(HeatMode.vsLeague.rawValue).tag(HeatMode.vsLeague)
                            if epAvailable { Text(HeatMode.pointsPerShot.rawValue).tag(HeatMode.pointsPerShot) }
                        }.pickerStyle(.segmented)
                        caption(heatMode == .vsLeague ? Self.heatCaptionVsLeague : Self.heatCaptionPointsPerShot)
                        caption(heatMode == .vsLeague ? Self.legendVsLeague : Self.legendPointsPerShot)
                        if heatMode == .pointsPerShot { caption(Self.epHint) }
                    }
                    if unavailable {
                        caption(Self.unavailableCaption(pointsEmpty: chart.points.isEmpty,
                                                        metaFGA: chart.meta.fga, leagueMissing: leagueMissing))
                    } else if let note = Self.droppedNoCoordCaption(chart.meta.droppedNoCoord) {
                        caption(note)
                    }
                } else { notAvailable("Shot chart") }
            }
            if let mu = matchupStore.matchup(for: player.slug) {
                statLine("As scorer",
                         mu.offense.ptsPerPoss.map { String(format: "%.2f pts/poss", $0) } ?? "—",
                         mu.offense.efg.map { String(format: "%.1f%% eFG", $0 * 100) } ?? "—")
            }
            // FIX 3: the "Scouting read" renders UNDER BOTH the shot map AND the "As scorer"
            // line — but STILL only in the .data-with-chart state (never on
            // .loading/.collectionEmpty/.playerMissing), preserving that invariant exactly.
            if case .data = phase, let chart = shotStore.chart(for: player.slug) {
                scoutingRead(chart)
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

    // MARK: - Heat-model v2 pure wiring helpers (unit-testable, no SwiftUI)

    /// The composite .task id: re-fires on slug change, chart-availability flip, OR any
    /// leagueRevision bump (F12/PF9 — the grid must rebuild when the league field loads OR is
    /// replaced by a valid fetch over a non-nil seed; an Int revision catches the non-nil ->
    /// non-nil replacement a `league != nil` boolean would miss).
    nonisolated static func heatTaskID(slug: String, chartAvailable: Bool, leagueRevision: Int) -> String {
        "\(slug)#\(chartAvailable)#\(leagueRevision)"
    }

    /// The segmented control is visible only when the heat layer is blended in (D2).
    nonisolated static func showsHeatModeControl(heatBlend: Double) -> Bool { heatBlend > 0 }

    /// EP (Points/shot) mode is available iff a full-length league field AND a finite mean-PPS
    /// anchor are loaded (PA8: also require `league.count == 624` and `pps.isFinite`). The
    /// [0.8, 1.4] RANGE check is NOT duplicated here — the validation layer (`LeagueField.isValid`)
    /// owns it; this gate only guards a nil/empty field and a NaN/Inf anchor from reaching buildEP.
    nonisolated static func epModeAvailable(league: [Double]?, pps: Double?) -> Bool {
        guard let league, league.count == 26 * 24, let pps, pps.isFinite else { return false }
        return true
    }

    /// The grid the parent hands the view for a given mode (pointer swap, no recompute).
    nonisolated static func activeGrid(mode: HeatMode, vsLeague: HeatGrid?, ep: HeatGrid?) -> HeatGrid? {
        mode == .vsLeague ? vsLeague : ep
    }

    /// Rebuild the HeatGrid only when the player slug changes (grid cache invalidation).
    nonisolated static func shouldRebuildGrid(slug: String, cachedSlug: String?) -> Bool {
        slug != cachedSlug
    }

    /// The Dot↔Heat slider is disabled when there are no plotted shots, the season FGA is
    /// zero, OR the league baseline is missing (never a fabricated/own-baseline field).
    nonisolated static func heatUnavailable(pointsEmpty: Bool, metaFGA: Int, leagueMissing: Bool) -> Bool {
        pointsEmpty || metaFGA == 0 || leagueMissing
    }

    /// The disabled caption: the league-missing string when the ONLY failing condition is a
    /// missing league field, else the no-shots string.
    nonisolated static func unavailableCaption(pointsEmpty: Bool, metaFGA: Int, leagueMissing: Bool) -> String {
        if leagueMissing && !pointsEmpty && metaFGA != 0 { return unavailableNoLeague }
        return unavailableNoShots
    }

    /// The one-line disclosure shown ONLY when some shots lacked a location; nil otherwise.
    nonisolated static func droppedNoCoordCaption(_ droppedNoCoord: Int) -> String? {
        droppedNoCoord > 0
            ? "Heat reflects plotted shots only (\(droppedNoCoord) without a location)."
            : nil
    }

    // MARK: - Copy (section 12, banned-word screened)
    static let heatCaptionVsLeague = "Heat vs NBA average from that spot."
    static let heatCaptionPointsPerShot = "Points per shot attempt vs the league mean."
    static let epHint = "Color shows points per shot attempt — not full possession value."
    static let unavailableNoShots = "Heat map needs plotted shots — none available yet."
    static let unavailableNoLeague = "Heat map needs the league baseline — not loaded yet."
    static let legendVsLeague = "Warmer = makes it more often than NBA average here; cooler = less often."
    static let legendPointsPerShot = "Warmer = more points per shot attempt than the league average."
}
