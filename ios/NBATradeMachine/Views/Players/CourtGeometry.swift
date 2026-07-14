import CoreGraphics

/// PURE half-court geometry: maps court coords (tenths-ft, hoop at origin, y up toward
/// the half-court line; x in [-250,250], y in [-48,422]) into a SwiftUI frame, and
/// provides zone centroids for FG% overlays. Same numeric contract as shotmaps/court.py.
nonisolated enum CourtGeometry {
    static let xMin: CGFloat = -250, xMax: CGFloat = 250
    static let yMin: CGFloat = -48,  yMax: CGFloat = 422
    static let zones = ["Restricted Area", "In The Paint (Non-RA)", "Mid-Range",
                        "Left Corner 3", "Right Corner 3", "Above the Break 3"]

    /// Court (x,y) -> view point. x maps left→right; y maps UP-in-court to TOP-of-view
    /// (SwiftUI y grows downward, so we invert).
    static func point(x: Int, y: Int, in rect: CGRect) -> CGPoint {
        let fx = (CGFloat(x) - xMin) / (xMax - xMin)          // 0..1 left→right
        let fy = (CGFloat(y) - yMin) / (yMax - yMin)          // 0..1 baseline→halfcourt
        return CGPoint(x: rect.minX + fx * rect.width,
                       y: rect.maxY - fy * rect.height)        // invert Y
    }

    /// Representative center of each zone (court coords) mapped into the frame.
    static func zoneCentroids(in rect: CGRect) -> [String: CGPoint] {
        let c: [String: (Int, Int)] = [
            "Restricted Area": (0, 15), "In The Paint (Non-RA)": (0, 110),
            "Mid-Range": (140, 160), "Left Corner 3": (-230, 40),
            "Right Corner 3": (230, 40), "Above the Break 3": (0, 270),
        ]
        return c.mapValues { point(x: $0.0, y: $0.1, in: rect) }
    }
}
