import SwiftUI

/// Pick a saved fantasy team (or the free "Any player pool") for a trade side.
/// `onPick(nil)` = Any player pool. Dismisses itself after a pick.
struct FantasyTeamPickerSheet: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onPick: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        Label("Any player pool", systemImage: "person.3")
                    }
                }
                if !fantasyTeamStore.teams.isEmpty {
                    Section("Saved Teams") {
                        ForEach(fantasyTeamStore.teams) { team in
                            Button {
                                onPick(team.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(team.name)
                                    Spacer()
                                    Text("\(team.playerSlugs.count)").foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
