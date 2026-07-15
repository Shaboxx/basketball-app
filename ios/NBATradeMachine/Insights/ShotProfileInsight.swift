import Foundation

/// One tiered, hedged, stat-cited shot-profile scouting conclusion. Pure `nonisolated`
/// value type (like MatchupInsight). All copy/tone lives here; every cited baseline is
/// read from `profile.signals[...].norm` — norms are DATA, never Swift literals.
nonisolated struct ShotProfileInsight: Equatable, Identifiable {
    enum Family: String { case spacing, positionViability, shotDiet }
    enum Confidence: String { case high, moderate }   // exactly two chips; no .low

    let family: Family
    let headline: String       // bold read
    let confidence: Confidence
    let evidence: [String]     // cited bullets ("• {value} — {above/below} the ~{norm} {label} norm")
    let basis: String          // basis/caveat line (always states what the read is NOT built on)
    var id: String { family.rawValue }
}

extension ShotProfileInsight {
    // MARK: Named constants (single source; referenced by tests)
    // Sample-size gates (on profile.fga) — TWO-CHIP model
    static let FGA_SUPPRESS_FLOOR = 60      // fga <= this => the family emits NOTHING
    static let FGA_MODERATE_MAX = 350       // (SUPPRESS, this] => ceiling .moderate; above => .high eligible
    static let ZONE_MIN_FGA = 20            // a hot/cold bullet needs >= this FGA in its group
    // Distance-from-norm thresholds (percentile-based; symmetric)
    static let PCT_STRONG_HIGH = 80.0
    static let PCT_ABOVE = 65.0
    static let PCT_BELOW = 35.0
    static let PCT_STRONG_LOW = 20.0
    // Family 1: spacing role & gravity
    static let FLOOR_SPACER_3SHARE_PCT = 80.0
    static let FLOOR_SPACER_3FG_MIN = 0.34
    static let RIM_GRAVITY_RIMSHARE_PCT = 75.0
    static let RIM_GRAVITY_RIMFG_MIN = 0.62
    static let CLOG_RISK_3SHARE_PCT = 25.0
    static let CLOG_RISK_RIMSHARE_PCT = 55.0
    static let INTERIOR_ANCHOR_3SHARE_PCT_MAX = 25.0   // gap band lower driver (== CLOG_RISK_3SHARE_PCT)
    static let INTERIOR_ANCHOR_RIMSHARE_PCT_LO = 55.0  // gap band: rim share above the clog-risk ceiling
    static let INTERIOR_ANCHOR_RIMSHARE_PCT_HI = 75.0  // ... and below the rim-gravity floor
    static let INTERIOR_ANCHOR_ENABLED = false         // D4: flipped TRUE in the calibration-verified commit (pin 6d: C-bucket 5-30%)
    static let BIG_BUCKETS: Set<String> = ["PF", "C", "F"]
    // Family 2: position viability
    static let SIZE_UNDERSIZED_PCT = 25.0
    static let SIZE_PROTOTYPE_PCT = 60.0
    static let STRETCH_BIG_3SHARE_PCT = 70.0
    // Family 3: shot diet & hot/cold
    static let THREE_LEVEL_MIN_PCT = 25.0
    static let THREE_LEVEL_SPREAD_MAX = 0.55
    static let ONE_DIM_DOMINANT_SHARE = 0.60
    static let HOTCOLD_FGPCT_PCT_HIGH = 70.0
    static let HOTCOLD_FGPCT_PCT_LOW = 30.0
    // Earned-level threshold: max|pct-50| >= this earns .high
    static let EARNED_HIGH_DISTANCE = 30.0

    typealias Profile = PlayerShotChart.Profile
    typealias Signal = PlayerShotChart.Profile.Signal

    /// The ordered scouting read for a decoded profile (spacing -> positionViability ->
    /// shotDiet). Empty when the profile is nil, has no signals, or no family fires.
    static func make(from profile: Profile?) -> [ShotProfileInsight] {
        guard let p = profile, p.fga > FGA_SUPPRESS_FLOOR else { return [] }
        var out: [ShotProfileInsight] = []
        if let s = spacing(p) { out.append(s) }
        if let v = positionViability(p) { out.append(v) }
        if let d = shotDiet(p) { out.append(d) }
        return out
    }

