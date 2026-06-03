import Foundation

/// A descriptive tag that fired for a lineup, with display metadata.
nonisolated struct LineupTag: Equatable, Hashable, Identifiable {
    let key: String          // registry key, e.g. "spread_high_spacing"
    let category: String     // "offense" | "defense" | "possession" | "liability"
    let label: String        // human-readable label
    var isProxy: Bool        // trigger is a PROXY for an unavailable measurement
    var id: String { key }
}

/// Part-2 descriptive TAGS for a five-man lineup — a faithful Swift port of
/// scripts/lineup_labeling/tags.py. Each predicate is pure over the 5-player
/// feature records and the league norms. Thresholds are the SAME tunable
/// constants as tags.py. The registry carries each tag's category, label,
/// enables and strains; the engine consumes both predicates and registry.
nonisolated enum LineupTags {

    // MARK: - Tunable thresholds (mirror tags.py)

    // Offensive
    static let SPACING_CORNER_PCTL = 0.50
    static let SPACING_MIN_SPACERS = 4
    static let SPACING_SHOOTQ_PCTL = 0.40
    static let CLOG_THREEPAR_PCTL = 0.20
    static let CLOG_MIN_CLOGGERS = 2
    static let CLOG_SQ_PCTL = 0.45
    static let MOVEMENT_ATB3_PCTL = 0.60
    static let MOVEMENT_FG3_PCTL = 0.50
    static let RIM_PRESSURE_PCTL = 0.60
    static let INTERIOR_POST_PCTL = 0.60
    static let INTERIOR_TS_PCTL = 0.50
    static let MIDRANGE_PCTL = 0.62
    static let MIDRANGE_SQ_MIN = 0.30
    static let MIDRANGE_SQ_MAX = 0.70
    static let PLAYMAKING_CREATION_PCTL = 0.58
    static let PLAYMAKING_PASSER_PCTL = 0.55
    static let PLAYMAKING_MAX_HHI = 0.30
    static let BALL_DOM_LOAD_PCTL = 0.85
    static let BALL_DOM_MIN_HHI = 0.28
    static let BALL_DOM_SECOND_CREATION_PCTL = 0.45

    // Defensive (REAL tracking features as of the Phase-1 de-proxy)
    static let SWITCH_VERSATILITY_PCTL = 0.50
    static let SWITCH_MIN_SWITCHERS = 4

    // rim_protection: >=1 player with real rim volume AND below-expected rim FG%.
    static let RIM_VOL_PCTL = 0.60       // rim_dfga_per36 percentile (gate on volume)
    static let RIM_DELTA_PCTL = 0.80     // rim_def_delta percentile (defends better than expected)

    // poa_d: >=2 real perimeter defenders / deflectors who don't foul.
    static let POA_PERIM_PCTL = 0.75     // perim_def_delta percentile
    static let POA_DEFLECT_PCTL = 0.78   // deflections_per36 percentile (OR with perim D)
    static let POA_RPF_PCTL = 0.50       // but they don't foul a lot (low rpf)
    static let POA_MIN_DEFENDERS = 2

    // disruptive: high lineup-mean deflections.
    static let DISRUPTIVE_DEFLECT_PCTL = 0.62

    // drop_bound: tall interior defender who CANNOT switch (+ P&R-roll D when known).
    static let DROP_HEIGHT_IN = 82.0
    static let DROP_RIM_DELTA_PCTL = 0.55   // real interior defense (rim_def_delta)
    static let DROP_VERSATILITY_PCTL = 0.40 // ...and NOT switchable (low versatility)
    static let DROP_PNR_PCTL = 0.55         // Synergy P&R-roll defense (null -> not required)

    // Possession / physical
    static let GLASS_PCTL = 0.58
    static let FOUL_DRAW_FTR_PCTL = 0.60
    static let YOUTH_AGE_MAX = 24.0
    static let VETERAN_AGE_MIN = 31.0
    static let UP_TEMPO_PACE_PCTL = 0.62    // lineup-mean pace percentile clearly above league

    // Liability
    static let HACK_FT_PCT = 65.0
    static let HACK_MIN_HACKERS = 2
    static let TURNOVER_TOV_PCTL = 0.60
    static let TURNOVER_CTOV_PCTL = 0.55
    static let FOUL_PRONE_RPF_PCTL = 0.62

    // MARK: - Helpers (mirror tags._ge / _le)

    private static func ge(_ value: Double?, _ threshold: Double) -> Bool {
        value != nil && value! >= threshold
    }

    private static func le(_ value: Double?, _ threshold: Double) -> Bool {
        value != nil && value! <= threshold
    }

    private typealias N = LineupNorms

    // MARK: - Offensive tags

    static func spreadHighSpacing(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let spacers = N.countAbove(players, "z_corner3", SPACING_CORNER_PCTL, norms)
        let shootOk = ge(N.meanPctl(players, "fg3_pct", norms), SPACING_SHOOTQ_PCTL)
            || ge(N.meanPctl(players, "sq", norms), SPACING_SHOOTQ_PCTL)
        return spacers >= SPACING_MIN_SPACERS && shootOk
    }

    static func cloggedLowSpacing(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let cloggers = N.countBelow(players, "three_par", CLOG_THREEPAR_PCTL, norms)
        let lowSq = le(N.meanPctl(players, "sq", norms), CLOG_SQ_PCTL)
        return cloggers >= CLOG_MIN_CLOGGERS && lowSq
    }

    static func movementShooting(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let atb = ge(N.meanPctl(players, "z_atb3", norms), MOVEMENT_ATB3_PCTL)
        let acc = ge(N.meanPctl(players, "fg3_pct", norms), MOVEMENT_FG3_PCTL)
            || ge(N.meanPctl(players, "ts", norms), MOVEMENT_FG3_PCTL)
        return atb && acc
    }

    static func rimPressure(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let ra = ge(N.meanPctl(players, "z_ra", norms), RIM_PRESSURE_PCTL)
        let ftr = ge(N.meanPctl(players, "ftr", norms), RIM_PRESSURE_PCTL)
        let load = ge(N.meanPctl(players, "load", norms), RIM_PRESSURE_PCTL)
        return ra && (ftr || load)
    }

    static func interiorPost(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let paint = ge(N.meanPctl(players, "z_paint", norms), INTERIOR_POST_PCTL)
        let ts = ge(N.meanPctl(players, "ts", norms), INTERIOR_TS_PCTL)
        return paint && ts
    }

    static func midrangeTough(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let mid = ge(N.meanPctl(players, "z_mid", norms), MIDRANGE_PCTL)
        let sq = N.meanPctl(players, "sq", norms)
        let moderate = sq != nil && sq! >= MIDRANGE_SQ_MIN && sq! <= MIDRANGE_SQ_MAX
        return mid && moderate
    }

    static func playmakingHub(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let creation = ge(N.meanPctl(players, "box_creation", norms), PLAYMAKING_CREATION_PCTL)
        let passing = ge(N.meanPctl(players, "passer_rtg", norms), PLAYMAKING_PASSER_PCTL)
        let hhi = N.loadHHI(players.map { N.feat($0, "load") })
        let spread = hhi != nil && hhi! <= PLAYMAKING_MAX_HHI
        return creation && passing && spread
    }

    static func ballDominant(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let topLoad = ge(N.maxPctl(players, "load", norms), BALL_DOM_LOAD_PCTL)
        let hhi = N.loadHHI(players.map { N.feat($0, "load") })
        let concentrated = hhi != nil && hhi! >= BALL_DOM_MIN_HHI
        let second = N.secondPctl(players, "box_creation", norms)
        let noSecond = second == nil || second! <= BALL_DOM_SECOND_CREATION_PCTL
        return topLoad && concentrated && noSecond
    }

    // MARK: - Defensive tags

    /// >=1 player with REAL rim volume AND below-expected opponent rim FG%:
    /// a high rim-defense FGA rate (not a tiny-sample fluke) AND a strong
    /// rim_def_delta (normal − allowed, positive = defends the rim better than
    /// expected). Mirrors tags.rim_protection.
    static func rimProtection(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        for p in players {
            if ge(N.pctl(p, "rim_dfga_per36", norms), RIM_VOL_PCTL)
                && ge(N.pctl(p, "rim_def_delta", norms), RIM_DELTA_PCTL) {
                return true
            }
        }
        return false
    }

    static func switchable(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        N.countAbove(players, "versatility", SWITCH_VERSATILITY_PCTL, norms) >= SWITCH_MIN_SWITCHERS
    }

    /// >=2 REAL point-of-attack defenders: contain on the perimeter OR get a lot
    /// of deflections, AND don't foul a lot (low reaching-foul rate). Mirrors
    /// tags.poa_d.
    static func poaD(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        var n = 0
        for p in players {
            let perim = N.pctl(p, "perim_def_delta", norms)
            let deflect = N.pctl(p, "deflections_per36", norms)
            let rpf = N.pctl(p, "rpf", norms)
            let disrupt = ge(perim, POA_PERIM_PCTL) || ge(deflect, POA_DEFLECT_PCTL)
            let clean = rpf == nil || rpf! <= POA_RPF_PCTL
            if disrupt && clean { n += 1 }
        }
        return n >= POA_MIN_DEFENDERS
    }

    /// High lineup-mean DEFLECTION rate (real ball pressure / forced turnovers).
    /// Mirrors tags.disruptive.
    static func disruptive(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        ge(N.meanPctl(players, "deflections_per36", norms), DISRUPTIVE_DEFLECT_PCTL)
    }

    /// >=1 tall interior defender who CANNOT switch (low versatility): real
    /// interior defense (rim_def_delta) + height + low switchability, plus
    /// Synergy P&R-roll defense when available (null -> not required). Mirrors
    /// tags.drop_bound.
    static func dropBound(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        for p in players {
            let pnr = N.feat(p, "pnr_roll_def_pctl")
            let pnrOk = pnr == nil || pnr! >= DROP_PNR_PCTL
            if ge(N.feat(p, "height_in"), DROP_HEIGHT_IN)
                && ge(N.pctl(p, "rim_def_delta", norms), DROP_RIM_DELTA_PCTL)
                && le(N.pctl(p, "versatility", norms), DROP_VERSATILITY_PCTL)
                && pnrOk {
                return true
            }
        }
        return false
    }

    // MARK: - Possession / physical tags

    static func glass(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let orb = N.meanPctl(players, "orb_pct", norms)
        let drb = N.meanPctl(players, "drb_pct", norms)
        let vals = [orb, drb].compactMap { $0 }
        guard !vals.isEmpty else { return false }
        return (vals.reduce(0, +) / Double(vals.count)) >= GLASS_PCTL
    }

    /// Fast lineup: lineup-mean PACE percentile clearly above the league.
    /// Mirrors tags.up_tempo.
    static func upTempo(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        ge(N.meanPctl(players, "pace", norms), UP_TEMPO_PACE_PCTL)
    }

    static func foulDrawing(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        ge(N.meanPctl(players, "ftr", norms), FOUL_DRAW_FTR_PCTL)
    }

    static func youth(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        guard let age = N.avgAge(players) else { return false }
        return age < YOUTH_AGE_MAX
    }

    static func veteran(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        guard let age = N.avgAge(players) else { return false }
        return age > VETERAN_AGE_MIN
    }

    // MARK: - Liability tags

    static func hackRisk(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        N.countRawBelow(players, "ft_pct", HACK_FT_PCT) >= HACK_MIN_HACKERS
    }

    static func turnoverProne(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        let tov = ge(N.meanPctl(players, "tov_pct", norms), TURNOVER_TOV_PCTL)
        let ctov = ge(N.meanPctl(players, "ctov_pct", norms), TURNOVER_CTOV_PCTL)
        return tov && ctov
    }

    static func foulProne(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Bool {
        ge(N.meanPctl(players, "rpf", norms), FOUL_PRONE_RPF_PCTL)
    }

    // MARK: - Registry

    /// Category ordering used for stable output ordering in the engine.
    static let categoryOrder = ["offense", "defense", "possession", "liability"]

    nonisolated struct TagMeta {
        let fn: ([LineupFeatures?], LeagueNorms) -> Bool
        let category: String
        let label: String
        let enables: [String]
        let strains: [String]
    }

    /// Tags whose triggers are PROXIES for an unavailable measurement. All five
    /// defense/pace tags now read REAL tracking features, so this set is empty;
    /// the symbol is kept so the breakdown UI's proxy `?` glyph mechanism still
    /// exists for any future tag that has to fall back to a proxy.
    static let proxyTags: Set<String> = []

    /// Registry key -> metadata. Insertion order is the stable registry order
    /// (mirrors tags.REGISTRY exactly: offense, defense, possession, liability).
    static let registryKeys: [String] = [
        // Offensive
        "spread_high_spacing", "clogged_low_spacing", "movement_shooting",
        "rim_pressure", "interior_post", "midrange_tough", "playmaking_hub",
        "ball_dominant",
        // Defensive
        "rim_protection", "switchable", "poa_d", "disruptive", "drop_bound",
        // Possession / physical
        "glass", "up_tempo", "foul_drawing", "youth", "veteran",
        // Liability
        "hack_risk", "turnover_prone", "foul_prone",
    ]

    static let registry: [String: TagMeta] = [
        "spread_high_spacing": TagMeta(
            fn: spreadHighSpacing, category: "offense",
            label: "High Spacing (5-Out Spread)",
            enables: ["driving lanes", "kick-out threes", "closeout attacks"],
            strains: []),
        "clogged_low_spacing": TagMeta(
            fn: cloggedLowSpacing, category: "offense",
            label: "Clogged Spacing",
            enables: [],
            strains: ["driving lanes", "kick-out threes"]),
        "movement_shooting": TagMeta(
            fn: movementShooting, category: "offense",
            label: "Movement Shooting",
            enables: ["off-ball screening actions", "relocation threes"],
            strains: []),
        "rim_pressure": TagMeta(
            fn: rimPressure, category: "offense",
            label: "Rim Pressure",
            enables: ["downhill drives", "free-throw trips", "collapse-and-kick"],
            strains: []),
        "interior_post": TagMeta(
            fn: interiorPost, category: "offense",
            label: "Interior / Post Scoring",
            enables: ["post-ups", "paint touches", "second-side actions"],
            strains: []),
        "midrange_tough": TagMeta(
            fn: midrangeTough, category: "offense",
            label: "Midrange (Tough Shots)",
            enables: ["late-clock shot-making"],
            strains: ["shot quality"]),
        "playmaking_hub": TagMeta(
            fn: playmakingHub, category: "offense",
            label: "Shared Playmaking",
            enables: ["ball movement", "advantage passing", "open shots"],
            strains: []),
        "ball_dominant": TagMeta(
            fn: ballDominant, category: "offense",
            label: "Ball-Dominant Engine",
            enables: ["shot creation", "late-clock bailouts"],
            strains: ["ball movement", "off-ball rhythm"]),
        "rim_protection": TagMeta(
            fn: rimProtection, category: "defense",
            label: "Rim Protection",
            enables: ["paint deterrence", "shot contests at the rim"],
            strains: []),
        "switchable": TagMeta(
            fn: switchable, category: "defense",
            label: "Switchable Defense",
            enables: ["switch coverage", "ball-screen defense without help"],
            strains: []),
        "poa_d": TagMeta(
            fn: poaD, category: "defense",
            label: "Point-of-Attack Defense",
            enables: ["on-ball containment", "pressure full court"],
            strains: []),
        "disruptive": TagMeta(
            fn: disruptive, category: "defense",
            label: "Disruptive / Forced Turnovers",
            enables: ["forced turnovers", "transition off defense"],
            strains: []),
        "drop_bound": TagMeta(
            fn: dropBound, category: "defense",
            label: "Drop-Coverage Bound",
            enables: ["paint protection in drop"],
            strains: ["switch coverage", "perimeter coverage on the big"]),
        "glass": TagMeta(
            fn: glass, category: "possession",
            label: "Strong on the Glass",
            enables: ["second-chance points", "defensive-rebound stops"],
            strains: []),
        "up_tempo": TagMeta(
            fn: upTempo, category: "possession",
            label: "Up-Tempo",
            enables: ["transition offense"],
            strains: []),
        "foul_drawing": TagMeta(
            fn: foulDrawing, category: "possession",
            label: "Foul Drawing",
            enables: ["free-throw trips", "bonus pressure"],
            strains: []),
        "youth": TagMeta(
            fn: youth, category: "possession",
            label: "Young Lineup",
            enables: ["energy", "transition athleticism"],
            strains: ["late-game execution"]),
        "veteran": TagMeta(
            fn: veteran, category: "possession",
            label: "Veteran Lineup",
            enables: ["late-game execution", "poise"],
            strains: ["transition athleticism"]),
        "hack_risk": TagMeta(
            fn: hackRisk, category: "liability",
            label: "Hack-a Risk",
            enables: [],
            strains: ["free-throw trips", "late-game closing"]),
        "turnover_prone": TagMeta(
            fn: turnoverProne, category: "liability",
            label: "Turnover-Prone",
            enables: [],
            strains: ["ball movement", "transition offense"]),
        "foul_prone": TagMeta(
            fn: foulProne, category: "liability",
            label: "Foul-Prone",
            enables: [],
            strains: ["paint deterrence", "bonus pressure"]),
    ]

    /// Tag keys that fire, in registry (category) order.
    static func fireTags(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> [String] {
        registryKeys.filter { key in
            registry[key]?.fn(players, norms) ?? false
        }
    }
}
