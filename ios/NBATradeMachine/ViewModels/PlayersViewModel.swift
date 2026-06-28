import Foundation
import Combine

@MainActor
final class PlayersViewModel: ObservableObject {
    enum SortMode: String, CaseIterable, Identifiable {
        case name
        case totalSigmaDesc
        case offSigmaDesc
        case defSigmaDesc
        case salaryDesc

        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name"
            case .totalSigmaDesc: return "Total σ"
            case .offSigmaDesc: return "OFF σ"
            case .defSigmaDesc: return "DEF σ"
            case .salaryDesc: return "Salary"
            }
        }
    }

    @Published var players: [Player] = []
    @Published var searchText = ""
    @Published var sortMode: SortMode = .name
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard players.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await service.fetchPlayers()
            self.players = p.sorted { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Seed from an already-loaded roster set (the Players tab shares TeamsViewModel's
    /// single players fetch instead of re-reading the whole collection). `filtered`
    /// re-sorts per `sortMode`, so order here only sets the default name display.
    func adopt(_ players: [Player]) {
        self.players = players.sorted { $0.name < $1.name }
        self.isLoading = false
        self.errorMessage = nil
    }

    var filtered: [Player] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let base: [Player] = q.isEmpty
            ? players
            : players.filter { $0.name.lowercased().contains(q) }
        return sorted(base)
    }

    /// Sort sentinel: pick a value missing-σ players will lose to, so they sink
    /// to the bottom under any σ-descending sort.
    private static let missingSigmaSentinel = -Double.infinity

    private func sorted(_ list: [Player]) -> [Player] {
        switch sortMode {
        case .name:
            return list.sorted { $0.name < $1.name }
        case .totalSigmaDesc:
            return list.sorted { lhs, rhs in
                key(lhs, \.dispTotal) > key(rhs, \.dispTotal)
            }
        case .offSigmaDesc:
            return list.sorted { lhs, rhs in
                key(lhs, \.dispOff) > key(rhs, \.dispOff)
            }
        case .defSigmaDesc:
            return list.sorted { lhs, rhs in
                key(lhs, \.dispDef) > key(rhs, \.dispDef)
            }
        case .salaryDesc:
            return list.sorted { ($0.currentSalary) > ($1.currentSalary) }
        }
    }

    private func key(_ p: Player, _ kp: KeyPath<Player, Double?>) -> Double {
        p[keyPath: kp] ?? Self.missingSigmaSentinel
    }
}
