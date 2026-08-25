import Foundation

/// A maskable facet of an entity (spec §10 field-specific visibility). `identity`
/// is the player's name; the rest mirror `GameField`.
nonisolated enum EntityFacet: String, Codable, Equatable {
    case identity, team, position, salary, rating
}

/// When an entity's hidden facets become visible (spec §10 subset). `full` =
/// always visible (Phase-1 default). `afterSlotAssignment` = hidden until the
/// entity is placed in a slot (Blind Draft).
nonisolated enum RevealMode: String, Codable, Equatable {
    case full
    case afterSlotAssignment
}

/// A blind-information modifier (spec §10). Optional on `GameDefinition`; absent
/// or `.full` = nothing masked. Presentation-only: the engine never reads it;
/// the view masks the listed facets of an offered-but-unplaced entity.
nonisolated struct RevealConfig: Codable, Equatable {
    let mode: RevealMode
    let hidden: Set<EntityFacet>

    /// Should `facet` be masked while an entity is still unplaced?
    func masks(_ facet: EntityFacet) -> Bool {
        mode == .afterSlotAssignment && hidden.contains(facet)
    }
}

/// A special-actions modifier (spec §12 subset). Phase 2 ships REROLL only;
/// the struct grows (vetoes/skips) when a game needs them. Optional on
/// `GameDefinition`; absent = no special actions.
nonisolated struct SpecialActionsConfig: Codable, Equatable {
    let rerolls: Int
}
