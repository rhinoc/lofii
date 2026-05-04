import Foundation

actor SceneVideoCache {
    static let shared = SceneVideoCache()

    private let session: URLSession
    private var inflight: [String: Task<URL, Error>] = [:]

    private init(session: URLSession = .shared) {
        self.session = session
    }

    static func localURL(for asset: SceneAsset, variant: SceneVariant) -> URL {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Lofii/scenes", isDirectory: true)
            .appendingPathComponent(asset.id, isDirectory: true)
            .appendingPathComponent("\(variant.rawValue).mp4", isDirectory: false)
    }

    static func cachedURLIfAvailable(for asset: SceneAsset, variant: SceneVariant) -> URL? {
        let url = localURL(for: asset, variant: variant)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func ensureLocalVideo(for asset: SceneAsset, variant: SceneVariant) async throws -> URL {
        let destination = Self.localURL(for: asset, variant: variant)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let key = "\(asset.id)/\(variant.rawValue)"
        if let existing = inflight[key] {
            return try await existing.value
        }

        let remote = asset.videoURL(variant: variant)
        let session = self.session

        let task = Task<URL, Error>.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let (tmpURL, response) = try await session.download(from: remote)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? fm.removeItem(at: tmpURL)
                throw URLError(.badServerResponse)
            }

            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            try fm.moveItem(at: tmpURL, to: destination)
            return destination
        }

        inflight[key] = task
        defer { inflight[key] = nil }
        return try await task.value
    }
}