    // MARK: - Confidence

    private static func sampleCeiling(_ fga: Int) -> Confidence {
        fga > FGA_MODERATE_MAX ? .high : .moderate
    }
    private static func earned(_ drivingPcts: [Double]) -> Confidence {
        let maxDist = drivingPcts.map { abs($0 - 50.0) }.max() ?? 0
        return maxDist >= EARNED_HIGH_DISTANCE ? .high : .moderate
    }
    private static func minConf(_ a: Confidence, _ b: Confidence) -> Confidence {
        (a == .high && b == .high) ? .high : .moderate
    }
    /// Final confidence = min(sample ceiling, earned), with an optional cap to .moderate.
    private static func confidence(fga: Int, drivingPcts: [Double], cap: Confidence = .high) -> Confidence {
        let base = minConf(sampleCeiling(fga), earned(drivingPcts))
        return minConf(base, cap)
    }

    // MARK: - Position-noun helper (NQ2)

    /// The noun for the player's bucket. Position-specific ("5"/"4"/...) only when
    /// bucketMode == "specific"; coarse buckets use generic "big"/"forward"/"guard".
    /// `stretchOrPlain` toggles the specific-bucket adjective form the caller wants.
    private static func bigWord(_ p: Profile) -> String {
        if p.bucketMode == "specific" {
            switch p.bucket {
            case "C": return "5"
            case "PF": return "4"
            case "SF": return "wing"
            case "SG", "PG": return "guard"
            default: return "big"
            }
        }
        switch p.bucket {
        case "C": return "big"
        case "F": return "forward"
        case "G": return "guard"
        default: return "big"
        }
    }

    /// SW-7: the noun for family-2 "Undersized for {noun}" / "Prototypical {noun} size"
    /// headlines. NEVER raw `p.position` — position-specific tokens ("C"/"PF"/...) only under
    /// `bucketMode == "specific"`; a coarse bucket uses a GENERIC noun ("big"/"forward"/
    /// "guard"), so a coarse-C reads "Undersized for big", a specific-C reads "Undersized for
    /// C". (A coarse-F never claims "PF" it has no PF-specific norm for.)
    private static func viabilityNoun(_ p: Profile) -> String {
        if p.bucketMode == "specific" {
            switch p.bucket {
            case "PG", "SG", "SF", "PF", "C": return p.bucket   // the specific position token
            default: return bigWord(p)
            }
        }
        switch p.bucket {
        case "C": return "big"
        case "F": return "forward"
        case "G": return "guard"
        default: return "big"
        }
    }

    /// The citable bucket label for a norm ("center"/"forward"/"guard"/"C"/...). Generic
    /// under coarse mode. Used in evidence bullets and basis lines ("~N% {label} norm").
    private static func bucketLabel(_ p: Profile) -> String {
        if p.bucketMode == "coarse" {
            switch p.bucket {
            case "G": return "guard"
            case "F": return "forward"
            case "C": return "center"
            default: return "positional"
            }
        }
        switch p.bucket {
        case "PG": return "point guard"
        case "SG": return "shooting guard"
        case "SF": return "small forward"
        case "PF": return "power forward"
        case "C": return "center"
        default: return "positional"
        }
    }

    // MARK: - Evidence bullet (cites value AND norm; rounded-tie suppresses direction)

    /// A share/FG% bullet naming the stat AND its norm:
    /// "{label}: {value%} — {above/below} the ~{norm%} {bucket} norm[ suffix]". The leading
    /// `label` names WHICH stat is cited (e.g. "rim share", "above-the-break 3s"); the norm
    /// citation is always present ("... norm"). Direction word from `pct`; dropped when the
    /// ROUNDED displayed value ties the ROUNDED displayed norm (never claim a direction the
    /// reader cannot see).
    private static func pctBullet(_ label: String, _ s: Signal, bucket: String,
                                  suffix: String = "") -> String {
        let vShown = pctText(s.value)          // "38%"
        let nShown = pctText(s.norm)
        let dir = direction(pct: s.pct, valueRounded: roundedPct(s.value), normRounded: roundedPct(s.norm))
        let core: String
        if dir.isEmpty {
            core = "\(label): \(vShown) vs ~\(nShown) \(bucket) norm"
        } else {
            core = "\(label): \(vShown) — \(dir) the ~\(nShown) \(bucket) norm"
        }
        return core + suffix
    }

