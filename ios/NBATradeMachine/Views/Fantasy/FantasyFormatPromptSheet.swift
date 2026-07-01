import SwiftUI

/// First-use Fantasy setup, shown the first time Fantasy mode is turned on. Picks the
/// scoring format + dynasty, then sets `hasChosenFantasyFormat` so it never auto-prompts
/// again (re-editable later from the gear via `FantasySettingsSheet`).
struct FantasyFormatPromptSheet: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Scoring Format") {
                    Picker("Scoring Format", selection: $appSettings.fantasyFormat) {
                        ForEach(FantasyFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                }
                Section {
                    Toggle("Dynasty", isOn: $appSettings.dynastyOn)
                } footer: {
                    Text("Dynasty weights long-term value by age.")
                }
                Section {
                    Button {
                        appSettings.hasChosenFantasyFormat = true
                        dismiss()
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Fantasy Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    FantasyFormatPromptSheet().environmentObject(AppSettings())
}
