import SwiftUI

/// Re-editable Fantasy scoring settings, opened from the settings gear at any time.
/// Same Format + Dynasty controls as the first-use prompt but does NOT touch
/// `hasChosenFantasyFormat`.
struct FantasySettingsSheet: View {
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
            }
            .navigationTitle("Fantasy Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FantasySettingsSheet().environmentObject(AppSettings())
}
