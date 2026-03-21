# Tasks: Task Mode Sidebar (Issue #14)

## Phase 1: Data Model & Persistence

- [x] 1.1 — Create `WorkflowStatus` enum with 5 cases + display helpers (`Packages/MoriCore/Sources/MoriCore/Models/WorkflowStatus.swift`)
- [x] 1.2 — Add `workflowStatus` field to `Worktree` model with backwards-compatible decoding (`Packages/MoriCore/Sources/MoriCore/Models/Worktree.swift`)
- [x] 1.3 — Update `SidebarMode` to `workspaces | tasks` with backwards-compatible decoding (`Packages/MoriCore/Sources/MoriCore/Models/SidebarMode.swift`, `UIState.swift`)
- [x] 1.4 — Add tests for WorkflowStatus, Worktree backwards compat, SidebarMode backwards compat (`Packages/MoriCore/Tests/MoriCoreTests/main.swift`)
- [x] 1.5 — Update existing SidebarMode tests in MoriCore and MoriPersistence (`Packages/MoriCore/Tests/MoriCoreTests/main.swift`, `Packages/MoriPersistence/Tests/MoriPersistenceTests/main.swift`)

## Phase 2: Task Mode Sidebar View

- [x] 2.1 — Create `TaskWorktreeRowView` (`Packages/MoriUI/Sources/MoriUI/TaskWorktreeRowView.swift`)
- [x] 2.2 — Create `WorkflowStatusMenu` reusable submenu (`Packages/MoriUI/Sources/MoriUI/WorkflowStatusMenu.swift`)
- [x] 2.3 — Create `TaskSidebarView` with status grouping, nested windows, lastActiveAt sorting, cancelled toggle (`Packages/MoriUI/Sources/MoriUI/TaskSidebarView.swift`)
- [x] 2.4 — Create `SidebarContainerView` with toggle (`Packages/MoriUI/Sources/MoriUI/SidebarContainerView.swift`)
- [x] 2.5 — Add "Set Status" context menu + `onSetWorkflowStatus` callback to both sidebar views (`WorktreeSidebarView.swift`, `TaskSidebarView.swift`)

## Phase 3: App Integration & WorkspaceManager

- [x] 3.1 — Add `setWorkflowStatus()` method to WorkspaceManager (`Sources/Mori/App/WorkspaceManager.swift`)
- [x] 3.2 — Update `selectWorktree()` to sync `selectedProjectId` from worktree's `projectId` (`Sources/Mori/App/WorkspaceManager.swift`)
- [x] 3.3 — Wire `SidebarContainerView` into `SidebarContentView` in HostingControllers (`Sources/Mori/App/HostingControllers.swift`)
- [x] 3.4 — Wire `onSetWorkflowStatus` callback (`Sources/Mori/App/HostingControllers.swift`)
- [x] 3.5 — Add auto-transition logic in `coordinatedPoll()` (`Sources/Mori/App/WorkspaceManager.swift`)

## Phase 4: Command Palette & IPC & CLI

- [x] 4.1 — Add `setWorkflowStatus` to `IPCCommand` (`Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift`)
- [x] 4.2 — Add `handleSetWorkflowStatus` in IPCHandler (`Sources/Mori/App/IPCHandler.swift`)
- [x] 4.3 — Add `StatusCmd` CLI subcommand: `mori status <project> <worktree> <status>` (`Sources/MoriCLI/MoriCLI.swift`)
- [x] 4.4 — Add "Set Worktree Status" to CommandPaletteDataSource (`Sources/Mori/App/CommandPaletteDataSource.swift`)
- [x] 4.5 — Handle new palette actions in AppDelegate (`Sources/Mori/App/AppDelegate.swift`)
- [x] 4.6 — Add IPC tests (`Packages/MoriIPC/Tests/MoriIPCTests/main.swift`)

## Phase 5: i18n & Polish

- [x] 5.1 — Add localized strings (en + zh-Hans) to all 3 `Localizable.strings` files
- [x] 5.2 — Run full test suite, fix regressions
- [x] 5.3 — Update CHANGELOG.md
