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
                    Picker("Source", selection: $appSettings.statSource) {
                        ForEach(StatSourceMode.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Scoring Source")
                } footer: {
                    Text("Projected uses season-long projections. Live scores standings on real season-to-date box scores.")
                }
                Section {
                    Toggle("Dynasty", isOn: $appSettings.dynastyOn)
                } footer: {
                    Text("Dynasty weights long-term value by age.")
                }
                Section {
                    Stepper("Lineup: \(appSettings.fantasyLineupLimit)",
                            value: $appSettings.fantasyLineupLimit, in: 1...15)
                    Stepper("Bench: \(appSettings.fantasyBenchLimit)",
                            value: $appSettings.fantasyBenchLimit, in: 0...10)
                    Stepper("IR: \(appSettings.fantasyIRLimit)",
                            value: $appSettings.fantasyIRLimit, in: 0...5)
                } header: {
                    Text("Roster Limits")
                } footer: {
                    Text("Total roster size: \(appSettings.fantasyRosterLimits.total). Standard divide is 10 lineup · 3 bench · 1 IR. Players assign to slots on the team page.")
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
