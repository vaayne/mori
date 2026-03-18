# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Project Scaffolding & Data Models -- COMPLETE

### Summary

All 6 tasks implemented and committed:

| Task | Description | Commit |
|------|-------------|--------|
| 1.1 | Root Package.swift with AppDelegate lifecycle, macOS 14 target | `c9d2d68` |
| 1.2 | MoriCore SPM package with all model structs and enums | `77d3add` |
| 1.3 | MoriPersistence SPM package with GRDB, records, repositories, migrations | `6eaa625` |
| 1.4 | AppState @Observable class with derived computed properties | `3f2408a` |
| 1.5 | Wire SPM packages into root project (verified full build) | `9d7ff31` |
| 1.6 | Unit tests: 67 model assertions + 42 GRDB round-trip assertions | `9c16993` |

### Key Decisions

- **swift-tools-version: 6.0** for all packages (Swift 6 strict concurrency)
- **Executable test targets** instead of XCTest/swift-testing -- the environment has Command Line Tools only (no Xcode), so XCTest and Testing frameworks are unavailable. Tests are structured as executable targets with a lightweight assertion helper. They can be upgraded to swift-testing once Xcode is installed.
- **SQL trace disabled** in AppDatabase configuration (was too noisy for test output). Can be re-enabled conditionally for debugging.
- **GRDB records** use String-typed UUID columns and String-typed enum columns with manual toModel()/from init conversion. This avoids GRDB-specific protocol requirements on the core models.

### Project Structure

```
Package.swift                              (root app executable)
Sources/Mori/App/
  main.swift                               (NSApplication entry point)
  AppDelegate.swift                        (AppKit lifecycle, TODO stubs)
Packages/
  MoriCore/
    Package.swift
    Sources/MoriCore/
      Models/
        Project.swift, Worktree.swift, RuntimeWindow.swift,
        RuntimePane.swift, UIState.swift,
        AgentState.swift, WorktreeStatus.swift, SidebarMode.swift,
        WindowBadge.swift, AlertState.swift
      State/
        AppState.swift
    Tests/MoriCoreTests/
      main.swift, Assert.swift
  MoriPersistence/
    Package.swift
    Sources/MoriPersistence/
      Database.swift
      Records/
        ProjectRecord.swift, WorktreeRecord.swift, UIStateRecord.swift
      Repositories/
        ProjectRepository.swift, WorktreeRepository.swift, UIStateRepository.swift
    Tests/MoriPersistenceTests/
      main.swift, Assert.swift
```

### What's Ready for Phase 2

- All 5 core data models (Project, Worktree, RuntimeWindow, RuntimePane, UIState) with full PRD fields
- SQLite persistence layer with GRDB (WAL mode, foreign keys, migrations)
- AppState @Observable class ready for UI binding
- Project builds cleanly with `swift build` from root
- All tests pass with `swift run MoriCoreTests` and `swift run MoriPersistenceTests`

### Blockers / Notes for Next Phase

- No Xcode installed -- only Command Line Tools. This is fine for SPM-based development but will matter for Phase 4 (libghostty XCFramework) and final .xcodeproj generation.
- The AppDelegate has TODO stubs for Phase 3 (main window) and Phase 5 (state persistence on quit).

## Phase 2: Tmux Backend -- COMPLETE

### Summary

All 7 tasks implemented and committed:

| Task | Description | Commit |
|------|-------------|--------|
| 2.1 | MoriTmux SPM package with TmuxCommandRunner (Process-based, PATH resolution) | `b37667a` |
| 2.2 | TmuxParser for list-sessions/windows/panes -F output with tab delimiters | `6bd9f96` |
| 2.3 | TmuxBackend actor with scanAll, createSession, selectWindow, killSession, isAvailable + runtime models | `2bb19ac` |
| 2.4 | TmuxControlling protocol with full PRD surface, Phase 1 subset implemented | `08c33d0` |
| 2.5 | Session naming ws::\<project\>::\<worktree\> with slugify and discovery | `e42f5ee` |
| 2.6 | Polling: 5s background timer with diff + user-action-triggered refreshNow() (in TmuxBackend) | `2bb19ac` |
| 2.7 | Unit tests: 95 assertions for TmuxParser + SessionNaming | `e5f4ad9` |

### Key Decisions

- **Tab delimiter** in tmux -F format strings to avoid collisions with colons/spaces in session names and paths
- **Separate runtime models** (TmuxSession, TmuxWindow, TmuxPane) from MoriCore models -- mapping happens at a higher layer
- **Actor isolation** for TmuxBackend and TmuxCommandRunner -- all tmux operations are async and thread-safe
- **Polling built into TmuxBackend** -- startPolling()/stopPolling() with 5s Task.sleep loop, pollOnce() diffs against lastSnapshot, onChange callback for state updates
- **No MoriCore dependency** -- MoriTmux is fully standalone, keeping the dependency graph clean
- **Binary path caching** -- tmux path resolved once and cached in TmuxCommandRunner actor state

### Package Structure

