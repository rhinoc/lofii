import AppKit
import Foundation

enum DiagnosticLog {
    private static let folderName = "lofii"
    private static let playbackFileName = "playback.log"
    private static let agentCompanionFileName = "agent-companion.log"

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: folderName, directoryHint: .isDirectory)
    }

    private static var playbackLogURL: URL {
        directoryURL.appending(path: playbackFileName, directoryHint: .notDirectory)
    }

    private static var agentCompanionLogURL: URL {
        directoryURL.appending(path: agentCompanionFileName, directoryHint: .notDirectory)
    }

    static func appendPlayback(_ message: String) {
        append(message, to: playbackLogURL, failureContext: "playback diagnostic log")
    }

    static func appendAgentCompanion(_ message: String) {
        append(message, to: agentCompanionLogURL, failureContext: "agent companion diagnostic log")
    }

    private static func append(_ message: String, to logURL: URL, failureContext: String) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let line = "\(Self.timestamp()) \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("lofii failed to write \(failureContext): \(error.localizedDescription)")
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
