import Foundation

/// One tiered, hedged, cited spatial lineup conclusion. Pure `nonisolated` value type, sibling
/// of ShotProfileInsight. All copy/tone lives here; every member-level cited baseline is read
/// from profile.signals[...].{value,pct,norm} (norms are DATA), and every geometric bullet
/// cites an absolute value + a named threshold and discloses no lineup-league baseline.
nonisolated struct SpatialLineupInsight: Equatable, Identifiable {
    enum Family: String {
        case noPerimeter, lonePerimeter, fiveOut,        // perimeter class (mutually exclusive)
             sharedOverlap,                              // overlap
             packedGeometry,                             // geometry
             rimCrowding,                                // interior
             emptyCorners, twoCornerCoverage,            // corners class (mutually exclusive)
             midRangeHeavy,                              // diet
             sideAsymmetry                               // geometry
    }
    enum Confidence: String { case high, moderate }      // exactly two chips; no .low (A house style)

    let family: Family
    let headline: String       // bold read
    let confidence: Confidence
    let evidence: [String]      // cited bullets ("• …")
    let basis: String           // basis/caveat line (always states what the read is NOT built on)
    var id: String { family.rawValue }
}

/// The precomputed per-lineup context the engine consumes. Built in the view layer (Task 5)
/// from SpatialLineupMetrics over the resolved usable members. Everything the rules cite.
nonisolated struct SpatialLineupContext {
    let usableCount: Int
    let combinedUsableFga: Int
    let minUsableFga: Int
    let memberNames: [String]                 // usable member display names
    let excludedNames: [String]               // thin + missing member names (for the basis line)

    // perimeter
    let perimeterShooterCount: Int
    let everyUsableHasPerimeterSignals: Bool
    let minThreeSharePct: Double?             // min over usable of threeShare.pct (five-out driving)
    let loneVolShare: Double?

    // overlap / geometry
    let overlapIndex: Double?
    let paintOverlap: Double?
    let overlapContributorCount: Int
    let centroidDispersion: Double?

    // diet
    let lineup3Share: Double?
    let lineupMidShare: Double?

    // interior
    let rimHeavyCount: Int
    let rimHeavyMaxPct: Double?
    let rimHeavyNames: [(String, Double)]     // (name, rimShare.pct) for up to 2 cited members

    // corners
    let cornerCoverage: SpatialLineupMetrics.CornerCoverage
    let leftClaimantShare: Double?            // claimant's zone share (for the "{pct}% of their shots" bullet)
    let rightClaimantShare: Double?

    // side skew
    let sideSkew: Double?
    let sideAttempts: Int
    let dominantSideIsLeft: Bool

    // member-level percentile citations (for high-eligible member bullets)
    let lonePerimeterName: String?
    let memberPercentiles: [String: (bucket: String, threeSharePct: Double, rimSharePct: Double)]
}

