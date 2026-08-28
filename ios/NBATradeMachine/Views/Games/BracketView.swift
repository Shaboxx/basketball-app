import SwiftUI

/// Live gameplay for a BRACKET game (Phase 8). Builds the current-era pool from
/// the app-wide PlayersViewModel, initializes a per-session BracketStore, then
/// renders the current matchup as two tappable cards. Advancing a winner reshapes
/// the next round; on the final it shows the champion + optional model-agreement.
struct BracketView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    let definition: BracketDefinition
    /// A CANONICAL seed for the shared daily/weekly path (Sol fix 1). Preset/creator
    /// callers pass nothing → nil → a fresh random seed each session (unchanged
    /// behavior); only the daily path threads a concrete, device-invariant seed.
    var seed: UInt64? = nil

    @State private var store: BracketStore?
    @State private var launchFailed = false

    var body: some View {
        Group {
            if let store {
                BracketContent(store: store)
            } else if launchFailed {
                ContentUnavailableView(
                    "Can't start this bracket",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Not enough eligible players for this field size."))
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
            let state = try BracketEngine.initialize(
                definition: definition, pool: pool,
                seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = BracketStore(state: state)
        } catch BracketError.notEnoughEntities {
            // Sol fix 3: the players source is loaded (guard above ⇒ non-empty), so an
            // insufficient-pool throw is TERMINAL, not a loading blip — latch failure
            // instead of spinning forever on a permanently-infeasible pool.
            launchFailed = true
        } catch {
            // A config error (bad field size) is permanent — latch failure.
            launchFailed = true
        }
    }
}

private struct BracketContent: View {
    @ObservedObject var store: BracketStore
    @EnvironmentObject var teamsVM: TeamsViewModel

    private var teamNames: [String: String] {
        Dictionary(teamsVM.teams.map { ($0.teamId, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    private func teamLabel(_ id: String) -> String { teamNames[id] ?? id }

    var body: some View {
        content
            // Sol fix 6: surface BracketStore.lastError (previously published but never
            // shown). BracketStore.advance records a typed BracketError on a rejected
            // pick; mirror RosterDraftContent's alert so it isn't a dead affordance.
            // clearError() on dismiss; a successful advance also clears it.
            .alert("Can't advance that pick",
                   isPresented: Binding(get: { store.lastError != nil },
                                        set: { if !$0 { store.clearError() } })) {
                Button("OK", role: .cancel) { store.clearError() }
            } message: { Text(errorText(store.lastError)) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .finished(let result):
            finished(result)
        case .choosing:
            choosing
        }
    }

    private func errorText(_ e: BracketError?) -> String {
        switch e {
        case .notInMatchup:  return "Pick one of the two players shown."
        case .unknownEntity: return "That isn't a player in this bracket."
        case .outOfOrder, .complete: return "This bracket is already finished."
        default:             return "That pick isn't allowed right now."
        }
    }

    @ViewBuilder
    private func finished(_ result: BracketResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill").font(.system(size: 44))
                .foregroundStyle(.yellow)
            if let champ = result.champion {
                Text("Champion").font(.headline).foregroundStyle(.secondary)
                Text(champ.name).font(.largeTitle.bold())
                Text("\(teamLabel(champ.team)) · \(champ.position)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let n = result.modelAgreementCount {
                Text("You matched the model on \(n)/\(result.totalMatchups)")
                    .font(.subheadline).foregroundStyle(.tint)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var choosing: some View {
        VStack(spacing: 16) {
            if let round = BracketEngine.currentRound(store.state) {
                Text(roundLabel(round: round, fieldSize: store.state.definition.fieldSize))
                    .font(.headline)
            }
            Text("Who advances?").font(.title3.bold())
            if let (left, right) = BracketEngine.currentMatchup(store.state) {
                card(left)
                Text("vs").font(.caption.bold()).foregroundStyle(.secondary)
                card(right)
            }
            Spacer()
        }
        .padding()
    }

    private func card(_ e: GameEntityRecord) -> some View {
        Button {
            store.advance(winnerId: e.id)
        } label: {
            VStack(spacing: 4) {
                Text(e.name).font(.title3.bold())
                Text("\(teamLabel(e.team)) · \(e.position)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding()
            .background(Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// "Round of N" / "Semifinal" / "Final" from the round index + field size.
    private func roundLabel(round: Int, fieldSize: Int) -> String {
        let remaining = fieldSize >> round     // entities entering this round
        switch remaining {
        case 2:  return "Final"
        case 4:  return "Semifinals"
        case 8:  return "Quarterfinals"
        default: return "Round of \(remaining)"
        }
    }
}
