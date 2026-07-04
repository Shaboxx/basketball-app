import Foundation
import FirebaseFirestore

/// A daily pick'em question (public read). Mirrors the `pickemQuestions` doc written by
/// scripts/generate_pickem.py + upload_pickem.py. Has `@DocumentID`, so — like `Comment` /
/// `Player` — it's MainActor-isolated (the property wrapper forbids `nonisolated`). Forgiving
/// optionals so schema drift never drops a whole doc.
struct PickemQuestion: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var type: String                          // game_winner | game_total | player_milestone
    var gameId: String
    var subject: String?                      // player canonical slug (milestone) or nil (game)
    var subjectName: String                   // display ("BOS @ NYK", player name)
    var stat: String?
    var threshold: Double?
    var sides: [String]                       // e.g. ["YES","NO"] / ["BOS","NYK"] / ["OVER","UNDER"]
    var impliedProbability: [String: Double]  // side -> baked implied prob
    var lockTime: Date                        // Firestore Timestamp -> absolute Date (UTC)
    var status: String                        // open | settled
    var result: String?                       // winning side, set at settlement
    var gameDate: String?                     // often ABSENT on the doc — see resolvedGameDate
    var source: String?

    enum QType: String { case gameWinner = "game_winner", gameTotal = "game_total", playerMilestone = "player_milestone" }
    var kind: QType? { QType(rawValue: type) }

    var isOpen: Bool { status == "open" }
    func isLocked(now: Date = Date()) -> Bool { now >= lockTime }
    func prob(for side: String) -> Double? { impliedProbability[side] }

    /// The `gameDate` the pick payload must carry: the question's field when present, else
    /// the UTC calendar date of `lockTime` — upload_pickem.py writes lockTime as
    /// "{game_date}T23:00:00+00:00", so its UTC day IS the game date.
    var resolvedGameDate: String {
        if let g = gameDate, !g.isEmpty { return g }
        return Self.utcDay.string(from: lockTime)
    }

    private static let utcDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// One placed pick (READ shape). `settled`/`delta` are set by the settlePickem CF, so both
/// are optional until settlement.
struct PickemPick: Codable, Identifiable, Hashable {
    @DocumentID var id: String?               // "{uid}_{questionId}"
    var uid: String
    var questionId: String
    var gameDate: String
    var side: String
    var stake: Int
    var createdAt: Date?
    var settled: Bool?
    var delta: Int?

    var isSettled: Bool { settled == true }
}

/// The WRITE intent — exactly the six keys the `pickemPicks` create rule allows. Plain
/// value type (no `@DocumentID`), so it's `nonisolated` + unit-testable; the service adds
/// `createdAt = serverTimestamp()` and writes to the deterministic doc id.
nonisolated struct PickemPickPayload: Equatable {
    var uid: String
    var questionId: String
    var gameDate: String
    var side: String
    var stake: Int

    /// Rules require the doc id == "{uid}_{questionId}".
    var docId: String { "\(uid)_\(questionId)" }
}

/// A player's cashless coin economy state (public read; the settlePickem CF is the sole
/// writer). No doc → the user is treated as a fresh account with WELCOME_COINS.
struct PickemUser: Codable, Identifiable, Hashable {
    @DocumentID var id: String?               // uid
    var coins: Int
    var correctCount: Int
    var totalSettled: Int
    var currentStreak: Int
    var handle: String?                       // denormalized by the CF on first settle
    var updatedAt: Date?

    var displayName: String { handle ?? "Player" }
    var accuracy: Double { totalSettled > 0 ? Double(correctCount) / Double(totalSettled) : 0 }
}
