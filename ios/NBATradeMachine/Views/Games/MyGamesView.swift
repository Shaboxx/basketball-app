import SwiftUI

/// A typed nav route so MyGames' launch destination doesn't collide with the
/// hub's `navigationDestination(for: String.self)` (which routes registry ids to
/// GameSetupView). A dedicated Hashable value resolves to MyGames' own handler.
nonisolated struct MyGameRoute: Hashable { let draftId: String }

/// Lists the user's saved custom games (GameDrafts) and launches them through the
/// SAME gameplay views as shipped presets, via `GameDraft.toLaunch()`. A Create
/// button opens the wizard; swipe-to-delete removes a game. Surfaced from
/// GamesHubView.
struct MyGamesView: View {
    @EnvironmentObject var creatorStore: GameCreatorStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GameCreatorView()
                } label: {
                    Label("Create a Game", systemImage: "plus.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

            if creatorStore.myGames.isEmpty {
                Section {
                    ContentUnavailableView("No custom games yet",
                                           systemImage: "square.grid.2x2",
                                           description: Text("Tap “Create a Game” to build one."))
                }
            } else {
                Section("My Games") {
                    ForEach(creatorStore.myGames) { draft in
                        NavigationLink(value: MyGameRoute(draftId: draft.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.title.isEmpty ? "Untitled" : draft.title)
                                    .font(.subheadline.bold())
                                Text(draft.family.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { creatorStore.myGames[$0].id }.forEach(creatorStore.delete)
                    }
                }
            }
        }
        .navigationTitle("My Games")
        .navigationDestination(for: MyGameRoute.self) { route in
            if let draft = creatorStore.myGames.first(where: { $0.id == route.draftId }) {
                MyGameLaunchView(draft: draft)
            }
        }
        .onAppear { creatorStore.reload() }
    }
}

/// Resolves a saved draft to its gameplay view (the SAME views presets use).
private struct MyGameLaunchView: View {
    let draft: GameDraft

    var body: some View {
        switch draft.toLaunch() {
        case .roster(let def):
            RosterDraftView(definition: def, settings: .default)
        case .classification(let def):
            ClassificationView(definition: def)
        case .compare(let def):
            CompareView(definition: def)
        case .bracket(let def):
            BracketView(definition: def)
        case .guess, .quiz, .survivor, .grid, .connection, .none:
            // GameDraft (creator) never authors Phase-5/6 single-player families, so
            // these are unreachable from a saved draft — show the unavailable view.
            ContentUnavailableView("Can't launch this game",
                                   systemImage: "exclamationmark.triangle")
        }
    }
}
