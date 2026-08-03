import SwiftUI

/// The Games hub: a vertical list of full-width cards, one per registry entry.
/// Each card shows an icon + title + subtitle + a status badge
/// (Available / Seasonal / Coming Soon). Playable cards navigate to `GameSetupView`;
/// disabled cards render the badge and do not navigate. Owns its own NavigationStack
/// so it drops into either SP1 wiring unchanged.
struct GamesHubView: View {
    @EnvironmentObject var setupStore: GameSetupStore
    @State private var path = NavigationPath()

    /// `now` for availability resolution — the current wall-clock at render.
    /// (Pure resolution lives in `GameAvailability.resolve(now:)`; passing it here
    /// keeps the view thin and the logic testable.)
    private let now = Date()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(DraftGameRegistry.all) { game in
                    let state = game.availability.resolve(now: now)
                    if state.isPlayable {
                        NavigationLink(value: game.id) {
                            GameCard(game: game, state: state)
                        }
                    } else {
                        GameCard(game: game, state: state)   // no navigation
                    }
                }
            }
            .navigationTitle("Games")
            .navigationDestination(for: String.self) { gameId in
                if let game = DraftGameRegistry.game(gameId) {
                    GameSetupView(game: game)
                        .environmentObject(setupStore)   // sheets/destinations don't inherit env
                }
            }
        }
    }
}

/// One hub card: icon + title + one-line subtitle + trailing status badge.
private struct GameCard: View {
    let game: DraftGame
    let state: AvailabilityState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: game.systemImage)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(state.isPlayable ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).font(.subheadline.bold())
                Text(game.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            badge
        }
        .opacity(state.isPlayable ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        let (label, tint): (String, Color) = {
            switch state.badge {
            case .available:  return ("Available", .green)
            case .seasonal:   return (state.isPlayable ? "Open" : "Seasonal", .orange)
            case .comingSoon: return ("Coming Soon", .gray)
            }
        }()
        return Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.2), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview {
    GamesHubView().environmentObject(GameSetupStore())
}
