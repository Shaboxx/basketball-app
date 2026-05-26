import Foundation

extension Player {
    private static let isoFullDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// Whole-year age computed from `birthdate` against the given reference date.
    /// Returns nil if `birthdate` is missing or unparseable.
    func age(asOf date: Date = Date()) -> Int? {
        guard let birthdate,
              let dob = Self.isoFullDate.date(from: birthdate) else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: date).year
    }

    /// Formats `cbaSeason + offset` as the season label.
    /// Example: cbaSeason="2025-26", offset=1 → "2026-27".
    /// Returns nil if `cbaSeason` is missing or malformed.
    func seasonLabel(forOffset offset: Int) -> String? {
        guard let cbaSeason,
              let dashIdx = cbaSeason.firstIndex(of: "-"),
              let startYear = Int(cbaSeason[..<dashIdx]) else { return nil }
        let newStart = startYear + offset
        let newEnd = (newStart + 1) % 100
        return "\(newStart)-\(String(format: "%02d", newEnd))"
    }

    /// "YYYY-YY" label for the season the current contract expires.
    /// Example: contractFinalYearSeasonEnd=2027 → "2026-27".
    var contractExpirySeason: String? {
        guard let end = contractFinalYearSeasonEnd else { return nil }
        let start = end - 1
        return "\(start)-\(String(format: "%02d", end % 100))"
    }

    /// Short form with leading apostrophe: "'26-27".
    var contractExpirySeasonShort: String? {
        guard let end = contractFinalYearSeasonEnd else { return nil }
        let startSuffix = (end - 1) % 100
        return "'\(String(format: "%02d", startSuffix))-\(String(format: "%02d", end % 100))"
    }

    /// "YYYY-YY" label for the season the projected next contract would start.
    /// Example: contractFinalYearSeasonEnd=2027 → "2027-28".
    var projectedContractStartSeason: String? {
        guard let end = contractFinalYearSeasonEnd else { return nil }
        let nextEnd = (end + 1) % 100
        return "\(end)-\(String(format: "%02d", nextEnd))"
    }

    /// Relative time string for `cbaUpdatedAt` (e.g. "2 days ago").
    /// Returns nil if `cbaUpdatedAt` is nil.
    var cbaUpdatedRelative: String? {
        guard let cbaUpdatedAt else { return nil }
        return Self.relFormatter.localizedString(for: cbaUpdatedAt, relativeTo: Date())
    }
}
