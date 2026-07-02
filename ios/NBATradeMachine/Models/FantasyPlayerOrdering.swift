import Foundation

/// Pure ordering for fantasy player lists: the active format's fantasy value,
/// DESCENDING. Players with no `fantasyValues` doc sink to the bottom; the name
/// tiebreak keeps the order stable and scannable.
nonisolated enum FantasyPlayerOrdering {

    static func byValue(_ players: [Player],
                        values: [String: FantasyValue],
                        format: FantasyFormat) -> [Player] {
        func value(_ p: Player) -> Double? {
            values[FantasyValueStore.canonicalSlug(p.slug)].map { format.entry(in: $0).value }
        }
        return players.sorted { a, b in
            switch (value(a), value(b)) {
            case let (x?, y?):
                if x != y { return x > y }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return a.name < b.name
        }
    }
}
