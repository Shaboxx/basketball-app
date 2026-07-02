import SwiftUI

/// Per-category head-to-head breakdown for ONE scheduled matchup. Pure presentation of
/// the engine result — plain-value inputs (the resolved productions map, the active
/// format, the pairing, a name resolver), NOT env objects, so it never re-resolves.
/// Category formats: one `CategoryBarRow` per category (home − away z), flanked by the
/// raw z values with a green tint on the winning side. Points formats: the two fp/game
/// totals. A nuance footer states the projected result is identical every meeting.
struct FantasyMatchupDetailView: View {
    let pairing: FantasyMatchupPairing
    let productions: [UUID: FantasyTeamProduction]
    let format: FantasyFormat
    let nameFor: (UUID) -> String
    let isLive: Bool

    private var result: FantasyMatchupResult {
        FantasyMatchupScoring.score(home: pairing.home, away: pairing.away,
                                    productions: productions, format: format)
    }
    private var homeName: String { nameFor(pairing.home) }
    private var awayName: String { nameFor(pairing.away) }

    var body: some View {
        NavigationStack {
            List {
                Section { header }

                if result.isPoints {
                    Section("Fantasy Points / Game") { pointsCard }
                } else {
                    Section("Categories") {
                        ForEach(result.lines, id: \.category) { line in categoryRow(line) }
                    }
                }

                Section {
                    Text(isLive
                         ? "Live — season-to-date production; totals are static, so the result is the same every meeting."
                         : "Projected — this matchup is the same every time these teams meet until live scoring is available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Matchup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.isPoints {
                Text("\(homeName)  \(String(format: "%.1f", result.homePoints)) — \(String(format: "%.1f", result.awayPoints))  \(awayName)")
                    .font(.headline)
            } else {
                Text("\(homeName)  \(result.homeCategoryWins) — \(result.awayCategoryWins)  \(awayName)")
                    .font(.headline)
                if result.categoryTies > 0 {
                    Text("\(result.categoryTies) categor\(result.categoryTies == 1 ? "y" : "ies") tied")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(winnerLine).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var winnerLine: String {
        switch result.outcome {
        case .home: return "Winner: \(homeName)"
        case .away: return "Winner: \(awayName)"
        case .tie:  return "Tie"
        }
    }

    @ViewBuilder private var pointsCard: some View {
        HStack {
            VStack(spacing: 2) {
                Text(homeName).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f", result.homePoints)).font(.title3.monospacedDigit())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(awayName).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f", result.awayPoints)).font(.title3.monospacedDigit())
            }
        }
    }

    /// Bar value for one category line. Projected productions are z-sums, so their diff
    /// already lives on CategoryBarRow's ±3σ window. Live productions are RAW per-game
    /// rates — normalize the diff by the league's per-category spread so every category
    /// renders comparably (the flanking numbers stay raw season-to-date rates).
    private func barValue(_ line: FantasyCategoryLine) -> Double {
        let diff = line.homeZ - line.awayZ
        guard isLive else { return diff }
        let sd = FantasyCategoryScale.sd(productions: Array(productions.values),
                                         category: line.category)
        return FantasyCategoryScale.normalizedDiff(diff, sd: sd)
    }

    @ViewBuilder private func categoryRow(_ line: FantasyCategoryLine) -> some View {
        VStack(spacing: 2) {
            CategoryBarRow(label: line.category.label, z: barValue(line))
            HStack {
                Text(String(format: "%.2f", line.homeZ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(line.outcome == .home ? .green : .secondary)
                Spacer()
                Text(String(format: "%.2f", line.awayZ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(line.outcome == .away ? .green : .secondary)
            }
        }
    }
}