    /// A size bullet naming the stat AND its norm:
    /// "{label}: {value}\" — {above/below} the ~{norm}\" {bucket} norm".
    private static func inchesBullet(_ label: String, _ s: Signal, bucket: String) -> String {
        let v = Int(s.value.rounded())
        let n = Int(s.norm.rounded())
        let dir = direction(pct: s.pct, valueRounded: Double(v), normRounded: Double(n))
        if dir.isEmpty {
            return "\(label): \(v)\" vs ~\(n)\" \(bucket) norm"
        }
        return "\(label): \(v)\" — \(dir) the ~\(n)\" \(bucket) norm"
    }

    /// "above" / "below" / "" (suppressed on a rounded-displayed tie).
    private static func direction(pct: Double, valueRounded: Double, normRounded: Double) -> String {
        if valueRounded == normRounded { return "" }   // rounded-tie suppression
        if pct >= PCT_ABOVE { return "above" }
        if pct <= PCT_BELOW { return "below" }
        return ""                                       // near the norm -> no direction claim
    }

    private static func pctText(_ frac: Double) -> String { "\(Int((frac * 100).rounded()))%" }
    private static func roundedPct(_ frac: Double) -> Double { (frac * 100).rounded() }
}

extension ShotProfileInsight {

    // MARK: - Family 1: Spacing role & gravity (NQ3: headline keys on total threeShare)

