import Foundation

extension Player {
    /// The model contract verdict reframed into an actionable conclusion.
    ///
    /// For an "overpriced" verdict ("Walk …" / "Negotiate Down …") this
    /// replaces the blunt walk-away with the model's *suggested correct price*
    /// — the cost-cone point clamped into the player's CBA salary window
    /// `[minSalary, standardMax]` — e.g. `"Overpriced — fair value ≈ $24.0M"`.
    /// Undervalued / fair verdicts pass through unchanged. Trust suffixes
    /// (`"(low confidence)"` / `"(model unreliable)"`) are preserved. Returns
    /// `nil` when there is no verdict.
    var contractConclusion: String? {
        guard let raw = compZ?.verdict, !raw.isEmpty else { return nil }

        // Split the base verdict from any "( … )" trust-suffix tail so the
        // suffixes survive the reframe ("(low confidence)" etc.).
        let base: String
        let suffix: String
        if let paren = raw.firstIndex(of: "(") {
            base = String(raw[..<paren]).trimmingCharacters(in: .whitespaces)
            suffix = String(raw[paren...])
        } else {
            base = raw
            suffix = ""
        }

        // Only the overpriced verdicts become a price suggestion; undervalued /
        // fair / max-tier verdicts already read as constructive conclusions.
        let isOverpriced = base.hasPrefix("Walk") || base.hasPrefix("Negotiate Down")
        guard isOverpriced, let point = compZ?.cost?.pointDollars, point > 0 else {
            return raw
        }

        // Clamp the suggestion into the CBA window so the "correct price" is
        // always a legal salary (never below the minimum or above the max).
        let lo = minSalary ?? 0
        let hi = standardMax ?? Int.max
        let fair = min(max(point, lo), hi)

        let suggestion = "Overpriced — fair value ≈ \(Money.display(fair))"
        return suffix.isEmpty ? suggestion : "\(suggestion) \(suffix)"
    }
}
