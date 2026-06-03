import SwiftUI

struct DepthSlot: Identifiable, Hashable {
    let player: Player
    let bestPosition: String
    let secondaryPositions: [String]   // canonical, excludes bestPosition
    let total: Double?                  // v2 display total (dispTotal)
    let off: Double?                    // v2 display offense (dispOff)
    let def: Double?                    // v2 display defense (dispDef)
    var id: String { player.id }
}

struct ColumnResult: Hashable {
    let shown: [DepthSlot]
    let overflow: Int
}

enum TeamDepthChartBuilder {
    static let positions = ["PG", "SG", "SF", "PF", "C"]

    /// Weight applied to the negative (below-average) component when ranking
    /// players for depth. Positive off/def contribute their full L² magnitude;
    /// negative off/def are discounted by this factor so a high-variance
    /// specialist (strong one end, weak the other) is rewarded over a flat
    /// neutral player with the same signed total.
    static let DEPTH_NEG_WEIGHT = 0.5

    /// Offensive axis weight in the depth ORDERING. Offense and defense split a
    /// unit budget (`a` to offense, `1−a` to defense) inside the L², so the
    /// depth chart favors offense the way real rotations do. At a=0.65 an
    /// equal-magnitude scorer earns ~1.36× an equal-magnitude defender, while
    /// defense still carries 35% weight (not sidelined). Calibrated against ESPN
    /// rotation order: depth-order agreement rises sharply from a=0.50 and
    /// flattens past ~0.65. Ordering only — displayed TOT/OFF/DEF and the
    /// green/red highlighting still use the honest two-way l2_signed.
    static let DEPTH_OFF_WEIGHT = 0.65

    /// Diminishing-returns knee for a single axis in the depth ORDERING. An axis
    /// magnitude counts linearly up to `DEPTH_SAT_KNEE`; the part beyond the knee
    /// is credited at `DEPTH_SAT_SLOPE`. This makes a redundant extreme value
    /// (e.g. a fifth elite defender on a defense-stacked roster) worth less at
    /// the margin, so a balanced or offense-contributing player rises when one
    /// axis is already very high — and vice versa. Ordering only.
    static let DEPTH_SAT_KNEE = 2.5
    static let DEPTH_SAT_SLOPE = 0.5

    /// Concave soft-knee saturation of a non-negative axis magnitude: linear up
    /// to `knee`, then shallower (`slope`) above it.
    static func saturate(_ x: Double,
                         knee: Double = DEPTH_SAT_KNEE,
                         slope: Double = DEPTH_SAT_SLOPE) -> Double {
        x <= knee ? x : knee + (x - knee) * slope
    }

    /// Above-average-offense ("OFF in the green") bonus in the depth ORDERING.
    /// Offense above the league median (v2 off is league-centered near 0, so
    /// `max(0, off)`) earns an extra linear reward, so an offensive star
    /// (e.g. Brunson off +4 / def −3) is ranked over a balanced role player
    /// (e.g. McBride off +2.1 / def +1.2) the way real rotations start them.
    /// Calibrated vs ESPN order: lifts starter-match 61.3%→64.7% at 0.30. (A
    /// per-player "don't reward offense when DEF is red" guardrail was tested
    /// and HURT the match — the stars ESPN starts are themselves defensive
    /// minuses — so it is intentionally omitted.) Ordering only.
    static let DEPTH_OFF_GREEN_WEIGHT = 0.30

    /// Offense-weighted, diminishing-returns reduced-negative L² depth score,
    /// plus an above-average-offense bonus. Each axis magnitude is first
    /// soft-knee `saturate`d (extreme single-axis values count for less); the
    /// positive parts add a weighted L² norm (offense weight `a`, defense
    /// `1−a`), the negative parts subtract a `mu`-scaled weighted L² norm, and
    /// `greenBonus`·max(0, off) rewards above-median offense. nil inputs → 0.
    /// Used ONLY to order players within a depth slot — never displayed.
    static func depthScore(off: Double?, def: Double?,
                           mu: Double = DEPTH_NEG_WEIGHT,
                           a: Double = DEPTH_OFF_WEIGHT) -> Double {
        let o = off ?? 0, d = def ?? 0
        func pos(_ x: Double) -> Double { saturate(max(x, 0)) }
        func neg(_ x: Double) -> Double { saturate(max(-x, 0)) }
        let positive = (a * pos(o) * pos(o) + (1 - a) * pos(d) * pos(d)).squareRoot()
        let negative = (a * neg(o) * neg(o) + (1 - a) * neg(d) * neg(d)).squareRoot()
        return positive - mu * negative + DEPTH_OFF_GREEN_WEIGHT * max(o, 0)
    }

