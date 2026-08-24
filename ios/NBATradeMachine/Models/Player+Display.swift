import Foundation
extension Player {
    /// Canonical SwishScore headline = the outcome-calibrated Model-Θ⊕Model-B blend from
    /// the thetaBoard pipeline. Docs without thetaBoard → nil → "—".
    var dispTotal: Double? { thetaBoard?.blend }
    var dispOff:   Double? { thetaBoard?.off ?? latentValue?.thetaZOff }
    var dispDef:   Double? { thetaBoard?.def ?? latentValue?.thetaZDef }
    var hasDisplayValue: Bool { dispOff != nil || dispDef != nil || dispTotal != nil }
    /// θ-total for the numeric lineup/chemistry engines, gated to a minimum on-court
    /// sample. Sub-1000-possession board totals are unshrunk NN estimates and can
    /// explode (observed ±13 on <300 poss); engines treat gated players as missing
    /// (nil) rather than trusting a wild point estimate. Display surfaces are NOT
    /// gated — they show the blend, which is calibrated/shrunk.
    nonisolated var engineImpact: Double? {
        guard let tb = thetaBoard, let total = tb.total else { return nil }
        if let poss = tb.poss, poss < 1000 { return nil }
        return total
    }
    /// Signed 1-dp string, or "—".
    static func fmtVal(_ v: Double?) -> String { v.map { String(format: "%+.1f", $0) } ?? "—" }
}