    static func spacing(_ p: Profile, enabled: Bool = INTERIOR_ANCHOR_ENABLED) -> ShotProfileInsight? {
        let word = bigWord(p)
        let label = bucketLabel(p)
        let three = p.signals["threeShare"]
        let rim = p.signals["rimShare"]
        let threeFg = p.signals["threeFgPct"]
        let rimFg = p.signals["rimFgPct"]
        let basis = "Basis: shot profile + size. Not lineup on/off data, so real-game spacing may differ."
            + (p.bucketMode == "coarse" ? " (vs \(label) norms)." : "")

        // FIX 2: 5-out enables/limits copy is a big-man read only — attached as a suffix on
        // an ALREADY-cited bullet (keeps the every-bullet-cites-value-and-norm guardrail).
        let isBig = BIG_BUCKETS.contains(p.bucket)

        // Floor-spacer
        if let three, let threeFg,
           three.pct >= FLOOR_SPACER_3SHARE_PCT, threeFg.value >= FLOOR_SPACER_3FG_MIN {
            var ev = [ "\u{2022} " + pctBullet("3P share", three, bucket: label,
                                               suffix: isBig ? " — profile supports 5-out looks" : ""),
                       "\u{2022} " + pctBullet("3P%", threeFg, bucket: label) ]
            if let atb = p.signals["atbShare"] {
                ev.append("\u{2022} " + pctBullet("above-the-break 3s", atb, bucket: label,
                                                  suffix: " (where the volume comes from)"))
            }
            if let rim, rim.pct <= PCT_STRONG_LOW {
                ev.append("\u{2022} " + pctBullet("rim share", rim, bucket: label,
                                                  suffix: " — limited vertical/rim pressure"))
            }
            return ShotProfileInsight(
                family: .spacing, headline: "Likely a floor-spacing \(word)",
                confidence: confidence(fga: p.fga, drivingPcts: [three.pct]),
                evidence: ev, basis: basis)
        }
        // Rim-gravity — FIX 1: gated to BIG_BUCKETS. "vertical/lob threat" is a big-man claim;
        // on real data the ungated rule mislabeled ~60 guards/wings (e.g. a high-usage PG) as
        // lob threats. A non-big rim-dominant profile falls through (it can't match a clog-risk
        // >= 75th-pct rim share) → family 1 stays silent (silence over a wrong claim).
        if isBig, let rim, let rimFg,
           rim.pct >= RIM_GRAVITY_RIMSHARE_PCT, rimFg.value >= RIM_GRAVITY_RIMFG_MIN {
            var ev = [ "\u{2022} " + pctBullet("rim share", rim, bucket: label,
                                               suffix: " \u{2014} vertical spacing / lob gravity near the rim"),
                       "\u{2022} " + pctBullet("rim FG%", rimFg, bucket: label) ]
            if let three, three.pct <= PCT_STRONG_LOW {
                ev.append("\u{2022} " + pctBullet("3P share", three, bucket: label,
                                                  suffix: " — not a floor-spacer"))
            }
            return ShotProfileInsight(
                family: .spacing, headline: "Rim-gravity \(word) — vertical/lob threat",
                confidence: confidence(fga: p.fga, drivingPcts: [rim.pct]),
                evidence: ev, basis: basis)
        }
        // Clog-risk
        if let three, let rim,
           three.pct <= CLOG_RISK_3SHARE_PCT, rim.pct <= CLOG_RISK_RIMSHARE_PCT {
            let ev = [ "\u{2022} " + pctBullet("3P share", three, bucket: label),
                       "\u{2022} " + pctBullet("rim share", rim, bucket: label) ]
            return ShotProfileInsight(
                family: .spacing, headline: "Non-spacing profile — may crowd the paint",
                // SW-1: pass the FULL enumerated set [threeShare.pct, rimShare.pct]; earned()
                // takes max over |pct-50| PER SIGNAL. Pre-reducing with max(pct) is wrong —
                // pcts 10 and 40 must earn from 10 (|10-50|=40), not from 40 (|40-50|=10).
                confidence: confidence(fga: p.fga, drivingPcts: [three.pct, rim.pct]),
                evidence: ev, basis: basis)
        }
        // D4: neutral interior-anchor (fills the F1 gap band; big buckets only; NEUTRAL, not a
        // deficiency). Placed after clog-risk (rim <= 55) so the bands are disjoint (anchor: rim in (55,75]).
        if enabled, isBig, let three, let rim,
           three.pct <= INTERIOR_ANCHOR_3SHARE_PCT_MAX,
           rim.pct > INTERIOR_ANCHOR_RIMSHARE_PCT_LO, rim.pct <= INTERIOR_ANCHOR_RIMSHARE_PCT_HI {
            let ev = [ "\u{2022} " + pctBullet("rim share", rim, bucket: label,
                                               suffix: " \u{2014} an interior-oriented profile, in the 55th\u{2013}75th-percentile interior band"),
                       "\u{2022} " + pctBullet("3P share", three, bucket: label,
                                               suffix: " \u{2014} not a floor-spacer, at/below the 25th-percentile spacer gate") ]
            return ShotProfileInsight(
                family: .spacing, headline: "Interior-oriented \(word) \u{2014} paint-centered shot profile",
                confidence: confidence(fga: p.fga, drivingPcts: [three.pct, rim.pct]),
                evidence: ev, basis: basis)
        }
        return nil
    }

    // MARK: - Family 2: Position viability (Stretch -> Small-ball -> Undersized -> Prototypical)

