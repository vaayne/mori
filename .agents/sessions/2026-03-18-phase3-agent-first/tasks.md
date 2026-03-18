# Phase 3: Agent-first — Task Checklist

## Phase 1: Window Semantic Tags
- [ ] 1.1 — Create `WindowTag` enum in MoriCore
- [ ] 1.2 — Add `tag` to `RuntimeWindow`, add `.longRunning` to `WindowBadge`
- [ ] 1.3 — Add `tag` to `WindowTemplate`, update `TemplateRegistry`
- [ ] 1.4 — Auto-assign tags during template application + name inference
- [ ] 1.5 — Show tags in sidebar WindowRowView and command palette
- [ ] 1.6 — Tests for WindowTag, RuntimeWindow tag, tag inference, WindowBadge.longRunning

## Phase 2: Agent State Detection
- [ ] 2.1 — Add `pane_current_command` and `pane_start_time` to TmuxParser/TmuxPane
- [ ] 2.2 — Create `DetectedAgentState` enum and `PaneState` model in MoriTmux
- [ ] 2.3 — Create `PaneStateDetector` with pattern matching
- [ ] 2.4 — Add `capturePaneOutput` to TmuxBackend/TmuxControlling
- [ ] 2.5 — Integrate detection into coordinated poll (agent-tagged windows only)
- [ ] 2.6 — Update StatusAggregator with richer badge derivation
- [ ] 2.7 — Tests for PaneStateDetector, DetectedAgentState, command filtering

## Phase 3: Worktree Status Enhancements
- [ ] 3.1 — Add `lastExitCode`, `isRunning`, `isLongRunning`, `agentState` to RuntimeWindow
- [ ] 3.2 — Propagate pane state to RuntimeWindow during poll
- [ ] 3.3 — Update sidebar views with badge-specific icons and colors
- [ ] 3.4 — Tests for enhanced status aggregation

## Phase 4: Notifications
- [ ] 4.1 — Create `NotificationDebouncer` in MoriCore (pure transition + debounce logic)
- [ ] 4.2 — Create `NotificationManager` in app target (UNUserNotificationCenter)
- [ ] 4.3 — Wire notifications to state transitions in WorkspaceManager
- [ ] 4.4 — Dock badge for aggregate unread count
- [ ] 4.5 — Notification click handling (focus window on click)
- [ ] 4.6 — Tests for NotificationDebouncer

## Phase 5: CLI / IPC Interface
- [ ] 5.1 — Create MoriIPC SPM package
- [ ] 5.2 — Define IPC protocol (IPCCommand, IPCRequest, IPCResponse)
- [ ] 5.3 — Create IPCServer with Network.framework (NWListener, Unix socket)
- [ ] 5.4 — Create IPCClient (NWConnection, Unix socket)
- [ ] 5.5 — Create `ws` CLI executable with swift-argument-parser
- [ ] 5.6 — Embed IPCServer in app (start/stop in AppDelegate)
- [ ] 5.7 — Wire all IPC commands in IPCHandler
- [ ] 5.8 — Tests for IPC protocol serialization

## Phase 6: Automation Hooks
- [ ] 6.1 — Define `HookEvent`, `HookAction`, `HookConfig` in MoriCore
- [ ] 6.2 — Create `HookRunner` (read/parse .mori/hooks.json, caching)
- [ ] 6.3 — Shell execution and tmuxSend for hook actions
- [ ] 6.4 — Wire hooks into WorkspaceManager lifecycle (create/focus/close)
- [ ] 6.5 — Add HookRunner to WorkspaceManager initialization
- [ ] 6.6 — Tests for HookConfig JSON parsing
