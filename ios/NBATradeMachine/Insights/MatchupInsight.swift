import Foundation

/// One hedged, stat-cited scouting insight: a headline that signals uncertainty and an
/// `evidence` statline the user can see the reasoning from. Never commands. The generator
/// lives in an extension on the struct (there is NO enum of the same name).
nonisolated struct MatchupInsight: Equatable, Identifiable {
    let headline: String     // hedged ("Tends to give up efficient looks to forwards")
    let evidence: String     // the quoted statline ("0.57 pts/poss allowed vs F over 2,781 poss")
    let isSmallSample: Bool
    var id: String { headline }
}

extension MatchupInsight {
    static let minPoss: Double = 200

    /// Defensive scouting insights from a Matchup: by-position vulnerability + overall
    /// efficiency allowed, framed with uncertainty phrasing + the supporting statline.
    /// Descriptive/hedged, never prescriptive. Returns at least one line when any
    /// defensive data exists (never leaves the panel blank).
    static func defensiveInsights(from m: Matchup) -> [MatchupInsight] {
        var out: [MatchupInsight] = []
        let posName = ["G": "guards", "F": "forwards", "C": "centers"]
        // Rank positions this player defends by opponent pts/poss (higher = more exploited).
        let ranked = m.byPosition
            .compactMap { key, s in s.ptsPerPoss.map { (key, s, $0) } }
            .sorted { $0.2 > $1.2 }
        if let (pos, s, ppp) = ranked.first {
            let noun = posName[pos] ?? pos
            let small = s.partialPoss < minPoss
            let hedge = small ? "On a small sample so far, may give up" : "Tends to give up"
            out.append(MatchupInsight(
                headline: "\(hedge) more efficient looks to \(noun)",
                evidence: String(format: "%.2f pts/poss allowed vs %@ over %@ poss", ppp, pos, poss(s.partialPoss))
                    + (small ? " (small sample)" : ""),
                isSmallSample: small))
        }
        // Overall efficiency-allowed framing, if present.
        if let efg = m.defense.oppEfgAllowed {
            let small = m.defense.totalPossGuarded < minPoss
            let verb = efg < 0.50 ? "suggests solid" : "suggests below-average"
            out.append(MatchupInsight(
                headline: "Overall, the data \(verb) shot defense so far",
                evidence: String(format: "%.1f%% opponent eFG allowed over %@ poss", efg * 100, poss(m.defense.totalPossGuarded))
                    + (small ? " (small sample)" : ""),
                isSmallSample: small))
        }
        // Fallback: matchup data exists but no rate is populated yet — never blank.
        if out.isEmpty && m.defense.totalPossGuarded > 0 {
            out.append(MatchupInsight(
                headline: "Not enough matchup detail for position reads yet",
                evidence: String(format: "%@ possessions guarded so far", poss(m.defense.totalPossGuarded)),
                isSmallSample: true))
        }
        return out
    }

    private static func poss(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n >= 1000 ? "\(n / 1000),\(String(format: "%03d", n % 1000))" : "\(n)"
    }
}
