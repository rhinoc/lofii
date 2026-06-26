import Foundation

enum AgentHookInstaller {
    static let codex = CodexAdapter()
    static let cursor = CursorAdapter()

    static func installSnapshot(
        codexHome: URL = CodexAdapter.defaultCodexHome(),
        cursorHome: URL = CursorAdapter.defaultCursorHome(),
        helperPath: String?,
        events: Set<AgentHookEvent> = CodexAdapter.defaultEvents,
        fileManager: FileManager = .default
    ) -> AgentHookInstallSnapshot {
        let codexHooks = Self.hooksDictionary(
            at: codexHome.appendingPathComponent("hooks.json"),
            fileManager: fileManager
        )
        let cursorHooks = Self.hooksDictionary(
            at: cursorHome.appendingPathComponent("hooks.json"),
            fileManager: fileManager
        )

        var expectedCount = 0
        var installedCount = 0
        for event in AgentHookEvent.allCases.filter(events.contains) {
            expectedCount += 1
            if codex.isHookInstalled(event: event, hooks: codexHooks, helperPath: helperPath) {
                installedCount += 1
            }

            for cursorEvent in CursorAdapter.cursorEventKeys(for: event) {
                expectedCount += 1
                if cursor.isHookInstalled(cursorEvent: cursorEvent, hooks: cursorHooks, helperPath: helperPath) {
                    installedCount += 1
                }
            }
        }

        let hasManagedHooks = codex.hasManagedHooks(codexHome: codexHome, helperPath: helperPath, fileManager: fileManager)
            || cursor.hasManagedHooks(cursorHome: cursorHome, helperPath: helperPath, fileManager: fileManager)

        return AgentHookInstallSnapshot(
            expectedCount: expectedCount,
            installedCount: installedCount,
            hasManagedHooks: hasManagedHooks
        )
    }

    private static func hooksDictionary(at url: URL, fileManager: FileManager) -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path),
              let root = try? AgentHookJSONStore.read(at: url),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return [:]
        }
        return hooks
    }
}

struct AgentHookInstallSnapshot: Equatable, Sendable {
    let expectedCount: Int
    let installedCount: Int
    let hasManagedHooks: Bool

    var isInstallComplete: Bool {
        expectedCount > 0 && installedCount == expectedCount
    }
}

enum AgentHookEvent: String, CaseIterable, Identifiable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .sessionStart: return "Session Start"
        case .userPromptSubmit: return "Prompt Submit"
        case .preToolUse: return "Pre Tool"
        case .postToolUse: return "Post Tool"
        case .preCompact: return "Pre Compact"
        case .postCompact: return "Post Compact"
        case .subagentStart: return "Subagent Start"
        case .subagentStop: return "Subagent Stop"
        case .permissionRequest: return "Permission"
        case .stop: return "Stop"
        case .sessionEnd: return "Session End"
        }
    }
}

struct CodexAdapter {
    static let defaultEvents = Set(AgentHookEvent.allCases)

    func install(
        codexHome: URL = Self.defaultCodexHome(),
        helperPath: String,
        events: Set<AgentHookEvent> = Self.defaultEvents,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

        let hooksPath = codexHome.appendingPathComponent("hooks.json")
        var root = try readJSONObject(at: hooksPath)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        hooks = removingManagedCommands(from: hooks, helperPath: helperPath)

        for event in events.sortedByDisplayOrder() {
            var groups = hooks[event.rawValue] as? [[String: Any]] ?? []
            if !groupsContainManagedCommand(groups, helperPath: helperPath) {
                groups.append([
                    "hooks": [[
                        "type": "command",
                        "command": Self.command(helperPath: helperPath, source: "codex"),
                        "timeout": 5,
                    ]],
                ])
            }
            hooks[event.rawValue] = groups
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: hooksPath)
        if !events.isEmpty {
            try enableCodexHooks(in: codexHome, fileManager: fileManager)
        }
    }

