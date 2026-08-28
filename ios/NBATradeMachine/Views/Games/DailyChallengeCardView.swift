import SwiftUI

/// The Daily + Weekly challenge cards at the top of the Games hub (spec §8). Each
/// Play button dispatches through the challenge's launch into the matching
/// gameplay View — no new engine. Reuses the hub's badge styling.
struct DailyChallengeCardView: View {
    @EnvironmentObject var dailyStore: DailyChallengeStore
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    // The launched gameplay views (RosterDraftView/CompareView/ClassificationView/
    // BracketView) read these; a pushed NavigationLink destination does NOT inherit
    // env objects here, so they must be re-injected onto the destination (below).
    // Both are injected at the ContentView root, so reading them here is safe.
    @EnvironmentObject var playersVM: PlayersViewModel
    @EnvironmentObject var teamsVM: TeamsViewModel

    var body: some View {
        VStack(spacing: 10) {
            ChallengeRow(challenge: dailyStore.daily,
                         played: dailyStore.hasPlayed(dailyStore.daily),
                         icon: "sun.max.fill", tint: .orange,
                         historicalStore: historicalStore,
                         playersVM: playersVM, teamsVM: teamsVM,
                         onPlay: { dailyStore.markPlayed(dailyStore.daily) })
            ChallengeRow(challenge: dailyStore.weekly,
                         played: dailyStore.hasPlayed(dailyStore.weekly),
                         icon: "calendar", tint: .blue,
                         historicalStore: historicalStore,
                         playersVM: playersVM, teamsVM: teamsVM,
                         onPlay: { dailyStore.markPlayed(dailyStore.weekly) })
        }
        .padding(.vertical, 6)
        .onAppear { dailyStore.refresh() }
    }
}

private struct ChallengeRow: View {
    let challenge: DailyChallenge
    let played: Bool
    let icon: String
    let tint: Color
    let historicalStore: HistoricalPoolStore
    let playersVM: PlayersViewModel
    let teamsVM: TeamsViewModel
    let onPlay: () -> Void

    var body: some View {
        NavigationLink {
            ChallengeLaunchView(challenge: challenge)
                .environmentObject(historicalStore)
                .environmentObject(playersVM)   // destinations don't inherit env
                .environmentObject(teamsVM)
                .onAppear(perform: onPlay)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title).font(.subheadline.bold())
                    Text(challenge.cadence == .daily ? "New every day" : "New every week")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(played ? "Played" : "Play")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((played ? Color.gray : tint).opacity(0.2), in: Capsule())
                    .foregroundStyle(played ? .gray : tint)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

/// Resolves a challenge to its gameplay view (the SAME views presets use).
private struct ChallengeLaunchView: View {
    let challenge: DailyChallenge

    var body: some View {
        switch challenge.toLaunch() {
        case .roster(let def):
            // Daily/weekly challenges are single-player builds against the live pool.
            // Thread the challenge's canonical seed (Sol fix 1) so every device plays
            // the SAME entities today, not just the same Definition.
            RosterDraftView(definition: def, settings: .default, seed: challenge.seed)
        case .classification(let def):
            ClassificationView(definition: def, seed: challenge.seed)
        case .compare(let def):
            CompareView(definition: def, seed: challenge.seed)
        case .bracket(let def):
            BracketView(definition: def, seed: challenge.seed)
        case .guess, .quiz, .survivor, .grid, .connection, .none:
            // Phase-5/6 single-player families aren't part of the daily rotation →
            // unreachable from a challenge, but keep the switch exhaustive.
            ContentUnavailableView("Can't start today's challenge",
                                   systemImage: "exclamationmark.triangle")
        }
    }
}
