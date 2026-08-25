import Foundation

/// Deterministic splitmix64 RNG. Game state carries this value so CPU picks and
/// random offers replay identically from a seed — and so a future online session
/// can sync by seed instead of by streaming random values (roadmap Phase 7).
nonisolated struct SeededRNG: RandomNumberGenerator, Codable, Equatable {
    private(set) var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
