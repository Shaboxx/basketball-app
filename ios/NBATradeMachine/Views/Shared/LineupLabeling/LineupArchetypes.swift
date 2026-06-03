import Foundation

/// Part-1 ARCHETYPES, resolved by the Part-3 priority order — a faithful Swift
/// port of scripts/lineup_labeling/archetypes.py. Exactly one archetype is
/// assigned: `resolve` walks the predicates in priority order and returns the
/// FIRST that passes, falling back to `balanced`.
///
/// Priority groups (highest first):
///   1. death_lineup -> small_ball -> twin_towers -> five_out -> bully_ball
///   2. heliocentric -> iso_hero -> two_pg
///   3. positionless -> run_and_gun
///   4. bench_mob (reserve tiers only, above the reserve impact baseline)
///   5. balanced (fallback)
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

    private nonisolated static func primaryHandlers(_ players: [LineupFeatures?], _ norms: LeagueNorms) -> Int {
        var n = 0
        for p in players {
            let position = pos(p)
            let load = N.pctl(p, "load", norms)
            if isIn(position, PRIMARY_HANDLER_POS)
                && (load == nil || load! >= HANDLER_LOAD_PCTL - 0.2) {
                n += 1
            } else if let load, load >= HANDLER_LOAD_PCTL, isIn(position, GUARD_POS) {
                n += 1
            }
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
                      _ tags: [String], _ impacts: [Double?]?) -> Bool {
        primaryHandlers(players, norms) >= TWO_PG_MIN_HANDLERS
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

    nonisolated static func runAndGun(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                          _ tags: [String], _ impacts: [Double?]?) -> Bool {
        guard let age = N.avgAge(players), age < RUN_GUN_AGE_MAX else { return false }
        return primaryHandlers(players, norms) >= 2
    }

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

    /// Strains attached to each archetype identity (independent of tags).
    nonisolated static let archetypeStrains: [String: [String]] = [
        "death_lineup": ["interior rebounding vs. size"],
        "small_ball": ["interior rebounding vs. size", "rim protection vs. size"],
        "twin_towers": ["floor spacing", "perimeter switchability"],
        "five_out": ["interior rebounding vs. size"],
        "bully_ball": ["floor spacing", "transition defense"],
        "heliocentric": ["off-ball rhythm", "resilience if the hub sits"],
        "iso_hero": ["ball movement", "open shots from passing"],
        "two_pg": ["size on the wing", "defensive rebounding"],
        "positionless": [],
        "run_and_gun": ["half-court execution", "transition defense"],
        "bench_mob": [],
        "balanced": [],
    ]

    nonisolated static let archetypeLabels: [String: String] = [
        "death_lineup": "Death Lineup",
        "small_ball": "Small Ball",
        "twin_towers": "Twin Towers",
        "five_out": "Five-Out",
        "bully_ball": "Bully Ball",
        "heliocentric": "Heliocentric",
        "iso_hero": "Iso-Heavy",
        "two_pg": "Two Point Guards",
        "positionless": "Positionless",
        "run_and_gun": "Run-and-Gun",
        "bench_mob": "Bench Mob",
        "balanced": "Balanced",
    ]

    private typealias Predicate = @Sendable ([LineupFeatures?], LeagueNorms, [String], [Double?]?) -> Bool

    /// (name, predicate) in strict priority order. bench_mob is handled
    /// separately because it needs the tier argument.
    private nonisolated static let priority: [(String, Predicate)] = [
        ("death_lineup", deathLineup),
        ("small_ball", smallBall),
        ("twin_towers", twinTowers),
        ("five_out", fiveOut),
        ("bully_ball", bullyBall),
        ("heliocentric", heliocentric),
        ("iso_hero", isoHero),
        ("two_pg", twoPG),
        ("positionless", positionless),
        ("run_and_gun", runAndGun),
    ]

    /// Return the single archetype name (first passing predicate, by priority).
    nonisolated static func resolve(_ players: [LineupFeatures?], _ norms: LeagueNorms,
                        tags: [String], impacts: [Double?]? = nil,
                        tier: String = "starters") -> String {
        for (name, fn) in priority {
            if fn(players, norms, tags, impacts) { return name }
        }
        if benchMob(players, norms, tags, impacts, tier) { return "bench_mob" }
        return "balanced"
    }
}
