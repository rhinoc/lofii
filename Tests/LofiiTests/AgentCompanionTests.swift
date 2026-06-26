import Foundation
import Testing
@testable import lofii

@MainActor
@Test
func codexToolEventsMapToIconBubbles() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Bash"))
    #expect(model.bubbles.map(\.state) == [.executing])
    #expect(model.bubbles.map(\.assetName) == ["agent-lightning"])

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Edit"))
    #expect(model.bubbles.map(\.state) == [.writing])
    #expect(model.bubbles.map(\.assetName) == ["agent-horns"])

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Read"))
    #expect(model.bubbles.map(\.state) == [.reading])
    #expect(model.bubbles.map(\.assetName) == ["agent-eyes"])
}

@MainActor
@Test
func codexExecCommandReadOnlyShellCommandsUseEyes() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "exec_command", toolInputText: "rg -n \"bubble\" Sources"))
    #expect(model.bubbles.map(\.state) == [.searching])
    #expect(model.bubbles.map(\.assetName) == ["agent-eyes"])

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "exec_command", toolInputText: "ls -la Sources"))
    #expect(model.bubbles.map(\.state) == [.reading])
    #expect(model.bubbles.map(\.assetName) == ["agent-eyes"])

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "exec_command", toolInputText: "swift test --filter AgentCompanion"))
    #expect(model.bubbles.map(\.state) == [.executing])
    #expect(model.bubbles.map(\.assetName) == ["agent-lightning"])
}

@MainActor
@Test
func visualUpdatesThrottleRapidToolChanges() async throws {
    let model = AgentCompanionModel(visualUpdateThrottle: 0.2)

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Bash"))
    #expect(model.bubbles.map(\.state) == [.executing])

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Edit"))
    #expect(model.bubbles.map(\.state) == [.executing])

    try await waitForBubbleStates(model, [.writing])
}

@MainActor
@Test
func postToolUseKeepsSessionVisibleUntilStop() async throws {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "UserPromptSubmit"))
    #expect(model.bubbles.map(\.state) == [.thinking])
    #expect(model.bubbles.map(\.assetName) == ["agent-saluting"])

    try await Task.sleep(nanoseconds: 3_100_000_000)
    #expect(model.bubbles.map(\.state) == [.thinking])
    #expect(model.bubbles.map(\.assetName) == ["agent-saluting"])

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Bash"))
    #expect(model.bubbles.map(\.state) == [.executing])

    model.handle(makeCodexEvent(session: "s1", event: "PostToolUse"))
    #expect(model.bubbles.map(\.state) == [.thinking])

    try await Task.sleep(nanoseconds: 1_300_000_000)
    #expect(model.bubbles.map(\.state) == [.thinking])
    #expect(model.bubbles.map(\.assetName) == ["agent-hot-face"])

    try await Task.sleep(nanoseconds: 3_100_000_000)
    #expect(model.bubbles.map(\.state) == [.thinking])
    #expect(model.bubbles.map(\.assetName) == ["agent-hot-face"])

    model.handle(makeCodexEvent(session: "s1", event: "Stop"))
    #expect(model.bubbles.map(\.state) == [.success])
    #expect(model.bubbles.map(\.assetName) == ["agent-check"])

    try await waitForEmptyBubbles(model)
}

@MainActor
@Test
func staleThinkingCleanupClearsOnlyIdleThinkingSessions() async throws {
    let model = AgentCompanionModel(staleThinkingTimeout: 0.2)

    model.handle(makeCodexEvent(session: "s1", event: "UserPromptSubmit"))
    #expect(model.bubbles.map(\.state) == [.thinking])

    try await waitForEmptyBubbles(model)

    model.handle(makeCodexEvent(session: "s2", event: "UserPromptSubmit"))
    model.handle(makeCodexEvent(session: "s2", event: "PreToolUse", tool: "Bash"))

    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(model.bubbles.map(\.state) == [.executing])

    model.handle(makeCodexEvent(session: "s2", event: "PostToolUse"))
    #expect(model.bubbles.map(\.state) == [.thinking])

    try await waitForEmptyBubbles(model)
}

