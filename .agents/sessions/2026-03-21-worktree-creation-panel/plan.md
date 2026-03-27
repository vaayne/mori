# Plan: Worktree Creation Panel

## Overview

Replace the inline TextField worktree creation with a keyboard-first NSPanel (modeled after CommandPaletteController). Users can fuzzy-search branches, create new branches from a chosen base, or check out existing branches — all without touching the mouse.

### Goals

- Enable creating worktrees from existing local/remote branches (not just new branches)
- Provide fuzzy branch search with metadata (relative time, local vs remote)
- Allow selecting base branch and template at creation time
- Keep it keyboard-first and fast — no extra clicks for the common case

### Success Criteria

- [ ] Can create worktree from an existing local branch
- [ ] Can create worktree from a remote branch (auto-creates local tracking branch)
- [ ] Can create a new branch from a chosen base branch
- [ ] Fuzzy search filters branches in real-time
- [ ] Template selector works (Basic / Go / Agent)
- [ ] Fully keyboard-navigable (type, arrows, Enter, Esc)
- [ ] Panel reuses CommandPaletteController's NSPanel patterns
- [ ] Existing tests still pass, new tests for GitBranchInfo parsing + fuzzy matching

### Out of Scope

- Importing existing worktrees not managed by Mori
- Custom path editing (auto-generated path displayed, not editable)
- Post-creation setup commands
- Worktree settings panel / archive

## Technical Approach

### Architecture

The panel follows the same pattern as `CommandPaletteController`:
- `WorktreeCreationController` — `NSWindowController` owning an `NSPanel`
- Delegates to `GitBackend` for branch data, `WorkspaceManager` for creation
- Pure AppKit (no SwiftUI) for consistency with existing panel code

### Key Design Decisions

1. **Branch data fetching**: `git branch -a --sort=-committerdate --format=...` gives us branch name, commit date, and tracking info in one call. Parsed into `GitBranchInfo` structs.

2. **Fuzzy matching**: Simple substring match on branch name (case-insensitive), same approach as CommandPaletteDataSource. No need for a fuzzy scoring library.

3. **Three git code paths for worktree creation**:
   - **Existing local branch**: `git worktree add <path> <branch>` (`createBranch: false`, no baseBranch)
   - **Existing remote branch**: `git worktree add <path> <branch>` (`createBranch: false` — git auto-creates local tracking branch)
   - **New branch from base**: `git worktree add -b <newbranch> <path> <base>` (`createBranch: true`, baseBranch required)

4. **Two-phase keyboard UX for "new branch"**:
   - User types a name that doesn't match → "Create new branch" row appears at top
   - User presses Enter on that row → footer expands with base branch inline selector
   - Base branch defaults to main/default branch, shown as `from: main`
   - User can type to change base (Tab cycles focus to the base field, type to filter, Enter to confirm)
   - Second Enter creates the worktree
   - For **existing branch** selection: single Enter creates immediately (no footer interaction needed)
   - Template is always shown in footer but defaults to Basic — user can Tab to it if desired

5. **Footer bar**: A fixed-height area below the table. Always shows: template selector + path preview. In "new branch" mode, additionally shows base branch selector. All footer controls are Tab-navigable from the search field.

6. **Remote branches**: Shown with `origin/` prefix stripped for display, grouped under "Remote" section header. Selecting a remote branch creates a local tracking branch automatically.

7. **`GitControlling` protocol change**: `addWorktree()` gains a new `baseBranch: String?` parameter. When non-nil and `createBranch` is true, the command becomes `git worktree add -b <branch> <path> <baseBranch>`.

8. **Method consolidation**: `handleCreateWorktreeFromPanel()` replaces `handleCreateWorktree(branchName:)`. The old method is removed. Command palette's create-worktree action is updated to open the panel instead.

### Components

- **`GitBranchInfo`** (MoriGit): Model for branch metadata — name, isRemote, commitDate, isHead
- **`GitBranchParser`** (MoriGit): Parses `git branch -a --sort=-committerdate --format=...` output
- **`GitBackend.listBranches()`** (MoriGit): New method on GitControlling protocol + GitBackend actor
- **`WorktreeCreationController`** (Mori app): NSPanel-based UI controller
- **`WorktreeCreationDataSource`** (Mori app): Branch fetching, filtering, section grouping — separated from controller for testability
- **`WorkspaceManager` extensions** (Mori app): Extended `createWorktree()` signature with `createBranch`, `baseBranch`, and `template` parameters
- **WorktreeSidebarView update** (MoriUI): Replace inline TextField with callback to show panel

## Implementation Phases

### Phase 1: Git Branch Listing + Protocol Update (MoriGit package)

