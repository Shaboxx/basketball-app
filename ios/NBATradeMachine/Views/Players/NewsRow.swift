import SwiftUI

/// A single news item row: title, source · relative date, optional summary.
/// With comments OFF it wraps the content in an external `Link` to the publisher
/// (when the URL is valid http(s)); with comments ON it instead pushes the in-app
/// `NewsDetailView` via `NavigationLink(value: item)`. Shared by the per-player
/// NewsSection (SP2) and the league NewsListView (SP3).
///
/// NOTE: when `AppConfig.commentsEnabled` is turned on, ANY screen that embeds
/// `NewsRow` under a NavigationStack must also register
/// `.navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }` so
/// the value-routed link resolves. NewsListView does this; the player-detail
/// NewsSection would need it too (out of scope for this task — flagged).
struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        if AppConfig.commentsEnabled {
            NavigationLink(value: item) { content }
                .buttonStyle(.plain)
        } else if let url = item.articleURL {
            Link(destination: url) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                if !item.source.isEmpty {
                    Text(item.source)
                    Text("·")
                }
                Text(item.relativeDate)
                if item.isMultiSource, let n = item.sourceCount {
                    Text("·")
                    Text("covered by \(n) sources")
                        .foregroundStyle(.tertiary)
                }
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
