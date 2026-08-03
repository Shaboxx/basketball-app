import Foundation
import Combine

/// Drives the Teams-grid "selection mode" that replaces the old Trade tab.
/// Kept as a tiny, view-free `ObservableObject` so the toggle / max-6 /
/// can-begin rules are unit-testable without standing up any SwiftUI view.
@MainActor
final class TradeSelectionState: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    static let maxTeams = 6

    /// Result of a `toggle` so the view can react (show the max-teams alert).
    enum ToggleResult: Equatable {
        case added
        case removed
        /// Adding a NEW id would push past `maxTeams`; the set is unchanged.
        case rejectedMax
    }

    /// True while the Teams grid is in selection mode (tiles toggle instead of
    /// navigating).
    @Published var isSelecting = false

    /// Selected team ids, in tap order (so the machine seats them predictably).
    @Published var selectedTeamIds: [String] = []

    var maxTeams: Int { Self.maxTeams }

    /// At least two teams are required before a trade can begin.
    var canBegin: Bool { selectedTeamIds.count >= 2 }

    /// Toggle a team's membership. Removing an already-selected id always
    /// succeeds; adding a new id is rejected (`.rejectedMax`) when already at
    /// `maxTeams`, leaving the set unchanged.
    @discardableResult
    func toggle(_ id: String) -> ToggleResult {
        if let idx = selectedTeamIds.firstIndex(of: id) {
            selectedTeamIds.remove(at: idx)
            return .removed
        }
        guard selectedTeamIds.count < maxTeams else {
            return .rejectedMax
        }
        selectedTeamIds.append(id)
        return .added
    }

    func isSelected(_ id: String) -> Bool {
        selectedTeamIds.contains(id)
    }

    /// Enter selection mode with a clean slate.
    func begin() {
        selectedTeamIds.removeAll()
        isSelecting = true
    }

    /// Exit selection mode and clear selections.
    func cancel() {
        isSelecting = false
        selectedTeamIds.removeAll()
    }

    /// Drop all selections without leaving selection mode.
    func clear() {
        selectedTeamIds.removeAll()
    }
}
