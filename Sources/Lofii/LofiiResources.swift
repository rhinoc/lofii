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
        ("StageMetalShaders", "metal"),
    ]

    static let bundle: Bundle = resolveBundle()

    static func resolveBundle(main: Bundle = .main) -> Bundle {
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

    private static func containsBundledResource(in bundle: Bundle) -> Bool {
        resourceMarkers.contains { marker in
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
}
