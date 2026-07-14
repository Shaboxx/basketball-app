import SwiftUI

/// Generated breakdown page for one depth-chart layer's five-man lineup. Renders
/// the resolved archetype headline, the firing tags grouped by category as
/// chips (proxy tags marked), and Strengths / Weaknesses as bulleted lists.
/// Compact, scrollable, phone-friendly. Tapping a player row → PlayerDetailView.
///
/// When norms are unavailable (doc unloaded/missing) or no player on the layer
/// carries a feature record, it shows an "unavailable" message instead of
/// crashing.
struct LineupBreakdownView: View {
    let players: [Player]
    let norms: LeagueNorms?
    let impacts: [Double?]
    var tier: String = "starters"

    private var label: LineupLabel? {
        guard let norms else { return nil }
        return LineupLabeler.label(players: players, norms: norms,
                                   tier: tier, impacts: impacts)
    }

    /// Written analysis (basic headlines + detail), narrated client-side from the
    /// already-computed `label` + each player's features. nil when there are no
    /// features to narrate from.
    private func report(for label: LineupLabel) -> LineupSuggestionReport? {
        guard let norms, !label.isEmpty else { return nil }
        let r = LineupNarrator.narrate(players: players, norms: norms, label: label)
        return r.basic.isEmpty ? nil : r
    }

