import Foundation
import AppKit
import QuickLookThumbnailing

/// Generates thumbnails for files, falling back to the system file icon.
/// Results are cached in-memory keyed by path + size.
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.dropshelf.thumbnails", qos: .userInitiated, attributes: .concurrent)

    private init() {
        cache.countLimit = 512
    }

    private func cacheKey(_ url: URL, _ size: CGSize) -> NSString {
        "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
    }

    /// Calls `completion` on the main queue with the best available image.
    func generate(for url: URL, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let key = cacheKey(url, size)
        if let cached = cache.object(forKey: key) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        // Immediate icon fallback so the UI never shows blank.
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = size

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let self else { return }
            let image: NSImage
            if let rep {
                image = rep.nsImage
            } else {
                image = icon
            }
            self.cache.setObject(image, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Synchronous icon (no QuickLook) — used for menu items and quick glyphs.
    func icon(for url: URL, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = size
        return icon
    }
}
