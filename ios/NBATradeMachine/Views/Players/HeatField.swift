import Foundation

/// A shrinkage-regularized SIGNED accuracy heat field over the offensive half court
/// (sub-project B). Pure, `nonisolated`, no SwiftUI: a deterministic function of the shot
/// points + the player's overall makes/attempts + named constants. No device scale, no
/// per-player normalization — so it is unit-testable, comparable across players, and
/// reusable by sub-project C (which builds one grid per player and composites).
nonisolated enum HeatField {
    // --- grid geometry (court units, tenths-of-feet; matches CourtGeometry) ---
    static let xMin: Double = -250, xMax: Double = 250     // court x span
    static let yMin: Double = -48,  yMax: Double = 422      // court y span
    static let spacing: Double = 20                         // cell-center step (court units)

    // --- kernel ---
    static let sigma: Double = 30                           // Gaussian bandwidth
    static let kernelCutoff: Double = 90                    // ignore shots farther than this from a cell center

    // --- shrinkage ---
    static let priorWeight: Double = 8                      // pseudo-attempts shrinking p̂ toward p0

    // --- masking / density / normalization ---
    static let minMass: Double = 5                          // cell masked (transparent) when A < this
    static let densityAnchor: Double = 25                   // A at which D saturates to 1 (via sqrt(A/25))
    static let accuracyAnchor: Double = 0.15                // ±15pp deviation maps to V = ±1 (ABSOLUTE, not per-player)
    static let epAnchor: Double = 0.25                      // ±0.25 PPS deviation maps to V_ep = ±1 (EP_ANCHOR)

    // --- color ramp (ABSOLUTE anchors so players are comparable) ---
    static let coolColor = (r: 0x21, g: 0x66, b: 0xAC)      // #2166AC at V = -1
    static let hotColor  = (r: 0xD9, g: 0x5F, b: 0x0E)      // #D95F0E at V = +1
    static let maxOpacity: Double = 0.78                    // cap on |V|-driven cell opacity

    /// PURE kernel accumulation for ONE cell center — the SINGLE SOURCE OF TRUTH for build's
    /// inner loop (B-7), so the exact Gaussian mass is directly unit-testable without exposing
    /// HeatGrid's stored shape. Returns (attempt mass A = Σw, made mass M = Σ(w·made)). Points
    /// farther than `kernelCutoff` from (cx,cy) contribute nothing. Callers pass in-bounds points.
    nonisolated static func massAndMade(points: [PlayerShotChart.ShotPoint],
                                        cx: Double,
                                        cy: Double) -> (mass: Double, made: Double) {
        let twoSigmaSq = 2 * sigma * sigma          // 2·30² = 1800
        let cutoffSq = kernelCutoff * kernelCutoff  // 90² = 8100
        var A = 0.0, M = 0.0
        for p in points {
            let dx = Double(p.x) - cx, dy = Double(p.y) - cy
            let d2 = dx * dx + dy * dy
            if d2 > cutoffSq { continue }            // hard kernel cutoff at 90 units
            let w = exp(-d2 / twoSigmaSq)            // Gaussian weight
            A += w
            if p.made { M += w }
        }
        return (A, M)
    }

    /// PURE, deterministic. `points`/`overallFGA`/`overallFGM` as before; `league` is the
    /// league per-cell FG% field (624 row-major doubles; a cell is `Double.nan` where the
    /// league kernel mass was below LEAGUE_MIN_MASS). Pass `nil` when the league field is
    /// unavailable => an ALL-MASKED grid (heat unavailable; NEVER own-baseline fallback).
    /// `overallFGA`/`overallFGM` are retained ONLY for the empty-input total-function guard
    /// and future diagnostics — they no longer feed the baseline (own-baseline retired, D1).
    nonisolated static func build(points: [PlayerShotChart.ShotPoint],
                                  overallFGA: Int,
                                  overallFGM: Int,
                                  league: [Double]?) -> HeatGrid {
        let cols = 26, rows = 24
        let allMasked = HeatGrid(cols: cols, rows: rows, spacing: spacing, xMin: xMin, yMin: yMin,
                                 values: [Double](repeating: Double.nan, count: cols * rows))
        // 0. League field REQUIRED. Missing or wrong-length => heat unavailable (all-masked).
        guard let L = league, L.count == cols * rows else { return allMasked }
        // 1. Defensive total-function guard (unchanged): no season attempts => all-masked.
        guard overallFGA > 0 else { return allMasked }
        // 2. In-bounds filter ONLY (unchanged).
        let inBounds = points.filter {
            Double($0.x) >= xMin && Double($0.x) <= xMax &&
            Double($0.y) >= yMin && Double($0.y) <= yMax
        }
        var values = [Double](repeating: Double.nan, count: cols * rows)
        for row in 0..<rows {
            let cy = yMin + Double(row) * spacing
            for col in 0..<cols {
                let idx = row * cols + col
                let Lc = L[idx]
                if Lc.isNaN { continue }                       // league null => player cell MASKED
                let cx = xMin + Double(col) * spacing
                let (A, M) = massAndMade(points: inBounds, cx: cx, cy: cy)
                if A < minMass { continue }                    // A < 5 mask (UNCHANGED)
                let pHat = (M + priorWeight * Lc) / (A + priorWeight)   // shrink toward L_c
                let D = min(1.0, (A / densityAnchor).squareRoot())      // density damping (UNCHANGED)
                let dev = (pHat - Lc) / accuracyAnchor                  // signed, ±0.15 -> ±1
                values[idx] = D * max(-1.0, min(1.0, dev))              // V = D·clamp(dev, ±1)
            }
        }
        return HeatGrid(cols: cols, rows: rows, spacing: spacing, xMin: xMin, yMin: yMin, values: values)
    }

    /// The 2/3 cell classifier (cell CENTERS, not raw shots). Byte-identical to the Python
    /// league_field.cell_shot_value. Reads CourtThreeGeometry (shared constants, F10).
    nonisolated static func cellShotValue(cx: Double, cy: Double) -> Int {
        if cy >= CourtThreeGeometry.cornerYStar {
            return (cx * cx + cy * cy) >= (CourtThreeGeometry.arcRadius * CourtThreeGeometry.arcRadius) ? 3 : 2
        }
        return abs(cx) >= CourtThreeGeometry.cornerX ? 3 : 2
    }

    /// PURE expected-points field (D2). Reuses the EXACT L_c-NaN mask, A<5 mask, p̂, and D from
    /// `build`, then colors EP_c = p̂_c·q_c anchored at `leagueMeanPPS`: V_ep = D·clamp((EP -
    /// leagueMeanPPS)/EP_ANCHOR, ±1), EP_ANCHOR = 0.25 PPS. Missing/wrong-length league OR a
    /// non-finite anchor => all-masked (PA3: a NaN/Inf leagueMeanPPS would poison every dev; the
    /// [0.8,1.4] RANGE policing stays at the validation layer, spec F6 — this is only a finiteness
    /// total-function guard, not a duplicate range check).
    nonisolated static func buildEP(points: [PlayerShotChart.ShotPoint],
                                    overallFGA: Int,
                                    overallFGM: Int,
                                    league: [Double]?,
                                    leagueMeanPPS: Double) -> HeatGrid {
        let cols = 26, rows = 24
        let allMasked = HeatGrid(cols: cols, rows: rows, spacing: spacing, xMin: xMin, yMin: yMin,
                                 values: [Double](repeating: Double.nan, count: cols * rows))
        guard let L = league, L.count == cols * rows else { return allMasked }
        guard overallFGA > 0 else { return allMasked }
        guard leagueMeanPPS.isFinite else { return allMasked }   // PA3: finiteness guard (not range)
        let inBounds = points.filter {
            Double($0.x) >= xMin && Double($0.x) <= xMax &&
            Double($0.y) >= yMin && Double($0.y) <= yMax
        }
        var values = [Double](repeating: Double.nan, count: cols * rows)
        for row in 0..<rows {
            let cy = yMin + Double(row) * spacing
            for col in 0..<cols {
                let idx = row * cols + col
                let Lc = L[idx]
                if Lc.isNaN { continue }
                let cx = xMin + Double(col) * spacing
                let (A, M) = massAndMade(points: inBounds, cx: cx, cy: cy)
                if A < minMass { continue }
                let pHat = (M + priorWeight * Lc) / (A + priorWeight)
                let D = min(1.0, (A / densityAnchor).squareRoot())
                let ep = pHat * Double(cellShotValue(cx: cx, cy: cy))
                let dev = (ep - leagueMeanPPS) / epAnchor
                values[idx] = D * max(-1.0, min(1.0, dev))
            }
        }
        return HeatGrid(cols: cols, rows: rows, spacing: spacing, xMin: xMin, yMin: yMin, values: values)
    }
}

