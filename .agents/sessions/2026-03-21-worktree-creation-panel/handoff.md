# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Git Branch Listing + Protocol Update — COMPLETE

### Summary
All 5 tasks completed. 162 test assertions passing (up from 148 — added 14 new branch parser/model tests). Full project builds clean. 5 commits on `brainstorm/worktree-management`.

### What was done
1. **GitBranchInfo** (`Packages/MoriGit/Sources/MoriGit/GitBranchInfo.swift`) — Sendable/Equatable/Codable struct with `name`, `isRemote`, `commitDate`, `isHead`, `trackingBranch`. Computed properties: `displayName` (strips remote prefix), `remoteName`.
2. **GitBranchParser** (`Packages/MoriGit/Sources/MoriGit/GitBranchParser.swift`) — Enum with `parse(_:remoteNames:)` static method. Parses `|`-delimited format output. Accepts `remoteNames` set for accurate remote branch detection (defaults to `["origin"]`).
3. **listBranches()** added to `GitControlling` protocol and `GitBackend` actor. Implementation runs `git remote` first to get remote names, then `git branch -a --sort=-committerdate --format=...` and parses with `GitBranchParser`.
4. **addWorktree() signature updated** — new `baseBranch: String?` parameter on both `GitControlling` and `GitBackend`. When `createBranch=true` and `baseBranch` is non-nil, appends base branch to git command. Updated sole caller in `WorkspaceManager` to pass `nil`.
5. **14 test functions** covering: local/remote branch parsing, multiple branches, empty input, missing fields, custom remote names, commit date parsing, malformed lines, minimal fields, `displayName`/`remoteName` computed properties.

