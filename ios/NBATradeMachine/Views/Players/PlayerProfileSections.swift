import SwiftUI

// MARK: - Roles

struct RolesSection: View {
    let player: Player
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if player.primaryRole == nil
                && player.secondaryRole == nil
                && player.defensiveRole == nil {
                noDataRow
            } else {
                row("Primary Offensive", player.primaryRole)
                row("Secondary Offensive", player.secondaryRole)
                row("Defensive", player.defensiveRole)
            }
        } label: {
            Text("Roles").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func row(_ key: String, _ value: String?) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Latent Value (Phase 7 v2)

/// Full breakdown of `Player.latentValue` — the fused CraftedPM ⊕ EPM rate
/// (θ̂, points/100) plus per-channel split, league-standardized z variants,
/// fusion weights, drift, and the Tier-B projection. Collapsed by default
/// since the headline OFF/DEF σ already appears in the page header.
struct LatentValueSection: View {
    let player: Player
    @EnvironmentObject var teamsVM: TeamsViewModel
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let lv = player.latentValue {
                content(lv)
            } else {
                noDataRow
            }
        } label: {
            Text("Latent Value").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    @ViewBuilder
    private func content(_ lv: LatentValue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ratePair(label: "θ̂  (pts/100)",
                     off: lv.thetaOff, def: lv.thetaDef, total: lv.theta)
            ratePair(label: "σ vs league",
                     off: lv.thetaZOff, def: lv.thetaZDef, total: lv.thetaZ)

            if let se = lv.se {
                row("SE", String(format: "±%.2f", se))
            }
            if let r = lv.reliability {
                row("Reliability", String(format: "%.2f", r))
            }
            if let w = lv.weights, let c = w.crafted, let e = w.epm {
                row("Crafted / EPM weights",
                    String(format: "%.0f%% / %.0f%%", c * 100, e * 100))
            }

            driftRow(lv)
            valueGapRow
            trajectory(lv)
            projectionRow(lv)

            if let v = lv.modelVersion ?? lv.version {
                Text("Model \(v)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    /// Sparkline of in-sample smoothed θ̂ (Tier-B `theta_by_season`) followed
    /// by the multi-season projection. Solid line up to the most recent
    /// in-sample point, then dashed through the projection. Hidden unless we
    /// have at least two points total — a single point isn't a trajectory.
    @ViewBuilder
    private func trajectory(_ lv: LatentValue) -> some View {
        let points = trajectoryPoints(lv)
        if points.count >= 2 {
            Divider().padding(.vertical, 4)
            HStack {
                Text("Trajectory")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("θ̂  pts/100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TrajectorySparkline(points: points)
                .frame(height: 56)
                .padding(.top, 4)
            HStack {
                if let first = points.first?.season {
                    Text(first).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let last = points.last?.season {
                    Text(last).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func trajectoryPoints(_ lv: LatentValue) -> [TrajectorySparkline.Point] {
        var out: [TrajectorySparkline.Point] = []
        if let hist = lv.thetaBySeason {
            for p in hist {
                if let s = p.season, let t = p.theta {
                    out.append(.init(season: s, theta: t, projected: false))
                }
            }
        }
        if let proj = lv.projection {
            for p in proj {
                if let s = p.season, let t = p.theta {
                    out.append(.init(season: s, theta: t, projected: true))
                }
            }
        }
        return out
    }

    /// "Paid like top X% · plays like top Y%, gap ±N pts." A positive gap
    /// means salary outruns rating (overpaid); negative means underpaid.
    /// Hidden when either signal is missing or fewer than ~10 league peers
    /// carry σ (the rank isn't meaningful below that).
    @ViewBuilder
    private var valueGapRow: some View {
        if let g = teamsVM.valueGap(for: player) {
            HStack(alignment: .firstTextBaseline) {
                Text("Value gap").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Paid top \(100 - g.salaryPct)% · Plays top \(100 - g.sigmaPct)%")
                        .font(.caption.monospacedDigit())
                    Text(gapLabel(g.gap))
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(gapColor(g.gap))
                }
            }
            .padding(.top, 6)
        }
    }

    private func gapColor(_ gap: Int) -> Color {
        if gap >= 15 { return .red }
        if gap <= -15 { return .green }
        return .secondary
    }

    private func gapLabel(_ gap: Int) -> String {
        if gap == 0 { return "Fair (gap 0 pts)" }
        let dir = gap > 0 ? "Overpaid" : "Underpaid"
        return "\(dir) by \(abs(gap)) pts"
    }

    @ViewBuilder
    private func driftRow(_ lv: LatentValue) -> some View {
        if let off = lv.driftZOff, let def = lv.driftZDef {
            HStack {
                Text("Drift Δσ/yr").foregroundStyle(.secondary)
                Spacer()
                Text("OFF \(signed(off, fmt: "%+.2f"))  ·  DEF \(signed(def, fmt: "%+.2f"))")
                    .monospacedDigit().bold()
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func projectionRow(_ lv: LatentValue) -> some View {
        if let proj = lv.projection, !proj.isEmpty {
            Divider().padding(.vertical, 4)
            Text("Projection")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(proj.indices, id: \.self) { i in
                let p = proj[i]
                HStack {
                    Text(p.season ?? "—").foregroundStyle(.secondary)
                    Spacer()
                    Text(projectionValue(p))
                        .monospacedDigit().bold()
                }
                .padding(.top, 4)
            }
        }
    }

    private func projectionValue(_ p: LatentValue.Projection) -> String {
        if let z = p.thetaZ {
            if let se = p.seZ { return String(format: "%+.2fσ ±%.2f", z, se) }
            return String(format: "%+.2fσ", z)
        }
        if let t = p.theta {
            if let se = p.se { return String(format: "%+.2f ±%.2f", t, se) }
            return String(format: "%+.2f", t)
        }
        return "—"
    }

    private func ratePair(label: String, off: Double?, def: Double?, total: Double?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("OFF \(signed(off, fmt: "%+.2f"))  ·  DEF \(signed(def, fmt: "%+.2f"))  ·  TOT \(signed(total, fmt: "%+.2f"))")
                .font(.subheadline.monospacedDigit())
                .bold()
        }
        .padding(.top, 6)
    }

    private func signed(_ v: Double?, fmt: String) -> String {
        guard let v else { return "—" }
        return String(format: fmt, v)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Trajectory sparkline

/// Tiny Canvas line chart for θ̂ history + projection. In-sample segment is
/// solid, projected segment is dashed; a small dot marks each season. Pure
/// view — drawing only, no interaction.
struct TrajectorySparkline: View {
    struct Point: Equatable {
        let season: String
        let theta: Double
        let projected: Bool
    }

    let points: [Point]

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let xs = points.indices.map { CGFloat($0) / CGFloat(points.count - 1) }
            let lo = points.map(\.theta).min() ?? 0
            let hi = points.map(\.theta).max() ?? 1
            let span = max(hi - lo, 0.5)
            func y(_ v: Double) -> CGFloat {
                let t = CGFloat((v - lo) / span)
                let pad: CGFloat = 6
                return size.height - pad - t * (size.height - pad * 2)
            }
            func x(_ i: Int) -> CGFloat { xs[i] * size.width }

            // Solid segment for in-sample, dashed for projection. We split at
            // the first projected index so a player without Tier-B projection
            // is drawn fully solid.
            let firstProj = points.firstIndex(where: \.projected) ?? points.count
            if firstProj >= 2 {
                var solid = Path()
                solid.move(to: CGPoint(x: x(0), y: y(points[0].theta)))
                for i in 1..<firstProj {
                    solid.addLine(to: CGPoint(x: x(i), y: y(points[i].theta)))
                }
                ctx.stroke(solid, with: .color(.blue), lineWidth: 1.6)
            }
            if firstProj < points.count {
                var dashed = Path()
                let startIdx = max(firstProj - 1, 0)
                dashed.move(to: CGPoint(x: x(startIdx), y: y(points[startIdx].theta)))
                for i in (startIdx + 1)..<points.count {
                    dashed.addLine(to: CGPoint(x: x(i), y: y(points[i].theta)))
                }
                ctx.stroke(
                    dashed,
                    with: .color(.blue.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1.6, dash: [3, 3])
                )
            }

            // Per-season dots: filled for in-sample, hollow for projection.
            for i in points.indices {
                let r: CGFloat = 2.5
                let rect = CGRect(x: x(i) - r, y: y(points[i].theta) - r,
                                  width: r * 2, height: r * 2)
                let path = Path(ellipseIn: rect)
                if points[i].projected {
                    ctx.stroke(path, with: .color(.blue), lineWidth: 1)
                } else {
                    ctx.fill(path, with: .color(.blue))
                }
            }

            // Zero baseline (faint) to anchor signed values.
            if lo < 0 && hi > 0 {
                var zero = Path()
                zero.move(to: CGPoint(x: 0, y: y(0)))
                zero.addLine(to: CGPoint(x: size.width, y: y(0)))
                ctx.stroke(zero, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Salary

struct SalarySection: View {
    let player: Player
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let amounts = [player.salaryY1, player.salaryY2, player.salaryY3, player.salaryY4]
            if amounts.allSatisfy({ $0 == nil }) {
                noDataRow
            } else {
                ForEach(0..<4, id: \.self) { idx in
                    if let amount = amounts[idx] {
                        salaryRow(label: label(forOffset: idx), amount: amount)
                    }
                }
            }
        } label: {
            Text("Salary").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func label(forOffset offset: Int) -> String {
        if let season = player.seasonLabel(forOffset: offset) { return season }
        return "Year \(offset + 1)"
    }

    private func salaryRow(label: String, amount: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(Money.display(amount)).monospacedDigit().bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Projected Contract

struct ProjectedContractSection: View {
    let player: Player
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if allFieldsNil {
                noDataRow
            } else {
                if let starts = player.projectedContractStartSeason {
                    row("Starts", starts)
                }
                if let tier = player.maxTierPct {
                    row("Max Tier", "\(tier)%")
                }
                if let nextMax = player.nextContractMax {
                    row("Next Max", Money.display(nextMax))
                }
                if let basis = player.nextContractMaxBasis {
                    row("Basis", basis)
                }
                if let met = player.higherMaxCriteriaMet {
                    row("Higher Max Met", met ? "Yes" : "No")
                }
                if let path = player.supermaxPath {
                    row("Supermax Path", path)
                }
                if let stdMax = player.standardMax {
                    row("Standard Max", Money.display(stdMax))
                }
                if let minSal = player.minSalary {
                    row("Min Salary", Money.display(minSal))
                }
                footer
            }
        } label: {
            Text("Projected Contract").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var allFieldsNil: Bool {
        player.projectedContractStartSeason == nil
            && player.maxTierPct == nil
            && player.nextContractMax == nil
            && player.nextContractMaxBasis == nil
            && player.higherMaxCriteriaMet == nil
            && player.supermaxPath == nil
            && player.standardMax == nil
            && player.minSalary == nil
    }

    @ViewBuilder private var footer: some View {
        if player.cbaSeason != nil || player.cbaUpdatedRelative != nil {
            HStack {
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if let season = player.cbaSeason { parts.append("CBA \(season)") }
        if let rel = player.cbaUpdatedRelative { parts.append("updated \(rel)") }
        return parts.joined(separator: " · ")
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}
