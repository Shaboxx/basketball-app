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

    // --- baseline / shrinkage ---
    static let baselineMinFGA: Int = 30                     // use player's own FG% only when overallFGA >= this
    static let leagueFallbackFG: Double = 0.46              // p0 fallback, used ONLY when overallFGA < baselineMinFGA
    static let priorWeight: Double = 8                      // pseudo-attempts shrinking p̂ toward p0

    // --- masking / density / normalization ---
    static let minMass: Double = 5                          // cell masked (transparent) when A < this
    static let densityAnchor: Double = 25                   // A at which D saturates to 1 (via sqrt(A/25))
    static let accuracyAnchor: Double = 0.15                // ±15pp deviation maps to V = ±1 (ABSOLUTE, not per-player)

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

    /// PURE, deterministic. `points` are `PlayerShotChart.ShotPoint` (x/y Int court units,
    /// made Bool). `overallFGA`/`overallFGM` are the player's season totals (`meta.fga`/`meta.fgm`).
    /// Returns a 26×24 `HeatGrid`; masked cells carry NaN. Empty/degraded input => all-masked grid.
    nonisolated static func build(points: [PlayerShotChart.ShotPoint],
                                  overallFGA: Int,
                                  overallFGM: Int) -> HeatGrid {
        let cols = 26, rows = 24
        // 0. Defensive total-function rule: overallFGA <= 0 => all-masked grid, ALWAYS,
        //    even if `points` is nonempty (impossible in real data — points ⊆ attempts — but the
        //    binding "no fabricated field at fga == 0" rule must hold for any input).
        guard overallFGA > 0 else {
            return HeatGrid(cols: cols, rows: rows, spacing: spacing, xMin: xMin, yMin: yMin,
                            values: [Double](repeating: Double.nan, count: cols * rows))
        }
        // 1. Baseline p0.
        let p0: Double = (overallFGA >= baselineMinFGA)
            ? Double(overallFGM) / Double(overallFGA)
            : leagueFallbackFG

        // 2. Filter to in-bounds points ONLY (adjudication Q3: OOB excluded from the field).
        let inBounds = points.filter {
            Double($0.x) >= xMin && Double($0.x) <= xMax &&
            Double($0.y) >= yMin && Double($0.y) <= yMax
        }

        var values = [Double](repeating: Double.nan, count: cols * rows)

        for row in 0..<rows {
            let cy = yMin + Double(row) * spacing
            for col in 0..<cols {
                let cx = xMin + Double(col) * spacing
                // Accumulate this cell's mass via the single-source helper (B-7).
                let (A, M) = massAndMade(points: inBounds, cx: cx, cy: cy)
                if A < minMass { continue }           // masked -> stays NaN
                let pHat = (M + priorWeight * p0) / (A + priorWeight)   // shrink toward p0
                let D = min(1.0, (A / densityAnchor).squareRoot())      // density damping
                let dev = (pHat - p0) / accuracyAnchor                  // signed, ±15pp -> ±1
                let V = D * max(-1.0, min(1.0, dev))                    // clamp to [-1,+1]
                values[row * cols + col] = V
            }
        }
        return HeatGrid(cols: cols, rows: rows, spacing: spacing,
                        xMin: xMin, yMin: yMin, values: values)
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