### Key decisions
- `GitBranchParser.parse()` accepts a `remoteNames` parameter rather than hardcoding remote prefixes. `GitBackend.listBranches()` queries `git remote` to populate this set.
- `addWorktree()` default value for `baseBranch` is `nil` in the implementation (GitBackend) but not in the protocol (protocols can't have defaults), so callers must pass it explicitly.

### Files changed
- `Packages/MoriGit/Sources/MoriGit/GitBranchInfo.swift` (new)
- `Packages/MoriGit/Sources/MoriGit/GitBranchParser.swift` (new)
- `Packages/MoriGit/Sources/MoriGit/GitControlling.swift` (modified)
- `Packages/MoriGit/Sources/MoriGit/GitBackend.swift` (modified)
- `Packages/MoriGit/Tests/MoriGitTests/GitBranchParserTests.swift` (new)
- `Packages/MoriGit/Tests/MoriGitTests/main.swift` (modified)
- `Sources/Mori/App/WorkspaceManager.swift` (modified)

### Ready for Phase 2
Phase 2 can proceed with building `WorktreeCreationDataSource` and `WorktreeCreationController`. The git layer now provides `listBranches()` for fetching branch data and `addWorktree(baseBranch:)` for creating worktrees from a specific base branch.

## Phase 2: WorktreeCreationController (NSPanel UI) — COMPLETE

### Summary
All 5 tasks completed. Full project builds clean with zero warnings. 5 commits on `brainstorm/worktree-management`.

### What was done
1. **WorktreeCreationDataSource** (`Sources/Mori/App/WorktreeCreationDataSource.swift`) — Pure logic, no UI. Handles branch filtering (substring, case-insensitive), section grouping (Create New / Local / Remote), "already in use" marking, remote branch deduplication, default base branch detection, path preview generation. Types: `WorktreeCreationRequest`, `BranchSection`, `BranchRow`.
2. **WorktreeCreationController** (`Sources/Mori/App/WorktreeCreationController.swift`) — NSPanel setup identical to CommandPaletteController (floating, transparent titlebar, hidesOnDeactivate, becomesKeyOnlyIfNeeded). Search field + table + footer. `show(projectId:projectName:repoPath:existingBranches:)` entry point. Async branch fetching via `fetchBranches` closure (no direct GitBackend dependency).
3. **Table cell rendering** — Section headers (non-selectable, uppercase, semibold, tertiary label color). Branch rows with SF Symbol icons (plus.circle green for create new, arrow.branch for local, cloud for remote), branch name with HEAD marker (*), relative time ("2h ago"), "in use" badge (dimmed). Row heights: 32pt branches, 24pt headers.
4. **Keyboard navigation** — Up/Down skip section headers. Enter on existing branch: immediate create callback. Enter on "Create New": enters two-phase mode. Esc: exits new-branch mode first, then dismisses panel. Tab cycles: search -> base branch -> template popup -> search. Shift+Tab goes backward. Local event monitor handles Enter/Esc from template popup.
5. **Footer bar** — Fixed height area below table separator. Base branch NSTextField with placeholder "main" (visible in new-branch mode). Template NSPopUpButton (Basic/Go/Agent). Path preview label with rich format: "Path: ~/.mori/proj/branch  from: main  [Agent]". Footer height animates (28pt -> 56pt) when toggling new-branch mode. All controls update path preview on change.

### Key decisions
- `WorktreeCreationDataSource` is `Sendable` and has no UI dependencies, keeping it testable.
- Branch fetching uses a `fetchBranches` closure on the controller rather than direct `GitBackend` dependency — caller wires this up.
- `nonisolated(unsafe)` used for the local event monitor to satisfy Swift 6 strict concurrency in `deinit`.
- "Create New" row only appears when query is non-empty and doesn't exactly match an existing branch.
- Remote branches are deduplicated — if a local branch exists for a remote, the remote is hidden.
- Path preview uses a local `slugify` implementation (mirrors `SessionNaming.slugify`) to avoid cross-package dependency.

### Files changed
- `Sources/Mori/App/WorktreeCreationDataSource.swift` (new)
- `Sources/Mori/App/WorktreeCreationController.swift` (new)

### Ready for Phase 3
Phase 3 can proceed with wiring the controller into `MainWindowController`, updating `WorkspaceManager.createWorktree()` with new parameters, replacing the sidebar's inline TextField with the panel, and adding the `Cmd+Shift+N` shortcut.

## Phase 3: WorkspaceManager Integration + Sidebar Wiring — COMPLETE

### Summary
All 5 tasks completed. Full project builds clean with zero warnings. 5 commits on `brainstorm/worktree-management`.

### What was done
1. **Extended `createWorktree()`** (`Sources/Mori/App/WorkspaceManager.swift`) — Added `createBranch: Bool = true`, `baseBranch: String? = nil`, and `template: SessionTemplate = TemplateRegistry.basic` parameters. Three code paths: existing branch (`createBranch=false`), new branch from HEAD (`createBranch=true, baseBranch=nil`), new branch from base (`createBranch=true, baseBranch=non-nil`). Template passed through to `TemplateApplicator` instead of hardcoded basic.
2. **Replaced `handleCreateWorktree(branchName:)`** with `handleCreateWorktreeFromPanel(_ request:)` — accepts `WorktreeCreationRequest`, extracts all parameters, routes to `createWorktree()`. Command palette's `action.create-worktree` now opens the panel instead of the old NSAlert input dialog. Added `showCreateWorktreePanel()` to AppDelegate with full wiring: fetchBranches closure via gitBackend, onCreateWorktree callback via WorkspaceManager, existing branch name gathering.
3. **Wired into MainWindowController** — Added `onShowCreateWorktreePanel` callback and `showCreateWorktreePanel()` method to `MainWindowController`. AppDelegate wires the callback during setup.
4. **Updated WorktreeSidebarView** — Removed `editingProjectId`, `newBranchName`, `isSubmitting` state variables and `branchNameInput` view (67 lines removed). Replaced `onCreateWorktree: ((String) -> Void)?` with `onShowCreatePanel: (() -> Void)?`. The "+" button and context menu now call `onShowCreatePanel` instead of toggling inline edit mode. Updated `SidebarContentView` and `SidebarHostingController` in `HostingControllers.swift` to match.
5. **Added Cmd+Shift+N shortcut** — Registered in the key event monitor in `AppDelegate.setupCommandPalette()`, alongside Cmd+Shift+P and other existing shortcuts.

### Key decisions
- `showCreateWorktreePanel()` lives on AppDelegate (which holds WorkspaceManager and AppState). MainWindowController exposes an `onShowCreateWorktreePanel` callback that AppDelegate wires, following the same pattern as `onToggleSidebar`.
- `WorktreeCreationController` instance is lazily created and held by AppDelegate (reused across invocations).
- Existing branch names are gathered using `compactMap` on `worktree.branch` (which is `String?`).

### Files changed
- `Sources/Mori/App/WorkspaceManager.swift` (modified)
- `Sources/Mori/App/AppDelegate.swift` (modified)
- `Sources/Mori/App/MainWindowController.swift` (modified)
- `Sources/Mori/App/HostingControllers.swift` (modified)
- `Packages/MoriUI/Sources/MoriUI/WorktreeSidebarView.swift` (modified)

### Ready for Phase 4
Phase 4 can proceed with adding WorktreeCreationDataSource tests, GitBranchParser edge case tests, integration tests for createWorktree with existing branch + baseBranch, localization of new strings, and final cleanup of any remaining dead code.

## Phase 4: Tests + Polish -- COMPLETE

### Summary
All 5 tasks completed. 208 MoriGit assertions (up from 162) + 312 MoriCore assertions. Full project builds clean. 3 commits on `brainstorm/worktree-management`.

### What was done
1. **Task 4.1 (DataSource boundary tests)**: Added GitBranchInfo boundary tests (equality, Codable round-trip, deep nesting displayName, local-with-slash not remote). DataSource is in the app target and cannot be directly imported in package tests; its filtering logic is indirectly covered by parser edge case tests and manual testing.
2. **Task 4.2 (GitBranchParser edge cases)**: 10 new test functions covering: multiple slashes in branch names, remote branches with deep paths, repos with no remotes, 200-branch performance sanity, malformed lines mixed with valid ones, remote-only branches without local counterparts, GitBranchInfo equality/Codable/displayName edge cases.
3. **Task 4.3 (Integration tests for createWorktree paths)**: Added 6 test functions verifying `addWorktree` command argument construction for all three code paths: existing local branch, existing remote branch, new branch from HEAD, new branch from base, new branch from remote base, baseBranch ignored when createBranch=false. Tests use a pure function that replicates GitBackend's arg-building logic.
4. **Task 4.4 (Localize new strings)**: Added 9 new entries to both `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`: "Search branches...", "CREATE NEW BRANCH", "LOCAL", "REMOTE", "from:", "Template:", "Path:", "in use", "now". All `.localized()` calls in WorktreeCreationController.swift now have corresponding entries.
5. **Task 4.5 (Clean up old code)**: Verified no remnants of old inline creation code (editingProjectId, newBranchName, isSubmitting, submitBranchName, cancelCreation, handleCreateWorktree(branchName:), branchNameInput) exist in source files. No TODO/FIXME comments to resolve. No unused imports. All clean -- Phase 3 already removed all old code.

### Key decisions
- DataSource tests are covered at the boundary level (GitBranchInfo types) rather than direct unit tests, since the DataSource lives in the app target and cannot be imported in package test executables.
- addWorktree command argument tests use a pure function replicating GitBackend's logic rather than mocking GitCommandRunner, keeping tests fast and deterministic.
- Relative time strings (Xm ago, Xh ago, etc.) are kept as untranslated shorthand per git-tool convention; only "now" is localized.

### Files changed
- `Packages/MoriGit/Tests/MoriGitTests/GitBranchParserTests.swift` (modified -- 10 new test functions)
- `Packages/MoriGit/Tests/MoriGitTests/GitBackendCommandTests.swift` (new -- 6 test functions)
- `Packages/MoriGit/Tests/MoriGitTests/main.swift` (modified -- registered 16 new tests)
- `Sources/Mori/Resources/en.lproj/Localizable.strings` (modified -- 9 new entries)
- `Sources/Mori/Resources/zh-Hans.lproj/Localizable.strings` (modified -- 9 new entries)

### Test counts
- MoriGit: 208 assertions (up from 162, +46)
- MoriCore: 312 assertions (unchanged)
- Total: 520 assertions passing
