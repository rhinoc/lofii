import Combine
import Foundation

enum AgentCompanionState: Equatable, Sendable {
    case idle
    case thinking
    case reading
    case writing
    case executing
    case searching
    case compacting
    case subagent
    case waiting
    case success
    case failure

    var priority: Int {
        switch self {
        case .waiting: return 90
        case .failure: return 85
        case .success: return 82
        case .compacting: return 75
        case .executing: return 70
        case .subagent: return 68
        case .writing: return 65
        case .searching: return 60
        case .reading: return 55
        case .thinking: return 45
        case .idle: return 0
        }
    }

    var fallbackIcon: String { "👀" }
}

struct AgentCompanionSession: Identifiable, Equatable, Sendable {
    let source: String
    let sessionID: String
    var agentID: String?
    var projectName: String?
    var state: AgentCompanionState
    var assetName: String
    var fallbackIcon: String
    var toolName: String?
    var lastActivity: Date
    var lastVisualUpdate: Date

    var id: String { "\(source):\(sessionID)" }
}

struct AgentCompanionBubble: Identifiable, Equatable, Sendable {
    let id: String
    let assetName: String
    let fallbackIcon: String
    let state: AgentCompanionState
    let freshness: Date
}

enum AgentCompanionBubblePosition: String, CaseIterable, Identifiable, Sendable {
    case topRight
    case topLeft
    case above
    case right

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .topRight: return "Top R"
        case .topLeft: return "Top L"
        case .above: return "Above"
        case .right: return "Right"
        }
    }
}

struct AgentCompanionHookEvent: Sendable {
    let eventName: String
    let source: String
    let sessionID: String
    let agentID: String?
    let cwd: String?
    let toolName: String?
    let toolInputText: String?
    let promptText: String?
    let agentMessageText: String?

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        self.init(rawJSON: object)
    }

    init?(rawJSON json: [String: Any]) {
        guard let source = AgentCompanionSourceAdapter.source(in: json),
              let event = AgentCompanionSourceAdapter.adapter(for: source).normalize(json)
        else { return nil }
        self = event
    }

    init?(
        source: String,
        eventName: String?,
        sessionID: String?,
        agentID: String?,
        cwd: String?,
        toolName: String?,
        toolInputText: String?,
        promptText: String?,
        agentMessageText: String?
    ) {
        guard let eventName, let sessionID else {
            return nil
        }
        self.source = source
        self.eventName = eventName
        self.sessionID = sessionID
        self.agentID = agentID
        self.cwd = cwd
        self.toolName = toolName
        self.toolInputText = toolInputText
        self.promptText = promptText
        self.agentMessageText = agentMessageText
    }
}

protocol AgentCompanionEventAdapter: Sendable {
    var source: String { get }
    func normalize(_ json: [String: Any]) -> AgentCompanionHookEvent?
}

enum AgentCompanionSourceAdapter {
    private static let adapters: [String: any AgentCompanionEventAdapter] = [
        "codex": CodexCompanionAdapter(),
    ]

    static func source(in json: [String: Any]) -> String? {
        firstString(in: json, keys: ["_source", "source", "agent_source", "agentSource"])?.lowercased()
    }

    static func adapter(for source: String) -> any AgentCompanionEventAdapter {
        adapters[source] ?? GenericCompanionAdapter(source: source)
    }

