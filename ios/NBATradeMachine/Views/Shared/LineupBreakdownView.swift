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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let label, !label.isEmpty {
                    archetypeHeader(label)
                    rosterStrip
                    tagsSection(label)
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

    // MARK: - Roster strip

    private var rosterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(players) { p in
                NavigationLink(value: p) {
                    HStack(spacing: 8) {
                        HeadshotImage(slug: p.slug, size: 28)
                        Text(p.name).font(.subheadline)
                        Spacer()
                        Text(p.position).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
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
private struct FlowLayout: Layout {
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
