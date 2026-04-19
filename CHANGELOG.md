# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] - 2026-04-19

### ✨ Features

- Add a user-toggleable Mori tmux defaults preset in Settings → Tools so Mori-managed sessions can start with mouse support enabled and the tmux status bar hidden, while still allowing an opt-out back to the user's own mouse and status-bar behavior from `tmux.conf` ([#78](https://github.com/vaayne/mori/pull/78))

### 🐛 Bug Fixes

- Include system fonts like JetBrains Maple Mono in the terminal font picker even when AppKit does not flag them as fixed-pitch, by falling back to uniform glyph-width detection ([#78](https://github.com/vaayne/mori/pull/78))
- Preserve symlinked agent settings files (e.g. `~/.claude/settings.json` linked into a dotfiles repo) when installing hooks; the atomic write now resolves the symlink first so the link is no longer replaced with a regular file ([#81](https://github.com/vaayne/mori/pull/81))
- Automatically close the companion Git / Files pane when the embedded Lazygit or Yazi process exits — no longer leaves a blank "press any key to close" panel that could only be dismissed by restarting Mori ([#82](https://github.com/vaayne/mori/pull/82))
- Scope agent hook tmux updates to the exact `TMUX_PANE` that fired the hook, fixing cases where one Claude / Codex / Pi pane could incorrectly stamp sibling panes in the same session as Running or Waiting ([#83](https://github.com/vaayne/mori/issues/83))
- Refresh already-enabled agent hook files from Mori's bundled resources on every launch, so `~/.config/mori/` stays in sync with the running app version and stale scripts self-heal after upgrades

**Full Changelog**: [v0.4.0...v0.4.1](https://github.com/vaayne/mori/compare/v0.4.0...v0.4.1)

## [0.4.0] - 2026-04-18

### 🎨 Design

- **Sidebar refinement** — calmer status strip with a right-aligned tree count, colorful per-project letter tiles for faster scanning, and a left accent bar plus soft gradient on the selected worktree row ([#77](https://github.com/vaayne/mori/pull/77))

**Full Changelog**: [v0.3.8...v0.4.0](https://github.com/vaayne/mori/compare/v0.3.8...v0.4.0)

## [0.3.8] - 2026-04-17

### ✨ Features

- **App icon refresh** — replace the scenic mascot Dock tile with a darker, terminal-aligned Mori mark: simplified stump silhouette, carved prompt glyph, and cleaner macOS-friendly composition
- **CLI redesign: context-aware addressing** — all address components (`--project`, `--worktree`, `--window`, `--pane`) are now optional flags that default to the matching `MORI_*` env var, eliminating repeated arguments inside Mori terminals
- **New `mori window` group** — `window list`, `window new`, `window rename`, `window close`
- **New `mori worktree list` and `worktree delete`** — list all worktrees for a project; delete a worktree (kills tmux session + removes git worktree)
- **New pane subcommands** — `pane new` (split), `pane send`, `pane rename`, `pane close` replace the old top-level `send` and `new-window` commands
- **`mori focus` improvements** — optionally targets a specific window via `--window`
- **`pane list` scoping** — now accepts `--window` to scope to a single window; inside a Mori terminal the current window is the default scope

### 🗑️ Breaking Changes

- Removed top-level `mori send`, `mori new-window`, and positional-arg `mori focus` — replaced by `mori pane send`, `mori window new`, and flag-based `mori focus`

**Full Changelog**: [v0.3.7...v0.3.8](https://github.com/vaayne/mori/compare/v0.3.7...v0.3.8)

## [0.3.7] - 2026-04-16

### ✨ Features

- Pin projects to the top of the sidebar via context menu or drag-and-drop ([#74](https://github.com/vaayne/mori/pull/74))

### 🐛 Bug Fixes

- Allow horizontal scrolling in MoriRemote KeyBarView even when touch starts on a button ([#69](https://github.com/vaayne/mori/pull/69))
- Apply `tmux status off` to newly created sessions ([#67](https://github.com/vaayne/mori/pull/67))

**Full Changelog**: [v0.3.6...v0.3.7](https://github.com/vaayne/mori/compare/v0.3.6...v0.3.7)

## [0.3.6] - 2026-04-13

### ✨ Features

- Drag-to-reorder projects in the sidebar ([#64](https://github.com/vaayne/mori/pull/64))
- Cmd-hold shortcut hints for toolbar and sidebar footer buttons ([#63](https://github.com/vaayne/mori/pull/63))

### 🐛 Bug Fixes

- Prevent key bar gesture recognizer crash on MoriRemote ([#62](https://github.com/vaayne/mori/pull/62))
- Remove noisy PreToolUse agent hook to reduce log clutter ([#65](https://github.com/vaayne/mori/pull/65))

**Full Changelog**: [v0.3.5...v0.3.6](https://github.com/vaayne/mori/compare/v0.3.5...v0.3.6)

## [0.3.5] - 2026-04-13

### ✨ Features

- **MoriRemote**: add adaptive iPad layouts with split-view server browsing while disconnected and a persistent two-pane workspace while connected ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: polish iPhone and iPad UI to follow the shared Mac-first `DESIGN.md` language with denser server rows, flatter tmux sidebars, compact terminal chrome, and normalized dark semantic styling ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: restyle the terminal accessory bar and key customization sheet with compact Mori tokens, semantic accent usage, and localized tmux actions ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: polish terminal connection microstates with richer iPad connection/failure detail states and a calmer in-terminal shell preparation overlay ([#60](https://github.com/vaayne/mori/pull/60))
- Start replacing Yazi/Lazygit's separate tmux-window flow with a shared in-window companion tool pane that reuses one right-side split for Files and Git ([#58](https://github.com/vaayne/mori/pull/58))

### 🐛 Bug Fixes

- **MoriRemote**: make the regular-width terminal sidebar collapsible again and replace the crashing iPad keyboard-accessory tmux menu with a stable confirmation dialog ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: move compact terminal navigation into the accessory row by adding a back control beside tmux, keeping the terminal viewport free of extra chrome ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: harden terminal session lifecycle handling so disconnects, host switches, stale shell callbacks, and accessory-bar reuse no longer race into broken shell/tmux state ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: defer accessory-bar navigation and tmux/customization presentation until after the keyboard responder cycle, preventing crashes when tapping Back or tmux actions ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: preserve reconnect reliability after Back/disconnect by preventing stale disconnect tasks from overwriting a newer SSH connection attempt ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**: stop the server list from hanging in "Connecting…" forever by surfacing missing-password and SSH timeout failures as explicit errors ([#60](https://github.com/vaayne/mori/pull/60))
- Add shared tool-path resolution for tmux, Lazygit, and Yazi, including custom install prefixes like `~/homebrew/bin`, explicit Settings overrides, and local launch paths that reuse the resolved executable instead of assuming the app's inherited PATH ([#59](https://github.com/vaayne/mori/pull/59))

### ♻️ Refactoring

- Remove legacy workflow-status and sidebar-mode code paths after the unified sidebar redesign, including the `mori status` CLI command and manual sidebar status controls ([#57](https://github.com/vaayne/mori/pull/57))

**Full Changelog**: [v0.3.4...v0.3.5](https://github.com/vaayne/mori/compare/v0.3.4...v0.3.5)

## [0.3.4] - 2026-04-12

### ✨ Features

- Ghostty translucency inheritance: Mori now reads and persists `background-blur` and `background-opacity-cells`, applies Ghostty window opacity/blur to the main workspace window, exposes translucency controls in Settings, improves tmux translucency by avoiding forced opaque backgrounds when cell opacity is disabled, adds macOS 26 glass background polish for terminal content, and avoids redundant tmux theme reapplication with debounced updates ([#55](https://github.com/vaayne/mori/pull/55))
- Add Droid agent status hook support for richer agent lifecycle tracking in Mori ([#53](https://github.com/vaayne/mori/pull/53))
- Introduce the unified sidebar redesign with task/workspace parity, collapsed non-active task groups by default, shared footer cleanup, and improved visual hierarchy ([#56](https://github.com/vaayne/mori/pull/56))

### 🐛 Bug Fixes

- Resolve the CLI/app IPC socket path mismatch when `mori` runs from inside the packaged `.app` bundle ([#52](https://github.com/vaayne/mori/pull/52))
- Fall back to the CI GhosttyKit artifact when the local Zig linker fails during dependency setup
- Fix MoriRemote keyboard input being obscured by the software keyboard and add a dismiss button
- Default iOS TestFlight build numbers to a UTC timestamp in CI to avoid duplicate build-number failures

**Full Changelog**: [v0.3.3...v0.3.4](https://github.com/vaayne/mori/compare/v0.3.3...v0.3.4)

## [0.3.3] - 2026-04-05

### ✨ Features

- Cmd-hold shortcut hints & context-aware ⌘1-9 quick jump ([#49](https://github.com/vaayne/mori/pull/49))
- Sidebar redesign — spacing, typography, and visual hierarchy ([#50](https://github.com/vaayne/mori/pull/50))

**Full Changelog**: [v0.3.2...v0.3.3](https://github.com/vaayne/mori/compare/v0.3.2...v0.3.3)

## [0.3.2] - 2026-04-03

### ✨ Features

- Add "Remote Connect" menu item in the app menu for quick remote host access
- Add project rename from sidebar context menu
- Skip git polling for non-git directories, show house icon, and display tool install hints
- Improve onboarding with default Home workspace and tool detection

### 🐛 Bug Fixes

- Non-git directories no longer show "main" branch; deduplicate worktree rows

### ♻️ Refactoring

- Open project now goes directly to folder picker (skips intermediate dialog)

**Full Changelog**: [v0.3.1...v0.3.2](https://github.com/vaayne/mori/compare/v0.3.1...v0.3.2)

## [0.3.1] - 2026-04-03

### 📝 Documentation

- Add practical GitHub issue templates for bug reports and feature requests

**Full Changelog**: [v0.3.0...v0.3.1](https://github.com/vaayne/mori/compare/v0.3.0...v0.3.1)

## [0.3.0] - 2026-04-02

### ✨ Features

- **Customizable keyboard shortcuts**: remap, unassign, or reset all Mori app shortcuts via Settings > Keyboard ([#37](https://github.com/vaayne/mori/pull/37))
- Shortcut conflict detection with locked system shortcuts (blocked) and configurable shortcuts (warn with override option)
- Sparse JSON persistence for keyboard shortcut overrides (`keybindings.json`)
- **Fuzzy search for command palette + Cmd+P project switcher** ([#34](https://github.com/vaayne/mori/pull/34), [#35](https://github.com/vaayne/mori/pull/35), [#38](https://github.com/vaayne/mori/pull/38))

### 🐛 Bug Fixes

- Make agent bridge pane-aware
- Show update status pill in titlebar top-right

**Full Changelog**: [v0.2.2...v0.3.0](https://github.com/vaayne/mori/compare/v0.2.2...v0.3.0)

## [0.2.2] - 2026-03-31

### 🐛 Bug Fixes

- Fix "Check for Updates" doing nothing — Sparkle 2.9 rejected duplicate XPC services in both `Contents/XPCServices/` and inside `Sparkle.framework`, causing `SPUUpdater.start()` to silently fail

**Full Changelog**: [v0.2.1...v0.2.2](https://github.com/vaayne/mori/compare/v0.2.1...v0.2.2)

## [0.2.1] - 2026-03-31

### ✨ Features

- **MoriRemote**: iOS app with SSH terminal for remote access ([#30](https://github.com/vaayne/mori/pull/30))

### 🐛 Bug Fixes

- Fix main-thread assertion crash in `NotificationManager` by switching `UNUserNotificationCenter` APIs from completion handlers to async/await

### 📦 Dependencies

- Bump `actions/checkout` from v5 to v6
- Bump `upload-artifact` and `download-artifact` from v5 to v7 for Node.js 24 support

**Full Changelog**: [v0.2.0...v0.2.1](https://github.com/vaayne/mori/compare/v0.2.0...v0.2.1)

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
- Added a `MoriRemote` iOS spike app target that connects over SSH, attaches to tmux control mode, renders pane output with Ghostty, and sends keyboard input back through tmux

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

[Unreleased]: https://github.com/vaayne/mori/compare/v0.3.7...HEAD
[0.3.7]: https://github.com/vaayne/mori/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/vaayne/mori/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/vaayne/mori/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/vaayne/mori/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/vaayne/mori/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/vaayne/mori/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/vaayne/mori/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/vaayne/mori/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/vaayne/mori/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/vaayne/mori/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/vaayne/mori/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/vaayne/mori/releases/tag/v0.1.3
[0.1.2]: https://github.com/vaayne/mori/releases/tag/v0.1.2
[0.1.1]: https://github.com/vaayne/mori/releases/tag/v0.1.1
[0.1.0]: https://github.com/vaayne/mori/releases/tag/v0.1.0
