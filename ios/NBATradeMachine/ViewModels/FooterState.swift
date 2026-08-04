import SwiftUI
import Combine
import UIKit

/// Shared expand/collapse state for `AppFooter`, driven independently by scroll
/// (up → expand, down → collapse) and tap (collapsed basketball → expand), plus the
/// user-chosen position of the dragged collapsed button.
@MainActor
final class FooterState: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
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
    /// Signed accumulator of directional scroll travel since the last flip or the
    /// last direction reversal. Positive = net downward, negative = net upward.
    /// A flip only fires once this exceeds the (asymmetric) travel budget, and it
    /// resets to 0 on every direction reversal — so a jittery back-and-forth
    /// gesture can never sum its way to a flip. That accumulate-then-reset rule is
    /// the "requires sustained movement / rate-limit" the footer needs: rapid tiny
    /// wiggles cancel out instead of repeatedly opening and closing the bar.
    private var travel: CGFloat = 0
    /// Sustained UP-scroll (points) required to re-show the footer.
    private let expandTravel: CGFloat = 26
    /// Sustained DOWN-scroll (points) required to hide it — deliberately larger
    /// than `expandTravel` so the bar biases toward staying visible (hysteresis:
    /// the show/hide thresholds are asymmetric, preventing flutter near a single
    /// boundary).
    private let collapseTravel: CGFloat = 48
    /// Within this top band (incl. the rubber-band zone) we always stay expanded.
    private let topZone: CGFloat = 8
    /// Ignore samples this far beyond the in-bounds range — rubber-band / bounce
    /// at either edge must never move the footer.
    private let overscrollSlack: CGFloat = 2

    /// Called by the active scroll view as its vertical content offset changes.
    /// `maxOffset` is the largest in-bounds content offset (0 when the content is
    /// too short to scroll).
    func onScroll(offset: CGFloat, maxOffset: CGFloat) {
        guard !lockedExpanded else { return }

        // Rubber-band / bounce at either edge: freeze. We neither flip nor update
        // `lastOffset`, so when the content springs back to its in-bounds resting
        // position the delta is ~0 and the footer is unaffected — bouncing off the
        // bottom of a screen leaves the menu exactly as it was.
        if offset < -overscrollSlack || (maxOffset > 0 && offset > maxOffset + overscrollSlack) {
            return
        }

        // At/above the top → always expanded, and reset the accumulator.
        if offset <= topZone {
            lastOffset = offset
            travel = 0
            setExpanded(true)
            return
        }

        let delta = offset - lastOffset
        lastOffset = offset
        if delta == 0 { return }

        // Reset the accumulator whenever direction reverses, so jitter / a fling
        // that reverses mid-flight can never accumulate its way to a flip.
        if travel != 0, (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta

        if travel <= -expandTravel {
            travel = 0
            setExpanded(true)
        } else if travel >= collapseTravel {
            travel = 0
            setExpanded(false)
        }
    }

    /// Tap on the collapsed button.
    func expand() { setExpanded(true) }

    /// Reset to expanded when switching screens/tabs.
    func resetForScreenChange() {
        lastOffset = 0
        travel = 0
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
        // Honor Reduce Motion — a quick fade instead of the spring for users who opted out.
        let anim: Animation = UIAccessibility.isReduceMotionEnabled
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.34, dampingFraction: 0.82)
        withAnimation(anim) { isExpanded = value }
    }
}

extension View {
    /// Report a scroll view's vertical offset to the footer state so it expands on scroll-up
    /// and collapses on scroll-down. Clearance for the expanded bar is handled centrally by
    /// `.appFooter` via `safeAreaInset` (no per-scroll-view inset needed here).
    func reportsFooterScroll(_ state: FooterState) -> some View {
        onScrollGeometryChange(for: FooterScrollSample.self) { geo in
            FooterScrollSample(
                offset: geo.contentOffset.y,
                // Largest in-bounds offset; anything past it (± slack) is bounce.
                maxOffset: max(0, geo.contentSize.height - geo.containerSize.height)
            )
        } action: { _, new in
            state.onScroll(offset: new.offset, maxOffset: new.maxOffset)
        }
    }
}

/// Minimal Equatable snapshot of a scroll view's vertical geometry, so
/// `onScrollGeometryChange` only re-runs the footer logic when it actually moves.
struct FooterScrollSample: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat
}
