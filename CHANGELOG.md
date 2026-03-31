# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-03-31

### ✨ Features

- **Agent Bridge**: Cross-pane agent monitoring, communication, and dashboard ([#31](https://github.com/vaayne/mori/pull/31))
  - `mori pane list` — list all panes with project/worktree/window/agent/state info
  - `mori pane read <project> <worktree> <window> [--lines N]` — capture pane output
  - `mori pane message <project> <worktree> <window> <text>` — send message with sender metadata
  - `mori pane id` — print current pane identity for self-labeling
  - Hover any window row with agent badge → popover shows last lines of pane output
  - Click waiting badge → inline reply field → sends keys to pane
  - New "Agents" sidebar mode groups all agent windows by state (Attention, Running, Completed, Idle)
  - Multi-pane dashboard panel (⌘⇧A) shows live output from all agent panes
  - Agent-to-agent messaging protocol with `[mori-bridge from:...]` envelope format
- Added "waiting" agent state for Quick Reply support

### 🐛 Bug Fixes

- Slugify project shortName in tmux session naming ([#28](https://github.com/vaayne/mori/pull/28))
- Prevent hover peek from triggering on click-to-switch
- Wire onRequestPaneOutput and onSendKeys callbacks from app layer

### ⚡ Performance

- Faster hover peek — show popover immediately with loading spinner

### 📝 Documentation

- Rewrite agent-bridge.md with comprehensive guide
- Add pre-push CI verification steps to AGENTS.md

**Full Changelog**: [v0.1.3...v0.2.0](https://github.com/vaayne/mori/compare/v0.1.3...v0.2.0)

## [0.1.3] - 2026-03-28
### ✨ Features

- **Sparkle Auto-Update**: In-app update checking and installation via Sparkle 2 framework ([#25](https://github.com/vaayne/mori/pull/25))
  - Titlebar pill badge shows update status (checking, available, downloading, installing)
  - Popover with version details, release notes link, and Install/Skip/Later actions
  - "Check for Updates..." menu item and command palette action
  - CI pipeline generates signed appcast.xml and publishes to GitHub Pages
  - Full localization support (English + Simplified Chinese)

- **Task Mode Sidebar**: Alternative sidebar view that groups all worktrees across projects by workflow status (To Do, In Progress, Needs Review, Done, Cancelled) instead of project hierarchy ([#14](https://github.com/vaayne/mori/issues/14))
  - Toggle between Tasks and Workspaces views via segmented control at sidebar top
  - Manual status changes via context menu, command palette, or `mori status` CLI command
  - Auto-transition from To Do to In Progress on first git activity or agent usage
  - Cancelled items hidden by default with reveal toggle; Done group collapsed by default
  - Cross-project worktree selection syncs project context automatically
  - Full localization support (English + Simplified Chinese)

- Add Project now prompts `Local Folder` vs `Remote Project (SSH)` ([#24](https://github.com/vaayne/mori/pull/24))
- Added SSH-backed remote project support so git/tmux operations can run on remote hosts while keeping Mori UI local
- Added a VS Code-style top input wizard for remote host connection (`[user@]host[:port]`, auth mode, path)
- Added command palette action `Remote: Connect to Host...`
- Remote add now allows non-git directories (git integration is best-effort, tmux workflow still works)
- Remote connect now detects active tmux sessions and lets you attach the project to an existing session so sidebar tabs/panes reflect that live workspace

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
- Worktree sessions now keep a minimum of one tmux window/pane per branch, and legacy worktrees without `tmuxSessionName` are auto-backfilled
- Remote session ensure/create/split now surface explicit "tmux unavailable" errors and avoid keeping stale terminal attachments when session bootstrap fails
- Remote tmux command PATH bootstrap now includes standard Linux/macOS system paths, reducing false negatives on non-login SSH shells
- Ghostty surface close events now trigger automatic session recovery so "Process exited" remote terminals reconnect instead of staying stuck
- Window-close safety now checks live tmux session window counts (not only cached sidebar state) to avoid races that accidentally kill the last remote window/session
- Remote terminal now performs automatic reconnect retries with a dedicated "Reconnecting session" state to provide a mosh-like continuity experience on transient SSH drops
- Remote session discovery/ensure now uses lightweight tmux queries (`list-sessions` / targeted `list-windows`) instead of deep full-tree scans, preventing false "no session" failures from unrelated pane/window scan errors
- Remote terminal SSH attach now forces `BatchMode=no` for interactive surfaces so password-auth sessions can recover instead of exiting immediately when no control master is active
- Runtime window indexing now tolerates duplicate window IDs safely and de-duplicates collisions, preventing startup/IPC crashes from stale overlapping session mappings
- Startup now auto-normalizes conflicting tmux session bindings per endpoint, and remote attach now blocks binding a session already used by another workspace
- SSH password bootstrap no longer injects secrets into inherited process environments; askpass now uses a minimal env and securely permissioned temp scripts
- SSH control socket paths now use fixed-length hashed names with `/tmp` fallback to avoid macOS Unix socket length failures
- Remote SSH command paths now include server keepalive options and hard execution timeouts to prevent hung git/tmux calls
- Keychain credential read failures are now surfaced to users with actionable alerts instead of silently falling back as "password not found"
- Ghostty config save now avoids redundant directory creation by relying on `ensureConfigFileExists()`
- Added unit tests for shared SSH helper behaviors (control path length, option filtering, shell escaping, askpass environment hardening)
- Mori app termination now removes the IPC socket synchronously, and the `mori` CLI now reports missing or stale app sockets directly instead of timing out ([#23](https://github.com/vaayne/mori/pull/23))
- CLI no longer crashes when invoked from inside the app bundle — safe multi-path resource bundle lookup replaces the fatalError-prone `Bundle.module`

### 📦 Dependencies

- Updated ghostty submodule to 6057f8d2b

**Full Changelog**: [v0.1.2...v0.1.3](https://github.com/vaayne/mori/compare/v0.1.2...v0.1.3)

## [0.1.2] - 2026-03-27

### ✨ Features

- Release app bundles now embed the `mori` CLI to support Homebrew cask installs

### 🐛 Bug Fixes

- Tagged releases now stamp Mori.app with the actual release version instead of a hardcoded app version

### 📝 Documentation

- Added Homebrew tap install instructions to the English and Chinese READMEs

### 🔧 CI/CD

- Release automation now updates `vaayne/homebrew-tap` with the new Homebrew cask version and SHA-256 after publishing a tagged release

**Full Changelog**: [v0.1.1...v0.1.2](https://github.com/vaayne/mori/compare/v0.1.1...v0.1.2)

## [0.1.1] - 2026-03-27

### ✨ Features

- Task Mode sidebar groups worktrees by workflow status, supports manual status changes, and keeps project selection in sync across task-focused navigation
- Worktree creation now uses a dedicated panel with local and remote branch discovery
- Sidebar worktree rows now show upstream state, relative activity time, and richer git status information
- Network proxy settings can be applied to tmux sessions from the app
- macOS release builds now ship as signed, notarized app archives plus DMG installers

### 🐛 Bug Fixes

- Packaged `.app` bundles now load SwiftPM resources from the app bundle correctly and launch tmux using the resolved absolute binary path
- Release archives now avoid AppleDouble `._` files across copy, zip, and unzip flows so signatures remain valid after download
- Release workflow env handling and signing/notarization steps were fixed for CI builds
- Task sidebar and tmux integration received follow-up fixes for naming, session theme application, and startup behavior

### 📝 Documentation

- Added code signing, network proxy, and worktree guides
- Updated README, keymaps, and release-related docs to match the current app behavior

### 🔧 CI/CD

- Release automation now builds signed and notarized archives and publishes DMG artifacts

**Full Changelog**: [v0.1.0...v0.1.1](https://github.com/vaayne/mori/compare/v0.1.0...v0.1.1)

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

[Unreleased]: https://github.com/vaayne/mori/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/vaayne/mori/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/vaayne/mori/releases/tag/v0.1.3
[0.1.2]: https://github.com/vaayne/mori/releases/tag/v0.1.2
[0.1.1]: https://github.com/vaayne/mori/releases/tag/v0.1.1
[0.1.0]: https://github.com/vaayne/mori/releases/tag/v0.1.0
