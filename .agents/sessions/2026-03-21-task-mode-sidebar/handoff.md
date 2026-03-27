# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Data Model & Persistence — COMPLETE

**Commits:** 4 (f0d457b, 0e5637a, 069ce9a, 0509fe4)

**What was done:**
- Created `WorkflowStatus` enum with 5 cases (`todo`, `inProgress`, `needsReview`, `done`, `cancelled`), display helpers (`displayName`, `iconName`, `sortOrder`), conforming to `String, Codable, Sendable, CaseIterable`
- Added `workflowStatus: WorkflowStatus` field to `Worktree` model with default `.todo` and backwards-compatible decoding via `decodeIfPresent`
- Replaced `SidebarMode` enum cases from `worktrees | search` to `workspaces | tasks` with custom `init(from:)` that maps old values (`"worktrees"` and `"search"`) to `.workspaces`
- Updated `UIState` default from `.worktrees` to `.workspaces`
- Added 12 new test functions covering WorkflowStatus round-trip, sort order, display helpers, Worktree backwards compat (with and without workflowStatus in JSON), and SidebarMode backwards compat
- Updated 5 existing test assertions in MoriCore and MoriPersistence to use new enum values

**Test results:** 346 MoriCore assertions passing, 47 MoriPersistence assertions passing. Zero build warnings.

**Files modified:**
- `Packages/MoriCore/Sources/MoriCore/Models/WorkflowStatus.swift` (new)
- `Packages/MoriCore/Sources/MoriCore/Models/Worktree.swift`
- `Packages/MoriCore/Sources/MoriCore/Models/SidebarMode.swift`
- `Packages/MoriCore/Sources/MoriCore/Models/UIState.swift`
- `Packages/MoriCore/Tests/MoriCoreTests/main.swift`
- `Packages/MoriPersistence/Tests/MoriPersistenceTests/main.swift`

**Notes for Phase 2:**
- `SidebarMode.workspaces` and `.tasks` are ready for use in UI toggle
- `Worktree.workflowStatus` is ready for grouping in `TaskSidebarView`
- `WorkflowStatus.sortOrder` defines group ordering: inProgress(0) > needsReview(1) > todo(2) > done(3) > cancelled(4)

## Phase 2: Task Mode Sidebar View — COMPLETE

**Commits:** 5 (8f2fc90, 02e8f68, 9fe4d97, d79d890, 9e6ae59)

**What was done:**
- Created `TaskWorktreeRowView` — shows branch name + project shortName badge + git status indicators + alert badge, following `WorktreeRowView` patterns
- Created `WorkflowStatusMenu` — reusable submenu with all 5 WorkflowStatus options, checkmark on current status
- Created `TaskSidebarView` — groups worktrees by WorkflowStatus (inProgress → needsReview → todo → done), cancelled hidden by default with toggle, done collapsed by default, empty groups hidden, group headers with count, sorted by lastActiveAt descending, windows nested under worktrees, unavailable worktrees filtered out, same footer as WorktreeSidebarView
- Created `SidebarContainerView` — segmented control (Tasks | Workspaces) at top, conditionally renders TaskSidebarView or WorktreeSidebarView, passes through all callbacks
- Added `onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)?` callback to `WorktreeSidebarView`
- Added "Set Status" context menu (via `WorkflowStatusMenu`) to worktree rows in both `WorktreeSidebarView` and `TaskSidebarView`

**Build result:** Zero errors, zero warnings (only existing ghostty linker warnings).

**Files created:**
- `Packages/MoriUI/Sources/MoriUI/TaskWorktreeRowView.swift`
- `Packages/MoriUI/Sources/MoriUI/WorkflowStatusMenu.swift`
- `Packages/MoriUI/Sources/MoriUI/TaskSidebarView.swift`
- `Packages/MoriUI/Sources/MoriUI/SidebarContainerView.swift`

**Files modified:**
- `Packages/MoriUI/Sources/MoriUI/WorktreeSidebarView.swift` (added `onSetWorkflowStatus` callback + "Set Status" context menu)

