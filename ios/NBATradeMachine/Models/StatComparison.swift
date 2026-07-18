import Foundation

nonisolated enum StatCell: Equatable { case up, down, neutral, injury, dash }
nonisolated enum StatDirection: Equatable { case higherBetter, lowerBetter }

/// A box-score line that the comparison engine can read from any context.
/// All requirements are `nonisolated` so the pure `StatComparison` enum can
/// call them without a MainActor hop.
protocol BoxLine {
    nonisolated var pts: Int? { get }
    nonisolated var fga: Int? { get }
    nonisolated var fta: Int? { get }
    nonisolated var fgm: Int? { get }
    nonisolated var fg3m: Int? { get }
    nonisolated var ftm: Int? { get }
    nonisolated var oreb: Int? { get }
    nonisolated var dreb: Int? { get }
    nonisolated var stl: Int? { get }
    nonisolated var ast: Int? { get }
    nonisolated var blk: Int? { get }
    nonisolated var pf: Int? { get }
    nonisolated var tov: Int? { get }
}

extension GameLine: BoxLine {}

nonisolated enum StatComparison {
    static let meaningfulDeltaPct = 0.10
    static let minComparableGamesPlayed = 25
    static let injuryDaysForYellow = 20
    static let zeroBaselineEps = 1e-9

    static func percentDelta(_ dir: StatDirection, this: Double?, prev: Double?) -> StatCell {
        guard let t = this else { return .dash }
        guard let p = prev else { return .neutral }
        let betterUp = dir == .higherBetter
        if abs(p) < zeroBaselineEps {
            if abs(t) < zeroBaselineEps { return .neutral }
            let improved = t > 0
            return (improved == betterUp) ? .up : .down
        }
        var d = (t - p) / abs(p)
        if !betterUp { d = -d }                 // invert so positive d == improvement
        if d >= meaningfulDeltaPct { return .up }
        if d <= -meaningfulDeltaPct { return .down }
        return .neutral
    }

    static func seasonCell(_ dir: StatDirection, this: Double?, prev: Double?,
                           thisComparable: Bool, prevComparable: Bool) -> StatCell {
        if !thisComparable || !prevComparable { return .injury }
        return percentDelta(dir, this: this, prev: prev)
    }

    static func isSeasonComparable(gp: Int?, injuryWindowDays: Int?) -> Bool {
        (gp ?? 0) >= minComparableGamesPlayed && (injuryWindowDays ?? 0) < injuryDaysForYellow
    }

    static func gameCell(_ dir: StatDirection, game: Double?, seasonAvg: Double?) -> StatCell {
        percentDelta(dir, this: game, prev: seasonAvg)
    }

    struct Adv { let ts, efg, gmsc: Double? }

    static func advancedPerGame(_ g: any BoxLine) -> Adv? {
        func d(_ v: Int?) -> Double? { v.map(Double.init) }
        let ts: Double? = statZip3(d(g.pts), d(g.fga), d(g.fta)).flatMap { p, fga, fta in
            let denom = 2 * (fga + 0.44 * fta)
            return denom == 0 ? nil : p / denom
        }
        let efg: Double? = statZip3(d(g.fgm), d(g.fg3m), d(g.fga)).flatMap { fgm, fg3m, fga in
            fga == 0 ? nil : (fgm + 0.5 * fg3m) / fga
        }
        let gmsc = gameScore(g)
        return Adv(ts: ts, efg: efg, gmsc: gmsc)
    }

    static func gameScore(_ g: any BoxLine) -> Double? {
        let vals: [Int?] = [g.pts, g.fgm, g.fga, g.ftm, g.fta, g.oreb, g.dreb,
                            g.stl, g.ast, g.blk, g.pf, g.tov]
        guard vals.allSatisfy({ $0 != nil }) else { return nil }
        let f = vals.map { Double($0!) }
        // pts,fgm,fga,ftm,fta,oreb,dreb,stl,ast,blk,pf,tov
        return f[0] + 0.4*f[1] - 0.7*f[2] - 0.4*(f[4]-f[3]) + 0.7*f[5] + 0.3*f[6]
             + f[7] + 0.7*f[8] + 0.7*f[9] - 0.4*f[10] - f[11]
    }

    /// Season-average advanced header: TS%/eFG% from SUMMED components (matches the
    /// stored season value), GmSc as the mean of per-game Game Scores (resolution 4).
    struct AdvHeader { let ts, efg, gmsc: Double? }

    static func advancedSeasonHeader(_ games: [any BoxLine]) -> AdvHeader {
        func sum(_ kp: (any BoxLine) -> Int?) -> Double? {
            let vs = games.compactMap(kp)
            return vs.isEmpty ? nil : Double(vs.reduce(0, +))
        }
        let pts = sum { $0.pts }, fga = sum { $0.fga }, fta = sum { $0.fta }
        let fgm = sum { $0.fgm }, fg3m = sum { $0.fg3m }
        let ts: Double? = {
            guard let p = pts, let a = fga, let t = fta, (a + 0.44 * t) > 0
            else { return nil }
            return p / (2 * (a + 0.44 * t))
        }()
        let efg: Double? = {
            guard let m = fgm, let t3 = fg3m, let a = fga, a > 0
            else { return nil }
            return (m + 0.5 * t3) / a
        }()
        let scores = games.compactMap { gameScore($0) }
        let gmsc = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        return AdvHeader(ts: ts, efg: efg, gmsc: gmsc)
    }
}

private nonisolated func statZip3<A, B, C>(_ a: A?, _ b: B?, _ c: C?) -> (A, B, C)? {
    guard let a, let b, let c else { return nil }
    return (a, b, c)
}
