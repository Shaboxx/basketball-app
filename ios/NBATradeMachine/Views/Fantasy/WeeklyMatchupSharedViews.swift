import SwiftUI

/// Shared weekly-mode subviews used by both `FantasyLeagueDetailView` (local) and
/// `HostedLeagueDetailView` (hosted). All are pure-value inputs — no `@EnvironmentObject`
/// or @MainActor coupling — so they compose identically in both contexts.

// MARK: - WeeklyMatchupRow

/// A schedule row for weekly mode: shows team names plus the outcome chip or status badge.
/// Tapping fires `onTap(weekIndex, pairing)` so the parent can open the matchup detail sheet.
struct WeeklyMatchupRow: View {
    let pairing: FantasyMatchupPairing
    let weekIndex: Int
    let homeName: String
    let awayName: String
    let outcome: FantasyWeekOutcome?
    let onTap: (Int, FantasyMatchupPairing) -> Void

    var body: some View {
        let status = outcome?.status ?? .future
        Button {
            onTap(weekIndex, pairing)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(homeName)  vs  \(awayName)")
                        .foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    WeeklyMatchupChip(pairing: pairing, outcome: outcome, weekStatus: status)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WeeklyMatchupChip

/// The inline status / outcome chip shown beneath the team-name line.
struct WeeklyMatchupChip: View {
    let pairing: FantasyMatchupPairing
    let outcome: FantasyWeekOutcome?
    let weekStatus: FantasyWeekStatus

    var body: some View {
        switch weekStatus {
        case .future:
            Text("Projected")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(.secondary)

        case .current:
            if let mo = matchupOutcome {
                if mo.status == .pending {
                    Text("Awaiting stats").font(.caption2).foregroundStyle(.orange)
                } else if let result = mo.result {
                    HStack(spacing: 4) {
                        MatchupResultChip(result: result)
                        Text("In progress").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("In progress").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("In progress").font(.caption2).foregroundStyle(.secondary)
            }

        case .completed:
            if let mo = matchupOutcome {
                if mo.status == .pending {
                    Text("Awaiting stats").font(.caption2).foregroundStyle(.orange)
                } else if let result = mo.result {
                    MatchupResultChip(result: result)
                } else {
                    Text("Awaiting stats").font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Text("Awaiting stats").font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var matchupOutcome: FantasyMatchupOutcome? {
        outcome?.matchupOutcomes.first(where: { $0.pairing == pairing })
    }
}

// MARK: - MatchupResultChip

/// Category tally "6-3" or weekly fp totals chip, styled green/red for the winner.
struct MatchupResultChip: View {
    let result: FantasyMatchupResult

    var body: some View {
        Group {
            if result.isPoints {
                HStack(spacing: 2) {
                    Text(String(format: "%.0f", result.homePoints))
                        .foregroundStyle(result.outcome == .home ? .green :
                                         result.outcome == .away ? .red : .primary)
                    Text("–").foregroundStyle(.secondary)
                    Text(String(format: "%.0f", result.awayPoints))
                        .foregroundStyle(result.outcome == .away ? .green :
                                         result.outcome == .home ? .red : .primary)
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
            } else {
                HStack(spacing: 2) {
                    Text("\(result.homeCategoryWins)")
                        .foregroundStyle(result.outcome == .home ? .green :
                                         result.outcome == .away ? .red : .primary)
                    Text("–").foregroundStyle(.secondary)
                    Text("\(result.awayCategoryWins)")
                        .foregroundStyle(result.outcome == .away ? .green :
                                         result.outcome == .home ? .red : .primary)
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
            }
        }
    }
}

// MARK: - WeeklyStandingRow

/// One standings row for weekly mode. `teamName` is a closure so both local (UUID lookup via
/// store) and hosted (UUID lookup via nameByUuid dict) can supply the right resolver.
struct WeeklyStandingRow: View {
    let rank: Int
    let teamId: UUID
    let record: FantasyRecord
    let pointsScoring: Bool
    let teamName: (UUID) -> String

    var body: some View {
        HStack {
            Text("\(rank)").frame(width: 24, alignment: .leading)
            Text(teamName(teamId))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            Text("\(record.wins)-\(record.losses)-\(record.ties)")
                .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 64, alignment: .trailing)
            if pointsScoring {
                Text(String(format: "%.0f", record.pointsFor))
                    .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Text("\(record.categoryWins)-\(record.categoryLosses)")
                    .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}
