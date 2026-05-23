import AppKit
import Foundation

enum DiagnosticLog {
    private static let folderName = "lofii"
    private static let playbackFileName = "playback.log"

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: folderName, directoryHint: .isDirectory)
    }

    private static var playbackLogURL: URL {
        directoryURL.appending(path: playbackFileName, directoryHint: .notDirectory)
    }

    static func appendPlayback(_ message: String) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let line = "\(Self.timestamp()) \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: playbackLogURL.path) {
                let handle = try FileHandle(forWritingTo: playbackLogURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: playbackLogURL, options: .atomic)
            }
        } catch {
            NSLog("lofii failed to write playback diagnostic log: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func openDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(directoryURL)
        } catch {
            NSLog("lofii failed to open diagnostic log directory: \(error.localizedDescription)")
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
