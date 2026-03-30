# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Backend Plumbing — Pane Capture & IPC Commands

**Status:** complete

### What was done

- **1.3** — Created `AgentPaneInfo` model in MoriCore with endpoint, tmuxPaneId, projectName, worktreeName, windowName, agentState, detectedAgent fields
- **1.4** — Added `paneList` and `paneRead(project:worktree:window:lines:)` cases to `IPCCommand` enum
- **1.5** — Implemented `handlePaneList` (iterates all projects→worktrees→windows, builds AgentPaneInfo entries) and `handlePaneRead` (resolves target window, clamps lines 1–200, calls capturePaneOutput) in IPCHandler
- **1.6** — Added `mori pane` subcommand group with `list` and `read` subcommands to MoriCLI
- **1.7** — Added 5 IPC round-trip tests (paneList, paneRead, paneRead max lines, both framing tests) and 2 capturePaneOutput edge-case tests
- **1.1/1.2** — Validated existing capturePaneOutput (already working), target resolution follows same pattern as handleSend

### Files changed

- `Packages/MoriCore/Sources/MoriCore/Models/AgentPaneInfo.swift` (new)
- `Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift` (added 2 enum cases)
- `Sources/Mori/App/IPCHandler.swift` (added handlePaneList + handlePaneRead)
- `Sources/MoriCLI/MoriCLI.swift` (added PaneCmd group with PaneList + PaneRead)
- `Packages/MoriIPC/Tests/MoriIPCTests/main.swift` (5 new tests)
- `Packages/MoriTmux/Tests/MoriTmuxTests/main.swift` (2 new tests)

### Commits

- `4e08111` ✨ feat: add AgentPaneInfo model for pane list response
- `6bc1251` ✨ feat: add paneList and paneRead IPC commands
- `7f9dd06` ✨ feat: handle paneList and paneRead in IPCHandler
- `3ed8bdb` ✨ feat: add mori pane list and mori pane read CLI commands
- `64605a0` ✅ test: add paneList/paneRead IPC round-trip and capturePaneOutput edge-case tests

### Context for next phase

- `AgentPaneInfo` is available from MoriCore for any UI that needs pane metadata
- IPCHandler uses `worktree.resolvedLocation.endpointKey` for the endpoint field (from WorkspaceEndpoint extension)
- `handlePaneRead` clamps lineCount to 1–200 (plan spec: default 50, cap 200)
- The `activePaneId` from RuntimeWindow is preferred; falls back to `rawTmuxWindowId` (same as handleSend)
- All tests pass: MoriIPC (57), MoriTmux (206), MoriCore (361)
- Both `Mori` app and `mori` CLI build successfully

## Phase 2: Hover Peek — Pane Output Popover

**Status:** complete

### What was done

- **2.1** — Created `PaneOutputCache` in app layer: `@MainActor`, keyed by pane ID, 5s TTL, get/set/invalidateAll API
- **2.2** — Created `PanePreviewPopover` SwiftUI view: monospaced text, max 8 lines, `.ultraThickMaterial` background, trailing empty lines trimmed
- **2.3** — Added hover-triggered popover to `WindowRowView`: 300ms debounce via Timer, only shows when badge is present and `onRequestPaneOutput` callback is provided
- **2.4** — Wired `onRequestPaneOutput` callback into `WindowRowView` init (optional parameter, backward-compatible). The callback takes a pane ID and completion handler so the hosting controller can use PaneOutputCache + TmuxBackend to fetch output.

### Files changed

- `Sources/Mori/App/PaneOutputCache.swift` (new)
- `Packages/MoriUI/Sources/MoriUI/PanePreviewPopover.swift` (new)
- `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift` (added hover popover + onRequestPaneOutput)

### Commits

- `c242bf7` ✨ feat: add PaneOutputCache for transient pane output caching
- `e3bea09` ✨ feat: add PanePreviewPopover view for hover peek
- `9da285b` ✨ feat: add hover peek popover to WindowRowView with 300ms debounce

### Context for next phase

- `WindowRowView` now has an optional `onRequestPaneOutput` callback — the hosting controller (HostingControllers.swift) will need to pass this through when wiring the sidebar
- `PaneOutputCache` is available in the app layer for Phase 5 dashboard refresh
- The popover only triggers on badge hover (agent windows), not plain windows
- `PanePreviewPopover` is reusable — Phase 4 AgentWindowRowView can use it directly

## Phase 3: Quick Reply — Inline Input for Waiting Agents

**Status:** complete

### What was done

- **3.1** — Created `QuickReplyField` view: text field + send button, focused on appear, dismisses on submit/escape
- **3.2** — Waiting badge in `WindowRowView` is now a clickable button that toggles reply field
- **3.3** — `onSendKeys` callback wired into `WindowRowView` init (optional, backward-compatible)
- **3.4** — Reply sends `text + "\n"` via the pane ID — connects to existing `IPCCommand.send`

### Commits

- `2a48bef` ✨ feat: add QuickReplyField view for inline agent replies
- `1efe522` ✨ feat: add quick reply field to WindowRowView for waiting agents

## Phase 4: Agents Sidebar Mode

**Status:** complete

### What was done

- **4.1** — Added `.agents` case to `SidebarMode` with backward-compatible decoding
- **4.2** — Created `AgentWindowRowView` with project/worktree context, agent icon, state badge, hover peek, quick reply
- **4.3** — Created `AgentSidebarView` grouping windows by state: Attention, Running, Completed, Idle with collapsible sections
- **4.4** — Added Agents segment to `SidebarContainerView` picker
- **4.5** — Hover peek + quick reply reused from Phase 2–3 in agent rows

