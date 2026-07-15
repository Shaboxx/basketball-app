import Foundation

/// PURE, `nonisolated` spatial-lineup metrics for sub-project C: member-state resolution,
/// the overlap / geometry / diet / corner formulas, and the memo fingerprint. No SwiftUI, no
/// store — a deterministic function of the five members' `PlayerShotChart`s + named constants,
/// so it is unit-testable and computed off the render path. Mirrors `HeatField`'s purity.
nonisolated enum SpatialLineupMetrics {

    // MARK: - Named constants

    // --- member usability + section gate ---
    static let USABLE_MIN_FGA = 60             // A's FGA_SUPPRESS_FLOOR: usable iff chart present AND meta.fga >= this
    static let MIN_USABLE_MEMBERS = 3
    static let MIN_COMBINED_USABLE_FGA = 300

    // --- perimeter (reuse A's constants, verbatim) ---
    static let PERIM_3SHARE_PCT = 65.0         // == ShotProfileInsight.PCT_ABOVE
    static let PERIM_3FG_MIN = 0.34            // == ShotProfileInsight.FLOOR_SPACER_3FG_MIN
    static let LONE_PERIM_VOL_SHARE = 0.55
    static let FIVE_OUT_MIN_3SHARE_PCT = 35.0

    // --- interior ---
    static let RIM_HEAVY_PCT = 75.0
    static let RIM_HEAVY_VALUE_MIN = 0.30
    static let RIM_CROWD_MIN_COUNT = 2

    // --- corners ---
    static let CORNER_MIN_FGA = 20
    static let CORNER_MIN_SHARE = 0.06

    // --- shot diet (lineup-weighted) — CALIBRATED (Task 2, 30 real depth-order starting fives,
    //     rank-1 per position, 14 within-position rank fallbacks; 2026-07-14 calibration run) ---
    static let MIDHEAVY_MIN = 0.15             // p75 lineupMidShare over 30 lineups (dist: n=30 min=0.036 p25=0.094 median=0.124 p75=0.146 max=0.260); spec provisional was 0.30
    static let MIDHEAVY_MAX_3SHARE = 0.38      // p50 lineup3Share over 30 lineups (dist: n=30 min=0.273 p25=0.322 median=0.378 p75=0.428 max=0.529); spec provisional was 0.32
    // CE-2 (final-review honesty floor): the calibrated MIDHEAVY_MIN (0.15) is only ~p75 of a league where
    // mid-tilt is rare, so it can fire on a lineup that is NOT genuinely mid-heavy in an absolute sense.
    // Guard rule 9 with an ABSOLUTE floor: fire only when lineupMidShare >= max(MIDHEAVY_MIN, MIDHEAVY_ABS_MIN).
    static let MIDHEAVY_ABS_MIN = 0.22         // ~a genuinely mid-tilted diet; a future recalibration cannot silently drop below this

    // --- geometry — CALIBRATED (Task 2, 30 real depth-order starting fives; 2026-07-14 run) ---
    static let OVERLAP_HIGH = 0.95             // p75 overlapIndex over 30 lineups (dist: n=30 min=0.839 p25=0.918 median=0.931 p75=0.949 max=0.984); spec provisional was 0.35
    static let OVERLAP_MID = 0.93              // p50 overlapIndex over 30 lineups (median 0.931, same dist); spec provisional was 0.22
    // CE-3 (final-review): rule 4 (sharedOverlap ⇒ compress) is GATED OFF. The calibrated overlapIndex has
    // no discriminating range over real lineups (30 real fives: min 0.839, median 0.931, max 0.984 — nearly
    // every lineup shares heavily), so an "overlap ⇒ compress" conclusion pinned ~2pp above the median would
    // mislead: it fires on essentially all lineups and reads a league-universal fact as a distinctive flaw.
    // The VISUAL overlap layer still answers "where do they overlap"; only the verbal rule is suppressed.
    // Revisit when an on-court-together baseline exists (V2) that gives overlap a real discriminating range.
    static let SHARED_OVERLAP_ENABLED = false
    // --- heat-model v2 hot-cell overlap (rule 4 re-enable, section 9.4) ---
    // PROVENANCE (2026-07-14 recalibration, calibrate_lineup_metrics.py over the 30 real depth-order
    // fives, league field leagueMeanPPS=1.0913 / LEAGUE_MIN_MASS=200):
    //   hotOverlapNonRim dist: n=30 min=0.494 p10=0.561 p25=0.642 median=0.681 p75=0.746 p90=0.794 max=0.885
    //   (0 lineups with an empty non-RA hot union.)
    //   Criteria (spec 9.4): spread(p90-p10)=0.234 — FAILED (need >= 0.25); p75 pin fires on 27% — passed (<= 40%).
    //   RULE 4 RE-ENABLE: NO -> SHARED_OVERLAP_ENABLED stays false. The hot-cell redefinition DID create
    //   real range for the first time (0.494–0.885 vs the raw-mass 0.839–0.984), but the spread criterion
    //   narrowly missed, and the pinned criteria are binding — no post-hoc threshold bending. Rule 4 stays
    //   suppressed pending an on-court-together baseline (V2). rule4Body's copy path stays tested directly.
    static let HOT_OVERLAP_PIN = 0.746         // p75 hotOverlapNonRim (2026-07-14 run above; unused while the flag is off)
    static let HOT_OVERLAP_ABS_MIN = 0.30      // PINNED absolute floor: a genuinely shared hot court, not p75 of a still-clustered league
    static let DISPERSION_TIGHT = 31.3         // p25 centroidDispersion (court units) over 30 lineups (dist: n=30 min=18.533 p25=31.339 median=39.785 p75=54.306 max=68.121); spec provisional was 90 (~9 ft)
    static let SIDE_SKEW_MIN = 0.09            // p75 sideSkew over 30 lineups (dist: n=30 min=0.003 p25=0.024 median=0.065 p75=0.092 max=0.230); spec provisional was 0.45
    // CE-1 (final-review honesty floor): the calibrated SIDE_SKEW_MIN (0.09) is only ~p75 of a league where
    // side-symmetry is the norm, so it can fire at a barely-perceptible ~55/45 split. Guard rule 10 with an
    // ABSOLUTE floor: fire only when sideSkew >= max(SIDE_SKEW_MIN, SIDE_SKEW_ABS_MIN). S=0.20 ≈ a 60/40
    // dominant split ((1+S)/2), the point where "tilts to one side" is a defensible read.
    static let SIDE_SKEW_ABS_MIN = 0.20        // ≈60/40 dominant split; a future recalibration cannot silently drop below this
    static let SIDE_SKEW_MIN_ATTEMPTS = 100
    static let SIDE_CENTER_BAND = 25.0         // |x| < this excluded from a side

    // --- confidence (A house style) ---
    static let FGA_MODERATE_MAX = 350          // == ShotProfileInsight.FGA_MODERATE_MAX (min usable fga ceiling)
    static let EARNED_HIGH_DISTANCE = 30.0     // == ShotProfileInsight.EARNED_HIGH_DISTANCE

    // --- canonical corner zone keys (verbatim court.ZONES) ---
    static let LEFT_CORNER = "Left Corner 3"
    static let RIGHT_CORNER = "Right Corner 3"
    static let ALL_ZONES = ["Restricted Area", "In The Paint (Non-RA)", "Mid-Range",
                            "Left Corner 3", "Right Corner 3", "Above the Break 3"]

    // --- paint region for paintOverlap (matches A/B court geometry) ---
    static let PAINT_Y_MAX = 142.0
    static let PAINT_X_ABS = 80.0

    // MARK: - Inputs + member state

    /// One supplied lineup slot: a display name, its slug, and its (possibly nil) season chart.
    struct MemberInput: Equatable {
        let name: String
        let slug: String
        let chart: PlayerShotChart?
    }

    enum MemberState: String { case usable, thin, missing }

    /// usable iff chart present AND meta.fga >= 60; thin iff present AND 0 < fga < 60; missing otherwise.
    static func state(for chart: PlayerShotChart?) -> MemberState {
        guard let c = chart, c.meta.fga > 0 else { return .missing }
        return c.meta.fga >= USABLE_MIN_FGA ? .usable : .thin
    }

    // MARK: - Overlap (raw mass; feeds BOTH the render layer and overlapIndex)

    /// k_c per cell = #{ grid g : g[c] >= HeatField.minMass }. One computation for render + metric.
    static func overlapCounts(grids: [[Double]]) -> [Int] {
        let n = 26 * 24
        guard let first = grids.first else { return [Int](repeating: 0, count: n) }
        precondition(first.count == n)
        return (0..<n).map { c in grids.reduce(0) { $0 + ($1[c] >= HeatField.minMass ? 1 : 0) } }
    }

    /// union-denominator overlap ratio over usable members' raw mass grids. nil when the union
    /// (any usable member's in-bounds mass) is empty. Range [0,1].
    static func overlapIndex(grids: [[Double]]) -> Double? {
        overlapRatio(grids: grids) { _ in true }
    }
    /// paintOverlap = the same ratio restricted to paint cells (y<=142, |x|<=80). nil if no paint union.
    static func paintOverlap(grids: [[Double]]) -> Double? {
        overlapRatio(grids: grids) { c in
            let col = c % 26, row = c / 26
            let cx = HeatField.xMin + Double(col) * HeatField.spacing
            let cy = HeatField.yMin + Double(row) * HeatField.spacing
            return cy <= PAINT_Y_MAX && abs(cx) <= PAINT_X_ABS
        }
    }
    private static func overlapRatio(grids: [[Double]], include: (Int) -> Bool) -> Double? {
        guard !grids.isEmpty else { return nil }
        let k = overlapCounts(grids: grids)
        var union = 0, inter = 0
        for c in 0..<k.count where include(c) {
            if k[c] >= 1 { union += 1 }
            if k[c] >= 2 { inter += 1 }
        }
        return union == 0 ? nil : Double(inter) / Double(union)
    }

    /// #{ usable members whose massGrid has >= HeatField.minMass mass in AT LEAST ONE overlap cell
    /// (a cell where k_c >= 2) }. This is the count that ACTUALLY contributes to the shared area —
    /// NOT usableCharts.count. A member piling mass only in disjoint cells shares nothing and is not
    /// counted. 0 when there is no overlap cell (no k_c >= 2). Feeds rule 4's contributor bullet.
    static func overlapContributorCount(grids: [[Double]]) -> Int {
        guard !grids.isEmpty else { return 0 }
        let k = overlapCounts(grids: grids)
        let overlapCells = (0..<k.count).filter { k[$0] >= 2 }
        guard !overlapCells.isEmpty else { return 0 }
        return grids.reduce(0) { acc, g in
            acc + (overlapCells.contains(where: { g[$0] >= HeatField.minMass }) ? 1 : 0)
        }
    }

    // MARK: - Hot-cell overlap (heat-model v2, efficiency-aware; sections 9.1-9.3)

    /// Hot cells for one usable member: indices c where massGrid_m[c] >= minMass AND p̂ > L_c
    /// (equivalently V_m(c) > 0; damping-independent). `made` mass recomputed per cell via
    /// massAndMade; a cell where league[c] is NaN is never hot (no defined baseline).
    static func memberHotCells(points: [PlayerShotChart.ShotPoint], league: [Double]) -> Set<Int> {
        guard league.count == 26 * 24 else { return [] }
        var hot = Set<Int>()
        for row in 0..<24 {
            let cy = HeatField.yMin + Double(row) * HeatField.spacing
            for col in 0..<26 {
                let cx = HeatField.xMin + Double(col) * HeatField.spacing
                let idx = row * 26 + col
                let Lc = league[idx]
                if Lc.isNaN { continue }
                let (A, M) = HeatField.massAndMade(points: points, cx: cx, cy: cy)
                if A < HeatField.minMass { continue }
                let pHat = (M + HeatField.priorWeight * Lc) / (A + HeatField.priorWeight)
                if pHat > Lc { hot.insert(idx) }
            }
        }
        return hot
    }

    /// k_hot_c = #{ usable member m : c in memberHotCells(m) }. A cell is a visual overlap
    /// cell iff k_hot_c >= 2 (all cells, section 9.2).
    static func hotOverlapCounts(memberHotSets: [Set<Int>]) -> [Int] {
        (0..<(26 * 24)).map { c in memberHotSets.reduce(0) { $0 + ($1.contains(c) ? 1 : 0) } }
    }

    /// A cell is restricted-area iff its center is within 40 court units of the hoop (0,0)
    /// (section 9.3). Over real centers this is exactly {38,39,63,64,65,66,89,90,91,92,116,117}.
    static func isRAcell(_ c: Int) -> Bool {
        let col = c % 26, row = c / 26
        let cx = HeatField.xMin + Double(col) * HeatField.spacing
        let cy = HeatField.yMin + Double(row) * HeatField.spacing
        return (cx * cx + cy * cy) <= 1600.0
    }

    /// hotOverlapNonRim = |{c: k_hot_c >= 2 AND non-RA}| / |{c: k_hot_c >= 1 AND non-RA}|
    /// (section 9.3). nil when the non-RA union is empty. Range [0,1].
    static func hotOverlapNonRim(memberHotSets: [Set<Int>]) -> Double? {
        let k = hotOverlapCounts(memberHotSets: memberHotSets)
        var union = 0, inter = 0
        for c in 0..<k.count where !isRAcell(c) {
            if k[c] >= 1 { union += 1 }
            if k[c] >= 2 { inter += 1 }
        }
        return union == 0 ? nil : Double(inter) / Double(union)
    }

    // MARK: - Perimeter

    /// #{ usable member with threeShare.pct >= 65 AND threeFgPct.value >= 0.34 }. A nil profile
    /// or a missing signal is NOT counted.
    static func perimeterShooterCount(profiles: [PlayerShotChart.Profile?]) -> Int {
        profiles.reduce(0) { acc, p in
            guard let p, let three = p.signals["threeShare"], let fg = p.signals["threeFgPct"] else { return acc }
            return acc + (three.pct >= PERIM_3SHARE_PCT && fg.value >= PERIM_3FG_MIN ? 1 : 0)
        }
    }
    /// Data-absence guard (rules 1 + 2): every usable member must carry BOTH threeShare AND threeFgPct.
    static func everyUsableHasPerimeterSignals(profiles: [PlayerShotChart.Profile?]) -> Bool {
        profiles.allSatisfy { p in
            guard let p else { return false }
            return p.signals["threeShare"] != nil && p.signals["threeFgPct"] != nil
        }
    }
    /// The single perimeter member's fraction of the lineup's plotted 3PA. nil when the denominator is 0.
    static func loneVolShare(lonePoints: [PlayerShotChart.ShotPoint],
                             allUsablePoints: [[PlayerShotChart.ShotPoint]]) -> Double? {
        func threes(_ pts: [PlayerShotChart.ShotPoint]) -> Int { pts.reduce(0) { $0 + ($1.value == 3 ? 1 : 0) } }
        let total = allUsablePoints.reduce(0) { $0 + threes($1) }
        return total == 0 ? nil : Double(threes(lonePoints)) / Double(total)
    }

    // MARK: - Lineup-weighted diet means

    /// Σ(fga·signal.value) / Σ fga over usable members. nil when any member lacks the signal.
    static func lineupWeightedShare(members: [(fga: Int, profile: PlayerShotChart.Profile?)],
                                    signalKey: String) -> Double? {
        var num = 0.0, den = 0.0
        for m in members {
            guard let s = m.profile?.signals[signalKey] else { return nil }
            num += Double(m.fga) * s.value
            den += Double(m.fga)
        }
        return den == 0 ? nil : num / den
    }

    // MARK: - Corner coverage

    struct CornerCoverage: Equatable {
        let leftClaimant: String?
        let rightClaimant: String?
        var count: Int { (leftClaimant != nil ? 1 : 0) + (rightClaimant != nil ? 1 : 0) }
        var distinctClaimants: Bool {
            guard let l = leftClaimant, let r = rightClaimant else { return false }
            return l != r
        }
    }

    /// A corner is claimed by the deterministic winner among usable members with zone.fga >= 20
    /// AND zone.fga / memberTalliedFGA >= 0.06. Winner = highest zone share -> higher zone fga ->
    /// alphabetical slug. Uses chart.zones tallies ONLY (no profile requirement).
    static func cornerCoverage(members: [MemberInput]) -> CornerCoverage {
        func talliedFGA(_ c: PlayerShotChart) -> Int { ALL_ZONES.reduce(0) { $0 + (c.zones[$1]?.fga ?? 0) } }
        func claimant(_ zoneKey: String) -> String? {
            // candidates: (slug, share, fga) that clear both thresholds.
            var best: (slug: String, share: Double, fga: Int)? = nil
            for m in members {
                guard let c = m.chart, state(for: c) == .usable else { continue }
                let tallied = talliedFGA(c)
                guard tallied > 0, let z = c.zones[zoneKey], z.fga >= CORNER_MIN_FGA else { continue }
                let share = Double(z.fga) / Double(tallied)
                guard share >= CORNER_MIN_SHARE else { continue }
                let cand = (slug: m.slug, share: share, fga: z.fga)
                if let b = best {
                    // higher share -> higher fga -> alphabetical slug (ascending)
                    if cand.share > b.share
                        || (cand.share == b.share && cand.fga > b.fga)
                        || (cand.share == b.share && cand.fga == b.fga && cand.slug < b.slug) {
                        best = cand
                    }
                } else { best = cand }
            }
            return best?.slug
        }
        return CornerCoverage(leftClaimant: claimant(LEFT_CORNER), rightClaimant: claimant(RIGHT_CORNER))
    }

    // MARK: - Centroid dispersion

    /// mean pairwise Euclidean distance of usable members' in-bounds FGA-weighted centroids. nil for
    /// <2 members, AND nil when ANY usable member has no in-bounds points (a total-function contract:
    /// silently dropping a member would misrepresent the lineup — consistent with the any-missing-input
    /// ⇒ nil rule for the lineup means; realistically unreachable at 60+ FGA all-OOB, but made explicit).
    static func centroidDispersion(membersPoints: [[PlayerShotChart.ShotPoint]]) -> Double? {
        func centroid(_ pts: [PlayerShotChart.ShotPoint]) -> (Double, Double)? {
            let ib = pts.filter { inBounds($0) }
            guard !ib.isEmpty else { return nil }
            let n = Double(ib.count)
            return (ib.reduce(0.0) { $0 + Double($1.x) } / n, ib.reduce(0.0) { $0 + Double($1.y) } / n)
        }
        let cents = membersPoints.map { centroid($0) }
        guard !cents.contains(where: { $0 == nil }) else { return nil }   // any member with no in-bounds points ⇒ nil
        let present = cents.compactMap { $0 }
        guard present.count >= 2 else { return nil }
        var sum = 0.0, pairs = 0
        for i in 0..<present.count {
            for j in (i + 1)..<present.count {
                let dx = present[i].0 - present[j].0, dy = present[i].1 - present[j].1
                sum += (dx * dx + dy * dy).squareRoot()
                pairs += 1
            }
        }
        return sum / Double(pairs)
    }

    // MARK: - Side skew

    /// (|M_L - M_R| / (M_L + M_R), M_L + M_R) over usable members' in-bounds value==3, |x|>=25 points.
    /// skew is nil when the qualifying total is 0.
    static func sideSkew(membersPoints: [[PlayerShotChart.ShotPoint]]) -> (skew: Double?, attempts: Int) {
        var ml = 0, mr = 0
        for pts in membersPoints {
            for p in pts where inBounds(p) && p.value == 3 && abs(Double(p.x)) >= SIDE_CENTER_BAND {
                if p.x < 0 { ml += 1 } else if p.x > 0 { mr += 1 }
            }
        }
        let total = ml + mr
        guard total > 0 else { return (nil, 0) }
        return (Double(abs(ml - mr)) / Double(total), total)
    }

    // MARK: - Memo fingerprint

    /// Full member-state fingerprint: for all five supplied members in slot order, "slug#fga"
    /// where fga = chart.meta.fga (the RAW meta.fga, so 0 stays 0) or -1 when the chart is nil.
    static func memoKey(members: [MemberInput]) -> String {
        members.map { "\($0.slug)#\($0.chart?.meta.fga ?? -1)" }.joined(separator: ",")
    }

    // MARK: - Ordinal suffix (CE-8)

    /// English ordinal for a percentile rendered as a rounded int: "1st", "2nd", "3rd", "4th"…"11th",
    /// "12th", "13th", "21st", "82nd", "112th". Percentiles are 0–100 one-decimal; callers pass the
    /// value and this rounds to the nearest int before suffixing. The 11/12/13 teens exception is honored
    /// via the last-two-digits check (so 111/112/113 also take "th").
    static func ordinal(_ pct: Double) -> String {
        let n = Int(pct.rounded())
        let mod100 = ((n % 100) + 100) % 100
        let mod10 = ((n % 10) + 10) % 10
        let suffix: String
        if mod100 >= 11 && mod100 <= 13 { suffix = "th" }
        else if mod10 == 1 { suffix = "st" }
        else if mod10 == 2 { suffix = "nd" }
        else if mod10 == 3 { suffix = "rd" }
        else { suffix = "th" }
        return "\(n)\(suffix)"
    }

    // MARK: - Shared in-bounds filter

    static func inBounds(_ p: PlayerShotChart.ShotPoint) -> Bool {
        Double(p.x) >= HeatField.xMin && Double(p.x) <= HeatField.xMax &&
        Double(p.y) >= HeatField.yMin && Double(p.y) <= HeatField.yMax
    }
}
