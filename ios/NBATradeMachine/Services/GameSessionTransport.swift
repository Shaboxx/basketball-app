import Foundation

/// Errors surfaced by the online game-session seam (callables + listeners).
/// Mirrors `HostedError`: each case maps a Cloud Function error-dict `type`
/// string so the store can present a human message without importing Firebase.
nonisolated enum GameSessionTransportError: Error, Equatable {
    case unauthenticated, notFound, full, notYourTurn, gameOver, conflict, badInput
    case network(String), unknown

    var message: String {
        switch self {
        case .unauthenticated: return "Sign in with Apple to play online."
        case .notFound:        return "No game found for that code."
        case .full:            return "That game is already full."
        case .notYourTurn:     return "It's not your turn."
        case .gameOver:        return "This game has already finished."
        case .conflict:        return "That couldn't be completed — the game may have moved on. It'll refresh."
        case .badInput:        return "That action wasn't valid."
        case .network(let m):  return "Network error: \(m)"
        case .unknown:         return "Something went wrong. Try again."
        }
    }

    /// Map a Cloud Function error dict `type` to a case (mirrors HostedError.from).
    static func from(type: String?) -> GameSessionTransportError {
        switch type {
        case "unauthenticated": return .unauthenticated
        case "not_found":       return .notFound
        case "full":            return .full
        case "not_your_turn":   return .notYourTurn
        case "game_over":       return .gameOver
        case "conflict":        return .conflict
        case "bad_input":       return .badInput
        default:                return .unknown
        }
    }
}

/// Opaque handle so the store can tear down a session listener without importing
/// Firestore. `nonisolated` + `Sendable` so the store's (nonisolated) `deinit`
/// can read the token and `stop()` it — same shape as `HostedListenerToken`.
nonisolated protocol GameSessionListenerToken: Sendable { func stop() }
nonisolated struct NoopGameSessionToken: GameSessionListenerToken { func stop() {} }

/// The online game-session write + real-time-read seam (Sol Fork-1: server-
/// authoritative full-state doc, clients listen only). The four callables route
/// to gated Cloud Functions that run the SAME pure roster engine in a
/// transaction; `listenSession` attaches a snapshot listener and hands back a
/// token the store owns + stops. Mockable so `OnlineGameSessionStore` is
/// unit-tested with no Firebase. Mirrors `HostedLeagueWriting` exactly.
///
/// FUTURE MATCHMAKING SEAM (Sol Fork-4, intentionally absent now): a quick-match
/// queue drops in as a fifth method on THIS protocol — e.g.
/// `func enqueueMatch(definitionId:) async throws -> String  // sessionId`
/// backed by a `matchmaking` CF + queue collection — without touching the store's
/// create/join code path. It is deliberately NOT declared until the queue
/// lifecycle (abandonment, concurrency) is designed; the join-code path ships
/// complete instead of shipping dead scaffolding.
@MainActor
protocol GameSessionTransport: Sendable {
    /// Mint a code, write `gameSessions/{id}` with the host's frozen initial state,
    /// and return the new session id + shareable join code. The HOST builds the
    /// initial `RosterGameState` locally (definition + the frozen pool + seat count
    /// + seed, via the shipped engine) and the CF stores it as the authoritative
    /// starting state; every SUBSEQUENT action is CF-validated server-side against
    /// this frozen state (Sol Fork-1). `humanSeats` is the number of human seats to
    /// leave open in the lobby (the state already encodes the seat/participant count).
    func createSession(definitionId: String, seed: UInt64,
                       humanSeats: Int, cpuSeats: Int,
                       pickSeconds: Int,
                       initialState: RosterGameState) async throws -> (id: String, joinCode: String)
    /// Join an open lobby by code; claims the next open human seat. Returns the session id.
    func joinSession(code: String) async throws -> String
    /// Submit a turn action (pick / reroll) for `seat`; the CF verifies it's the
    /// caller's turn, runs the engine, and writes the whole new state.
    func submitAction(sessionId: String, seat: Int, kind: GameSessionActionKind) async throws
    /// Fire the server-side auto-advance when a pick clock expires. ANY member may
    /// call it; the CF re-checks the real deadline in a transaction, so an early /
    /// racing call is a harmless no-op. `expectedTurnIndex` is the engine turn the
    /// caller OBSERVED when it armed the timer; the CF rejects (conflict) if the game
    /// has since moved on, so a stale timer can't clobber a later turn.
    func autoAdvance(sessionId: String, expectedTurnIndex: Int) async throws
    /// Attach a snapshot listener on `gameSessions/{id}`; `onChange` fires with the
    /// decoded doc (or nil if it's gone / undecodable). Returns a token the store retains + stops.
    func listenSession(_ id: String,
                       onChange: @escaping @MainActor (GameSessionDoc?) -> Void) -> GameSessionListenerToken
}

