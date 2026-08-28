import SwiftUI

/// Live gameplay for a GRID (immaculate 3×3). Renders row/col axis headers and
/// tappable cells; tapping an empty cell opens a name-search typeahead sheet over
/// the distinct-player pool (Sol Q1: free-text search, not a visible pool). A
/// correct answer scores eligibility-rarity and fills the cell. Sources the shared
/// distinct-player pool from `HistoricalPoolStore` (off-main load-once); follows
/// `HistoricalRosterDraftView`'s launch protocol (retry-on-republish vs latch).
struct GridView: View {
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let definition: GridDefinition
    var seed: UInt64? = nil

    @State private var store: GridStore?
    @State private var launchFailed = false

    var body: some View {
        Group {
            if let store {
                GridContent(store: store)
            } else if launchFailed {
                ContentUnavailableView("Can't start this game",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Couldn't build a solvable grid from the pool."))
            } else if historicalStore.phase == .failed {
                ContentUnavailableView {
                    Label("Couldn't load historical players", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The historical dataset failed to load.")
                } actions: {
                    Button("Try Again") { Task { await historicalStore.load() } }
                }
            } else {
                ProgressView("Loading players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await historicalStore.load() }
        .onAppear(perform: launchIfReady)
        .onChange(of: historicalStore.phase) { _, newPhase in
            if newPhase == .loaded { launchIfReady() }
        }
    }

    private func launchIfReady() {
        guard store == nil, !launchFailed, historicalStore.phase == .loaded else { return }
        let pool = historicalStore.distinctPlayers
        // Loaded-but-empty distinct pool is a terminal config failure (latch).
        guard !pool.isEmpty else { launchFailed = true; return }
        do {
            let state = try GridEngine.initialize(
                definition: definition, pool: pool,
                seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = GridStore(state: state)
        } catch {
            // The pool is loaded (guard above), so an infeasible draw is TERMINAL.
            launchFailed = true
        }
    }
}

private struct GridContent: View {
    @ObservedObject var store: GridStore

    private var rows: [GridAxis] { store.state.rowAxes }
    private var cols: [GridAxis] { store.state.colAxes }

    var body: some View {
        content
            .sheet(item: Binding(get: { store.selectedCell },
                                 set: { if $0 == nil { store.selectedCell = nil } })) { cell in
                GridAnswerSheet(store: store, cell: cell)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .finished(let score):
            finished(score: score)
        case .filling:
            filling
        }
    }

    private var filling: some View {
        VStack(spacing: 12) {
            Text("Score: \(store.state.score)").font(.headline)
            grid
            Text("Tap a cell, then search for a player who fits BOTH headers. Rarer answers score more.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var grid: some View {
        VStack(spacing: 6) {
            // Column headers (top-left corner blank).
            HStack(spacing: 6) {
                cornerCell
                ForEach(Array(cols.enumerated()), id: \.offset) { _, axis in
                    headerCell(axis)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowAxis in
                HStack(spacing: 6) {
                    headerCell(rowAxis)
                    ForEach(Array(cols.enumerated()), id: \.offset) { colIndex, _ in
                        answerCell(row: rowIndex, col: colIndex)
                    }
                }
            }
        }
    }

    private var cornerCell: some View {
        Color.clear.frame(maxWidth: .infinity, minHeight: 56)
    }

    private func headerCell(_ axis: GridAxis) -> some View {
        Text(axis.displayLabel)
            .font(.caption.bold())
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func answerCell(row: Int, col: Int) -> some View {
        let cell = GridCell(row: row, col: col)
        let fill = store.state.cellFills[cell]
        Button {
            store.selectCell(cell)
        } label: {
            VStack(spacing: 2) {
                if let fill {
                    Text(fill.playerName).font(.caption2.bold())
                        .multilineTextAlignment(.center).lineLimit(2)
                    Text("+\(fill.points)").font(.caption2).foregroundStyle(.tint)
                } else {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background((fill == nil ? Color.secondary.opacity(0.08) : Color.green.opacity(0.15)),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(fill != nil)
    }

    @ViewBuilder
    private func finished(score: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Grid complete!").font(.title2.bold())
            Text("Score: \(score)").font(.largeTitle.bold()).foregroundStyle(.tint)
            grid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// The typeahead answer sheet for one cell — free-text search over a NORMALIZED
/// offline name index built from the distinct-player pool (Sol Q1). Normalizes
/// lowercase + strips diacritics/punctuation; keys on distinct-player id (duplicate
/// names are disambiguated by best-rating subtitle).
private struct GridAnswerSheet: View {
    @ObservedObject var store: GridStore
    let cell: GridCell
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rowAxis: GridAxis { store.state.rowAxes[cell.row] }
    private var colAxis: GridAxis { store.state.colAxes[cell.col] }

    private var matches: [HistoricalPlayerEntity] {
        let q = HistoricalNameIndex.normalize(query)
        guard !q.isEmpty else { return [] }
        return store.state.pool
            .filter { !store.state.usedPlayerIds.contains($0.id) }
            .filter { HistoricalNameIndex.normalize($0.name).contains(q) }
            .prefix(50).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(rowAxis.displayLabel)  ×  \(colAxis.displayLabel)")
                        .font(.subheadline.bold())
                }
                if let err = store.lastError {
                    Section {
                        Text(errorMessage(err)).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Search") {
                    if matches.isEmpty {
                        Text(query.isEmpty ? "Type a player's name." : "No players match \"\(query)\".")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matches) { e in
                            Button {
                                store.submitAnswer(cell: cell, playerId: e.id)
                                if store.selectedCell == nil { dismiss() }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(e.name)
                                    Text(subtitle(e)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search for a player")
            .navigationTitle("Fill Cell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.selectedCell = nil; dismiss() }
                }
            }
        }
    }

    private func subtitle(_ e: HistoricalPlayerEntity) -> String {
        let franchises = e.franchises.sorted().joined(separator: ", ")
        return franchises.isEmpty ? "Rating \(Int(e.bestRating))" : franchises
    }

    private func errorMessage(_ err: GridError) -> String {
        switch err {
        case .doesNotSatisfy: return "That player doesn't fit both headers."
        case .alreadyUsed:    return "You already used that player."
        case .cellFilled:     return "That cell is already filled."
        default:              return "Try another player."
        }
    }
}
