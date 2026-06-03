# Agent Companion Hooks

Lofii receives agent hook events through a small helper binary:

```text
lofii-agent-hook
```

The main app listens on a local Unix socket:

```text
/tmp/lofii-agent-<uid>.sock
```

Providers share the same bridge and app server. The bridge tags each payload
with `_source`, then the app normalizes the payload through a source adapter.
Codex is the first adapter.

## App Setup

Open BongoCat settings and use `Agent Hooks` -> `Install`.

The current installer writes Codex hook entries to `$CODEX_HOME/hooks.json` or
`~/.codex/hooks.json`, and enables hooks in `config.toml`:

```toml
[features]
hooks = true
```

Existing non-Lofii hook commands are preserved. `Uninstall` only removes
commands whose executable is `lofii-agent-hook`.

## Development Reference

Build the helper:

```bash
swift build --product lofii-agent-hook
```

Use the built helper path if you need to inspect or write a temporary
`hooks.json` manually. Codex should pass `--source codex`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 5,
            "command": "/path/to/lofii/.build/debug/lofii-agent-hook --source codex"
          }
        ]
      }
    ]
  }
}
```

The helper is fire-and-forget: it never approves or denies Codex permission
requests. Codex keeps its normal approval flow.
