import Foundation

/// Sum a roster's 9-category z-vectors and expose a strength-first ordering, plus a
/// points-format fantasy-points/game total. Pure — inputs are already-resolved
/// `FantasyValue`s (the caller drops store misses). Reuses `FantasyCategoryOrder`
/// so team-level ordering matches the per-player breakdown label set exactly
/// (labels: "PTS","REB","AST","STL","BLK","TO","3PM","FG%","FT%").
nonisolated enum FantasyTeamProfile {

    /// Element-wise sum of `categoryZ` across the roster (turnovers already
    /// sign-flipped server-side: positive `to` = good, so a plain sum is correct).
    static func categoryTotals(_ values: [FantasyValue]) -> FantasyValue.CategoryZ {
        values.reduce(.zero) { a, fv in
            let z = fv.categoryZ
            return FantasyValue.CategoryZ(
                pts: a.pts + z.pts,   reb: a.reb + z.reb,   ast: a.ast + z.ast,
                stl: a.stl + z.stl,   blk: a.blk + z.blk,   to:  a.to  + z.to,
                fg3m: a.fg3m + z.fg3m, fgPct: a.fgPct + z.fgPct, ftPct: a.ftPct + z.ftPct)
        }
    }

    /// (label, z) pairs sorted descending — strengths first, weaknesses last.
    static func ordered(_ totals: FantasyValue.CategoryZ) -> [(label: String, z: Double)] {
        FantasyCategoryOrder.ordered(totals)   // shared label set + descending sort
    }

    /// Summed projected fantasy points/game for the active POINTS format (0 for cat formats).
    static func fpPerGameTotal(_ values: [FantasyValue], format: FantasyFormat) -> Double {
        values.reduce(0) { $0 + (format.entry(in: $1).fpPerGame ?? 0) }
    }
}

/// Sum of tradeable per-player value for a side, in a VALUE-ABOVE-REPLACEMENT
/// currency. Honors dynasty on/off precisely:
///   • dynasty ON  → `FantasyValueMath.dynastyAdjustedValue` = max(0, value − repl) × dynastyFactor.
///   • dynasty OFF → max(0, value − repl)   (value-above-replacement, floored, NO factor).
/// The meta-absent branch is a PRE-LOAD PLACEHOLDER only (values + `_meta` load together);
/// it is floored on BOTH dynasty paths so the number can only move in the same direction
/// once meta arrives.
nonisolated enum FantasySideValue {

    static func playerValue(_ fv: FantasyValue, meta: FantasyMeta?,
                            format: FantasyFormat, dynastyOn: Bool) -> Double {
        let entry = format.entry(in: fv)
        guard let meta else {
            return dynastyOn ? max(0, entry.value) * fv.dynastyFactor
                             : max(0, entry.value)
        }
        if dynastyOn {
            return FantasyValueMath.dynastyAdjustedValue(fv, meta, format: format)
        } else {
            return max(0, entry.value - format.replacement(in: meta))
        }
    }

    static func sum(_ values: [FantasyValue], meta: FantasyMeta?,
                    format: FantasyFormat, dynastyOn: Bool) -> Double {
        values.reduce(0) { $0 + playerValue($1, meta: meta, format: format, dynastyOn: dynastyOn) }
    }
}

/// One human-readable verdict line derived from the swing.
nonisolated struct FantasyTradeFlag: Equatable, Hashable {
    enum Kind: Equatable { case gain, loss, neutral }
    let kind: Kind
    let text: String
}

/// The per-side verdict: net value delta, per-category delta vector, and (points
/// formats only) an fp/game delta, plus derived flags.
nonisolated struct FantasyTradeSwing: Equatable {
    let netValue: Double                        // incoming value − outgoing value
    let categoryDelta: FantasyValue.CategoryZ   // per-category: incoming − outgoing
    let fpPerGameDelta: Double?                 // set only when `format.isPoints`
    let flags: [FantasyTradeFlag]
}

