import Foundation

/// League-relative aggregate helpers over a five-man lineup — a faithful Swift
/// port of scripts/lineup_labeling/norms.py (the single-player lookups and the
/// aggregate helpers over the 5 players).
///
/// A "player" here is a `LineupFeatures?` (one player's feature record). Any
/// feature may be nil; helpers skip missing players (the "abstain" rule) rather
/// than guessing. The two primitives (`percentile`, `zscore`) live on
/// `LeagueNorms`; these helpers build the lineup-level aggregates on top.
enum LineupNorms {

    // MARK: - Single-player lookups (mirror norms.feat / pctl / z)

    /// Raw value of `name` for a player, or nil if absent.
    static func feat(_ player: LineupFeatures?, _ name: String) -> Double? {
        player?.value(name)
    }

    /// League percentile (0..1) of a player's `name` value. nil when the player
    /// lacks the feature or the norms doc has no distribution for it.
    static func pctl(_ player: LineupFeatures?, _ name: String,
                     _ norms: LeagueNorms) -> Double? {
        guard let value = player?.value(name) else { return nil }
        return norms.percentile(value, feature: name)
    }

    /// League z-score of a player's `name` value (nil if missing).
    static func z(_ player: LineupFeatures?, _ name: String,
                  _ norms: LeagueNorms) -> Double? {
        guard let value = player?.value(name) else { return nil }
        return norms.zscore(value, feature: name)
    }

    // MARK: - Aggregate helpers over the 5 players

    private static func present(_ values: [Double?]) -> [Double] {
        values.compactMap { $0 }
    }

    /// Mean of the lineup's percentiles for `name` (skipping abstainers).
    static func meanPctl(_ players: [LineupFeatures?], _ name: String,
                         _ norms: LeagueNorms) -> Double? {
        let vals = present(players.map { pctl($0, name, norms) })
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Mean of the lineup's z-scores for `name` (skipping abstainers).
    static func meanZ(_ players: [LineupFeatures?], _ name: String,
                      _ norms: LeagueNorms) -> Double? {
        let vals = present(players.map { z($0, name, norms) })
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Mean of a raw feature over the lineup (skipping missing).
    static func meanRaw(_ players: [LineupFeatures?], _ name: String) -> Double? {
        let vals = present(players.map { feat($0, name) })
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// How many players have percentile(`name`) >= `p`. Abstainers don't count.
    static func countAbove(_ players: [LineupFeatures?], _ name: String,
                           _ p: Double, _ norms: LeagueNorms) -> Int {
        players.reduce(0) { acc, pl in
            acc + ((pctl(pl, name, norms) ?? -1.0) >= p ? 1 : 0)
        }
    }

    /// How many players have percentile(`name`) <= `p`. Abstainers don't count.
    static func countBelow(_ players: [LineupFeatures?], _ name: String,
                           _ p: Double, _ norms: LeagueNorms) -> Int {
        players.reduce(0) { acc, pl in
            if let pq = pctl(pl, name, norms), pq <= p { return acc + 1 }
            return acc
        }
    }

    /// How many players have raw `name` < `threshold`. Missing don't count.
    static func countRawBelow(_ players: [LineupFeatures?], _ name: String,
                              _ threshold: Double) -> Int {
        players.reduce(0) { acc, pl in
            if let v = feat(pl, name), v < threshold { return acc + 1 }
            return acc
        }
    }

    /// How many players have raw `name` >= `threshold`. Missing don't count.
    static func countRawAtLeast(_ players: [LineupFeatures?], _ name: String,
                                _ threshold: Double) -> Int {
        players.reduce(0) { acc, pl in
            if let v = feat(pl, name), v >= threshold { return acc + 1 }
            return acc
        }
    }

    /// Highest percentile for `name` across the lineup (nil if all abstain).
    static func maxPctl(_ players: [LineupFeatures?], _ name: String,
                        _ norms: LeagueNorms) -> Double? {
        present(players.map { pctl($0, name, norms) }).max()
    }

    /// Lowest percentile for `name` across the lineup (nil if all abstain).
    static func minPctl(_ players: [LineupFeatures?], _ name: String,
                        _ norms: LeagueNorms) -> Double? {
        present(players.map { pctl($0, name, norms) }).min()
    }

    /// All present percentiles for `name`, descending.
    static func sortedPctls(_ players: [LineupFeatures?], _ name: String,
                            _ norms: LeagueNorms) -> [Double] {
        present(players.map { pctl($0, name, norms) }).sorted(by: >)
    }

    /// Second-highest percentile for `name` (nil if < 2 players have it).
    static func secondPctl(_ players: [LineupFeatures?], _ name: String,
                           _ norms: LeagueNorms) -> Double? {
        let s = sortedPctls(players, name, norms)
        return s.count >= 2 ? s[1] : nil
    }

    /// Herfindahl-Hirschman concentration index of a list of loads, in (0, 1].
    /// HHI = sum(share_i^2) over the present, positive loads. 1/n = perfectly
    /// even (low), 1.0 = one player carries everything (high). nil when no
    /// usable load is present or the total is non-positive.
    static func loadHHI(_ loads: [Double?]) -> Double? {
        let vals = loads.compactMap { $0 }.filter { $0 > 0 }
        let total = vals.reduce(0, +)
        guard !vals.isEmpty, total > 0 else { return nil }
        let shares = vals.map { $0 / total }
        return shares.reduce(0) { $0 + $1 * $1 }
    }

    /// Mean age over the lineup (nil if no ages present).
    static func avgAge(_ players: [LineupFeatures?]) -> Double? {
        meanRaw(players, "age")
    }
}
