import SwiftUI

struct TeamPickerView: View {
    let label: String
    let teams: [Team]
    @Binding var selection: Team?

    var body: some View {
        Menu {
            Button("None") { selection = nil }
            Divider()
            ForEach(teams) { team in
                Button(team.fullName) { selection = team }
            }
        } label: {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                if let s = selection {
                    Text(s.fullName).bold()
                } else {
                    Text("Select").bold().foregroundStyle(.blue)
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
