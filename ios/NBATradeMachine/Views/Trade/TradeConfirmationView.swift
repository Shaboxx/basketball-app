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
            .navigationTitle("Trade Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // "Close" (not "Done"): this is a shareable review summary,
                    // not a submission — closing returns to editing (NAV-02).
                    Button("Close") { onDismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var contentSurface: some View {
        VStack(spacing: 16) {
            // Always render the grade lede — a placeholder when it can't be
            // computed, mirroring the other tiles' explicit-degradation pattern
            // rather than silently vanishing.
            TradeGradeHeader(grade: confirmation.grade)
            teamsSurface
        }
    }

    @ViewBuilder
    private var teamsSurface: some View {
        if horizontalSizeClass == .regular {
            // Side-by-side columns on iPad / landscape — single tall surface
            // for the screenshot share.
            HStack(alignment: .top, spacing: 16) {
                ForEach(confirmation.teams) { pkg in
                    TradeConfirmationTeamSection(package: pkg)
                        .frame(minWidth: 280, idealWidth: 320)
                }
                Phase7fColumn(
                    teams: confirmation.teams,
                    peakTimeline: confirmation.peakTimeline
                )
                .frame(minWidth: 240, idealWidth: 280)
            }
        } else {
            VStack(spacing: 18) {
                ForEach(confirmation.teams) { pkg in
                    TradeConfirmationTeamSection(package: pkg)
                }
                Phase7fColumn(
                    teams: confirmation.teams,
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
            RollupFooter(rollup: package.rollup, tradeValueNet: tradeValueNet)
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

    /// Net Trade Value for this team, all valued to THIS team's tricode:
    /// (sum of incoming player value) − (sum of outgoing player value).
    /// Nil when neither side carries any team-relative Trade Value entry.
    private var tradeValueNet: Double? {
        let tricode = package.team.tricode
        var any = false
        func sum(_ players: [Player]) -> Double {
            players.reduce(0.0) { acc, p in
                if let v = p.tradeValue?.forTeam(tricode)?.value {
                    any = true
                    return acc + v
                }
                return acc
            }
        }
        let tvIn = sum(package.incomingPlayers)
        let tvOut = sum(package.outgoingPlayers)
        return any ? tvIn - tvOut : nil
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
                HStack(spacing: 6) {
                    metric(label: "Asset",
                           value: formatSignedDollars(asset),
                           color: asset >= 0 ? .green : .red)
                    if let tier = player.compZ?.asset?.tier {
                        AssetTierBadge(tier: tier)
                    }
                }
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
    /// Net team-relative Trade Value (tvIn − tvOut), in raw dollars. Nil when
    /// no moving player on either side carries a Trade Value entry.
    var tradeValueNet: Double? = nil

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
            if let net = tradeValueNet {
                rollupCell(label: "Trade Value",
                           value: String(format: "%+.1fM", net / 1_000_000),
                           color: dollarColor(Int(net)))
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
    let teams: [TradeConfirmation.TeamPackage]
    let peakTimeline: PeakTimelineForecast?

    private var hasChemistry: Bool { teams.contains { $0.chemistry != nil } }
    private var hasPeak: Bool {
        guard let p = peakTimeline else { return false }
        return p.peakStartSeason != nil && p.peakEndSeason != nil
    }

    var body: some View {
        // Only render tiles that actually have data — no permanent
        // "Not yet available." dead placeholders at the bottom of the sheet.
        VStack(spacing: 12) {
            if hasChemistry { ChemistryTile(teams: teams) }
            if hasPeak { PeakTimelineTile(peakTimeline: peakTimeline) }
        }
    }
}

private struct ChemistryTile: View {
    let teams: [TradeConfirmation.TeamPackage]

    private var lines: [(tricode: String, chem: LineupChemistryDelta)] {
        teams.compactMap { pkg in
            pkg.chemistry.map { (pkg.team.tricode, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Role chemistry", systemImage: "person.2.circle")
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.tricode) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.tricode)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    Text(line.chem.summaryLine)
                        .font(.caption)
                        .foregroundStyle(chemColor(line.chem.delta))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(line.tricode) starters: \(line.chem.summaryLine)")
            }
            Text("Resulting-starters fit vs. today.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func chemColor(_ delta: Double?) -> Color {
        guard let d = delta else { return .primary }
        if d > 0.15 { return .green }
        if d < -0.15 { return .red }
        return .primary
    }
}

// MARK: - Trade Grade header

private struct TradeGradeHeader: View {
    /// nil → the grade couldn't be computed (renders an explicit placeholder
    /// rather than vanishing).
    let grade: TradeGrade?

    var body: some View {
        HStack(spacing: 14) {
            Text(grade?.letter ?? "—")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(letterColor)
                .frame(minWidth: 56)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(letterColor.opacity(0.18))
                )
                .accessibilityHidden(true)   // spoken in the combined label
            VStack(alignment: .leading, spacing: 3) {
                Text("Fairness Grade")
                    .font(.caption).foregroundStyle(.secondary)
                Text(grade?.verdict ?? "Grade unavailable")
                    .font(.headline)
                Text(caption)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(letterColor.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var letterColor: Color {
        guard let g = grade else { return .secondary }
        return Self.color(for: g.letter)
    }

    /// Monotone good→bad ramp, distinct from the per-player `TradeTierBadge`
    /// palette so A→F reads as one worsening gradient and F is the most
    /// alarming (never calmer than D).
    private static func color(for letter: String) -> Color {
        switch letter.first {
        case "A": return .green
        case "B": return .mint
        case "C": return .orange
        case "D": return Color(red: 0.85, green: 0.30, blue: 0.10)   // deep orange
        default:  return .red                                         // F
        }
    }

    private var caption: String {
        guard let g = grade else {
            return "Player values not loaded for this trade."
        }
        return g.approximate
            ? "Comp-Z asset balance · excludes picks, cash & unpriced players."
            : "Comp-Z asset balance across both sides."
    }

    private var a11yLabel: String {
        guard let g = grade else {
            return "Fairness grade unavailable — player values not loaded."
        }
        let spoken = g.letter == "A+" ? "A plus" : g.letter
        return "Fairness grade \(spoken). \(g.verdict)."
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
                Text("Not yet available.")
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