extension HeatField {
    /// PURE, `nonisolated`. The RAW kernel attempt-mass field (Σ Gaussian weights) over the
    /// SAME 26×24 = 624-cell grid geometry as `build`, reusing `massAndMade` and the identical
    /// in-bounds filter. Returns a row-major `[Double]` of length 624 (NOT a HeatGrid — this is
    /// raw mass A, not a signed value V; HeatGrid's stored shape is unchanged). No shrinkage, no
    /// baseline, no normalization: `mass_c = Σ_p exp(-d²/(2σ²))` over in-bounds points within the
    /// kernel cutoff. Empty / all-OOB input => all-zero array (a valid total function). Cell
    /// indexing (`row * 26 + col`, cell centers) is byte-identical to `build`'s, so a member's
    /// `massGrid[c]` aligns with that member's `HeatGrid` cell `c`.
    nonisolated static func massGrid(points: [PlayerShotChart.ShotPoint]) -> [Double] {
        let cols = 26, rows = 24
        let inBounds = points.filter {
            Double($0.x) >= xMin && Double($0.x) <= xMax &&
            Double($0.y) >= yMin && Double($0.y) <= yMax
        }
        var mass = [Double](repeating: 0, count: cols * rows)
        for row in 0..<rows {
            let cy = yMin + Double(row) * spacing
            for col in 0..<cols {
                let cx = xMin + Double(col) * spacing
                mass[row * cols + col] = massAndMade(points: inBounds, cx: cx, cy: cy).mass
            }
        }
        return mass
    }
}

