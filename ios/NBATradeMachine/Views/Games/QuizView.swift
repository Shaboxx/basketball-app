import SwiftUI

/// Live gameplay for a QUIZ game (Phase 5). Renders a seeded question stem with
/// seeded multiple-choice buttons (Sol Q2a). Progress + finished(score) card.
/// Follows CompareView's launch protocol (current) / HistoricalRosterDraftView's
/// (historical), branching on `poolSource`.
struct QuizView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let definition: QuizDefinition
    var seed: UInt64? = nil

    @State private var store: QuizStore?
    @State private var launchFailed = false

    private var isHistorical: Bool {
        if case .historical = definition.poolSource { return true }
        return false
    }

    var body: some View {
        Group {
            if let store {
                QuizContent(store: store)
            } else if launchFailed {
                ContentUnavailableView("Can't start this quiz",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Not enough data to build questions."))
            } else if isHistorical, historicalStore.phase == .failed {
                ContentUnavailableView {
                    Label("Couldn't load historical players", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The historical dataset failed to load.")
                } actions: {
                    Button("Try Again") { Task { await historicalStore.load() } }
                }
            } else {
                ProgressView("Loading quiz…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if isHistorical { await historicalStore.load() } }
        .onAppear(perform: launchIfReady)
        .onReceive(playersVM.$players) { _ in if !isHistorical { launchIfReady() } }
        .onChange(of: historicalStore.phase) { _, newPhase in
            if isHistorical, newPhase == .loaded { launchIfReady() }
        }
    }

    private func launchIfReady() {
        guard store == nil, !launchFailed else { return }
        let pool: [GameEntityRecord]
        switch definition.poolSource {
        case .current:
            if playersVM.players.isEmpty {
                // Still loading: keep spinning. Loaded-but-empty: latch failure.
                if playersVM.hasLoaded { launchFailed = true }
                return
            }
            pool = GamePoolBuilder.pool(from: playersVM.players)
            // A built-but-empty pool is a terminal config failure when the roster is done.
            if pool.isEmpty {
                if playersVM.hasLoaded { launchFailed = true }
                return
            }
        case .historical(let filter):
            guard historicalStore.phase == .loaded else { return }
            pool = historicalStore.pool(for: filter)
        }
        // Historical loaded-but-empty pool is a terminal config failure (latch, don't spin).
        guard !pool.isEmpty else { launchFailed = true; return }
        do {
            let state = try QuizEngine.initialize(
                definition: definition, pool: pool,
                seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = QuizStore(state: state)
        } catch {
            launchFailed = true
        }
    }
}

private struct QuizContent: View {
    @ObservedObject var store: QuizStore

    var body: some View {
        switch store.phase {
        case .finished(let score):
            finished(score: score)
        case .answering:
            answering
        }
    }

    @ViewBuilder
    private var answering: some View {
        if let q = store.state.currentQuestion {
            VStack(spacing: 16) {
                Text("Question \(store.state.currentIndex + 1) of \(store.state.questions.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(q.stem).font(.title3.bold())
                    .multilineTextAlignment(.center)
                ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, label in
                    Button {
                        store.answer(choiceIndex: idx)
                    } label: {
                        Text(label)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Score: \(store.state.score)").font(.headline)
            }
            .padding()
        } else {
            ProgressView()
        }
    }

    private func finished(score: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.checkered").font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("\(score) / \(store.state.questions.count)")
                .font(.system(size: 48, weight: .bold))
            Text("correct").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