**Notes for Phase 3:**
- `SidebarContainerView` is ready to replace `WorktreeSidebarView` in `HostingControllers.swift`
- It takes `sidebarMode: SidebarMode` and `onToggleSidebarMode: (SidebarMode) -> Void` for the toggle
- `onSetWorkflowStatus` callback needs wiring to `WorkspaceManager.setWorkflowStatus()`
- All views are pure SwiftUI (data + callbacks), no AppState dependency
- `WorktreeSidebarView` now accepts optional `onSetWorkflowStatus` — existing callers unaffected (defaults to nil)

## Phase 3: App Integration & WorkspaceManager — COMPLETE

**Commits:** 2 (9583119, c6f81c6)

**What was done:**
- Added `setWorkflowStatus(worktreeId:status:)` to WorkspaceManager — updates AppState and persists via `worktreeRepo.save()` (3.1)
- Added `setSidebarMode(_:)` to WorkspaceManager — updates `appState.uiState.sidebarMode` and persists via `saveUIState()` (supports 3.3 toggle)
- Updated `selectWorktree()` to sync `selectedProjectId` when the worktree belongs to a different project — enables cross-project selection in task mode (3.2)
- Replaced `WorktreeSidebarView` with `SidebarContainerView` in `SidebarContentView` — sidebar now shows Tasks/Workspaces segmented toggle, reads mode from `appState.uiState.sidebarMode` (3.3)
- Added `onToggleSidebarMode` and `onSetWorkflowStatus` callbacks through the hosting chain: `SidebarHostingController` → `SidebarContentView` → `SidebarContainerView` (3.3/3.4)
- Wired callbacks in `AppDelegate` to `WorkspaceManager.setSidebarMode()` and `WorkspaceManager.setWorkflowStatus()` (3.4)
- Added `autoTransitionTodoWorktrees()` called in `coordinatedPoll()` after git status update — transitions `.todo` worktrees to `.inProgress` when `modifiedCount > 0 || stagedCount > 0 || aheadCount > 0 || agentState != .none` (3.5)

**Build result:** Zero errors, zero warnings (only existing ghostty linker warnings).

**Files modified:**
- `Sources/Mori/App/WorkspaceManager.swift` (added setSidebarMode, setWorkflowStatus, autoTransitionTodoWorktrees, selectWorktree projectId sync)
- `Sources/Mori/App/HostingControllers.swift` (replaced WorktreeSidebarView with SidebarContainerView, added new callback params)
- `Sources/Mori/App/AppDelegate.swift` (wired onToggleSidebarMode and onSetWorkflowStatus callbacks)

**Notes for Phase 4:**
- `WorkspaceManager.setWorkflowStatus()` is ready to be called from IPCHandler and CommandPaletteDataSource
- `setSidebarMode()` is wired and persists — sidebar toggle is fully functional
- Auto-transition fires during each 5s poll tick, lightweight check only on `.todo` worktrees
- Cross-project selection in task mode works: selecting a worktree from a different project auto-syncs `selectedProjectId`

## Phase 4: Command Palette & IPC & CLI — COMPLETE

**Commits:** 7 (75e656c, 11d2036, 745bd20, ab86426, 30708e4, 4919176, 8a386b6)

**What was done:**
- Added `setWorkflowStatus(project:worktree:status:)` case to `IPCCommand` enum in MoriIPC (4.1)
- Added `handleSetWorkflowStatus` in `IPCHandler` — resolves project + worktree by case-insensitive name matching, validates status string against `WorkflowStatus.allCases`, returns descriptive error for invalid values (4.2)
- Added `StatusCmd` CLI subcommand: `mori status <project> <worktree> <status>` with localized help text and discussion showing valid status values (4.3)
- Added "Set Worktree Status" actions to `CommandPaletteDataSource` — one `.action` per `WorkflowStatus` case, only shown when a worktree is selected, with subtitle indicating current vs. target status (4.4)
- Handled `action.status-<rawValue>` pattern in `AppDelegate.handlePaletteAction()` — parses raw value, resolves via `WorkflowStatus(rawValue:)`, calls `WorkspaceManager.setWorkflowStatus()` (4.5)
- Added 3 IPC test functions covering: single round-trip, all 5 status values round-trip, and framing encode/decode (4.6)