```
Packages/MoriTmux/
  Package.swift
  Sources/MoriTmux/
    TmuxCommandRunner.swift    (Process-based tmux execution, PATH resolution)
    TmuxParser.swift           (parse -F format output for sessions/windows/panes)
    TmuxBackend.swift          (actor: scanning, lifecycle, polling)
    TmuxControlling.swift      (protocol with full PRD surface + defaults)
    TmuxSession.swift          (runtime model with Mori session detection)
    TmuxWindow.swift           (runtime model for parsed windows)
    TmuxPane.swift             (runtime model for parsed panes)
    SessionNaming.swift        (ws:: naming convention, slugify, parse)
  Tests/MoriTmuxTests/
    main.swift                 (95 assertions)
    Assert.swift               (lightweight test helper)
```

### What's Ready for Phase 3

- TmuxBackend is ready to be used by WorkspaceManager for session lifecycle
- SessionNaming.sessionName(project:worktree:) generates names for new sessions
- scanAll() returns full runtime tree that can be mapped to MoriCore models
- Polling can be started/stopped and onChange callback wired to AppState updates
- Root Package.swift already includes MoriTmux dependency
- All tests pass with `swift run MoriTmuxTests` (95 assertions)
- Full project builds cleanly with `swift build` from root

### Blockers / Notes for Next Phase

- TmuxBackend.scanAll() iterates sessions sequentially (one list-windows call per session). This is fine for Phase 1 but could be optimized with concurrent calls if session count grows.
- The onChange callback is @Sendable but runs on the TmuxBackend actor; Phase 3 WorkspaceManager will need to dispatch updates to main actor for UI.

## Phase 3: AppKit Shell & Sidebar UI -- COMPLETE

### Summary

All 8 tasks implemented and committed:

| Task | Description | Commit |
|------|-------------|--------|
| 3.1 | MainWindowController with toolbar and "Add Project" button | `c1f6bc1` |
| 3.2 | RootSplitViewController with 3-pane split (rail/sidebar/content) | `5732367` |
| 3.3 | MoriUI SPM package with ProjectRailView (SwiftUI) | `5e85e63` |
| 3.4 | WorktreeSidebarView, WorktreeRowView, WindowRowView (SwiftUI) | `0930788` |
| 3.5 | NSHostingControllers wiring AppState into SwiftUI views | `b93cbe6` |
| 3.6 | Add Project via NSOpenPanel (creates Project + Worktree + tmux session) | `f0f902d` |
| 3.7 | WorkspaceManager coordinating project/worktree/window selection | `c51f263` |
| 3.8 | Single instance enforcement via NSRunningApplication check | `f0f902d` |

### Key Decisions

- **@MainActor on AppState** -- Added per reviewer note from Phase 1; ensures all state mutations happen on the main thread for UI safety
- **@MainActor on AppDelegate** -- Required by Swift 6 strict concurrency since AppDelegate accesses MainActor-isolated types (NSOpenPanel, AppState, etc.)
- **WorkspaceManager in app target** -- Lives in `Sources/Mori/App/` rather than MoriCore to avoid circular SPM dependencies (it needs MoriPersistence + MoriTmux + MoriCore)
- **Callback-based SwiftUI wiring** -- ProjectRailView and WorktreeSidebarView use closure callbacks (`onSelect`, `onSelectWorktree`, `onSelectWindow`) rather than directly mutating AppState, keeping views pure and testable
- **NSHostingController with @Bindable** -- `ProjectRailContentView` and `WorktreeSidebarContentView` are thin wrapper views that bridge `@Observable AppState` into the SwiftUI views via `@Bindable`
- **PlaceholderContentViewController** -- Simple "Select a worktree" label as content area placeholder until Phase 4 terminal integration

### Project Structure (new/modified files)

```
Package.swift                                     (updated: added MoriUI dependency)
Sources/Mori/App/
  AppDelegate.swift                               (fully wired: DB, repos, state, window, tmux polling)
  MainWindowController.swift                      (NSWindowController with toolbar)
  RootSplitViewController.swift                   (NSSplitViewController, 3 panes)
  PlaceholderContentViewController.swift          (content placeholder)
  HostingControllers.swift                        (NSHostingController wrappers for SwiftUI views)
  WorkspaceManager.swift                          (coordinates state/persistence/tmux)
Packages/
  MoriCore/Sources/MoriCore/State/
    AppState.swift                                (added @MainActor)
  MoriUI/
    Package.swift                                 (new package, depends on MoriCore)
    Sources/MoriUI/
      ProjectRailView.swift                       (project rail with circle icons)
      WorktreeSidebarView.swift                   (worktree sections + window rows)
      WorktreeRowView.swift                       (worktree row with status indicator)
      WindowRowView.swift                         (window row with active indicator)
```

### What's Ready for Phase 4

- Full 3-pane window layout with SwiftUI sidebar views bound to @Observable AppState
- WorkspaceManager.selectWorktree() ensures tmux session exists and refreshes runtime state
- RootSplitViewController.replaceContentController() is ready for swapping in TerminalAreaViewController
- WorkspaceManager.refreshRuntimeState() maps tmux sessions/windows to RuntimeWindow models
- Tmux polling is active with onChange callback dispatching to main actor
- "Add Project" flow creates Project + Worktree + tmux session end-to-end
- All existing tests pass (67 model + 42 GRDB + 95 tmux = 204 assertions)
- Project builds cleanly with `swift build`, zero errors, zero warnings

