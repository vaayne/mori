# Plan: Agent Bridge — Cross-Pane Monitoring, Communication & Dashboard

## Overview

Add smux-inspired cross-pane agent communication and monitoring to Mori. Agents running in different tmux panes/worktrees can discover, read, and message each other via the `mori` CLI. The UI surfaces agent activity progressively: badges (existing), hover peek, quick reply, Agents sidebar mode, and a multi-pane dashboard panel.

### Goals

- Let users monitor agent output without switching context (hover peek)
- Let users reply to waiting agents inline (quick reply)
- Provide an Agents sidebar mode that groups all agent windows by state
- Provide a multi-pane dashboard showing live output from multiple agent panes
- Enable agent-to-agent communication via `mori` CLI (read, message, pane list)
- Expose pane output capture as a first-class capability in MoriTmux and MoriIPC

### Success Criteria

- [ ] `mori pane list` returns all panes with project/worktree/window/agent/state info
- [ ] `mori pane read <project> <worktree> <window> [--lines N]` captures pane output
- [ ] `mori pane message <project> <worktree> <window> <text>` sends text with sender metadata
- [ ] Hover any window row with agent badge → popover shows last 5 lines
- [ ] Click waiting badge → inline reply field → sends keys to pane
- [ ] `[Tasks | Workspaces | Agents]` third sidebar segment works
- [ ] Agents sidebar groups windows by state: attention, running, completed, idle
- [ ] Multi-pane dashboard panel shows live output from agent panes
- [ ] Two agents in different worktrees can exchange messages via `mori` CLI
- [ ] All new strings localized (en + zh-Hans)
- [ ] No disruption to existing Workspaces/Tasks sidebar modes
- [ ] Tests pass: `mise run test`

### Out of Scope

- Hook-based agent chaining (on-complete triggers) — future
- Agent workflow YAML config files — future
- Read guard enforcement in CLI — future
- Changes to tmux keybindings or config

## Technical Approach

Layer new capabilities onto existing architecture without new packages or major refactors.

### Components

- **MoriTmux / TmuxBackend**: Validate existing `capturePaneOutput()` implementation (already working at line ~273), add edge-case tests
- **MoriIPC / IPCProtocol**: Add `paneList`, `paneRead`, `paneMessage` commands
- **MoriCLI**: Add `mori pane` subcommand group (list, read, message)
- **IPCHandler**: Handle new commands by coordinating WorkspaceManager + TmuxBackend
- **MoriCore / SidebarMode**: Add `.agents` case
- **MoriCore / AgentPaneInfo**: New lightweight model for pane list response
- **MoriUI / AgentSidebarView**: New sidebar view (same pattern as TaskSidebarView)
- **MoriUI / AgentWindowRowView**: Row view for agent sidebar with output preview
- **MoriUI / PanePreviewPopover**: Hover popover showing last N lines of pane output
- **MoriUI / QuickReplyField**: Inline text field for replying to waiting agents
- **MoriUI / MultiPaneDashboardView**: Panel showing live output from multiple panes
- **App / AgentDashboardController**: AppKit controller hosting the dashboard panel

## Implementation Phases

### Phase 1: Backend Plumbing — Pane Capture & IPC Commands

The foundation everything else depends on.

