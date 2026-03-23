# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### ✨ Features

- **Task Mode Sidebar**: Alternative sidebar view that groups all worktrees across projects by workflow status (To Do, In Progress, Needs Review, Done, Cancelled) instead of project hierarchy ([#14](https://github.com/vaayne/mori/issues/14))
  - Toggle between Tasks and Workspaces views via segmented control at sidebar top
  - Manual status changes via context menu, command palette, or `mori status` CLI command
  - Auto-transition from To Do to In Progress on first git activity or agent usage
  - Cancelled items hidden by default with reveal toggle; Done group collapsed by default
  - Cross-project worktree selection syncs project context automatically
  - Full localization support (English + Simplified Chinese)

- Add Project now prompts `Local Folder` vs `Remote Project (SSH)`
- Added SSH-backed remote project support so git/tmux operations can run on remote hosts while keeping Mori UI local
- Added a VS Code-style top input wizard for remote host connection (`[user@]host[:port]`, auth mode, path)
- Added command palette action `Remote: Connect to Host...`
- Remote add now allows non-git directories (git integration is best-effort, tmux workflow still works)

### 🐛 Bug Fixes

- `mise run build`/`build:release` now auto-bootstrap GhosttyKit via `build:ghostty` to avoid missing XCFramework errors on fresh clones
- `scripts/build-ghostty.sh` now validates XCFramework contents and rebuilds invalid artifacts instead of treating empty directories as valid
- `scripts/build-ghostty.sh` now auto-installs the Metal Toolchain when `xcrun metal` is unavailable
- Settings `Open Config` now forces text-editor open and normalizes config file permissions to non-executable
- Remote terminal attach now reuses SSH control options for more reliable remote tmux session handling
- Password-auth SSH projects now persist credentials in macOS Keychain and automatically re-authenticate after app restarts
- Terminal surface caching now namespaces by endpoint so local and remote sessions with the same tmux name no longer collide
- `mori send` / `mori new-window` now route to the selected worktree's endpoint backend and use raw tmux target IDs
- Persisted selected window IDs now migrate from legacy raw tmux IDs (e.g. `@1`) to endpoint-namespaced IDs on first restore
- Remote tmux commands now augment PATH (`/opt/homebrew/bin`, `/usr/local/bin`) to support non-default remote installs
- Added `Update Remote Credentials…` action in project menus so SSH auth can be corrected without re-adding the project

## [0.1.0] - 2026-03-20

Initial release of Mori — a macOS native workspace terminal organized around Projects, Worktrees, and tmux sessions.

### ✨ Features

- Three-column UI: project rail, worktree sidebar, terminal area (AppKit + SwiftUI)
- libghostty GPU-accelerated terminal rendering (Metal) with full ghostty config compatibility
- tmux as persistent runtime backend with 5s coordinated polling
- Project and worktree management (add/remove projects, create/remove worktrees)
- Session templates with automatic window creation (shell/run/logs)
- Git status polling with sidebar badges (dirty, unread, agent states)
- Command palette with fuzzy search (Cmd+Shift+P)
- Agent-aware tabs with hook-based status detection for Claude Code, Codex CLI, and Pi ([#4](https://github.com/vaayne/mori/pull/4))
- macOS notifications and dock badge for unread/agent activity
- IPC via Unix socket with `mori` CLI (6 subcommands)
- Automation hooks system (`.mori/hooks.json` per project)
- Ghostty-aligned keybindings (splits, tabs, pane navigation)
- Resizable sidebar with draggable divider
- Window size persistence across launches
- Auto-install to /Applications after bundle

### 🐛 Bug Fixes

- Scoped tmux theme options to Mori-managed sessions only ([#6](https://github.com/vaayne/mori/pull/6))
- Swift 6 concurrency fixes (SIGTRAP crash, PTYTerminalView deinit)
- Robust keybinding handling with menu-first + ghostty action callback
- Context-aware empty state with Reconnect for dead sessions
- Interactive login shell for PATH resolution in .app context

### ♻️ Refactoring

- Replaced GRDB/SQLite with JSON file persistence ([#5](https://github.com/vaayne/mori/pull/5))
- Migrated from SwiftTerm to libghostty terminal backend
- Renamed `ws` CLI to `mori`
- Ghostty submodule with bundled themes for .app builds

### 📝 Documentation

- README with banner, Chinese translation, and keymaps reference
- CLAUDE.md with architecture guide and build commands
- Agent hooks user guide (`docs/agent-hooks.md`)

### 🔧 CI/CD

- GitHub Actions workflows for CI build and release
- GhosttyKit XCFramework build infrastructure

**Full Changelog**: [v0.1.0](https://github.com/vaayne/mori/commits/v0.1.0)

[Unreleased]: https://github.com/vaayne/mori/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vaayne/mori/releases/tag/v0.1.0
