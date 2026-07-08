import SwiftUI

extension View {
    /// Attaches the app footer to a screen's content in its two states:
    /// - EXPANDED: a bottom bar that RESERVES its height via `safeAreaInset`, so content
    ///   scrolls under it and shows through the `.ultraThinMaterial` (native chrome behaviour,
    ///   exact clearance, no per-scroll-view coupling).
    /// - COLLAPSED: a floating, draggable `basketball.fill` in an overlay that reserves NO
    ///   space (content uses the full height; the button floats over it).
    /// State + animation live in `FooterState`.
    func appFooter<Bar: View>(_ state: FooterState, @ViewBuilder bar: @escaping () -> Bar) -> some View {
        modifier(AppFooterModifier(state: state, bar: bar))
    }
}

private struct AppFooterModifier<Bar: View>: ViewModifier {
    @ObservedObject var state: FooterState
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if state.isExpanded {
                    VStack(spacing: 0) {
                        Divider()
                        bar()
                    }
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !state.isExpanded {
                    CollapsedFooterButton(state: state)
                        .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
    }
}

/// The collapsed footer: a single basketball button — tap to expand, hold-and-drag to move.
private struct CollapsedFooterButton: View {
    @ObservedObject var state: FooterState
    // Live translation while repositioning (committed to `state` on release).
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        Image(systemName: "basketball.fill")
            .font(.title2)
            .foregroundStyle(Color.accentColor)
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .padding(.leading, 16)
            .padding(.bottom, 12)
            .offset(x: state.collapsedOffset.width + dragTranslation.width,
                    y: state.collapsedOffset.height + dragTranslation.height)
            .contentShape(Circle())
            // Tap is a first-class way to re-open the footer.
            .onTapGesture { state.expand() }
            // Hold, then drag, to reposition — the long-press disambiguates from the tap.
            .gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture())
                    .updating($dragTranslation) { value, out, _ in
                        if case .second(true, let drag?) = value { out = drag.translation }
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value { state.commitDrag(drag.translation) }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Open menu")
            .accessibilityHint("Double-tap to expand the footer; touch and hold to move it")
    }
}