    func uninstall(
        codexHome: URL = Self.defaultCodexHome(),
        helperPath: String?,
        fileManager: FileManager = .default
    ) throws {
        let hooksPath = codexHome.appendingPathComponent("hooks.json")
        guard fileManager.fileExists(atPath: hooksPath.path) else { return }

        var root = try readJSONObject(at: hooksPath)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        hooks = removingManagedCommands(from: hooks, helperPath: helperPath)

        root["hooks"] = hooks
        try writeJSONObject(root, to: hooksPath)
    }

    func isInstalled(
        codexHome: URL = Self.defaultCodexHome(),
        helperPath: String?,
        events: Set<AgentHookEvent> = Self.defaultEvents,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !events.isEmpty else {
            return hasManagedHooks(codexHome: codexHome, helperPath: helperPath, fileManager: fileManager) == false
        }
        let hooksPath = codexHome.appendingPathComponent("hooks.json")
        guard fileManager.fileExists(atPath: hooksPath.path),
              let root = try? readJSONObject(at: hooksPath),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }
        return events.allSatisfy { event in
            guard let groups = hooks[event.rawValue] as? [[String: Any]] else { return false }
            return groupsContainManagedCommand(groups, helperPath: helperPath)
        } && AgentHookEvent.allCases
            .filter { !events.contains($0) }
            .allSatisfy { event in
                guard let groups = hooks[event.rawValue] as? [[String: Any]] else { return true }
                return !groupsContainManagedCommand(groups, helperPath: helperPath)
            }
    }

    func hasManagedHooks(
        codexHome: URL = Self.defaultCodexHome(),
        helperPath: String?,
        fileManager: FileManager = .default
    ) -> Bool {
        let hooksPath = codexHome.appendingPathComponent("hooks.json")
        guard fileManager.fileExists(atPath: hooksPath.path),
              let root = try? readJSONObject(at: hooksPath),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }
        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groupsContainManagedCommand(groups, helperPath: helperPath)
        }
    }

    func isHookInstalled(
        event: AgentHookEvent,
        hooks: [String: Any],
        helperPath: String?
    ) -> Bool {
        guard let groups = hooks[event.rawValue] as? [[String: Any]] else { return false }
        return groupsContainManagedCommand(groups, helperPath: helperPath)
    }

    func enableCodexHooks(
        in codexHome: URL,
        fileManager: FileManager = .default
    ) throws {
        let configPath = codexHome.appendingPathComponent("config.toml")
        var contents = ""
        if fileManager.fileExists(atPath: configPath.path) {
            contents = try String(contentsOf: configPath, encoding: .utf8)
        }

        let hooksPattern = #"(?m)^\s*hooks\s*=\s*(true|false)\s*(#.*)?$"#
        let hooksTruePattern = #"(?m)^\s*hooks\s*=\s*true\s*(#.*)?$"#
        let hooksFalsePattern = #"(?m)^\s*hooks\s*=\s*false\s*(#.*)?$"#

        if contents.range(of: hooksTruePattern, options: .regularExpression) != nil {
            return
        }
        if contents.range(of: hooksPattern, options: .regularExpression) != nil {
            contents = contents.replacingOccurrences(
                of: hooksFalsePattern,
                with: "hooks = true",
                options: .regularExpression
            )
        } else {
            var lines = contents.components(separatedBy: "\n")
            if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
                lines.insert("hooks = true", at: featuresIndex + 1)
            } else {
                if lines.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    lines.append("")
                }
                lines.append("[features]")
                lines.append("hooks = true")
            }
            contents = lines.joined(separator: "\n")
        }

        let normalized = contents.trimmingCharacters(in: .newlines) + "\n"
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try normalized.write(to: configPath, atomically: true, encoding: .utf8)
    }

    static func defaultCodexHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private static func command(helperPath: String, source: String) -> String {
        AgentHookCommandBuilder.command(helperPath: helperPath, source: source)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        try AgentHookJSONStore.read(at: url)
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try AgentHookJSONStore.write(object, to: url)
    }

    private func removingManagedCommands(from hooks: [String: Any], helperPath: String?) -> [String: Any] {
        var hooks = hooks
        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let filteredGroups = groups.compactMap { group -> [String: Any]? in
                guard var nestedHooks = group["hooks"] as? [[String: Any]] else {
                    return group
                }
                nestedHooks.removeAll { hook in
                    guard let command = hook["command"] as? String else { return false }
                    return isManagedCommand(command, helperPath: helperPath)
                }
                guard !nestedHooks.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = nestedHooks
                return updated
            }
            if filteredGroups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = filteredGroups
            }
        }
        return hooks
    }

    private func groupsContainManagedCommand(_ groups: [[String: Any]], helperPath: String?) -> Bool {
        groups.contains { group in
            guard let nestedHooks = group["hooks"] as? [[String: Any]] else { return false }
            return nestedHooks.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return isManagedCommand(command, helperPath: helperPath)
            }
        }
    }

    private func isManagedCommand(_ command: String, helperPath: String?) -> Bool {
        if let helperPath,
           command == Self.command(helperPath: helperPath, source: "codex")
            || command == helperPath {
            return true
        }
        return command.contains("lofii-agent-hook")
    }
}

