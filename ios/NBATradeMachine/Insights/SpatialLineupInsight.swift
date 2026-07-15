import Foundation

/// One tiered, hedged, cited spatial lineup conclusion. Pure `nonisolated` value type, sibling
/// of ShotProfileInsight. All copy/tone lives here; every member-level cited baseline is read
/// from profile.signals[...].{value,pct,norm} (norms are DATA), and every geometric bullet
/// cites an absolute value + a named threshold and discloses no lineup-league baseline.
nonisolated struct SpatialLineupInsight: Equatable, Identifiable {
    enum Family: String {
        case noPerimeter, lonePerimeter, fiveOut,        // perimeter class (mutually exclusive)
             sharedOverlap,                              // overlap (permanently dark, retired)
             sharedHubProximity,                         // G1b hub congestion (rank 4; dark)
             packedGeometry,                             // geometry
             rimCrowding,                                // interior
             emptyCorners, twoCornerCoverage,            // corners class (mutually exclusive)
             midRangeHeavy,                              // diet
             sideAsymmetry,                              // geometry
             multiSpotPerimeter                          // G1b arc versatility (rank 8; dark)
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
    // heat-model v2 hot-cell overlap (section 9.3) — additive; the RAW overlapIndex above is unchanged.
    let hotOverlapNonRim: Double?          // nil when no usable member is hot on any non-RA cell
    let hotOverlapContributorCount: Int    // # usable members with a non-RA shared hot cell (k_hot >= 2)
    let centroidDispersion: Double?

    // G1b hub overlap (section 8) — additive; nil/empty when the league field is nil => rules dark.
    let minHubDistance: Double?                                   // section 5; nil when < 2 members have hubs
    let collidingPair: SpatialLineupMetrics.HubCollision?         // the pair achieving the min (nil when minHubDistance nil)
    let versatileMembers: [SpatialLineupMetrics.VersatileMember]  // usable members with arcHubCount >= ARC_VERSATILE_N

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
    // CE-6: the slug in cornerCoverage drives DETERMINISTIC selection; these resolve to the member's
    // display NAME for ALL user-facing copy (rule 8). nil when the corner has no claimant.
    let leftClaimantName: String?
    let rightClaimantName: String?

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

    /// PUBLIC entry — unchanged signature. Supplies the hub read behind the dark flag, then delegates.
    static func make(from c: SpatialLineupContext) -> [SpatialLineupInsight] {
        makeResolved(from: c, hubInsight: M.HUB_CONGESTION_ENABLED ? hubBody(c) : nil)
    }

    /// SEAM (SF6) — receives the ALREADY-EVALUATED hub insight; tests call this directly with a
    /// non-nil hubInsight to exercise the `hub fired => skip rule 5` path WITHOUT flipping the flag.
    /// Uses the concrete `SpatialLineupInsight?` (not the private `I` alias) so the seam is non-private
    /// and unit-testable, matching the `rule4Body` convention.
    static func makeResolved(from c: SpatialLineupContext, hubInsight hub: SpatialLineupInsight?) -> [SpatialLineupInsight] {
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
        add(4, rule4(c))                    // CE-3: rule4 self-suppresses via SHARED_OVERLAP_ENABLED (returns nil while false)
        add(4, hub)                         // .sharedHubProximity, passed in; shares the rank-4 slot (rule 4 never fires).
        if hub == nil { add(5, rule5(c)) }  // MUTUAL EXCLUSION: skip rule 5 when the hub read fires.
        add(6, rule6(c))
        // Corners class: 7 vs 8, coverage==1 fires neither.
        // CE-7: rule 8 (twoCornerCoverage) is demoted to the LOWEST display rank (11, below sideAsymmetry's
        // 10). It fires on 26/30 real lineups (near-universal), so it must never crowd distinctive reads
        // out of the top-4. rule 7 (emptyCorners) keeps its natural rank 7.
        add(7, rule7(c)); add(11, rule8(c))
        add(8, rule9Multi(c))               // .multiSpotPerimeter — dark behind ARC_VERSATILITY_ENABLED.
        add(9, rule9(c))
        add(10, rule10(c))

        return out.sorted { $0.rank < $1.rank }.prefix(4).map { $0.insight }
    }

    // MARK: - Copy helpers

    private static func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
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
            ev.append("\u{2022} \(name)'s 3-point share sits in the \(M.ordinal(mp.threeSharePct)) percentile of \(mp.bucket) (A's positional norm).")
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

    // Rule 4 — Shared hot zones outside the rim (heat-model v2). Fires when hotOverlapNonRim >=
    // max(HOT_OVERLAP_PIN, HOT_OVERLAP_ABS_MIN) with >= 2 contributors. GATED behind
    // SHARED_OVERLAP_ENABLED (section 9.4): stays suppressed unless the recalibration criteria fire.
    // The body is split out so the enabled COPY SHAPE is unit-testable while the flag stays false.
    static func rule4(_ c: SpatialLineupContext) -> SpatialLineupInsight? {
        guard M.SHARED_OVERLAP_ENABLED else { return nil }
        return rule4Body(c)
    }

    /// The fire logic WITHOUT the flag guard (flag-independent, unit-testable copy shape, section 9.4).
    /// Return type is the concrete SpatialLineupInsight (not the private `I` alias) so the function can
    /// be non-private for the enabled-shape test.
    static func rule4Body(_ c: SpatialLineupContext) -> SpatialLineupInsight? {
        let threshold = max(M.HOT_OVERLAP_PIN, M.HOT_OVERLAP_ABS_MIN)
        guard let observed = c.hotOverlapNonRim, observed >= threshold,
              c.hotOverlapContributorCount >= 2 else { return nil }
        return I(family: .sharedOverlap,
                 headline: "Shared hot zones outside the rim — spacing may compress",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} Members share above-league hot cells over \(pct(observed)) of their occupied non-rim hot court (named threshold \(pct(threshold))).",
                    "\u{2022} Restricted-area convergence is excluded — this cites perimeter/mid overlap only.",
                    "\u{2022} \(noBaseline) Absolute overlap share, not a percentile."],
                 basis: "Basis: composited individual season above-league hot cells on a fixed 20-unit grid, restricted area excluded. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 5 — Packed / clustered geometry. dispersion<=TIGHT AND overlapIndex>=MID. Geometric cap.
    private static func rule5(_ c: SpatialLineupContext) -> I? {
        guard let disp = c.centroidDispersion, disp <= M.DISPERSION_TIGHT,
              let ov = c.overlapIndex, ov >= M.OVERLAP_MID else { return nil }
        // CE-4(a): court units are tenths of feet, so feet = DISPERSION_TIGHT / 10 (31.3 units ≈ 3.1 ft).
        let tightFeet = String(format: "%.1f", M.DISPERSION_TIGHT / 10.0)
        return I(family: .packedGeometry, headline: "Shot centroids cluster — spacing tends to pack in",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} Mean pairwise centroid distance is \(Int(disp.rounded())) court units (named threshold \(Int(M.DISPERSION_TIGHT.rounded())), ~\(tightFeet) ft).",
                    // CE-4(b): OVERLAP_MID is the SAMPLE MEDIAN, not a cleared floor — cite it as a supporting
                    // value, not a threshold the lineup "clears". Dispersion (above) is the driving citation.
                    "\u{2022} The tight centroids coincide with broadly shared shot area (overlap \(pct(ov))).",
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
            ev.append("\u{2022} \(name)'s rim share is in the \(M.ordinal(pctVal)) percentile of \(bucket).")
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
    // CE-6: slug drives deterministic selection (in cornerCoverage), but ALL user-facing copy uses the
    // member's display NAME — leftClaimantName/rightClaimantName (resolved slug→name in the context builder).
    private static func rule8(_ c: SpatialLineupContext) -> I? {
        guard c.cornerCoverage.count == 2,
              let left = c.leftClaimantName, let right = c.rightClaimantName else { return nil }
        // distinctClaimants compares the underlying SLUGS (correct member identity even if two members
        // share a display name); the copy renders the resolved display names.
        let lShare = c.leftClaimantShare.map { pct($0) } ?? "a qualifying share"
        let rShare = c.rightClaimantShare.map { pct($0) } ?? "a qualifying share"
        if c.cornerCoverage.distinctClaimants {
            return I(family: .twoCornerCoverage, headline: "Both corners claimed by different members",
                     confidence: .moderate,
                     evidence: [
                        "\u{2022} Left corner claimed by \(left) (\(lShare) of their shots); right corner by \(right) (\(rShare)).",
                        "\u{2022} Each claimant clears the \u{2265}20-attempt, \u{2265}6%-share filter (named thresholds).",
                        "\u{2022} Bilateral corner presence tends to widen the floor."],
                     basis: "Basis: individual season corner-zone tallies from each member's shot profile. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
        }
        // Same member qualifies in BOTH corners: that is a VERSATILE two-sided corner profile
        // (viable from either side, lets the lineup flip its strong side) — never phrased as one
        // player occupying two spots at once. Headline stays geometry-voiced (names live in the
        // evidence, matching every sibling rule — Opus final-review advisory).
        return I(family: .twoCornerCoverage, headline: "Versatile two-sided corner profile — viable from either corner",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} \(left)'s profile qualifies from either corner: \(lShare) of their shots from the left corner and \(rShare) from the right.",
                    "\u{2022} Both corner samples clear the \u{2265}20-attempt, \u{2265}6%-share filter (named thresholds).",
                    "\u{2022} The two-sided profile supports flipping the lineup's strong side; viable corner options tend to widen the floor."],
                 basis: "Basis: individual season corner-zone tallies from each member's shot profile. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 9 — Mid-range-heavy. lineupMidShare>=max(MIDHEAVY_MIN, MIDHEAVY_ABS_MIN) AND lineup3Share<MIDHEAVY_MAX_3SHARE.
    // CE-2: the effective threshold is the MAX of the calibrated pin and the absolute honesty floor; the bullet
    // cites that effective threshold (not the bare calibrated pin, which can be below a genuinely mid-heavy diet).
    private static func rule9(_ c: SpatialLineupContext) -> I? {
        let midThreshold = max(M.MIDHEAVY_MIN, M.MIDHEAVY_ABS_MIN)
        guard let mid = c.lineupMidShare, mid >= midThreshold,
              let three = c.lineup3Share, three < M.MIDHEAVY_MAX_3SHARE else { return nil }
        return I(family: .midRangeHeavy, headline: "Mid-range-tilted shot diet — spacing tends to stay tighter",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} FGA-weighted mid-range share is \(pct(mid)) (named threshold \(pct(midThreshold))).",
                    "\u{2022} FGA-weighted 3-point share is \(pct(three)), below the \(pct(M.MIDHEAVY_MAX_3SHARE)) floor.",
                    "\u{2022} A mid-tilted diet tends to pull fewer defenders off the paint; no lineup-level league baseline yet."],
                 basis: "Basis: FGA-weighted individual season shot mixes. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // Rule 10 — Side asymmetry. sideSkew>=max(SIDE_SKEW_MIN, SIDE_SKEW_ABS_MIN) AND attempts>=100. Geometric cap.
    // CE-1: the effective threshold is the MAX of the calibrated pin and the absolute honesty floor (≈60/40 split),
    // so a barely-perceptible ~55/45 tilt never fires. CE-5: the bullet cites the numeric effective threshold.
    private static func rule10(_ c: SpatialLineupContext) -> I? {
        let skewThreshold = max(M.SIDE_SKEW_MIN, M.SIDE_SKEW_ABS_MIN)
        guard let s = c.sideSkew, s >= skewThreshold, c.sideAttempts >= M.SIDE_SKEW_MIN_ATTEMPTS else { return nil }
        let dominantPct = pct((1 + s) / 2)
        let side = c.dominantSideIsLeft ? "left" : "right"
        let val = String(format: "%.2f", s)
        return I(family: .sideAsymmetry, headline: "Perimeter attempts tilt to one side",
                 confidence: .moderate,
                 evidence: [
                    "\u{2022} \(dominantPct) of the lineup's qualifying 3-point attempts come from the \(side) side (named threshold \(pct(skewThreshold)), observed skew \(val)).",
                    "\u{2022} Measured over \(c.sideAttempts) qualifying attempts (\u{2265}100 floor), excluding a straight-on center band.",
                    "\u{2022} \(noBaseline) Absolute side split only."],
                 basis: "Basis: individual season 3-point attempt sides from each member's shot profile (center band excluded). \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    // MARK: - G1b rule bodies (section 6, 7)

    /// .sharedHubProximity body (rank 4, G1b, section 6.1/7.1). Flag-independent copy shape
    /// (rule4Body pattern). Fires iff minHubDistance <= min(HUB_DIST_PIN, HUB_DIST_ABS_MAX).
    /// `make` calls this only when HUB_CONGESTION_ENABLED is true.
    static func hubBody(_ c: SpatialLineupContext) -> SpatialLineupInsight? {
        let floor = M.effectiveFloor()   // PF14: the ONE floor primitive (== min(HUB_DIST_PIN, HUB_DIST_ABS_MAX))
        guard let dist = c.minHubDistance, dist <= floor, let col = c.collidingPair else { return nil }
        let d = "\(Int(dist.rounded()))", t = "\(Int(floor.rounded()))"
        let sa = pct(col.hubA.strength), sb = pct(col.hubB.strength)   // SF12: each own-member share, separate
        var ev = [
            "\u{2022} \(col.nameA)'s and \(col.nameB)'s nearest shot-making hubs sit \(d) court units apart (named threshold \(t)); the colliding hubs hold \(sa) and \(sb) of each player's own non-rim shot-making mass.",
            "\u{2022} Similar geography can mean two reads: contested space, or players swapping in and out of the same spots across possessions \u{2014} season charts cannot separate the two.",
            "\u{2022} Restricted-area convergence is excluded; this cites non-rim hub centroids only."]
        // Relocation bullet(s): per qualifying colliding versatile member, in collision order (A then B, SF3).
        // Pluralized (post-final-review sol advisory): "1 qualifying arc hub sits" / "n qualifying arc hubs sit".
        for name in [col.nameA, col.nameB] {
            if let v = c.versatileMembers.first(where: { $0.name == name }), v.hasEscapeHub {
                let hubs = v.escapeHubCount == 1 ? "1 qualifying arc hub sits" : "\(v.escapeHubCount) qualifying arc hubs sit"
                ev.append("\u{2022} \(v.name)'s profile supports relocating \u{2014} \(hubs) away from the collision spot.")
            }
        }
        return I(family: .sharedHubProximity,
                 headline: "Shot hubs sit close together \u{2014} contested spacing or shared real estate",
                 confidence: .moderate, evidence: ev,
                 basis: "Basis: composited individual season above-league hub centroids on a fixed 20-unit grid, restricted area excluded; season charts are not possession-synchronized, so shared geography tends to admit more than one read. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }

    /// .multiSpotPerimeter (rank 8, G1b, section 6.2b/7.2). PF5: the FINAL split form — `rule9Multi`
    /// self-suppresses via ARC_VERSATILITY_ENABLED (because `makeResolved` calls `add(8, rule9Multi(c))`
    /// UNCONDITIONALLY, mirroring how the shipped `rule4` self-suppresses via SHARED_OVERLAP_ENABLED),
    /// then delegates to the flag-INDEPENDENT `rule9MultiBody` that the copy-shape tests call directly.
    /// (Asymmetry with `hubBody`, which is flag-independent because `make` gates it via
    /// `HUB_CONGESTION_ENABLED ? hubBody(c) : nil`; section 6.3.)
    static func rule9Multi(_ c: SpatialLineupContext) -> SpatialLineupInsight? {
        guard M.ARC_VERSATILITY_ENABLED else { return nil }
        return rule9MultiBody(c)
    }
    /// Flag-independent copy shape (rule4Body pattern) — unit-testable while ARC_VERSATILITY_ENABLED
    /// is false. Fires per lineup when >= 1 usable member is versatile.
    static func rule9MultiBody(_ c: SpatialLineupContext) -> SpatialLineupInsight? {
        guard !c.versatileMembers.isEmpty else { return nil }
        var ev = c.versatileMembers.map { v in
            "\u{2022} \(v.name) carries \(v.arcHubCount) arc hubs (named threshold \(M.ARC_VERSATILE_N)) across \(v.hotThreeCellCount) hot three-point cells."
        }
        ev.append("\u{2022} Multiple quality arc spots tend to give a lineup more ways to space; viable relocation options tend to widen the floor. \(noBaseline)")
        return I(family: .multiSpotPerimeter,
                 headline: "Multi-spot perimeter profiles \u{2014} arc versatility tends to widen the floor",
                 confidence: .moderate, evidence: ev,
                 basis: "Basis: composited individual season above-league arc hubs on a fixed 20-unit grid; arc counts describe reachable spots, not that any relocation occurred. \(notOnCourt) \(noBaseline)\(exclPhrase(c.excludedNames))")
    }
}
