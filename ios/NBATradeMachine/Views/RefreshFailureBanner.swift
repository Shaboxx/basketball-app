import SwiftUI

extension View {
    /// Non-destructive refresh-failure feedback: shows a brief "couldn't refresh" banner each time
    /// `trigger` changes (a counter the view-model bumps when a background refresh fails while
    /// cached content is already on screen), then auto-dismisses. Convention: Apple News keeps the
    /// stale content and surfaces a transient banner rather than blowing the list away.
    func refreshFailureBanner(_ trigger: Int) -> some View {
        modifier(RefreshFailureBanner(trigger: trigger))
    }
}

private struct RefreshFailureBanner: ViewModifier {
    let trigger: Int
    @State private var showing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showing {
                    Label("Couldn't refresh — showing saved data", systemImage: "wifi.exclamationmark")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .padding(.top, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            // A counter (not a Bool) so repeated failures each re-trigger the banner.
            .onChange(of: trigger) { _, _ in
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3)) { showing = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut) { showing = false }
                }
            }
    }
}