    private static func positionViability(_ p: Profile) -> ShotProfileInsight? {
        guard p.position != nil, let height = p.signals["heightIn"] else { return nil }
        let wing = p.signals["wingspanIn"]
        let word = bigWord(p)
        let label = bucketLabel(p)
        let three = p.signals["threeShare"]
        let hasWing = wing != nil
        let cap: Confidence = hasWing ? .high : .moderate
        var basis = "Basis: listed size vs \(label) norms + shot profile. Not defensive tracking or role data."
        if !hasWing { basis += " Wingspan unavailable — read is height-only." }

        func sizeEvidence() -> [String] {
            var ev = ["\u{2022} " + inchesBullet("height", height, bucket: label)]
            if let wing { ev.append("\u{2022} " + inchesBullet("wingspan", wing, bucket: label)) }
            return ev
        }
        func drivingSize() -> [Double] {
            var d = [height.pct]; if let wing { d.append(wing.pct) }; return d
        }

        // Stretch big (bucket C/PF + high three share)
        if (p.bucket == "C" || p.bucket == "PF"), let three, three.pct >= STRETCH_BIG_3SHARE_PCT {
            var ev = sizeEvidence()
            ev.append("\u{2022} " + pctBullet("3P share", three, bucket: label))
            return ShotProfileInsight(
                family: .positionViability, headline: "Stretch \(word)",
                confidence: confidence(fga: p.fga, drivingPcts: [three.pct], cap: cap),
                evidence: ev, basis: basis)
        }
        // Small-ball-only (C bucket, undersized, NOT a stretch big).
        // SW-2: this label cites height + rim + three shares, so ALL of heightIn (already
        // bound), rimShare AND threeShare must be present — no `?? 0` fabricated pct. If any
        // required cited signal is absent the label does NOT fire (falls through to Undersized).
        if p.bucket == "C", height.pct <= SIZE_UNDERSIZED_PCT,
           let rim = p.signals["rimShare"], let three, three.pct < STRETCH_BIG_3SHARE_PCT {
            var ev = sizeEvidence()
            ev.append("\u{2022} " + pctBullet("rim share", rim, bucket: label))
            ev.append("\u{2022} " + pctBullet("3P share", three, bucket: label))
            return ShotProfileInsight(
                family: .positionViability, headline: "Small-ball \(word) profile",
                confidence: confidence(fga: p.fga, drivingPcts: [height.pct, three.pct], cap: cap),
                evidence: ev, basis: basis)
        }
        // Undersized (SW-7: noun from the (bucket, bucketMode) helper, never raw p.position)
        let wingUnder = wing.map { $0.pct <= SIZE_UNDERSIZED_PCT } ?? true
        if height.pct <= SIZE_UNDERSIZED_PCT, wingUnder {
            return ShotProfileInsight(
                family: .positionViability, headline: "Undersized for \(viabilityNoun(p))",
                confidence: confidence(fga: p.fga, drivingPcts: drivingSize(), cap: cap),
                evidence: sizeEvidence(), basis: basis)
        }
        // Prototypical / traditional (SW-7: noun from the helper, never raw p.position)
        let wingProto = wing.map { $0.pct >= SIZE_PROTOTYPE_PCT } ?? true
        if height.pct >= SIZE_PROTOTYPE_PCT, wingProto {
            let head = (p.bucketMode == "specific" && p.bucket == "C" && (three?.pct ?? 100) < STRETCH_BIG_3SHARE_PCT)
                ? "Traditional 5 size"
                : "Prototypical \(viabilityNoun(p)) size"
            return ShotProfileInsight(
                family: .positionViability, headline: head,
                confidence: confidence(fga: p.fga, drivingPcts: drivingSize(), cap: cap),
                evidence: sizeEvidence(), basis: basis)
        }
        return nil
    }

    // MARK: - Family 3: Shot diet & hot/cold

    private static func shotDiet(_ p: Profile) -> ShotProfileInsight? {
        guard let rim = p.signals["rimShare"], let mid = p.signals["midShare"],
              let three = p.signals["threeShare"] else { return nil }
        let label = bucketLabel(p)
        let mixRim = p.mix.rim, mixMid = p.mix.mid, mixThree = p.mix.three

        var headline: String
        var evidence: [String]
        var driving: [Double]

        if rim.pct >= THREE_LEVEL_MIN_PCT, mid.pct >= THREE_LEVEL_MIN_PCT,
           three.pct >= THREE_LEVEL_MIN_PCT,
           max(mixRim, max(mixMid, mixThree)) <= THREE_LEVEL_SPREAD_MAX {
            headline = "Three-level scorer"
            evidence = [ "\u{2022} " + pctBullet("rim share", rim, bucket: label),
                         "\u{2022} " + pctBullet("mid share", mid, bucket: label),
                         "\u{2022} " + pctBullet("3P share", three, bucket: label) ]
            driving = [rim.pct, mid.pct, three.pct]
        } else if let (area, dominantSig, dominantMix) = dominantComponent(p, rim: rim, mid: mid, three: three),
                  dominantMix >= ONE_DIM_DOMINANT_SHARE {
            headline = "One-dimensional \(area) scorer"
            // SW-8: name the SMALLEST of the three labeled shares concretely ("rim share"/
            // "mid-range share"/"3-point share") — never the generic phrase "smallest share".
            let named: [(String, Signal)] = [("rim share", rim), ("mid-range share", mid),
                                             ("3-point share", three)]
            let smallest = named.min { $0.1.value < $1.1.value }!
            evidence = [ "\u{2022} " + pctBullet("\(area) share", dominantSig, bucket: label),
                         "\u{2022} " + pctBullet(smallest.0, smallest.1, bucket: label) ]
            driving = [dominantSig.pct]
        } else {
            // Balanced: cite the two most norm-divergent of rim/mid/three by |pct-50|,
            // ties broken rim -> mid -> three.
            let ordered = [("rim", rim), ("mid", mid), ("three", three)]
                .enumerated()
                .sorted { a, b in
                    let da = abs(a.element.1.pct - 50), db = abs(b.element.1.pct - 50)
                    return da == db ? a.offset < b.offset : da > db
                }
                .map { $0.element }
            headline = "Balanced shot diet"
            evidence = ordered.prefix(2).map { "\u{2022} " + pctBullet("\($0.0) share", $0.1, bucket: label) }
            driving = ordered.prefix(2).map { $0.1.pct }
        }

        let conf = confidence(fga: p.fga, drivingPcts: driving)
        // Hot/cold bullets (up to 2) over rim/mid/three FG% groups gated by group FGA.
        evidence += hotColdBullets(p, label: label)

        var basis = "Basis: shot-location mix + FG% vs \(label) norms, season 2025-26 so far. Not defensive or tracking data."
        if conf == .moderate { basis += " Sample may be small." }
        return ShotProfileInsight(family: .shotDiet, headline: headline,
                                  confidence: conf, evidence: evidence, basis: basis)
    }

