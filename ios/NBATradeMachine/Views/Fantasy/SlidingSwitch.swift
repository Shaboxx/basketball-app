import SwiftUI

/// Reusable two-slot sliding switch — the NBA/Fantasy toggle look: a thumb pill
/// slides under the ACTIVE slot. Color-scheme adaptive: DAY mode uses a NAVY
/// thumb (a white pill vanishes against the light track) with the active label
/// in light blue; NIGHT mode uses a white thumb with the accent label.
struct SlidingSwitch<Left: View, Right: View>: View {
    @Environment(\.colorScheme) private var scheme

    @Binding var isRight: Bool
    let left: Left
    let right: Right
    var width: CGFloat = 168
    var height: CGFloat = 32
    var accessibilityName: String = "Switch"
    /// Spoken state names — `.accessibilityElement()` hides the slot content
    /// (incl. icon-only slots) from VoiceOver, so the value must be explicit.
    var leftName: String = "Left"
    var rightName: String = "Right"

    init(isRight: Binding<Bool>, width: CGFloat = 168, height: CGFloat = 32,
         accessibilityName: String = "Switch",
         leftName: String = "Left", rightName: String = "Right",
         @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self._isRight = isRight
        self.width = width
        self.height = height
        self.accessibilityName = accessibilityName
        self.leftName = leftName
        self.rightName = rightName
        self.left = left()
        self.right = right()
    }

    private var thumbColor: Color {
        scheme == .dark ? .white : Color(red: 0.07, green: 0.16, blue: 0.38)   // navy in day mode
    }
    private var activeColor: Color {
        scheme == .dark ? Color.accentColor : Color(red: 0.55, green: 0.78, blue: 1.0)
    }

    var body: some View {
        ZStack {
            Capsule().fill(Color(.tertiarySystemFill))
            Capsule()
                .fill(thumbColor)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .frame(width: width / 2, height: height)
                .offset(x: isRight ? width / 4 : -width / 4)
            HStack(spacing: 0) {
                left
                    .foregroundStyle(isRight ? Color.secondary : activeColor)
                    .frame(width: width / 2)
                right
                    .foregroundStyle(isRight ? activeColor : Color.secondary)
                    .frame(width: width / 2)
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(width: width, height: height)
        .animation(.snappy, value: isRight)
        .contentShape(Capsule())
        .onTapGesture { isRight.toggle() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(isRight ? rightName : leftName)
        .accessibilityAddTraits(.isButton)
    }
}
