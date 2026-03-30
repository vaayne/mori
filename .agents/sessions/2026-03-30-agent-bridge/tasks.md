# Tasks: Agent Bridge

## Phase 1: Backend Plumbing — Pane Capture & IPC Commands

- [ ] 1.1 — Validate existing `capturePaneOutput` in TmuxBackend, add edge-case tests (empty pane, large scrollback) (`Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift`, `Packages/MoriTmux/Tests/`)
- [ ] 1.2 — Define target resolution strategy: `<project>/<worktree>/<window>` → `activePaneId`. Document multi-pane and SSH behavior (`Sources/Mori/App/IPCHandler.swift`)
- [ ] 1.3 — Add `AgentPaneInfo` model with endpoint, canonical paneId, project/worktree/window context (`Packages/MoriCore/Sources/MoriCore/Models/AgentPaneInfo.swift`)
- [ ] 1.4 — Add `paneList` and `paneRead` IPC commands (`Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift`)
- [ ] 1.5 — Handle `paneList` and `paneRead` in IPCHandler (`Sources/Mori/App/IPCHandler.swift`)
- [ ] 1.6 — Add `mori pane list` and `mori pane read` CLI commands (`Sources/MoriCLI/MoriCLI.swift`)
- [ ] 1.7 — Write tests for capturePaneOutput edge cases and IPC round-trip (`Packages/MoriTmux/Tests/`, `Packages/MoriIPC/Tests/`)

## Phase 2: Hover Peek — Pane Output Popover

- [ ] 2.1 — Create app-layer `PaneOutputCache` (keyed by pane ID, 5s TTL) (`Sources/Mori/App/PaneOutputCache.swift`)
- [ ] 2.2 — Create `PanePreviewPopover` view (`Packages/MoriUI/Sources/MoriUI/PanePreviewPopover.swift`)
- [ ] 2.3 — Add popover trigger to `WindowRowView` on badge hover with 300ms debounce (`Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`)
- [ ] 2.4 — Wire `onRequestPaneOutput` callback through sidebar chain

## Phase 3: Quick Reply — Inline Input for Waiting Agents

- [ ] 3.1 — Create `QuickReplyField` view (`Packages/MoriUI/Sources/MoriUI/QuickReplyField.swift`)
- [ ] 3.2 — Add reply toggle to `WindowRowView` on waiting badge click (`Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`)
- [ ] 3.3 — Wire `onSendKeys` callback through sidebar chain
- [ ] 3.4 — Connect to existing `IPCCommand.send` for key delivery

## Phase 4: Agents Sidebar Mode

- [ ] 4.1 — Add `.agents` case to `SidebarMode` enum with backward-compatible decoding (`Packages/MoriCore/Sources/MoriCore/Models/SidebarMode.swift`)
- [ ] 4.2 — Create `AgentWindowRowView` (`Packages/MoriUI/Sources/MoriUI/AgentWindowRowView.swift`)
- [ ] 4.3 — Create `AgentSidebarView` (`Packages/MoriUI/Sources/MoriUI/AgentSidebarView.swift`)
- [ ] 4.4 — Add Agents segment to `SidebarContainerView` picker (`Packages/MoriUI/Sources/MoriUI/SidebarContainerView.swift`)
- [ ] 4.5 — Include hover peek + quick reply in agent rows (reuse Phase 2–3)
- [ ] 4.6 — Add localization strings (en + zh-Hans) for MoriUI + Mori app targets

## Phase 5: Multi-Pane Dashboard

- [ ] 5.1 — Create `PaneTileView` (`Packages/MoriUI/Sources/MoriUI/PaneTileView.swift`)
- [ ] 5.2 — Create `MultiPaneDashboardView` (`Packages/MoriUI/Sources/MoriUI/MultiPaneDashboardView.swift`)
- [ ] 5.3 — Create `AgentDashboardPanel` as floating NSPanel (`Sources/Mori/App/AgentDashboardPanel.swift`)
- [ ] 5.4 — Add "Agent Dashboard" menu item (⌘⇧A) to existing "Window" menu in `AppDelegate.setupMainMenu()` (`Sources/Mori/App/AppDelegate.swift`)
- [ ] 5.5 — Periodic refresh for visible tiles (5s interval, paused when hidden), using PaneOutputCache (`Sources/Mori/App/AgentDashboardPanel.swift`)
- [ ] 5.6 — Add localization strings

## Phase 6: Agent-to-Agent Messaging Protocol

- [ ] 6.1 — Define `AgentMessage` envelope model (`Packages/MoriCore/Sources/MoriCore/Models/AgentMessage.swift`)
- [ ] 6.2 — Add `paneMessage(project, worktree, window, text)` IPC command (`Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift`)
- [ ] 6.3 — Implement `paneMessage` handler in IPCHandler — resolve target, prepend envelope, sendKeys + Enter (`Sources/Mori/App/IPCHandler.swift`)
- [ ] 6.4 — Add `mori pane message` CLI command (`Sources/MoriCLI/MoriCLI.swift`)
- [ ] 6.5 — Add `mori pane id` CLI command (`Sources/MoriCLI/MoriCLI.swift`)
- [ ] 6.6 — Document messaging protocol + agent skill (`docs/agent-bridge.md`)
- [ ] 6.7 — Update `CHANGELOG.md` and `README.md` (`CHANGELOG.md`, `README.md`)
- [ ] 6.8 — Write integration test for message exchange (`Packages/MoriIPC/Tests/`)
