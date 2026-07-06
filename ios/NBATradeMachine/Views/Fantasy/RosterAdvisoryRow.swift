import SwiftUI

/// A non-blocking orange advisory shown near a trade verdict when the deal would
/// leave a team over its roster-size limit (see FantasyRosterAdvisory). Reused by
/// every trade assembly/review surface so the warning reads identically.
struct RosterAdvisoryRow: View {
    let note: String
    var body: some View {
        Label(note, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityLabel("Roster warning: \(note)")
    }
}
