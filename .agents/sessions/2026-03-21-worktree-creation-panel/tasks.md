# Tasks: Worktree Creation Panel

## Phase 1: Git Branch Listing + Protocol Update (MoriGit)

- [x] 1.1 — Add `GitBranchInfo` model (`Packages/MoriGit/Sources/MoriGit/GitBranchInfo.swift`)
- [x] 1.2 — Add `GitBranchParser` (`Packages/MoriGit/Sources/MoriGit/GitBranchParser.swift`)
- [x] 1.3 — Add `listBranches(repoPath:)` to `GitControlling` + `GitBackend` (`GitControlling.swift`, `GitBackend.swift`)
- [x] 1.4 — Update `addWorktree()` signature with `baseBranch: String?` on `GitControlling` + `GitBackend` (`GitControlling.swift`, `GitBackend.swift`)
- [x] 1.5 — Add `GitBranchParser` tests (`Packages/MoriGit/Sources/MoriGitTests/GitBranchParserTests.swift`)

## Phase 2: WorktreeCreationController (NSPanel UI)

- [ ] 2.1 — Create `WorktreeCreationDataSource` — filtering, grouping, "in use" marking (`Sources/Mori/App/WorktreeCreationDataSource.swift`)
- [ ] 2.2 — Create `WorktreeCreationController` — NSPanel, search field, table, footer (`Sources/Mori/App/WorktreeCreationController.swift`)
- [ ] 2.3 — Implement table cell rendering — icons, branch name, relative time, section headers (`WorktreeCreationController.swift`)
- [ ] 2.4 — Implement keyboard navigation — Up/Down/Enter/Esc/Tab (`WorktreeCreationController.swift`)
- [ ] 2.5 — Implement footer bar — base branch field, template popup, path preview (`WorktreeCreationController.swift`)

## Phase 3: WorkspaceManager Integration + Sidebar Wiring

- [x] 3.1 — Extend `createWorktree()` with `createBranch`, `baseBranch`, `template` params (`WorkspaceManager.swift`)
- [x] 3.2 — Replace `handleCreateWorktree` with `handleCreateWorktreeFromPanel`, update command palette action (`WorkspaceManager.swift`, `AppDelegate.swift`)
- [x] 3.3 — Wire controller into `MainWindowController` (`MainWindowController.swift`)
- [x] 3.4 — Update `WorktreeSidebarView` — remove inline TextField, add `onShowCreatePanel` callback (`WorktreeSidebarView.swift`)
- [x] 3.5 — Add `Cmd+Shift+N` shortcut (`AppDelegate.swift`)

## Phase 4: Tests + Polish

- [x] 4.1 — Add `WorktreeCreationDataSource` tests (MoriGit boundary tests for GitBranchInfo)
- [x] 4.2 — Add `GitBranchParser` edge case tests (`GitBranchParserTests.swift`)
- [x] 4.3 — Add integration tests for createWorktree with existing branch + baseBranch (MoriGit test target)
- [x] 4.4 — Localize new strings in en + zh-Hans (`Localizable.strings`)
- [x] 4.5 — Clean up old inline creation code (verified clean — Phase 3 already removed all remnants)