    var body: some View {
        let label = self.label   // compute the label engine once per render
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let label, !label.isEmpty {
                    archetypeHeader(label)
                    rosterStrip
                    analysisSection(report(for: label))
                    tagsSection(label)
                    formationsSection(label)
                    capabilitiesSection(label)
                    if AppConfig.matchupsEnabled {
                        shotGeographySection
                    }
                    strengthsSection(label)
                    weaknessesSection(label)
                } else {
                    unavailable
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Lineup Breakdown")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private func archetypeHeader(_ label: LineupLabel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Archetype").font(.caption).foregroundStyle(.secondary)
            Text(label.archetypeLabel)
                .font(.largeTitle.bold())
        }
    }

    // MARK: - Written analysis (narrated client-side by LineupNarrator)

    /// The prose layer: always-visible `basic` headlines + an expandable
    /// per-category `detail` breakdown (grade / tags / explanation). Renders
    /// nothing when there is no narration for this five.
    @ViewBuilder
    private func analysisSection(_ report: LineupSuggestionReport?) -> some View {
        if let report, !report.basic.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Analysis").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.basic, id: \.self) { line in
                        basicRow(line)
                    }
                }
                if hasDetail(report) {
                    DisclosureGroup {
                        detailBody(report).padding(.top, 6)
                    } label: {
                        Text("Detailed breakdown").font(.subheadline.weight(.semibold))
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private func basicRow(_ line: SuggestionLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(analysisColor(line.category))
                .frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text).font(.subheadline)
                // Conservative-negative: a low-confidence finding is flagged as
                // tentative so a thin sample never reads as a hard verdict.
                if line.confidence == "low" {
                    Text("tentative — limited sample")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hasDetail(_ report: LineupSuggestionReport) -> Bool {
        SuggestionCategory.order.contains { !(report.detail[$0]?.isEmpty ?? true) }
    }

    private func detailBody(_ report: LineupSuggestionReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(SuggestionCategory.order, id: \.self) { cat in
                let items = report.detail[cat] ?? []
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(SuggestionCategory.title(cat))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(items, id: \.self) { item in
                            detailItem(item)
                        }
                    }
                }
            }
        }
    }

    private func detailItem(_ item: SuggestionDetail) -> some View {
        // Conservative-negative: a low-confidence finding never shows a hard
        // (e.g. red "Poor") verdict — the grade pill is desaturated to gray and a
        // "tentative" caption is appended, matching the basic-row treatment.
        let tentative = item.confidence == "low"
        return VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 6) {
                if let grade = item.grade {
                    let color = tentative ? Color.gray : gradeColor(grade)
                    Text(grade)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(color.opacity(0.18), in: Capsule())
                        .foregroundStyle(color)
                }
                ForEach(item.tags ?? [], id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .foregroundStyle(.secondary)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            if let explanation = item.explanation, !explanation.isEmpty {
                Text(explanation).font(.footnote).foregroundStyle(.secondary)
            }
            if tentative {
                Text("tentative — limited sample")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func analysisColor(_ category: String) -> Color {
        switch category {
        case "offense": return .orange
        case "defense": return .blue
        case "structure": return .purple
        case "tempo": return .teal
        default: return .gray
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade.lowercased() {
        case "elite", "great", "good": return .green
        case "poor", "bad", "weak": return .red
        default: return .gray
        }
    }

    // MARK: - Roster strip

    private var rosterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(players) { p in
                NavigationLink(value: p) {
                    HStack(spacing: 8) {
                        HeadshotImage(slug: p.slug, size: 28)
                        Text(p.name).font(.subheadline)
                        Spacer()
                        valueBadge(p)
                        Text(p.position).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - SP-C: marginal value, formation viability, capability magnitudes

    /// All roster players share a team; the marginal-value badge is the player's value to it.
    private var teamId: String? { players.first?.teamId }

    @ViewBuilder private func valueBadge(_ p: Player) -> some View {
        if let tri = teamId, let v = p.rosterValue?.value(for: tri) {
            Text("$\(v / 1_000_000, specifier: "%.1f")M")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.18), in: Capsule())
                .foregroundStyle(Color.green)
        }
    }

    private func formationsSection(_ label: LineupLabel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Formations").font(.headline)
            let order = LineupFormations.formations
            chipRow(order.filter { label.formationsViable[$0] == true }, enabled: true)
            chipRow(order.filter { label.formationsViable[$0] != true }, enabled: false)
        }
    }

    private func chipRow(_ keys: [String], enabled: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Text(formationLabel(key))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(enabled ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12), in: Capsule())
                    .foregroundStyle(enabled ? Color.accentColor : .secondary)
            }
        }
    }

    private func capabilitiesSection(_ label: LineupLabel) -> some View {
        let order: [(String, Bool)] = [("spacing", true), ("pnr_fit", true), ("creation_redundancy", true),
                                       ("switchable", false), ("rim_protection", false)]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Capabilities").font(.headline)
            ForEach(order, id: \.0) { key, isOffense in
                let v = label.capabilityMagnitudes[key] ?? 0
                HStack {
                    Text(capabilityLabel(key)).font(.caption).frame(width: 120, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(isOffense ? Color.orange.opacity(0.6) : Color.blue.opacity(0.6))
                            .frame(width: min(geo.size.width, max(2, abs(v) / 10.0 * geo.size.width)), height: 8)
                    }.frame(height: 8)
                    Text(String(format: "%.1f", v)).font(.caption2).foregroundStyle(.secondary).frame(width: 36)
                }
            }
        }
    }

    private func formationLabel(_ k: String) -> String {
        ["five_out": "5-Out", "switch_everything": "Switch", "two_big_drop": "Two-Big Drop",
         "pnr_heavy": "PnR-Heavy"][k] ?? k
    }
    private func capabilityLabel(_ k: String) -> String {
        ["spacing": "Spacing", "pnr_fit": "PnR Fit", "creation_redundancy": "Creation Overlap",
         "switchable": "Switchability", "rim_protection": "Rim Protection"][k] ?? k
    }

    // MARK: - Tags grouped by category

    private static let categoryTitles: [String: String] = [
        "offense": "Offensive",
        "defense": "Defensive",
        "possession": "Possession / Physical",
        "liability": "Liabilities",
    ]

    @ViewBuilder
    private func tagsSection(_ label: LineupLabel) -> some View {
        if label.tags.isEmpty {
            Text("No descriptive tags fired for this lineup.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tags").font(.headline)
                ForEach(LineupTags.categoryOrder, id: \.self) { cat in
                    let inCat = label.tags.filter { $0.category == cat }
                    if !inCat.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Self.categoryTitles[cat] ?? cat.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            chipFlow(inCat)
                        }
                    }
                }
            }
        }
    }

    private func chipFlow(_ tags: [LineupTag]) -> some View {
        // Simple wrapping layout via a vertical stack of rows is overkill for a
        // handful of chips; a horizontal-wrapping FlowLayout keeps it compact.
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                chip(tag)
            }
        }
    }

    private func chip(_ tag: LineupTag) -> some View {
        HStack(spacing: 4) {
            Text(tag.label)
            if tag.isProxy {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 9))
            }
        }
        .font(.caption2.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(chipForeground(tag.category))
        .background(chipBackground(tag.category), in: Capsule())
    }

    private func chipBackground(_ category: String) -> Color {
        switch category {
        case "offense": return Color.green.opacity(0.18)
        case "defense": return Color.blue.opacity(0.18)
        case "possession": return Color.orange.opacity(0.18)
        case "liability": return Color.red.opacity(0.18)
        default: return Color(.secondarySystemBackground)
        }
    }

    private func chipForeground(_ category: String) -> Color {
        switch category {
        case "offense": return .green
        case "defense": return .blue
        case "possession": return .orange
        case "liability": return .red
        default: return .primary
        }
    }

    // MARK: - Strengths / Weaknesses

    @ViewBuilder
    private func strengthsSection(_ label: LineupLabel) -> some View {
        if !label.strengths.isEmpty {
            bulletSection(title: "Strengths", items: label.strengths, color: .green)
        }
    }

    @ViewBuilder
    private func weaknessesSection(_ label: LineupLabel) -> some View {
        if !label.weaknesses.isEmpty {
            bulletSection(title: "Weaknesses", items: label.weaknesses, color: .red)
        }
    }

    private func bulletSection(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(color).frame(width: 5, height: 5).padding(.top, 6)
                    Text(item).font(.subheadline)
                }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("Lineup breakdown unavailable")
                .font(.headline)
            Text("League norms or player feature data have not loaded for this lineup.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// Minimal wrapping HStack for the tag chips (no external dependency).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGFloat]] = [[]]
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                height += rowHeight + spacing
                rowHeight = 0
                x = 0
                rows.append([])
            }
            rows[rows.count - 1].append(size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
