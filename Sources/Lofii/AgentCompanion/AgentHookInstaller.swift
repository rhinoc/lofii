import Foundation

enum AgentHookInstaller {
    static let codex = CodexAdapter()
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
        let executable = helperPath.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            ? helperPath
            : "\"\(helperPath)\""
        return "\(executable) --source \(source)"
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
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

private extension Set where Element == AgentHookEvent {
    func sortedByDisplayOrder() -> [AgentHookEvent] {
        AgentHookEvent.allCases.filter(contains)
    }
}
