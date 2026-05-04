import Foundation
import ImageIO

/// Process-wide LRU pool of `GifFrameCache` objects keyed by file URL.
///
/// Why a shared pool?
///  • Multiple views can request the same GIF URL concurrently (e.g. the
///    snow static overlay in `SceneView` and a `GifSceneView` both using
///    the same bundled static frame). Without sharing, each creates its own
///    `CGImageSource` backed by the same file — wasted file handles and
///    redundant ImageIO metadata parsing.
///  • Bounding the pool to `maxEntries` ensures we never keep more than N
///    ImageIO sources open simultaneously, putting a ceiling on memory even
///    when the user has cycled through many different GIFs.
///
/// Thread safety: all mutations go through a `NSLock` so callers on any
/// thread (including the background decode queue) can safely call `cache(for:)`.
final class GifFrameCachePool: @unchecked Sendable {
    static let shared = GifFrameCachePool()

    /// Maximum number of `GifFrameCache` entries to keep alive at once.
    /// Each cache may memoise up to ~64 MB of decoded RGBA frames (see
    /// `GifFrameCache.cacheableTotalBytes`), so the pool's worst-case
    /// resident-set contribution is roughly `maxEntries × 64 MB`.
    /// 4+ covers: visible + previous GIF, `SceneView` / `GifSceneView` snow
    /// overlays, and headroom so LRU eviction doesn't drop an in-flight URL.
    private static let maxEntries = 5

    private var order: [URL] = []          // LRU order, oldest first
    private var entries: [URL: GifFrameCache] = [:]
    private let lock = NSLock()

    private init() {}

    /// Returns a `GifFrameCache` for `url`, creating one if needed and
    /// evicting the least-recently-used entry when the pool is full.
    func cache(for url: URL) -> GifFrameCache? {
        lock.lock()
        defer { lock.unlock() }

        if let existing = entries[url] {
            // Move to most-recently-used position.
            order.removeAll { $0 == url }
            order.append(url)
            return existing
        }

        guard let cache = GifFrameCache(url: url) else { return nil }

        // Evict LRU entry if at capacity.
        while order.count >= Self.maxEntries, let oldest = order.first {
            order.removeFirst()
            entries[oldest] = nil
        }

        entries[url] = cache
        order.append(url)
        return cache
    }
}
