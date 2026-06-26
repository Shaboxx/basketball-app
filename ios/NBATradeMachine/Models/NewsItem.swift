import Foundation

/// A news item from the Firestore `news` collection (written by SP1's
/// scripts/news pipeline). Plain Codable — the `id` field equals the doc id, so
/// no @DocumentID is needed and it decodes from JSON in tests.
nonisolated struct NewsItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let source: String
    let summary: String
    let publishedAt: String      // ISO-8601 UTC, e.g. "2026-06-24T15:04:00Z"
    let playerSlugs: [String]

    // Cluster fields (live, ranked news). Optional so legacy per-item docs still decode.
    let firstSeenAt: String?
    let sourceCount: Int?
    let hotnessScore: Double?
    let sources: [NewsSource]?

    /// True when the story is corroborated by more than one feed (drives the chip).
    var isMultiSource: Bool { (sourceCount ?? 1) > 1 }

    /// The publisher URL, but only when it is a real http(s) link — guards
    /// against `javascript:`/non-web schemes so a row is never a tap hazard.
    var articleURL: URL? {
        guard let u = URL(string: url),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return u
    }

    var relativeDate: String { NewsDateFormatter.relative(from: publishedAt) }
}

/// One corroborating source within a news cluster.
nonisolated struct NewsSource: Codable, Hashable {
    let name: String
    let url: String
    let publishedAt: String
}

/// Sort mode for the league news feed.
nonisolated enum NewsSort: String, CaseIterable, Identifiable {
    case top, newest
    var id: String { rawValue }
    var label: String { self == .top ? "Top" : "Newest" }
    var field: String { self == .top ? "hotnessScore" : "publishedAt" }
}

/// `meta/hotPlayers` — the top players by current news heat (written by ingestNews).
nonisolated struct HotPlayers: Codable { let players: [HotPlayer] }

nonisolated struct HotPlayer: Codable, Identifiable, Hashable {
    let slug: String
    let name: String
    let heat: Double
    var id: String { slug }
}

/// ISO-8601 -> "2h ago" / "Jun 24". SP1 emits `%Y-%m-%dT%H:%M:%SZ` (no
/// fractional seconds); we also accept fractional, and fall back to the
/// `YYYY-MM-DD` prefix so it never crashes on bad input.
nonisolated enum NewsDateFormatter {
    // nonisolated(unsafe): these formatters are configured once and only read
    // (formatting/parsing) thereafter, so sharing them across isolation is safe.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()

    static func relative(from iso: String) -> String {
        guard let date = Self.iso.date(from: iso) ?? Self.isoFractional.date(from: iso) else {
            return String(iso.prefix(10))
        }
        // Clamp to now: a just-published item under positive server-clock skew
        // would otherwise render future-tense ("in 2 min"). Collapse to "now".
        let now = Date()
        return Self.rel.localizedString(for: min(date, now), relativeTo: now)
    }
}
