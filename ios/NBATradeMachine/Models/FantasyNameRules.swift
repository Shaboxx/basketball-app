import Foundation

/// Pure name validation for user-entered fantasy names (teams, leagues, owners):
/// profanity screening + duplicate detection. The word list is a compact curated
/// subset of the de-facto-standard open-source LDNOOBW list ("List of Dirty,
/// Naughty, Obscene, and Otherwise Bad Words"), matched on NORMALIZED tokens
/// (lowercased, leet-mapped, split on non-alphanumerics) so "Sh1t Hawks" and
/// "s.h.i.t" are caught, while token matching keeps "Assist Kings" and
/// "Scunthorpe" clean. A short high-severity slur list is ALSO matched as a
/// substring of the fully-collapsed string (evasion via spacing), chosen so
/// substring false positives are implausible.
nonisolated enum FantasyNameRules {

    enum Verdict: Equatable { case ok, empty, profanity, duplicate }

    // MARK: Normalization

    private static let leet: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
        "$": "s", "@": "a", "!": "i",
    ]

    /// Lowercased, leet-mapped tokens split on every non-alphanumeric.
    static func tokens(_ s: String) -> [String] {
        let mapped = String(s.lowercased().map { leet[$0] ?? $0 })
        return mapped.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The whole string lowercased, leet-mapped, with separators removed.
    static func collapsed(_ s: String) -> String {
        tokens(s).joined()
    }

    // MARK: Word lists (curated LDNOOBW subset)

    /// Exact-token matches (word-level profanity; safe against embedded words).
    private static let profaneTokens: Set<String> = [
        "anal", "anus", "arse", "ass", "asshole", "ballsack", "bastard", "bitch",
        "bitches", "blowjob", "bollocks", "boner", "boob", "boobs", "bullshit",
        "clit", "cock", "coon", "cum", "cunt", "dick", "dickhead", "dildo",
        "douche", "fag", "faggot", "felch", "fellatio", "fuck", "fucker",
        "fucking", "goddamn", "handjob", "hoe", "homo", "jizz", "kike", "labia",
        "masturbate", "milf", "nutsack", "penis", "piss", "poon", "porn",
        "pube", "pussy", "queef", "rimjob", "scrotum", "shit", "shitty", "slut",
        "smegma", "spic", "tit", "tits", "twat", "vagina", "wank", "whore",
    ]

    /// High-severity slurs also caught as SUBSTRINGS of the collapsed string
    /// (spacing/punctuation evasion). Kept to strings where embedded false
    /// positives are implausible.
    private static let slurSubstrings: [String] = [
        "nigger", "nigga", "faggot", "beaner", "wetback", "chink", "gook",
        "kike", "tranny", "retard",
    ]

    // MARK: API

    /// Runs of CONSECUTIVE short tokens (≤2 chars) joined back together — the
    /// "s.h.i.t" / "fu-ck" spacing-evasion pattern. Long clean words never join
    /// ("Classy Cavs" produces no runs), so token-level false-positive safety holds.
    private static func evasionRuns(_ toks: [String]) -> [String] {
        var runs: [String] = []
        var current = ""
        for t in toks {
            if t.count <= 2 {
                current += t
            } else {
                if current.count >= 3 { runs.append(current) }
                current = ""
            }
        }
        if current.count >= 3 { runs.append(current) }
        return runs
    }

    static func containsProfanity(_ s: String) -> Bool {
        let toks = tokens(s)
        if toks.contains(where: profaneTokens.contains) { return true }
        if evasionRuns(toks).contains(where: { run in
            profaneTokens.contains(run) || profaneTokens.contains(where: run.contains)
        }) { return true }
        let flat = toks.joined()
        return slurSubstrings.contains { flat.contains($0) }
    }

    /// Commit-time hardening on top of `containsProfanity`: a name whose ANY
    /// token (≥4 chars) is a strict PREFIX of a profane token reads as
    /// profanity to a human even though the token itself is clean — the
    /// keystroke-persistence leak ("Fucke", "Asshol", "Shitt") the review
    /// found. Use THIS for every persist gate; the plain check is fine for
    /// live error display.
    static func readsProfane(_ s: String) -> Bool {
        if containsProfanity(s) { return true }
        return tokens(s).contains { t in
            t.count >= 4 && profaneTokens.contains { $0.count > t.count && $0.hasPrefix(t) }
        }
    }

    /// Case/spacing-insensitive duplicate check (normalized comparison).
    static func isDuplicate(_ name: String, in existing: [String]) -> Bool {
        let target = collapsed(name)
        guard !target.isEmpty else { return false }
        return existing.contains { collapsed($0) == target }
    }

    /// Full verdict for a proposed name against sibling names (e.g. the other
    /// team names in the same league).
    static func validate(name: String, existing: [String] = []) -> Verdict {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if containsProfanity(trimmed) { return .profanity }
        if isDuplicate(trimmed, in: existing) { return .duplicate }
        return .ok
    }
}
