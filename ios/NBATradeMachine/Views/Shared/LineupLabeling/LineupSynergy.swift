import Foundation

/// Swift port of scripts/lineup_value/synergy.py — the 5 pairwise capability magnitudes over a
/// lineup's LineupFeatures, STANDARDIZED to league z-scores via LeagueNorms before any formula
/// (kept in lock-step with the Python; parity asserted in LineupSynergyTests). Pure.
nonisolated enum LineupSynergy {
    // Thresholds in z-UNITS (mirror synergy.py).
    static let switchVersatilityMin = 0.25
    static let switchHeightBand = 6.0
    static let shooterFg3Min = 0.0
    static let shooterZoneMin = 0.0
    static let paintRaZ = 1.0

    /// Raw value, None-safe — for absolute fields (height) and rank selection (rim volume).
    private static func raw(_ f: LineupFeatures, _ k: String, _ dflt: Double = 0) -> Double {
        f.value(k) ?? dflt
    }
    /// League z-score via norms; nil (missing value / missing norm / std<=0) -> 0.0.
    private static func z(_ f: LineupFeatures, _ k: String, _ norms: LeagueNorms) -> Double {
        norms.zscore(f.value(k), feature: k) ?? 0.0
    }
    static func isShooter(_ f: LineupFeatures, _ norms: LeagueNorms) -> Bool {
        f.value("fg3_pct") != nil
            && z(f, "fg3_pct", norms) >= shooterFg3Min
            && max(z(f, "z_corner3", norms), z(f, "z_atb3", norms)) >= shooterZoneMin
    }
    private static func isPaintBound(_ f: LineupFeatures, _ norms: LeagueNorms) -> Bool {
        z(f, "z_ra", norms) > paintRaZ && !isShooter(f, norms)
    }
    private static func pairs(_ l: [LineupFeatures]) -> [(LineupFeatures, LineupFeatures)] {
        var out: [(LineupFeatures, LineupFeatures)] = []
        for i in 0..<l.count { for j in (i + 1)..<l.count { out.append((l[i], l[j])) } }
        return out
    }

    static func spacing(_ lineup: [LineupFeatures], _ norms: LeagueNorms) -> Double {
        var bonus = 0.0
        for (a, b) in pairs(lineup) {
            if isShooter(a, norms) && isShooter(b, norms) {
                let comp = abs(z(a, "z_corner3", norms) - z(b, "z_corner3", norms))
                         + abs(z(a, "z_atb3", norms) - z(b, "z_atb3", norms))
                bonus += (z(a, "fg3_pct", norms) + z(b, "fg3_pct", norms)) * (1.0 + 0.25 * comp)
            }
            if isPaintBound(a, norms) && isPaintBound(b, norms) {
                bonus -= (z(a, "z_ra", norms) + z(b, "z_ra", norms))
            }
        }
        return bonus
    }

    static func pnrFit(_ lineup: [LineupFeatures], _ norms: LeagueNorms) -> Double {
        var best = 0.0
        for (a, b) in pairs(lineup) {
            for (creator, other) in [(a, b), (b, a)] {
                let create = max(z(creator, "box_creation", norms), 0.0) * (1.0 + max(z(creator, "passer_rtg", norms), 0.0))
                let roll = max(z(other, "z_ra", norms), 0.0) + max(z(other, "orb_pct", norms), 0.0)
                let space = isShooter(other, norms) ? 1.0 : 0.0
                best = max(best, create * (roll + 0.5 * space))
            }
        }
        return best
    }

    static func switchable(_ lineup: [LineupFeatures], _ norms: LeagueNorms) -> Double {
        var n = 0
        for (a, b) in pairs(lineup) {
            if z(a, "versatility", norms) >= switchVersatilityMin, z(b, "versatility", norms) >= switchVersatilityMin,
               abs(raw(a, "height_in", 78) - raw(b, "height_in", 78)) <= switchHeightBand { n += 1 }
        }
        return Double(n)
    }

    static func rimProtection(_ lineup: [LineupFeatures], _ norms: LeagueNorms) -> Double {
        guard let anchorIdx = lineup.indices.max(by: { raw(lineup[$0], "rim_dfga_per36") < raw(lineup[$1], "rim_dfga_per36") })
        else { return 0 }
        let anchor = lineup[anchorIdx]
        let anchorStop = max(z(anchor, "rim_dfga_per36", norms), 0.0) * max(-z(anchor, "rim_def_delta", norms), 0.0)
        let others = lineup.indices.filter { $0 != anchorIdx }.map { lineup[$0] }
        let funnelSum = others.reduce(0.0) { $0 + max(-z($1, "perim_def_delta", norms), 0.0) + max(z($1, "deflections_per36", norms), 0.0) }
        let funnel = funnelSum / Double(max(others.count, 1))
        return anchorStop * (0.5 + funnel)
    }

    static func creationRedundancy(_ lineup: [LineupFeatures], _ norms: LeagueNorms) -> Double {
        let loads = lineup.map { max(z($0, "load", norms), 0.0) }.sorted(by: >)
        return loads.dropFirst().prefix(2).reduce(0, +)   // surplus load beyond the primary hub
    }

    static func magnitudes(_ lineup: [LineupFeatures], _ norms: LeagueNorms) -> [String: Double] {
        ["spacing": spacing(lineup, norms), "pnr_fit": pnrFit(lineup, norms), "switchable": switchable(lineup, norms),
         "rim_protection": rimProtection(lineup, norms), "creation_redundancy": creationRedundancy(lineup, norms)]
    }
}
