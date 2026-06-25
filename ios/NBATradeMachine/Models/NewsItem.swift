import Foundation

/// A news item from the Firestore `news` collection (written by SP1's
/// scripts/news pipeline). Plain Codable — the `id` field equals the doc id, so
/// no @DocumentID is needed and it decodes from JSON in tests.
struct NewsItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let source: String
    let summary: String
    let publishedAt: String      // ISO-8601 UTC, e.g. "2026-06-24T15:04:00Z"
    let playerSlugs: [String]

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

/// ISO-8601 -> "2h ago" / "Jun 24". SP1 emits `%Y-%m-%dT%H:%M:%SZ` (no
/// fractional seconds); we also accept fractional, and fall back to the
/// `YYYY-MM-DD` prefix so it never crashes on bad input.
enum NewsDateFormatter {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let rel: RelativeDateTimeFormatter = {
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
