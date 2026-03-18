# Handoff

## Goal

Build Mori — a macOS native workspace terminal organized around Projects and Worktrees, with tmux as the persistent runtime backend and agent-aware automation.

## Progress

**Phases 1–3 COMPLETE. UI polish pass done. Theme sync session done.**

- **Phase 1** (30 tasks): Project scaffolding, tmux backend, AppKit shell, PTY terminal, state restoration
- **Phase 2** (47 tasks): MoriGit package, create/remove worktree, templates, git status polling, badges, unread tracking, command palette
- **Phase 3** (36 tasks): Window tags, agent detection, richer badges, notifications, CLI/IPC, automation hooks
- **UI Polish** (6 commits): Design tokens, accessibility, live theme, 2-column sidebar redesign
- **Theme Sync** (4 commits): Settings persistence, tmux theme sync, sidebar/window chrome theme, settings page rewrite

**553 test assertions** passing (297 core + 175 tmux + 42 persistence + 39 IPC). Zero build warnings under Swift 6 strict concurrency.

### Theme Sync (latest session)

1. **Settings Persistence Fix** — Switched from `UserDefaults.standard` (unreliable under `swift run`) to `UserDefaults(suiteName: "com.mori.app")` for stable persistence across rebuilds
2. **Settings View Reactivity** — Wrapped `TerminalSettingsView` in `SettingsWindowContent` with `@State` ownership so SwiftUI properly tracks changes (theme preview, font size, etc. update in real time)
3. **tmux Theme Sync** — `TmuxThemeApplicator` now separates session options (`-g`) from window options (`-gw`), applies to both global defaults and existing sessions, added `setWindowOption` to `TmuxBackend`/`TmuxControlling`
4. **Sidebar Theme Sync** — Sidebar background and color scheme match the terminal theme; `AppState.terminalSettings` provides reactive updates; `TerminalTheme.isDark` computed via ITU-R BT.709 luminance
5. **Window Chrome Sync** — `window.appearance` set to `.darkAqua`/`.aqua` based on theme; toolbar button and titlebar controls visible in all theme/system mode combinations
6. **Sidebar Appearance Override** — `SidebarHostingController.updateAppearance()` sets NSView-level appearance; `.preferredColorScheme` always explicit (`.dark`/`.light`, never `nil`)
7. **Settings Page Rewrite** — Replaced generic `Form/.grouped` with theme-aware custom layout:
   - Theme picker: visual grid with mini terminal previews (background, `Aa` text, ANSI traffic-light dots)
   - Cursor picker: visual block/underline/bar previews in theme cursor color
   - Settings window: transparent titlebar, background and appearance update live on theme change
   - All colors derived from current theme (background, foreground, accent from ANSI blue)
8. **Shared Color Helper** — Promoted `nsColor(hex:)` to package-internal in `DesignTokens.swift` (was duplicated as private)

### UI Polish (prior session)

1. **Design Token System** — `MoriTokens` enum in MoriUI: semantic colors, 7-step spacing scale, radii, icon sizes, typography presets, opacity levels. All 5 view files migrated.
2. **Accessibility** — `.accessibilityLabel()` on all badge icons, status dots, indicators across WorktreeRowView and WindowRowView
3. **Hover States** — `onHover` + highlight background on WorktreeRowView and WindowRowView
4. **Window Restoration** — `setFrameAutosaveName("MoriMainWindow")` persists position/size
5. **Live Theme Update** — SwiftTermAdapter nudges frame size (±1px SIGWINCH) to force tmux redraw after theme change
6. **2-Column Sidebar (Option B)** — Replaced 3-column (rail | sidebar | terminal) with 2-column layout
7. **Minimal Titlebar** — Hidden title visibility, transparent titlebar, compact toolbar with sidebar toggle
8. **Title Sync** — Window title updates on project/worktree/window switch
9. **Command Palette** — Extracted `Layout` enum (15 constants), added keyboard shortcut hints (⌘R, ⌘O)