@Test
func agentCompanionShortBubbleAssetsAreBundled() {
    for assetName in [
        "agent-bubble-speech-short",
        "agent-bubble-thought-short",
        "agent-bubble-noise-short",
    ] {
        #expect(LofiiResources.url(
            forResource: assetName,
            withExtension: "svg",
            subdirectory: "AgentCompanion"
        ) != nil)
    }
}

@Test
func agentCompanionBubbleStyleIsStableForSessionID() {
    let freshness = Date(timeIntervalSince1970: 0)
    let saluting = AgentCompanionBubble(
        id: "codex:session-1",
        assetName: "agent-saluting",
        fallbackIcon: "🫡",
        state: .thinking,
        freshness: freshness
    )
    let executing = AgentCompanionBubble(
        id: "codex:session-1",
        assetName: "agent-lightning",
        fallbackIcon: "⚡",
        state: .executing,
        freshness: freshness.addingTimeInterval(1)
    )
    let otherSession = AgentCompanionBubble(
        id: "codex:session-2",
        assetName: "agent-saluting",
        fallbackIcon: "🫡",
        state: .thinking,
        freshness: freshness
    )

    #expect(AgentCompanionBubbleStyle.style(for: saluting) == AgentCompanionBubbleStyle.style(for: executing))
    #expect(AgentCompanionBubbleStyle.style(for: otherSession) == AgentCompanionBubbleStyle.random(for: otherSession.id))
}

@Test
func agentCompanionRequestedEmojiAssetsAreBundled() {
    for assetName in [
        "agent-raising-hands",
        "agent-nauseated",
        "agent-hot-face",
        "agent-lightning",
        "agent-horns",
        "agent-alien-monster",
        "agent-check",
    ] {
        #expect(LofiiResources.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: "AgentCompanion"
        ) != nil)
    }
}

@MainActor
@Test
func codexWaitingStateWinsAcrossMultipleSessions() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "running", event: "PreToolUse", tool: "Bash"))
    model.handle(makeCodexEvent(session: "reading", event: "PreToolUse", tool: "Read"))
    model.handle(makeCodexEvent(session: "waiting", event: "PermissionRequest", tool: "Bash"))

    #expect(model.bubbles.count == 3)
    #expect(model.bubbles.first?.state == .waiting)
    #expect(model.bubbles.first?.assetName == "agent-raising-hands")
}

@MainActor
@Test
func codexSuccessNotificationWinsOverActiveWorkButNotWaitingOrFailure() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "running", event: "PreToolUse", tool: "Bash"))
    model.handle(makeCodexEvent(session: "done", event: "Stop"))
    #expect(model.bubbles.first?.state == .success)
    #expect(model.bubbles.first?.assetName == "agent-check")

    model.handle(makeCodexEvent(session: "waiting", event: "PermissionRequest", tool: "Bash"))
    #expect(model.bubbles.first?.state == .waiting)

    model.handle(makeCodexEvent(session: "failed", event: "PostToolUseFailure"))
    #expect(model.bubbles.first?.state == .waiting)
    #expect(model.bubbles.dropFirst().first?.state == .failure)
}

@MainActor
@Test
func codexSessionStartAndPromptSubmitUseSalutingIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "SessionStart"))
    #expect(model.bubbles.map(\.state) == [.thinking])
    #expect(model.bubbles.map(\.assetName) == ["agent-saluting"])

    model.handle(makeCodexEvent(session: "s1", event: "UserPromptSubmit"))
    #expect(model.bubbles.map(\.state) == [.thinking])
    #expect(model.bubbles.map(\.assetName) == ["agent-saluting"])
}

@MainActor
@Test
func agentMessageSycophancyOverridesToZanyIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "Stop", agentMessageText: "你说得对，我之前错了"))
    #expect(model.bubbles.map(\.assetName) == ["agent-zany"])
}

