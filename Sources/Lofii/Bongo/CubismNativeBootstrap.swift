import Foundation
import CubismNativeBridge

struct CubismNativeStatus: Sendable {
    let connected: Bool
    let frameworkStarted: Bool
    let frameworkInitialized: Bool
    let mocLoaded: Bool
    let mocConsistent: Bool
    let coreVersion: UInt32
    let latestMocVersion: UInt32
    let mocVersion: UInt32
    let errorMessage: String?
}

@MainActor
enum CubismNativeBootstrap {
    private static var cachedMocPath: String?
    private static var cachedStatus: CubismNativeStatus?

    static func prepareBundledBongoModel(mocURL: URL?) -> CubismNativeStatus {
        if let mocURL, let cachedMocPath, cachedMocPath == mocURL.path, let cachedStatus {
            return cachedStatus
        }

        guard let mocURL else {
            let status = CubismNativeStatus(
                connected: false,
                frameworkStarted: false,
                frameworkInitialized: false,
                mocLoaded: false,
                mocConsistent: false,
                coreVersion: 0,
                latestMocVersion: 0,
                mocVersion: 0,
                errorMessage: "Bundled Live2D .moc3 not found"
            )
            cachedMocPath = nil
            cachedStatus = status
            print("[CubismNative] ERROR: \(status.errorMessage ?? "unknown")")
            return status
        }

        var diagnostics = CubismNativeDiagnostics()
        let connected = mocURL.path.withCString { path in
            CubismNativeCopyDiagnostics(path, &diagnostics)
        }

        let errorMessage: String? = withUnsafePointer(to: &diagnostics.errorMessage.0) { ptr in
            let cString = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            guard cString.pointee != 0 else { return nil }
            return String(cString: cString)
        }

        let status = CubismNativeStatus(
            connected: connected,
            frameworkStarted: diagnostics.frameworkStarted,
            frameworkInitialized: diagnostics.frameworkInitialized,
            mocLoaded: diagnostics.mocLoaded,
            mocConsistent: diagnostics.mocConsistent,
            coreVersion: diagnostics.coreVersion,
            latestMocVersion: diagnostics.latestMocVersion,
            mocVersion: diagnostics.mocVersion,
            errorMessage: errorMessage
        )

        cachedMocPath = mocURL.path
        cachedStatus = status

        if connected {
            print(
                "[CubismNative] ready core=\(status.coreVersion) moc=\(status.mocVersion) " +
                "latestMoc=\(status.latestMocVersion) consistent=\(status.mocConsistent)"
            )
        } else {
            print("[CubismNative] ERROR: \(status.errorMessage ?? "unknown")")
        }

        return status
    }
}
