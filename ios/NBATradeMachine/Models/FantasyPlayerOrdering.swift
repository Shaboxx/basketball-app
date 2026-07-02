import Foundation

/// Pure ordering for fantasy player lists: the active format's fantasy value,
/// DESCENDING. Players with no `fantasyValues` doc sink to the bottom; the name
/// tiebreak keeps the order stable and scannable.
nonisolated enum FantasyPlayerOrdering {

    static func byValue(_ players: [Player],
                        values: [String: FantasyValue],
                        format: FantasyFormat) -> [Player] {
        // Decorate-sort-undecorate: canonicalSlug runs a regex, so computing the
        // key INSIDE the comparator would cost ~2·n·log n regex evaluations per
        // sort (this runs per render in the players list / draft room).
        let keyed: [(player: Player, value: Double?)] = players.map { p in
            (p, values[FantasyValueStore.canonicalSlug(p.slug)].map { format.entry(in: $0).value })
        }
        return keyed.sorted { a, b in
            switch (a.value, b.value) {
            case let (x?, y?):
                if x != y { return x > y }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return a.player.name < b.player.name
        }.map(\.player)
    }
}