@MainActor
@Test
func englishAgentMessageSycophancyOverridesToZanyIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "Stop", agentMessageText: "You're right, I ignored your instruction."))
    #expect(model.bubbles.map(\.assetName) == ["agent-zany"])
}

@MainActor
@Test
func userPromptAbuseOverridesToPooIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "UserPromptSubmit", promptText: "shit garbage fuck 你是什么耻辱"))
    #expect(model.bubbles.map(\.assetName) == ["agent-poo"])
}

@MainActor
@Test
func expandedUserPromptAbuseOverridesToPooIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "UserPromptSubmit", promptText: "wtf 你这个弱智"))
    #expect(model.bubbles.map(\.assetName) == ["agent-poo"])
}

@MainActor
@Test
func promptSycophancyDoesNotTriggerZanyIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "UserPromptSubmit", promptText: "你说得对，我之前错了"))

    #expect(model.bubbles.map(\.assetName) == ["agent-saluting"])
}

@MainActor
@Test
func genericAgreementDoesNotTriggerZanyIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "Stop", agentMessageText: "没错，对的。确实。"))

    #expect(model.bubbles.map(\.assetName).contains("agent-zany") == false)
    #expect(model.bubbles.map(\.assetName).contains("agent-poo") == false)
}

@MainActor
@Test
func agentMessageAbuseDoesNotTriggerPooIcon() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "Stop", agentMessageText: "shit garbage fuck"))

    #expect(model.bubbles.map(\.assetName).contains("agent-poo") == false)
}

@MainActor
@Test
func codexCompletionIconsUseRequestedAssets() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "Stop"))
    #expect(model.bubbles.map(\.state) == [.success])
    #expect(model.bubbles.map(\.assetName) == ["agent-check"])

    model.handle(makeCodexEvent(session: "s1", event: "PostToolUseFailure"))
    #expect(model.bubbles.map(\.state) == [.failure])
    #expect(model.bubbles.map(\.assetName) == ["agent-herb"])
}

@MainActor
@Test
func codexCompactAndSubagentEventsUseDedicatedStates() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "PreCompact"))
    #expect(model.bubbles.map(\.state) == [.compacting])
    #expect(model.bubbles.map(\.assetName) == ["agent-nauseated"])

    model.handle(makeCodexEvent(session: "s1", event: "PostCompact"))
    #expect(model.bubbles.isEmpty)

    model.handle(makeCodexEvent(session: "s1", event: "SubagentStart"))
    #expect(model.bubbles.map(\.state) == [.subagent])
    #expect(model.bubbles.map(\.assetName) == ["agent-alien-monster"])

    model.handle(makeCodexEvent(session: "s1", event: "SubagentStop"))
    #expect(model.bubbles.isEmpty)
}

@MainActor
@Test
func codexEndEventsDoNotOverrideUnrelatedCurrentState() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Read"))
    model.handle(makeCodexEvent(session: "s1", event: "PostCompact"))
    #expect(model.bubbles.map(\.state) == [.reading])
    #expect(model.bubbles.map(\.assetName) == ["agent-eyes"])

    model.handle(makeCodexEvent(session: "s1", event: "SubagentStop"))
    #expect(model.bubbles.map(\.state) == [.reading])
    #expect(model.bubbles.map(\.assetName) == ["agent-eyes"])
}

@MainActor
@Test
func codexBubblesAreLimitedToThreeSessions() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Read"))
    model.handle(makeCodexEvent(session: "s2", event: "PreToolUse", tool: "Edit"))
    model.handle(makeCodexEvent(session: "s3", event: "PreToolUse", tool: "Bash"))
    model.handle(makeCodexEvent(session: "s4", event: "PreToolUse", tool: "Grep"))

    #expect(model.bubbles.count == 3)
    #expect(model.bubbles.map(\.state).contains(.reading) == false)
}