### Blockers / Notes for Next Phase

- Content area shows placeholder; Phase 4 replaces it with TerminalAreaViewController hosting libghostty
- Window title updates on addProject but not yet on project selection change (minor; can be wired in Phase 5)
- AppDelegate.applicationWillTerminate still has TODO stub for Phase 5 state persistence on quit
- No Xcode installed -- Command Line Tools only. Phase 4 may need Xcode for libghostty XCFramework integration.

## Phase 4: Terminal Integration -- COMPLETE

### Summary

All 8 tasks implemented and committed:

| Task | Description | Commit |
|------|-------------|--------|
| 4.0 | API verification spike: libghostty-spm unavailable (no Xcode/XCFramework), PTY fallback chosen | `26fa144` |
| 4.1 | MoriTerminal SPM package with TerminalHost protocol + NativeTerminalAdapter | `26fa144` |
| 4.2 | NativeTerminalAdapter: forkpty(), execv, ANSI parser, keyboard forwarding, copy/paste | `26fa144` |
| 4.3 | TerminalAreaViewController hosting terminal surfaces with resize propagation | `2561b08` |
| 4.4 | Worktree selection wired to terminal via WorkspaceManager.onTerminalSwitch callback | `781ea76` |
| 4.5 | Focus: terminal becomes first responder on click, worktree switch, and window switch | `781ea76` |
| 4.6 | LRU TerminalSurfaceCache (max 3 surfaces, keyed by session name, evicts via destroySurface) | `38ff364` |
| 4.7 | N/A -- ghostty_app_tick not needed; PTY adapter uses GCD DispatchSourceRead for async I/O | `781ea76` |

### Key Decisions

- **PTY fallback instead of libghostty** -- Environment has Command Line Tools only (no Xcode), so the libghostty-spm XCFramework cannot be used. Implemented NativeTerminalAdapter using forkpty()/execv() with a real pseudo-terminal. The TerminalHost protocol abstracts the backend, so GhosttyAdapter can be added later as a drop-in replacement.
- **execv instead of execl** -- Swift 6 strict concurrency marks variadic C functions as unavailable. Used execv() with explicit argument array.
- **GCD DispatchSourceRead for PTY I/O** -- More efficient than FileHandle.readabilityHandler; fires on the global queue with main-thread dispatch for UI updates.
- **ANSI parser with SGR support** -- Handles 8/16/256/truecolor SGR codes, cursor movement, clear screen/line, OSC title sequences, carriage return, bell. Sufficient for tmux rendering.
- **Shell-escaped tmux attach command** -- Terminal runs `tmux attach-session -t '<name>' || tmux new-session -s '<name>'` with proper shell escaping of session names.
- **Callback-based terminal switching** -- WorkspaceManager.onTerminalSwitch callback decouples workspace logic from terminal view controller. AppDelegate wires the two together.

### Project Structure (new/modified files)

```
Package.swift                                     (updated: added MoriTerminal dependency)
Sources/Mori/App/
  AppDelegate.swift                               (updated: wires TerminalAreaViewController, cleanup)
  WorkspaceManager.swift                          (updated: onTerminalSwitch callback)
  TerminalAreaViewController.swift                (new: hosts terminal surfaces, LRU cache)
Packages/
  MoriTerminal/
    Package.swift                                 (new package, no external dependencies)
    Sources/MoriTerminal/
      TerminalHost.swift                          (protocol: createSurface, destroySurface, resize, focus)
      NativeTerminalAdapter.swift                 (PTY-based terminal: forkpty, keyboard, copy/paste)
      ANSIParser.swift                            (incremental ANSI escape sequence parser)
      TerminalSurfaceCache.swift                  (LRU cache, max 3 surfaces, keyed by session name)
```

### What's Ready for Phase 5

- Full terminal integration: selecting a worktree creates a PTY running tmux attach-session
- LRU cache keeps up to 3 terminal surfaces alive across worktree switches
- Focus management: terminal becomes first responder on click and selection change
- Keyboard input forwarded to PTY (including Ctrl+key, arrow keys, special keys)
- Copy/paste via Cmd+C/V, select-all via Cmd+A
- ANSI color rendering (8/16/256/truecolor) for tmux output
- Surface cleanup on app termination
- All 204 existing tests pass (67 model + 42 GRDB + 95 tmux)
- Project builds cleanly with `swift build`, zero errors, zero warnings

### Blockers / Notes for Next Phase

- PlaceholderContentViewController is no longer used (can be removed or kept for empty state)
- Terminal rendering is basic (NSTextView-based, no cursor positioning grid). Sufficient for tmux session management but not a full VT100 emulator. Upgrading to libghostty when Xcode is available will provide proper terminal emulation.
- Window title still only updates on addProject, not on project selection change (Phase 5)
- AppDelegate.applicationWillTerminate has surface cleanup but still needs Phase 5 UI state persistence
