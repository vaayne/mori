# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
mise run build           # Debug build (swift build | xcbeautify)
mise run build:release   # Release build
mise run dev             # Build + run the app
mise run test            # All tests (parallel across packages)
mise run test:core       # MoriCore tests only
mise run test:persistence # MoriPersistence tests only
mise run test:tmux       # MoriTmux tests only
mise run clean           # Remove .build and .derived-data
```

Tests are executable targets (no Xcode/XCTest available), run via `swift run <TestTarget>` from each package directory. Each test target has a lightweight assertion helper in `Assert.swift`.

## Architecture

Mori is a macOS native workspace terminal. It organizes development around **Projects** (git repos) and **Worktrees** (branches), using **tmux** as the persistent runtime backend and a **PTY-based terminal** for rendering.

### Package Dependency Graph

```
App Target (Sources/Mori/)
  ├─ MoriCore       — Models + @Observable AppState (no I/O)
  ├─ MoriPersistence — GRDB/SQLite repositories (depends on MoriCore)
  ├─ MoriTmux       — tmux CLI integration via actors (no deps on other packages)
  ├─ MoriTerminal   — libghostty GPU terminal + PTY fallback (depends on GhosttyKit XCFramework)
  └─ MoriUI         — SwiftUI sidebar views (depends on MoriCore)
```

`WorkspaceManager` lives in the app target (not a package) because it coordinates across MoriPersistence, MoriTmux, and MoriCore — putting it in any package would create circular dependencies.

### Data Flow

```
User action → WorkspaceManager → AppState (@Observable) → SwiftUI re-render
                ↓                       ↓
         TmuxBackend (actor)    UIStateRepository (SQLite)
```

**AppState** (`@MainActor @Observable`) is the single source of truth for UI. It holds projects, worktrees, runtime windows/panes, and UI selection state. SwiftUI views bind to it via `@Bindable` in hosting controllers.

**TmuxBackend** (actor) polls tmux every 5 seconds via CLI (`tmux list-sessions/windows/panes -F`), parses with tab-delimited format strings, and notifies WorkspaceManager of changes.

### UI Structure

AppKit shell with SwiftUI leaf views:

```
NSSplitViewController (3 columns)
  ├─ NSHostingController → ProjectRailView      (60-80pt, SwiftUI)
  ├─ NSHostingController → WorktreeSidebarView   (200pt min, SwiftUI)
  └─ TerminalAreaViewController                  (400pt min, AppKit)
       └─ GhosttySurfaceView (libghostty Metal rendering)
```

### Key Mapping: Worktree → tmux

Each worktree binds to exactly one tmux session named `<project-short-name>/<branch-slug>` (e.g. `mori/main`, `api/auth-flow`). Projects have a user-editable `shortName` (auto-generated from dir name). Common branch prefixes (`feature/`, `fix/`, etc.) are stripped. The terminal surface runs `tmux attach-session -t <name>`. An LRU cache (max 3) keeps recently-used surfaces alive to avoid recreate latency on switch.

### Terminal Rendering

`TerminalHost` protocol abstracts terminal backends. Primary implementation is `GhosttyAdapter` (libghostty — GPU-accelerated Metal rendering, native mouse/scroll/paste/IME). `NativeTerminalAdapter` (PTY via `forkpty()`) is kept as an emergency fallback. The GhosttyKit XCFramework is built from Ghostty source via `mise run build:ghostty` (requires Zig 0.15.2 + Xcode).

### Persistence

GRDB.swift with SQLite (WAL mode) at `~/Library/Application Support/Mori/mori.sqlite`. Three tables: `project`, `worktree`, `uiState`. Record types bridge between GRDB and domain models via `toModel()`/`init(from:)`.

## Key Conventions

- **Swift 6 strict concurrency**: All packages use swift-tools-version 6.0. UI code is `@MainActor`. tmux integration uses actors. GCD handlers use `WeakSendableRef` to bridge to `@MainActor`.
- **macOS 14+ (Sonoma)**: Required for `@Observable` macro.
- **AppKit-first**: Terminal embedding and window management use AppKit. SwiftUI is only for sidebar list views.
- **SwiftUI views are pure**: They take data + callbacks as parameters (no direct AppState dependency). Hosting controllers bridge the gap.
- **tmux session naming**: `<shortName>/<branchSlug>` via `SessionNaming.sessionName(projectShortName:worktree:)`. Common branch prefixes (feature/, fix/, etc.) are stripped automatically. Never assume session names are unique — use tmux session IDs internally.
- **No XCTest**: Tests are executable targets with a custom `assertEqual`/`assertTrue` helper. Run them as executables, not via `swift test`.
