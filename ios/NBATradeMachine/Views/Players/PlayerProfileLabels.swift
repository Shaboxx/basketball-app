import Foundation

/// A descriptive label that fired for a single player, with display metadata.
/// `salience` drives best-3 selection (higher wins); `dimension` enforces the
/// "at most one label per dimension" rule and provides the tie-break order.
nonisolated struct ProfileLabel: Equatable, Hashable {
    let text: String
    let dimension: Dimension
    let salience: Int
    let style: Style

    /// The label families. Each dimension contributes AT MOST ONE label to the
    /// final set. The raw value also encodes the tie-break order for equal
    /// salience (lower rawValue wins): H > B > A > D > F > C.
    nonisolated enum Dimension: Int, Equatable, Hashable, CaseIterable {
        case headline   = 0   // H — marquee
        case impact     = 1   // B — impact tier
        case role       = 2   // A — role / playstyle
        case career     = 3   // D — career phase
        case contract   = 4   // F — contract / asset
        case reputation = 5   // C — reputation
    }

    /// Visual treatment hint for the UI. `descriptive` is the subtle neutral
    /// chip; `accent` is reserved for marquee headlines.
    nonisolated enum Style: Equatable, Hashable {
        case descriptive
        case accent
    }
}

/// Dynamic "player profile labels" engine. Pure, deterministic, and league
/// -relative where noted. Produces the top-3 best-fit descriptive labels for a
/// player's profile card.
///
/// Concurrency: this is a pure `nonisolated enum` with NO mutable state. Because
/// `nonisolated` on the type does not propagate to members in this toolchain,
/// EVERY member is marked `nonisolated` explicitly (mirrors the proven template
/// in Views/Shared/LineupLabeling/LineupTags.swift).
nonisolated enum PlayerProfileLabels {

    private typealias N = LineupNorms

    // MARK: - Public entry point

    /// The top-3 best-fit labels for `player`, league-relative against `norms`.
    /// Collects the single best label per dimension, sorts by salience desc
    /// (tie-break by dimension order H>B>A>D>F>C), and returns the first 3.
    nonisolated static func labels(for player: Player, norms: LeagueNorms?) -> [ProfileLabel] {
        let age = playerAge(player)
        let impactPctl = impactPercentile(player)
        let volumePctl = norms.flatMap { N.pctl(player.lineupFeatures, "usg", $0) }

        var collected: [ProfileLabel] = []

        if let h = headlineLabel(player, impactPctl: impactPctl, age: age) {
            collected.append(h)
        }
        if let b = impactLabel(impactPctl: impactPctl) {
            collected.append(b)
        }
        if let a = roleLabel(player, norms: norms) {
            collected.append(a)
        }
        if let d = careerLabel(player, age: age) {
            collected.append(d)
        }
        if let f = contractLabel(player) {
            collected.append(f)
        }
        if let c = reputationLabel(impactPctl: impactPctl, volumePctl: volumePctl) {
            collected.append(c)
        }

        // Sort by salience desc, then by dimension order (lower rawValue first).
        let sorted = collected.sorted { lhs, rhs in
            if lhs.salience != rhs.salience { return lhs.salience > rhs.salience }
            return lhs.dimension.rawValue < rhs.dimension.rawValue
        }
        return Array(sorted.prefix(3))
    }

    // MARK: - Shared derivations

    /// Whole-year age from `birthdate` ("YYYY-MM-DD"); nil when missing or
    /// unparseable. Computed inline (rather than via `Player.age()`, which is
    /// main-actor isolated) so the engine stays a pure `nonisolated` type, and
    /// without a stored formatter so there is no shared mutable global state.
    private nonisolated static func playerAge(_ player: Player) -> Int? {
        guard let birthdate = player.birthdate else { return nil }
        let parts = birthdate.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let dob = cal.date(from: comps) else { return nil }
        return cal.dateComponents([.year], from: dob, to: Date()).year
    }

    /// Standard-normal CDF Φ(x) = 0.5 * erfc(-x / sqrt(2)).
    private nonisolated static func phi(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Impact percentile in [0,1] from thetaBoard.blend (preferred; blend is z-scale-compatible
    /// with the old combined) or latentValue.thetaZ (fallback): pctl = Φ(theta / 2).
    /// nil when neither signal is present.
    private nonisolated static func impactPercentile(_ player: Player) -> Double? {
        if let combined = player.thetaBoard?.blend {
            return phi(combined / 2.0)
        }
        if let thetaZ = player.latentValue?.thetaZ {
            return phi(thetaZ / 2.0)
        }
        return nil
    }

    private nonisolated static func ge(_ value: Double?, _ threshold: Double) -> Bool {
        value != nil && value! >= threshold
    }

    private nonisolated static func le(_ value: Double?, _ threshold: Double) -> Bool {
        value != nil && value! <= threshold
    }

    /// Coarse position bucket from positionEligibility.primary (guard/wing/big).
    private nonisolated static func bucket(_ player: Player) -> String? {
        guard let raw = player.positionEligibility?.primary?.uppercased() else { return nil }
        switch raw {
        case "PG", "SG", "G", "GUARD": return "guard"
        case "SF", "GF", "WING", "F": return "wing"
        case "PF", "C", "FC", "BIG": return "big"
        default: return nil
        }
    }

    private nonisolated static func isGuard(_ player: Player) -> Bool { bucket(player) == "guard" }
    private nonisolated static func isWing(_ player: Player) -> Bool { bucket(player) == "wing" }
    private nonisolated static func isBig(_ player: Player) -> Bool { bucket(player) == "big" }

    // MARK: - B. Impact tier (salience 90)

    private nonisolated static func impactLabel(impactPctl: Double?) -> ProfileLabel? {
        guard let p = impactPctl else { return nil }
        let text: String
        switch p {
        case let x where x >= 0.99: text = "Superstar"
        case let x where x >= 0.95: text = "All-NBA"
        case let x where x >= 0.90: text = "All-Star"
        case let x where x >= 0.75: text = "Quality Starter"
        case let x where x >= 0.55: text = "Solid Rotation"
        case let x where x >= 0.30: text = "Bench"
        case let x where x >= 0.10: text = "Replacement-Level"
        default: text = "Below Replacement"
        }
        return ProfileLabel(text: text, dimension: .impact, salience: 90, style: .descriptive)
    }

    // MARK: - D. Career phase (salience 70)

    private nonisolated static func careerLabel(_ player: Player, age: Int?) -> ProfileLabel? {
        let yos = player.yos
        let text: String?
        if yos == 0 {
            text = "Rookie"
        } else if yos == 1 {
            text = "Sophomore"
        } else if let a = age, a <= 24, (yos ?? 0) <= 4 {
            text = "Young / Developing"
        } else if let a = age, (26...30).contains(a) {
            text = "In His Prime"
        } else if let a = age, a >= 33 {
            text = "Veteran"
        } else if (yos ?? 0) >= 13 {
            text = "Veteran"
        } else if age != nil || yos != nil {
            text = "Established"
        } else {
            text = nil
        }
        guard let t = text else { return nil }
        return ProfileLabel(text: t, dimension: .career, salience: 70, style: .descriptive)
    }

    // MARK: - F. Contract / asset (salience 78)

    private nonisolated static func contractLabel(_ player: Player) -> ProfileLabel? {
        // First match wins.
        if player.supermaxEligible == true || (player.maxTierPct ?? 0) >= 35 {
            return ProfileLabel(text: "Max / Supermax", dimension: .contract, salience: 78, style: .descriptive)
        }
        if let tier = player.compZ?.asset?.tier, tier == .tradeChip || tier == .plus {
            return ProfileLabel(text: "Bargain", dimension: .contract, salience: 78, style: .descriptive)
        }
        if let tier = player.compZ?.asset?.tier, tier == .minus || tier == .dead {
            return ProfileLabel(text: "Overpaid", dimension: .contract, salience: 78, style: .descriptive)
        }
        if (player.salaryY1 ?? 0) > 0 && (player.salaryY2 ?? 0) == 0 {
            return ProfileLabel(text: "Expiring", dimension: .contract, salience: 78, style: .descriptive)
        }
        let rookieScaleCeiling = player.minSalary.map { $0 * 3 } ?? 8_000_000
        if (player.yos ?? 99) <= 3 && (player.salaryY1 ?? 0) < rookieScaleCeiling {
            return ProfileLabel(text: "Rookie-Scale", dimension: .contract, salience: 78, style: .descriptive)
        }
        return nil
    }

    // MARK: - C. Reputation (salience 74)

    private nonisolated static func reputationLabel(impactPctl: Double?, volumePctl: Double?) -> ProfileLabel? {
        guard let impact = impactPctl, let volume = volumePctl else { return nil }
        if impact - volume >= 0.25 {
            return ProfileLabel(text: "Underrated", dimension: .reputation, salience: 74, style: .descriptive)
        }
        if volume - impact >= 0.25 {
            return ProfileLabel(text: "Overrated", dimension: .reputation, salience: 74, style: .descriptive)
        }
        if volume >= 0.75 && impact < 0.50 {
            return ProfileLabel(text: "Empty Stats", dimension: .reputation, salience: 74, style: .descriptive)
        }
        return nil
    }

    // MARK: - A. Role / playstyle (salience 80)

    /// First-match-by-priority role from lineup-feature percentiles + position
    /// bucket. Abstains (nil) when lineupFeatures/norms are missing or nothing
    /// fires.
    private nonisolated static func roleLabel(_ player: Player, norms: LeagueNorms?) -> ProfileLabel? {
        guard let norms, let lf = player.lineupFeatures else { return nil }
        func p(_ feat: String) -> Double? { N.pctl(lf, feat, norms) }
        let guardP = isGuard(player)
        let wingP = isWing(player)
        let bigP = isBig(player)

        let text: String?
        if ge(p("load"), 0.90) && ge(p("box_creation"), 0.85) {
            text = "Heliocentric Engine"
        } else if guardP && ge(p("passer_rtg"), 0.75) && ge(p("load"), 0.65) {
            text = "Floor General"
        } else if bigP && ge(p("rim_def_delta"), 0.80) && ge(p("blk_pct"), 0.75) {
            text = "Defensive Anchor"
        } else if bigP && ge(p("three_par"), 0.60) {
            text = "Stretch Big"
        } else if bigP && ge(p("z_ra"), 0.70) && le(p("three_par"), 0.30) {
            text = "Roll Man / Lob Threat"
        } else if wingP && ge(p("three_par"), 0.60) && (ge(p("stl_pct"), 0.6) || ge(p("versatility"), 0.6)) && le(p("load"), 0.55) {
            text = "3&D Wing"
        } else if wingP && ge(p("z_ra"), 0.65) && ge(p("ftr"), 0.60) {
            text = "Slashing Wing"
        } else if ge(p("three_par"), 0.70) && le(p("load"), 0.35) {
            text = "Spot-Up Specialist"
        } else if ge(p("stl_pct"), 0.75) && le(p("load"), 0.5) {
            text = "Lockdown / POA Stopper"
        } else if ge(p("passer_rtg"), 0.6) && le(p("load"), 0.45) && ge(p("versatility"), 0.55) {
            text = "Connector / Glue Guy"
        } else if ge(p("load"), 0.6) && ge(p("z_ra"), 0.5) && ge(p("z_mid"), 0.5) && ge(p("three_par"), 0.4) {
            text = "3-Level Scorer"
        } else {
            text = nil
        }

        guard let t = text else { return nil }
        return ProfileLabel(text: t, dimension: .role, salience: 80, style: .descriptive)
    }

    // MARK: - H. Headline (salience 100)

    private nonisolated static func headlineLabel(_ player: Player, impactPctl: Double?, age: Int?) -> ProfileLabel? {
        guard let impact = impactPctl else { return nil }
        let yos = player.yos ?? 0
        let text: String?
        if impact >= 0.95, let a = age, a <= 30, yos >= 2 {
            text = "Franchise Player"
        } else if impact >= 0.75, let a = age, a <= 23 {
            text = "Building Block / Future Star"
        } else if impact >= 0.6, impact < 0.9, let a = age, a >= 33 {
            text = "Aging Star"
        } else {
            text = nil
        }
        guard let t = text else { return nil }
        return ProfileLabel(text: t, dimension: .headline, salience: 100, style: .accent)
    }
}
