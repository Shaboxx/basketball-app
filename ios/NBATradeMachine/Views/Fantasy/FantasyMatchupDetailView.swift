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
    let customCategories: [FantasyLeagueCategory]?
    let nameFor: (UUID) -> String
    let isLive: Bool
    /// Dream Team leagues score on raw ownership-divided stats (like live) — the bars
    /// need league-SD normalization, not the projected z-window.
    var dreamTeam: Bool = false
    /// When true, `productions` holds weekly aggregated TOTALS (pts 52 vs 47 etc.) rather
    /// than season-to-date per-game rates. The detail view renders raw integer totals in the
    /// subtitle rows instead of z-scores, and the footer reflects the real-week context.
    var weeklyTotalsMode: Bool = false
    /// The status of the week this matchup belongs to (nil when not in weekly mode).
    var weekStatus: FantasyWeekStatus? = nil

    /// Raw-scale productions (live OR Dream Team) — normalize bars by the league spread.
    private var rawScale: Bool { isLive || dreamTeam }

    private var result: FantasyMatchupResult {
        FantasyMatchupScoring.score(home: pairing.home, away: pairing.away,
                                    productions: productions, format: format,
                                    customCategories: customCategories)
    }
    private var homeName: String { nameFor(pairing.home) }
    private var awayName: String { nameFor(pairing.away) }

    var body: some View {
        NavigationStack {
            List {
                Section { header }

                if result.isPoints {
                    let ptsSectionTitle = weeklyTotalsMode ? "Fantasy Points (Week)" : "Fantasy Points / Game"
                    Section(ptsSectionTitle) { pointsCard }
                } else {
                    let catSectionTitle = weeklyTotalsMode ? "Categories (Week Totals)" : "Categories"
                    Section(catSectionTitle) {
                        ForEach(result.lines, id: \.category) { line in categoryRow(line) }
                    }
                }

                Section {
                    Text(footerText)
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
            if weeklyTotalsMode, let status = weekStatus {
                switch status {
                case .current:
                    Label("In progress", systemImage: "clock")
                        .font(.caption).foregroundStyle(.orange)
                case .completed:
                    Label("Completed week", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                case .future:
                    Label("Projected", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
                if weeklyTotalsMode {
                    Text("pts this week").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text(awayName).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f", result.awayPoints)).font(.title3.monospacedDigit())
                if weeklyTotalsMode {
                    Text("pts this week").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Bar value for one category line. Projected standard productions are z-sums, so
    /// their diff already lives on CategoryBarRow's ±3σ window. Raw-scale productions
    /// (live, or Dream Team's ownership-divided totals) are per-game rates — normalize
    /// the diff by the league's per-category spread so every category renders comparably.
    private func barValue(_ line: FantasyCategoryLine) -> Double {
        let diff = line.homeZ - line.awayZ
        guard rawScale else { return diff }
        let sd = FantasyCategoryScale.sd(productions: Array(productions.values),
                                         category: line.category)
        return FantasyCategoryScale.normalizedDiff(diff, sd: sd)
    }

    private var footerText: String {
        if dreamTeam {
            return "Dream Team — shared players' counting stats are split by ownership, so these totals already reflect the split. \(isLive ? "Live season-to-date." : "Projected season-long.")"
        }
        if weeklyTotalsMode {
            switch weekStatus {
            case .current:
                return "In progress — these are live week-to-date totals. They will update as more games are played this week."
            case .completed:
                return "Completed week — totals reflect all games played during this calendar week."
            default:
                return "Weekly totals for this matchup week."
            }
        }
        return isLive
            ? "Live — season-to-date production; totals are static, so the result is the same every meeting."
            : "Projected — this matchup is the same every time these teams meet until live scoring is available."
    }

    @ViewBuilder private func categoryRow(_ line: FantasyCategoryLine) -> some View {
        VStack(spacing: 2) {
            CategoryBarRow(label: line.category.label, z: barValue(line))
            HStack {
                Text(weeklyTotalsMode
                     ? formatWeeklyTotal(line.homeZ, category: line.category)
                     : String(format: "%.2f", line.homeZ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(line.outcome == .home ? .green : .secondary)
                Spacer()
                Text(weeklyTotalsMode
                     ? formatWeeklyTotal(line.awayZ, category: line.category)
                     : String(format: "%.2f", line.awayZ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(line.outcome == .away ? .green : .secondary)
            }
        }
    }

    /// Format a weekly-total value for display. Counting stats are whole numbers; FG%/FT% are
    /// ratios; TO was sign-flipped (stored as -Σtov so higher is better) — we display it as
    /// the raw positive turnover count (negate back) for legibility.
    private func formatWeeklyTotal(_ value: Double, category: FantasyLeagueCategory) -> String {
        switch category {
        case .fgPct, .ftPct:
            return String(format: "%.1f%%", value * 100)
        case .to:
            // value == -Σtov (engine convention: higher is better); display as positive count
            return String(format: "%.0f", -value)
        default:
            return String(format: "%.0f", value)
        }
    }
}
