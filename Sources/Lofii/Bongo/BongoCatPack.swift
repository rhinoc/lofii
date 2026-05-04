import AppKit
import Foundation

// MARK: - User import root (~/.lofii/bongo/<folder>)

/// Live2D Bongo overlay pack: bundled in the app or imported under `~/.lofii/bongo/<name>/`.
enum BongoCatPack: Equatable, Hashable, Sendable {
    /// Prefix for persisted imported selection (`user:<folder name>`).
    static let userImportPersistencePrefix = "user:"

    case bundled(BongoCatModelKind)
    case imported(folderName: String)

    var menuLabel: String {
        switch self {
        case .bundled(let kind):
            return kind.menuLabel
        case .imported(let folderName):
            return folderName
        }
    }

    /// Stable string for Metal texture cache identity and SwiftUI `.id`.
    var cacheTag: String {
        switch self {
        case .bundled(let kind):
            return kind.rawValue
        case .imported(let folderName):
            return Self.userImportPersistencePrefix + folderName
        }
    }

    var persistenceValue: String {
        switch self {
        case .bundled(let kind):
            return kind.rawValue
        case .imported(let folderName):
            return Self.userImportPersistencePrefix + folderName
        }
    }

    /// Returns `nil` when the string does not describe a valid pack shape.
    static func decode(persistence raw: String) -> BongoCatPack? {
        if raw.hasPrefix(userImportPersistencePrefix) {
            let name = String(raw.dropFirst(userImportPersistencePrefix.count))
            guard Self.isSafeImportedFolderName(name) else { return nil }
            return .imported(folderName: name)
        }
        if let kind = BongoCatModelKind(rawValue: raw) {
            return .bundled(kind)
        }
        return nil
    }

    /// If an imported folder is missing or invalid, fall back to the default bundled model.
    func resolvedIfPackFolderMissing() -> BongoCatPack {
        switch self {
        case .bundled:
            return self
        case .imported(let folderName):
            let root = Self.importedPackRoot(folderName: folderName)
            guard Self.isValidImportedPackRoot(root) else {
                return .bundled(BongoCatModelKind.bundledDefault)
            }
            return self
        }
    }

    // MARK: Paths

    static func userImportsRootURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lofii/bongo", isDirectory: true)
    }

    static func importedPackRoot(folderName: String) -> URL {
        userImportsRootURL().appendingPathComponent(folderName, isDirectory: true)
    }

    var modelRootURL: URL? {
        switch self {
        case .bundled(let kind):
            LofiiResources.bundle.url(
                forResource: kind.bundleFolderName,
                withExtension: nil,
                subdirectory: "BongoCat"
            )
        case .imported(let folderName):
            Self.importedPackRoot(folderName: folderName)
        }
    }

    /// Directory containing `background.png` and `left-keys/` (same layout as bundled `…/resources`).
    var resourcesDirectoryURL: URL? {
        switch self {
        case .bundled(let kind):
            LofiiResources.bundle.url(
                forResource: "resources",
                withExtension: nil,
                subdirectory: "BongoCat/\(kind.bundleFolderName)"
            )
        case .imported(let folderName):
            Self.importedPackRoot(folderName: folderName).appendingPathComponent("resources", isDirectory: true)
        }
    }

    var leftKeysDirectoryURL: URL? {
        resourcesDirectoryURL?.appendingPathComponent("left-keys", isDirectory: true)
    }

    /// `cat.model3.json` or the first `*.model3.json` in the model root.
    func resolvedModel3JSONFileName() -> String? {
        guard let root = modelRootURL else { return nil }
        return Self.preferredModel3JSONFilename(in: root)
    }

    /// Pixel-sized stage cap (before `BongoStageScaleTier`); bundled uses fixed values, imported prefers `resources/background.png` size halved like Retina parity.
    var maxLogicalStageSize: CGSize {
        switch self {
        case .bundled(let kind):
            return kind.maxLogicalStageSize
        case .imported(let folderName):
            let bg = Self.importedPackRoot(folderName: folderName)
                .appendingPathComponent("resources/background.png")
            if let px = Self.pngPixelSize(at: bg), px.width > 1, px.height > 1 {
                return CGSize(width: px.width / 2.0, height: px.height / 2.0)
            }
            return BongoCatModelKind.standard.maxLogicalStageSize
        }
    }

    // MARK: Scan / validate / import

    /// Alphanumeric folder names plus common safe punctuation (imported path segment under `~/.lofii/bongo/`).
    static func isSafeImportedFolderName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        guard !name.contains("/"), !name.contains("\\") else { return false }
        guard !name.hasPrefix(userImportPersistencePrefix) else { return false }
        return true
    }

    static func listImportedFolderNames() -> [String] {
        let root = userImportsRootURL()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var names: [String] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            guard isSafeImportedFolderName(url.lastPathComponent) else { continue }
            if isValidImportedPackRoot(url) {
                names.append(url.lastPathComponent)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func isValidImportedPackRoot(_ root: URL) -> Bool {
        guard let jsonName = preferredModel3JSONFilename(in: root) else { return false }
        guard let mocURL = mocURL(modelRoot: root, model3FileName: jsonName),
              FileManager.default.fileExists(atPath: mocURL.path)
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(jsonName).path)
    }

    private static func preferredModel3JSONFilename(in root: URL) -> String? {
        let fm = FileManager.default
        let cat = root.appendingPathComponent(BongoCatModelKind.modelSettingFileName)
        if fm.fileExists(atPath: cat.path) {
            return BongoCatModelKind.modelSettingFileName
        }
        guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else {
            return nil
        }
        let candidates = urls.filter { url in
            url.pathExtension == "json" && url.lastPathComponent.hasSuffix(".model3.json")
        }
        return candidates.map(\.lastPathComponent).sorted().first
    }

    private struct Live2DModel3Root: Decodable {
        struct FileRefs: Decodable {
            let Moc: String
        }

        let FileReferences: FileRefs
    }

    static func mocURL(modelRoot: URL, model3FileName: String) -> URL? {
        let jsonURL = modelRoot.appendingPathComponent(model3FileName)
        if let data = try? Data(contentsOf: jsonURL),
           let decoded = try? JSONDecoder().decode(Live2DModel3Root.self, from: data)
        {
            return modelRoot.appendingPathComponent(decoded.FileReferences.Moc)
        }
        return firstMoc3File(in: modelRoot)
    }

    private static func firstMoc3File(in root: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else {
            return nil
        }
        return urls.filter { $0.pathExtension.lowercased() == "moc3" }.sorted { $0.path < $1.path }.first
    }

    private static func pngPixelSize(at url: URL) -> CGSize? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let image = NSImage(contentsOf: url),
              let rep = image.representations.first
        else {
            return nil
        }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        return CGSize(width: CGFloat(w), height: CGFloat(h))
    }
}

extension BongoCatPack {
    /// Same scaling rule as bundled packs: tier multiplier on the logical stage cap.
    func maxLogicalStageSize(scaledBy tier: BongoStageScaleTier) -> CGSize {
        let base = maxLogicalStageSize
        let s = tier.scale
        return CGSize(width: base.width * s, height: base.height * s)
    }
}
