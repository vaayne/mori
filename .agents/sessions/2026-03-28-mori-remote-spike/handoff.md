# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Cross-Platform Package Foundation

**Status:** complete

**Tasks completed:**
- 1.1: Added `.iOS(.v17)` platform to `MoriCore/Package.swift`
- 1.2: Audited all MoriCore sources — no macOS-only APIs found. `SSHCommandSupport.swift` uses `CryptoKit`, `Darwin`, `Foundation` (all cross-platform). No `Process` usage in this file despite the plan's NOTE suggesting otherwise.
- 1.3: Added `.iOS(.v17)` platform to `MoriTmux/Package.swift`
- 1.4: Gated `SendableResumeGuard` and `TmuxCommandRunner` actor behind `#if os(macOS)`. Kept `TmuxSSHConfig` typealias and `TmuxError` enum cross-platform (required by `TmuxControlling.swift`).
- 1.5: Gated entire `TmuxBackend` actor behind `#if os(macOS)` (depends on `TmuxCommandRunner`).
- 1.6: Audited `PaneStateDetector.swift` and `AgentDetector.swift` — both use only `Foundation` and cross-platform types. No gating needed.
- 1.7: Audited `TmuxControlling.swift` protocol and test targets. `TmuxControlling` kept cross-platform for Phase 3 iOS use. Tests only reference cross-platform types (`TmuxParser`, `TmuxSession`, `TmuxPane`, `SessionNaming`, `PaneStateDetector`, `AgentDetector`). No gating needed.
- 1.8: Verified macOS build + tests pass: `test:core` 361/361 assertions, `test:tmux` 200/200 assertions.

**Files changed:**
- `Packages/MoriCore/Package.swift` — added `.iOS(.v17)` platform
- `Packages/MoriTmux/Package.swift` — added `.iOS(.v17)` platform
- `Packages/MoriTmux/Sources/MoriTmux/TmuxCommandRunner.swift` — `#if os(macOS)` around `SendableResumeGuard` + `TmuxCommandRunner`; `TmuxSSHConfig` and `TmuxError` remain cross-platform
- `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift` — `#if os(macOS)` around entire `TmuxBackend` actor
- `.agents/sessions/2026-03-28-mori-remote-spike/tasks.md` — task checklist updated

**Commits:**
- `4729529` — ✨ feat: add iOS 17+ platform to MoriCore package
- `35c0b78` — ✨ feat: add iOS 17+ platform to MoriTmux package
- `c727acb` — ♻️ refactor: gate TmuxCommandRunner behind #if os(macOS)
- `12279be` — ♻️ refactor: gate TmuxBackend behind #if os(macOS)

**Decisions & context for next phase:**
- `TmuxError` and `TmuxSSHConfig` are deliberately kept outside `#if os(macOS)` in `TmuxCommandRunner.swift` because `TmuxControlling.swift` (cross-platform) depends on them. If a future refactor moves these to a dedicated file, update the gate boundary.
- `TmuxControlling` protocol stays cross-platform — Phase 3's `TmuxControlClient` can conform to it on iOS.
- `PaneStateDetector`, `AgentDetector`, `TmuxParser`, `SessionNaming`, `TmuxSession`, `TmuxWindow`, `TmuxPane`, `PaneState`, `PaneDirection` are all cross-platform. Tests exercise only these types, so they work on both platforms.
- `SSHCommandSupport.swift` compiles on iOS but `createAskPassScript()` and `askPassEnvironment()` are macOS-oriented (shell-based SSH askpass). Phase 2's `MoriSSH` package will use SwiftNIO SSH directly, not these helpers. Consider gating them in a future cleanup if they confuse the iOS API surface.
- The full `mise run build` fails due to missing `GhosttyKit.xcframework` (not built in this environment), but this is unrelated to Phase 1 changes. Package-level builds (`swift build` in MoriCore/MoriTmux directories) succeed.
