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
    /// Default NBA sort is Total σ (alphabetical is a menu option, not the default).
    @Published var sortMode: SortMode = .totalSigmaDesc
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    /// Bumped whenever `players` is reassigned — part of the `filtered` cache key
    /// so a roster reload invalidates the memoized result.
    private var playersVersion = 0
    /// Memoized `filtered` result + the key it was computed for. Plain (non-@Published)
    /// so writing the cache from the getter doesn't trigger objectWillChange.
    private var _filtered: [Player]?
    private var _filteredKey: String?

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
            self.playersVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Seed from an already-loaded roster set (the Players tab shares TeamsViewModel's
    /// single players fetch instead of re-reading the whole collection). `filtered`
    /// re-sorts per `sortMode`, so order here only sets the default name display.
    func adopt(_ players: [Player]) {
        self.players = players.sorted { $0.name < $1.name }
        self.playersVersion += 1
        self.isLoading = false
        self.errorMessage = nil
    }

    /// Filter (by search) + sort (by `sortMode`) over the full player set. Memoized
    /// on (playersVersion, sortMode, query): SwiftUI re-evaluates `body` for reasons
    /// unrelated to these inputs, and recomputing the filter+sort over the whole
    /// league each time is wasted work. The cache returns the prior result until one
    /// of the three inputs actually changes.
    var filtered: [Player] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let cacheKey = "\(playersVersion)|\(sortMode.rawValue)|\(q)"
        if _filteredKey == cacheKey, let cached = _filtered { return cached }
        let base: [Player] = q.isEmpty
            ? players
            : players.filter { $0.name.lowercased().contains(q) }
        let result = sorted(base)
        _filtered = result
        _filteredKey = cacheKey
        return result
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
