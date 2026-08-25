import SwiftUI

/// Live gameplay for a classification game. Builds the pool from PlayersViewModel,
/// generates subjects, and hands the session to a ClassificationStore. Each
/// subject is tapped, then a destination bucket; when all are assigned the model
/// score is shown.
struct ClassificationView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    let definition: ClassificationDefinition

    @State private var store: ClassificationStore?
    @State private var launchFailed = false

    var body: some View {
        Group {
            if let store {
                ClassificationContent(store: store)
            } else if launchFailed {
                ContentUnavailableView("Can't start this game",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("This game is misconfigured."))
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
        do {
            let state = try ClassificationEngine.initialize(
                definition: definition, pool: pool,
                seed: UInt64.random(in: UInt64.min...UInt64.max))
            store = ClassificationStore(state: state)
        } catch ClassificationError.invalidConfig {
            launchFailed = true   // a real config bug — never resolves
        } catch {
            // R10: insufficient data now (notEnoughSubjects) — leave store nil and
            // retry when PlayersViewModel republishes a fuller roster.
        }
    }
}

private struct ClassificationContent: View {
    @ObservedObject var store: ClassificationStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @State private var selected: String?    // subjectId awaiting a destination

    private var teamNames: [String: String] {
        Dictionary(teamsVM.teams.map { ($0.teamId, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    private func teamLabel(_ id: String) -> String { teamNames[id] ?? id }
    private var cfg: ClassificationConfig { store.state.definition.config }

    var body: some View {
        switch store.phase {
        case .finished(let score):
            resultView(score: score)
        case .assigning:
            assigningView
        }
    }

    private var assigningView: some View {
        VStack(spacing: 0) {
            List {
                Section("Players") {
                    ForEach(store.state.subjects) { subject in
                        Button {
                            selected = (selected == subject.id) ? nil : subject.id
                        } label: {
                            HStack {
                                Image(systemName: selected == subject.id
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading) {
                                    Text(subject.name)
                                    Text(teamLabel(subject.team)).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let d = store.state.assignments[subject.id] {
                                    Text(cfg.destinationLabel(d))
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            destinationBar
        }
        .alert("Not allowed",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.clearError() } })) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: { Text(errorText(store.lastError)) }
    }

    private var destinationBar: some View {
        VStack(spacing: 6) {
            Text(selected == nil ? "Pick a player, then a slot" : "Assign to…")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<cfg.destinationCount, id: \.self) { d in
                        Button(cfg.destinationLabel(d)) {
                            // R11: clear the selection only if the assign succeeded.
                            if let s = selected, store.assign(subjectId: s, destination: d) {
                                selected = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selected == nil)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private func resultView(score: Int) -> some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("\(score)").font(.system(size: 56, weight: .bold))
                    Text("match with the model").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            Section("Your call vs the model") {
                ForEach(store.state.subjects.sorted {
                    (store.state.assignments[$0.id] ?? 0) < (store.state.assignments[$1.id] ?? 0)
                }) { s in
                    HStack {
                        Text(cfg.destinationLabel(store.state.assignments[s.id] ?? 0))
                            .font(.caption.bold()).frame(width: 44, alignment: .leading)
                        Text(s.name)
                        Spacer()
                        Text(String(format: "%+.1f", s.rating))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func errorText(_ e: ClassificationError?) -> String {
        switch e {
        case .destinationTaken: return "That slot is taken — free it first."
        case .invalidDestination: return "That slot isn't available."
        default: return "That move isn't allowed."
        }
    }
}
