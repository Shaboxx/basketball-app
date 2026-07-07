import SwiftUI

/// The app's bottom footer in its two states: EXPANDED shows the caller's existing
/// contents (Trade button + Fantasy/Teams·Players·News row) over `.ultraThinMaterial`;
/// COLLAPSED condenses to a single draggable `basketball.fill` button (tap → expand,
/// hold-and-drag → reposition). State/animation live in `FooterState`.
struct AppFooter<Expanded: View>: View {
    @ObservedObject var state: FooterState
    @ViewBuilder var expanded: () -> Expanded

    // Live drag translation while repositioning the collapsed button.
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if state.isExpanded {
                expandedBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedButton
                    .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var expandedBar: some View {
        VStack(spacing: 0) {
            Divider()
            expanded()
        }
        .background(.ultraThinMaterial)
        // Report the bar's height so scroll views can inset their content to match.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.expandedHeight = $0 }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var collapsedButton: some View {
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
            // Hold, then drag, to reposition — long-press disambiguates from the tap.
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
