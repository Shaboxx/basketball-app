import SwiftUI

/// Post-validation Trade Confirmation page.
///
/// Layout adapts to size class:
///   • Compact (portrait phones) — vertical scrollable stack of per-team
///     sections.
///   • Regular (iPad / landscape) — horizontally scrollable row of fixed-
///     width team columns, each column independently vertically scrollable.
///
/// Renders cards for every incoming player + pick on each team, plus a
/// per-team rollup footer (asset Δ, OFF/DEF Δ vs self, vs league, trust
/// flag union), and two forward-compat placeholder tiles (Chemistry and
/// Peak Window) that surface once Phase 7f payloads exist.
///
/// A bottom share bar renders the full surface as a single image plus a
/// text summary via SwiftUI's ShareLink.
struct TradeConfirmationView: View {
    let confirmation: TradeConfirmation
    /// The original trade — used only for share-text serialization.
    let trade: Trade
    /// Player lookup used by the share-text serializer.
    let playersById: [String: Player]
    var onDismiss: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    contentSurface
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                }
                Divider()
                TradeConfirmationShareBar(
                    trade: trade,
                    confirmation: confirmation,
                    playersById: playersById
                )
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Trade Confirmed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var contentSurface: some View {
        if horizontalSizeClass == .regular {
            // Side-by-side columns on iPad / landscape — single tall surface
            // for the screenshot share.
            HStack(alignment: .top, spacing: 16) {
                ForEach(confirmation.teams) { pkg in
                    TradeConfirmationTeamSection(package: pkg)
                        .frame(minWidth: 280, idealWidth: 320)
                }
                if confirmation.chemistry != nil || confirmation.peakTimeline != nil {
                    Phase7fColumn(
                        chemistry: confirmation.chemistry,
                        peakTimeline: confirmation.peakTimeline
                    )
                    .frame(minWidth: 240, idealWidth: 280)
                } else {
                    Phase7fColumn(chemistry: nil, peakTimeline: nil)
                        .frame(minWidth: 240, idealWidth: 280)
                }
            }
        } else {
            VStack(spacing: 18) {
                ForEach(confirmation.teams) { pkg in
                    TradeConfirmationTeamSection(package: pkg)
                }
                Phase7fColumn(
                    chemistry: confirmation.chemistry,
                    peakTimeline: confirmation.peakTimeline
                )
            }
        }
    }
}

// MARK: - Team section

private struct TradeConfirmationTeamSection: View {
    let package: TradeConfirmation.TeamPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if package.incomingPlayers.isEmpty
                && package.incomingPicks.isEmpty
                && package.cashOutgoing == 0 {
                Text("Receives nothing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(package.incomingPlayers) { p in
                    IncomingPlayerCard(player: p)
                }
                ForEach(package.incomingPicks) { pick in
                    IncomingPickCard(pick: pick)
                }
                if package.cashOutgoing > 0 {
                    CashCard(dollars: package.cashOutgoing)
                }
            }
            RollupFooter(rollup: package.rollup)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(package.team.fullName.uppercased())
                .font(.caption).foregroundStyle(.secondary)
            Text("receive")
                .font(.title3.weight(.semibold))
        }
    }
}

// MARK: - Player / Pick / Cash cards

private struct IncomingPlayerCard: View {
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(player.name).font(.headline)
                Spacer()
                if let salary = player.salaryY1 {
                    Text(formatDollars(salary))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            metricsRow
            if let role = player.compZ?.role {
                Text(role)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private var metricsRow: some View {
        let lv = player.latentValue
        HStack(spacing: 14) {
            if let theta = lv?.theta {
                metric(label: "θ", value: String(format: "%+.2f", theta))
            }
            // Prefer the standardized z; fall back to raw θ_off so the row
            // never goes blank while the Rev-2 z fields aren't in Firestore.
            if let oz = lv?.thetaZOff {
                metric(label: "OFF σ", value: String(format: "%+.2f", oz),
                       color: tint(for: oz))
            } else if let o = lv?.thetaOff {
                metric(label: "OFF θ", value: String(format: "%+.2f", o),
                       color: tint(for: o))
            }
            if let dz = lv?.thetaZDef {
                metric(label: "DEF σ", value: String(format: "%+.2f", dz),
                       color: tint(for: dz))
            } else if let d = lv?.thetaDef {
                metric(label: "DEF θ", value: String(format: "%+.2f", d),
                       color: tint(for: d))
            }
            // Asset prefers Phase 7e comp-Z dollarsPoint; falls back to
            // raw current-year salary so the contract still surfaces.
            if let asset = player.compZ?.asset?.dollarsPoint {
                metric(label: "Asset",
                       value: formatSignedDollars(asset),
                       color: asset >= 0 ? .green : .red)
            } else if let salary = player.salaryY1 {
                metric(label: "Salary",
                       value: formatDollars(salary),
                       color: .secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit())
    }

    private func tint(for z: Double) -> Color {
        if z > 0.15 { return .green }
        if z < -0.15 { return .red }
        return .secondary
    }

    private func metric(label: String, value: String,
                        color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).foregroundStyle(color)
        }
    }
}

private struct IncomingPickCard: View {
    let pick: Pick
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.shortLabel).font(.subheadline.weight(.semibold))
                if let pos = pick.projectedPosition {
                    Text("Projected #\(pos)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground))
        )
    }
}

private struct CashCard: View {
    let dollars: Int
    var body: some View {
        HStack {
            Image(systemName: "dollarsign.circle")
                .foregroundStyle(.secondary)
            Text("Cash: \(formatDollars(dollars))")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground))
        )
    }
}

