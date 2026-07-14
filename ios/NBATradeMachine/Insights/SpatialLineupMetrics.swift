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

    // --- geometry — CALIBRATED (Task 2, 30 real depth-order starting fives; 2026-07-14 run) ---
    static let OVERLAP_HIGH = 0.95             // p75 overlapIndex over 30 lineups (dist: n=30 min=0.839 p25=0.918 median=0.931 p75=0.949 max=0.984); spec provisional was 0.35
    static let OVERLAP_MID = 0.93              // p50 overlapIndex over 30 lineups (median 0.931, same dist); spec provisional was 0.22
    static let DISPERSION_TIGHT = 31.3         // p25 centroidDispersion (court units) over 30 lineups (dist: n=30 min=18.533 p25=31.339 median=39.785 p75=54.306 max=68.121); spec provisional was 90 (~9 ft)
    static let SIDE_SKEW_MIN = 0.09            // p75 sideSkew over 30 lineups (dist: n=30 min=0.003 p25=0.024 median=0.065 p75=0.092 max=0.230); spec provisional was 0.45
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

    // MARK: - Shared in-bounds filter

    static func inBounds(_ p: PlayerShotChart.ShotPoint) -> Bool {
        Double(p.x) >= HeatField.xMin && Double(p.x) <= HeatField.xMax &&
        Double(p.y) >= HeatField.yMin && Double(p.y) <= HeatField.yMax
    }
}
