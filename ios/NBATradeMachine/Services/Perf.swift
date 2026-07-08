import Foundation
import os

/// Lightweight performance instrumentation surfaced to Instruments (os_signpost) and the
/// unified log — near-zero cost (signposts are no-ops unless a trace is recording):
/// - a **LAUNCH interval** from app `didFinishLaunching` to the first screen's data being ready
///   (add the "os_signpost" / "App Launch" instrument, filter subsystem `com.nbatrademachine.perf`),
/// - a **main-thread HITCH watchdog** that logs + signposts when the main queue was blocked
///   longer than a threshold (a hang/hitch worth profiling with Time Profiler).
///
/// All state is touched only on the main thread (begin/end from launch + ContentView), so the
/// `nonisolated(unsafe)` statics are safe.
enum Perf {
    // `nonisolated` so the background hitch watchdog (also nonisolated) can read them; both are
    // immutable Sendable constants, so this is safe off the main actor.
    nonisolated private static let subsystem = "com.nbatrademachine.perf"
    nonisolated private static let signposter = OSSignposter(subsystem: subsystem, category: "Perf")

    nonisolated(unsafe) private static var launchState: OSSignpostIntervalState?
    nonisolated(unsafe) private static var launchStart: DispatchTime?
    nonisolated(unsafe) private static var watchdog: DispatchSourceTimer?

    /// Open the "AppLaunch" interval as early as possible (call from `didFinishLaunching`).
    static func beginLaunch() {
        guard launchState == nil else { return }
        launchStart = .now()
        launchState = signposter.beginInterval("AppLaunch")
    }

    /// Close the launch interval once the first screen's data is ready + log the duration.
    static func endLaunch() {
        guard let state = launchState else { return }
        signposter.endInterval("AppLaunch", state)
        launchState = nil
        if let start = launchStart {
            let ms = Int(Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)
            Logger(subsystem: subsystem, category: "Launch").notice("App launch → first content: \(ms, privacy: .public) ms")
        }
    }

    /// Start a 1 Hz main-thread stall watchdog: a background timer pings the main queue and,
    /// when the ping was delayed beyond `threshold`, logs + emits a signpost event. Idempotent.
    ///
    /// `nonisolated` is load-bearing: the enum is `@MainActor` by default (MainActor-default
    /// isolation), so a plain method here would make the `setEventHandler` closure inherit
    /// MainActor isolation. The dispatch timer then runs that closure on the background
    /// `perf.hitch` queue, the Swift runtime asserts it's on the main executor, and traps
    /// (`EXC_BREAKPOINT` at launch). Marking the method `nonisolated` keeps the handler
    /// closures off the main executor, which is exactly where the timer fires them.
    nonisolated static func startHitchWatchdog(threshold: TimeInterval = 0.25) {
        guard watchdog == nil else { return }
        let log = Logger(subsystem: subsystem, category: "Hitch")
        let sp = signposter
        let thresholdMs = threshold * 1000
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "perf.hitch", qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 1)
        timer.setEventHandler {
            let sent = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async {
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- sent) / 1_000_000
                if ms > thresholdMs {
                    log.warning("Main-thread hitch: \(Int(ms), privacy: .public) ms")
                    sp.emitEvent("MainThreadHitch")
                }
            }
        }
        timer.resume()
        watchdog = timer
    }
}
