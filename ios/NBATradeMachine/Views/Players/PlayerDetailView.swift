import SwiftUI

struct PlayerDetailView: View {
    let player: Player

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeadshotImage(slug: player.slug, size: 160)
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(player.name).font(.title.bold())
                    Text("\(player.teamId) · \(player.position)")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    stat("Height", player.heightDisplay)
                    stat("Weight", player.weightLbs.map { "\($0) lb" } ?? "—")
                }

                VStack(alignment: .leading, spacing: 6) {
                    label("Primary role", player.primaryRole ?? "—")
                    label("Secondary role", player.secondaryRole ?? "—")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Salary").font(.headline)
                    salaryRow("Year 1 (2025-26)", player.salaryY1)
                    salaryRow("Year 2", player.salaryY2)
                    salaryRow("Year 3", player.salaryY3)
                    salaryRow("Year 4", player.salaryY4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func label(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }

    private func salaryRow(_ label: String, _ amount: Int?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(Money.display(amount)).monospacedDigit().bold()
        }
    }
}
