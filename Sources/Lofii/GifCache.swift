import Foundation

actor GifCache {
    static let shared = GifCache()

    private let session: URLSession
    private var inflight: [String: Task<URL, Error>] = [:]

    private init(session: URLSession = .shared) {
        self.session = session
    }

    static func localURL(for asset: GifAsset) -> URL {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Lofii/gifs", isDirectory: true)
            .appendingPathComponent("\(asset.id).gif", isDirectory: false)
    }

    /// URL of the asset shipped inside the app bundle (Resources/Statics),
    /// when one exists. Today only the eight `static1`…`static8` snow
    /// frames are bundled — the larger animated GIFs and mp4 scenes still
    /// stream on demand. Returning a bundle URL means we can guarantee the
    /// channel-change transition works the very first time the app launches,
    /// even on a flaky network.
    static func bundledURL(for asset: GifAsset) -> URL? {
        LofiiResources.bundle.url(
            forResource: asset.id,
            withExtension: "gif",
            subdirectory: "Statics"
        )
    }

    static func cachedURLIfAvailable(for asset: GifAsset) -> URL? {
        if let bundled = bundledURL(for: asset) {
            return bundled
        }
        let url = localURL(for: asset)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Random bundled static “snow” frame URL — synchronous, no actor hop.
    /// Used so overlays can paint snow on the first frame without async delay.
    nonisolated static func bundledSnowOverlayURL() -> URL? {
        GifSceneCatalog.staticFrames.compactMap { bundledURL(for: $0) }.randomElement()
    }

    /// One random bundled snow URL chosen once per process for startup. The
    /// startup path can have multiple overlay layers active at once, so they
    /// must agree on the same GIF or the first-frame fallback appears to jump
    /// to a different static animation.
    nonisolated static let startupSnowOverlayURL: URL? = {
        GifSceneCatalog.staticFrames.compactMap { bundledURL(for: $0) }.randomElement()
    }()

    /// Best-effort download of every static "snow" frame. With the frames
    /// now bundled this is a no-op for the common case (the bundled URLs
    /// resolve immediately), but we keep it around so a future asset that
    /// isn't bundled — or a bundle that loses a file for some reason —
    /// still gets warmed up before the user needs it.
    func prefetchStatics() async {
        await withTaskGroup(of: Void.self) { group in
            for asset in GifSceneCatalog.staticFrames where Self.bundledURL(for: asset) == nil {
                group.addTask { [weak self] in
                    _ = try? await self?.ensureLocal(for: asset)
                }
            }
        }
    }

    func randomCachedStatic() -> URL? {
        let cached = GifSceneCatalog.staticFrames.compactMap { Self.cachedURLIfAvailable(for: $0) }
        return cached.randomElement()
    }

    func ensureLocal(for asset: GifAsset) async throws -> URL {
        // Bundled assets are always preferred — no need to write a copy
        // to ~/Library/Caches when the bytes already live in the app.
        if let bundled = Self.bundledURL(for: asset) {
            return bundled
        }

        let destination = Self.localURL(for: asset)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        if let existing = inflight[asset.id] {
            return try await existing.value
        }

        let primary = asset.remoteURL
        let fallback = asset.fallbackURL
        let session = self.session

        let task = Task<URL, Error>.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            do {
                try await Self.download(from: primary, to: destination, session: session)
                return destination
            } catch {
                if let fallback {
                    try await Self.download(from: fallback, to: destination, session: session)
                    return destination
                }
                throw error
            }
        }

        inflight[asset.id] = task
        defer { inflight[asset.id] = nil }
        return try await task.value
    }

    private static func download(from remote: URL, to destination: URL, session: URLSession) async throws {
        let (tmpURL, response) = try await session.download(from: remote)
        let fm = FileManager.default

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? fm.removeItem(at: tmpURL)
            throw URLError(.badServerResponse)
        }

        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tmpURL, to: destination)
    }
}
