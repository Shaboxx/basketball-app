import SwiftUI

/// Status tags shown as chips on PlayerDetailView. Extend this enum to
/// surface new player-status signals (DVPE, rookie scale, 10-year vet, etc.)
/// without changing the chip-rendering code.
enum PlayerTag: String, Hashable {
    case supermax

    var label: String {
        switch self {
        case .supermax: return "Supermax"
        }
    }

    var background: Color {
        switch self {
        case .supermax: return .purple
        }
    }

    var foreground: Color {
        switch self {
        case .supermax: return .white
        }
    }
}

extension Player {
    /// All player status tags currently applicable. Empty if none.
    var playerTags: [PlayerTag] {
        var tags: [PlayerTag] = []
        if supermaxEligible == true { tags.append(.supermax) }
        return tags
    }
}
