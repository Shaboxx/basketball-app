import SwiftUI

/// The shared offensive half-court line drawing, extracted verbatim from HalfCourtView so the
/// new lineup shot-geography canvas draws an IDENTICAL court. Pure `nonisolated` static — no
/// state, no store. HalfCourtView.drawCourt now delegates here (single source of truth).
nonisolated enum CourtLines {
    static func draw(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        let line = Color.secondary.opacity(0.5)
        func P(_ x: Int, _ y: Int) -> CGPoint { CourtGeometry.point(x: x, y: y, in: rect) }
        // Boundary (baseline/sidelines + half-court line are the frame edges).
        ctx.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(line), lineWidth: 1)
        // Backboard + rim.
        var bb = Path(); bb.move(to: P(-30, -8)); bb.addLine(to: P(30, -8))
        ctx.stroke(bb, with: .color(line), lineWidth: 1.5)
        let rim = P(0, 0)
        ctx.stroke(Path(ellipseIn: CGRect(x: rim.x - 6, y: rim.y - 6, width: 12, height: 12)),
                   with: .color(line), lineWidth: 1)
        // Paint (lane) from baseline to the FT line (+/- 8 ft).
        let tl = P(-80, 142), br = P(80, -48)
        ctx.stroke(Path(CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)),
                   with: .color(line), lineWidth: 1)
        // FT circle.
        let ft = P(0, 142), ftR = abs(P(60, 142).x - ft.x)
        ctx.stroke(Path(ellipseIn: CGRect(x: ft.x - ftR, y: ft.y - ftR, width: ftR * 2, height: ftR * 2)),
                   with: .color(line), lineWidth: 1)
        // 3-point line: corner verticals (x = +/-220 up to the break at y=88) + the arc.
        var corners = Path()
        corners.move(to: P(-220, -48)); corners.addLine(to: P(-220, 88))
        corners.move(to: P(220, -48));  corners.addLine(to: P(220, 88))
        ctx.stroke(corners, with: .color(line), lineWidth: 1)
        var arc = Path()
        let r = 237.5, start = atan2(88.0, -220.0), end = atan2(88.0, 220.0), steps = 40
        for i in 0...steps {
            let t = start + (end - start) * Double(i) / Double(steps)
            let pt = P(Int((r * cos(t)).rounded()), Int((r * sin(t)).rounded()))
            if i == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
        }
        ctx.stroke(arc, with: .color(line), lineWidth: 1)
    }
}
