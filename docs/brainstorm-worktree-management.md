# Worktree Management — Brainstorm

## Current State

- Cmd+Shift+N opens creation panel with branch name input, project/base-branch dropdowns
- Creates new branch from selected base, or checks out existing branch if name matches
- Path: `~/.mori/{project}/{branch}`, template: "basic" (single shell window)
- Remove is the only lifecycle action (soft or hard delete)
- No import of external worktrees, no settings after creation

## Ideas

### P0 — Core pain points

**Import existing worktrees**
- `git worktree list` → show untracked ones → user selects → Mori creates DB entries + tmux sessions

**Worktree context menu**
- Right-click: rename, copy path, reveal in Finder, archive, remove
- Info: branch, path, creation date, git status

**Template selection at creation**
- Built-in: Basic (shell), Development (editor + server + tests), Agent (editor + agent + logs)
- Custom templates in `.mori/templates/`

### P1 — Quality of life

**Archive / unarchive** — hide from sidebar, kill tmux session, preserve git worktree

**Sidebar drag & drop** — reorder worktrees, persist custom order

**Inline quick actions** — hover reveals pull/push/open-editor buttons

**Post-creation hooks** — surface `.mori/hooks.json` `onWorktreeCreate` in UI (npm install, make deps, etc.)

### P2 — Power user

**Git forge integration** — show PR status per worktree (open/merged/draft), link to PR/issue

**Branch naming conventions** — configurable prefix (`feature/`, `fix/`), auto-suggest from issue tracker

**Bulk actions** — multi-select, bulk archive/delete/pull

## Open Questions

1. **Auto-cleanup?** — suggest archiving worktrees whose branches are merged? How aggressive?
2. **Template scope?** — per-project, per-user global, or both?
3. **Monorepo?** — multiple projects sharing one git repo with different worktree roots?
