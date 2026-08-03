import SwiftUI

/// The Start destination for a game whose rules are not built yet. Shows the
/// game's identity + an honest "Gameplay coming soon" message. No simulated play.
struct GamePlaceholderView: View {
    let game: DraftGame
    let settings: GameSetupSettings

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: game.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(game.title)
                .font(.title2.bold())
            Text("Gameplay coming soon")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("\(settings.humanCount) player\(settings.humanCount == 1 ? "" : "s") · "
                 + "\(settings.cpuCount) CPU\(settings.cpuCount == 1 ? "" : "s") · "
                 + settings.playMode.displayName)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GamePlaceholderView(game: DraftGameRegistry.all[0], settings: .default)
    }
}
