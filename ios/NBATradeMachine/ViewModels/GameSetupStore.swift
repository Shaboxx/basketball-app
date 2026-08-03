import Foundation
import SwiftUI
import Combine

/// Local (UserDefaults-backed) cache of each game's last-used setup. One
/// `GameSetupSettings` per game under the versioned key `gameSetup.v1.<gameId>`.
/// No published array (settings are read on demand per game); mirrors
/// `FantasyTeamStore`'s injectable-`defaults` seam. No Firestore, no network.
@MainActor
final class GameSetupStore: ObservableObject {
    private static let keyPrefix = "gameSetup.v1."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ gameId: String) -> String { Self.keyPrefix + gameId }

    /// The cached settings for a game, CLAMPED to the game's current capabilities
    /// (limits may have tightened since the last save). Absent → the 2/0/local
    /// default, itself clamped.
    func settings(for gameId: String, capabilities: SetupCapabilities) -> GameSetupSettings {
        let raw: GameSetupSettings
        if let data = defaults.data(forKey: key(gameId)),
           let decoded = try? JSONDecoder().decode(GameSetupSettings.self, from: data) {
            raw = decoded
        } else {
            raw = .default
        }
        return Self.clamped(raw, to: capabilities)
    }

    /// Persist a game's settings (clamped first, so we never store an illegal pair).
    func save(_ settings: GameSetupSettings, for gameId: String,
              capabilities: SetupCapabilities) {
        let safe = Self.clamped(settings, to: capabilities)
        if let data = try? JSONEncoder().encode(safe) {
            defaults.set(data, forKey: key(gameId))
        }
    }

    /// Pure clamp of a settings blob to capabilities: counts via
    /// `SetupCapabilities.clamp`, play mode forced to `.soloVsCPU` if local
    /// friends aren't allowed (and to `.localFriends` if CPUs aren't allowed and
    /// the stored mode was solo-vs-CPU).
    private static func clamped(_ s: GameSetupSettings,
                                to caps: SetupCapabilities) -> GameSetupSettings {
        let counts = caps.clamp(humans: s.humanCount, cpus: s.cpuCount)
        var mode = s.playMode
        if mode == .localFriends && !caps.allowsLocalFriends { mode = .soloVsCPU }
        if mode == .soloVsCPU && !caps.allowsCPU { mode = .localFriends }
        return GameSetupSettings(humanCount: counts.humans, cpuCount: counts.cpus, playMode: mode)
    }
}