1. Validate existing `capturePaneOutput(paneId:lineCount:)` in `TmuxBackend` — already implemented, add tests and verify edge cases (empty pane, large scrollback clamping) (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift`, `Packages/MoriTmux/Tests/`)
2. Define target resolution strategy: CLI accepts `<project> <worktree> <window>` and resolves to the active pane in that window. For multi-pane windows, target the active pane (`activePaneId` on `RuntimeWindow`). Error if window not found. Remote/SSH worktrees use the same resolution via their `TmuxBackend` instance. (files: `Sources/Mori/App/IPCHandler.swift`)
3. Add `AgentPaneInfo` model for structured pane list response — includes `endpoint` (local/ssh), canonical `tmuxPaneId`, project/worktree/window context (files: `Packages/MoriCore/Sources/MoriCore/Models/AgentPaneInfo.swift`)
4. Add IPC commands: `paneList`, `paneRead(project, worktree, window, lines)` (files: `Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift`)
5. Handle `paneList` and `paneRead` in `IPCHandler` using target resolution from step 2 (files: `Sources/Mori/App/IPCHandler.swift`)
6. Add `mori pane list` and `mori pane read` CLI commands (files: `Sources/MoriCLI/MoriCLI.swift`)
7. Write tests for `capturePaneOutput` edge cases and IPC round-trip for paneList/paneRead (files: `Packages/MoriTmux/Tests/`, `Packages/MoriIPC/Tests/`)

### Phase 2: Hover Peek — Pane Output Popover

Lightest UI touch — adds value to existing window rows.

1. Add transient `PaneOutputCache` (app-layer, NOT in MoriCore) — a simple `[String: (output: String, fetchedAt: Date)]` dictionary keyed by tmux pane ID, with 5-second TTL invalidation. Lives in the hosting controller or WorkspaceManager scope. (files: `Sources/Mori/App/PaneOutputCache.swift`)
2. Create `PanePreviewPopover` SwiftUI view — monospaced text, max 8 lines, dark background (files: `Packages/MoriUI/Sources/MoriUI/PanePreviewPopover.swift`)
3. Add popover trigger to `WindowRowView` on badge hover (files: `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`)
4. Wire `onRequestPaneOutput` callback through `SidebarContainerView` → `WorktreeSidebarView` → `WindowRowView` (files: sidebar views)

### Phase 3: Quick Reply — Inline Input for Waiting Agents

Click-to-reply on waiting badges.

1. Create `QuickReplyField` SwiftUI view — text field + send button, dismisses on submit (files: `Packages/MoriUI/Sources/MoriUI/QuickReplyField.swift`)
2. Add reply state to `WindowRowView` — toggle on badge click when state is `waiting` (files: `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`)
3. Wire `onSendKeys` callback through sidebar chain (files: sidebar views)
4. Connect to existing `IPCCommand.send` for key delivery

### Phase 4: Agents Sidebar Mode

Third sidebar segment for agent-focused workflow.

1. Add `.agents` case to `SidebarMode` enum (files: `Packages/MoriCore/Sources/MoriCore/Models/SidebarMode.swift`)
2. Create `AgentWindowRowView` — shows project/worktree context, agent name, state, last output line (files: `Packages/MoriUI/Sources/MoriUI/AgentWindowRowView.swift`)
3. Create `AgentSidebarView` — groups windows by agent state (attention → running → completed → idle), collapsible sections (files: `Packages/MoriUI/Sources/MoriUI/AgentSidebarView.swift`)
4. Add Agents segment to `SidebarContainerView` picker + conditional render (files: `Packages/MoriUI/Sources/MoriUI/SidebarContainerView.swift`)
5. Include hover peek + quick reply in agent rows (reuse from Phase 2–3)
6. Add localization strings for "Agents", status group headers (files: `Sources/Mori/Resources/*/Localizable.strings`, `Packages/MoriUI/Sources/MoriUI/Resources/*/Localizable.strings`)

### Phase 5: Multi-Pane Dashboard

Live monitoring panel as a floating `NSPanel` — independent of the main window, toggleable.

1. Create `PaneTileView` — single pane tile with header (agent name, state badge) + scrollable monospaced output (files: `Packages/MoriUI/Sources/MoriUI/PaneTileView.swift`)
2. Create `MultiPaneDashboardView` — grid/flow layout of `PaneTileView` tiles, auto-populated from active agent windows (files: `Packages/MoriUI/Sources/MoriUI/MultiPaneDashboardView.swift`)
3. Create `AgentDashboardPanel` — floating `NSPanel` (non-modal, `.utilityWindow` style level) hosting the dashboard via `NSHostingView`. Remembers position/size. (files: `Sources/Mori/App/AgentDashboardPanel.swift`)
4. Add "Agent Dashboard" menu item (⌘⇧A) to the existing "Window" menu in `AppDelegate.setupMainMenu()` (files: `Sources/Mori/App/AppDelegate.swift`). `MainWindowController` owns the panel toggle state. (files: `Sources/Mori/App/MainWindowController.swift`)
5. Periodic refresh: poll `capturePaneOutput` for visible tiles every 5 seconds, pause when panel is hidden/occluded. Uses `PaneOutputCache` from Phase 2. (files: `Sources/Mori/App/AgentDashboardPanel.swift`)
6. Add localization strings (files: Localizable.strings)

### Phase 6: Agent-to-Agent Messaging Protocol

The transport layer for agents to talk to each other. Consolidates all `paneMessage` work (IPC command + handler + CLI) that was split across Phase 1 and Phase 6 in the original plan.

1. Define message envelope format — `[mori-bridge from:<project>/<worktree>/<window> pane:<id>] <text>` (files: `Packages/MoriCore/Sources/MoriCore/Models/AgentMessage.swift`)
2. Add `paneMessage(project, worktree, window, text)` IPC command (files: `Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift`)
3. Implement `paneMessage` handler in `IPCHandler` — resolves target via Phase 1 target resolution, prepends envelope, calls `sendKeys` + `Enter` (files: `Sources/Mori/App/IPCHandler.swift`)
4. Add `mori pane message` CLI command (files: `Sources/MoriCLI/MoriCLI.swift`)
5. Add `mori pane id` — print current pane's identity for self-labeling (files: `Sources/MoriCLI/MoriCLI.swift`)
6. Document the messaging protocol and agent skill (files: `docs/agent-bridge.md`)
7. Update `CHANGELOG.md` under `[Unreleased]` and `README.md` feature list (files: `CHANGELOG.md`, `README.md`)
8. Write integration test: two mock panes exchange messages (files: `Packages/MoriIPC/Tests/`)

## Future Enhancements (Not in Current Scope)

These are planned for follow-up work after the core agent bridge ships:

### F1: Hook-Based Agent Chaining
- On agent state transition (completed/error), trigger configurable actions
- Config: `mori hook add on-complete <source> <command>`
- Example: `mori hook add on-complete mori/main/claude "mori pane message mori/main/codex 'Review claude's changes'"`
- Requires: state transition events from TmuxBackend polling

### F2: Agent Workflow YAML
- Declarative multi-step agent pipelines
- Config file: `.mori/agent-workflows.yml`
- Example:
  ```yaml
  pipelines:
    code-review:
      - agent: claude
        task: "Write login handler"
      - agent: codex
        trigger: on-complete
        task: "Review changes"
  ```
- Requires: F1 (hook system)

### F3: Read Guard Enforcement
- CLI tracks read-before-write state per pane (smux pattern)
- `mori pane message` requires prior `mori pane read` to the same target
- Prevents agents from blindly typing into stale panes
- Temp file markers at `~/Library/Application Support/Mori/read-guards/`

### F4: Pane Labeling & Custom Names
- `mori pane name <target> <label>` — set custom label on a pane
- Labels stored as tmux pane options (`@mori-label`)
- Labels resolve in all IPC commands (alternative to project/worktree/window addressing)
- UI: editable label field in sidebar rows

### F5: Agent Notifications
- macOS native notifications when agent state changes in background
- Notification categories: waiting-for-input, error, completed
- Click notification → focus that worktree + window
- Requires: NSUserNotificationCenter or UNUserNotificationCenter

### F6: Pane Output Search
- Search across all pane output (grep-like)
- `mori pane search <query>` — returns matching lines with pane context
- UI: search field in Agent sidebar / dashboard

### F7: Agent Session History
- Persist captured pane output snapshots
- Timeline view of agent interactions per worktree
- Useful for reviewing what agents did after the fact
- Storage: `~/Library/Application Support/Mori/agent-history/`

### F8: Split Terminal View
- Show two panes side-by-side in the terminal area
- One pane for your work, one for monitoring an agent
- Reuses existing GhosttyAdapter with multiple surfaces

### F9: Agent Templates
- Pre-configured agent launch templates
- Example: "Launch Claude Code in new window with review prompt"
- Integrates with existing SessionTemplate system

### F10: Cross-Machine Agent Bridge
- Extend messaging to SSH-connected remote projects
- `mori pane message api@remote/main/claude "review auth"` 
- Requires: SSH tunnel for IPC or remote MoriCLI relay

## Testing Strategy

- Unit tests for `capturePaneOutput` edge cases: empty pane, large lineCount clamping (MoriTmux)
- Unit tests for new IPC command encode/decode (MoriIPC)
- Unit tests for `AgentPaneInfo` model codable round-trip (MoriCore)
- Unit tests for `AgentMessage` envelope formatting + parsing (MoriCore)
- Integration test for IPC round-trip: paneList, paneRead
- Integration test for paneMessage: envelope prepended, sendKeys called
- Manual test: hover peek shows output, quick reply sends keys
- Manual test: Agents sidebar displays correct groupings
- Manual test: Dashboard panel opens/closes, shows live output, refreshes
- Manual test: Two CLI agents exchange messages via `mori pane message`
- `mise run test` passes for all packages
- `swift build -c release --product Mori` succeeds (strict concurrency)
- `swift build --build-path .build-cli -c release --product mori` succeeds

## Docs & Localization Checklist

- [ ] `CHANGELOG.md` — entry under `[Unreleased]` for each user-visible change
- [ ] `README.md` — update features section with agent bridge capabilities
- [ ] `docs/agent-bridge.md` — new doc: messaging protocol, CLI usage, agent skill
- [ ] Localization: all new UI strings in `en.lproj/Localizable.strings` + `zh-Hans.lproj/Localizable.strings` for Mori app, MoriUI, and MoriCLI targets

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `capturePaneOutput` performance on large scrollback | Medium | Limit default to 50 lines, cap at 200 |
| Dashboard polling overhead with many panes | Medium | Only poll visible tiles, 5s interval, pause when hidden |
| Popover flicker on fast mouse movement | Low | Debounce hover with 300ms delay |
| Message envelope parsing by agents | Medium | Use simple, grep-friendly format; document in agent skill |
| SidebarMode enum change breaks persistence | Low | Add backward-compatible decoding (already done for prior migrations) |
| Swift 6 Sendable requirements for new models | Medium | All new models are structs with Sendable conformance |

## Open Questions

*None — all resolved into assumptions:*
- **Dashboard placement**: Floating `NSPanel` (`.utilityWindow` style level, non-modal) — can be toggled independently of main window
- **Pane output refresh for hover**: On-demand capture when popover appears, cached in app-layer `PaneOutputCache` with 5s TTL (not in MoriCore models)
- **Message format**: `[mori-bridge from:<project>/<worktree>/<window> pane:<id>]` prefix, similar to smux but with semantic addressing
- **Agent sidebar filtering**: Show all windows with `detectedAgent != nil` OR `agentState != .none`
- **Target resolution**: CLI `<project> <worktree> <window>` resolves to `activePaneId` of matched `RuntimeWindow`. Multi-pane windows target the active pane. Error if window not found. Remote/SSH worktrees use their own `TmuxBackend` instance.
- **Captured output state**: Transient app-layer cache (`PaneOutputCache`), NOT stored in `RuntimeWindow` or any MoriCore model. Avoids violating the architecture layering (MoriCore = models only, no I/O state).
- **Menu construction**: Dashboard menu item lives in `AppDelegate.setupMainMenu()` under the existing "Window" menu (merged window/view menu), not in `MainWindowController`

## Review Feedback

*(Updated during plan review rounds)*

## Final Status

*(Updated after implementation completes)*
