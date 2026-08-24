import Foundation

/// Post-trade role-chemistry readout for one team, derived from the shipped
/// `LineupLabeler` synergy engine applied to the team's top-five-by-impact
/// starters before and after the deal. Pure + deterministic.
struct LineupChemistryDelta: Equatable {
    /// Post-trade starters' composite (offense + defense quality), z-scale.
    let postComposite: Double
    /// post − pre composite; nil when the pre-trade starters couldn't be
    /// evaluated (too few players carrying lineup features).
    let delta: Double?
    /// Human archetype of the resulting starting five (e.g. "Five-Out").
    let archetype: String
    /// Up to two most-moved capabilities, phrased with direction, e.g.
    /// ["spacing ↑", "rim protection ↓"]. Descriptive only — the sign of the
    /// overall change is carried by `delta`.
    let topChanges: [String]

    /// One-line rollup for the confirmation tile. Labeled "fit" so it reads as
    /// a distinct axis from the per-player value "Δσ" in the rollup footer.
    var summaryLine: String {
        guard let d = delta else { return "\(archetype) (no baseline to compare)" }
        let mag = String(format: "fit %+.2fσ", d)
        if topChanges.isEmpty { return "\(archetype) · \(mag)" }
        return "\(archetype) · \(mag) (\(topChanges.joined(separator: ", ")))"
    }
}

/// Builds a `LineupChemistryDelta` for a team by labeling its resulting
/// starting five and comparing it to the pre-trade five. Reuses
/// `LineupLabeler` unchanged — same engine that renders on lineup cards.
nonisolated enum TradeChemistry {
    /// Minimum starters carrying lineup features for a readout to be shown.
    private static let minFeatured = 3
    /// Minimum absolute capability shift worth surfacing (z-scale).
    private static let changeThreshold = 0.15

    static func evaluate(preRoster: [Player], postRoster: [Player],
                         norms: LeagueNorms) -> LineupChemistryDelta? {
        let postStarters = starters(postRoster)
        guard featuredCount(postStarters) >= minFeatured else { return nil }
        let post = label(postStarters, norms: norms)
        let postComposite = post.oQuality + post.dQuality

        var delta: Double? = nil
        var topChanges: [String] = []
        let preStarters = starters(preRoster)
        if featuredCount(preStarters) >= minFeatured {
            let pre = label(preStarters, norms: norms)
            delta = postComposite - (pre.oQuality + pre.dQuality)
            topChanges = capabilityChanges(pre: pre, post: post)
        }

        return LineupChemistryDelta(
            postComposite: postComposite,
            delta: delta,
            archetype: post.archetypeLabel,
            topChanges: topChanges
        )
    }

    // MARK: - Helpers

    /// Top five players by θ-total from thetaBoard — the engine's "starters" proxy.
    /// Tie-broken by name ascending for stable ordering when impacts are equal.
    private static func starters(_ roster: [Player]) -> [Player] {
        roster
            .sorted {
                let a = $0.thetaBoard?.total ?? -.greatestFiniteMagnitude
                let b = $1.thetaBoard?.total ?? -.greatestFiniteMagnitude
                return a != b ? a > b : $0.name < $1.name
            }
            .prefix(5)
            .map { $0 }
    }

    private static func featuredCount(_ players: [Player]) -> Int {
        players.filter { $0.lineupFeatures != nil }.count
    }

    private static func label(_ players: [Player], norms: LeagueNorms) -> LineupLabel {
        LineupLabeler.label(players: players, norms: norms,
                            impacts: players.map { $0.thetaBoard?.total })
    }

    /// Fixed capability order → deterministic ties.
    private static let capabilityOrder: [(key: String, name: String)] = [
        ("spacing", "spacing"),
        ("pnr_fit", "pick-and-roll fit"),
        ("switchable", "switchability"),
        ("rim_protection", "rim protection"),
        ("creation_redundancy", "creation overlap"),
    ]

    private static func capabilityChanges(pre: LineupLabel, post: LineupLabel) -> [String] {
        capabilityOrder.enumerated()
            .compactMap { idx, cap -> (name: String, mag: Double, idx: Int)? in
                let d = (post.capabilityMagnitudes[cap.key] ?? 0)
                      - (pre.capabilityMagnitudes[cap.key] ?? 0)
                guard abs(d) >= changeThreshold else { return nil }
                return (cap.name, d, idx)
            }
            .sorted { a, b in
                abs(a.mag) != abs(b.mag) ? abs(a.mag) > abs(b.mag) : a.idx < b.idx
            }
            .prefix(2)
            .map { "\($0.name) \($0.mag > 0 ? "↑" : "↓")" }
    }
}
