import SwiftUI

struct TradeHistorySheet: View {
    @ObservedObject var vm: TradeMachineViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.history.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock",
                        description: Text("Your trade actions will appear here.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(Array(vm.history.enumerated().reversed()), id: \.element.id) { index, entry in
                                Button {
                                    vm.undoTo(entryId: entry.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                        Text(entry.label).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } footer: {
                            Text("Tap an entry to revert to that state.")
                                .font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("Trade History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        vm.clearHistory()
                        dismiss()
                    } label: {
                        Text("Clear")
                    }
                    .disabled(vm.history.isEmpty)
                }
            }
        }
    }
}
