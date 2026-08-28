import Foundation
import Combine

@MainActor
final class PlayersViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
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
            case .totalSigmaDesc: return "SwishScore"
            case .offSigmaDesc: return "Offense"
            case .defSigmaDesc: return "Defense"
            case .salaryDesc: return "Salary"
            }
        }
    }

    @Published var players: [Player] = []
    @Published var searchText = ""
    /// Default NBA sort is Total σ (alphabetical is a menu option, not the default).
    /// Persisted so the user's sort survives tab switches / relaunches (NAV-05).
    @Published var sortMode: SortMode = .totalSigmaDesc {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: Self.sortKey) }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasLoaded = false

    private static let sortKey = "playersSortMode"
    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) {
        self.service = service
        if let raw = UserDefaults.standard.string(forKey: Self.sortKey),
           let saved = SortMode(rawValue: raw) {
            sortMode = saved
        }
    }

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
        defer { hasLoaded = true }
        do {
            let p = try await service.fetchPlayers()
            self.players = p.sorted { $0.name < $1.name }
            self.playersVersion += 1
            errorMessage = nil   // clear a prior failure on success (matches Teams/News reload())
        } catch {
            errorMessage = FriendlyError.message(error)
        }
    }

    /// Seed from an already-loaded roster set (the Players tab shares TeamsViewModel's
    /// single players fetch instead of re-reading the whole collection). `filtered`
    /// re-sorts per `sortMode`, so order here only sets the default name display.
    func adopt(_ players: [Player]) {
        self.players = players.sorted { $0.name < $1.name }
        self.playersVersion += 1
        self.isLoading = false
        self.hasLoaded = true   // a completed adopt IS a completed load (games latch empty-vs-loading on this)
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

    /// Fantasy-value ordering over `filtered`, memoized on (playersVersion, query, sort,
    /// values-count). Otherwise `PlayersListView` re-runs it every render on a PRIMARY tab — an
    /// O(n log n) sort plus a regex `canonicalSlug` per ~500 players — on every keystroke and every
    /// unrelated store change. `values.count` is a cheap version proxy (the map loads once).
    private var _fantasyOrdered: [Player]?
    private var _fantasyOrderedKey: String?
    func fantasyOrdered(sort: String, values: [String: FantasyValue], format: FantasyFormat) -> [Player] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let key = "\(playersVersion)|\(q)|\(sort)|\(values.count)"
        if _fantasyOrderedKey == key, let cached = _fantasyOrdered { return cached }
        let result = FantasyPlayerOrdering.byValue(filtered, values: values, format: format)
        _fantasyOrdered = result
        _fantasyOrderedKey = key
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
