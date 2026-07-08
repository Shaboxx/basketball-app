import Foundation
import Combine

/// The app-wide fantasy load phase. Top-level (NOT nested in the @MainActor store)
/// so `FantasyEmptyState.decide` and its test stay cleanly off the MainActor.
nonisolated enum FantasyPhase: Equatable { case idle, loading, loaded, empty, failed }

/// Loads the whole `fantasyValues` collection (+ `_meta`) once and serves per-slug
/// lookups, keyed by canonical (period-stripped) slug. Mirrors `LeagueNormsViewModel`
/// + the `PlayersViewModel.load()` guard (idempotent load-once).
@MainActor
final class FantasyValueStore: ObservableObject {
    @Published private(set) var values: [String: FantasyValue] = [:]
    @Published private(set) var meta: FantasyMeta?
    @Published private(set) var phase: FantasyPhase = .idle

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        // Load-once, but allow a RETRY after a failed fetch — with lazy loading the first
        // fetch happens on the user's fantasy-mode toggle, so a transient failure must be
        // recoverable (re-toggle / foreground refresh) without an app relaunch.
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let (vals, m) = try await service.fetchFantasyValues()
            values = vals; meta = m
            phase = vals.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed
        }
    }

    func value(for slug: String) -> FantasyValue? { values[Self.canonicalSlug(slug)] }

    /// Port of the Python `canonical_slug`: strip ".", collapse doubled hyphens, trim
    /// edge hyphens — matches the period-stripped Firestore doc ids (e.g.
    /// "jaren-jackson-jr." → "jaren-jackson-jr"). nonisolated → unit-testable.
    nonisolated static func canonicalSlug(_ slug: String) -> String {
        guard !slug.isEmpty else { return slug }
        let noDots = slug.replacingOccurrences(of: ".", with: "")
        let collapsed = noDots.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