### Phase 3 features delivered

1. **Window Semantic Tags** — `WindowTag` enum (shell/editor/agent/server/logs/tests), auto-inferred from window names, SF Symbol icons in sidebar, `tag:` prefix filtering in command palette
2. **Agent State Detection** — `PaneStateDetector` with pattern matching (waiting/error/completed/running), `capture-pane` scoped to agent-tagged windows only, 30s long-running threshold
3. **Worktree Status Enhancements** — Per-window `isRunning`/`isLongRunning`/`agentState`/`lastExitCode`, richer badge icons with colors, worktree-level aggregation with per-poll reset
4. **Notifications** — `NotificationDebouncer` (pure, testable in MoriCore), macOS native notifications for agent-waiting/error/long-running-complete, dock badge for unread count, click-to-focus
5. **CLI / IPC** — `MoriIPC` package with Network.framework Unix socket (`~/Library/Application Support/Mori/mori.sock`), `ws` CLI executable (6 subcommands: project list, worktree create, focus, send, new-window, open), `IPCHandler` dispatching to WorkspaceManager
6. **Automation Hooks** — `.mori/hooks.json` per-project config, 6 lifecycle events (onWorktreeCreate/Focus/Close, onWindowCreate/Focus/Close), shell + tmuxSend actions, 60s cache TTL, 10s shell timeout

## Key Decisions

- **2-column layout over 3-column** — Merged project rail into sidebar as flat sections; saves horizontal space, follows Tower/Fork pattern
- **Design tokens in MoriUI** — `MoriTokens` enum with nested enums (Color, Spacing, Radius, Icon, Size, Font, Opacity); SwiftUI-specific, no MoriCore dependency
- **Sidebar toggle in titlebar toolbar** — Compact toolbar with single button; always accessible even when sidebar collapsed
- **Window appearance from theme** — `window.appearance` set to `.darkAqua`/`.aqua` based on `TerminalTheme.isDark`; ensures toolbar and titlebar controls are visible regardless of system appearance
- **Settings persistence via suite** — `UserDefaults(suiteName: "com.mori.app")` instead of `.standard`; stable across `swift run` rebuilds without bundle identifier
- **Settings @State wrapper** — `SettingsWindowContent` wraps `TerminalSettingsView` with `@State` ownership; plain `Binding` on `NSObject` property didn't trigger SwiftUI re-renders
- **terminalSettings in AppState** — Makes theme observable for sidebar; sidebar reads `appState.terminalSettings.theme` reactively
- **TerminalTheme.isDark** — ITU-R BT.709 relative luminance on background hex; threshold at 0.5
- **setWindowOption (-gw)** — tmux window options (`window-style`, `pane-border-style`) need `-gw` flag, distinct from session options (`-g`)
- **UNUserNotificationCenter guarded** — All 4 call sites check `Bundle.main.bundleIdentifier != nil` for swift run compatibility
- **DetectedAgentState in MoriTmux** — String raw values mirroring MoriCore `AgentState` to avoid cross-package dependency
- **Agent detection scoped to `.agent`-tagged windows only** — `capture-pane` is expensive; non-agent windows derive state from `currentCommand` field alone
- **NotificationDebouncer is pure logic in MoriCore** — Injectable `Date`, no UNUserNotificationCenter dependency, fully testable
- **IPC via Network.framework** — `NWListener`/`NWConnection` over Unix domain socket; Swift concurrency friendly, no XPC needed
- **Hooks are fire-and-forget** — detached tasks with 10s timeout; config cached 60s per project

## Current State