nonisolated enum SpatialLineupEngine {
    private typealias M = SpatialLineupMetrics
    private typealias I = SpatialLineupInsight

    /// Evaluate all 10 rules, drop non-firing, sort by fixed priority, return the top 4.
    /// Returns [] when the section gate fails (caller shows the caption).
    static func make(from c: SpatialLineupContext) -> [SpatialLineupInsight] {
        guard c.usableCount >= M.MIN_USABLE_MEMBERS,
              c.combinedUsableFga >= M.MIN_COMBINED_USABLE_FGA else { return [] }

        var out: [(rank: Int, insight: I)] = []
        func add(_ rank: Int, _ ins: I?) { if let ins { out.append((rank, ins)) } }

        // Perimeter class: 1 -> 2 -> 3, first match wins (mutual exclusion).
        if c.everyUsableHasPerimeterSignals {
            if let r = rule1(c) { add(1, r) }
            else if let r = rule2(c) { add(2, r) }
            else if let r = rule3(c) { add(3, r) }
        } else if c.usableCount == 5, let r = rule3(c) {
            // rule 3 requires its own min-threeShare guard; data-absence blocks only rules 1/2.
            add(3, r)
        }
        add(4, rule4(c))
        add(5, rule5(c))
        add(6, rule6(c))
        // Corners class: 7 vs 8, coverage==1 fires neither.
        add(7, rule7(c)); add(8, rule8(c))
        add(9, rule9(c))
        add(10, rule10(c))

        return out.sorted { $0.rank < $1.rank }.prefix(4).map { $0.insight }
    }

    // MARK: - Copy helpers

    private static func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
    private static func pctOfHundred(_ p: Double) -> String { "\(Int(p.rounded()))" }
    private static func exclPhrase(_ names: [String]) -> String {
        names.isEmpty ? "" : " Excludes \(names.joined(separator: ", ")) — thin/no sample."
    }
    private static let notOnCourt = "Not minutes those five shared the floor; season mixes may span teams."
    private static let noBaseline = "No lineup-level league baseline yet."

    // MARK: - Confidence

    private static func sampleCeiling(_ minFga: Int) -> I.Confidence { minFga > M.FGA_MODERATE_MAX ? .high : .moderate }
    private static func earned(_ drivingPct: Double) -> I.Confidence {
        abs(drivingPct - 50.0) >= M.EARNED_HIGH_DISTANCE ? .high : .moderate
    }
    private static func minConf(_ a: I.Confidence, _ b: I.Confidence) -> I.Confidence {
        (a == .high && b == .high) ? .high : .moderate
    }

    // MARK: - Rules

    // Rule 1 — No-perimeter. Fires when perimeterShooterCount == 0. Cap .moderate.
    private static func rule1(_ c: SpatialLineupContext) -> I? {
        guard c.perimeterShooterCount == 0, let three = c.lineup3Share else { return nil }
        let insideShare = pct(1 - three)
        return I(family: .noPerimeter,
                 headline: "Limited perimeter spacing — paint may be easier to protect",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} No usable member clears the 65th-pct 3P-share, \u{2265}34% 3P% spacer filter (A's positional thresholds).",
                    "\u{2022} Lineup 3-point share is \(pct(three)) (FGA-weighted across \(c.usableCount) usable members).",
                    "\u{2022} The remaining \(insideShare) of the FGA-weighted mix is inside the arc, so help defenders may stay closer to the paint."],
                 basis: "Basis: individual season shot profiles + A's positional 3-point filters. \(notOnCourt)\(exclPhrase(c.excludedNames))")
    }

    // Rule 2 — Lone-perimeter dependence. count==1 AND loneVolShare>=0.55. Cap .moderate.
    private static func rule2(_ c: SpatialLineupContext) -> I? {
        guard c.perimeterShooterCount == 1, let lone = c.loneVolShare, lone >= M.LONE_PERIM_VOL_SHARE,
              let name = c.lonePerimeterName else { return nil }
        var ev = ["\u{2022} \(name) supplies \(pct(lone)) of the lineup's plotted 3-point attempts (named threshold 55%)."]
        if let mp = c.memberPercentiles[name] {
            ev.append("\u{2022} \(name)'s 3-point share sits in the \(pctOfHundred(mp.threeSharePct))th percentile of \(mp.bucket) (A's positional norm).")
        }
        ev.append("\u{2022} The other usable members clear no spacer filter, so perimeter looks may concentrate on \(name).")
        return I(family: .lonePerimeter, headline: "Perimeter volume leans on \(name)",
                 confidence: .moderate, evidence: ev,
                 basis: "Basis: individual season shot profiles + A's positional filters. \(notOnCourt)\(exclPhrase(c.excludedNames))")
    }

    // Rule 3 — Five-out shape. usableCount==5 AND count>=4 AND minThreeSharePct>=35. High-eligible.
    private static func rule3(_ c: SpatialLineupContext) -> I? {
        guard c.usableCount == 5, c.perimeterShooterCount >= 4,
              let minPct = c.minThreeSharePct, minPct >= M.FIVE_OUT_MIN_3SHARE_PCT,
              let three = c.lineup3Share else { return nil }
        let conf = minConf(sampleCeiling(c.minUsableFga), earned(minPct))
        return I(family: .fiveOut, headline: "Profile suggests a five-out shape",
                 confidence: conf,
                 evidence: [
                    "\u{2022} All five usable members carry a 3-point share at or above the 35th-percentile floor for their positions.",
                    "\u{2022} \(c.perimeterShooterCount) of five clear A's spacer filter (65th-pct 3P share, \u{2265}34% 3P%).",
                    "\u{2022} Lineup 3-point share is \(pct(three)) (FGA-weighted), so the floor tends to stay stretched."],
                 basis: "Basis: individual season shot profiles + A's positional norms. \(notOnCourt)\(exclPhrase(c.excludedNames))")
    }

    // Rule 4 — Shared-area overlap. overlapIndex>=OVERLAP_HIGH with >=2 contributors. Geometric cap.
    private static func rule4(_ c: SpatialLineupContext) -> I? {
        guard let ov = c.overlapIndex, ov >= M.OVERLAP_HIGH, c.overlapContributorCount >= 2 else { return nil }
        return I(family: .sharedOverlap, headline: "Shot areas overlap — may compress operating space",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} Shared shot area covers \(pct(ov)) of the lineup's occupied court (named threshold \(pct(M.OVERLAP_HIGH))).",
                    "\u{2022} \(c.overlapContributorCount) usable members contribute mass to the shared cells, so preferred spots may crowd.",
                    "\u{2022} \(noBaseline) This cites the absolute overlap share, not a percentile."],
                 basis: "Basis: composited individual season shot mass on a fixed 20-unit grid. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 5 — Packed / clustered geometry. dispersion<=TIGHT AND overlapIndex>=MID. Geometric cap.
    private static func rule5(_ c: SpatialLineupContext) -> I? {
        guard let disp = c.centroidDispersion, disp <= M.DISPERSION_TIGHT,
              let ov = c.overlapIndex, ov >= M.OVERLAP_MID else { return nil }
        return I(family: .packedGeometry, headline: "Shot centroids cluster — spacing tends to pack in",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} Mean pairwise centroid distance is \(Int(disp.rounded())) court units (named threshold \(Int(M.DISPERSION_TIGHT.rounded())), ~9 ft).",
                    "\u{2022} Overlap index \(pct(ov)) clears the \(pct(M.OVERLAP_MID)) packing floor, so the tight centroids coincide with shared area.",
                    "\u{2022} \(noBaseline) Absolute geometry only."],
                 basis: "Basis: individual season shot centroids + composited mass. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 6 — Rim-crowding. rimHeavyCount>=2 (>=3 strengthens). High-eligible on rimShare.pct.
    private static func rule6(_ c: SpatialLineupContext) -> I? {
        guard c.rimHeavyCount >= M.RIM_CROWD_MIN_COUNT, let maxPct = c.rimHeavyMaxPct else { return nil }
        let conf = minConf(sampleCeiling(c.minUsableFga), earned(maxPct))
        let headline = c.rimHeavyCount >= 3
            ? "Multiple rim-heavy profiles — driving lanes may crowd"
            : "Two rim-heavy profiles — driving lanes may crowd"
        var ev = ["\u{2022} \(c.rimHeavyCount) usable members carry a rim share at/above the 75th percentile of their positions (A's norm) and \u{2265}30% by volume."]
        if let po = c.paintOverlap {
            ev.append("\u{2022} Shared paint area covers \(pct(po)) of the occupied paint, so interior lanes may compress.")
        }
        for (name, pctVal) in c.rimHeavyNames.prefix(2) {
            let bucket = c.memberPercentiles[name]?.bucket ?? "their position"
            ev.append("\u{2022} \(name)'s rim share is in the \(pctOfHundred(pctVal))th percentile of \(bucket).")
        }
        return I(family: .rimCrowding, headline: headline, confidence: conf, evidence: ev,
                 basis: "Basis: individual season rim shares vs A's positional norms + composited paint mass. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 7 — Empty corners. cornerCoverage==0. Cap .moderate.
    private static func rule7(_ c: SpatialLineupContext) -> I? {
        guard c.cornerCoverage.count == 0 else { return nil }
        return I(family: .emptyCorners, headline: "No claimed corner shooting in the profile",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} Neither corner has a usable member with \u{2265}20 attempts at \u{2265}6% of their own shots (named thresholds).",
                    "\u{2022} Corner spacing tends to help drives, so its absence may let help defenders sit closer.",
                    "\u{2022} Cites season corner volume only — no lineup-level league baseline yet."],
                 basis: "Basis: individual season corner-zone tallies. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 8 — Two-corner coverage. cornerCoverage==2. Cap .moderate.
    private static func rule8(_ c: SpatialLineupContext) -> I? {
        guard c.cornerCoverage.count == 2,
              let left = c.cornerCoverage.leftClaimant, let right = c.cornerCoverage.rightClaimant else { return nil }
        let headline = c.cornerCoverage.distinctClaimants
            ? "Both corners claimed by different members"
            : "Both corners claimed in the profile"
        let lShare = c.leftClaimantShare.map { pct($0) } ?? "a qualifying share"
        let rShare = c.rightClaimantShare.map { pct($0) } ?? "a qualifying share"
        return I(family: .twoCornerCoverage, headline: headline, confidence: .moderate,
                 evidence: [
                    "\u{2022} Left corner claimed by \(left) (\(lShare) of their shots); right corner by \(right) (\(rShare)).",
                    "\u{2022} Each claimant clears the \u{2265}20-attempt, \u{2265}6%-share filter (named thresholds).",
                    "\u{2022} Bilateral corner presence tends to widen the floor."],
                 basis: "Basis: individual season corner-zone tallies from each member's shot profile. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 9 — Mid-range-heavy. lineupMidShare>=MIDHEAVY_MIN AND lineup3Share<MIDHEAVY_MAX_3SHARE. Cap .moderate.
    private static func rule9(_ c: SpatialLineupContext) -> I? {
        guard let mid = c.lineupMidShare, mid >= M.MIDHEAVY_MIN,
              let three = c.lineup3Share, three < M.MIDHEAVY_MAX_3SHARE else { return nil }
        return I(family: .midRangeHeavy, headline: "Mid-range-tilted shot diet — spacing tends to stay tighter",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} FGA-weighted mid-range share is \(pct(mid)) (named threshold \(pct(M.MIDHEAVY_MIN))).",
                    "\u{2022} FGA-weighted 3-point share is \(pct(three)), below the \(pct(M.MIDHEAVY_MAX_3SHARE)) floor.",
                    "\u{2022} A mid-tilted diet tends to pull fewer defenders off the paint; no lineup-level league baseline yet."],
                 basis: "Basis: FGA-weighted individual season shot mixes. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 10 — Side asymmetry. sideSkew>=SIDE_SKEW_MIN AND attempts>=100. Geometric cap.
    private static func rule10(_ c: SpatialLineupContext) -> I? {
        guard let s = c.sideSkew, s >= M.SIDE_SKEW_MIN, c.sideAttempts >= M.SIDE_SKEW_MIN_ATTEMPTS else { return nil }
        let dominantPct = pct((1 + s) / 2)
        let side = c.dominantSideIsLeft ? "left" : "right"
        let val = String(format: "%.2f", s)
        return I(family: .sideAsymmetry, headline: "Perimeter attempts tilt to one side",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} \(dominantPct) of the lineup's qualifying 3-point attempts come from the \(side) side (named threshold, skew \(val)).",
                    "\u{2022} Measured over \(c.sideAttempts) qualifying attempts (\u{2265}100 floor), excluding a straight-on center band.",
                    "\u{2022} \(noBaseline) Absolute side split only."],
                 basis: "Basis: individual season 3-point attempt sides from each member's shot profile (center band excluded). \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }
}
