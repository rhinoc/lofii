# AGENTS.md

## Evidence-First Debugging

When the user reports a concrete runtime fact, treat it as the starting fact to verify, not as something to speculate around.

- Do not contradict or route around a user-observed fact without first gathering direct evidence from this machine.
- Before changing code for a runtime bug, verify the live path with local state: running process, `UserDefaults`, current preset/source, API response, cache files, logs, and the specific renderer/loader involved.
- If a claim is testable locally, test it before proposing causes. For example, for track artwork issues, verify the current `LiveTrack`, artwork URL, cached file, `NSImage` decode, and `MTKTextureLoader` decode before discussing fallback behavior.
- Separate diagnosis from implementation. If the user asks for analysis, keep the turn read-only. If implementation is appropriate, make only the smallest fix that follows from verified evidence.
- Do not add workaround code for unverified hypotheses. If an exploratory patch was based on a disproven hypothesis, remove it before finishing.
- When multiple render paths exist, identify the active path from current state before editing. In this app, Bongo-enabled visual modes use `BongoView` / unified Metal rendering rather than the ordinary SwiftUI background path.
- In final replies, distinguish verified facts from inferences. State what was checked and what remains unverified.

## Lofii Runtime Checks

Useful probes before editing visual/audio runtime bugs:

- `defaults read dev.rhinoc.lofii`
- `pgrep -af 'lofii|Lofii|LofiNative'`
- `ps -p <pid> -o pid,ppid,comm,args,lstart`
- `log show --style compact --last 10m --predicate 'process CONTAINS "lofii" OR eventMessage CONTAINS "StageMetal" OR eventMessage CONTAINS "BongoUnifiedMetal"'`
- For Chillhop: fetch the active station API and inspect the current track/artwork URL.
- For cached media: inspect the real cache file with `ls -l`, `file`, and a direct decode check when possible.

## Current Architecture Reminders

- `VisualMode` selection lives in `AppModel`.
- Main widget background routing lives in `WidgetRootView` in `ContentView.swift`.
- Bongo overlay is not just an overlay for all modes: when enabled, background media is routed through `BongoView` and the unified Metal renderer.
- Ordinary GIF/video/image Metal playback uses `StageMetalPlayerView`; Bongo-enabled playback uses `BongoUnifiedMetalView`.
- Readout UI should remain text-only unless explicitly requested otherwise; track artwork belongs in system media controls or dedicated visual modes.
