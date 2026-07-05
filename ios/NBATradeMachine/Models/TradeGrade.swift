import Foundation

/// At-a-glance whole-trade fairness verdict.
///
/// Derived purely from what `TradeConfirmation` already computes (each team's
/// asset-value Δ in comp-Z dollars) — no new modeling, no network. The letter
/// expresses how evenly value is split across the teams; the verdict names the
/// favored side. `approximate` is set when picks / cash / players missing a
/// comp-Z are in the deal, since those aren't priced into the asset Δ.
struct TradeGrade: Equatable {
    /// "A+" … "F". Higher = more balanced.
    let letter: String
    /// One-line human verdict, e.g. "Even value both ways" or "Favors LAL".
    let verdict: String
    /// True when picks/cash/uncomped players mean the grade reflects only the
    /// priced player value — surfaced to the user as a caveat.
    let approximate: Bool
}

extension TradeConfirmation {
    /// Deterministic whole-trade fairness grade, or nil when fewer than two
    /// teams carry a comp-Z asset Δ (nothing meaningful to compare).
    ///
    /// Metric: the dollar spread between the team that gains the most asset
    /// value and the one that gains the least, normalized by the gross player
    /// value moving through the trade. For a two-team swap this reduces to
    /// twice the haul imbalance as a fraction of total value exchanged.
    var grade: TradeGrade? {
        let deltas: [(team: Team, delta: Int)] = teams.compactMap { pkg in
            guard let d = pkg.rollup.assetDeltaDollars else { return nil }
            return (pkg.team, d)
        }
        guard deltas.count >= 2 else { return nil }

        let winner = deltas.max { $0.delta < $1.delta }!
        let loser = deltas.min { $0.delta < $1.delta }!
        let spread = winner.delta - loser.delta

        // Gross player value moved = sum of positive incoming asset dollars
        // across every team (each player is incoming to exactly one team, so
        // this counts the trade's total priced value once).
        let gross = teams.reduce(0) { acc, pkg in
            acc + pkg.incomingPlayers.reduce(0) { $0 + max(0, $1.compZ?.asset?.dollarsPoint ?? 0) }
        }

        let ratio: Double = gross > 0
            ? Double(spread) / Double(gross)
            : (spread == 0 ? 0 : 1)

        // Bands are intentionally forgiving near the middle so a realistic,
        // roughly-even trade grades well; tune here if grades feel off.
        let letter: String
        switch ratio {
        case ..<0.06: letter = "A+"
        case ..<0.16: letter = "A"
        case ..<0.30: letter = "B"
        case ..<0.48: letter = "C"
        case ..<0.70: letter = "D"
        default:      letter = "F"
        }

        let approximate = teams.contains { pkg in
            !pkg.incomingPicks.isEmpty || !pkg.outgoingPicks.isEmpty
                || pkg.cashIncoming > 0 || pkg.cashOutgoing > 0
                || pkg.rollup.assetDeltaHadMissing
        }

        let verdict: String
        if spread <= 0 || ratio < 0.06 {
            verdict = "Even value both ways"
        } else {
            verdict = "Favors \(winner.team.tricode)"
        }

        return TradeGrade(letter: letter, verdict: verdict, approximate: approximate)
    }
}