// MARK: - Rollup

private struct RollupFooter: View {
    let rollup: TradeConfirmation.Rollup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                rollupCell(label: assetCell.label,
                           value: assetCell.value,
                           color: assetCell.color)
                Spacer()
                rollupCell(label: offCell.label,
                           value: offCell.value,
                           color: offCell.color)
                Spacer()
                rollupCell(label: defCell.label,
                           value: defCell.value,
                           color: defCell.color)
            }
            if rollup.assetDeltaHadMissing && rollup.assetDeltaDollars != nil {
                Text("Some players lack comp-Z — asset Δ excludes them.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !rollup.trustFlagsRaised.isEmpty {
                TrustFlagStrip(flags: rollup.trustFlagsRaised)
            }
        }
    }

    /// Prefers compZ asset; falls back to current-year salary so the cell
    /// always shows something meaningful even before the Phase 7e join is
    /// running upstream.
    private var assetCell: (label: String, value: String, color: Color) {
        if let d = rollup.assetDeltaDollars {
            return ("Asset Δ", formatSignedDollars(d), dollarColor(d))
        }
        if let s = rollup.salaryDeltaY1 {
            return ("Salary Δ", formatSignedDollars(s), .secondary)
        }
        return ("Asset Δ", "—", .secondary)
    }

    /// Prefers league-z fields; falls back to raw θ delta with a relabel
    /// so the magnitude isn't presented as a σ when it isn't standardized.
    private var offCell: (label: String, value: String, color: Color) {
        if let z = rollup.offDeltaLeagueZ {
            return ("OFF Δσ", String(format: "%+.2f", z), zColor(z))
        }
        if let v = rollup.offDeltaSelf {
            return ("OFF Δθ", String(format: "%+.2f", v), zColor(v))
        }
        return ("OFF Δσ", "—", .secondary)
    }

    private var defCell: (label: String, value: String, color: Color) {
        if let z = rollup.defDeltaLeagueZ {
            return ("DEF Δσ", String(format: "%+.2f", z), zColor(z))
        }
        if let v = rollup.defDeltaSelf {
            return ("DEF Δθ", String(format: "%+.2f", v), zColor(v))
        }
        return ("DEF Δσ", "—", .secondary)
    }

    private func dollarColor(_ d: Int) -> Color {
        d > 0 ? .green : (d < 0 ? .red : .primary)
    }

    private func zColor(_ z: Double) -> Color {
        if z > 0.15 { return .green }
        if z < -0.15 { return .red }
        return .primary
    }

    private func rollupCell(label: String, value: String,
                            color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

private struct TrustFlagStrip: View {
    let flags: Set<TradeConfirmation.TrustFlag>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(humanReadable)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var humanReadable: String {
        flags
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map(Self.label(for:))
            .joined(separator: " · ")
    }

    nonisolated private static func label(for flag: TradeConfirmation.TrustFlag) -> String {
        switch flag {
        case .costZero:        return "Zero cost"
        case .modelUnreliable: return "Low confidence"
        case .outlierAsset:    return "Outlier asset"
        case .value2xCost:     return "Value > 2× cost"
        case .staleStats:      return "Stale stats"
        case .freeAgent:       return "Free agent"
        }
    }
}

// MARK: - Phase 7f forward-compat tiles

private struct Phase7fColumn: View {
    let chemistry: ChemistryReport?
    let peakTimeline: PeakTimelineForecast?

    var body: some View {
        VStack(spacing: 12) {
            ChemistryTile(chemistry: chemistry)
            PeakTimelineTile(peakTimeline: peakTimeline)
        }
    }
}

private struct ChemistryTile: View {
    let chemistry: ChemistryReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Role chemistry", systemImage: "person.2.circle")
                .font(.subheadline.weight(.semibold))
            if let chemistry, let summary = chemistry.summary {
                Text(summary).font(.callout)
            } else if let chemistry, let score = chemistry.score {
                Text("Composite \(String(format: "%+.2fσ", score))")
                    .font(.callout)
            } else {
                Text("Coming with Phase 7f.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct PeakTimelineTile: View {
    let peakTimeline: PeakTimelineForecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Peak window", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
            if let p = peakTimeline,
               let start = p.peakStartSeason,
               let end = p.peakEndSeason {
                Text("Lineup peaks \(start) – \(end)").font(.callout)
                if let composite = p.peakComposite {
                    Text("Composite θ \(String(format: "%+.2f", composite))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Coming with Phase 7f.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Formatters (file-private)

private func formatDollars(_ value: Int) -> String {
    let abs = Swift.abs(value)
    if abs >= 1_000_000 {
        return String(format: "$%.2fM", Double(value) / 1_000_000)
    }
    if abs >= 1_000 {
        return String(format: "$%.0fK", Double(value) / 1_000)
    }
    return "$\(value)"
}

private func formatSignedDollars(_ value: Int) -> String {
    let sign = value >= 0 ? "+" : "−"
    return "\(sign)\(formatDollars(Swift.abs(value)))"
}
