import SwiftUI

struct AddTeamSheet: View {
    @ObservedObject var vm: TradeMachineViewModel
    let onSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(vm.availableTeamsToAdd) { team in
                Button {
                    vm.addTeam(team)
                    onSelected(team.teamId)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        TeamLogoMark(teamId: team.teamId, size: 30, aliasFont: .caption2, showsAlias: false)
                        Text(team.fullName).foregroundStyle(.primary)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Add Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
