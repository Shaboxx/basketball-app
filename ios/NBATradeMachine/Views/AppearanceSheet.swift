import SwiftUI

/// Day/night appearance controls, opened from the settings gear. Two sliding
/// switches (the NBA/Fantasy toggle visual): Auto ↔ Manual, and — only when
/// Manual — a Day/Night switch below it with the sun and crescent-moon symbols
/// in the slots. Auto follows the iPhone's setting.
struct AppearanceSheet: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Manual = any forced scheme; flipping back to Auto restores match-device.
    /// Flipping TO Manual seeds from the currently-EFFECTIVE scheme (what the
    /// user sees under Auto) instead of jarring a dark screen into Day.
    private var manualBinding: Binding<Bool> {
        Binding(get: { appSettings.appearance != .system },
                set: { manual in
                    appSettings.appearance = manual
                        ? (colorScheme == .dark ? .dark : .light)
                        : .system
                })
    }
    private var nightBinding: Binding<Bool> {
        Binding(get: { appSettings.appearance == .dark },
                set: { night in appSettings.appearance = night ? .dark : .light })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    SlidingSwitch(isRight: manualBinding, accessibilityName: "Appearance mode",
                                  leftName: "Auto", rightName: "Manual") {
                        Text("Auto")
                    } right: {
                        Text("Manual")
                    }
                    Text(appSettings.appearance == .system
                         ? "Following your iPhone's appearance."
                         : "Pick day or night below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if appSettings.appearance != .system {
                    SlidingSwitch(isRight: nightBinding, accessibilityName: "Day or night",
                                  leftName: "Day", rightName: "Night") {
                        Image(systemName: "sun.max.fill")
                    } right: {
                        Image(systemName: "moon.fill")
                    }
                }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.height(220)])
    }
}

#Preview {
    AppearanceSheet().environmentObject(AppSettings())
}
