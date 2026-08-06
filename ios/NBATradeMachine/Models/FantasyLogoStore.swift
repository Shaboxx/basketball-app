import UIKit

/// Local storage for user-picked fantasy team logos: photo-library data is
/// normalized (downscaled + JPEG-recompressed) and written under Application
/// Support/FantasyLogos as `logo-<teamId>.jpg`. Pure file IO with an
/// injectable base directory for tests; the team model stores only the file
/// name, so blobs never enter UserDefaults.
nonisolated enum FantasyLogoStore {

    static let maxDimension: CGFloat = 512

    static func directory(base: URL? = nil) -> URL {
        // Fallback chain instead of a force-index: Application Support is effectively always
        // present, but a bad-index trap here would crash the fantasy team builder on logo save.
        let root = base
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = root.appendingPathComponent("FantasyLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Normalize + persist picked image data. Returns the stored file name, or
    /// nil when the data isn't a decodable image. Overwrites the team's prior
    /// logo (stable name per team → no orphan cleanup needed on re-pick).
    @discardableResult
    static func save(_ data: Data, teamId: UUID, base: URL? = nil) -> String? {
        guard let normalized = normalizedJPEG(from: data) else { return nil }
        let name = "logo-\(teamId.uuidString).jpg"
        let url = directory(base: base).appendingPathComponent(name)
        do {
            try normalized.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func imageData(named name: String, base: URL? = nil) -> Data? {
        try? Data(contentsOf: directory(base: base).appendingPathComponent(name))
    }

    static func delete(named name: String, base: URL? = nil) {
        try? FileManager.default.removeItem(
            at: directory(base: base).appendingPathComponent(name))
    }

    /// Downscale to ≤ maxDimension on the long edge and re-encode as JPEG —
    /// bounds a multi-MB HEIC photo to a grid-thumbnail-sized asset.
    static func normalizedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxDimension / longEdge)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        // Force renderer scale 1: the default is the SCREEN scale (3x), which
        // would triple the pixel dimensions past the cap.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return scaled.jpegData(compressionQuality: 0.85)
    }
}
