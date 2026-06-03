import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)
signal(SIGALRM) { _ in
    _exit(0)
}

@_silgen_name("fork")
private func systemFork() -> pid_t

private func socketPath() -> String {
    "/tmp/lofii-agent-\(getuid()).sock"
}

private func argumentValue(named name: String) -> String? {
    let arguments = CommandLine.arguments.dropFirst()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        if argument == name {
            return iterator.next()
        }
        if argument.hasPrefix("\(name)=") {
            return String(argument.dropFirst(name.count + 1))
        }
    }
    return nil
}

private func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func connectSocket(_ path: String, timeoutMs: Int32 = 800) -> Int32? {
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else { return nil }

    var noSigPipe: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
        path.withCString { source in
            _ = strcpy(ptr, source)
        }
    }

    let flags = fcntl(sock, F_GETFL)
    _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    if result != 0 && errno != EINPROGRESS {
        close(sock)
        return nil
    }

    if result != 0 {
        var pollDescriptor = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollDescriptor, 1, timeoutMs) > 0 else {
            close(sock)
            return nil
        }
        var socketError: Int32 = 0
        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength)
        guard socketError == 0 else {
            close(sock)
            return nil
        }
    }

    _ = fcntl(sock, F_SETFL, flags)
    return sock
}

private func sendAll(_ sock: Int32, data: Data) {
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var sent = 0
        while sent < buffer.count {
            let count = send(sock, base + sent, buffer.count - sent, 0)
            if count < 0 {
                if errno == EINTR { continue }
                return
            }
            if count == 0 { return }
            sent += count
        }
    }
}

private func redirectStandardIOToDevNull() {
    let devNull = open("/dev/null", O_RDWR)
    guard devNull >= 0 else {
        close(STDIN_FILENO)
        close(STDOUT_FILENO)
        close(STDERR_FILENO)
        return
    }

    if devNull != STDIN_FILENO {
        dup2(devNull, STDIN_FILENO)
    }
    if devNull != STDOUT_FILENO {
        dup2(devNull, STDOUT_FILENO)
    }
    if devNull != STDERR_FILENO {
        dup2(devNull, STDERR_FILENO)
    }
    if devNull > STDERR_FILENO {
        close(devNull)
    }
}

private func deliver(_ data: Data) {
    var statBuffer = stat()
    let path = socketPath()
    guard stat(path, &statBuffer) == 0, (statBuffer.st_mode & S_IFMT) == S_IFSOCK else {
        return
    }

    guard let sock = connectSocket(path) else {
        return
    }

    var sendTimeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
    sendAll(sock, data: data)
    shutdown(sock, SHUT_WR)
    close(sock)
}

private func normalizeEventName(_ name: String) -> String {
    switch name {
    case "user_prompt_submit", "userPromptSubmit", "UserPromptSubmitted":
        return "UserPromptSubmit"
    case "pre_tool_use", "preToolUse":
        return "PreToolUse"
    case "post_tool_use", "postToolUse":
        return "PostToolUse"
    case "pre_compact", "preCompact":
        return "PreCompact"
    case "post_compact", "postCompact":
        return "PostCompact"
    case "subagent_start", "subagentStart":
        return "SubagentStart"
    case "subagent_stop", "subagentStop":
        return "SubagentStop"
    case "post_tool_use_failure", "postToolUseFailure":
        return "PostToolUseFailure"
    case "permission_request", "permissionRequest":
        return "PermissionRequest"
    case "session_start", "sessionStart":
        return "SessionStart"
    case "session_end", "sessionEnd":
        return "SessionEnd"
    case "stop":
        return "Stop"
    default:
        return name
    }
}

private func normalizedSource(from json: [String: Any]) -> String? {
    nonEmptyString(argumentValue(named: "--source"))
        ?? nonEmptyString(ProcessInfo.processInfo.environment["LOFII_AGENT_SOURCE"])
        ?? nonEmptyString(json["_source"])
        ?? nonEmptyString(json["source"])
        ?? nonEmptyString(json["agent_source"])
        ?? nonEmptyString(json["agentSource"])
}

private func enrich(_ json: inout [String: Any]) {
    let source = normalizedSource(from: json)?.lowercased() ?? "codex"

    if json["hook_event_name"] == nil {
        if let event = nonEmptyString(json["hookEventName"])
            ?? nonEmptyString(json["eventName"])
            ?? nonEmptyString(json["event"]) {
            json["hook_event_name"] = normalizeEventName(event)
        }
    } else if let event = nonEmptyString(json["hook_event_name"]) {
        json["hook_event_name"] = normalizeEventName(event)
    }

    if json["session_id"] == nil {
        if let sessionID = nonEmptyString(json["sessionId"]) {
            json["session_id"] = sessionID
        } else if let payload = json["payload"] as? [String: Any],
                  let sessionID = nonEmptyString(payload["session_id"]) ?? nonEmptyString(payload["sessionId"]) {
            json["session_id"] = sessionID
        } else if let data = json["data"] as? [String: Any],
                  let sessionID = nonEmptyString(data["session_id"]) ?? nonEmptyString(data["sessionId"]) {
            json["session_id"] = sessionID
        } else {
            json["session_id"] = "\(source)-ppid-\(getppid())"
        }
    }

    if json["agent_id"] == nil {
        if let agentID = nonEmptyString(argumentValue(named: "--agent-id"))
            ?? nonEmptyString(json["agentId"]) {
            json["agent_id"] = agentID
        }
    }

    if json["tool_name"] == nil {
        if let tool = json["toolName"] as? String {
            json["tool_name"] = tool
        } else if let nested = json["tool"] as? [String: Any],
                  let tool = nonEmptyString(nested["name"]) {
            json["tool_name"] = tool
        }
    }

    json["_source"] = source
    json["_ppid"] = Int(getppid())
}

var statBuffer = stat()
guard stat(socketPath(), &statBuffer) == 0, (statBuffer.st_mode & S_IFMT) == S_IFSOCK else {
    exit(0)
}

alarm(5)
let input = FileHandle.standardInput.readDataToEndOfFile()
alarm(0)

guard !input.isEmpty,
      var json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
    exit(0)
}

enrich(&json)

guard json["hook_event_name"] != nil,
      json["session_id"] != nil,
      let output = try? JSONSerialization.data(withJSONObject: json) else {
    exit(0)
}

let childPID = systemFork()
guard childPID == 0 else {
    _exit(0)
}

redirectStandardIOToDevNull()
alarm(3)
deliver(output)
_exit(0)
