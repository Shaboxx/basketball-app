import SwiftUI
import UIKit

struct InitialTeamSelectionView: View {
    @ObservedObject var vm: TradeMachineViewModel
    @State private var teamA: Team?
    @State private var teamB: Team?
    @State private var codeError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Choose two teams to start a trade")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TeamPickerView(label: "Team 1", teams: vm.allTeams, selection: $teamA)
                TeamPickerView(label: "Team 2", teams: availableForB, selection: $teamB)

                Button {
                    if let a = teamA, let b = teamB { vm.setInitialTeams(a, b) }
                } label: {
                    Label("Start Trade", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(teamA == nil || teamB == nil || teamA == teamB)

                // NAV-21: reload a trade someone shared as a code. On success the
                // machine has 2+ teams and swaps to the active trade view.
                Button {
                    if let text = UIPasteboard.general.string,
                       let code = TradeCodec.decode(text),
                       vm.applyTradeCode(code) {
                        // handled — parent switches away from this view
                    } else {
                        codeError = true
                    }
                } label: {
                    Label("Paste trade code", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 40)
            }
            .padding()
        }
        .alert("No trade code found", isPresented: $codeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy a trade code (shared from a trade summary) to the clipboard, then tap Paste trade code.")
        }
    }

    private var availableForB: [Team] {
        guard let a = teamA else { return vm.allTeams }
        return vm.allTeams.filter { $0.teamId != a.teamId }
    }
}
