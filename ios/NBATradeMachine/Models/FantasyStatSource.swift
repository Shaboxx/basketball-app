import Foundation

/// Format-PARAMETERIZED raw production for one fantasy team: the summed 9-category
/// z-vector (format-independent) PLUS a projected fantasy-points/game figure (which IS
/// format-specific — ESPN vs Yahoo, and 0 for category formats). "Raw" = not yet reduced
/// to standings or win-loss; the standings/matchup layer selects the category vector or
/// the points scalar per active format.
///
/// INVARIANT: a productions map must be built with the SAME `format` later passed to the
/// engine. The detail view guarantees this by recomputing the map each render from
/// `appSettings.fantasyFormat`, so there is no staleness.
///
/// This is the shape a future ActualsStatSource must also emit (real game logs → summed
/// category totals + actual fantasy points under the scoring format), so the engine never
/// changes when live data lands.
nonisolated struct FantasyTeamProduction: Equatable {
    let categoryTotals: FantasyValue.CategoryZ   // summed categoryZ (format-independent)
    let pointsPerGame: Double                    // summed fp/game for the ACTIVE points format (0 for category formats)

    static let zero = FantasyTeamProduction(categoryTotals: .zero, pointsPerGame: 0)
}

/// The data-source seam. `production(for:format:)` yields a team's raw production.
/// The concrete `ProjectedStatSource` computes it from already-loaded projections;
/// a future `ActualsStatSource` computes the same shape from real game logs (DEFERRED).
/// The format is passed in because the points figure is inherently format-specific
/// (ESPN vs Yahoo) — and a real actuals source must apply a specific scoring formula.
nonisolated protocol FantasyStatSource {
    func production(for team: FantasyTeam, format: FantasyFormat) -> FantasyTeamProduction
}

/// Projected-now source: sums the roster's projected `fantasyValues` via the shipped
/// pure `FantasyTeamProfile`. PURE + testable — it holds a plain `[String: FantasyValue]`
/// SNAPSHOT (a Sendable value dictionary), NOT a reference to the @MainActor store and
/// NOT a MainActor-isolated closure, so nothing crosses isolation. The view passes
/// `fantasyStore.values` on MainActor; tests pass a fixture dictionary. Slugs are
/// canonicalized before lookup (idempotent — roster slugs are already canonical) and
/// store misses are dropped (a slug with no FantasyValue contributes 0), matching the
/// team-detail resolver.
nonisolated struct ProjectedStatSource: FantasyStatSource {
    /// canonical-slug → FantasyValue snapshot.
    let values: [String: FantasyValue]

    init(values: [String: FantasyValue]) { self.values = values }

    func production(for team: FantasyTeam, format: FantasyFormat) -> FantasyTeamProduction {
        let resolved = team.playerSlugs.compactMap { values[FantasyValueStore.canonicalSlug($0)] }
        return FantasyTeamProduction(
            categoryTotals: FantasyTeamProfile.categoryTotals(resolved),
            pointsPerGame:  FantasyTeamProfile.fpPerGameTotal(resolved, format: format))
    }
}
