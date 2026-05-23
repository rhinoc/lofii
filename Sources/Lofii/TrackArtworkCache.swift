import Foundation

enum TrackArtworkCache {
    private static let directoryName = "track-artwork"

    static func cachedURLIfAvailable(for remoteURL: URL?) -> URL? {
        guard let remoteURL else { return nil }
        if remoteURL.isFileURL {
            return FileManager.default.fileExists(atPath: remoteURL.path) ? remoteURL : nil
        }
        let localURL = cachedFileURL(for: remoteURL)
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }

    static func ensureLocal(for remoteURL: URL) async throws -> URL {
        if remoteURL.isFileURL {
            return remoteURL
        }

        let localURL = cachedFileURL(for: remoteURL)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        try data.write(to: localURL, options: .atomic)
        return localURL
    }

    private static var cacheDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lofii", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func cachedFileURL(for remoteURL: URL) -> URL {
        let encoded = Data(remoteURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let ext = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
        return cacheDirectory.appendingPathComponent("\(encoded).\(ext)", isDirectory: false)
    }
}
