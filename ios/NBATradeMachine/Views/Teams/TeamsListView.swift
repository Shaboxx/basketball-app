import SwiftUI

struct TeamsListView: View {
    @EnvironmentObject var teamsVM: TeamsViewModel

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let err = teamsVM.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.red)
                        Text("Couldn't load teams").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else if teamsVM.isLoading && teamsVM.teams.isEmpty {
                    ProgressView().padding(.top, 80)
                } else if teamsVM.teams.isEmpty {
                    Text("No teams loaded yet — check Xcode console.")
                        .foregroundStyle(.secondary).padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(teamsVM.teams) { team in
                            NavigationLink(value: team) {
                                VStack(spacing: 8) {
                                    TeamLogoMark(teamId: team.teamId, size: 56, aliasFont: .caption2)
                                    Text(team.name)
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
                                    Text(team.city)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Teams")
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team)
            }
        }
        .task { await teamsVM.load() }
    }
}
