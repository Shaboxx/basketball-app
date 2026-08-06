import SwiftUI

/// Shared "couldn't load — retry" row for fantasy sections. A fetch failure must be
/// distinguishable from an empty collection (no silent "not available yet"), and the
/// user needs a way to recover a transient network failure without relaunching. The
/// retry funnels back through the store's load-once-with-retry guard.
private struct FantasyRetryRow: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).foregroundStyle(.secondary)
            Button("Retry") { Task { await retry() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.top, 6)
    }
}

// MARK: - Fantasy Value (value + rank [+ fpPerGame] [+ dynasty])

struct FantasyValueSection: View {
    let player: Player
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var appSettings: AppSettings
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            Text("Fantasy Value").font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        let fv = fantasyStore.value(for: player.slug)
        switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: fv) {
        case .loading:
            HStack(spacing: 8) { ProgressView(); Text("Loading fantasy values…").foregroundStyle(.secondary) }
                .padding(.top, 6)
        case .failed:
            FantasyRetryRow(message: "Couldn't load fantasy values.") { await fantasyStore.load() }
        case .collectionEmpty, .playerMissing:
            noDataRow
        case .data:
            if let fv { loaded(fv) } else { noDataRow }   // .data ⇒ non-nil
        }
    }

    @ViewBuilder
    private func loaded(_ fv: FantasyValue) -> some View {
        let fmt = appSettings.fantasyFormat
        let entry = fmt.entry(in: fv)
        VStack(alignment: .leading, spacing: 6) {
            row("Format", fmt.displayName)
            // Cross-format magnitudes aren't comparable — show rank for any framing.
            row("Value", String(format: "%.2f", entry.value))
            row("Rank", entry.rank.map { "#\($0)" } ?? "Unranked")
            if let fp = entry.fpPerGame {
                row("Fantasy pts/game", String(format: "%.1f", fp))
            }
            // Dynasty sub-row needs `_meta.replacement`; hide it gracefully if meta absent.
            if appSettings.dynastyOn, let meta = fantasyStore.meta {
                Divider().padding(.vertical, 4)
                row("Dynasty value",
                    String(format: "%.2f", FantasyValueMath.dynastyAdjustedValue(fv, meta, format: fmt)))
                Text("age \(player.age().map { String($0) } ?? "—") × \(String(format: "%.2f", fv.dynastyFactor))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
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
        Text("Fantasy values not available yet.")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Category Breakdown (signed z over the full 9-vector)

struct CategoryBreakdownSection: View {
    let player: Player
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: fantasyStore.value(for: player.slug)) {
            case .data:
                if let fv = fantasyStore.value(for: player.slug) { content(fv) } else { noDataRow }
            case .failed:
                FantasyRetryRow(message: "Couldn't load fantasy values.") { await fantasyStore.load() }
            default:
                noDataRow
            }
        } label: {
            Text("Category Breakdown").font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func content(_ fv: FantasyValue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(FantasyCategoryOrder.ordered(fv.categoryZ), id: \.label) { item in
                HStack {
                    Text(item.label).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                    categoryBar(z: item.z)
                    Text(String(format: "%+.2f", item.z))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(item.z >= 0 ? .green : .red)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.top, 4)
            }
        }
    }

    /// Bar centered at 0: green right = strength, red left = weakness; clamped at ±3σ.
    private func categoryBar(z: Double) -> some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            // Guard non-finite z: a NaN width traps in CoreGraphics.
            let mag = min(CGFloat(z.isFinite ? abs(z) : 0) / 3.0, 1.0) * half
            ZStack(alignment: .center) {
                Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                Capsule()
                    .fill(z >= 0 ? Color.green : Color.red)
                    .frame(width: mag, height: 6)
                    .offset(x: z >= 0 ? mag / 2 : -mag / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 14)
    }

    private var noDataRow: some View {
        Text("Fantasy values not available yet.")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Projected Box Line (scoringMeans + derived FG%/FT%)

struct FantasyBoxSection: View {
    let player: Player
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: fantasyStore.value(for: player.slug)) {
            case .data:
                if let fv = fantasyStore.value(for: player.slug) { content(fv.scoringMeans) } else { noDataRow }
            case .failed:
                FantasyRetryRow(message: "Couldn't load fantasy values.") { await fantasyStore.load() }
            default:
                noDataRow
            }
        } label: {
            Text("Projected Box Line").font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func content(_ m: FantasyValue.ScoringMeans) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("PTS", String(format: "%.1f", m.pts))
            row("REB", String(format: "%.1f", m.reb))
            row("AST", String(format: "%.1f", m.ast))
            row("STL", String(format: "%.1f", m.stl))
            row("BLK", String(format: "%.1f", m.blk))
            row("TOV", String(format: "%.1f", m.tov))
            row("3PM", String(format: "%.1f", m.fg3m))
            row("FG%", m.fgPct.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
            row("FT%", m.ftPct.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
        }
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
        Text("Fantasy values not available yet.")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Seasonal Outlook (SP-4 Rdur: talent × durability projected season total)

/// Draft/keeper value: the projected full-season fantasy-points total, decomposed into its two
/// validated drivers — talent (last-season fantasy pts/game) and durability (expected games =
/// EB games-played rate × 82). Reads the isolated `fantasySeasonalValues` collection via
/// `FantasyValueStore` (the ubiquitous store); empty-safe until that collection is populated.
struct FantasySeasonalValueSection: View {
    let player: Player
    @EnvironmentObject var fantasyStore: FantasyValueStore   // seasonal data rides on this ubiquitous store
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            Text("Seasonal Outlook").font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        let fsv = fantasyStore.seasonalValue(for: player.slug)
        switch FantasyEmptyState.decide(phase: fantasyStore.seasonalPhase, hasData: fsv != nil) {
        case .loading:
            HStack(spacing: 8) { ProgressView(); Text("Loading seasonal outlook…").foregroundStyle(.secondary) }
                .padding(.top, 6)
        case .failed:
            FantasyRetryRow(message: "Couldn't load seasonal outlook.") { await fantasyStore.load() }
        case .collectionEmpty, .playerMissing:
            noDataRow
        case .data:
            if let fsv { loaded(fsv) } else { noDataRow }   // .data ⇒ non-nil
        }
    }

    @ViewBuilder
    private func loaded(_ fsv: FantasySeasonalValue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Projected fantasy pts (season)", fsv.projectedSeasonTotalText)
            row("Talent (fantasy pts/game)", String(format: "%.1f", fsv.talentFpPerGame))
            row("Expected games", "\(fsv.expectedGamesText) / 82")
            row("Durability", fsv.durabilityBand)
            Text("Season fantasy points = talent × games played. Ranges are the typical (middle-50%) "
                 + "outcome; games played is the big driver of the spread. Draft value; season \(fsv.season).")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
        }
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
        Text("Seasonal outlook not available yet.")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

