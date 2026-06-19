import Foundation

/// Swift port of scripts/lineup_value/formations.py — formation viability over the synergy magnitudes.
nonisolated enum LineupFormations {
    static let tauSpace = 3.0
    static let tauSwitch = 3.0
    static let tauRim = 4.0
    static let tauPnr = 2.0
    static let formations = ["five_out", "switch_everything", "two_big_drop", "pnr_heavy"]

    static func viable(_ mags: [String: Double], nNonshooters: Int, hasDropAnchor: Bool) -> [String: Bool] {
        let m: (String) -> Double = { mags[$0] ?? 0 }
        return [
            "five_out": m("spacing") >= tauSpace && nNonshooters == 0,
            "switch_everything": m("switchable") >= tauSwitch,
            "two_big_drop": hasDropAnchor && m("rim_protection") >= tauRim,
            "pnr_heavy": m("pnr_fit") >= tauPnr && m("spacing") >= tauSpace / 2.0,
        ]
    }
}
