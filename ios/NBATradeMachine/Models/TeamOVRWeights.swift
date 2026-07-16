import Foundation

/// Weighted team-OVR rollup — exact port of scripts/ovr_calibration/weights.py::team_weights.
/// Ships behind AppConfig.weightedOvrEnabled (default false).
/// Pure nonisolated logic (app target is MainActor-default; pure logic must be nonisolated).
enum TeamOVRWeights {

    enum Branch: String, Equatable {
        case minutes, depth, flat
    }

    struct Result {
        let branch: Branch
        /// Normalized weights, Σ=5 over rated players.
        let weights: [String: Double]
        /// Usage-tilted normalized weights, Σ=5 over rated players.
        let offWeights: [String: Double]
        let off: Double
        let def: Double
        let rated: Int
        let contributing: Int
    }

    /// Decoupled input type — keeps the algorithm independent of Player internals
    /// and makes parity tests straightforward.
    struct PlayerInput {
        let slug: String
        let off: Double?
        let def: Double?
        let relevance: Player.Relevance?
        let usg: Double?    // convenience alias for relevance?.usg
    }

    /// Compute weighted team OVR.
    /// k and beta are production constants (k=20, beta=0.0); exposed as parameters for parity tests.
    nonisolated static func compute(
        players: [PlayerInput],
        k: Double = 20,
        beta: Double = 0.0,
        expectedSeason: String? = nil,
        leagueUsgMean: Double? = nil
    ) -> Result {

        // Step 1: rated = players where off != nil OR def != nil
        let rated = players.filter { $0.off != nil || $0.def != nil }
        guard !rated.isEmpty else {
            return Result(branch: .flat, weights: [:], offWeights: [:],
                          off: 0, def: 0, rated: 0, contributing: 0)
        }

        // Step 2: relevance validity check
        func isValid(_ p: PlayerInput) -> Bool {
            guard let rel = p.relevance else { return false }
            if let es = expectedSeason, rel.season != es { return false }
            let mpg = rel.mpgSeason
            guard mpg.isFinite, mpg > 0, mpg <= 60 else { return false }
            guard rel.gp >= 1 else { return false }
            return true
        }
        let validRated = rated.filter(isValid)

        // Step 3: shrunk = mpgSeason * gp / (gp + k) for each valid-rated player
        var shrunk: [String: Double] = [:]
        for p in validRated {
            let rel = p.relevance!
            shrunk[p.slug] = rel.mpgSeason * Double(rel.gp) / (Double(rel.gp) + k)
        }
        // Sum in deterministic input order (matches Python's insertion-order sum) —
        // dictionary-order summation could diverge by ULPs at the 96.0 branch boundary.
        let sumShrunk = validRated.reduce(0.0) { $0 + (shrunk[$1.slug] ?? 0) }

        // Step 4: branch selection — exactly one branch
        var branch: Branch = .flat
        var rawWeights: [String: Double] = [:]
        var totalRaw = 0.0

        // Try MINUTES: >=6 valid-rated AND sumShrunk >= 96.0
        if validRated.count >= 6 && sumShrunk >= 96.0 {
            branch = .minutes
            for p in rated {
                rawWeights[p.slug] = shrunk[p.slug] ?? 0.0
            }
            totalRaw = rated.reduce(0.0) { $0 + (rawWeights[$1.slug] ?? 0) }
            if totalRaw == 0 {
                // Fall through — reset to try DEPTH
                branch = .flat
                rawWeights = [:]
                totalRaw = 0
            }
        }

        // Try DEPTH: rated >= 5 (branch is still .flat means minutes didn't fire or fell through)
        if branch == .flat && rated.count >= 5 {
            branch = .depth
            let sorted = rated.sorted { lhs, rhs in
                let lv = (lhs.off ?? 0) + (lhs.def ?? 0)
                let rv = (rhs.off ?? 0) + (rhs.def ?? 0)
                if lv != rv { return lv > rv }
                return lhs.slug < rhs.slug
            }
            for (idx, p) in sorted.enumerated() {
                let rank = idx + 1
                if rank <= 5       { rawWeights[p.slug] = 1.0 }
                else if rank <= 8  { rawWeights[p.slug] = 0.5 }
                else               { rawWeights[p.slug] = 0.2 }
            }
            totalRaw = sorted.reduce(0.0) { $0 + (rawWeights[$1.slug] ?? 0) }
        }

        // FLAT: fewer than 5 rated (branch still .flat after both checks above)
        if branch == .flat {
            for p in rated { rawWeights[p.slug] = 1.0 }
            totalRaw = rated.reduce(0.0) { $0 + (rawWeights[$1.slug] ?? 0) }
        }

        // Step 5: normalize — w_i = 5 * raw_i / Σraw over rated players
        var normWeights: [String: Double] = [:]
        for p in rated {
            normWeights[p.slug] = totalRaw > 0
                ? 5.0 * (rawWeights[p.slug] ?? 0) / totalRaw
                : 0.0
        }

        // Step 6: def = Σ w_i × (def_i ?? 0); nil channel contributes zero
        let defVal = rated.reduce(0.0) { sum, p in
            sum + (normWeights[p.slug] ?? 0) * (p.def ?? 0)
        }

        // Step 7: usage tilt (offense only); implement even at beta=0 for fixture parity.
        // beta == 0 short-circuits to the exact identity (0 × ∞ would be NaN otherwise),
        // and non-finite usg is treated as missing.
        var mDict: [String: Double] = [:]
        for p in rated {
            if beta != 0, let usg = p.usg, usg.isFinite, let mean = leagueUsgMean {
                let raw = 1.0 + beta * (usg - mean) / 10.0
                mDict[p.slug] = max(0.5, min(1.5, raw))
            } else {
                mDict[p.slug] = 1.0
            }
        }

        var rawOffW: [String: Double] = [:]
        for p in rated {
            rawOffW[p.slug] = (normWeights[p.slug] ?? 0) * (mDict[p.slug] ?? 1.0)
        }
        let sumRawOffW = rated.reduce(0.0) { $0 + (rawOffW[$1.slug] ?? 0) }

        var offWeights: [String: Double] = [:]
        for p in rated {
            offWeights[p.slug] = sumRawOffW > 0
                ? 5.0 * (rawOffW[p.slug] ?? 0) / sumRawOffW
                : 0.0
        }
        let offVal = rated.reduce(0.0) { sum, p in
            sum + (offWeights[p.slug] ?? 0) * (p.off ?? 0)
        }

        // Step 8: contributing = players where w_i > 0
        let contributing = normWeights.values.filter { $0 > 0 }.count

        return Result(branch: branch, weights: normWeights, offWeights: offWeights,
                      off: offVal, def: defVal, rated: rated.count, contributing: contributing)
    }
}