/// Test double: an in-memory transport that drives the store without Firebase.
/// Seed a `doc`, then `submitAction`/`autoAdvance` mutate it and re-deliver to the
/// retained `onChange`, so a test can walk lobby→active→picks→auto-pick→finished
/// deterministically. Every call is captured for assertions, and each callable's
/// result is overridable (inject success ids or an error). It does NOT run the
/// engine itself — the test seeds each `nextDoc` it wants delivered — so the
/// store is exercised purely as a render-only listener (the real authority is the
/// CF, mirrored here by the test's scripted docs).
@MainActor
final class MockGameSessionTransport: GameSessionTransport {
    /// Canned callable results.
    var createResult: Result<(id: String, joinCode: String), Error> = .success(("S1", "ABC234"))
    var joinResult: Result<String, Error> = .success("S1")
    /// If set, `submitAction` / `autoAdvance` throw it instead of applying `nextDoc`.
    var submitError: Error?
    var autoError: Error?

    /// The doc the listener currently holds; `deliver(_:)` publishes a new one.
    var doc: GameSessionDoc?
    /// The doc a successful `submitAction` should deliver next (test scripts the
    /// authoritative result). When nil, `submitAction` leaves the doc unchanged.
    var nextDocOnSubmit: GameSessionDoc?
    /// The doc a successful `autoAdvance` delivers next (nil = unchanged).
    var nextDocOnAuto: GameSessionDoc?

    // Captures.
    private(set) var created: [(definitionId: String, seed: UInt64, humanSeats: Int, cpuSeats: Int, pickSeconds: Int)] = []
    private(set) var createdStates: [RosterGameState] = []
    private(set) var joined: [String] = []
    private(set) var submitted: [(seat: Int, kind: GameSessionActionKind)] = []
    private(set) var autoAdvances = 0
    /// The `expectedTurnIndex` passed to each `autoAdvance` call (for assertions).
    private(set) var autoAdvanceTurns: [Int] = []
    /// Retained so a test can replay a late/superseded delivery.
    private(set) var lastOnChange: (@MainActor (GameSessionDoc?) -> Void)?

    func createSession(definitionId: String, seed: UInt64,
                       humanSeats: Int, cpuSeats: Int,
                       pickSeconds: Int,
                       initialState: RosterGameState) async throws -> (id: String, joinCode: String) {
        created.append((definitionId, seed, humanSeats, cpuSeats, pickSeconds))
        createdStates.append(initialState)
        return try createResult.get()
    }

    func joinSession(code: String) async throws -> String {
        joined.append(code); return try joinResult.get()
    }

    func submitAction(sessionId: String, seat: Int, kind: GameSessionActionKind) async throws {
        submitted.append((seat, kind))
        if let submitError { throw submitError }
        if let next = nextDocOnSubmit { deliver(next) }
    }

    func autoAdvance(sessionId: String, expectedTurnIndex: Int) async throws {
        autoAdvances += 1
        autoAdvanceTurns.append(expectedTurnIndex)
        if let autoError { throw autoError }
        if let next = nextDocOnAuto { deliver(next) }
    }

    func listenSession(_ id: String,
                       onChange: @escaping @MainActor (GameSessionDoc?) -> Void) -> GameSessionListenerToken {
        lastOnChange = onChange
        onChange(doc)                  // immediate first delivery, like Firestore
        return NoopGameSessionToken()
    }

    /// Publish a new doc to the retained listener (and remember it as `doc`).
    func deliver(_ new: GameSessionDoc?) {
        doc = new
        lastOnChange?(new)
    }
}
