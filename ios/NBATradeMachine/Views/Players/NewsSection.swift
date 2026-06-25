import SwiftUI

/// Default-open "News" dropdown for a player's profile. Owns its own
/// NewsViewModel, loads on appear, and renders NOTHING until items arrive
/// (so a player with no news shows no empty card). Mirrors SalarySection's card.
struct NewsSection: View {
    let player: Player
    @StateObject private var vm = NewsViewModel()
    @State private var isExpanded = true

    var body: some View {
        Group {
            if !vm.items.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(vm.items) { NewsRow(item: $0) }
                } label: {
                    Text("News").font(.headline)
                }
                .padding()
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        // id: player.slug so a reused NewsSection reloads if the player changes.
        .task(id: player.slug) { await vm.load(for: player.slug) }
    }
}
