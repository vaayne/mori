# Plan: Phase 3 — Agent-first

## Overview

Make Mori agent-aware and automatable. Detect what's running in each terminal pane, tag windows with semantic roles, notify users of important events, and expose a CLI for scripting.

### Goals

- Tag windows with semantic roles (editor, agent, server, logs, tests) for filtering and grouping
- Detect agent state (running, waiting, error, completed) from pane output patterns
- Enhance window/worktree badges with running/error/long-running status
- Deliver macOS native notifications for key events (agent waiting, errors, long commands)
- Expose a CLI (`ws`) over Unix socket for automation
- Support lifecycle hooks (on-create, on-focus, on-close) via per-project config

### Success Criteria

- [ ] Windows carry semantic tags; sidebar and command palette can filter by tag
- [ ] Agent state detected from pane output patterns and reflected in badges
- [ ] Badges show running/error/long-running (30s threshold) status
- [ ] macOS notifications fire for agent-waiting, command-error, long-running-complete
- [ ] Dock badge shows aggregate unread count
- [ ] `ws` CLI communicates with running app via Unix socket
- [ ] Per-project `.mori/hooks.json` triggers scripts on lifecycle events
- [ ] All existing tests pass; new features have test coverage
- [ ] Zero build warnings under Swift 6 strict concurrency

### Out of Scope

- Agent-specific detection (Claude Code, Cursor, Aider) — generic patterns only
- Cloud sync or remote collaboration
- XPC service (Unix socket is sufficient)
- URL scheme (`mori://`) — deferred to Phase 4
- Finder integration / Services menu

## Technical Approach

### Key Decisions

1. **Window semantic tags** — New `WindowTag` enum in MoriCore. Stored on `RuntimeWindow` and `WindowTemplate`. Auto-assigned from template names, overridable via command palette.
2. **Agent detection** — New `PaneStateDetector` in MoriTmux that reads pane output via `tmux capture-pane` and matches patterns (prompt markers, error indicators). Runs during the coordinated 5s poll. Uses a MoriTmux-local `DetectedAgentState` enum (String raw values), converted to MoriCore `AgentState` in WorkspaceManager.
3. **Pane command state** — Extend `TmuxParser` pane format to include `#{pane_current_command}` and `#{pane_start_time}`. Derive running/idle/long-running from command name + start time. Exit codes are best-effort via output pattern matching (tmux only provides `#{pane_dead_status}` for dead panes).
4. **Notifications** — `UNUserNotificationCenter` in app target. Fires on state transitions (idle→waiting, idle→error, running→completed after >30s). Dock badge via `NSApp.dockTile.badgeLabel`. Debounce logic extracted to a pure `NotificationDebouncer` in MoriCore for testability.
5. **CLI/IPC** — New `MoriIPC` package with shared protocol. App embeds `IPCServer` using `Network.framework` (`NWListener` with Unix socket `NWEndpoint`), which is Swift concurrency-friendly on macOS 14+. Separate `ws` executable target uses `IPCClient`. CLI uses `swift-argument-parser` for arg parsing.
6. **Hooks** — `HookRunner` in app target reads `.mori/hooks.json` from project root. Fires shell commands via `Process` on lifecycle events. No new package needed.

### Components

- **`WindowTag`** (MoriCore): Enum — shell, editor, agent, server, logs, tests
- **`DetectedAgentState`** (MoriTmux): Local enum — none, running, waitingForInput, error, completed (String raw values, no MoriCore dependency)
- **`PaneStateDetector`** (MoriTmux): Captures pane output, matches patterns → `PaneState`
- **`PaneState`** (MoriTmux): Struct — command, isRunning, isLongRunning, detectedAgentState, exitCode
- **`NotificationDebouncer`** (MoriCore): Pure logic for state transition detection and debounce
- **`IPCServer`** / **`IPCClient`** (MoriIPC): Network.framework Unix socket, JSON protocol
- **`IPCProtocol`** (MoriIPC): Shared request/response types
- **`HookRunner`** (app target): Reads `.mori/hooks.json`, executes on events
- **`NotificationManager`** (app target): UNUserNotificationCenter wrapper using NotificationDebouncer

