import SwiftUI

/// Reusable offensive half-court shot map. PURE inputs (points + zone summary +
/// zoneLabelMode + heatBlend + an optional precomputed HeatGrid + an onTap callback); no
/// store dependency, so sub-project C can reuse it. Green ● = make, red ✕ = miss. Tapping
/// advances the parent-owned zoneLabelMode (off -> FG% -> Volume -> both -> off) via onTap.
/// The Dot↔Heat slider lives in the PARENT (below this view, outside the Canvas) and drives
/// heatBlend in [0,1]: dots fade at (1 - heatBlend), the heat layer fades in at heatBlend.
/// Canvas draw order (binding): heat -> court -> dots -> labels.
struct HalfCourtView: View {
    let points: [PlayerShotChart.ShotPoint]
    let zones: [String: PlayerShotChart.ZoneTally]
    let zoneLabelMode: ZoneLabelMode       // was: @Binding var showZoneFG: Bool
    let heatBlend: Double                    // 0 = dots only, 1 = heat only
    let heatGrid: HeatGrid?                  // precomputed once per chart; nil => no heat layer
    let onTap: () -> Void                    // parent advances zoneLabelMode (owns the @State)

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)

            // 1. HEAT LAYER (bottom-most): only when blended in and a grid is injected.
            if heatBlend > 0, let grid = heatGrid {
                drawHeat(&ctx, rect, grid)
            }

            // 2. COURT LINES: above the heat layer.
            drawCourt(&ctx, rect)

            // 3. DOTS (make ●/miss ✕): above the court lines, faded by (1 - heatBlend).
            let dotAlpha = 1.0 - heatBlend
            if dotAlpha > 0 {
                for p in points {
                    let pt = CourtGeometry.point(x: p.x, y: p.y, in: rect)
                    if p.made {
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                                 with: .color(.green.opacity(0.65 * dotAlpha)))
                    } else {
                        var x = Path()
                        x.move(to: CGPoint(x: pt.x - 2.5, y: pt.y - 2.5)); x.addLine(to: CGPoint(x: pt.x + 2.5, y: pt.y + 2.5))
                        x.move(to: CGPoint(x: pt.x + 2.5, y: pt.y - 2.5)); x.addLine(to: CGPoint(x: pt.x - 2.5, y: pt.y + 2.5))
                        ctx.stroke(x, with: .color(.red.opacity(0.6 * dotAlpha)), lineWidth: 1)
                    }
                }
            }

            // 4. ZONE LABELS (above everything), independent of heatBlend.
            drawZoneLabels(&ctx, rect)
        }
        .aspectRatio(50.0 / 47.0, contentMode: .fit)      // court is 50ft wide x 47ft (half)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(alignment: .topTrailing) {
            Text(zoneLabelMode.hint)
                .font(.caption2).foregroundStyle(.secondary).padding(4)
        }
    }

    // MARK: zone labels — the tap-cycle overlay

    private func drawZoneLabels(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        if zoneLabelMode == .off { return }
        // `zoneLabelLines` (B-8) is the SINGLE SOURCE OF TRUTH for the `fga >= 5` gate and the
        // exact per-mode strings; the view only maps those lines to fonts/colors/anchors. This
        // keeps the `.fgPct` first line byte-identical to the legacy overlay (same string, and
        // .caption2/.bold/.primary at the same centroid) while making the gate unit-testable.
        let total = totalTalliedFGA(zones)
        for (zone, pt) in CourtGeometry.zoneCentroids(in: rect) {
            guard let t = zones[zone] else { continue }
            let lines = zoneLabelLines(mode: zoneLabelMode, tally: t, totalFGA: total)
            guard !lines.isEmpty else { continue }        // sub-5 (or nil fgPct) => draw nothing
            if lines.count == 1 {
                // .fgPct => primary bold (byte-identical style); .share => secondary bold.
                let color: Color = (zoneLabelMode == .fgPct) ? .primary : .secondary
                let text = Text(lines[0]).font(.caption2).bold().foregroundColor(color)
                ctx.draw(ctx.resolve(text), at: pt)
            } else {
                // .both => two-line stack: FG% (primary bold) on top, "VOL n%" (secondary) below.
                let top = Text(lines[0]).font(.caption2).bold().foregroundColor(.primary)
                ctx.draw(ctx.resolve(top), at: CGPoint(x: pt.x, y: pt.y - 6))
                let bottom = Text(lines[1]).font(.caption2).foregroundColor(.secondary)
                ctx.draw(ctx.resolve(bottom), at: CGPoint(x: pt.x, y: pt.y + 6))
            }
        }
    }

    // MARK: heat layer

    private func drawHeat(_ ctx: inout GraphicsContext, _ rect: CGRect, _ grid: HeatGrid) {
        // Cell footprint in view units: `spacing` court units mapped both axes. Use the court
        // transform on the cell center and a spacing-sized rounded rect around it.
        // NOTE: CourtGeometry.xMin/xMax/yMin/yMax are CGFloat and match the court span exactly
        // (B-10 verified against the real CourtGeometry.swift); grid.spacing is Double, so every
        // operand is coerced to CGFloat explicitly to keep the mixed-type arithmetic compiling.
        let spacingCG = CGFloat(grid.spacing)
        let halfW = rect.width * (spacingCG / (CourtGeometry.xMax - CourtGeometry.xMin)) / 2
        let halfH = rect.height * (spacingCG / (CourtGeometry.yMax - CourtGeometry.yMin)) / 2
        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let v = grid.values[row * grid.cols + col]
                if v.isNaN || v == 0 { continue }                  // masked or neutral -> skip
                let t = abs(v)
                let base = v < 0 ? HeatField.coolColor : HeatField.hotColor
                let cellOpacity = min(HeatField.maxOpacity, t * HeatField.maxOpacity) * heatBlend
                if cellOpacity <= 0 { continue }
                let center = grid.center(col: col, row: row)
                let c = CourtGeometry.point(x: center.x, y: center.y, in: rect)
                let cellRect = CGRect(x: c.x - halfW, y: c.y - halfH, width: halfW * 2, height: halfH * 2)
                let color = Color(red: Double(base.r) / 255, green: Double(base.g) / 255,
                                  blue: Double(base.b) / 255).opacity(cellOpacity)
                ctx.fill(Path(roundedRect: cellRect, cornerRadius: 2), with: .color(color))
            }
        }
    }

    // MARK: court lines (UNCHANGED from the shipped version)

    private func drawCourt(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        CourtLines.draw(&ctx, rect)     // single source of truth (shared with LineupShotGeographyCanvas)
    }
}
