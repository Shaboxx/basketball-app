import Foundation
extension Player {
    /// Displayed value metric: prefer v2, fall back to legacy theta_z.
    var dispTotal: Double? { thetaV2?.l2Signed ?? latentValue?.thetaZ }
    var dispOff:   Double? { thetaV2?.off ?? latentValue?.thetaZOff }
    var dispDef:   Double? { thetaV2?.def ?? latentValue?.thetaZDef }
    var hasDisplayValue: Bool { dispOff != nil || dispDef != nil || dispTotal != nil }
    /// Signed 1-dp string, or "—".
    static func fmtVal(_ v: Double?) -> String { v.map { String(format: "%+.1f", $0) } ?? "—" }
}
