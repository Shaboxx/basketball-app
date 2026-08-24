import Foundation
extension Player {
    /// Canonical SwishScore headline = the outcome-calibrated Model-Θ⊕Model-B blend from
    /// the thetaBoard pipeline. Docs without thetaBoard → nil → "—".
    var dispTotal: Double? { thetaBoard?.blend }
    var dispOff:   Double? { thetaBoard?.off ?? latentValue?.thetaZOff }
    var dispDef:   Double? { thetaBoard?.def ?? latentValue?.thetaZDef }
    var hasDisplayValue: Bool { dispOff != nil || dispDef != nil || dispTotal != nil }
    /// Signed 1-dp string, or "—".
    static func fmtVal(_ v: Double?) -> String { v.map { String(format: "%+.1f", $0) } ?? "—" }
}
