# Worktrees

Mori organizes work around git worktrees. Each worktree is a branch checkout with its own directory and persistent tmux session.

```
Project (git repo)
  └─ Worktree (branch checkout)  →  ~/.mori/{project}/{branch}/
       └─ tmux session           →  {project}/{branch}
```

## Creating a Worktree

Open the creation panel with `Cmd+Shift+N` or click `+` next to a project in the sidebar.

The panel has two rows:
- **Branch name** — type a name and press Enter (or `Cmd+Enter`)
- **Project / Base branch** — select which project and base branch to use

If the typed name matches an existing local or remote branch, Mori checks it out into a new worktree. Otherwise, Mori creates a new branch from the selected base.

The worktree is created at `~/.mori/{project-slug}/{branch-slug}` with a "basic" template (single shell window).

## Switching Worktrees

| Method | How |
|--------|-----|
| Sidebar | Click a worktree in the sidebar |
| Keyboard | `Ctrl+Tab` / `Ctrl+Shift+Tab` to cycle |
| Command palette | `Cmd+Shift+P`, type worktree name |

## Removing a Worktree

Right-click a worktree in the sidebar and select "Remove". This removes the tmux session and the git worktree directory.

## CLI

```bash
mori worktree create <project> <branch>   # Create a worktree
mori focus <project> <worktree>            # Switch to a worktree
```

## How It Works

1. `git worktree add` creates the branch checkout in `~/.mori/`
2. A tmux session is created with the naming convention `{project}/{branch}`
3. The "basic" template creates a single shell window in the worktree directory
4. Mori's 5-second polling timer picks up git status and tmux state changes

Sessions persist across app restarts. If a tmux session dies, Mori recreates it automatically on the next poll or when you select the worktree.
