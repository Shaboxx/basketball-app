import Foundation

/// The single shared source of the 2/3 shot-value geometry (F10). Mirrors the arc/corner
/// geometry CourtLines.swift draws, but uses the GEOMETRICALLY EXACT corner/arc intersection
/// y* (not CourtLines's rounded drawing convenience 88). Python league_field.py mirrors these
/// three constants byte-for-byte for the cross-language classifier contract.
nonisolated enum CourtThreeGeometry {
    static let arcRadius = 237.5
    static let cornerX = 220.0
    static let cornerYStar = 89.4776508408664   // sqrt(237.5^2 - 220^2), exact
    // NOTE: CourtLines.swift draws the arc/corner with a rounded y = 88 (a sanctioned
    // drawing-only approximation): it diverges from cornerYStar by < 1.5 court units
    // (< 2 pt on screen) and is NOT shared with the classifier. This round does NOT modify
    // CourtLines.swift.
}