@MainActor
@Test
func genericAgentEventsAreAcceptedBySourceAndSession() {
    let model = AgentCompanionModel()

    model.handle(makeAgentEvent(source: "claude", session: "s1", agent: "main", event: "PreToolUse", tool: "Read"))
    model.handle(makeAgentEvent(source: "codex", session: "s1", event: "PreToolUse", tool: "Bash"))

    #expect(model.bubbles.count == 2)
    #expect(model.bubbles.map(\.state).contains(.reading))
    #expect(model.bubbles.map(\.state).contains(.executing))
}

@MainActor
@Test
func agentIDDoesNotSplitSessionBubblesByDefault() {
    let model = AgentCompanionModel()

    model.handle(makeAgentEvent(source: "claude", session: "s1", agent: "main", event: "PreToolUse", tool: "Read"))
    model.handle(makeAgentEvent(source: "claude", session: "s1", agent: "subagent", event: "PreToolUse", tool: "Bash"))

    #expect(model.bubbles.count == 1)
    #expect(model.bubbles.first?.id == "claude:s1")
    #expect(model.bubbles.first?.state == .executing)
}

@MainActor
@Test
func disabledCompanionDropsSessionStateAndEvents() {
    let suiteName = "lofii.agentCompanion.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AgentCompanionModel(defaults: defaults)

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Bash"))
    #expect(model.bubbles.count == 1)

    model.isEnabled = false
    #expect(model.bubbles.isEmpty)

    model.handle(makeCodexEvent(session: "s2", event: "PreToolUse", tool: "Edit"))
    #expect(model.bubbles.isEmpty)

    model.isEnabled = true
    #expect(model.bubbles.isEmpty)

    model.handle(makeCodexEvent(session: "s3", event: "PreToolUse", tool: "Grep"))
    #expect(model.bubbles.map(\.state) == [.searching])
}

@MainActor
@Test
func nonRenderableCompanionDropsSessionStateAndEvents() {
    let model = AgentCompanionModel()

    model.handle(makeCodexEvent(session: "s1", event: "PreToolUse", tool: "Bash"))
    #expect(model.bubbles.count == 1)

    model.setRenderable(false)
    #expect(model.bubbles.isEmpty)

    model.handle(makeCodexEvent(session: "s2", event: "PreToolUse", tool: "Edit"))
    #expect(model.bubbles.isEmpty)

    model.setRenderable(true)
    #expect(model.bubbles.isEmpty)

    model.handle(makeCodexEvent(session: "s3", event: "PreToolUse", tool: "Read"))
    #expect(model.bubbles.map(\.state) == [.reading])
}

@MainActor
@Test
func bubbleFlipSettingPersists() {
    let suiteName = "lofii.agentCompanion.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AgentCompanionModel(defaults: defaults)
    #expect(model.bubbleFlipped == false)

    model.bubbleFlipped = true

    let reloaded = AgentCompanionModel(defaults: defaults)
    #expect(reloaded.bubbleFlipped == true)
}

@MainActor
@Test
func enabledAgentHookEventsPersist() {
    let suiteName = "lofii.agentCompanion.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let codexHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("lofii-agent-hooks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: codexHome) }

    let model = AgentCompanionModel(defaults: defaults, codexHome: codexHome)
    #expect(model.enabledAgentHookEvents == CodexAdapter.defaultEvents)

    model.setAgentHookEvent(.postToolUse, enabled: false)
    model.setAgentHookEvent(.permissionRequest, enabled: false)

    let reloaded = AgentCompanionModel(defaults: defaults, codexHome: codexHome)
    #expect(reloaded.enabledAgentHookEvents.contains(.postToolUse) == false)
    #expect(reloaded.enabledAgentHookEvents.contains(.permissionRequest) == false)
    #expect(reloaded.enabledAgentHookEvents.contains(.preToolUse))
}