/// A row-major 26×24 signed-value grid. Masked cells carry `Double.nan` (transparent).
/// NOT `Equatable`: a synthesized `==` would report two identical all-masked grids UNEQUAL
/// because `NaN != NaN`. Tests compare via the NaN-aware `isEqual` helper instead.
nonisolated struct HeatGrid {
    let cols: Int              // 26
    let rows: Int              // 24
    let spacing: Double        // 20 (cell size in court units)
    let xMin: Double, yMin: Double
    /// Signed value per cell, row-major (row * cols + col). NaN == masked (transparent).
    let values: [Double]

    /// NaN-aware comparison for tests: corresponding NaNs are EQUAL; non-NaN values must
    /// match within `tolerance` (float addition order can differ across reorderings).
    static func isEqual(_ a: HeatGrid, _ b: HeatGrid, tolerance: Double = 1e-9) -> Bool {
        guard a.cols == b.cols, a.rows == b.rows, a.values.count == b.values.count else { return false }
        return zip(a.values, b.values).allSatisfy { x, y in
            (x.isNaN && y.isNaN) || (!x.isNaN && !y.isNaN && abs(x - y) <= tolerance)
        }
    }

    /// Court-space center of a cell (used with `CourtGeometry.point` to place it).
    func center(col: Int, row: Int) -> (x: Int, y: Int) {
        (Int((xMin + Double(col) * spacing).rounded()),
         Int((yMin + Double(row) * spacing).rounded()))
    }
}