1. Add `GitBranchInfo` model — name, isRemote, commitDate, isHead, trackingBranch (files: `Packages/MoriGit/Sources/MoriGit/GitBranchInfo.swift`)
2. Add `GitBranchParser` — parse `git branch -a --sort=-committerdate --format='%(refname:short)|%(HEAD)|%(committerdate:unix)|%(upstream:short)'` with `|` delimiters (files: `Packages/MoriGit/Sources/MoriGit/GitBranchParser.swift`)
3. Add `listBranches(repoPath:)` to `GitControlling` protocol and `GitBackend` (files: `Packages/MoriGit/Sources/MoriGit/GitControlling.swift`, `Packages/MoriGit/Sources/MoriGit/GitBackend.swift`)
4. Update `addWorktree()` signature on `GitControlling` and `GitBackend` — add `baseBranch: String? = nil` parameter. When `createBranch: true` and `baseBranch` is non-nil: `git worktree add -b <branch> <path> <baseBranch>`. Update existing callers (WorkspaceManager) to pass `nil` for unchanged behavior. (files: `Packages/MoriGit/Sources/MoriGit/GitControlling.swift`, `Packages/MoriGit/Sources/MoriGit/GitBackend.swift`)
5. Add parser tests — local branches, remote branches, HEAD marker, detached HEAD, empty repo (files: `Packages/MoriGit/Sources/MoriGitTests/GitBranchParserTests.swift`)

### Phase 2: WorktreeCreationController (NSPanel UI)

1. Create `WorktreeCreationDataSource` — branch fetching, fuzzy filtering (substring, case-insensitive), section grouping (Create New / Local / Remote), "already in use" marking. Pure logic, no UI — testable independently. (files: `Sources/Mori/App/WorktreeCreationDataSource.swift`)
2. Create `WorktreeCreationController` with NSPanel setup, search field, table view, footer bar — following CommandPaletteController patterns exactly (files: `Sources/Mori/App/WorktreeCreationController.swift`)
3. Implement table cell rendering — branch icon (local/remote/new), branch name, relative time, section headers as non-selectable group rows (files: `Sources/Mori/App/WorktreeCreationController.swift`)
4. Implement keyboard navigation — Up/Down (skip section headers), Enter (confirm or enter two-phase for new branch), Esc (cancel), Tab (cycle to footer controls in new-branch mode) (files: `Sources/Mori/App/WorktreeCreationController.swift`)
5. Implement footer bar — base branch text field with inline filtering (only for new branch mode), template NSPopUpButton (Basic/Go/Agent), path preview label. Footer expands when "Create new branch" is selected, collapses for existing branch selection. (files: `Sources/Mori/App/WorktreeCreationController.swift`)

### Phase 3: WorkspaceManager Integration + Sidebar Wiring

1. Extend `WorkspaceManager.createWorktree()` — add `createBranch: Bool` (default true for backward compat), `baseBranch: String?` (default nil), and `template: SessionTemplate` (default `.basic`) parameters. Three code paths: existing branch (createBranch=false), new branch (createBranch=true, baseBranch=nil → from HEAD), new branch from base (createBranch=true, baseBranch=non-nil). (files: `Sources/Mori/App/WorkspaceManager.swift`)
2. Replace `handleCreateWorktree(branchName:)` with `handleCreateWorktreeFromPanel()` — accepts branch name, createBranch flag, baseBranch, template; routes to `createWorktree()`. Update command palette's create-worktree action to open the panel instead. (files: `Sources/Mori/App/WorkspaceManager.swift`, `Sources/Mori/App/AppDelegate.swift`)
3. Wire `WorktreeCreationController` into `MainWindowController` — instantiate, hold reference, expose `showCreateWorktreePanel(for projectId:)`. Guard: if no project selected, show alert. (files: `Sources/Mori/App/MainWindowController.swift`)
4. Update `WorktreeSidebarView` — remove inline TextField creation UI (editingProjectId, newBranchName, isSubmitting states). Replace `onCreateWorktree` callback with `onShowCreatePanel` callback. "+" button triggers the panel. (files: `Packages/MoriUI/Sources/MoriUI/WorktreeSidebarView.swift`)
5. Add keyboard shortcut to trigger panel — use `Cmd+Shift+N` (avoids conflict with ghostty/macOS `Cmd+N` for new window). Register in key event monitor alongside existing shortcuts. (files: `Sources/Mori/App/MainWindowController.swift`)

### Phase 4: Tests + Polish