/// Pure fantasy-trade evaluation for ONE side. `incoming`/`outgoing` are resolved
/// `FantasyValue`s for that side; `teamProfile` is that side's CURRENT (pre-trade)
/// summed `categoryZ`, used to phrase "addresses a weakness" vs "adds to a strength".
nonisolated enum FantasyTradeMath {

    /// Value epsilon under which the net is reported "roughly even".
    static let valueEpsilon = 0.5
    /// Per-category |delta| under which a category flag is suppressed as noise.
    static let categoryEpsilon = 0.5

    static func swing(incoming: [FantasyValue], outgoing: [FantasyValue],
                      teamProfile: FantasyValue.CategoryZ,
                      meta: FantasyMeta?, format: FantasyFormat, dynastyOn: Bool) -> FantasyTradeSwing {
        let net = FantasySideValue.sum(incoming, meta: meta, format: format, dynastyOn: dynastyOn)
                - FantasySideValue.sum(outgoing, meta: meta, format: format, dynastyOn: dynastyOn)

        let delta = subtract(FantasyTeamProfile.categoryTotals(incoming),
                             FantasyTeamProfile.categoryTotals(outgoing))

        let fp: Double? = format.isPoints
            ? FantasyTeamProfile.fpPerGameTotal(incoming, format: format)
            - FantasyTeamProfile.fpPerGameTotal(outgoing, format: format)
            : nil

        return FantasyTradeSwing(
            netValue: net, categoryDelta: delta, fpPerGameDelta: fp,
            flags: flags(net: net, delta: delta, teamProfile: teamProfile, format: format, fpDelta: fp))
    }

    // MARK: helpers
    static func subtract(_ a: FantasyValue.CategoryZ, _ b: FantasyValue.CategoryZ) -> FantasyValue.CategoryZ {
        FantasyValue.CategoryZ(
            pts: a.pts - b.pts, reb: a.reb - b.reb, ast: a.ast - b.ast,
            stl: a.stl - b.stl, blk: a.blk - b.blk, to:  a.to  - b.to,
            fg3m: a.fg3m - b.fg3m, fgPct: a.fgPct - b.fgPct, ftPct: a.ftPct - b.ftPct)
    }

    private static func flags(net: Double, delta: FantasyValue.CategoryZ,
                              teamProfile: FantasyValue.CategoryZ,
                              format: FantasyFormat, fpDelta: Double?) -> [FantasyTradeFlag] {
        var out: [FantasyTradeFlag] = []

        // 1) Always: a value verdict.
        if net > valueEpsilon {
            out.append(.init(kind: .gain, text: String(format: "You come out ahead on fantasy value (+%.1f).", net)))
        } else if net < -valueEpsilon {
            out.append(.init(kind: .loss, text: String(format: "You give up more value than you get (%.1f).", net)))
        } else {
            out.append(.init(kind: .neutral, text: "Roughly even on fantasy value."))
        }

        // 2) Points formats: a single fp/game line, no category flags.
        if format.isPoints, let fp = fpDelta {
            let kind: FantasyTradeFlag.Kind = fp > 0 ? .gain : (fp < 0 ? .loss : .neutral)
            out.append(.init(kind: kind, text: String(format: "Projected fantasy points/game change by %+.1f.", fp)))
            return out
        }

        // 3) Category formats: most-improved + most-hurt category, phrased vs the profile.
        let profile = Dictionary(uniqueKeysWithValues:
            FantasyCategoryOrder.ordered(teamProfile).map { ($0.label, $0.z) })
        let ranked = FantasyCategoryOrder.ordered(delta)   // desc: first = most gained, last = most lost
        if let best = ranked.first, best.z > categoryEpsilon {
            let weak = (profile[best.label] ?? 0) < 0
            out.append(.init(kind: .gain, text: weak
                ? String(format: "Addresses your %@ weakness (%+.2f).", best.label, best.z)
                : String(format: "Adds to your %@ strength (%+.2f).", best.label, best.z)))
        }
        if let worst = ranked.last, worst.z < -categoryEpsilon {
            let weak = (profile[worst.label] ?? 0) < 0
            out.append(.init(kind: .loss, text: weak
                ? String(format: "Worsens your %@ weakness (%+.2f).", worst.label, worst.z)
                : String(format: "Trims your %@ strength (%+.2f).", worst.label, worst.z)))
        }
        return out
    }
}