## Implementation Phases

### Phase 1: Window Semantic Tags (6 tasks)

1.1. Create `WindowTag` enum in MoriCore (files: `Packages/MoriCore/Sources/MoriCore/Models/WindowTag.swift`)
  - Cases: `shell`, `editor`, `agent`, `server`, `logs`, `tests`
  - Codable, Sendable, Equatable, RawRepresentable (String)

1.2. Add `tag` field to `RuntimeWindow` and `.longRunning` case to `WindowBadge` (files: `Packages/MoriCore/Sources/MoriCore/Models/RuntimeWindow.swift`, `Packages/MoriCore/Sources/MoriCore/Models/WindowBadge.swift`)
  - `public var tag: WindowTag?` on RuntimeWindow, default nil; add to init
  - Add `.longRunning` case to `WindowBadge` (needed in Phase 2/3 for richer badges)

1.3. Add `tag` field to `WindowTemplate` (files: `Packages/MoriCore/Sources/MoriCore/Models/SessionTemplate.swift`, `Packages/MoriCore/Sources/MoriCore/Models/TemplateRegistry.swift`)
  - Add `tag: WindowTag?` to `WindowTemplate`
  - Update `TemplateRegistry` built-in templates with appropriate tags:
    - basic: shell→.shell, run→.shell, logs→.logs
    - go: editor→.editor, server→.server, tests→.tests, logs→.logs
    - agent: editor→.editor, agent→.agent, server→.server, logs→.logs

1.4. Auto-assign tags during template application (files: `Sources/Mori/App/TemplateApplicator.swift`, `Sources/Mori/App/WorkspaceManager.swift`)
  - When creating windows from template, propagate tag to RuntimeWindow
  - Infer tag from window name if template doesn't specify (heuristic: "agent"→.agent, "logs"→.logs, "server"→.server, "editor"→.editor, "test*"→.tests, default→.shell)
  - Add tag inference function to MoriCore for testability

1.5. Show tags in sidebar and command palette (files: `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`, `Sources/Mori/App/CommandPaletteItem.swift`, `Sources/Mori/App/CommandPaletteDataSource.swift`)
  - WindowRowView: show tag icon (SF Symbol) next to window name
    - .shell→"terminal", .editor→"pencil", .agent→"cpu", .server→"server.rack", .logs→"doc.text", .tests→"checkmark.circle"
  - CommandPaletteItem.window: include tag in subtitle
  - Command palette: filter by tag prefix (e.g. "tag:agent")

1.6. Tests for WindowTag and tag propagation (files: `Packages/MoriCore/Tests/MoriCoreTests/main.swift`)
  - WindowTag enum raw values
  - RuntimeWindow with tag
  - Tag inference from window name
  - WindowBadge.longRunning raw value

### Phase 2: Agent State Detection (7 tasks)

