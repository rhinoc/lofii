import Foundation
@preconcurrency import ImageIO

enum VisualMediaKind: String, CaseIterable, Codable, Sendable {
    case builtInGif
    case userGif
    case userImage
    case userVideo
}

enum VisualMediaLibraryScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case builtIn
    case custom
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .builtIn: return "Built-in"
        case .custom: return "Custom"
        case .all: return "All"
        }
    }
}

enum VisualMediaSource: Equatable, Sendable {
    case builtInGif(GifAsset)
    case userFile(URL, kind: VisualMediaKind)
}

struct VisualMediaAsset: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: VisualMediaKind
    let source: VisualMediaSource

    static func builtInGif(_ asset: GifAsset) -> VisualMediaAsset {
        VisualMediaAsset(
            id: "builtin-gif:\(asset.id)",
            displayName: asset.id,
            kind: .builtInGif,
            source: .builtInGif(asset)
        )
    }

    var stageIdentityKey: String { id }

    func cachedStageMetalSourceIfAvailable() -> StageMetalSource? {
        switch source {
        case .builtInGif(let asset):
            guard let url = GifCache.cachedURLIfAvailable(for: asset) else { return nil }
            return .gif(url)
        case .userFile(let url, let kind):
            return Self.stageMetalSource(for: url, kind: kind)
        }
    }

    func resolveStageMetalSource() async throws -> StageMetalSource {
        switch source {
        case .builtInGif(let asset):
            let url = try await GifCache.shared.ensureLocal(for: asset)
            return .gif(url)
        case .userFile(let url, let kind):
            guard FileManager.default.fileExists(atPath: url.path),
                  let source = Self.stageMetalSource(for: url, kind: kind)
            else {
                throw CocoaError(.fileNoSuchFile)
            }
            return source
        }
    }

    private static func stageMetalSource(for url: URL, kind: VisualMediaKind) -> StageMetalSource? {
        switch kind {
        case .builtInGif, .userGif:
            return .gif(url)
        case .userImage:
            return .image(url)
        case .userVideo:
            return .video(url)
        }
    }
}

enum UserVisualMediaLibrary {
    static func userImportsRootURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lofii/media", isDirectory: true)
    }

    static func listImportedMedia() -> [VisualMediaAsset] {
        listImportedMedia(in: userImportsRootURL())
    }

    static func listImportedMedia(in root: URL) -> [VisualMediaAsset] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { url in
            guard isSafeUserMediaFile(url),
                  let kind = mediaKind(for: url),
                  decoderCanOpen(url: url, kind: kind)
            else {
                return nil
            }
            return VisualMediaAsset(
                id: "user-media:\(url.standardizedFileURL.path)",
                displayName: url.deletingPathExtension().lastPathComponent,
                kind: kind,
                source: .userFile(url.standardizedFileURL, kind: kind)
            )
        }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func mediaKind(for url: URL) -> VisualMediaKind? {
        switch url.pathExtension.lowercased() {
        case "gif":
            return .userGif
        case "png", "jpg", "jpeg":
            return .userImage
        case "mp4", "m4v", "mov":
            return .userVideo
        default:
            return nil
        }
    }

    private static func isSafeUserMediaFile(_ url: URL) -> Bool {
        guard !url.lastPathComponent.isEmpty,
              !url.lastPathComponent.hasPrefix("."),
              mediaKind(for: url) != nil
        else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey])
        if values?.isDirectory == true || values?.isHidden == true || values?.isSymbolicLink == true {
            return false
        }
        return true
    }

    private static func decoderCanOpen(url: URL, kind: VisualMediaKind) -> Bool {
        switch kind {
        case .builtInGif:
            return true
        case .userGif, .userImage:
            return CGImageSourceCreateWithURL(url as CFURL, nil) != nil
        case .userVideo:
            return true
        }
    }
}
