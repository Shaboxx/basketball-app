import SwiftUI

/// A single news item row: title, source · relative date, optional summary,
/// wrapped in a Link to the publisher when the URL is valid http(s). Shared by
/// the per-player NewsSection (SP2) and the league NewsListView (SP3).
struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        if let url = item.articleURL {
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