2.1. Add `pane_current_command` and `pane_start_time` to TmuxParser (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxParser.swift`, `Packages/MoriTmux/Sources/MoriTmux/TmuxPane.swift`)
  - Extend pane format: add `#{pane_current_command}`, `#{pane_start_time}`
  - Add `currentCommand: String?` and `startTime: TimeInterval?` to TmuxPane
  - Update parsePanes to extract new fields

2.2. Create `DetectedAgentState` enum and `PaneState` model in MoriTmux (files: `Packages/MoriTmux/Sources/MoriTmux/PaneState.swift`)
  - `DetectedAgentState`: enum with String raw values — `none`, `running`, `waitingForInput`, `error`, `completed` (MoriTmux-local, no MoriCore dependency)
  - `PaneState` struct: `command: String?`, `isRunning: Bool`, `isLongRunning: Bool`, `detectedAgentState: DetectedAgentState`, `exitCode: Int?`
  - `isLongRunning` = command running > 30 seconds (computed from `startTime`)
  - `exitCode` is best-effort: parsed from captured output patterns like "exit code: N", "exited with N". Nil if not detected.

2.3. Create `PaneStateDetector` (files: `Packages/MoriTmux/Sources/MoriTmux/PaneStateDetector.swift`)
  - `static func detect(pane: TmuxPane, capturedOutput: String, now: TimeInterval) -> PaneState`
  - Agent pattern matching on captured output:
    - waitingForInput: lines ending with "> ", "? ", "waiting for input", "[Y/n]", "Press any key"
    - error: lines containing "error:", "Error:", "FAILED", "panic:", "fatal:"
    - completed: lines containing "Done", "Complete", "Finished" near end of output
    - running: if currentCommand != shell and none of the above match
  - Command state: if `currentCommand` ∉ {bash, zsh, fish, sh, -bash, -zsh} → isRunning=true
  - Long-running: `now - startTime > 30` and isRunning
  - Shell processes: isRunning=false (shell itself is not "running a command")

2.4. Add `capture-pane` to TmuxBackend (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift`, `Packages/MoriTmux/Sources/MoriTmux/TmuxControlling.swift`)
  - `func capturePaneOutput(paneId: String, lineCount: Int) async throws -> String`
  - Uses `tmux capture-pane -p -t <paneId> -S -<lineCount>`
  - Add to `TmuxControlling` protocol with default stub that throws `notYetImplemented`

2.5. Integrate detection into coordinated poll (files: `Sources/Mori/App/WorkspaceManager.swift`)
  - During `coordinatedPoll`, after tmux scan:
    1. Iterate `appState.runtimeWindows` where `tag == .agent`
    2. For each, find matching tmux window via `latestSessions` (match on `tmuxWindowId`)
    3. Get active pane ID from the tmux window's panes
    4. Call `tmuxBackend.capturePaneOutput(paneId:lineCount:20)`
    5. Call `PaneStateDetector.detect(pane:capturedOutput:now:)`
    6. Map `DetectedAgentState` → MoriCore `AgentState` (same raw values, direct mapping)
    7. Update `RuntimeWindow.badge` and parent `Worktree.agentState`
  - For non-agent windows: derive running/idle from pane `currentCommand` field (no capture needed)

2.6. Update StatusAggregator for richer badges (files: `Packages/MoriCore/Sources/MoriCore/Models/StatusAggregator.swift`, `Packages/MoriCore/Sources/MoriCore/Models/AlertState.swift`)
  - New `windowBadge(hasUnreadOutput:isRunning:isLongRunning:agentState:)` method
  - Priority: error > waiting > longRunning > running > unread > idle
  - Map `.longRunning` badge to `AlertState.warning` in `alertState(from:)`

2.7. Tests for PaneStateDetector and DetectedAgentState (files: `Packages/MoriTmux/Tests/MoriTmuxTests/main.swift`)
  - DetectedAgentState raw values
  - Pattern matching for agent states (waiting, error, completed, running)
  - Running/idle detection from command name
  - Long-running detection from timestamps
  - Shell command filtering

### Phase 3: Worktree Status Enhancements (4 tasks)

3.1. Add runtime state fields to RuntimeWindow (files: `Packages/MoriCore/Sources/MoriCore/Models/RuntimeWindow.swift`)
  - `public var lastExitCode: Int?`
  - `public var isRunning: Bool` (default false)
  - `public var isLongRunning: Bool` (default false)
  - `public var agentState: AgentState` (default .none) — per-window agent state

3.2. Propagate pane state to RuntimeWindow during poll (files: `Sources/Mori/App/WorkspaceManager.swift`)
  - For each RuntimeWindow, aggregate pane states from all its panes:
    - Any pane running → window isRunning=true
    - Any pane long-running → window isLongRunning=true
    - Highest-priority agent state wins
    - Last exit code from most recently exited pane (best-effort)
  - Use enhanced `StatusAggregator.windowBadge(...)` for badge derivation

3.3. Update sidebar views for richer badges (files: `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`, `Packages/MoriUI/Sources/MoriUI/WorktreeRowView.swift`)
  - WindowRowView: show badge-specific icons:
    - .running → "bolt.fill" (green)
    - .longRunning → "clock.fill" (orange)
    - .waiting → "exclamationmark.bubble.fill" (yellow)
    - .error → "xmark.circle.fill" (red)
    - .unread → "circle.fill" (blue, small)
    - .idle → no icon
  - WorktreeRowView: show highest-priority alert badge with color

3.4. Tests for enhanced status aggregation (files: `Packages/MoriCore/Tests/MoriCoreTests/main.swift`)
  - windowBadge with all input combinations (running, longRunning, agentState, unread)
  - Worktree aggregation with running/error/longRunning window badges
  - AlertState mapping for .longRunning badge

### Phase 4: Notifications (5 tasks)

4.1. Create NotificationDebouncer in MoriCore (files: `Packages/MoriCore/Sources/MoriCore/Models/NotificationDebouncer.swift`)
  - Pure logic: tracks previous badge per window ID, detects transitions
  - `func shouldNotify(windowId: String, oldBadge: WindowBadge?, newBadge: WindowBadge, now: Date) -> NotificationEvent?`
  - `NotificationEvent` enum: `agentWaiting`, `commandError`, `longRunningComplete`
  - Debounce: suppress re-fire for same window+event within 30s
  - Testable without UNUserNotificationCenter

4.2. Create NotificationManager (files: `Sources/Mori/App/NotificationManager.swift`)
  - Request notification permission on first use
  - Methods: `notify(_ event: NotificationEvent, windowTitle: String, worktreeName: String)`
  - Uses `UNUserNotificationCenter` to post notifications
  - Notification category with identifier for click handling

4.3. Wire notifications to state transitions (files: `Sources/Mori/App/WorkspaceManager.swift`)
  - Store `previousBadges: [String: WindowBadge]` dictionary
  - After badge update in `coordinatedPoll`, compare with previous
  - Use `NotificationDebouncer.shouldNotify(...)` to decide
  - Call `NotificationManager.notify(...)` for approved transitions

4.4. Dock badge for unread count (files: `Sources/Mori/App/AppDelegate.swift`, `Sources/Mori/App/WorkspaceManager.swift`)
  - Add `updateDockBadge()` method to WorkspaceManager
  - Compute total unread across all projects: `appState.projects.reduce(0) { $0 + $1.aggregateUnreadCount }`
  - Set `NSApp.dockTile.badgeLabel` (nil to clear, string for count)
  - Call at end of `coordinatedPoll` and `clearUnread`

4.5. Notification click handling (files: `Sources/Mori/App/NotificationManager.swift`, `Sources/Mori/App/AppDelegate.swift`)
  - `UNUserNotificationCenterDelegate` on AppDelegate
  - Encode windowId + worktreeId in notification `userInfo`
  - On click → `workspaceManager.selectWindow(windowId)`
  - Bring app to front via `NSApp.activate()`

4.6. Tests for NotificationDebouncer (files: `Packages/MoriCore/Tests/MoriCoreTests/main.swift`)
  - State transition detection (idle→waiting, idle→error, running→idle)
  - Debounce suppression within 30s
  - No notification for non-transition (same badge)
  - Multiple windows tracked independently

### Phase 5: CLI / IPC Interface (8 tasks)

5.1. Create MoriIPC package (files: `Packages/MoriIPC/Package.swift`, `Packages/MoriIPC/Sources/MoriIPC/`)
  - New SPM package, swift-tools-version 6.0, macOS 14+
  - No dependencies on other Mori packages
  - Shared types: `IPCRequest`, `IPCResponse`, `IPCCommand` enum

5.2. Define IPC protocol (files: `Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift`)
  - JSON-encoded newline-delimited messages over Unix socket
  - `IPCCommand` enum (Codable): `projectList`, `worktreeCreate(project: String, branch: String)`, `focus(project: String, worktree: String)`, `send(project: String, worktree: String, window: String, keys: String)`, `newWindow(project: String, worktree: String, name: String?)`, `open(path: String)`
  - `IPCRequest`: wraps `IPCCommand` with optional `requestId: String`
  - `IPCResponse`: `success(payload: Data?)` or `error(message: String)`, with `requestId`

5.3. Create IPCServer using Network.framework (files: `Packages/MoriIPC/Sources/MoriIPC/IPCServer.swift`)
  - `NWListener` with `NWParameters` configured for Unix domain socket
  - Socket path: `~/Library/Application Support/Mori/mori.sock`
  - Accept connections, read newline-delimited JSON, dispatch to handler
  - Handler callback: `@Sendable (IPCRequest) async -> IPCResponse`
  - Clean up socket file on stop
  - Actor-based for state management

5.4. Create IPCClient (files: `Packages/MoriIPC/Sources/MoriIPC/IPCClient.swift`)
  - `NWConnection` to Unix domain socket
  - Send JSON request, read response (with 5s timeout)
  - Synchronous wrapper for CLI use (using semaphore)

5.5. Create `ws` CLI executable (files: `Package.swift`, `Sources/WS/main.swift`)
  - Add `swift-argument-parser` dependency to root Package.swift
  - Add `ws` executable target depending on `MoriIPC` and `ArgumentParser`
  - Subcommands: `ws project list`, `ws worktree create <project> <branch>`, `ws focus <project> <worktree>`, `ws send <project> <worktree> <window> <keys>`, `ws new-window <project> <worktree> [--name <name>]`, `ws open <path>`
  - Maps args to `IPCRequest`, sends via `IPCClient`, prints JSON result

5.6. Embed IPCServer in app (files: `Sources/Mori/App/AppDelegate.swift`, `Sources/Mori/App/IPCHandler.swift`)
  - Start server in `applicationDidFinishLaunching` (after WorkspaceManager init)
  - Stop in `applicationWillTerminate`
  - `IPCHandler`: receives `IPCRequest`, dispatches to `@MainActor WorkspaceManager` methods via `MainActor.run {}`

5.7. Wire all IPC commands (files: `Sources/Mori/App/IPCHandler.swift`)
  - `projectList` → return `appState.projects` as JSON
  - `worktreeCreate` → find project by name, call `createWorktree`
  - `focus` → find project + worktree by name, call `selectProject` + `selectWorktree`
  - `send` → find session + pane, call `tmuxBackend.sendKeys`
  - `newWindow` → find worktree, call `createNewWindow` (or new overload with name)
  - `open` → call `addProject(path:)`

5.8. Tests for IPC protocol serialization (files: `Packages/MoriIPC/Tests/MoriIPCTests/main.swift`)
  - IPCCommand encoding/decoding round-trip for each command variant
  - IPCRequest/IPCResponse serialization
  - Error response handling
  - Newline-delimited message framing

### Phase 6: Automation Hooks (6 tasks)

6.1. Define hook config schema (files: `Packages/MoriCore/Sources/MoriCore/Models/HookConfig.swift`)
  - `HookEvent` enum (Codable): `onWorktreeCreate`, `onWorktreeFocus`, `onWorktreeClose`, `onWindowCreate`, `onWindowFocus`, `onWindowClose`
  - `HookAction` struct (Codable): `shell: String?` (command to run), `tmuxSend: String?` (keys to send to active pane)
  - `HookConfig` struct (Codable): `hooks: [HookEntry]` where `HookEntry` = `event: HookEvent, actions: [HookAction]`

6.2. Create HookRunner (files: `Sources/Mori/App/HookRunner.swift`)
  - Reads `.mori/hooks.json` from project root path
  - Parses JSON into `HookConfig` (graceful failure: log warning, skip)
  - Caches parsed config per project (invalidate on project switch or after 60s)
  - `func fire(event: HookEvent, context: HookContext)` — runs matching actions

6.3. Shell execution for hook actions (files: `Sources/Mori/App/HookRunner.swift`)
  - `shell` actions: run via `Process("/bin/zsh", "-c", command)` with env vars:
    - `MORI_PROJECT`, `MORI_WORKTREE`, `MORI_SESSION`, `MORI_CWD`, `MORI_WINDOW`
  - `tmuxSend` actions: send keys via `TmuxBackend.sendKeys`
  - Non-blocking: spawn in background `Task`, fire-and-forget with 10s timeout
  - `HookContext` struct: projectName, worktreeName, sessionName, windowName, cwd

6.4. Wire hooks into WorkspaceManager lifecycle (files: `Sources/Mori/App/WorkspaceManager.swift`)
  - Fire `onWorktreeCreate` after `createWorktree` succeeds
  - Fire `onWorktreeFocus` after `selectWorktree`
  - Fire `onWorktreeClose` in `removeWorktree` (before cleanup)
  - Fire `onWindowCreate` after `createNewWindow`
  - Fire `onWindowFocus` after `selectWindow`
  - Fire `onWindowClose` in `closeCurrentWindow` (before kill)

6.5. Add HookRunner to WorkspaceManager (files: `Sources/Mori/App/WorkspaceManager.swift`)
  - `let hookRunner: HookRunner` property
  - Initialize with `tmuxBackend` reference (for tmuxSend actions)
  - Build `HookContext` from current state at each fire point

6.6. Tests for HookConfig parsing (files: `Packages/MoriCore/Tests/MoriCoreTests/main.swift`)
  - JSON decoding of valid hooks.json
  - Event enum raw values
  - Action with shell command
  - Action with tmuxSend
  - Invalid/missing JSON handling (empty config)
  - HookEntry matching by event

## Testing Strategy

- **Unit tests**: Each phase adds tests to the relevant package's executable test target
- **Integration**: Manual testing via `mise run dev` after each phase
- **Pattern matching**: Agent detection tested with sample tmux output strings
- **IPC**: Test protocol serialization; manual integration test of `ws` CLI against running app
- **Hooks**: Test config parsing; manual test of shell execution
- **Regression**: Run full `mise run test` after every phase — must stay green

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `capture-pane` adds latency to poll | Medium | Only capture panes in agent-tagged windows, limit to 20 lines |
| Agent pattern matching false positives | Medium | Start conservative (few patterns), expand based on feedback |
| Unix socket permissions on macOS | Low | Socket in Application Support dir, standard user permissions |
| Hooks running arbitrary commands | Medium | Document security implications; no auto-execution without config file |
| Swift 6 strict concurrency with Network.framework | Medium | Network.framework is designed for Swift concurrency; use actor isolation for IPCServer |
| Exit code detection unreliable | Low | Marked as best-effort; only from output pattern matching |

## Assumptions

- Agent detection uses generic pattern matching, not agent-specific parsers
- Unix domain socket via Network.framework, not XPC, for IPC
- Hooks config lives in `.mori/hooks.json` in project root
- Long-running threshold is 30 seconds (hardcoded, not configurable in Phase 3)
- `ws` CLI is a separate executable target using `swift-argument-parser`
- Exit codes are best-effort from output pattern matching (tmux `pane_dead_status` only works for dead panes)
- `DetectedAgentState` in MoriTmux mirrors `AgentState` raw values for easy mapping

## Review Feedback

### Round 1 (Reviewer)
- [x] Fixed: `AgentState` type contradiction — introduced `DetectedAgentState` enum local to MoriTmux with String raw values
- [x] Fixed: Clarified pane-to-window tag lookup in task 2.5 — explicit 7-step flow
- [x] Fixed: Added `.longRunning` case to `WindowBadge` in task 1.2
- [x] Fixed: IPC uses `Network.framework` (`NWListener`/`NWConnection`) for Swift 6 compatibility
- [x] Fixed: Exit code sourcing marked as best-effort from output patterns
- [x] Fixed: Added close hooks (`onWorktreeClose`, `onWindowClose`) to task 6.4
- [x] Fixed: Notification debounce logic extracted to `NotificationDebouncer` in MoriCore for testability
- [x] Fixed: `ws` CLI uses `swift-argument-parser`

## Final Status

(Updated after implementation completes)
