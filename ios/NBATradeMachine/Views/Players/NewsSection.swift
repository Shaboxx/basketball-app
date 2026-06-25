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
                    ForEach(vm.items) { row($0) }
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
        .task { await vm.load(for: player.slug) }
    }

    @ViewBuilder
    private func row(_ item: NewsItem) -> some View {
        if let url = item.articleURL {
            Link(destination: url) { rowContent(item) }
                .buttonStyle(.plain)
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Text(item.source)
                Text("·")
                Text(item.relativeDate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
