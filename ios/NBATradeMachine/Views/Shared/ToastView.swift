import SwiftUI

/// A transient confirmation/error banner for async writes that would otherwise
/// dismiss silently (NAV-18). Reusable across surfaces via `.toast($message)`.
struct ToastMessage: Equatable {
    let text: String
    var systemImage: String = "checkmark.circle.fill"
    var isError: Bool = false

    static func success(_ text: String) -> ToastMessage {
        ToastMessage(text: text, systemImage: "checkmark.circle.fill", isError: false)
    }
    static func failure(_ text: String) -> ToastMessage {
        ToastMessage(text: text, systemImage: "exclamationmark.triangle.fill", isError: true)
    }
}

extension View {
    /// Presents an auto-dismissing toast pinned to the bottom when `message` is
    /// non-nil. Setting a new message re-arms the timer.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let m = message {
                    Label(m.text, systemImage: m.systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(m.isError ? Color.red : Color.primary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                (m.isError ? Color.red : Color.green).opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)
                        .task(id: m) {
                            try? await Task.sleep(for: .seconds(2.2))
                            withAnimation { message = nil }
                        }
                }
            }
            .animation(.snappy, value: message)
    }
}
