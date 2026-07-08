import SwiftUI

/// Static, content-shaped placeholders shown during a browse surface's *first* load.
/// A skeleton reads as "loading this kind of content" far better than a bare centered
/// spinner, and — being static — needs no Reduce-Motion handling (nothing animates).
/// Shapes fill with `.quaternary` so they adapt to light/dark and stay quiet, and each
/// skeleton is `accessibilityHidden` (decorative; the real content becomes available to
/// VoiceOver as soon as it loads).
private struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: height)
    }
}

/// Grid of placeholder team tiles — mirrors `TeamsListView.teamTile` (logo, name, city, badge).
struct TeamGridSkeleton: View {
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle().fill(.quaternary).frame(width: 56, height: 56)
                    SkeletonBar(width: 72, height: 12)
                    SkeletonBar(width: 48, height: 9)
                    Capsule().fill(.quaternary).frame(width: 44, height: 18)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .accessibilityHidden(true)
    }
}

/// Placeholder player rows — mirrors the `PlayersListView` row (headshot, name/meta, trailing value).
struct PlayerListSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(.quaternary).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBar(width: 150, height: 12)
                        SkeletonBar(width: 90, height: 9)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Capsule().fill(.quaternary).frame(width: 40, height: 18)
                        SkeletonBar(width: 52, height: 9)
                    }
                }
                .padding(.vertical, 11)
                .padding(.horizontal)
                Divider().opacity(0.25)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Placeholder news rows — mirrors `NewsRow` (two title lines + a source/date line).
struct NewsListSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBar(height: 13)                 // title line 1 (fills width)
                    SkeletonBar(width: 220, height: 13)     // title line 2
                    SkeletonBar(width: 130, height: 9)      // source · date
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal)
                Divider().opacity(0.25)
            }
        }
        .accessibilityHidden(true)
    }
}
