<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <b>English</b> | <a href="README.zh-Hans.md">中文</a>
</p>

A native macOS workspace terminal organized around **Projects** and **Worktrees**, powered by **tmux** and **libghostty**.

Mori treats git repositories as first-class projects. Each worktree gets its own persistent tmux session, presented through a native sidebar and GPU-accelerated terminal.

## Features

- **Project-first navigation** — switch between repos and branches, not anonymous tabs
- **Persistent sessions** — close the app, reopen later, tmux keeps everything running
- **Worktree-aware** — multiple branches of the same repo run side-by-side
- **Local + SSH projects** — add local folders or remote repos from one flow
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

```bash
mori project list
mori open /path/to/repo
mori worktree create <project> <branch>
mori focus <project> <worktree>
mori new-window <project> <worktree> <name>
mori send <project> <worktree> <window> "keys"
mori pane list|read|message|id
```

## Terminal Configuration

Mori uses Ghostty's configuration system. Customize your terminal in `~/.config/ghostty/config`. Mori only overrides a few embedding-specific settings (no window decorations, no quit-on-last-window).

## Keyboard Shortcuts

See [docs/keymaps.md](docs/keymaps.md) for the full list. Key highlights:

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd>+<kbd>T</kbd> | New tab |
| <kbd>⌘</kbd>+<kbd>D</kbd> / <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>D</kbd> | Split right / down |
| <kbd>⌃</kbd>+<kbd>Tab</kbd> | Cycle worktrees |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>N</kbd> | New worktree |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>P</kbd> | Command palette |
| <kbd>⌘</kbd>+<kbd>G</kbd> | Lazygit |
| <kbd>⌘</kbd>+<kbd>E</kbd> | Yazi |

## License

[MIT](LICENSE)