struct CursorAdapter {
    static let defaultEvents = Set(AgentHookEvent.allCases)

    func install(
        cursorHome: URL = Self.defaultCursorHome(),
        helperPath: String,
        events: Set<AgentHookEvent> = Self.defaultEvents,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: cursorHome, withIntermediateDirectories: true)

        let hooksPath = cursorHome.appendingPathComponent("hooks.json")
        var root = try readJSONObject(at: hooksPath)
        if root["version"] == nil {
            root["version"] = 1
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        hooks = removingManagedCommands(from: hooks, helperPath: helperPath)

        for event in events.sortedByDisplayOrder() {
            for cursorEvent in Self.cursorEventKeys(for: event) {
                var entries = hooks[cursorEvent] as? [[String: Any]] ?? []
                if !entriesContainManagedCommand(entries, helperPath: helperPath) {
                    entries.append([
                        "type": "command",
                        "command": Self.command(helperPath: helperPath, source: "cursor"),
                        "timeout": 5,
                    ])
                }
                hooks[cursorEvent] = entries
            }
        }

        for cursorEvent in Self.allCursorEventKeys() where !Self.isCursorEventEnabled(cursorEvent, events: events) {
            guard var entries = hooks[cursorEvent] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let command = entry["command"] as? String else { return false }
                return isManagedCommand(command, helperPath: helperPath)
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: cursorEvent)
            } else {
                hooks[cursorEvent] = entries
            }
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: hooksPath)
    }

    func uninstall(
        cursorHome: URL = Self.defaultCursorHome(),
        helperPath: String?,
        fileManager: FileManager = .default
    ) throws {
        let hooksPath = cursorHome.appendingPathComponent("hooks.json")
        guard fileManager.fileExists(atPath: hooksPath.path) else { return }

        var root = try readJSONObject(at: hooksPath)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        hooks = removingManagedCommands(from: hooks, helperPath: helperPath)

        root["hooks"] = hooks
        try writeJSONObject(root, to: hooksPath)
    }

    func isInstalled(
        cursorHome: URL = Self.defaultCursorHome(),
        helperPath: String?,
        events: Set<AgentHookEvent> = Self.defaultEvents,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !events.isEmpty else {
            return hasManagedHooks(cursorHome: cursorHome, helperPath: helperPath, fileManager: fileManager) == false
        }
        let hooksPath = cursorHome.appendingPathComponent("hooks.json")
        guard fileManager.fileExists(atPath: hooksPath.path),
              let root = try? readJSONObject(at: hooksPath),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }
        let enabledCursorEvents = Set(events.flatMap(Self.cursorEventKeys(for:)))
        let disabledCursorEvents = Set(Self.allCursorEventKeys()).subtracting(enabledCursorEvents)
        return enabledCursorEvents.allSatisfy { cursorEvent in
            guard let entries = hooks[cursorEvent] as? [[String: Any]] else { return false }
            return entriesContainManagedCommand(entries, helperPath: helperPath)
        } && disabledCursorEvents.allSatisfy { cursorEvent in
            guard let entries = hooks[cursorEvent] as? [[String: Any]] else { return true }
            return !entriesContainManagedCommand(entries, helperPath: helperPath)
        }
    }

    func hasManagedHooks(
        cursorHome: URL = Self.defaultCursorHome(),
        helperPath: String?,
        fileManager: FileManager = .default
    ) -> Bool {
        let hooksPath = cursorHome.appendingPathComponent("hooks.json")
        guard fileManager.fileExists(atPath: hooksPath.path),
              let root = try? readJSONObject(at: hooksPath),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }
        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entriesContainManagedCommand(entries, helperPath: helperPath)
        }
    }

    func isHookInstalled(
        cursorEvent: String,
        hooks: [String: Any],
        helperPath: String?
    ) -> Bool {
        guard let entries = hooks[cursorEvent] as? [[String: Any]] else { return false }
        return entriesContainManagedCommand(entries, helperPath: helperPath)
    }

    static func defaultCursorHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = environment["CURSOR_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor")
    }

    static func cursorEventKeys(for event: AgentHookEvent) -> [String] {
        switch event {
        case .sessionStart: return ["sessionStart"]
        case .userPromptSubmit: return ["beforeSubmitPrompt"]
        case .preToolUse: return ["preToolUse"]
        case .postToolUse: return ["postToolUse"]
        case .preCompact: return ["preCompact"]
        case .postCompact: return []
        case .subagentStart: return ["subagentStart"]
        case .subagentStop: return ["subagentStop"]
        case .permissionRequest: return ["beforeShellExecution", "beforeMCPExecution"]
        case .stop: return ["stop"]
        case .sessionEnd: return ["sessionEnd"]
        }
    }

    private static func allCursorEventKeys() -> [String] {
        Array(Set(AgentHookEvent.allCases.flatMap(cursorEventKeys(for:))))
    }

    private static func isCursorEventEnabled(_ cursorEvent: String, events: Set<AgentHookEvent>) -> Bool {
        events.contains { cursorEventKeys(for: $0).contains(cursorEvent) }
    }

    private static func command(helperPath: String, source: String) -> String {
        AgentHookCommandBuilder.command(helperPath: helperPath, source: source)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        try AgentHookJSONStore.read(at: url)
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try AgentHookJSONStore.write(object, to: url)
    }

    private func removingManagedCommands(from hooks: [String: Any], helperPath: String?) -> [String: Any] {
        var hooks = hooks
        for event in Array(hooks.keys) {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let command = entry["command"] as? String else { return false }
                return isManagedCommand(command, helperPath: helperPath)
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }
        return hooks
    }

    private func entriesContainManagedCommand(_ entries: [[String: Any]], helperPath: String?) -> Bool {
        entries.contains { entry in
            guard let command = entry["command"] as? String else { return false }
            return isManagedCommand(command, helperPath: helperPath)
        }
    }

    private func isManagedCommand(_ command: String, helperPath: String?) -> Bool {
        if let helperPath,
           command == Self.command(helperPath: helperPath, source: "cursor")
            || command == helperPath {
            return true
        }
        return command.contains("lofii-agent-hook")
    }
}

private enum AgentHookCommandBuilder {
    static func command(helperPath: String, source: String) -> String {
        let executable = helperPath.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            ? helperPath
            : "\"\(helperPath)\""
        return "\(executable) --source \(source)"
    }
}

private enum AgentHookJSONStore {
    static func read(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    static func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

private extension Set where Element == AgentHookEvent {
    func sortedByDisplayOrder() -> [AgentHookEvent] {
        AgentHookEvent.allCases.filter(contains)
    }
}