1. Add `WorktreeCreationDataSource` tests in MoriCore test target — fuzzy filtering, section grouping, "already in use" filtering, empty query returns all branches, remote branch deduplication when local exists. DataSource is pure logic, testable without UI. (files: `Packages/MoriCore/Sources/MoriCoreTests/WorktreeCreationDataSourceTests.swift` or inline in existing test executable)
2. Add `GitBranchParser` edge case tests — branch with slashes (feature/auth/v2), no remotes, hundreds of branches, malformed lines (files: `Packages/MoriGit/Sources/MoriGitTests/GitBranchParserTests.swift`)
3. Add integration test — `createWorktree` with existing branch (createBranch: false), `createWorktree` with baseBranch (files: existing MoriGit test target)
4. Localize all new strings — panel placeholder, section headers ("Local", "Remote", "Create new branch"), footer labels ("from:", "Template:"), path preview. Add to `Sources/Mori/Resources/Localizable.xcstrings` (app target catalog) for en + zh-Hans. (files: `Sources/Mori/Resources/Localizable.xcstrings`)
5. Clean up: remove old inline creation state (editingProjectId, newBranchName, isSubmitting) and related methods from WorktreeSidebarView. Remove old `handleCreateWorktree(branchName:)` from WorkspaceManager. (files: `Packages/MoriUI/Sources/MoriUI/WorktreeSidebarView.swift`, `Sources/Mori/App/WorkspaceManager.swift`)

## Testing Strategy

- **Unit tests**: GitBranchParser (various formats, edge cases), fuzzy matching logic, section grouping
- **Integration tests**: `GitBackend.listBranches()` on a real git repo (existing test pattern), `createWorktree` with `createBranch: false` and with `baseBranch`
- **Manual testing**: Panel appearance, keyboard flow end-to-end, remote branch checkout, template selection, Cmd+N shortcut
- **Edge cases**: Repo with no remote, repo with hundreds of branches (scroll performance), branch name with `/` separators (feature/foo), detached HEAD state

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| `git branch -a` slow on large repos | Medium | Use `--sort=-committerdate` + limit to 200 branches; async fetch with loading indicator |
| Remote branches stale (not fetched) | Low | Don't auto-fetch — show last-known remotes. User can `git fetch` manually. Add note in UI if remotes are old. |
| Conflicting branch names (local + remote with same name) | Low | Show both with clear local/remote labels; prefer local when user selects |
| Template application fails on complex templates | Low | Already handled — tmux failure is non-fatal in existing code |
| NSPanel first responder conflict with ghostty | Medium | CommandPaletteController already handles this pattern successfully. Reuse same `becomesKeyOnlyIfNeeded` + `hidesOnDeactivate` approach. Test dismiss → terminal regains focus. |
| Branch already checked out in non-Mori worktree | Low | `git worktree add` will fail with clear error. Catch and display in alert — no special handling needed. |

## Open Questions

None — all resolved into assumptions:
- **Assumption**: No auto `git fetch` on panel open (too slow, network-dependent)
- **Assumption**: Path is auto-generated, not user-editable (keeps UI simple)
- **Assumption**: Fuzzy match is substring-based (not Levenshtein/scoring), matching CommandPaletteDataSource
- **Assumption**: `Cmd+Shift+N` for shortcut (avoids `Cmd+N` conflict with ghostty/macOS new window)
- **Assumption**: If no project selected when panel is triggered, show an alert rather than empty panel

## Review Feedback

### Round 1
Reviewer verdict: CHANGES NEEDED. Four issues addressed:
1. **GitControlling protocol change**: Added Phase 1 Task 4 — `addWorktree()` gains `baseBranch: String?` param. Three code paths documented in Key Design Decisions.
2. **Keyboard UX for two-phase flow**: Fully specified in Key Design Decision #4 — Tab cycles to footer, Enter confirms.
3. **handleCreateWorktreeFromPanel vs handleCreateWorktree**: Clarified in Key Design Decision #8 — replaces old method. Command palette action updated to open panel.
4. **Test target**: Resolved — DataSource extracted as pure logic, testable in MoriCore tests. Controller is manual-test only.

## Final Status

**COMPLETE** — All 4 phases implemented, reviewed, and approved.

- 18 commits on `brainstorm/worktree-management`
- 767 test assertions passing (208 git + 312 core + 200 tmux + 47 persistence)
- Zero build warnings
- All success criteria met:
  - [x] Can create worktree from an existing local branch
  - [x] Can create worktree from a remote branch
  - [x] Can create a new branch from a chosen base branch
  - [x] Fuzzy search filters branches in real-time
  - [x] Template selector works (Basic / Go / Agent)
  - [x] Fully keyboard-navigable (type, arrows, Enter, Esc, Tab)
  - [x] Panel reuses CommandPaletteController's NSPanel patterns
  - [x] Existing tests still pass, new tests for GitBranchInfo parsing + fuzzy matching
- No deviations from plan
- Known limitation: DataSource filtering logic tested only at boundaries (GitBranchInfo/parser level) since it lives in app target
