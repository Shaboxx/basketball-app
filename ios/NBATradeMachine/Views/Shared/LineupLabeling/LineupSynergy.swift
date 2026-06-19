import Foundation

/// Swift port of scripts/lineup_value/synergy.py — the 5 pairwise capability magnitudes over a
/// lineup's RAW LineupFeatures (z-scores, fractions, inches). Kept in lock-step with the Python
/// (parity asserted in LineupSynergyTests). Pure.
nonisolated enum LineupSynergy {
    static let switchVersatilityMin = 0.25
    static let switchHeightBand = 6.0
    static let shooterFg3Min = 0.34
    static let shooterZoneMin = 0.0

    private static func g(_ f: LineupFeatures, _ k: String, _ dflt: Double = 0) -> Double {
        f.value(k) ?? dflt
    }
    static func isShooter(_ f: LineupFeatures) -> Bool {
        g(f, "fg3_pct") >= shooterFg3Min && max(g(f, "z_corner3"), g(f, "z_atb3")) >= shooterZoneMin
    }
    private static func isPaintBound(_ f: LineupFeatures) -> Bool {
        g(f, "z_ra") > 0.5 && !isShooter(f)
    }
    private static func pairs(_ l: [LineupFeatures]) -> [(LineupFeatures, LineupFeatures)] {
        var out: [(LineupFeatures, LineupFeatures)] = []
        for i in 0..<l.count { for j in (i + 1)..<l.count { out.append((l[i], l[j])) } }
        return out
    }

    static func spacing(_ lineup: [LineupFeatures]) -> Double {
        var bonus = 0.0
        for (a, b) in pairs(lineup) {
            if isShooter(a) && isShooter(b) {
                let comp = abs(g(a, "z_corner3") - g(b, "z_corner3")) + abs(g(a, "z_atb3") - g(b, "z_atb3"))
                bonus += (g(a, "fg3_pct") + g(b, "fg3_pct")) * (1.0 + 0.25 * comp)
            }
            if isPaintBound(a) && isPaintBound(b) { bonus -= (g(a, "z_ra") + g(b, "z_ra")) }
        }
        return bonus
    }

    static func pnrFit(_ lineup: [LineupFeatures]) -> Double {
        var best = 0.0
        for (a, b) in pairs(lineup) {
            for (creator, other) in [(a, b), (b, a)] {
                let create = max(g(creator, "box_creation"), 0.0) * (1.0 + max(g(creator, "passer_rtg"), 0.0) / 10.0)
                let roll = max(g(other, "z_ra"), 0.0) + max(g(other, "orb_pct") * 10.0, 0.0)
                let space = isShooter(other) ? 1.0 : 0.0
                best = max(best, create * (roll + 0.5 * space))
            }
        }
        return best
    }

    static func switchable(_ lineup: [LineupFeatures]) -> Double {
        var n = 0
        for (a, b) in pairs(lineup) {
            if g(a, "versatility") >= switchVersatilityMin, g(b, "versatility") >= switchVersatilityMin,
               abs(g(a, "height_in", 78) - g(b, "height_in", 78)) <= switchHeightBand { n += 1 }
        }
        return Double(n)
    }

    static func rimProtection(_ lineup: [LineupFeatures]) -> Double {
        guard let anchorIdx = lineup.indices.max(by: { g(lineup[$0], "rim_dfga_per36") < g(lineup[$1], "rim_dfga_per36") })
        else { return 0 }
        let anchor = lineup[anchorIdx]
        let anchorStop = g(anchor, "rim_dfga_per36") * max(-g(anchor, "rim_def_delta"), 0.0)
        let others = lineup.indices.filter { $0 != anchorIdx }.map { lineup[$0] }
        let funnelSum = others.reduce(0.0) { $0 + max(-g($1, "perim_def_delta"), 0.0) + g($1, "deflections_per36") / 10.0 }
        let funnel = funnelSum / Double(max(others.count, 1))
        return anchorStop * (0.5 + funnel)
    }

    static func creationRedundancy(_ lineup: [LineupFeatures]) -> Double {
        let loads = lineup.map { max(g($0, "load"), 0.0) }.sorted(by: >)
        return loads.dropFirst().prefix(2).reduce(0, +)   // surplus load beyond the primary hub
    }

    static func magnitudes(_ lineup: [LineupFeatures]) -> [String: Double] {
        ["spacing": spacing(lineup), "pnr_fit": pnrFit(lineup), "switchable": switchable(lineup),
         "rim_protection": rimProtection(lineup), "creation_redundancy": creationRedundancy(lineup)]
    }
}