    static func firstString(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func firstString(
        inNestedDictionary json: [String: Any],
        containerKeys: [String],
        keys: [String]
    ) -> String? {
        for containerKey in containerKeys {
            guard let nested = json[containerKey] as? [String: Any] else { continue }
            if let value = firstString(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }

    static func firstText(
        inNestedDictionary json: [String: Any],
        containerKeys: [String],
        keys: [String]
    ) -> String? {
        for containerKey in containerKeys {
            guard let nested = json[containerKey] as? [String: Any] else { continue }
            if let value = firstString(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }

    static func normalizeEventName(_ name: String) -> String {
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

    static func promptText(in json: [String: Any], eventName: String) -> String? {
        if eventName == "UserPromptSubmit" {
            return firstString(
                in: json,
                keys: ["prompt", "user_prompt", "userPrompt", "message", "input", "content", "text"]
            )
                ?? firstText(
                    inNestedDictionary: json,
                    containerKeys: ["payload", "data"],
                    keys: ["prompt", "user_prompt", "userPrompt", "message", "input", "content", "text"]
                )
        }
        return firstString(in: json, keys: ["last_user_message", "user_message", "userMessage", "prompt"])
            ?? firstText(
                inNestedDictionary: json,
                containerKeys: ["payload", "data"],
                keys: ["last_user_message", "user_message", "userMessage", "prompt"]
            )
    }

    static func agentMessageText(in json: [String: Any], eventName: String) -> String? {
        guard eventName != "UserPromptSubmit" else { return nil }
        return firstString(
            in: json,
            keys: ["last_assistant_message", "assistant_message", "assistantMessage", "message", "text", "summary", "detail", "content"]
        )
            ?? firstText(
                inNestedDictionary: json,
                containerKeys: ["payload", "data"],
                keys: ["last_assistant_message", "assistant_message", "assistantMessage", "message", "text", "summary", "detail", "content"]
            )
    }

    static func toolInputText(in json: [String: Any]) -> String? {
        if let text = firstString(in: json, keys: ["cmd", "command", "tool_input", "toolInput", "arguments"]) {
            return text
        }
        for containerKey in ["tool_input", "toolInput", "tool", "payload", "data", "arguments"] {
            guard let nested = json[containerKey] as? [String: Any] else { continue }
            if let text = firstString(in: nested, keys: ["cmd", "command", "script", "input", "arguments"]) {
                return text
            }
        }
        return nil
    }
}

struct CodexCompanionAdapter: AgentCompanionEventAdapter {
    let source = "codex"

    func normalize(_ json: [String: Any]) -> AgentCompanionHookEvent? {
        let eventName = AgentCompanionSourceAdapter.firstString(
            in: json,
            keys: ["hook_event_name", "hookEventName", "event_name", "eventName", "event"]
        ).map(AgentCompanionSourceAdapter.normalizeEventName)
        return AgentCompanionHookEvent(
            source: source,
            eventName: eventName,
            sessionID: AgentCompanionSourceAdapter.firstString(in: json, keys: ["session_id", "sessionId"]),
            agentID: AgentCompanionSourceAdapter.firstString(in: json, keys: ["agent_id", "agentId"]),
            cwd: AgentCompanionSourceAdapter.firstString(in: json, keys: ["cwd"]),
            toolName: AgentCompanionSourceAdapter.firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"])
                ?? AgentCompanionSourceAdapter.firstString(
                    inNestedDictionary: json,
                    containerKeys: ["tool", "payload", "data"],
                    keys: ["name", "tool_name", "toolName"]
                ),
            toolInputText: AgentCompanionSourceAdapter.toolInputText(in: json),
            promptText: eventName.flatMap { AgentCompanionSourceAdapter.promptText(in: json, eventName: $0) },
            agentMessageText: eventName.flatMap { AgentCompanionSourceAdapter.agentMessageText(in: json, eventName: $0) }
        )
    }
}

struct GenericCompanionAdapter: AgentCompanionEventAdapter {
    let source: String

    func normalize(_ json: [String: Any]) -> AgentCompanionHookEvent? {
        let eventName = AgentCompanionSourceAdapter.firstString(
            in: json,
            keys: ["hook_event_name", "hookEventName", "event_name", "eventName", "event"]
        ).map(AgentCompanionSourceAdapter.normalizeEventName)
        return AgentCompanionHookEvent(
            source: source,
            eventName: eventName,
            sessionID: AgentCompanionSourceAdapter.firstString(in: json, keys: ["session_id", "sessionId"]),
            agentID: AgentCompanionSourceAdapter.firstString(in: json, keys: ["agent_id", "agentId"]),
            cwd: AgentCompanionSourceAdapter.firstString(in: json, keys: ["cwd"]),
            toolName: AgentCompanionSourceAdapter.firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"])
                ?? AgentCompanionSourceAdapter.firstString(
                    inNestedDictionary: json,
                    containerKeys: ["tool", "payload", "data"],
                    keys: ["name", "tool_name", "toolName"]
                ),
            toolInputText: AgentCompanionSourceAdapter.toolInputText(in: json),
            promptText: eventName.flatMap { AgentCompanionSourceAdapter.promptText(in: json, eventName: $0) },
            agentMessageText: eventName.flatMap { AgentCompanionSourceAdapter.agentMessageText(in: json, eventName: $0) }
        )
    }
}

@MainActor
final class AgentCompanionModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isActive {
                refreshBubbles()
            } else {
                clearSessions()
            }
        }
    }
    @Published private(set) var isRenderable = true
    @Published var bubblePosition: AgentCompanionBubblePosition {
        didSet {
            guard bubblePosition != oldValue else { return }
            defaults.set(bubblePosition.rawValue, forKey: Self.bubblePositionKey)
        }
    }
    @Published var bubbleFlipped: Bool {
        didSet {
            guard bubbleFlipped != oldValue else { return }
            defaults.set(bubbleFlipped, forKey: Self.bubbleFlippedKey)
        }
    }
    @Published var enabledAgentHookEvents: Set<AgentHookEvent> {
        didSet {
            guard enabledAgentHookEvents != oldValue else { return }
            log("model.hooks.events.change from=\(Self.logAgentHookEvents(oldValue)) to=\(Self.logAgentHookEvents(enabledAgentHookEvents))")
            saveEnabledAgentHookEvents()
            syncInstalledAgentHooksIfNeeded()
        }
    }
    @Published private(set) var bubbles: [AgentCompanionBubble] = []
    @Published private(set) var agentHooksInstalled = false

    private let defaults: UserDefaults
    private let codexHome: URL
    private let visualUpdateThrottle: TimeInterval
    private let staleThinkingTimeout: TimeInterval
    private var sessions: [String: AgentCompanionSession] = [:]
    private var pendingSessions: [String: AgentCompanionSession] = [:]
    private var pendingUpdateTasks: [String: Task<Void, Never>] = [:]
    private var expiryTasks: [String: Task<Void, Never>] = [:]
    private var hookServer: AgentCompanionHookServer?

    private struct ToolStateDecision {
        let state: AgentCompanionState
        let reason: String
        let executable: String?
    }

    private static let enabledKey = "lofii.agentCompanion.enabled"
    private static let bubblePositionKey = "lofii.agentCompanion.bubblePosition"
    private static let bubbleFlippedKey = "lofii.agentCompanion.bubbleFlipped"
    private static let enabledAgentHookEventsKey = "lofii.agentCompanion.enabledAgentHookEvents"

    init(
        defaults: UserDefaults = .standard,
        visualUpdateThrottle: TimeInterval = 0,
        codexHome: URL = CodexAdapter.defaultCodexHome(),
        staleThinkingTimeout: TimeInterval = 300
    ) {
        self.defaults = defaults
        self.codexHome = codexHome
        self.visualUpdateThrottle = max(0, visualUpdateThrottle)
        self.staleThinkingTimeout = max(0, staleThinkingTimeout)
        isEnabled = Self.loadEnabled(defaults)
        bubblePosition = Self.loadBubblePosition(defaults)
        bubbleFlipped = defaults.bool(forKey: Self.bubbleFlippedKey)
        enabledAgentHookEvents = Self.loadEnabledAgentHookEvents(defaults)
        refreshAgentHookStatus()
    }

    func startAgentHookServer() {
        log("model.server.startRequested hasServer=\(hookServer != nil)")
        if hookServer == nil {
            hookServer = AgentCompanionHookServer(model: self)
        }
        hookServer?.start()
    }

    func refreshAgentHookStatus() {
        let installed = AgentHookInstaller.codex.isInstalled(
            codexHome: codexHome,
            helperPath: Self.agentHookBridgePath(),
            events: enabledAgentHookEvents
        )
        guard agentHooksInstalled != installed else { return }
        agentHooksInstalled = installed
        log("model.hooks.status installed=\(installed) enabledEvents=\(Self.logAgentHookEvents(enabledAgentHookEvents))")
    }

    func setAgentHookEvent(_ event: AgentHookEvent, enabled: Bool) {
        if enabled {
            enabledAgentHookEvents.insert(event)
        } else {
            enabledAgentHookEvents.remove(event)
        }
    }

    func setRenderable(_ renderable: Bool) {
        guard isRenderable != renderable else { return }
        log("model.renderable.change from=\(isRenderable) to=\(renderable)")
        isRenderable = renderable
        if isActive {
            refreshBubbles()
        } else {
            clearSessions()
        }
    }

    func installAgentHooks() {
        guard let helperPath = Self.agentHookBridgePath() else {
            NSLog("[AgentCompanion] Cannot install agent hooks: lofii-agent-hook helper missing")
            log("model.hooks.install.failed reason=missing-helper")
            agentHooksInstalled = false
            return
        }
        log("model.hooks.install.start helper=\(Self.logField(helperPath)) enabledEvents=\(Self.logAgentHookEvents(enabledAgentHookEvents))")
        do {
            try AgentHookInstaller.codex.install(codexHome: codexHome, helperPath: helperPath, events: enabledAgentHookEvents)
            log("model.hooks.install.done helper=\(Self.logField(helperPath))")
        } catch {
            NSLog("[AgentCompanion] Failed to install agent hooks: \(error)")
            log("model.hooks.install.failed helper=\(Self.logField(helperPath)) error=\(Self.logField(String(describing: error)))")
        }
        refreshAgentHookStatus()
    }

    func uninstallAgentHooks() {
        log("model.hooks.uninstall.start")
        do {
            try AgentHookInstaller.codex.uninstall(codexHome: codexHome, helperPath: Self.agentHookBridgePath())
            log("model.hooks.uninstall.done")
        } catch {
            NSLog("[AgentCompanion] Failed to uninstall agent hooks: \(error)")
            log("model.hooks.uninstall.failed error=\(Self.logField(String(describing: error)))")
        }
        refreshAgentHookStatus()
    }

    func handle(_ event: AgentCompanionHookEvent) {
        guard isActive else {
            log(
                "model.event.drop reason=inactive enabled=\(isEnabled) renderable=\(isRenderable) source=\(event.source) event=\(event.eventName) session=\(Self.logField(event.sessionID)) tool=\(Self.logField(event.toolName))"
            )
            return
        }

        let now = Date()
        let key = Self.sessionKey(for: event)
        let previousSession = sessions[key]
        log(
            "model.event.begin key=\(Self.logField(key)) source=\(event.source) event=\(event.eventName) previousState=\(Self.logState(previousSession?.state)) previousAsset=\(Self.logField(previousSession?.assetName)) tool=\(Self.logField(event.toolName)) toolInput=\(Self.logField(event.toolInputText))"
        )
        var session = sessions[key] ?? AgentCompanionSession(
            source: event.source,
            sessionID: event.sessionID,
            agentID: event.agentID,
            projectName: event.cwd.map(Self.projectName),
            state: .idle,
            assetName: Self.assetName(for: .idle, event: event),
            fallbackIcon: Self.fallbackIcon(forAssetName: Self.assetName(for: .idle, event: event)),
            toolName: nil,
            lastActivity: now,
            lastVisualUpdate: .distantPast
        )

        if let cwd = event.cwd {
            session.projectName = Self.projectName(cwd)
        }
        session.agentID = event.agentID
        session.lastActivity = now

        switch event.eventName {
        case "SessionStart":
            session.state = .thinking
            session.toolName = nil
            session.assetName = Self.keywordAssetName(for: event) ?? "agent-saluting"
            scheduleStaleThinkingCleanup(for: key)
        case "UserPromptSubmit":
            session.state = .thinking
            session.toolName = nil
            session.assetName = Self.keywordAssetName(for: event) ?? "agent-saluting"
            scheduleStaleThinkingCleanup(for: key)
        case "PreToolUse":
            session.toolName = event.toolName
            let decision = Self.toolStateDecision(forToolName: event.toolName, toolInputText: event.toolInputText)
            session.state = decision.state
            log(
                "model.toolState key=\(Self.logField(key)) tool=\(Self.logField(event.toolName)) executable=\(Self.logField(decision.executable)) state=\(Self.logState(decision.state)) reason=\(decision.reason) toolInput=\(Self.logField(event.toolInputText))"
            )
            session.assetName = Self.assetName(for: session.state, event: event)
            cancelExpiry(for: key)
        case "PostToolUse":
            session.state = .thinking
            session.toolName = nil
            session.assetName = Self.assetName(for: .thinking, event: event)
            scheduleStaleThinkingCleanup(for: key)
        case "PreCompact":
            session.state = .compacting
            session.toolName = nil
            session.assetName = Self.assetName(for: .compacting, event: event)
            cancelExpiry(for: key)
        case "PostCompact":
            if session.state == .compacting {
                sessions.removeValue(forKey: key)
                cancelPendingUpdate(for: key)
                cancelExpiry(for: key)
                refreshBubbles()
                log("model.event.remove key=\(Self.logField(key)) event=\(event.eventName) reason=postCompact")
                return
            }
            log("model.event.ignore key=\(Self.logField(key)) event=\(event.eventName) reason=notCompacting currentState=\(Self.logState(session.state))")
            return
        case "SubagentStart":
            session.state = .subagent
            session.toolName = nil
            session.assetName = Self.assetName(for: .subagent, event: event)
            cancelExpiry(for: key)
        case "SubagentStop":
            if session.state == .subagent {
                sessions.removeValue(forKey: key)
                cancelPendingUpdate(for: key)
                cancelExpiry(for: key)
                refreshBubbles()
                log("model.event.remove key=\(Self.logField(key)) event=\(event.eventName) reason=subagentStop")
                return
            }
            log("model.event.ignore key=\(Self.logField(key)) event=\(event.eventName) reason=notSubagent currentState=\(Self.logState(session.state))")
            return
        case "PostToolUseFailure":
            session.state = .failure
            session.toolName = nil
            session.assetName = Self.assetName(for: .failure, event: event)
            cancelExpiry(for: key)
        case "PermissionRequest":
            session.state = .waiting
            session.toolName = event.toolName
            session.assetName = Self.assetName(for: .waiting, event: event)
            cancelExpiry(for: key)
        case "Stop":
            session.state = .success
            session.toolName = nil
            session.assetName = Self.assetName(for: .success, event: event)
            scheduleExpiry(for: key, after: 3)
        case "SessionEnd":
            sessions.removeValue(forKey: key)
            cancelPendingUpdate(for: key)
            cancelExpiry(for: key)
            refreshBubbles()
            log("model.event.remove key=\(Self.logField(key)) event=\(event.eventName) reason=sessionEnd")
            return
        default:
            session.state = .thinking
            session.toolName = nil
            session.assetName = Self.assetName(for: .thinking, event: event)
            scheduleStaleThinkingCleanup(for: key)
        }
        session.fallbackIcon = Self.fallbackIcon(forAssetName: session.assetName)
        log(
            "model.event.resolved key=\(Self.logField(key)) event=\(event.eventName) state=\(Self.logState(session.state)) asset=\(Self.logField(session.assetName)) fallback=\(Self.logField(session.fallbackIcon))"
        )

        applyVisualUpdate(session, key: key, now: now, eventName: event.eventName)
    }

    private static func state(forToolName toolName: String?, toolInputText: String? = nil) -> AgentCompanionState {
        toolStateDecision(forToolName: toolName, toolInputText: toolInputText).state
    }

    private static func toolStateDecision(
        forToolName toolName: String?,
        toolInputText: String? = nil
    ) -> ToolStateDecision {
        let raw = (toolName ?? "").lowercased()
        if isGenericShellToolName(raw) {
            let executable = firstShellExecutable(in: toolInputText)
            if let executable, !executable.isEmpty {
                if readOnlyShellExecutables.contains(executable) {
                    return ToolStateDecision(state: .reading, reason: "shell.readOnly", executable: executable)
                }
                if searchShellExecutables.contains(executable) {
                    return ToolStateDecision(state: .searching, reason: "shell.search", executable: executable)
                }
            }
        }
        if raw.contains("bash") || raw.contains("shell") || raw.contains("exec") || raw.contains("command") {
            return ToolStateDecision(state: .executing, reason: "tool.shellLike", executable: nil)
        }
        if raw.contains("write") || raw.contains("edit") || raw.contains("patch") || raw.contains("apply") {
            return ToolStateDecision(state: .writing, reason: "tool.writeLike", executable: nil)
        }
        if raw.contains("grep") || raw.contains("glob") || raw.contains("search") || raw.contains("find") {
            return ToolStateDecision(state: .searching, reason: "tool.searchLike", executable: nil)
        }
        if raw.contains("read") || raw.contains("open") || raw.contains("fetch") || raw.contains("cat") {
            return ToolStateDecision(state: .reading, reason: "tool.readLike", executable: nil)
        }
        return ToolStateDecision(state: .thinking, reason: "tool.defaultThinking", executable: nil)
    }

    private static func isGenericShellToolName(_ raw: String) -> Bool {
        raw == "exec_command" ||
            raw == "bash" ||
            raw == "shell" ||
            raw.contains("exec") ||
            raw.contains("command")
    }

    private static func firstShellExecutable(in command: String?) -> String? {
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        let token = trimmed
            .split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == ";" || $0 == "|" || $0 == "&" }
            .first
            .map(String.init) ?? ""
        return URL(fileURLWithPath: token).lastPathComponent.lowercased()
    }

    private static let readOnlyShellExecutables: Set<String> = [
        "cat",
        "defaults",
        "file",
        "head",
        "jq",
        "ls",
        "nl",
        "plutil",
        "sed",
        "stat",
        "tail",
        "wc",
    ]

    private static let searchShellExecutables: Set<String> = [
        "fd",
        "find",
        "grep",
        "rg",
        "tree",
    ]

    private static func assetName(for state: AgentCompanionState, event: AgentCompanionHookEvent) -> String {
        if let keywordAssetName = keywordAssetName(for: event) {
            return keywordAssetName
        }
        switch state {
        case .idle: return "agent-eyes"
        case .thinking: return "agent-hot-face"
        case .reading, .searching: return "agent-eyes"
        case .writing: return "agent-horns"
        case .executing: return "agent-lightning"
        case .compacting: return "agent-nauseated"
        case .subagent: return "agent-alien-monster"
        case .waiting: return "agent-raising-hands"
        case .success: return "agent-check"
        case .failure: return "agent-herb"
        }
    }

    private static func randomAssetName(_ names: [String]) -> String {
        names.randomElement() ?? "agent-eyes"
    }

    private static func keywordAssetName(for event: AgentCompanionHookEvent) -> String? {
        if containsPromptAbuse(event.promptText) {
            return "agent-poo"
        }
        guard let text = event.agentMessageText else { return nil }
        let normalized = text.lowercased()
        let sycophanticPatterns = [
            "你说得对",
            "你说的对",
            "你说得完全正确",
            "你说的完全正确",
            "你是对的",
            "完全同意你的判断",
            "完全是我的问题",
            "我之前错了",
            "我刚才错了",
            "我错了",
            "是我错了",
            "刚才是我错了",
            "确实是我错了",
            "确实是我的问题",
            "你抓得对",
            "你指出得对",
            "你提醒得对",
            "我没有听从",
            "我没听从",
            "我没有遵守",
            "我没有执行",
            "我没按要求",
            "我没有按指令",
            "我忽略了你的要求",
            "我没有按你的要求",
            "我漏看了",
            "我误解了",
            "you are right",
            "you're right",
            "you were right",
            "you caught that",
            "you caught me",
            "i was wrong",
            "i made a mistake",
            "my mistake",
            "i failed to follow",
            "i didn't follow",
            "i did not follow",
            "i ignored your instruction",
            "i missed your instruction",
            "i should have followed",
        ]
        if sycophanticPatterns.contains(where: normalized.contains) {
            return "agent-zany"
        }
        return nil
    }

    private static func containsPromptAbuse(_ text: String?) -> Bool {
        guard let text else { return false }
        let normalized = text.lowercased()
        return [
            "shit",
            "garbage",
            "trash",
            "fuck",
            "fucking",
            "bullshit",
            "crap",
            "wtf",
            "idiot",
            "stupid",
            "moron",
            "useless",
            "shame",
            "屎",
            "鬼",
            "垃圾",
            "耻辱",
            "废物",
            "傻逼",
            "傻屌",
            "脑残",
            "弱智",
            "智障",
            "白痴",
            "蠢货",
            "混蛋",
            "操",
            "艹",
            "他妈",
            "妈的",
            "滚",
            "烂",
        ].contains(where: normalized.contains)
    }

    private static func fallbackIcon(forAssetName assetName: String) -> String {
        switch assetName {
        case "agent-saluting": return "🫡"
        case "agent-zany": return "🤪"
        case "agent-thinking": return "🤔"
        case "agent-nerd": return "🤓"
        case "agent-nauseated": return "🤢"
        case "agent-raising-hands": return "🙌"
        case "agent-flexed-biceps": return "💪"
        case "agent-horns": return "🤘"
        case "agent-hot-face": return "🥵"
        case "agent-fire": return "🔥"
        case "agent-joystick": return "🕹️"
        case "agent-cartwheeling": return "🤸"
        case "agent-alien-monster": return "👾"
        case "agent-sparkles": return "✨"
        case "agent-herb": return "🌿"
        case "agent-party-popper": return "🎉"
        case "agent-poo": return "💩"
        case "agent-check": return "✅"
        case "agent-rocket": return "🚀"
        case "agent-lightning": return "⚡"
        case "agent-flushed": return "😳"
        case "agent-eyes": return "👀"
        default: return "👀"
        }
    }

    private static func projectName(_ cwd: String) -> String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    private static func sessionKey(for event: AgentCompanionHookEvent) -> String {
        return "\(event.source):\(event.sessionID)"
    }

    private func refreshBubbles() {
        guard isActive else {
            if !bubbles.isEmpty {
                log("model.bubbles.clear reason=inactive previous=\(Self.logBubbleSummary(bubbles))")
            }
            bubbles = []
            return
        }
        let nextBubbles = sessions.values
            .filter { $0.state != .idle }
            .sorted { lhs, rhs in
                if lhs.state.priority != rhs.state.priority {
                    return lhs.state.priority > rhs.state.priority
                }
                return lhs.lastActivity > rhs.lastActivity
            }
            .prefix(3)
            .map {
                AgentCompanionBubble(
                    id: $0.id,
                    assetName: $0.assetName,
                    fallbackIcon: $0.fallbackIcon,
                    state: $0.state,
                    freshness: $0.lastActivity
                )
            }
        if bubbles != nextBubbles {
            log(
                "model.bubbles.update count=\(nextBubbles.count) previous=\(Self.logBubbleSummary(bubbles)) next=\(Self.logBubbleSummary(nextBubbles)) sessions=\(Self.logSessionSummary(sessions))"
            )
        }
        bubbles = nextBubbles
    }

    private var isActive: Bool {
        isEnabled && isRenderable
    }

    private func clearSessions() {
        log(
            "model.sessions.clear sessions=\(sessions.count) bubbles=\(bubbles.count) pending=\(pendingUpdateTasks.count) expiry=\(expiryTasks.count)"
        )
        for task in pendingUpdateTasks.values {
            task.cancel()
        }
        for task in expiryTasks.values {
            task.cancel()
        }
        pendingSessions = [:]
        pendingUpdateTasks = [:]
        expiryTasks = [:]
        sessions = [:]
        bubbles = []
    }

    private func applyVisualUpdate(
        _ session: AgentCompanionSession,
        key: String,
        now: Date,
        eventName: String
    ) {
        let elapsed = now.timeIntervalSince(sessions[key]?.lastVisualUpdate ?? .distantPast)
        let applyImmediately = visualUpdateThrottle == 0
            || Self.bypassesVisualThrottle(eventName)
            || elapsed >= visualUpdateThrottle
        guard applyImmediately else {
            log(
                "model.visual.defer key=\(Self.logField(key)) event=\(eventName) elapsed=\(Self.logInterval(elapsed)) wait=\(Self.logInterval(visualUpdateThrottle - elapsed)) state=\(Self.logState(session.state)) asset=\(Self.logField(session.assetName))"
            )
            pendingSessions[key] = session
            schedulePendingVisualUpdate(for: key, after: visualUpdateThrottle - elapsed)
            return
        }

        cancelPendingUpdate(for: key)
        var session = session
        session.lastVisualUpdate = now
        sessions[key] = session
        log(
            "model.visual.apply key=\(Self.logField(key)) event=\(eventName) immediate=\(applyImmediately) state=\(Self.logState(session.state)) asset=\(Self.logField(session.assetName))"
        )
        refreshBubbles()
    }

    private static func bypassesVisualThrottle(_ eventName: String) -> Bool {
        switch eventName {
        case "SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUseFailure", "Stop":
            return true
        default:
            return false
        }
    }

    private func schedulePendingVisualUpdate(for key: String, after seconds: TimeInterval) {
        guard pendingUpdateTasks[key] == nil else { return }
        log("model.visual.schedulePending key=\(Self.logField(key)) after=\(Self.logInterval(seconds))")
        pendingUpdateTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                guard var session = self.pendingSessions.removeValue(forKey: key) else {
                    self.pendingUpdateTasks[key] = nil
                    self.log("model.visual.pendingSkip key=\(Self.logField(key)) reason=noPendingSession")
                    return
                }
                session.lastVisualUpdate = Date()
                self.sessions[key] = session
                self.pendingUpdateTasks[key] = nil
                self.log(
                    "model.visual.pendingApply key=\(Self.logField(key)) state=\(Self.logState(session.state)) asset=\(Self.logField(session.assetName))"
                )
                self.refreshBubbles()
            }
        }
    }

