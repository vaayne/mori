# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### ✨ Features

- Release app bundles now embed the `mori` CLI to support Homebrew cask installs

### 🐛 Bug Fixes

- Tagged releases now stamp Mori.app with the actual release version instead of a hardcoded app version

### 📝 Documentation

- Added Homebrew tap install instructions to the English and Chinese READMEs

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

[Unreleased]: https://github.com/vaayne/mori/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/vaayne/mori/releases/tag/v0.1.1
[0.1.0]: https://github.com/vaayne/mori/releases/tag/v0.1.0
