import Foundation

/// Part-1 ARCHETYPES, resolved by the Part-3 priority order — a faithful Swift
/// port of scripts/lineup_labeling/archetypes.py. Exactly one archetype is
/// assigned: `resolve` walks the predicates in priority order and returns the
/// FIRST that passes, falling back to `balanced`.
///
/// The flag `AppConfig.archetypeTaxonomyV2` selects between the V1 chain
/// (original minus run_and_gun) and the V2 chain (two_star_engine added, the
/// V2-excluded keys absent, reordered). Enabled after the committed calibration
/// run (see provenance in archetypes.py).
nonisolated enum LineupArchetypes {

    // MARK: - Tunable thresholds (mirror archetypes.py)

    nonisolated static let BIG_HEIGHT_IN = 82.0
    nonisolated static let SMALL_BALL_MAX_HEIGHT_IN = 82.0
    nonisolated static let TEAM_CENTER_TALL_IN = 83.0
    nonisolated static let POSITIONLESS_MIN_IN = 75.0
    nonisolated static let POSITIONLESS_MAX_IN = 82.0

    nonisolated static let FRONTCOURT_POS: Set<String> = ["PF", "C", "F", "F-C", "C-F", "PF-C"]
    nonisolated static let CENTER_POS: Set<String> = ["C", "C-F", "F-C", "PF-C"]
    nonisolated static let WING_POS: Set<String> = ["SF", "SG", "G-F", "F-G", "F", "SF-SG", "SG-SF", "SF-PF"]
    nonisolated static let GUARD_POS: Set<String> = ["PG", "SG", "G", "PG-SG", "SG-PG", "G-F"]
    nonisolated static let PRIMARY_HANDLER_POS: Set<String> = ["PG", "G", "PG-SG", "SG-PG"]

    nonisolated static let SHOOTER_THREEPAR_PCTL = 0.55
    nonisolated static let SHOOTER_FG3_PCTL = 0.45
    nonisolated static let NON_SHOOTER_THREEPAR_PCTL = 0.20

    nonisolated static let BULLY_ORB_PCTL = 0.60
    nonisolated static let BULLY_WEIGHT_PCTL = 0.60

    nonisolated static let HELIO_LOAD_PCTL = 0.90
    nonisolated static let HELIO_CREATION_PCTL = 0.75
    nonisolated static let HELIO_OTHERS_LOAD_PCTL = 0.60
    nonisolated static let ISO_LOAD_PCTL = 0.80
    nonisolated static let ISO_TEAM_CREATION_PCTL = 0.45
    nonisolated static let ISO_MAX_SECONDARY_CREATORS = 1
    nonisolated static let SECONDARY_CREATOR_PCTL = 0.60
    nonisolated static let TWO_PG_MIN_HANDLERS = 2
    nonisolated static let HANDLER_LOAD_PCTL = 0.60

    nonisolated static let POSITIONLESS_MIN_WINGS = 3
    nonisolated static let POSITIONLESS_VERSATILITY_PCTL = 0.55
    nonisolated static let RUN_GUN_AGE_MAX = 25.5

    nonisolated static let DEATH_MIN_IMPACT = 0.0
    nonisolated static let BENCH_RESERVE_BASELINE = -1.5

    // --- V2 taxonomy pins (spec G3) ---
    nonisolated static let HANDLER_LOAD_PCTL_V2_CREDIT = 0.10
    nonisolated static let TWO_STAR_LOAD_PCTL = 0.90
    nonisolated static let TWO_STAR_COSTAR_PCTL = 0.75
    nonisolated static let BULLY_WEIGHT_PCTL_V2 = 0.55
    nonisolated static let BULLY_FC_HEIGHT_MIN = 80.0

    private typealias N = LineupNorms

    // MARK: - Small role/feature helpers

    private nonisolated static func pos(_ player: LineupFeatures?) -> String {
        player?.pos ?? ""
    }

    private nonisolated static func isIn(_ p: String, _ group: Set<String>) -> Bool {
        group.contains(p)
    }

    private nonisolated static func heights(_ players: [LineupFeatures?]) -> [Double] {
        players.compactMap { N.feat($0, "height_in") }
    }

    private nonisolated static func isShooter(_ player: LineupFeatures?, _ norms: LeagueNorms) -> Bool {
        let tp = N.pctl(player, "three_par", norms)
        let acc = N.pctl(player, "fg3_pct", norms)
        return (tp != nil && tp! >= SHOOTER_THREEPAR_PCTL)
            && (acc == nil || acc! >= SHOOTER_FG3_PCTL)
    }

    private nonisolated static func isNonShooter(_ player: LineupFeatures?, _ norms: LeagueNorms) -> Bool {
        let tp = N.pctl(player, "three_par", norms)
        return tp != nil && tp! <= NON_SHOOTER_THREEPAR_PCTL
    }

    private nonisolated static func secondaryCreators(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                                          excludeIdx: Int? = nil) -> Int {
        var n = 0
        for (i, p) in players.enumerated() {
            if i == excludeIdx { continue }
            if let c = N.pctl(p, "box_creation", norms), c >= SECONDARY_CREATOR_PCTL { n += 1 }
        }
        return n
    }

    private nonisolated static func primaryHandlers(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                                                    v2: Bool) -> Int {
        let credit = v2 ? HANDLER_LOAD_PCTL_V2_CREDIT : 0.2
        var n = 0
        for p in players {
            let position = pos(p)
            let load = N.pctl(p, "load", norms)
            if isIn(position, PRIMARY_HANDLER_POS) && (load == nil || load! >= HANDLER_LOAD_PCTL - credit) { n += 1 }
            else if let load, load >= HANDLER_LOAD_PCTL, isIn(position, GUARD_POS) { n += 1 }
        }
        return n
    }

    /// Tallest player record (mirrors max(players, key=height_in or 0)). Ties
    /// resolve to the first occurrence, matching Python's `max`.
    private nonisolated static func tallest(_ players: [LineupFeatures?]) -> LineupFeatures? {
        var best: LineupFeatures?
        var bestH = -Double.infinity
        for p in players {
            let h = N.feat(p, "height_in") ?? 0
            if h > bestH {
                bestH = h
                best = p
            }
        }
        return best
    }

    // MARK: - Group 1: size + spacing

    nonisolated static func deathLineup(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                            _ tags: [String], _ impacts: [Double?]?) -> Bool {
        guard let impacts, impacts.count == players.count, !players.isEmpty else { return false }
        if impacts.contains(where: { $0 == nil }) { return false }
        if !impacts.allSatisfy({ ($0 ?? 0) > DEATH_MIN_IMPACT }) { return false }
        let hs = heights(players)
        if let mx = hs.max(), mx > SMALL_BALL_MAX_HEIGHT_IN { return false }
        if !tags.contains("switchable") { return false }
        let tall = tallest(players)
        let ver = N.pctl(tall, "versatility", norms)
        // Python precedence: (A and not B) or (A and (ver>=t))
        let isForwardFive =
            (isIn(pos(tall), FRONTCOURT_POS) && !isIn(pos(tall), CENTER_POS))
            || (isIn(pos(tall), FRONTCOURT_POS) && (ver ?? 0) >= POSITIONLESS_VERSATILITY_PCTL)
        return isForwardFive && (ver ?? 0) >= POSITIONLESS_VERSATILITY_PCTL
    }

    nonisolated static func smallBall(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                          _ tags: [String], _ impacts: [Double?]?) -> Bool {
        let hs = heights(players)
        guard !hs.isEmpty else { return false }
        if hs.max()! > SMALL_BALL_MAX_HEIGHT_IN { return false }
        if players.contains(where: { isIn(pos($0), CENTER_POS) }) { return false }
        if hs.max()! >= TEAM_CENTER_TALL_IN { return false }
        let tall = tallest(players)
        if !(isIn(pos(tall), FRONTCOURT_POS) && !isIn(pos(tall), CENTER_POS)) { return false }
        return tags.contains("spread_high_spacing") || tags.contains("movement_shooting")
    }

    nonisolated static func twinTowers(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                           _ tags: [String], _ impacts: [Double?]?) -> Bool {
        var bigs = 0
        for p in players {
            if (N.feat(p, "height_in") ?? 0) >= BIG_HEIGHT_IN && isIn(pos(p), FRONTCOURT_POS) {
                bigs += 1
            }
        }
        return bigs >= 2
    }

    nonisolated static func fiveOut(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                        _ tags: [String], _ impacts: [Double?]?) -> Bool {
        guard !players.isEmpty else { return false }
        if players.contains(where: { isNonShooter($0, norms) }) { return false }
        return players.allSatisfy { isShooter($0, norms) }
    }

    nonisolated static func bullyBall(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                          _ tags: [String], _ impacts: [Double?]?) -> Bool {
        guard let weight = N.meanPctl(players, "weight_lb", norms), weight >= BULLY_WEIGHT_PCTL
        else { return false }
        guard let orb = N.meanPctl(players, "orb_pct", norms), orb >= BULLY_ORB_PCTL
        else { return false }
        let frontcourt = players.reduce(0) { $0 + (isIn(pos($1), FRONTCOURT_POS) ? 1 : 0) }
        return frontcourt >= 3
    }

    // MARK: - Group 2: ball-handling

    nonisolated static func heliocentric(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                             _ tags: [String], _ impacts: [Double?]?) -> Bool {
        let loads: [(Int, Double?)] = players.enumerated().map { ($0.offset, N.pctl($0.element, "load", norms)) }
        let present: [(Int, Double)] = loads.compactMap { idx, v in v.map { (idx, $0) } }
        guard !present.isEmpty else { return false }
        // max by value; ties -> first (matches Python max over enumerated list).
        var topIdx = present[0].0
        var topV = present[0].1
        for (i, v) in present where v > topV { topV = v; topIdx = i }
        if topV < HELIO_LOAD_PCTL { return false }
        guard let creation = N.pctl(players[topIdx], "box_creation", norms),
              creation >= HELIO_CREATION_PCTL else { return false }
        let others = present.filter { $0.0 != topIdx }.map { $0.1 }
        return others.allSatisfy { $0 < HELIO_OTHERS_LOAD_PCTL }
    }

    nonisolated static func isoHero(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                        _ tags: [String], _ impacts: [Double?]?) -> Bool {
        guard let top = N.maxPctl(players, "load", norms), top >= ISO_LOAD_PCTL else { return false }
        guard let teamCreation = N.meanPctl(players, "box_creation", norms),
              teamCreation <= ISO_TEAM_CREATION_PCTL else { return false }
        return secondaryCreators(players, norms) <= ISO_MAX_SECONDARY_CREATORS
    }

    nonisolated static func twoPG(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                      _ tags: [String], _ impacts: [Double?]?, v2: Bool) -> Bool {
        primaryHandlers(players, norms, v2: v2) >= TWO_PG_MIN_HANDLERS
    }

    // MARK: - V2 predicates

    nonisolated static func twoStarEngine(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                                          _ tags: [String], _ impacts: [Double?]?) -> Bool {
        let loads: [(Int, Double?)] = players.enumerated().map { ($0.offset, N.pctl($0.element, "load", norms)) }
        let present: [(Int, Double)] = loads.compactMap { idx, v in v.map { (idx, $0) } }
        guard !present.isEmpty else { return false }
        var topIdx = present[0].0, topV = present[0].1
        for (i, v) in present where v > topV { topV = v; topIdx = i }
        if topV < TWO_STAR_LOAD_PCTL { return false }
        guard let creation = N.pctl(players[topIdx], "box_creation", norms),
              creation >= HELIO_CREATION_PCTL else { return false }
        let others = present.filter { $0.0 != topIdx }.map { $0.1 }
        return others.contains { $0 >= TWO_STAR_COSTAR_PCTL }
    }

    nonisolated static func bullyBallV2(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                                        _ tags: [String], _ impacts: [Double?]?) -> Bool {
        guard let weight = N.meanPctl(players, "weight_lb", norms), weight >= BULLY_WEIGHT_PCTL_V2
        else { return false }
        var fc = 0
        for p in players {
            let position = pos(p)
            let h = N.feat(p, "height_in")
            let isFC = isIn(position, FRONTCOURT_POS) || (position == "SF" && (h ?? 0) >= BULLY_FC_HEIGHT_MIN)
            guard isFC, let hh = h, hh >= BULLY_FC_HEIGHT_MIN else { continue }
            guard let orb = N.pctl(p, "orb_pct", norms), orb >= BULLY_ORB_PCTL else { continue }
            fc += 1
        }
        return fc >= 2
    }

    // MARK: - Group 3: defense / tempo

    nonisolated static func positionless(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                             _ tags: [String], _ impacts: [Double?]?) -> Bool {
        let hs = heights(players)
        if hs.count < players.count || hs.isEmpty { return false }
        if !hs.allSatisfy({ POSITIONLESS_MIN_IN <= $0 && $0 <= POSITIONLESS_MAX_IN }) { return false }
        let wings = players.reduce(0) { acc, p in
            acc + ((isIn(pos(p), WING_POS) || isIn(pos(p), FRONTCOURT_POS)) ? 1 : 0)
        }
        if wings < POSITIONLESS_MIN_WINGS { return false }
        guard let ver = N.meanPctl(players, "versatility", norms) else { return false }
        return ver >= POSITIONLESS_VERSATILITY_PCTL
    }

    // runAndGun REMOVED OUTRIGHT (spec 2.1 A / G3-A5): input-independent shadow-dead
    // (strict subset of two_pg at strictly lower priority -> never resolvable for ANY input).

    // MARK: - Group 4: bench

    nonisolated static func benchMob(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                         _ tags: [String], _ impacts: [Double?]?, _ tier: String) -> Bool {
        if tier != "bench" { return false }
        guard let impacts, !impacts.isEmpty else { return false }
        let present = impacts.compactMap { $0 }
        guard !present.isEmpty else { return false }
        return (present.reduce(0, +) / Double(present.count)) > BENCH_RESERVE_BASELINE
    }

    // MARK: - Resolver (Part-3 priority)

    // V1 maps: byte-identical to today MINUS run_and_gun (removed outright, spec 2.1 A).
    nonisolated static let archetypeStrainsV1: [String: [String]] = [
        "death_lineup": ["interior rebounding vs. size"],
        "small_ball": ["interior rebounding vs. size", "rim protection vs. size"],
        "twin_towers": ["floor spacing", "perimeter switchability"],
        "five_out": ["interior rebounding vs. size"],
        "bully_ball": ["floor spacing", "transition defense"],
        "heliocentric": ["off-ball rhythm", "resilience if the hub sits"],
        "iso_hero": ["ball movement", "open shots from passing"],
        "two_pg": ["size on the wing", "defensive rebounding"],
        "positionless": [],
        "bench_mob": [],
        "balanced": [],
    ]
    nonisolated static let archetypeLabelsV1: [String: String] = [
        "death_lineup": "Death Lineup",
        "small_ball": "Small Ball",
        "twin_towers": "Twin Towers",
        "five_out": "Five-Out",
        "bully_ball": "Bully Ball",
        "heliocentric": "Heliocentric",
        "iso_hero": "Iso-Heavy",
        "two_pg": "Two Point Guards",
        "positionless": "Positionless",
        "bench_mob": "Bench Mob",
        "balanced": "Balanced",
    ]

    // V2 maps: display renames (keys stable) + the new two_star_engine; OMIT the V2-excluded keys.
    nonisolated static let archetypeStrainsV2: [String: [String]] = [
        "small_ball": ["interior rebounding vs. size", "rim protection vs. size"],
        "twin_towers": ["floor spacing", "perimeter switchability"],
        "bully_ball": ["floor spacing", "transition defense"],
        "heliocentric": ["off-ball rhythm", "resilience if the hub sits"],
        "two_star_engine": ["off-ball rhythm", "resilience if the hub sits"],
        "iso_hero": ["ball movement", "open shots from passing"],
        "two_pg": ["size on the wing", "defensive rebounding"],
        "positionless": [],
        "balanced": [],
    ]
    nonisolated static let archetypeLabelsV2: [String: String] = [
        "small_ball": "Small Ball",
        "twin_towers": "Twin Towers",
        "bully_ball": "Bully Ball",
        "heliocentric": "Heliocentric",
        "two_star_engine": "Two-Star Engine",
        "iso_hero": "Iso-Heavy",
        "two_pg": "Dual Initiators",
        "positionless": "Positionless",
        "balanced": "Conventional",
    ]

    // Back-compat aliases: enabled after the committed calibration run (see provenance);
    // existing readers use the V1 maps.
    nonisolated static let archetypeStrains = archetypeStrainsV1
    nonisolated static let archetypeLabels = archetypeLabelsV1

    private typealias Predicate = @Sendable ([LineupFeatures?], LeagueNorms, [String], [Double?]?) -> Bool

    /// V1 priority list (original minus run_and_gun; bench_mob resolved separately).
    private nonisolated static let priorityV1: [(String, Predicate)] = [
        ("death_lineup", deathLineup),
        ("small_ball", smallBall),
        ("twin_towers", twinTowers),
        ("five_out", fiveOut),
        ("bully_ball", bullyBall),
        ("heliocentric", heliocentric),
        ("iso_hero", isoHero),
        ("two_pg", { twoPG($0, $1, $2, $3, v2: false) }),
        ("positionless", positionless),
    ]

    /// V2 priority list: two_star_engine added, bully repaired, reordered,
    /// death_lineup/five_out/bench_mob absent by construction.
    private nonisolated static let priorityV2: [(String, Predicate)] = [
        ("small_ball", smallBall),
        ("twin_towers", twinTowers),
        ("heliocentric", heliocentric),
        ("iso_hero", isoHero),
        ("two_star_engine", twoStarEngine),
        ("bully_ball", bullyBallV2),
        ("positionless", positionless),
        ("two_pg", { twoPG($0, $1, $2, $3, v2: true) }),
    ]

    /// Test/introspection helper: the priority key list for the given taxonomy.
    nonisolated static func priorityKeys(v2: Bool) -> [String] {
        (v2 ? priorityV2 : priorityV1).map { $0.0 }
    }

    /// Production resolve reads the flag; the v2: overload is for tests (no static-let toggle).
    nonisolated static func resolve(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                        tags: [String], impacts: [Double?]? = nil,
                        tier: String = "starters") -> String {
        resolve(players, norms, tags: tags, impacts: impacts, tier: tier,
                v2: AppConfig.archetypeTaxonomyV2)
    }

    nonisolated static func resolve(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                        tags: [String], impacts: [Double?]?, tier: String, v2: Bool) -> String {
        if v2 {
            for (name, fn) in priorityV2 where fn(players, norms, tags, impacts) { return name }
            return "balanced"
        }
        for (name, fn) in priorityV1 where fn(players, norms, tags, impacts) { return name }
        if benchMob(players, norms, tags, impacts, tier) { return "bench_mob" }
        return "balanced"
    }
}
