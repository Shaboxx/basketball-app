import SwiftUI

/// Live gameplay for a Higher/Lower game. Two player cards; tap the one you think
/// wins the metric. Correct → streak++ and a new pair; wrong → game over.
struct CompareView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    let definition: CompareDefinition

    @State private var store: CompareStore?
    @State private var launchFailed = false

    var body: some View {
        Group {
            if let store {
                CompareContent(store: store)
            } else if launchFailed {
                ContentUnavailableView("Can't start this game",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Not enough players with this stat."))
            } else {
                ProgressView("Loading players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: launchIfReady)
        .onReceive(playersVM.$players) { _ in launchIfReady() }
    }

    private func launchIfReady() {
        guard store == nil, !launchFailed, !playersVM.players.isEmpty else { return }
        let pool = GamePoolBuilder.pool(from: playersVM.players)
        // R10: the only failure is notEnoughComparable (transient) — leave store
        // nil and retry when PlayersViewModel republishes a fuller roster; never
        // latch a permanent failure for a data-availability blip.
        let state = try? CompareEngine.initialize(
            definition: definition, pool: pool,
            seed: UInt64.random(in: UInt64.min...UInt64.max))
        store = state.map(CompareStore.init)
    }
}

private struct CompareContent: View {
    @ObservedObject var store: CompareStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @State private var revealed = false
    @State private var revealTask: Task<Void, Never>?   // R12: cancellable reveal

    private var teamNames: [String: String] {
        Dictionary(teamsVM.teams.map { ($0.teamId, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    private func teamLabel(_ id: String) -> String { teamNames[id] ?? id }
    private var metric: CompareMetric { store.state.definition.config.metric }

    var body: some View {
        content
            .onDisappear { revealTask?.cancel() }   // R12
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .finished(let score):
            VStack(spacing: 12) {
                Image(systemName: "flag.checkered").font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Streak: \(score)").font(.largeTitle.bold())
                Text("Game over").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .guessing:
            guessing
        }
    }

    private var guessing: some View {
        VStack(spacing: 16) {
            Text("Streak: \(store.state.score)").font(.headline)
            Text(metric.prompt).font(.title3.bold()).multilineTextAlignment(.center)
            ForEach(store.state.pair, id: \.self) { id in
                if let e = store.state.entity(id) {
                    Button {
                        guard !revealed else { return }
                        revealed = true
                        revealTask = Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            guard !Task.isCancelled else { return }
                            store.guess(subjectId: id)
                            revealed = false
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(e.name).font(.title3.bold())
                            Text("\(teamLabel(e.team)) · \(e.position)")
                                .font(.caption).foregroundStyle(.secondary)
                            if revealed {
                                Text(metric.format(e))
                                    .font(.title2.monospacedDigit().bold())
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(revealed)
                }
            }
            Spacer()
        }
        .padding()
    }
}