    /// The dominant labeled mix component (rim/mid/three only; paintNonRim never drives).
    private static func dominantComponent(_ p: Profile, rim: Signal, mid: Signal, three: Signal)
        -> (area: String, sig: Signal, mix: Double)? {
        let candidates: [(String, Signal, Double)] = [
            ("rim", rim, p.mix.rim), ("mid-range", mid, p.mix.mid), ("3", three, p.mix.three),
        ]
        return candidates.max { $0.2 < $1.2 }.map { (area: $0.0, sig: $0.1, mix: $0.2) }
    }

    /// Up to 2 hot/cold bullets over the three FG% signals, each requiring its group FGA
    /// >= ZONE_MIN_FGA, kept by |pct-50|, tie-break rim -> mid -> three.
    private static func hotColdBullets(_ p: Profile, label: String) -> [String] {
        func groupFga(_ zoneNames: [String]) -> Int {
            zoneNames.reduce(0) { $0 + (p.zones[$1]?.fga ?? 0) }
        }
        // (order-index, signalKey, phrase, group FGA)
        let groups: [(Int, String, String, Int)] = [
            (0, "rimFgPct", "at the rim", groupFga(["Restricted Area"])),
            (1, "midFgPct", "from mid-range", groupFga(["Mid-Range"])),
            (2, "threeFgPct", "from three", groupFga(["Left Corner 3", "Right Corner 3", "Above the Break 3"])),
        ]
        var eligible: [(Int, Signal, String)] = []
        for (idx, key, phrase, fga) in groups {
            guard fga >= ZONE_MIN_FGA, let s = p.signals[key] else { continue }
            // SW-3: a hot/cold bullet is a direction claim ("over/under-performing"). If the
            // DISPLAYED (rounded) FG% ties the DISPLAYED (rounded) norm, a direction cannot be
            // shown — SKIP the bullet entirely (it also does not consume the up-to-2 cap).
            if roundedPct(s.value) == roundedPct(s.norm) { continue }
            if s.pct >= HOTCOLD_FGPCT_PCT_HIGH || s.pct <= HOTCOLD_FGPCT_PCT_LOW {
                eligible.append((idx, s, phrase))
            }
        }
        let kept = eligible
            .sorted { a, b in
                let da = abs(a.1.pct - 50), db = abs(b.1.pct - 50)
                return da == db ? a.0 < b.0 : da > db
            }
            .prefix(2)
        return kept.map { (_, s, phrase) in
            let verb = s.pct >= HOTCOLD_FGPCT_PCT_HIGH ? "over-performing" : "under-performing"
            return "\u{2022} \(verb) \(phrase): \(pctText(s.value)) vs ~\(pctText(s.norm)) \(label) norm"
        }
    }
}