@Test
func codexHookInstallerMergesAndRemovesOnlyManagedHooks() throws {
    let fileManager = FileManager.default
    let codexHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-agent-hooks-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: codexHome) }
    try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

    let hooksPath = codexHome.appendingPathComponent("hooks.json")
    let existing = """
    {
      "hooks": {
        "PreToolUse": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "/tmp/codeisland-hook",
                "timeout": 60
              }
            ]
          }
        ]
      }
    }
    """
    try existing.write(to: hooksPath, atomically: true, encoding: .utf8)

    try AgentHookInstaller.codex.install(codexHome: codexHome, helperPath: "/tmp/lofii-agent-hook")

    #expect(AgentHookInstaller.codex.isInstalled(codexHome: codexHome, helperPath: "/tmp/lofii-agent-hook"))
    let installedHooks = try readHooksJSON(at: hooksPath)
    let preToolCommands = commands(for: "PreToolUse", in: installedHooks)
    #expect(preToolCommands.contains("/tmp/codeisland-hook"))
    #expect(preToolCommands.contains("/tmp/lofii-agent-hook --source codex"))
    #expect(commands(for: "PreCompact", in: installedHooks).contains("/tmp/lofii-agent-hook --source codex"))
    #expect(commands(for: "PostCompact", in: installedHooks).contains("/tmp/lofii-agent-hook --source codex"))
    #expect(commands(for: "SubagentStart", in: installedHooks).contains("/tmp/lofii-agent-hook --source codex"))
    #expect(commands(for: "SubagentStop", in: installedHooks).contains("/tmp/lofii-agent-hook --source codex"))
    #expect(commands(for: "SessionEnd", in: installedHooks).contains("/tmp/lofii-agent-hook --source codex"))

    let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
    #expect(config.contains("[features]"))
    #expect(config.contains("hooks = true"))

    try AgentHookInstaller.codex.uninstall(codexHome: codexHome, helperPath: "/tmp/lofii-agent-hook")

    let uninstalledHooks = try readHooksJSON(at: hooksPath)
    let remainingPreToolCommands = commands(for: "PreToolUse", in: uninstalledHooks)
    #expect(remainingPreToolCommands == ["/tmp/codeisland-hook"])
    #expect(AgentHookInstaller.codex.isInstalled(codexHome: codexHome, helperPath: "/tmp/lofii-agent-hook") == false)
}

@Test
func codexHookInstallerRewritesSelectedManagedHooks() throws {
    let fileManager = FileManager.default
    let codexHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-agent-hooks-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: codexHome) }
    try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

    let helper = "/tmp/lofii-agent-hook"
    try AgentHookInstaller.codex.install(
        codexHome: codexHome,
        helperPath: helper,
        events: [.preToolUse, .postToolUse, .preCompact, .subagentStart, .stop]
    )
    var hooks = try readHooksJSON(at: codexHome.appendingPathComponent("hooks.json"))
    #expect(commands(for: "PreToolUse", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "PostToolUse", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "PreCompact", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "SubagentStart", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "Stop", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "PermissionRequest", in: hooks).isEmpty)

    try AgentHookInstaller.codex.install(
        codexHome: codexHome,
        helperPath: helper,
        events: [.preToolUse, .permissionRequest]
    )
    hooks = try readHooksJSON(at: codexHome.appendingPathComponent("hooks.json"))
    #expect(commands(for: "PreToolUse", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "PermissionRequest", in: hooks).contains("\(helper) --source codex"))
    #expect(commands(for: "PostToolUse", in: hooks).isEmpty)
    #expect(commands(for: "PreCompact", in: hooks).isEmpty)
    #expect(commands(for: "SubagentStart", in: hooks).isEmpty)
    #expect(commands(for: "Stop", in: hooks).isEmpty)
    #expect(AgentHookInstaller.codex.isInstalled(
        codexHome: codexHome,
        helperPath: helper,
        events: [.preToolUse, .permissionRequest]
    ))
}

