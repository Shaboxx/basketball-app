import SwiftUI

struct PlayersListView: View {
    @StateObject private var vm = PlayersViewModel()
    @EnvironmentObject var teamsVM: TeamsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.players.isEmpty {
                    ProgressView()
                } else {
                    List(vm.filtered) { p in
                        NavigationLink(value: p) {
                            HStack(spacing: 12) {
                                HeadshotImage(slug: p.slug, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.subheadline.bold())
                                    HStack(spacing: 6) {
                                        Text(p.teamId).font(.caption).foregroundStyle(.secondary)
                                        Text("·").foregroundStyle(.secondary)
                                        Text(p.position).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Money.display(p.currentSalary))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Players")
            .searchable(text: $vm.searchText, prompt: "Search players")
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
            }
        }
        .task { await vm.load() }
    }
}
