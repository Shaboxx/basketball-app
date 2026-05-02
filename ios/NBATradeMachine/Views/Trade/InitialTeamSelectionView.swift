import SwiftUI

struct InitialTeamSelectionView: View {
    @ObservedObject var vm: TradeMachineViewModel
    @State private var teamA: Team?
    @State private var teamB: Team?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Toggle("Offseason mode (next season)", isOn: $vm.isOffseason)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

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

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    private var availableForB: [Team] {
        guard let a = teamA else { return vm.allTeams }
        return vm.allTeams.filter { $0.teamId != a.teamId }
    }
}
