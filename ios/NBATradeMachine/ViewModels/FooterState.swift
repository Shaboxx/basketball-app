import SwiftUI
import Combine

/// Shared expand/collapse state for `AppFooter`, driven independently by scroll
/// (up → expand, down → collapse) and tap (collapsed basketball → expand), plus the
/// user-chosen position of the dragged collapsed button.
@MainActor
final class FooterState: ObservableObject {
    @Published var isExpanded = true
    /// Offset of the collapsed button from its default bottom-leading spot (drag-to-move).
    @Published var collapsedOffset: CGSize = .zero
    /// Size of the region the collapsed button may be dragged within (for clamping).
    var containerSize: CGSize = .zero
    /// While true (e.g. trade-selection mode) the footer never collapses.
    var lockedExpanded = false {
        didSet { if lockedExpanded, !isExpanded { setExpanded(true) } }
    }

    private var lastOffset: CGFloat = 0
    /// Movement must exceed this (points) to flip state — absorbs bounce jitter.
    private let threshold: CGFloat = 12
    /// Within this top band (incl. the rubber-band zone) we always stay expanded.
    private let topZone: CGFloat = 8

    /// Called by the active scroll view as its vertical content offset changes.
    func onScroll(old: CGFloat, new: CGFloat) {
        guard !lockedExpanded else { return }
        if new <= topZone {            // at/above the top (incl. bounce) → expanded
            lastOffset = new
            setExpanded(true)
            return
        }
        let delta = new - lastOffset
        guard abs(delta) > threshold else { return }   // ignore tiny/jittery moves
        lastOffset = new
        setExpanded(delta < 0)         // scrolling up (offset decreasing) expands
    }

    /// Tap on the collapsed button.
    func expand() { setExpanded(true) }

    /// Reset to expanded when switching screens/tabs.
    func resetForScreenChange() {
        lastOffset = 0
        setExpanded(true)
    }

    /// Commit a finished drag of the collapsed button, clamped to stay on screen.
    func commitDrag(_ translation: CGSize) {
        var next = CGSize(width: collapsedOffset.width + translation.width,
                          height: collapsedOffset.height + translation.height)
        // Default spot is bottom-leading, so it can move right (+w) and up (-h).
        let maxRight = max(0, containerSize.width - 84)     // ~button + margins
        let maxUp = max(0, containerSize.height - 140)
        next.width = min(max(next.width, 0), maxRight)
        next.height = min(max(next.height, -maxUp), 0)
        collapsedOffset = next
    }

    private func setExpanded(_ value: Bool) {
        guard isExpanded != value else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { isExpanded = value }
    }
}

extension View {
    /// Report a scroll view's vertical offset to the footer state so it expands on scroll-up
    /// and collapses on scroll-down. Clearance for the expanded bar is handled centrally by
    /// `.appFooter` via `safeAreaInset` (no per-scroll-view inset needed here).
    func reportsFooterScroll(_ state: FooterState) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
            state.onScroll(old: old, new: new)
        }
    }
}