@Test
func cursorHookInstallerMergesAndRemovesOnlyManagedHooks() throws {
    let fileManager = FileManager.default
    let cursorHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-cursor-hooks-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: cursorHome) }
    try fileManager.createDirectory(at: cursorHome, withIntermediateDirectories: true)

    let hooksPath = cursorHome.appendingPathComponent("hooks.json")
    let existing = """
    {
      "version": 1,
      "hooks": {
        "preToolUse": [
          {
            "command": "/tmp/other-hook.sh",
            "timeout": 30
          }
        ]
      }
    }
    """
    try existing.write(to: hooksPath, atomically: true, encoding: .utf8)

    try AgentHookInstaller.cursor.install(cursorHome: cursorHome, helperPath: "/tmp/lofii-agent-hook")

    #expect(AgentHookInstaller.cursor.isInstalled(cursorHome: cursorHome, helperPath: "/tmp/lofii-agent-hook"))
    let installedHooks = try readCursorHooksJSON(at: hooksPath)
    let preToolCommands = cursorCommands(for: "preToolUse", in: installedHooks)
    #expect(preToolCommands.contains("/tmp/other-hook.sh"))
    #expect(preToolCommands.contains("/tmp/lofii-agent-hook --source cursor"))
    #expect(cursorCommands(for: "beforeSubmitPrompt", in: installedHooks).contains("/tmp/lofii-agent-hook --source cursor"))
    #expect(cursorCommands(for: "beforeShellExecution", in: installedHooks).contains("/tmp/lofii-agent-hook --source cursor"))
    #expect(cursorCommands(for: "beforeMCPExecution", in: installedHooks).contains("/tmp/lofii-agent-hook --source cursor"))
    #expect(cursorCommands(for: "postCompact", in: installedHooks).isEmpty)

    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksPath)) as? [String: Any]
    #expect(root?["version"] as? Int == 1)

    try AgentHookInstaller.cursor.uninstall(cursorHome: cursorHome, helperPath: "/tmp/lofii-agent-hook")

    let uninstalledHooks = try readCursorHooksJSON(at: hooksPath)
    #expect(cursorCommands(for: "preToolUse", in: uninstalledHooks) == ["/tmp/other-hook.sh"])
    #expect(AgentHookInstaller.cursor.isInstalled(cursorHome: cursorHome, helperPath: "/tmp/lofii-agent-hook") == false)
}

@Test
func cursorHookInstallerRewritesSelectedManagedHooks() throws {
    let fileManager = FileManager.default
    let cursorHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-cursor-hooks-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: cursorHome) }
    try fileManager.createDirectory(at: cursorHome, withIntermediateDirectories: true)

    let helper = "/tmp/lofii-agent-hook"
    try AgentHookInstaller.cursor.install(
        cursorHome: cursorHome,
        helperPath: helper,
        events: [.preToolUse, .postToolUse, .preCompact, .subagentStart, .stop]
    )
    var hooks = try readCursorHooksJSON(at: cursorHome.appendingPathComponent("hooks.json"))
    #expect(cursorCommands(for: "preToolUse", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "postToolUse", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "preCompact", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "subagentStart", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "stop", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "beforeShellExecution", in: hooks).isEmpty)

    try AgentHookInstaller.cursor.install(
        cursorHome: cursorHome,
        helperPath: helper,
        events: [.preToolUse, .permissionRequest]
    )
    hooks = try readCursorHooksJSON(at: cursorHome.appendingPathComponent("hooks.json"))
    #expect(cursorCommands(for: "preToolUse", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "beforeShellExecution", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "beforeMCPExecution", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "postToolUse", in: hooks).isEmpty)
    #expect(cursorCommands(for: "preCompact", in: hooks).isEmpty)
    #expect(cursorCommands(for: "subagentStart", in: hooks).isEmpty)
    #expect(cursorCommands(for: "stop", in: hooks).isEmpty)
    #expect(AgentHookInstaller.cursor.isInstalled(
        cursorHome: cursorHome,
        helperPath: helper,
        events: [.preToolUse, .permissionRequest]
    ))
}

