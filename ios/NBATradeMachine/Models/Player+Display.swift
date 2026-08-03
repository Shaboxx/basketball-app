import Foundation
extension Player {
    /// Canonical SwishScore headline. Returns theta ONLY when the doc axis is "combined" so
    /// a non-combined/legacy doc never silently shows as SwishScore. Post-cutover all uploaded
    /// docs carry headlineAxis=="combined"; old/l2 docs → nil → "—".
    var dispTotal: Double? { thetaV2?.headlineAxis == "combined" ? thetaV2?.theta : nil }
    var dispOff:   Double? { thetaV2?.off ?? latentValue?.thetaZOff }
    var dispDef:   Double? { thetaV2?.def ?? latentValue?.thetaZDef }
    var hasDisplayValue: Bool { dispOff != nil || dispDef != nil || dispTotal != nil }
    /// Signed 1-dp string, or "—".
    static func fmtVal(_ v: Double?) -> String { v.map { String(format: "%+.1f", $0) } ?? "—" }
}
