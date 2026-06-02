import Foundation

/// Pure model for the post-validation Trade Confirmation surface.
///
/// `TradeConfirmation` is built once from a validated `Trade`, the league's
/// `Player` lookup, and the optional Phase 7f reports. Every aggregation
/// (asset Δ, OFF/DEF Δ vs self, vs league, trust flag union, etc.) is a
/// stored value here — the view consumes it without any further math.
/// Easy to unit-test; deterministic from inputs.
struct TradeConfirmation: Equatable {
    let teams: [TeamPackage]
    let chemistry: ChemistryReport?
    let peakTimeline: PeakTimelineForecast?

    /// Per-team incoming bundle plus its precomputed rollup metrics.
    struct TeamPackage: Equatable, Identifiable {
        let team: Team
        let incomingPlayers: [Player]
        let outgoingPlayers: [Player]
        let incomingPicks: [Pick]
        let outgoingPicks: [Pick]
        let cashIncoming: Int
        let cashOutgoing: Int
        let rollup: Rollup

        var id: String { team.teamId }
    }

    /// All rollup metrics for a single team. Every field is optional so a
    /// team with no compZ-bearing players or no prior-season latent value
    /// degrades to nil rather than zero (zero is a real, meaningful number
    /// here — e.g. a Δ of 0 means "no change").
    struct Rollup: Equatable {
        /// Sum of incoming compZ.asset.dollarsPoint minus outgoing. Nil when
        /// neither side has any compZ-bearing players.
        let assetDeltaDollars: Int?
        /// True when at least one player on either side lacked compZ — the
        /// asset Δ excludes them. UI surfaces this as a caveat line.
        let assetDeltaHadMissing: Bool

        /// Fallback for the asset cell when compZ isn't yet in Firestore.
        /// Sum of incoming salaryY1 minus outgoing salaryY1. The view shows
        /// this with a "Salary Δ" label only when `assetDeltaDollars` is nil.
        let salaryDeltaY1: Int?

        /// Roster-wide change to OFF/DEF latent value (incoming − outgoing),
        /// in points / 100. Nil when no incoming OR outgoing player carries
        /// a Tier-A/B latentValue.
        let offDeltaSelf: Double?
        let defDeltaSelf: Double?

        /// Same delta expressed in per-season z-units (league-relative).
        /// Nil when the Rev-2 z fields are absent from latentValue.
        let offDeltaLeagueZ: Double?
        let defDeltaLeagueZ: Double?

        /// Union of trust flags raised by any incoming player — surfaces to
        /// the UI as a caveat strip ("3 incoming players: stale stats").
        let trustFlagsRaised: Set<TrustFlag>

        /// Convenience: true when the team is net-positive in dollars-point,
        /// or — when compZ is missing — in raw Y1 salary.
        var isAssetWinner: Bool? {
            if let d = assetDeltaDollars { return d > 0 }
            if let d = salaryDeltaY1 { return d > 0 }
            return nil
        }
    }

    /// Stable enum mirror of CompZValuation.TrustFlags' six booleans so the
    /// union is hashable / set-able for the UI rollup.
    enum TrustFlag: String, Hashable {
        case costZero
        case modelUnreliable
        case outlierAsset
        case value2xCost
        case staleStats
        case freeAgent
    }
}

extension TradeConfirmation {
    /// Build a confirmation from a validated trade. The player lookup must
    /// contain every player referenced by `trade.movements`; missing players
    /// are skipped. Pass `chemistry` / `peakTimeline` when Phase 7f has
    /// produced them — otherwise leave nil and the view renders placeholders.
    static func build(
        trade: Trade,
        playersById: [String: Player],
        chemistry: ChemistryReport? = nil,
        peakTimeline: PeakTimelineForecast? = nil
    ) -> TradeConfirmation {
        let packages: [TeamPackage] = trade.teams.map { team in
            let inIds = trade.incomingPlayerIds(to: team.teamId)
            let outIds = trade.outgoingPlayerIds(from: team.teamId)
            let incoming = inIds.compactMap { playersById[$0] }
            let outgoing = outIds.compactMap { playersById[$0] }
            let inPicks = trade.picksIncoming(to: team.teamId).map(\.pick)
            let outPicks = trade.picksOutgoing(from: team.teamId).map(\.pick)
            let rollup = Rollup.compute(incoming: incoming, outgoing: outgoing)
            return TeamPackage(
                team: team,
                incomingPlayers: incoming,
                outgoingPlayers: outgoing,
                incomingPicks: inPicks,
                outgoingPicks: outPicks,
                cashIncoming: trade.cashSent
                    .filter { $0.key != team.teamId }
                    .values.reduce(0, +),
                cashOutgoing: trade.cash(from: team.teamId),
                rollup: rollup
            )
        }
        return TradeConfirmation(
            teams: packages,
            chemistry: chemistry,
            peakTimeline: peakTimeline
        )
    }
}

