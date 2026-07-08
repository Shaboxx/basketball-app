import Foundation

/// Maps raw errors to short, user-facing copy. Firestore surfaces a dead/flaky backend as
/// domain `FIRFirestoreErrorDomain` code 14 (unavailable); URL-loading failures come through
/// `NSURLErrorDomain`. Everything else gets a generic, non-alarming line — never the raw
/// `error.localizedDescription` (e.g. "…(FIRFirestoreErrorDomain error 14.)"), which is
/// meaningless to users and can't distinguish offline from server-down.
/// `nonisolated` (the enum is otherwise `@MainActor` by default under MainActor-default
/// isolation): it's a pure mapper with no state, callable from any context — VMs and tests alike.
nonisolated enum FriendlyError {
    static let offline = "Unable to connect. Check your network and try again."
    static let generic = "Something went wrong. Please try again in a moment."

    static func message(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return offline }
        if ns.domain == "FIRFirestoreErrorDomain" {
            switch ns.code {
            case 14: return offline                                // unavailable (offline / can't reach)
            case 4:  return "The server took too long. Try again." // deadline exceeded
            case 7:  return "Access denied."                       // permission denied
            case 16: return "Please sign in again."                // unauthenticated
            default: return generic
            }
        }
        return generic
    }

    /// Sign-in-flavored copy for the Apple + Firestore auth path. Returns `nil` when the failure
    /// is a user-initiated cancellation of the Apple sheet (`ASAuthorizationError.canceled`,
    /// code 1001) or an empty/unknown dismiss — those must NOT surface an alarming error.
    static func signInMessage(_ error: Error) -> String? {
        let ns = error as NSError
        if ns.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            switch ns.code {
            case 1001: return nil                        // canceled by the user (dismissed the sheet)
            case 1000: return nil                        // unknown — commonly a silent dismiss
            default:   return "Sign-in failed. Please try again."
            }
        }
        if ns.domain == NSURLErrorDomain { return "No connection — try again." }
        if ns.domain == "FIRFirestoreErrorDomain" || ns.domain == "FIRAuthErrorDomain" {
            switch ns.code {
            case 14: return "No connection — try again."
            case 7:  return "Sign-in denied."
            default: return "Sign-in failed. Please try again."
            }
        }
        return "Sign-in failed. Please try again."
    }
}
