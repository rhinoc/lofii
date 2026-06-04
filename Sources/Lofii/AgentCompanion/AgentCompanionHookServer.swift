import Darwin
import Foundation
import Network
import OSLog

@MainActor
final class AgentCompanionHookServer {
    nonisolated static var socketPath: String {
        "/tmp/lofii-agent-\(getuid()).sock"
    }

    private static let maxPayloadSize = 1_048_576

    private let model: AgentCompanionModel
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "lofii",
        category: "agent.companion"
    )
    private var listener: NWListener?

    init(model: AgentCompanionModel) {
        self.model = model
    }

    func start() {
        guard listener == nil else { return }

        unlink(Self.socketPath)
        let previousUmask = umask(0o077)

        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        do {
            listener = try NWListener(using: parameters)
        } catch {
            umask(previousUmask)
            logger.error("Failed to start Agent companion hook server: \(error.localizedDescription, privacy: .public)")
            DiagnosticLog.appendAgentCompanion("server.start.failed path=\(Self.socketPath) error=\(Self.logField(error.localizedDescription))")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handle(connection)
            }
        }
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                umask(previousUmask)
                chmod(Self.socketPath, 0o700)
                self?.logger.info("Agent companion hook server listening on \(Self.socketPath, privacy: .public)")
                DiagnosticLog.appendAgentCompanion("server.ready path=\(Self.socketPath)")
            case .failed(let error):
                umask(previousUmask)
                self?.logger.error("Agent companion hook server failed: \(error.localizedDescription, privacy: .public)")
                DiagnosticLog.appendAgentCompanion("server.failed path=\(Self.socketPath) error=\(Self.logField(error.localizedDescription))")
            case .cancelled:
                umask(previousUmask)
                DiagnosticLog.appendAgentCompanion("server.cancelled path=\(Self.socketPath)")
            default:
                break
            }
        }
        listener?.start(queue: .main)
    }

    func stop() {
        DiagnosticLog.appendAgentCompanion("server.stop path=\(Self.socketPath)")
        listener?.cancel()
        listener = nil
        let path = Self.socketPath
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            unlink(path)
        }
    }

    private func handle(_ connection: NWConnection) {
        DiagnosticLog.appendAgentCompanion("server.connection.start")
        connection.start(queue: .main)
        receiveAll(connection, accumulated: Data())
    }

    private func receiveAll(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var data = accumulated
                if let content {
                    data.append(content)
                }
                if data.count > Self.maxPayloadSize {
                    self.logger.warning("Dropping oversized Agent companion hook payload")
                    DiagnosticLog.appendAgentCompanion("server.payload.drop reason=oversized bytes=\(data.count)")
                    connection.cancel()
                    return
                }
                if isComplete || error != nil {
                    if let error {
                        DiagnosticLog.appendAgentCompanion("server.receive.complete bytes=\(data.count) error=\(Self.logField(error.localizedDescription))")
                    } else {
                        DiagnosticLog.appendAgentCompanion("server.receive.complete bytes=\(data.count)")
                    }
                    self.process(data, connection: connection)
                } else {
                    self.receiveAll(connection, accumulated: data)
                }
            }
        }
    }

    private func process(_ data: Data, connection: NWConnection) {
        defer {
            sendResponse(connection, data: Data("{}".utf8))
        }

        guard let event = AgentCompanionHookEvent(data: data) else {
            logger.warning("Dropping unparsable Agent companion hook payload")
            DiagnosticLog.appendAgentCompanion("server.payload.drop reason=unparsable bytes=\(data.count)")
            return
        }
        DiagnosticLog.appendAgentCompanion(
            "server.event.accept source=\(event.source) event=\(event.eventName) session=\(Self.logField(event.sessionID)) agent=\(Self.logField(event.agentID)) tool=\(Self.logField(event.toolName)) toolInput=\(Self.logField(event.toolInputText))"
        )
        model.handle(event)
    }

    private func sendResponse(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func logField(_ value: String?, maxLength: Int = 180) -> String {
        guard let value else { return "nil" }
        var sanitized = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if sanitized.count > maxLength {
            sanitized = "\(sanitized.prefix(maxLength))..."
        }
        return "\"\(sanitized)\""
    }
}
