import SwiftUI

/// Live gameplay for CONNECTION (six-degrees teammate chain). Shows two seeded
/// endpoint players (BFS-verified connected at init) and the chain built so far;
/// a teammate-search typeahead appends validated links until the chain reaches the
/// endpoint. On completion, shows optimality vs the graph's shortest path (reward
/// shorter). Sources the distinct-player pool (names) + teammate graph from
/// `HistoricalPoolStore`. Follows the historical launch protocol.
struct ConnectionView: View {
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let definition: ConnectionDefinition
    var seed: UInt64? = nil

    @State private var store: ConnectionStore?
    @State private var launchFailed = false

    /// Ready when BOTH the distinct pool (names) and the graph are loaded.
    private var bothLoaded: Bool {
        historicalStore.phase == .loaded && historicalStore.graphPhase == .loaded
    }
    private var eitherFailed: Bool {
        historicalStore.phase == .failed || historicalStore.graphPhase == .failed
    }

    var body: some View {
        Group {
            if let store {
                ConnectionContent(store: store, names: nameLookup)
            } else if launchFailed {
                ContentUnavailableView("Can't start this game",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Couldn't seed a connectable pair of players."))
            } else if eitherFailed {
                ContentUnavailableView {
                    Label("Couldn't load the teammate graph", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The historical data failed to load.")
                } actions: {
                    Button("Try Again") {
                        Task { await historicalStore.load(); await historicalStore.loadGraph() }
                    }
                }
            } else {
                ProgressView("Loading teammate graph…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await historicalStore.load(); await historicalStore.loadGraph() }
        .onAppear(perform: launchIfReady)
        .onChange(of: historicalStore.phase) { _, _ in launchIfReady() }
        .onChange(of: historicalStore.graphPhase) { _, _ in launchIfReady() }
    }

    /// id → display name from the distinct-player set (graph nodes not in the
    /// distinct pool fall back to their raw id in the content view).
    private var nameLookup: [String: String] {
        Dictionary(historicalStore.distinctPlayers.map { ($0.id, $0.name) },
                   uniquingKeysWith: { a, _ in a })
    }

    private func launchIfReady() {
        guard store == nil, !launchFailed, bothLoaded, let rawGraph = historicalStore.graph else { return }
        // Restrict to the NAME-SEARCHABLE distinct players so every endpoint and
        // every valid intermediate link is a player the typeahead can find (the raw
        // graph carries ~1200 ineligible nodes absent from the answer index).
        let named = Set(historicalStore.distinctPlayers.map { $0.id })
        let graph = named.isEmpty ? rawGraph : rawGraph.restricted(to: named)
        do {
            let state = try ConnectionEngine.initialize(
                definition: definition, graph: graph,
                seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = ConnectionStore(state: state, graph: graph)
        } catch {
            launchFailed = true
        }
    }
}

private struct ConnectionContent: View {
    @ObservedObject var store: ConnectionStore
    let names: [String: String]
    @State private var query = ""

    private func name(_ id: String) -> String { names[id] ?? "Player #\(id)" }

    /// Teammate candidates of the current chain tail, name-searchable, not yet used.
    private var matches: [(id: String, name: String)] {
        let q = HistoricalNameIndex.normalize(query)
        guard !q.isEmpty else { return [] }
        // The store's graph is private; we search the distinct-name universe and
        // let the engine validate teammate-of-tail on submit (authoritative gate).
        return names
            .filter { !store.state.chain.contains($0.key) }
            .filter { HistoricalNameIndex.normalize($0.value).contains(q) }
            .sorted { $0.value < $1.value }
            .prefix(50)
            .map { (id: $0.key, name: $0.value) }
    }

    var body: some View {
        content
            .alert("Invalid link",
                   isPresented: Binding(get: { store.lastError != nil },
                                        set: { if !$0 { store.clearError() } })) {
                Button("OK", role: .cancel) { store.clearError() }
            } message: { Text(errorMessage(store.lastError)) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .finished(let score):
            finished(score: score)
        case .building:
            building
        }
    }

    private var building: some View {
        List {
            Section("Connect these two") {
                HStack {
                    endpointCard(store.state.startId, label: "Start")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    endpointCard(store.state.endId, label: "End")
                }
            }
            Section("Your chain (\(store.state.linksUsed) links, best \(store.state.optimalLength))") {
                ForEach(Array(store.state.chain.enumerated()), id: \.offset) { _, id in
                    Text(name(id))
                }
            }
            Section("Add the next teammate of \(name(store.state.tail))") {
                if matches.isEmpty {
                    Text(query.isEmpty ? "Search for a player." : "No players match \"\(query)\".")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches, id: \.id) { m in
                        Button {
                            store.appendLink(playerId: m.id)
                        } label: { Text(m.name) }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button {
                    store.undo()
                } label: {
                    Label("Undo last link", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(store.state.linksUsed == 0)
                Button(role: .destructive) {
                    store.reset()
                } label: {
                    Label("Restart chain", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.state.linksUsed == 0)
            }
        }
        .searchable(text: $query, prompt: "Search for a teammate")
    }

    private func endpointCard(_ id: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(name(id)).font(.subheadline.bold()).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func finished(score: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("Connected!").font(.title2.bold())
            Text("\(store.state.linksUsed) links · best possible \(store.state.optimalLength)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Score: \(score)").font(.largeTitle.bold()).foregroundStyle(.tint)
            VStack(spacing: 4) {
                ForEach(Array(store.state.chain.enumerated()), id: \.offset) { _, id in
                    Text(name(id)).font(.subheadline)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorMessage(_ err: ConnectionError?) -> String {
        switch err {
        case .notTeammate:  return "That player was never a teammate of the current player."
        case .alreadyUsed:  return "That player is already in your chain."
        case .unknownPlayer: return "That player isn't in the teammate graph."
        case .deadEnd:      return "That link would strand you — the end player couldn't be reached from there. Try another teammate, or Undo."
        case .nothingToUndo: return "Nothing to undo — you're back at the start."
        default:            return "Try another player."
        }
    }
}
