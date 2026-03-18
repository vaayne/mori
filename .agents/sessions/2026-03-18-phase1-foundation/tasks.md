# Tasks: Mori Phase 1 — Foundation

## Phase 1: Project Scaffolding & Data Models

- [x] 1.1 — Create Xcode project with AppDelegate lifecycle, macOS 14 target (`Mori.xcodeproj`, `Mori/App/AppDelegate.swift`)
- [x] 1.2 — Create `MoriCore` SPM package with model structs: Project, Worktree, RuntimeWindow, RuntimePane, UIState, enums (AgentState, WorktreeStatus, SidebarMode, WindowBadge)
- [x] 1.3 — Create `MoriPersistence` SPM package with GRDB: Database.swift, ProjectRepository, WorktreeRepository, UIStateRepository, Migrations
- [x] 1.4 — Create `AppState` @Observable class coordinating state across repositories
- [x] 1.5 — Wire SPM packages into Xcode project as local dependencies
- [x] 1.6 — Write unit tests for models and GRDB round-trip persistence

## Phase 2: Tmux Backend

- [x] 2.1 — Create `MoriTmux` SPM package with `TmuxCommandRunner` (Process-based, PATH resolution with fallbacks)
- [x] 2.2 — Implement `TmuxParser` for list-sessions/windows/panes -F output
- [x] 2.3 — Implement `TmuxBackend` actor: scanAll, createSession, selectWindow, killSession, isAvailable
- [x] 2.4 — Define `TmuxControlling` protocol (full PRD surface, Phase 1 subset implemented)
- [x] 2.5 — Implement session naming `ws::<project>::<worktree>` and pre-existing session discovery
- [x] 2.6 — Implement polling: user-action-triggered + 5s background timer with diff
- [x] 2.7 — Write unit tests for `TmuxParser` with fixture strings

## Phase 3: AppKit Shell & Sidebar UI

- [x] 3.1 — Implement `MainWindowController` with toolbar and window config
- [x] 3.2 — Implement `RootSplitViewController` with 3 split items (rail 60-80pt, sidebar 200pt, content 400pt)
- [x] 3.3 — Create `MoriUI` SPM package with `ProjectRailView` (SwiftUI)
- [x] 3.4 — Create `WorktreeSidebarView` with worktree sections and window rows (SwiftUI)
- [x] 3.5 — Wire `AppState` into SwiftUI views via NSHostingController
- [x] 3.6 — Implement "Add Project" via NSOpenPanel (creates Project + default Worktree + tmux session)
- [x] 3.7 — Implement `WorkspaceManager` coordinating project/worktree/window selection flow
- [x] 3.8 — Enforce single app instance via NSRunningApplication check

## Phase 4: Terminal Integration

- [ ] 4.0 — libghostty API verification spike (test import, surface creation, fallback plan)
- [ ] 4.1 — Add `libghostty-spm` dependency to `MoriTerminal` package
- [ ] 4.2 — Implement `GhosttyAdapter`: app singleton, config, surface lifecycle
- [ ] 4.3 — Implement `TerminalAreaViewController` hosting ghostty NSView with resize handling
- [ ] 4.4 — Connect worktree selection → ghostty surface with `tmux attach-session -t <name>`
- [ ] 4.5 — Handle focus: terminal first responder on click and worktree/window switch
- [ ] 4.6 — Implement LRU surface cache (max 3 surfaces, evict via ghostty_surface_free)
- [ ] 4.7 — Handle `ghostty_app_tick()` via wakeup callback on main thread

## Phase 5: State Restoration & Polish

- [ ] 5.1 — Implement UIStateRepository save/load (selected project/worktree/window)
- [ ] 5.2 — Implement launch restoration: load state → restore selection → attach tmux → show terminal
- [ ] 5.3 — Handle edge cases: session gone (recreate), path invalid (mark unavailable), tmux missing (alert)
- [ ] 5.4 — Add app menu items: File > Open Project, Edit menu copy/paste passthrough
- [ ] 5.5 — Final integration testing: full lifecycle flow