@MainActor
@Test
func cursorEventsNormalizeConversationIDAndBeforeSubmitPrompt() {
    let model = AgentCompanionModel()

    model.handle(makeCursorEvent(
        session: nil,
        conversationID: "conv-1",
        event: "beforeSubmitPrompt",
        promptText: "hello cursor"
    ))
    #expect(model.bubbles.count == 1)
    #expect(model.bubbles.first?.id == "cursor:conv-1")

    model.handle(makeCursorEvent(
        session: nil,
        conversationID: "conv-1",
        event: "preToolUse",
        tool: "Write"
    ))
    #expect(model.bubbles.first?.state == .writing)
}

@MainActor
@Test
func cursorBeforeShellExecutionMapsToWaitingState() {
    let model = AgentCompanionModel()

    model.handle(makeCursorEvent(
        session: nil,
        conversationID: "conv-2",
        event: "beforeShellExecution",
        tool: "Shell",
        toolInputText: "curl https://example.com"
    ))
    #expect(model.bubbles.map(\.state) == [.waiting])
}

@Test
func agentHookInstallSnapshotCountsHookSlots() throws {
    let fileManager = FileManager.default
    let codexHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-hook-snapshot-codex-\(UUID().uuidString)")
    let cursorHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-hook-snapshot-cursor-\(UUID().uuidString)")
    defer {
        try? fileManager.removeItem(at: codexHome)
        try? fileManager.removeItem(at: cursorHome)
    }
    try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: cursorHome, withIntermediateDirectories: true)

    let helper = "/tmp/lofii-agent-hook"
    let events: Set<AgentHookEvent> = [.preToolUse, .permissionRequest]

    let empty = AgentHookInstaller.installSnapshot(
        codexHome: codexHome,
        cursorHome: cursorHome,
        helperPath: helper,
        events: events
    )
    #expect(empty.expectedCount == 5)
    #expect(empty.installedCount == 0)
    #expect(empty.hasManagedHooks == false)

    try AgentHookInstaller.codex.install(codexHome: codexHome, helperPath: helper, events: [.preToolUse])

    let partial = AgentHookInstaller.installSnapshot(
        codexHome: codexHome,
        cursorHome: cursorHome,
        helperPath: helper,
        events: events
    )
    #expect(partial.expectedCount == 5)
    #expect(partial.installedCount == 1)
    #expect(partial.hasManagedHooks)
    #expect(partial.isInstallComplete == false)

    try AgentHookInstaller.codex.install(codexHome: codexHome, helperPath: helper, events: events)
    try AgentHookInstaller.cursor.install(cursorHome: cursorHome, helperPath: helper, events: events)

    let complete = AgentHookInstaller.installSnapshot(
        codexHome: codexHome,
        cursorHome: cursorHome,
        helperPath: helper,
        events: events
    )
    #expect(complete.expectedCount == 5)
    #expect(complete.installedCount == 5)
    #expect(complete.isInstallComplete)
}