extension TradeConfirmation.Rollup {
    static func compute(incoming: [Player], outgoing: [Player]) -> Self {
        let (assetDelta, hadMissing) = assetDelta(incoming: incoming,
                                                  outgoing: outgoing)
        let salaryDelta = salaryY1Delta(incoming: incoming, outgoing: outgoing)
        let offSelf = thetaDelta(incoming: incoming, outgoing: outgoing,
                                 keyPath: \.latentValue?.thetaOff)
        let defSelf = thetaDelta(incoming: incoming, outgoing: outgoing,
                                 keyPath: \.latentValue?.thetaDef)
        let offZ = thetaDelta(incoming: incoming, outgoing: outgoing,
                              keyPath: \.latentValue?.thetaZOff)
        let defZ = thetaDelta(incoming: incoming, outgoing: outgoing,
                              keyPath: \.latentValue?.thetaZDef)
        let flags = trustFlagsRaised(by: incoming)
        return TradeConfirmation.Rollup(
            assetDeltaDollars: assetDelta,
            assetDeltaHadMissing: hadMissing,
            salaryDeltaY1: salaryDelta,
            offDeltaSelf: offSelf,
            defDeltaSelf: defSelf,
            offDeltaLeagueZ: offZ,
            defDeltaLeagueZ: defZ,
            trustFlagsRaised: flags
        )
    }

    /// Salary delta in current-year dollars (incoming − outgoing). Returns nil
    /// only when both sides are completely empty; a side with no salaries
    /// contributes 0 (treated as no contract).
    private static func salaryY1Delta(
        incoming: [Player],
        outgoing: [Player]
    ) -> Int? {
        guard !(incoming.isEmpty && outgoing.isEmpty) else { return nil }
        let sumIn = incoming.compactMap(\.salaryY1).reduce(0, +)
        let sumOut = outgoing.compactMap(\.salaryY1).reduce(0, +)
        return sumIn - sumOut
    }

    private static func assetDelta(
        incoming: [Player],
        outgoing: [Player]
    ) -> (delta: Int?, hadMissing: Bool) {
        var sumIn = 0
        var sumOut = 0
        var anyContrib = false
        var missing = false
        for p in incoming {
            if let v = p.compZ?.asset?.dollarsPoint {
                sumIn += v
                anyContrib = true
            } else {
                missing = true
            }
        }
        for p in outgoing {
            if let v = p.compZ?.asset?.dollarsPoint {
                sumOut += v
                anyContrib = true
            } else {
                missing = true
            }
        }
        return (anyContrib ? sumIn - sumOut : nil, missing)
    }

    private static func thetaDelta(
        incoming: [Player],
        outgoing: [Player],
        keyPath: KeyPath<Player, Double?>
    ) -> Double? {
        var sumIn: Double = 0
        var sumOut: Double = 0
        var anyContrib = false
        for p in incoming {
            if let v = p[keyPath: keyPath] {
                sumIn += v
                anyContrib = true
            }
        }
        for p in outgoing {
            if let v = p[keyPath: keyPath] {
                sumOut += v
                anyContrib = true
            }
        }
        return anyContrib ? sumIn - sumOut : nil
    }

    private static func trustFlagsRaised(
        by players: [Player]
    ) -> Set<TradeConfirmation.TrustFlag> {
        var out = Set<TradeConfirmation.TrustFlag>()
        for p in players {
            guard let f = p.compZ?.trust?.flags else { continue }
            if f.costZero == true        { out.insert(.costZero) }
            if f.modelUnreliable == true { out.insert(.modelUnreliable) }
            if f.outlierAsset == true    { out.insert(.outlierAsset) }
            if f.value2xCost == true     { out.insert(.value2xCost) }
            if f.staleStats == true      { out.insert(.staleStats) }
            if f.freeAgent == true       { out.insert(.freeAgent) }
        }
        return out
    }
}