### Commits

- `842a78e` ✨ feat: add .agents case to SidebarMode enum
- `f491e11` ✨ feat: add Agents sidebar mode with AgentSidebarView and AgentWindowRowView

## Phase 5: Multi-Pane Dashboard

**Status:** complete

### What was done

- **5.1** — Created `PaneTileView` with header (agent + state) and scrollable monospaced output
- **5.2** — Created `MultiPaneDashboardView` with adaptive grid layout
- **5.3** — Created `AgentDashboardPanel` as floating NSPanel (utility window, non-modal)
- **5.4** — Added “Agent Dashboard” menu item (⌘⇧A) in Window menu
- **5.5** — 5-second periodic refresh, pauses when panel is hidden, uses PaneOutputCache

### Commits

- `26308a5` ✨ feat: add multi-pane agent dashboard panel with ⌘⇧A toggle

## Phase 6: Agent-to-Agent Messaging Protocol

**Status:** complete

### What was done

- **6.1** — Created `AgentMessage` model with envelope format and bidirectional parse
- **6.2** — Added `paneMessage` IPC command
- **6.3** — Implemented `paneMessage` handler with envelope prepend + sendKeys. Refactored target resolution into shared `resolveWindow()` helper
- **6.4** — Added `mori pane message` CLI command
- **6.5** — Added `mori pane id` CLI command (reads MORI_* env vars)
- **6.6** — Created `docs/agent-bridge.md` with full protocol documentation
- **6.7** — Updated CHANGELOG.md and README.md
- **6.8** — Added paneMessage IPC round-trip tests + AgentMessage model tests (envelope, parse, codable)

### Commits

- `5732e34` ✨ feat: add AgentMessage envelope model with format and parse
- `1a387a5` ✨ feat: add paneMessage IPC command
- `a28aad6` ✨ feat: implement paneMessage handler with envelope and target resolution refactor
- `616d233` ✨ feat: add mori pane message and mori pane id CLI commands
- `a3f4817` 📝 docs: update CHANGELOG and README with agent bridge features
- `b9829ae` 📝 docs: add agent bridge documentation
- `d3feb94` ✅ test: add paneMessage IPC round-trip and AgentMessage model tests

## Final Summary

**All 6 phases complete.** Test results:
- MoriIPC: 61 assertions passed
- MoriCore: 372 assertions passed
- MoriTmux: 206 assertions passed
- MoriPersistence: 47 assertions passed
- Release build (Mori app): ✅
- Release build (mori CLI): ✅

## Phase 7: Tasks + Agents Merge

**Status:** complete

### What was done

- **7.1** — `TaskWorktreeRowView` badge now shows agent name alongside icon (e.g. `"⚡ claude"`) via new `agentName` init parameter
- **7.2** — `TaskSidebarView` uses `AgentWindowRowView` inline for windows with `detectedAgent`, passes `onRequestPaneOutput`/`onSendKeys` callbacks through, adds attention summary banner at top ("N agents need attention")
- **7.3** — Removed `SidebarMode.agents` enum case; decoding `"agents"` maps to `.tasks` for backward compat; `SidebarContainerView` dropped to 2-segment picker (Tasks | Workspaces); removed `AgentSidebarView` reference from container
- **7.4** — Added `.agent` case to `CommandPaletteItem` with agent-specific icon/subtitle; `CommandPaletteDataSource` includes agent windows with project/worktree context; supports `agent:` prefix filter
- **7.5** — Added `testSidebarModeBackwardsCompatAgents()` test
- **7.6** — Localization strings added for both en and zh-Hans

### Files changed

- `Packages/MoriCore/Sources/MoriCore/Models/SidebarMode.swift` (removed `.agents`, added backward compat)
- `Packages/MoriCore/Tests/MoriCoreTests/main.swift` (added backward compat test)
- `Packages/MoriUI/Sources/MoriUI/TaskWorktreeRowView.swift` (agent name in badge)
- `Packages/MoriUI/Sources/MoriUI/TaskSidebarView.swift` (enriched agent rows, attention banner, callbacks)
- `Packages/MoriUI/Sources/MoriUI/SidebarContainerView.swift` (2-segment picker, callback passthrough)
- `Sources/Mori/App/CommandPaletteItem.swift` (`.agent` case)
- `Sources/Mori/App/CommandPaletteDataSource.swift` (agent entries, `agent:` filter)
- `Sources/Mori/App/AppDelegate.swift` (handle `.agent` palette selection)
- Localization strings (MoriUI + Mori, en + zh-Hans)

### Commits

- `635170b` ✨ feat: show agent name in TaskWorktreeRowView badge
- `21b7223` ✨ feat: enrich agent windows in TaskSidebarView with attention banner
- `f9b8abf` ♻️ refactor: remove SidebarMode.agents — fold into Tasks view
- `ad89dc3` ✨ feat: add agent entries and agent: filter to command palette
- `0d2e79b` 🌐 i18n: add localization strings for Tasks+Agents merge

### Test results

- MoriCore: 373 assertions passed
- MoriIPC: 61 assertions passed
- MoriTmux: 206 assertions passed
- MoriPersistence: 47 assertions passed
- Mori app build: ✅
- mori CLI build: ✅

### Design decisions

- `AgentSidebarView.swift` is **not deleted** — kept as reference / potential reuse for dashboard panel. No code references it from the main app path.
- Non-agent users see zero added clutter: attention banner only appears when agents need attention, agent badge only shows when `agentState != .none`
- Agent Dashboard panel (⌘⇧A) remains completely separate and unaffected
