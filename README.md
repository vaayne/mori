<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <b>English</b> | <a href="README.zh-Hans.md">中文</a>
</p>

A native macOS workspace terminal organized around **Projects** and **Worktrees**, powered by **tmux** and **libghostty**.

Instead of managing loose terminal tabs, Mori treats your git repositories as first-class projects. Each worktree (branch checkout) gets its own persistent tmux session with multiple windows and panes — all presented through a native sidebar and GPU-accelerated terminal.

## Why Mori

- **Project-first navigation** — switch between repos and branches, not anonymous tabs
- **Persistent sessions** — close the app, reopen later, everything is still running in tmux
- **Native macOS experience** — sidebar, command palette, notifications, keyboard shortcuts
- **GPU-rendered terminal** — libghostty (Ghostty's rendering engine) with Metal acceleration
- **Worktree-aware** — multiple branches of the same repo run side-by-side with independent sessions

## How It Works

```
Project (git repo)
  └─ Worktree (branch checkout)
       └─ tmux Session
            ├─ Window (tab)   →  Pane
            ├─ Window         →  Pane | Pane
            └─ Window         →  Pane
```

Each worktree maps to one tmux session. Windows and panes are standard tmux constructs. Mori provides the UI layer on top — organizing, navigating, and displaying status.

## Architecture

```
App (AppKit shell + SwiftUI sidebar views)
  ├─ MoriCore         — Models + observable app state
  ├─ MoriUI           — SwiftUI sidebar views
  ├─ MoriTmux         — tmux CLI integration (actor)
  ├─ MoriGit          — Git worktree/status discovery (actor)
  ├─ MoriTerminal     — libghostty terminal surface
  ├─ MoriPersistence  — SQLite via GRDB
  └─ MoriIPC          — Unix socket IPC + `ws` CLI
```

## Requirements

- macOS 14 (Sonoma) or later
- tmux
- [mise](https://mise.jdx.dev/) (task runner)
- Zig 0.15.2 + Xcode (for building libghostty)

## Build & Run

```bash
mise run build           # Debug build
mise run build:release   # Release build
mise run dev             # Build + run
mise run test            # Run all tests
mise run clean           # Clean build artifacts
```

`mise run build` and `mise run build:release` automatically bootstrap the libghostty XCFramework on first run. You can also build it manually:

```bash
mise run build:ghostty   # Requires Zig 0.15.2 + Xcode (downloads Metal Toolchain if missing)
```

## CLI

The `mori` command lets you interact with Mori from the terminal:

```bash
mori project list
mori open /path/to/repo
mori worktree create <project> <branch>
mori focus <project> <worktree>
mori send <project> <worktree> <window> "command"
mori new-window <project> <worktree> <name>
```

## Mori Remote (iOS)

Mori Remote is an iOS companion app that lets you access your Mac's tmux sessions from anywhere via a cloud relay.

**How it works:**

```
Mac (MoriRemoteHost)  ──WSS──>  Cloud Relay (Go)  <──WSS──  iOS (Mori Remote)
        │ pty                    (Fly.io)                    (libghostty)
        v
  tmux attach -t <session>
```

- **MoriRemoteHost** runs on your Mac as a standalone process, bridging tmux sessions to the relay via WebSocket
- **Go Relay** pairs Mac and iOS connections using one-time tokens, streams terminal bytes bidirectionally
- **Mori Remote** (iOS 17+) renders the terminal using the same libghostty Metal renderer as the Mac app

**Features:**
- QR-code pairing between Mac and iOS (no accounts needed)
- Session list with display-friendly names
- Read-only and interactive mode toggle
- Fast reconnect on app resume (no background keep-alive)
- Localized in English and Simplified Chinese

**Quick start:**

```bash
# Start the host connector
mori-remote-host serve --relay-url wss://your-relay.fly.dev/ws --token <TOKEN>

# Generate a QR code for iOS pairing
mori-remote-host qrcode --relay-url https://your-relay.fly.dev

# List sessions
mori-remote-host sessions

# Build iOS app (requires Xcode + iOS simulator)
mise run ios:build
```

## Terminal Configuration

Mori uses Ghostty's configuration system. Customize your terminal in `~/.config/ghostty/config`. Mori only overrides a few embedding-specific settings (no window decorations, no quit-on-last-window).

## Keyboard Shortcuts

See [docs/worktrees.md](docs/worktrees.md) for worktree management and [docs/keymaps.md](docs/keymaps.md) for the full shortcut list. Highlights:

| Shortcut                                                     | Action                |
| ------------------------------------------------------------ | --------------------- |
| <kbd>⌘</kbd>+<kbd>T</kbd>                                    | New tab (tmux window) |
| <kbd>⌘</kbd>+<kbd>W</kbd>                                    | Close pane            |
| <kbd>⌘</kbd>+<kbd>D</kbd> / <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>D</kbd> | Split right / down    |
| <kbd>⌘</kbd>+<kbd>1</kbd>–<kbd>⌘</kbd>+<kbd>9</kbd>          | Go to tab N           |
| <kbd>⌃</kbd>+<kbd>Tab</kbd> / <kbd>⌃</kbd>+<kbd>⇧</kbd>+<kbd>Tab</kbd> | Cycle worktrees       |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>N</kbd>                       | New worktree          |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>P</kbd>                       | Command palette       |
| <kbd>⌘</kbd>+<kbd>B</kbd>                                    | Toggle sidebar        |
| <kbd>⌘</kbd>+<kbd>G</kbd>                                    | Lazygit               |
| <kbd>⌘</kbd>+<kbd>E</kbd>                                    | Yazi                  |


## License

[MIT](LICENSE)
