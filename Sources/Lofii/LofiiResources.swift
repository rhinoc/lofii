import Foundation

/// SwiftPM places resources in `lofii_lofii.bundle` (`Bundle.module`) for
/// development builds. Release `.app` bundles flatten the same resources into
/// `Contents/Resources/` (`Bundle.main`) to avoid a nested bundle at the app
/// root, which would break codesign.
enum LofiiResources {
    private static let swiftPMResourceBundleName = "lofii_lofii.bundle"
    private static let resourceMarkers: [(name: String, extensionName: String?)] = [
        ("Statics", nil),
        ("BongoCat", nil),
        ("Fonts", nil),
        ("FrameworkMetallibs", nil),
        ("ShatteredGlass", nil),
        ("AppIcon", "icns"),
        ("MenuBarIcon", "svg"),
        ("StageMetalShaders", "metal"),
    ]

    static let bundle: Bundle = resolveBundle()

    static func url(forResource name: String, withExtension extensionName: String?, subdirectory: String? = nil) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: extensionName, subdirectory: subdirectory) {
            return url
        }
        for candidate in candidateSwiftPMBundleURLs(main: .main) {
            guard let candidateBundle = Bundle(url: candidate),
                  let url = candidateBundle.url(
                    forResource: name,
                    withExtension: extensionName,
                    subdirectory: subdirectory
                  )
            else { continue }
            return url
        }
        for candidate in developmentSwiftPMBundleURLs() {
            guard let candidateBundle = Bundle(url: candidate),
                  let url = candidateBundle.url(
                    forResource: name,
                    withExtension: extensionName,
                    subdirectory: subdirectory
                  )
            else { continue }
            return url
        }
        return nil
    }

    static func resolveBundle(main: Bundle = .main) -> Bundle {
        if containsAgentCompanionResource(in: main) {
            return main
        }

        for url in candidateSwiftPMBundleURLs(main: main) {
            guard let bundle = Bundle(url: url),
                  containsAgentCompanionResource(in: bundle)
            else { continue }
            return bundle
        }

        if containsBundledResource(in: main) {
            return main
        }

        for url in candidateSwiftPMBundleURLs(main: main) {
            guard let bundle = Bundle(url: url),
                  containsBundledResource(in: bundle)
            else { continue }
            return bundle
        }

        return main
    }

    private static func containsAgentCompanionResource(in bundle: Bundle) -> Bool {
        bundle.url(forResource: "agent-bubble-speech-short", withExtension: "svg", subdirectory: "AgentCompanion") != nil
    }

    private static func containsBundledResource(in bundle: Bundle) -> Bool {
        return resourceMarkers.contains { marker in
            bundle.url(forResource: marker.name, withExtension: marker.extensionName) != nil
        }
    }

    private static func candidateSwiftPMBundleURLs(main: Bundle) -> [URL] {
        var candidates: [URL] = []

        func appendBundle(in directory: URL?) {
            guard let directory else { return }
            candidates.append(directory.appendingPathComponent(swiftPMResourceBundleName, isDirectory: true))
        }

        appendBundle(in: main.resourceURL)
        appendBundle(in: main.bundleURL)
        appendBundle(in: main.bundleURL.deletingLastPathComponent())

        if let executableDirectory = main.executableURL?.deletingLastPathComponent() {
            appendBundle(in: executableDirectory)
            appendBundle(in: executableDirectory.deletingLastPathComponent())
            appendBundle(in: executableDirectory.deletingLastPathComponent().deletingLastPathComponent())
            appendBundle(in: executableDirectory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func developmentSwiftPMBundleURLs() -> [URL] {
        var candidates: [URL] = []

        func appendBundle(in directory: URL) {
            candidates.append(directory.appendingPathComponent(swiftPMResourceBundleName, isDirectory: true))
        }

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        appendBundle(in: workingDirectory.appendingPathComponent(".build/debug", isDirectory: true))
        appendBundle(in: workingDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true))

        let sourcePackageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        appendBundle(in: sourcePackageRoot.appendingPathComponent(".build/debug", isDirectory: true))
        appendBundle(in: sourcePackageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true))

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
