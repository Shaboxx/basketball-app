import SwiftUI

/// Reusable two-slot sliding switch — the NBA/Fantasy toggle look: a thumb pill
/// slides under the ACTIVE slot. Color-scheme adaptive: DAY mode uses a NAVY
/// thumb (a white pill vanishes against the light track) with the active label
/// in light blue; NIGHT mode uses a white thumb with the accent label.
struct SlidingSwitch<Left: View, Right: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    /// Optional DAY-mode overrides. Defaults preserve the navy/light-blue Appearance-toggle
    /// look; the NBA/Fantasy toggle passes the accent scheme so its thumb matches the
    /// prominent Trade button (accent fill + white active label).
    var dayThumbColor: Color? = nil
    var dayActiveColor: Color? = nil

    init(isRight: Binding<Bool>, width: CGFloat = 168, height: CGFloat = 32,
         accessibilityName: String = "Switch",
         leftName: String = "Left", rightName: String = "Right",
         dayThumbColor: Color? = nil, dayActiveColor: Color? = nil,
         @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self._isRight = isRight
        self.width = width
        self.height = height
        self.accessibilityName = accessibilityName
        self.leftName = leftName
        self.rightName = rightName
        self.dayThumbColor = dayThumbColor
        self.dayActiveColor = dayActiveColor
        self.left = left()
        self.right = right()
    }

    private var thumbColor: Color {
        scheme == .dark ? .white : (dayThumbColor ?? Color(red: 0.07, green: 0.16, blue: 0.38))   // navy default
    }
    private var activeColor: Color {
        scheme == .dark ? Color.accentColor : (dayActiveColor ?? Color(red: 0.55, green: 0.78, blue: 1.0))
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
                    .frame(width: width / 2, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { isRight = false }   // tap-to-select: active side is a no-op
                right
                    .foregroundStyle(isRight ? activeColor : Color.secondary)
                    .frame(width: width / 2, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { isRight = true }
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy, value: isRight)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(isRight ? rightName : leftName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isRight.toggle() }   // VoiceOver double-tap still toggles
    }
}