    static func canonical(_ raw: String) -> String? {
        let s = raw.uppercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "PG", "SG", "SF", "PF", "C": return s
        case "G": return "PG"
        case "F": return "SF"
        case "F-C", "FC", "C-F", "CF": return "PF"
        case "G-F", "GF", "F-G", "FG": return "SF"
        default:
            let token = s.split(whereSeparator: { "-/ ".contains($0) })
                .first.map(String.init) ?? ""
            switch token {
            case "PG", "SG", "SF", "PF", "C": return token
            case "G": return "PG"
            case "F": return "SF"
            default: return nil
            }
        }
    }

    static func roleProfile(_ p: Player) -> (best: String, secondaries: [String], columns: [String])? {
        if let elig = p.positionEligibility,
           let primaryRaw = elig.primary, let best = canonical(primaryRaw) {
            let ordered = elig.eligible
                .sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
                .compactMap { canonical($0.position) }
            var columns: [String] = []
            for c in ordered where !columns.contains(c) { columns.append(c) }
            if !columns.contains(best) { columns.insert(best, at: 0) }
            let secondaries = columns.filter { $0 != best }
            return (best, secondaries, columns)
        }
        guard let best = canonical(p.position) else { return nil }
        return (best, [], [best])
    }

    /// Per-player view used by the layer-based assignment.
    private struct Profile {
        let slot: DepthSlot
        let primary: String          // canonical ESPN primary (a valid column)
        let eligible: [String]       // canonical eligible columns (incl. primary)
        let rank: Double             // depthScore(dispOff, dispDef); nil inputs → 0
        var id: String { slot.player.id }
    }

    /// Layer-based two-pass assignment. Pass 1 fills each position's column
    /// top-down with the players whose PRIMARY is that position (best total at
    /// the top). Pass 2 backfills empty cells with adjacent-eligible players,
    /// never placing a player twice on the same layer or twice in the same
    /// column. `overflow` per position reflects extra PRIMARIES that didn't fit.
    static func columns(for roster: [Player], cap: Int = 4) -> [String: ColumnResult] {
        // 1. Build profiles; skip players without a canonical primary column.
        var profiles: [Profile] = []
        for p in roster {
            guard let role = roleProfile(p) else { continue }
            guard positions.contains(role.best) else { continue }
            let eligible = role.columns.filter { positions.contains($0) }
            let slot = DepthSlot(
                player: p,
                bestPosition: role.best,
                secondaryPositions: role.secondaries,
                total: p.dispTotal,
                off: p.dispOff,
                def: p.dispDef
            )
            profiles.append(Profile(slot: slot, primary: role.best,
                                    eligible: eligible,
                                    rank: depthScore(off: p.dispOff, def: p.dispDef)))
        }

        // Stable ordering helper: depthScore desc, then name. nil off/def
        // collapse to a 0 score (sorts low) inside depthScore.
        func better(_ a: Profile, _ b: Profile) -> Bool {
            if a.rank != b.rank { return a.rank > b.rank }
            return a.slot.player.name < b.slot.player.name
        }

        // grid[pos][layer] = assigned Profile (nil = empty cell)
        var grid: [String: [Profile?]] = [:]
        for pos in positions { grid[pos] = Array(repeating: nil, count: cap) }
        var placedOnLayer: [Set<String>] = Array(repeating: [], count: cap)
        var placedAtPos: [String: Set<String>] = [:]
        for pos in positions { placedAtPos[pos] = [] }
        var primaryCount: [String: Int] = [:]

        // 2. Pass 1 — primaries.
        var byPrimary: [String: [Profile]] = [:]
        for p in profiles { byPrimary[p.primary, default: []].append(p) }
        for pos in positions {
            let group = (byPrimary[pos] ?? []).sorted(by: better)
            primaryCount[pos] = group.count
            for (layer, prof) in group.enumerated() where layer < cap {
                grid[pos]?[layer] = prof
                placedOnLayer[layer].insert(prof.id)
                placedAtPos[pos]?.insert(prof.id)
            }
        }

        // 3. Pass 2 — adjacent depth fill, layer by layer.
        let sortedProfiles = profiles.sorted(by: better)
        for layer in 0..<cap {
            for pos in positions where grid[pos]?[layer] == nil {
                guard let pick = sortedProfiles.first(where: { prof in
                    prof.eligible.contains(pos)
                        && !placedOnLayer[layer].contains(prof.id)
                        && !(placedAtPos[pos]?.contains(prof.id) ?? false)
                }) else { continue }
                grid[pos]?[layer] = pick
                placedOnLayer[layer].insert(pick.id)
                placedAtPos[pos]?.insert(pick.id)
            }
        }

        // 4. Build ColumnResult per position.
        var result: [String: ColumnResult] = [:]
        for pos in positions {
            let shown = (grid[pos] ?? []).compactMap { $0?.slot }
            let overflow = max(0, (primaryCount[pos] ?? 0) - shown.count)
            result[pos] = ColumnResult(shown: shown, overflow: overflow)
        }
        return result
    }

    // MARK: - League-wide per-layer statistics (Part A)

    /// Sigma band for green/red highlighting: a value is "above" when it is
    /// more than this many population-std above the layer mean, "below" when
    /// more than this many below, otherwise neutral.
    static let layerHighlightSigma: Double = 0.75

    /// Mean + population std for one metric across a sample.
    struct MetricStats: Equatable {
        let mean: Double
        let std: Double
    }

    /// Per-layer league statistics. `playerByLayer[L]` describes the
    /// distribution of every SHOWN player slot's TOT/OFF/DEF at layer L across
    /// the league. `totalByLayer[L]` describes the distribution of each TEAM's
    /// layer-L summed TOT/OFF/DEF.
    struct LeagueLayerStats {
        let playerByLayer: [Int: (tot: MetricStats, off: MetricStats, def: MetricStats)]
        let totalByLayer: [Int: (tot: MetricStats, off: MetricStats, def: MetricStats)]
    }

    enum Highlight { case above, below, neutral }

    /// Classify a value against a metric distribution. nil value or zero std
    /// (degenerate / single sample) → neutral.
    static func highlight(_ v: Double?, _ s: MetricStats,
                          sigma: Double = layerHighlightSigma) -> Highlight {
        guard let v, s.std > 0 else { return .neutral }
        if v > s.mean + sigma * s.std { return .above }
        if v < s.mean - sigma * s.std { return .below }
        return .neutral
    }

    /// Sum the filled position cells at a given layer of one team's columns.
    static func layerTotals(_ columns: [String: ColumnResult],
                            layer: Int) -> (tot: Double, off: Double, def: Double) {
        var tot = 0.0, off = 0.0, def = 0.0
        for pos in positions {
            guard let shown = columns[pos]?.shown, layer < shown.count else { continue }
            let slot = shown[layer]
            tot += slot.total ?? 0
            off += slot.off ?? 0
            def += slot.def ?? 0
        }
        return (tot, off, def)
    }

    /// Population mean + std of a sample. n < 2 → std 0 (neutral highlighting).
    private static func meanStd(_ xs: [Double]) -> MetricStats {
        guard !xs.isEmpty else { return MetricStats(mean: 0, std: 0) }
        let mean = xs.reduce(0, +) / Double(xs.count)
        guard xs.count >= 2 else { return MetricStats(mean: mean, std: 0) }
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return MetricStats(mean: mean, std: variance.squareRoot())
    }

    /// Build per-layer league statistics from every team's roster. For each
    /// layer it collects (a) every shown player slot's TOT/OFF/DEF league-wide
    /// (PLAYER stats) and (b) each team's layer-L summed TOT/OFF/DEF (TOTAL
    /// stats). Missing TOT/OFF/DEF count as 0 in the team totals.
    static func leagueLayerStats(rostersByTeam: [String: [Player]],
                                 cap: Int = 4) -> LeagueLayerStats {
        var playerTot = Array(repeating: [Double](), count: cap)
        var playerOff = Array(repeating: [Double](), count: cap)
        var playerDef = Array(repeating: [Double](), count: cap)
        var teamTot = Array(repeating: [Double](), count: cap)
        var teamOff = Array(repeating: [Double](), count: cap)
        var teamDef = Array(repeating: [Double](), count: cap)

        for (_, roster) in rostersByTeam {
            let cols = columns(for: roster, cap: cap)
            for layer in 0..<cap {
                var filled = false
                for pos in positions {
                    guard let shown = cols[pos]?.shown, layer < shown.count else { continue }
                    filled = true
                    let slot = shown[layer]
                    if let t = slot.total { playerTot[layer].append(t) }
                    if let o = slot.off { playerOff[layer].append(o) }
                    if let d = slot.def { playerDef[layer].append(d) }
                }
                // Only count a team's layer total when the layer has cells.
                if filled {
                    let t = layerTotals(cols, layer: layer)
                    teamTot[layer].append(t.tot)
                    teamOff[layer].append(t.off)
                    teamDef[layer].append(t.def)
                }
            }
        }

        var playerByLayer: [Int: (tot: MetricStats, off: MetricStats, def: MetricStats)] = [:]
        var totalByLayer: [Int: (tot: MetricStats, off: MetricStats, def: MetricStats)] = [:]
        for layer in 0..<cap {
            playerByLayer[layer] = (meanStd(playerTot[layer]),
                                    meanStd(playerOff[layer]),
                                    meanStd(playerDef[layer]))
            totalByLayer[layer] = (meanStd(teamTot[layer]),
                                   meanStd(teamOff[layer]),
                                   meanStd(teamDef[layer]))
        }
        return LeagueLayerStats(playerByLayer: playerByLayer, totalByLayer: totalByLayer)
    }
}