**Build result:** Zero errors, zero warnings (only existing ghostty linker warnings).

**Test results:** 48 MoriIPC assertions passing (up from 39).

**Files modified:**
- `Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift` (added setWorkflowStatus case)
- `Sources/Mori/App/IPCHandler.swift` (added handleSetWorkflowStatus method + dispatch)
- `Sources/MoriCLI/MoriCLI.swift` (added StatusCmd subcommand)
- `Sources/Mori/App/CommandPaletteDataSource.swift` (added status action items)
- `Sources/Mori/App/AppDelegate.swift` (added status action handling in palette)
- `Packages/MoriIPC/Tests/MoriIPCTests/main.swift` (added 3 test functions)

**Notes for Phase 5:**
- All external interfaces (IPC, CLI, command palette) are wired and functional
- New user-facing strings in MoriCLI and app target need localization entries (en + zh-Hans)
- CLI help text uses `.localized()` already — just needs Localizable.strings entries
- Command palette strings use `.localized()` — needs entries in app Localizable.strings

## Phase 5: i18n & Polish — COMPLETE

**Commits:** 2 (cd091a2, 80b1b3d)

**What was done:**
- Added `.localized()` calls for computed strings in MoriUI views that were using raw string literals:
  - `SidebarContainerView`: "Tasks" and "Workspaces" picker labels
  - `WorkflowStatusMenu`: "Set Status" menu title, WorkflowStatus display names via `String.LocalizationValue(stringLiteral:)`
  - `TaskSidebarView`: Status group headers (display names), "Show Cancelled"/"Hide Cancelled" toggle
  - `TaskWorktreeRowView`: Relative time strings ("just now", "%dm ago", etc.)
- Added localized strings (en + zh-Hans) to all 6 Localizable.strings files:
  - MoriUI (16 new entries each): Tasks/Workspaces toggle, Set Status menu, 5 WorkflowStatus display names, Show/Hide Cancelled, relative time strings
  - App target (3 new entries each): Command palette status actions (Status: %@, Current status for %@, Set %@ to %@)
  - MoriCLI (3 new entries each): StatusCmd abstract, discussion, and status argument help text
- Ran full test suite: 641 assertions passing (346 core + 47 persistence + 200 tmux + 48 IPC), zero regressions
- Updated CHANGELOG.md with Task Mode Sidebar feature entry under [Unreleased]

**Build result:** Zero errors, zero warnings (only existing ghostty linker warnings).

**Test results:** 641 total assertions passing across all 4 test targets. Zero regressions.

**Files modified:**
- `Packages/MoriUI/Sources/MoriUI/SidebarContainerView.swift` (added .localized() to picker labels)
- `Packages/MoriUI/Sources/MoriUI/WorkflowStatusMenu.swift` (added .localized() to menu title and status labels)
- `Packages/MoriUI/Sources/MoriUI/TaskSidebarView.swift` (added .localized() to group headers and cancelled toggle)
- `Packages/MoriUI/Sources/MoriUI/TaskWorktreeRowView.swift` (added .localized() to relative time strings)
- `Packages/MoriUI/Sources/MoriUI/Resources/en.lproj/Localizable.strings` (16 new entries)
- `Packages/MoriUI/Sources/MoriUI/Resources/zh-Hans.lproj/Localizable.strings` (16 new entries)
- `Sources/Mori/Resources/en.lproj/Localizable.strings` (3 new entries)
- `Sources/Mori/Resources/zh-Hans.lproj/Localizable.strings` (3 new entries)
- `Sources/MoriCLI/Resources/en.lproj/Localizable.strings` (3 new entries)
- `Sources/MoriCLI/Resources/zh-Hans.lproj/Localizable.strings` (3 new entries)
- `CHANGELOG.md` (added Task Mode Sidebar feature entry)
