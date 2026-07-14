import Foundation
import CoreGraphics

/// The four-state zone-label tap cycle for the offensive shot map (sub-project B).
/// Pure and `nonisolated`: owned as transient `@State` by `MatchupCourtSection` and passed
/// into `HalfCourtView` by value; the view advances it only through its tap callback.
/// Cycle (BINDING, adjudication Q2): off -> fgPct ("Accuracy") -> share ("Volume") -> both -> off.
nonisolated enum ZoneLabelMode: Int, CaseIterable {
    case off, fgPct, share, both

    /// Advance on tap: off -> fgPct -> share -> both -> off.
    var next: ZoneLabelMode {
        switch self {
        case .off:   return .fgPct
        case .fgPct: return .share
        case .share: return .both
        case .both:  return .off
        }
    }

    /// The hint caption ALWAYS names the NEXT tap's result (adjudication Q2). Exact,
    /// byte-stable strings (asserted by a test); lowercase to match the existing hint style.
    var hint: String {
        switch self {
        case .off:   return "tap: Accuracy by zone"   // next tap -> fgPct
        case .fgPct: return "tap: Volume by zone"      // next tap -> share
        case .share: return "tap: Accuracy + Volume"   // next tap -> both
        case .both:  return "tap: hide labels"         // next tap -> off
        }
    }
}

/// The FG% label string, BYTE-IDENTICAL to the legacy `showZoneFG` overlay
/// (`Text("\(Int((pct * 100).rounded()))%")`). Kept as a free function so the exact
/// legacy formatting is unit-testable without SwiftUI.
nonisolated func zoneFGText(pct: Double) -> String {
    "\(Int((pct * 100).rounded()))%"
}

/// The Volume (attempt-share) label string, same rounding shape as the FG% string — except a
/// NONZERO share that would round to "0%" reads "<1%" (a zone can hold 5 of 1080 attempts —
/// 0.46% — and still show a real FG%, so "VOL 0%" next to "60%" reads as impossible).
nonisolated func zoneShareText(share: Double) -> String {
    let intPct = Int((share * 100).rounded())
    if intPct == 0 && share > 0 { return "<1%" }
    return "\(intPct)%"
}

/// Tallied total FGA across all zones (the denominator for attempt share, adjudication Q1 —
/// the SAME denominator A's `profile.zones.*.share` uses; NOT `meta.fga`).
nonisolated func totalTalliedFGA(_ zones: [String: PlayerShotChart.ZoneTally]) -> Int {
    zones.values.reduce(0) { $0 + $1.fga }
}

/// Per-zone attempt share = zone.fga / Σ zone.fga (adjudication Q1). Returns 0 when the
/// tallied total is 0 (the `fga >= 5` label gate suppresses every label anyway; no divide risk).
nonisolated func zoneAttemptShare(_ zone: PlayerShotChart.ZoneTally, totalFGA: Int) -> Double {
    totalFGA > 0 ? Double(zone.fga) / Double(totalFGA) : 0.0
}

/// The exact label LINES a zone renders for a given mode (B-8) — the single source of truth
/// for the `fga >= 5` gate, extracted from the `Canvas` so it is unit-testable:
///   - returns `[]` (NO label) whenever `tally.fga < 5`, in EVERY mode incl. `.off`;
///   - `.fgPct`  -> one line: the byte-preserved FG% string (nil `fgPct` also yields `[]`);
///   - `.share`  -> one line: the Volume attempt-share string;
///   - `.both`   -> two lines: FG% string FIRST, then `"VOL n%"` (both gated; nil `fgPct` -> `[]`).
/// The `Canvas` label pass calls this to decide what (and whether) to draw; styling/anchoring
/// (fonts, colors, the ±6 pt two-line offset) stays in the view.
/// Clamped center-x for a zone label of the given measured width so the label fits inside
/// `rect` inset by `inset` horizontally: the corner-3 centroids sit at x = ±230 of a ±250
/// court (~4% from each edge), so text centered there clips at the canvas boundary. Text
/// wider than the available span keeps its original center (degenerate case). Pure so the
/// arithmetic is unit-testable without a GraphicsContext.
nonisolated func clampedLabelCenterX(width: CGFloat, originalX: CGFloat,
                                     in rect: CGRect, inset: CGFloat = 2) -> CGFloat {
    let available = rect.width - 2 * inset
    guard available > 0, width <= available else { return originalX }
    let half = width / 2
    return min(max(originalX, rect.minX + inset + half), rect.maxX - inset - half)
}

nonisolated func zoneLabelLines(mode: ZoneLabelMode,
                                tally: PlayerShotChart.ZoneTally,
                                totalFGA: Int) -> [String] {
    guard tally.fga >= 5 else { return [] }           // the shared small-sample gate
    switch mode {
    case .off:
        return []
    case .fgPct:
        guard let pct = tally.fgPct else { return [] }
        return [zoneFGText(pct: pct)]
    case .share:
        return [zoneShareText(share: zoneAttemptShare(tally, totalFGA: totalFGA))]
    case .both:
        guard let pct = tally.fgPct else { return [] }
        return [zoneFGText(pct: pct),
                "VOL \(zoneShareText(share: zoneAttemptShare(tally, totalFGA: totalFGA)))"]
    }
}
