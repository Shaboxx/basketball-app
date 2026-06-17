import SwiftUI

struct OffseasonListsView: View {
    let summary: OffseasonSummary

    var body: some View {
        List {
            Section("Unsigned free agents") {
                if summary.unsignedFAs.isEmpty { Text("None.").foregroundStyle(.secondary) }
                ForEach(summary.unsignedFAs) { fa in
                    HStack {
                        Text(fa.name.isEmpty ? offseasonDisplayName(fa.playerId) : fa.name)
                        Spacer()
                        if let t = fa.faType { Text(t).font(.caption).foregroundStyle(.secondary) }
                        if let tm = fa.team { Text(tm).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Untraded blocks") {
                if summary.untradedBlocks.isEmpty { Text("None.").foregroundStyle(.secondary) }
                ForEach(summary.untradedBlocks) { b in
                    HStack {
                        Text(offseasonDisplayName(b.playerId)); Spacer()
                        Text(b.team).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Free agents & blocks")
    }
}