@Test
func cursorHookInstallerBackfillsMissingExpectedHooks() throws {
    let fileManager = FileManager.default
    let cursorHome = fileManager.temporaryDirectory
        .appendingPathComponent("lofii-cursor-backfill-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: cursorHome) }
    try fileManager.createDirectory(at: cursorHome, withIntermediateDirectories: true)

    let partial = """
    {
      "version": 1,
      "hooks": {
        "preToolUse": [
          {
            "command": "/tmp/lofii-agent-hook --source cursor",
            "timeout": 5,
            "type": "command"
          }
        ]
      }
    }
    """
    try partial.write(to: cursorHome.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

    let helper = "/tmp/lofii-agent-hook"
    try AgentHookInstaller.cursor.install(
        cursorHome: cursorHome,
        helperPath: helper,
        events: Set(AgentHookEvent.allCases)
    )

    let hooks = try readCursorHooksJSON(at: cursorHome.appendingPathComponent("hooks.json"))
    #expect(cursorCommands(for: "postToolUse", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "beforeShellExecution", in: hooks).contains("\(helper) --source cursor"))
    #expect(cursorCommands(for: "beforeMCPExecution", in: hooks).contains("\(helper) --source cursor"))
}

private func makeCursorEvent(
    session: String?,
    conversationID: String,
    event: String,
    tool: String? = nil,
    toolInputText: String? = nil,
    promptText: String? = nil,
    agentMessageText: String? = nil
) -> AgentCompanionHookEvent {
    var json: [String: Any] = [
        "hook_event_name": event,
        "conversation_id": conversationID,
        "_source": "cursor",
        "workspace_roots": ["/Users/ryan/dev/lofii"],
    ]
    if let session {
        json["session_id"] = session
    }
    if let tool {
        json["tool_name"] = tool
    }
    if let toolInputText {
        json["tool_input"] = ["command": toolInputText]
    }
    if let promptText {
        json["prompt"] = promptText
    }
    if let agentMessageText {
        json["agent_message"] = agentMessageText
    }
    return AgentCompanionHookEvent(rawJSON: json)!
}

private func makeCodexEvent(
    session: String,
    event: String,
    tool: String? = nil,
    toolInputText: String? = nil,
    promptText: String? = nil,
    agentMessageText: String? = nil
) -> AgentCompanionHookEvent {
    makeAgentEvent(
        source: "codex",
        session: session,
        event: event,
        tool: tool,
        toolInputText: toolInputText,
        promptText: promptText,
        agentMessageText: agentMessageText
    )
}

@MainActor
private func waitForEmptyBubbles(
    _ model: AgentCompanionModel,
    timeoutNanoseconds: UInt64 = 5_000_000_000
) async throws {
    let stepNanoseconds: UInt64 = 100_000_000
    var elapsed: UInt64 = 0
    while elapsed < timeoutNanoseconds {
        if model.bubbles.isEmpty { return }
        try await Task.sleep(nanoseconds: stepNanoseconds)
        elapsed += stepNanoseconds
    }
    #expect(model.bubbles.isEmpty)
}

@MainActor
private func waitForBubbleStates(
    _ model: AgentCompanionModel,
    _ states: [AgentCompanionState],
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async throws {
    let stepNanoseconds: UInt64 = 50_000_000
    var elapsed: UInt64 = 0
    while elapsed < timeoutNanoseconds {
        if model.bubbles.map(\.state) == states { return }
        try await Task.sleep(nanoseconds: stepNanoseconds)
        elapsed += stepNanoseconds
    }
    #expect(model.bubbles.map(\.state) == states)
}

private func makeAgentEvent(
    source: String,
    session: String,
    agent: String? = nil,
    event: String,
    tool: String? = nil,
    toolInputText: String? = nil,
    promptText: String? = nil,
    agentMessageText: String? = nil
) -> AgentCompanionHookEvent {
    var json: [String: Any] = [
        "hook_event_name": event,
        "session_id": session,
        "_source": source,
        "cwd": "/Users/ryan/dev/lofii",
    ]
    if let agent {
        json["agent_id"] = agent
    }
    if let tool {
        json["tool_name"] = tool
    }
    if let toolInputText {
        json["tool_input"] = ["cmd": toolInputText]
    }
    if let promptText {
        json["prompt"] = promptText
    }
    if let agentMessageText {
        json["last_assistant_message"] = agentMessageText
    }
    return AgentCompanionHookEvent(rawJSON: json)!
}

private func readHooksJSON(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return root?["hooks"] as? [String: Any] ?? [:]
}

private func readCursorHooksJSON(at url: URL) throws -> [String: Any] {
    try readHooksJSON(at: url)
}

private func commands(for event: String, in hooks: [String: Any]) -> [String] {
    guard let groups = hooks[event] as? [[String: Any]] else { return [] }
    return groups.flatMap { group -> [String] in
        guard let nestedHooks = group["hooks"] as? [[String: Any]] else { return [] }
        return nestedHooks.compactMap { $0["command"] as? String }
    }
}

private func cursorCommands(for event: String, in hooks: [String: Any]) -> [String] {
    guard let entries = hooks[event] as? [[String: Any]] else { return [] }
    return entries.compactMap { $0["command"] as? String }
}