The app builds and runs via `mise run dev`. It now includes all Phase 1–3 features plus full theme sync:
- 2-column window (sidebar | terminal) with SwiftTerm
- All projects as flat sidebar sections with two-line worktree rows
- Sidebar, terminal, window chrome, and settings all follow the terminal theme
- Minimal titlebar with sidebar toggle, title syncs on selection
- Design token system with consistent styling across all views
- Git status badges, hover states, accessibility labels
- Window semantic tags with icons and filtering
- Agent state detection with richer badges (running/error/waiting/longRunning)
- macOS notifications + dock badge for unread count
- `ws` CLI for scripting (communicates via Unix socket)
- Per-project automation hooks via `.mori/hooks.json`
- Theme-aware settings page with visual theme/cursor pickers
- Settings persist across `swift run` rebuilds

### Architecture

```
Sources/Mori/App/          — AppDelegate, MainWindowController, RootSplitViewController (2-pane),
                             TerminalAreaViewController, WorkspaceManager,
                             GitStatusCoordinator, UnreadTracker, TemplateApplicator,
                             NotificationManager, IPCHandler, HookRunner,
                             CommandPaletteController, SidebarHostingController,
                             TmuxThemeApplicator, SettingsWindowContent
Sources/WS/               — ws CLI executable (swift-argument-parser)
Packages/MoriCore/         — Models, AppState (+ terminalSettings), WindowTag, NotificationDebouncer, HookConfig
Packages/MoriPersistence/  — GRDB/SQLite (WAL), Records, Repositories
Packages/MoriTmux/         — TmuxBackend (actor), TmuxParser, PaneStateDetector, PaneState
Packages/MoriGit/          — GitBackend (actor), GitCommandRunner, GitStatusParser
Packages/MoriTerminal/     — TerminalHost protocol, SwiftTermAdapter, NativeTerminalAdapter
Packages/MoriUI/           — DesignTokens (+ nsColor helper), WorktreeSidebarView, WorktreeRowView,
                             WindowRowView, ProjectRailView (unused), TerminalSettingsView
Packages/MoriIPC/          — IPCServer (actor), IPCClient, IPCProtocol
```

### Build & Test

```bash
mise run build            # Debug build
mise run dev              # Build + run
mise run test             # All tests (parallel): core, tmux, persistence, ipc
mise run test:core        # MoriCore (297 assertions)
mise run test:tmux        # MoriTmux (175 assertions)
mise run test:persistence # MoriPersistence (42 assertions)
mise run test:ipc         # MoriIPC (39 assertions)
```

## Blockers / Gotchas

- **`clearUnread` badge reset** — Briefly resets running windows to `.idle` until next 5s poll self-corrects
- **`"done"` substring match** — `matchesCompleted` in PaneStateDetector has false-positive risk (matches "abandoned", etc.)
- **`sendKeys` always appends Enter** — No opt-out flag for partial input or Ctrl sequences
- **`NSApp.activate(ignoringOtherApps:)` deprecated** — Should use `NSApp.activate()` on macOS 14+
- **`previousBadges` not pruned** — Dictionary grows when windows are removed (minor, long sessions only)
- **`onWindowCreate` hook** — `MORI_WINDOW` env var is empty (window name not captured from createWindow)
- **AlertState.none ambiguity** — `.none` case collides with `Optional.none`; deferred rename to avoid GRDB migration
- **ProjectRailView unused** — Still exists in MoriUI but no longer wired; can be removed or repurposed
- **Session folders** — Phase 1: `.agents/sessions/2026-03-18-phase1-foundation/`, Phase 2: `.agents/sessions/2026-03-18-phase2-product/`, Phase 3: `.agents/sessions/2026-03-18-phase3-agent-first/`

## Next Steps

1. **Manual testing** — Run `mise run dev` and exercise full UI: project switching, worktree creation, sidebar collapse/expand, theme changes, command palette
2. **Remove ProjectRailView** — Dead code after Option B migration; clean up MoriUI package
3. **Polish items** — Fix the minor issues listed in Blockers/Gotchas above
4. **Phase 4 planning** — PRD has Phase 4 scope: URL scheme (`mori://`), Finder integration, Services menu
5. **Documentation** — Update README with `ws` CLI usage and `.mori/hooks.json` format