    private func cancelPendingUpdate(for key: String) {
        if pendingSessions[key] != nil || pendingUpdateTasks[key] != nil {
            log("model.visual.cancelPending key=\(Self.logField(key))")
        }
        pendingSessions[key] = nil
        pendingUpdateTasks[key]?.cancel()
        pendingUpdateTasks[key] = nil
    }

    private func scheduleExpiry(for key: String, after seconds: TimeInterval) {
        cancelExpiry(for: key)
        log("model.expiry.schedule key=\(Self.logField(key)) after=\(Self.logInterval(seconds))")
        expiryTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                return
            }
            await MainActor.run {
                guard let self else { return }
                guard var session = self.sessions[key] else { return }
                session.state = .idle
                session.toolName = nil
                self.sessions[key] = session
                self.expiryTasks[key] = nil
                self.log("model.expiry.apply key=\(Self.logField(key))")
                self.refreshBubbles()
            }
        }
    }

    private func scheduleStaleThinkingCleanup(for key: String) {
        cancelExpiry(for: key)
        log("model.stale.schedule key=\(Self.logField(key)) after=\(Self.logInterval(staleThinkingTimeout))")
        let timeout = staleThinkingTimeout
        expiryTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            await MainActor.run {
                guard let self else { return }
                guard var session = self.sessions[key] else {
                    self.expiryTasks[key] = nil
                    return
                }
                guard session.state == .thinking, session.toolName == nil else {
                    self.expiryTasks[key] = nil
                    self.log(
                        "model.stale.skip key=\(Self.logField(key)) state=\(Self.logState(session.state)) tool=\(Self.logField(session.toolName))"
                    )
                    return
                }
                session.state = .idle
                session.toolName = nil
                self.sessions[key] = session
                self.expiryTasks[key] = nil
                self.log("model.stale.apply key=\(Self.logField(key))")
                self.refreshBubbles()
            }
        }
    }

    private func cancelExpiry(for key: String) {
        if expiryTasks[key] != nil {
            log("model.expiry.cancel key=\(Self.logField(key))")
        }
        expiryTasks[key]?.cancel()
        expiryTasks[key] = nil
    }

    private func log(_ message: String) {
        DiagnosticLog.appendAgentCompanion(message)
    }

    private static func logField(_ value: String?, maxLength: Int = 180) -> String {
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

    private static func logState(_ state: AgentCompanionState?) -> String {
        state.map { String(describing: $0) } ?? "nil"
    }

    private static func logInterval(_ interval: TimeInterval) -> String {
        String(format: "%.3fs", max(0, interval))
    }

    private static func logBubbleSummary(_ bubbles: [AgentCompanionBubble]) -> String {
        guard !bubbles.isEmpty else { return "[]" }
        return "[\(bubbles.map { "\($0.id):\(String(describing: $0.state)):\($0.assetName)" }.joined(separator: ","))]"
    }

    private static func logSessionSummary(_ sessions: [String: AgentCompanionSession]) -> String {
        guard !sessions.isEmpty else { return "[]" }
        return "[\(sessions.values.sorted { $0.id < $1.id }.map { "\($0.id):\(String(describing: $0.state)):\($0.assetName)" }.joined(separator: ","))]"
    }

    private static func logAgentHookEvents(_ events: Set<AgentHookEvent>) -> String {
        "[\(AgentHookEvent.allCases.filter(events.contains).map(\.rawValue).joined(separator: ","))]"
    }

    private static func loadEnabled(_ defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: enabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: enabledKey)
    }

    private static func loadBubblePosition(_ defaults: UserDefaults) -> AgentCompanionBubblePosition {
        guard let raw = defaults.string(forKey: bubblePositionKey),
              let position = AgentCompanionBubblePosition(rawValue: raw)
        else {
            return .topRight
        }
        return position
    }

    private static func loadEnabledAgentHookEvents(_ defaults: UserDefaults) -> Set<AgentHookEvent> {
        guard let rawValues = defaults.stringArray(forKey: enabledAgentHookEventsKey) else {
            return CodexAdapter.defaultEvents
        }
        return Set(rawValues.compactMap(AgentHookEvent.init(rawValue:)))
    }

    private func saveEnabledAgentHookEvents() {
        let rawValues = AgentHookEvent.allCases
            .filter(enabledAgentHookEvents.contains)
            .map(\.rawValue)
        defaults.set(rawValues, forKey: Self.enabledAgentHookEventsKey)
    }

    private func syncInstalledAgentHooksIfNeeded() {
        guard AgentHookInstaller.codex.hasManagedHooks(codexHome: codexHome, helperPath: Self.agentHookBridgePath()) || agentHooksInstalled else {
            refreshAgentHookStatus()
            return
        }
        installAgentHooks()
    }

    private static func agentHookBridgePath(fileManager: FileManager = .default) -> String? {
        var candidates: [URL] = []
        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("lofii-agent-hook")
            )
        }
        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(".build/debug/lofii-agent-hook")
        )

        return candidates.first { url in
            fileManager.isExecutableFile(atPath: url.path)
        }?.path
    }
}
