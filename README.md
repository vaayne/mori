<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <b>English</b> | <a href="README.zh-Hans.md">中文</a>
</p>

Mori is a macOS terminal built for developers who work across multiple git branches at the same time. Instead of juggling anonymous tabs or losing tmux state between context switches, Mori gives each branch its own persistent environment — and keeps them all one click away in a sidebar.

## The mental model

Mori maps your development hierarchy directly onto tmux:

```
Project  (git repo)
└── Worktree  (branch)          ← tmux session  e.g. myapp/feat-auth
    ├── Window  (tab)           ← tmux window   e.g. "shell"
    │   ├── Pane  (split left)  ← tmux pane
    │   └── Pane  (split right) ← tmux pane
    └── Window  (tab)           ← tmux window   e.g. "logs"
        └── Pane
```

- **Project** — a git repository. Mori tracks it by its root path and a short name.
- **Worktree** — a `git worktree` checkout of a branch. Each gets its own directory and its own tmux session (`<project-shortname>/<branch-slug>`). Close the app, come back tomorrow — the session is still there.
- **Window** — a tmux window inside the worktree's session. Equivalent to a tab.
- **Pane** — a tmux pane inside a window. Equivalent to a split.

The sidebar shows your projects and their worktrees. Clicking a worktree attaches the terminal to that session. Switching between worktrees is instant — you never lose what was running.

## Features

- **Project-first navigation** — switch between repos and branches via sidebar, not anonymous tabs
- **Persistent sessions** — close the app, reopen later; tmux keeps everything running
- **Git worktree aware** — multiple branches of the same repo run side-by-side with full isolation
- **Local + SSH** — add local folders or remote repos; the UI stays on your Mac
- **CLI (`mori`)** — control the app from the terminal; built for agent workflows
- **MoriRemote** — iPhone/iPad companion app for SSH/tmux access away from your Mac
- **GPU-rendered terminal** — libghostty (Ghostty's engine) with Metal acceleration

## Install

```bash
brew tap vaayne/tap
brew install --cask mori
```

Or download from [GitHub Releases](https://github.com/vaayne/mori/releases). MoriRemote for iOS is on [TestFlight](https://testflight.apple.com/join/k2GFJPC2).

## Build

Requires macOS 14+, tmux, [mise](https://mise.jdx.dev/), Zig 0.15.2, and Xcode.

```bash
mise run build    # Debug build (bootstraps libghostty automatically)
mise run dev      # Build + run
mise run test     # Run all tests
```

## CLI

The `mori` CLI communicates with the running app over a Unix socket. It auto-launches Mori if not running. All commands accept `--json` for machine-readable output.

Address flags (`--project`, `--worktree`, `--window`, `--pane`) default to the `MORI_*` environment variables that Mori sets in every terminal pane — so inside a Mori session you can omit them entirely.

```bash
# Projects
mori project list
mori project open .                          # register current directory

# Worktrees
mori worktree list --project myapp
mori worktree new feat/auth --project myapp  # creates git worktree + tmux session
mori worktree delete --project myapp --worktree feat/auth

# Windows (tabs within a worktree session)
mori window list --project myapp --worktree main
mori window new  --name logs                 # context-aware inside Mori terminal
mori window rename logs --window shell
mori window close --window logs

# Panes (splits within a window)
mori pane list                               # lists panes in current window
mori pane new --split h                      # horizontal split
mori pane send "npm test Enter"              # send keys to active pane
mori pane read --lines 100                   # capture pane output
mori pane rename agent --pane %3
mori pane close --pane %3

# Navigation
mori focus --project myapp --worktree feat/auth
mori focus --window logs                     # focus a window (context-aware)

# Agent communication
mori pane message "build done" --window orchestrator
mori pane id                                 # print current pane identity
```

See [docs/cli-redesign.md](docs/cli-redesign.md) for the full CLI specification.

## Terminal Configuration

Mori uses Ghostty's configuration system. Customize your terminal in `~/.config/ghostty/config`. Mori only overrides a few embedding-specific settings (no window decorations, no quit-on-last-window).

For Mori-managed tmux sessions, Mori also applies a small tmux preset by default to speed up onboarding: mouse support on, status bar off. You can turn that off in **Settings → Tools** if you prefer to keep your own mouse and status-bar behavior from `tmux.conf` instead.

## Keyboard Shortcuts

See [docs/keymaps.md](docs/keymaps.md) for the full list. Key highlights:

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd>+<kbd>T</kbd> | New window (tab) |
| <kbd>⌘</kbd>+<kbd>D</kbd> / <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>D</kbd> | Split right / down |
| <kbd>⌃</kbd>+<kbd>Tab</kbd> | Cycle worktrees |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>N</kbd> | New worktree |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>P</kbd> | Command palette |
| <kbd>⌘</kbd>+<kbd>G</kbd> | Lazygit |
| <kbd>⌘</kbd>+<kbd>E</kbd> | Yazi |

## License

[MIT](LICENSE)
