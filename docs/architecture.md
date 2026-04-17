# Architecture

Mori is a macOS native workspace terminal. It organizes development around **Projects** (git repos) and **Worktrees** (branches), using **tmux** as the persistent runtime backend and a **PTY-based terminal** for rendering.

## Package Dependency Graph

```
App Target (Sources/Mori/)
  ├─ MoriCore       — Models + @Observable AppState (no I/O)
  ├─ MoriPersistence — JSON file repositories (depends on MoriCore)
  ├─ MoriTmux       — tmux CLI integration via actors (no deps on other packages)
  ├─ MoriTerminal   — libghostty GPU terminal + PTY fallback (depends on GhosttyKit XCFramework)
  ├─ MoriUI         — SwiftUI sidebar views (depends on MoriCore)
  ├─ MoriGit        — Git CLI integration via actors (standalone)
  └─ MoriIPC        — Unix socket IPC protocol + server/client
```

`WorkspaceManager` lives in the app target (not a package) because it coordinates across MoriPersistence, MoriTmux, MoriGit, and MoriCore — putting it in any package would create circular dependencies.

## Data Flow

```
User action → WorkspaceManager → AppState (@Observable) → SwiftUI re-render
                ↓                       ↓
         TmuxBackend (actor)    JSON file persistence
```

**AppState** (`@MainActor @Observable`) is the single source of truth for UI. It holds projects, worktrees, runtime windows/panes, and UI selection state. SwiftUI views bind to it via `@Bindable` in hosting controllers.

**TmuxBackend** (actor) polls tmux every 5 seconds via CLI (`tmux list-sessions/windows/panes -F`), parses with tab-delimited format strings, and notifies WorkspaceManager of changes.

Projects can execute in two locations:
- `local` — git/tmux run on the host machine
- `ssh` — git/tmux run on a remote host via SSH while UI remains local

## UI Structure

AppKit shell with SwiftUI leaf views:

```
NSSplitViewController (3 columns)
  ├─ NSHostingController → ProjectRailView      (60-80pt, SwiftUI)
  ├─ NSHostingController → WorktreeSidebarView   (200pt min, SwiftUI)
  └─ TerminalAreaViewController                  (400pt min, AppKit)
       └─ GhosttySurfaceView (libghostty Metal rendering)
```

## Concept → tmux Mapping

Mori's four UI concepts map 1-to-1 onto tmux's hierarchy:

```
Mori concept          tmux entity          naming / notes
─────────────────     ──────────────────   ──────────────────────────────────────
Project               (no direct entity)   owns N worktrees; has a short name
Worktree              session              "<project-shortname>/<branch-slug>"
Window                window               user-editable name, e.g. "shell", "logs"
Pane                  pane                 tmux pane ID, e.g. %3
```

**Session naming** — `shortName` is auto-generated from the repo directory name and is user-editable. Branch slugs strip common prefixes (`feature/`, `fix/`, `chore/`, etc.) so `feature/auth-flow` becomes `auth-flow`. Example: a project named `api` on branch `feature/auth-flow` → session `api/auth-flow`.

**Attachment** — the terminal surface runs `tmux attach-session -t <session-name>`. An LRU cache (max 3) keeps recently-used Ghostty surfaces alive to avoid recreate latency on worktree switch.

**Environment variables** — Mori injects `MORI_PROJECT`, `MORI_WORKTREE`, `MORI_WINDOW`, and `MORI_PANE_ID` into every pane's environment so CLI tools and agents can resolve their own address without arguments.

## Terminal Rendering

`TerminalHost` protocol abstracts terminal backends. Primary implementation is `GhosttyAdapter` (libghostty — GPU-accelerated Metal rendering, native mouse/scroll/paste/IME). `NativeTerminalAdapter` (PTY via `forkpty()`) is kept as an emergency fallback. The GhosttyKit XCFramework is built from Ghostty source via `mise run build:ghostty` (requires Zig 0.15.2 + Xcode).

## Persistence

JSON files at `~/Library/Application Support/Mori/`. Record types bridge between JSON and domain models.
